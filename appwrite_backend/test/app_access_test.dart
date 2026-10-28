import 'dart:convert';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:test/test.dart';
import '../lib/service.dart';
import 'memory_store.dart';
import 'spec_engine_check.dart' as checks;

class AccessStore extends MemoryStore {
  final readTables = <String>[];
  bool armed = false;
  int appReads = 0;
  Future<void> Function()? beforeSecondAppRead;
  @override
  Future<Row?> get(String table, String id, {String? transactionId}) async {
    readTables.add(table);
    if (armed &&
        table == 'apps' &&
        id == 'app' &&
        transactionId == null &&
        ++appReads == 2) {
      armed = false;
      await beforeSecondAppRead!();
    }
    return super.get(table, id, transactionId: transactionId);
  }
}

Future<(AccessStore, PlatformService)> fixture(bool full) async {
  final store = AccessStore();
  final api = PlatformService(store);
  await api.execute('alice', {
    'op': 'createWorkspace',
    'id': 'ws',
    'name': 'Workspace',
  });
  await api.execute('alice', {
    'op': full ? 'spec.createApp' : 'createApp',
    'id': 'app',
    'workspaceId': 'ws',
    'name': 'Published shell',
    if (full) 'operationId': 'create',
  });
  if (full) {
    await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'expectedRevision': 0,
      'expectedVersionId': null,
      'operationId': 'private-draft',
      'spec': spec.starterTemplates()['reading']!.toJson(),
    });
  } else {
    await api.execute('alice', {
      'op': 'saveDraft',
      'appId': 'app',
      'expectedRevision': 0,
      'expectedPublishedRevision': 0,
      'operationId': 'private-draft',
      'definition': {
        'title': 'Unpublished private title',
        'description': 'Private description',
        'primaryFieldId': 'title',
        'fields': [
          {
            'id': 'title',
            'label': 'Private field',
            'kind': 'text',
            'required': true,
          },
        ],
      },
    });
  }
  return (store, api);
}

void main() {
  test(
    'metadata is read-only, engine-discriminated and never hydrates author drafts or definitions',
    () async {
      for (final full in [false, true]) {
        final (store, api) = await fixture(full);
        store.readTables.clear();
        final before = jsonEncode(store.rows);
        final result = await api.execute('alice', {
          'op': 'getAppAccess',
          'appId': 'app',
        });
        final app = result['app'] as Row;
        expect(app.keys.toSet(), {
          'id',
          'workspaceId',
          'name',
          'engine',
          'role',
          'archived',
          'capabilities',
        });
        expect(app['engine'], full ? 'appspec.v1' : 'bounded.v1');
        expect(app['name'], 'Published shell');
        expect(app['role'], 'owner');
        expect(utf8.encode(jsonEncode(result)).length, lessThan(2048));
        expect(jsonEncode(store.rows), before);
        expect(
          store.readTables.toSet().difference({
            'apps',
            'workspaces',
            'memberships',
            'grants',
          }),
          isEmpty,
        );
        expect(
          jsonEncode(result),
          isNot(contains('Unpublished private title')),
        );
      }
    },
  );
  test(
    'all explicit app roles get shared capabilities without full-policy write inference',
    () async {
      for (final full in [false, true]) {
        final (_, api) = await fixture(full);
        for (final entry in ['builder', 'member', 'viewer'].indexed) {
          final actor = 'user-${entry.$1}';
          await checks.join(api, actor, 60 + entry.$1, role: entry.$2);
          final app =
              (await api.execute(actor, {
                    'op': 'getAppAccess',
                    'appId': 'app',
                  }))['app']
                  as Row;
          expect(app['role'], entry.$2);
          expect(app['engine'], full ? 'appspec.v1' : 'bounded.v1');
          final caps = app['capabilities'] as Row;
          expect(caps['share'], entry.$2 == 'builder');
          expect(caps['writeRecords'], entry.$2 == 'builder');
          expect(app.containsKey('definition'), false);
          expect(app.containsKey('draft'), false);
        }
      }
    },
  );
  test(
    'archive metadata remains available and only authorized owners/builders retain revocation controls',
    () async {
      final (_, api) = await fixture(true);
      await checks.join(api, 'builder', 71, role: 'builder');
      await checks.join(api, 'viewer', 72, role: 'viewer');
      await api.execute('alice', {
        'op': 'archiveApp',
        'appId': 'app',
        'operationId': 'archive',
      });
      for (final actor in ['alice', 'builder', 'viewer']) {
        final app =
            (await api.execute(actor, {
                  'op': 'getAppAccess',
                  'appId': 'app',
                }))['app']
                as Row;
        final caps = app['capabilities'] as Row;
        expect(app['archived'], true);
        expect(caps['editDefinition'], false);
        expect(caps['share'], false);
        expect(caps['writeRecords'], false);
        expect(caps['archive'], false);
        expect(caps['revokeAccess'], actor != 'viewer');
      }
    },
  );
  test(
    'metadata requires current membership AND app grant and rejects unknown payload keys',
    () async {
      final (store, api) = await fixture(true);
      await checks.join(api, 'bob', 81, role: 'viewer');
      await checks.error(
        () => api.execute('stranger', {'op': 'getAppAccess', 'appId': 'app'}),
        'not_found',
      );
      await checks.error(
        () => api.execute('bob', {
          'op': 'getAppAccess',
          'appId': 'app',
          'draft': true,
        }),
        'invalid_request',
      );
      final member = store.rows['memberships']!.values.singleWhere(
        (m) => m['actorId'] == 'bob',
      );
      await store.update('memberships', member[r'$id'] as String, {
        'active': false,
      });
      await checks.error(
        () => api.execute('bob', {'op': 'getAppAccess', 'appId': 'app'}),
        'not_found',
      );
      await store.update('memberships', member[r'$id'] as String, {
        'active': true,
      });
      await api.execute('alice', {
        'op': 'setGrant',
        'appId': 'app',
        'actorId': 'bob',
        'role': null,
        'expectedRevision': 1,
        'operationId': 'remove',
      });
      await checks.error(
        () => api.execute('bob', {'op': 'getAppAccess', 'appId': 'app'}),
        'not_found',
      );
    },
  );
  test(
    'a grant revocation during metadata hydration prevents returning the previously authorized summary',
    () async {
      final (store, api) = await fixture(true);
      await checks.join(api, 'bob', 91, role: 'builder');
      store.beforeSecondAppRead = () => api
          .execute('alice', {
            'op': 'setGrant',
            'appId': 'app',
            'actorId': 'bob',
            'role': null,
            'expectedRevision': 1,
            'operationId': 'revoke-during-read',
          })
          .then((_) {});
      store.appReads = 0;
      store.armed = true;
      await checks.error(
        () => api.execute('bob', {'op': 'getAppAccess', 'appId': 'app'}),
        'not_found',
      );
    },
  );
}
