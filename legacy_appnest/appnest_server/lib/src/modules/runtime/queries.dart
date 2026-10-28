import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';

import '../../generated/protocol.dart';
import '../automation/worker.dart';
import 'access.dart';

class Queries {
  static String column(FieldType type) => switch (type) {
    FieldType.integer || FieldType.number => 'numberValue',
    FieldType.boolean => 'boolValue',
    FieldType.timestamp => 'timestampValue',
    _ => 'textValue',
  };
  static Object? value(FieldSpec f, Object? v) => v == null
      ? null
      : f.type == FieldType.timestamp
      ? DateTime.parse(f.normalize(v) as String)
      : f.normalize(v);

  /// Shared by pages and database-wide aggregates, after schema validation.
  static List<String> compileFilters(
    CollectionSpec col,
    List<Map<String, dynamic>> filters,
    Map<String, dynamic> params,
  ) {
    final where = <String>[
      'r."appId" = @app',
      'r."collectionId" = @collection',
      'NOT r.deleted',
    ];
    for (var i = 0; i < filters.length; i++) {
      final filter = filters[i],
          f = col.field(filter['fieldId'] as String),
          op = filter['operator'],
          ref = 'f$i',
          param = 'v$i';
      params['field$i'] = f.id;
      final expression = '$ref."${column(f.type)}"';
      String comparison;
      if (op == 'in') {
        final list = filter['value'] as List;
        final names = <String>[];
        for (var n = 0; n < list.length; n++) {
          params['${param}_$n'] = value(f, list[n]);
          names.add('@${param}_$n');
        }
        comparison = names.isEmpty
            ? 'FALSE'
            : '$expression IN (${names.join(',')})';
      } else if (filter['value'] == null) {
        if (op != 'eq') fail('invalidInput', 'Only equality supports null.');
        where.add(
          'NOT EXISTS (SELECT 1 FROM nest_field_value $ref WHERE $ref."recordId"=r.id AND $ref."fieldId"=@field$i)',
        );
        continue;
      } else {
        params[param] = value(f, filter['value']);
        comparison = switch (op) {
          'eq' => '$expression = @$param',
          'gte' => '$expression >= @$param',
          'lt' => '$expression < @$param',
          'lte' => '$expression <= @$param',
          'contains' => 'strpos(lower($expression), lower(@$param)) > 0',
          _ => throw const SpecException('Unsupported operator'),
        };
      }
      where.add(
        'EXISTS (SELECT 1 FROM nest_field_value $ref WHERE $ref."recordId"=r.id AND $ref."fieldId"=@field$i AND $comparison)',
      );
    }
    return where;
  }

  static Future<RecordPage> query(
    Session s,
    int appId,
    String collectionId,
    String queryJson,
  ) => validated(
    () => s.db.transaction((tx) async {
      final a = await access(s, appId, tx: tx, lock: true),
          spec = await a.spec(s, tx: tx),
          col = spec.collection(collectionId);
      if (queryJson.length > 16384) fail('invalidInput', 'Query is too large.');
      final input = payload(jsonDecode(queryJson)),
          q = RecordQuery.parse(col, input);
      final fingerprint = hashJson({
        'app': appId,
        'collection': collectionId,
        'filters': q.filters,
        'sort': q.sort,
      });
      int? after;
      if (q.cursor != null) {
        try {
          final c = payload(
            jsonDecode(utf8.decode(base64Url.decode(q.cursor!))),
          );
          if (c['hash'] != fingerprint || c['id'] is! int) {
            throw const FormatException();
          }
          after = c['id'] as int;
        } catch (_) {
          fail('invalidInput', 'Invalid cursor for this query.');
        }
      }
      final params = <String, dynamic>{
        'app': appId,
        'collection': collectionId,
        'limit': q.limit + 1,
      };
      final where = compileFilters(col, q.filters, params);
      final joins = <String>[], order = <String>[];
      for (var i = 0; i < q.sort.length; i++) {
        final sort = q.sort[i], f = col.field(sort['fieldId'] as String);
        params['sort$i'] = f.id;
        joins.add(
          'LEFT JOIN nest_field_value s$i ON s$i."recordId"=r.id AND s$i."fieldId"=@sort$i',
        );
        order.add(
          's$i."${column(f.type)}" ${sort['descending'] == true ? 'DESC' : 'ASC'} NULLS LAST',
        );
      }
      order.add('r.id ASC');
      final base =
          'FROM nest_record r ${joins.join(' ')} WHERE ${where.join(' AND ')}';
      final counts = await s.db.unsafeQuery(
        'SELECT COUNT(*) $base',
        parameters: QueryParameters.named(Map.from(params)..remove('limit')),
        transaction: tx,
      );
      final total = counts.first.first as int;
      if (after != null) {
        // Cursor must still identify a matching authorized record; never silently restart.
        final found = await s.db.unsafeQuery(
          'SELECT r.id $base AND r.id=@after',
          parameters: QueryParameters.named({
            ...params..remove('limit'),
            'after': after,
          }),
          transaction: tx,
        );
        if (found.isEmpty) {
          fail('recordConflict', 'The page changed. Refresh the list.');
        }
        params['limit'] = q.limit + 1;
        params['after'] = after;
      }
      final result = await s.db.unsafeQuery(
        'WITH ranked AS (SELECT r.id, row_number() OVER (ORDER BY ${order.join(',')}) AS position $base) SELECT id FROM ranked ${after == null ? '' : 'WHERE position > (SELECT position FROM ranked WHERE id=@after)'} ORDER BY position LIMIT @limit',
        parameters: QueryParameters.named(params),
        transaction: tx,
      );
      final ids = result.take(q.limit).map((r) => r.first as int).toList();
      final records = <RuntimeRecord>[];
      for (final id in ids) {
        records.add(
          await dto(s, a, spec, await record(s, a, id, tx: tx), tx: tx),
        );
      }
      return RecordPage(
        records: records,
        total: total,
        nextCursor: result.length > q.limit
            ? base64Url.encode(
                utf8.encode(jsonEncode({'hash': fingerprint, 'id': ids.last})),
              )
            : null,
      );
    }),
  );
  static Future<RecordSummary> summary(
    Session s,
    int appId,
    String collectionId,
    String queryJson,
    String groupFieldId,
  ) => validated(
    () => s.db.transaction((tx) async {
      final a = await access(s, appId, tx: tx, lock: true),
          spec = await a.spec(s, tx: tx),
          col = spec.collection(collectionId),
          field = col.field(groupFieldId);
      if (field.type != FieldType.choice) {
        fail('invalidInput', 'Summaries group by a choice field.');
      }
      if (queryJson.length > 16384) fail('invalidInput', 'Query is too large.');
      final q = RecordQuery.parse(col, payload(jsonDecode(queryJson)));
      final params = <String, dynamic>{
        'app': appId,
        'collection': collectionId,
        'groupField': groupFieldId,
      };
      final where = compileFilters(col, q.filters, params);
      // One grouped query also counts records without a value. Pagination and
      // sorting never narrow the aggregate, and the app lock serializes writes.
      final rows = await s.db.unsafeQuery(
        'SELECT g."textValue", COUNT(*) FROM nest_record r '
        'LEFT JOIN nest_field_value g ON g."recordId"=r.id AND g."fieldId"=@groupField '
        'WHERE ${where.join(' AND ')} GROUP BY g."textValue"',
        parameters: QueryParameters.named(params),
        transaction: tx,
      );
      var total = 0;
      final groups = <String, int>{
        for (final choice in field.choices) choice: 0,
      };
      for (final row in rows) {
        final count = row[1] as int;
        total += count;
        if (row[0] != null) groups[row[0] as String] = count;
      }
      return RecordSummary(total: total, groups: groups);
    }),
  );

  static Future<List<ReminderState>> reminderState(
    Session s,
    int appId,
    int id,
  ) => validated(
    () => s.db.transaction((tx) async {
      final a = await access(s, appId, tx: tx, lock: true),
          spec = await a.spec(s, tx: tx),
          row = await record(s, a, id, tx: tx),
          data = payload(row.data);
      final rules = await Automation.db.find(
        s,
        where: (t) => t.appId.equals(appId),
        transaction: tx,
      );
      final result = <ReminderState>[];
      for (final definition in spec.automationRequests.where(
        (rule) => rule.collectionId == row.collectionId,
      )) {
        final rule = rules.where((r) => r.ruleId == definition.id).firstOrNull,
            date = data[definition.fieldId] as String?;
        final due = date == null
            ? null
            : DateTime.parse(date).subtract(
                Duration(seconds: definition.offsetSeconds),
              );
        var state = date == null ? 'unset' : 'disabled';
        var eligible = false;
        if (Worker.remindersEnabled(s) &&
            date != null &&
            rule != null &&
            rule.enabled) {
          final signature = Worker.scheduleSignature(rule, date, due);
          final run = await AutomationRun.db.findFirstRow(
            s,
            where: (t) =>
                t.automationId.equals(rule.id!) &
                t.recordId.equals(id) &
                t.ruleVersion.equals(rule.ruleVersion) &
                t.scheduleSignature.equals(signature),
            transaction: tx,
          );
          eligible =
              !a.app.archived &&
              Worker.conditionMatches(definition, data) &&
              await Worker.hasAccess(
                s,
                a.app,
                rule.executionActorId,
                tx,
                builder: true,
              ) &&
              (definition.effect != 'notifyOwner' ||
                  await Worker.hasAccess(s, a.app, a.app.ownerId, tx));
          if (run != null) {
            state = switch (run.status) {
              'succeeded' => 'delivered',
              'suppressed' => 'suppressed',
              'failed' => 'failed',
              _ => 'pending',
            };
          } else {
            final enrolled = await Worker.isEnrolled(s, a.app, rule, row, tx);
            state = enrolled ? 'pending' : 'unenrolled';
          }
          if (a.app.archived && state == 'pending') state = 'suppressed';
        }
        result.add(
          ReminderState(
            ruleId: definition.id,
            state: state,
            scheduledAt: due,
            eligible: eligible,
          ),
        );
      }
      return result;
    }),
  );

  static Future<RuntimeRecord> get(Session s, int appId, int id) =>
      s.db.transaction((tx) async {
        final a = await access(s, appId, tx: tx, lock: true);
        return dto(
          s,
          a,
          await a.spec(s, tx: tx),
          await record(s, a, id, tx: tx),
          tx: tx,
        );
      });

  static Future<RuntimeRecord> dto(
    Session s,
    Access a,
    AppSpec spec,
    EntityRecord row, {
    Transaction? tx,
  }) async {
    final pool = await ResourcePool.db.findFirstRow(
      s,
      where: (t) => t.appId.equals(a.app.id!) & t.recordId.equals(row.id!),
      transaction: tx,
    );
    final claim = pool == null
        ? null
        : await Claim.db.findFirstRow(
            s,
            where: (t) =>
                t.poolId.equals(pool.id!) &
                t.actorId.equals(actor(s)) &
                t.active.equals(true),
            transaction: tx,
          );
    return RuntimeRecord(
      id: row.id!,
      collectionId: row.collectionId,
      data: payload(row.data),
      revision: row.revision,
      capacity: pool?.capacity,
      allocated: pool?.allocated,
      claimed: claim != null,
      allowedActions: spec.actions
          .where(
            (x) => x.collectionId == row.collectionId && allowed(a, spec, x),
          )
          .map((x) => x.id)
          .toList(),
    );
  }
}
