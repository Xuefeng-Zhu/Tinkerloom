import 'dart:convert';

import 'package:appnest_flutter/features/mini_app/device_timer_store.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> disk;
  DeviceTimerStore store({
    String server = 'http://localhost:8180/',
    String actor = 'alice',
    int app = 7,
  }) => DeviceTimerStore.withStorage(
    server: server,
    actorId: actor,
    appId: app,
    readString: (key) async => disk[key],
    writeString: (key, value) async => disk[key] = value,
  );

  setUp(() => disk = {});

  test(
    'countdown survives controller replacement and expires while away',
    () async {
      var now = DateTime.utc(2026, 9, 23, 12);
      final first = UtilityTimerController(store: store(), now: () => now);
      await first.start('focus', durationMinutes: 25);
      first.dispose();
      now = now.add(const Duration(minutes: 10));
      final reopened = UtilityTimerController(store: store(), now: () => now);
      final restored = await reopened.load('focus', durationMinutes: 40);
      expect(
        restored.remainingAt(now),
        const Duration(minutes: 15).inMilliseconds,
      );
      expect(restored.durationSeconds, 25 * 60);
      await reopened.pause('focus');
      reopened.dispose();
      now = now.add(const Duration(hours: 1));
      final paused = UtilityTimerController(store: store(), now: () => now);
      expect((await paused.load('focus')).remainingAt(now), 15 * 60000);
      await paused.resume('focus');
      paused.dispose();
      now = now.add(const Duration(minutes: 16));
      final expired = UtilityTimerController(store: store(), now: () => now);
      expect((await expired.load('focus')).phaseAt(now), 'complete');
      await expired.reset('focus', durationMinutes: 40);
      expect(expired.stateFor('focus')!.remainingAt(now), 40 * 60000);
      expired.dispose();
    },
  );

  test(
    'reopening restores only the matching account, app and component',
    () async {
      final state = <String, dynamic>{
        'status': 'running',
        'deadline': DateTime.utc(2026, 9, 23, 12, 25).toIso8601String(),
      };
      await store().write('focus', state);
      expect(await store().read('focus'), state);
      expect(await store(actor: 'bob').read('focus'), isNull);
      expect(await store(app: 8).read('focus'), isNull);
      expect(await store().read('breakTimer'), isNull);
      expect(
        await store(server: 'https://example.test/').read('focus'),
        isNull,
      );
      expect(await store(server: 'http://localhost:8180').read('focus'), state);
    },
  );

  test(
    'encoded scopes cannot collide through delimiter-like account names',
    () async {
      await store(actor: 'alice.7.focus').write('focus', {'remaining': 100});
      expect(await store(actor: 'alice').read('focus'), isNull);
      await store(actor: 'alice').write('focus', {'remaining': 200});
      expect(disk.length, 2);
      expect(await store(actor: 'alice.7.focus').read('focus'), {
        'remaining': 100,
      });
    },
  );

  test('malformed persisted data is reported without erasing it', () async {
    await store().write('focus', {'remaining': 60});
    final key = disk.keys.single;
    for (final value in ['not JSON', '[]', 'null', jsonEncode('x' * 2100)]) {
      disk[key] = value;
      await expectLater(store().read('focus'), throwsFormatException);
      expect(disk[key], value);
    }
  });

  test(
    'storage failures propagate instead of claiming successful persistence',
    () async {
      final failing = DeviceTimerStore.withStorage(
        server: 'http://localhost:8180/',
        actorId: 'alice',
        appId: 7,
        readString: (_) => Future.error(StateError('unavailable')),
        writeString: (_, value) => Future.error(StateError('full')),
      );
      await expectLater(failing.read('focus'), throwsStateError);
      await expectLater(failing.write('focus', {}), throwsStateError);
    },
  );

  test('missing identity or invalid backend cannot create a shared scope', () {
    expect(() => store(actor: ''), throwsArgumentError);
    expect(() => store(app: 0), throwsArgumentError);
    expect(() => store(server: 'file:///tmp'), throwsArgumentError);
  });
}
