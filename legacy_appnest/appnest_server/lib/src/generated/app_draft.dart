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

abstract class AppDraft
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  AppDraft._({
    this.id,
    required this.appId,
    required this.workspaceId,
    required this.actorId,
    this.baseVersionId,
    required this.candidateJson,
    required this.candidateHash,
    int? mutation,
    this.activeJobId,
    this.publishedVersionId,
    required this.updatedAt,
  }) : mutation = mutation ?? 0;

  factory AppDraft({
    int? id,
    required int appId,
    required int workspaceId,
    required String actorId,
    int? baseVersionId,
    required String candidateJson,
    required String candidateHash,
    int? mutation,
    int? activeJobId,
    int? publishedVersionId,
    required DateTime updatedAt,
  }) = _AppDraftImpl;

  factory AppDraft.fromJson(Map<String, dynamic> jsonSerialization) {
    return AppDraft(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      workspaceId: jsonSerialization['workspaceId'] as int,
      actorId: jsonSerialization['actorId'] as String,
      baseVersionId: jsonSerialization['baseVersionId'] as int?,
      candidateJson: jsonSerialization['candidateJson'] as String,
      candidateHash: jsonSerialization['candidateHash'] as String,
      mutation: jsonSerialization['mutation'] as int?,
      activeJobId: jsonSerialization['activeJobId'] as int?,
      publishedVersionId: jsonSerialization['publishedVersionId'] as int?,
      updatedAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['updatedAt'],
      ),
    );
  }

  static final t = AppDraftTable();

  static const db = AppDraftRepository._();

  @override
  int? id;

  int appId;

  int workspaceId;

  String actorId;

  int? baseVersionId;

  String candidateJson;

  String candidateHash;

  int mutation;

  int? activeJobId;

  int? publishedVersionId;

  DateTime updatedAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [AppDraft]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AppDraft copyWith({
    int? id,
    int? appId,
    int? workspaceId,
    String? actorId,
    int? baseVersionId,
    String? candidateJson,
    String? candidateHash,
    int? mutation,
    int? activeJobId,
    int? publishedVersionId,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AppDraft',
      if (id != null) 'id': id,
      'appId': appId,
      'workspaceId': workspaceId,
      'actorId': actorId,
      if (baseVersionId != null) 'baseVersionId': baseVersionId,
      'candidateJson': candidateJson,
      'candidateHash': candidateHash,
      'mutation': mutation,
      if (activeJobId != null) 'activeJobId': activeJobId,
      if (publishedVersionId != null) 'publishedVersionId': publishedVersionId,
      'updatedAt': updatedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static AppDraftInclude include() {
    return AppDraftInclude._();
  }

  static AppDraftIncludeList includeList({
    _is.WhereExpressionBuilder<AppDraftTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AppDraftTable>? orderBy,
    _is.OrderByListBuilder<AppDraftTable>? orderByList,
    AppDraftInclude? include,
  }) {
    return AppDraftIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AppDraft.t),
      orderByList: orderByList?.call(AppDraft.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AppDraftImpl extends AppDraft {
  _AppDraftImpl({
    int? id,
    required int appId,
    required int workspaceId,
    required String actorId,
    int? baseVersionId,
    required String candidateJson,
    required String candidateHash,
    int? mutation,
    int? activeJobId,
    int? publishedVersionId,
    required DateTime updatedAt,
  }) : super._(
         id: id,
         appId: appId,
         workspaceId: workspaceId,
         actorId: actorId,
         baseVersionId: baseVersionId,
         candidateJson: candidateJson,
         candidateHash: candidateHash,
         mutation: mutation,
         activeJobId: activeJobId,
         publishedVersionId: publishedVersionId,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [AppDraft]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AppDraft copyWith({
    Object? id = _Undefined,
    int? appId,
    int? workspaceId,
    String? actorId,
    Object? baseVersionId = _Undefined,
    String? candidateJson,
    String? candidateHash,
    int? mutation,
    Object? activeJobId = _Undefined,
    Object? publishedVersionId = _Undefined,
    DateTime? updatedAt,
  }) {
    return AppDraft(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      workspaceId: workspaceId ?? this.workspaceId,
      actorId: actorId ?? this.actorId,
      baseVersionId: baseVersionId is int? ? baseVersionId : this.baseVersionId,
      candidateJson: candidateJson ?? this.candidateJson,
      candidateHash: candidateHash ?? this.candidateHash,
      mutation: mutation ?? this.mutation,
      activeJobId: activeJobId is int? ? activeJobId : this.activeJobId,
      publishedVersionId: publishedVersionId is int?
          ? publishedVersionId
          : this.publishedVersionId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AppDraftUpdateTable extends _is.UpdateTable<AppDraftTable> {
  AppDraftUpdateTable(super.table);

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

  _is.ColumnValue<int, int> baseVersionId(int? value) => _is.ColumnValue(
    table.baseVersionId,
    value,
  );

  _is.ColumnValue<String, String> candidateJson(String value) =>
      _is.ColumnValue(
        table.candidateJson,
        value,
      );

  _is.ColumnValue<String, String> candidateHash(String value) =>
      _is.ColumnValue(
        table.candidateHash,
        value,
      );

  _is.ColumnValue<int, int> mutation(int value) => _is.ColumnValue(
    table.mutation,
    value,
  );

  _is.ColumnValue<int, int> activeJobId(int? value) => _is.ColumnValue(
    table.activeJobId,
    value,
  );

  _is.ColumnValue<int, int> publishedVersionId(int? value) => _is.ColumnValue(
    table.publishedVersionId,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> updatedAt(DateTime value) =>
      _is.ColumnValue(
        table.updatedAt,
        value,
      );
}

class AppDraftTable extends _is.Table<int?> {
  AppDraftTable({super.tableRelation}) : super(tableName: 'nest_draft') {
    updateTable = AppDraftUpdateTable(this);
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
    baseVersionId = _is.ColumnInt(
      'baseVersionId',
      this,
    );
    candidateJson = _is.ColumnString(
      'candidateJson',
      this,
    );
    candidateHash = _is.ColumnString(
      'candidateHash',
      this,
    );
    mutation = _is.ColumnInt(
      'mutation',
      this,
      hasDefault: true,
    );
    activeJobId = _is.ColumnInt(
      'activeJobId',
      this,
    );
    publishedVersionId = _is.ColumnInt(
      'publishedVersionId',
      this,
    );
    updatedAt = _is.ColumnDateTime(
      'updatedAt',
      this,
    );
  }

  late final AppDraftUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnInt workspaceId;

  late final _is.ColumnString actorId;

  late final _is.ColumnInt baseVersionId;

  late final _is.ColumnString candidateJson;

  late final _is.ColumnString candidateHash;

  late final _is.ColumnInt mutation;

  late final _is.ColumnInt activeJobId;

  late final _is.ColumnInt publishedVersionId;

  late final _is.ColumnDateTime updatedAt;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    workspaceId,
    actorId,
    baseVersionId,
    candidateJson,
    candidateHash,
    mutation,
    activeJobId,
    publishedVersionId,
    updatedAt,
  ];
}

class AppDraftInclude extends _is.IncludeObject {
  AppDraftInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => AppDraft.t;
}

class AppDraftIncludeList extends _is.IncludeList {
  AppDraftIncludeList._({
    _is.WhereExpressionBuilder<AppDraftTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AppDraft.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => AppDraft.t;
}

class AppDraftRepository {
  const AppDraftRepository._();

  /// Returns a list of [AppDraft]s matching the given query parameters.
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
  Future<List<AppDraft>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AppDraftTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AppDraftTable>? orderBy,
    _is.OrderByListBuilder<AppDraftTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AppDraft>(
      where: where?.call(AppDraft.t),
      orderBy: orderBy?.call(AppDraft.t),
      orderByList: orderByList?.call(AppDraft.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AppDraft] matching the given query parameters.
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
  Future<AppDraft?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AppDraftTable>? where,
    int? offset,
    _is.OrderByBuilder<AppDraftTable>? orderBy,
    _is.OrderByListBuilder<AppDraftTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AppDraft>(
      where: where?.call(AppDraft.t),
      orderBy: orderBy?.call(AppDraft.t),
      orderByList: orderByList?.call(AppDraft.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AppDraft] by its [id] or null if no such row exists.
  Future<AppDraft?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AppDraft>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AppDraft]s in the list and returns the inserted rows.
  ///
  /// The returned [AppDraft]s will have their `id` fields set.
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
  Future<List<AppDraft>> insert(
    _is.DatabaseSession session,
    List<AppDraft> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<AppDraft>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [AppDraft] and returns the inserted row.
  ///
  /// The returned [AppDraft] will have its `id` field set.
  Future<AppDraft> insertRow(
    _is.DatabaseSession session,
    AppDraft row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<AppDraft>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [AppDraft]s in the list and returns the resulting rows.
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
  /// The returned [AppDraft]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AppDraft>> upsert(
    _is.DatabaseSession session,
    List<AppDraft> rows, {
    required _is.ColumnSelections<AppDraftTable> conflictColumns,
    _is.ColumnSelections<AppDraftTable>? updateColumns,
    _is.WhereExpressionBuilder<AppDraftTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<AppDraft>(
      rows,
      conflictColumns: conflictColumns(AppDraft.t),
      updateColumns: updateColumns?.call(AppDraft.t),
      updateWhere: updateWhere?.call(AppDraft.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [AppDraft] and returns the resulting row.
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
  /// The returned [AppDraft] will have its `id` field set.
  Future<AppDraft?> upsertRow(
    _is.DatabaseSession session,
    AppDraft row, {
    required _is.ColumnSelections<AppDraftTable> conflictColumns,
    _is.ColumnSelections<AppDraftTable>? updateColumns,
    _is.WhereExpressionBuilder<AppDraftTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<AppDraft>(
      row,
      conflictColumns: conflictColumns(AppDraft.t),
      updateColumns: updateColumns?.call(AppDraft.t),
      updateWhere: updateWhere?.call(AppDraft.t),
      transaction: transaction,
    );
  }

  /// Updates all [AppDraft]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AppDraft>> update(
    _is.DatabaseSession session,
    List<AppDraft> rows, {
    _is.ColumnSelections<AppDraftTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<AppDraft>(
      rows,
      columns: columns?.call(AppDraft.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [AppDraft]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AppDraft> updateRow(
    _is.DatabaseSession session,
    AppDraft row, {
    _is.ColumnSelections<AppDraftTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<AppDraft>(
      row,
      columns: columns?.call(AppDraft.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AppDraft] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AppDraft?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<AppDraftUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<AppDraft>(
      id,
      columnValues: columnValues(AppDraft.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AppDraft]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AppDraft>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<AppDraftUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<AppDraftTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AppDraftTable>? orderBy,
    _is.OrderByListBuilder<AppDraftTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<AppDraft>(
      columnValues: columnValues(AppDraft.t.updateTable),
      where: where(AppDraft.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AppDraft.t),
      orderByList: orderByList?.call(AppDraft.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [AppDraft]s in the list and returns the deleted rows.
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
  Future<List<AppDraft>> delete(
    _is.DatabaseSession session,
    List<AppDraft> rows, {
    _is.OrderByBuilder<AppDraftTable>? orderBy,
    _is.OrderByListBuilder<AppDraftTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<AppDraft>(
      rows,
      orderBy: orderBy?.call(AppDraft.t),
      orderByList: orderByList?.call(AppDraft.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [AppDraft].
  Future<AppDraft> deleteRow(
    _is.DatabaseSession session,
    AppDraft row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AppDraft>(
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
  Future<List<AppDraft>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AppDraftTable> where,
    _is.OrderByBuilder<AppDraftTable>? orderBy,
    _is.OrderByListBuilder<AppDraftTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<AppDraft>(
      where: where(AppDraft.t),
      orderBy: orderBy?.call(AppDraft.t),
      orderByList: orderByList?.call(AppDraft.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AppDraftTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<AppDraft>(
      where: where?.call(AppDraft.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AppDraft] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AppDraftTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AppDraft>(
      where: where(AppDraft.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
