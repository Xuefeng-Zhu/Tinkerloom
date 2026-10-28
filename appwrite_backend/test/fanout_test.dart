import 'dart:async';
import 'dart:convert';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import '../lib/service.dart';
import 'memory_store.dart';
import 'spec_engine_check.dart' as base;
import 'workers_test.dart' as workers;

String identity(String kind, List<String> parts) =>
    '$kind${sha256.convert(utf8.encode(jsonEncode(parts))).toString().substring(0, 32)}';

/// Counts transport calls at the RowStore boundary. MemoryStore's internal
/// create/update implementation reads are deliberately not counted as HTTP.
class RpcStore implements RowStore {
  RpcStore(this.memory);
  final MemoryStore memory;
  final counts = <String, int>{};
  bool recording = false;
  Future<void> Function()? beforeBatch;
  void count(String operation, String table) {
    if (recording)
      counts['$operation:$table'] = (counts['$operation:$table'] ?? 0) + 1;
  }

  int get total => counts.values.fold(0, (a, b) => a + b);
  @override
  Future<Row?> get(String table, String id, {String? transactionId}) {
    count('get', table);
    return memory.get(table, id, transactionId: transactionId);
  }

  @override
  Future<Row> create(
    String table,
    String id,
    Row data, {
    String? transactionId,
  }) async {
    count('create', table);
    if (table == 'notification_batches' && beforeBatch != null)
      await beforeBatch!();
    return memory.create(table, id, data, transactionId: transactionId);
  }

  @override
  Future<Row> update(
    String table,
    String id,
    Row data, {
    String? transactionId,
  }) {
    count('update', table);
    return memory.update(table, id, data, transactionId: transactionId);
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
    count('list', table);
    return memory.list(
      table,
      filters,
      transactionId: transactionId,
      limit: limit,
      afterId: afterId,
      detectOverflow: detectOverflow,
      select: select,
    );
  }

  @override
  Future<String> beginTransaction() {
    count('begin', 'transaction');
    return memory.beginTransaction();
  }

  @override
  Future<void> finishTransaction(String id, {required bool commit}) {
    count(commit ? 'commit' : 'rollback', 'transaction');
    return memory.finishTransaction(id, commit: commit);
  }
}

Future<(workers.Fixture, RpcStore, String)> fixture(
  int participants, {
  bool otherOwner = false,
}) async {
  final store = MemoryStore(), clock = workers.Clock();
  final rpc = RpcStore(store);
  final service = PlatformService(
    rpc,
    clock: clock.call,
    remindersEnabled: true,
  );
  await service.execute('alice', {
    'op': 'createWorkspace',
    'id': 'ws',
    'name': 'Workspace',
  });
  await service.execute('alice', {
    'op': 'spec.createApp',
    'workspaceId': 'ws',
    'id': 'app',
    'name': 'App',
    'operationId': 'create',
  });
  final f = workers.Fixture(store, clock, service);
  await f.save(spec.starterTemplates()['volunteer']!, 0, null, 'draft');
  final version = await f.publish(
    1,
    null,
    'publish',
    enabled: ['shiftReminder'],
  );
  final out = await base.run(
    service,
    'alice',
    base.action('shift', version, 'addShift', {
      'data': {
        'title': 'Shift',
        'startsAt': clock.value
            .add(const Duration(hours: 1, minutes: 1))
            .toIso8601String(),
      },
      'capacity': 500,
    }),
  );
  final pool = store.rows['spec_pools']!.values.single;
  for (var i = 0; i < participants; i++)
    await addActor(store, 'actor-$i', pool[r'$id'] as String);
  await store.update('spec_pools', pool[r'$id'] as String, {
    'allocated': participants,
  });
  await f.worker.reminders();
  if (otherOwner) {
    await store.update('apps', 'app', {'ownerId': 'different-owner'});
    await addActor(store, 'different-owner', pool[r'$id'] as String);
  }
  return (f, rpc, out['recordId'] as String);
}

Future<void> addActor(
  MemoryStore memory,
  String actor,
  String pool, {
  String role = 'member',
}) async {
  await memory.create('memberships', identity('m', ['ws', actor]), {
    'workspaceId': 'ws',
    'actorId': actor,
    'active': true,
    'role': 'member',
    'revision': 1,
  });
  await memory.create('grants', identity('g', ['app', actor]), {
    'workspaceId': 'ws',
    'appId': 'app',
    'actorId': actor,
    'role': role,
    'revision': 1,
    'revoked': false,
  });
  await memory.create('spec_claims', identity('c', [pool, actor]), {
    'workspaceId': 'ws',
    'appId': 'app',
    'poolId': pool,
    'actorId': actor,
    'active': true,
    'createdAt': '2030-01-01T10:00:00.000Z',
    'updatedAt': '2030-01-01T10:00:00.000Z',
  });
}

void main() {
  test(
    '500 fanout uses paged authorization with zero per-recipient keyed access reads',
    () async {
      final (f, rpc, _) = await fixture(500);
      f.clock.advance(61);
      rpc.recording = true;
      await f.worker.reminders(limit: 1);
      rpc.recording = false;
      expect(
        f.store.rows['automation_runs']!.values.single['status'],
        'succeeded',
      );
      expect(
        f.store.rows['automation_runs']!.values.single['recipientCount'],
        500,
      );
      expect(rpc.counts['get:memberships'] ?? 0, 0);
      expect(rpc.counts['get:grants'] ?? 0, 0);
      expect(rpc.counts['list:memberships'], 6);
      expect(rpc.counts['list:grants'], 6);
      expect(
        rpc.total,
        lessThanOrEqualTo(40),
        reason: 'Transport must stay bounded by scoped pages, not 4*500 GETs',
      );
      print(
        '500 fanout transport boundary: ${rpc.total} calls; ${jsonEncode(rpc.counts)} (simulated, not measured Cloud latency)',
      );
    },
  );
  test(
    'paged filtering preserves membership AND grants, canonical IDs, valid read roles and owner exceptions',
    () async {
      final (f, rpc, _) = await fixture(16);
      final memory = f.store,
          pool = memory.rows['spec_pools']!.values.single[r'$id'] as String;
      await memory.update('memberships', identity('m', ['ws', 'actor-0']), {
        'active': false,
      });
      await memory.update('grants', identity('g', ['app', 'actor-1']), {
        'revoked': true,
      });
      await memory.update('grants', identity('g', ['app', 'actor-2']), {
        'role': 'invalid',
      });
      await memory.update('grants', identity('g', ['app', 'actor-3']), {
        'workspaceId': 'another-workspace',
      });
      await memory.update('memberships', identity('m', ['ws', 'actor-4']), {
        'workspaceId': 'another-workspace',
      });
      await memory.update('memberships', identity('m', ['ws', 'actor-5']), {
        'active': false,
      });
      await memory.create('memberships', 'forged-membership', {
        'workspaceId': 'ws',
        'actorId': 'actor-5',
        'active': true,
        'role': 'member',
        'revision': 1,
      });
      await memory.update('grants', identity('g', ['app', 'actor-6']), {
        'revoked': true,
      });
      await memory.create('grants', 'forged-grant', {
        'workspaceId': 'ws',
        'appId': 'app',
        'actorId': 'actor-6',
        'role': 'member',
        'revision': 1,
        'revoked': false,
      });
      await memory.update('grants', identity('g', ['app', 'actor-7']), {
        'role': 'viewer',
      });
      await memory.update('grants', identity('g', ['app', 'actor-8']), {
        'role': 'builder',
      });
      // Workspace/app owner uses the original implicit access exception.
      await memory.create('spec_claims', identity('c', [pool, 'alice']), {
        'workspaceId': 'ws',
        'appId': 'app',
        'poolId': pool,
        'actorId': 'alice',
        'active': true,
        'createdAt': '2030-01-01T10:00:00.000Z',
        'updatedAt': '2030-01-01T10:00:00.000Z',
      });
      f.clock.advance(61);
      rpc.recording = true;
      await f.worker.reminders(limit: 1);
      final recipients =
          (jsonDecode(
                    memory
                            .rows['notification_batches']!
                            .values
                            .single['recipientIdsJson']
                        as String,
                  )
                  as List)
              .cast<String>();
      expect(recipients.toSet(), {
        'alice',
        for (var i = 7; i < 16; i++) 'actor-$i',
      });
    },
  );
  test(
    'a different app owner still needs membership and a workspace owner still needs an app grant',
    () async {
      final (f, _, _) = await fixture(16, otherOwner: true);
      final store = f.store;
      // Keep the original approving actor authorized as builder although it is
      // now only workspace owner; workspace ownership alone is not an app grant.
      await store.create('grants', identity('g', ['app', 'alice']), {
        'workspaceId': 'ws',
        'appId': 'app',
        'actorId': 'alice',
        'role': 'builder',
        'revision': 1,
        'revoked': false,
      });
      await store.update(
        'memberships',
        identity('m', ['ws', 'different-owner']),
        {'active': false},
      );
      f.clock.advance(61);
      await f.worker.reminders(limit: 1);
      final recipients =
          jsonDecode(
                store
                        .rows['notification_batches']!
                        .values
                        .single['recipientIdsJson']
                    as String,
              )
              as List;
      expect(recipients, hasLength(16));
      expect(recipients, isNot(contains('different-owner')));
    },
  );
  test(
    'batch owners preserve the original independent workspace and app ownership exceptions',
    () async {
      final (f, _, _) = await fixture(16, otherOwner: true);
      final store = f.store,
          pool = store.rows['spec_pools']!.values.single[r'$id'] as String;
      await store.update('grants', identity('g', ['app', 'actor-15']), {
        'role': 'builder',
      });
      final rule = store.rows['automations']!.values.single;
      await store.update('automations', rule[r'$id'] as String, {
        'executionActorId': 'actor-15',
      });
      await store.update('grants', identity('g', ['app', 'different-owner']), {
        'revoked': true,
      });
      // A workspace owner is an implicit member, but app ownership is separate.
      await store.create('spec_claims', identity('c', [pool, 'alice']), {
        'workspaceId': 'ws',
        'appId': 'app',
        'poolId': pool,
        'actorId': 'alice',
        'active': true,
        'createdAt': '2030-01-01T10:00:00.000Z',
        'updatedAt': '2030-01-01T10:00:00.000Z',
      });
      f.clock.advance(61);
      await f.worker.reminders(limit: 1);
      final recipients =
          jsonDecode(
                store
                        .rows['notification_batches']!
                        .values
                        .single['recipientIdsJson']
                    as String,
              )
              as List;
      expect(recipients, hasLength(17));
      expect(recipients, contains('different-owner'));
      expect(recipients, isNot(contains('alice')));
    },
  );
  test(
    'inactive claims and unrelated workspace members never enter a paginated recipient batch',
    () async {
      final (f, _, _) = await fixture(16);
      final store = f.store,
          pool = store.rows['spec_pools']!.values.single[r'$id'] as String;
      await store.update('spec_claims', identity('c', [pool, 'actor-0']), {
        'active': false,
      });
      for (var i = 0; i < 205; i++) {
        await store
            .create('memberships', identity('m', ['ws', 'unrelated-$i']), {
              'workspaceId': 'ws',
              'actorId': 'unrelated-$i',
              'active': true,
              'role': 'member',
              'revision': 1,
            });
      }
      f.clock.advance(61);
      await f.worker.reminders(limit: 1);
      final recipients =
          jsonDecode(
                store
                        .rows['notification_batches']!
                        .values
                        .single['recipientIdsJson']
                    as String,
              )
              as List;
      expect(recipients, hasLength(15));
      expect(recipients, isNot(contains('actor-0')));
      expect(recipients.every((a) => (a as String).startsWith('actor-')), true);
    },
  );
  test(
    'a grant revocation during batch insertion conflicts, retries authorization and cannot deliver to revoked actor',
    () async {
      final (f, rpc, _) = await fixture(16);
      final started = Completer<void>(), release = Completer<void>();
      var blocked = false;
      rpc.beforeBatch = () async {
        if (!blocked) {
          blocked = true;
          started.complete();
          await release.future;
        }
      };
      f.clock.advance(61);
      final delivery = f.worker.reminders(limit: 1);
      await started.future;
      await f.service.execute('alice', {
        'op': 'setGrant',
        'appId': 'app',
        'actorId': 'actor-0',
        'role': null,
        'expectedRevision': 1,
        'operationId': 'revoke-during-delivery',
      });
      release.complete();
      await delivery;
      final recipients =
          jsonDecode(
                f
                        .store
                        .rows['notification_batches']!
                        .values
                        .single['recipientIdsJson']
                    as String,
              )
              as List;
      expect(recipients, hasLength(15));
      expect(recipients, isNot(contains('actor-0')));
      expect(f.store.rows['notification_batches']!.length, 1);
      expect(f.store.rows['automation_runs']!.values.single['attempts'], 1);
    },
  );
}
