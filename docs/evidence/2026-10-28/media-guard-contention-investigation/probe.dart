import 'dart:convert';
import 'dart:io';
import 'file:///Users/frank/mygit/Tinkerloom/appwrite_backend/lib/service.dart';
import 'file:///Users/frank/mygit/Tinkerloom/appwrite_backend/test/confirmed_abort_test.dart'
    as concurrency;
import 'file:///Users/frank/mygit/Tinkerloom/appwrite_backend/test/media_check.dart'
    as media;

Future<Row> call(media.Fixture f, Row input) async {
  try {
    final value = await f.api.execute('alice', input);
    return {'status': 200, 'keys': value.keys.toList()};
  } on ServiceException catch (error) {
    return {'status': error.status, 'code': error.code};
  }
}

Row business(media.Fixture f) => {
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
    table: f.store.rows[table]?.length ?? 0,
};
Future<void> main() async {
  final f = media.Fixture(memory: concurrency.CloudStore());
  final memory = f.store as concurrency.CloudStore;
  await f.setup();
  final a = await f.ready('first', media.png()),
      b = await f.ready('second', media.png());
  final statusA = <String, dynamic>{
        'op': 'spec.media.status',
        'appId': 'app',
        'assetId': a,
      },
      statusB = <String, dynamic>{
        'op': 'spec.media.status',
        'appId': 'app',
        'assetId': b,
      };
  final readA = <String, dynamic>{
        'op': 'spec.media.read',
        'appId': 'app',
        'assetId': a,
        'variant': 'thumbnail',
        'offset': 0,
      },
      readB = <String, dynamic>{
        'op': 'spec.media.read',
        'appId': 'app',
        'assetId': b,
        'variant': 'thumbnail',
        'offset': 0,
      };
  final version =
      jsonDecode(
            f.store.rows['spec_versions']![f.version]!['specJson'] as String,
          )
          as Map;
  final collection = ((version['collections'] as List).first as Map)['id'];
  final query = <String, dynamic>{
    'op': 'spec.query',
    'appId': 'app',
    'versionId': f.version,
    'collectionId': collection,
    'query': <String, dynamic>{},
  };
  final results = <Row>[];
  for (final pair in [
    [statusA, statusB],
    [readA, readB],
    [readA, query],
  ]) {
    final before = business(f),
        filesBefore = media.digest(utf8.encode(f.files.values.keys.join('|')));
    memory.arm();
    final first = call(f, pair[0]);
    await memory.paused!.future.timeout(const Duration(seconds: 5));
    late Row fast;
    try {
      fast = await call(f, pair[1]);
    } finally {
      memory.resume!.complete();
    }
    final slow = await first,
        sequential = [await call(f, pair[0]), await call(f, pair[1])];
    final after = business(f);
    if (slow['status'] != 409 ||
        slow['code'] != 'transaction_conflict' ||
        fast['status'] != 200 ||
        sequential.any((item) => item['status'] != 200) ||
        jsonEncode(before) != jsonEncode(after))
      throw StateError('unexpected synthetic read outcome');
    results.add({
      'pausedOp': pair[0]['op'],
      'otherOp': pair[1]['op'],
      'overlap': [slow, fast],
      'sequential': sequential,
      'businessRowsUnchanged': jsonEncode(before) == jsonEncode(after),
      'fileIdentitiesUnchanged':
          filesBefore ==
          media.digest(utf8.encode(f.files.values.keys.join('|'))),
    });
  }
  final output = {
    'proof':
        'actual_PlatformService_synthetic_optimistic_MemoryStore_fake_Storage_only_not_Cloud',
    'source': '0acf9eadeed00b3cd966c57465a36ce9ffc823fb',
    'cases': results,
  };
  final text = const JsonEncoder.withIndent('  ').convert(output);
  File(
    Platform.script.resolve('result.json').toFilePath(),
  ).writeAsStringSync('$text\n');
  stdout.writeln(text);
}
