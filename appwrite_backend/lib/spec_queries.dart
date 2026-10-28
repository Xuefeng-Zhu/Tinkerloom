part of 'service.dart';

class _SpecQueryData {
  const _SpecQueryData(
    this.version,
    this.collection,
    this.query,
    this.records,
    this.values,
  );
  final _SpecVersion version;
  final spec.CollectionSpec collection;
  final spec.RecordQuery query;
  final List<Row> records;
  final Map<String, Row> values;
}

extension _SpecQueries on PlatformService {
  Future<List<Row>> _scanSpecRows(
    String table,
    Map<String, String> filters,
    String tx, {
    List<String>? select,
  }) async {
    final result = <Row>[];
    String? cursor;
    while (true) {
      final page = await store.list(
        table,
        filters,
        transactionId: tx,
        limit: 100,
        afterId: cursor,
        detectOverflow: false,
        select: select,
      );
      result.addAll(page);
      if (page.length < 100) return result;
      final next = page.last[r'$id'] as String;
      if (next == cursor) throw const ServiceException('integrity_error', 500);
      cursor = next;
    }
  }

  Object? _projectionValue(spec.FieldSpec field, Row row) {
    if (row['present'] != true) return null;
    final Object? raw = switch (field.type) {
      spec.FieldType.integer || spec.FieldType.number => row['numberValue'],
      spec.FieldType.boolean => row['boolValue'],
      spec.FieldType.timestamp => row['timestampValue'],
      _ => row['textValue'],
    };
    if (raw == null) throw const ServiceException('integrity_error', 500);
    if (field.type == spec.FieldType.integer &&
        raw is num &&
        raw.isFinite &&
        raw == raw.toInt())
      return field.normalize(raw.toInt());
    return field.normalize(raw);
  }

  int _compareSpecValue(spec.FieldSpec field, Object a, Object b) {
    if (field.type == spec.FieldType.timestamp)
      return DateTime.parse(a as String).compareTo(DateTime.parse(b as String));
    if (a is num && b is num) return a.compareTo(b);
    if (a is bool && b is bool) return a == b ? 0 : (a ? 1 : -1);
    return (a as String).compareTo(b as String);
  }

  bool _matchesSpecFilters(
    spec.CollectionSpec collection,
    Row values,
    List<Row> filters,
  ) {
    for (final filter in filters) {
      final field = collection.field(filter['fieldId'] as String);
      final actual = values[field.id], expected = filter['value'];
      final op = filter['operator'];
      if (op == 'eq') {
        if (actual != expected) return false;
        continue;
      }
      if (actual == null) return false;
      if (op == 'in') {
        if (!(expected as List).contains(actual)) return false;
        continue;
      }
      if (op == 'contains') {
        if (!(actual as String).toLowerCase().contains(
          (expected as String).toLowerCase(),
        ))
          return false;
        continue;
      }
      final comparison = _compareSpecValue(field, actual, expected as Object);
      if ((op == 'gte' && comparison < 0) ||
          (op == 'lte' && comparison > 0) ||
          (op == 'lt' && comparison >= 0))
        return false;
    }
    return true;
  }

  Future<_SpecQueryData> _specQueryData(
    AppAccess access,
    Row input,
    String tx, {
    Set<String> extraFields = const {},
  }) async {
    final version = await _activeSpec(
      access,
      tx,
      expected: _validId(input['versionId']),
    );
    final collection = version.definition.collection(
      spec.stableId(input['collectionId']),
    );
    final queryInput = jsonObject(input['query'], 'invalid_query');
    if (utf8.encode(jsonEncode(queryInput)).length > 16384)
      throw const ServiceException('invalid_query', 400);
    final query = spec.RecordQuery.parse(collection, queryInput);
    final rows = await _scanSpecRows(
      'spec_records',
      {'appId': access.app[r'$id'] as String, 'collectionId': collection.id},
      tx,
      select: [
        r'$id',
        'workspaceId',
        'appId',
        'collectionId',
        'revision',
        'writtenUnderVersionId',
        'deleted',
      ],
    );
    final live = <Row>[];
    final values = <String, Row>{};
    for (final record in rows) {
      if (record['workspaceId'] != access.app['workspaceId'] ||
          record['appId'] != access.app[r'$id'] ||
          record['collectionId'] != collection.id)
        throw const ServiceException('integrity_error', 500);
      if (record['deleted'] != false) continue;
      live.add(record);
      values[record[r'$id'] as String] = {};
    }
    final fields = <String>{
      ...query.filters.map((filter) => filter['fieldId'] as String),
      ...query.sort.map((sort) => sort['fieldId'] as String),
      ...extraFields,
    };
    for (final fieldId in fields) {
      final field = collection.field(fieldId);
      final projections = await _scanSpecRows('spec_values', {
        'appId': access.app[r'$id'] as String,
        'collectionId': collection.id,
        'fieldId': fieldId,
      }, tx);
      for (final row in projections) {
        if (row['workspaceId'] != access.app['workspaceId'] ||
            row['appId'] != access.app[r'$id'] ||
            row['collectionId'] != collection.id ||
            row['fieldId'] != fieldId)
          throw const ServiceException('integrity_error', 500);
        final data = values[row['recordId']];
        if (data == null) continue;
        if (data.containsKey(fieldId))
          throw const ServiceException('integrity_error', 500);
        data[fieldId] = _projectionValue(field, row);
      }
    }
    final matching = live
        .where(
          (record) => _matchesSpecFilters(
            collection,
            values[record[r'$id']]!,
            query.filters,
          ),
        )
        .toList();
    matching.sort((a, b) {
      for (final order in query.sort) {
        final field = collection.field(order['fieldId'] as String);
        final av = values[a[r'$id']]![field.id],
            bv = values[b[r'$id']]![field.id];
        if (av == null || bv == null) {
          if (av == bv) continue;
          return av == null ? 1 : -1; // NULLS LAST even for descending order.
        }
        var comparison = _compareSpecValue(field, av, bv);
        if (order['descending'] == true) comparison = -comparison;
        if (comparison != 0) return comparison;
      }
      return (a[r'$id'] as String).compareTo(b[r'$id'] as String);
    });
    return _SpecQueryData(version, collection, query, matching, values);
  }

  Future<Row> _specQuery(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'versionId', 'collectionId', 'query'});
    return _specRead(actor, _validId(input['appId']), (access, tx) async {
      final data = await _specQueryData(access, input, tx);
      final fingerprint = spec.hashJson({
        'app': access.app[r'$id'],
        'version': data.version.row[r'$id'],
        'collection': data.collection.id,
        'filters': data.query.filters,
        'sort': data.query.sort,
      });
      var start = 0;
      if (data.query.cursor != null) {
        Row cursor;
        try {
          cursor = jsonObject(
            jsonDecode(utf8.decode(base64Url.decode(data.query.cursor!))),
            'invalid_request',
          );
          if (cursor.keys.toSet().difference({'hash', 'id'}).isNotEmpty ||
              cursor['hash'] != fingerprint)
            throw const FormatException();
          _validId(cursor['id']);
        } catch (_) {
          throw const ServiceException('invalid_request', 400);
        }
        final anchor = data.records.indexWhere(
          (record) => record[r'$id'] == cursor['id'],
        );
        if (anchor < 0) throw const ServiceException('revision_conflict', 409);
        start = anchor + 1;
      }
      final selected = data.records.skip(start).take(data.query.limit).toList();
      final records = <Row>[];
      for (final metadata in selected) {
        final record = await _specRecord(
          access,
          metadata[r'$id'] as String,
          tx,
        );
        records.add(
          await _specRecordDto(
            actor,
            access,
            data.version.definition,
            record,
            tx,
          ),
        );
      }
      return {
        'records': records,
        'total': data.records.length,
        'versionId': data.version.row[r'$id'],
        'nextCursor': start + selected.length < data.records.length
            ? base64Url.encode(
                utf8.encode(
                  jsonEncode({
                    'hash': fingerprint,
                    'id': selected.last[r'$id'],
                  }),
                ),
              )
            : null,
      };
    });
  }

  Future<Row> _specSummary(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'versionId',
      'collectionId',
      'query',
      'groupFieldId',
    });
    final group = spec.stableId(input['groupFieldId']);
    return _specRead(actor, _validId(input['appId']), (access, tx) async {
      final data = await _specQueryData(
        access,
        input,
        tx,
        extraFields: {group},
      );
      final field = data.collection.field(group);
      if (field.type != spec.FieldType.choice)
        throw const ServiceException('invalid_query', 400);
      final groups = <String, int>{
        for (final choice in field.choices) choice: 0,
      };
      for (final row in data.records) {
        final value = data.values[row[r'$id']]![group];
        if (value != null) groups[value as String] = (groups[value] ?? 0) + 1;
      }
      return {
        'total': data.records.length,
        'groups': groups,
        'versionId': data.version.row[r'$id'],
      };
    });
  }

  Object? _metricValue(
    spec.AggregateQuery aggregate,
    List<Row> rows,
    Map<String, Row> values,
  ) {
    if (aggregate.metric == 'count') return rows.length;
    final numbers = rows
        .map((row) => values[row[r'$id']]![aggregate.fieldId])
        .whereType<num>()
        .toList();
    if (numbers.isEmpty) return aggregate.metric == 'average' ? null : 0;
    final sum = numbers.fold<num>(0, (total, value) => total + value);
    if (!sum.isFinite) throw const ServiceException('aggregate_overflow', 409);
    return aggregate.metric == 'average' ? sum / numbers.length : sum;
  }

  Future<Row> _specAggregate(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'versionId',
      'collectionId',
      'query',
      'aggregate',
    });
    return _specRead(actor, _validId(input['appId']), (access, tx) async {
      final version = await _activeSpec(
        access,
        tx,
        expected: _validId(input['versionId']),
      );
      final collection = version.definition.collection(
        spec.stableId(input['collectionId']),
      );
      final raw = jsonObject(input['aggregate'], 'invalid_query');
      if (utf8.encode(jsonEncode(raw)).length > 65536)
        throw const ServiceException('invalid_query', 400);
      final aggregate = spec.AggregateQuery.parse(collection, raw);
      final data = await _specQueryData(
        access,
        input,
        tx,
        extraFields: {
          if (aggregate.fieldId != null) aggregate.fieldId!,
          if (aggregate.groupFieldId != null) aggregate.groupFieldId!,
          if (aggregate.dateFieldId != null) aggregate.dateFieldId!,
        },
      );
      final groups = <Row>[];
      if (aggregate.groupFieldId != null) {
        final field = collection.field(aggregate.groupFieldId!);
        final hasNull = data.records.any(
          (row) => data.values[row[r'$id']]![field.id] == null,
        );
        for (final key in <String?>[...field.choices, if (hasNull) null]) {
          final rows = data.records
              .where((row) => data.values[row[r'$id']]![field.id] == key)
              .toList();
          groups.add({
            'key': key ?? '',
            'count': rows.length,
            'value': _metricValue(aggregate, rows, data.values),
          });
        }
      } else if (aggregate.dateFieldId != null) {
        for (final bucket in aggregate.buckets) {
          final start = DateTime.parse(bucket['start'] as String),
              end = DateTime.parse(bucket['end'] as String);
          final rows = data.records.where((row) {
            final value = data.values[row[r'$id']]![aggregate.dateFieldId];
            if (value == null) return false;
            final date = DateTime.parse(value as String);
            return !date.isBefore(start) && date.isBefore(end);
          }).toList();
          groups.add({
            'key': bucket['key'],
            'count': rows.length,
            'value': _metricValue(aggregate, rows, data.values),
          });
        }
      }
      return {
        'total': data.records.length,
        'value': _metricValue(aggregate, data.records, data.values),
        'groups': groups,
        'versionId': data.version.row[r'$id'],
      };
    });
  }
}
