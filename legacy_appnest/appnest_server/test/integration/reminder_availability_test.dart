import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_server/src/modules/runtime/queries.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod(
    'Reminders with background jobs disabled',
    (sessions, endpoints) {
      late Session owner;
      late int workspace, appId, version;
      late DateTime now;
      late DateTime Function() originalClock;

      setUpAll(() async => Integrity.ensure(sessions.build()));
      setUp(() async {
        originalClock = clock;
        now = DateTime.utc(2030, 3, 10, 12);
        clock = () => now;
        owner = sessions
            .copyWith(
              authentication: AuthenticationOverride.authenticationInfo(
                'starter-owner-${randomToken()}',
                {},
              ),
            )
            .build();
        workspace = await Apps.createWorkspace(owner, 'Starter reminders');
        appId = await Apps.instantiate(owner, workspace, 'planner');
        version = (await Apps.manifest(owner, appId)).versionId!;
      });
      tearDown(() => clock = originalClock);

      PublishRequest publication(
        BuilderSnapshot draft, {
        bool enableReminder = false,
        String key = 'publish',
      }) {
        final rules = enableReminder ? ['taskReminder'] : <String>[];
        return PublishRequest(
          draftId: draft.draftId,
          candidateHash: draft.candidateHash,
          expectedCurrentVersionId: version,
          enabledRuleIds: rules,
          activateExistingRecordIds: const [],
          reviewHash: hashJson({
            'candidateHash': draft.candidateHash,
            'enabledRuleIds': rules,
            'activateExistingRecordIds': [],
          }),
          idempotencyKey: key,
        );
      }

      Future<int> createTask(DateTime reminderAt) async {
        final outcome = await Commands.execute(
          owner,
          ActionRequest(
            appId: appId,
            actionId: 'addTask',
            expectedDefinitionVersionId: version,
            input: {
              'data': {
                'title': 'Starter task',
                'status': 'Open',
                'reminderAt': reminderAt.toIso8601String(),
              },
            },
            idempotencyKey: 'create-task',
          ),
        );
        return outcome.recordId;
      }

      test('reminder approval rejects before publication writes', () async {
        final draft = await Builder.begin(owner, workspace, 'planner', appId);
        final eventCount = await OutboxEvent.db.count(
          owner,
          where: (t) => t.appId.equals(appId),
        );
        await expectLater(
          Builder.publish(owner, publication(draft, enableReminder: true)),
          throwsA(
            isA<NestError>()
                .having(
                  (error) => error.category,
                  'category',
                  'unsupportedCapability',
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('Publish without enabling reminders'),
                ),
          ),
        );
        expect((await Apps.manifest(owner, appId)).versionId, version);
        expect(
          await AppVersion.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          1,
        );
        expect(
          (await AppDraft.db.findById(
            owner,
            draft.draftId,
          ))!.publishedVersionId,
          isNull,
        );
        expect(
          await Automation.db.count(owner, where: (t) => t.appId.equals(appId)),
          0,
        );
        expect(
          await ActionReceipt.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          0,
        );
        expect(
          await OutboxEvent.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          eventCount,
        );
        expect(
          await AutomationRun.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          0,
        );
      });

      test(
        'manual publication and record edits keep working without approval',
        () async {
          var draft = await Builder.begin(owner, workspace, 'planner', appId);
          draft = await Builder.patch(
            owner,
            draft.draftId,
            draft.mutation,
            jsonEncode({
              'type': 'RenameLabel',
              'targetId': 'todayPage',
              'label': 'Starter day',
            }),
          );
          version = await Builder.publish(owner, publication(draft));
          final due = now.add(const Duration(hours: 1));
          final id = await createTask(due);
          final task = await Queries.get(owner, appId, id);
          await Commands.execute(
            owner,
            ActionRequest(
              appId: appId,
              actionId: 'editTask',
              targetRecordId: id,
              expectedDefinitionVersionId: version,
              expectedRecordRevision: task.revision,
              input: {
                'data': {'notes': 'Saved on Starter'},
              },
              idempotencyKey: 'edit-task',
            ),
          );
          expect(
            (await Queries.get(owner, appId, id)).data['notes'],
            'Saved on Starter',
          );
          expect(
            AppSpec.parse((await Apps.manifest(owner, appId)).specJson!)
                .page('todayPage')
                .title,
            'Starter day',
          );
          final reminder = (await Queries.reminderState(
            owner,
            appId,
            id,
          )).single;
          expect(reminder.state, 'disabled');
          expect(reminder.eligible, isFalse);
          expect(reminder.scheduledAt, due);
          await Worker.drain(owner);
          expect(
            await AutomationRun.db.count(
              owner,
              where: (t) => t.appId.equals(appId),
            ),
            0,
          );
        },
      );

      test(
        'legacy approvals and pending runs cannot enqueue or deliver',
        () async {
          final definition = dailyPlannerTemplate().automationRequests.single;
          final due = now.subtract(const Duration(minutes: 1));
          final rule = await Automation.db.insertRow(
            owner,
            Automation(
              appId: appId,
              workspaceId: workspace,
              ruleId: definition.id,
              ruleVersion: 1,
              ruleJson: canonicalJson(definition.toJson()),
              enabled: true,
              executionActorId: actor(owner),
              activateExisting: false,
              activatedAt: now.subtract(const Duration(hours: 1)),
            ),
          );
          final id = await createTask(due);
          for (final event in await OutboxEvent.db.find(
            owner,
            where: (t) => t.appId.equals(appId),
          )) {
            await Worker.plan(owner, event.id!);
          }
          expect(
            await AutomationRun.db.count(
              owner,
              where: (t) => t.appId.equals(appId),
            ),
            0,
          );
          final run = await AutomationRun.db.insertRow(
            owner,
            AutomationRun(
              appId: appId,
              automationId: rule.id!,
              ruleVersion: rule.ruleVersion,
              recordId: id,
              occurrenceKey: 'starter-${randomToken()}',
              scheduleSignature: Worker.scheduleSignature(
                rule,
                due.toIso8601String(),
                due,
              ),
              dueAt: due,
              nextAttemptAt: due,
              status: 'pending',
              createdAt: now,
            ),
          );
          await Worker.execute(owner, run.id!);
          await Worker.drain(owner);
          final unchanged = (await AutomationRun.db.findById(owner, run.id!))!;
          expect(unchanged.status, 'pending');
          expect(unchanged.attempts, 0);
          expect(unchanged.completedAt, isNull);
          expect(
            await AutomationRun.db.count(
              owner,
              where: (t) => t.appId.equals(appId),
            ),
            1,
          );
          expect(
            await Notification.db.count(
              owner,
              where: (t) => t.appId.equals(appId),
            ),
            0,
          );
          final reminder = (await Queries.reminderState(
            owner,
            appId,
            id,
          )).single;
          expect(reminder.state, 'disabled');
          expect(reminder.eligible, isFalse);
        },
      );
    },
    configOverride: (config) =>
        config.copyWith(futureCallExecutionEnabled: false),
  );
}
