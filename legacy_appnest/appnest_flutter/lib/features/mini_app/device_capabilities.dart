import 'dart:async';
import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device values never cross the backend boundary. Only local consent is saved.
class PhoneDeviceCapabilities extends DeviceCapabilitiesAdapter
    with WidgetsBindingObserver {
  static const channel = MethodChannel('appnest/device');
  static const events = EventChannel('appnest/device/events');
  static int _sequence = 0;
  final String _session =
      '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
  final String _key;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final Future<Object?> Function(String, Map<String, Object?>) _invoke;
  final Stream<Object?> _events;
  @override
  final Set<String> requested;
  @override
  final bool supported;
  final _grants = <String>{};
  Map<String, dynamic> _values = {};
  Map<String, String> _availability = {};
  String? _error;
  bool _busy = false, _loaded = false, _disposed = false, _paused = false;
  bool _foreground = true;
  int _references = 0, _epoch = 0;
  Future<void> _tail = Future.value();
  StreamSubscription<Object?>? _subscription;
  PhoneDeviceCapabilities({
    required String server,
    required String actorId,
    required int appId,
    required AppSpec spec,
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
    Future<Object?> Function(String, Map<String, Object?>)? invoke,
    Stream<Object?>? updates,
    bool? mobile,
  }) : requested = Set.unmodifiable(requestedDeviceCapabilities(spec)),
       supported =
           mobile ??
           (!kIsWeb &&
               {
                 TargetPlatform.android,
                 TargetPlatform.iOS,
               }.contains(defaultTargetPlatform)),
       _key = _scope(server, actorId, appId),
       _read = read ?? SharedPreferencesAsync().getString,
       _write = write ?? SharedPreferencesAsync().setString,
       _invoke =
           invoke ??
           ((method, args) => channel.invokeMethod<Object?>(method, args)),
       _events = updates ?? events.receiveBroadcastStream() {
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }
  static String _scope(String server, String actor, int app) {
    final uri = Uri.parse(server);
    if (actor.isEmpty ||
        app <= 0 ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme)) {
      throw ArgumentError('Device access requires a signed-in app scope');
    }
    final backend = uri
        .replace(
          path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
          query: '',
          fragment: '',
        )
        .toString();
    return 'appnest.device.v1.${hashJson({'backend': backend, 'actor': actor, 'app': app})}';
  }

  @override
  Set<String> get granted => Set.unmodifiable(_grants);
  @override
  Map<String, dynamic> get values => Map.unmodifiable(_values);
  @override
  Map<String, String> get availability => Map.unmodifiable(_availability);
  @override
  String? get error => _error;
  @override
  bool get busy => _busy;
  bool get _active =>
      supported && !_disposed && !_paused && _foreground && _references > 0;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void attach() {
    _references++;
    // Widgets attach during build; never notify synchronously here.
    scheduleMicrotask(() {
      if (_active) refresh();
    });
  }

  @override
  void detach() {
    if (_references > 0) _references--;
    scheduleMicrotask(() {
      if (_references == 0) _release();
    });
  }

  Future<void> _load() async {
    if (_loaded) return;
    final encoded = await _read(_key);
    if (_disposed) return;
    if (encoded != null) {
      final decoded = jsonDecode(encoded);
      if (decoded is! List ||
          decoded.any(
            (e) => e is! String || !deviceCapabilityLabels.containsKey(e),
          )) {
        throw const FormatException('Invalid device access preferences');
      }
      _grants.addAll(decoded.cast<String>().where(requested.contains));
    }
    _loaded = true;
  }

  Future<void> _run(
    Future<void> Function(int epoch) action, {
    bool load = true,
  }) {
    if (!_active || _busy) return Future.value();
    final epoch = _epoch;
    _busy = true;
    _error = null;
    _notify();
    final result = _tail.then((_) async {
      try {
        if (load) await _load();
        if (!_active || epoch != _epoch) return;
        await action(epoch);
      } catch (e) {
        if (epoch == _epoch && !_disposed) {
          _error = switch (e) {
            PlatformException(code: 'permissionDenied') => 'Permission denied. Retry or enable camera access in AppNest system settings to use the flashlight.',
            PlatformException(code: 'unavailable') =>
              'This feature is unavailable or in use. Try again.',
            PlatformException(code: 'inactive') =>
              'Return to this mini-app and try again.',
            MissingPluginException() =>
              'Device features are unavailable in this build.',
            _ => 'Could not complete the device request. Try again.',
          };
        }
      } finally {
        if (!_active || epoch != _epoch) {
          try {
            await _invoke('release', {'session': _session});
          } catch (_) {}
        }
        _busy = false;
        _notify();
        if (_active && epoch != _epoch) scheduleMicrotask(refresh);
      }
    });
    _tail = result;
    return result;
  }

  Future<void> _configure() async {
    await _invoke('configure', {
      'session': _session,
      'grants': _grants.toList(),
    });
  }

  Future<void> _query(int epoch) async {
    if (!_active || epoch != _epoch) return;
    final raw = await _invoke('query', {'session': _session});
    if (!_active || epoch != _epoch || raw is! Map) return;
    final values = Map<String, dynamic>.from(raw['values'] as Map? ?? {});
    // Filter again on the Flutter side: no ungranted values enter the UI.
    _values = {
      for (final e in values.entries)
        if ((deviceInfoFields.containsKey(e.key) &&
                _grants.contains(deviceFieldCapability(e.key))) ||
            (deviceControlLabels.containsKey(e.key) && _grants.contains(e.key)))
          e.key: e.value,
    };
    _availability = Map<String, String>.from(raw['availability'] as Map? ?? {});
  }

  @override
  Future<void> refresh() => _run((epoch) async {
    await _configure();
    if (!_active || epoch != _epoch) {
      await _invoke('release', {'session': _session});
      return;
    }
    _subscription ??= _events.listen(
      (_) {
        if (_active) refresh();
      },
      onError: (Object _) {
        if (_active) {
          _error = 'Live device updates are unavailable. Use Refresh.';
          _notify();
        }
      },
    );
    await _query(epoch);
  });
  @override
  Future<void> setGrant(String capability, bool enabled) => _run((epoch) async {
    if (!requested.contains(capability)) return;
    final next = {..._grants};
    enabled ? next.add(capability) : next.remove(capability);
    // Revoke locally/native first, so a storage error cannot leave a control on.
    if (!enabled) {
      _grants.remove(capability);
      _values.removeWhere(
        (key, _) => deviceInfoFields.containsKey(key)
            ? deviceFieldCapability(key) == capability
            : key == capability,
      );
      await _configure();
    }
    await _write(_key, jsonEncode(next.toList()..sort()));
    if (!_active || epoch != _epoch) {
      _loaded = false;
      return;
    }
    _grants
      ..clear()
      ..addAll(next);
    await _configure();
    await _query(epoch);
  });
  @override
  Future<void> command(String control, Object? value) => _run((epoch) async {
    if (!deviceControlLabels.containsKey(control) ||
        !_grants.contains(control)) {
      return;
    }
    if ((control == 'flashlight' || control == 'keepAwake') && value is! bool) {
      return;
    }
    if (control == 'brightness' &&
        value != null &&
        (value is! num || !value.isFinite || value < 0 || value > 1)) {
      return;
    }
    await _configure();
    if (!_active || epoch != _epoch) {
      await _invoke('release', {'session': _session});
      return;
    }
    await _invoke('command', {
      'session': _session,
      'control': control,
      'value': value,
    });
    await _query(epoch);
  });
  @override
  Future<void> resetGrants() => _run((epoch) async {
    _grants.clear();
    _values.clear();
    await _configure();
    await _write(_key, '[]');
    _loaded = true;
    await _query(epoch);
  }, load: false);

  @override
  Future<void> openSettings() => _run((_) async {
    await _invoke('settings', {'session': _session});
  });
  Future<void> setPaused(bool paused) async {
    _paused = paused;
    if (paused) {
      await _release();
    } else if (_active) {
      await refresh();
    }
  }

  Future<void> _release() async {
    _epoch++;
    _values = {};
    await _subscription?.cancel();
    _subscription = null;
    if (supported) {
      try {
        await _invoke('release', {'session': _session});
      } catch (_) {
        /* Native lifecycle also releases controls. */
      }
    }
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      unawaited(_release());
    } else {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_release());
    super.dispose();
  }
}
