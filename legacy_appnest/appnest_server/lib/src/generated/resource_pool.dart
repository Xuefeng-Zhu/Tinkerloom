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

abstract class ResourcePool
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  ResourcePool._({
    this.id,
    required this.appId,
    required this.workspaceId,
    required this.recordId,
    required this.behaviorId,
    required this.capacity,
    int? allocated,
  }) : allocated = allocated ?? 0;

  factory ResourcePool({
    int? id,
    required int appId,
    required int workspaceId,
    required int recordId,
    required String behaviorId,
    required int capacity,
    int? allocated,
  }) = _ResourcePoolImpl;

  factory ResourcePool.fromJson(Map<String, dynamic> jsonSerialization) {
    return ResourcePool(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      workspaceId: jsonSerialization['workspaceId'] as int,
      recordId: jsonSerialization['recordId'] as int,
      behaviorId: jsonSerialization['behaviorId'] as String,
      capacity: jsonSerialization['capacity'] as int,
      allocated: jsonSerialization['allocated'] as int?,
    );
  }

  static final t = ResourcePoolTable();

  static const db = ResourcePoolRepository._();

  @override
  int? id;

  int appId;

  int workspaceId;

  int recordId;

  String behaviorId;

  int capacity;

  int allocated;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [ResourcePool]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  ResourcePool copyWith({
    int? id,
    int? appId,
    int? workspaceId,
    int? recordId,
    String? behaviorId,
    int? capacity,
    int? allocated,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ResourcePool',
      if (id != null) 'id': id,
      'appId': appId,
      'workspaceId': workspaceId,
      'recordId': recordId,
      'behaviorId': behaviorId,
      'capacity': capacity,
      'allocated': allocated,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static ResourcePoolInclude include() {
    return ResourcePoolInclude._();
  }

  static ResourcePoolIncludeList includeList({
    _is.WhereExpressionBuilder<ResourcePoolTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<ResourcePoolTable>? orderBy,
    _is.OrderByListBuilder<ResourcePoolTable>? orderByList,
    ResourcePoolInclude? include,
  }) {
    return ResourcePoolIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(ResourcePool.t),
      orderByList: orderByList?.call(ResourcePool.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ResourcePoolImpl extends ResourcePool {
  _ResourcePoolImpl({
    int? id,
    required int appId,
    required int workspaceId,
    required int recordId,
    required String behaviorId,
    required int capacity,
    int? allocated,
  }) : super._(
         id: id,
         appId: appId,
         workspaceId: workspaceId,
         recordId: recordId,
         behaviorId: behaviorId,
         capacity: capacity,
         allocated: allocated,
       );

  /// Returns a shallow copy of this [ResourcePool]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  ResourcePool copyWith({
    Object? id = _Undefined,
    int? appId,
    int? workspaceId,
    int? recordId,
    String? behaviorId,
    int? capacity,
    int? allocated,
  }) {
    return ResourcePool(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      workspaceId: workspaceId ?? this.workspaceId,
      recordId: recordId ?? this.recordId,
      behaviorId: behaviorId ?? this.behaviorId,
      capacity: capacity ?? this.capacity,
      allocated: allocated ?? this.allocated,
    );
  }
}

class ResourcePoolUpdateTable extends _is.UpdateTable<ResourcePoolTable> {
  ResourcePoolUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<int, int> recordId(int value) => _is.ColumnValue(
    table.recordId,
    value,
  );

  _is.ColumnValue<String, String> behaviorId(String value) => _is.ColumnValue(
    table.behaviorId,
    value,
  );

  _is.ColumnValue<int, int> capacity(int value) => _is.ColumnValue(
    table.capacity,
    value,
  );

  _is.ColumnValue<int, int> allocated(int value) => _is.ColumnValue(
    table.allocated,
    value,
  );
}

class ResourcePoolTable extends _is.Table<int?> {
  ResourcePoolTable({super.tableRelation}) : super(tableName: 'nest_pool') {
    updateTable = ResourcePoolUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    recordId = _is.ColumnInt(
      'recordId',
      this,
    );
    behaviorId = _is.ColumnString(
      'behaviorId',
      this,
    );
    capacity = _is.ColumnInt(
      'capacity',
      this,
    );
    allocated = _is.ColumnInt(
      'allocated',
      this,
      hasDefault: true,
    );
  }

  late final ResourcePoolUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnInt workspaceId;

  late final _is.ColumnInt recordId;

  late final _is.ColumnString behaviorId;

  late final _is.ColumnInt capacity;

  late final _is.ColumnInt allocated;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    workspaceId,
    recordId,
    behaviorId,
    capacity,
    allocated,
  ];
}

class ResourcePoolInclude extends _is.IncludeObject {
  ResourcePoolInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => ResourcePool.t;
}

class ResourcePoolIncludeList extends _is.IncludeList {
  ResourcePoolIncludeList._({
    _is.WhereExpressionBuilder<ResourcePoolTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(ResourcePool.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => ResourcePool.t;
}

class ResourcePoolRepository {
  const ResourcePoolRepository._();

  /// Returns a list of [ResourcePool]s matching the given query parameters.
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
  Future<List<ResourcePool>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<ResourcePoolTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<ResourcePoolTable>? orderBy,
    _is.OrderByListBuilder<ResourcePoolTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<ResourcePool>(
      where: where?.call(ResourcePool.t),
      orderBy: orderBy?.call(ResourcePool.t),
      orderByList: orderByList?.call(ResourcePool.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [ResourcePool] matching the given query parameters.
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
  Future<ResourcePool?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<ResourcePoolTable>? where,
    int? offset,
    _is.OrderByBuilder<ResourcePoolTable>? orderBy,
    _is.OrderByListBuilder<ResourcePoolTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<ResourcePool>(
      where: where?.call(ResourcePool.t),
      orderBy: orderBy?.call(ResourcePool.t),
      orderByList: orderByList?.call(ResourcePool.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [ResourcePool] by its [id] or null if no such row exists.
  Future<ResourcePool?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<ResourcePool>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [ResourcePool]s in the list and returns the inserted rows.
  ///
  /// The returned [ResourcePool]s will have their `id` fields set.
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
  Future<List<ResourcePool>> insert(
    _is.DatabaseSession session,
    List<ResourcePool> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<ResourcePool>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [ResourcePool] and returns the inserted row.
  ///
  /// The returned [ResourcePool] will have its `id` field set.
  Future<ResourcePool> insertRow(
    _is.DatabaseSession session,
    ResourcePool row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<ResourcePool>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [ResourcePool]s in the list and returns the resulting rows.
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
  /// The returned [ResourcePool]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ResourcePool>> upsert(
    _is.DatabaseSession session,
    List<ResourcePool> rows, {
    required _is.ColumnSelections<ResourcePoolTable> conflictColumns,
    _is.ColumnSelections<ResourcePoolTable>? updateColumns,
    _is.WhereExpressionBuilder<ResourcePoolTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<ResourcePool>(
      rows,
      conflictColumns: conflictColumns(ResourcePool.t),
      updateColumns: updateColumns?.call(ResourcePool.t),
      updateWhere: updateWhere?.call(ResourcePool.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [ResourcePool] and returns the resulting row.
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
  /// The returned [ResourcePool] will have its `id` field set.
  Future<ResourcePool?> upsertRow(
    _is.DatabaseSession session,
    ResourcePool row, {
    required _is.ColumnSelections<ResourcePoolTable> conflictColumns,
    _is.ColumnSelections<ResourcePoolTable>? updateColumns,
    _is.WhereExpressionBuilder<ResourcePoolTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<ResourcePool>(
      row,
      conflictColumns: conflictColumns(ResourcePool.t),
      updateColumns: updateColumns?.call(ResourcePool.t),
      updateWhere: updateWhere?.call(ResourcePool.t),
      transaction: transaction,
    );
  }

  /// Updates all [ResourcePool]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ResourcePool>> update(
    _is.DatabaseSession session,
    List<ResourcePool> rows, {
    _is.ColumnSelections<ResourcePoolTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<ResourcePool>(
      rows,
      columns: columns?.call(ResourcePool.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [ResourcePool]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<ResourcePool> updateRow(
    _is.DatabaseSession session,
    ResourcePool row, {
    _is.ColumnSelections<ResourcePoolTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<ResourcePool>(
      row,
      columns: columns?.call(ResourcePool.t),
      transaction: transaction,
    );
  }

  /// Updates a single [ResourcePool] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<ResourcePool?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<ResourcePoolUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<ResourcePool>(
      id,
      columnValues: columnValues(ResourcePool.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [ResourcePool]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<ResourcePool>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<ResourcePoolUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<ResourcePoolTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<ResourcePoolTable>? orderBy,
    _is.OrderByListBuilder<ResourcePoolTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<ResourcePool>(
      columnValues: columnValues(ResourcePool.t.updateTable),
      where: where(ResourcePool.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(ResourcePool.t),
      orderByList: orderByList?.call(ResourcePool.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [ResourcePool]s in the list and returns the deleted rows.
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
  Future<List<ResourcePool>> delete(
    _is.DatabaseSession session,
    List<ResourcePool> rows, {
    _is.OrderByBuilder<ResourcePoolTable>? orderBy,
    _is.OrderByListBuilder<ResourcePoolTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<ResourcePool>(
      rows,
      orderBy: orderBy?.call(ResourcePool.t),
      orderByList: orderByList?.call(ResourcePool.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [ResourcePool].
  Future<ResourcePool> deleteRow(
    _is.DatabaseSession session,
    ResourcePool row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<ResourcePool>(
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
  Future<List<ResourcePool>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<ResourcePoolTable> where,
    _is.OrderByBuilder<ResourcePoolTable>? orderBy,
    _is.OrderByListBuilder<ResourcePoolTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<ResourcePool>(
      where: where(ResourcePool.t),
      orderBy: orderBy?.call(ResourcePool.t),
      orderByList: orderByList?.call(ResourcePool.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<ResourcePoolTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<ResourcePool>(
      where: where?.call(ResourcePool.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [ResourcePool] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<ResourcePoolTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<ResourcePool>(
      where: where(ResourcePool.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
