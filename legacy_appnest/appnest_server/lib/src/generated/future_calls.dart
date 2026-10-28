/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: depend_on_referenced_packages

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _ida;
import 'package:clock/clock.dart' as _io0w16m8;
import 'package:serverpod/serverpod.dart' as _is;
import '../modules/automation/worker.dart' as _inz3cl7p;
import 'future_calls_generated_models/nest_worker_future_call_execute_model.dart'
    as _i2npzse7;
import 'future_calls_generated_models/nest_worker_future_call_generate_model.dart'
    as _i7d9xtt1;

/// Invokes a future call.
typedef _InvokeFutureCall =
    Future<void> Function(String name, _is.SerializableModel? object);

extension ServerpodFutureCallsGetter on _is.Serverpod {
  /// Generated future calls.
  FutureCalls get futureCalls => FutureCalls();
}

class FutureCalls extends _is.FutureCallDispatch<_FutureCallRef> {
  FutureCalls._();

  factory FutureCalls() {
    return _instance;
  }

  static final FutureCalls _instance = FutureCalls._();

  _is.FutureCallManager? _futureCallManager;

  String? _serverId;

  String get _effectiveServerId {
    if (_serverId == null) {
      throw StateError('FutureCalls is not initialized.');
    }
    return _serverId!;
  }

  _is.FutureCallManager get _effectiveFutureCallManager {
    if (_futureCallManager == null) {
      throw StateError('FutureCalls is not initialized.');
    }
    return _futureCallManager!;
  }

  @override
  void initialize(
    _is.FutureCallManager futureCallManager,
    String serverId,
  ) {
    var registeredFutureCalls = <String, _is.InvokableFutureCall>{
      'NestWorkerReconcileFutureCall': NestWorkerReconcileFutureCall(),
      'NestWorkerExecuteFutureCall': NestWorkerExecuteFutureCall(),
      'NestWorkerGenerateFutureCall': NestWorkerGenerateFutureCall(),
    };
    _futureCallManager = futureCallManager;
    _serverId = serverId;
    for (final entry in registeredFutureCalls.entries) {
      _futureCallManager?.registerFutureCall(entry.value, entry.key);
    }
  }

  @override
  _FutureCallRef callAtTime(
    DateTime time, {
    String? identifier,
  }) {
    return _FutureCallRef(
      (name, object) {
        return _effectiveFutureCallManager.scheduleFutureCall(
          name,
          object,
          time,
          _effectiveServerId,
          identifier,
        );
      },
    );
  }

  @override
  _FutureCallRef callWithDelay(
    Duration delay, {
    String? identifier,
  }) {
    return _FutureCallRef(
      (name, object) {
        return _effectiveFutureCallManager.scheduleFutureCall(
          name,
          object,
          DateTime.now().toUtc().add(delay),
          _effectiveServerId,
          identifier,
        );
      },
    );
  }

  @override
  _is.RecurringFutureCallDispatch<_FutureCallRef> callRecurring({
    String? identifier,
  }) {
    return _RecurringFutureCallDispatchImpl(
      _effectiveFutureCallManager,
      _effectiveServerId,
      identifier,
    );
  }

  @override
  Future<void> cancel(String identifier) async {
    await _effectiveFutureCallManager.cancelFutureCall(identifier);
  }
}

class _RecurringFutureCallDispatchImpl
    extends _is.RecurringFutureCallDispatch<_FutureCallRef> {
  _RecurringFutureCallDispatchImpl(
    this._futureCallManager,
    this._serverId,
    this._identifier,
  );

  final _is.FutureCallManager _futureCallManager;

  final String _serverId;

  final String? _identifier;

  @override
  _FutureCallRef cron(String cronExpression) {
    return _FutureCallRef(
      (name, object) {
        return _futureCallManager.scheduleFutureCall(
          name,
          object,
          _is.Cron.parse(cronExpression).nextTime(),
          _serverId,
          _identifier,
          scheduling: _is.CronFutureCallScheduling(cron: cronExpression),
        );
      },
    );
  }

  @override
  _FutureCallRef every(
    Duration interval, {
    DateTime? start,
  }) {
    final now = _io0w16m8.clock.now().toUtc();
    return _FutureCallRef(
      (name, object) {
        return _futureCallManager.scheduleFutureCall(
          name,
          object,
          start ?? now.add(interval),
          _serverId,
          _identifier,
          scheduling: _is.IntervalFutureCallScheduling(
            interval: interval,
            start: start,
          ),
        );
      },
    );
  }
}

class _FutureCallRef {
  _FutureCallRef(this._invokeFutureCall);

  final _InvokeFutureCall _invokeFutureCall;

  late final nestWorker = _NestWorkerFutureCallDispatcher(_invokeFutureCall);
}

class _NestWorkerFutureCallDispatcher {
  _NestWorkerFutureCallDispatcher(this._invokeFutureCall);

  final _InvokeFutureCall _invokeFutureCall;

  Future<void> reconcile() {
    return _invokeFutureCall(
      'NestWorkerReconcileFutureCall',
      null,
    );
  }

  Future<void> execute(int runId) {
    var object = _i2npzse7.NestWorkerFutureCallExecuteModel(runId: runId);
    return _invokeFutureCall(
      'NestWorkerExecuteFutureCall',
      object,
    );
  }

  Future<void> generate(int jobId) {
    var object = _i7d9xtt1.NestWorkerFutureCallGenerateModel(jobId: jobId);
    return _invokeFutureCall(
      'NestWorkerGenerateFutureCall',
      object,
    );
  }
}

class NestWorkerReconcileFutureCall extends _is.FutureCall
    implements _is.InvokableFutureCall {
  @override
  _ida.Future<void> invoke(
    _is.Session session,
    _is.SerializableModel? object,
  ) async {
    await _inz3cl7p.NestWorkerFutureCall().reconcile(session);
  }
}

class NestWorkerExecuteFutureCall
    extends _is.FutureCall<_i2npzse7.NestWorkerFutureCallExecuteModel>
    implements
        _is.InvokableFutureCall<_i2npzse7.NestWorkerFutureCallExecuteModel> {
  @override
  _ida.Future<void> invoke(
    _is.Session session,
    _i2npzse7.NestWorkerFutureCallExecuteModel? object,
  ) async {
    if (object != null) {
      await _inz3cl7p.NestWorkerFutureCall().execute(
        session,
        object.runId,
      );
    }
  }
}

class NestWorkerGenerateFutureCall
    extends _is.FutureCall<_i7d9xtt1.NestWorkerFutureCallGenerateModel>
    implements
        _is.InvokableFutureCall<_i7d9xtt1.NestWorkerFutureCallGenerateModel> {
  @override
  _ida.Future<void> invoke(
    _is.Session session,
    _i7d9xtt1.NestWorkerFutureCallGenerateModel? object,
  ) async {
    if (object != null) {
      await _inz3cl7p.NestWorkerFutureCall().generate(
        session,
        object.jobId,
      );
    }
  }
}
