import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:tinkerloom_client/tinkerloom_client.dart';

import '../../../appwrite_backend/lib/providers/provider.dart' as ai;
import '../../../appwrite_backend/lib/service.dart' as backend;
import '../../../appwrite_backend/test/spec_engine_check.dart' as checks;
import '../../../appwrite_backend/test/workers_test.dart' as workers;
import 'client_test.dart' as fixture;

class SuccessfulProvider implements ai.AiProvider {
  final edits = <bool>[];
  @override
  Future<ai.AiResult> generate(
    String request,
    spec.AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
    String? rejectedOutput,
  }) async {
    edits.add(editing);
    return ai.AiResult(
      editing
          ? jsonEncode({
              'patches': [
                {
                  'type': 'RenameLabel',
                  'targetId': 'app',
                  'label': 'Renamed reading list',
                },
              ],
            })
          : ai.creationReferenceJson,
      'offline',
      'offline',
      {},
    );
  }
}

void main() {
  test('creation intent survives a client restart and clears when the creation succeeds', () async {
    final provider = SuccessfulProvider();
    final f = fixture.Fixture(provider: provider);
    addTearDown(f.client.close);
    final workspace = await f.client.apps.createWorkspace('Offline workspace');
    final draft = await f.client.builder.begin(
      workspace,
      'volunteer',
      null,
      creationIntent: true,
    );
    expect(draft.creationIntent, isTrue);
    expect(draft.candidateReady, isFalse);
    final initialSave = f.calls.singleWhere(
      (call) => call['op'] == 'spec.saveDraft',
    );
    expect(initialSave['creationIntent'], isTrue);

    final reopenedClient = f.forActor('alice');
    addTearDown(reopenedClient.close);
    final reopened = await reopenedClient.builder.begin(
      workspace,
      'notes',
      draft.appId,
    );
    expect(reopened.creationIntent, isTrue);
    expect(reopened.candidateReady, isFalse);
    expect(reopened.candidateHash, draft.candidateHash);
    await expectLater(
      reopenedClient.builder.generate(
        reopened.draftId,
        reopened.mutation,
        'Stale edit',
        startFromScratch: false,
      ),
      throwsA(
        isA<NestError>().having(
          (error) => error.category,
          'category',
          'creation_intent_mismatch',
        ),
      ),
    );
    expect(f.store.rows['generation_jobs'], isNull);
    expect(
      (await reopenedClient.builder.get(reopened.draftId)).creationIntent,
      isTrue,
    );

    final queued = await reopenedClient.builder.generate(
      reopened.draftId,
      reopened.mutation,
      'A reading list',
      startFromScratch: reopened.creationIntent,
    );
    expect(queued.creationIntent, isTrue);
    expect(queued.stage, 'queued');
    final storedJob = f.store.rows['generation_jobs']!.values.single;
    expect(storedJob['mode'], 'create');
    await backend.WorkerEngine(f.service).generate(queued.jobId!);
    final generated = await reopenedClient.builder.get(reopened.draftId);
    expect(provider.edits, [false]);
    expect(generated.stage, 'preview ready');
    expect(generated.creationIntent, isFalse);
    expect(generated.candidateReady, isTrue);
    final before = spec.AppSpec.parse(generated.candidateJson);
    // A stale client may continue to send true: the established session still
    // converts this to an edit, preserving all collection identities.
    final followup = await reopenedClient.builder.generate(
      generated.draftId,
      generated.mutation,
      'Rename the app',
      startFromScratch: true,
    );
    final newest = f.store.rows['generation_jobs']![followup.jobId]!;
    expect(newest['mode'], 'edit');
    await backend.WorkerEngine(f.service).generate(followup.jobId!);
    final edited = await reopenedClient.builder.get(generated.draftId);
    expect(edited.stage, 'preview ready');
    expect(provider.edits, [false, true]);
    final after = spec.AppSpec.parse(edited.candidateJson);
    expect(after.name, 'Renamed reading list');
    expect(
      after.collections.map((item) => item.id),
      before.collections.map((item) => item.id),
    );
    final version = await reopenedClient.builder.publish(
      PublishRequest(
        draftId: edited.draftId,
        candidateHash: edited.candidateHash,
        expectedCurrentVersionId: null,
        enabledRuleIds: [],
        activateExistingRecordIds: [],
        reviewHash: spec.hashJson({
          'candidateHash': edited.candidateHash,
          'enabledRuleIds': <String>[],
          'activateExistingRecordIds': <String>[],
        }),
        idempotencyKey: 'publish-creation-test',
      ),
    );
    expect(version, isNotEmpty);
    expect(
      (await reopenedClient.apps.manifest(edited.appId)).versionId,
      version,
    );
  });

  test('legacy manual failed edit with null latest job never becomes creation intent', () async {
    final provider = fixture.OfflineRejectedProvider();
    final f = fixture.Fixture(provider: provider);
    addTearDown(f.client.close);
    final workspace = await f.client.apps.createWorkspace('Offline workspace');
    final draft = await f.client.builder.begin(workspace, 'volunteer', null);
    expect(draft.creationIntent, isFalse);
    expect(draft.candidateReady, isTrue);
    final queued = await f.client.builder.generate(
      draft.draftId,
      draft.mutation,
      'Rename the app',
      startFromScratch: false,
    );
    await backend.WorkerEngine(f.service).generate(queued.jobId!);
    final failed = await f.client.builder.get(draft.draftId);
    expect(failed.stage, 'failed');
    expect(failed.creationIntent, isFalse);
    await f.client.builder.abandonFailedEdit(
      failed.draftId,
      failed.mutation,
      failed.jobId!,
    );
    final session = f.store.rows['generation_sessions']!.values.single;
    expect(session['latestJobId'], isNull);
    expect(session['generationEstablished'], isFalse);
    final reopenedClient = f.forActor('alice');
    addTearDown(reopenedClient.close);
    final reopened = await reopenedClient.builder.begin(
      workspace,
      'notes',
      draft.appId,
    );
    expect(reopened.creationIntent, isFalse);
    expect(reopened.candidateReady, isTrue);
    expect(reopened.candidateHash, draft.candidateHash);
  });

  test('failed create job retains creation intent after reopening', () async {
    final provider = fixture.OfflineRejectedProvider();
    final f = fixture.Fixture(provider: provider);
    addTearDown(f.client.close);
    final workspace = await f.client.apps.createWorkspace('Offline workspace');
    final draft = await f.client.builder.begin(
      workspace,
      'volunteer',
      null,
      creationIntent: true,
    );
    final queued = await f.client.builder.generate(
      draft.draftId,
      draft.mutation,
      'A trip checklist',
      startFromScratch: true,
    );
    await backend.WorkerEngine(f.service).generate(queued.jobId!);
    final reopenedClient = f.forActor('alice');
    addTearDown(reopenedClient.close);
    final failed = await reopenedClient.builder.begin(
      workspace,
      'notes',
      draft.appId,
    );
    expect(failed.stage, 'failed');
    expect(failed.creationIntent, isTrue);
    expect(failed.candidateReady, isFalse);
    expect(failed.candidateHash, draft.candidateHash);
    expect(provider.calls, 1);
    await expectLater(
      reopenedClient.builder.generate(
        failed.draftId,
        failed.mutation,
        'Stale edit',
        startFromScratch: false,
      ),
      throwsA(
        isA<NestError>().having(
          (error) => error.category,
          'category',
          'creation_intent_mismatch',
        ),
      ),
    );
    expect(f.store.rows['generation_jobs']!.length, 1);
    expect(
      (await reopenedClient.builder.get(failed.draftId)).creationIntent,
      isTrue,
    );
  });

  test('viewer access never exposes another actor creation intent', () async {
    final f = await workers.fixture();
    await f.service.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'creation-draft',
      'expectedRevision': 0,
      'expectedVersionId': null,
      'spec': spec.starterTemplates()['volunteer']!.toJson(),
      'creationIntent': true,
    });
    await checks.join(f.service, 'bob', 99, role: 'viewer');
    final metadata = await f.service.execute('bob', {
      'op': 'getAppAccess',
      'appId': 'app',
    });
    expect(jsonEncode(metadata), isNot(contains('creationIntent')));
    expect(jsonEncode(metadata), isNot(contains('creation-intent')));
    await expectLater(
      f.service.execute('bob', {'op': 'spec.getApp', 'appId': 'app'}),
      throwsA(
        isA<backend.ServiceException>().having(
          (error) => error.code,
          'code',
          'not_found',
        ),
      ),
    );
  });

  test(
    'legacy manual save advances revision and invalidates old creation intent',
    () async {
      final f = fixture.Fixture();
      addTearDown(f.client.close);
      final workspace = await f.client.apps.createWorkspace(
        'Offline workspace',
      );
      final draft = await f.client.builder.begin(
        workspace,
        'volunteer',
        null,
        creationIntent: true,
      );
      final row = f.store.rows['spec_drafts']!.values.single;
      expect(row['creationIntentRevision'], row['revision']);
      // An older Core updates revision without knowing about the new column.
      await f.store.update('spec_drafts', row[r'$id'] as String, {
        'revision': 2,
      });
      final reopened = await f.client.builder.get(draft.draftId);
      expect(reopened.mutation, 2);
      expect(reopened.creationIntent, isFalse);
      expect(reopened.candidateReady, isTrue);
    },
  );

  test(
    'legacy published placeholder does not revive creation intent',
    () async {
      final f = fixture.Fixture();
      addTearDown(f.client.close);
      final workspace = await f.client.apps.createWorkspace(
        'Offline workspace',
      );
      final draft = await f.client.builder.begin(
        workspace,
        'volunteer',
        null,
        creationIntent: true,
      );
      final row = f.store.rows['spec_drafts']!.values.single;
      // Old Core may publish without clearing or advancing the optional marker.
      await f.store.update('spec_drafts', row[r'$id'] as String, {
        'publishedVersionId': 'legacy-version',
      });
      final beforeHead = await f.service.execute('alice', {
        'op': 'spec.getApp',
        'appId': draft.appId,
      });
      expect(
        ((beforeHead['app'] as Map)['draft'] as Map)['creationIntent'],
        isFalse,
      );
      await f.store.create('spec_versions', 'legacy-version', {
        'workspaceId': workspace,
        'appId': draft.appId,
        'number': 1,
        'specJson': row['specJson'],
        'hash': row['candidateHash'],
      });
      await f.store.update('apps', draft.appId, {
        'specVersionId': 'legacy-version',
        'specVersionNumber': 1,
      });
      final restored = await f.service.execute('alice', {
        'op': 'spec.getApp',
        'appId': draft.appId,
      });
      final app = restored['app'] as Map;
      expect((app['version'] as Map)['id'], 'legacy-version');
      expect((app['draft'] as Map)['creationIntent'], isFalse);
    },
  );

  test('a manual save deliberately supersedes creation placeholder and keeps its definition', () async {
    final f = fixture.Fixture();
    addTearDown(f.client.close);
    final workspace = await f.client.apps.createWorkspace('Offline workspace');
    final draft = await f.client.builder.begin(
      workspace,
      'volunteer',
      null,
      creationIntent: true,
    );
    await expectLater(
      f.service.execute('alice', {
        'op': 'spec.review',
        'appId': draft.appId,
        'expectedRevision': draft.mutation,
        'enabledRuleIds': <String>[],
        'activateExistingRecordIds': <String>[],
      }),
      throwsA(
        isA<backend.ServiceException>().having(
          (e) => e.code,
          'code',
          'generation_pending',
        ),
      ),
    );
    final updated = await f.client.builder.patch(
      draft.draftId,
      draft.mutation,
      jsonEncode({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': 'My volunteer app',
      }),
    );
    expect(updated.creationIntent, isFalse);
    expect(updated.candidateReady, isTrue);
    final reopened = await f.client.builder.get(draft.draftId);
    expect(reopened.creationIntent, isFalse);
    expect(spec.AppSpec.parse(reopened.candidateJson).name, 'My volunteer app');
  });
}
