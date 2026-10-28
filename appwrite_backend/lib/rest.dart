import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'store.dart';

/// A server-only adapter. Request keys, JWTs, and provider bodies are not logged.
class AppwriteRest implements RowStore {
  AppwriteRest(this.endpoint, this.project, this.database, this.key);
  final Uri endpoint;
  final String project;
  final String database;
  final String key;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

  Uri _uri(
    String path, {
    List<Map<String, dynamic>> queries = const [],
    String? transactionId,
  }) {
    final base = endpoint.toString().replaceFirst(RegExp(r'/$'), '');
    final pairs = <String, String>{};
    for (var i = 0; i < queries.length; i++) {
      pairs['queries[$i]'] = jsonEncode(queries[i]);
    }
    if (transactionId != null) pairs['transactionId'] = transactionId;
    return Uri.parse(
      '$base$path',
    ).replace(queryParameters: pairs.isEmpty ? null : pairs);
  }

  String _rows(String table) =>
      '/tablesdb/${Uri.encodeComponent(database)}/tables/${Uri.encodeComponent(table)}/rows';

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? jwt,
  }) async {
    final request = await _client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 8));
    request.headers.set('X-Appwrite-Project', project);
    request.headers.set(
      jwt == null ? 'X-Appwrite-Key' : 'X-Appwrite-JWT',
      jwt ?? key,
    );
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw RestException(
        response.statusCode,
        authFailure:
            jwt != null &&
            (response.statusCode == 401 || response.statusCode == 403),
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > 33554432)
        throw const RestException(502);
      bytes.addAll(chunk);
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  Future<Map<String, dynamic>> account(String jwt) =>
      _request('GET', _uri('/account'), jwt: jwt);

  @override
  Future<Map<String, dynamic>?> get(
    String table,
    String id, {
    String? transactionId,
  }) async {
    try {
      return await _request(
        'GET',
        _uri(
          '${_rows(table)}/${Uri.encodeComponent(id)}',
          transactionId: transactionId,
        ),
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
    Map<String, dynamic> data, {
    String? transactionId,
  }) => _request(
    'POST',
    _uri(_rows(table)),
    body: {
      'rowId': id,
      'data': data,
      'permissions': <String>[],
      if (transactionId != null) 'transactionId': transactionId,
    },
  );

  @override
  Future<Map<String, dynamic>> update(
    String table,
    String id,
    Map<String, dynamic> data, {
    String? transactionId,
  }) => _request(
    'PATCH',
    _uri('${_rows(table)}/${Uri.encodeComponent(id)}'),
    body: {
      'data': data,
      if (transactionId != null) 'transactionId': transactionId,
    },
  );

  @override
  Future<List<Map<String, dynamic>>> list(
    String table,
    Map<String, String> filters, {
    String? transactionId,
    int limit = 100,
    String? afterId,
    bool detectOverflow = true,
    List<String>? select,
  }) async {
    final queries = [
      for (final entry in filters.entries)
        {
          'method': 'equal',
          'attribute': entry.key,
          'values': [entry.value],
        },
      {'method': 'orderAsc', 'attribute': r'$id'},
      {
        'method': 'limit',
        'values': [limit],
      },
      if (afterId != null)
        {
          'method': 'cursorAfter',
          'values': [afterId],
        },
      if (select != null) {'method': 'select', 'values': select},
    ];
    final result = await _request(
      'GET',
      _uri(_rows(table), queries: queries, transactionId: transactionId),
    );
    if (detectOverflow && (result['total'] as int) > limit)
      throw const ServiceException('too_many_results', 409);
    return (result['rows'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<String> beginTransaction() async {
    final transaction = await _request(
      'POST',
      _uri('/tablesdb/transactions'),
      body: {'ttl': 60},
    );
    return transaction[r'$id'] as String;
  }

  @override
  Future<void> finishTransaction(
    String transactionId, {
    required bool commit,
  }) async {
    await _request(
      'PATCH',
      _uri('/tablesdb/transactions/${Uri.encodeComponent(transactionId)}'),
      body: {if (commit) 'commit': true else 'rollback': true},
    );
  }

  void close() => _client.close(force: true);
}
