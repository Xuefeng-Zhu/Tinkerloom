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

abstract class MiniApp
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  MiniApp._({
    this.id,
    required this.workspaceId,
    required this.ownerId,
    required this.name,
    this.activeVersionId,
    bool? archived,
    int? controlRevision,
    required this.createdAt,
  }) : archived = archived ?? false,
       controlRevision = controlRevision ?? 0;

  factory MiniApp({
    int? id,
    required int workspaceId,
    required String ownerId,
    required String name,
    int? activeVersionId,
    bool? archived,
    int? controlRevision,
    required DateTime createdAt,
  }) = _MiniAppImpl;

  factory MiniApp.fromJson(Map<String, dynamic> jsonSerialization) {
    return MiniApp(
      id: jsonSerialization['id'] as int?,
      workspaceId: jsonSerialization['workspaceId'] as int,
      ownerId: jsonSerialization['ownerId'] as String,
      name: jsonSerialization['name'] as String,
      activeVersionId: jsonSerialization['activeVersionId'] as int?,
      archived: jsonSerialization['archived'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['archived']),
      controlRevision: jsonSerialization['controlRevision'] as int?,
      createdAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
    );
  }

  static final t = MiniAppTable();

  static const db = MiniAppRepository._();

  @override
  int? id;

  int workspaceId;

  String ownerId;

  String name;

  int? activeVersionId;

  bool archived;

  int controlRevision;

  DateTime createdAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [MiniApp]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  MiniApp copyWith({
    int? id,
    int? workspaceId,
    String? ownerId,
    String? name,
    int? activeVersionId,
    bool? archived,
    int? controlRevision,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MiniApp',
      if (id != null) 'id': id,
      'workspaceId': workspaceId,
      'ownerId': ownerId,
      'name': name,
      if (activeVersionId != null) 'activeVersionId': activeVersionId,
      'archived': archived,
      'controlRevision': controlRevision,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static MiniAppInclude include() {
    return MiniAppInclude._();
  }

  static MiniAppIncludeList includeList({
    _is.WhereExpressionBuilder<MiniAppTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MiniAppTable>? orderBy,
    _is.OrderByListBuilder<MiniAppTable>? orderByList,
    MiniAppInclude? include,
  }) {
    return MiniAppIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(MiniApp.t),
      orderByList: orderByList?.call(MiniApp.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _MiniAppImpl extends MiniApp {
  _MiniAppImpl({
    int? id,
    required int workspaceId,
    required String ownerId,
    required String name,
    int? activeVersionId,
    bool? archived,
    int? controlRevision,
    required DateTime createdAt,
  }) : super._(
         id: id,
         workspaceId: workspaceId,
         ownerId: ownerId,
         name: name,
         activeVersionId: activeVersionId,
         archived: archived,
         controlRevision: controlRevision,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [MiniApp]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  MiniApp copyWith({
    Object? id = _Undefined,
    int? workspaceId,
    String? ownerId,
    String? name,
    Object? activeVersionId = _Undefined,
    bool? archived,
    int? controlRevision,
    DateTime? createdAt,
  }) {
    return MiniApp(
      id: id is int? ? id : this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      activeVersionId: activeVersionId is int?
          ? activeVersionId
          : this.activeVersionId,
      archived: archived ?? this.archived,
      controlRevision: controlRevision ?? this.controlRevision,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class MiniAppUpdateTable extends _is.UpdateTable<MiniAppTable> {
  MiniAppUpdateTable(super.table);

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<String, String> ownerId(String value) => _is.ColumnValue(
    table.ownerId,
    value,
  );

  _is.ColumnValue<String, String> name(String value) => _is.ColumnValue(
    table.name,
    value,
  );

  _is.ColumnValue<int, int> activeVersionId(int? value) => _is.ColumnValue(
    table.activeVersionId,
    value,
  );

  _is.ColumnValue<bool, bool> archived(bool value) => _is.ColumnValue(
    table.archived,
    value,
  );

  _is.ColumnValue<int, int> controlRevision(int value) => _is.ColumnValue(
    table.controlRevision,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );
}

class MiniAppTable extends _is.Table<int?> {
  MiniAppTable({super.tableRelation}) : super(tableName: 'nest_app') {
    updateTable = MiniAppUpdateTable(this);
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    ownerId = _is.ColumnString(
      'ownerId',
      this,
    );
    name = _is.ColumnString(
      'name',
      this,
    );
    activeVersionId = _is.ColumnInt(
      'activeVersionId',
      this,
    );
    archived = _is.ColumnBool(
      'archived',
      this,
      hasDefault: true,
    );
    controlRevision = _is.ColumnInt(
      'controlRevision',
      this,
      hasDefault: true,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
    );
  }

  late final MiniAppUpdateTable updateTable;

  late final _is.ColumnInt workspaceId;

  late final _is.ColumnString ownerId;

  late final _is.ColumnString name;

  late final _is.ColumnInt activeVersionId;

  late final _is.ColumnBool archived;

  late final _is.ColumnInt controlRevision;

  late final _is.ColumnDateTime createdAt;

  @override
  List<_is.Column> get columns => [
    id,
    workspaceId,
    ownerId,
    name,
    activeVersionId,
    archived,
    controlRevision,
    createdAt,
  ];
}

class MiniAppInclude extends _is.IncludeObject {
  MiniAppInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => MiniApp.t;
}

class MiniAppIncludeList extends _is.IncludeList {
  MiniAppIncludeList._({
    _is.WhereExpressionBuilder<MiniAppTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(MiniApp.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => MiniApp.t;
}

class MiniAppRepository {
  const MiniAppRepository._();

  /// Returns a list of [MiniApp]s matching the given query parameters.
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
  Future<List<MiniApp>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MiniAppTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MiniAppTable>? orderBy,
    _is.OrderByListBuilder<MiniAppTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<MiniApp>(
      where: where?.call(MiniApp.t),
      orderBy: orderBy?.call(MiniApp.t),
      orderByList: orderByList?.call(MiniApp.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [MiniApp] matching the given query parameters.
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
  Future<MiniApp?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MiniAppTable>? where,
    int? offset,
    _is.OrderByBuilder<MiniAppTable>? orderBy,
    _is.OrderByListBuilder<MiniAppTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<MiniApp>(
      where: where?.call(MiniApp.t),
      orderBy: orderBy?.call(MiniApp.t),
      orderByList: orderByList?.call(MiniApp.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [MiniApp] by its [id] or null if no such row exists.
  Future<MiniApp?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<MiniApp>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [MiniApp]s in the list and returns the inserted rows.
  ///
  /// The returned [MiniApp]s will have their `id` fields set.
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
  Future<List<MiniApp>> insert(
    _is.DatabaseSession session,
    List<MiniApp> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<MiniApp>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [MiniApp] and returns the inserted row.
  ///
  /// The returned [MiniApp] will have its `id` field set.
  Future<MiniApp> insertRow(
    _is.DatabaseSession session,
    MiniApp row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<MiniApp>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [MiniApp]s in the list and returns the resulting rows.
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
  /// The returned [MiniApp]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<MiniApp>> upsert(
    _is.DatabaseSession session,
    List<MiniApp> rows, {
    required _is.ColumnSelections<MiniAppTable> conflictColumns,
    _is.ColumnSelections<MiniAppTable>? updateColumns,
    _is.WhereExpressionBuilder<MiniAppTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<MiniApp>(
      rows,
      conflictColumns: conflictColumns(MiniApp.t),
      updateColumns: updateColumns?.call(MiniApp.t),
      updateWhere: updateWhere?.call(MiniApp.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [MiniApp] and returns the resulting row.
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
  /// The returned [MiniApp] will have its `id` field set.
  Future<MiniApp?> upsertRow(
    _is.DatabaseSession session,
    MiniApp row, {
    required _is.ColumnSelections<MiniAppTable> conflictColumns,
    _is.ColumnSelections<MiniAppTable>? updateColumns,
    _is.WhereExpressionBuilder<MiniAppTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<MiniApp>(
      row,
      conflictColumns: conflictColumns(MiniApp.t),
      updateColumns: updateColumns?.call(MiniApp.t),
      updateWhere: updateWhere?.call(MiniApp.t),
      transaction: transaction,
    );
  }

  /// Updates all [MiniApp]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<MiniApp>> update(
    _is.DatabaseSession session,
    List<MiniApp> rows, {
    _is.ColumnSelections<MiniAppTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<MiniApp>(
      rows,
      columns: columns?.call(MiniApp.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [MiniApp]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<MiniApp> updateRow(
    _is.DatabaseSession session,
    MiniApp row, {
    _is.ColumnSelections<MiniAppTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<MiniApp>(
      row,
      columns: columns?.call(MiniApp.t),
      transaction: transaction,
    );
  }

  /// Updates a single [MiniApp] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<MiniApp?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<MiniAppUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<MiniApp>(
      id,
      columnValues: columnValues(MiniApp.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [MiniApp]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<MiniApp>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<MiniAppUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<MiniAppTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MiniAppTable>? orderBy,
    _is.OrderByListBuilder<MiniAppTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<MiniApp>(
      columnValues: columnValues(MiniApp.t.updateTable),
      where: where(MiniApp.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(MiniApp.t),
      orderByList: orderByList?.call(MiniApp.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [MiniApp]s in the list and returns the deleted rows.
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
  Future<List<MiniApp>> delete(
    _is.DatabaseSession session,
    List<MiniApp> rows, {
    _is.OrderByBuilder<MiniAppTable>? orderBy,
    _is.OrderByListBuilder<MiniAppTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<MiniApp>(
      rows,
      orderBy: orderBy?.call(MiniApp.t),
      orderByList: orderByList?.call(MiniApp.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [MiniApp].
  Future<MiniApp> deleteRow(
    _is.DatabaseSession session,
    MiniApp row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<MiniApp>(
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
  Future<List<MiniApp>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<MiniAppTable> where,
    _is.OrderByBuilder<MiniAppTable>? orderBy,
    _is.OrderByListBuilder<MiniAppTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<MiniApp>(
      where: where(MiniApp.t),
      orderBy: orderBy?.call(MiniApp.t),
      orderByList: orderByList?.call(MiniApp.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MiniAppTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<MiniApp>(
      where: where?.call(MiniApp.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [MiniApp] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<MiniAppTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<MiniApp>(
      where: where(MiniApp.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
