import 'dart:async';

/// Polls without an async-generator cancellation gap or overlapping reads.
/// Every heartbeat invokes [readRevision], including unchanged revisions.
class RevisionEvents {
  final Future<int> Function() readRevision;
  final Duration interval;
  final void Function()? onStop;
  late final StreamController<int> _controller;
  Timer? _timer;
  var _stopped = false, _paused = false, _reading = false;
  int? _revision;

  RevisionEvents(
    this.readRevision, {
    this.interval = const Duration(seconds: 2),
    this.onStop,
  }) {
    _controller = StreamController<int>(
      onListen: _poll,
      onCancel: stop,
      onPause: () {
        _paused = true;
        _timer?.cancel();
      },
      onResume: () {
        _paused = false;
        _poll();
      },
    );
  }

  Stream<int> get stream => _controller.stream;

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    onStop?.call();
    // A paused subscriber must never hold session closure open.
    unawaited(_controller.close());
  }

  Future<void> _poll() async {
    if (_stopped || _paused || _reading) return;
    _reading = true;
    try {
      final revision = await readRevision();
      if (!_stopped && !_paused && revision != _revision) {
        _revision = revision;
        _controller.add(revision);
      }
    } catch (error, stack) {
      if (!_stopped) {
        _controller.addError(error, stack);
        stop();
      }
    } finally {
      _reading = false;
      if (!_stopped && !_paused) _timer = Timer(interval, _poll);
    }
  }
}
