// Test-only stdio adapter. Real service/sanitizer, simulated rows/files. No HTTP,
// credentials, production adapters, provider calls or live-worker claims.
import 'dart:convert';
import 'dart:io';
import '../lib/service.dart';
import 'memory_store.dart';
import 'media_check.dart' as media;

Future<void> main() async {
  final store = MemoryStore(), files = media.Files();
  final service = PlatformService(store, media: files);
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    try {
      final request = jsonDecode(line) as Row, input = request['input'] as Row;
      if (input['op'] == 'spec.media.status') {
        final asset = await store.get(
          'media_assets',
          input['assetId'] as String,
        );
        if (asset?['status'] == 'queued')
          await service.processMedia(input['assetId'] as String);
      }
      final data = await service.execute(request['actor'] as String, input);
      stdout.writeln(jsonEncode({'status': 200, 'data': data}));
    } on ServiceException catch (e) {
      stdout.writeln(
        jsonEncode({
          'status': e.status,
          'data': {'error': e.code},
        }),
      );
    } catch (_) {
      stdout.writeln('{"status":500,"data":{"error":"bridge_failure"}}');
    }
  }
}
