import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appnest_spec/appnest_spec.dart' as spec;

import '../lib/service.dart';
import 'memory_store.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> error(Future<dynamic> Function() action, String code) async {
  try {
    await action();
    throw StateError('Expected $code');
  } on ServiceException catch (actual) {
    check(actual.code == code, 'Expected $code, received ${actual.code}');
  }
}

Row clone(Row row) => jsonDecode(jsonEncode(row)) as Row;

Future<(MemoryStore, PlatformService, String)> fixture(String template,
    {MemoryStore? store}) async {
  final memory = store ?? MemoryStore(),
      api = PlatformService(store ?? MemoryStore());
  final service = store == null ? PlatformService(memory) : api;
  await service.execute(
      'alice', {'op': 'createWorkspace', 'id': 'ws', 'name': 'Workspace'});
  await service.execute('alice', {
    'op': 'spec.createApp',
    'id': 'app',
    'workspaceId': 'ws',
    'name': 'Full app',
    'operationId': 'create'
  });
  final app = spec.starterTemplates()[template]!;
  await service.execute('alice', {
    'op': 'spec.saveDraft',
    'appId': 'app',
    'operationId': 'draft',
    'expectedRevision': 0,
    'expectedVersionId': null,
    'spec': app.toJson()
  });
  final version = await publish(service, 'alice', 1, null, 'publish');
  return (memory, service, version);
}

Future<String> publish(PlatformService api, String actor, int revision,
    String? base, String operation) async {
  final review = (await api.execute(actor, {
    'op': 'spec.review',
    'appId': 'app',
    'expectedRevision': revision,
    'enabledRuleIds': <String>[],
    'activateExistingRecordIds': <String>[]
  }))['review'] as Map;
  final result = await api.execute(actor, {
    'op': 'spec.publish',
    'appId': 'app',
    'operationId': operation,
    'expectedRevision': revision,
    'expectedVersionId': base,
    'candidateHash': review['candidateHash'],
    'reviewHash': review['reviewHash'],
    'enabledRuleIds': <String>[],
    'activateExistingRecordIds': <String>[]
  });
  return (((result['app'] as Map)['version'] as Map)['id']) as String;
}

Row action(String operation, String version, String id, Row input,
        {String? record, int? revision}) =>
    {
      'op': 'spec.execute',
      'appId': 'app',
      'operationId': operation,
      'versionId': version,
      'actionId': id,
      'input': input,
      if (record != null) 'targetRecordId': record,
      if (revision != null) 'expectedRecordRevision': revision,
    };
Future<Row> run(PlatformService api, String actor, Row command) async =>
    (await api.execute(actor, command))['outcome'] as Row;
Future<Row> get(
        PlatformService api, String actor, String version, String id) async =>
    (await api.execute(actor, {
      'op': 'spec.getRecord',
      'appId': 'app',
      'versionId': version,
      'recordId': id
    }))['record'] as Row;
String token(int seed) => base64Url
    .encode(List.generate(32, (i) => (seed + i) % 256))
    .replaceAll('=', '');
Future<void> join(PlatformService api, String actor, int seed,
    {String role = 'member'}) async {
  await api.execute('alice', {
    'op': 'createInvitation',
    'appId': 'app',
    'id': 'invite-$seed',
    'operationId': 'invite-$seed',
    'role': role,
    'recipientId': actor,
    'token': token(seed)
  });
  await api.execute(actor, {
    'op': 'acceptInvitation',
    'token': token(seed),
    'operationId': 'accept-$seed'
  });
}

class BarrierStore extends MemoryStore {
  int remaining = 0;
  Completer<void>? gate;
  void barrier(int count) {
    remaining = count;
    gate = Completer<void>();
  }

  @override
  Future<void> finishTransaction(String transactionId,
      {required bool commit}) async {
    if (commit && remaining > 0) {
      final wait = gate!;
      remaining--;
      if (remaining == 0) wait.complete();
      await wait.future;
    }
    return super.finishTransaction(transactionId, commit: commit);
  }
}

/// Applies the declared Appwrite datetime column's millisecond codec. A
/// canonical varchar bypasses this loss. This is not a live Cloud receipt.
class ProjectionSchemaStore extends MemoryStore {
  ProjectionSchemaStore(this.timestampColumn);
  final Row timestampColumn;
  Row _encode(String table, Row data) {
    final result = Map<String, dynamic>.from(data);
    if (table == 'spec_values' &&
        result['timestampValue'] is String &&
        timestampColumn['type'] == 'datetime') {
      final instant = DateTime.parse(result['timestampValue'] as String);
      result['timestampValue'] = DateTime.fromMillisecondsSinceEpoch(
              instant.millisecondsSinceEpoch,
              isUtc: true)
          .toIso8601String();
    }
    return result;
  }

  @override
  Future<Row> create(String table, String id, Row data,
          {String? transactionId}) =>
      super.create(table, id, _encode(table, data),
          transactionId: transactionId);
  @override
  Future<Row> update(String table, String id, Row data,
          {String? transactionId}) =>
      super.update(table, id, _encode(table, data),
          transactionId: transactionId);
}

Future<int> runSpecEngineChecks() async {
  var passed = 0;
  Future<void> test(String label, Future<void> Function() action) async {
    await action();
    passed++;
    print('PASS $label');
  }

  await test(
      'full AppSpec templates parse canonically without changing bounded APIs or stored receipts',
      () async {
    final store = MemoryStore(), api = PlatformService(MemoryStore());
    check(store.rows.isEmpty, 'Unexpected store state');
    final capabilities =
        await api.execute('alice', {'op': 'spec.capabilities'});
    check(
        (capabilities['actionCapabilities'] as List).length == 7 &&
            (capabilities['effects'] as List).isEmpty,
        'Capabilities falsely advertise workers');
    for (final entry in spec.starterTemplates().entries) {
      final (_, service, version) = await fixture(entry.key);
      final response = (await service.execute(
          'alice', {'op': 'spec.getApp', 'appId': 'app'}))['app'] as Map;
      check(
          (response['version'] as Map)['id'] == version &&
              (response['version'] as Map)['hash'] == entry.value.hash,
          'Template canonical hash changed');
      await error(
          () => service.execute('alice', {'op': 'getApp', 'appId': 'app'}),
          'unsupported_runtime');
      await error(
          () => service.execute('alice', {
                'op': 'saveDraft',
                'appId': 'app',
                'operationId': 'wrong-api',
                'expectedRevision': 0,
                'definition': {
                  'title': 'Bounded',
                  'description': '',
                  'primaryFieldId': 'title',
                  'fields': [
                    {
                      'id': 'title',
                      'label': 'Title',
                      'kind': 'text',
                      'required': true
                    }
                  ]
                }
              }),
          'unsupported_runtime');
    }
  });

  await test(
      'full publication persists immutable versions hashes private candidates and exact receipts',
      () async {
    final (store, api, version) = await fixture('reading');
    await join(api, 'bob', 1, role: 'builder');
    final owner = (await api
        .execute('alice', {'op': 'spec.getApp', 'appId': 'app'}))['app'] as Map;
    final shared = (await api
        .execute('bob', {'op': 'spec.getApp', 'appId': 'app'}))['app'] as Map;
    check(shared['draft'] == null, 'Owner candidate leaked');
    final candidate = clone(spec.starterTemplates()['reading']!.toJson())
      ..['name'] = 'Bob candidate';
    await api.execute('bob', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'bob-draft',
      'expectedRevision': 0,
      'expectedVersionId': version,
      'spec': candidate
    });
    final second = await publish(api, 'bob', 1, version, 'bob-publish');
    check(second != version && store.rows['spec_versions']!.length == 2,
        'No immutable version history');
    check(
        store.rows['spec_versions']![version]!['hash'] ==
            ((owner['version'] as Map)['hash']),
        'Original version changed');
    await error(
        () => api.execute('alice', {
              'op': 'spec.publish',
              'appId': 'app',
              'operationId': 'owner-stale',
              'expectedRevision': 1,
              'expectedVersionId': version,
              'candidateHash': ((owner['draft'] as Map)['candidateHash']),
              'reviewHash': spec.hashJson({
                'candidateHash': ((owner['draft'] as Map)['candidateHash']),
                'enabledRuleIds': [],
                'activateExistingRecordIds': []
              }),
              'enabledRuleIds': [],
              'activateExistingRecordIds': []
            }),
        'definition_conflict');
    final apps = (await api.execute(
        'bob', {'op': 'listApps', 'workspaceId': 'ws'}))['apps'] as List;
    check((apps.single as Map)['engine'] == 'appspec.v1',
        'Shared AppSpec app not discoverable');
  });

  await test(
      'personal member policy reads records but denies actions and viewers cannot mutate',
      () async {
    final (_, api, version) = await fixture('reading');
    await join(api, 'bob', 2);
    await join(api, 'carol', 3, role: 'viewer');
    final created = await run(
        api,
        'alice',
        action('create-book', version, 'addBook', {
          'data': {'title': 'A', 'status': 'Reading'}
        }));
    for (final actor in ['bob', 'carol']) {
      final record =
          await get(api, actor, version, created['recordId'] as String);
      check((record['allowedActions'] as List).isEmpty,
          'Read-only member has actions');
      await error(
          () => api.execute(
              actor,
              action(
                  'deny-$actor',
                  version,
                  'editBook',
                  {
                    'data': {'notes': 'No'}
                  },
                  record: created['recordId'] as String,
                  revision: 1)),
          'forbidden');
    }
  });

  await test(
      'workflow members use approved transitions assignments and protected fields never generic patch',
      () async {
    final (_, api, version) = await fixture('chores');
    await join(api, 'bob', 4);
    await join(api, 'carol', 5);
    final created = await run(
        api,
        'bob',
        action('new-chore', version, 'addChore', {
          'data': {'title': 'Clean', 'status': 'Open', 'assignee': 'carol'}
        }));
    final id = created['recordId'] as String;
    await error(
        () => api.execute(
            'bob',
            action(
                'patch-status',
                version,
                'editChore',
                {
                  'data': {'status': 'Done'}
                },
                record: id,
                revision: 1)),
        'forbidden');
    await error(
        () => api.execute(
            'bob',
            action(
                'patch-assignee',
                version,
                'editChore',
                {
                  'data': {'assignee': 'alice'}
                },
                record: id,
                revision: 1)),
        'forbidden');
    await error(
        () => api.execute(
            'bob',
            action('skip-transition', version, 'moveChore', {'value': 'Done'},
                record: id, revision: 1)),
        'invalid_values');
    await run(
        api,
        'bob',
        action('move', version, 'moveChore', {'value': 'Doing'},
            record: id, revision: 1));
    await error(
        () => api.execute(
            'bob',
            action(
                'stale-notes',
                version,
                'editChore',
                {
                  'data': {'notes': 'Stale'}
                },
                record: id,
                revision: 1)),
        'revision_conflict');
    await api.execute('alice', {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'carol',
      'role': null,
      'expectedRevision': 1,
      'operationId': 'revoke-assignee'
    });
    await run(
        api,
        'bob',
        action(
            'notes-with-revoked-assignee',
            version,
            'editChore',
            {
              'data': {'notes': 'Unrelated update'}
            },
            record: id,
            revision: 2));
    await error(
        () => api.execute(
            'bob',
            action(
                'reassign-revoked', version, 'assignChore', {'value': 'carol'},
                record: id, revision: 3)),
        'invalid_values');
    await run(
        api,
        'bob',
        action('clear-assignment', version, 'assignChore', {'value': null},
            record: id, revision: 3));
    final record = await get(api, 'bob', version, id);
    check(
        (record['data'] as Map)['status'] == 'Doing' &&
            !(record['data'] as Map).containsKey('assignee'),
        'Approved actions produced wrong normalized state');
  });

  await test(
      'capacity claims configure release and reactivation preserve typed counters',
      () async {
    final (_, api, version) = await fixture('volunteer');
    await join(api, 'bob', 6);
    await join(api, 'carol', 7);
    await error(
        () => api.execute(
            'bob',
            action('member-create-shift', version, 'addShift', {
              'data': {'title': 'Shift', 'startsAt': '2026-11-01T09:00:00Z'},
              'capacity': 1
            })),
        'forbidden');
    final made = await run(
        api,
        'alice',
        action('new-shift', version, 'addShift', {
          'data': {'title': 'Shift', 'startsAt': '2026-11-01T09:00:00Z'},
          'capacity': 1
        }));
    final id = made['recordId'] as String;
    final claim = action('bob-claim', version, 'join', {}, record: id);
    final receipt = await api.execute('bob', claim);
    await api.execute('bob', claim);
    check((await get(api, 'bob', version, id))['allocated'] == 1,
        'Exact claim retry allocated twice');
    await run(api, 'bob',
        action('claim-again-new-key', version, 'join', {}, record: id));
    await error(
        () => api.execute(
            'carol', action('full', version, 'join', {}, record: id)),
        'exhausted_capacity');
    await error(
        () => api.execute(
            'alice',
            action('shrink', version, 'configure', {'capacity': 0},
                record: id)),
        'invalid_values');
    await run(api, 'bob', action('leave', version, 'leave', {}, record: id));
    await run(
        api, 'bob', action('leave-again', version, 'leave', {}, record: id));
    check((await get(api, 'alice', version, id))['allocated'] == 0,
        'Repeated release decremented twice');
    await run(
        api, 'bob', action('reactivate', version, 'join', {}, record: id));
    check((await get(api, 'alice', version, id))['allocated'] == 1,
        'Existing claim did not reactivate');
    check(jsonEncode(await api.execute('bob', claim)) == jsonEncode(receipt),
        'Original claim outcome changed');
  });

  await test(
      'twenty independent final-place transactions produce one committed allocation',
      () async {
    final store = BarrierStore();
    final (_, api, version) = await fixture('volunteer', store: store);
    for (var i = 0; i < 20; i++) await join(api, 'member$i', 20 + i);
    final made = await run(
        api,
        'alice',
        action('race-shift', version, 'addShift', {
          'data': {'title': 'Last place', 'startsAt': '2026-11-01T09:00:00Z'},
          'capacity': 1
        }));
    final id = made['recordId'] as String;
    store.barrier(20);
    final results = await Future.wait(List.generate(20, (i) async {
      try {
        await run(api, 'member$i',
            action('claim-$i', version, 'join', {}, record: id));
        return true;
      } on ServiceException catch (actual) {
        check(actual.code == 'transaction_conflict',
            'Unexpected capacity race error');
        return false;
      }
    }));
    check(
        results.where((ok) => ok).length == 1, 'Multiple final-place winners');
    for (var i = 0; i < 20; i++)
      if (!results[i])
        await error(
            () => api.execute('member$i',
                action('claim-$i', version, 'join', {}, record: id)),
            'exhausted_capacity');
    final state = await get(api, 'alice', version, id);
    check(
        state['allocated'] == 1 &&
            store.rows['spec_claims']!.values
                    .where((claim) => claim['active'] == true)
                    .length ==
                1,
        'Claim and allocation disagree');
  });

  await test(
      'business records projections receipts audit and outbox roll back atomically',
      () async {
    final (store, api, version) = await fixture('reading');
    final before = jsonEncode(store.rows);
    store.failBeforeCommit = true;
    try {
      await api.execute(
          'alice',
          action('rollback', version, 'addBook', {
            'data': {'title': 'Rollback', 'status': 'Reading', 'rating': 4}
          }));
      throw StateError('Expected failure');
    } on RestException {/* deliberately failed commit */}
    store.failBeforeCommit = false;
    check(jsonEncode(store.rows) == before,
        'Partial business/projection/audit/outbox/receipt commit');
    store.loseCommitResponse = true;
    final command = action('unknown', version, 'addBook', {
      'data': {'title': 'Unknown', 'status': 'Reading'}
    });
    try {
      await api.execute('alice', command);
      throw StateError('Expected unknown');
    } on RestException {/* committed unknown */}
    final recovered = await run(api, 'alice', command);
    check(
        store.rows['spec_records']!.length == 1 &&
            recovered['recordId'] == store.rows['spec_records']!.keys.single,
        'Unknown create duplicated record');
    check(
        store.rows['audit']!.values
                    .where((row) => row['requestId'] == 'unknown')
                    .length ==
                1 &&
            store.rows['outbox']!.values
                    .where((row) => row['recordId'] == recovered['recordId'])
                    .length ==
                1,
        'Audit/outbox mismatch');
  });

  await test(
      'complete typed queries span backend pages and preserve nulls-last ranked cursors',
      () async {
    final (_, api, version) = await fixture('reading');
    for (var i = 0; i < 115; i++)
      await run(
          api,
          'alice',
          action('book-$i', version, 'addBook', {
            'data': {
              'title': 'Book ${i.toString().padLeft(3, '0')}',
              'status': i % 2 == 0 ? 'Reading' : 'Finished',
              if (i % 5 != 0) 'rating': i % 7,
              'notes': i % 3 == 0 ? 'ALPHA note' : 'Beta',
            }
          }));
    final query = {
      'filters': [
        {'fieldId': 'notes', 'operator': 'contains', 'value': 'alpha'}
      ],
      'sort': [
        {'fieldId': 'rating', 'descending': true},
        {'fieldId': 'title', 'descending': false}
      ],
      'limit': 7
    };
    final ids = <String>[];
    String? cursor;
    var total = 0;
    bool sawNull = false;
    num? prior;
    do {
      final page = await api.execute('alice', {
        'op': 'spec.query',
        'appId': 'app',
        'versionId': version,
        'collectionId': 'books',
        'query': {...query, if (cursor != null) 'cursor': cursor}
      });
      total = page['total'] as int;
      for (final record in (page['records'] as List).cast<Map>()) {
        ids.add(record['id'] as String);
        final rating = (record['data'] as Map)['rating'];
        if (rating == null)
          sawNull = true;
        else {
          check(!sawNull, 'NULLS LAST changed for descending');
          if (prior != null)
            check((rating as num) <= prior, 'Wrong descending rank');
          prior = rating as num;
        }
      }
      cursor = page['nextCursor'] as String?;
    } while (cursor != null);
    check(total == 39 && ids.length == 39 && ids.toSet().length == 39,
        'Complete query missed rows across source pages');
    final empty = await api.execute('alice', {
      'op': 'spec.query',
      'appId': 'app',
      'versionId': version,
      'collectionId': 'books',
      'query': {
        'filters': [
          {'fieldId': 'rating', 'operator': 'eq', 'value': null}
        ]
      }
    });
    check(empty['total'] == 23,
        'Unset equality did not use missing projection semantics');
  });

  await test(
      'query cursors bind query version scope and fail on a stale matching anchor',
      () async {
    final (_, api, version) = await fixture('reading');
    for (var i = 0; i < 3; i++)
      await run(
          api,
          'alice',
          action('cursor-book-$i', version, 'addBook', {
            'data': {'title': '$i', 'status': 'Reading'}
          }));
    final first = await api.execute('alice', {
      'op': 'spec.query',
      'appId': 'app',
      'versionId': version,
      'collectionId': 'books',
      'query': {'limit': 1}
    });
    final cursor = first['nextCursor'] as String;
    await error(
        () => api.execute('alice', {
              'op': 'spec.query',
              'appId': 'app',
              'versionId': version,
              'collectionId': 'books',
              'query': {
                'limit': 1,
                'cursor': cursor,
                'filters': [
                  {'fieldId': 'title', 'operator': 'eq', 'value': '0'}
                ]
              }
            }),
        'invalid_request');
    final record = (first['records'] as List).single as Map;
    await run(
        api,
        'alice',
        action(
            'cursor-patch',
            version,
            'editBook',
            {
              'data': {'status': 'Finished'}
            },
            record: record['id'] as String,
            revision: 1));
    final filtered = await api.execute('alice', {
      'op': 'spec.query',
      'appId': 'app',
      'versionId': version,
      'collectionId': 'books',
      'query': {
        'limit': 1,
        'filters': [
          {'fieldId': 'status', 'operator': 'eq', 'value': 'Reading'}
        ]
      }
    });
    final anchor = (filtered['records'] as List).single as Map;
    await run(
        api,
        'alice',
        action(
            'remove-anchor',
            version,
            'editBook',
            {
              'data': {'status': 'Finished'}
            },
            record: anchor['id'] as String,
            revision: 1));
    await error(
        () => api.execute('alice', {
              'op': 'spec.query',
              'appId': 'app',
              'versionId': version,
              'collectionId': 'books',
              'query': {
                'limit': 1,
                'cursor': filtered['nextCursor'],
                'filters': [
                  {'fieldId': 'status', 'operator': 'eq', 'value': 'Reading'}
                ]
              }
            }),
        'revision_conflict');
  });

  await test(
      'database-wide summary and numeric choice aggregates exclude missing numbers from averages',
      () async {
    final (_, api, version) = await fixture('reading');
    for (var i = 0; i < 105; i++)
      await run(
          api,
          'alice',
          action('aggregate-$i', version, 'addBook', {
            'data': {
              'title': '$i',
              'status': i % 2 == 0 ? 'Reading' : 'Finished',
              if (i < 100) 'rating': i,
            }
          }));
    final base = {
      'appId': 'app',
      'versionId': version,
      'collectionId': 'books',
      'query': {'limit': 1}
    };
    final summary = await api.execute(
        'alice', {'op': 'spec.summary', ...base, 'groupFieldId': 'status'});
    check(
        summary['total'] == 105 && (summary['groups'] as Map)['Reading'] == 53,
        'Summary was page-local');
    final average = await api.execute('alice', {
      'op': 'spec.aggregate',
      ...base,
      'aggregate': {
        'metric': 'average',
        'fieldId': 'rating',
        'groupFieldId': 'status'
      }
    });
    check(average['total'] == 105 && average['value'] == 49.5,
        'Missing numeric values entered average');
    final empty = await api.execute('alice', {
      'op': 'spec.aggregate',
      ...base,
      'query': {
        'filters': [
          {'fieldId': 'rating', 'operator': 'eq', 'value': null}
        ]
      },
      'aggregate': {'metric': 'sum', 'fieldId': 'rating'}
    });
    check(empty['total'] == 5 && empty['value'] == 0,
        'Empty numeric sum did not return zero');
    final nullAverage = await api.execute('alice', {
      'op': 'spec.aggregate',
      ...base,
      'query': {
        'filters': [
          {'fieldId': 'rating', 'operator': 'eq', 'value': null}
        ]
      },
      'aggregate': {'metric': 'average', 'fieldId': 'rating'}
    });
    check(nullAverage['value'] == null, 'Empty average is not null');
  });

  await test(
      'strict timestamps preserve explicit offsets microseconds and reject civil rollover',
      () async {
    final field =
        spec.FieldSpec('date', 'Date', spec.FieldType.timestamp, false, []);
    check(
        field.normalize('2024-02-29T01:02:03.123456+02:30') ==
            '2024-02-28T22:32:03.123456Z',
        'Offset/microsecond normalization changed');
    check(
        field.normalize('-0001-01-01T00:00:00Z') == '-0001-01-01T00:00:00.000Z',
        'Negative year formatting changed');
    for (final value in [
      '2024-02-30T00:00:00Z',
      '2024-01-01T24:00:00Z',
      '2024-01-01T00:00:60Z',
      '2024-01-01',
      '2024-01-01T00:00:00+24:00',
      '2024-01-01T00:00:00Z\n'
    ]) {
      try {
        field.normalize(value);
        throw StateError('Invalid timestamp accepted: $value');
      } on spec.SpecException {/* intended strict rejection */}
    }
    for (final type in [spec.FieldType.integer, spec.FieldType.number]) {
      try {
        spec.FieldSpec('n', 'Number', type, false, [])
            .normalize(-9223372036854775808);
        throw StateError('Minimum integer bypassed magnitude bound');
      } on spec.SpecException {/* explicit comparisons reject abs overflow */}
    }
  });

  await test(
      'publication binds exact review compatibility and single-use candidate without partial writes',
      () async {
    final (store, api, version) = await fixture('reading');
    final candidate = clone(spec.starterTemplates()['reading']!.toJson());
    ((candidate['collections'] as List).single['fields'] as List).add({
      'id': 'optional',
      'label': 'Optional',
      'type': 'text',
      'required': false
    });
    await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'optional-draft',
      'expectedRevision': 1,
      'expectedVersionId': version,
      'spec': candidate
    });
    final review = (await api.execute('alice', {
      'op': 'spec.review',
      'appId': 'app',
      'expectedRevision': 2,
      'enabledRuleIds': [],
      'activateExistingRecordIds': []
    }))['review'] as Map;
    final command = {
      'op': 'spec.publish',
      'appId': 'app',
      'operationId': 'optional-publish',
      'expectedRevision': 2,
      'expectedVersionId': version,
      'candidateHash': review['candidateHash'],
      'reviewHash': review['reviewHash'],
      'enabledRuleIds': [],
      'activateExistingRecordIds': []
    };
    final before = jsonEncode(store.rows);
    await error(
        () => api.execute('alice', {...command, 'reviewHash': '0' * 64}),
        'invalid_review');
    check(jsonEncode(store.rows) == before, 'Bad review partially published');
    final published = await api.execute('alice', command);
    await error(
        () => api.execute(
            'alice', {...command, 'operationId': 'republish-consumed'}),
        'definition_conflict');
    check(
        jsonEncode(await api.execute('alice', command)) ==
            jsonEncode(published),
        'Consumed candidate lost receipt');
    final current =
        (((published['app'] as Map)['version'] as Map)['id']) as String;
    final destructive = clone(candidate);
    ((destructive['collections'] as List).single['fields'] as List).removeAt(1);
    await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'destructive',
      'expectedRevision': 2,
      'expectedVersionId': current,
      'spec': destructive
    });
    await error(() => publish(api, 'alice', 3, current, 'destructive-publish'),
        'incompatible_definition');
  });

  await test(
      'worker and private media effects fail closed without claiming permanent exclusions',
      () async {
    final (store, api, version) = await fixture('volunteer');
    final candidate = spec.starterTemplates()['volunteer']!;
    await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'worker-draft',
      'expectedRevision': 1,
      'expectedVersionId': version,
      'spec': candidate.toJson()
    });
    final rules = ['shiftReminder'];
    final reviewHash = spec.hashJson({
      'candidateHash': candidate.hash,
      'enabledRuleIds': rules,
      'activateExistingRecordIds': []
    });
    final before = jsonEncode(store.rows);
    await error(
        () => api.execute('alice', {
              'op': 'spec.publish',
              'appId': 'app',
              'operationId': 'worker-enable',
              'expectedRevision': 2,
              'expectedVersionId': version,
              'candidateHash': candidate.hash,
              'reviewHash': reviewHash,
              'enabledRuleIds': rules,
              'activateExistingRecordIds': []
            }),
        'capability_unavailable');
    check(jsonEncode(store.rows) == before,
        'Unavailable worker partially enabled');
    final (_, mediaApi, mediaVersion) = await fixture('photoJournal');
    final definition = spec.starterTemplates()['photoJournal']!;
    final create = definition.actions
        .firstWhere((action) => action.capability == 'records.create.v1');
    final collection = definition.collection(create.collectionId);
    final data = <String, dynamic>{};
    for (final field in collection.fields) {
      if (field.type == spec.FieldType.image) {
        data[field.id] = 'img_unavailable';
      } else if (field.required && field.type == spec.FieldType.text) {
        data[field.id] = 'Photo';
      } else if (field.required && field.type == spec.FieldType.timestamp) {
        data[field.id] = '2026-10-28T00:00:00Z';
      }
    }
    await error(
        () => mediaApi.execute('alice',
            action('unready-media', mediaVersion, create.id, {'data': data})),
        'capability_unavailable');
  });

  await test(
      'full action receipts survive publication and archive while changed payloads and revoked roles fail',
      () async {
    final (_, api, version) = await fixture('reading');
    await join(api, 'bob', 61, role: 'builder');
    final command = action('retained-action', version, 'addBook', {
      'data': {'title': 'Retained', 'status': 'Reading'}
    });
    final original = await api.execute('bob', command);
    final updated = clone(spec.starterTemplates()['reading']!.toJson())
      ..['name'] = 'A new name';
    await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'receipt-draft',
      'expectedRevision': 1,
      'expectedVersionId': version,
      'spec': updated
    });
    await publish(api, 'alice', 2, version, 'receipt-publish');
    check(jsonEncode(await api.execute('bob', command)) == jsonEncode(original),
        'Republish lost receipt');
    await error(
        () => api.execute('bob', {
              ...command,
              'input': {
                'data': {'title': 'Changed', 'status': 'Reading'}
              }
            }),
        'operation_conflict');
    await api.execute('alice',
        {'op': 'archiveApp', 'appId': 'app', 'operationId': 'archive-full'});
    check(jsonEncode(await api.execute('bob', command)) == jsonEncode(original),
        'Archive lost receipt');
    await api.execute('alice', {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'bob',
      'role': null,
      'expectedRevision': 1,
      'operationId': 'revoke-full'
    });
    await error(() => api.execute('bob', command), 'not_found');
  });

  await test(
      'full record version collection and tenant identities reject substituted parents',
      () async {
    final (_, api, version) = await fixture('reading');
    final made = await run(
        api,
        'alice',
        action('isolation-book', version, 'addBook', {
          'data': {'title': 'Private', 'status': 'Reading'}
        }));
    final id = made['recordId'] as String;
    await error(
        () => api.execute('mallory', {
              'op': 'spec.getRecord',
              'appId': 'app',
              'versionId': version,
              'recordId': id
            }),
        'not_found');
    await api.execute('alice', {
      'op': 'spec.createApp',
      'id': 'other',
      'workspaceId': 'ws',
      'name': 'Other',
      'operationId': 'create-other'
    });
    await error(
        () => api.execute('alice', {
              'op': 'spec.getRecord',
              'appId': 'other',
              'versionId': version,
              'recordId': id
            }),
        'not_published');
    await error(
        () => api.execute('alice', {
              'op': 'spec.query',
              'appId': 'app',
              'versionId': version,
              'collectionId': 'notBooks',
              'query': {}
            }),
        'invalid_spec');
    final draft = clone(spec.starterTemplates()['reading']!.toJson())
      ..['name'] = 'Renamed';
    await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'isolation-draft',
      'expectedRevision': 1,
      'expectedVersionId': version,
      'spec': draft
    });
    final next = await publish(api, 'alice', 2, version, 'isolation-publish');
    await error(
        () => api.execute('alice', {
              'op': 'spec.getRecord',
              'appId': 'app',
              'versionId': version,
              'recordId': id
            }),
        'definition_conflict');
    check(
        (await get(api, 'alice', next, id))['writtenUnderVersionId'] == version,
        'Publication rewrote record version');
  });

  await test(
      'all validated query operators and projection clearing retain source semantics',
      () async {
    final (_, api, version) = await fixture('reading');
    final a = await run(
        api,
        'alice',
        action('ops-a', version, 'addBook', {
          'data': {'title': 'Alpha', 'status': 'Reading', 'rating': 0}
        }));
    await run(
        api,
        'alice',
        action('ops-b', version, 'addBook', {
          'data': {'title': 'Beta', 'status': 'Finished', 'rating': 5}
        }));
    await run(
        api,
        'alice',
        action('ops-c', version, 'addBook', {
          'data': {'title': 'Gamma', 'status': 'Reading'}
        }));
    Future<int> count(List<Row> filters) async => (await api.execute('alice', {
          'op': 'spec.query',
          'appId': 'app',
          'versionId': version,
          'collectionId': 'books',
          'query': {'filters': filters}
        }))['total'] as int;
    check(
        await count([
              {'fieldId': 'rating', 'operator': 'gte', 'value': 0},
              {'fieldId': 'rating', 'operator': 'lt', 'value': 5}
            ]) ==
            1,
        'Range or zero comparison changed');
    check(
        await count([
              {'fieldId': 'rating', 'operator': 'lte', 'value': 5}
            ]) ==
            2,
        'Inclusive upper bound changed');
    check(
        await count([
              {
                'fieldId': 'status',
                'operator': 'in',
                'value': ['Reading']
              }
            ]) ==
            2,
        'Membership filter changed');
    check(
        await count([
              {'fieldId': 'title', 'operator': 'contains', 'value': 'ALP'}
            ]) ==
            1,
        'Contains is not case-insensitive');
    await run(
        api,
        'alice',
        action(
            'clear-rating',
            version,
            'editBook',
            {
              'data': {'rating': null}
            },
            record: a['recordId'] as String,
            revision: 1));
    check(
        await count([
              {'fieldId': 'rating', 'operator': 'eq', 'value': null}
            ]) ==
            2,
        'Projection did not clear null numeric field');
    await error(
        () => count([
              {'fieldId': 'rating', 'operator': 'contains', 'value': '0'}
            ]),
        'invalid_spec');
    await error(
        () => count([
              {
                'fieldId': 'status',
                'operator': 'in',
                'value': [null]
              }
            ]),
        'invalid_spec');
  });

  await test(
      'explicit UTC date buckets cover a 23-hour local day without machine timezone substitution',
      () async {
    final (_, api, version) = await fixture('reading');
    final definition = clone(spec.starterTemplates()['reading']!.toJson());
    ((definition['collections'] as List).single['fields'] as List).add({
      'id': 'when',
      'label': 'When',
      'type': 'timestamp',
      'required': false
    });
    await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'date-draft',
      'expectedRevision': 1,
      'expectedVersionId': version,
      'spec': definition
    });
    final current = await publish(api, 'alice', 2, version, 'date-publish');
    final times = [
      '2026-03-08T07:59:59Z',
      '2026-03-08T08:00:00Z',
      '2026-03-09T06:59:59.999999Z',
      '2026-03-09T07:00:00Z'
    ];
    for (var i = 0; i < times.length; i++)
      await run(
          api,
          'alice',
          action('date-$i', current, 'addBook', {
            'data': {'title': '$i', 'status': 'Reading', 'when': times[i]}
          }));
    final base = {
      'op': 'spec.aggregate',
      'appId': 'app',
      'versionId': current,
      'collectionId': 'books',
      'query': {'limit': 1}
    };
    final result = await api.execute('alice', {
      ...base,
      'aggregate': {
        'metric': 'count',
        'dateFieldId': 'when',
        'buckets': [
          {
            'key': 'Spring day',
            'start': '2026-03-08T08:00:00Z',
            'end': '2026-03-09T07:00:00Z'
          },
        ]
      }
    });
    check(
        result['total'] == 4 &&
            ((result['groups'] as List).single as Map)['value'] == 2,
        'UTC boundaries ignored DST day length');
    await error(
        () => api.execute('alice', {
              ...base,
              'aggregate': {
                'metric': 'count',
                'dateFieldId': 'when',
                'buckets': [
                  {
                    'key': 'Rollover',
                    'start': '2026-02-30T00:00:00Z',
                    'end': '2026-03-03T00:00:00Z'
                  },
                ]
              }
            }),
        'invalid_spec');
  });

  await test(
      'full records exceed bounded envelopes without changing their per-field contract',
      () async {
    final (store, api, version) = await fixture('reading');
    final definition = clone(spec.starterTemplates()['reading']!.toJson());
    final fields = (definition['collections'] as List).single['fields'] as List;
    for (var i = 0; i < 30; i++)
      fields.add({
        'id': 'extra$i',
        'label': 'Extra $i',
        'type': 'text',
        'required': false
      });
    await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'large-draft',
      'expectedRevision': 1,
      'expectedVersionId': version,
      'spec': definition
    });
    final current = await publish(api, 'alice', 2, version, 'large-publish');
    final data = <String, dynamic>{
      'title': 'Large',
      'status': 'Reading',
      for (var i = 0; i < 30; i++) 'extra$i': 'x' * 4000
    };
    check(utf8.encode(jsonEncode(data)).length > 65536,
        'Fixture did not exceed bounded request limit');
    final made = await run(api, 'alice',
        action('large-record', current, 'addBook', {'data': data}));
    final record = await get(api, 'alice', current, made['recordId'] as String);
    check(((record['data'] as Map)['extra29'] as String).length == 4000,
        'Large record truncated');
    check(store.rows['spec_values']!.length == 35,
        'Not all typed projections persisted');
  });

  await test(
      'full definition transport and archive receipts exceed old bounds while oversized specs preserve state',
      () async {
    final (store, api, version) = await fixture('reading');
    final definition = clone(spec.starterTemplates()['reading']!.toJson());
    final fields = (definition['collections'] as List).single['fields'] as List;
    for (var i = 0; i < 30; i++)
      fields.add({
        'id': 'choice$i',
        'label': 'Choice $i',
        'type': 'choice',
        'required': false,
        'choices': List.generate(20, (n) => '${i}_${n}_${'x' * 65}')
      });
    final canonical = spec.AppSpec.parse(jsonEncode(definition)).canonical;
    check(utf8.encode(canonical).length > 32768,
        'Definition fixture did not exceed legacy request budget');
    final saved = await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'big-spec',
      'expectedRevision': 1,
      'expectedVersionId': version,
      'spec': definition
    });
    check((saved['app'] as Map)['draft'] != null,
        'Large private definition was not saved');
    final current = await publish(api, 'alice', 2, version, 'big-spec-publish');
    final before = jsonEncode(store.rows);
    final tooLarge = clone(definition);
    for (final field
        in (((tooLarge['collections'] as List).single['fields'] as List)
            .skip(5))) {
      (field as Map)['choices'] = List.generate(30, (n) => '$n${'界' * 75}');
    }
    check(
        utf8.encode(jsonEncode(tooLarge)).length > spec.Limits.definitionBytes,
        'Oversize fixture too small');
    await error(
        () => api.execute('alice', {
              'op': 'spec.saveDraft',
              'appId': 'app',
              'operationId': 'oversized-spec',
              'expectedRevision': 2,
              'expectedVersionId': current,
              'spec': tooLarge
            }),
        'invalid_spec');
    check(jsonEncode(store.rows) == before,
        'Oversized definition changed private/published state');
    final archive = {
      'op': 'archiveApp',
      'appId': 'app',
      'operationId': 'archive-big-spec'
    };
    final response = await api.execute('alice', archive);
    check(utf8.encode(jsonEncode(response)).length > 65536,
        'Archive fixture did not exceed old receipt bound');
    check(
        jsonEncode(await api.execute('alice', archive)) == jsonEncode(response),
        'Large archive receipt was not exact');
  });

  await test(
      'timestamp projection schema preserves signed years and microsecond exact queries and buckets',
      () async {
    final schema = jsonDecode(await File('schema.json').readAsString()) as Map;
    final values = (schema['tables'] as List)
        .cast<Map>()
        .singleWhere((table) => table['tableId'] == 'spec_values');
    final column = Map<String, dynamic>.from((values['columns'] as List)
        .cast<Map>()
        .singleWhere((column) => column['key'] == 'timestampValue'));
    final store = ProjectionSchemaStore(column);
    final (_, api, previous) = await fixture('reading', store: store);
    final definition = clone(spec.starterTemplates()['reading']!.toJson());
    ((definition['collections'] as List).single['fields'] as List).add({
      'id': 'exactAt',
      'label': 'Exact timestamp',
      'type': 'timestamp',
      'required': false,
    });
    await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'timestamp-schema-draft',
      'expectedRevision': 1,
      'expectedVersionId': previous,
      'spec': definition,
    });
    final version =
        await publish(api, 'alice', 2, previous, 'timestamp-schema-publish');
    final times = [
      '2030-01-01T10:00:00.123456Z',
      '2030-01-01T10:00:00.123457Z',
      '-0001-01-01T00:00:00.000001Z',
      '+010000-01-01T00:00:00.000002Z',
    ];
    for (var i = 0; i < times.length; i++) {
      await run(
          api,
          'alice',
          action('timestamp-schema-record-$i', version, 'addBook', {
            'data': {
              'title': 'Timestamp $i',
              'status': 'Reading',
              'exactAt': times[i]
            },
          }));
      final response = await api.execute('alice', {
        'op': 'spec.query',
        'appId': 'app',
        'versionId': version,
        'collectionId': 'books',
        'query': {
          'filters': [
            {'fieldId': 'exactAt', 'operator': 'eq', 'value': times[i]}
          ],
        },
      });
      check(response['total'] == 1,
          'Lossy projection missed exact timestamp ${times[i]}');
    }
    final aggregate = await api.execute('alice', {
      'op': 'spec.aggregate',
      'appId': 'app',
      'versionId': version,
      'collectionId': 'books',
      'query': <String, dynamic>{},
      'aggregate': {
        'metric': 'count',
        'dateFieldId': 'exactAt',
        'buckets': [
          {'key': 'one-microsecond', 'start': times[0], 'end': times[1]},
        ]
      },
    });
    check(((aggregate['groups'] as List).single as Map)['value'] == 1,
        'Lossy projection changed half-open microsecond bucket count');
    check(column['type'] == 'varchar' && column['size'] == 64,
        'Timestamp projection must remain a bounded lossless canonical string');
  });

  return passed;
}

Future<void> main() async {
  final count = await runSpecEngineChecks();
  print(
      '$count full AppSpec engine checks passed (simulated store; live Cloud acceptance is separate).');
}
