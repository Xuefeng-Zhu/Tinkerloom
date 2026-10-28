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

abstract class Template
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  Template._({
    this.id,
    required this.key,
    required this.specJson,
    required this.description,
  });

  factory Template({
    int? id,
    required String key,
    required String specJson,
    required String description,
  }) = _TemplateImpl;

  factory Template.fromJson(Map<String, dynamic> jsonSerialization) {
    return Template(
      id: jsonSerialization['id'] as int?,
      key: jsonSerialization['key'] as String,
      specJson: jsonSerialization['specJson'] as String,
      description: jsonSerialization['description'] as String,
    );
  }

  static final t = TemplateTable();

  static const db = TemplateRepository._();

  @override
  int? id;

  String key;

  String specJson;

  String description;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [Template]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  Template copyWith({
    int? id,
    String? key,
    String? specJson,
    String? description,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Template',
      if (id != null) 'id': id,
      'key': key,
      'specJson': specJson,
      'description': description,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static TemplateInclude include() {
    return TemplateInclude._();
  }

  static TemplateIncludeList includeList({
    _is.WhereExpressionBuilder<TemplateTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<TemplateTable>? orderBy,
    _is.OrderByListBuilder<TemplateTable>? orderByList,
    TemplateInclude? include,
  }) {
    return TemplateIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Template.t),
      orderByList: orderByList?.call(Template.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _TemplateImpl extends Template {
  _TemplateImpl({
    int? id,
    required String key,
    required String specJson,
    required String description,
  }) : super._(
         id: id,
         key: key,
         specJson: specJson,
         description: description,
       );

  /// Returns a shallow copy of this [Template]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  Template copyWith({
    Object? id = _Undefined,
    String? key,
    String? specJson,
    String? description,
  }) {
    return Template(
      id: id is int? ? id : this.id,
      key: key ?? this.key,
      specJson: specJson ?? this.specJson,
      description: description ?? this.description,
    );
  }
}

class TemplateUpdateTable extends _is.UpdateTable<TemplateTable> {
  TemplateUpdateTable(super.table);

  _is.ColumnValue<String, String> key(String value) => _is.ColumnValue(
    table.key,
    value,
  );

  _is.ColumnValue<String, String> specJson(String value) => _is.ColumnValue(
    table.specJson,
    value,
  );

  _is.ColumnValue<String, String> description(String value) => _is.ColumnValue(
    table.description,
    value,
  );
}

class TemplateTable extends _is.Table<int?> {
  TemplateTable({super.tableRelation}) : super(tableName: 'nest_template') {
    updateTable = TemplateUpdateTable(this);
    key = _is.ColumnString(
      'key',
      this,
    );
    specJson = _is.ColumnString(
      'specJson',
      this,
    );
    description = _is.ColumnString(
      'description',
      this,
    );
  }

  late final TemplateUpdateTable updateTable;

  late final _is.ColumnString key;

  late final _is.ColumnString specJson;

  late final _is.ColumnString description;

  @override
  List<_is.Column> get columns => [
    id,
    key,
    specJson,
    description,
  ];
}

class TemplateInclude extends _is.IncludeObject {
  TemplateInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => Template.t;
}

class TemplateIncludeList extends _is.IncludeList {
  TemplateIncludeList._({
    _is.WhereExpressionBuilder<TemplateTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(Template.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => Template.t;
}

class TemplateRepository {
  const TemplateRepository._();

  /// Returns a list of [Template]s matching the given query parameters.
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
  Future<List<Template>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<TemplateTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<TemplateTable>? orderBy,
    _is.OrderByListBuilder<TemplateTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<Template>(
      where: where?.call(Template.t),
      orderBy: orderBy?.call(Template.t),
      orderByList: orderByList?.call(Template.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [Template] matching the given query parameters.
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
  Future<Template?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<TemplateTable>? where,
    int? offset,
    _is.OrderByBuilder<TemplateTable>? orderBy,
    _is.OrderByListBuilder<TemplateTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<Template>(
      where: where?.call(Template.t),
      orderBy: orderBy?.call(Template.t),
      orderByList: orderByList?.call(Template.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [Template] by its [id] or null if no such row exists.
  Future<Template?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<Template>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [Template]s in the list and returns the inserted rows.
  ///
  /// The returned [Template]s will have their `id` fields set.
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
  Future<List<Template>> insert(
    _is.DatabaseSession session,
    List<Template> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<Template>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [Template] and returns the inserted row.
  ///
  /// The returned [Template] will have its `id` field set.
  Future<Template> insertRow(
    _is.DatabaseSession session,
    Template row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<Template>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [Template]s in the list and returns the resulting rows.
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
  /// The returned [Template]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Template>> upsert(
    _is.DatabaseSession session,
    List<Template> rows, {
    required _is.ColumnSelections<TemplateTable> conflictColumns,
    _is.ColumnSelections<TemplateTable>? updateColumns,
    _is.WhereExpressionBuilder<TemplateTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<Template>(
      rows,
      conflictColumns: conflictColumns(Template.t),
      updateColumns: updateColumns?.call(Template.t),
      updateWhere: updateWhere?.call(Template.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [Template] and returns the resulting row.
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
  /// The returned [Template] will have its `id` field set.
  Future<Template?> upsertRow(
    _is.DatabaseSession session,
    Template row, {
    required _is.ColumnSelections<TemplateTable> conflictColumns,
    _is.ColumnSelections<TemplateTable>? updateColumns,
    _is.WhereExpressionBuilder<TemplateTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<Template>(
      row,
      conflictColumns: conflictColumns(Template.t),
      updateColumns: updateColumns?.call(Template.t),
      updateWhere: updateWhere?.call(Template.t),
      transaction: transaction,
    );
  }

  /// Updates all [Template]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Template>> update(
    _is.DatabaseSession session,
    List<Template> rows, {
    _is.ColumnSelections<TemplateTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<Template>(
      rows,
      columns: columns?.call(Template.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [Template]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<Template> updateRow(
    _is.DatabaseSession session,
    Template row, {
    _is.ColumnSelections<TemplateTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<Template>(
      row,
      columns: columns?.call(Template.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Template] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<Template?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<TemplateUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<Template>(
      id,
      columnValues: columnValues(Template.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [Template]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Template>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<TemplateUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<TemplateTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<TemplateTable>? orderBy,
    _is.OrderByListBuilder<TemplateTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<Template>(
      columnValues: columnValues(Template.t.updateTable),
      where: where(Template.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Template.t),
      orderByList: orderByList?.call(Template.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [Template]s in the list and returns the deleted rows.
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
  Future<List<Template>> delete(
    _is.DatabaseSession session,
    List<Template> rows, {
    _is.OrderByBuilder<TemplateTable>? orderBy,
    _is.OrderByListBuilder<TemplateTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<Template>(
      rows,
      orderBy: orderBy?.call(Template.t),
      orderByList: orderByList?.call(Template.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [Template].
  Future<Template> deleteRow(
    _is.DatabaseSession session,
    Template row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<Template>(
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
  Future<List<Template>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<TemplateTable> where,
    _is.OrderByBuilder<TemplateTable>? orderBy,
    _is.OrderByListBuilder<TemplateTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<Template>(
      where: where(Template.t),
      orderBy: orderBy?.call(Template.t),
      orderByList: orderByList?.call(Template.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<TemplateTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<Template>(
      where: where?.call(Template.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [Template] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<TemplateTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<Template>(
      where: where(Template.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
