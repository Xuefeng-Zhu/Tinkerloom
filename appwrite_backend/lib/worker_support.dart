part of 'service.dart';

/// Scheduling is an optional wakeup, never the durable source of truth.
abstract interface class WorkerWakeups {
  Future<String> schedule({
    required String dispatchId,
    required String proof,
    required DateTime at,
  });
}

/// Trusted server runner. It is deliberately absent from execute() operations;
/// deploy one private Function with execute:[] and separate execution modes.
class WorkerEngine {
  WorkerEngine(this.service);
  final PlatformService service;
  Future<void> generate(String jobId) => service._runGeneration(jobId);
  Future<Row> reminders({int limit = 100}) => service._drainReminders(limit);
  Future<Row> generations({int limit = 2}) => service._drainGenerations(limit);
  Future<Row> flushWakeups({int limit = 10}) => service._flushWakeups(limit);
  Future<Row> reconcile({int limit = 25}) => service._reconcileWorker(limit);
  Future<Row> dispatch(String dispatchId, String proof) =>
      service._dispatchWorker(dispatchId, proof);
}

extension _WorkerSupport on PlatformService {
  bool get _extendedGlmGeneration =>
      aiProvider is ai.ChatCompletionProvider &&
      (aiProvider as ai.ChatCompletionProvider).usesExtendedGlmDeadline;

  /// Retry only optimistic DB conflicts while preserving the same already
  /// computed provider response. No network/provider call belongs in action.
  Future<T> _workerTransaction<T>(Future<T> Function(String) action) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _transaction(action);
      } on ServiceException catch (error) {
        if (error.code != 'transaction_conflict' || attempt >= 4) rethrow;
      }
    }
  }

  DateTime _time(Object? value) => DateTime.parse(value as String).toUtc();
  String _now() => clock().toUtc().toIso8601String();
  String _limitedDiagnostic(String value, {int maximum = 8192}) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maximum) return value;
    var end = maximum;
    while (end > 0 && (bytes[end] & 0xc0) == 0x80) end--;
    return utf8.decode(bytes.sublist(0, end));
  }

  Future<AppAccess> _workerStage(String appId, String tx) async {
    final app = await store.get('apps', appId, transactionId: tx);
    if (app == null || app['engine'] != 'appspec.v1')
      throw const ServiceException('not_found', 404);
    final workspaceId = app['workspaceId'] as String;
    final workspace = await store.get(
      'workspaces',
      workspaceId,
      transactionId: tx,
    );
    if (workspace == null) throw const ServiceException('not_found', 404);
    await store.update('workspaces', workspaceId, {
      'guard': _nonce(),
    }, transactionId: tx);
    final current = await store.update('apps', appId, {
      'guard': _nonce(),
    }, transactionId: tx);
    return AppAccess(current, workspace, 'owner');
  }

  Future<bool> _workerHasAccess(
    AppAccess access,
    String actor,
    String tx, {
    bool builder = false,
  }) async {
    try {
      final current = await _access(
        actor,
        access.app[r'$id'] as String,
        transactionId: tx,
      );
      return !builder || current.builder;
    } on ServiceException {
      return false;
    }
  }

  Future<List<Row>> _workerRows(
    String table,
    Map<String, String> filters,
    String? tx,
  ) async {
    final result = <Row>[];
    String? cursor;
    while (true) {
      final page = await store.list(
        table,
        filters,
        transactionId: tx,
        limit: 100,
        afterId: cursor,
        detectOverflow: false,
      );
      result.addAll(page);
      if (page.length < 100) return result;
      final next = page.last[r'$id'] as String;
      if (next == cursor) throw const ServiceException('integrity_error', 500);
      cursor = next;
    }
  }

  Future<bool> _wakeGeneration(String id, DateTime at) async {
    try {
      await _flushWakeups(3);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Row?> _generationForApp(
    String actor,
    AppAccess access,
    String? tx,
  ) async {
    if (!access.builder) return null;
    final session = await store.get(
      'generation_sessions',
      _identity('g', [access.app[r'$id'] as String, actor]),
      transactionId: tx,
    );
    if (session == null || session['latestJobId'] == null) return null;
    if (session['appId'] != access.app[r'$id'] ||
        session['actorId'] != actor ||
        session['workspaceId'] != access.app['workspaceId'])
      throw const ServiceException('integrity_error', 500);
    final job = await store.get(
      'generation_jobs',
      session['latestJobId'] as String,
      transactionId: tx,
    );
    if (job == null ||
        job['appId'] != access.app[r'$id'] ||
        job['actorId'] != actor)
      throw const ServiceException('integrity_error', 500);
    return _publicGeneration(job);
  }

  Row _publicGeneration(Row job) => {
    'id': job[r'$id'],
    'status': job['status'],
    'mode': job['mode'],
    'mutation': job['mutation'],
    'attempts': job['attempts'],
    'requestText': job['requestText'],
    'diagnostics': job['diagnostics'],
    'provider': job['provider'],
    'model': job['model'],
    'nextAttemptAt': job['nextAttemptAt'],
    'failureCategory': job['failureCategory'],
  };

  Future<void> _clearActorGeneration(Row job, String tx) async {
    final actor = job['actorId'] as String;
    final limits = await _stageActorLimit(actor, tx);
    if (limits['activeGenerationJobId'] == job[r'$id'])
      await store.update('actor_limits', limits[r'$id'] as String, {
        'activeGenerationJobId': null,
      }, transactionId: tx);
  }

  Future<void> _manualSupersede(
    String actor,
    AppAccess access,
    String tx,
  ) async {
    final sessionId = _identity('g', [access.app[r'$id'] as String, actor]);
    final session = await store.get(
      'generation_sessions',
      sessionId,
      transactionId: tx,
    );
    if (session == null || session['latestJobId'] == null) return;
    final job = await store.get(
      'generation_jobs',
      session['latestJobId'] as String,
      transactionId: tx,
    );
    if (job != null &&
        {'queued', 'generating', 'validating'}.contains(job['status'])) {
      await store.update('generation_jobs', job[r'$id'] as String, {
        'status': 'stale',
        'leaseGeneration': (job['leaseGeneration'] as int) + 1,
        'leaseUntil': null,
        'repairJson': null,
        'updatedAt': _now(),
      }, transactionId: tx);
      await _clearActorGeneration(job, tx);
    }
    await store.update('generation_sessions', sessionId, {
      'latestJobId': null,
    }, transactionId: tx);
  }
}
