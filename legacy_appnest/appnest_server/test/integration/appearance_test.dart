import 'dart:convert';

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
import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Appearance publication and generation', (sessions, endpoints) {
    Session user() => sessions
        .copyWith(
          authentication: AuthenticationOverride.authenticationInfo(
            'appearance-${randomToken()}',
            {},
          ),
        )
        .build();

    setUpAll(() => Integrity.ensure(sessions.build()));

    Future<int> publish(
      Session owner,
      BuilderSnapshot draft,
      int? version, {
      List<String> rules = const [],
    }) => Builder.publish(
      owner,
      PublishRequest(
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
        idempotencyKey: 'publish-${randomToken()}',
      ),
    );

    Future<BuilderSnapshot> generate(
      Session owner,
      BuilderSnapshot draft,
      String output, {
      required String mode,
    }) async {
      final job = await GenerationJob.db.insertRow(
        owner,
        GenerationJob(
          appId: draft.appId,
          draftId: draft.draftId,
          actorId: actor(owner),
          mutation: draft.mutation,
          status: 'queued',
          requestText: 'Synthetic appearance integration check',
          mode: mode,
          promptVersion: 'appearance-test',
          attempts: Limits.generationAttempts - 1,
          nextAttemptAt: clock(),
          diagnostics: '',
          usageJson: '{}',
          createdAt: clock(),
          updatedAt: clock(),
        ),
      );
      final row = (await AppDraft.db.findById(owner, draft.draftId))!
        ..activeJobId = job.id;
      await AppDraft.db.updateRow(owner, row);
      await Worker.generate(owner, job.id!, provider: FakeAiProvider(output));
      final next = await Builder.get(owner, draft.draftId);
      expect(next.stage, 'preview ready', reason: next.diagnostics.join('; '));
      return next;
    }

    test('restyling persists without changing records, grants or reminder enrollment', () async {
      final owner = user(), viewer = user(), stranger = user();
      final workspace = await Apps.createWorkspace(owner, 'Appearance test');
      var draft = await Builder.begin(owner, workspace, 'planner', null);
      final appId = draft.appId;
      var version = await publish(owner, draft, null, rules: ['taskReminder']);
      await Sharing.accept(
        viewer,
        await Sharing.invite(owner, appId, 'viewer', null),
      );
      final recordId = (await Commands.execute(
        owner,
        ActionRequest(
          appId: appId,
          actionId: 'addTask',
          expectedDefinitionVersionId: version,
          input: {
            'data': {
              'title': 'Keep the same task',
              'status': 'Open',
              'priority': 'Normal',
              'reminderAt': clock()
                  .add(const Duration(hours: 2))
                  .toIso8601String(),
            },
          },
          idempotencyKey: 'record-${randomToken()}',
        ),
      )).recordId;
      final recordBefore = await Queries.get(owner, appId, recordId);
      final reminderBefore = (await Queries.reminderState(
        owner,
        appId,
        recordId,
      )).single;
      final ruleBefore = (await Automation.db.findFirstRow(
        owner,
        where: (t) => t.appId.equals(appId),
      ))!;
      final original = AppSpec.parse(
        (await Apps.manifest(owner, appId)).specJson!,
      );
      draft = await Builder.begin(owner, workspace, 'planner', appId);
      final appearancePatch = jsonEncode({
        'type': 'SetAppearance',
        'appearance': {'style': 'editorial', 'accentColor': '#386641'},
      });
      await expectLater(
        Builder.patch(stranger, draft.draftId, draft.mutation, appearancePatch),
        throwsA(isA<NestError>()),
      );
      await expectLater(
        Builder.patch(viewer, draft.draftId, draft.mutation, appearancePatch),
        throwsA(isA<NestError>()),
      );
      final previous = draft;
      draft = await Builder.patch(
        owner,
        draft.draftId,
        draft.mutation,
        appearancePatch,
      );
      await expectLater(
        Builder.patch(
          owner,
          previous.draftId,
          previous.mutation,
          appearancePatch,
        ),
        throwsA(isA<NestError>()),
      );
      draft = await Builder.patch(
        owner,
        draft.draftId,
        draft.mutation,
        jsonEncode({
          'type': 'UpdatePage',
          'pageId': 'todayPage',
          'page': {
            ...original.page('todayPage').toJson()..remove('id'),
            'layout': 'featuredFirst',
          },
        }),
      );
      // Unpublished appearance remains private to the draft.
      expect(
        AppSpec.parse((await Apps.manifest(viewer, appId)).specJson!)
            .appearance,
        isNull,
      );
      expect(draft.enabledRuleIds, ['taskReminder']);
      version = await publish(
        owner,
        draft,
        version,
        rules: draft.enabledRuleIds,
      );
      final manifest = await Apps.manifest(viewer, appId);
      final saved = AppSpec.parse(manifest.specJson!);
      expect(saved.hash, draft.candidateHash);
      expect(saved.appearance!.style, 'editorial');
      expect(saved.page('todayPage').layout, 'featuredFirst');
      expect(manifest.approvedRuleIds, ['taskReminder']);
      final recordAfter = await Queries.get(owner, appId, recordId);
      expect(recordAfter.data, recordBefore.data);
      expect(recordAfter.revision, recordBefore.revision);
      expect(
        (await Queries.get(viewer, appId, recordId)).allowedActions,
        isEmpty,
      );
      final ruleAfter = (await Automation.db.findById(owner, ruleBefore.id!))!;
      expect(ruleAfter.ruleVersion, ruleBefore.ruleVersion);
      expect(ruleAfter.ruleJson, ruleBefore.ruleJson);
      expect(ruleAfter.executionActorId, ruleBefore.executionActorId);
      expect(
        (await Queries.reminderState(owner, appId, recordId)).single.state,
        reminderBefore.state,
      );
      expect(original.compatibilityErrors(saved), isEmpty);
      await expectLater(
        Queries.get(stranger, appId, recordId),
        throwsA(isA<NestError>()),
      );
    });

    test(
      'AI-selected styles survive create, publish and presentation-only edit',
      () async {
        final owner = user();
        final workspace = await Apps.createWorkspace(owner, 'Design examples');
        for (final (name, template, style) in [
          ('Reading journal', 'reading', 'editorial'),
          ('Plant care', 'photoJournal', 'playful'),
          ('Trip planner', 'planner', 'clean'),
        ]) {
          var spec = starterTemplates()[template]!.patch({
            'type': 'RenameLabel',
            'targetId': 'app',
            'label': name,
          }, () => throw StateError('No IDs'));
          spec = spec.patch({
            'type': 'SetAppearance',
            'appearance': {'style': style},
          }, () => throw StateError('No IDs'));
          var draft = await Builder.begin(owner, workspace, 'reading', null);
          draft = await generate(owner, draft, spec.canonical, mode: 'create');
          expect(draft.candidateHash, spec.hash);
          final version = await publish(owner, draft, null);
          final published = AppSpec.parse(
            (await Apps.manifest(owner, draft.appId)).specJson!,
          );
          expect(published.hash, spec.hash);
          draft = await Builder.begin(owner, workspace, template, draft.appId);
          draft = await generate(
            owner,
            draft,
            jsonEncode({
              'patches': [
                {
                  'type': 'SetAppearance',
                  'appearance': {'style': style, 'density': 'spacious'},
                },
              ],
            }),
            mode: 'edit',
          );
          final after = AppSpec.parse(draft.candidateJson);
          final afterJson = after.toJson()..remove('appearance');
          final beforeJson = published.toJson()..remove('appearance');
          expect(afterJson, beforeJson);
          await publish(owner, draft, version);
          expect(
            AppSpec.parse((await Apps.manifest(owner, draft.appId)).specJson!)
                .hash,
            after.hash,
          );
        }
      },
    );
  }, rollbackDatabase: RollbackDatabase.disabled);
}
