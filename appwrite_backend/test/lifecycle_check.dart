import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import '../lib/service.dart';
import 'memory_store.dart';
import 'spec_engine_check.dart' as engine;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Row> call(PlatformService api, String actor, Row input) =>
    api.execute(actor, engine.clone(input));
Future<void> error(Future<dynamic> Function() action, String code) =>
    engine.error(action, code);
Future<Row> instantiate(
  PlatformService api,
  String actor,
  String id, {
  String workspace = 'ws',
  String template = 'reading',
  String? operation,
}) async =>
    (await call(api, actor, {
          'op': 'spec.instantiate',
          'id': id,
          'workspaceId': workspace,
          'templateKey': template,
          'operationId': operation ?? 'new-$id',
        }))['app']
        as Row;
Future<Row> remix(
  PlatformService api,
  String actor,
  String id,
  String version, {
  String source = 'app',
  String workspace = 'ws',
  String? operation,
}) => call(api, actor, {
  'op': 'spec.remix',
  'id': id,
  'workspaceId': workspace,
  'operationId': operation ?? 'copy-$id',
  'sourceAppId': source,
  'sourceVersionId': version,
});
Future<String> publish(
  PlatformService api,
  String actor,
  String appId,
  int revision,
  String? base,
  String operation,
) async {
  final review =
      (await call(api, actor, {
            'op': 'spec.review',
            'appId': appId,
            'expectedRevision': revision,
            'enabledRuleIds': [],
            'activateExistingRecordIds': [],
          }))['review']
          as Row;
  final result = await call(api, actor, {
    'op': 'spec.publish',
    'appId': appId,
    'operationId': operation,
    'expectedRevision': revision,
    'expectedVersionId': base,
    'candidateHash': review['candidateHash'],
    'reviewHash': review['reviewHash'],
    'enabledRuleIds': [],
    'activateExistingRecordIds': [],
  });
  return (((result['app'] as Map)['version'] as Map)['id']) as String;
}

Future<void> save(
  PlatformService api,
  String actor,
  String appId,
  Row definition,
  int revision,
  String? base,
  String operation,
) async {
  await call(api, actor, {
    'op': 'spec.saveDraft',
    'appId': appId,
    'operationId': operation,
    'expectedRevision': revision,
    'expectedVersionId': base,
    'spec': definition,
  });
}

Future<Row> listApps(
  PlatformService api,
  String actor, {
  String workspace = 'ws',
  int limit = 20,
  String? cursor,
  bool pinnedOnly = false,
}) => call(api, actor, {
  'op': 'spec.launcher',
  'workspaceId': workspace,
  'limit': limit,
  'pinnedOnly': pinnedOnly,
  if (cursor != null) 'cursor': cursor,
});
Future<Row> listDrafts(
  PlatformService api,
  String actor, {
  String workspace = 'ws',
  int limit = 20,
  String? cursor,
}) => call(api, actor, {
  'op': 'spec.listDrafts',
  'workspaceId': workspace,
  'limit': limit,
  if (cursor != null) 'cursor': cursor,
});
Future<void> grant(
  PlatformService api,
  String appId,
  String actor,
  String? role,
  int revision,
  String operation,
) async {
  await call(api, 'alice', {
    'op': 'setGrant',
    'appId': appId,
    'actorId': actor,
    'role': role,
    'expectedRevision': revision,
    'operationId': operation,
  });
}

Future<Row> pin(
  PlatformService api,
  String actor,
  String appId,
  bool pinned,
  int revision,
  String operation,
) => call(api, actor, {
  'op': 'spec.setPinned',
  'appId': appId,
  'pinned': pinned,
  'expectedRevision': revision,
  'operationId': operation,
});

class PausedCommitStore extends MemoryStore {
  Completer<void>? reached, release;
  void pauseNext() {
    reached = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<void> finishTransaction(
    String transactionId, {
    required bool commit,
  }) async {
    final pause = reached;
    if (commit && pause != null) {
      reached = null;
      pause.complete();
      await release!.future;
    }
    await super.finishTransaction(transactionId, commit: commit);
  }
}

class ReceiptHookStore extends MemoryStore {
  String? watch;
  Future<void> Function()? hook;
  @override
  Future<Row?> get(String table, String id, {String? transactionId}) async {
    final row = await super.get(table, id, transactionId: transactionId);
    if (table == 'receipts' &&
        id == watch &&
        transactionId == null &&
        hook != null) {
      final action = hook!;
      hook = null;
      await action();
    }
    return row;
  }
}

class DraftBlindStore extends MemoryStore {
  bool blind = false;
  @override
  Future<Row?> get(String table, String id, {String? transactionId}) {
    if (blind && {'apps', 'drafts', 'spec_drafts'}.contains(table))
      throw StateError('Private/full app hydration attempted');
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
    if (blind) {
      if ({'drafts', 'spec_drafts'}.contains(table))
        throw StateError('Draft list attempted');
      if (table == 'apps' &&
          (select == null ||
              select.any(
                (key) => {'draftJson', 'publishedJson'}.contains(key),
              )))
        throw StateError('Private app columns selected');
    }
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

Future<int> runLifecycleChecks() async {
  var passed = 0;
  Future<void> test(String name, Future<void> Function() body) async {
    await body();
    passed++;
    print('PASS $name');
  }

  await test(
    'all twelve templates create immediate immutable empty apps and actor-private shortcuts without effects',
    () async {
      final store = MemoryStore(), api = PlatformService(store);
      await call(api, 'alice', {
        'op': 'createWorkspace',
        'id': 'ws',
        'name': 'Workspace',
      });
      for (final entry in spec.starterTemplates().entries) {
        final id = 'template-${entry.key}',
            app = await instantiate(api, 'alice', id, template: entry.key);
        check(
          app['draft'] == null && (app['version'] as Map)['number'] == 1,
          'Template is not immediately published',
        );
        check(
          (app['version'] as Map)['hash'] == entry.value.hash,
          'Template structure changed',
        );
        final pinned = await listApps(api, 'alice', pinnedOnly: true);
        check(
          (pinned['apps'] as List).any(
            (row) => row['id'] == id && row['pinned'] == true,
          ),
          'Creator shortcut missing',
        );
      }
      for (final table in [
        'spec_records',
        'spec_values',
        'spec_pools',
        'spec_claims',
        'spec_drafts',
        'grants',
        'invitations',
      ])
        check(
          store.rows[table]?.isEmpty ?? true,
          'Instantiation copied $table',
        );
      check(
        store.rows['spec_versions']!.length == 12,
        'Template versions not independent',
      );
      for (final row in store.rows['outbox']!.values) {
        final payload = jsonDecode(row['payloadJson'] as String) as Map;
        check(
          (payload['enabledRuleIds'] as List).isEmpty &&
              (payload['activateExistingRecordIds'] as List).isEmpty,
          'Template enabled effects',
        );
      }
    },
  );
  await test(
    'template creation receipts stay exact after later publication and archive',
    () async {
      final store = MemoryStore(), api = PlatformService(store);
      await call(api, 'alice', {
        'op': 'createWorkspace',
        'id': 'ws',
        'name': 'Workspace',
      });
      final original = await instantiate(
            api,
            'alice',
            'new-app',
            operation: 'instantiate-receipt',
          ),
          base = (original['version'] as Map)['id'] as String;
      final changed = engine.clone(spec.starterTemplates()['reading']!.toJson())
        ..['name'] = 'Edited name';
      await save(api, 'alice', 'new-app', changed, 0, base, 'edit-copy');
      await publish(api, 'alice', 'new-app', 1, base, 'publish-copy');
      await call(api, 'alice', {
        'op': 'archiveApp',
        'appId': 'new-app',
        'operationId': 'archive-copy',
      });
      check(
        jsonEncode(
              await instantiate(
                api,
                'alice',
                'new-app',
                operation: 'instantiate-receipt',
              ),
            ) ==
            jsonEncode(original),
        'Original creation receipt changed',
      );
      check(
        store.rows['spec_versions']!.length == 2,
        'Retry created another version',
      );
      await error(
        () => instantiate(
          api,
          'alice',
          'new-app',
          template: 'notes',
          operation: 'instantiate-receipt',
        ),
        'operation_conflict',
      );
    },
  );
  await test(
    'remix copies only captured published structure into an independent immediately usable instance',
    () async {
      final (store, api, version) = await engine.fixture('volunteer');
      await engine.join(api, 'bob', 71, role: 'viewer');
      await call(api, 'bob', {
        'op': 'createWorkspace',
        'id': 'target',
        'name': 'Target',
      });
      await engine.run(
        api,
        'alice',
        engine.action('private-source-record', version, 'addShift', {
          'data': {
            'title': 'Private source row',
            'startsAt': '2030-01-01T10:00:00Z',
          },
          'capacity': 4,
        }),
      );
      final private = engine.clone(
        spec.starterTemplates()['volunteer']!.toJson(),
      )..['name'] = 'Unpublished private name';
      await save(
        api,
        'alice',
        'app',
        private,
        1,
        version,
        'private-source-draft',
      );
      final result = await remix(
            api,
            'bob',
            'remixed',
            version,
            workspace: 'target',
          ),
          app = result['app'] as Map;
      check(
        app['role'] == 'owner' &&
            app['draft'] == null &&
            (app['version'] as Map)['number'] == 1,
        'Remix did not create independent publication',
      );
      check(
        (app['version'] as Map)['id'] != version,
        'Remix reused immutable version ID',
      );
      check(
        (app['version'] as Map)['hash'] ==
            spec.starterTemplates()['volunteer']!.hash,
        'Remix copied a private candidate',
      );
      for (final table in [
        'spec_records',
        'spec_values',
        'spec_pools',
        'spec_claims',
        'grants',
        'invitations',
        'spec_drafts',
      ])
        check(
          !(store.rows[table]?.values.any((row) => row['appId'] == 'remixed') ??
              false),
          'Remix copied private $table',
        );
      await error(
        () => call(api, 'alice', {'op': 'spec.getApp', 'appId': 'remixed'}),
        'not_found',
      );
      check(
        (await listApps(
              api,
              'bob',
              workspace: 'target',
              pinnedOnly: true,
            ))['apps']
            is List,
        'Remix shortcut unavailable',
      );
    },
  );
  await test(
    'remix strips private static image IDs while preserving valid banner structure',
    () async {
      final (store, api, version) = await engine.fixture('projectHub');
      final json = engine.clone(
        spec.starterTemplates()['projectHub']!.toJson(),
      );
      final banner = (json['views'] as List).cast<Map>().firstWhere(
        (view) => view['type'] == 'banner',
      );
      (banner['options'] as Map).addAll(<String, dynamic>{
        'imageAssetId': 'private-source-image',
        'imageAlt': 'Example private image',
        'imagePlacement': 'beside',
      });
      (json['requires'] as List).add('appearance.v1');
      final definition = spec.AppSpec.parse(jsonEncode(json));
      await store.update('spec_versions', version, {
        'specJson': definition.canonical,
        'hash': definition.hash,
      });
      final result = await remix(api, 'alice', 'no-assets', version),
          copied = spec.AppSpec.parse(
            jsonEncode(((result['app'] as Map)['version'] as Map)['spec']),
          );
      check(
        copied.views
            .where((view) => view.type == 'banner')
            .every((view) => !view.options.containsKey('imageAssetId')),
        'Private image reference copied',
      );
      check(
        copied.collections.length == definition.collections.length,
        'Remix lost collection structure',
      );
    },
  );
  await test(
    'remix rejects new stale-source commands but exact receipts survive later source publication and archive',
    () async {
      final (store, api, version) = await engine.fixture('reading');
      final original = await remix(
        api,
        'alice',
        'copy',
        version,
        operation: 'exact-copy',
      );
      final changed = engine.clone(spec.starterTemplates()['reading']!.toJson())
        ..['name'] = 'Current source';
      await save(api, 'alice', 'app', changed, 1, version, 'source-edit');
      await publish(api, 'alice', 'app', 2, version, 'source-publish');
      await error(
        () => remix(api, 'alice', 'stale-copy', version),
        'definition_conflict',
      );
      check(
        store.rows['apps']?['stale-copy'] == null,
        'Stale source partially created target',
      );
      await call(api, 'alice', {
        'op': 'archiveApp',
        'appId': 'app',
        'operationId': 'archive-source',
      });
      check(
        jsonEncode(
              await remix(
                api,
                'alice',
                'copy',
                version,
                operation: 'exact-copy',
              ),
            ) ==
            jsonEncode(original),
        'Remix receipt changed after source updates',
      );
      await error(
        () => remix(
          api,
          'alice',
          'copy',
          version,
          operation: 'exact-copy',
          workspace: 'missing',
        ),
        'not_found',
      );
    },
  );
  await test(
    'remix receipts reauthorize source access and revocation does not erase an already owned copy',
    () async {
      final (_, api, version) = await engine.fixture('reading');
      await engine.join(api, 'bob', 72, role: 'viewer');
      await call(api, 'bob', {
        'op': 'createWorkspace',
        'id': 'target',
        'name': 'Target',
      });
      await remix(
        api,
        'bob',
        'copy',
        version,
        workspace: 'target',
        operation: 'owned-copy',
      );
      await grant(api, 'app', 'bob', null, 1, 'revoke-copy-source');
      await error(
        () => remix(
          api,
          'bob',
          'copy',
          version,
          workspace: 'target',
          operation: 'owned-copy',
        ),
        'not_found',
      );
      check(
        ((await call(api, 'bob', {'op': 'spec.getApp', 'appId': 'copy'}))['app']
                as Map)['role'] ==
            'owner',
        'Revocation destroyed independent copy',
      );
    },
  );
  await test(
    'remix source revocation during receipt hydration cannot return a cached private result',
    () async {
      final store = ReceiptHookStore();
      final (_, api, version) = await engine.fixture('reading', store: store);
      await engine.join(api, 'bob', 73, role: 'viewer');
      await call(api, 'bob', {
        'op': 'createWorkspace',
        'id': 'target',
        'name': 'Target',
      });
      await remix(
        api,
        'bob',
        'copy',
        version,
        workspace: 'target',
        operation: 'receipt-hydration',
      );
      store.watch = 'receipt-hydration';
      store.hook = () => grant(api, 'app', 'bob', null, 1, 'hydrate-revoke');
      await error(
        () => remix(
          api,
          'bob',
          'copy',
          version,
          workspace: 'target',
          operation: 'receipt-hydration',
        ),
        'not_found',
      );
    },
  );
  await test(
    'concurrent exact remix retries create one version receipt audit and outbox event',
    () async {
      final store = engine.BarrierStore();
      final (_, api, version) = await engine.fixture('reading', store: store);
      store.barrier(2);
      final results = await Future.wait([
        remix(api, 'alice', 'copy', version, operation: 'parallel-copy'),
        remix(api, 'alice', 'copy', version, operation: 'parallel-copy'),
      ]);
      check(
        jsonEncode(results[0]) == jsonEncode(results[1]),
        'Exact parallel retries disagreed',
      );
      for (final table in ['spec_versions', 'audit', 'outbox'])
        check(
          store.rows[table]!.values
                  .where((row) => row['appId'] == 'copy')
                  .length ==
              1,
          'Duplicate $table from retries',
        );
      check(
        store.rows['receipts']!.values
                .where((row) => row['appId'] == 'copy')
                .length ==
            1,
        'Duplicate remix receipt',
      );
    },
  );
  await test(
    'destination app quota rejects remix atomically without a partial target',
    () async {
      final (store, api, version) = await engine.fixture('reading');
      await call(api, 'alice', {
        'op': 'createWorkspace',
        'id': 'target',
        'name': 'Target',
      });
      for (var i = 0; i < 100; i++)
        await call(api, 'alice', {
          'op': 'spec.createApp',
          'id': 'full-$i',
          'workspaceId': 'target',
          'name': 'Full',
          'operationId': 'full-$i',
        });
      final before = jsonEncode(store.rows);
      await error(
        () => remix(api, 'alice', 'quota-copy', version, workspace: 'target'),
        'quota_exceeded',
      );
      check(
        jsonEncode(store.rows) == before,
        'Quota failure changed guards/business data',
      );
    },
  );
  await test(
    'pin and unpin are actor-private revision-checked preferences with exact receipts and no business effects',
    () async {
      final (store, api, version) = await engine.fixture('reading');
      await engine.join(api, 'bob', 74, role: 'viewer');
      final audit = store.rows['audit']!.length,
          outbox = store.rows['outbox']!.length;
      final original = await pin(api, 'bob', 'app', true, 0, 'pin-bob');
      check(
        ((await listApps(api, 'bob', pinnedOnly: true))['apps'] as List)
                .length ==
            1,
        'Viewer could not pin',
      );
      check(
        ((await listApps(api, 'alice', pinnedOnly: true))['apps'] as List)
            .isEmpty,
        'Pin preference leaked to owner',
      );
      await pin(api, 'bob', 'app', false, 1, 'unpin-bob');
      check(
        ((await listApps(api, 'bob', pinnedOnly: true))['apps'] as List)
            .isEmpty,
        'Unpin did not remove shortcut',
      );
      check(
        jsonEncode(await pin(api, 'bob', 'app', true, 0, 'pin-bob')) ==
            jsonEncode(original),
        'Pin replay lost original outcome',
      );
      await error(
        () => pin(api, 'bob', 'app', false, 0, 'stale-pin'),
        'revision_conflict',
      );
      await error(
        () => pin(api, 'bob', 'app', false, 0, 'pin-bob'),
        'operation_conflict',
      );
      check(
        store.rows['audit']!.length == audit &&
            store.rows['outbox']!.length == outbox,
        'Private bookmark emitted business event',
      );
      check(
        (store.rows['apps']!['app']!['specVersionId']) == version,
        'Unpin changed published structure',
      );
    },
  );
  await test(
    'archived apps allow personal shortcuts but revoked actors cannot read or recover them',
    () async {
      final (_, api, _) = await engine.fixture('reading');
      await engine.join(api, 'bob', 75, role: 'viewer');
      await call(api, 'alice', {
        'op': 'archiveApp',
        'appId': 'app',
        'operationId': 'archive-pin',
      });
      await pin(api, 'bob', 'app', true, 0, 'archived-pin');
      await grant(api, 'app', 'bob', null, 1, 'revoke-pin');
      await error(
        () => pin(api, 'bob', 'app', true, 0, 'archived-pin'),
        'not_found',
      );
      check(
        ((await listApps(api, 'bob'))['apps'] as List).isEmpty,
        'Revoked actor retained launcher metadata',
      );
    },
  );
  await test(
    'authorized launcher paging is complete beyond raw hidden rows and cursor scopes cannot cross actors/filters',
    () async {
      final (_, api, _) = await engine.fixture('reading');
      await engine.join(api, 'bob', 76, role: 'viewer');
      final expected = <String>['app'];
      for (var i = 0; i < 24; i++) {
        final id = 'catalog-${i.toString().padLeft(2, '0')}';
        await instantiate(api, 'alice', id);
        if (i % 3 == 0) {
          final token = engine.token(100 + i);
          await call(api, 'alice', {
            'op': 'createInvitation',
            'appId': id,
            'id': 'catalog-invite-$i',
            'operationId': 'catalog-invite-$i',
            'role': 'viewer',
            'recipientId': 'bob',
            'token': token,
          });
          await call(api, 'bob', {
            'op': 'acceptInvitation',
            'token': token,
            'operationId': 'catalog-accept-$i',
          });
          expected.add(id);
        }
      }
      final found = <String>[];
      String? cursor;
      String? first;
      do {
        final page = await listApps(api, 'bob', limit: 3, cursor: cursor);
        found.addAll((page['apps'] as List).map((app) => app['id'] as String));
        cursor = page['nextCursor'] as String?;
        first ??= cursor;
      } while (cursor != null);
      expected.sort((a, b) => b.compareTo(a));
      check(
        jsonEncode(found) == jsonEncode(expected),
        'Launcher truncated filtered visible apps',
      );
      await error(
        () => listApps(api, 'alice', limit: 3, cursor: first),
        'invalid_request',
      );
      await error(
        () => listApps(api, 'bob', limit: 3, cursor: first, pinnedOnly: true),
        'invalid_request',
      );
    },
  );
  await test(
    'draft discovery is current-author private excludes consumed archived and demoted drafts and marks stale bases',
    () async {
      final (_, api, version) = await engine.fixture('reading');
      await engine.join(api, 'bob', 77, role: 'builder');
      final alice = engine.clone(spec.starterTemplates()['reading']!.toJson())
        ..['name'] = 'Alice private';
      final bob = engine.clone(spec.starterTemplates()['reading']!.toJson())
        ..['name'] = 'Bob private';
      await save(api, 'alice', 'app', alice, 1, version, 'alice-private');
      await save(api, 'bob', 'app', bob, 0, version, 'bob-private');
      final a = (await listDrafts(api, 'alice'))['drafts'] as List,
          b = (await listDrafts(api, 'bob'))['drafts'] as List;
      check(
        a.length == 1 &&
            a.single['name'] == 'Alice private' &&
            b.length == 1 &&
            b.single['name'] == 'Bob private',
        'Draft authors leaked',
      );
      await publish(api, 'alice', 'app', 2, version, 'alice-publish');
      check(
        ((await listDrafts(api, 'alice'))['drafts'] as List).isEmpty,
        'Consumed candidate discoverable',
      );
      check(
        (((await listDrafts(api, 'bob'))['drafts'] as List).single
                as Map)['stale'] ==
            true,
        'Stale base not identified',
      );
      await grant(api, 'app', 'bob', 'viewer', 1, 'demote-draft');
      check(
        ((await listDrafts(api, 'bob'))['drafts'] as List).isEmpty,
        'Demoted builder retained private draft',
      );
      await call(api, 'alice', {
        'op': 'archiveApp',
        'appId': 'app',
        'operationId': 'archive-draft',
      });
      check(
        ((await listDrafts(api, 'alice'))['drafts'] as List).isEmpty,
        'Archived draft was offered for resume',
      );
    },
  );
  await test(
    'workspace catalog guard rejects a permission change committed during private draft hydration',
    () async {
      final store = PausedCommitStore();
      final (_, api, version) = await engine.fixture('reading', store: store);
      await engine.join(api, 'bob', 78, role: 'builder');
      await save(
        api,
        'bob',
        'app',
        spec.starterTemplates()['reading']!.toJson(),
        0,
        version,
        'guarded-private',
      );
      store.pauseNext();
      final reached = store.reached!, request = listDrafts(api, 'bob');
      await reached.future;
      await grant(api, 'app', 'bob', null, 1, 'revoke-catalog');
      store.release!.complete();
      await error(() => request, 'transaction_conflict');
      check(
        ((await listDrafts(api, 'bob'))['drafts'] as List).isEmpty,
        'Revoked draft leaked after race',
      );
    },
  );
  await test(
    'immutable version history pages by publication number and never includes private candidates',
    () async {
      final (_, api, first) = await engine.fixture('reading');
      var current = first;
      for (var i = 2; i <= 4; i++) {
        final definition = engine.clone(
          spec.starterTemplates()['reading']!.toJson(),
        )..['name'] = 'Version $i';
        await save(
          api,
          'alice',
          'app',
          definition,
          i - 1,
          current,
          'history-draft-$i',
        );
        current = await publish(
          api,
          'alice',
          'app',
          i,
          current,
          'history-publish-$i',
        );
      }
      await save(
        api,
        'alice',
        'app',
        engine.clone(spec.starterTemplates()['reading']!.toJson())
          ..['name'] = 'Private next',
        4,
        current,
        'history-private',
      );
      final page = await call(api, 'alice', {
        'op': 'spec.listVersions',
        'appId': 'app',
        'limit': 2,
      });
      check(
        jsonEncode(
                  (page['versions'] as List).map((v) => v['number']).toList(),
                ) ==
                '[4,3]' &&
            page['nextBeforeNumber'] == 3,
        'History is not newest first',
      );
      final second = await call(api, 'alice', {
        'op': 'spec.listVersions',
        'appId': 'app',
        'limit': 2,
        'beforeNumber': page['nextBeforeNumber'],
      });
      check(
        jsonEncode(
                  (second['versions'] as List).map((v) => v['number']).toList(),
                ) ==
                '[2,1]' &&
            second['nextBeforeNumber'] == null,
        'History continuation missed versions',
      );
      final old =
          (await call(api, 'alice', {
                'op': 'spec.getVersion',
                'appId': 'app',
                'versionId': first,
              }))['version']
              as Map;
      check(
        old['hash'] == spec.starterTemplates()['reading']!.hash,
        'Historical version changed',
      );
      check(
        (page['versions'] as List).every(
          (version) =>
              version['name'] != 'Private next' && !version.containsKey('spec'),
        ),
        'History leaked private/full candidate',
      );
    },
  );
  await test(
    'history reauthorizes current app access and rejects foreign versions while archive preserves authorized reads',
    () async {
      final (_, api, version) = await engine.fixture('reading');
      await engine.join(api, 'bob', 79, role: 'viewer');
      final other = await instantiate(api, 'alice', 'other');
      await error(
        () => call(api, 'bob', {
          'op': 'spec.getVersion',
          'appId': 'app',
          'versionId': (other['version'] as Map)['id'],
        }),
        'not_found',
      );
      await call(api, 'alice', {
        'op': 'archiveApp',
        'appId': 'app',
        'operationId': 'archive-history',
      });
      check(
        ((await call(api, 'bob', {
                      'op': 'spec.listVersions',
                      'appId': 'app',
                    }))['versions']
                    as List)
                .length ==
            1,
        'Archive hid authorized history',
      );
      await grant(api, 'app', 'bob', null, 1, 'revoke-history');
      await error(
        () => call(api, 'bob', {
          'op': 'spec.getVersion',
          'appId': 'app',
          'versionId': version,
        }),
        'not_found',
      );
      await error(
        () => call(api, 'alice', {
          'op': 'spec.listVersions',
          'appId': 'app',
          'beforeNumber': 3,
        }),
        'invalid_request',
      );
    },
  );
  await test(
    'template and remix admission failures do not partially create metadata versions shortcuts or receipts',
    () async {
      final (store, api, version) = await engine.fixture('reading');
      await error(
        () => instantiate(api, 'mallory', 'unauthorized'),
        'not_found',
      );
      await error(
        () => instantiate(
          api,
          'alice',
          'invalid-template',
          template: 'unsupported',
        ),
        'invalid_request',
      );
      final before = jsonEncode(store.rows);
      store.failBeforeCommit = true;
      try {
        await remix(api, 'alice', 'failed-copy', version);
        throw StateError('Expected commit failure');
      } on RestException {
        /* intended */
      } finally {
        store.failBeforeCommit = false;
      }
      check(
        jsonEncode(store.rows) == before,
        'Failed remix partially persisted',
      );
      store.loseCommitResponse = true;
      try {
        await remix(
          api,
          'alice',
          'unknown-copy',
          version,
          operation: 'unknown-copy',
        );
        throw StateError('Expected unknown commit');
      } on RestException {
        /* retained command must retry */
      }
      final result = await remix(
        api,
        'alice',
        'unknown-copy',
        version,
        operation: 'unknown-copy',
      );
      check(
        ((result['app'] as Map)['version'] as Map)['number'] == 1,
        'Unknown outcome recovery did not resolve original instance',
      );
      check(
        store.rows['spec_versions']!.values
                .where((row) => row['appId'] == 'unknown-copy')
                .length ==
            1,
        'Unknown response duplicated remix',
      );
    },
  );
  await test(
    'launcher creation order uses UTC-normalized Appwrite metadata with stable continuation',
    () async {
      final (store, api, _) = await engine.fixture('reading');
      for (final id in ['z-older', 'a-newer', 'm-middle'])
        await instantiate(api, 'alice', id);
      await store.update('apps', 'z-older', {
        r'$createdAt': '2030-01-01T01:00:00+02:00',
      });
      await store.update('apps', 'a-newer', {
        r'$createdAt': '2030-01-01T00:30:00+00:00',
      });
      await store.update('apps', 'm-middle', {
        r'$createdAt': '2030-01-01T00:00:00.000Z',
      });
      final first = await listApps(api, 'alice', limit: 2),
          apps = first['apps'] as List;
      check(
        jsonEncode(apps.map((app) => app['id']).toList()) ==
            '["a-newer","m-middle"]',
        'Launcher used IDs or local offsets as creation order',
      );
      check(
        apps.first['createdAt'] == '2030-01-01T00:30:00.000Z',
        'Metadata not normalized to UTC',
      );
      final next = await listApps(
        api,
        'alice',
        limit: 2,
        cursor: first['nextCursor'] as String,
      );
      check(
        jsonEncode((next['apps'] as List).map((app) => app['id']).toList()) ==
            '["z-older","app"]',
        'Newest-created continuation skipped apps',
      );
    },
  );
  await test(
    'mixed bounded and full launcher preserves actual visibility and private draft engine identity',
    () async {
      final (store, api, version) = await engine.fixture('reading');
      await engine.join(api, 'bob', 81, role: 'viewer');
      final definition = <String, dynamic>{
        'title': 'Bounded title',
        'description': 'Legacy',
        'primaryFieldId': 'title',
        'fields': [
          {'id': 'title', 'label': 'Title', 'kind': 'text', 'required': true},
        ],
      };
      await call(api, 'alice', {
        'op': 'createApp',
        'id': 'legacy',
        'workspaceId': 'ws',
        'name': 'Legacy',
      });
      await call(api, 'alice', {
        'op': 'saveDraft',
        'appId': 'legacy',
        'operationId': 'legacy-draft',
        'expectedRevision': 0,
        'definition': definition,
      });
      await call(api, 'alice', {
        'op': 'publishApp',
        'appId': 'legacy',
        'operationId': 'legacy-publish',
        'expectedRevision': 1,
      });
      for (var i = 0; i < 3; i++)
        await call(api, 'alice', {
          'op': 'saveRecord',
          'appId': 'legacy',
          'id': 'legacy-$i',
          'operationId': 'legacy-record-$i',
          'expectedRevision': 0,
          'definitionRevision': 1,
          'values': {'title': 'Legacy record $i'},
        });
      await engine.run(
        api,
        'alice',
        engine.action('full-record', version, 'addBook', {
          'data': {'title': 'Full record', 'status': 'Reading'},
        }),
      );
      final token = engine.token(82);
      await call(api, 'alice', {
        'op': 'createInvitation',
        'appId': 'legacy',
        'id': 'legacy-invite',
        'operationId': 'legacy-invite',
        'role': 'viewer',
        'recipientId': 'bob',
        'token': token,
      });
      await call(api, 'bob', {
        'op': 'acceptInvitation',
        'operationId': 'legacy-accept',
        'token': token,
      });
      final rows = (await listApps(api, 'bob'))['apps'] as List,
          legacy = rows.singleWhere((app) => app['id'] == 'legacy') as Map,
          full = rows.singleWhere((app) => app['id'] == 'app') as Map;
      check(
        legacy['engine'] == 'bounded.v1' &&
            legacy['publishedRevision'] == 1 &&
            legacy['version'] == null &&
            legacy['recordCount'] == 3,
        'Bounded engine/revision/count changed',
      );
      check(
        full['engine'] == 'appspec.v1' && full['recordCount'] == 1,
        'Full engine count changed',
      );
      await pin(api, 'bob', 'legacy', true, 0, 'legacy-pin');
      check(
        ((await listApps(api, 'bob', pinnedOnly: true))['apps'] as List)
                .single['id'] ==
            'legacy',
        'Bounded app could not use private shortcut',
      );
      definition['title'] = 'Private bounded edit';
      await call(api, 'alice', {
        'op': 'saveDraft',
        'appId': 'legacy',
        'operationId': 'legacy-private',
        'expectedRevision': 1,
        'expectedPublishedRevision': 1,
        'definition': definition,
      });
      final drafts = (await listDrafts(api, 'alice'))['drafts'] as List;
      check(
        drafts.length == 1 &&
            drafts.single['engine'] == 'bounded.v1' &&
            drafts.single['name'] == 'Private bounded edit',
        'Bounded private draft lost or misinterpreted as AppSpec',
      );
      check(
        ((await listDrafts(api, 'bob'))['drafts'] as List).isEmpty,
        'Reader saw bounded private edit',
      );
      await store.create('apps', 'v1-only', {
        'ownerId': 'alice',
        'workspaceId': 'ws',
        'name': 'Old v1 shell',
        'draftRevision': 1,
        'publishedRevision': 0,
        'draftJson': jsonEncode(definition),
        'guard': 'legacy-guard',
      });
      final adopted = (await listDrafts(api, 'alice'))['drafts'] as List;
      check(
        adopted.any(
          (draft) =>
              draft['appId'] == 'v1-only' && draft['engine'] == 'bounded.v1',
        ),
        'Owner v1 unadopted private draft not discoverable',
      );
      check(
        !((await listApps(api, 'bob'))['apps'] as List).any(
          (app) => app['id'] == 'v1-only',
        ),
        'Unpublished owner shell leaked',
      );
    },
  );
  await test(
    'launcher totals include all record and pool pages and stay consistent under a concurrent business write',
    () async {
      final store = PausedCommitStore();
      final (_, api, _) = await engine.fixture('reading', store: store);
      final app = await instantiate(
            api,
            'alice',
            'capacity',
            template: 'volunteer',
          ),
          version = (app['version'] as Map)['id'] as String;
      String? first;
      for (var i = 0; i < 101; i++) {
        final result = await call(api, 'alice', {
          'op': 'spec.execute',
          'appId': 'capacity',
          'versionId': version,
          'operationId': 'pool-$i',
          'actionId': 'addShift',
          'input': {
            'data': {'title': 'Pool $i', 'startsAt': '2030-01-01T10:00:00Z'},
            'capacity': 2,
          },
        });
        first ??= (result['outcome'] as Map)['recordId'] as String;
      }
      await call(api, 'alice', {
        'op': 'spec.execute',
        'appId': 'capacity',
        'versionId': version,
        'operationId': 'one-claim',
        'actionId': 'join',
        'targetRecordId': first,
        'input': {},
      });
      final summary =
          ((await listApps(api, 'alice'))['apps'] as List).singleWhere(
                (app) => app['id'] == 'capacity',
              )
              as Map;
      check(
        summary['recordCount'] == 101 && summary['availablePlaces'] == 201,
        'Launcher counted only a row/pool page',
      );
      store.pauseNext();
      final reached = store.reached!, reading = listApps(api, 'alice');
      await reached.future;
      await call(api, 'alice', {
        'op': 'spec.execute',
        'appId': 'capacity',
        'versionId': version,
        'operationId': 'release-during-count',
        'actionId': 'leave',
        'targetRecordId': first,
        'input': {},
      });
      store.release!.complete();
      await error(() => reading, 'transaction_conflict');
      final fresh =
          ((await listApps(api, 'alice'))['apps'] as List).singleWhere(
                (app) => app['id'] == 'capacity',
              )
              as Map;
      check(
        fresh['recordCount'] == 101 && fresh['availablePlaces'] == 202,
        'Launcher did not refetch a consistent complete count',
      );
    },
  );
  await test(
    'sharing appAccess reads only current metadata across both engines without any private candidate hydration',
    () async {
      final store = DraftBlindStore();
      final (_, api, version) = await engine.fixture('chores', store: store);
      await engine.join(api, 'bob', 83, role: 'member');
      await save(
        api,
        'alice',
        'app',
        spec.starterTemplates()['chores']!.toJson(),
        1,
        version,
        'metadata-private',
      );
      await call(api, 'alice', {
        'op': 'createApp',
        'id': 'bounded-shell',
        'workspaceId': 'ws',
        'name': 'Bounded shell',
      });
      await call(api, 'alice', {
        'op': 'spec.createApp',
        'id': 'full-shell',
        'workspaceId': 'ws',
        'name': 'Full shell',
        'operationId': 'metadata-shell',
      });
      store.blind = true;
      final shared =
          (await call(api, 'bob', {
                'op': 'spec.appAccess',
                'appId': 'app',
              }))['app']
              as Map;
      check(
        shared['engine'] == 'appspec.v1' &&
            shared['role'] == 'member' &&
            (shared['capabilities'] as Map)['writeRecords'] == true,
        'Full source policy lost in metadata summary',
      );
      check(
        !shared.containsKey('draft') &&
            !shared.containsKey('version') &&
            !shared.containsKey('candidateHash'),
        'Sharing response carried definitions/candidates',
      );
      final bounded =
          (await call(api, 'alice', {
                'op': 'spec.appAccess',
                'appId': 'bounded-shell',
              }))['app']
              as Map;
      check(
        bounded['engine'] == 'bounded.v1' && bounded['name'] == 'Bounded shell',
        'Bounded metadata unavailable',
      );
      final shell =
          (await call(api, 'alice', {
                'op': 'spec.appAccess',
                'appId': 'full-shell',
              }))['app']
              as Map;
      check(
        (shell['capabilities'] as Map)['writeRecords'] == false,
        'Unpublished full shell invented writable actions',
      );
      await error(
        () => call(api, 'mallory', {'op': 'spec.appAccess', 'appId': 'app'}),
        'not_found',
      );
    },
  );
  await test(
    'lifecycle provisioning keeps provider bulk column types and every new table private',
    () async {
      final schema =
          jsonDecode(await File('schema.json').readAsString()) as Map;
      final tables = (schema['tables'] as List).cast<Map>(),
          values = tables.singleWhere(
            (table) => table['tableId'] == 'spec_values',
          );
      final columns = (values['columns'] as List).cast<Map>();
      check(
        columns.singleWhere(
              (column) => column['key'] == 'numberValue',
            )['type'] ==
            'double',
        'Appwrite bulk float column must use double type',
      );
      final timestamp = columns.singleWhere(
        (column) => column['key'] == 'timestampValue',
      );
      check(
        timestamp['type'] == 'varchar' && timestamp['size'] == 64,
        'Lossless timestamp projection regressed',
      );
      for (final table in tables)
        check(
          table['rowSecurity'] == true &&
              (table['permissions'] as List).isEmpty,
          'A table acquired public permissions',
        );
    },
  );
  return passed;
}

Future<void> main() async {
  final count = await runLifecycleChecks();
  print(
    '$count lifecycle checks passed (simulated store; live Cloud acceptance remains separate).',
  );
}
