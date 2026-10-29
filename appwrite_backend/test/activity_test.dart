import 'dart:async';
import 'dart:convert';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:test/test.dart';
import '../lib/service.dart';
import 'memory_store.dart';
import 'spec_engine_check.dart' as base;

class ActivityStore extends MemoryStore {
  final auditReads = <Row>[];
  Future<void> Function()? afterAuditRead;
  @override
  Future<List<Row>> list(
    String table,
    Map<String, String> filters, {
    String? transactionId,
    int limit = 100,
    String? afterId,
    bool detectOverflow = true,
    List<String>? select,
  }) async {
    final result = await super.list(
      table,
      filters,
      transactionId: transactionId,
      limit: limit,
      afterId: afterId,
      detectOverflow: detectOverflow,
      select: select,
    );
    if (table == 'audit') {
      auditReads.add({
        'filters': filters,
        'limit': limit,
        'afterId': afterId,
        'transaction': transactionId,
        'select': select,
      });
      final callback = afterAuditRead;
      afterAuditRead = null;
      if (callback != null) await callback();
    }
    return result;
  }
}

Future<(ActivityStore, PlatformService, String)> fixture() async {
  final store = ActivityStore();
  final service = PlatformService(store, clock: () => DateTime.utc(2030, 1, 2));
  await service.execute('alice', {
    'op': 'createWorkspace',
    'id': 'ws',
    'name': 'Private workspace',
  });
  await service.execute('alice', {
    'op': 'spec.createApp',
    'id': 'app',
    'workspaceId': 'ws',
    'name': 'Private app',
    'operationId': 'create',
  });
  await service.execute('alice', {
    'op': 'spec.saveDraft',
    'appId': 'app',
    'operationId': 'draft',
    'expectedRevision': 0,
    'expectedVersionId': null,
    'spec': spec.starterTemplates()['chores']!.toJson(),
  });
  final version = await base.publish(service, 'alice', 1, null, 'publish');
  return (store, service, version);
}

Future<Row> page(
  PlatformService service,
  String actor, {
  String? cursor,
  int limit = 2,
}) => service.execute(actor, {
  'op': 'spec.listActivity',
  'appId': 'app',
  'limit': limit,
  if (cursor != null) 'cursor': cursor,
});

Future<void> createRecord(
  PlatformService service,
  String version,
  int n,
) async {
  await base.run(
    service,
    'alice',
    base.action('activity-$n', version, 'addChore', {
      'data': {'title': 'PRIVATE_RECORD_TITLE_$n', 'status': 'Open'},
    }),
  );
}

Future<Row> activityWire() async {
  final (_, service, version) = await fixture();
  for (var n = 0; n < 3; n++) await createRecord(service, version, n);
  final first = await page(service, 'alice');
  final second = await page(
    service,
    'alice',
    cursor: first['nextCursor'] as String,
  );
  return {'first': first, 'second': second};
}

void main() {
  test(
    'all four current roles receive only committed action/time metadata',
    () async {
      final (store, service, version) = await fixture();
      var seed = 1;
      for (final role in ['builder', 'member', 'viewer']) {
        await base.join(service, role, seed++, role: role);
      }
      await createRecord(service, version, 0);
      final beforeAudit = store.rows['audit']!.length,
          beforeReceipts = store.rows['receipts']!.length;
      for (final actor in ['alice', 'builder', 'member', 'viewer']) {
        final result = await page(service, actor, limit: 50);
        expect(result['appId'], 'app');
        for (final item in result['items'] as List) {
          expect((item as Row).keys.toSet(), {
            'id',
            'action',
            'createdAt',
            'status',
          });
          expect(item['status'], 'committed');
          expect(item['createdAt'], '2030-01-02T00:00:00.000Z');
        }
        final encoded = jsonEncode(result);
        for (final forbidden in [
          'PRIVATE_RECORD_TITLE',
          'actorId',
          'requestId',
          'recordId',
          'specJson',
        ]) {
          expect(encoded, isNot(contains(forbidden)));
        }
      }
      expect(store.rows['audit']!.length, beforeAudit);
      expect(store.rows['receipts']!.length, beforeReceipts);
    },
  );

  test(
    'indexed pages are bounded, complete, unique and stable across equal timestamps',
    () async {
      final (store, service, version) = await fixture();
      for (var n = 0; n < 6; n++) await createRecord(service, version, n);
      final ids = <String>[];
      String? cursor;
      do {
        final result = await page(service, 'alice', cursor: cursor);
        final items = (result['items'] as List).cast<Row>();
        expect(items.length, lessThanOrEqualTo(2));
        ids.addAll(items.map((item) => item['id'] as String));
        cursor = result['nextCursor'] as String?;
      } while (cursor != null);
      expect(ids.toSet().length, store.rows['audit']!.length);
      expect(ids, [...ids]..sort());
      expect(store.auditReads.length, (ids.length / 2).ceil());
      for (final call in store.auditReads) {
        expect(call['filters'], {'appId': 'app'});
        expect(call['limit'], 3);
        expect(call['transaction'], isA<String>());
        expect(call['select'], [
          r'$id',
          'workspaceId',
          'appId',
          'action',
          'createdAt',
        ]);
      }
    },
  );

  test(
    'cursor binds actor, app, page size and supported control revision',
    () async {
      final (_, service, version) = await fixture();
      await base.join(service, 'viewer', 10, role: 'viewer');
      final first = await page(service, 'alice');
      final cursor = first['nextCursor'] as String;
      await base.error(
        () => page(service, 'viewer', cursor: cursor),
        'invalid_request',
      );
      await base.error(
        () => page(service, 'alice', cursor: cursor, limit: 3),
        'invalid_request',
      );
      await createRecord(service, version, 0);
      await base.error(
        () => page(service, 'alice', cursor: cursor),
        'revision_conflict',
      );
    },
  );

  test(
    'cross-app anchor cannot enter a scoped page even if cursor hash is retained',
    () async {
      final (store, service, _) = await fixture();
      final first = await page(service, 'alice');
      final decoded =
          jsonDecode(
                utf8.decode(base64Url.decode(first['nextCursor'] as String)),
              )
              as Row;
      await store.create('audit', 'foreign', {
        'appId': 'another-app',
        'workspaceId': 'another-workspace',
        'action': 'records.create.v1',
        'createdAt': '2030-01-02T00:00:00.000Z',
      });
      decoded['id'] = 'foreign';
      await base.error(
        () => page(
          service,
          'alice',
          cursor: base64Url.encode(utf8.encode(jsonEncode(decoded))),
        ),
        'revision_conflict',
      );
    },
  );

  test(
    'membership alone, foreign actor and revoked grant cannot read history',
    () async {
      final (_, service, _) = await fixture();
      await service.execute('bob', {
        'op': 'createWorkspace',
        'id': 'other-ws',
        'name': 'Other',
      });
      await base.error(() => page(service, 'bob'), 'not_found');
      await base.join(service, 'bob', 11, role: 'viewer');
      await page(service, 'bob');
      await service.execute('alice', {
        'op': 'setGrant',
        'appId': 'app',
        'actorId': 'bob',
        'role': null,
        'expectedRevision': 1,
        'operationId': 'remove-bob',
      });
      await base.error(() => page(service, 'bob'), 'not_found');
    },
  );

  test(
    'archived activity remains readable to currently authorized viewer',
    () async {
      final (_, service, _) = await fixture();
      await base.join(service, 'viewer', 12, role: 'viewer');
      await service.execute('alice', {
        'op': 'archiveApp',
        'appId': 'app',
        'operationId': 'archive',
      });
      expect((await page(service, 'viewer', limit: 50))['items'], isNotEmpty);
    },
  );

  test(
    'revocation committing during page read prevents a mixed-authority response',
    () async {
      final (store, service, _) = await fixture();
      await base.join(service, 'viewer', 13, role: 'viewer');
      store.afterAuditRead = () async {
        await service.execute('alice', {
          'op': 'setGrant',
          'appId': 'app',
          'actorId': 'viewer',
          'role': null,
          'expectedRevision': 1,
          'operationId': 'revoke-during-read',
        });
      };
      await base.error(() => page(service, 'viewer'), 'transaction_conflict');
      await base.error(() => page(service, 'viewer'), 'not_found');
    },
  );

  test(
    'unknown properties, oversized cursors and limits reject without audit reads',
    () async {
      final (store, service, _) = await fixture();
      for (final extra in <Row>[
        {'limit': 0},
        {'limit': 51},
        {'limit': 1.2},
        {'cursor': 'x' * 1025},
        {'cursor': '!'},
        {'actorId': 'alice'},
        {'workspaceId': 'ws'},
      ]) {
        await base.error(
          () => service.execute('alice', {
            'op': 'spec.listActivity',
            'appId': 'app',
            ...extra,
          }),
          'invalid_request',
        );
      }
      expect(store.auditReads, isEmpty);
      await base.error(
        () => service.execute('', {'op': 'spec.listActivity', 'appId': 'app'}),
        'unauthenticated',
      );
    },
  );

  test(
    'corrupt workspace/timestamp fails closed and private extra columns stay absent',
    () async {
      final (store, service, _) = await fixture();
      final row = store.rows['audit']!.values.first;
      row['secretPayload'] = 'PRIVATE_RAW_PAYLOAD';
      expect(
        jsonEncode(await page(service, 'alice', limit: 50)),
        isNot(contains('PRIVATE_RAW_PAYLOAD')),
      );
      final workspace = row['workspaceId'];
      row['workspaceId'] = 'foreign-workspace';
      await base.error(() => page(service, 'alice'), 'integrity_error');
      row['workspaceId'] = workspace;
      row['createdAt'] = '2030-02-31T00:00:00.000Z';
      await base.error(() => page(service, 'alice'), 'integrity_error');
    },
  );

  test(
    'actual wire fixture is repeatable with fixed server clock and stable operation IDs',
    () async {
      expect(
        jsonEncode(await activityWire()),
        jsonEncode(await activityWire()),
      );
    },
  );
}
