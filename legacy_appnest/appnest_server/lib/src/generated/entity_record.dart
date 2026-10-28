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
import 'package:appnest_server/src/generated/protocol.dart' as _i270vp9r;
import 'package:serverpod/serverpod.dart' as _is;

abstract class EntityRecord
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  EntityRecord._({
    this.id,
    required this.appId,
    required this.workspaceId,
    required this.collectionId,
    required this.data,
    required this.creatorId,
    required this.revision,
    required this.writtenUnderVersionId,
    required this.createdAt,
    required this.updatedAt,
    bool? deleted,
  }) : deleted = deleted ?? false;

  factory EntityRecord({
    int? id,
    required int appId,
    required int workspaceId,
    required String collectionId,
    required dynamic data,
    required String creatorId,
    required int revision,
    required int writtenUnderVersionId,
    required DateTime createdAt,
    required DateTime updatedAt,
    bool? deleted,
  }) = _EntityRecordImpl;

  factory EntityRecord.fromJson(Map<String, dynamic> jsonSerialization) {
    return EntityRecord(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      workspaceId: jsonSerialization['workspaceId'] as int,
      collectionId: jsonSerialization['collectionId'] as String,
      data: _i270vp9r.Protocol().deserializeDynamicFieldValue(
        jsonSerialization['data'],
      ),
      creatorId: jsonSerialization['creatorId'] as String,
      revision: jsonSerialization['revision'] as int,
      writtenUnderVersionId: jsonSerialization['writtenUnderVersionId'] as int,
      createdAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      updatedAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['updatedAt'],
      ),
      deleted: jsonSerialization['deleted'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['deleted']),
    );
  }

  static final t = EntityRecordTable();

  static const db = EntityRecordRepository._();

  @override
  int? id;

  int appId;

  int workspaceId;

  String collectionId;

  dynamic data;

  String creatorId;

  int revision;

  int writtenUnderVersionId;

  DateTime createdAt;

  DateTime updatedAt;

  bool deleted;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [EntityRecord]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  EntityRecord copyWith({
    int? id,
    int? appId,
    int? workspaceId,
    String? collectionId,
    dynamic data,
    String? creatorId,
    int? revision,
    int? writtenUnderVersionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'EntityRecord',
      if (id != null) 'id': id,
      'appId': appId,
      'workspaceId': workspaceId,
      'collectionId': collectionId,
      'data': _i270vp9r.Protocol().dynamicFieldToJson(data),
      'creatorId': creatorId,
      'revision': revision,
      'writtenUnderVersionId': writtenUnderVersionId,
      'createdAt': createdAt.toJson(),
      'updatedAt': updatedAt.toJson(),
      'deleted': deleted,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static EntityRecordInclude include() {
    return EntityRecordInclude._();
  }

  static EntityRecordIncludeList includeList({
    _is.WhereExpressionBuilder<EntityRecordTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<EntityRecordTable>? orderBy,
    _is.OrderByListBuilder<EntityRecordTable>? orderByList,
    EntityRecordInclude? include,
  }) {
    return EntityRecordIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(EntityRecord.t),
      orderByList: orderByList?.call(EntityRecord.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _EntityRecordImpl extends EntityRecord {
  _EntityRecordImpl({
    int? id,
    required int appId,
    required int workspaceId,
    required String collectionId,
    required dynamic data,
    required String creatorId,
    required int revision,
    required int writtenUnderVersionId,
    required DateTime createdAt,
    required DateTime updatedAt,
    bool? deleted,
  }) : super._(
         id: id,
         appId: appId,
         workspaceId: workspaceId,
         collectionId: collectionId,
         data: data,
         creatorId: creatorId,
         revision: revision,
         writtenUnderVersionId: writtenUnderVersionId,
         createdAt: createdAt,
         updatedAt: updatedAt,
         deleted: deleted,
       );

  /// Returns a shallow copy of this [EntityRecord]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  EntityRecord copyWith({
    Object? id = _Undefined,
    int? appId,
    int? workspaceId,
    String? collectionId,
    Object? data = _Undefined,
    String? creatorId,
    int? revision,
    int? writtenUnderVersionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return EntityRecord(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      workspaceId: workspaceId ?? this.workspaceId,
      collectionId: collectionId ?? this.collectionId,
      data: data != _Undefined ? data : this.data,
      creatorId: creatorId ?? this.creatorId,
      revision: revision ?? this.revision,
      writtenUnderVersionId:
          writtenUnderVersionId ?? this.writtenUnderVersionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}

class EntityRecordUpdateTable extends _is.UpdateTable<EntityRecordTable> {
  EntityRecordUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<int, int> workspaceId(int value) => _is.ColumnValue(
    table.workspaceId,
    value,
  );

  _is.ColumnValue<String, String> collectionId(String value) => _is.ColumnValue(
    table.collectionId,
    value,
  );

  _is.ColumnValue<dynamic, dynamic> data(dynamic value) => _is.ColumnValue(
    table.data,
    value,
  );

  _is.ColumnValue<String, String> creatorId(String value) => _is.ColumnValue(
    table.creatorId,
    value,
  );

  _is.ColumnValue<int, int> revision(int value) => _is.ColumnValue(
    table.revision,
    value,
  );

  _is.ColumnValue<int, int> writtenUnderVersionId(int value) => _is.ColumnValue(
    table.writtenUnderVersionId,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> createdAt(DateTime value) =>
      _is.ColumnValue(
        table.createdAt,
        value,
      );

  _is.ColumnValue<DateTime, DateTime> updatedAt(DateTime value) =>
      _is.ColumnValue(
        table.updatedAt,
        value,
      );

  _is.ColumnValue<bool, bool> deleted(bool value) => _is.ColumnValue(
    table.deleted,
    value,
  );
}

class EntityRecordTable extends _is.Table<int?> {
  EntityRecordTable({super.tableRelation}) : super(tableName: 'nest_record') {
    updateTable = EntityRecordUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    workspaceId = _is.ColumnInt(
      'workspaceId',
      this,
    );
    collectionId = _is.ColumnString(
      'collectionId',
      this,
    );
    data = _is.ColumnStructured<dynamic>(
      'data',
      this,
    );
    creatorId = _is.ColumnString(
      'creatorId',
      this,
    );
    revision = _is.ColumnInt(
      'revision',
      this,
    );
    writtenUnderVersionId = _is.ColumnInt(
      'writtenUnderVersionId',
      this,
    );
    createdAt = _is.ColumnDateTime(
      'createdAt',
      this,
    );
    updatedAt = _is.ColumnDateTime(
      'updatedAt',
      this,
    );
    deleted = _is.ColumnBool(
      'deleted',
      this,
      hasDefault: true,
    );
  }

  late final EntityRecordUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnInt workspaceId;

  late final _is.ColumnString collectionId;

  late final _is.ColumnStructured<dynamic> data;

  late final _is.ColumnString creatorId;

  late final _is.ColumnInt revision;

  late final _is.ColumnInt writtenUnderVersionId;

  late final _is.ColumnDateTime createdAt;

  late final _is.ColumnDateTime updatedAt;

  late final _is.ColumnBool deleted;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    workspaceId,
    collectionId,
    data,
    creatorId,
    revision,
    writtenUnderVersionId,
    createdAt,
    updatedAt,
    deleted,
  ];
}

class EntityRecordInclude extends _is.IncludeObject {
  EntityRecordInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => EntityRecord.t;
}

class EntityRecordIncludeList extends _is.IncludeList {
  EntityRecordIncludeList._({
    _is.WhereExpressionBuilder<EntityRecordTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(EntityRecord.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => EntityRecord.t;
}

class EntityRecordRepository {
  const EntityRecordRepository._();

  /// Returns a list of [EntityRecord]s matching the given query parameters.
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
  Future<List<EntityRecord>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<EntityRecordTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<EntityRecordTable>? orderBy,
    _is.OrderByListBuilder<EntityRecordTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<EntityRecord>(
      where: where?.call(EntityRecord.t),
      orderBy: orderBy?.call(EntityRecord.t),
      orderByList: orderByList?.call(EntityRecord.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [EntityRecord] matching the given query parameters.
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
  Future<EntityRecord?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<EntityRecordTable>? where,
    int? offset,
    _is.OrderByBuilder<EntityRecordTable>? orderBy,
    _is.OrderByListBuilder<EntityRecordTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<EntityRecord>(
      where: where?.call(EntityRecord.t),
      orderBy: orderBy?.call(EntityRecord.t),
      orderByList: orderByList?.call(EntityRecord.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [EntityRecord] by its [id] or null if no such row exists.
  Future<EntityRecord?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<EntityRecord>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [EntityRecord]s in the list and returns the inserted rows.
  ///
  /// The returned [EntityRecord]s will have their `id` fields set.
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
  Future<List<EntityRecord>> insert(
    _is.DatabaseSession session,
    List<EntityRecord> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<EntityRecord>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [EntityRecord] and returns the inserted row.
  ///
  /// The returned [EntityRecord] will have its `id` field set.
  Future<EntityRecord> insertRow(
    _is.DatabaseSession session,
    EntityRecord row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<EntityRecord>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [EntityRecord]s in the list and returns the resulting rows.
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
  /// The returned [EntityRecord]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<EntityRecord>> upsert(
    _is.DatabaseSession session,
    List<EntityRecord> rows, {
    required _is.ColumnSelections<EntityRecordTable> conflictColumns,
    _is.ColumnSelections<EntityRecordTable>? updateColumns,
    _is.WhereExpressionBuilder<EntityRecordTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<EntityRecord>(
      rows,
      conflictColumns: conflictColumns(EntityRecord.t),
      updateColumns: updateColumns?.call(EntityRecord.t),
      updateWhere: updateWhere?.call(EntityRecord.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [EntityRecord] and returns the resulting row.
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
  /// The returned [EntityRecord] will have its `id` field set.
  Future<EntityRecord?> upsertRow(
    _is.DatabaseSession session,
    EntityRecord row, {
    required _is.ColumnSelections<EntityRecordTable> conflictColumns,
    _is.ColumnSelections<EntityRecordTable>? updateColumns,
    _is.WhereExpressionBuilder<EntityRecordTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<EntityRecord>(
      row,
      conflictColumns: conflictColumns(EntityRecord.t),
      updateColumns: updateColumns?.call(EntityRecord.t),
      updateWhere: updateWhere?.call(EntityRecord.t),
      transaction: transaction,
    );
  }

  /// Updates all [EntityRecord]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<EntityRecord>> update(
    _is.DatabaseSession session,
    List<EntityRecord> rows, {
    _is.ColumnSelections<EntityRecordTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<EntityRecord>(
      rows,
      columns: columns?.call(EntityRecord.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [EntityRecord]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<EntityRecord> updateRow(
    _is.DatabaseSession session,
    EntityRecord row, {
    _is.ColumnSelections<EntityRecordTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<EntityRecord>(
      row,
      columns: columns?.call(EntityRecord.t),
      transaction: transaction,
    );
  }

  /// Updates a single [EntityRecord] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<EntityRecord?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<EntityRecordUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<EntityRecord>(
      id,
      columnValues: columnValues(EntityRecord.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [EntityRecord]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<EntityRecord>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<EntityRecordUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<EntityRecordTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<EntityRecordTable>? orderBy,
    _is.OrderByListBuilder<EntityRecordTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<EntityRecord>(
      columnValues: columnValues(EntityRecord.t.updateTable),
      where: where(EntityRecord.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(EntityRecord.t),
      orderByList: orderByList?.call(EntityRecord.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [EntityRecord]s in the list and returns the deleted rows.
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
  Future<List<EntityRecord>> delete(
    _is.DatabaseSession session,
    List<EntityRecord> rows, {
    _is.OrderByBuilder<EntityRecordTable>? orderBy,
    _is.OrderByListBuilder<EntityRecordTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<EntityRecord>(
      rows,
      orderBy: orderBy?.call(EntityRecord.t),
      orderByList: orderByList?.call(EntityRecord.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [EntityRecord].
  Future<EntityRecord> deleteRow(
    _is.DatabaseSession session,
    EntityRecord row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<EntityRecord>(
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
  Future<List<EntityRecord>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<EntityRecordTable> where,
    _is.OrderByBuilder<EntityRecordTable>? orderBy,
    _is.OrderByListBuilder<EntityRecordTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<EntityRecord>(
      where: where(EntityRecord.t),
      orderBy: orderBy?.call(EntityRecord.t),
      orderByList: orderByList?.call(EntityRecord.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<EntityRecordTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<EntityRecord>(
      where: where?.call(EntityRecord.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [EntityRecord] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<EntityRecordTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<EntityRecord>(
      where: where(EntityRecord.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
