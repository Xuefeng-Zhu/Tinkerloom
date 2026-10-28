part of '../appnest_renderer.dart';

/// The host scopes this store to one backend, account and app. Preview supplies
/// an independent memory store and never receives the host's device store.
abstract class UtilityTimerStore {
  Future<Map<String, dynamic>?> read(String viewId);
  Future<void> write(String viewId, Map<String, dynamic> value);
}

class MemoryUtilityTimerStore implements UtilityTimerStore {
  final _values = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String viewId) async {
    final value = _values[viewId];
    return value == null ? null : Map.of(value);
  }

  @override
  Future<void> write(String viewId, Map<String, dynamic> value) async {
    _values[viewId] = Map.of(value);
  }
}

class UtilityTimerState {
  final String phase;
  final int durationSeconds, remainingMilliseconds;
  final DateTime? deadline;
  const UtilityTimerState({
    required this.phase,
    required this.durationSeconds,
    required this.remainingMilliseconds,
    this.deadline,
  });
  factory UtilityTimerState.ready(int minutes) {
    TimerOptions.fromJson({'durationMinutes': minutes});
    return UtilityTimerState(
      phase: 'ready',
      durationSeconds: minutes * 60,
      remainingMilliseconds: minutes * 60000,
    );
  }
  factory UtilityTimerState.fromJson(Map<String, dynamic> value) {
    final duration = value['durationSeconds'],
        remaining = value['remainingMilliseconds'];
    final phase = value['phase'];
    final rawDeadline = value['deadline'];
    final deadline = rawDeadline is String
        ? DateTime.tryParse(rawDeadline)
        : null;
    if (value['version'] != 1 ||
        duration is! int ||
        duration < 60 ||
        duration > 10800 ||
        remaining is! int ||
        remaining < 0 ||
        remaining > duration * 1000 ||
        !{'ready', 'running', 'paused', 'complete'}.contains(phase) ||
        (phase == 'running' && (deadline == null || !deadline.isUtc)) ||
        (phase != 'running' && rawDeadline != null) ||
        (phase == 'complete' && remaining != 0)) {
      throw const FormatException('Saved timer is invalid.');
    }
    return UtilityTimerState(
      phase: phase as String,
      durationSeconds: duration,
      remainingMilliseconds: remaining,
      deadline: deadline,
    );
  }
  int remainingAt(DateTime now) =>
      (phase == 'running'
              ? deadline!.difference(now).inMilliseconds
              : remainingMilliseconds)
          .clamp(0, durationSeconds * 1000);
  String phaseAt(DateTime now) =>
      phase == 'running' && remainingAt(now) == 0 ? 'complete' : phase;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'phase': phase,
    'durationSeconds': durationSeconds,
    'remainingMilliseconds': remainingMilliseconds,
    if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
  };
}

/// Deadline state lives beyond widget mounts. Writes are serialized per view,
/// committed before publishing a new state, and never depend on app shutdown.
class UtilityTimerController extends ChangeNotifier {
  final UtilityTimerStore store;
  final DateTime Function() now;
  final _states = <String, UtilityTimerState>{};
  final _loads = <String, Future<UtilityTimerState>>{};
  final _pending = <String, Future<void>>{};
  bool _disposed = false;
  UtilityTimerController({UtilityTimerStore? store, DateTime Function()? now})
    : store = store ?? MemoryUtilityTimerStore(),
      now = now ?? DateTime.now;
  UtilityTimerState? stateFor(String viewId) => _states[viewId];
  Future<UtilityTimerState> load(String viewId, {int durationMinutes = 25}) {
    if (_disposed)
      return Future.error(StateError('Timer controller is closed.'));
    if (_states[viewId] case final state?) return Future.value(state);
    if (_loads[viewId] case final pending?) return pending;
    final result = Completer<UtilityTimerState>();
    _loads[viewId] = result.future;
    unawaited(_read(viewId, durationMinutes, result));
    return result.future;
  }

  Future<void> _read(
    String viewId,
    int minutes,
    Completer<UtilityTimerState> result,
  ) async {
    try {
      final value = await store.read(viewId);
      final state = value == null
          ? UtilityTimerState.ready(minutes)
          : UtilityTimerState.fromJson(value);
      _states[viewId] = state;
      _loads.remove(viewId);
      result.complete(state);
    } catch (error, stack) {
      _loads.remove(viewId);
      result.completeError(error, stack);
    }
  }

  Future<void> _change(
    String viewId,
    int minutes,
    UtilityTimerState Function(UtilityTimerState state, DateTime now) change,
  ) => _enqueue(viewId, () async {
    final before = await load(viewId, durationMinutes: minutes);
    await _save(viewId, change(before, now().toUtc()));
  });

  Future<void> _save(String viewId, UtilityTimerState state) async {
    await store.write(viewId, state.toJson());
    _states[viewId] = state;
    if (!_disposed) notifyListeners();
  }

  Future<void> _enqueue(String viewId, Future<void> Function() operation) {
    final task = (_pending[viewId] ?? Future<void>.value()).then((_) async {
      if (_disposed) throw StateError('Timer controller is closed.');
      await operation();
    });
    // Keep the serialization chain usable after a failed operation, while the
    // caller retains the original failing future for a visible retry message.
    _pending[viewId] = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return task;
  }

  Future<void> start(String viewId, {int durationMinutes = 25}) =>
      _change(viewId, durationMinutes, (state, now) {
        if (state.phase != 'ready') return state;
        return UtilityTimerState(
          phase: 'running',
          durationSeconds: state.durationSeconds,
          remainingMilliseconds: state.remainingAt(now),
          deadline: now.add(Duration(milliseconds: state.remainingAt(now))),
        );
      });
  Future<void> pause(String viewId, {int durationMinutes = 25}) =>
      _change(viewId, durationMinutes, (state, now) {
        if (state.phase != 'running') return state;
        final remaining = state.remainingAt(now);
        return UtilityTimerState(
          phase: remaining == 0 ? 'complete' : 'paused',
          durationSeconds: state.durationSeconds,
          remainingMilliseconds: remaining,
        );
      });
  Future<void> resume(String viewId, {int durationMinutes = 25}) => _change(
    viewId,
    durationMinutes,
    (state, now) {
      if (state.phase != 'paused' || state.remainingAt(now) == 0) return state;
      return UtilityTimerState(
        phase: 'running',
        durationSeconds: state.durationSeconds,
        remainingMilliseconds: state.remainingAt(now),
        deadline: now.add(Duration(milliseconds: state.remainingAt(now))),
      );
    },
  );
  Future<void> reset(String viewId, {int durationMinutes = 25}) => _change(
    viewId,
    durationMinutes,
    (_, __) => UtilityTimerState.ready(durationMinutes),
  );

  /// Explicit user recovery for unreadable/corrupt state; never used as an
  /// automatic fallback. A failed write leaves the previous state untouched.
  Future<void> resetSaved(String viewId, {int durationMinutes = 25}) =>
      _enqueue(viewId, () async {
        final fresh = UtilityTimerState.ready(durationMinutes);
        final pendingLoad = _loads[viewId];
        if (pendingLoad != null) {
          try {
            await pendingLoad;
          } catch (_) {
            /* Explicitly replacing it. */
          }
        }
        await _save(viewId, fresh);
      });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
