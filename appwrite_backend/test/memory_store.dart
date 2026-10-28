import 'dart:convert';
import '../lib/service.dart';

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

class _Transaction {
  final staged = <String, Map<String, dynamic>>{};
  final versions = <String, int>{};
}

/// Simulated optimistic staging, not a substitute for Appwrite integration tests.
class MemoryStore implements RowStore {
  final rows = <String, Map<String, Map<String, dynamic>>>{};
  final versions = <String, int>{};
  final transactions = <String, _Transaction>{};
  var _counter = 0;
  bool failBeforeCommit = false;
  bool loseCommitResponse = false;
  String _key(String table, String id) => '$table\u0000$id';

  @override
  Future<Map<String, dynamic>?> get(String table, String id,
      {String? transactionId}) async {
    Map<String, dynamic>? row = rows[table]?[id];
    if (transactionId != null)
      row = transactions[transactionId]!.staged[_key(table, id)] ?? row;
    return row == null ? null : _copy(row);
  }

  @override
  Future<Map<String, dynamic>> create(
      String table, String id, Map<String, dynamic> data,
      {String? transactionId}) async {
    if (await get(table, id, transactionId: transactionId) != null)
      throw const RestException(409);
    return _write(table, id, {r'$id': id, ...data}, transactionId);
  }

  @override
  Future<Map<String, dynamic>> update(
      String table, String id, Map<String, dynamic> data,
      {String? transactionId}) async {
    final old = await get(table, id, transactionId: transactionId);
    if (old == null) throw const RestException(404);
    return _write(table, id, {...old, ...data}, transactionId);
  }

  Map<String, dynamic> _write(String table, String id, Map<String, dynamic> row,
      String? transactionId) {
    final key = _key(table, id);
    if (transactionId != null) {
      final tx = transactions[transactionId]!;
      tx.versions.putIfAbsent(key, () => versions[key] ?? 0);
      tx.staged[key] = _copy(row);
    } else {
      rows.putIfAbsent(table, () => {})[id] = _copy(row);
      versions[key] = (versions[key] ?? 0) + 1;
    }
    return _copy(row);
  }

  @override
  Future<List<Map<String, dynamic>>> list(
      String table, Map<String, String> filters,
      {String? transactionId,
      int limit = 100,
      String? afterId,
      bool detectOverflow = true,
      List<String>? select}) async {
    final all = {...?rows[table]};
    if (transactionId != null) {
      for (final entry in transactions[transactionId]!.staged.entries) {
        if (entry.key.startsWith('$table\u0000'))
          all[entry.value[r'$id'] as String] = entry.value;
      }
    }
    final result = all.values
        .where((row) =>
            filters.entries.every((entry) => row[entry.key] == entry.value))
        .toList()
      ..sort((a, b) => (a[r'$id'] as String).compareTo(b[r'$id'] as String));
    if (detectOverflow && result.length > limit)
      throw const ServiceException('too_many_results', 409);
    return result
        .where((row) =>
            afterId == null || (row[r'$id'] as String).compareTo(afterId) > 0)
        .take(limit)
        .map((row) => select == null
            ? _copy(row)
            : {
                for (final key in select)
                  if (row.containsKey(key)) key: row[key]
              })
        .toList();
  }

  @override
  Future<String> beginTransaction() async {
    final id = 'transaction-${++_counter}';
    transactions[id] = _Transaction();
    return id;
  }

  @override
  Future<void> finishTransaction(String transactionId,
      {required bool commit}) async {
    final tx = transactions[transactionId];
    if (tx == null) throw const RestException(409);
    if (!commit) {
      transactions.remove(transactionId);
      return;
    }
    if (failBeforeCommit) throw const RestException(502);
    for (final entry in tx.versions.entries) {
      if ((versions[entry.key] ?? 0) != entry.value)
        throw const RestException(409);
    }
    for (final entry in tx.staged.entries) {
      final parts = entry.key.split('\u0000');
      rows.putIfAbsent(parts[0], () => {})[parts[1]] = _copy(entry.value);
      versions[entry.key] = (versions[entry.key] ?? 0) + 1;
    }
    transactions.remove(transactionId);
    if (loseCommitResponse) {
      loseCommitResponse = false;
      throw const RestException(502);
    }
  }
}
