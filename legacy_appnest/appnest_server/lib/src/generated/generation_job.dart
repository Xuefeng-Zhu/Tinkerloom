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

abstract class GenerationJob
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  GenerationJob._({
    this.id,
    required this.appId,
    required this.draftId,
    required this.actorId,
    required this.mutation,
    required this.status,
    required this.requestText,
    required this.mode,
    this.provider,
    this.model,
    required this.promptVersion,
    int? attempts,
    int? leaseGeneration,
    this.leaseUntil,
    required this.nextAttemptAt,
    required this.diagnostics,
    required this.usageJson,
    required this.createdAt,
    required this.updatedAt,
  }) : attempts = attempts ?? 0,
       leaseGeneration = leaseGeneration ?? 0;

  factory GenerationJob({
    int? id,
    required int appId,
    required int draftId,
    required String actorId,
    required int mutation,
    required String status,
    required String requestText,
    required String mode,
    String? provider,
    String? model,
    required String promptVersion,
    int? attempts,
    int? leaseGeneration,
    DateTime? leaseUntil,
    required DateTime nextAttemptAt,
    required String diagnostics,
    required String usageJson,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _GenerationJobImpl;

  factory GenerationJob.fromJson(Map<String, dynamic> jsonSerialization) {
    return GenerationJob(
      id: jsonSerialization['id'] as int?,
      appId: jsonSerialization['appId'] as int,
      draftId: jsonSerialization['draftId'] as int,
      actorId: jsonSerialization['actorId'] as String,
      mutation: jsonSerialization['mutation'] as int,
      status: jsonSerialization['status'] as String,
      requestText: jsonSerialization['requestText'] as String,
      mode: jsonSerialization['mode'] as String,
      provider: jsonSerialization['provider'] as String?,
      model: jsonSerialization['model'] as String?,
      promptVersion: jsonSerialization['promptVersion'] as String,
      attempts: jsonSerialization['attempts'] as int?,
      leaseGeneration: jsonSerialization['leaseGeneration'] as int?,
      leaseUntil: jsonSerialization['leaseUntil'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(jsonSerialization['leaseUntil']),
      nextAttemptAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['nextAttemptAt'],
      ),
      diagnostics: jsonSerialization['diagnostics'] as String,
      usageJson: jsonSerialization['usageJson'] as String,
      createdAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      updatedAt: _is.DateTimeJsonExtension.fromJson(
        jsonSerialization['updatedAt'],
      ),
    );
  }

  static final t = GenerationJobTable();

  static const db = GenerationJobRepository._();

  @override
  int? id;

  int appId;

  int draftId;

  String actorId;

  int mutation;

  String status;

  String requestText;

  String mode;

  String? provider;

  String? model;

  String promptVersion;

  int attempts;

  int leaseGeneration;

  DateTime? leaseUntil;

  DateTime nextAttemptAt;

  String diagnostics;

  String usageJson;

  DateTime createdAt;

  DateTime updatedAt;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [GenerationJob]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  GenerationJob copyWith({
    int? id,
    int? appId,
    int? draftId,
    String? actorId,
    int? mutation,
    String? status,
    String? requestText,
    String? mode,
    String? provider,
    String? model,
    String? promptVersion,
    int? attempts,
    int? leaseGeneration,
    DateTime? leaseUntil,
    DateTime? nextAttemptAt,
    String? diagnostics,
    String? usageJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'GenerationJob',
      if (id != null) 'id': id,
      'appId': appId,
      'draftId': draftId,
      'actorId': actorId,
      'mutation': mutation,
      'status': status,
      'requestText': requestText,
      'mode': mode,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      'promptVersion': promptVersion,
      'attempts': attempts,
      'leaseGeneration': leaseGeneration,
      if (leaseUntil != null) 'leaseUntil': leaseUntil?.toJson(),
      'nextAttemptAt': nextAttemptAt.toJson(),
      'diagnostics': diagnostics,
      'usageJson': usageJson,
      'createdAt': createdAt.toJson(),
      'updatedAt': updatedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  static GenerationJobInclude include() {
    return GenerationJobInclude._();
  }

  static GenerationJobIncludeList includeList({
    _is.WhereExpressionBuilder<GenerationJobTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<GenerationJobTable>? orderBy,
    _is.OrderByListBuilder<GenerationJobTable>? orderByList,
    GenerationJobInclude? include,
  }) {
    return GenerationJobIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(GenerationJob.t),
      orderByList: orderByList?.call(GenerationJob.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _GenerationJobImpl extends GenerationJob {
  _GenerationJobImpl({
    int? id,
    required int appId,
    required int draftId,
    required String actorId,
    required int mutation,
    required String status,
    required String requestText,
    required String mode,
    String? provider,
    String? model,
    required String promptVersion,
    int? attempts,
    int? leaseGeneration,
    DateTime? leaseUntil,
    required DateTime nextAttemptAt,
    required String diagnostics,
    required String usageJson,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : super._(
         id: id,
         appId: appId,
         draftId: draftId,
         actorId: actorId,
         mutation: mutation,
         status: status,
         requestText: requestText,
         mode: mode,
         provider: provider,
         model: model,
         promptVersion: promptVersion,
         attempts: attempts,
         leaseGeneration: leaseGeneration,
         leaseUntil: leaseUntil,
         nextAttemptAt: nextAttemptAt,
         diagnostics: diagnostics,
         usageJson: usageJson,
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [GenerationJob]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  GenerationJob copyWith({
    Object? id = _Undefined,
    int? appId,
    int? draftId,
    String? actorId,
    int? mutation,
    String? status,
    String? requestText,
    String? mode,
    Object? provider = _Undefined,
    Object? model = _Undefined,
    String? promptVersion,
    int? attempts,
    int? leaseGeneration,
    Object? leaseUntil = _Undefined,
    DateTime? nextAttemptAt,
    String? diagnostics,
    String? usageJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GenerationJob(
      id: id is int? ? id : this.id,
      appId: appId ?? this.appId,
      draftId: draftId ?? this.draftId,
      actorId: actorId ?? this.actorId,
      mutation: mutation ?? this.mutation,
      status: status ?? this.status,
      requestText: requestText ?? this.requestText,
      mode: mode ?? this.mode,
      provider: provider is String? ? provider : this.provider,
      model: model is String? ? model : this.model,
      promptVersion: promptVersion ?? this.promptVersion,
      attempts: attempts ?? this.attempts,
      leaseGeneration: leaseGeneration ?? this.leaseGeneration,
      leaseUntil: leaseUntil is DateTime? ? leaseUntil : this.leaseUntil,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      diagnostics: diagnostics ?? this.diagnostics,
      usageJson: usageJson ?? this.usageJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class GenerationJobUpdateTable extends _is.UpdateTable<GenerationJobTable> {
  GenerationJobUpdateTable(super.table);

  _is.ColumnValue<int, int> appId(int value) => _is.ColumnValue(
    table.appId,
    value,
  );

  _is.ColumnValue<int, int> draftId(int value) => _is.ColumnValue(
    table.draftId,
    value,
  );

  _is.ColumnValue<String, String> actorId(String value) => _is.ColumnValue(
    table.actorId,
    value,
  );

  _is.ColumnValue<int, int> mutation(int value) => _is.ColumnValue(
    table.mutation,
    value,
  );

  _is.ColumnValue<String, String> status(String value) => _is.ColumnValue(
    table.status,
    value,
  );

  _is.ColumnValue<String, String> requestText(String value) => _is.ColumnValue(
    table.requestText,
    value,
  );

  _is.ColumnValue<String, String> mode(String value) => _is.ColumnValue(
    table.mode,
    value,
  );

  _is.ColumnValue<String, String> provider(String? value) => _is.ColumnValue(
    table.provider,
    value,
  );

  _is.ColumnValue<String, String> model(String? value) => _is.ColumnValue(
    table.model,
    value,
  );

  _is.ColumnValue<String, String> promptVersion(String value) =>
      _is.ColumnValue(
        table.promptVersion,
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

  _is.ColumnValue<DateTime, DateTime> nextAttemptAt(DateTime value) =>
      _is.ColumnValue(
        table.nextAttemptAt,
        value,
      );

  _is.ColumnValue<String, String> diagnostics(String value) => _is.ColumnValue(
    table.diagnostics,
    value,
  );

  _is.ColumnValue<String, String> usageJson(String value) => _is.ColumnValue(
    table.usageJson,
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
}

class GenerationJobTable extends _is.Table<int?> {
  GenerationJobTable({super.tableRelation})
    : super(tableName: 'nest_generation') {
    updateTable = GenerationJobUpdateTable(this);
    appId = _is.ColumnInt(
      'appId',
      this,
    );
    draftId = _is.ColumnInt(
      'draftId',
      this,
    );
    actorId = _is.ColumnString(
      'actorId',
      this,
    );
    mutation = _is.ColumnInt(
      'mutation',
      this,
    );
    status = _is.ColumnString(
      'status',
      this,
    );
    requestText = _is.ColumnString(
      'requestText',
      this,
    );
    mode = _is.ColumnString(
      'mode',
      this,
    );
    provider = _is.ColumnString(
      'provider',
      this,
    );
    model = _is.ColumnString(
      'model',
      this,
    );
    promptVersion = _is.ColumnString(
      'promptVersion',
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
    nextAttemptAt = _is.ColumnDateTime(
      'nextAttemptAt',
      this,
    );
    diagnostics = _is.ColumnString(
      'diagnostics',
      this,
    );
    usageJson = _is.ColumnString(
      'usageJson',
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
  }

  late final GenerationJobUpdateTable updateTable;

  late final _is.ColumnInt appId;

  late final _is.ColumnInt draftId;

  late final _is.ColumnString actorId;

  late final _is.ColumnInt mutation;

  late final _is.ColumnString status;

  late final _is.ColumnString requestText;

  late final _is.ColumnString mode;

  late final _is.ColumnString provider;

  late final _is.ColumnString model;

  late final _is.ColumnString promptVersion;

  late final _is.ColumnInt attempts;

  late final _is.ColumnInt leaseGeneration;

  late final _is.ColumnDateTime leaseUntil;

  late final _is.ColumnDateTime nextAttemptAt;

  late final _is.ColumnString diagnostics;

  late final _is.ColumnString usageJson;

  late final _is.ColumnDateTime createdAt;

  late final _is.ColumnDateTime updatedAt;

  @override
  List<_is.Column> get columns => [
    id,
    appId,
    draftId,
    actorId,
    mutation,
    status,
    requestText,
    mode,
    provider,
    model,
    promptVersion,
    attempts,
    leaseGeneration,
    leaseUntil,
    nextAttemptAt,
    diagnostics,
    usageJson,
    createdAt,
    updatedAt,
  ];
}

class GenerationJobInclude extends _is.IncludeObject {
  GenerationJobInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => GenerationJob.t;
}

class GenerationJobIncludeList extends _is.IncludeList {
  GenerationJobIncludeList._({
    _is.WhereExpressionBuilder<GenerationJobTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(GenerationJob.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => GenerationJob.t;
}

class GenerationJobRepository {
  const GenerationJobRepository._();

  /// Returns a list of [GenerationJob]s matching the given query parameters.
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
  Future<List<GenerationJob>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<GenerationJobTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<GenerationJobTable>? orderBy,
    _is.OrderByListBuilder<GenerationJobTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<GenerationJob>(
      where: where?.call(GenerationJob.t),
      orderBy: orderBy?.call(GenerationJob.t),
      orderByList: orderByList?.call(GenerationJob.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [GenerationJob] matching the given query parameters.
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
  Future<GenerationJob?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<GenerationJobTable>? where,
    int? offset,
    _is.OrderByBuilder<GenerationJobTable>? orderBy,
    _is.OrderByListBuilder<GenerationJobTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<GenerationJob>(
      where: where?.call(GenerationJob.t),
      orderBy: orderBy?.call(GenerationJob.t),
      orderByList: orderByList?.call(GenerationJob.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [GenerationJob] by its [id] or null if no such row exists.
  Future<GenerationJob?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<GenerationJob>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [GenerationJob]s in the list and returns the inserted rows.
  ///
  /// The returned [GenerationJob]s will have their `id` fields set.
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
  Future<List<GenerationJob>> insert(
    _is.DatabaseSession session,
    List<GenerationJob> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<GenerationJob>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [GenerationJob] and returns the inserted row.
  ///
  /// The returned [GenerationJob] will have its `id` field set.
  Future<GenerationJob> insertRow(
    _is.DatabaseSession session,
    GenerationJob row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<GenerationJob>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [GenerationJob]s in the list and returns the resulting rows.
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
  /// The returned [GenerationJob]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GenerationJob>> upsert(
    _is.DatabaseSession session,
    List<GenerationJob> rows, {
    required _is.ColumnSelections<GenerationJobTable> conflictColumns,
    _is.ColumnSelections<GenerationJobTable>? updateColumns,
    _is.WhereExpressionBuilder<GenerationJobTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<GenerationJob>(
      rows,
      conflictColumns: conflictColumns(GenerationJob.t),
      updateColumns: updateColumns?.call(GenerationJob.t),
      updateWhere: updateWhere?.call(GenerationJob.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [GenerationJob] and returns the resulting row.
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
  /// The returned [GenerationJob] will have its `id` field set.
  Future<GenerationJob?> upsertRow(
    _is.DatabaseSession session,
    GenerationJob row, {
    required _is.ColumnSelections<GenerationJobTable> conflictColumns,
    _is.ColumnSelections<GenerationJobTable>? updateColumns,
    _is.WhereExpressionBuilder<GenerationJobTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<GenerationJob>(
      row,
      conflictColumns: conflictColumns(GenerationJob.t),
      updateColumns: updateColumns?.call(GenerationJob.t),
      updateWhere: updateWhere?.call(GenerationJob.t),
      transaction: transaction,
    );
  }

  /// Updates all [GenerationJob]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GenerationJob>> update(
    _is.DatabaseSession session,
    List<GenerationJob> rows, {
    _is.ColumnSelections<GenerationJobTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<GenerationJob>(
      rows,
      columns: columns?.call(GenerationJob.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [GenerationJob]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<GenerationJob> updateRow(
    _is.DatabaseSession session,
    GenerationJob row, {
    _is.ColumnSelections<GenerationJobTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<GenerationJob>(
      row,
      columns: columns?.call(GenerationJob.t),
      transaction: transaction,
    );
  }

  /// Updates a single [GenerationJob] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<GenerationJob?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<GenerationJobUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<GenerationJob>(
      id,
      columnValues: columnValues(GenerationJob.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [GenerationJob]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<GenerationJob>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<GenerationJobUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<GenerationJobTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<GenerationJobTable>? orderBy,
    _is.OrderByListBuilder<GenerationJobTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<GenerationJob>(
      columnValues: columnValues(GenerationJob.t.updateTable),
      where: where(GenerationJob.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(GenerationJob.t),
      orderByList: orderByList?.call(GenerationJob.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [GenerationJob]s in the list and returns the deleted rows.
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
  Future<List<GenerationJob>> delete(
    _is.DatabaseSession session,
    List<GenerationJob> rows, {
    _is.OrderByBuilder<GenerationJobTable>? orderBy,
    _is.OrderByListBuilder<GenerationJobTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<GenerationJob>(
      rows,
      orderBy: orderBy?.call(GenerationJob.t),
      orderByList: orderByList?.call(GenerationJob.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [GenerationJob].
  Future<GenerationJob> deleteRow(
    _is.DatabaseSession session,
    GenerationJob row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<GenerationJob>(
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
  Future<List<GenerationJob>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<GenerationJobTable> where,
    _is.OrderByBuilder<GenerationJobTable>? orderBy,
    _is.OrderByListBuilder<GenerationJobTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<GenerationJob>(
      where: where(GenerationJob.t),
      orderBy: orderBy?.call(GenerationJob.t),
      orderByList: orderByList?.call(GenerationJob.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<GenerationJobTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<GenerationJob>(
      where: where?.call(GenerationJob.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [GenerationJob] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<GenerationJobTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<GenerationJob>(
      where: where(GenerationJob.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
