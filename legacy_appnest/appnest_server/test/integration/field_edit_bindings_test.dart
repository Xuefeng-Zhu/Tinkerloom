import 'dart:convert';

import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/queries.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Compound field edit', (sessions, endpoints) {
    Session user(String id) => sessions
        .copyWith(
          authentication: AuthenticationOverride.authenticationInfo(id, {}),
        )
        .build();
    late Session owner;
    late int workspace, appId, version, recordId;
    late Map<String, String> originalPasswords;

    setUp(() async {
      owner = user('field-edit-${randomToken()}');
      originalPasswords = owner.server.passwords;
      // Enable enqueue with synthetic configuration. Worker calls below always
      // inject FakeAiProvider, so this test never calls an external AI service.
      owner.server.passwords = {
        ...originalPasswords,
        'AI_BASE_URL': 'https://example.invalid/v1',
        'AI_MODEL': 'test-only',
        'AI_API_KEY': 'test-only',
      };
      workspace = await Apps.createWorkspace(owner, 'Compound field test');
      appId = await Apps.instantiate(owner, workspace, 'notes');
      version = (await Apps.manifest(owner, appId)).versionId!;
      recordId = (await Commands.execute(
        owner,
        ActionRequest(
          appId: appId,
          actionId: 'addRecord',
          expectedDefinitionVersionId: version,
          input: {
            'data': {'title': 'Existing note', 'body': 'Keep this content'},
          },
          idempotencyKey: 'initial-note',
        ),
      )).recordId;
    });
    tearDown(() => owner.server.passwords = originalPasswords);

    test('AI rename and Priority binding publishes without changing existing records', () async {
      final before = await Queries.get(owner, appId, recordId);
      final initial = AppSpec.parse(
        (await Apps.manifest(owner, appId)).specJson!,
      );
      final draft = await Builder.begin(owner, workspace, 'notes', appId);
      final queued = await Builder.generate(
        owner,
        draft.draftId,
        draft.mutation,
        'Rename the app and add optional Priority to the list, details and editor.',
      );
      await Worker.generate(
        owner,
        queued.jobId!,
        provider: FakeAiProvider(
          jsonEncode({
            'patches': [
              {
                'type': 'RenameLabel',
                'targetId': 'app',
                'label': 'Priority Notes',
              },
              {
                'type': 'AddField',
                'collectionId': 'notes',
                'field': {
                  'label': 'Priority',
                  'type': 'choice',
                  'required': false,
                  'choices': ['Low', 'Normal', 'High'],
                },
                'viewIds': ['allEntries', 'entryDetails', 'entryEditor'],
              },
            ],
          }),
        ),
      );
      final ready = await Builder.get(owner, draft.draftId);
      expect(
        ready.stage,
        'preview ready',
        reason: ready.diagnostics.join('; '),
      );
      expect(
        (await GenerationJob.db.findById(owner, queued.jobId!))!.attempts,
        1,
      );
      final candidate = AppSpec.parse(ready.candidateJson);
      final field = candidate.collection('notes').fields.last;
      expect(candidate.name, 'Priority Notes');
      expect(field.label, 'Priority');
      expect(field.id, isNot('priority'));
      for (final id in ['allEntries', 'entryDetails', 'entryEditor']) {
        expect(candidate.view(id).fieldIds, [
          ...initial.view(id).fieldIds,
          field.id,
        ]);
      }
      expect(initial.compatibilityErrors(candidate), isEmpty);
      // Accepted draft changes do not alter the live manifest or existing data.
      expect((await Apps.manifest(owner, appId)).versionId, version);
      expect(
        (await Queries.get(owner, appId, recordId)).toJson(),
        before.toJson(),
      );

      final nextVersion = await Builder.publish(
        owner,
        PublishRequest(
          draftId: ready.draftId,
          candidateHash: ready.candidateHash,
          expectedCurrentVersionId: version,
          enabledRuleIds: [],
          activateExistingRecordIds: [],
          reviewHash: hashJson({
            'candidateHash': ready.candidateHash,
            'enabledRuleIds': [],
            'activateExistingRecordIds': [],
          }),
          idempotencyKey: 'publish-priority',
        ),
      );
      final publishedRecord = await Queries.get(owner, appId, recordId);
      expect(publishedRecord.id, recordId);
      expect(publishedRecord.revision, before.revision);
      expect(publishedRecord.data, before.data);
      await Commands.execute(
        owner,
        ActionRequest(
          appId: appId,
          actionId: 'editRecord',
          targetRecordId: recordId,
          expectedRecordRevision: publishedRecord.revision,
          expectedDefinitionVersionId: nextVersion,
          input: {
            'data': {field.id: 'High'},
          },
          idempotencyKey: 'set-priority',
        ),
      );

      final reconnected = user(actor(owner));
      final manifest = await Apps.manifest(reconnected, appId);
      final reloaded = AppSpec.parse(manifest.specJson!);
      expect(manifest.versionId, nextVersion);
      expect(reloaded.hash, candidate.hash);
      final saved = await Queries.get(reconnected, appId, recordId);
      expect(saved.id, recordId);
      expect(saved.revision, before.revision + 1);
      expect(saved.data, {...before.data, field.id: 'High'});
      expect(
        await EntityRecord.db.count(owner, where: (t) => t.appId.equals(appId)),
        1,
      );
    });

    test(
      'a guessed field reference still rejects the whole compound edit',
      () async {
        final draft = await Builder.begin(owner, workspace, 'notes', appId);
        final queued = await Builder.generate(
          owner,
          draft.draftId,
          draft.mutation,
          'Rename and add Priority to the list.',
        );
        final job = (await GenerationJob.db.findById(owner, queued.jobId!))!
          ..attempts = Limits.generationAttempts - 1;
        await GenerationJob.db.updateRow(owner, job);
        final view = AppSpec.parse(
          draft.candidateJson,
        ).view('allEntries').toJson()..remove('id');
        view['fieldIds'] = [...view['fieldIds'] as List, 'priority'];
        await Worker.generate(
          owner,
          queued.jobId!,
          provider: FakeAiProvider(
            jsonEncode({
              'patches': [
                {
                  'type': 'RenameLabel',
                  'targetId': 'app',
                  'label': 'Rejected rename',
                },
                {
                  'type': 'AddField',
                  'collectionId': 'notes',
                  'field': {'label': 'Priority', 'type': 'text'},
                },
                {'type': 'UpdateView', 'viewId': 'allEntries', 'view': view},
              ],
            }),
          ),
        );
        final rejected = await Builder.get(owner, draft.draftId);
        expect(rejected.stage, 'failed');
        expect(
          rejected.diagnostics.join('; '),
          contains('Unknown field priority'),
        );
        expect(rejected.candidateJson, draft.candidateJson);
        expect(rejected.candidateHash, draft.candidateHash);
        expect((await Apps.manifest(owner, appId)).versionId, version);
        expect(
          (await Queries.get(owner, appId, recordId)).data['body'],
          'Keep this content',
        );
      },
    );
  }, rollbackDatabase: RollbackDatabase.disabled);
}
