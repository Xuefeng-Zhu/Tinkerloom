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

abstract class FieldValue
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  FieldValue._({
    this.id,
    required this.recordId,
    required this.appId,
    required this.collectionId,
    required this.fieldId,
    this.textValue,
    this.numberValue,
    this.boolValue,
    this.timestampValue,
  });

  factory FieldValue({
    int? id,
    required int recordId,
    required int appId,
    required String collectionId,
    required String fieldId,
    String? textValue,
    double? numberValue,
    bool? boolValue,
    DateTime? timestampValue,
  }) = _FieldValueImpl;

  factory FieldValue.fromJson(Map<String, dynamic> jsonSerialization) {
    return FieldValue(
      id: jsonSerialization['id'] as int?,
      recordId: jsonSerialization['recordId'] as int,
      appId: jsonSerialization['appId'] as int,
      collectionId: jsonSerialization['collectionId'] as String,
      fieldId: jsonSerialization['fieldId'] as String,
      textValue: jsonSerialization['textValue'] as String?,
      numberValue: (jsonSerialization['numberValue'] as num?)?.toDouble(),
      boolValue: jsonSerialization['boolValue'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['boolValue']),
      timestampValue: jsonSerialization['timestampValue'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(
              jsonSerialization['timestampValue'],
            ),
    );
  }

  static final t = FieldValueTable();

  static const db = FieldValueRepository._();

  @override
  int? id;

  int recordId;

  int appId;

  String collectionId;

  String fieldId;

  String? textValue;

  double? numberValue;

  bool? boolValue;

  DateTime? timestampValue;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [FieldValue]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  FieldValue copyWith({
    int? id,
    int? recordId,
    int? appId,
    String? collectionId,
    String? fieldId,
    String? textValue,
    double? numberValue,
    bool? boolValue,
    DateTime? timestampValue,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'FieldValue',
      if (id != null) 'id': id,
      'recordId': recordId,
      'appId': appId,
      'collectionId': collectionId,
      'fieldId': fieldId,
      if (textValue != null) 'textValue': textValue,
      if (numberValue != null) 'numberValue': numberValue,
      if (boolValue != null) 'boolValue': boolValue,
      if (timestampValue != null) 'timestampValue': timestampValue?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static FieldValueInclude include() {
    return FieldValueInclude._();
  }

  static FieldValueIncludeList includeList({
    _is.WhereExpressionBuilder<FieldValueTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<FieldValueTable>? orderBy,
    _is.OrderByListBuilder<FieldValueTable>? orderByList,
    FieldValueInclude? include,
  }) {
    return FieldValueIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(FieldValue.t),
      orderByList: orderByList?.call(FieldValue.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _FieldValueImpl extends FieldValue {
  _FieldValueImpl({
    int? id,
    required int recordId,
    required int appId,
    required String collectionId,
    required String fieldId,
    String? textValue,
    double? numberValue,
    bool? boolValue,
    DateTime? timestampValue,
  }) : super._(
         id: id,
         recordId: recordId,
         appId: appId,
         collectionId: collectionId,
         fieldId: fieldId,
         textValue: textValue,
         numberValue: numberValue,
         boolValue: boolValue,
         timestampValue: timestampValue,
       );

  /// Returns a shallow copy of this [FieldValue]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  FieldValue copyWith({
    Object? id = _Undefined,
    int? recordId,
    int? appId,
    String? collectionId,
    String? fieldId,
    Object? textValue = _Undefined,
    Object? numberValue = _Undefined,
    Object? boolValue = _Undefined,
    Object? timestampValue = _Undefined,
  }) {
    return FieldValue(
      id: id is int? ? id : this.id,
      recordId: recordId ?? this.recordId,
      appId: appId ?? this.appId,
      collectionId: collectionId ?? this.collectionId,
      fieldId: fieldId ?? this.fieldId,
      textValue: textValue is String? ? textValue : this.textValue,
      numberValue: numberValue is double? ? numberValue : this.numberValue,
      boolValue: boolValue is bool? ? boolValue : this.boolValue,
      timestampValue: timestampValue is DateTime?
          ? timestampValue
          : this.timestampValue,
    );
  }
}

class FieldValueUpdateTable extends _is.UpdateTable<FieldValueTable> {
  FieldValueUpdateTable(super.table);

  _is.ColumnValue<int, int> recordId(int value) => _is.ColumnValue(
    table.recordId,
    value,
  );

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<String, String> collectionId(String value) => _is.ColumnValue(
    table.collectionId,
    value,
  );

  _is.ColumnValue<String, String> fieldId(String value) => _is.ColumnValue(
    table.fieldId,
    value,
  );

  _is.ColumnValue<String, String> textValue(String? value) => _is.ColumnValue(
    table.textValue,
    value,
  );

  _is.ColumnValue<double, double> numberValue(double? value) => _is.ColumnValue(
    table.numberValue,
    value,
  );

  _is.ColumnValue<bool, bool> boolValue(bool? value) => _is.ColumnValue(
    table.boolValue,
    value,
  );

  _is.ColumnValue<DateTime, DateTime> timestampValue(DateTime? value) =>
      _is.ColumnValue(
        table.timestampValue,
        value,
      );
}

class FieldValueTable extends _is.Table<int?> {
  FieldValueTable({super.tableRelation})
    : super(tableName: 'nest_field_value') {
    updateTable = FieldValueUpdateTable(this);
    recordId = _is.ColumnInt(
      'recordId',
      this,
    );
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    collectionId = _is.ColumnString(
      'collectionId',
      this,
    );
    fieldId = _is.ColumnString(
      'fieldId',
      this,
    );
    textValue = _is.ColumnString(
      'textValue',
      this,
    );
    numberValue = _is.ColumnDouble(
      'numberValue',
      this,
    );
    boolValue = _is.ColumnBool(
      'boolValue',
      this,
    );
    timestampValue = _is.ColumnDateTime(
      'timestampValue',
      this,
    );
  }

  late final FieldValueUpdateTable updateTable;

  late final _is.ColumnInt recordId;

  late final _is.ColumnInt appId;

  late final _is.ColumnString collectionId;

  late final _is.ColumnString fieldId;

  late final _is.ColumnString textValue;

  late final _is.ColumnDouble numberValue;

  late final _is.ColumnBool boolValue;

  late final _is.ColumnDateTime timestampValue;

  @override
  List<_is.Column> get columns => [
    id,
    recordId,
    appId,
    collectionId,
    fieldId,
    textValue,
    numberValue,
    boolValue,
    timestampValue,
  ];
}

class FieldValueInclude extends _is.IncludeObject {
  FieldValueInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => FieldValue.t;
}

class FieldValueIncludeList extends _is.IncludeList {
  FieldValueIncludeList._({
    _is.WhereExpressionBuilder<FieldValueTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(FieldValue.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => FieldValue.t;
}

class FieldValueRepository {
  const FieldValueRepository._();

  /// Returns a list of [FieldValue]s matching the given query parameters.
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
  Future<List<FieldValue>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<FieldValueTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<FieldValueTable>? orderBy,
    _is.OrderByListBuilder<FieldValueTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<FieldValue>(
      where: where?.call(FieldValue.t),
      orderBy: orderBy?.call(FieldValue.t),
      orderByList: orderByList?.call(FieldValue.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [FieldValue] matching the given query parameters.
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
  Future<FieldValue?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<FieldValueTable>? where,
    int? offset,
    _is.OrderByBuilder<FieldValueTable>? orderBy,
    _is.OrderByListBuilder<FieldValueTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<FieldValue>(
      where: where?.call(FieldValue.t),
      orderBy: orderBy?.call(FieldValue.t),
      orderByList: orderByList?.call(FieldValue.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [FieldValue] by its [id] or null if no such row exists.
  Future<FieldValue?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<FieldValue>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [FieldValue]s in the list and returns the inserted rows.
  ///
  /// The returned [FieldValue]s will have their `id` fields set.
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
  Future<List<FieldValue>> insert(
    _is.DatabaseSession session,
    List<FieldValue> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<FieldValue>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [FieldValue] and returns the inserted row.
  ///
  /// The returned [FieldValue] will have its `id` field set.
  Future<FieldValue> insertRow(
    _is.DatabaseSession session,
    FieldValue row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<FieldValue>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [FieldValue]s in the list and returns the resulting rows.
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
  /// The returned [FieldValue]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<FieldValue>> upsert(
    _is.DatabaseSession session,
    List<FieldValue> rows, {
    required _is.ColumnSelections<FieldValueTable> conflictColumns,
    _is.ColumnSelections<FieldValueTable>? updateColumns,
    _is.WhereExpressionBuilder<FieldValueTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<FieldValue>(
      rows,
      conflictColumns: conflictColumns(FieldValue.t),
      updateColumns: updateColumns?.call(FieldValue.t),
      updateWhere: updateWhere?.call(FieldValue.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [FieldValue] and returns the resulting row.
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
  /// The returned [FieldValue] will have its `id` field set.
  Future<FieldValue?> upsertRow(
    _is.DatabaseSession session,
    FieldValue row, {
    required _is.ColumnSelections<FieldValueTable> conflictColumns,
    _is.ColumnSelections<FieldValueTable>? updateColumns,
    _is.WhereExpressionBuilder<FieldValueTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<FieldValue>(
      row,
      conflictColumns: conflictColumns(FieldValue.t),
      updateColumns: updateColumns?.call(FieldValue.t),
      updateWhere: updateWhere?.call(FieldValue.t),
      transaction: transaction,
    );
  }

  /// Updates all [FieldValue]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<FieldValue>> update(
    _is.DatabaseSession session,
    List<FieldValue> rows, {
    _is.ColumnSelections<FieldValueTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<FieldValue>(
      rows,
      columns: columns?.call(FieldValue.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [FieldValue]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<FieldValue> updateRow(
    _is.DatabaseSession session,
    FieldValue row, {
    _is.ColumnSelections<FieldValueTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<FieldValue>(
      row,
      columns: columns?.call(FieldValue.t),
      transaction: transaction,
    );
  }

  /// Updates a single [FieldValue] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<FieldValue?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<FieldValueUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<FieldValue>(
      id,
      columnValues: columnValues(FieldValue.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [FieldValue]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<FieldValue>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<FieldValueUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<FieldValueTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<FieldValueTable>? orderBy,
    _is.OrderByListBuilder<FieldValueTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<FieldValue>(
      columnValues: columnValues(FieldValue.t.updateTable),
      where: where(FieldValue.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(FieldValue.t),
      orderByList: orderByList?.call(FieldValue.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [FieldValue]s in the list and returns the deleted rows.
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
  Future<List<FieldValue>> delete(
    _is.DatabaseSession session,
    List<FieldValue> rows, {
    _is.OrderByBuilder<FieldValueTable>? orderBy,
    _is.OrderByListBuilder<FieldValueTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<FieldValue>(
      rows,
      orderBy: orderBy?.call(FieldValue.t),
      orderByList: orderByList?.call(FieldValue.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [FieldValue].
  Future<FieldValue> deleteRow(
    _is.DatabaseSession session,
    FieldValue row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<FieldValue>(
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
  Future<List<FieldValue>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<FieldValueTable> where,
    _is.OrderByBuilder<FieldValueTable>? orderBy,
    _is.OrderByListBuilder<FieldValueTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<FieldValue>(
      where: where(FieldValue.t),
      orderBy: orderBy?.call(FieldValue.t),
      orderByList: orderByList?.call(FieldValue.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<FieldValueTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<FieldValue>(
      where: where?.call(FieldValue.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [FieldValue] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<FieldValueTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<FieldValue>(
      where: where(FieldValue.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
