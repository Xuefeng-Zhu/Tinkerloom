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

abstract class AppVersion
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  AppVersion._({
    this.id,
    required this.appId,
    required this.workspaceId,
    required this.number,
    required this.specJson,
    required this.candidateHash,
    required this.publisherId,
    required this.createdAt,
  });

  factory AppVersion({
    int? id,
    required int appId,
    required int workspaceId,
    required int number,
    required String specJson,
    required String candidateHash,
    required String publisherId,
    required DateTime createdAt,
  }) = _AppVersionImpl;

  factory AppVersion.fromJson(Map<String, dynamic> jsonSerialization) {
    return AppVersion(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      workspaceId: jsonSerialization['workspaceId'] as int,
      number: jsonSerialization['number'] as int,
      specJson: jsonSerialization['specJson'] as String,
      candidateHash: jsonSerialization['candidateHash'] as String,
      publisherId: jsonSerialization['publisherId'] as String,
      createdAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
    );
  }

  static final t = AppVersionTable();

  static const db = AppVersionRepository._();

  @override
  int? id;

  int appId;

  int workspaceId;

  int number;

  String specJson;

  String candidateHash;

  String publisherId;

  DateTime createdAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [AppVersion]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AppVersion copyWith({
    int? id,
    int? appId,
    int? workspaceId,
    int? number,
    String? specJson,
    String? candidateHash,
    String? publisherId,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AppVersion',
      if (id != null) 'id': id,
      'appId': appId,
      'workspaceId': workspaceId,
      'number': number,
      'specJson': specJson,
      'candidateHash': candidateHash,
      'publisherId': publisherId,
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static AppVersionInclude include() {
    return AppVersionInclude._();
  }

  static AppVersionIncludeList includeList({
    _is.WhereExpressionBuilder<AppVersionTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AppVersionTable>? orderBy,
    _is.OrderByListBuilder<AppVersionTable>? orderByList,
    AppVersionInclude? include,
  }) {
    return AppVersionIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AppVersion.t),
      orderByList: orderByList?.call(AppVersion.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AppVersionImpl extends AppVersion {
  _AppVersionImpl({
    int? id,
    required int appId,
    required int workspaceId,
    required int number,
    required String specJson,
    required String candidateHash,
    required String publisherId,
    required DateTime createdAt,
  }) : super._(
         id: id,
         appId: appId,
         workspaceId: workspaceId,
         number: number,
         specJson: specJson,
         candidateHash: candidateHash,
         publisherId: publisherId,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [AppVersion]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AppVersion copyWith({
    Object? id = _Undefined,
    int? appId,
    int? workspaceId,
    int? number,
    String? specJson,
    String? candidateHash,
    String? publisherId,
    DateTime? createdAt,
  }) {
    return AppVersion(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      workspaceId: workspaceId ?? this.workspaceId,
      number: number ?? this.number,
      specJson: specJson ?? this.specJson,
      candidateHash: candidateHash ?? this.candidateHash,
      publisherId: publisherId ?? this.publisherId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class AppVersionUpdateTable extends _is.UpdateTable<AppVersionTable> {
  AppVersionUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<int, int> number(int value) => _is.ColumnValue(
    table.number,
    value,
  );

  _is.ColumnValue<String, String> specJson(String value) => _is.ColumnValue(
    table.specJson,
    value,
  );

  _is.ColumnValue<String, String> candidateHash(String value) =>
      _is.ColumnValue(
        table.candidateHash,
        value,
      );

  _is.ColumnValue<String, String> publisherId(String value) => _is.ColumnValue(
    table.publisherId,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );
}

class AppVersionTable extends _is.Table<int?> {
  AppVersionTable({super.tableRelation}) : super(tableName: 'nest_version') {
    updateTable = AppVersionUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    number = _is.ColumnInt(
      'number',
      this,
    );
    specJson = _is.ColumnString(
      'specJson',
      this,
    );
    candidateHash = _is.ColumnString(
      'candidateHash',
      this,
    );
    publisherId = _is.ColumnString(
      'publisherId',
      this,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
    );
  }

  late final AppVersionUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnInt workspaceId;

  late final _is.ColumnInt number;

  late final _is.ColumnString specJson;

  late final _is.ColumnString candidateHash;

  late final _is.ColumnString publisherId;

  late final _is.ColumnDateTime createdAt;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    workspaceId,
    number,
    specJson,
    candidateHash,
    publisherId,
    createdAt,
  ];
}

class AppVersionInclude extends _is.IncludeObject {
  AppVersionInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => AppVersion.t;
}

class AppVersionIncludeList extends _is.IncludeList {
  AppVersionIncludeList._({
    _is.WhereExpressionBuilder<AppVersionTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AppVersion.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => AppVersion.t;
}

class AppVersionRepository {
  const AppVersionRepository._();

  /// Returns a list of [AppVersion]s matching the given query parameters.
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
  Future<List<AppVersion>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AppVersionTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AppVersionTable>? orderBy,
    _is.OrderByListBuilder<AppVersionTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AppVersion>(
      where: where?.call(AppVersion.t),
      orderBy: orderBy?.call(AppVersion.t),
      orderByList: orderByList?.call(AppVersion.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AppVersion] matching the given query parameters.
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
  Future<AppVersion?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AppVersionTable>? where,
    int? offset,
    _is.OrderByBuilder<AppVersionTable>? orderBy,
    _is.OrderByListBuilder<AppVersionTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AppVersion>(
      where: where?.call(AppVersion.t),
      orderBy: orderBy?.call(AppVersion.t),
      orderByList: orderByList?.call(AppVersion.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AppVersion] by its [id] or null if no such row exists.
  Future<AppVersion?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AppVersion>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AppVersion]s in the list and returns the inserted rows.
  ///
  /// The returned [AppVersion]s will have their `id` fields set.
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
  Future<List<AppVersion>> insert(
    _is.DatabaseSession session,
    List<AppVersion> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<AppVersion>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [AppVersion] and returns the inserted row.
  ///
  /// The returned [AppVersion] will have its `id` field set.
  Future<AppVersion> insertRow(
    _is.DatabaseSession session,
    AppVersion row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<AppVersion>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [AppVersion]s in the list and returns the resulting rows.
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
  /// The returned [AppVersion]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AppVersion>> upsert(
    _is.DatabaseSession session,
    List<AppVersion> rows, {
    required _is.ColumnSelections<AppVersionTable> conflictColumns,
    _is.ColumnSelections<AppVersionTable>? updateColumns,
    _is.WhereExpressionBuilder<AppVersionTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<AppVersion>(
      rows,
      conflictColumns: conflictColumns(AppVersion.t),
      updateColumns: updateColumns?.call(AppVersion.t),
      updateWhere: updateWhere?.call(AppVersion.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [AppVersion] and returns the resulting row.
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
  /// The returned [AppVersion] will have its `id` field set.
  Future<AppVersion?> upsertRow(
    _is.DatabaseSession session,
    AppVersion row, {
    required _is.ColumnSelections<AppVersionTable> conflictColumns,
    _is.ColumnSelections<AppVersionTable>? updateColumns,
    _is.WhereExpressionBuilder<AppVersionTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<AppVersion>(
      row,
      conflictColumns: conflictColumns(AppVersion.t),
      updateColumns: updateColumns?.call(AppVersion.t),
      updateWhere: updateWhere?.call(AppVersion.t),
      transaction: transaction,
    );
  }

  /// Updates all [AppVersion]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AppVersion>> update(
    _is.DatabaseSession session,
    List<AppVersion> rows, {
    _is.ColumnSelections<AppVersionTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<AppVersion>(
      rows,
      columns: columns?.call(AppVersion.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [AppVersion]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AppVersion> updateRow(
    _is.DatabaseSession session,
    AppVersion row, {
    _is.ColumnSelections<AppVersionTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<AppVersion>(
      row,
      columns: columns?.call(AppVersion.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AppVersion] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AppVersion?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<AppVersionUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<AppVersion>(
      id,
      columnValues: columnValues(AppVersion.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AppVersion]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AppVersion>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<AppVersionUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<AppVersionTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AppVersionTable>? orderBy,
    _is.OrderByListBuilder<AppVersionTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<AppVersion>(
      columnValues: columnValues(AppVersion.t.updateTable),
      where: where(AppVersion.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AppVersion.t),
      orderByList: orderByList?.call(AppVersion.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [AppVersion]s in the list and returns the deleted rows.
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
  Future<List<AppVersion>> delete(
    _is.DatabaseSession session,
    List<AppVersion> rows, {
    _is.OrderByBuilder<AppVersionTable>? orderBy,
    _is.OrderByListBuilder<AppVersionTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<AppVersion>(
      rows,
      orderBy: orderBy?.call(AppVersion.t),
      orderByList: orderByList?.call(AppVersion.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [AppVersion].
  Future<AppVersion> deleteRow(
    _is.DatabaseSession session,
    AppVersion row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AppVersion>(
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
  Future<List<AppVersion>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AppVersionTable> where,
    _is.OrderByBuilder<AppVersionTable>? orderBy,
    _is.OrderByListBuilder<AppVersionTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<AppVersion>(
      where: where(AppVersion.t),
      orderBy: orderBy?.call(AppVersion.t),
      orderByList: orderByList?.call(AppVersion.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AppVersionTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<AppVersion>(
      where: where?.call(AppVersion.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AppVersion] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AppVersionTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AppVersion>(
      where: where(AppVersion.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
