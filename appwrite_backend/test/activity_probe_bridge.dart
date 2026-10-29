// Test-only stdio bridge. Never an HTTP endpoint or production authentication path.
import 'dart:convert';
import 'dart:io';
import '../lib/service.dart';
import 'memory_store.dart';

Future<void> main() async {
  final service = PlatformService(
    MemoryStore(),
    clock: () => DateTime.utc(2030, 1, 2),
    // The activity probe must not assume irrelevant reminder flags are off.
    remindersEnabled: true,
  );
  await service.execute('usr-owner', {
    'op': 'createWorkspace',
    'id': 'preflight-ws',
    'name': 'Synthetic preflight',
  });
  await service.execute('usr-owner', {
    'op': 'spec.createApp',
    'id': 'preflight-app',
    'workspaceId': 'preflight-ws',
    'name': 'Synthetic preflight',
    'operationId': 'preflight-create',
  });
  stdout.writeln(
    jsonEncode({'ready': true, 'proof': 'synthetic_local_service'}),
  );
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    try {
      if (line.length > 65536) throw const FormatException();
      final envelope = jsonDecode(line) as Map<String, dynamic>;
      final response = await service.execute(
        envelope['actor'] as String,
        Map<String, dynamic>.from(envelope['input'] as Map),
      );
      stdout.writeln(jsonEncode({'status': 200, 'data': response}));
    } on ServiceException catch (error) {
      stdout.writeln(
        jsonEncode({
          'status': error.status,
          'data': {'error': error.code},
        }),
      );
    } catch (_) {
      stdout.writeln(
        jsonEncode({
          'status': 500,
          'data': {'error': 'offline_bridge_failure'},
        }),
      );
    }
  }
}
