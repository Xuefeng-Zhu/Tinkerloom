import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores utility state on this device only. The backend, account and app are
/// part of every key, so switching accounts or servers cannot restore another
/// user's countdown. App records and credentials never enter this store.
class DeviceTimerStore implements UtilityTimerStore {
  final String _prefix;
  final Future<String?> Function(String key) readString;
  final Future<void> Function(String key, String value) writeString;

  factory DeviceTimerStore({
    required String server,
    required String actorId,
    required int appId,
    SharedPreferencesAsync? preferences,
  }) {
    final storage = preferences ?? SharedPreferencesAsync();
    return DeviceTimerStore.withStorage(
      server: server,
      actorId: actorId,
      appId: appId,
      readString: storage.getString,
      writeString: storage.setString,
    );
  }

  DeviceTimerStore.withStorage({
    required String server,
    required String actorId,
    required int appId,
    required this.readString,
    required this.writeString,
  }) : _prefix = _scope(server, actorId, appId);

  static String _scope(String server, String actorId, int appId) {
    if (actorId.isEmpty || appId <= 0) {
      throw ArgumentError('A signed-in account and app are required.');
    }
    final uri = Uri.parse(server);
    if (!uri.hasAuthority || !{'http', 'https'}.contains(uri.scheme)) {
      throw ArgumentError('A valid AppNest server is required.');
    }
    final backend = uri
        .replace(
          path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
          query: '',
          fragment: '',
        )
        .toString();
    final encoded = base64Url.encode(
      utf8.encode(
        jsonEncode([
          backend,
          actorId,
          appId,
        ]),
      ),
    );
    return 'appnest.timer.v1.$encoded.';
  }

  String _key(String viewId) {
    return '$_prefix${stableId(viewId)}';
  }

  @override
  Future<Map<String, dynamic>?> read(String viewId) async {
    final value = await readString(_key(viewId));
    if (value == null) return null;
    // Surface corrupt state instead of silently restarting a running timer.
    if (value.length > 2048) {
      throw const FormatException('Stored timer state is invalid.');
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Stored timer state is invalid.');
    }
    return decoded;
  }

  @override
  Future<void> write(String viewId, Map<String, dynamic> state) =>
      writeString(_key(viewId), jsonEncode(state));
}
