import 'dart:convert';
import 'dart:io';

import '../lib/definition.dart';
import '../lib/service.dart';
import 'memory_store.dart';
import 'rich_contract_check.dart' as rich;

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

Future<void> expectError(Future<Object?> Function() run, String code) async {
  try {
    await run();
    throw StateError('Expected $code');
  } on ServiceException catch (error) {
    check(error.code == code, 'Expected $code, got ${error.code}');
  }
}

final definition = <String, dynamic>{
  'title': 'Tasks',
  'description': 'A small live list',
  'primaryFieldId': 'title',
  'fields': [
    {'id': 'title', 'label': 'Task', 'kind': 'text', 'required': true},
    {'id': 'done', 'label': 'Done', 'kind': 'boolean'},
    {
      'id': 'priority',
      'label': 'Priority',
      'kind': 'choice',
      'options': ['Soon', 'Today'],
    },
  ],
};
Map<String, dynamic> copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

Future<(MemoryStore, PlatformService)> fixture() async {
  final store = MemoryStore();
  final api = PlatformService(store);
  await api.execute('alice', {
    'op': 'createWorkspace',
    'id': 'workspace1',
    'name': ' My space ',
  });
  await api.execute('alice', {
    'op': 'createApp',
    'id': 'app1',
    'workspaceId': 'workspace1',
    'name': 'Tasks',
  });
  return (store, api);
}

Map<String, dynamic> draft(
  String operationId,
  int expected, [
  Map<String, dynamic>? spec,
]) =>
    {
      'op': 'saveDraft',
      'appId': 'app1',
      'expectedRevision': expected,
      'operationId': operationId,
      'definition': spec ?? definition,
    };
Map<String, dynamic> publish(String operationId, int expected) => {
      'op': 'publishApp',
      'appId': 'app1',
      'expectedRevision': expected,
      'operationId': operationId,
    };
Map<String, dynamic> record(
  String operationId,
  String id,
  int expected, {
  int published = 1,
  String title = 'Walk',
  String appId = 'app1',
}) =>
    {
      'op': 'saveRecord',
      'appId': appId,
      'id': id,
      'expectedRevision': expected,
      'definitionRevision': published,
      'operationId': operationId,
      'values': {'title': title, 'done': false, 'priority': 'Today'},
    };
Future<void> published(PlatformService api) async {
  await api.execute('alice', draft('draft-one', 0));
  await api.execute('alice', publish('publish-one', 1));
}

Future<void> main() async {
  var passed = 0;
  Future<void> test(String name, Future<void> Function() run) async {
    await run();
    passed++;
    print('PASS $name');
  }

  await test('basic owner isolation and exact app-create retry', () async {
    final (_, api) = await fixture();
    await api.execute('alice', {
      'op': 'createApp',
      'id': 'app1',
      'workspaceId': 'workspace1',
      'name': 'Tasks',
    });
    await expectError(
      () => api.execute('bob', {'op': 'getApp', 'appId': 'app1'}),
      'not_found',
    );
    await expectError(
      () => api.execute('bob', draft('bob-operation', 0)),
      'not_found',
    );
    await expectError(
      () => api.execute('alice', {
        'op': 'createApp',
        'id': 'app1',
        'workspaceId': 'workspace1',
        'name': 'Other',
      }),
      'id_conflict',
    );
    check(
      ((await api.execute('bob', {'op': 'listWorkspaces'}))['workspaces']
              as List)
          .isEmpty,
      'Tenant leak',
    );
  });
  await test(
    'saved definition and durable receipt survive later drafts',
    () async {
      final (_, api) = await fixture();
      final first = await api.execute('alice', draft('draft-one', 0));
      final next = copy(definition)..['title'] = 'A new title';
      await api.execute('alice', draft('draft-two', 1, next));
      check(
        canonicalJson(await api.execute('alice', draft('draft-one', 0))) ==
            canonicalJson(first),
        'Retry lost original receipt',
      );
      await expectError(
        () => api.execute('alice', draft('draft-one', 0, next)),
        'operation_conflict',
      );
      check(
        ((await api.execute('alice', {'op': 'getApp', 'appId': 'app1'}))['app']
                as Map)['draftRevision'] ==
            2,
        'Draft overwritten by retry',
      );
    },
  );
  await test('publication requires exact reviewed revision', () async {
    final (_, api) = await fixture();
    await api.execute('alice', draft('draft-one', 0));
    await expectError(
      () => api.execute('alice', publish('stale-publish', 0)),
      'revision_conflict',
    );
    await api.execute('alice', publish('publish-one', 1));
    final app = (await api
        .execute('alice', {'op': 'getApp', 'appId': 'app1'}))['app'] as Map;
    check(
      app['publishedRevision'] == 1 &&
          (app['publishedDefinition'] as Map)['title'] == 'Tasks',
      'Publication mismatch',
    );
  });
  await test(
    'live values are validated and record edits check revisions',
    () async {
      final (store, api) = await fixture();
      await published(api);
      final created = await api.execute(
        'alice',
        record('record-one', 'record1', 0),
      );
      check(
        (created['record'] as Map)['revision'] == 1,
        'Create revision missing',
      );
      final bad = record('bad-values', 'bad1', 0)
        ..['values'] = {'title': 'Bad', 'priority': 'Never'};
      await expectError(() => api.execute('alice', bad), 'invalid_values');
      check(
        store.rows['records']!.length == 1 &&
            !store.rows['receipts']!.containsKey('bad-values'),
        'Invalid write partially committed',
      );
      await api.execute(
        'alice',
        record('edit-one', 'record1', 1, title: 'Long walk'),
      );
      await expectError(
        () => api.execute(
          'alice',
          record('stale-edit', 'record1', 1, title: 'Stale'),
        ),
        'revision_conflict',
      );
      check(
        jsonDecode(
              store.rows['records']!['record1']!['valuesJson'] as String,
            )['title'] ==
            'Long walk',
        'Stale edit overwrote record',
      );
    },
  );
  await test(
    'record receipt resolves retry after record edit and publication',
    () async {
      final (_, api) = await fixture();
      await published(api);
      final command = record('record-one', 'record1', 0);
      final first = await api.execute('alice', command);
      await api.execute(
        'alice',
        record('edit-one', 'record1', 1, title: 'Edited'),
      );
      await api.execute(
        'alice',
        draft('draft-two', 1, copy(definition)..['title'] = 'Updated title'),
      );
      await api.execute('alice', publish('publish-two', 2));
      check(
        canonicalJson(await api.execute('alice', command)) ==
            canonicalJson(first),
        'Retry after publish did not return receipt',
      );
    },
  );
  await test('concurrent drafts conflict on common staged guard', () async {
    final (store, api) = await fixture();
    final results = await Future.wait(
      [draft('race-one', 0), draft('race-two', 0)].map((command) async {
        try {
          await api.execute('alice', command);
          return 'ok';
        } on ServiceException catch (e) {
          return e.code;
        }
      }),
    );
    check(
      results.where((value) => value == 'ok').length == 1,
      'More than one stale draft committed',
    );
    check(
      store.rows['receipts']!.length == 1 &&
          store.rows['apps']!['app1']!['draftRevision'] == 1,
      'Race state inconsistent',
    );
  });
  await test(
    'concurrent record edits produce one update and one receipt',
    () async {
      final (store, api) = await fixture();
      await published(api);
      await api.execute('alice', record('record-one', 'record1', 0));
      final results = await Future.wait(
        [
          record('edit-a', 'record1', 1, title: 'A'),
          record('edit-b', 'record1', 1, title: 'B'),
        ].map((command) async {
          try {
            await api.execute('alice', command);
            return 'ok';
          } on ServiceException catch (e) {
            return e.code;
          }
        }),
      );
      check(
        results.where((value) => value == 'ok').length == 1,
        'Concurrent stale record edits both committed',
      );
      check(
        store.rows['records']!['record1']!['revision'] == 2,
        'Record revision inconsistent',
      );
    },
  );
  await test(
    'transaction failure rolls back guard business data and receipt',
    () async {
      final (store, api) = await fixture();
      final before = canonicalJson(store.rows['apps']!['app1']);
      store.failBeforeCommit = true;
      try {
        await api.execute('alice', draft('failed-draft', 0));
        throw StateError('Expected commit failure');
      } on RestException catch (e) {
        check(e.status == 502, 'Unexpected failure');
      }
      check(
        canonicalJson(store.rows['apps']!['app1']) == before,
        'App partially modified',
      );
      check(
        store.rows['receipts'] == null && store.transactions.isEmpty,
        'Transaction/receipt leaked',
      );
    },
  );
  await test(
    'unknown commit response is reconciled by exact stored receipt',
    () async {
      final (store, api) = await fixture();
      store.loseCommitResponse = true;
      final command = draft('lost-draft', 0);
      try {
        await api.execute('alice', command);
        throw StateError('Expected lost response');
      } on RestException catch (_) {
        /* Simulated committed-but-unconfirmed outcome. */
      }
      final recovered = await api.execute('alice', command);
      check(
        (recovered['app'] as Map)['draftRevision'] == 1 &&
            store.rows['receipts']!.length == 1,
        'Recovery duplicated mutation',
      );
    },
  );
  await test(
    'compatible additions retain old records and normalize optional fields',
    () async {
      final (_, api) = await fixture();
      await published(api);
      await api.execute('alice', record('record-one', 'record1', 0));
      final next = copy(definition);
      (next['fields'] as List).add({
        'id': 'detail',
        'label': 'Detail',
        'kind': 'longText',
      });
      await api.execute('alice', draft('draft-two', 1, next));
      await api.execute('alice', publish('publish-two', 2));
      final page = await api.execute('alice', {
        'op': 'listRecords',
        'appId': 'app1',
        'definitionRevision': 2,
      });
      check(
        (((page['records'] as List).single as Map)['values']
                as Map)['detail'] ==
            '',
        'Optional field was not normalized',
      );
      await expectError(
        () => api.execute('alice', record('stale-schema', 'record2', 0)),
        'definition_conflict',
      );
    },
  );
  await test('destructive field evolution cannot publish', () async {
    final (_, api) = await fixture();
    await published(api);
    final next = copy(definition);
    (next['fields'] as List).removeLast();
    await api.execute('alice', draft('draft-two', 1, next));
    await expectError(
      () => api.execute('alice', publish('bad-publication', 2)),
      'incompatible_definition',
    );
    final app = (await api
        .execute('alice', {'op': 'getApp', 'appId': 'app1'}))['app'] as Map;
    check(
      app['publishedRevision'] == 1,
      'Incompatible version replaced live definition',
    );
  });
  await test(
    'record paging is deterministic and cross-app cursors are denied',
    () async {
      final (_, api) = await fixture();
      await published(api);
      for (var i = 0; i < 23; i++) {
        await api.execute(
          'alice',
          record(
            'create-${i.toString().padLeft(2, '0')}',
            'record${i.toString().padLeft(2, '0')}',
            0,
          ),
        );
      }
      final first = await api.execute('alice', {
        'op': 'listRecords',
        'appId': 'app1',
        'definitionRevision': 1,
      });
      final second = await api.execute('alice', {
        'op': 'listRecords',
        'appId': 'app1',
        'definitionRevision': 1,
        'afterId': first['nextCursor'],
      });
      final third = await api.execute('alice', {
        'op': 'listRecords',
        'appId': 'app1',
        'definitionRevision': 1,
        'afterId': second['nextCursor'],
      });
      check(
        (first['records'] as List).length == 10 &&
            (second['records'] as List).length == 10 &&
            (third['records'] as List).length == 3 &&
            third['nextCursor'] == null,
        'Pagination lost records',
      );
      await expectError(
        () => api.execute('bob', {
          'op': 'listRecords',
          'appId': 'app1',
          'definitionRevision': 1,
          'afterId': first['nextCursor'],
        }),
        'not_found',
      );
    },
  );
  await test(
    'bounded definition rejects unknown fields bad IDs and oversized values',
    () async {
      final (_, api) = await fixture();
      await expectError(
        () => api.execute(
          'alice',
          draft('invalid-def', 0, {...definition, 'code': 'execute()'}),
        ),
        'invalid_definition',
      );
      await expectError(
        () => api.execute('alice', {
          ...draft('invalid-rev', 0),
          'expectedRevision': 0.5,
        }),
        'invalid_revision',
      );
      await expectError(
        () => api.execute('alice', {
          ...draft('invalid-id', 0),
          'appId': '../bad',
        }),
        'invalid_id',
      );
      await published(api);
      await expectError(
        () => api.execute('alice', {
          ...record('invalid-row', 'record1', 0),
          'values': {'title': 'x' * 201},
        }),
        'invalid_values',
      );
    },
  );
  await test(
    'REST adapter emits Appwrite attribute queries and staged transaction parameters',
    transportCheck,
  );
  passed += await rich.runRichChecks();
  print(
    '$passed backend checks passed (simulated store and local HTTP transport; live Appwrite acceptance is separate).',
  );
}

Future<void> transportCheck() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests = <Map<String, dynamic>>[];
  final subscription = server.listen((request) async {
    final text = await utf8.decoder.bind(request).join();
    requests.add({
      'method': request.method,
      'uri': request.uri,
      'body': text.isEmpty ? null : jsonDecode(text),
      'key': request.headers.value('x-appwrite-key'),
      'jwt': request.headers.value('x-appwrite-jwt'),
    });
    request.response.headers.contentType = ContentType.json;
    final path = request.uri.path;
    request.response.write(
      jsonEncode(
        path.endsWith('/transactions')
            ? {r'$id': 'tx1'}
            : path.endsWith('/account')
                ? {r'$id': 'alice'}
                : path.endsWith('/rows') && request.method == 'GET'
                    ? {'total': 0, 'rows': []}
                    : {r'$id': 'app1', 'ownerId': 'alice'},
      ),
    );
    await request.response.close();
  });
  final rest = AppwriteRest(
    Uri.parse('http://127.0.0.1:${server.port}/v1'),
    'project',
    'database',
    'ephemeral-key',
  );
  try {
    await rest.list(
      'apps',
      {'ownerId': 'alice'},
      afterId: 'app0',
      limit: 11,
      detectOverflow: false,
    );
    final uri = requests.last['uri'] as Uri;
    final equal = jsonDecode(uri.queryParameters['queries[0]']!) as Map;
    check(
      equal['attribute'] == 'ownerId' && !equal.containsKey('column'),
      'Wrong equality query encoding',
    );
    check(
      jsonDecode(uri.queryParameters['queries[3]']!)['method'] == 'cursorAfter',
      'Cursor missing',
    );
    check(await rest.beginTransaction() == 'tx1', 'Transaction ID not parsed');
    await rest.update(
        'apps',
        'app1',
        {
          'guard': 'guard1',
        },
        transactionId: 'tx1');
    check(
      (requests.last['body'] as Map)['transactionId'] == 'tx1',
      'Update transaction ID missing',
    );
    await rest.get('apps', 'app1', transactionId: 'tx1');
    check(
      (requests.last['uri'] as Uri).queryParameters['transactionId'] == 'tx1',
      'Read transaction ID missing',
    );
    await rest.finishTransaction('tx1', commit: true);
    check(
      (requests.last['body'] as Map)['commit'] == true,
      'Commit parameter missing',
    );
    await rest.account('user-jwt');
    check(
      requests.last['jwt'] == 'user-jwt' && requests.last['key'] == null,
      'Mixed privileged and user auth headers',
    );
  } finally {
    rest.close();
    await subscription.cancel();
    await server.close(force: true);
  }
}
