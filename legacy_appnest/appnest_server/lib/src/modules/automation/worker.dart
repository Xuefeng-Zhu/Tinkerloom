import 'dart:convert';
import 'dart:math';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';

import '../../generated/protocol.dart';
import '../../generated/future_calls.dart';
import '../runtime/access.dart';
import '../builder/provider.dart';
import '../builder/creation_compiler.dart';
import '../builder/generation_quality.dart';
import '../builder/generation_requirements.dart';
import '../builder/repair_bindings.dart';
import '../media/media.dart';

class _ExpiredGenerationLease implements Exception {
  const _ExpiredGenerationLease();
}

class Worker {
  static bool remindersEnabled(Session s) =>
      s.serverpod.config.futureCallExecutionEnabled;

  static void requireRemindersEnabled(Session s) {
    if (!remindersEnabled(s)) {
      fail(
        'unsupportedCapability',
        'Reminders are unavailable on this server because background jobs are disabled. '
            'Publish without enabling reminders.',
      );
    }
  }

  /// Delivery conditions deliberately do not participate in occurrence identity:
  /// completing/reopening or editing unrelated fields cannot resend a reminder.
  static bool conditionMatches(
    AutomationSpec definition,
    Map<String, dynamic> data,
  ) =>
      definition.condition == null ||
      data[definition.condition!.fieldId] == definition.condition!.value;

  static String scheduleSignature(
    Automation rule,
    String? date,
    DateTime? due,
  ) => hashJson({
    'ruleVersion': rule.ruleVersion,
    'timestamp': date,
    'due': due?.toIso8601String(),
  });

  static String enrollmentKind(Automation rule) =>
      'enrollRule:${rule.id}:${rule.ruleVersion}';

  /// Enrollment is approval evidence, independent of whether a reminder time
  /// has been selected or its outbox event has already been processed.
  static Future<bool> isEnrolled(
    Session s,
    MiniApp app,
    Automation rule,
    EntityRecord record,
    Transaction tx,
  ) async {
    if (!record.createdAt.isBefore(rule.activatedAt)) return true;
    if (await AutomationRun.db.findFirstRow(
          s,
          where: (t) =>
              t.automationId.equals(rule.id!) &
              t.recordId.equals(record.id!) &
              t.ruleVersion.equals(rule.ruleVersion),
          transaction: tx,
        ) !=
        null) {
      return true;
    }
    return await OutboxEvent.db.findFirstRow(
          s,
          where: (t) =>
              t.appId.equals(app.id!) &
              t.recordId.equals(record.id!) &
              (t.kind.equals(enrollmentKind(rule)) |
                  // Preserve already queued pre-generation-stamp activation events.
                  // Their old current-version restriction cannot enroll a later rule.
                  t.kind.equals('activateExisting:${app.activeVersionId}')),
          transaction: tx,
        ) !=
        null;
  }

  static Future<bool> hasAccess(
    Session s,
    MiniApp app,
    String id,
    Transaction tx, {
    bool builder = false,
  }) async {
    if (await WorkspaceMember.db.findFirstRow(
          s,
          where: (t) =>
              t.workspaceId.equals(app.workspaceId) & t.actorId.equals(id),
          transaction: tx,
        ) ==
        null) {
      return false;
    }
    if (app.ownerId == id) return true;
    final grant = await MiniAppGrant.db.findFirstRow(
      s,
      where: (t) =>
          t.appId.equals(app.id!) &
          t.actorId.equals(id) &
          t.revoked.equals(false),
      transaction: tx,
    );
    return grant != null && (!builder || grant.role == 'builder');
  }

  static Future<void> drain(Session s) async {
    await Media.cleanup(s);
    final events = await OutboxEvent.db.find(
      s,
      where: (t) =>
          (t.planned.equals(false) | t.invalidated.equals(false)) &
          (t.nextAttemptAt <= clock()),
      orderBy: (t) => t.id,
      limit: Limits.automationBatch,
    );
    for (final e in events) {
      try {
        await plan(s, e.id!);
        // Stream clients also poll the committed control revision. This independent stage
        // never prevents reminder planning, and reminder failures never lose invalidation.
        e.invalidated = true;
        await s.db.unsafeExecute(
          'UPDATE nest_outbox SET invalidated=true WHERE id=@id',
          parameters: QueryParameters.named({'id': e.id}),
        );
      } catch (_) {
        e.attempts++;
        e.nextAttemptAt = clock().add(
          Duration(seconds: min(300, 1 << min(e.attempts, 8))),
        );
        await s.db.unsafeExecute(
          'UPDATE nest_outbox SET attempts=@attempts,"nextAttemptAt"=@next WHERE id=@id',
          parameters: QueryParameters.named({
            'attempts': e.attempts,
            'next': e.nextAttemptAt,
            'id': e.id,
          }),
        );
        s.log('outbox_retry event_id=${e.id} attempt=${e.attempts}');
      }
    }
    final generationsScheduled = await scheduleDueGenerations(s);
    final runs = remindersEnabled(s)
        ? await AutomationRun.db.find(
            s,
            where: (t) =>
                t.status.equals('pending') &
                (t.nextAttemptAt <= clock().add(const Duration(minutes: 1))),
            orderBy: (t) => t.id,
            limit: Limits.automationBatch,
          )
        : <AutomationRun>[];
    for (final run in runs) {
      final eligibleAt = run.nextAttemptAt.isAfter(run.dueAt)
          ? run.nextAttemptAt
          : run.dueAt;
      if (!eligibleAt.isAfter(clock())) {
        try {
          await execute(s, run.id!);
        } catch (_) {
          // execute persists backoff for every caller after rollback. A stale
          // reconciler snapshot must not advance the retry budget a second time.
        }
      } else {
        await s.serverpod.futureCalls
            .callAtTime(eligibleAt, identifier: 'run-${run.id}')
            .nestWorker
            .execute(run.id!);
      }
    }
    if (events.isNotEmpty || generationsScheduled > 0 || runs.isNotEmpty) {
      s.log(
        'reconcile outbox_batch=${events.length} generations_scheduled=$generationsScheduled run_batch=${runs.length}',
      );
    }
  }

  static Future<void> plan(Session s, int eventId) => s.db.transaction((
    tx,
  ) async {
    var e = await OutboxEvent.db.findById(s, eventId, transaction: tx);
    if (e == null || e.planned) return;
    final app = await MiniApp.db.findFirstRow(
      s,
      where: (t) => t.id.equals(e!.appId),
      transaction: tx,
      lockMode: LockMode.forUpdate,
    );
    if (app == null) return;
    e = await OutboxEvent.db.findById(s, eventId, transaction: tx);
    if (e == null || e.planned) return;
    if (remindersEnabled(s) && !app.archived && e.recordId != null) {
      final record = await EntityRecord.db.findFirstRow(
        s,
        where: (t) =>
            t.id.equals(e!.recordId!) &
            t.appId.equals(app.id!) &
            t.deleted.equals(false),
        transaction: tx,
      );
      final rules = await Automation.db.find(
        s,
        where: (t) => t.appId.equals(app.id!) & t.enabled.equals(true),
        transaction: tx,
      );
      if (record != null) {
        for (final rule in rules) {
          final definition = AutomationSpec.fromJson(
            payload(jsonDecode(rule.ruleJson)),
          );
          if (definition.collectionId != record.collectionId) continue;
          final date = payload(record.data)[definition.fieldId];
          if (date == null) continue;
          if (!await isEnrolled(s, app, rule, record, tx)) continue;
          final due = DateTime.parse(
            date as String,
          ).subtract(Duration(seconds: definition.offsetSeconds));
          final signature = scheduleSignature(rule, date, due);
          final occurrence = hashJson({
            'app': app.id,
            'rule': rule.id,
            'record': record.id,
            'signature': signature,
          });
          if (await AutomationRun.db.findFirstRow(
                s,
                where: (t) => t.occurrenceKey.equals(occurrence),
                transaction: tx,
              ) ==
              null) {
            await AutomationRun.db.insertRow(
              s,
              AutomationRun(
                appId: app.id!,
                automationId: rule.id!,
                ruleVersion: rule.ruleVersion,
                recordId: record.id!,
                occurrenceKey: occurrence,
                scheduleSignature: signature,
                dueAt: due,
                nextAttemptAt: due,
                status: 'pending',
                createdAt: clock(),
              ),
              transaction: tx,
            );
          }
        }
      }
    }
    e.planned = true;
    await OutboxEvent.db.updateRow(s, e, transaction: tx);
  });
  static bool _runEligible(AutomationRun run) =>
      run.status == 'pending' &&
      !run.dueAt.isAfter(clock()) &&
      !run.nextAttemptAt.isAfter(clock());

  static Future<void> execute(Session s, int runId) async {
    int? claimedGeneration;
    try {
      await s.db.transaction((tx) async {
        if (!remindersEnabled(s)) return;
        var run = await AutomationRun.db.findById(s, runId, transaction: tx);
        if (run == null || !_runEligible(run)) {
          return;
        }
        final app = await MiniApp.db.findFirstRow(
          s,
          where: (t) => t.id.equals(run!.appId),
          transaction: tx,
          lockMode: LockMode.forUpdate,
        );
        if (app == null) return;
        run = await AutomationRun.db.findById(s, runId, transaction: tx);
        if (run == null || !_runEligible(run)) return;
        claimedGeneration = run.leaseGeneration;
        run.leaseGeneration++;
        run.attempts++;
        run.leaseUntil = clock().add(const Duration(seconds: 30));
        final rule = await Automation.db.findById(
              s,
              run.automationId,
              transaction: tx,
            ),
            record = await EntityRecord.db.findById(
              s,
              run.recordId,
              transaction: tx,
            );
        var suppress =
            app.archived ||
            rule == null ||
            !rule.enabled ||
            rule.appId != app.id ||
            record == null ||
            record.deleted ||
            record.appId != app.id;
        final recipients = <String>{};
        if (!suppress) {
          final definition = AutomationSpec.fromJson(
                payload(jsonDecode(rule.ruleJson)),
              ),
              date = payload(record.data)[definition.fieldId];
          final due = date == null
              ? null
              : DateTime.parse(
                  date as String,
                ).subtract(Duration(seconds: definition.offsetSeconds));
          suppress =
              scheduleSignature(rule, date as String?, due) !=
                  run.scheduleSignature ||
              !conditionMatches(definition, payload(record.data)) ||
              !await hasAccess(
                s,
                app,
                rule.executionActorId,
                tx,
                builder: true,
              );
          if (!suppress) {
            if (definition.effect == 'notifyOwner') {
              // Owner identity is trusted app state, never a generated actor ID.
              if (await hasAccess(s, app, app.ownerId, tx)) {
                recipients.add(app.ownerId);
              } else {
                suppress = true;
              }
            } else if (definition.effect == 'notifyActiveClaimants') {
              final pools = await ResourcePool.db.find(
                s,
                where: (t) =>
                    t.appId.equals(app.id!) & t.recordId.equals(record.id!),
                transaction: tx,
              );
              for (final pool in pools) {
                final claims = await Claim.db.find(
                  s,
                  where: (t) =>
                      t.poolId.equals(pool.id!) & t.active.equals(true),
                  limit: Limits.notificationFanout + 1,
                  transaction: tx,
                );
                if (claims.length > Limits.notificationFanout) {
                  fail(
                    'quotaExceeded',
                    'Reminder fan-out exceeds the configured limit.',
                  );
                }
                recipients.addAll(claims.map((c) => c.actorId));
              }
            } else {
              final version = await AppVersion.db.findById(
                    s,
                    app.activeVersionId!,
                    transaction: tx,
                  ),
                  spec = AppSpec.parse(version!.specJson),
                  col = spec.collection(record.collectionId);
              for (final b in col.behaviors.where(
                (b) => b.type == 'assignment.v1',
              )) {
                final id = payload(record.data)[b.fieldId];
                if (id is String) recipients.add(id);
              }
            }
          }
        }
        if (recipients.length > Limits.notificationFanout) {
          fail(
            'quotaExceeded',
            'Reminder fan-out exceeds the configured limit.',
          );
        }
        if (!suppress) {
          for (final id in recipients) {
            if (!await hasAccess(s, app, id, tx)) continue;
            final key = hashJson({
              'occurrence': run.occurrenceKey,
              'actor': id,
            });
            if (await Notification.db.findFirstRow(
                  s,
                  where: (t) => t.deliveryKey.equals(key),
                  transaction: tx,
                ) ==
                null) {
              await Notification.db.insertRow(
                s,
                Notification(
                  appId: app.id!,
                  workspaceId: app.workspaceId,
                  actorId: id,
                  runId: run.id!,
                  deliveryKey: key,
                  title: 'A reminder from ${app.name}',
                  body: 'An upcoming item needs your attention. Open the app for current details.',
                  createdAt: clock(),
                ),
                transaction: tx,
              );
            }
          }
        }
        run.status = suppress ? 'suppressed' : 'succeeded';
        run.completedAt = clock();
        run.leaseUntil = null;
        await AutomationRun.db.updateRow(s, run, transaction: tx);
        s.log(
          'run_complete run_id=$runId status=${run.status} lag_seconds=${clock().difference(run.dueAt).inSeconds}',
        );
      });
    } catch (error, stack) {
      if (claimedGeneration != null) {
        await _recordRunFailure(s, runId, claimedGeneration!);
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Failed effects roll back before this transaction. The same app lock and
  /// generation fence prevent duplicate/stale wakeups from recording a second
  /// failure, changing a terminal outcome, or shortening another retry deadline.
  static Future<void> _recordRunFailure(
    Session s,
    int runId,
    int generation,
  ) => s.db.transaction((tx) async {
    var run = await AutomationRun.db.findById(s, runId, transaction: tx);
    if (run == null) return;
    final app = await MiniApp.db.findFirstRow(
      s,
      where: (t) => t.id.equals(run!.appId),
      lockMode: LockMode.forUpdate,
      transaction: tx,
    );
    if (app == null) return;
    run = await AutomationRun.db.findById(s, runId, transaction: tx);
    if (run == null ||
        run.leaseGeneration != generation ||
        !_runEligible(run)) {
      return;
    }
    run.attempts++;
    run.leaseGeneration++;
    run.status = run.attempts >= 5 ? 'failed' : 'pending';
    run.errorCategory = 'retryableFailure';
    run.leaseUntil = null;
    run.nextAttemptAt = clock().add(Duration(seconds: 1 << run.attempts));
    if (run.status == 'failed') run.completedAt = clock();
    await AutomationRun.db.updateRow(s, run, transaction: tx);
    s.log('run_retry run_id=$runId attempt=${run.attempts}');
  });
  static const _repairUsageKey = '_appnestRepair';
  static const _failureUsageKey = '_appnestFailureCategory';
  static const _repairDiagnosticBytes = 8192;
  // The free development provider can spend 90 seconds awaiting a response.
  // Validation/commit still need headroom, and an expired result is fenced below.
  static const _generationLease = Duration(seconds: 120);

  /// Named calls are wakeups, not deduplication keys. The job lease and revision
  /// checks are authoritative even when the scheduler delivers duplicates.
  static Future<bool> scheduleGeneration(Session s, int id, DateTime at) async {
    try {
      await s.serverpod.futureCalls
          .callAtTime(at, identifier: 'appnest-generation-$id')
          .nestWorker
          .generate(id);
      return true;
    } catch (_) {
      s.log('generation_schedule_pending job_id=$id');
      return false;
    }
  }

  /// Recover a bounded batch so missed wakeups for independent jobs can run
  /// concurrently. Duplicate wakeups remain fenced by each job's lease.
  static Future<int> scheduleDueGenerations(Session s) async {
    final jobs = await GenerationJob.db.find(
      s,
      where: (t) =>
          t.status.inSet({'queued', 'generating', 'validating'}) &
          (t.nextAttemptAt <= clock()) &
          (t.leaseUntil.equals(null) | (t.leaseUntil <= clock())),
      orderBy: (t) => t.id,
      limit: Limits.automationBatch,
    );
    var scheduled = 0;
    for (final job in jobs) {
      if (await scheduleGeneration(s, job.id!, clock())) scheduled++;
    }
    return scheduled;
  }

  static String? failureCategory(GenerationJob job) {
    if (job.status == 'stale') return 'stale';
    final category = _generationUsage(job.usageJson)[_failureUsageKey];
    return category is String && _failureCategories.contains(category)
        ? category
        : job.status == 'failed'
        ? 'validation'
        : null;
  }

  static const _failureCategories = {
    'timeout',
    'responseFormat',
    'responseTooLarge',
    'unsupported',
    'providerUnavailable',
    'validation',
    'internal',
  };

  static String _safeFailureCategory(String? kind) => switch (kind) {
    'timeout' => 'timeout',
    'truncated' ||
    'output_json' ||
    'output_shape' ||
    'envelope_json' ||
    'envelope_shape' ||
    'content_missing' ||
    'completion_stopped' => 'responseFormat',
    'response_size' => 'responseTooLarge',
    'unsupported' => 'unsupported',
    'http_error' ||
    'transport_error' ||
    'providerUnavailable' => 'providerUnavailable',
    'unexpected' => 'internal',
    _ => 'validation',
  };

  static Map<String, dynamic> _generationUsage(String source) {
    try {
      final value = jsonDecode(source);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // Old or malformed usage metadata must never prevent a safe retry.
    }
    return {};
  }

  static String _withoutRepair(String source) => jsonEncode(
    _generationUsage(source)..remove(_repairUsageKey),
  );

  static String _boundedRepairDiagnostic(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length <= _repairDiagnosticBytes) return value;
    var end = _repairDiagnosticBytes;
    while ((bytes[end] & 0xc0) == 0x80) {
      end--;
    }
    return utf8.decode(bytes.sublist(0, end));
  }

  static Map<String, dynamic>? _repairContext(
    GenerationJob job,
    AppDraft draft,
    AppSpec base,
  ) {
    final repair = _generationUsage(job.usageJson)[_repairUsageKey];
    if (repair is! Map ||
        repair['jobId'] != job.id ||
        repair['draftId'] != draft.id ||
        repair['mutation'] != job.mutation ||
        repair['mutation'] != draft.mutation ||
        repair['baseCandidateHash'] != base.hash ||
        repair['baseCandidateHash'] != draft.candidateHash ||
        repair['baseVersionId'] != draft.baseVersionId ||
        repair['mode'] != job.mode ||
        repair['attempt'] is! int ||
        (repair['attempt'] as int) < 1 ||
        (repair['attempt'] as int) >= job.attempts) {
      return null;
    }
    final output = repair['output'];
    if (output is! String ||
        output.isEmpty ||
        utf8.encode(output).length > Limits.definitionBytes) {
      return null;
    }
    // Older persisted context did not store its diagnostic. It is safe to use
    // the job diagnostic only while that rejection is the immediately prior
    // attempt; after a transport error it no longer describes the rejected text.
    final diagnostics =
        repair['diagnostics'] ??
        (repair['attempt'] == job.attempts - 1 ? job.diagnostics : null);
    if (diagnostics is! String ||
        diagnostics.isEmpty ||
        utf8.encode(diagnostics).length > _repairDiagnosticBytes) {
      return null;
    }
    return {
      'jobId': job.id,
      'draftId': draft.id,
      'mutation': job.mutation,
      'baseCandidateHash': base.hash,
      'baseVersionId': draft.baseVersionId,
      'mode': job.mode,
      'attempt': repair['attempt'],
      'output': output,
      'diagnostics': diagnostics,
    };
  }

  static Future<void> generate(
    Session s,
    int id, {
    AiProvider? provider,
  }) async {
    final claimed = await s.db.transaction((tx) async {
      var j = await GenerationJob.db.findById(s, id, transaction: tx);
      if (j == null) return null;
      final app = await MiniApp.db.findFirstRow(
        s,
        where: (t) => t.id.equals(j!.appId),
        transaction: tx,
        lockMode: LockMode.forUpdate,
      );
      j = await GenerationJob.db.findById(s, id, transaction: tx);
      if (j == null ||
          !{'queued', 'generating', 'validating'}.contains(j.status) ||
          (j.leaseUntil?.isAfter(clock()) ?? false)) {
        return null;
      }
      final d = await AppDraft.db.findById(s, j.draftId, transaction: tx);
      if (app == null ||
          app.archived ||
          d == null ||
          d.activeJobId != j.id ||
          d.mutation != j.mutation ||
          d.baseVersionId != app.activeVersionId ||
          !await hasAccess(s, app, j.actorId, tx, builder: true)) {
        j.status = 'stale';
        j.usageJson = _withoutRepair(j.usageJson);
        await GenerationJob.db.updateRow(s, j, transaction: tx);
        return null;
      }
      if (j.attempts >= Limits.generationAttempts) {
        j.status = 'failed';
        j.diagnostics = 'Generation attempt limit reached.';
        j.usageJson = _withoutRepair(j.usageJson);
        await GenerationJob.db.updateRow(s, j, transaction: tx);
        return null;
      }
      if (j.nextAttemptAt.isAfter(clock())) return null;
      // The app row lock and this job's lease fence duplicate claims. Other
      // apps can claim their own jobs without waiting for this provider call.
      j.status = 'generating';
      j.attempts++;
      j.leaseGeneration++;
      j.leaseUntil = clock().add(_generationLease);
      j.updatedAt = clock();
      await GenerationJob.db.updateRow(s, j, transaction: tx);
      return (j, d);
    });
    if (claimed == null) return;
    final (job, draft) = claimed;
    AppSpec? candidate;
    AiResult? result;
    String? error;
    String? errorKind;
    String? baseCandidateHash;
    Map<String, dynamic>? repairContext;
    CompiledGeneratedCreation? compilation;
    bool? retryable;
    Duration? retryAfter;
    try {
      final ai = provider ?? ChatCompletionProvider.configured(s);
      if (ai == null) {
        fail(
          'providerUnavailable',
          'AI provider is not configured. Templates remain available.',
        );
      }
      final base = AppSpec.parse(draft.candidateJson);
      baseCandidateHash = base.hash;
      repairContext = _repairContext(job, draft, base);
      result = await ai.generate(
        job.requestText,
        base,
        editing: job.mode == 'edit',
        diagnostics: repairContext != null
            ? [repairContext['diagnostics'] as String]
            : job.diagnostics.isEmpty
            ? []
            : [job.diagnostics],
        rejectedOutput: repairContext?['output'] as String?,
      );
      await s.db.unsafeExecute(
        'UPDATE nest_generation SET status=\'validating\' WHERE id=@id AND "leaseGeneration"=@lease AND "leaseUntil">@now',
        parameters: QueryParameters.named({
          'id': id,
          'lease': job.leaseGeneration,
          'now': clock(),
        }),
      );
      final output = parseAiOutput(result.text);
      if (output['unsupported'] is String) {
        throw const AiResponseException(
          'unsupported',
          'Requested capability is unavailable. Choose supported AppNest features.',
        );
      }
      if (job.mode == 'edit') {
        keys(output, {'patches'}, 'edit output');
        candidate = base;
        for (final patch in array(output['patches'], 'patches', 10)) {
          candidate = candidate!.patch(
            payload(patch),
            () => 'id_${randomToken().substring(0, 16).replaceAll('-', '_')}',
          );
        }
        final errors = base.compatibilityErrors(candidate!);
        if (errors.isNotEmpty) throw SpecException(errors.join(' '));
      } else {
        try {
          compilation = compileGeneratedCreation(
            jsonEncode(output),
            rawOutput: result.text,
          );
          candidate = compilation.spec;
        } on SpecException catch (error) {
          // Preserve strict rejection and the authored bytes. A malformed
          // primary/form route can hide missing edit capabilities and invalid
          // behavior bindings; aggregate only bounded identity-based evidence.
          final raw = creationRawRepairMetadata(
            output,
            request: job.requestText,
          );
          final diagnostics = (raw['rawDiagnostics'] as List? ?? [])
              .cast<String>();
          throw SpecException([error.message, ...diagnostics].join(' '));
        }
        // Fresh AI apps get a finished default design. Existing definitions and
        // edit jobs keep their exact presentation unless explicitly changed.
        if (candidate.appearance == null) {
          candidate = candidate.patch({
            'type': 'SetAppearance',
            'appearance': {'style': 'clean'},
          }, () => throw StateError('Appearance must not allocate IDs'));
        }
      }
      final experienceErrors = <String>[];
      try {
        validateGeneratedExperience(
          candidate,
          baseline: job.mode == 'edit' ? base : null,
        );
      } on SpecException catch (error) {
        experienceErrors.add(error.message);
      }
      if (job.mode != 'edit') {
        try {
          GenerationRequirements.fromRequest(job.requestText)
              .validate(candidate);
        } on SpecException catch (error) {
          experienceErrors.add(error.message);
        }
      }
      if (experienceErrors.isNotEmpty) {
        throw SpecException(experienceErrors.join(' '));
      }
    } on AiResponseException catch (e) {
      error = e.message;
      errorKind = e.kind;
      retryable = e.retryable;
      retryAfter = e.retryAfter;
    } on SpecException catch (e) {
      error = e.message;
      errorKind = 'spec_validation';
    } on NestError catch (e) {
      error = e.message;
      errorKind = e.category == 'providerUnavailable'
          ? 'providerUnavailable'
          : 'request_validation';
    } on FormatException {
      error = 'The generated definition contains an invalid value format. Return valid values matching the AppSpec schema.';
      errorKind = 'value_format';
    } catch (_) {
      error = 'Generation could not validate the response. Return a complete object matching the AppSpec schema.';
      errorKind = 'unexpected';
    }
    try {
      await s.db.transaction((tx) async {
        final app = await MiniApp.db.findFirstRow(
              s,
              where: (t) => t.id.equals(job.appId),
              transaction: tx,
              lockMode: LockMode.forUpdate,
            ),
            j = await GenerationJob.db.findById(s, id, transaction: tx),
            d = await AppDraft.db.findById(s, job.draftId, transaction: tx);
        if (j == null ||
            j.leaseGeneration != job.leaseGeneration ||
            !(j.leaseUntil?.isAfter(clock()) ?? false)) {
          return;
        }
        final stale =
            app == null ||
            app.archived ||
            d == null ||
            d.activeJobId != id ||
            d.mutation != job.mutation ||
            d.candidateHash != draft.candidateHash ||
            d.baseVersionId != app.activeVersionId ||
            !await hasAccess(s, app, job.actorId, tx, builder: true);
        if (!stale && candidate != null && error == null) {
          try {
            await Media.syncDefinition(
              s,
              Access(app, 'builder'),
              candidate,
              tx,
              draftId: d.id,
            );
          } on NestError {
            error = 'The generated definition references an unavailable image. Preserve existing image references or omit new image references.';
            errorKind = 'media_reference';
          }
        }
        if (!(j.leaseUntil?.isAfter(clock()) ?? false)) {
          // Media synchronisation can wait on rows after the initial lease check.
          // Roll its reference changes back together with any late job result.
          throw const _ExpiredGenerationLease();
        }
        j.status = stale
            ? 'stale'
            : error != null
            ? (j.attempts >= Limits.generationAttempts ||
                      errorKind == 'unsupported' ||
                      retryable == false
                  ? 'failed'
                  : 'queued')
            : 'preview ready';
        j.diagnostics = error ?? '';
        j.provider = result?.provider;
        j.model = result?.model;
        // Provider metadata cannot supply or retain our private repair context.
        final usage = Map<String, dynamic>.from(result?.usage ?? {})
          ..remove(_repairUsageKey)
          ..remove(_failureUsageKey)
          ..remove('_appnestCompilation');
        if (!stale && error == null && compilation != null) {
          usage['_appnestCompilation'] = {
            ...compilation.toJson(),
            'finalCandidateHash': candidate!.hash,
          };
        }
        if (errorKind != null) {
          usage[_failureUsageKey] = _safeFailureCategory(errorKind);
        }
        final output = result?.text;
        if (j.status == 'queued' &&
            {
              'output_json',
              'output_shape',
              'spec_validation',
              'value_format',
              'media_reference',
            }.contains(errorKind) &&
            baseCandidateHash != null &&
            output != null &&
            output.isNotEmpty &&
            utf8.encode(output).length <= Limits.definitionBytes) {
          usage[_repairUsageKey] = {
            'jobId': j.id,
            'draftId': draft.id,
            'mutation': job.mutation,
            'baseCandidateHash': baseCandidateHash,
            'baseVersionId': draft.baseVersionId,
            'mode': job.mode,
            'attempt': j.attempts,
            'output': output,
            'diagnostics': _boundedRepairDiagnostic(error!),
          };
        } else if (j.status == 'queued' &&
            repairContext != null &&
            (retryable == true ||
                {
                  'timeout',
                  'http_error',
                  'transport_error',
                  'envelope_json',
                  'envelope_shape',
                  'content_missing',
                  'completion_stopped',
                  'truncated',
                  'response_size',
                }.contains(errorKind))) {
          // The public latest failure can describe transport trouble while the
          // next attempt still repairs the last bounded semantic rejection.
          usage[_repairUsageKey] = repairContext;
        }
        j.usageJson = jsonEncode(usage);
        j.leaseUntil = null;
        final retryAfterSeconds = retryAfter == null
            ? 0
            : (retryAfter.inMicroseconds / Duration.microsecondsPerSecond)
                  .ceil()
                  .clamp(1, 120);
        j.nextAttemptAt = clock().add(
          Duration(seconds: max(1 << j.attempts, retryAfterSeconds)),
        );
        j.updatedAt = clock();
        if (!stale && candidate != null && error == null) {
          d.candidateJson = candidate.canonical;
          d.candidateHash = candidate.hash;
          d.updatedAt = clock();
          await AppDraft.db.updateRow(s, d, transaction: tx);
        }
        await GenerationJob.db.updateRow(s, j, transaction: tx);
        if (!(job.leaseUntil?.isAfter(clock()) ?? false)) {
          throw const _ExpiredGenerationLease();
        }
        s.log(
          'generation_result job_id=$id status=${j.status} attempt=${j.attempts} error_kind=${errorKind ?? 'none'}',
        );
      });
    } on _ExpiredGenerationLease {
      return;
    }
    final next = await GenerationJob.db.findById(s, id);
    if (next?.status == 'queued') {
      await scheduleGeneration(s, id, next!.nextAttemptAt);
    }
  }
}

class NestWorkerFutureCall extends FutureCall {
  Future<void> reconcile(Session session) => Worker.drain(session);
  Future<void> execute(Session session, int runId) =>
      Worker.execute(session, runId);
  Future<void> generate(Session session, int jobId) =>
      Worker.generate(session, jobId);
}
