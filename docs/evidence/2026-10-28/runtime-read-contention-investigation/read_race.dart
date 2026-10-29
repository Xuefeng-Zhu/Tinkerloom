import 'dart:convert';
import 'dart:io';
import 'file:///Users/frank/mygit/Tinkerloom/appwrite_backend/lib/service.dart';
import 'file:///Users/frank/mygit/Tinkerloom/appwrite_backend/test/confirmed_abort_test.dart' as fixtures;

Future<Row> call(fixtures.LocalDatabase f, Row input) async {
  try {
    final data = await f.service.execute('alice', input);
    return {'status': 200, 'keys': data.keys.toList()};
  } on ServiceException catch (error) {
    return {'status': error.status, 'code': error.code};
  }
}
Row business(fixtures.LocalDatabase f) => {
  for (final table in ['receipts', 'audit', 'outbox', 'spec_records', 'spec_cells', 'spec_versions'])
    table: f.memory.rows[table]?.length ?? 0,
};

Future<void> main() async {
  final f = await fixtures.LocalDatabase.create();
  try {
    await f.setup();
    await f.service.execute('alice', await fixtures.publicationCommand(f));
    final app = f.memory.rows['apps']!['app-one']!;
    final versionId = app['specVersionId'];
    final version = f.memory.rows['spec_versions']![versionId]!;
    final definition = jsonDecode(version['specJson'] as String) as Map;
    final collection = (definition['collections'] as List).first as Map;
    final getApp = <String, dynamic>{'op': 'spec.getApp', 'appId': 'app-one'};
    final watch = <String, dynamic>{'op': 'spec.watch', 'appId': 'app-one'};
    final query = <String, dynamic>{
      'op': 'spec.query', 'appId': 'app-one', 'versionId': versionId,
      'collectionId': collection['id'], 'query': <String, dynamic>{},
    };
    final cases = <List<Row>>[
      [getApp, query], [watch, query], [query, query],
      [getApp, {'op': 'spec.getApp', 'appId': 'app-two'}],
    ];
    final results = <Row>[];
    for (final pair in cases) {
      final before = business(f);
      final failedBefore = f.states.values.where((v) => v == 'failed').length;
      f.memory.arm();
      final slow = call(f, pair[0]);
      await f.memory.paused!.future.timeout(const Duration(seconds: 5));
      late Row fast;
      try {
        fast = await call(f, pair[1]);
      } finally {
        f.memory.resume!.complete();
      }
      final first = await slow;
      final sequenced = [await call(f, pair[0]), await call(f, pair[1])];
      final after = business(f);
      if (first['status'] != 409 || first['code'] != 'transaction_conflict' || fast['status'] != 200 ||
          sequenced.any((r) => r['status'] != 200) || jsonEncode(before) != jsonEncode(after)) {
        throw StateError('Unexpected read concurrency result: $first / $fast / $sequenced / $before / $after');
      }
      results.add({
        'paused': pair[0]['op'], 'concurrent': pair[1]['op'],
        'crossAppSameWorkspace': pair[0]['appId'] != pair[1]['appId'],
        'overlap': [first, fast], 'sequenced': sequenced,
        'newConfirmedFailedTransactions': f.states.values.where((v) => v == 'failed').length - failedBefore,
        'businessRowsBefore': before, 'businessRowsAfter': after,
      });
    }
    final output = {'proof': 'actual_service_loopback_rest_optimistic_memory_only', 'cases': results};
    final encoded = const JsonEncoder.withIndent('  ').convert(output);
    File('/private/tmp/tinkerloom-runtime-read-investigation/result.json').writeAsStringSync('$encoded\n');
    stdout.writeln(encoded);
  } finally {
    await f.close();
  }
}
