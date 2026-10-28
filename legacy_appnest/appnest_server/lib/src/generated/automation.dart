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

abstract class Automation
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  Automation._({
    this.id,
    required this.appId,
    required this.workspaceId,
    required this.ruleId,
    required this.ruleVersion,
    required this.ruleJson,
    required this.enabled,
    required this.executionActorId,
    required this.activateExisting,
    required this.activatedAt,
  });

  factory Automation({
    int? id,
    required int appId,
    required int workspaceId,
    required String ruleId,
    required int ruleVersion,
    required String ruleJson,
    required bool enabled,
    required String executionActorId,
    required bool activateExisting,
    required DateTime activatedAt,
  }) = _AutomationImpl;

  factory Automation.fromJson(Map<String, dynamic> jsonSerialization) {
    return Automation(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      workspaceId: jsonSerialization['workspaceId'] as int,
      ruleId: jsonSerialization['ruleId'] as String,
      ruleVersion: jsonSerialization['ruleVersion'] as int,
      ruleJson: jsonSerialization['ruleJson'] as String,
      enabled: _is.BoolJsonExtension.fromJson(jsonSerialization['enabled']),
      executionActorId: jsonSerialization['executionActorId'] as String,
      activateExisting: _is.BoolJsonExtension.fromJson(
        jsonSerialization['activateExisting'],
      ),
      activatedAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['activatedAt'],
      ),
    );
  }

  static final t = AutomationTable();

  static const db = AutomationRepository._();

  @override
  int? id;

  int appId;

  int workspaceId;

  String ruleId;

  int ruleVersion;

  String ruleJson;

  bool enabled;

  String executionActorId;

  bool activateExisting;

  DateTime activatedAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [Automation]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  Automation copyWith({
    int? id,
    int? appId,
    int? workspaceId,
    String? ruleId,
    int? ruleVersion,
    String? ruleJson,
    bool? enabled,
    String? executionActorId,
    bool? activateExisting,
    DateTime? activatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Automation',
      if (id != null) 'id': id,
      'appId': appId,
      'workspaceId': workspaceId,
      'ruleId': ruleId,
      'ruleVersion': ruleVersion,
      'ruleJson': ruleJson,
      'enabled': enabled,
      'executionActorId': executionActorId,
      'activateExisting': activateExisting,
      'activatedAt': activatedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static AutomationInclude include() {
    return AutomationInclude._();
  }

  static AutomationIncludeList includeList({
    _is.WhereExpressionBuilder<AutomationTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AutomationTable>? orderBy,
    _is.OrderByListBuilder<AutomationTable>? orderByList,
    AutomationInclude? include,
  }) {
    return AutomationIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Automation.t),
      orderByList: orderByList?.call(Automation.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AutomationImpl extends Automation {
  _AutomationImpl({
    int? id,
    required int appId,
    required int workspaceId,
    required String ruleId,
    required int ruleVersion,
    required String ruleJson,
    required bool enabled,
    required String executionActorId,
    required bool activateExisting,
    required DateTime activatedAt,
  }) : super._(
         id: id,
         appId: appId,
         workspaceId: workspaceId,
         ruleId: ruleId,
         ruleVersion: ruleVersion,
         ruleJson: ruleJson,
         enabled: enabled,
         executionActorId: executionActorId,
         activateExisting: activateExisting,
         activatedAt: activatedAt,
       );

  /// Returns a shallow copy of this [Automation]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  Automation copyWith({
    Object? id = _Undefined,
    int? appId,
    int? workspaceId,
    String? ruleId,
    int? ruleVersion,
    String? ruleJson,
    bool? enabled,
    String? executionActorId,
    bool? activateExisting,
    DateTime? activatedAt,
  }) {
    return Automation(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      workspaceId: workspaceId ?? this.workspaceId,
      ruleId: ruleId ?? this.ruleId,
      ruleVersion: ruleVersion ?? this.ruleVersion,
      ruleJson: ruleJson ?? this.ruleJson,
      enabled: enabled ?? this.enabled,
      executionActorId: executionActorId ?? this.executionActorId,
      activateExisting: activateExisting ?? this.activateExisting,
      activatedAt: activatedAt ?? this.activatedAt,
    );
  }
}

class AutomationUpdateTable extends _is.UpdateTable<AutomationTable> {
  AutomationUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<String, String> ruleId(String value) => _is.ColumnValue(
    table.ruleId,
    value,
  );

  _is.ColumnValue<int, int> ruleVersion(int value) => _is.ColumnValue(
    table.ruleVersion,
    value,
  );

  _is.ColumnValue<String, String> ruleJson(String value) => _is.ColumnValue(
    table.ruleJson,
    value,
  );

  _is.ColumnValue<bool, bool> enabled(bool value) => _is.ColumnValue(
    table.enabled,
    value,
  );

  _is.ColumnValue<String, String> executionActorId(String value) =>
      _is.ColumnValue(
        table.executionActorId,
        value,
      );

  _is.ColumnValue<bool, bool> activateExisting(bool value) => _is.ColumnValue(
    table.activateExisting,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> activatedAt(DateTime value) =>
      _is.ColumnValue(
        table.activatedAt,
        value,
      );
}

class AutomationTable extends _is.Table<int?> {
  AutomationTable({super.tableRelation}) : super(tableName: 'nest_automation') {
    updateTable = AutomationUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    ruleId = _is.ColumnString(
      'ruleId',
      this,
    );
    ruleVersion = _is.ColumnInt(
      'ruleVersion',
      this,
    );
    ruleJson = _is.ColumnString(
      'ruleJson',
      this,
    );
    enabled = _is.ColumnBool(
      'enabled',
      this,
    );
    executionActorId = _is.ColumnString(
      'executionActorId',
      this,
    );
    activateExisting = _is.ColumnBool(
      'activateExisting',
      this,
    );
    activatedAt = _is.ColumnDateTime(
      'activatedAt',
      this,
    );
  }

  late final AutomationUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnInt workspaceId;

  late final _is.ColumnString ruleId;

  late final _is.ColumnInt ruleVersion;

  late final _is.ColumnString ruleJson;

  late final _is.ColumnBool enabled;

  late final _is.ColumnString executionActorId;

  late final _is.ColumnBool activateExisting;

  late final _is.ColumnDateTime activatedAt;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    workspaceId,
    ruleId,
    ruleVersion,
    ruleJson,
    enabled,
    executionActorId,
    activateExisting,
    activatedAt,
  ];
}

class AutomationInclude extends _is.IncludeObject {
  AutomationInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => Automation.t;
}

class AutomationIncludeList extends _is.IncludeList {
  AutomationIncludeList._({
    _is.WhereExpressionBuilder<AutomationTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(Automation.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => Automation.t;
}

class AutomationRepository {
  const AutomationRepository._();

  /// Returns a list of [Automation]s matching the given query parameters.
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
  Future<List<Automation>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AutomationTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AutomationTable>? orderBy,
    _is.OrderByListBuilder<AutomationTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<Automation>(
      where: where?.call(Automation.t),
      orderBy: orderBy?.call(Automation.t),
      orderByList: orderByList?.call(Automation.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [Automation] matching the given query parameters.
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
  Future<Automation?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AutomationTable>? where,
    int? offset,
    _is.OrderByBuilder<AutomationTable>? orderBy,
    _is.OrderByListBuilder<AutomationTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<Automation>(
      where: where?.call(Automation.t),
      orderBy: orderBy?.call(Automation.t),
      orderByList: orderByList?.call(Automation.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [Automation] by its [id] or null if no such row exists.
  Future<Automation?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<Automation>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [Automation]s in the list and returns the inserted rows.
  ///
  /// The returned [Automation]s will have their `id` fields set.
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
  Future<List<Automation>> insert(
    _is.DatabaseSession session,
    List<Automation> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<Automation>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [Automation] and returns the inserted row.
  ///
  /// The returned [Automation] will have its `id` field set.
  Future<Automation> insertRow(
    _is.DatabaseSession session,
    Automation row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<Automation>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [Automation]s in the list and returns the resulting rows.
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
  /// The returned [Automation]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Automation>> upsert(
    _is.DatabaseSession session,
    List<Automation> rows, {
    required _is.ColumnSelections<AutomationTable> conflictColumns,
    _is.ColumnSelections<AutomationTable>? updateColumns,
    _is.WhereExpressionBuilder<AutomationTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<Automation>(
      rows,
      conflictColumns: conflictColumns(Automation.t),
      updateColumns: updateColumns?.call(Automation.t),
      updateWhere: updateWhere?.call(Automation.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [Automation] and returns the resulting row.
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
  /// The returned [Automation] will have its `id` field set.
  Future<Automation?> upsertRow(
    _is.DatabaseSession session,
    Automation row, {
    required _is.ColumnSelections<AutomationTable> conflictColumns,
    _is.ColumnSelections<AutomationTable>? updateColumns,
    _is.WhereExpressionBuilder<AutomationTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<Automation>(
      row,
      conflictColumns: conflictColumns(Automation.t),
      updateColumns: updateColumns?.call(Automation.t),
      updateWhere: updateWhere?.call(Automation.t),
      transaction: transaction,
    );
  }

  /// Updates all [Automation]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Automation>> update(
    _is.DatabaseSession session,
    List<Automation> rows, {
    _is.ColumnSelections<AutomationTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<Automation>(
      rows,
      columns: columns?.call(Automation.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [Automation]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<Automation> updateRow(
    _is.DatabaseSession session,
    Automation row, {
    _is.ColumnSelections<AutomationTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<Automation>(
      row,
      columns: columns?.call(Automation.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Automation] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<Automation?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<AutomationUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<Automation>(
      id,
      columnValues: columnValues(Automation.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [Automation]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Automation>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<AutomationUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<AutomationTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AutomationTable>? orderBy,
    _is.OrderByListBuilder<AutomationTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<Automation>(
      columnValues: columnValues(Automation.t.updateTable),
      where: where(Automation.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Automation.t),
      orderByList: orderByList?.call(Automation.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [Automation]s in the list and returns the deleted rows.
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
  Future<List<Automation>> delete(
    _is.DatabaseSession session,
    List<Automation> rows, {
    _is.OrderByBuilder<AutomationTable>? orderBy,
    _is.OrderByListBuilder<AutomationTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<Automation>(
      rows,
      orderBy: orderBy?.call(Automation.t),
      orderByList: orderByList?.call(Automation.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [Automation].
  Future<Automation> deleteRow(
    _is.DatabaseSession session,
    Automation row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<Automation>(
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
  Future<List<Automation>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AutomationTable> where,
    _is.OrderByBuilder<AutomationTable>? orderBy,
    _is.OrderByListBuilder<AutomationTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<Automation>(
      where: where(Automation.t),
      orderBy: orderBy?.call(Automation.t),
      orderByList: orderByList?.call(Automation.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AutomationTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<Automation>(
      where: where?.call(Automation.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [Automation] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AutomationTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<Automation>(
      where: where(Automation.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
