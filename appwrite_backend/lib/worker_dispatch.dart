part of 'service.dart';

/// A persisted work wakeup is not evidence that the work was delivered. Unknown
/// execution-creation responses can cause duplicate wakeups; job/run guards are
/// the authoritative idempotency boundary.
extension _WorkerDispatch on PlatformService {
  Future<void> _queueDispatch(
    String mode,
    String target,
    String appId,
    DateTime at,
    String tx,
  ) async {
    final id = _identity('d', [mode, target, at.toUtc().toIso8601String()]);
    if (await store.get('worker_dispatches', id, transactionId: tx) != null)
      return;
    await store.create('worker_dispatches', id, {
      'appId': appId,
      'mode': mode,
      'targetId': target,
      'runAt': at.toUtc().toIso8601String(),
      'status': 'planned',
      'attempts': 0,
      'generation': 0,
      'proofHash': null,
      'leaseUntil': null,
      'executionId': null,
      'nextAttemptAt': _now(),
      'errorCategory': null,
      'createdAt': _now(),
      'completedAt': null,
    }, transactionId: tx);
  }

  Future<Row> _flushWakeups(int maximum) async {
    if (maximum < 1 || maximum > 25)
      throw ArgumentError('Wakeup batch must be 1..25');
    if (wakeups == null) return {'scheduled': 0, 'unavailable': true};
    final all = await _workerRows('worker_dispatches', {}, null);
    final pending = all
        .where(
          (row) =>
              (row['status'] == 'planned' ||
                  row['status'] == 'sending' &&
                      !_time(row['leaseUntil']).isAfter(clock().toUtc())) &&
              (row['attempts'] as int) < 5 &&
              !_time(row['nextAttemptAt']).isAfter(clock().toUtc()),
        )
        .take(maximum);
    var scheduled = 0;
    for (final initial in pending) {
      // Only the short-lived body contains this nonce. Persistence has its hash.
      final proof = base64Url
          .encode(
            List.generate(32, (_) => PlatformService._random.nextInt(256)),
          )
          .replaceAll('=', '');
      Row? claim;
      try {
        claim = await _workerTransaction<Row?>((tx) async {
          final row = await store.get(
            'worker_dispatches',
            initial[r'$id'] as String,
            transactionId: tx,
          );
          if (row == null ||
              (row['status'] != 'planned' &&
                  !(row['status'] == 'sending' &&
                      !_time(row['leaseUntil']).isAfter(clock().toUtc()))) ||
              (row['attempts'] as int) >= 5 ||
              _time(row['nextAttemptAt']).isAfter(clock().toUtc()))
            return null;
          return store.update('worker_dispatches', row[r'$id'] as String, {
            'status': 'sending',
            'generation': (row['generation'] as int) + 1,
            'attempts': (row['attempts'] as int) + 1,
            'proofHash': sha256.convert(utf8.encode(proof)).toString(),
            'leaseUntil': clock()
                .toUtc()
                .add(const Duration(seconds: 60))
                .toIso8601String(),
          }, transactionId: tx);
        });
        if (claim == null) continue;
        final execution = await wakeups!.schedule(
          dispatchId: claim[r'$id'] as String,
          proof: proof,
          at: _time(claim['runAt']),
        );
        await _workerTransaction((tx) async {
          final row = await store.get(
            'worker_dispatches',
            claim![r'$id'] as String,
            transactionId: tx,
          );
          if (row == null ||
              row['generation'] != claim['generation'] ||
              row['status'] != 'sending')
            return;
          await store.update('worker_dispatches', row[r'$id'] as String, {
            'status': 'scheduled',
            'executionId': execution,
            'leaseUntil': null,
            'errorCategory': null,
          }, transactionId: tx);
        });
        scheduled++;
      } catch (_) {
        if (claim == null) continue;
        try {
          await _workerTransaction((tx) async {
            final row = await store.get(
              'worker_dispatches',
              claim![r'$id'] as String,
              transactionId: tx,
            );
            if (row == null ||
                row['generation'] != claim['generation'] ||
                row['status'] != 'sending')
              return;
            final attempts = row['attempts'] as int;
            await store.update('worker_dispatches', row[r'$id'] as String, {
              'status': attempts >= 5 ? 'failed' : 'planned',
              'leaseUntil': null,
              'errorCategory': 'wakeup_unavailable',
              'nextAttemptAt': clock()
                  .toUtc()
                  .add(Duration(seconds: 1 << attempts))
                  .toIso8601String(),
            }, transactionId: tx);
          });
        } catch (_) {
          /* durable sending lease and hourly reconciliation recover */
        }
      }
    }
    return {'scheduled': scheduled, 'unavailable': false};
  }

  Future<Row> _dispatchWorker(String id, String proof) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(proof))
      throw const ServiceException('not_found', 404);
    final hash = sha256.convert(utf8.encode(proof)).toString();
    final claim = await _workerTransaction<Row?>((tx) async {
      final row = await store.get(
        'worker_dispatches',
        _validId(id),
        transactionId: tx,
      );
      if (row == null || row['proofHash'] != hash)
        throw const ServiceException('not_found', 404);
      if (row['status'] == 'delivered') return null;
      if (!{
            'sending',
            'scheduled',
            'running',
            'planned',
          }.contains(row['status']) ||
          (_time(row['runAt']).isAfter(clock().toUtc()) ||
              _time(row['nextAttemptAt']).isAfter(clock().toUtc())))
        throw const ServiceException('work_not_due', 409);
      if (row['status'] == 'running' &&
          _time(row['leaseUntil']).isAfter(clock().toUtc()))
        return null;
      return store.update('worker_dispatches', id, {
        'status': 'running',
        'leaseUntil': clock()
            .toUtc()
            .add(const Duration(seconds: 130))
            .toIso8601String(),
      }, transactionId: tx);
    });
    if (claim == null) return {'accepted': true, 'duplicate': true};
    var done = false;
    try {
      switch (claim['mode']) {
        case 'generation':
          await _runGeneration(claim['targetId'] as String);
        case 'reminder':
          await _executeReminder(claim['targetId'] as String);
        case 'reconcile':
          await _planEvent(claim['targetId'] as String);
        default:
          throw const ServiceException('invalid_request', 400);
      }
      done = true;
      if (claim['mode'] == 'generation') {
        final job = await store.get(
          'generation_jobs',
          claim['targetId'] as String,
        );
        // A full global provider lease pool does not consume an AI attempt, but
        // it must leave a wakeup pending rather than acknowledge lost work.
        if (job != null &&
            _activeGeneration(job) &&
            job['status'] == 'queued' &&
            job['nextAttemptAt'] == claim['runAt'])
          done = false;
      }
    } finally {
      // A handler exception keeps a planned wakeup. Domain state is separately
      // atomic; this delivery receipt can never turn a failed domain write green.
      await _workerTransaction((tx) async {
        final current = await store.get(
          'worker_dispatches',
          id,
          transactionId: tx,
        );
        if (current == null ||
            current['proofHash'] != hash ||
            current['status'] != 'running')
          return;
        await store.update('worker_dispatches', id, {
          'status': done
              ? 'delivered'
              : (current['attempts'] as int) >= 5
              ? 'failed'
              : 'planned',
          'leaseUntil': null,
          'completedAt': done ? _now() : null,
          if (!done) 'errorCategory': 'handler_failure',
          if (!done)
            'nextAttemptAt': clock()
                .toUtc()
                .add(const Duration(seconds: 30))
                .toIso8601String(),
        }, transactionId: tx);
      });
    }
    await _flushWakeups(10);
    return {'accepted': true, 'duplicate': false};
  }

  /// Hourly recovery never calls a provider in this execution. Each provider job
  /// is woken as a different execution of the same private Function.
  Future<Row> _reconcileWorker(int maximum) async {
    if (maximum < 1 || maximum > 100)
      throw ArgumentError('Recovery batch must be 1..100');
    final result = await _drainReminders(maximum);
    final now = clock().toUtc();
    final jobs = await _workerRows('generation_jobs', {}, null);
    for (final job in jobs.where(_activeGeneration).take(maximum)) {
      if (job['leaseUntil'] != null && _time(job['leaseUntil']).isAfter(now))
        continue;
      await _workerTransaction((tx) async {
        var at = _time(job['nextAttemptAt']);
        final id = _identity('d', [
          'generation',
          job[r'$id'] as String,
          at.toIso8601String(),
        ]);
        final prior = await store.get(
          'worker_dispatches',
          id,
          transactionId: tx,
        );
        if (prior != null &&
            {'delivered', 'failed'}.contains(prior['status'])) {
          // A fresh hourly recovery pass may attempt actual still-pending work;
          // each dispatch retains its own five-attempt audit trail.
          at = now;
        }
        await _queueDispatch(
          'generation',
          job[r'$id'] as String,
          job['appId'] as String,
          at,
          tx,
        );
      });
    }
    // Lost scheduled executions and crashed dispatch handlers recover without
    // requiring a new public request or a permanent credential.
    for (final dispatch in (await _workerRows(
      'worker_dispatches',
      {},
      null,
    )).take(1000)) {
      if ((dispatch['status'] == 'scheduled' &&
              now.isAfter(
                _time(dispatch['runAt']).add(const Duration(minutes: 5)),
              )) ||
          dispatch['status'] == 'running' &&
              !_time(dispatch['leaseUntil']).isAfter(now)) {
        await _workerTransaction((tx) async {
          final current = await store.get(
            'worker_dispatches',
            dispatch[r'$id'] as String,
            transactionId: tx,
          );
          if (current == null ||
              current['status'] != dispatch['status'] ||
              current['generation'] != dispatch['generation'])
            return;
          await store.update('worker_dispatches', current[r'$id'] as String, {
            'status': (current['attempts'] as int) >= 5 ? 'failed' : 'planned',
            'leaseUntil': null,
            'nextAttemptAt': _now(),
            'errorCategory': 'execution_unconfirmed',
          }, transactionId: tx);
        });
      }
    }
    return {...result, 'wakeups': await _flushWakeups(25)};
  }
}
