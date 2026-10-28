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

abstract class MediaReference
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  MediaReference._({
    this.id,
    required this.appId,
    required this.assetRowId,
    this.draftId,
    this.versionId,
    this.recordId,
  });

  factory MediaReference({
    int? id,
    required int appId,
    required int assetRowId,
    int? draftId,
    int? versionId,
    int? recordId,
  }) = _MediaReferenceImpl;

  factory MediaReference.fromJson(Map<String, dynamic> jsonSerialization) {
    return MediaReference(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      assetRowId: jsonSerialization['assetRowId'] as int,
      draftId: jsonSerialization['draftId'] as int?,
      versionId: jsonSerialization['versionId'] as int?,
      recordId: jsonSerialization['recordId'] as int?,
    );
  }

  static final t = MediaReferenceTable();

  static const db = MediaReferenceRepository._();

  @override
  int? id;

  int appId;

  int assetRowId;

  int? draftId;

  int? versionId;

  int? recordId;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [MediaReference]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  MediaReference copyWith({
    int? id,
    int? appId,
    int? assetRowId,
    int? draftId,
    int? versionId,
    int? recordId,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MediaReference',
      if (id != null) 'id': id,
      'appId': appId,
      'assetRowId': assetRowId,
      if (draftId != null) 'draftId': draftId,
      if (versionId != null) 'versionId': versionId,
      if (recordId != null) 'recordId': recordId,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static MediaReferenceInclude include() {
    return MediaReferenceInclude._();
  }

  static MediaReferenceIncludeList includeList({
    _is.WhereExpressionBuilder<MediaReferenceTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MediaReferenceTable>? orderBy,
    _is.OrderByListBuilder<MediaReferenceTable>? orderByList,
    MediaReferenceInclude? include,
  }) {
    return MediaReferenceIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(MediaReference.t),
      orderByList: orderByList?.call(MediaReference.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _MediaReferenceImpl extends MediaReference {
  _MediaReferenceImpl({
    int? id,
    required int appId,
    required int assetRowId,
    int? draftId,
    int? versionId,
    int? recordId,
  }) : super._(
         id: id,
         appId: appId,
         assetRowId: assetRowId,
         draftId: draftId,
         versionId: versionId,
         recordId: recordId,
       );

  /// Returns a shallow copy of this [MediaReference]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  MediaReference copyWith({
    Object? id = _Undefined,
    int? appId,
    int? assetRowId,
    Object? draftId = _Undefined,
    Object? versionId = _Undefined,
    Object? recordId = _Undefined,
  }) {
    return MediaReference(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      assetRowId: assetRowId ?? this.assetRowId,
      draftId: draftId is int? ? draftId : this.draftId,
      versionId: versionId is int? ? versionId : this.versionId,
      recordId: recordId is int? ? recordId : this.recordId,
    );
  }
}

class MediaReferenceUpdateTable extends _is.UpdateTable<MediaReferenceTable> {
  MediaReferenceUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<int, int> assetRowId(int value) => _is.ColumnValue(
    table.assetRowId,
    value,
  );

  _is.ColumnValue<int, int> draftId(int? value) => _is.ColumnValue(
    table.draftId,
    value,
  );

  _is.ColumnValue<int, int> versionId(int? value) => _is.ColumnValue(
    table.versionId,
    value,
  );

  _is.ColumnValue<int, int> recordId(int? value) => _is.ColumnValue(
    table.recordId,
    value,
  );
}

class MediaReferenceTable extends _is.Table<int?> {
  MediaReferenceTable({super.tableRelation})
    : super(tableName: 'nest_media_reference') {
    updateTable = MediaReferenceUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    assetRowId = _is.ColumnInt(
      'assetRowId',
      this,
    );
    draftId = _is.ColumnInt(
      'draftId',
      this,
    );
    versionId = _is.ColumnInt(
      'versionId',
      this,
    );
    recordId = _is.ColumnInt(
      'recordId',
      this,
    );
  }

  late final MediaReferenceUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnInt assetRowId;

  late final _is.ColumnInt draftId;

  late final _is.ColumnInt versionId;

  late final _is.ColumnInt recordId;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    assetRowId,
    draftId,
    versionId,
    recordId,
  ];
}

class MediaReferenceInclude extends _is.IncludeObject {
  MediaReferenceInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => MediaReference.t;
}

class MediaReferenceIncludeList extends _is.IncludeList {
  MediaReferenceIncludeList._({
    _is.WhereExpressionBuilder<MediaReferenceTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(MediaReference.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => MediaReference.t;
}

class MediaReferenceRepository {
  const MediaReferenceRepository._();

  /// Returns a list of [MediaReference]s matching the given query parameters.
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
  Future<List<MediaReference>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MediaReferenceTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MediaReferenceTable>? orderBy,
    _is.OrderByListBuilder<MediaReferenceTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<MediaReference>(
      where: where?.call(MediaReference.t),
      orderBy: orderBy?.call(MediaReference.t),
      orderByList: orderByList?.call(MediaReference.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [MediaReference] matching the given query parameters.
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
  Future<MediaReference?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MediaReferenceTable>? where,
    int? offset,
    _is.OrderByBuilder<MediaReferenceTable>? orderBy,
    _is.OrderByListBuilder<MediaReferenceTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<MediaReference>(
      where: where?.call(MediaReference.t),
      orderBy: orderBy?.call(MediaReference.t),
      orderByList: orderByList?.call(MediaReference.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [MediaReference] by its [id] or null if no such row exists.
  Future<MediaReference?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<MediaReference>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [MediaReference]s in the list and returns the inserted rows.
  ///
  /// The returned [MediaReference]s will have their `id` fields set.
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
  Future<List<MediaReference>> insert(
    _is.DatabaseSession session,
    List<MediaReference> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<MediaReference>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [MediaReference] and returns the inserted row.
  ///
  /// The returned [MediaReference] will have its `id` field set.
  Future<MediaReference> insertRow(
    _is.DatabaseSession session,
    MediaReference row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<MediaReference>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [MediaReference]s in the list and returns the resulting rows.
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
  /// The returned [MediaReference]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<MediaReference>> upsert(
    _is.DatabaseSession session,
    List<MediaReference> rows, {
    required _is.ColumnSelections<MediaReferenceTable> conflictColumns,
    _is.ColumnSelections<MediaReferenceTable>? updateColumns,
    _is.WhereExpressionBuilder<MediaReferenceTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<MediaReference>(
      rows,
      conflictColumns: conflictColumns(MediaReference.t),
      updateColumns: updateColumns?.call(MediaReference.t),
      updateWhere: updateWhere?.call(MediaReference.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [MediaReference] and returns the resulting row.
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
  /// The returned [MediaReference] will have its `id` field set.
  Future<MediaReference?> upsertRow(
    _is.DatabaseSession session,
    MediaReference row, {
    required _is.ColumnSelections<MediaReferenceTable> conflictColumns,
    _is.ColumnSelections<MediaReferenceTable>? updateColumns,
    _is.WhereExpressionBuilder<MediaReferenceTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<MediaReference>(
      row,
      conflictColumns: conflictColumns(MediaReference.t),
      updateColumns: updateColumns?.call(MediaReference.t),
      updateWhere: updateWhere?.call(MediaReference.t),
      transaction: transaction,
    );
  }

  /// Updates all [MediaReference]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<MediaReference>> update(
    _is.DatabaseSession session,
    List<MediaReference> rows, {
    _is.ColumnSelections<MediaReferenceTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<MediaReference>(
      rows,
      columns: columns?.call(MediaReference.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [MediaReference]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<MediaReference> updateRow(
    _is.DatabaseSession session,
    MediaReference row, {
    _is.ColumnSelections<MediaReferenceTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<MediaReference>(
      row,
      columns: columns?.call(MediaReference.t),
      transaction: transaction,
    );
  }

  /// Updates a single [MediaReference] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<MediaReference?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<MediaReferenceUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<MediaReference>(
      id,
      columnValues: columnValues(MediaReference.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [MediaReference]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<MediaReference>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<MediaReferenceUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<MediaReferenceTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MediaReferenceTable>? orderBy,
    _is.OrderByListBuilder<MediaReferenceTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<MediaReference>(
      columnValues: columnValues(MediaReference.t.updateTable),
      where: where(MediaReference.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(MediaReference.t),
      orderByList: orderByList?.call(MediaReference.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [MediaReference]s in the list and returns the deleted rows.
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
  Future<List<MediaReference>> delete(
    _is.DatabaseSession session,
    List<MediaReference> rows, {
    _is.OrderByBuilder<MediaReferenceTable>? orderBy,
    _is.OrderByListBuilder<MediaReferenceTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<MediaReference>(
      rows,
      orderBy: orderBy?.call(MediaReference.t),
      orderByList: orderByList?.call(MediaReference.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [MediaReference].
  Future<MediaReference> deleteRow(
    _is.DatabaseSession session,
    MediaReference row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<MediaReference>(
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
  Future<List<MediaReference>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<MediaReferenceTable> where,
    _is.OrderByBuilder<MediaReferenceTable>? orderBy,
    _is.OrderByListBuilder<MediaReferenceTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<MediaReference>(
      where: where(MediaReference.t),
      orderBy: orderBy?.call(MediaReference.t),
      orderByList: orderByList?.call(MediaReference.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MediaReferenceTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<MediaReference>(
      where: where?.call(MediaReference.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [MediaReference] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<MediaReferenceTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<MediaReference>(
      where: where(MediaReference.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
