import 'dart:convert';

import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_server/src/modules/runtime/queries.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Personal utility publication lifecycle', (
    sessions,
    endpoints,
  ) {
    late Session owner;
    late int workspace;
    var sequence = 0;
    setUpAll(() async => Integrity.ensure(sessions.build()));
    setUp(() async {
      owner = sessions
          .copyWith(
            authentication: AuthenticationOverride.authenticationInfo(
              'utilities-${randomToken()}',
              {},
            ),
          )
          .build();
      workspace = await Apps.createWorkspace(owner, 'Personal utilities');
    });

    Future<int> publish(
      BuilderSnapshot draft, {
      List<String> enabled = const [],
    }) => Builder.publish(
      owner,
      PublishRequest(
        draftId: draft.draftId,
        candidateHash: draft.candidateHash,
        expectedCurrentVersionId: draft.baseVersionId,
        enabledRuleIds: enabled,
        activateExistingRecordIds: [],
        reviewHash: hashJson({
          'candidateHash': draft.candidateHash,
          'enabledRuleIds': enabled,
          'activateExistingRecordIds': [],
        }),
        idempotencyKey: 'utility-publish-${sequence++}',
      ),
    );

    test(
      'focus has no artificial records through begin, edit, publish and reopen',
      () async {
        var draft = await Builder.begin(owner, workspace, 'focus', null);
        expect(AppSpec.parse(draft.candidateJson).collections, isEmpty);
        draft = await Builder.patch(
          owner,
          draft.draftId,
          draft.mutation,
          jsonEncode({
            'type': 'UpdateView',
            'viewId': 'focusTimer',
            'view': {
              'type': 'timer',
              'label': 'Deep work',
              'options': {'durationMinutes': 45},
            },
          }),
        );
        final version = await publish(draft);
        final manifest = await Apps.manifest(owner, draft.appId);
        expect(manifest.versionId, version);
        final spec = AppSpec.parse(manifest.specJson!);
        expect(spec.collections, isEmpty);
        expect(spec.actions, isEmpty);
        expect(spec.view('focusTimer').options['durationMinutes'], 45);
        final reopened = await Builder.begin(
          owner,
          workspace,
          'focus',
          draft.appId,
        );
        expect(reopened.candidateReady, isTrue);
        expect(reopened.candidateHash, draft.candidateHash);
        expect(
          await EntityRecord.db.count(
            owner,
            where: (t) => t.appId.equals(draft.appId),
          ),
          0,
        );
      },
    );

    test(
      'Phone Toolkit publishes definitions without device grants or data',
      () async {
        final draft = await Builder.begin(
          owner,
          workspace,
          'phoneToolkit',
          null,
        );
        final version = await publish(draft);
        final manifest = await Apps.manifest(owner, draft.appId);
        expect(manifest.versionId, version);
        final spec = AppSpec.parse(manifest.specJson!);
        expect(
          requestedDeviceCapabilities(spec),
          deviceCapabilityLabels.keys.toSet(),
        );
        expect(spec.collections, isEmpty);
        expect(spec.automationRequests, isEmpty);
        expect(
          await EntityRecord.db.count(
            owner,
            where: (t) => t.appId.equals(draft.appId),
          ),
          0,
        );
        expect(
          await Automation.db.count(
            owner,
            where: (t) => t.appId.equals(draft.appId),
          ),
          0,
        );
        final reopened = await Builder.begin(
          owner,
          workspace,
          'phoneToolkit',
          draft.appId,
        );
        expect(reopened.candidateHash, spec.hash);
      },
    );

    for (final key in ['notes', 'reminders', 'calendar']) {
      test('$key publishes and supports authenticated create/edit', () async {
        final draft = await Builder.begin(owner, workspace, key, null);
        final version = await publish(draft);
        final spec = AppSpec.parse(draft.candidateJson);
        final collection = spec.collections.first;
        final create = spec.actions.firstWhere(
          (a) => a.capability == 'records.create.v1',
        );
        final edit = spec.actions.firstWhere(
          (a) => a.capability == 'records.patch.v1',
        );
        final data = <String, dynamic>{
          'title': 'A useful personal entry',
          if (key == 'notes') 'body': 'Line one\nLine two',
          if (key == 'reminders') 'status': 'Open',
          if (key == 'reminders')
            'reminderAt': clock()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          if (key == 'calendar')
            'startsAt': clock().add(const Duration(days: 1)).toIso8601String(),
        };
        final created = await Commands.execute(
          owner,
          ActionRequest(
            appId: draft.appId,
            actionId: create.id,
            expectedDefinitionVersionId: version,
            input: {'data': data},
            idempotencyKey: 'utility-create',
          ),
        );
        var record = await Queries.get(owner, draft.appId, created.recordId);
        await Commands.execute(
          owner,
          ActionRequest(
            appId: draft.appId,
            actionId: edit.id,
            targetRecordId: record.id,
            expectedDefinitionVersionId: version,
            expectedRecordRevision: record.revision,
            input: {
              'data': {'title': 'My customized entry'},
            },
            idempotencyKey: 'utility-edit',
          ),
        );
        record = await Queries.get(owner, draft.appId, record.id);
        expect((record.data as Map)['title'], 'My customized entry');
        expect(
          (await Queries.query(owner, draft.appId, collection.id, '{}')).total,
          1,
        );

        if (key == 'notes') {
          var revision = await Builder.begin(
            owner,
            workspace,
            key,
            draft.appId,
          );
          revision = await Builder.patch(
            owner,
            revision.draftId,
            revision.mutation,
            jsonEncode({
              'type': 'SetAppearance',
              'appearance': {'style': 'editorial'},
            }),
          );
          revision = await Builder.patch(
            owner,
            revision.draftId,
            revision.mutation,
            jsonEncode({
              'type': 'AddField',
              'collectionId': collection.id,
              'field': {'label': 'Mood', 'type': 'text', 'required': false},
            }),
          );
          await publish(revision);
          final retained = await Queries.get(owner, draft.appId, record.id);
          expect((retained.data as Map)['body'], 'Line one\nLine two');
          expect((retained.data as Map)['title'], 'My customized entry');
          expect(retained.revision, record.revision);
        }
      });
    }

    test('changed reminder approval resets after reopening and old records stay unenrolled', () async {
      var draft = await Builder.begin(owner, workspace, 'reminders', null);
      final version = await publish(draft, enabled: ['taskReminder']);
      final created = await Commands.execute(
        owner,
        ActionRequest(
          appId: draft.appId,
          actionId: 'addTask',
          expectedDefinitionVersionId: version,
          input: {
            'data': {
              'title': 'Previously enrolled',
              'status': 'Open',
              'reminderAt': clock()
                  .add(const Duration(hours: 2))
                  .toIso8601String(),
            },
          },
          idempotencyKey: 'old-reminder',
        ),
      );
      for (final event in await OutboxEvent.db.find(
        owner,
        where: (t) => t.appId.equals(draft.appId),
      )) {
        await Worker.plan(owner, event.id!);
      }
      draft = await Builder.begin(owner, workspace, 'reminders', draft.appId);
      expect(draft.enabledRuleIds, ['taskReminder']);
      final rule = AppSpec.parse(
        draft.candidateJson,
      ).automationRequests.single.toJson()..remove('id');
      (rule['trigger'] as Map)['offsetSeconds'] = 300;
      draft = await Builder.patch(
        owner,
        draft.draftId,
        draft.mutation,
        jsonEncode({
          'type': 'UpdateReminder',
          'ruleId': 'taskReminder',
          'rule': rule,
        }),
      );
      expect(draft.enabledRuleIds, isEmpty);
      expect((await Builder.get(owner, draft.draftId)).enabledRuleIds, isEmpty);
      final changedVersion = await publish(draft, enabled: ['taskReminder']);
      expect(changedVersion, isNot(version));
      final automation = (await Automation.db.findFirstRow(
        owner,
        where: (t) => t.appId.equals(draft.appId),
      ))!;
      expect(automation.ruleVersion, 2);
      for (final event in await OutboxEvent.db.find(
        owner,
        where: (t) => t.appId.equals(draft.appId),
      )) {
        await Worker.plan(owner, event.id!);
      }
      final runs = await AutomationRun.db.find(
        owner,
        where: (t) => t.appId.equals(draft.appId),
      );
      expect(runs.any((run) => run.ruleVersion == 2), isFalse);
      expect(
        (await Queries.get(owner, draft.appId, created.recordId)).id,
        created.recordId,
      );
    });
  }, rollbackDatabase: RollbackDatabase.disabled);
}
