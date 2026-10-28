import 'dart:async';

/// Runs independent model lanes fairly, with at most one task per lane active.
/// Returning false retries the same item on that lane's next turn. Exceptions
/// stop new tasks and propagate only after all already-started tasks drain.
Future<void> runNemotronModelLanes<T>(
  List<List<T>> lanes, {
  required int concurrency,
  required Future<bool> Function(T) execute,
  required bool Function() shouldStop,
}) async {
  if (concurrency < 1 || concurrency > 4) {
    throw ArgumentError.value(
      concurrency,
      'concurrency',
      'Must be 1 through 4',
    );
  }
  final positions = List<int>.filled(lanes.length, 0);
  final busy = List<bool>.filled(lanes.length, false);
  final active = <Future<void>>{};
  var cursor = 0;
  Object? firstError;
  StackTrace? firstStack;
  while (true) {
    while (active.length < concurrency && firstError == null && !shouldStop()) {
      int? selected;
      for (var offset = 0; offset < lanes.length; offset++) {
        final index = (cursor + offset) % lanes.length;
        if (!busy[index] && positions[index] < lanes[index].length) {
          selected = index;
          break;
        }
      }
      if (selected == null) break;
      final lane = selected;
      cursor = (lane + 1) % lanes.length;
      busy[lane] = true;
      late Future<void> task;
      task = Future<bool>.sync(() => execute(lanes[lane][positions[lane]]))
          .then<void>(
            (advance) {
              if (advance) positions[lane]++;
            },
            onError: (Object error, StackTrace stack) {
              firstError ??= error;
              firstStack ??= stack;
            },
          )
          .whenComplete(() {
            busy[lane] = false;
            active.remove(task);
          });
      active.add(task);
    }
    if (active.isEmpty) break;
    await Future.any(active);
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError!, firstStack!);
  }
}

/// FIFO gate; failures in one action do not poison later queued actions.
class NemotronAsyncGate {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) async {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    await previous;
    try {
      return await action();
    } finally {
      released.complete();
    }
  }
}
