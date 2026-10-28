import 'dart:io';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:appnest_server/src/generated/serverpod.dart';
import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/collaboration/sharing.dart';
import 'package:appnest_server/src/modules/runtime/queries.dart';

Future<void> main() async {
  final tag = Platform.environment['APPNEST_RESTART_TAG'],
      phase = Platform.environment['APPNEST_RESTART_PHASE'],
      scenario = Platform.environment['APPNEST_RESTART_SCENARIO'] ?? 'claimant';
  if (tag == null ||
      !{'write', 'read'}.contains(phase) ||
      !{'claimant', 'planner'}.contains(scenario)) {
    throw StateError('Use scripts/restart_smoke.dart.');
  }
  final pod = Serverpod(
    ['--mode', 'test', '--apply-migrations'],
    configOverride: (c) => c.copyWith(
      database: PostgresDatabaseConfig.embedded(
        name: 'appnest_restart_smoke',
        dataPath: '.serverpod/restart/pgdata',
        maxConnectionCount: 10,
      ),
    ),
  );
  await pod.start();
  final s = await pod.createSession();
  s.updateAuthenticated(
    AuthenticationInfo(
      'restart-$scenario-$tag',
      {},
      authId: 'test-only-internal-session',
    ),
  );
  await Integrity.ensure(s);
  if (scenario == 'planner') {
    if (phase == 'write') {
      await _writePlanner(s, tag);
      stdout.writeln(
        'Committed owner reminder runs. Exiting before scheduling.',
      );
      exit(0);
    }
    await _readPlanner(s, tag);
    await s.close();
    await pod.shutdown(exitProcess: false);
    return;
  }
  if (phase == 'write') {
    final w = await Apps.createWorkspace(s, 'Restart $tag'),
        app = await Apps.instantiate(s, w, 'volunteer'),
        m = await Apps.manifest(s, app);
    final r = await Commands.execute(
      s,
      ActionRequest(
        appId: app,
        actionId: 'addShift',
        expectedDefinitionVersionId: m.versionId!,
        input: {
          'data': {
            'title': 'Accelerated restart proof',
            'startsAt': clock().toIso8601String(),
          },
          'capacity': 1,
        },
        idempotencyKey: 'record',
      ),
    );
    await Commands.execute(
      s,
      ActionRequest(
        appId: app,
        actionId: 'join',
        targetRecordId: r.recordId,
        expectedDefinitionVersionId: m.versionId!,
        input: {},
        idempotencyKey: 'claim',
      ),
    );
    await Automation.db.insertRow(
      s,
      Automation(
        appId: app,
        workspaceId: w,
        ruleId: 'smoke',
        ruleVersion: 1,
        ruleJson: canonicalJson({
          'id': 'smoke',
          'trigger': {
            'type': 'beforeTimestamp',
            'collectionId': 'shifts',
            'fieldId': 'startsAt',
            'offsetSeconds': 0,
          },
          'effect': {'type': 'notifyActiveClaimants', 'channel': 'inApp'},
        }),
        enabled: true,
        executionActorId: actor(s),
        activateExisting: false,
        activatedAt: clock().subtract(const Duration(days: 1)),
      ),
    );
    final events = await OutboxEvent.db.find(
      s,
      where: (t) => t.appId.equals(app),
    );
    for (final e in events) {
      await Worker.plan(s, e.id!);
    }
    if (await AutomationRun.db.count(s, where: (t) => t.appId.equals(app)) !=
        1) {
      throw StateError('Missing committed run.');
    }
    stdout.writeln(
      'Committed run. Exiting immediately before scheduling a wake-up.',
    );
    exit(0); // Deliberate process interruption, after database commit.
  }
  final w = (await Workspace.db.findFirstRow(
    s,
    where: (t) => t.name.equals('Restart $tag'),
  ))!;
  final app = (await MiniApp.db.findFirstRow(
    s,
    where: (t) => t.workspaceId.equals(w.id!),
  ))!;
  final run = (await AutomationRun.db.findFirstRow(
    s,
    where: (t) => t.appId.equals(app.id!),
  ))!;
  await Worker.drain(s);
  await Worker.execute(s, run.id!);
  if (await Notification.db.count(s, where: (t) => t.appId.equals(app.id!)) !=
      1) {
    throw StateError('Notification was lost or duplicated.');
  }
  if ((await ResourcePool.db.findFirstRow(
        s,
        where: (t) => t.appId.equals(app.id!),
      ))!.allocated !=
      1) {
    throw StateError('Claim did not survive restart.');
  }
  stdout.writeln(
    'PASS: reconciler recovered the committed run; duplicate wake-up was harmless.',
  );
  await s.close();
  await pod.shutdown(exitProcess: false);
}

Future<void> _writePlanner(Session s, String tag) async {
  final workspace = await Apps.createWorkspace(s, 'Planner restart $tag');
  final draft = await Builder.begin(s, workspace, 'planner', null);
  final enabled = ['taskReminder'];
  final version = await Builder.publish(
    s,
    PublishRequest(
      draftId: draft.draftId,
      candidateHash: draft.candidateHash,
      enabledRuleIds: enabled,
      activateExistingRecordIds: const [],
      reviewHash: hashJson({
        'candidateHash': draft.candidateHash,
        'enabledRuleIds': enabled,
        'activateExistingRecordIds': [],
      }),
      idempotencyKey: 'publish-planner',
    ),
  );
  for (final done in [false, true]) {
    final result = await Commands.execute(
      s,
      ActionRequest(
        appId: draft.appId,
        actionId: 'addTask',
        expectedDefinitionVersionId: version,
        input: {
          'data': {
            'title': done ? 'Completed before restart' : 'Open at restart',
            'status': 'Open',
            'reminderAt': clock().toIso8601String(),
          },
        },
        idempotencyKey: 'task-$done',
      ),
    );
    if (done) {
      await Commands.execute(
        s,
        ActionRequest(
          appId: draft.appId,
          actionId: 'moveTask',
          targetRecordId: result.recordId,
          expectedDefinitionVersionId: version,
          expectedRecordRevision: result.revision,
          input: {'value': 'Done'},
          idempotencyKey: 'complete',
        ),
      );
    }
  }
  for (final event in await OutboxEvent.db.find(
    s,
    where: (t) => t.appId.equals(draft.appId),
    // Planning order does not define which task an automation run belongs to.
    // Exercise the completed task first to keep that distinction in the probe.
    orderBy: (t) => t.id.desc(),
  )) {
    await Worker.plan(s, event.id!);
  }
  if (await AutomationRun.db.count(
        s,
        where: (t) => t.appId.equals(draft.appId) & t.status.equals('pending'),
      ) !=
      2) {
    throw StateError('Owner reminder runs were not committed.');
  }
}

Future<void> _readPlanner(Session s, String tag) async {
  final workspace = (await Workspace.db.findFirstRow(
    s,
    where: (t) => t.name.equals('Planner restart $tag'),
  ))!;
  final app = (await MiniApp.db.findFirstRow(
    s,
    where: (t) => t.workspaceId.equals(workspace.id!),
  ))!;
  final tasks = await Queries.query(s, app.id!, 'tasks', '{}');
  final open = tasks.records
      .where((record) => record.data['title'] == 'Open at restart')
      .toList();
  final done = tasks.records
      .where((record) => record.data['title'] == 'Completed before restart')
      .toList();
  if (tasks.records.length != 2 ||
      open.length != 1 ||
      done.length != 1 ||
      open.single.data['status'] != 'Open' ||
      done.single.data['status'] != 'Done') {
    throw StateError(
      'Planner task identities or statuses did not survive restart.',
    );
  }
  final openRecordId = open.single.id;
  final completedRecordId = done.single.id;
  final runs = await AutomationRun.db.find(
    s,
    where: (t) => t.appId.equals(app.id!),
    orderBy: (t) => t.id,
  );
  await Worker.drain(s);
  for (final run in runs) {
    await Worker.execute(s, run.id!);
    await Worker.execute(s, run.id!);
  }
  final statuses = await AutomationRun.db.find(
    s,
    where: (t) => t.appId.equals(app.id!),
    orderBy: (t) => t.id,
  );
  final openRuns = statuses
      .where((run) => run.recordId == openRecordId)
      .toList();
  final completedRuns = statuses
      .where((run) => run.recordId == completedRecordId)
      .toList();
  if (statuses.length != 2 ||
      openRuns.length != 1 ||
      completedRuns.length != 1 ||
      openRuns.single.status != 'succeeded' ||
      completedRuns.single.status != 'suppressed') {
    throw StateError(
      'Owner reminder delivery conditions did not survive restart.',
    );
  }
  final inbox = await Sharing.inbox(s);
  if (inbox.length != 1 ||
      inbox.single.appId != app.id ||
      inbox.single.recordId != openRecordId ||
      inbox.single.collectionId != 'tasks') {
    throw StateError(
      'Owner inbox delivery was lost, duplicated or mistargeted.',
    );
  }
  final completed = await Queries.get(s, app.id!, completedRecordId);
  await Commands.execute(
    s,
    ActionRequest(
      appId: app.id!,
      actionId: 'moveTask',
      targetRecordId: completed.id,
      expectedDefinitionVersionId: app.activeVersionId!,
      expectedRecordRevision: completed.revision,
      input: {'value': 'Open'},
      idempotencyKey: 'reopen-after-restart',
    ),
  );
  await Worker.drain(s);
  if ((await Queries.reminderState(s, app.id!, completed.id)).single.state !=
          'suppressed' ||
      (await Sharing.inbox(s)).length != 1 ||
      await AutomationRun.db.count(s, where: (t) => t.appId.equals(app.id!)) !=
          2) {
    throw StateError('Reopening revived a terminal owner reminder.');
  }
  stdout.writeln(
    'PASS: owner reminder recovered, completed task suppressed, reopen and duplicate wake-ups did not resend.',
  );
}
