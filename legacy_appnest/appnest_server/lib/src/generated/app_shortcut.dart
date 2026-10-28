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

abstract class AppShortcut
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  AppShortcut._({
    this.id,
    required this.appId,
    required this.actorId,
  });

  factory AppShortcut({
    int? id,
    required int appId,
    required String actorId,
  }) = _AppShortcutImpl;

  factory AppShortcut.fromJson(Map<String, dynamic> jsonSerialization) {
    return AppShortcut(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      actorId: jsonSerialization['actorId'] as String,
    );
  }

  static final t = AppShortcutTable();

  static const db = AppShortcutRepository._();

  @override
  int? id;

  int appId;

  String actorId;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [AppShortcut]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AppShortcut copyWith({
    int? id,
    int? appId,
    String? actorId,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AppShortcut',
      if (id != null) 'id': id,
      'appId': appId,
      'actorId': actorId,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static AppShortcutInclude include() {
    return AppShortcutInclude._();
  }

  static AppShortcutIncludeList includeList({
    _is.WhereExpressionBuilder<AppShortcutTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AppShortcutTable>? orderBy,
    _is.OrderByListBuilder<AppShortcutTable>? orderByList,
    AppShortcutInclude? include,
  }) {
    return AppShortcutIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AppShortcut.t),
      orderByList: orderByList?.call(AppShortcut.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AppShortcutImpl extends AppShortcut {
  _AppShortcutImpl({
    int? id,
    required int appId,
    required String actorId,
  }) : super._(
         id: id,
         appId: appId,
         actorId: actorId,
       );

  /// Returns a shallow copy of this [AppShortcut]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AppShortcut copyWith({
    Object? id = _Undefined,
    int? appId,
    String? actorId,
  }) {
    return AppShortcut(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      actorId: actorId ?? this.actorId,
    );
  }
}

class AppShortcutUpdateTable extends _is.UpdateTable<AppShortcutTable> {
  AppShortcutUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<String, String> actorId(String value) => _is.ColumnValue(
    table.actorId,
    value,
  );
}

class AppShortcutTable extends _is.Table<int?> {
  AppShortcutTable({super.tableRelation}) : super(tableName: 'nest_shortcut') {
    updateTable = AppShortcutUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    actorId = _is.ColumnString(
      'actorId',
      this,
    );
  }

  late final AppShortcutUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnString actorId;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    actorId,
  ];
}

class AppShortcutInclude extends _is.IncludeObject {
  AppShortcutInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => AppShortcut.t;
}

class AppShortcutIncludeList extends _is.IncludeList {
  AppShortcutIncludeList._({
    _is.WhereExpressionBuilder<AppShortcutTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AppShortcut.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => AppShortcut.t;
}

class AppShortcutRepository {
  const AppShortcutRepository._();

  /// Returns a list of [AppShortcut]s matching the given query parameters.
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
  Future<List<AppShortcut>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AppShortcutTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AppShortcutTable>? orderBy,
    _is.OrderByListBuilder<AppShortcutTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AppShortcut>(
      where: where?.call(AppShortcut.t),
      orderBy: orderBy?.call(AppShortcut.t),
      orderByList: orderByList?.call(AppShortcut.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AppShortcut] matching the given query parameters.
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
  Future<AppShortcut?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AppShortcutTable>? where,
    int? offset,
    _is.OrderByBuilder<AppShortcutTable>? orderBy,
    _is.OrderByListBuilder<AppShortcutTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AppShortcut>(
      where: where?.call(AppShortcut.t),
      orderBy: orderBy?.call(AppShortcut.t),
      orderByList: orderByList?.call(AppShortcut.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AppShortcut] by its [id] or null if no such row exists.
  Future<AppShortcut?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AppShortcut>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AppShortcut]s in the list and returns the inserted rows.
  ///
  /// The returned [AppShortcut]s will have their `id` fields set.
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
  Future<List<AppShortcut>> insert(
    _is.DatabaseSession session,
    List<AppShortcut> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<AppShortcut>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [AppShortcut] and returns the inserted row.
  ///
  /// The returned [AppShortcut] will have its `id` field set.
  Future<AppShortcut> insertRow(
    _is.DatabaseSession session,
    AppShortcut row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<AppShortcut>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [AppShortcut]s in the list and returns the resulting rows.
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
  /// The returned [AppShortcut]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AppShortcut>> upsert(
    _is.DatabaseSession session,
    List<AppShortcut> rows, {
    required _is.ColumnSelections<AppShortcutTable> conflictColumns,
    _is.ColumnSelections<AppShortcutTable>? updateColumns,
    _is.WhereExpressionBuilder<AppShortcutTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<AppShortcut>(
      rows,
      conflictColumns: conflictColumns(AppShortcut.t),
      updateColumns: updateColumns?.call(AppShortcut.t),
      updateWhere: updateWhere?.call(AppShortcut.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [AppShortcut] and returns the resulting row.
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
  /// The returned [AppShortcut] will have its `id` field set.
  Future<AppShortcut?> upsertRow(
    _is.DatabaseSession session,
    AppShortcut row, {
    required _is.ColumnSelections<AppShortcutTable> conflictColumns,
    _is.ColumnSelections<AppShortcutTable>? updateColumns,
    _is.WhereExpressionBuilder<AppShortcutTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<AppShortcut>(
      row,
      conflictColumns: conflictColumns(AppShortcut.t),
      updateColumns: updateColumns?.call(AppShortcut.t),
      updateWhere: updateWhere?.call(AppShortcut.t),
      transaction: transaction,
    );
  }

  /// Updates all [AppShortcut]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AppShortcut>> update(
    _is.DatabaseSession session,
    List<AppShortcut> rows, {
    _is.ColumnSelections<AppShortcutTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<AppShortcut>(
      rows,
      columns: columns?.call(AppShortcut.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [AppShortcut]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AppShortcut> updateRow(
    _is.DatabaseSession session,
    AppShortcut row, {
    _is.ColumnSelections<AppShortcutTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<AppShortcut>(
      row,
      columns: columns?.call(AppShortcut.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AppShortcut] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AppShortcut?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<AppShortcutUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<AppShortcut>(
      id,
      columnValues: columnValues(AppShortcut.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AppShortcut]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AppShortcut>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<AppShortcutUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<AppShortcutTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AppShortcutTable>? orderBy,
    _is.OrderByListBuilder<AppShortcutTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<AppShortcut>(
      columnValues: columnValues(AppShortcut.t.updateTable),
      where: where(AppShortcut.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AppShortcut.t),
      orderByList: orderByList?.call(AppShortcut.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [AppShortcut]s in the list and returns the deleted rows.
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
  Future<List<AppShortcut>> delete(
    _is.DatabaseSession session,
    List<AppShortcut> rows, {
    _is.OrderByBuilder<AppShortcutTable>? orderBy,
    _is.OrderByListBuilder<AppShortcutTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<AppShortcut>(
      rows,
      orderBy: orderBy?.call(AppShortcut.t),
      orderByList: orderByList?.call(AppShortcut.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [AppShortcut].
  Future<AppShortcut> deleteRow(
    _is.DatabaseSession session,
    AppShortcut row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AppShortcut>(
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
  Future<List<AppShortcut>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AppShortcutTable> where,
    _is.OrderByBuilder<AppShortcutTable>? orderBy,
    _is.OrderByListBuilder<AppShortcutTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<AppShortcut>(
      where: where(AppShortcut.t),
      orderBy: orderBy?.call(AppShortcut.t),
      orderByList: orderByList?.call(AppShortcut.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AppShortcutTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<AppShortcut>(
      where: where?.call(AppShortcut.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AppShortcut] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AppShortcutTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AppShortcut>(
      where: where(AppShortcut.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
