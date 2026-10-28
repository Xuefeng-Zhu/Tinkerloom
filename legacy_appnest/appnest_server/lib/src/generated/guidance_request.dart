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

abstract class GuidanceRequest
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  GuidanceRequest._({
    this.id,
    required this.actorId,
    required this.createdAt,
  });

  factory GuidanceRequest({
    int? id,
    required String actorId,
    required DateTime createdAt,
  }) = _GuidanceRequestImpl;

  factory GuidanceRequest.fromJson(Map<String, dynamic> jsonSerialization) {
    return GuidanceRequest(
      id: jsonSerialization['id'] as int?,
      actorId: jsonSerialization['actorId'] as String,
      createdAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
    );
  }

  static final t = GuidanceRequestTable();

  static const db = GuidanceRequestRepository._();

  @override
  int? id;

  String actorId;

  DateTime createdAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [GuidanceRequest]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  GuidanceRequest copyWith({
    int? id,
    String? actorId,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'GuidanceRequest',
      if (id != null) 'id': id,
      'actorId': actorId,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static GuidanceRequestInclude include() {
    return GuidanceRequestInclude._();
  }

  static GuidanceRequestIncludeList includeList({
    _is.WhereExpressionBuilder<GuidanceRequestTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<GuidanceRequestTable>? orderBy,
    _is.OrderByListBuilder<GuidanceRequestTable>? orderByList,
    GuidanceRequestInclude? include,
  }) {
    return GuidanceRequestIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(GuidanceRequest.t),
      orderByList: orderByList?.call(GuidanceRequest.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _GuidanceRequestImpl extends GuidanceRequest {
  _GuidanceRequestImpl({
    int? id,
    required String actorId,
    required DateTime createdAt,
  }) : super._(
         id: id,
         actorId: actorId,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [GuidanceRequest]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  GuidanceRequest copyWith({
    Object? id = _Undefined,
    String? actorId,
    DateTime? createdAt,
  }) {
    return GuidanceRequest(
      id: id is int? ? id : this.id,
      actorId: actorId ?? this.actorId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class GuidanceRequestUpdateTable extends _is.UpdateTable<GuidanceRequestTable> {
  GuidanceRequestUpdateTable(super.table);

  _is.ColumnValue<String, String> actorId(String value) => _is.ColumnValue(
    table.actorId,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );
}

class GuidanceRequestTable extends _is.Table<int?> {
  GuidanceRequestTable({super.tableRelation})
    : super(tableName: 'nest_guidance_request') {
    updateTable = GuidanceRequestUpdateTable(this);
    actorId = _is.ColumnString(
      'actorId',
      this,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
    );
  }

  late final GuidanceRequestUpdateTable updateTable;

  late final _is.ColumnString actorId;

  late final _is.ColumnDateTime createdAt;

  @override
  List<_is.Column> get columns => [
    id,
    actorId,
    createdAt,
  ];
}

class GuidanceRequestInclude extends _is.IncludeObject {
  GuidanceRequestInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => GuidanceRequest.t;
}

class GuidanceRequestIncludeList extends _is.IncludeList {
  GuidanceRequestIncludeList._({
    _is.WhereExpressionBuilder<GuidanceRequestTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(GuidanceRequest.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => GuidanceRequest.t;
}

class GuidanceRequestRepository {
  const GuidanceRequestRepository._();

  /// Returns a list of [GuidanceRequest]s matching the given query parameters.
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
  Future<List<GuidanceRequest>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<GuidanceRequestTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<GuidanceRequestTable>? orderBy,
    _is.OrderByListBuilder<GuidanceRequestTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<GuidanceRequest>(
      where: where?.call(GuidanceRequest.t),
      orderBy: orderBy?.call(GuidanceRequest.t),
      orderByList: orderByList?.call(GuidanceRequest.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [GuidanceRequest] matching the given query parameters.
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
  Future<GuidanceRequest?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<GuidanceRequestTable>? where,
    int? offset,
    _is.OrderByBuilder<GuidanceRequestTable>? orderBy,
    _is.OrderByListBuilder<GuidanceRequestTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<GuidanceRequest>(
      where: where?.call(GuidanceRequest.t),
      orderBy: orderBy?.call(GuidanceRequest.t),
      orderByList: orderByList?.call(GuidanceRequest.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [GuidanceRequest] by its [id] or null if no such row exists.
  Future<GuidanceRequest?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<GuidanceRequest>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [GuidanceRequest]s in the list and returns the inserted rows.
  ///
  /// The returned [GuidanceRequest]s will have their `id` fields set.
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
  Future<List<GuidanceRequest>> insert(
    _is.DatabaseSession session,
    List<GuidanceRequest> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<GuidanceRequest>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [GuidanceRequest] and returns the inserted row.
  ///
  /// The returned [GuidanceRequest] will have its `id` field set.
  Future<GuidanceRequest> insertRow(
    _is.DatabaseSession session,
    GuidanceRequest row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<GuidanceRequest>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [GuidanceRequest]s in the list and returns the resulting rows.
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
  /// The returned [GuidanceRequest]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GuidanceRequest>> upsert(
    _is.DatabaseSession session,
    List<GuidanceRequest> rows, {
    required _is.ColumnSelections<GuidanceRequestTable> conflictColumns,
    _is.ColumnSelections<GuidanceRequestTable>? updateColumns,
    _is.WhereExpressionBuilder<GuidanceRequestTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<GuidanceRequest>(
      rows,
      conflictColumns: conflictColumns(GuidanceRequest.t),
      updateColumns: updateColumns?.call(GuidanceRequest.t),
      updateWhere: updateWhere?.call(GuidanceRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [GuidanceRequest] and returns the resulting row.
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
  /// The returned [GuidanceRequest] will have its `id` field set.
  Future<GuidanceRequest?> upsertRow(
    _is.DatabaseSession session,
    GuidanceRequest row, {
    required _is.ColumnSelections<GuidanceRequestTable> conflictColumns,
    _is.ColumnSelections<GuidanceRequestTable>? updateColumns,
    _is.WhereExpressionBuilder<GuidanceRequestTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<GuidanceRequest>(
      row,
      conflictColumns: conflictColumns(GuidanceRequest.t),
      updateColumns: updateColumns?.call(GuidanceRequest.t),
      updateWhere: updateWhere?.call(GuidanceRequest.t),
      transaction: transaction,
    );
  }

  /// Updates all [GuidanceRequest]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GuidanceRequest>> update(
    _is.DatabaseSession session,
    List<GuidanceRequest> rows, {
    _is.ColumnSelections<GuidanceRequestTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<GuidanceRequest>(
      rows,
      columns: columns?.call(GuidanceRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [GuidanceRequest]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<GuidanceRequest> updateRow(
    _is.DatabaseSession session,
    GuidanceRequest row, {
    _is.ColumnSelections<GuidanceRequestTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<GuidanceRequest>(
      row,
      columns: columns?.call(GuidanceRequest.t),
      transaction: transaction,
    );
  }

  /// Updates a single [GuidanceRequest] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<GuidanceRequest?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<GuidanceRequestUpdateTable>
    columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<GuidanceRequest>(
      id,
      columnValues: columnValues(GuidanceRequest.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [GuidanceRequest]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GuidanceRequest>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<GuidanceRequestUpdateTable>
    columnValues,
    required _is.WhereExpressionBuilder<GuidanceRequestTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<GuidanceRequestTable>? orderBy,
    _is.OrderByListBuilder<GuidanceRequestTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<GuidanceRequest>(
      columnValues: columnValues(GuidanceRequest.t.updateTable),
      where: where(GuidanceRequest.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(GuidanceRequest.t),
      orderByList: orderByList?.call(GuidanceRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [GuidanceRequest]s in the list and returns the deleted rows.
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
  Future<List<GuidanceRequest>> delete(
    _is.DatabaseSession session,
    List<GuidanceRequest> rows, {
    _is.OrderByBuilder<GuidanceRequestTable>? orderBy,
    _is.OrderByListBuilder<GuidanceRequestTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<GuidanceRequest>(
      rows,
      orderBy: orderBy?.call(GuidanceRequest.t),
      orderByList: orderByList?.call(GuidanceRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [GuidanceRequest].
  Future<GuidanceRequest> deleteRow(
    _is.DatabaseSession session,
    GuidanceRequest row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<GuidanceRequest>(
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
  Future<List<GuidanceRequest>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<GuidanceRequestTable> where,
    _is.OrderByBuilder<GuidanceRequestTable>? orderBy,
    _is.OrderByListBuilder<GuidanceRequestTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<GuidanceRequest>(
      where: where(GuidanceRequest.t),
      orderBy: orderBy?.call(GuidanceRequest.t),
      orderByList: orderByList?.call(GuidanceRequest.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<GuidanceRequestTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<GuidanceRequest>(
      where: where?.call(GuidanceRequest.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [GuidanceRequest] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<GuidanceRequestTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<GuidanceRequest>(
      where: where(GuidanceRequest.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
