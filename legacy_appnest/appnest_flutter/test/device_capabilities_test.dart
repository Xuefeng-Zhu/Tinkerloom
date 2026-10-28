import 'dart:async';
import 'dart:convert';

import 'package:appnest_flutter/features/mini_app/device_capabilities.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class NativeFake {
  final calls = <String>[];
  final storage = <String, String>{};
  final updates = StreamController<Object?>.broadcast();
  Set<String> grants = {};
  String? session;
  bool light = false, failWrite = false;
  Completer<void>? gate;
  String? failure;
  Future<Object?> invoke(String method, Map<String, Object?> args) async {
    calls.add(method);
    if (method == 'configure') {
      await gate?.future;
      session = args['session'] as String;
      grants = Set<String>.from(args['grants'] as List);
      if (!grants.contains('flashlight')) light = false;
    }
    if (method == 'release' && session == args['session']) {
      session = null;
      light = false;
      grants = {};
    }
    if (method == 'command') {
      if (failure != null) throw PlatformException(code: failure!);
      if (args['control'] == 'flashlight') light = args['value'] == true;
    }
    if (method == 'query') {
      return {
        // Deliberately over-return to check the Dart boundary also filters readings.
        'values': {
          'batteryLevel': 82,
          'model': 'Test phone',
          'flashlight': light,
          'serialNumber': 'MUST_NOT_SURFACE',
        },
        'availability': {'flashlight': 'available'},
      };
    }
    return null;
  }

  PhoneDeviceCapabilities adapter({
    String actor = 'owner',
    int app = 1,
    String server = 'https://appnest.example/',
    bool mobile = true,
    AppSpec? spec,
  }) => PhoneDeviceCapabilities(
    server: server,
    actorId: actor,
    appId: app,
    spec: spec ?? phoneToolkitTemplate(),
    mobile: mobile,
    read: (key) async => storage[key],
    write: (key, value) async {
      if (failWrite) throw StateError('storage failed');
      storage[key] = value;
    },
    invoke: invoke,
    updates: updates.stream,
  );
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'no data or actions before per-app access; only granted fields surface',
    () async {
      final native = NativeFake();
      final adapter = native.adapter();
      adapter.attach();
      await settle();
      expect(adapter.values, isEmpty);
      await adapter.command('flashlight', true);
      expect(native.calls.where((c) => c == 'command'), isEmpty);
      await adapter.setGrant('battery', true);
      expect(adapter.values, {'batteryLevel': 82});
      await adapter.setGrant('flashlight', true);
      await adapter.command('flashlight', true);
      expect(native.light, isTrue);
      expect(adapter.values.containsKey('serialNumber'), isFalse);
      expect(native.storage.values.single, isNot(contains('82')));
      adapter.dispose();
      await settle();
      expect(native.light, isFalse);
      await native.updates.close();
    },
  );
  test('grants persist only for same backend account and app', () async {
    final native = NativeFake();
    var adapter = native.adapter();
    adapter.attach();
    await settle();
    await adapter.setGrant('battery', true);
    adapter.dispose();
    await settle();
    adapter = native.adapter();
    adapter.attach();
    await settle();
    expect(adapter.granted, {'battery'});
    adapter.dispose();
    await settle();
    for (final other in [
      native.adapter(actor: 'other'),
      native.adapter(app: 2),
      native.adapter(server: 'https://other.example'),
    ]) {
      other.attach();
      await settle();
      expect(other.granted, isEmpty);
      other.dispose();
      await settle();
    }
    await native.updates.close();
  });
  test(
    'revocation cleans hardware before persistence and clears queried values',
    () async {
      final native = NativeFake();
      final device = native.adapter();
      device.attach();
      await settle();
      await device.setGrant('flashlight', true);
      await device.command('flashlight', true);
      native.failWrite = true;
      await device.setGrant('flashlight', false);
      expect(native.light, isFalse);
      expect(device.granted, isEmpty);
      expect(device.error, isNotNull);
      device.dispose();
      await settle();
      await native.updates.close();
    },
  );
  test('leaving during configure prevents queued command and releases native session', () async {
    final native = NativeFake();
    final device = native.adapter();
    device.attach();
    await settle();
    await device.setGrant('flashlight', true);
    native.gate = Completer<void>();
    final command = device.command('flashlight', true);
    await settle();
    await device.setPaused(true);
    native.gate!.complete();
    await command;
    expect(native.calls.where((c) => c == 'command'), isEmpty);
    expect(native.session, isNull);
    device.dispose();
    await native.updates.close();
  });
  test('permission denial and unavailable hardware are honest, commands never auto-retry', () async {
    final native = NativeFake();
    final device = native.adapter();
    device.attach();
    await settle();
    await device.setGrant('flashlight', true);
    native.failure = 'permissionDenied';
    await device.command('flashlight', true);
    expect(device.error, contains('Permission denied'));
    expect(native.light, isFalse);
    await device.refresh();
    expect(native.calls.where((c) => c == 'command').length, 1);
    native.failure = 'unavailable';
    await device.command('flashlight', true);
    expect(device.error, contains('unavailable'));
    device.dispose();
    await settle();
    await native.updates.close();
  });
  test('web and desktop never invoke native channels', () async {
    final native = NativeFake();
    final device = native.adapter(mobile: false);
    device.attach();
    await settle();
    await device.refresh();
    await device.setGrant('battery', true);
    await device.command('flashlight', true);
    device.dispose();
    await settle();
    expect(native.calls, isEmpty);
    await native.updates.close();
  });
  test('new capability stays off, corrupt consent fails closed', () async {
    final native = NativeFake();
    final device = native.adapter();
    device.attach();
    await settle();
    await device.setGrant('battery', true);
    device.dispose();
    await settle();
    final reopened = native.adapter();
    reopened.attach();
    await settle();
    expect(reopened.granted, {'battery'});
    reopened.dispose();
    await settle();
    native.storage.updateAll((_, value) => jsonEncode(['arbitraryCode']));
    final corrupt = native.adapter();
    corrupt.attach();
    await settle();
    expect(corrupt.granted, isEmpty);
    expect(corrupt.error, isNotNull);
    await corrupt.resetGrants();
    expect(corrupt.error, isNull);
    expect(corrupt.granted, isEmpty);
    corrupt.dispose();
    await settle();
    await native.updates.close();
  });
  test('background and last component removal release controls', () async {
    final native = NativeFake();
    final device = native.adapter();
    device.attach();
    device.attach();
    await settle();
    await device.setGrant('flashlight', true);
    await device.command('flashlight', true);
    device.detach();
    await settle();
    expect(native.light, isTrue);
    device.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();
    expect(native.light, isFalse);
    device.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle();
    expect(native.light, isFalse);
    await device.command('flashlight', true);
    device.detach();
    await settle();
    expect(native.light, isFalse);
    device.dispose();
    await native.updates.close();
  });
}
