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

abstract class OutboxEvent
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  OutboxEvent._({
    this.id,
    required this.appId,
    this.recordId,
    required this.kind,
    bool? planned,
    bool? invalidated,
    int? attempts,
    required this.nextAttemptAt,
    required this.createdAt,
  }) : planned = planned ?? false,
       invalidated = invalidated ?? false,
       attempts = attempts ?? 0;

  factory OutboxEvent({
    int? id,
    required int appId,
    int? recordId,
    required String kind,
    bool? planned,
    bool? invalidated,
    int? attempts,
    required DateTime nextAttemptAt,
    required DateTime createdAt,
  }) = _OutboxEventImpl;

  factory OutboxEvent.fromJson(Map<String, dynamic> jsonSerialization) {
    return OutboxEvent(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      recordId: jsonSerialization['recordId'] as int?,
      kind: jsonSerialization['kind'] as String,
      planned: jsonSerialization['planned'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['planned']),
      invalidated: jsonSerialization['invalidated'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['invalidated']),
      attempts: jsonSerialization['attempts'] as int?,
      nextAttemptAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['nextAttemptAt'],
      ),
      createdAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
    );
  }

  static final t = OutboxEventTable();

  static const db = OutboxEventRepository._();

  @override
  int? id;

  int appId;

  int? recordId;

  String kind;

  bool planned;

  bool invalidated;

  int attempts;

  DateTime nextAttemptAt;

  DateTime createdAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [OutboxEvent]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  OutboxEvent copyWith({
    int? id,
    int? appId,
    int? recordId,
    String? kind,
    bool? planned,
    bool? invalidated,
    int? attempts,
    DateTime? nextAttemptAt,
    DateTime? createdAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'OutboxEvent',
      if (id != null) 'id': id,
      'appId': appId,
      if (recordId != null) 'recordId': recordId,
      'kind': kind,
      'planned': planned,
      'invalidated': invalidated,
      'attempts': attempts,
      'nextAttemptAt': nextAttemptAt.toJson(),
      'createdAt': createdAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static OutboxEventInclude include() {
    return OutboxEventInclude._();
  }

  static OutboxEventIncludeList includeList({
    _is.WhereExpressionBuilder<OutboxEventTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<OutboxEventTable>? orderBy,
    _is.OrderByListBuilder<OutboxEventTable>? orderByList,
    OutboxEventInclude? include,
  }) {
    return OutboxEventIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(OutboxEvent.t),
      orderByList: orderByList?.call(OutboxEvent.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _OutboxEventImpl extends OutboxEvent {
  _OutboxEventImpl({
    int? id,
    required int appId,
    int? recordId,
    required String kind,
    bool? planned,
    bool? invalidated,
    int? attempts,
    required DateTime nextAttemptAt,
    required DateTime createdAt,
  }) : super._(
         id: id,
         appId: appId,
         recordId: recordId,
         kind: kind,
         planned: planned,
         invalidated: invalidated,
         attempts: attempts,
         nextAttemptAt: nextAttemptAt,
         createdAt: createdAt,
       );

  /// Returns a shallow copy of this [OutboxEvent]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  OutboxEvent copyWith({
    Object? id = _Undefined,
    int? appId,
    Object? recordId = _Undefined,
    String? kind,
    bool? planned,
    bool? invalidated,
    int? attempts,
    DateTime? nextAttemptAt,
    DateTime? createdAt,
  }) {
    return OutboxEvent(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      recordId: recordId is int? ? recordId : this.recordId,
      kind: kind ?? this.kind,
      planned: planned ?? this.planned,
      invalidated: invalidated ?? this.invalidated,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class OutboxEventUpdateTable extends _is.UpdateTable<OutboxEventTable> {
  OutboxEventUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<int, int> recordId(int? value) => _is.ColumnValue(
    table.recordId,
    value,
  );

  _is.ColumnValue<String, String> kind(String value) => _is.ColumnValue(
    table.kind,
    value,
  );

  _is.ColumnValue<bool, bool> planned(bool value) => _is.ColumnValue(
    table.planned,
    value,
  );

  _is.ColumnValue<bool, bool> invalidated(bool value) => _is.ColumnValue(
    table.invalidated,
    value,
  );

  _is.ColumnValue<int, int> attempts(int value) => _is.ColumnValue(
    table.attempts,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> nextAttemptAt(DateTime value) =>
      _is.ColumnValue(
        table.nextAttemptAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );
}

class OutboxEventTable extends _is.Table<int?> {
  OutboxEventTable({super.tableRelation}) : super(tableName: 'nest_outbox') {
    updateTable = OutboxEventUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    recordId = _is.ColumnInt(
      'recordId',
      this,
    );
    kind = _is.ColumnString(
      'kind',
      this,
    );
    planned = _is.ColumnBool(
      'planned',
      this,
      hasDefault: true,
    );
    invalidated = _is.ColumnBool(
      'invalidated',
      this,
      hasDefault: true,
    );
    attempts = _is.ColumnInt(
      'attempts',
      this,
      hasDefault: true,
    );
    nextAttemptAt = _is.ColumnDateTime(
      'nextAttemptAt',
      this,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
    );
  }

  late final OutboxEventUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnInt recordId;

  late final _is.ColumnString kind;

  late final _is.ColumnBool planned;

  late final _is.ColumnBool invalidated;

  late final _is.ColumnInt attempts;

  late final _is.ColumnDateTime nextAttemptAt;

  late final _is.ColumnDateTime createdAt;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    recordId,
    kind,
    planned,
    invalidated,
    attempts,
    nextAttemptAt,
    createdAt,
  ];
}

class OutboxEventInclude extends _is.IncludeObject {
  OutboxEventInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => OutboxEvent.t;
}

class OutboxEventIncludeList extends _is.IncludeList {
  OutboxEventIncludeList._({
    _is.WhereExpressionBuilder<OutboxEventTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(OutboxEvent.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => OutboxEvent.t;
}

class OutboxEventRepository {
  const OutboxEventRepository._();

  /// Returns a list of [OutboxEvent]s matching the given query parameters.
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
  Future<List<OutboxEvent>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<OutboxEventTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<OutboxEventTable>? orderBy,
    _is.OrderByListBuilder<OutboxEventTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<OutboxEvent>(
      where: where?.call(OutboxEvent.t),
      orderBy: orderBy?.call(OutboxEvent.t),
      orderByList: orderByList?.call(OutboxEvent.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [OutboxEvent] matching the given query parameters.
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
  Future<OutboxEvent?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<OutboxEventTable>? where,
    int? offset,
    _is.OrderByBuilder<OutboxEventTable>? orderBy,
    _is.OrderByListBuilder<OutboxEventTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<OutboxEvent>(
      where: where?.call(OutboxEvent.t),
      orderBy: orderBy?.call(OutboxEvent.t),
      orderByList: orderByList?.call(OutboxEvent.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [OutboxEvent] by its [id] or null if no such row exists.
  Future<OutboxEvent?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<OutboxEvent>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [OutboxEvent]s in the list and returns the inserted rows.
  ///
  /// The returned [OutboxEvent]s will have their `id` fields set.
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
  Future<List<OutboxEvent>> insert(
    _is.DatabaseSession session,
    List<OutboxEvent> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<OutboxEvent>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [OutboxEvent] and returns the inserted row.
  ///
  /// The returned [OutboxEvent] will have its `id` field set.
  Future<OutboxEvent> insertRow(
    _is.DatabaseSession session,
    OutboxEvent row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<OutboxEvent>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [OutboxEvent]s in the list and returns the resulting rows.
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
  /// The returned [OutboxEvent]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<OutboxEvent>> upsert(
    _is.DatabaseSession session,
    List<OutboxEvent> rows, {
    required _is.ColumnSelections<OutboxEventTable> conflictColumns,
    _is.ColumnSelections<OutboxEventTable>? updateColumns,
    _is.WhereExpressionBuilder<OutboxEventTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<OutboxEvent>(
      rows,
      conflictColumns: conflictColumns(OutboxEvent.t),
      updateColumns: updateColumns?.call(OutboxEvent.t),
      updateWhere: updateWhere?.call(OutboxEvent.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [OutboxEvent] and returns the resulting row.
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
  /// The returned [OutboxEvent] will have its `id` field set.
  Future<OutboxEvent?> upsertRow(
    _is.DatabaseSession session,
    OutboxEvent row, {
    required _is.ColumnSelections<OutboxEventTable> conflictColumns,
    _is.ColumnSelections<OutboxEventTable>? updateColumns,
    _is.WhereExpressionBuilder<OutboxEventTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<OutboxEvent>(
      row,
      conflictColumns: conflictColumns(OutboxEvent.t),
      updateColumns: updateColumns?.call(OutboxEvent.t),
      updateWhere: updateWhere?.call(OutboxEvent.t),
      transaction: transaction,
    );
  }

  /// Updates all [OutboxEvent]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<OutboxEvent>> update(
    _is.DatabaseSession session,
    List<OutboxEvent> rows, {
    _is.ColumnSelections<OutboxEventTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<OutboxEvent>(
      rows,
      columns: columns?.call(OutboxEvent.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [OutboxEvent]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<OutboxEvent> updateRow(
    _is.DatabaseSession session,
    OutboxEvent row, {
    _is.ColumnSelections<OutboxEventTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<OutboxEvent>(
      row,
      columns: columns?.call(OutboxEvent.t),
      transaction: transaction,
    );
  }

  /// Updates a single [OutboxEvent] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<OutboxEvent?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<OutboxEventUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<OutboxEvent>(
      id,
      columnValues: columnValues(OutboxEvent.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [OutboxEvent]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<OutboxEvent>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<OutboxEventUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<OutboxEventTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<OutboxEventTable>? orderBy,
    _is.OrderByListBuilder<OutboxEventTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<OutboxEvent>(
      columnValues: columnValues(OutboxEvent.t.updateTable),
      where: where(OutboxEvent.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(OutboxEvent.t),
      orderByList: orderByList?.call(OutboxEvent.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [OutboxEvent]s in the list and returns the deleted rows.
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
  Future<List<OutboxEvent>> delete(
    _is.DatabaseSession session,
    List<OutboxEvent> rows, {
    _is.OrderByBuilder<OutboxEventTable>? orderBy,
    _is.OrderByListBuilder<OutboxEventTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<OutboxEvent>(
      rows,
      orderBy: orderBy?.call(OutboxEvent.t),
      orderByList: orderByList?.call(OutboxEvent.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [OutboxEvent].
  Future<OutboxEvent> deleteRow(
    _is.DatabaseSession session,
    OutboxEvent row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<OutboxEvent>(
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
  Future<List<OutboxEvent>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<OutboxEventTable> where,
    _is.OrderByBuilder<OutboxEventTable>? orderBy,
    _is.OrderByListBuilder<OutboxEventTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<OutboxEvent>(
      where: where(OutboxEvent.t),
      orderBy: orderBy?.call(OutboxEvent.t),
      orderByList: orderByList?.call(OutboxEvent.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<OutboxEventTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<OutboxEvent>(
      where: where?.call(OutboxEvent.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [OutboxEvent] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<OutboxEventTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<OutboxEvent>(
      where: where(OutboxEvent.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
