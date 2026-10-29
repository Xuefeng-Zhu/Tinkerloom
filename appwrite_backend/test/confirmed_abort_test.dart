import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../lib/service.dart';
import 'memory_store.dart';

const conflict = {'type': 'transaction_conflict', 'code': 409};
Matcher get confirmed => predicate<Object>(
  (error) =>
      error is RestException &&
      error.runtimeType.toString() == 'ConfirmedTransactionAbort',
  'confirmed terminal commit abort',
);
Matcher get ordinary => predicate<Object>(
  (error) => error is RestException && error.runtimeType == RestException,
  'ordinary conservative REST error',
);

Future<void> transportCase({
  Object? error = conflict,
  int status = 409,
  Object? terminal = const {r'$id': 'tx', 'status': 'failed'},
  int terminalStatus = 200,
  bool terminalTimeout = false,
  bool commit = true,
  bool staging = false,
  required Matcher expected,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final calls = <Row>[];
  server.listen((request) async {
    final body = await utf8.decoder.bind(request).join();
    calls.add({
      'method': request.method,
      'path': request.uri.path,
      'body': body,
    });
    expect(request.headers.value('X-Appwrite-Key'), 'synthetic-key');
    expect(request.headers.value('X-Appwrite-JWT'), isNull);
    request.response.headers.contentType = ContentType.json;
    if (request.method == 'GET') {
      if (terminalTimeout) {
        await Future<void>.delayed(const Duration(seconds: 17));
        try {
          await request.response.close();
        } catch (_) {}
        return;
      }
      request.response.statusCode = terminalStatus;
      request.response.write(
        terminal is String ? terminal : jsonEncode(terminal),
      );
    } else {
      request.response.statusCode = status;
      request.response.write(error is String ? error : jsonEncode(error));
    }
    await request.response.close();
  });
  final rest = AppwriteRest(
    Uri.parse('http://127.0.0.1:${server.port}/v1'),
    'project',
    'db',
    'synthetic-key',
  );
  try {
    await expectLater(
      staging
          ? rest.update('apps', 'app', {'name': 'x'}, transactionId: 'tx')
          : rest.finishTransaction('tx', commit: commit),
      throwsA(expected),
    );
    expect(calls.first['method'], 'PATCH');
    expect(
      calls.first['path'],
      staging
          ? '/v1/tablesdb/db/tables/apps/rows/app'
          : '/v1/tablesdb/transactions/tx',
    );
    if (!staging)
      expect(jsonDecode(calls.first['body'] as String), {
        commit ? 'commit' : 'rollback': true,
      });
    if (!commit || staging || status != 409 || error != conflict) {
      // Other errors are never promoted merely because their HTTP status is409.
      expect(
        calls.where((call) => call['method'] == 'GET').length,
        lessThanOrEqualTo(1),
      );
    }
  } finally {
    rest.close();
    await server.close(force: true);
  }
}

/// Explicit local Appwrite REST simulation: actual PlatformService, worker,
/// optimistic MemoryStore and transport; not Cloud transaction evidence.
class CloudStore extends MemoryStore {
  bool armed = false;
  Completer<void>? paused, resume;
  void arm() {
    armed = true;
    paused = Completer<void>();
    resume = Completer<void>();
  }

  @override
  Future<Row> update(
    String table,
    String id,
    Row data, {
    String? transactionId,
  }) async {
    final result = await super.update(
      table,
      id,
      data,
      transactionId: transactionId,
    );
    if (armed && table == 'workspaces' && transactionId != null) {
      armed = false;
      paused!.complete();
      await resume!.future;
    }
    return result;
  }
}

class LocalDatabase {
  LocalDatabase(this.server, this.memory) {
    rest = AppwriteRest(
      Uri.parse('http://127.0.0.1:${server.port}/v1'),
      'project',
      'db',
      'synthetic-key',
    );
    service = PlatformService(
      rest,
      remindersEnabled: true,
      clock: () => DateTime.utc(2030, 1, 2),
    );
    server.listen(handle);
  }
  static Future<LocalDatabase> create() async => LocalDatabase(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    CloudStore(),
  );
  final HttpServer server;
  final CloudStore memory;
  late final AppwriteRest rest;
  late final PlatformService service;
  final states = <String, String>{};
  final commits = <String>[];
  final getStates = <String>[];
  int forcedAborts = 0;
  bool ambiguous = false;
  bool loseCommitReply = false;
  Future<void> Function()? afterAbort;
  Future<void> close() async {
    rest.close();
    await server.close(force: true);
  }

  Future<void> handle(HttpRequest request) async {
    Row? body;
    final text = await utf8.decoder.bind(request).join();
    if (text.isNotEmpty)
      body = Map<String, dynamic>.from(jsonDecode(text) as Map);
    request.response.headers.contentType = ContentType.json;
    Object? output;
    try {
      final path = request.uri.pathSegments;
      if (path.length == 3 && path[2] == 'transactions') {
        final tx = await memory.beginTransaction();
        states[tx] = 'pending';
        output = {r'$id': tx, 'status': 'pending'};
      } else if (path.length == 4 && path[2] == 'transactions') {
        final tx = path[3];
        if (request.method == 'GET') {
          getStates.add(tx);
          output = {r'$id': tx, 'status': states[tx]};
        } else if (body?['rollback'] == true) {
          if (states[tx] != 'pending') throw const RestException(409);
          await memory.finishTransaction(tx, commit: false);
          states[tx] = 'rolled_back';
          output = {r'$id': tx, 'status': 'rolled_back'};
        } else {
          commits.add(tx);
          try {
            if (forcedAborts > 0) {
              forcedAborts--;
              throw const RestException(409);
            }
            await memory.finishTransaction(tx, commit: true);
            states[tx] = 'committed';
            output = {r'$id': tx, 'status': 'committed'};
            if (loseCommitReply) {
              loseCommitReply = false;
              request.response.statusCode = 502;
              output = {'type': 'general_unknown', 'code': 502};
            }
          } on RestException catch (error) {
            if (error.status != 409) rethrow;
            await memory.finishTransaction(tx, commit: false);
            states[tx] = 'failed';
            final callback = afterAbort;
            afterAbort = null;
            if (callback != null) await callback();
            request.response.statusCode = ambiguous ? 502 : 409;
            output = ambiguous
                ? {'type': 'general_unknown', 'code': 502}
                : conflict;
          }
        }
      } else {
        final table = path[4], rowId = path.length > 6 ? path[6] : null;
        final tx =
            body?['transactionId'] as String? ??
            request.uri.queryParameters['transactionId'];
        if (request.method == 'POST') {
          output = await memory.create(
            table,
            body!['rowId'] as String,
            Map<String, dynamic>.from(body['data'] as Map),
            transactionId: tx,
          );
        } else if (request.method == 'PATCH') {
          output = await memory.update(
            table,
            rowId!,
            Map<String, dynamic>.from(body!['data'] as Map),
            transactionId: tx,
          );
        } else if (rowId != null) {
          output = await memory.get(table, rowId, transactionId: tx);
          if (output == null) throw const RestException(404);
        } else {
          final filters = <String, String>{};
          var limit = 100;
          String? after;
          List<String>? select;
          for (final query in request.uri.queryParameters.entries.where(
            (entry) => entry.key.startsWith('queries['),
          )) {
            final data = jsonDecode(query.value) as Row;
            switch (data['method']) {
              case 'equal':
                filters[data['attribute'] as String] = (data['values'] as List)
                    .single
                    .toString();
              case 'limit':
                limit = (data['values'] as List).single as int;
              case 'cursorAfter':
                after = (data['values'] as List).single as String;
              case 'select':
                select = (data['values'] as List).cast<String>();
            }
          }
          final rows = await memory.list(
            table,
            filters,
            transactionId: tx,
            limit: limit,
            afterId: after,
            detectOverflow: false,
            select: select,
          );
          output = {'total': rows.length, 'rows': rows};
        }
      }
    } on RestException catch (error) {
      request.response.statusCode = error.status;
      output = {'type': 'transaction_not_ready', 'code': error.status};
    }
    request.response.write(jsonEncode(output));
    await request.response.close();
  }

  Future<void> setup() async {
    await service.execute('alice', {
      'op': 'createWorkspace',
      'id': 'ws',
      'name': 'Workspace',
    });
    await instantiate('app-one');
    await instantiate('app-two');
  }

  Future<Row> instantiate(String id, {String actor = 'alice'}) =>
      service.execute(actor, {
        'op': 'spec.instantiate',
        'id': id,
        'workspaceId': 'ws',
        'operationId': 'create-$id',
        'templateKey': 'chores',
      });
}

void main() {
  test(
    'only exact commit conflict plus matching terminal state is classified',
    () async {
      await transportCase(expected: confirmed);
      await transportCase(
        terminal: {r'$id': 'tx', 'status': 'rolled_back'},
        expected: confirmed,
      );
    },
  );
  test(
    'noncommit or wrong HTTP/code/type/body conflicts remain ordinary',
    () async {
      for (final error in [
        {'type': 'transaction_not_ready', 'code': 409},
        {'type': 'transaction_conflict', 'code': 500},
        {'type': 'transaction_conflict', 'code': 409.0},
        {'type': 'transaction_conflict', 'code': 409, 'private': 'never log'},
        {'type': 'transaction_conflict', 'code': 409, 'message': {}},
        'not-json',
        [],
        {'type': 'transaction_conflict', 'code': 409, 'message': 'x' * 9000},
      ])
        await transportCase(error: error, expected: ordinary);
      await transportCase(status: 502, expected: ordinary);
      await transportCase(commit: false, expected: ordinary);
      await transportCase(staging: true, expected: ordinary);
    },
  );
  test(
    'unconfirmed state status identity and schema never enable retry',
    () async {
      for (final terminal in [
        {r'$id': 'other', 'status': 'failed'},
        for (final state in ['pending', 'committing', 'committed', 'unknown'])
          {r'$id': 'tx', 'status': state},
        'malformed',
        [],
        {r'$id': 'tx'},
      ])
        await transportCase(terminal: terminal, expected: ordinary);
      for (final status in [403, 404, 500, 502])
        await transportCase(terminalStatus: status, expected: ordinary);
    },
  );
  test(
    'transaction state timeout never enables retry',
    () async {
      await transportCase(terminalTimeout: true, expected: ordinary);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  test(
    'actual worker versus instantiate race retries only its aborted attempt',
    () async {
      final f = await LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      final before = f.commits.length;
      f.memory.arm();
      final pending = f.instantiate('app-three');
      await f.memory.paused!.future;
      try {
        await WorkerEngine(f.service).reminders();
      } finally {
        f.memory.resume!.complete();
      }
      final result = await pending;
      expect((result['app'] as Row)['id'], 'app-three');
      expect(f.getStates, hasLength(1));
      expect(f.commits.skip(before).toSet().length, f.commits.length - before);
      expect(
        f.memory.rows['spec_versions']!.values.where(
          (row) => row['appId'] == 'app-three',
        ),
        hasLength(1),
      );
      expect(
        f.memory.rows['audit']!.values.where(
          (row) => row['appId'] == 'app-three',
        ),
        hasLength(1),
      );
      expect(
        f.memory.rows['receipts']!.values.where(
          (row) => row['appId'] == 'app-three',
        ),
        hasLength(1),
      );
    },
  );
  test(
    'instantiate exhausts two retries and never retries ambiguous commit',
    () async {
      for (final ambiguous in [false, true]) {
        final f = await LocalDatabase.create();
        addTearDown(f.close);
        await f.setup();
        final before = f.commits.length;
        f.forcedAborts = 5;
        f.ambiguous = ambiguous;
        await expectLater(f.instantiate('no-app'), throwsA(anything));
        expect(f.commits.length - before, ambiguous ? 1 : 3);
        expect(f.memory.rows['apps']?['no-app'], isNull);
      }
    },
  );
  test(
    'lost successful commit reply never triggers an internal repeat and its exact receipt remains recoverable',
    () async {
      final f = await LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      final before = f.commits.length;
      f.loseCommitReply = true;
      await expectLater(f.instantiate('lost'), throwsA(isA<RestException>()));
      expect(f.commits.length - before, 1);
      expect(f.memory.rows['apps']?['lost'], isNotNull);
      expect(f.getStates, isEmpty);
      final recovered = await f.instantiate('lost');
      expect((recovered['app'] as Row)['id'], 'lost');
      expect(f.commits.length - before, 1);
    },
  );
  test('new transaction rechecks workspace authority and app quota', () async {
    for (final change in ['authority', 'quota']) {
      final f = await LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      f.forcedAborts = 1;
      f.afterAbort = () async {
        if (change == 'authority') {
          await f.memory.update('workspaces', 'ws', {'ownerId': 'outsider'});
          for (final row in f.memory.rows['memberships']!.values.toList())
            if (row['actorId'] == 'alice')
              await f.memory.update('memberships', row[r'$id'] as String, {
                'active': false,
              });
        } else {
          for (var n = 0; n < 98; n++)
            await f.memory.create('apps', 'quota-$n', {'workspaceId': 'ws'});
        }
      };
      await expectLater(
        f.instantiate('denied'),
        throwsA(
          isA<ServiceException>().having(
            (e) => e.code,
            'code',
            change == 'quota' ? 'quota_exceeded' : 'not_found',
          ),
        ),
      );
      expect(f.memory.rows['apps']?['denied'], isNull);
    }
  });
  Future<Row> invite(
    LocalDatabase f, {
    String issuer = 'alice',
    String tokenId = 'invite',
    String recipient = 'bob',
  }) async {
    final token = base64Url
        .encode(List.generate(32, (n) => n))
        .replaceAll('=', '');
    await f.service.execute(issuer, {
      'op': 'createInvitation',
      'appId': 'app-one',
      'id': tokenId,
      'operationId': 'create-$tokenId',
      'token': token,
      'recipientId': recipient,
      'role': 'member',
    });
    return {
      'op': 'acceptInvitation',
      'token': token,
      'operationId': 'accept-$tokenId',
    };
  }

  test(
    'actual worker versus acceptance race preserves one grant receipt audit and current access',
    () async {
      final f = await LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      final input = await invite(f);
      f.memory.arm();
      final pending = f.service.execute('bob', input);
      await f.memory.paused!.future;
      try {
        await WorkerEngine(f.service).reminders();
      } finally {
        f.memory.resume!.complete();
      }
      expect(await pending, {'appId': 'app-one'});
      final app =
          (await f.service.execute('bob', {
                'op': 'getAppAccess',
                'appId': 'app-one',
              }))['app']
              as Row;
      expect(app['role'], 'member');
      expect(f.getStates, hasLength(1));
      expect(
        f.memory.rows['grants']!.values.where((row) => row['actorId'] == 'bob'),
        hasLength(1),
      );
      expect(f.memory.rows['receipts']!['accept-invite'], isNotNull);
      expect(
        f.memory.rows['audit']!.values.where((row) => row['action'] == 'join'),
        hasLength(1),
      );
      expect(await f.service.execute('bob', input), {'appId': 'app-one'});
    },
  );
  test(
    'acceptance rechecks invitation revocation and actor workspace quota on fresh attempts',
    () async {
      for (final change in ['invitation', 'quota']) {
        final f = await LocalDatabase.create();
        addTearDown(f.close);
        await f.setup();
        final input = await invite(f);
        f.forcedAborts = 1;
        f.afterAbort = () async {
          if (change == 'invitation') {
            await f.memory.update('invitations', 'invite', {'revoked': true});
          } else {
            for (var n = 0; n < 100; n++)
              await f.memory.create('workspaces', 'bob-$n', {'ownerId': 'bob'});
          }
        };
        await expectLater(
          f.service.execute('bob', input),
          throwsA(
            isA<ServiceException>().having(
              (e) => e.code,
              'code',
              change == 'quota' ? 'quota_exceeded' : 'invitation_unavailable',
            ),
          ),
        );
        expect(f.memory.rows['receipts']?['accept-invite'], isNull);
        expect(
          f.memory.rows['grants']?.values.where(
                (row) => row['actorId'] == 'bob',
              ) ??
              [],
          isEmpty,
        );
        expect(
          f.memory.rows['memberships']?.values.where(
                (row) => row['actorId'] == 'bob',
              ) ??
              [],
          isEmpty,
        );
      }
    },
  );
  test(
    'acceptance rechecks issuer grant generation after a confirmed abort',
    () async {
      final f = await LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      final token = base64Url
          .encode(List.generate(32, (n) => n + 1))
          .replaceAll('=', '');
      await f.service.execute('alice', {
        'op': 'createInvitation',
        'appId': 'app-one',
        'id': 'builder',
        'operationId': 'invite-builder',
        'token': token,
        'recipientId': 'builder',
        'role': 'builder',
      });
      await f.service.execute('builder', {
        'op': 'acceptInvitation',
        'token': token,
        'operationId': 'join-builder',
      });
      final input = await invite(f, issuer: 'builder');
      f.forcedAborts = 1;
      f.afterAbort = () async {
        final grant = f.memory.rows['grants']!.values.singleWhere(
          (row) => row['actorId'] == 'builder',
        );
        await f.memory.update('grants', grant[r'$id'] as String, {
          'revision': 2,
        });
      };
      await expectLater(
        f.service.execute('bob', input),
        throwsA(
          isA<ServiceException>().having(
            (e) => e.code,
            'code',
            'invitation_unavailable',
          ),
        ),
      );
      expect(f.memory.rows['receipts']?['accept-invite'], isNull);
      expect(
        f.memory.rows['grants']!.values.where((row) => row['actorId'] == 'bob'),
        isEmpty,
      );
    },
  );
  test(
    'remix and generic mutations remain opted out despite typed confirmed abort',
    () async {
      for (final op in ['archiveApp', 'spec.remix']) {
        final f = await LocalDatabase.create();
        addTearDown(f.close);
        await f.setup();
        final version = f.memory.rows['spec_versions']!.values.firstWhere(
          (row) => row['appId'] == 'app-one',
        )[r'$id'];
        final before = f.commits.length;
        f.forcedAborts = 1;
        await expectLater(
          f.service.execute(
            'alice',
            op == 'archiveApp'
                ? {'op': op, 'appId': 'app-one', 'operationId': 'archive'}
                : {
                    'op': op,
                    'id': 'remix',
                    'workspaceId': 'ws',
                    'sourceAppId': 'app-one',
                    'sourceVersionId': version,
                    'operationId': 'remix',
                  },
          ),
          throwsA(isA<ServiceException>()),
        );
        expect(f.commits.length - before, 1);
        expect(f.memory.rows['apps']?['remix'], isNull);
        expect(f.memory.rows['apps']!['app-one']!['archived'], false);
      }
    },
  );
}
