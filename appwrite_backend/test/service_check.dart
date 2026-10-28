import '../lib/service.dart';

class MemoryStore implements RowStore {
  final rows = <String, Map<String, Map<String, dynamic>>>{};
  @override
  Future<Map<String, dynamic>?> get(String table, String id) async =>
      rows[table]?[id];
  @override
  Future<Map<String, dynamic>> create(
    String table,
    String id,
    Map<String, dynamic> data,
  ) async {
    final collection = rows.putIfAbsent(table, () => {});
    if (collection.containsKey(id)) throw const RestException(409);
    return collection[id] = {r'$id': id, ...data};
  }

  @override
  Future<List<Map<String, dynamic>>> list(
    String table,
    Map<String, String> filters,
  ) async => (rows[table]?.values ?? [])
      .where((r) => filters.entries.every((e) => r[e.key] == e.value))
      .toList();
}

Future<void> expectError(Future<Object?> Function() run, String code) async {
  try {
    await run();
    throw StateError('Expected $code');
  } on ServiceException catch (e) {
    if (e.code != code) throw StateError('Expected $code, got ${e.code}');
  }
}

Future<void> main() async {
  final store = MemoryStore();
  final api = PlatformService(store);
  final create = {
    'op': 'createWorkspace',
    'id': 'workspace1',
    'name': ' My space ',
  };
  final first = await api.execute('alice', create);
  final again = await api.execute('alice', create);
  if ((first['workspace'] as Map)['name'] != 'My space' ||
      (again['workspace'] as Map)['id'] != 'workspace1')
    throw StateError('Create/retry failed');
  await expectError(
    () => api.execute('alice', {...create, 'name': 'Other'}),
    'id_conflict',
  );
  await expectError(() => api.execute('bob', create), 'id_conflict');
  await expectError(
    () => api.execute('bob', {'op': 'listApps', 'workspaceId': 'workspace1'}),
    'not_found',
  );
  await expectError(
    () => api.execute('bob', {
      'op': 'createApp',
      'workspaceId': 'workspace1',
      'id': 'bad',
      'name': 'Bad',
    }),
    'not_found',
  );
  await api.execute('alice', {
    'op': 'createApp',
    'workspaceId': 'workspace1',
    'id': 'app1',
    'name': 'Tasks',
  });
  final apps = await api.execute('alice', {
    'op': 'listApps',
    'workspaceId': 'workspace1',
  });
  if ((apps['apps'] as List).length != 1) throw StateError('App missing');
  final bob = await api.execute('bob', {'op': 'listWorkspaces'});
  if ((bob['workspaces'] as List).isNotEmpty)
    throw StateError('Tenant data leaked');
  await expectError(
    () => api.execute('alice', {
      'op': 'createWorkspace',
      'id': '../bad',
      'name': 'Bad',
    }),
    'invalid_id',
  );
  await expectError(
    () => api.execute('alice', {
      'op': 'createWorkspace',
      'id': 'good',
      'name': ' ',
    }),
    'invalid_name',
  );
  print('Platform service checks passed');
}
