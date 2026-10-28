import 'dart:async';
import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_server/src/modules/collaboration/sharing.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_server/src/modules/runtime/queries.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Daily Planner committed PostgreSQL runtime', (
    sessions,
    endpoints,
  ) {
    late Session owner;
    late int workspace, appId, version;
    late DateTime now;
    late DateTime Function() originalClock;
    var sequence = 0;

    Session user(String id) => sessions
        .copyWith(
          authentication: AuthenticationOverride.authenticationInfo(id, {}),
        )
        .build();

    setUpAll(() async => Integrity.ensure(sessions.build()));
    setUp(() async {
      originalClock = clock;
      now = DateTime.utc(2030, 3, 10, 12);
      clock = () => now;
      owner = user('planner-owner-${randomToken()}');
      workspace = await Apps.createWorkspace(owner, 'Planner tests');
      appId = await Apps.instantiate(owner, workspace, 'planner');
      version = (await Apps.manifest(owner, appId)).versionId!;
    });
    tearDown(() => clock = originalClock);

    Future<int> create({
      DateTime? due,
      DateTime? reminder,
      String title = 'Task',
    }) async {
      final outcome = await Commands.execute(
        owner,
        ActionRequest(
          appId: appId,
          actionId: 'addTask',
          expectedDefinitionVersionId: version,
          input: {
            'data': {
              'title': title,
              'status': 'Open',
              'priority': 'Normal',
              if (due != null) 'dueAt': due.toIso8601String(),
              if (reminder != null) 'reminderAt': reminder.toIso8601String(),
            },
          },
          idempotencyKey: 'create-${sequence++}',
        ),
      );
      return outcome.recordId;
    }

    Future<void> edit(int id, Map<String, dynamic> data) async {
      final row = await Queries.get(owner, appId, id);
      await Commands.execute(
        owner,
        ActionRequest(
          appId: appId,
          actionId: 'editTask',
          targetRecordId: id,
          expectedDefinitionVersionId: version,
          expectedRecordRevision: row.revision,
          input: {'data': data},
          idempotencyKey: 'edit-${sequence++}',
        ),
      );
    }

    Future<void> status(int id, String value) async {
      final row = await Queries.get(owner, appId, id);
      await Commands.execute(
        owner,
        ActionRequest(
          appId: appId,
          actionId: 'moveTask',
          targetRecordId: id,
          expectedDefinitionVersionId: version,
          expectedRecordRevision: row.revision,
          input: {'value': value},
          idempotencyKey: 'status-${sequence++}',
        ),
      );
    }

    Future<void> approve({
      bool enabled = true,
      List<int> existing = const [],
    }) async {
      now = now.add(const Duration(seconds: 1));
      final draft = await Builder.begin(owner, workspace, 'planner', appId);
      final rules = enabled ? ['taskReminder'] : <String>[];
      version = await Builder.publish(
        owner,
        PublishRequest(
          draftId: draft.draftId,
          candidateHash: draft.candidateHash,
          expectedCurrentVersionId: version,
          enabledRuleIds: rules,
          activateExistingRecordIds: existing,
          reviewHash: hashJson({
            'candidateHash': draft.candidateHash,
            'enabledRuleIds': rules,
            'activateExistingRecordIds': existing,
          }),
          idempotencyKey: 'publish-${sequence++}',
        ),
      );
    }

    Future<void> plan() async {
      for (final event in await OutboxEvent.db.find(
        owner,
        where: (t) => t.appId.equals(appId),
        orderBy: (t) => t.id,
      )) {
        await Worker.plan(owner, event.id!);
      }
    }

    Future<List<AutomationRun>> runs() => AutomationRun.db.find(
      owner,
      where: (t) => t.appId.equals(appId),
      orderBy: (t) => t.id,
    );
    Future<ReminderState> reminder(int id) async =>
        (await Queries.reminderState(owner, appId, id)).single;

    test('manual builder creation and generated reachable tab publish before the complete planner lifecycle', () async {
      var draft = await Builder.begin(owner, workspace, 'planner', null);
      appId = draft.appId;
      draft = await Builder.patch(
        owner,
        draft.draftId,
        draft.mutation,
        jsonEncode({
          'type': 'RenameLabel',
          'targetId': 'todayPage',
          'label': 'My day',
        }),
      );
      Future<int> publishDraft(BuilderSnapshot reviewed, int? expected) =>
          Builder.publish(
            owner,
            PublishRequest(
              draftId: reviewed.draftId,
              candidateHash: reviewed.candidateHash,
              expectedCurrentVersionId: expected,
              enabledRuleIds: const ['taskReminder'],
              activateExistingRecordIds: const [],
              reviewHash: hashJson({
                'candidateHash': reviewed.candidateHash,
                'enabledRuleIds': ['taskReminder'],
                'activateExistingRecordIds': [],
              }),
              idempotencyKey: 'lifecycle-publish-${sequence++}',
            ),
          );
      version = await publishDraft(draft, null);
      expect(
        (await Queries.query(owner, appId, 'tasks', '{}')).records,
        isEmpty,
      );
      expect(
        AppSpec.parse((await Apps.manifest(owner, appId)).specJson!)
            .page('todayPage')
            .title,
        'My day',
      );

      draft = await Builder.begin(owner, workspace, 'planner', appId);
      final job = await GenerationJob.db.insertRow(
        owner,
        GenerationJob(
          appId: appId,
          draftId: draft.draftId,
          actorId: actor(owner),
          mutation: draft.mutation,
          status: 'queued',
          requestText: 'Add a Focus tab showing open tasks',
          mode: 'edit',
          promptVersion: 'test',
          nextAttemptAt: clock(),
          diagnostics: '',
          usageJson: '{}',
          createdAt: clock(),
          updatedAt: clock(),
        ),
      );
      final draftRow = (await AppDraft.db.findById(owner, draft.draftId))!
        ..activeJobId = job.id;
      await AppDraft.db.updateRow(owner, draftRow);
      await Worker.generate(
        owner,
        job.id!,
        provider: FakeAiProvider(
          jsonEncode({
            'patches': [
              {
                'type': 'AddPage',
                'page': {'title': 'Focus'},
                'tab': {'label': 'Focus', 'icon': 'check'},
                'newViews': [
                  {
                    'type': 'list',
                    'collectionId': 'tasks',
                    'label': 'Open tasks',
                    'titleFieldId': 'title',
                    'actionIds': ['moveTask'],
                    'query': {
                      'filters': [
                        {
                          'fieldId': 'status',
                          'operator': 'eq',
                          'value': 'Open',
                        },
                      ],
                    },
                  },
                ],
              },
            ],
          }),
        ),
      );
      draft = await Builder.get(owner, draft.draftId);
      expect(
        draft.stage,
        'preview ready',
        reason: draft.diagnostics.join('; '),
      );
      final candidate = AppSpec.parse(draft.candidateJson);
      final tab = candidate.navigation!.tabs.singleWhere(
        (t) => t.label == 'Focus',
      );
      final focus = candidate.page(tab.pageId);
      expect(focus.viewIds, hasLength(1));
      expect(
        candidate.view(focus.viewIds.single).query!['filters'],
        hasLength(1),
      );
      version = await publishDraft(draft, version);
      expect((await Queries.query(owner, appId, 'tasks', '{}')).total, 0);
      expect((await Apps.manifest(owner, appId)).approvedRuleIds, [
        'taskReminder',
      ]);

      final due = now.add(const Duration(minutes: 1));
      final id = await create(
        reminder: due,
        due: now.add(const Duration(hours: 1)),
      );
      await edit(id, {
        'title': 'Finish the new mini-app',
        'notes': 'Saved through the trusted action service',
      });
      await status(id, 'Done');
      await status(id, 'Open');
      await plan();
      expect(await runs(), hasLength(1));
      now = due;
      await Worker.execute(owner, (await runs()).single.id!);
      await Worker.execute(owner, (await runs()).single.id!);
      final inbox = await Sharing.inbox(owner);
      expect(inbox, hasLength(1));
      expect(inbox.single.recordId, id);
      final reopened = await Queries.get(owner, appId, inbox.single.recordId!);
      expect(reopened.data['status'], 'Open');
      expect(
        reopened.data['notes'],
        'Saved through the trusted action service',
      );
      expect((await reminder(id)).state, 'delivered');
    });

    test('direct wakeups and reconciliation respect retry deadlines', () async {
      await approve();
      final id = await create(
        reminder: now.subtract(const Duration(seconds: 1)),
      );
      await plan();
      final run = (await runs()).single;
      run.attempts = 3;
      run.nextAttemptAt = now.add(const Duration(seconds: 32));
      await AutomationRun.db.updateRow(owner, run);

      await NestWorkerFutureCall().execute(owner, run.id!);
      await Worker.drain(owner);
      final deferred = (await runs()).single;
      expect(deferred.status, 'pending');
      expect(deferred.attempts, 3);
      expect(deferred.leaseGeneration, run.leaseGeneration);
      expect(await Sharing.inbox(owner), isEmpty);

      now = run.nextAttemptAt;
      await Worker.drain(owner);
      await NestWorkerFutureCall().execute(owner, run.id!);
      expect((await runs()).single.status, 'succeeded');
      expect((await runs()).single.attempts, 4);
      expect((await Sharing.inbox(owner)).single.recordId, id);
    });

    test('failed direct wakeups persist the same bounded backoff as reconciliation', () async {
      await approve();
      await create(reminder: now.subtract(const Duration(seconds: 1)));
      await plan();
      final run = (await runs()).single;
      final rule = (await Automation.db.findById(owner, run.automationId))!;
      final validRule = rule.ruleJson;
      rule.ruleJson = 'not valid JSON';
      await Automation.db.updateRow(owner, rule);

      await expectLater(
        NestWorkerFutureCall().execute(owner, run.id!),
        throwsFormatException,
      );
      var failed = (await runs()).single;
      expect(failed.status, 'pending');
      expect(failed.attempts, 1);
      expect(failed.leaseGeneration, 1);
      expect(failed.nextAttemptAt, now.add(const Duration(seconds: 2)));
      expect(failed.errorCategory, 'retryableFailure');
      expect(await Sharing.inbox(owner), isEmpty);

      await Worker.drain(owner);
      await NestWorkerFutureCall().execute(owner, run.id!);
      expect((await runs()).single.attempts, 1);

      // A reconciler failure advances the same persisted budget exactly once.
      now = failed.nextAttemptAt;
      await Worker.drain(owner);
      failed = (await runs()).single;
      expect(failed.attempts, 2);
      expect(failed.leaseGeneration, 2);
      expect(failed.nextAttemptAt, now.add(const Duration(seconds: 4)));

      rule.ruleJson = validRule;
      await Automation.db.updateRow(owner, rule);
      now = failed.nextAttemptAt;
      await NestWorkerFutureCall().execute(owner, run.id!);
      expect((await runs()).single.status, 'succeeded');
      expect((await runs()).single.attempts, 3);
      expect(await Sharing.inbox(owner), hasLength(1));
    });

    test(
      'a retry deadline committed while waiting for the app lock is rechecked',
      () async {
        await approve();
        await create(reminder: now.subtract(const Duration(seconds: 1)));
        await plan();
        final run = (await runs()).single;
        final locked = Completer<void>();
        final release = Completer<void>();
        final holder = user(actor(owner));
        final waiting = user(actor(owner));
        final blocker = holder.db.transaction((tx) async {
          await MiniApp.db.findFirstRow(
            holder,
            where: (t) => t.id.equals(appId),
            transaction: tx,
            lockMode: LockMode.forUpdate,
          );
          locked.complete();
          await release.future;
          run.nextAttemptAt = now.add(const Duration(seconds: 32));
          await AutomationRun.db.updateRow(holder, run, transaction: tx);
        });
        await locked.future;
        final execution = Worker.execute(waiting, run.id!);
        try {
          var isWaiting = false;
          for (var i = 0; i < 100; i++) {
            final locks = await owner.db.unsafeQuery(
              "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%nest_app%'",
            );
            if ((locks.single.single as int) > 0) {
              isWaiting = true;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(
            isWaiting,
            isTrue,
            reason: 'The worker must have read the old run and reached the contended app lock.',
          );
        } finally {
          release.complete();
          await blocker;
          await execution;
        }
        expect((await runs()).single.status, 'pending');
        expect((await runs()).single.attempts, 0);
        expect(await Sharing.inbox(owner), isEmpty);
      },
    );

    test('five direct effect failures exhaust one occurrence without extra deliveries', () async {
      await approve();
      await create(reminder: now.subtract(const Duration(seconds: 1)));
      await plan();
      final run = (await runs()).single;
      final rule = (await Automation.db.findById(owner, run.automationId))!;
      rule.ruleJson = 'not valid JSON';
      await Automation.db.updateRow(owner, rule);
      for (var attempt = 1; attempt <= 5; attempt++) {
        await expectLater(
          Worker.execute(owner, run.id!),
          throwsFormatException,
        );
        final failed = (await runs()).single;
        expect(failed.attempts, attempt);
        expect(failed.status, attempt == 5 ? 'failed' : 'pending');
        now = failed.nextAttemptAt;
      }
      await Worker.execute(owner, run.id!);
      await Worker.drain(owner);
      final terminal = (await runs()).single;
      expect(terminal.attempts, 5);
      expect(terminal.completedAt, isNotNull);
      expect(terminal.leaseUntil, isNull);
      expect(await Sharing.inbox(owner), isEmpty);
    });

    test('database-wide choice summaries, exclusive day bounds, null dates and authorization', () async {
      final start = DateTime.utc(2030, 3, 10), end = DateTime.utc(2030, 3, 11);
      for (var i = 0; i < 105; i++) {
        final id = await create(
          due: start.add(Duration(minutes: i)),
          title: 'Task $i',
        );
        if (i % 3 == 0) await status(id, 'Done');
      }
      await create(due: end);
      await create(due: start.subtract(const Duration(microseconds: 1)));
      await create();
      final query = jsonEncode({
        'limit': 1,
        'filters': [
          {
            'fieldId': 'dueAt',
            'operator': 'gte',
            'value': start.toIso8601String(),
          },
          {
            'fieldId': 'dueAt',
            'operator': 'lt',
            'value': end.toIso8601String(),
          },
        ],
      });
      final total = await Queries.summary(
        owner,
        appId,
        'tasks',
        '{}',
        'status',
      );
      expect(total.total, 108);
      expect(total.groups, {'Open': 73, 'Done': 35});
      final today = await Queries.summary(
        owner,
        appId,
        'tasks',
        query,
        'status',
      );
      expect(today.total, 105);
      expect(today.groups, {'Open': 70, 'Done': 35});
      final page = await Queries.query(owner, appId, 'tasks', query);
      expect(page.records, hasLength(1));
      expect(page.total, today.total);
      expect(page.nextCursor, isNotNull);
      final next = await Queries.query(
        owner,
        appId,
        'tasks',
        jsonEncode({
          ...jsonDecode(query) as Map<String, dynamic>,
          'cursor': page.nextCursor,
        }),
      );
      expect(next.records.single.id, isNot(page.records.single.id));
      final undated = await Queries.summary(
        owner,
        appId,
        'tasks',
        jsonEncode({
          'filters': [
            {'fieldId': 'dueAt', 'operator': 'eq', 'value': null},
          ],
        }),
        'status',
      );
      expect(undated.total, 1);
      expect(undated.groups, {'Open': 1, 'Done': 0});
      await expectLater(
        Queries.summary(owner, appId, 'tasks', '{}', 'title'),
        throwsA(isA<NestError>()),
      );
      final stranger = user('stranger-${randomToken()}');
      await expectLater(
        Queries.summary(stranger, appId, 'tasks', '{}', 'status'),
        throwsA(isA<NestError>()),
      );
      final otherApp = await Apps.instantiate(owner, workspace, 'planner');
      expect(
        (await Queries.summary(owner, otherApp, 'tasks', '{}', 'status')).total,
        0,
      );
    });

    test('owner reminder plans while done, delivers after reopen exactly once, and targets inbox record', () async {
      expect((await Apps.manifest(owner, appId)).approvedRuleIds, isEmpty);
      final withoutReminder = await create(due: now);
      expect((await reminder(withoutReminder)).state, 'unset');
      await approve();
      expect((await Apps.manifest(owner, appId)).approvedRuleIds, [
        'taskReminder',
      ]);
      expect((await Apps.list(owner, workspace)).single.approvedRuleIds, [
        'taskReminder',
      ]);
      final due = now.add(const Duration(minutes: 1));
      final id = await create(reminder: due);
      expect((await reminder(id)).state, 'pending'); // Outbox not yet planned.
      await status(id, 'Done');
      await plan();
      expect((await runs()), hasLength(1));
      expect((await reminder(id)).state, 'pending');
      expect((await reminder(id)).eligible, false);
      await status(id, 'Open');
      await plan();
      expect((await reminder(id)).eligible, true);
      now = due.add(const Duration(seconds: 1));
      final run = (await runs()).single;
      await Worker.execute(owner, run.id!);
      await Worker.execute(owner, run.id!);
      await edit(id, {'notes': 'Does not create another occurrence'});
      await plan();
      expect(await runs(), hasLength(1));
      expect((await reminder(id)).state, 'delivered');
      final inbox = await Sharing.inbox(owner);
      expect(inbox, hasLength(1));
      expect(inbox.single.recordId, id);
      expect(inbox.single.collectionId, 'tasks');
      await status(id, 'Done');
      await status(id, 'Open');
      await plan();
      await Worker.execute(owner, run.id!);
      expect(await Sharing.inbox(owner), hasLength(1));
    });

    test('suppressed occurrences remain terminal and state follows current reminder timestamp', () async {
      await approve();
      var due = now.add(const Duration(minutes: 1));
      final id = await create(reminder: due);
      await plan();
      await status(id, 'Done');
      now = due;
      await Worker.execute(owner, (await runs()).single.id!);
      expect((await reminder(id)).state, 'suppressed');
      await status(id, 'Open');
      await plan();
      await Worker.execute(owner, (await runs()).single.id!);
      expect((await reminder(id)).state, 'suppressed');
      expect(await Sharing.inbox(owner), isEmpty);

      due = now.add(const Duration(minutes: 1));
      await edit(id, {'reminderAt': due.toIso8601String()});
      expect((await reminder(id)).state, 'pending');
      await plan();
      expect(await runs(), hasLength(2));
      await edit(id, {'reminderAt': null});
      expect((await reminder(id)).state, 'unset');
      expect((await reminder(id)).scheduledAt, isNull);
      now = due;
      await Worker.execute(owner, (await runs()).last.id!);
      expect((await runs()).last.status, 'suppressed');

      due = now.add(const Duration(minutes: 1));
      await edit(id, {'reminderAt': due.toIso8601String()});
      await plan();
      final current = (await runs()).last;
      current.status = 'failed';
      await AutomationRun.db.updateRow(owner, current);
      expect((await reminder(id)).state, 'failed');
      await edit(id, {
        'reminderAt': due.add(const Duration(minutes: 1)).toIso8601String(),
      });
      expect((await reminder(id)).state, 'pending'); // Not the old failed run.
    });

    test(
      'existing records require explicit enrollment for each rule generation',
      () async {
        final id = await create(reminder: now.add(const Duration(hours: 1)));
        expect((await reminder(id)).state, 'disabled');
        await approve();
        expect((await reminder(id)).state, 'unenrolled');
        await plan();
        expect(await runs(), isEmpty);
        await approve(existing: [id]);
        expect(
          (await reminder(id)).state,
          'pending',
        ); // Enrollment outbox is durable.
        await plan();
        expect(await runs(), hasLength(1));
        await approve(enabled: false);
        expect((await reminder(id)).state, 'disabled');
        await approve();
        expect((await reminder(id)).state, 'unenrolled');
        await edit(id, {'notes': 'No implicit re-enrollment'});
        await plan();
        expect(await runs(), hasLength(1));
        await approve(existing: [id]);
        expect((await reminder(id)).state, 'pending');
        await plan();
        expect(await runs(), hasLength(2));
        now = now.add(const Duration(hours: 2));
        for (final run in await runs()) {
          await Worker.execute(owner, run.id!);
        }
        expect((await runs()).first.status, 'suppressed');
        expect((await runs()).last.status, 'succeeded');
        expect((await reminder(id)).state, 'delivered');
        expect(await Sharing.inbox(owner), hasLength(1));
      },
    );

    test('explicit enrollment survives queued publication and an initially unset time, but never another rule generation', () async {
      final selected = await create(
        reminder: now.add(const Duration(hours: 1)),
      );
      final initiallyUnset = await create();
      await approve(existing: [selected, initiallyUnset]);

      Future<void> republish({bool changeRule = false}) async {
        now = now.add(const Duration(seconds: 1));
        var draft = await Builder.begin(owner, workspace, 'planner', appId);
        if (changeRule) {
          // A validated changed-rule draft exercises generation reconciliation.
          final definition = AppSpec.parse(draft.candidateJson).toJson();
          definition['automationRequests'][0]['trigger']['offsetSeconds'] = 60;
          final candidate = AppSpec.parse(jsonEncode(definition));
          final row = (await AppDraft.db.findById(owner, draft.draftId))!;
          row.candidateJson = candidate.canonical;
          row.candidateHash = candidate.hash;
          await AppDraft.db.updateRow(owner, row);
          draft = await Builder.get(owner, draft.draftId);
        } else {
          draft = await Builder.patch(
            owner,
            draft.draftId,
            draft.mutation,
            jsonEncode({
              'type': 'RenameLabel',
              'targetId': 'todayPage',
              'label': 'A new page title',
            }),
          );
        }
        version = await Builder.publish(
          owner,
          PublishRequest(
            draftId: draft.draftId,
            candidateHash: draft.candidateHash,
            expectedCurrentVersionId: version,
            enabledRuleIds: const ['taskReminder'],
            activateExistingRecordIds: const [],
            reviewHash: hashJson({
              'candidateHash': draft.candidateHash,
              'enabledRuleIds': ['taskReminder'],
              'activateExistingRecordIds': [],
            }),
            idempotencyKey: 'enrollment-publish-${sequence++}',
          ),
        );
      }

      await republish(); // The original enrollment has not been planned yet.
      expect((await reminder(selected)).state, 'pending');
      await plan();
      expect(await runs(), hasLength(1));
      expect((await reminder(initiallyUnset)).state, 'unset');
      await edit(initiallyUnset, {
        'reminderAt': now.add(const Duration(hours: 2)).toIso8601String(),
      });
      expect((await reminder(initiallyUnset)).state, 'pending');
      await plan();
      expect(await runs(), hasLength(2));

      await republish(changeRule: true);
      expect((await reminder(selected)).state, 'unenrolled');
      expect((await reminder(initiallyUnset)).state, 'unenrolled');
      await edit(selected, {
        'notes': 'Changed rules need another approval scope',
      });
      await plan();
      expect(await runs(), hasLength(2));
      await approve(existing: [selected]);
      await plan();
      expect(await runs(), hasLength(3));
      await approve(enabled: false);
      await approve();
      expect((await reminder(selected)).state, 'unenrolled');
      await plan();
      expect(await runs(), hasLength(3));
    });

    test('archive suppresses pending reminders; viewer writes and revoked read access fail', () async {
      await approve();
      final due = now.add(const Duration(minutes: 1));
      final id = await create(reminder: due);
      final viewer = user('viewer-${randomToken()}');
      await Sharing.accept(
        viewer,
        await Sharing.invite(owner, appId, 'viewer', null),
      );
      expect((await Queries.get(viewer, appId, id)).allowedActions, isEmpty);
      expect(
        (await Queries.reminderState(viewer, appId, id)).single.state,
        'pending',
      );
      await expectLater(
        Commands.execute(
          viewer,
          ActionRequest(
            appId: appId,
            actionId: 'editTask',
            targetRecordId: id,
            expectedDefinitionVersionId: version,
            expectedRecordRevision: 1,
            input: {
              'data': {'notes': 'Blocked'},
            },
            idempotencyKey: 'viewer-write',
          ),
        ),
        throwsA(isA<NestError>()),
      );
      await Sharing.setGrant(owner, appId, actor(viewer), null);
      await expectLater(
        Queries.reminderState(viewer, appId, id),
        throwsA(isA<NestError>()),
      );
      await expectLater(
        Queries.get(viewer, appId, id),
        throwsA(isA<NestError>()),
      );
      await plan();
      await Apps.archive(owner, appId);
      expect((await reminder(id)).state, 'suppressed');
      expect((await reminder(id)).eligible, false);
      now = due;
      await Worker.execute(owner, (await runs()).single.id!);
      expect((await runs()).single.status, 'suppressed');
      expect(await Sharing.inbox(owner), isEmpty);
    });
  }, rollbackDatabase: RollbackDatabase.disabled);
}
