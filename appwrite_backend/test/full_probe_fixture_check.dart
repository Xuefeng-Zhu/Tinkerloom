import 'dart:convert';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import '../lib/service.dart';
import 'spec_engine_check.dart' as harness;

var assertions = 0;
void check(bool value, String message) {
  assertions++;
  if (!value) throw StateError(message);
}

Future<void> rejects(PlatformService api, Row body) async {
  try {
    await api.execute('alice', body);
    throw StateError('Invalid numeric command committed');
  } on ServiceException catch (error) {
    check(error.code == 'invalid_values', 'Wrong rejection');
    check(error.status == 400, 'Wrong status');
  }
}

Future<int> total(
  PlatformService api,
  String version,
  String collection,
) async =>
    (await api.execute('alice', {
          'op': 'spec.query',
          'appId': 'app',
          'versionId': version,
          'collectionId': collection,
          'query': {'limit': 1},
        }))['total']
        as int;
Future<void> main() async {
  final (store, api, version) = await harness.fixture('reading');
  check(
    spec
            .starterTemplates()['reading']!
            .collection('books')
            .field('rating')
            .type ==
        spec.FieldType.integer,
    'Reading rating type drifted',
  );
  final command = harness.action('accepted-safe', version, 'addBook', {
    'data': {
      'title': 'Valid integer above number bound',
      'status': 'Reading',
      'rating': 1000000000000001,
    },
  });
  final accepted = await api.execute('alice', command),
      snapshot = jsonEncode(store.rows);
  check((accepted['outcome'] as Map)['revision'] == 1, 'Valid integer failed');
  check(
    jsonEncode(await api.execute('alice', command)) == jsonEncode(accepted),
    'Exact receipt changed',
  );
  check(jsonEncode(store.rows) == snapshot, 'Exact retry changed rows');
  for (final value in [-9007199254740991, 9007199254740991])
    await api.execute(
      'alice',
      harness.action('accept-$value', version, 'addBook', {
        'data': {'title': 'Boundary', 'status': 'Reading', 'rating': value},
      }),
    );
  check(
    await total(api, version, 'books') == 3,
    'Valid integer population wrong',
  );
  var i = 0;
  for (final value in [-9007199254740992, 9007199254740992, 1.25, '1']) {
    final before = jsonEncode(store.rows);
    await rejects(
      api,
      harness.action('invalid-integer-${i++}', version, 'addBook', {
        'data': {'title': 'Rejected', 'status': 'Reading', 'rating': value},
      }),
    );
    check(
      jsonEncode(store.rows) == before,
      'Rejected integer changed rows/receipt/audit/outbox',
    );
  }
  check(
    await total(api, version, 'books') == 3,
    'Invalid integer polluted population',
  );
  final (numberStore, numberApi, numberVersion) = await harness.fixture(
    'habitTracker',
  );
  final field = spec
      .starterTemplates()['habitTracker']!
      .collection('checkins')
      .field('minutes');
  check(field.type == spec.FieldType.number, 'Minutes type drifted');
  i = 0;
  for (final value in [-1e15, 1e15, 1.25, 0])
    await numberApi.execute(
      'alice',
      harness.action('valid-number-${i++}', numberVersion, 'addRecord', {
        'data': {
          'title': 'Number',
          'loggedAt': '2026-01-01T00:00:00.000Z',
          'minutes': value,
        },
      }),
    );
  check(
    await total(numberApi, numberVersion, 'checkins') == 4,
    'Number bounds/fraction rejected',
  );
  i = 0;
  for (final value in [-1000000000000001, 1000000000000001, '1']) {
    final before = jsonEncode(numberStore.rows);
    await rejects(
      numberApi,
      harness.action('invalid-number-${i++}', numberVersion, 'addRecord', {
        'data': {
          'title': 'Rejected',
          'loggedAt': '2026-01-01T00:00:00.000Z',
          'minutes': value,
        },
      }),
    );
    check(
      jsonEncode(numberStore.rows) == before,
      'Rejected number changed rows/receipt/audit/outbox',
    );
  }
  for (final value in [double.nan, double.infinity, double.negativeInfinity]) {
    try {
      field.normalize(value);
      throw StateError('Nonfinite accepted');
    } on spec.SpecException {
      assertions++;
    }
  }
  final empty = await api.execute('alice', {
    'op': 'spec.launcher',
    'workspaceId': 'ws',
    'limit': 50,
    'pinnedOnly': true,
  });
  check(
    (empty['apps'] as List).isEmpty,
    'Manual create unexpectedly auto-pinned',
  );
  await harness.join(api, 'viewer', 7, role: 'viewer');
  final pin = await api.execute('alice', {
    'op': 'spec.setPinned',
    'appId': 'app',
    'operationId': 'owner-pin',
    'pinned': true,
    'expectedRevision': 0,
  });
  check((pin['shortcut'] as Map)['revision'] == 1, 'Owner explicit pin failed');
  await api.execute('viewer', {
    'op': 'spec.setPinned',
    'appId': 'app',
    'operationId': 'viewer-pin',
    'pinned': true,
    'expectedRevision': 0,
  });
  await api.execute('viewer', {
    'op': 'spec.setPinned',
    'appId': 'app',
    'operationId': 'viewer-unpin',
    'pinned': false,
    'expectedRevision': 1,
  });
  for (final actor in ['alice', 'viewer']) {
    final result = await api.execute(actor, {
      'op': 'spec.launcher',
      'workspaceId': 'ws',
      'limit': 50,
      'pinnedOnly': true,
    });
    check(
      (result['apps'] as List).any((value) => (value as Map)['id'] == 'app') ==
          (actor == 'alice'),
      'Viewer unpin affected owner',
    );
  }
  print(
    jsonEncode({
      'checks': 4,
      'assertions': assertions,
      'status': 'passed',
      'proof':
          'Actual PlatformService with simulated MemoryStore; no Cloud/transport proof',
      'integerAcceptedPopulation': 3,
      'numberAcceptedPopulation': 4,
      'manualAutoPin': false,
      'viewerUnpinLeavesOwnerPinned': true,
    }),
  );
}
