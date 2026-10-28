import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';

import '../../generated/protocol.dart';
import '../runtime/access.dart';
import '../definitions/apps.dart';
import '../automation/worker.dart';
import '../media/media.dart';
import 'provider.dart';

class Builder {
  static PlatformInfo platform(Session s) {
    final executionEnabled = s.serverpod.config.futureCallExecutionEnabled;
    final aiAvailable =
        executionEnabled && ChatCompletionProvider.configured(s) != null;
    return PlatformInfo(
      aiAvailable: aiAvailable,
      aiMode: !executionEnabled
          ? 'Template mode — AI background processing is disabled'
          : aiAvailable
          ? 'Live AI'
          : 'Template mode — AI provider not configured',
      development: s.serverpod.runMode == 'development',
      actorId: actor(s),
    );
  }

  static void _requireAiExecution(Session s) {
    if (!s.serverpod.config.futureCallExecutionEnabled) {
      fail(
        'providerUnavailable',
        'AI is unavailable on this server because background processing is disabled. Use templates or manual edits.',
      );
    }
  }

  /// Guidance is a read-only definition operation. An empty result means the
  /// request can proceed as written. The reservation is committed before the
  /// provider request so concurrent calls share a strict rolling cap.
  static Future<List<GuidanceQuestion>> suggestQuestions(
    Session s,
    String idea,
    int? workspaceId,
    int? draftId, {
    GuidanceProvider? provider,
  }) => validated(() async {
    final request = str(idea, 'idea', max: 2000).trim();
    if (utf8.encode(request).length > 4000) {
      fail('invalidInput', 'Idea exceeds the guidance byte limit.');
    }
    if ((workspaceId == null) == (draftId == null)) {
      fail('invalidInput', 'Choose a workspace or a draft for guidance.');
    }
    final ai = provider ?? ChatCompletionProvider.configured(s);
    final definition = await s.db.transaction<AppSpec?>((tx) async {
      AppSpec? current;
      if (workspaceId != null) {
        await workspaceAccess(s, workspaceId, tx: tx);
      } else {
        final d = await draft(s, draftId!, tx: tx);
        if (d.publishedVersionId != null) {
          fail('recordConflict', 'This draft is already published.');
        }
        current = AppSpec.parse(d.candidateJson);
      }
      _requireAiExecution(s);
      if (ai == null) {
        fail(
          'providerUnavailable',
          'AI guidance is unavailable. Try the built-in questions.',
        );
      }
      final id = actor(s);
      await s.db.unsafeQuery(
        'SELECT pg_advisory_xact_lock(hashtextextended(@actor, 37))',
        parameters: QueryParameters.named({'actor': id}),
        transaction: tx,
      );
      final now = clock();
      final used = await GuidanceRequest.db.count(
        s,
        where: (t) =>
            t.actorId.equals(id) &
            (t.createdAt >= now.subtract(const Duration(days: 1))),
        transaction: tx,
      );
      if (used >= 20) {
        fail('quotaExceeded', 'Daily guidance limit reached.');
      }
      await GuidanceRequest.db.insertRow(
        s,
        GuidanceRequest(actorId: id, createdAt: now),
        transaction: tx,
      );
      return current;
    });
    try {
      return await ai!.suggestQuestions(request, definition: definition);
    } on AiResponseException {
      fail('providerUnavailable', 'AI guidance is unavailable. Try again.');
    }
  });

  static Future<AppDraft> draft(Session s, int id, {Transaction? tx}) async {
    final d = await AppDraft.db.findById(s, id, transaction: tx);
    if (d == null || d.actorId != actor(s)) {
      fail('notFound', 'Draft unavailable.');
    }
    final a = await access(s, d.appId, tx: tx);
    if (d.workspaceId != a.app.workspaceId) {
      fail('notFound', 'Draft unavailable.');
    }
    a.requireBuilder();
    return d;
  }

  static Future<BuilderSnapshot> begin(
    Session s,
    int workspaceId,
    String templateKey,
    int? appId,
  ) => validated(
    () => s.db.transaction((tx) async {
      await workspaceAccess(s, workspaceId, tx: tx);
      MiniApp app;
      AppSpec spec;
      if (appId != null) {
        final a = await access(s, appId, tx: tx, lock: true);
        a.requireBuilder();
        a.writable();
        app = a.app;
        if (app.workspaceId != workspaceId) {
          fail('notFound', 'App unavailable in this workspace.');
        }
        if (app.activeVersionId == null) {
          final existing = await Apps.unpublishedDraft(s, a, tx: tx);
          if (existing == null) fail('notFound', 'Draft unavailable.');
          return snapshot(s, existing, tx: tx);
        }
        spec = await a.spec(s, tx: tx);
      } else {
        await reserveAppSlot(s, workspaceId, tx);
        spec =
            starterTemplates()[templateKey] ??
            (throw const SpecException('Unknown template'));
        app = await MiniApp.db.insertRow(
          s,
          MiniApp(
            workspaceId: workspaceId,
            ownerId: actor(s),
            name: spec.name,
            createdAt: clock(),
          ),
          transaction: tx,
        );
      }
      final d = await AppDraft.db.insertRow(
        s,
        AppDraft(
          appId: app.id!,
          workspaceId: app.workspaceId,
          actorId: actor(s),
          baseVersionId: app.activeVersionId,
          candidateJson: spec.canonical,
          candidateHash: spec.hash,
          updatedAt: clock(),
        ),
        transaction: tx,
      );
      await Media.syncDefinition(
        s,
        Access(app, 'builder'),
        spec,
        tx,
        draftId: d.id,
      );
      return snapshot(s, d, tx: tx);
    }),
  );
  static Future<BuilderSnapshot> get(Session s, int draftId) =>
      s.db.transaction((tx) async {
        var d = await draft(s, draftId, tx: tx);
        // Generation saves the candidate and job status under the app lock.
        // Read them under the same lock so polling cannot report a completed
        // request while still returning its previous candidate.
        await access(s, d.appId, tx: tx, lock: true);
        d = await draft(s, draftId, tx: tx);
        return snapshot(s, d, tx: tx);
      });
  static Future<BuilderSnapshot> snapshot(
    Session s,
    AppDraft d, {
    Transaction? tx,
  }) async {
    final job = d.activeJobId == null
        ? null
        : await GenerationJob.db.findById(s, d.activeJobId!, transaction: tx);
    final base = d.baseVersionId == null
        ? null
        : await AppVersion.db.findById(s, d.baseVersionId!, transaction: tx);
    final candidate = AppSpec.parse(d.candidateJson);
    return BuilderSnapshot(
      appId: d.appId,
      draftId: d.id!,
      jobId: job?.id,
      baseVersionId: d.baseVersionId,
      mutation: d.mutation,
      stage: job?.status ?? 'preview ready',
      candidateJson: d.candidateJson,
      candidateHash: d.candidateHash,
      diagnostics: job == null || job.diagnostics.isEmpty
          ? []
          : [job.diagnostics],
      changes: candidate.diff(
        base == null ? null : AppSpec.parse(base.specJson),
      ),
      enabledRuleIds:
          (await Automation.db.find(
                s,
                where: (t) => t.appId.equals(d.appId) & t.enabled.equals(true),
                transaction: tx,
              ))
              .where(
                (approved) => candidate.automationRequests.any(
                  (rule) =>
                      rule.id == approved.ruleId &&
                      canonicalJson(rule.toJson()) == approved.ruleJson,
                ),
              )
              .map((r) => r.ruleId)
              .toList(),
      publishedVersionId: d.publishedVersionId,
      candidateReady:
          job == null || job.mode == 'edit' || job.status == 'preview ready',
      latestRequest: job?.requestText,
      jobAttempts: job?.attempts ?? 0,
      jobCreatedAt: job?.createdAt,
      jobUpdatedAt: job?.updatedAt,
      failureCategory: job == null ? null : Worker.failureCategory(job),
    );
  }

  static Future<BuilderSnapshot> patch(
    Session s,
    int id,
    int mutation,
    String patchJson,
  ) => validated(
    () => s.db.transaction((tx) async {
      var d = await draft(s, id, tx: tx);
      final a = await access(s, d.appId, tx: tx, lock: true);
      a.writable();
      d = await draft(s, id, tx: tx);
      if (d.mutation != mutation || d.publishedVersionId != null) {
        fail('recordConflict', 'This draft changed. Refresh it.');
      }
      final next = AppSpec.parse(d.candidateJson).patch(
        payload(jsonDecode(patchJson)),
        () => 'id_${randomToken().substring(0, 16).replaceAll('-', '_')}',
      );
      d.candidateJson = next.canonical;
      d.candidateHash = next.hash;
      d.mutation++;
      d.activeJobId = null;
      d.updatedAt = clock();
      await AppDraft.db.updateRow(s, d, transaction: tx);
      await Media.syncDefinition(s, a, next, tx, draftId: d.id);
      return snapshot(s, d, tx: tx);
    }),
  );

  /// A successful unpublished generation establishes a definition to edit.
  /// Manual changes and later failed requests retain that context; a failed
  /// first request leaves only the placeholder and must still create from scratch.
  static Future<String> generationMode(
    Session s,
    AppDraft d, {
    required Transaction tx,
    bool startFromScratch = true,
  }) async {
    if (!startFromScratch || d.baseVersionId != null) return 'edit';
    final successful = await GenerationJob.db.findFirstRow(
      s,
      where: (t) =>
          t.appId.equals(d.appId) &
          t.draftId.equals(d.id!) &
          t.status.equals('preview ready'),
      transaction: tx,
    );
    return successful == null ? 'create' : 'edit';
  }

  static Future<BuilderSnapshot> generate(
    Session s,
    int id,
    int mutation,
    String request, {
    bool startFromScratch = true,
  }) => validated(() async {
    final accepted = await s.db.transaction((tx) async {
      str(request, 'request', max: Limits.promptBytes);
      if (utf8.encode(request).length > Limits.promptBytes) {
        fail('invalidInput', 'Request exceeds the prompt byte limit.');
      }
      var d = await draft(s, id, tx: tx);
      final a = await access(s, d.appId, tx: tx, lock: true);
      a.writable();
      d = await draft(s, id, tx: tx);
      await s.db.unsafeQuery(
        'SELECT pg_advisory_xact_lock(hashtextextended(@actor,1))',
        parameters: QueryParameters.named({'actor': actor(s)}),
        transaction: tx,
      );
      if (d.mutation != mutation || d.publishedVersionId != null) {
        fail('recordConflict', 'This draft changed. Refresh it.');
      }
      _requireAiExecution(s);
      final active = await GenerationJob.db.find(
        s,
        where: (t) =>
            t.actorId.equals(actor(s)) &
            t.status.inSet({'queued', 'generating', 'validating'}),
        limit: 1,
        transaction: tx,
      );
      if (active.isNotEmpty) {
        fail(
          'quotaExceeded',
          'One generation at a time. Wait for the current request.',
        );
      }
      if (await GenerationJob.db.count(
            s,
            where: (t) =>
                t.actorId.equals(actor(s)) &
                (t.createdAt >= clock().subtract(const Duration(days: 1))),
            transaction: tx,
          ) >=
          Limits.generationJobsPerDay) {
        fail(
          'quotaExceeded',
          'Daily generation limit reached. Templates and existing apps remain available.',
        );
      }
      if (ChatCompletionProvider.configured(s) == null) {
        fail(
          'providerUnavailable',
          'AI is not configured. Use templates or manual edits; ask the server operator to configure AI_BASE_URL, AI_MODEL, and AI_API_KEY.',
        );
      }
      d.mutation++;
      final job = await GenerationJob.db.insertRow(
        s,
        GenerationJob(
          appId: d.appId,
          draftId: d.id!,
          actorId: actor(s),
          mutation: d.mutation,
          status: 'queued',
          requestText: request,
          mode: await generationMode(
            s,
            d,
            tx: tx,
            startFromScratch: startFromScratch,
          ),
          promptVersion: 'appnest-v1-typed-customization-21',
          nextAttemptAt: clock(),
          diagnostics: '',
          usageJson: '{}',
          createdAt: clock(),
          updatedAt: clock(),
        ),
        transaction: tx,
      );
      d.activeJobId = job.id;
      d.updatedAt = clock();
      await AppDraft.db.updateRow(s, d, transaction: tx);
      return snapshot(s, d, tx: tx);
    });
    // The accepted job is committed before the durable wakeup. Reconciliation
    // recovers a crash or scheduling failure in this small gap.
    await Worker.scheduleGeneration(s, accepted.jobId!, clock());
    return accepted;
  });

  static Future<BuilderSnapshot> abandonFailedEdit(
    Session s,
    int draftId,
    int mutation,
    int jobId,
  ) => validated(
    () => s.db.transaction((tx) async {
      var d = await draft(s, draftId, tx: tx);
      final a = await access(s, d.appId, tx: tx, lock: true);
      a.writable();
      d = await draft(s, draftId, tx: tx);
      if (d.mutation != mutation ||
          d.activeJobId != jobId ||
          d.publishedVersionId != null ||
          d.baseVersionId != a.app.activeVersionId) {
        fail(
          'recordConflict',
          'This draft changed. Refresh it before continuing.',
        );
      }
      final job = await GenerationJob.db.findById(s, jobId, transaction: tx);
      if (job == null ||
          job.draftId != d.id ||
          job.mutation != mutation ||
          job.status != 'failed' ||
          job.mode != 'edit') {
        fail(
          'invalidInput',
          'Only a failed edit can keep its previous preview.',
        );
      }
      // Edit jobs begin from a validated template, earlier successful candidate,
      // or published version. A failed create still contains only a placeholder.
      AppSpec.parse(d.candidateJson);
      d.activeJobId = null;
      d.mutation++;
      d.updatedAt = clock();
      await AppDraft.db.updateRow(s, d, transaction: tx);
      return snapshot(s, d, tx: tx);
    }),
  );
  static Future<int> publish(Session s, PublishRequest request) => validated(
    () => s.db.transaction((tx) async {
      var d = await draft(s, request.draftId, tx: tx);
      final a = await access(s, d.appId, tx: tx, lock: true);
      a.requireBuilder();
      d = await draft(s, request.draftId, tx: tx);
      final key =
              'publish:${str(request.idempotencyKey, 'publication key', max: 100)}',
          hash = hashJson(request.toJson());
      final receipt = await ActionReceipt.db.findFirstRow(
        s,
        where: (t) =>
            t.appId.equals(a.app.id!) &
            t.actorId.equals(actor(s)) &
            t.idempotencyKey.equals(key),
        transaction: tx,
      );
      if (receipt != null) {
        if (receipt.requestHash != hash) {
          fail('invalidInput', 'Publication key already used.');
        }
        return jsonDecode(receipt.outcomeJson)['versionId'] as int;
      }
      a.writable();
      if (d.publishedVersionId != null ||
          d.candidateHash != request.candidateHash ||
          a.app.activeVersionId != request.expectedCurrentVersionId ||
          d.baseVersionId != request.expectedCurrentVersionId) {
        fail(
          'staleDefinition',
          'The candidate or published app changed. Review again.',
        );
      }
      if (d.activeJobId != null) {
        final job = await GenerationJob.db.findById(
          s,
          d.activeJobId!,
          transaction: tx,
        );
        if (job?.status != 'preview ready') {
          fail(
            'invalidInput',
            'Wait for a validated preview before publishing.',
          );
        }
      }
      final spec = AppSpec.parse(d.candidateJson);
      if (spec.hash != request.candidateHash) {
        fail('invalidInput', 'Candidate integrity check failed.');
      }
      if (a.app.activeVersionId != null) {
        final previous = await a.spec(s, tx: tx),
            errors = previous.compatibilityErrors(spec);
        if (errors.isNotEmpty) fail('invalidInput', errors.join(' '));
      }
      if (request.activateExistingRecordIds.length > Limits.activationScope) {
        fail('quotaExceeded', 'Existing-record activation scope is too large.');
      }
      final ruleIds = request.enabledRuleIds.toSet();
      if (ruleIds.any(
        (id) => !spec.automationRequests.any((r) => r.id == id),
      )) {
        fail('invalidInput', 'Unknown requested reminder.');
      }
      if (request.enabledRuleIds.isNotEmpty) Worker.requireRemindersEnabled(s);
      final review = hashJson({
        'candidateHash': spec.hash,
        'enabledRuleIds': List<String>.from(request.enabledRuleIds)..sort(),
        'activateExistingRecordIds': List<int>.from(
          request.activateExistingRecordIds,
        )..sort(),
      });
      if (review != request.reviewHash) {
        fail(
          'invalidInput',
          'Review approval does not match this publication.',
        );
      }
      final versions = await AppVersion.db.count(
        s,
        where: (t) => t.appId.equals(a.app.id!),
        transaction: tx,
      );
      final version = await AppVersion.db.insertRow(
        s,
        AppVersion(
          appId: a.app.id!,
          workspaceId: a.app.workspaceId,
          number: versions + 1,
          specJson: spec.canonical,
          candidateHash: spec.hash,
          publisherId: actor(s),
          createdAt: clock(),
        ),
        transaction: tx,
      );
      await Media.syncDefinition(s, a, spec, tx, versionId: version.id);
      final rules = await Automation.db.find(
        s,
        where: (t) => t.appId.equals(a.app.id!),
        transaction: tx,
      );
      for (final old in rules) {
        if (!ruleIds.contains(old.ruleId)) {
          old.enabled = false;
          await Automation.db.updateRow(s, old, transaction: tx);
        }
      }
      for (final r in spec.automationRequests.where(
        (r) => ruleIds.contains(r.id),
      )) {
        final text = canonicalJson(r.toJson()),
            old = rules.where((x) => x.ruleId == r.id).firstOrNull;
        if (old == null) {
          await Automation.db.insertRow(
            s,
            Automation(
              appId: a.app.id!,
              workspaceId: a.app.workspaceId,
              ruleId: r.id,
              ruleVersion: 1,
              ruleJson: text,
              enabled: true,
              executionActorId: actor(s),
              activateExisting: false,
              activatedAt: clock(),
            ),
            transaction: tx,
          );
        } else if (!old.enabled || old.ruleJson != text) {
          old.ruleVersion++;
          old.ruleJson = text;
          old.enabled = true;
          old.executionActorId = actor(s);
          old.activatedAt = clock();
          await Automation.db.updateRow(s, old, transaction: tx);
        }
      }
      final approvedRules = await Automation.db.find(
        s,
        where: (t) => t.appId.equals(a.app.id!) & t.enabled.equals(true),
        transaction: tx,
      );
      for (final id in request.activateExistingRecordIds.toSet()) {
        final existing = await record(s, a, id, tx: tx);
        for (final rule in approvedRules) {
          if (spec.automationRequests
                  .firstWhere((r) => r.id == rule.ruleId)
                  .collectionId !=
              existing.collectionId) {
            continue;
          }
          await OutboxEvent.db.insertRow(
            s,
            OutboxEvent(
              appId: a.app.id!,
              recordId: id,
              kind: Worker.enrollmentKind(rule),
              nextAttemptAt: clock(),
              createdAt: clock(),
            ),
            transaction: tx,
          );
        }
      }
      a.app.activeVersionId = version.id;
      a.app.name = spec.name;
      d.publishedVersionId = version.id;
      await AppDraft.db.updateRow(s, d, transaction: tx);
      if (await AppShortcut.db.findFirstRow(
            s,
            where: (t) =>
                t.appId.equals(a.app.id!) & t.actorId.equals(actor(s)),
            transaction: tx,
          ) ==
          null) {
        await AppShortcut.db.insertRow(
          s,
          AppShortcut(appId: a.app.id!, actorId: actor(s)),
          transaction: tx,
        );
      }
      await changed(s, a, 'publish', tx, requestId: key);
      await ActionReceipt.db.insertRow(
        s,
        ActionReceipt(
          appId: a.app.id!,
          actorId: actor(s),
          idempotencyKey: key,
          requestHash: hash,
          outcomeJson: jsonEncode({'versionId': version.id}),
          createdAt: clock(),
        ),
        transaction: tx,
      );
      return version.id!;
    }),
  );
}
