import 'dart:async';

import 'package:appnest_server/src/modules/runtime/revision_events.dart';
import 'package:test/test.dart';

void main() {
  const interval = Duration(milliseconds: 5);
  test(
    'idle cancellation finishes immediately and stops heartbeat reads',
    () async {
      var reads = 0;
      final polled = Completer<void>();
      final events = RevisionEvents(() async {
        if (++reads == 3) polled.complete();
        return 7;
      }, interval: interval);
      final values = <int>[];
      final sub = events.stream.listen(values.add);
      await polled.future.timeout(const Duration(seconds: 2));
      await sub.cancel().timeout(const Duration(milliseconds: 100));
      final count = reads;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reads, count);
      expect(values, [7]);
    },
  );
  test(
    'cancel during a pending read discards it without scheduling another',
    () async {
      var reads = 0;
      final pending = Completer<int>();
      final events = RevisionEvents(() {
        reads++;
        return pending.future;
      }, interval: interval);
      final values = <int>[];
      final sub = events.stream.listen(values.add);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel().timeout(const Duration(milliseconds: 100));
      pending.complete(8);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reads, 1);
      expect(values, isEmpty);
    },
  );
  test('session-close stop never waits for a paused subscriber', () async {
    var reads = 0, stops = 0;
    final started = Completer<void>();
    final events = RevisionEvents(
      () async {
        reads++;
        if (!started.isCompleted) started.complete();
        return 7;
      },
      interval: interval,
      onStop: () => stops++,
    );
    final sub = events.stream.listen((_) {});
    await started.future;
    sub.pause();
    events.stop();
    events.stop();
    final count = reads;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(reads, count);
    expect(stops, 1);
    sub.resume();
    await sub.cancel();
  });
  test(
    'unchanged heartbeat still checks grants and access failure terminates',
    () async {
      var reads = 0;
      final events = RevisionEvents(() async {
        if (++reads == 3) throw StateError('revoked');
        return 7;
      }, interval: interval);
      await expectLater(
        events.stream,
        emitsInOrder([7, emitsError(isA<StateError>()), emitsDone]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reads, 3);
    },
  );
  test('slow reads never overlap and resumed subscriptions refresh', () async {
    var active = 0, peak = 0, revision = 1;
    final received = Completer<void>();
    final events = RevisionEvents(() async {
      active++;
      if (active > peak) peak = active;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      active--;
      return revision;
    }, interval: interval);
    final sub = events.stream.listen((n) {
      if (n == 2) received.complete();
    });
    await Future<void>.delayed(const Duration(milliseconds: 15));
    sub.pause();
    revision = 2;
    sub.resume();
    await received.future.timeout(const Duration(seconds: 2));
    await sub.cancel();
    expect(peak, 1);
  });
}
