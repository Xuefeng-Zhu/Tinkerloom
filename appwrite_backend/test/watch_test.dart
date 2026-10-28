import 'dart:convert';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import '../lib/service.dart';
import 'memory_store.dart';
import 'spec_engine_check.dart' as checks;

Future<Row> watch(
  PlatformService api, {
  String actor = 'alice',
  String appId = 'app',
}) => api.execute(actor, {'op': 'spec.watch', 'appId': appId});
String identity(String kind, List<String> parts) =>
    '$kind${sha256.convert(utf8.encode(jsonEncode(parts))).toString().substring(0, 32)}';

class MetadataOnlyStore extends MemoryStore {
  bool armed = false;
  @override
  Future<Row?> get(String table, String id, {String? transactionId}) {
    if (armed &&
        {
          'spec_versions',
          'spec_drafts',
          'spec_records',
          'drafts',
          'records',
        }.contains(table))
      throw StateError('Watch hydrated business data: $table');
    return super.get(table, id, transactionId: transactionId);
  }

  @override
  Future<List<Row>> list(
    String table,
    Map<String, String> filters, {
    String? transactionId,
    int limit = 100,
    String? afterId,
    bool detectOverflow = true,
    List<String>? select,
  }) {
    if (armed) throw StateError('Watch enumerated rows');
    return super.list(
      table,
      filters,
      transactionId: transactionId,
      limit: limit,
      afterId: afterId,
      detectOverflow: detectOverflow,
      select: select,
    );
  }
}

class RevokeAfterHydration extends MemoryStore {
  bool armed = false;
  Future<void> Function()? revoke;
  @override
  Future<Row?> get(String table, String id, {String? transactionId}) async {
    final row = await super.get(table, id, transactionId: transactionId);
    if (armed &&
        table == 'grants' &&
        row?['actorId'] == 'bob' &&
        transactionId != null) {
      armed = false;
      await revoke!();
    }
    return row;
  }
}

Future<void> changeGrant(
  PlatformService api,
  String? role, {
  int revision = 1,
  String operation = 'change-grant',
}) => api.execute('alice', {
  'op': 'setGrant',
  'appId': 'app',
  'actorId': 'bob',
  'expectedRevision': revision,
  'role': role,
  'operationId': operation,
});

void main() {
  test(
    'capabilities negotiate bounded polling without claiming realtime or row permissions',
    () async {
      final api = PlatformService(MemoryStore());
      final caps = await api.execute('alice', {'op': 'spec.capabilities'});
      expect(caps['invalidations'], {
        'mode': 'poll.v1',
        'minimumIntervalMs': 15000,
      });
      expect((caps['parserCapabilities'] as List), contains('collections.v1'));
      expect(caps.containsKey('realtime'), false);
    },
  );
  test(
    'watch returns only exact semantic metadata without loading versions candidates or records',
    () async {
      final store = MetadataOnlyStore();
      final (_, api, version) = await checks.fixture('reading', store: store);
      store.armed = true;
      final state = await watch(api);
      expect(state.keys.toSet(), {
        'appId',
        'versionId',
        'controlRevision',
        'role',
        'archived',
      });
      expect(state, {
        'appId': 'app',
        'versionId': version,
        'controlRevision': 3,
        'role': 'owner',
        'archived': false,
      });
      expect(jsonEncode(state), isNot(contains('guard')));
    },
  );
  test(
    'unpublished shells are owner-only even for an otherwise valid builder grant',
    () async {
      final store = MemoryStore();
      final service = PlatformService(store);
      await service.execute('alice', {
        'op': 'createWorkspace',
        'id': 'ws',
        'name': 'Workspace',
      });
      await service.execute('alice', {
        'op': 'spec.createApp',
        'id': 'app',
        'workspaceId': 'ws',
        'name': 'Private shell',
        'operationId': 'create',
      });
      // An authorization fixture isolates the published-or-owner boundary from
      // the invitation flow, whose access contracts have their own tests.
      await store.create('memberships', identity('m', ['ws', 'bob']), {
        'workspaceId': 'ws',
        'actorId': 'bob',
        'active': true,
      });
      await store.create('grants', identity('g', ['app', 'bob']), {
        'workspaceId': 'ws',
        'appId': 'app',
        'actorId': 'bob',
        'role': 'builder',
        'revoked': false,
      });
      expect((await watch(service))['versionId'], isNull);
      await checks.error(() => watch(service, actor: 'bob'), 'not_found');
    },
  );
  test(
    'normal reads and repeated identical watch IDs change guards but leave the semantic snapshot stable',
    () async {
      final (store, api, version) = await checks.fixture('reading');
      final before = await watch(api);
      final guard = store.rows['apps']!['app']!['guard'];
      for (var i = 0; i < 4; i++) expect(await watch(api), before);
      await api.execute('alice', {'op': 'spec.getApp', 'appId': 'app'});
      await api.execute('alice', {'op': 'getAppAccess', 'appId': 'app'});
      await api.execute('alice', {
        'op': 'spec.query',
        'appId': 'app',
        'versionId': version,
        'collectionId': 'books',
        'query': <String, dynamic>{},
      });
      await api.execute('alice', {
        'op': 'spec.launcher',
        'workspaceId': 'ws',
        'limit': 50,
      });
      await api.execute('alice', {
        'op': 'spec.listVersions',
        'appId': 'app',
        'limit': 25,
      });
      await api.execute('alice', {
        'op': 'spec.getVersion',
        'appId': 'app',
        'versionId': version,
      });
      expect(await watch(api), before);
      expect(store.rows['apps']!['app']!['guard'], isNot(guard));
      await api.execute('alice', {
        'op': 'spec.setPinned',
        'appId': 'app',
        'pinned': true,
        'expectedRevision': 0,
        'operationId': 'pin',
      });
      expect(
        await watch(api),
        before,
        reason: 'Personal shortcuts are not shared runtime state',
      );
    },
  );
  test(
    'record actions update control state once while exact receipt replay and record reads stay stable',
    () async {
      final (_, api, version) = await checks.fixture('reading');
      final before = await watch(api);
      final created = await checks.run(
        api,
        'alice',
        checks.action('new-record', version, 'addBook', {
          'data': {'title': 'QA book', 'status': 'Reading'},
        }),
      );
      final afterCreate = await watch(api);
      expect(
        afterCreate['controlRevision'],
        (before['controlRevision'] as int) + 1,
      );
      expect(afterCreate['versionId'], version);
      final id = created['recordId'] as String;
      await checks.get(api, 'alice', version, id);
      expect(await watch(api), afterCreate);
      final edit = checks.action(
        'edit-record',
        version,
        'editBook',
        {
          'data': {'notes': 'Edited'},
        },
        record: id,
        revision: 1,
      );
      await api.execute('alice', edit);
      final afterEdit = await watch(api);
      expect(
        afterEdit['controlRevision'],
        (afterCreate['controlRevision'] as int) + 1,
      );
      await api.execute('alice', edit);
      expect(await watch(api), afterEdit);
    },
  );
  test(
    'saved candidates and publication advance semantic state while review and snapshot reads do not',
    () async {
      final (_, api, version) = await checks.fixture('reading');
      final before = await watch(api);
      final candidate = Map<String, dynamic>.from(
        spec.starterTemplates()['reading']!.toJson(),
      )..['name'] = 'Reading ledger';
      await api.execute('alice', {
        'op': 'spec.saveDraft',
        'appId': 'app',
        'operationId': 'next-draft',
        'expectedRevision': 1,
        'expectedVersionId': version,
        'spec': candidate,
      });
      final afterSave = await watch(api);
      expect(
        afterSave['controlRevision'],
        (before['controlRevision'] as int) + 1,
      );
      expect(afterSave['versionId'], version);
      final second = await checks.publish(
        api,
        'alice',
        2,
        version,
        'publish-second',
      );
      final afterPublish = await watch(api);
      expect(
        afterPublish['controlRevision'],
        (afterSave['controlRevision'] as int) + 1,
      );
      expect(afterPublish['versionId'], second);
      expect(second, isNot(version));
      expect(await watch(api), afterPublish);
    },
  );
  test(
    'current role archive and revocation are authoritative and archived snapshots remain readable',
    () async {
      final (_, api, version) = await checks.fixture('reading');
      await checks.join(api, 'bob', 41, role: 'builder');
      final builder = await watch(api, actor: 'bob');
      expect(builder['role'], 'builder');
      await changeGrant(api, 'viewer');
      final viewer = await watch(api, actor: 'bob');
      expect(viewer['role'], 'viewer');
      expect(
        viewer['controlRevision'],
        greaterThan(builder['controlRevision'] as int),
      );
      await api.execute('alice', {
        'op': 'archiveApp',
        'appId': 'app',
        'operationId': 'archive-watch',
      });
      final archived = await watch(api, actor: 'bob');
      expect(archived['archived'], true);
      expect(archived['versionId'], version);
      expect(
        archived['controlRevision'],
        greaterThan(viewer['controlRevision'] as int),
      );
      expect(await watch(api, actor: 'bob'), archived);
      await changeGrant(api, null, revision: 2, operation: 'revoke-archived');
      await checks.error(() => watch(api, actor: 'bob'), 'not_found');
      expect((await watch(api))['archived'], true);
    },
  );
  test(
    'workspace membership remains necessary independently of a live app grant',
    () async {
      final (store, api, _) = await checks.fixture('reading');
      await checks.join(api, 'bob', 42, role: 'viewer');
      await watch(api, actor: 'bob');
      final membership = store.rows['memberships']!.values.singleWhere(
        (r) => r['actorId'] == 'bob',
      );
      await store.update('memberships', membership[r'$id'] as String, {
        'active': false,
      });
      await checks.error(() => watch(api, actor: 'bob'), 'not_found');
    },
  );
  test(
    'strict keys and single ID validation reject substitutions duplicate batches and wrong engines',
    () async {
      final (_, api, _) = await checks.fixture('reading');
      for (final extra in [
        {'actorId': 'bob'},
        {'workspaceId': 'other'},
        {'versionId': 'other'},
        {'operationId': 'read'},
        {
          'appIds': ['app', 'app'],
        },
      ]) {
        await checks.error(
          () => api.execute('alice', {
            'op': 'spec.watch',
            'appId': 'app',
            ...extra,
          }),
          'invalid_request',
        );
      }
      for (final id in [
        null,
        1,
        ['app', 'app'],
        {'id': 'app'},
        '../app',
      ]) {
        await checks.error(
          () => api.execute('alice', {'op': 'spec.watch', 'appId': id}),
          'invalid_id',
        );
      }
      await api.execute('alice', {
        'op': 'createApp',
        'id': 'bounded',
        'workspaceId': 'ws',
        'name': 'Legacy',
      });
      await checks.error(
        () => watch(api, appId: 'bounded'),
        'unsupported_runtime',
      );
      await api.execute('bob', {
        'op': 'createWorkspace',
        'id': 'other-ws',
        'name': 'Other',
      });
      await api.execute('bob', {
        'op': 'spec.createApp',
        'id': 'other',
        'workspaceId': 'other-ws',
        'name': 'Other',
        'operationId': 'other-create',
      });
      await checks.error(() => watch(api, appId: 'other'), 'not_found');
      await checks.error(() => watch(api, actor: 'bob'), 'not_found');
      await checks.error(() => watch(api, appId: 'missing'), 'not_found');
    },
  );
  test(
    'revocation after grant hydration cannot commit stale watch metadata',
    () async {
      final store = RevokeAfterHydration();
      final (_, api, _) = await checks.fixture('reading', store: store);
      await checks.join(api, 'bob', 43, role: 'viewer');
      store.revoke = () =>
          changeGrant(api, null, operation: 'revoke-during-watch');
      store.armed = true;
      await checks.error(
        () => watch(api, actor: 'bob'),
        'transaction_conflict',
      );
      await checks.error(() => watch(api, actor: 'bob'), 'not_found');
    },
  );
  test(
    'concurrent duplicate watch IDs preserve semantic revision and conflict safely on read fences',
    () async {
      final store = checks.BarrierStore();
      final (_, api, _) = await checks.fixture('reading', store: store);
      final before = await watch(api);
      store.barrier(2);
      Future<Object> attempt() async {
        try {
          return await watch(api);
        } on ServiceException catch (error) {
          return error.code;
        }
      }

      final result = await Future.wait([attempt(), attempt()]);
      expect(result.whereType<Row>().single, before);
      expect(result.whereType<String>().single, 'transaction_conflict');
      expect(await watch(api), before);
    },
  );
}
