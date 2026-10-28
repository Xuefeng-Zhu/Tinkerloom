import 'dart:convert';
import 'dart:io';

class ServiceException implements Exception {
  const ServiceException(this.code, this.status);
  final String code;
  final int status;
}

class RestException implements Exception {
  const RestException(this.status, {this.authFailure = false});
  final int status;
  final bool authFailure;
}

abstract interface class RowStore {
  Future<Map<String, dynamic>?> get(String table, String id);
  Future<Map<String, dynamic>> create(
    String table,
    String id,
    Map<String, dynamic> data,
  );
  Future<List<Map<String, dynamic>>> list(
    String table,
    Map<String, String> filters,
  );
}

/// All rows are private to this backend. Access is checked on every operation.
/// This first slice supports owners only; it does not implement sharing.
class PlatformService {
  PlatformService(this.store);
  final RowStore store;
  static final _id = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,35}$');

  String _validId(Object? value) {
    if (value is! String || !_id.hasMatch(value)) {
      throw const ServiceException('invalid_id', 400);
    }
    return value;
  }

  String _name(Object? value) {
    if (value is! String) throw const ServiceException('invalid_name', 400);
    final name = value.trim();
    if (name.isEmpty || name.length > 128) {
      throw const ServiceException('invalid_name', 400);
    }
    return name;
  }

  Future<Map<String, dynamic>> _workspace(String actor, Object? id) async {
    final row = await store.get('workspaces', _validId(id));
    // Deliberately avoid disclosing whether another user's workspace exists.
    if (row == null || row['ownerId'] != actor) {
      throw const ServiceException('not_found', 404);
    }
    return row;
  }

  Map<String, dynamic> _publicRow(
    Map<String, dynamic> row, {
    bool app = false,
  }) => {
    'id': row[r'$id'],
    'name': row['name'],
    if (app) 'workspaceId': row['workspaceId'],
  };

  Future<Map<String, dynamic>> _createOnce(
    String table,
    String id,
    Map<String, dynamic> data,
  ) async {
    try {
      return await store.create(table, id, data);
    } on RestException catch (error) {
      if (error.status != 409) rethrow;
      final old = await store.get(table, id);
      if (old != null &&
          data.entries.every((entry) => old[entry.key] == entry.value)) {
        return old;
      }
      throw const ServiceException('id_conflict', 409);
    }
  }

  Future<Map<String, dynamic>> execute(
    String actor,
    Map<String, dynamic> input,
  ) async {
    if (actor.isEmpty) throw const ServiceException('unauthenticated', 401);
    switch (input['op']) {
      case 'createWorkspace':
        final id = _validId(input['id']);
        final row = await _createOnce('workspaces', id, {
          'ownerId': actor,
          'name': _name(input['name']),
        });
        return {'workspace': _publicRow(row)};
      case 'listWorkspaces':
        final rows = await store.list('workspaces', {'ownerId': actor});
        return {'workspaces': rows.map(_publicRow).toList()};
      case 'createApp':
        final id = _validId(input['id']);
        final workspace = await _workspace(actor, input['workspaceId']);
        final row = await _createOnce('apps', id, {
          'ownerId': actor,
          'workspaceId': workspace[r'$id'],
          'name': _name(input['name']),
        });
        return {'app': _publicRow(row, app: true)};
      case 'listApps':
        final workspace = await _workspace(actor, input['workspaceId']);
        final rows = await store.list('apps', {
          'ownerId': actor,
          'workspaceId': workspace[r'$id'] as String,
        });
        return {'apps': rows.map((row) => _publicRow(row, app: true)).toList()};
      default:
        throw const ServiceException('unknown_operation', 400);
    }
  }
}

/// Calls Appwrite's documented REST API; the key never leaves the Function.
class AppwriteRest implements RowStore {
  AppwriteRest(this.endpoint, this.project, this.database, this.key);
  final Uri endpoint;
  final String project;
  final String database;
  final String key;
  final _client = HttpClient();

  Uri _uri(String path, [List<Map<String, dynamic>> queries = const []]) {
    final base = endpoint.toString().replaceFirst(RegExp(r'/$'), '');
    final pairs = <String, String>{};
    for (var i = 0; i < queries.length; i++) {
      pairs['queries[$i]'] = jsonEncode(queries[i]);
    }
    return Uri.parse('$base$path')
        .replace(queryParameters: pairs.isEmpty ? null : pairs);
  }

  String _rows(String table) =>
      '/tablesdb/${Uri.encodeComponent(database)}/tables/${Uri.encodeComponent(table)}/rows';

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? jwt,
  }) async {
    final request = await _client.openUrl(method, uri);
    request.headers.set('X-Appwrite-Project', project);
    if (jwt == null) {
      request.headers.set('X-Appwrite-Key', key);
    } else {
      request.headers.set('X-Appwrite-JWT', jwt);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RestException(
        response.statusCode,
        authFailure:
            jwt != null &&
            (response.statusCode == 401 || response.statusCode == 403),
      );
    }
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  }

  Future<Map<String, dynamic>> account(String jwt) =>
      _request('GET', _uri('/account'), jwt: jwt);

  @override
  Future<Map<String, dynamic>?> get(String table, String id) async {
    try {
      return await _request(
        'GET',
        _uri('${_rows(table)}/${Uri.encodeComponent(id)}'),
      );
    } on RestException catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> create(
    String table,
    String id,
    Map<String, dynamic> data,
  ) => _request(
    'POST',
    _uri(_rows(table)),
    body: {'rowId': id, 'data': data, 'permissions': <String>[]},
  );

  @override
  Future<List<Map<String, dynamic>>> list(
    String table,
    Map<String, String> filters,
  ) async {
    final queries = [
      for (final entry in filters.entries)
        {
          'method': 'equal',
          'column': entry.key,
          'values': [entry.value],
        },
      {
        'method': 'limit',
        'values': [100],
      },
    ];
    final result = await _request('GET', _uri(_rows(table), queries));
    if ((result['total'] as int) > 100)
      throw const ServiceException('too_many_results', 409);
    return (result['rows'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  void close() => _client.close(force: true);
}
