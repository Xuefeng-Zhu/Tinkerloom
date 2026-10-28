/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod/serverpod.dart' as _is;

abstract class ActionReceipt
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  ActionReceipt._({
    this.id,
    required this.appId,
    required this.actorId,
    required this.idempotencyKey,
    required this.requestHash,
    required this.outcomeJson,
    required this.createdAt,
  });

  factory ActionReceipt({
    int? id,
    required int appId,
    required String actorId,
    required String idempotencyKey,
    required String requestHash,
    required String outcomeJson,
    required DateTime createdAt,
  }) = _ActionReceiptImpl;

  factory ActionReceipt.fromJson(Map<String, dynamic> jsonSerialization) {
    return ActionReceipt(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      actorId: jsonSerialization['actorId'] as String,
      idempotencyKey: jsonSerialization['idempotencyKey'] as String,
      requestHash: jsonSerialization['requestHash'] as String,
      outcomeJson: jsonSerialization['outcomeJson'] as String,
      createdAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
    );
  }

  static final t = ActionReceiptTable();

  static const db = ActionReceiptRepository._();

  @override
  int? id;

  int appId;

  String actorId;

  String idempotencyKey;

  String requestHash;

  String outcomeJson;

  DateTime createdAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [ActionReceipt]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  ActionReceipt copyWith({
    int? id,
    int? appId,
    String? actorId,
    String? idempotencyKey,
    String? requestHash,
    String? outcomeJson,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ActionReceipt',
      if (id != null) 'id': id,
      'appId': appId,
      'actorId': actorId,
      'idempotencyKey': idempotencyKey,
      'requestHash': requestHash,
      'outcomeJson': outcomeJson,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static ActionReceiptInclude include() {
    return ActionReceiptInclude._();
  }

  static ActionReceiptIncludeList includeList({
    _is.WhereExpressionBuilder<ActionReceiptTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<ActionReceiptTable>? orderBy,
    _is.OrderByListBuilder<ActionReceiptTable>? orderByList,
    ActionReceiptInclude? include,
  }) {
    return ActionReceiptIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(ActionReceipt.t),
      orderByList: orderByList?.call(ActionReceipt.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ActionReceiptImpl extends ActionReceipt {
  _ActionReceiptImpl({
    int? id,
    required int appId,
    required String actorId,
    required String idempotencyKey,
    required String requestHash,
    required String outcomeJson,
    required DateTime createdAt,
  }) : super._(
         id: id,
         appId: appId,
         actorId: actorId,
         idempotencyKey: idempotencyKey,
         requestHash: requestHash,
         outcomeJson: outcomeJson,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [ActionReceipt]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  ActionReceipt copyWith({
    Object? id = _Undefined,
    int? appId,
    String? actorId,
    String? idempotencyKey,
    String? requestHash,
    String? outcomeJson,
    DateTime? createdAt,
  }) {
    return ActionReceipt(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      actorId: actorId ?? this.actorId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      requestHash: requestHash ?? this.requestHash,
      outcomeJson: outcomeJson ?? this.outcomeJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ActionReceiptUpdateTable extends _is.UpdateTable<ActionReceiptTable> {
  ActionReceiptUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<String, String> actorId(String value) => _is.ColumnValue(
    table.actorId,
    value,
  );

  _is.ColumnValue<String, String> idempotencyKey(String value) =>
      _is.ColumnValue(
        table.idempotencyKey,
        value,
      );

  _is.ColumnValue<String, String> requestHash(String value) => _is.ColumnValue(
    table.requestHash,
    value,
  );

  _is.ColumnValue<String, String> outcomeJson(String value) => _is.ColumnValue(
    table.outcomeJson,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );
}

class ActionReceiptTable extends _is.Table<int?> {
  ActionReceiptTable({super.tableRelation}) : super(tableName: 'nest_receipt') {
    updateTable = ActionReceiptUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    actorId = _is.ColumnString(
      'actorId',
      this,
    );
    idempotencyKey = _is.ColumnString(
      'idempotencyKey',
      this,
    );
    requestHash = _is.ColumnString(
      'requestHash',
      this,
    );
    outcomeJson = _is.ColumnString(
      'outcomeJson',
      this,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
    );
  }

  late final ActionReceiptUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnString actorId;

  late final _is.ColumnString idempotencyKey;

  late final _is.ColumnString requestHash;

  late final _is.ColumnString outcomeJson;

  late final _is.ColumnDateTime createdAt;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    actorId,
    idempotencyKey,
    requestHash,
    outcomeJson,
    createdAt,
  ];
}

class ActionReceiptInclude extends _is.IncludeObject {
  ActionReceiptInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => ActionReceipt.t;
}

class ActionReceiptIncludeList extends _is.IncludeList {
  ActionReceiptIncludeList._({
    _is.WhereExpressionBuilder<ActionReceiptTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(ActionReceipt.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => ActionReceipt.t;
}

class ActionReceiptRepository {
  const ActionReceiptRepository._();

  /// Returns a list of [ActionReceipt]s matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order of the items use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// The maximum number of items can be set by [limit]. If no limit is set,
  /// all items matching the query will be returned.
  ///
  /// [offset] defines how many items to skip, after which [limit] (or all)
  /// items are read from the database.
  ///
  /// ```dart
  /// var persons = await Persons.db.find(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.firstName,
  ///   limit: 100,
  /// );
  /// ```
  Future<List<ActionReceipt>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<ActionReceiptTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<ActionReceiptTable>? orderBy,
    _is.OrderByListBuilder<ActionReceiptTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<ActionReceipt>(
      where: where?.call(ActionReceipt.t),
      orderBy: orderBy?.call(ActionReceipt.t),
      orderByList: orderByList?.call(ActionReceipt.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [ActionReceipt] matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// [offset] defines how many items to skip, after which the next one will be picked.
  ///
  /// ```dart
  /// var youngestPerson = await Persons.db.findFirstRow(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.age,
  /// );
  /// ```
  Future<ActionReceipt?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<ActionReceiptTable>? where,
    int? offset,
    _is.OrderByBuilder<ActionReceiptTable>? orderBy,
    _is.OrderByListBuilder<ActionReceiptTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<ActionReceipt>(
      where: where?.call(ActionReceipt.t),
      orderBy: orderBy?.call(ActionReceipt.t),
      orderByList: orderByList?.call(ActionReceipt.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [ActionReceipt] by its [id] or null if no such row exists.
  Future<ActionReceipt?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<ActionReceipt>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [ActionReceipt]s in the list and returns the inserted rows.
  ///
  /// The returned [ActionReceipt]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  ///
  /// If [noReturn] is set to `true`, the inserted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ActionReceipt>> insert(
    _is.DatabaseSession session,
    List<ActionReceipt> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<ActionReceipt>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [ActionReceipt] and returns the inserted row.
  ///
  /// The returned [ActionReceipt] will have its `id` field set.
  Future<ActionReceipt> insertRow(
    _is.DatabaseSession session,
    ActionReceipt row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<ActionReceipt>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [ActionReceipt]s in the list and returns the resulting rows.
  ///
  /// If a row conflicts on the given [conflictColumns], the existing row is
  /// updated with the new values. Otherwise, a new row is inserted.
  ///
  /// If [updateColumns] is provided, only those columns will be updated on
  /// conflict. If null, all non-conflict, non-id columns are updated.
  ///
  /// If [updateWhere] is provided, the update only applies to rows matching the
  /// given expression. Conflicting rows that don't match are skipped and not
  /// returned, so the resulting list may be shorter than [rows].
  ///
  /// The returned [ActionReceipt]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ActionReceipt>> upsert(
    _is.DatabaseSession session,
    List<ActionReceipt> rows, {
    required _is.ColumnSelections<ActionReceiptTable> conflictColumns,
    _is.ColumnSelections<ActionReceiptTable>? updateColumns,
    _is.WhereExpressionBuilder<ActionReceiptTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<ActionReceipt>(
      rows,
      conflictColumns: conflictColumns(ActionReceipt.t),
      updateColumns: updateColumns?.call(ActionReceipt.t),
      updateWhere: updateWhere?.call(ActionReceipt.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [ActionReceipt] and returns the resulting row.
  ///
  /// If the row conflicts on the given [conflictColumns], the existing row is
  /// updated. Otherwise, a new row is inserted.
  ///
  /// If [updateColumns] is provided, only those columns will be updated on
  /// conflict. If null, all non-conflict, non-id columns are updated.
  ///
  /// If [updateWhere] is provided, the update only applies when the existing
  /// row matches the expression. Returns `null` if no row was affected — for
  /// example when [updateWhere] does not match the conflicting row.
  ///
  /// The returned [ActionReceipt] will have its `id` field set.
  Future<ActionReceipt?> upsertRow(
    _is.DatabaseSession session,
    ActionReceipt row, {
    required _is.ColumnSelections<ActionReceiptTable> conflictColumns,
    _is.ColumnSelections<ActionReceiptTable>? updateColumns,
    _is.WhereExpressionBuilder<ActionReceiptTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<ActionReceipt>(
      row,
      conflictColumns: conflictColumns(ActionReceipt.t),
      updateColumns: updateColumns?.call(ActionReceipt.t),
      updateWhere: updateWhere?.call(ActionReceipt.t),
      transaction: transaction,
    );
  }

  /// Updates all [ActionReceipt]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ActionReceipt>> update(
    _is.DatabaseSession session,
    List<ActionReceipt> rows, {
    _is.ColumnSelections<ActionReceiptTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<ActionReceipt>(
      rows,
      columns: columns?.call(ActionReceipt.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [ActionReceipt]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<ActionReceipt> updateRow(
    _is.DatabaseSession session,
    ActionReceipt row, {
    _is.ColumnSelections<ActionReceiptTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<ActionReceipt>(
      row,
      columns: columns?.call(ActionReceipt.t),
      transaction: transaction,
    );
  }

  /// Updates a single [ActionReceipt] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<ActionReceipt?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<ActionReceiptUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<ActionReceipt>(
      id,
      columnValues: columnValues(ActionReceipt.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [ActionReceipt]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ActionReceipt>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<ActionReceiptUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<ActionReceiptTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<ActionReceiptTable>? orderBy,
    _is.OrderByListBuilder<ActionReceiptTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<ActionReceipt>(
      columnValues: columnValues(ActionReceipt.t.updateTable),
      where: where(ActionReceipt.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(ActionReceipt.t),
      orderByList: orderByList?.call(ActionReceipt.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [ActionReceipt]s in the list and returns the deleted rows.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ActionReceipt>> delete(
    _is.DatabaseSession session,
    List<ActionReceipt> rows, {
    _is.OrderByBuilder<ActionReceiptTable>? orderBy,
    _is.OrderByListBuilder<ActionReceiptTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<ActionReceipt>(
      rows,
      orderBy: orderBy?.call(ActionReceipt.t),
      orderByList: orderByList?.call(ActionReceipt.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [ActionReceipt].
  Future<ActionReceipt> deleteRow(
    _is.DatabaseSession session,
    ActionReceipt row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<ActionReceipt>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ActionReceipt>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<ActionReceiptTable> where,
    _is.OrderByBuilder<ActionReceiptTable>? orderBy,
    _is.OrderByListBuilder<ActionReceiptTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<ActionReceipt>(
      where: where(ActionReceipt.t),
      orderBy: orderBy?.call(ActionReceipt.t),
      orderByList: orderByList?.call(ActionReceipt.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<ActionReceiptTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<ActionReceipt>(
      where: where?.call(ActionReceipt.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [ActionReceipt] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<ActionReceiptTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<ActionReceipt>(
      where: where(ActionReceipt.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
