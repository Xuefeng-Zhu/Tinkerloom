import 'dart:async';
import 'dart:convert';

import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

class _ObservedProvider implements AiProvider {
  final String output;
  final Future<void>? waitFor;
  final started = Completer<void>();
  final List<({String request, AppSpec current, bool editing})> calls = [];

  _ObservedProvider(this.output, {this.waitFor});

  @override
  Future<AiResult> generate(
    String request,
    AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
    String? rejectedOutput,
  }) async {
    calls.add((request: request, current: current, editing: editing));
    if (!started.isCompleted) started.complete();
    await waitFor;
    return AiResult(output, 'context-test-only', 'deterministic', {});
  }
}

void main() {
  withServerpod('Unpublished AI generation context', (sessions, endpoints) {
    late Session owner;
    late int workspace;
    late Map<String, String> originalPasswords;

    setUp(() async {
      owner = sessions
          .copyWith(
            authentication: AuthenticationOverride.authenticationInfo(
              'followup-${randomToken()}',
              {},
            ),
          )
          .build();
      originalPasswords = owner.server.passwords;
      // Enqueue uses synthetic configuration; all executions inject a provider
      // below and never contact the configured or any external AI service.
      owner.server.passwords = {
        ...originalPasswords,
        'AI_BASE_URL': 'https://example.invalid/v1',
        'AI_MODEL': 'test-only',
        'AI_API_KEY': 'test-only',
      };
      workspace = await Apps.createWorkspace(owner, 'Follow-up tests');
    });
    tearDown(() => owner.server.passwords = originalPasswords);

    Future<BuilderSnapshot> createdDraft() async {
      final draft = await Builder.begin(owner, workspace, 'volunteer', null);
      final queued = await Builder.generate(
        owner,
        draft.draftId,
        draft.mutation,
        'Create a personal planner.',
      );
      final provider = _ObservedProvider(
        starterTemplates()['planner']!.canonical,
      );
      await Worker.generate(owner, queued.jobId!, provider: provider);
      expect(provider.calls.single.editing, isFalse);
      final ready = await Builder.get(owner, draft.draftId);
      expect(
        ready.stage,
        'preview ready',
        reason: ready.diagnostics.join('; '),
      );
      return ready;
    }

    test(
      'success establishes edit context across later failures and manual edits',
      () async {
        final owner = sessions
            .copyWith(
              authentication: AuthenticationOverride.authenticationInfo(
                'generation-${randomToken()}',
                {},
              ),
            )
            .build();
        final workspace = await Apps.createWorkspace(owner, 'Generation tests');
        var draft = await Builder.begin(owner, workspace, 'volunteer', null);
        Future<String> mode({bool startFromScratch = true}) =>
            owner.db.transaction(
              (tx) async => Builder.generationMode(
                owner,
                (await AppDraft.db.findById(
                  owner,
                  draft.draftId,
                  transaction: tx,
                ))!,
                tx: tx,
                startFromScratch: startFromScratch,
              ),
            );
        Future<void> attempt(
          String output, {
          bool startFromScratch = true,
        }) async {
          final job = await GenerationJob.db.insertRow(
            owner,
            GenerationJob(
              appId: draft.appId,
              draftId: draft.draftId,
              actorId: actor(owner),
              mutation: draft.mutation,
              status: 'queued',
              requestText: 'Synthetic generation context test',
              mode: await mode(startFromScratch: startFromScratch),
              promptVersion: 'test',
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
          await Worker.generate(
            owner,
            job.id!,
            provider: FakeAiProvider(output),
          );
          draft = await Builder.get(owner, draft.draftId);
        }

        expect(await mode(), 'create');
        await attempt('invalid JSON');
        expect(draft.stage, 'failed');
        expect(await mode(), 'create');
        final planner = starterTemplates()['planner']!;
        final styledPlanner = planner.patch({
          'type': 'SetAppearance',
          'appearance': {'style': 'clean'},
        }, () => throw StateError('No new IDs'));
        await attempt('```json\n${planner.canonical}\n```');
        expect(
          draft.stage,
          'preview ready',
          reason: draft.diagnostics.join('; '),
        );
        expect(draft.candidateHash, styledPlanner.hash);
        expect(await mode(), 'edit');
        await attempt('invalid JSON');
        expect(draft.stage, 'failed');
        expect(draft.candidateHash, styledPlanner.hash);
        expect(await mode(), 'edit');
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
        expect(draft.jobId, isNull);
        expect(await mode(), 'edit');
        await attempt(
          jsonEncode({
            'patches': [
              {
                'type': 'RenameLabel',
                'targetId': 'todayPage',
                'label': 'Focus today',
              },
            ],
          }),
        );
        expect(
          draft.stage,
          'preview ready',
          reason: draft.diagnostics.join('; '),
        );
        expect(
          AppSpec.parse(draft.candidateJson).page('todayPage').title,
          'Focus today',
        );

        // A successful generation in another draft cannot turn this placeholder
        // into an edit request, even when the owner is the same.
        draft = await Builder.begin(owner, workspace, 'volunteer', null);
        expect(await mode(), 'create');
        expect(await mode(startFromScratch: false), 'edit');
        await attempt('invalid JSON', startFromScratch: false);
        expect(draft.stage, 'failed');
        expect(await mode(startFromScratch: false), 'edit');
        final selectedTemplate = AppSpec.parse(draft.candidateJson);
        await attempt(
          jsonEncode({
            'patches': [
              {
                'type': 'RenameLabel',
                'targetId': 'app',
                'label': 'Neighborhood Helpers',
              },
            ],
          }),
          startFromScratch: false,
        );
        expect(
          draft.stage,
          'preview ready',
          reason: draft.diagnostics.join('; '),
        );
        final editedTemplate = AppSpec.parse(draft.candidateJson);
        expect(editedTemplate.name, 'Neighborhood Helpers');
        expect(
          editedTemplate.collections.map((c) => c.toJson()).toList(),
          selectedTemplate.collections.map((c) => c.toJson()).toList(),
        );
        expect(
          editedTemplate.views.map((v) => v.toJson()).toList(),
          selectedTemplate.views.map((v) => v.toJson()).toList(),
        );
        expect(await mode(), 'edit');
      },
    );

    test('normal enqueue follows up on the same unpublished candidate and recovers after failure', () async {
      final created = await createdDraft();
      final baseline = AppSpec.parse(created.candidateJson);
      final originalAppCount = await MiniApp.db.count(owner);
      final originalVersionCount = await AppVersion.db.count(owner);
      final originalRecordCount = await EntityRecord.db.count(owner);
      const rename = {
        'type': 'RenameLabel',
        'targetId': 'todayPage',
        'label': 'Focus today',
      };
      const request = 'Rename the Today page to Focus today.';
      final queued = await Builder.generate(
        owner,
        created.draftId,
        created.mutation,
        request,
      );
      final job = (await GenerationJob.db.findById(owner, queued.jobId!))!;
      expect(job.mode, 'edit');
      expect(queued.candidateReady, isTrue);
      expect(queued.candidateJson, created.candidateJson);
      expect(queued.latestRequest, request);
      final provider = _ObservedProvider(
        jsonEncode({
          'patches': [rename],
        }),
      );
      await Worker.generate(owner, job.id!, provider: provider);
      expect(provider.calls.single.request, request);
      expect(provider.calls.single.editing, isTrue);
      expect(provider.calls.single.current.canonical, created.candidateJson);
      var ready = await Builder.get(owner, created.draftId);
      final expected = baseline.patch(
        rename,
        () => throw StateError('No new IDs'),
      );
      expect(
        ready.stage,
        'preview ready',
        reason: ready.diagnostics.join('; '),
      );
      expect(ready.appId, created.appId);
      expect(ready.draftId, created.draftId);
      expect(ready.baseVersionId, isNull);
      expect(ready.publishedVersionId, isNull);
      // Full canonical equality proves that IDs, bindings, appearance and every
      // other unrequested definition property survive the follow-up.
      expect(ready.candidateJson, expected.canonical);
      expect(ready.candidateHash, expected.hash);

      final rejected = await Builder.generate(
        owner,
        ready.draftId,
        ready.mutation,
        'Add unsupported background phone alerts.',
      );
      await Worker.generate(
        owner,
        rejected.jobId!,
        provider: _ObservedProvider(
          '{"unsupported":"Background alerts are unavailable."}',
        ),
      );
      final failed = await Builder.get(owner, created.draftId);
      expect(failed.stage, 'failed');
      expect(failed.candidateReady, isTrue);
      expect(failed.candidateJson, expected.canonical);
      ready = await Builder.abandonFailedEdit(
        owner,
        failed.draftId,
        failed.mutation,
        failed.jobId!,
      );
      expect(ready.jobId, isNull);
      expect(ready.candidateJson, expected.canonical);
      final resumed = await Builder.begin(
        owner,
        workspace,
        'volunteer',
        created.appId,
      );
      expect(resumed.draftId, created.draftId);
      expect(resumed.candidateJson, expected.canonical);

      final next = await Builder.generate(
        owner,
        resumed.draftId,
        resumed.mutation,
        'Rename the app to My focus planner.',
      );
      final nextProvider = _ObservedProvider(
        jsonEncode({
          'patches': [
            {
              'type': 'RenameLabel',
              'targetId': 'app',
              'label': 'My focus planner',
            },
          ],
        }),
      );
      await Worker.generate(owner, next.jobId!, provider: nextProvider);
      expect(nextProvider.calls.single.editing, isTrue);
      expect(nextProvider.calls.single.current.canonical, expected.canonical);
      final finalCandidate = expected.patch({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': 'My focus planner',
      }, () => throw StateError('No new IDs'));
      expect(
        (await Builder.get(owner, created.draftId)).candidateJson,
        finalCandidate.canonical,
      );
      expect(await MiniApp.db.count(owner), originalAppCount);
      expect(await AppVersion.db.count(owner), originalVersionCount);
      expect(await EntityRecord.db.count(owner), originalRecordCount);
    });

    test('polling cannot combine an old candidate with a completed follow-up job', () async {
      final created = await createdDraft();
      final queued = await Builder.generate(
        owner,
        created.draftId,
        created.mutation,
        'Rename the app to Finished follow-up.',
      );
      final job = (await GenerationJob.db.findById(owner, queued.jobId!))!
        ..status = 'validating';
      await GenerationJob.db.updateRow(owner, job);
      final expected = AppSpec.parse(created.candidateJson).patch({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': 'Finished follow-up',
      }, () => throw StateError('No new IDs'));
      final locked = Completer<void>();
      final release = Completer<void>();
      final save = owner.db.transaction((tx) async {
        await MiniApp.db.findById(
          owner,
          created.appId,
          transaction: tx,
          lockMode: LockMode.forUpdate,
        );
        // Hold the job read after the candidate read in the old implementation.
        // This reproduces a worker commit between the two snapshot queries.
        await owner.db.unsafeExecute(
          'LOCK TABLE nest_generation IN ACCESS EXCLUSIVE MODE',
          transaction: tx,
        );
        final draft =
            (await AppDraft.db.findById(
                owner,
                created.draftId,
                transaction: tx,
              ))!
              ..candidateJson = expected.canonical
              ..candidateHash = expected.hash;
        await AppDraft.db.updateRow(owner, draft, transaction: tx);
        job.status = 'preview ready';
        await GenerationJob.db.updateRow(owner, job, transaction: tx);
        locked.complete();
        await release.future;
      });
      Future<BuilderSnapshot>? polling;
      try {
        await locked.future.timeout(const Duration(seconds: 5));
        polling = Builder.get(owner, created.draftId);
        final wait = Stopwatch()..start();
        var blocked = false;
        while (!blocked && wait.elapsed < const Duration(seconds: 5)) {
          final rows = await owner.db.unsafeQuery(
            "SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND (query LIKE '%nest_generation%' OR query LIKE '%nest_app%')",
          );
          blocked = rows.isNotEmpty;
          if (!blocked) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
        expect(
          blocked,
          isTrue,
          reason: 'The polling read must overlap the save transaction.',
        );
        release.complete();
        await save.timeout(const Duration(seconds: 5));
        final snapshot = await polling.timeout(const Duration(seconds: 5));
        expect(snapshot.stage, 'preview ready');
        expect(snapshot.candidateJson, expected.canonical);
        expect(snapshot.candidateHash, expected.hash);
      } finally {
        if (!release.isCompleted) release.complete();
        await save;
        await polling;
      }
    });

    test('simultaneous follow-ups accept one request and a late result preserves newer manual edits', () async {
      final created = await createdDraft();
      Future<Object> enqueue(String request) async {
        try {
          return await Builder.generate(
            owner,
            created.draftId,
            created.mutation,
            request,
          );
        } on NestError catch (error) {
          return error;
        }
      }

      final outcomes = await Future.wait([
        enqueue('Rename the app to First request.'),
        enqueue('Rename the app to Second request.'),
      ]);
      final accepted = outcomes.whereType<BuilderSnapshot>().single;
      expect(outcomes.whereType<NestError>().single.category, 'recordConflict');
      expect(
        (await GenerationJob.db.findById(owner, accepted.jobId!))!.mode,
        'edit',
      );
      expect(
        await GenerationJob.db.count(
          owner,
          where: (t) => t.draftId.equals(created.draftId),
        ),
        2,
      );
      final release = Completer<void>();
      final provider = _ObservedProvider(
        jsonEncode({
          'patches': [
            {
              'type': 'RenameLabel',
              'targetId': 'app',
              'label': 'Late AI result',
            },
          ],
        }),
        waitFor: release.future,
      );
      final running = Worker.generate(
        owner,
        accepted.jobId!,
        provider: provider,
      );
      await provider.started.future;
      late BuilderSnapshot manuallyEdited;
      try {
        manuallyEdited = await Builder.patch(
          owner,
          created.draftId,
          accepted.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'app',
            'label': 'My manual name',
          }),
        );
      } finally {
        release.complete();
        await running;
      }
      final stored = await Builder.get(owner, created.draftId);
      expect(stored.candidateJson, manuallyEdited.candidateJson);
      expect(stored.candidateHash, manuallyEdited.candidateHash);
      expect(stored.jobId, isNull);
      expect(
        (await GenerationJob.db.findById(owner, accepted.jobId!))!.status,
        'stale',
      );
      expect(provider.calls, hasLength(1));
    });
  }, rollbackDatabase: RollbackDatabase.disabled);
}
