import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';

import 'access.dart';
import 'queries.dart';

/// Database-wide aggregates use exactly the predicates used by record pages.
class Aggregates {
  static Future<String> aggregate(
    Session s,
    int appId,
    String collectionId,
    String queryJson,
    String aggregateJson,
  ) => validated(
    () => s.db.transaction((tx) async {
      final a = await access(s, appId, tx: tx, lock: true);
      final col = (await a.spec(s, tx: tx)).collection(collectionId);
      if (queryJson.length > 16384 || aggregateJson.length > 65536) {
        fail('invalidInput', 'Aggregate request is too large.');
      }
      final query = RecordQuery.parse(col, payload(jsonDecode(queryJson)));
      final aggregate = AggregateQuery.parse(
        col,
        payload(jsonDecode(aggregateJson)),
      );
      final params = <String, dynamic>{
        'app': appId,
        'collection': collectionId,
      };
      final where = Queries.compileFilters(col, query.filters, params);
      final joins = <String>[];
      if (aggregate.fieldId != null) {
        params['metricField'] = aggregate.fieldId;
        joins.add(
          'LEFT JOIN nest_field_value m ON m."recordId"=r.id AND m."fieldId"=@metricField',
        );
      }
      final metric = switch (aggregate.metric) {
        'count' => 'COUNT(*)',
        'sum' => 'COALESCE(SUM(m."numberValue"),0)',
        'average' => 'AVG(m."numberValue")',
        _ => throw const SpecException('Unsupported metric'),
      };
      final base =
          'FROM nest_record r ${joins.join(' ')} WHERE ${where.join(' AND ')}';
      final overall = (await s.db.unsafeQuery(
        'SELECT COUNT(*), $metric $base',
        parameters: QueryParameters.named(params),
        transaction: tx,
      )).single;
      final groups = <Map<String, dynamic>>[];
      if (aggregate.groupFieldId != null) {
        final field = col.field(aggregate.groupFieldId!);
        final rows = await s.db.unsafeQuery(
          'SELECT g."textValue", COUNT(*), $metric FROM nest_record r '
          '${joins.join(' ')} LEFT JOIN nest_field_value g ON g."recordId"=r.id AND g."fieldId"=@groupField '
          'WHERE ${where.join(' AND ')} GROUP BY g."textValue"',
          parameters: QueryParameters.named({
            ...params,
            'groupField': field.id,
          }),
          transaction: tx,
        );
        final byKey = {for (final row in rows) row[0] as String?: row};
        for (final key in <String?>[
          ...field.choices,
          if (byKey.containsKey(null)) null,
        ]) {
          final row = byKey[key];
          groups.add({
            'key': key ?? '',
            'count': row?[1] ?? 0,
            'value': row == null
                ? (aggregate.metric == 'average' ? null : 0)
                : row[2],
          });
        }
      } else if (aggregate.dateFieldId != null) {
        // Bounded explicit UTC ranges preserve each client's local-day/DST boundaries.
        // One query, rather than one database round trip per bucket.
        final bucketParams = <String, dynamic>{
          ...params,
          'dateField': aggregate.dateFieldId,
        };
        final values = <String>[];
        for (var i = 0; i < aggregate.buckets.length; i++) {
          final bucket = aggregate.buckets[i];
          bucketParams['key$i'] = bucket['key'];
          bucketParams['start$i'] = DateTime.parse(bucket['start'] as String);
          bucketParams['end$i'] = DateTime.parse(bucket['end'] as String);
          values.add(
            '(@key$i::text,@start$i::timestamptz,@end$i::timestamptz,$i)',
          );
        }
        final numeric = aggregate.fieldId == null
            ? 'NULL::double precision'
            : 'm."numberValue"';
        final bucketMetric = switch (aggregate.metric) {
          'count' => 'COUNT(f.id)',
          'sum' => 'COALESCE(SUM(f.metric),0)',
          _ => 'AVG(f.metric)',
        };
        final rows = await s.db.unsafeQuery(
          'WITH buckets(key,start_at,end_at,position) AS (VALUES ${values.join(',')}), '
          'filtered AS (SELECT r.id, d."timestampValue" AS date, $numeric AS metric '
          'FROM nest_record r ${joins.join(' ')} '
          'JOIN nest_field_value d ON d."recordId"=r.id AND d."fieldId"=@dateField '
          'WHERE ${where.join(' AND ')}) '
          'SELECT b.key,COUNT(f.id),$bucketMetric FROM buckets b '
          'LEFT JOIN filtered f ON f.date>=b.start_at AND f.date<b.end_at '
          'GROUP BY b.key,b.position ORDER BY b.position',
          parameters: QueryParameters.named(bucketParams),
          transaction: tx,
        );
        groups.addAll(
          rows.map((r) => {'key': r[0], 'count': r[1], 'value': r[2]}),
        );
      }
      return jsonEncode({
        'total': overall[0],
        'value': overall[1],
        'groups': groups,
      });
    }),
  );
}
