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

abstract class MiniAppGrant
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  MiniAppGrant._({
    this.id,
    required this.appId,
    required this.workspaceId,
    required this.actorId,
    required this.role,
    bool? revoked,
  }) : revoked = revoked ?? false;

  factory MiniAppGrant({
    int? id,
    required int appId,
    required int workspaceId,
    required String actorId,
    required String role,
    bool? revoked,
  }) = _MiniAppGrantImpl;

  factory MiniAppGrant.fromJson(Map<String, dynamic> jsonSerialization) {
    return MiniAppGrant(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      workspaceId: jsonSerialization['workspaceId'] as int,
      actorId: jsonSerialization['actorId'] as String,
      role: jsonSerialization['role'] as String,
      revoked: jsonSerialization['revoked'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['revoked']),
    );
  }

  static final t = MiniAppGrantTable();

  static const db = MiniAppGrantRepository._();

  @override
  int? id;

  int appId;

  int workspaceId;

  String actorId;

  String role;

  bool revoked;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [MiniAppGrant]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  MiniAppGrant copyWith({
    int? id,
    int? appId,
    int? workspaceId,
    String? actorId,
    String? role,
    bool? revoked,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MiniAppGrant',
      if (id != null) 'id': id,
      'appId': appId,
      'workspaceId': workspaceId,
      'actorId': actorId,
      'role': role,
      'revoked': revoked,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static MiniAppGrantInclude include() {
    return MiniAppGrantInclude._();
  }

  static MiniAppGrantIncludeList includeList({
    _is.WhereExpressionBuilder<MiniAppGrantTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MiniAppGrantTable>? orderBy,
    _is.OrderByListBuilder<MiniAppGrantTable>? orderByList,
    MiniAppGrantInclude? include,
  }) {
    return MiniAppGrantIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(MiniAppGrant.t),
      orderByList: orderByList?.call(MiniAppGrant.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _MiniAppGrantImpl extends MiniAppGrant {
  _MiniAppGrantImpl({
    int? id,
    required int appId,
    required int workspaceId,
    required String actorId,
    required String role,
    bool? revoked,
  }) : super._(
         id: id,
         appId: appId,
         workspaceId: workspaceId,
         actorId: actorId,
         role: role,
         revoked: revoked,
       );

  /// Returns a shallow copy of this [MiniAppGrant]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  MiniAppGrant copyWith({
    Object? id = _Undefined,
    int? appId,
    int? workspaceId,
    String? actorId,
    String? role,
    bool? revoked,
  }) {
    return MiniAppGrant(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      workspaceId: workspaceId ?? this.workspaceId,
      actorId: actorId ?? this.actorId,
      role: role ?? this.role,
      revoked: revoked ?? this.revoked,
    );
  }
}

class MiniAppGrantUpdateTable extends _is.UpdateTable<MiniAppGrantTable> {
  MiniAppGrantUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<String, String> actorId(String value) => _is.ColumnValue(
    table.actorId,
    value,
  );

  _is.ColumnValue<String, String> role(String value) => _is.ColumnValue(
    table.role,
    value,
  );

  _is.ColumnValue<bool, bool> revoked(bool value) => _is.ColumnValue(
    table.revoked,
    value,
  );
}

class MiniAppGrantTable extends _is.Table<int?> {
  MiniAppGrantTable({super.tableRelation}) : super(tableName: 'nest_grant') {
    updateTable = MiniAppGrantUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    actorId = _is.ColumnString(
      'actorId',
      this,
    );
    role = _is.ColumnString(
      'role',
      this,
    );
    revoked = _is.ColumnBool(
      'revoked',
      this,
      hasDefault: true,
    );
  }

  late final MiniAppGrantUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnInt workspaceId;

  late final _is.ColumnString actorId;

  late final _is.ColumnString role;

  late final _is.ColumnBool revoked;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    workspaceId,
    actorId,
    role,
    revoked,
  ];
}

class MiniAppGrantInclude extends _is.IncludeObject {
  MiniAppGrantInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => MiniAppGrant.t;
}

class MiniAppGrantIncludeList extends _is.IncludeList {
  MiniAppGrantIncludeList._({
    _is.WhereExpressionBuilder<MiniAppGrantTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(MiniAppGrant.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => MiniAppGrant.t;
}

class MiniAppGrantRepository {
  const MiniAppGrantRepository._();

  /// Returns a list of [MiniAppGrant]s matching the given query parameters.
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
  Future<List<MiniAppGrant>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MiniAppGrantTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MiniAppGrantTable>? orderBy,
    _is.OrderByListBuilder<MiniAppGrantTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<MiniAppGrant>(
      where: where?.call(MiniAppGrant.t),
      orderBy: orderBy?.call(MiniAppGrant.t),
      orderByList: orderByList?.call(MiniAppGrant.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [MiniAppGrant] matching the given query parameters.
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
  Future<MiniAppGrant?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MiniAppGrantTable>? where,
    int? offset,
    _is.OrderByBuilder<MiniAppGrantTable>? orderBy,
    _is.OrderByListBuilder<MiniAppGrantTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<MiniAppGrant>(
      where: where?.call(MiniAppGrant.t),
      orderBy: orderBy?.call(MiniAppGrant.t),
      orderByList: orderByList?.call(MiniAppGrant.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [MiniAppGrant] by its [id] or null if no such row exists.
  Future<MiniAppGrant?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<MiniAppGrant>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [MiniAppGrant]s in the list and returns the inserted rows.
  ///
  /// The returned [MiniAppGrant]s will have their `id` fields set.
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
  Future<List<MiniAppGrant>> insert(
    _is.DatabaseSession session,
    List<MiniAppGrant> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<MiniAppGrant>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [MiniAppGrant] and returns the inserted row.
  ///
  /// The returned [MiniAppGrant] will have its `id` field set.
  Future<MiniAppGrant> insertRow(
    _is.DatabaseSession session,
    MiniAppGrant row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<MiniAppGrant>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [MiniAppGrant]s in the list and returns the resulting rows.
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
  /// The returned [MiniAppGrant]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<MiniAppGrant>> upsert(
    _is.DatabaseSession session,
    List<MiniAppGrant> rows, {
    required _is.ColumnSelections<MiniAppGrantTable> conflictColumns,
    _is.ColumnSelections<MiniAppGrantTable>? updateColumns,
    _is.WhereExpressionBuilder<MiniAppGrantTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<MiniAppGrant>(
      rows,
      conflictColumns: conflictColumns(MiniAppGrant.t),
      updateColumns: updateColumns?.call(MiniAppGrant.t),
      updateWhere: updateWhere?.call(MiniAppGrant.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [MiniAppGrant] and returns the resulting row.
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
  /// The returned [MiniAppGrant] will have its `id` field set.
  Future<MiniAppGrant?> upsertRow(
    _is.DatabaseSession session,
    MiniAppGrant row, {
    required _is.ColumnSelections<MiniAppGrantTable> conflictColumns,
    _is.ColumnSelections<MiniAppGrantTable>? updateColumns,
    _is.WhereExpressionBuilder<MiniAppGrantTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<MiniAppGrant>(
      row,
      conflictColumns: conflictColumns(MiniAppGrant.t),
      updateColumns: updateColumns?.call(MiniAppGrant.t),
      updateWhere: updateWhere?.call(MiniAppGrant.t),
      transaction: transaction,
    );
  }

  /// Updates all [MiniAppGrant]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<MiniAppGrant>> update(
    _is.DatabaseSession session,
    List<MiniAppGrant> rows, {
    _is.ColumnSelections<MiniAppGrantTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<MiniAppGrant>(
      rows,
      columns: columns?.call(MiniAppGrant.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [MiniAppGrant]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<MiniAppGrant> updateRow(
    _is.DatabaseSession session,
    MiniAppGrant row, {
    _is.ColumnSelections<MiniAppGrantTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<MiniAppGrant>(
      row,
      columns: columns?.call(MiniAppGrant.t),
      transaction: transaction,
    );
  }

  /// Updates a single [MiniAppGrant] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<MiniAppGrant?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<MiniAppGrantUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<MiniAppGrant>(
      id,
      columnValues: columnValues(MiniAppGrant.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [MiniAppGrant]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<MiniAppGrant>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<MiniAppGrantUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<MiniAppGrantTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MiniAppGrantTable>? orderBy,
    _is.OrderByListBuilder<MiniAppGrantTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<MiniAppGrant>(
      columnValues: columnValues(MiniAppGrant.t.updateTable),
      where: where(MiniAppGrant.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(MiniAppGrant.t),
      orderByList: orderByList?.call(MiniAppGrant.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [MiniAppGrant]s in the list and returns the deleted rows.
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
  Future<List<MiniAppGrant>> delete(
    _is.DatabaseSession session,
    List<MiniAppGrant> rows, {
    _is.OrderByBuilder<MiniAppGrantTable>? orderBy,
    _is.OrderByListBuilder<MiniAppGrantTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<MiniAppGrant>(
      rows,
      orderBy: orderBy?.call(MiniAppGrant.t),
      orderByList: orderByList?.call(MiniAppGrant.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [MiniAppGrant].
  Future<MiniAppGrant> deleteRow(
    _is.DatabaseSession session,
    MiniAppGrant row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<MiniAppGrant>(
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
  Future<List<MiniAppGrant>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<MiniAppGrantTable> where,
    _is.OrderByBuilder<MiniAppGrantTable>? orderBy,
    _is.OrderByListBuilder<MiniAppGrantTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<MiniAppGrant>(
      where: where(MiniAppGrant.t),
      orderBy: orderBy?.call(MiniAppGrant.t),
      orderByList: orderByList?.call(MiniAppGrant.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MiniAppGrantTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<MiniAppGrant>(
      where: where?.call(MiniAppGrant.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [MiniAppGrant] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<MiniAppGrantTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<MiniAppGrant>(
      where: where(MiniAppGrant.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
