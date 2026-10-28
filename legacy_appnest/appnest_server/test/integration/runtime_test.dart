import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/queries.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_server/src/modules/collaboration/sharing.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('AppNest committed PostgreSQL runtime', (sessions, endpoints) {
    Session user(String name) => sessions
        .copyWith(
          authentication: AuthenticationOverride.authenticationInfo(name, {}),
        )
        .build();
    late Session owner;
    late int workspace, appId, version, recordId;
    late String prefix;
    setUpAll(() async {
      await Integrity.ensure(sessions.build());
    });
    setUp(() async {
      prefix = randomToken();
      owner = user('owner-$prefix');
      workspace = await Apps.createWorkspace(owner, 'Integration $prefix');
      appId = await Apps.instantiate(owner, workspace, 'volunteer');
      version = (await Apps.manifest(owner, appId)).versionId!;
      final result = await Commands.execute(
        owner,
        ActionRequest(
          appId: appId,
          actionId: 'addShift',
          expectedDefinitionVersionId: version,
          input: {
            'data': {
              'title': 'Garden morning',
              'startsAt': clock()
                  .add(const Duration(hours: 2))
                  .toIso8601String(),
            },
            'capacity': 1,
          },
          idempotencyKey: 'create',
        ),
      );
      recordId = result.recordId;
    });
    Future<Session> member(String name, {String role = 'member'}) async {
      final s = user('$name-$prefix');
      final token = await Sharing.invite(owner, appId, role, null);
      await Sharing.accept(s, token);
      return s;
    }

    ActionRequest claim(String key) => ActionRequest(
      appId: appId,
      actionId: 'join',
      targetRecordId: recordId,
      expectedDefinitionVersionId: version,
      input: {},
      idempotencyKey: key,
    );
    test(
      '20 independent actors competing for final place accept exactly one',
      () async {
        final participants = <Session>[];
        for (var i = 0; i < 20; i++) {
          participants.add(await member('participant$i'));
        }
        final outcomes = await Future.wait(
          participants.map((s) async {
            try {
              await Commands.execute(s, claim('claim'));
              return true;
            } on NestError catch (e) {
              expect(e.category, 'exhaustedCapacity');
              return false;
            }
          }),
        );
        expect(outcomes.where((x) => x).length, 1);
        final pool = await ResourcePool.db.findFirstRow(
          owner,
          where: (t) => t.appId.equals(appId),
        );
        expect(pool!.allocated, 1);
        expect(
          await Claim.db.count(
            owner,
            where: (t) => t.poolId.equals(pool.id!) & t.active.equals(true),
          ),
          1,
        );
      },
    );
    test(
      'receipts, changed key input, repeated cancellation, atomic failure',
      () async {
        final s = await member('alex');
        final first = await Commands.execute(s, claim('same'));
        expect(
          (await Commands.execute(s, claim('same'))).toJson(),
          first.toJson(),
        );
        await expectLater(
          Commands.execute(s, claim('same')..input = {'unexpected': true}),
          throwsA(
            isA<NestError>().having(
              (e) => e.category,
              'category',
              'invalidInput',
            ),
          ),
        );
        for (var i = 0; i < 2; i++) {
          await Commands.execute(
            s,
            ActionRequest(
              appId: appId,
              actionId: 'leave',
              targetRecordId: recordId,
              expectedDefinitionVersionId: version,
              input: {},
              idempotencyKey: 'leave$i',
            ),
          );
        }
        expect(
          (await ResourcePool.db.findFirstRow(
            owner,
            where: (t) => t.appId.equals(appId),
          ))!.allocated,
          0,
        );
        final count = await EntityRecord.db.count(
              owner,
              where: (t) => t.appId.equals(appId),
            ),
            events = await OutboxEvent.db.count(
              owner,
              where: (t) => t.appId.equals(appId),
            );
        await expectLater(
          Commands.execute(
            owner,
            ActionRequest(
              appId: appId,
              actionId: 'addShift',
              expectedDefinitionVersionId: version,
              input: {
                'data': {'title': 'bad', 'startsAt': clock().toIso8601String()},
                'capacity': -1,
              },
              idempotencyKey: 'bad',
            ),
          ),
          throwsA(isA<NestError>()),
        );
        expect(
          await EntityRecord.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          count,
        );
        expect(
          await OutboxEvent.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          events,
        );
      },
    );
    test(
      'authorization, scoped queries, revision conflicts and protected counters',
      () async {
        final stranger = user('stranger-$prefix'),
            s = await member('alex'),
            viewer = await member('viewer', role: 'viewer');
        await expectLater(
          Queries.get(stranger, appId, recordId),
          throwsA(isA<NestError>()),
        );
        await expectLater(
          Commands.execute(viewer, claim('no')),
          throwsA(isA<NestError>()),
        );
        await expectLater(
          Sharing.invite(s, appId, 'builder', null),
          throwsA(isA<NestError>()),
        );
        await expectLater(
          Commands.execute(
            s,
            ActionRequest(
              appId: appId,
              actionId: 'configure',
              targetRecordId: recordId,
              expectedDefinitionVersionId: version,
              input: {'capacity': 20},
              idempotencyKey: 'forged',
            ),
          ),
          throwsA(isA<NestError>()),
        );
        final page = await Queries.query(
          owner,
          appId,
          'shifts',
          jsonEncode({
            'filters': [
              {'fieldId': 'title', 'operator': 'contains', 'value': 'garden'},
            ],
            'sort': [
              {'fieldId': 'startsAt', 'descending': false},
            ],
          }),
        );
        expect(page.total, 1);
        expect(page.records.single.id, recordId);
        await expectLater(
          Commands.execute(
            owner,
            ActionRequest(
              appId: appId,
              actionId: 'editShift',
              targetRecordId: recordId,
              expectedDefinitionVersionId: version,
              expectedRecordRevision: 0,
              input: {
                'data': {'notes': 'conflict'},
              },
              idempotencyKey: 'conflict',
            ),
          ),
          throwsA(
            isA<NestError>().having(
              (e) => e.category,
              'category',
              'recordConflict',
            ),
          ),
        );
      },
    );
    test(
      'safe publication preserves claims and old receipts, retry does not duplicate',
      () async {
        final s = await member('alex');
        await Commands.execute(s, claim('stable'));
        var d = await Builder.begin(owner, workspace, 'volunteer', appId);
        d = await Builder.patch(
          owner,
          d.draftId,
          d.mutation,
          jsonEncode({
            'type': 'AddField',
            'collectionId': 'shifts',
            'field': {
              'label': 'Meeting point',
              'type': 'text',
              'required': false,
            },
          }),
        );
        final req = PublishRequest(
          draftId: d.draftId,
          candidateHash: d.candidateHash,
          expectedCurrentVersionId: version,
          enabledRuleIds: [],
          activateExistingRecordIds: [],
          reviewHash: hashJson({
            'candidateHash': d.candidateHash,
            'enabledRuleIds': [],
            'activateExistingRecordIds': [],
          }),
          idempotencyKey: 'publish',
        );
        final next = await Builder.publish(owner, req);
        expect(await Builder.publish(owner, req), next);
        expect(next, isNot(version));
        expect((await Queries.get(s, appId, recordId)).claimed, true);
        await Commands.execute(s, claim('stable'));
        await expectLater(
          Commands.execute(s, claim('new-stale')),
          throwsA(
            isA<NestError>().having(
              (e) => e.category,
              'category',
              'staleDefinition',
            ),
          ),
        );
      },
    );
    test(
      're-enabled rules do not enroll old records without explicit scope',
      () async {
        Future<void> publishRules(
          List<String> enabled,
          List<int> scope,
          String key,
        ) async {
          final d = await Builder.begin(owner, workspace, 'volunteer', appId);
          version = await Builder.publish(
            owner,
            PublishRequest(
              draftId: d.draftId,
              candidateHash: d.candidateHash,
              expectedCurrentVersionId: version,
              enabledRuleIds: enabled,
              activateExistingRecordIds: scope,
              reviewHash: hashJson({
                'candidateHash': d.candidateHash,
                'enabledRuleIds': enabled,
                'activateExistingRecordIds': scope,
              }),
              idempotencyKey: key,
            ),
          );
        }

        Future<void> planAll() async {
          for (final e in await OutboxEvent.db.find(
            owner,
            where: (t) => t.appId.equals(appId),
          )) {
            await Worker.plan(owner, e.id!);
          }
        }

        await publishRules(['shiftReminder'], [recordId], 'enroll');
        await planAll();
        expect(
          await AutomationRun.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          1,
        );
        await publishRules([], [], 'disable');
        await publishRules(['shiftReminder'], [], 'reenable');
        await Commands.execute(
          owner,
          ActionRequest(
            appId: appId,
            actionId: 'editShift',
            targetRecordId: recordId,
            expectedDefinitionVersionId: version,
            expectedRecordRevision: 1,
            input: {
              'data': {'notes': 'Unrelated notes'},
            },
            idempotencyKey: 'notes',
          ),
        );
        await planAll();
        expect(
          await AutomationRun.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          1,
        );
        await publishRules(['shiftReminder'], [recordId], 'explicit-reenroll');
        await planAll();
        expect(
          await AutomationRun.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          2,
        );
      },
    );
    test(
      'outbox recovery, duplicate wakeups and authorization at delivery',
      () async {
        final s = await member('alex');
        await Commands.execute(s, claim('claim'));
        final d = await Builder.begin(owner, workspace, 'volunteer', appId);
        final enabled = ['shiftReminder'], scope = [recordId];
        await Builder.publish(
          owner,
          PublishRequest(
            draftId: d.draftId,
            candidateHash: d.candidateHash,
            expectedCurrentVersionId: version,
            enabledRuleIds: enabled,
            activateExistingRecordIds: scope,
            reviewHash: hashJson({
              'candidateHash': d.candidateHash,
              'enabledRuleIds': enabled,
              'activateExistingRecordIds': scope,
            }),
            idempotencyKey: 'with-rule',
          ),
        );
        final events = await OutboxEvent.db.find(
          owner,
          where: (t) => t.appId.equals(appId),
        );
        for (final e in events) {
          await Worker.plan(owner, e.id!);
          await Worker.plan(owner, e.id!);
        }
        final runs = await AutomationRun.db.find(
          owner,
          where: (t) => t.appId.equals(appId),
        );
        expect(runs.length, 1);
        final originalClock = clock;
        clock = () => runs.single.dueAt.add(const Duration(seconds: 1));
        try {
          await Worker.execute(owner, runs.single.id!);
          await Worker.execute(owner, runs.single.id!);
        } finally {
          clock = originalClock;
        }
        expect((await Sharing.inbox(s)).length, 1);
        expect(
          await Notification.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          1,
        );
        await Sharing.setGrant(owner, appId, actor(s), null);
        expect(await Sharing.inbox(s), isEmpty);
      },
    );
    test(
      'different definitions and a relabeled fourth app use identical CRUD handlers',
      () async {
        for (final key in ['reading', 'chores']) {
          final id = await Apps.instantiate(owner, workspace, key),
              manifest = await Apps.manifest(owner, id),
              spec = AppSpec.parse(manifest.specJson!),
              col = spec.collections.first;
          final data = syntheticRecords(col).first;
          for (final f in col.fields.where((f) => f.type == FieldType.member)) {
            data[f.id] = actor(owner);
          }
          final create = spec.actions.firstWhere(
            (a) => a.capability == 'records.create.v1',
          );
          final result = await Commands.execute(
            owner,
            ActionRequest(
              appId: id,
              actionId: create.id,
              expectedDefinitionVersionId: manifest.versionId!,
              input: {'data': data},
              idempotencyKey: 'add',
            ),
          );
          expect(
            (await Queries.get(user(actor(owner)), id, result.recordId)).data,
            data,
          );
          if (key == 'chores') {
            final patch = spec.actions.firstWhere(
              (a) => a.capability == 'records.patch.v1',
            );
            await expectLater(
              Commands.execute(
                owner,
                ActionRequest(
                  appId: id,
                  actionId: patch.id,
                  targetRecordId: result.recordId,
                  expectedDefinitionVersionId: manifest.versionId!,
                  expectedRecordRevision: 1,
                  input: {
                    'data': {'status': 'Done'},
                  },
                  idempotencyKey: 'protected',
                ),
              ),
              throwsA(isA<NestError>()),
            );
            await Commands.execute(
              owner,
              ActionRequest(
                appId: id,
                actionId: 'moveChore',
                targetRecordId: result.recordId,
                expectedDefinitionVersionId: manifest.versionId!,
                expectedRecordRevision: 1,
                input: {'value': 'Doing'},
                idempotencyKey: 'transition',
              ),
            );
          }
        }
        final custom = starterTemplates()['reading']!
            .patch({
              'type': 'RenameLabel',
              'targetId': 'app',
              'label': 'Seed Library',
            }, () => 'unused')
            .patch({
              'type': 'RenameLabel',
              'targetId': 'title',
              'label': 'Variety',
            }, () => 'unused');
        final id = await Apps.create(owner, workspace, custom),
            m = await Apps.manifest(owner, id);
        await Commands.execute(
          owner,
          ActionRequest(
            appId: id,
            actionId: 'addBook',
            expectedDefinitionVersionId: m.versionId!,
            input: {
              'data': {'title': 'Tomato', 'status': 'Reading'},
            },
            idempotencyKey: 'seed',
          ),
        );
        expect(
          (await Queries.query(
            owner,
            id,
            'books',
            '{}',
          )).records.single.data['title'],
          'Tomato',
        );
      },
    );
    test(
      'database rejects cross-app scope and impossible capacity independently of endpoints',
      () async {
        final other = await Apps.instantiate(owner, workspace, 'volunteer');
        final pool = (await ResourcePool.db.findFirstRow(
          owner,
          where: (t) => t.appId.equals(appId),
        ))!;
        await expectLater(
          ResourcePool.db.updateRow(owner, pool.copyWith(capacity: -1)),
          throwsA(anything),
        );
        await expectLater(
          Claim.db.insertRow(
            owner,
            Claim(
              appId: other,
              workspaceId: workspace,
              poolId: pool.id!,
              actorId: 'intruder',
              active: true,
              createdAt: clock(),
              updatedAt: clock(),
            ),
          ),
          throwsA(anything),
        );
        expect((await ResourcePool.db.findById(owner, pool.id!))!.capacity, 1);
      },
    );
    test(
      'recipient-bound invitations and revocations do not leak app or notification IDs',
      () async {
        final token = await Sharing.invite(
          owner,
          appId,
          'viewer',
          'recipient-$prefix',
        );
        await expectLater(
          Sharing.accept(user('wrong-$prefix'), token),
          throwsA(isA<NestError>()),
        );
        expect(await Sharing.accept(user('recipient-$prefix'), token), appId);
        await Sharing.revokeInvite(owner, appId, token);
        await expectLater(
          Sharing.accept(user('recipient-$prefix'), token),
          throwsA(isA<NestError>()),
        );
        await expectLater(
          Sharing.read(user('wrong-$prefix'), 999999),
          throwsA(isA<NestError>()),
        );
        await expectLater(
          Queries.get(
            owner,
            await Apps.instantiate(owner, workspace, 'reading'),
            recordId,
          ),
          throwsA(isA<NestError>()),
        );
      },
    );
    test(
      'date changes, archive, rule disable and revoked execution grant suppress occurrences',
      () async {
        for (final reason in ['date', 'archive', 'rule', 'grant']) {
          final id = await Apps.instantiate(owner, workspace, 'volunteer'),
              m = await Apps.manifest(owner, id);
          final record = await Commands.execute(
            owner,
            ActionRequest(
              appId: id,
              actionId: 'addShift',
              expectedDefinitionVersionId: m.versionId!,
              input: {
                'data': {
                  'title': reason,
                  'startsAt': clock()
                      .add(const Duration(hours: 2))
                      .toIso8601String(),
                },
                'capacity': 2,
              },
              idempotencyKey: 'create',
            ),
          );
          final rule = await Automation.db.insertRow(
            owner,
            Automation(
              appId: id,
              workspaceId: workspace,
              ruleId: 'shiftReminder',
              ruleVersion: 1,
              ruleJson: canonicalJson(
                starterTemplates()['volunteer']!.automationRequests.single
                    .toJson(),
              ),
              enabled: true,
              executionActorId: reason == 'grant'
                  ? 'revoked-user'
                  : actor(owner),
              activateExisting: true,
              activatedAt: clock().subtract(const Duration(days: 1)),
            ),
          );
          final events = await OutboxEvent.db.find(
            owner,
            where: (t) => t.appId.equals(id),
          );
          for (final event in events) {
            await Worker.plan(owner, event.id!);
          }
          final run = (await AutomationRun.db.findFirstRow(
            owner,
            where: (t) => t.appId.equals(id),
          ))!;
          if (reason == 'date') {
            await Commands.execute(
              owner,
              ActionRequest(
                appId: id,
                actionId: 'editShift',
                targetRecordId: record.recordId,
                expectedDefinitionVersionId: m.versionId!,
                expectedRecordRevision: 1,
                input: {
                  'data': {
                    'startsAt': clock()
                        .add(const Duration(hours: 4))
                        .toIso8601String(),
                  },
                },
                idempotencyKey: 'date',
              ),
            );
          }
          if (reason == 'archive') await Apps.archive(owner, id);
          if (reason == 'rule') {
            rule.enabled = false;
            await Automation.db.updateRow(owner, rule);
          }
          final previousClock = clock;
          clock = () => run.dueAt.add(const Duration(seconds: 1));
          try {
            await Worker.execute(owner, run.id!);
          } finally {
            clock = previousClock;
          }
          expect(
            (await AutomationRun.db.findById(owner, run.id!))!.status,
            'suppressed',
            reason: reason,
          );
          expect(
            await Notification.db.count(
              owner,
              where: (t) => t.appId.equals(id),
            ),
            0,
          );
        }
      },
    );
    test(
      'malformed AI is bounded, stale jobs cannot overwrite manual edits, existing apps work',
      () async {
        var d = await Builder.begin(owner, workspace, 'volunteer', appId);
        Future<GenerationJob> job(int mutation) async {
          final j = await GenerationJob.db.insertRow(
            owner,
            GenerationJob(
              appId: appId,
              draftId: d.draftId,
              actorId: actor(owner),
              mutation: mutation,
              status: 'queued',
              requestText: 'Add a note',
              mode: 'edit',
              promptVersion: 'test',
              nextAttemptAt: clock(),
              diagnostics: '',
              usageJson: '{}',
              createdAt: clock(),
              updatedAt: clock(),
            ),
          );
          final row = (await AppDraft.db.findById(owner, d.draftId))!
            ..activeJobId = j.id;
          await AppDraft.db.updateRow(owner, row);
          return j;
        }

        final malformed = await job(d.mutation);
        for (var i = 0; i < 3; i++) {
          final stored = (await GenerationJob.db.findById(
            owner,
            malformed.id!,
          ))!;
          final previous = clock;
          clock = () => stored.nextAttemptAt;
          try {
            await Worker.generate(
              owner,
              malformed.id!,
              provider: FakeAiProvider('not JSON'),
            );
          } finally {
            clock = previous;
          }
        }
        expect(
          (await GenerationJob.db.findById(owner, malformed.id!))!.status,
          'failed',
        );
        expect((await Queries.query(owner, appId, 'shifts', '{}')).total, 1);
        final obsolete = await job(d.mutation);
        d = await Builder.patch(
          owner,
          d.draftId,
          d.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'app',
            'label': 'New label',
          }),
        );
        await Worker.generate(
          owner,
          obsolete.id!,
          provider: FakeAiProvider('{}'),
        );
        expect(
          (await GenerationJob.db.findById(owner, obsolete.id!))!.status,
          'stale',
        );
        expect(
          (await Builder.get(owner, d.draftId)).candidateHash,
          d.candidateHash,
        );
      },
    );
    test(
      'cursor paging is deterministic, query rejection is explicit, stream access is rechecked',
      () async {
        for (var i = 0; i < 3; i++) {
          await Commands.execute(
            owner,
            ActionRequest(
              appId: appId,
              actionId: 'addShift',
              expectedDefinitionVersionId: version,
              input: {
                'data': {
                  'title': 'More $i',
                  'startsAt': clock().toIso8601String(),
                },
                'capacity': 1,
              },
              idempotencyKey: 'more$i',
            ),
          );
        }
        final first = await Queries.query(
              owner,
              appId,
              'shifts',
              jsonEncode({'limit': 2}),
            ),
            next = await Queries.query(
              owner,
              appId,
              'shifts',
              jsonEncode({'limit': 2, 'cursor': first.nextCursor}),
            );
        expect(first.total, 4);
        expect(
          next.records
              .map((r) => r.id)
              .toSet()
              .intersection(first.records.map((r) => r.id).toSet()),
          isEmpty,
        );
        await expectLater(
          Queries.query(owner, appId, 'shifts', '{"limit":101}'),
          throwsA(isA<NestError>()),
        );
        final s = await member('stream');
        final builder = sessions.copyWith(
          authentication: AuthenticationOverride.authenticationInfo(
            actor(s),
            {},
          ),
        );
        final stream = endpoints.runtime
            .events(builder, appId)
            .asBroadcastStream();
        expect((await stream.first).appId, appId);
        await Sharing.setGrant(owner, appId, actor(s), null);
        await expectLater(stream.first, throwsA(isA<NestError>()));
      },
    );
  }, rollbackDatabase: RollbackDatabase.disabled);
}
