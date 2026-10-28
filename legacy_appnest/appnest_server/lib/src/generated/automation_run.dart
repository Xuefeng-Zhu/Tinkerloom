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

abstract class AutomationRun
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  AutomationRun._({
    this.id,
    required this.appId,
    required this.automationId,
    int? ruleVersion,
    required this.recordId,
    required this.occurrenceKey,
    required this.scheduleSignature,
    required this.dueAt,
    required this.nextAttemptAt,
    required this.status,
    int? attempts,
    int? leaseGeneration,
    this.leaseUntil,
    this.errorCategory,
    required this.createdAt,
    this.completedAt,
  }) : ruleVersion = ruleVersion ?? 1,
       attempts = attempts ?? 0,
       leaseGeneration = leaseGeneration ?? 0;

  factory AutomationRun({
    int? id,
    required int appId,
    required int automationId,
    int? ruleVersion,
    required int recordId,
    required String occurrenceKey,
    required String scheduleSignature,
    required DateTime dueAt,
    required DateTime nextAttemptAt,
    required String status,
    int? attempts,
    int? leaseGeneration,
    DateTime? leaseUntil,
    String? errorCategory,
    required DateTime createdAt,
    DateTime? completedAt,
  }) = _AutomationRunImpl;

  factory AutomationRun.fromJson(Map<String, dynamic> jsonSerialization) {
    return AutomationRun(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      automationId: jsonSerialization['automationId'] as int,
      ruleVersion: jsonSerialization['ruleVersion'] as int?,
      recordId: jsonSerialization['recordId'] as int,
      occurrenceKey: jsonSerialization['occurrenceKey'] as String,
      scheduleSignature: jsonSerialization['scheduleSignature'] as String,
      dueAt: _is.DateTimeJsonExtension.fromJson(jsonSerialization['dueAt']),
      nextAttemptAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['nextAttemptAt'],
      ),
      status: jsonSerialization['status'] as String,
      attempts: jsonSerialization['attempts'] as int?,
      leaseGeneration: jsonSerialization['leaseGeneration'] as int?,
      leaseUntil: jsonSerialization['leaseUntil'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['leaseUntil']),
      errorCategory: jsonSerialization['errorCategory'] as String?,
      createdAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      completedAt: jsonSerialization['completedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(
              jsonSerialization['completedAt'],
            ),
    );
  }

  static final t = AutomationRunTable();

  static const db = AutomationRunRepository._();

  @override
  int? id;

  int appId;

  int automationId;

  int ruleVersion;

  int recordId;

  String occurrenceKey;

  String scheduleSignature;

  DateTime dueAt;

  DateTime nextAttemptAt;

  String status;

  int attempts;

  int leaseGeneration;

  DateTime? leaseUntil;

  String? errorCategory;

  DateTime createdAt;

  DateTime? completedAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [AutomationRun]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AutomationRun copyWith({
    int? id,
    int? appId,
    int? automationId,
    int? ruleVersion,
    int? recordId,
    String? occurrenceKey,
    String? scheduleSignature,
    DateTime? dueAt,
    DateTime? nextAttemptAt,
    String? status,
    int? attempts,
    int? leaseGeneration,
    DateTime? leaseUntil,
    String? errorCategory,
    DateTime? createdAt,
    DateTime? completedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AutomationRun',
      if (id != null) 'id': id,
      'appId': appId,
      'automationId': automationId,
      'ruleVersion': ruleVersion,
      'recordId': recordId,
      'occurrenceKey': occurrenceKey,
      'scheduleSignature': scheduleSignature,
      'dueAt': dueAt.toJson(),
      'nextAttemptAt': nextAttemptAt.toJson(),
      'status': status,
      'attempts': attempts,
      'leaseGeneration': leaseGeneration,
      if (leaseUntil != null) 'leaseUntil': leaseUntil?.toJson(),
      if (errorCategory != null) 'errorCategory': errorCategory,
      'createdAt': createdAt.toJson(),
      if (completedAt != null) 'completedAt': completedAt?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static AutomationRunInclude include() {
    return AutomationRunInclude._();
  }

  static AutomationRunIncludeList includeList({
    _is.WhereExpressionBuilder<AutomationRunTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AutomationRunTable>? orderBy,
    _is.OrderByListBuilder<AutomationRunTable>? orderByList,
    AutomationRunInclude? include,
  }) {
    return AutomationRunIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AutomationRun.t),
      orderByList: orderByList?.call(AutomationRun.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AutomationRunImpl extends AutomationRun {
  _AutomationRunImpl({
    int? id,
    required int appId,
    required int automationId,
    int? ruleVersion,
    required int recordId,
    required String occurrenceKey,
    required String scheduleSignature,
    required DateTime dueAt,
    required DateTime nextAttemptAt,
    required String status,
    int? attempts,
    int? leaseGeneration,
    DateTime? leaseUntil,
    String? errorCategory,
    required DateTime createdAt,
    DateTime? completedAt,
  }) : super._(
         id: id,
         appId: appId,
         automationId: automationId,
         ruleVersion: ruleVersion,
         recordId: recordId,
         occurrenceKey: occurrenceKey,
         scheduleSignature: scheduleSignature,
         dueAt: dueAt,
         nextAttemptAt: nextAttemptAt,
         status: status,
         attempts: attempts,
         leaseGeneration: leaseGeneration,
         leaseUntil: leaseUntil,
         errorCategory: errorCategory,
         createdAt: createdAt,
         completedAt: completedAt,
       );

  /// Returns a shallow copy of this [AutomationRun]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AutomationRun copyWith({
    Object? id = _Undefined,
    int? appId,
    int? automationId,
    int? ruleVersion,
    int? recordId,
    String? occurrenceKey,
    String? scheduleSignature,
    DateTime? dueAt,
    DateTime? nextAttemptAt,
    String? status,
    int? attempts,
    int? leaseGeneration,
    Object? leaseUntil = _Undefined,
    Object? errorCategory = _Undefined,
    DateTime? createdAt,
    Object? completedAt = _Undefined,
  }) {
    return AutomationRun(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      automationId: automationId ?? this.automationId,
      ruleVersion: ruleVersion ?? this.ruleVersion,
      recordId: recordId ?? this.recordId,
      occurrenceKey: occurrenceKey ?? this.occurrenceKey,
      scheduleSignature: scheduleSignature ?? this.scheduleSignature,
      dueAt: dueAt ?? this.dueAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      leaseGeneration: leaseGeneration ?? this.leaseGeneration,
      leaseUntil: leaseUntil is DateTime? ? leaseUntil : this.leaseUntil,
      errorCategory: errorCategory is String?
          ? errorCategory
          : this.errorCategory,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt is DateTime? ? completedAt : this.completedAt,
    );
  }
}

class AutomationRunUpdateTable extends _is.UpdateTable<AutomationRunTable> {
  AutomationRunUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<int, int> automationId(int value) => _is.ColumnValue(
    table.automationId,
    value,
  );

  _is.ColumnValue<int, int> ruleVersion(int value) => _is.ColumnValue(
    table.ruleVersion,
    value,
  );

  _is.ColumnValue<int, int> recordId(int value) => _is.ColumnValue(
    table.recordId,
    value,
  );

  _is.ColumnValue<String, String> occurrenceKey(String value) =>
      _is.ColumnValue(
        table.occurrenceKey,
        value,
      );

  _is.ColumnValue<String, String> scheduleSignature(String value) =>
      _is.ColumnValue(
        table.scheduleSignature,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> dueAt(DateTime value) => _is.ColumnValue(
    table.dueAt,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> nextAttemptAt(DateTime value) =>
      _is.ColumnValue(
        table.nextAttemptAt,
        value,
      );

  _is.ColumnValue<String, String> status(String value) => _is.ColumnValue(
    table.status,
    value,
  );

  _is.ColumnValue<int, int> attempts(int value) => _is.ColumnValue(
    table.attempts,
    value,
  );

  _is.ColumnValue<int, int> leaseGeneration(int value) => _is.ColumnValue(
    table.leaseGeneration,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> leaseUntil(DateTime? value) =>
      _is.ColumnValue(
        table.leaseUntil,
        value,
      );

  _is.ColumnValue<String, String> errorCategory(String? value) =>
      _is.ColumnValue(
        table.errorCategory,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> completedAt(DateTime? value) =>
      _is.ColumnValue(
        table.completedAt,
        value,
      );
}

class AutomationRunTable extends _is.Table<int?> {
  AutomationRunTable({super.tableRelation}) : super(tableName: 'nest_run') {
    updateTable = AutomationRunUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    automationId = _is.ColumnInt(
      'automationId',
      this,
    );
    ruleVersion = _is.ColumnInt(
      'ruleVersion',
      this,
      hasDefault: true,
    );
    recordId = _is.ColumnInt(
      'recordId',
      this,
    );
    occurrenceKey = _is.ColumnString(
      'occurrenceKey',
      this,
    );
    scheduleSignature = _is.ColumnString(
      'scheduleSignature',
      this,
    );
    dueAt = _is.ColumnDateTime(
      'dueAt',
      this,
    );
    nextAttemptAt = _is.ColumnDateTime(
      'nextAttemptAt',
      this,
    );
    status = _is.ColumnString(
      'status',
      this,
    );
    attempts = _is.ColumnInt(
      'attempts',
      this,
      hasDefault: true,
    );
    leaseGeneration = _is.ColumnInt(
      'leaseGeneration',
      this,
      hasDefault: true,
    );
    leaseUntil = _is.ColumnDateTime(
      'leaseUntil',
      this,
    );
    errorCategory = _is.ColumnString(
      'errorCategory',
      this,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
    );
    completedAt = _is.ColumnDateTime(
      'completedAt',
      this,
    );
  }

  late final AutomationRunUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnInt automationId;

  late final _is.ColumnInt ruleVersion;

  late final _is.ColumnInt recordId;

  late final _is.ColumnString occurrenceKey;

  late final _is.ColumnString scheduleSignature;

  late final _is.ColumnDateTime dueAt;

  late final _is.ColumnDateTime nextAttemptAt;

  late final _is.ColumnString status;

  late final _is.ColumnInt attempts;

  late final _is.ColumnInt leaseGeneration;

  late final _is.ColumnDateTime leaseUntil;

  late final _is.ColumnString errorCategory;

  late final _is.ColumnDateTime createdAt;

  late final _is.ColumnDateTime completedAt;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    automationId,
    ruleVersion,
    recordId,
    occurrenceKey,
    scheduleSignature,
    dueAt,
    nextAttemptAt,
    status,
    attempts,
    leaseGeneration,
    leaseUntil,
    errorCategory,
    createdAt,
    completedAt,
  ];
}

class AutomationRunInclude extends _is.IncludeObject {
  AutomationRunInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => AutomationRun.t;
}

class AutomationRunIncludeList extends _is.IncludeList {
  AutomationRunIncludeList._({
    _is.WhereExpressionBuilder<AutomationRunTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AutomationRun.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => AutomationRun.t;
}

class AutomationRunRepository {
  const AutomationRunRepository._();

  /// Returns a list of [AutomationRun]s matching the given query parameters.
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
  Future<List<AutomationRun>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AutomationRunTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AutomationRunTable>? orderBy,
    _is.OrderByListBuilder<AutomationRunTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AutomationRun>(
      where: where?.call(AutomationRun.t),
      orderBy: orderBy?.call(AutomationRun.t),
      orderByList: orderByList?.call(AutomationRun.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [AutomationRun] matching the given query parameters.
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
  Future<AutomationRun?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AutomationRunTable>? where,
    int? offset,
    _is.OrderByBuilder<AutomationRunTable>? orderBy,
    _is.OrderByListBuilder<AutomationRunTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AutomationRun>(
      where: where?.call(AutomationRun.t),
      orderBy: orderBy?.call(AutomationRun.t),
      orderByList: orderByList?.call(AutomationRun.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AutomationRun] by its [id] or null if no such row exists.
  Future<AutomationRun?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AutomationRun>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AutomationRun]s in the list and returns the inserted rows.
  ///
  /// The returned [AutomationRun]s will have their `id` fields set.
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
  Future<List<AutomationRun>> insert(
    _is.DatabaseSession session,
    List<AutomationRun> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<AutomationRun>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [AutomationRun] and returns the inserted row.
  ///
  /// The returned [AutomationRun] will have its `id` field set.
  Future<AutomationRun> insertRow(
    _is.DatabaseSession session,
    AutomationRun row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<AutomationRun>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [AutomationRun]s in the list and returns the resulting rows.
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
  /// The returned [AutomationRun]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AutomationRun>> upsert(
    _is.DatabaseSession session,
    List<AutomationRun> rows, {
    required _is.ColumnSelections<AutomationRunTable> conflictColumns,
    _is.ColumnSelections<AutomationRunTable>? updateColumns,
    _is.WhereExpressionBuilder<AutomationRunTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<AutomationRun>(
      rows,
      conflictColumns: conflictColumns(AutomationRun.t),
      updateColumns: updateColumns?.call(AutomationRun.t),
      updateWhere: updateWhere?.call(AutomationRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [AutomationRun] and returns the resulting row.
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
  /// The returned [AutomationRun] will have its `id` field set.
  Future<AutomationRun?> upsertRow(
    _is.DatabaseSession session,
    AutomationRun row, {
    required _is.ColumnSelections<AutomationRunTable> conflictColumns,
    _is.ColumnSelections<AutomationRunTable>? updateColumns,
    _is.WhereExpressionBuilder<AutomationRunTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<AutomationRun>(
      row,
      conflictColumns: conflictColumns(AutomationRun.t),
      updateColumns: updateColumns?.call(AutomationRun.t),
      updateWhere: updateWhere?.call(AutomationRun.t),
      transaction: transaction,
    );
  }

  /// Updates all [AutomationRun]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AutomationRun>> update(
    _is.DatabaseSession session,
    List<AutomationRun> rows, {
    _is.ColumnSelections<AutomationRunTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<AutomationRun>(
      rows,
      columns: columns?.call(AutomationRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [AutomationRun]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AutomationRun> updateRow(
    _is.DatabaseSession session,
    AutomationRun row, {
    _is.ColumnSelections<AutomationRunTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<AutomationRun>(
      row,
      columns: columns?.call(AutomationRun.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AutomationRun] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AutomationRun?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<AutomationRunUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<AutomationRun>(
      id,
      columnValues: columnValues(AutomationRun.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AutomationRun]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AutomationRun>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<AutomationRunUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<AutomationRunTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AutomationRunTable>? orderBy,
    _is.OrderByListBuilder<AutomationRunTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<AutomationRun>(
      columnValues: columnValues(AutomationRun.t.updateTable),
      where: where(AutomationRun.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AutomationRun.t),
      orderByList: orderByList?.call(AutomationRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [AutomationRun]s in the list and returns the deleted rows.
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
  Future<List<AutomationRun>> delete(
    _is.DatabaseSession session,
    List<AutomationRun> rows, {
    _is.OrderByBuilder<AutomationRunTable>? orderBy,
    _is.OrderByListBuilder<AutomationRunTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<AutomationRun>(
      rows,
      orderBy: orderBy?.call(AutomationRun.t),
      orderByList: orderByList?.call(AutomationRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [AutomationRun].
  Future<AutomationRun> deleteRow(
    _is.DatabaseSession session,
    AutomationRun row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AutomationRun>(
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
  Future<List<AutomationRun>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AutomationRunTable> where,
    _is.OrderByBuilder<AutomationRunTable>? orderBy,
    _is.OrderByListBuilder<AutomationRunTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<AutomationRun>(
      where: where(AutomationRun.t),
      orderBy: orderBy?.call(AutomationRun.t),
      orderByList: orderByList?.call(AutomationRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AutomationRunTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<AutomationRun>(
      where: where?.call(AutomationRun.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AutomationRun] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AutomationRunTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AutomationRun>(
      where: where(AutomationRun.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
