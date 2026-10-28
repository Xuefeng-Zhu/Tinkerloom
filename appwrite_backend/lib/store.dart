abstract interface class RowStore {
  Future<Map<String, dynamic>?> get(String table, String id,
      {String? transactionId});
  Future<Map<String, dynamic>> create(
      String table, String id, Map<String, dynamic> data,
      {String? transactionId});
  Future<Map<String, dynamic>> update(
      String table, String id, Map<String, dynamic> data,
      {String? transactionId});
  Future<List<Map<String, dynamic>>> list(
    String table,
    Map<String, String> filters, {
    String? transactionId,
    int limit = 100,
    String? afterId,
    bool detectOverflow = true,
  });
  Future<String> beginTransaction();
  Future<void> finishTransaction(String transactionId, {required bool commit});
}
