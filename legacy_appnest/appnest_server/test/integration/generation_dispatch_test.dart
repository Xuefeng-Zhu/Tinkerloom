import 'dart:async';
import 'dart:convert';

import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/automation/worker.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';
import 'package:serverpod/protocol.dart' show FutureCallEntry;
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

class _HeldProvider implements AiProvider {
  final started = Completer<void>();
  final release = Completer<void>();
  int calls = 0;

  @override
  Future<AiResult> generate(
    String request,
    AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
    String? rejectedOutput,
  }) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await release.future;
    return AiResult(
      editing ? '{"patches":[]}' : starterTemplates()['planner']!.canonical,
      'test',
      'test',
      {},
    );
  }
}

void main() {
  withServerpod('Durable generation dispatch and recovery', (
    sessions,
    endpoints,
  ) {
    late Session owner;
    late int workspace;
    late DateTime now;
    late DateTime Function() originalClock;
    late Map<String, String> originalPasswords;

    setUpAll(() async => Integrity.ensure(sessions.build()));
    setUp(() async {
      originalClock = clock;
      now = DateTime.now().toUtc();
      clock = () => now;
      owner = sessions
          .copyWith(
            authentication: AuthenticationOverride.authenticationInfo(
              'dispatch-${randomToken()}',
              {},
            ),
          )
          .build();
      originalPasswords = owner.server.passwords;
      // Only exercises enqueue configuration. No test contacts a provider.
      owner.server.passwords = {
        ...originalPasswords,
        'AI_BASE_URL': 'https://example.invalid/v1',
        'AI_MODEL': 'test-only',
        'AI_API_KEY': 'test-only',
      };
      workspace = await Apps.createWorkspace(owner, 'Dispatch tests');
    });
    tearDown(() {
      clock = originalClock;
      owner.server.passwords = originalPasswords;
    });

    Future<GenerationJob> queue(
      BuilderSnapshot draft, {
      String mode = 'create',
      int attempts = 0,
      Session? session,
    }) async {
      final user = session ?? owner;
      final row = (await AppDraft.db.findById(user, draft.draftId))!;
      final job = await GenerationJob.db.insertRow(
        user,
        GenerationJob(
          appId: draft.appId,
          draftId: draft.draftId,
          actorId: actor(user),
          mutation: row.mutation,
          status: 'queued',
          requestText: 'Synthetic request',
          mode: mode,
          promptVersion: 'test',
          attempts: attempts,
          nextAttemptAt: clock(),
          diagnostics: '',
          usageJson: '{}',
          createdAt: clock(),
          updatedAt: clock(),
        ),
      );
      row.activeJobId = job.id;
      await AppDraft.db.updateRow(user, row);
      return job;
    }

    Future<List<FutureCallEntry>> wakeups(int id) => FutureCallEntry.db.find(
      owner,
      where: (t) => t.identifier.equals('appnest-generation-$id'),
    );

    test('enqueue commits before immediate durable wakeup and exposes recovery metadata', () async {
      final initial = await Builder.begin(owner, workspace, 'planner', null);
      final accepted = await Builder.generate(
        owner,
        initial.draftId,
        initial.mutation,
        'A personal task reminder app',
      );
      final stored = (await GenerationJob.db.findById(owner, accepted.jobId!))!;
      expect(stored.status, 'queued');
      expect(accepted.candidateReady, isFalse);
      expect(accepted.latestRequest, stored.requestText);
      expect(accepted.jobAttempts, 0);
      expect(accepted.jobCreatedAt, now);
      expect(accepted.jobUpdatedAt, now);
      expect(await wakeups(stored.id!), hasLength(1));
      expect((await wakeups(stored.id!)).single.time, now);
      final recovered = await Builder.get(owner, initial.draftId);
      expect(recovered.jobId, accepted.jobId);
      expect(recovered.mutation, initial.mutation + 1);
      await expectLater(
        Builder.generate(
          owner,
          initial.draftId,
          initial.mutation,
          stored.requestText,
        ),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'recordConflict',
          ),
        ),
      );
      expect(
        await GenerationJob.db.count(
          owner,
          where: (t) => t.draftId.equals(initial.draftId),
        ),
        1,
      );
      // Simulate the commit -> scheduler crash gap, then the reconciler wakeup.
      await FutureCallEntry.db.deleteWhere(
        owner,
        where: (t) => t.identifier.equals('appnest-generation-${stored.id}'),
      );
      expect(await Worker.scheduleDueGenerations(owner), 1);
      expect(await wakeups(stored.id!), hasLength(1));
      await Worker.generate(
        owner,
        stored.id!,
        provider: FakeAiProvider(starterTemplates()['planner']!.canonical),
      );
      expect(
        (await Builder.get(owner, initial.draftId)).candidateReady,
        isTrue,
      );
    });

    test('duplicates and early retries are harmless; expired generation lease recovers', () async {
      final draft = await Builder.begin(owner, workspace, 'planner', null);
      final job = await queue(draft);
      await Worker.generate(
        owner,
        job.id!,
        provider: FakeAiProvider('not JSON'),
      );
      var stored = (await GenerationJob.db.findById(owner, job.id!))!;
      expect(stored.attempts, 1);
      expect(
        (await Builder.get(owner, draft.draftId)).failureCategory,
        'responseFormat',
      );
      await Worker.generate(
        owner,
        job.id!,
        provider: FakeAiProvider(starterTemplates()['planner']!.canonical),
      );
      expect((await GenerationJob.db.findById(owner, job.id!))!.attempts, 1);
      now = stored.nextAttemptAt;
      // Simulate a dead worker whose claim has expired.
      stored.status = 'generating';
      stored.leaseUntil = now.subtract(const Duration(seconds: 1));
      await GenerationJob.db.updateRow(owner, stored);
      await Worker.generate(
        owner,
        job.id!,
        provider: FakeAiProvider(starterTemplates()['planner']!.canonical),
      );
      stored = (await GenerationJob.db.findById(owner, job.id!))!;
      expect(stored.status, 'preview ready');
      expect(stored.attempts, 2);
      expect(stored.leaseGeneration, 2);
      await Worker.generate(
        owner,
        job.id!,
        provider: FakeAiProvider('not JSON'),
      );
      expect(
        (await GenerationJob.db.findById(owner, job.id!))!.status,
        'preview ready',
      );
      expect((await GenerationJob.db.findById(owner, job.id!))!.attempts, 2);
    });

    test(
      'concurrent enqueue preserves the per-user active-job quota',
      () async {
        final first = await Builder.begin(owner, workspace, 'planner', null);
        final second = await Builder.begin(owner, workspace, 'planner', null);
        Future<Object> enqueue(BuilderSnapshot draft) async {
          try {
            return await Builder.generate(
              owner,
              draft.draftId,
              draft.mutation,
              'A personal task reminder app',
            );
          } on NestError catch (error) {
            return error;
          }
        }

        final results = await Future.wait([enqueue(first), enqueue(second)]);
        final accepted = results.whereType<BuilderSnapshot>().toList();
        final rejected = results.whereType<NestError>().toList();
        expect(accepted, hasLength(1));
        expect(rejected, hasLength(1));
        expect(rejected.single.category, 'quotaExceeded');
        expect(
          await GenerationJob.db.count(
            owner,
            where: (t) => t.actorId.equals(actor(owner)),
          ),
          1,
        );
        final rejectedDraft = accepted.single.draftId == first.draftId
            ? second
            : first;
        final unchanged = await Builder.get(owner, rejectedDraft.draftId);
        expect(unchanged.jobId, isNull);
        expect(unchanged.mutation, rejectedDraft.mutation);

        final other = sessions
            .copyWith(
              authentication: AuthenticationOverride.authenticationInfo(
                'quota-other-${randomToken()}',
                {},
              ),
            )
            .build();
        final otherWorkspace = await Apps.createWorkspace(other, 'Other quota');
        final otherDraft = await Builder.begin(
          other,
          otherWorkspace,
          'planner',
          null,
        );
        final otherAccepted = await Builder.generate(
          other,
          otherDraft.draftId,
          otherDraft.mutation,
          'A personal task reminder app',
        );
        expect(otherAccepted.stage, 'queued');
        expect(await wakeups(otherAccepted.jobId!), hasLength(1));
        await Future.wait([
          Worker.generate(
            owner,
            accepted.single.jobId!,
            provider: FakeAiProvider(starterTemplates()['planner']!.canonical),
          ),
          Worker.generate(
            other,
            otherAccepted.jobId!,
            provider: FakeAiProvider(starterTemplates()['planner']!.canonical),
          ),
        ]);
        // Once the first job completes, this user's other draft can enqueue.
        final next = await Builder.generate(
          owner,
          rejectedDraft.draftId,
          rejectedDraft.mutation,
          'A personal task reminder app',
        );
        await Worker.generate(
          owner,
          next.jobId!,
          provider: FakeAiProvider(starterTemplates()['planner']!.canonical),
        );
        expect(
          (await Builder.get(owner, rejectedDraft.draftId)).candidateReady,
          isTrue,
        );
      },
    );

    test('reconciliation wakes every due job without waking active leases or future retries', () async {
      final jobs = <GenerationJob>[];
      for (var i = 0; i < 5; i++) {
        final draft = await Builder.begin(owner, workspace, 'planner', null);
        jobs.add(await queue(draft));
      }
      jobs[1]
        ..status = 'generating'
        ..leaseUntil = now.subtract(const Duration(seconds: 1));
      jobs[2]
        ..status = 'validating'
        ..leaseUntil = now;
      jobs[3]
        ..status = 'generating'
        ..leaseUntil = now.add(const Duration(seconds: 30));
      jobs[4].nextAttemptAt = now.add(const Duration(seconds: 30));
      for (final job in jobs) {
        await GenerationJob.db.updateRow(owner, job);
      }
      try {
        expect(await Worker.scheduleDueGenerations(owner), 3);
        for (final job in jobs.take(3)) {
          final calls = await wakeups(job.id!);
          expect(calls, hasLength(1));
          expect(calls.single.time, now);
          expect(
            (await GenerationJob.db.findById(owner, job.id!))!.attempts,
            0,
          );
        }
        for (final job in jobs.skip(3)) {
          expect(await wakeups(job.id!), isEmpty);
        }
      } finally {
        // These committed synthetic rows must not influence later reconciliation.
        for (final job in jobs) {
          job.status = 'failed';
          await GenerationJob.db.updateRow(owner, job);
        }
      }
    });

    test(
      'an expired claim can recover without accepting the old worker result',
      () async {
        final draft = await Builder.begin(owner, workspace, 'planner', null);
        final job = await queue(draft);
        final expiredProvider = _HeldProvider();
        final replacementProvider = _HeldProvider();
        final expiredRun = Worker.generate(
          owner,
          job.id!,
          provider: expiredProvider,
        );
        Future<void>? replacementRun;
        try {
          await expiredProvider.started.future.timeout(
            const Duration(seconds: 5),
          );
          final firstClaim = (await GenerationJob.db.findById(owner, job.id!))!;
          now = firstClaim.leaseUntil!.add(const Duration(seconds: 1));
          replacementRun = Worker.generate(
            owner,
            job.id!,
            provider: replacementProvider,
          );
          await replacementProvider.started.future.timeout(
            const Duration(seconds: 5),
          );
          expiredProvider.release.complete();
          await expiredRun.timeout(const Duration(seconds: 5));
          final replacementClaim = (await GenerationJob.db.findById(
            owner,
            job.id!,
          ))!;
          expect(replacementClaim.status, 'generating');
          expect(
            replacementClaim.leaseGeneration,
            firstClaim.leaseGeneration + 1,
          );
          expect(replacementClaim.attempts, 2);
          expect(replacementProvider.release.isCompleted, isFalse);
          expect(
            (await Builder.get(owner, draft.draftId)).candidateReady,
            isFalse,
          );
        } finally {
          if (!expiredProvider.release.isCompleted) {
            expiredProvider.release.complete();
          }
          if (!replacementProvider.release.isCompleted) {
            replacementProvider.release.complete();
          }
          await Future.wait([
            expiredRun,
            ?replacementRun,
          ]).timeout(const Duration(seconds: 5));
        }
        expect(
          (await GenerationJob.db.findById(owner, job.id!))!.status,
          'preview ready',
        );
        expect(expiredProvider.calls, 1);
        expect(replacementProvider.calls, 1);
      },
    );

    test('failed edit can keep prior candidate, stale discard and initial create are rejected', () async {
      final draft = await Builder.begin(owner, workspace, 'planner', null);
      final failedCreate = await queue(
        draft,
        attempts: Limits.generationAttempts - 1,
      );
      await Worker.generate(
        owner,
        failedCreate.id!,
        provider: FakeAiProvider('not JSON'),
      );
      expect((await Builder.get(owner, draft.draftId)).candidateReady, isFalse);
      await expectLater(
        Builder.abandonFailedEdit(
          owner,
          draft.draftId,
          draft.mutation,
          failedCreate.id!,
        ),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'invalidInput',
          ),
        ),
      );
      final edit = await queue(
        draft,
        mode: 'edit',
        attempts: Limits.generationAttempts - 1,
      );
      await Worker.generate(
        owner,
        edit.id!,
        provider: FakeAiProvider('not JSON'),
      );
      final failed = await Builder.get(owner, draft.draftId);
      expect(failed.candidateReady, isTrue);
      await expectLater(
        Builder.abandonFailedEdit(
          owner,
          draft.draftId,
          draft.mutation + 1,
          edit.id!,
        ),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'recordConflict',
          ),
        ),
      );
      final kept = await Builder.abandonFailedEdit(
        owner,
        draft.draftId,
        draft.mutation,
        edit.id!,
      );
      expect(kept.stage, 'preview ready');
      expect(kept.jobId, isNull);
      expect(kept.candidateReady, isTrue);
      expect(kept.candidateHash, draft.candidateHash);
      expect(kept.candidateJson, draft.candidateJson);
      expect(kept.mutation, draft.mutation + 1);
      await expectLater(
        Builder.abandonFailedEdit(
          owner,
          draft.draftId,
          draft.mutation,
          edit.id!,
        ),
        throwsA(isA<NestError>()),
      );
    });

    test('an AI rename preserves an existing append-only app', () async {
      final json = starterTemplates()['reading']!.toJson();
      final removed = (json['actions'] as List)
          .where((action) => action['capability'] == 'records.patch.v1')
          .map((action) => action['id'])
          .toSet();
      (json['actions'] as List).removeWhere(
        (action) => removed.contains(action['id']),
      );
      for (final view in json['views'] as List) {
        (view['actionIds'] as List).removeWhere(removed.contains);
      }
      final appId = await Apps.create(
        owner,
        workspace,
        AppSpec.parse(jsonEncode(json)),
      );
      final draft = await Builder.begin(owner, workspace, 'reading', appId);
      final job = await queue(draft, mode: 'edit');
      await Worker.generate(
        owner,
        job.id!,
        provider: FakeAiProvider(
          jsonEncode({
            'patches': [
              {
                'type': 'RenameLabel',
                'targetId': 'app',
                'label': 'Still my reading log',
              },
            ],
          }),
        ),
      );
      final completed = await Builder.get(owner, draft.draftId);
      expect(
        completed.stage,
        'preview ready',
        reason: completed.diagnostics.join('; '),
      );
      expect(
        AppSpec.parse(completed.candidateJson).name,
        'Still my reading log',
      );
    });

    test(
      'different users generate concurrently while duplicates, reminders, and edits stay safe',
      () async {
        final first = await Builder.begin(owner, workspace, 'planner', null);
        final firstJob = await queue(first);
        final other = sessions
            .copyWith(
              authentication: AuthenticationOverride.authenticationInfo(
                'other-builder-${randomToken()}',
                {},
              ),
            )
            .build();
        final otherWorkspace = await Apps.createWorkspace(
          other,
          'Another user',
        );
        final second = await Builder.begin(
          other,
          otherWorkspace,
          'planner',
          null,
        );
        final secondJob = await queue(second, session: other);
        final firstProvider = _HeldProvider();
        final secondProvider = _HeldProvider();
        final running = [
          Worker.generate(owner, firstJob.id!, provider: firstProvider),
          Worker.generate(other, secondJob.id!, provider: secondProvider),
        ];
        try {
          await Future.wait([
            firstProvider.started.future,
            secondProvider.started.future,
          ]).timeout(const Duration(seconds: 5));
          // Both provider calls remain held. A serialized implementation cannot
          // reach this point, even if it would eventually finish both jobs.
          for (final id in [firstJob.id!, secondJob.id!]) {
            final stored = (await GenerationJob.db.findById(owner, id))!;
            expect(stored.status, 'generating');
            expect(stored.attempts, 1);
            expect(stored.leaseUntil!.isAfter(now), isTrue);
          }
          await Future.wait([
            Worker.generate(owner, firstJob.id!, provider: firstProvider),
            Worker.generate(other, secondJob.id!, provider: secondProvider),
          ]).timeout(const Duration(seconds: 3));
          expect(firstProvider.calls, 1);
          expect(secondProvider.calls, 1);

          final reminderApp = await Apps.instantiate(
            owner,
            workspace,
            'planner',
          );
          final version = (await Apps.manifest(owner, reminderApp)).versionId!;
          final approval = await Builder.begin(
            owner,
            workspace,
            'planner',
            reminderApp,
          );
          final published = await Builder.publish(
            owner,
            PublishRequest(
              draftId: approval.draftId,
              candidateHash: approval.candidateHash,
              expectedCurrentVersionId: version,
              enabledRuleIds: ['taskReminder'],
              activateExistingRecordIds: [],
              reviewHash: hashJson({
                'candidateHash': approval.candidateHash,
                'enabledRuleIds': ['taskReminder'],
                'activateExistingRecordIds': [],
              }),
              idempotencyKey: 'approve-reminder',
            ),
          );
          await Commands.execute(
            owner,
            ActionRequest(
              appId: reminderApp,
              actionId: 'addTask',
              expectedDefinitionVersionId: published,
              input: {
                'data': {
                  'title': 'Due while AI waits',
                  'status': 'Open',
                  'priority': 'Normal',
                  'reminderAt': now
                      .add(const Duration(seconds: 1))
                      .toIso8601String(),
                },
              },
              idempotencyKey: 'reminder-record',
            ),
          );
          now = now.add(const Duration(seconds: 2));
          await Worker.drain(owner).timeout(const Duration(seconds: 5));
          expect(
            await Notification.db.count(
              owner,
              where: (t) => t.appId.equals(reminderApp),
            ),
            1,
          );
          expect(firstProvider.release.isCompleted, isFalse);
          expect(secondProvider.release.isCompleted, isFalse);
          expect(
            (await GenerationJob.db.findById(owner, secondJob.id!))!.status,
            'generating',
          );

          // A manual edit during the provider call must fence off the late result.
          await Builder.patch(
            owner,
            first.draftId,
            first.mutation,
            jsonEncode({
              'type': 'RenameLabel',
              'targetId': 'app',
              'label': 'Kept manual title',
            }),
          );
        } finally {
          if (!firstProvider.release.isCompleted) {
            firstProvider.release.complete();
          }
          if (!secondProvider.release.isCompleted) {
            secondProvider.release.complete();
          }
          await Future.wait(running).timeout(const Duration(seconds: 5));
        }
        expect(
          (await GenerationJob.db.findById(owner, firstJob.id!))!.status,
          'stale',
        );
        expect(
          AppSpec.parse((await Builder.get(owner, first.draftId)).candidateJson)
              .name,
          'Kept manual title',
        );
        expect(
          (await GenerationJob.db.findById(owner, secondJob.id!))!.status,
          'preview ready',
        );
      },
    );
  }, rollbackDatabase: RollbackDatabase.disabled);
}
