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

abstract class Workspace
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  Workspace._({
    this.id,
    required this.name,
    required this.ownerId,
    bool? personal,
    required this.createdAt,
  }) : personal = personal ?? false;

  factory Workspace({
    int? id,
    required String name,
    required String ownerId,
    bool? personal,
    required DateTime createdAt,
  }) = _WorkspaceImpl;

  factory Workspace.fromJson(Map<String, dynamic> jsonSerialization) {
    return Workspace(
      id: jsonSerialization['id'] as int?,
      name: jsonSerialization['name'] as String,
      ownerId: jsonSerialization['ownerId'] as String,
      personal: jsonSerialization['personal'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['personal']),
      createdAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
    );
  }

  static final t = WorkspaceTable();

  static const db = WorkspaceRepository._();

  @override
  int? id;

  String name;

  String ownerId;

  bool personal;

  DateTime createdAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [Workspace]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  Workspace copyWith({
    int? id,
    String? name,
    String? ownerId,
    bool? personal,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Workspace',
      if (id != null) 'id': id,
      'name': name,
      'ownerId': ownerId,
      'personal': personal,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static WorkspaceInclude include() {
    return WorkspaceInclude._();
  }

  static WorkspaceIncludeList includeList({
    _is.WhereExpressionBuilder<WorkspaceTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<WorkspaceTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceTable>? orderByList,
    WorkspaceInclude? include,
  }) {
    return WorkspaceIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Workspace.t),
      orderByList: orderByList?.call(Workspace.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _WorkspaceImpl extends Workspace {
  _WorkspaceImpl({
    int? id,
    required String name,
    required String ownerId,
    bool? personal,
    required DateTime createdAt,
  }) : super._(
         id: id,
         name: name,
         ownerId: ownerId,
         personal: personal,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [Workspace]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  Workspace copyWith({
    Object? id = _Undefined,
    String? name,
    String? ownerId,
    bool? personal,
    DateTime? createdAt,
  }) {
    return Workspace(
      id: id is int? ? id : this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      personal: personal ?? this.personal,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class WorkspaceUpdateTable extends _is.UpdateTable<WorkspaceTable> {
  WorkspaceUpdateTable(super.table);

  _is.ColumnValue<String, String> name(String value) => _is.ColumnValue(
    table.name,
    value,
  );

  _is.ColumnValue<String, String> ownerId(String value) => _is.ColumnValue(
    table.ownerId,
    value,
  );

  _is.ColumnValue<bool, bool> personal(bool value) => _is.ColumnValue(
    table.personal,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );
}

class WorkspaceTable extends _is.Table<int?> {
  WorkspaceTable({super.tableRelation}) : super(tableName: 'nest_workspace') {
    updateTable = WorkspaceUpdateTable(this);
    name = _is.ColumnString(
      'name',
      this,
    );
    ownerId = _is.ColumnString(
      'ownerId',
      this,
    );
    personal = _is.ColumnBool(
      'personal',
      this,
      hasDefault: true,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
    );
  }

  late final WorkspaceUpdateTable updateTable;

  late final _is.ColumnString name;

  late final _is.ColumnString ownerId;

  late final _is.ColumnBool personal;

  late final _is.ColumnDateTime createdAt;

  @override
  List<_is.Column> get columns => [
    id,
    name,
    ownerId,
    personal,
    createdAt,
  ];
}

class WorkspaceInclude extends _is.IncludeObject {
  WorkspaceInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => Workspace.t;
}

class WorkspaceIncludeList extends _is.IncludeList {
  WorkspaceIncludeList._({
    _is.WhereExpressionBuilder<WorkspaceTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(Workspace.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => Workspace.t;
}

class WorkspaceRepository {
  const WorkspaceRepository._();

  /// Returns a list of [Workspace]s matching the given query parameters.
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
  Future<List<Workspace>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<WorkspaceTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<WorkspaceTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<Workspace>(
      where: where?.call(Workspace.t),
      orderBy: orderBy?.call(Workspace.t),
      orderByList: orderByList?.call(Workspace.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [Workspace] matching the given query parameters.
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
  Future<Workspace?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<WorkspaceTable>? where,
    int? offset,
    _is.OrderByBuilder<WorkspaceTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<Workspace>(
      where: where?.call(Workspace.t),
      orderBy: orderBy?.call(Workspace.t),
      orderByList: orderByList?.call(Workspace.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [Workspace] by its [id] or null if no such row exists.
  Future<Workspace?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<Workspace>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [Workspace]s in the list and returns the inserted rows.
  ///
  /// The returned [Workspace]s will have their `id` fields set.
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
  Future<List<Workspace>> insert(
    _is.DatabaseSession session,
    List<Workspace> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<Workspace>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [Workspace] and returns the inserted row.
  ///
  /// The returned [Workspace] will have its `id` field set.
  Future<Workspace> insertRow(
    _is.DatabaseSession session,
    Workspace row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<Workspace>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [Workspace]s in the list and returns the resulting rows.
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
  /// The returned [Workspace]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Workspace>> upsert(
    _is.DatabaseSession session,
    List<Workspace> rows, {
    required _is.ColumnSelections<WorkspaceTable> conflictColumns,
    _is.ColumnSelections<WorkspaceTable>? updateColumns,
    _is.WhereExpressionBuilder<WorkspaceTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<Workspace>(
      rows,
      conflictColumns: conflictColumns(Workspace.t),
      updateColumns: updateColumns?.call(Workspace.t),
      updateWhere: updateWhere?.call(Workspace.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [Workspace] and returns the resulting row.
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
  /// The returned [Workspace] will have its `id` field set.
  Future<Workspace?> upsertRow(
    _is.DatabaseSession session,
    Workspace row, {
    required _is.ColumnSelections<WorkspaceTable> conflictColumns,
    _is.ColumnSelections<WorkspaceTable>? updateColumns,
    _is.WhereExpressionBuilder<WorkspaceTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<Workspace>(
      row,
      conflictColumns: conflictColumns(Workspace.t),
      updateColumns: updateColumns?.call(Workspace.t),
      updateWhere: updateWhere?.call(Workspace.t),
      transaction: transaction,
    );
  }

  /// Updates all [Workspace]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Workspace>> update(
    _is.DatabaseSession session,
    List<Workspace> rows, {
    _is.ColumnSelections<WorkspaceTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<Workspace>(
      rows,
      columns: columns?.call(Workspace.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [Workspace]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<Workspace> updateRow(
    _is.DatabaseSession session,
    Workspace row, {
    _is.ColumnSelections<WorkspaceTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<Workspace>(
      row,
      columns: columns?.call(Workspace.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Workspace] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<Workspace?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<WorkspaceUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<Workspace>(
      id,
      columnValues: columnValues(Workspace.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [Workspace]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Workspace>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<WorkspaceUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<WorkspaceTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<WorkspaceTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<Workspace>(
      columnValues: columnValues(Workspace.t.updateTable),
      where: where(Workspace.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Workspace.t),
      orderByList: orderByList?.call(Workspace.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [Workspace]s in the list and returns the deleted rows.
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
  Future<List<Workspace>> delete(
    _is.DatabaseSession session,
    List<Workspace> rows, {
    _is.OrderByBuilder<WorkspaceTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<Workspace>(
      rows,
      orderBy: orderBy?.call(Workspace.t),
      orderByList: orderByList?.call(Workspace.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [Workspace].
  Future<Workspace> deleteRow(
    _is.DatabaseSession session,
    Workspace row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<Workspace>(
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
  Future<List<Workspace>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<WorkspaceTable> where,
    _is.OrderByBuilder<WorkspaceTable>? orderBy,
    _is.OrderByListBuilder<WorkspaceTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<Workspace>(
      where: where(Workspace.t),
      orderBy: orderBy?.call(Workspace.t),
      orderByList: orderByList?.call(Workspace.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<WorkspaceTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<Workspace>(
      where: where?.call(Workspace.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [Workspace] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<WorkspaceTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<Workspace>(
      where: where(Workspace.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
