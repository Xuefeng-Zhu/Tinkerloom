// Synthetic actor/Functions envelope; actual service, REST DB adapter and optimistic store.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'file:///Users/frank/mygit/Tinkerloom/appwrite_backend/lib/service.dart';
import 'file:///Users/frank/mygit/Tinkerloom/appwrite_backend/test/confirmed_abort_test.dart'
    as fixtures;
import 'file:///Users/frank/mygit/Tinkerloom/appwrite_backend/test/media_check.dart'
    as media;

Future<void> main() async {
  final fixture = media.Fixture(memory: fixtures.CloudStore());
  final store = fixture.store as fixtures.CloudStore;
  await fixture.setup();
  final first = await fixture.ready('first-media', media.png()),
      second = await fixture.ready('second-media', media.png());
  final db = fixtures.LocalDatabase(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    store,
  );
  final api = PlatformService(
    db.rest,
    media: fixture.files,
    clock: () => fixture.now,
  );
  final app =
      (await api.execute('alice', {'op': 'spec.getApp', 'appId': 'app'}))['app']
          as Row;
  final version = app['version'] as Row, spec = version['spec'] as Row;
  final collection = ((spec['collections'] as List).first as Row)['id'];
  final calls = <Row>[], results = <Row>[];
  var active = 0, maximum = 0;
  String digest(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
  Row stats() => {
    'calls': calls,
    'results': results,
    'active': active,
    'maximumConcurrentSDK': maximum,
    'failedTransactions': db.states.values.where((v) => v == 'failed').length,
    'businessCounts': {
      for (final table in [
        'receipts',
        'audit',
        'outbox',
        'spec_records',
        'spec_values',
        'spec_versions',
        'media_assets',
        'media_chunks',
      ])
        table: store.rows[table]?.length ?? 0,
    },
    'businessHash': digest({
      for (final table in [
        'receipts',
        'audit',
        'outbox',
        'spec_records',
        'spec_values',
        'spec_versions',
        'media_assets',
        'media_chunks',
      ])
        table: store.rows[table],
    }),
    'fileBytesHash': digest({
      for (final entry in fixture.files.values.entries)
        entry.key: sha256.convert(entry.value).toString(),
    }),
  };
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((http) async {
    active++;
    if (active > maximum) maximum = active;
    try {
      if (http.method != 'POST' ||
          http.uri.path != '/v1/functions/core/executions')
        throw const FormatException();
      final envelope = jsonDecode(await utf8.decoder.bind(http).join()) as Row,
          input = jsonDecode(envelope['body'] as String) as Row;
      calls.add({'op': input['op']});
      Object data;
      int status;
      try {
        data = await api.execute('alice', input);
        status = 200;
      } on ServiceException catch (error) {
        data = {'error': error.code};
        status = error.status;
      }
      results.add({'op': input['op'], 'status': status});
      http.response.headers.contentType = ContentType.json;
      http.response.statusCode = 201;
      http.response.write(
        jsonEncode({
          'status': 'completed',
          'responseStatusCode': status,
          'responseBody': jsonEncode(data),
        }),
      );
    } catch (_) {
      http.response.statusCode = 500;
      http.response.write('{}');
    }
    await http.response.close();
    active--;
  });
  stdout.writeln(
    jsonEncode({
      'ready': true,
      'endpoint': 'http://127.0.0.1:${server.port}/v1',
      'assetIds': [first, second],
      'displayHashes': [
        store.rows['media_assets']![first]!['displayHash'],
        store.rows['media_assets']![second]!['displayHash'],
      ],
      'app': app,
      'collectionId': collection,
    }),
  );
  final done = Completer<void>();
  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) async {
          final command = jsonDecode(line) as Row;
          Object? data;
          try {
            switch (command['action']) {
              case 'arm':
                store.arm();
                data = true;
              case 'paused':
                await store.paused!.future.timeout(const Duration(seconds: 10));
                data = true;
              case 'release':
                store.resume!.complete();
                data = true;
              case 'resetMaximum':
                maximum = 0;
                data = true;
              case 'stats':
                data = stats();
              case 'close':
                data = true;
                if (!done.isCompleted) done.complete();
              default:
                throw const FormatException();
            }
            stdout.writeln(jsonEncode({'id': command['id'], 'data': data}));
          } catch (error) {
            stdout.writeln(
              jsonEncode({
                'id': command['id'],
                'error': error.runtimeType.toString(),
              }),
            );
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
  await done.future;
  await server.close(force: true);
  await db.close();
}
