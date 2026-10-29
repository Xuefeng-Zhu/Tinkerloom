// Synthetic actor and Functions envelope only; actual PlatformService/REST/store.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'file:///Users/frank/mygit/Tinkerloom/appwrite_backend/lib/service.dart';
import 'file:///Users/frank/mygit/Tinkerloom/appwrite_backend/test/confirmed_abort_test.dart' as fixtures;

Future<void> main() async {
  final f = await fixtures.LocalDatabase.create();
  await f.setup();
  await f.service.execute('alice', await fixtures.publicationCommand(f));
  final outer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final calls = <Row>[];
  Row stats() => {
    'calls': calls,
    'failedTransactions': f.states.values.where((s) => s == 'failed').length,
    'business': { for (final table in ['receipts', 'audit', 'outbox', 'spec_records', 'spec_cells', 'spec_versions']) table: f.memory.rows[table]?.length ?? 0 },
  };
  outer.listen((http) async {
    try {
      if (http.method != 'POST' || http.uri.path != '/v1/functions/core/executions') throw const FormatException();
      final envelope = jsonDecode(await utf8.decoder.bind(http).join()) as Row;
      final input = jsonDecode(envelope['body'] as String) as Row;
      calls.add(Map<String, dynamic>.from(input));
      Object data;
      int status;
      try { data = await f.service.execute('alice', input); status = 200; }
      on ServiceException catch (e) { data = {'error': e.code}; status = e.status; }
      http.response.headers.contentType = ContentType.json;
      http.response.statusCode = 201;
      http.response.write(jsonEncode({'status': 'completed', 'responseStatusCode': status, 'responseBody': jsonEncode(data)}));
    } catch (_) { http.response.statusCode = 500; http.response.write('{}'); }
    await http.response.close();
  });
  stdout.writeln(jsonEncode({'ready': true, 'endpoint': 'http://127.0.0.1:${outer.port}/v1', 'app': (await f.service.execute('alice', {'op': 'spec.getApp', 'appId': 'app-one'}))['app']}));
  final done = Completer<void>();
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) async {
    final command = jsonDecode(line) as Row;
    Object? data;
    try {
      switch (command['action']) {
        case 'arm': f.memory.arm(); data = true;
        case 'paused': await f.memory.paused!.future.timeout(const Duration(seconds: 10)); data = true;
        case 'release': f.memory.resume!.complete(); data = true;
        case 'stats': data = stats();
        case 'close': data = true; if (!done.isCompleted) done.complete();
        default: throw const FormatException();
      }
      stdout.writeln(jsonEncode({'id': command['id'], 'data': data}));
    } catch (e) { stdout.writeln(jsonEncode({'id': command['id'], 'error': e.runtimeType.toString()})); }
  }, onDone: () { if (!done.isCompleted) done.complete(); });
  await done.future;
  await outer.close(force: true);
  await f.close();
}
