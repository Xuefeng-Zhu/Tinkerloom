part of 'service.dart';

extension _ReminderRuntime on PlatformService {
  bool _condition(spec.AutomationSpec rule, Row data) =>
      rule.condition == null ||
      data[rule.condition!.fieldId] == rule.condition!.value;
  String _scheduleSignature(Row rule, String? date, DateTime? due) =>
      spec.hashJson({
        'ruleVersion': rule['ruleVersion'],
        'timestamp': date,
        'due': due?.toIso8601String(),
      });

  Future<void> _reconcileRules(
    String actor,
    AppAccess access,
    spec.AppSpec definition,
    String versionId,
    List<String> selected,
    List<String> records,
    String operationId,
    String tx,
  ) async {
    final existing = await _workerRows('automations', {
      'appId': access.app[r'$id'] as String,
    }, tx);
    for (final old in existing) {
      if (old['workspaceId'] != access.app['workspaceId'])
        throw const ServiceException('integrity_error', 500);
      if (old['enabled'] == true && !selected.contains(old['ruleId']))
        await store.update('automations', old[r'$id'] as String, {
          'enabled': false,
        }, transactionId: tx);
    }
    for (final requested in definition.automationRequests.where(
      (rule) => selected.contains(rule.id),
    )) {
      final id = _identity('r', [access.app[r'$id'] as String, requested.id]);
      final old = existing.where((rule) => rule[r'$id'] == id).firstOrNull;
      final canonical = spec.canonicalJson(requested.toJson());
      Row rule;
      if (old == null) {
        rule = await store.create('automations', id, {
          'workspaceId': access.app['workspaceId'],
          'appId': access.app[r'$id'],
          'ruleId': requested.id,
          'ruleVersion': 1,
          'ruleJson': canonical,
          'enabled': true,
          'executionActorId': actor,
          'activatedAt': _now(),
          'activationControlRevision':
              _storedRevision(access.app, 'controlRevision') + 1,
          'activationVersionId': versionId,
        }, transactionId: tx);
      } else if (old['enabled'] != true || old['ruleJson'] != canonical) {
        if ((old['ruleVersion'] as int) >= 2147483646)
          throw const ServiceException('revision_conflict', 409);
        rule = await store.update('automations', id, {
          'ruleVersion': (old['ruleVersion'] as int) + 1,
          'ruleJson': canonical,
          'enabled': true,
          'executionActorId': actor,
          'activatedAt': _now(),
          'activationControlRevision':
              _storedRevision(access.app, 'controlRevision') + 1,
          'activationVersionId': versionId,
        }, transactionId: tx);
      } else {
        rule = old;
      }
      final scope = <String>[];
      for (final recordId in records) {
        final record = await _specRecord(access, recordId, tx);
        if (record['collectionId'] == requested.collectionId)
          scope.add(recordId);
      }
      if (scope.isNotEmpty)
        await store.create(
          'enrollments',
          _identity('e', [id, '${rule['ruleVersion']}', operationId]),
          {
            'workspaceId': access.app['workspaceId'],
            'appId': access.app[r'$id'],
            'automationId': id,
            'ruleVersion': rule['ruleVersion'],
            'recordIdsJson': jsonEncode(scope),
            'createdAt': _now(),
          },
          transactionId: tx,
        );
    }
  }

  Future<bool> _enrolled(
    AppAccess access,
    Row rule,
    Row record,
    String tx,
  ) async {
    final created = record['createdControlRevision'] as int?;
    final activated = rule['activationControlRevision'] as int?;
    if (created != null && activated != null && created > activated)
      return true;
    if (created == null &&
        _time(record['createdAt']).isAfter(_time(rule['activatedAt'])))
      return true;
    final runs = await _workerRows('automation_runs', {
      'automationId': rule[r'$id'] as String,
      'recordId': record[r'$id'] as String,
    }, tx);
    if (runs.any((run) => run['ruleVersion'] == rule['ruleVersion']))
      return true;
    final batches = await _workerRows('enrollments', {
      'automationId': rule[r'$id'] as String,
    }, tx);
    for (final batch in batches) {
      if (batch['workspaceId'] != access.app['workspaceId'] ||
          batch['appId'] != access.app[r'$id'])
        throw const ServiceException('integrity_error', 500);
      if (batch['ruleVersion'] == rule['ruleVersion'] &&
          (jsonDecode(batch['recordIdsJson'] as String) as List).contains(
            record[r'$id'],
          ))
        return true;
    }
    return false;
  }

  Future<void> _planReminderRecord(
    AppAccess access,
    String recordId,
    String tx,
  ) async {
    Row record;
    try {
      record = await _specRecord(access, recordId, tx);
    } on ServiceException catch (error) {
      if (error.code == 'not_found') return;
      rethrow;
    }
    final rules = await _workerRows('automations', {
      'appId': access.app[r'$id'] as String,
    }, tx);
    final data = jsonObject(
      jsonDecode(record['dataJson'] as String),
      'invalid_values',
    );
    for (final rule in rules.where((item) => item['enabled'] == true)) {
      if (rule['workspaceId'] != access.app['workspaceId'])
        throw const ServiceException('integrity_error', 500);
      final definition = spec.AutomationSpec.fromJson(
        jsonObject(jsonDecode(rule['ruleJson'] as String), 'invalid_spec'),
      );
      if (definition.collectionId != record['collectionId']) continue;
      final date = data[definition.fieldId] as String?;
      if (date == null || !await _enrolled(access, rule, record, tx)) continue;
      final due = DateTime.parse(
        date,
      ).subtract(Duration(seconds: definition.offsetSeconds)).toUtc();
      final signature = _scheduleSignature(rule, date, due);
      final occurrence = spec.hashJson({
        'app': access.app[r'$id'],
        'rule': rule[r'$id'],
        'record': recordId,
        'signature': signature,
      });
      final id = _identity('u', [occurrence]);
      final old = await store.get('automation_runs', id, transactionId: tx);
      if (old != null) {
        if (old['occurrenceKey'] != occurrence ||
            old['appId'] != access.app[r'$id'])
          throw const ServiceException('integrity_error', 500);
        continue;
      }
      await store.create('automation_runs', id, {
        'workspaceId': access.app['workspaceId'],
        'appId': access.app[r'$id'],
        'automationId': rule[r'$id'],
        'ruleVersion': rule['ruleVersion'],
        'recordId': recordId,
        'occurrenceKey': occurrence,
        'scheduleSignature': signature,
        'dueAt': due.toIso8601String(),
        'nextAttemptAt': due.toIso8601String(),
        'status': 'pending',
        'attempts': 0,
        'leaseGeneration': 0,
        'leaseUntil': null,
        'errorCategory': null,
        'recipientCount': 0,
        'createdAt': _now(),
        'completedAt': null,
      }, transactionId: tx);
      await _queueDispatch(
        'reminder',
        id,
        access.app[r'$id'] as String,
        due,
        tx,
      );
    }
  }

  Future<void> _planEvent(String eventId) async {
    if (!remindersEnabled) return;
    final initial = await store.get('outbox', eventId);
    if (initial == null ||
        initial['planningDone'] == true && initial['invalidationDone'] == true)
      return;
    try {
      await _workerTransaction((tx) async {
        final access = await _workerStage(initial['appId'] as String, tx);
        final event = await store.get('outbox', eventId, transactionId: tx);
        if (event == null || event['workspaceId'] != access.app['workspaceId'])
          throw const ServiceException('not_found', 404);
        if (event['planningDone'] == true && event['invalidationDone'] == true)
          return;
        final payload = jsonObject(
          jsonDecode(event['payloadJson'] as String),
          'invalid_request',
        );
        final targets = event['recordId'] != null
            ? [event['recordId'] as String]
            : ((payload['activateExistingRecordIds'] as List?) ?? [])
                  .cast<String>();
        final offset = (event['planningOffset'] as int?) ?? 0;
        final end = min(
          targets.length,
          offset + 4,
        ); // <=40 runs +40 dispatches plus guards/state on Free.
        if (remindersEnabled &&
            !access.archived &&
            event['planningDone'] != true)
          for (final id in targets.skip(offset).take(end - offset))
            await _planReminderRecord(access, id, tx);
        await store.update('outbox', eventId, {
          'planningOffset': end,
          'planningDone': end >= targets.length,
          'invalidationDone': true,
        }, transactionId: tx);
        if (end < targets.length)
          await _queueDispatch(
            'reconcile',
            eventId,
            access.app[r'$id'] as String,
            clock().toUtc().add(const Duration(seconds: 1)),
            tx,
          );
      });
    } catch (_) {
      await _workerTransaction((tx) async {
        await _workerStage(initial['appId'] as String, tx);
        final event = await store.get('outbox', eventId, transactionId: tx);
        if (event == null ||
            event['planningDone'] == true && event['invalidationDone'] == true)
          return;
        final attempts = ((event['attempts'] as int?) ?? 0) + 1;
        await store.update('outbox', eventId, {
          'attempts': attempts,
          'lastError': 'planning_failure',
          'nextAttemptAt': clock()
              .toUtc()
              .add(Duration(seconds: min(300, 1 << min(attempts, 8))))
              .toIso8601String(),
        }, transactionId: tx);
      });
      rethrow;
    }
  }

  /// The same app/workspace guards cover all supported membership/grant writes.
  /// Read one paginated authorized snapshot rather than four network GETs for
  /// each claimant. Canonical IDs preserve the exact keyed _access semantics;
  /// noncanonical duplicate rows cannot manufacture an otherwise absent grant.
  Future<Set<String>> _eligibleReminderRecipients(
    AppAccess access,
    Set<String> actors,
    String tx,
  ) async {
    if (actors.length <= 8) {
      final eligible = <String>{};
      for (final actor in actors) {
        if (await _workerHasAccess(access, actor, tx)) eligible.add(actor);
      }
      return eligible;
    }
    final workspaceId = access.app['workspaceId'] as String;
    final appId = access.app[r'$id'] as String;
    final members = <String>{access.workspace['ownerId'] as String};
    final grants = <String>{};
    for (final row in await _workerRows('memberships', {
      'workspaceId': workspaceId,
    }, tx)) {
      final actor = row['actorId'];
      if (actor is String &&
          actors.contains(actor) &&
          row[r'$id'] == _identity('m', [workspaceId, actor]) &&
          _validMembership(row, workspaceId, actor))
        members.add(actor);
    }
    for (final row in await _workerRows('grants', {'appId': appId}, tx)) {
      final actor = row['actorId'];
      if (actor is String &&
          actors.contains(actor) &&
          row[r'$id'] == _identity('g', [appId, actor]) &&
          _validGrant(row, access.app, actor))
        grants.add(actor);
    }
    return actors
        .where(
          (actor) =>
              members.contains(actor) &&
              (actor == access.app['ownerId'] || grants.contains(actor)),
        )
        .toSet();
  }

  bool _runDue(Row run) =>
      run['status'] == 'pending' &&
      !_time(run['dueAt']).isAfter(clock().toUtc()) &&
      !_time(run['nextAttemptAt']).isAfter(clock().toUtc());

  Future<void> _executeReminder(String runId) async {
    if (!remindersEnabled) return;
    int? claimedGeneration;
    try {
      final initial = await store.get('automation_runs', runId);
      if (initial == null || !_runDue(initial)) return;
      await _workerTransaction((tx) async {
        final access = await _workerStage(initial['appId'] as String, tx);
        final run = await store.get(
          'automation_runs',
          runId,
          transactionId: tx,
        );
        if (run == null || !_runDue(run)) return;
        claimedGeneration = run['leaseGeneration'] as int;
        final generation = claimedGeneration! + 1;
        final rule = await store.get(
          'automations',
          run['automationId'] as String,
          transactionId: tx,
        );
        final record = await store.get(
          'spec_records',
          run['recordId'] as String,
          transactionId: tx,
        );
        var suppress =
            access.archived ||
            rule == null ||
            rule['enabled'] != true ||
            rule['appId'] != access.app[r'$id'] ||
            rule['workspaceId'] != access.app['workspaceId'] ||
            rule['ruleVersion'] != run['ruleVersion'] ||
            record == null ||
            record['deleted'] != false ||
            record['appId'] != access.app[r'$id'] ||
            record['workspaceId'] != access.app['workspaceId'];
        final recipients = <String>{};
        if (!suppress) {
          final definition = spec.AutomationSpec.fromJson(
            jsonObject(jsonDecode(rule['ruleJson'] as String), 'invalid_spec'),
          );
          final data = jsonObject(
            jsonDecode(record['dataJson'] as String),
            'invalid_values',
          );
          final date = data[definition.fieldId] as String?;
          final due = date == null
              ? null
              : DateTime.parse(
                  date,
                ).subtract(Duration(seconds: definition.offsetSeconds)).toUtc();
          suppress =
              definition.collectionId != record['collectionId'] ||
              _scheduleSignature(rule, date, due) != run['scheduleSignature'] ||
              !_condition(definition, data) ||
              !await _workerHasAccess(
                access,
                rule['executionActorId'] as String,
                tx,
                builder: true,
              );
          if (!suppress) {
            if (definition.effect == 'notifyOwner') {
              if (await _workerHasAccess(
                access,
                access.app['ownerId'] as String,
                tx,
              ))
                recipients.add(access.app['ownerId'] as String);
              else
                suppress = true;
            } else if (definition.effect == 'notifyActiveClaimants') {
              final pools = await _workerRows('spec_pools', {
                'appId': access.app[r'$id'] as String,
                'recordId': record[r'$id'] as String,
              }, tx);
              for (final pool in pools) {
                final claims = await _workerRows('spec_claims', {
                  'poolId': pool[r'$id'] as String,
                }, tx);
                final active = claims
                    .where((claim) => claim['active'] == true)
                    .toList();
                if (active.length > spec.Limits.notificationFanout)
                  throw const ServiceException('quota_exceeded', 429);
                for (final claim in active) {
                  if (claim['appId'] != access.app[r'$id'] ||
                      claim['workspaceId'] != access.app['workspaceId'])
                    throw const ServiceException('integrity_error', 500);
                  recipients.add(claim['actorId'] as String);
                }
              }
            } else {
              final version = await _activeSpec(access, tx);
              final collection = version.definition.collection(
                record['collectionId'] as String,
              );
              for (final behavior in collection.behaviors.where(
                (item) => item.type == 'assignment.v1',
              )) {
                final id = data[behavior.fieldId];
                if (id is String) recipients.add(id);
              }
            }
          }
        }
        if (recipients.length > spec.Limits.notificationFanout)
          throw const ServiceException('quota_exceeded', 429);
        final eligible = suppress
            ? <String>[]
            : (await _eligibleReminderRecipients(
                access,
                recipients,
                tx,
              )).toList();
        eligible.sort();
        if (!suppress && eligible.isNotEmpty) {
          final batchId = _identity('b', [runId]);
          final batch = await store.get(
            'notification_batches',
            batchId,
            transactionId: tx,
          );
          if (batch == null)
            await store.create('notification_batches', batchId, {
              'workspaceId': access.app['workspaceId'],
              'appId': access.app[r'$id'],
              'runId': runId,
              'recordId': run['recordId'],
              'recipientIdsJson': jsonEncode(eligible),
              'leaseGeneration': generation,
              'title': 'A reminder from ${access.app['name']}',
              'body':
                  'An upcoming item needs your attention. Open the app for current details.',
              'createdAt': _now(),
            }, transactionId: tx);
        }
        await store.update('automation_runs', runId, {
          'status': suppress ? 'suppressed' : 'succeeded',
          'attempts': (run['attempts'] as int) + 1,
          'leaseGeneration': generation,
          'leaseUntil': null,
          'completedAt': _now(),
          'recipientCount': eligible.length,
        }, transactionId: tx);
      });
    } catch (_) {
      if (claimedGeneration != null)
        await _reminderFailure(runId, claimedGeneration!);
      rethrow;
    }
  }

  Future<void> _reminderFailure(String runId, int generation) async {
    final initial = await store.get('automation_runs', runId);
    if (initial == null) return;
    await _workerTransaction((tx) async {
      await _workerStage(initial['appId'] as String, tx);
      final run = await store.get('automation_runs', runId, transactionId: tx);
      if (run == null || run['leaseGeneration'] != generation || !_runDue(run))
        return;
      final attempts = (run['attempts'] as int) + 1;
      await store.update('automation_runs', runId, {
        'attempts': attempts,
        'leaseGeneration': generation + 1,
        'status': attempts >= 5 ? 'failed' : 'pending',
        'errorCategory': 'retryable_failure',
        'leaseUntil': null,
        'nextAttemptAt': clock()
            .toUtc()
            .add(Duration(seconds: 1 << attempts))
            .toIso8601String(),
        if (attempts >= 5) 'completedAt': _now(),
      }, transactionId: tx);
      if (attempts < 5)
        await _queueDispatch(
          'reminder',
          runId,
          initial['appId'] as String,
          clock().toUtc().add(Duration(seconds: 1 << attempts)),
          tx,
        );
    });
  }

  Future<Row> _drainReminders(int maximum) async {
    if (maximum < 1 || maximum > 100)
      throw ArgumentError('Worker batch must be1..100');
    if (!remindersEnabled)
      return {'planned': 0, 'executed': 0, 'enabled': false};
    var planned = 0, executed = 0;
    final events = (await _workerRows('outbox', {}, null))
        .where(
          (event) =>
              (event['planningDone'] != true ||
                  event['invalidationDone'] != true) &&
              !_time(event['nextAttemptAt']).isAfter(clock().toUtc()),
        )
        .take(maximum);
    for (final event in events) {
      try {
        await _planEvent(event[r'$id'] as String);
        planned++;
      } catch (_) {
        /* persisted retry */
      }
    }
    final runs =
        (await _workerRows('automation_runs', {
          'status': 'pending',
        }, null)).where(_runDue).toList()..sort(
          (a, b) =>
              _time(a['nextAttemptAt']).compareTo(_time(b['nextAttemptAt'])),
        );
    for (final run in runs.take(maximum)) {
      try {
        await _executeReminder(run[r'$id'] as String);
        executed++;
      } catch (_) {
        /* persisted retry */
      }
    }
    return {'planned': planned, 'executed': executed, 'enabled': true};
  }

  Future<Row> _reminderStates(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'versionId', 'recordId'});
    final versionId = _validId(input['versionId']);
    return _specRead(actor, _validId(input['appId']), (access, tx) async {
      final version = await _activeSpec(access, tx, expected: versionId);
      final record = await _specRecord(access, _validId(input['recordId']), tx);
      final data = jsonObject(
        jsonDecode(record['dataJson'] as String),
        'invalid_values',
      );
      final rules = await _workerRows('automations', {
        'appId': access.app[r'$id'] as String,
      }, tx);
      final states = <Row>[];
      for (final definition in version.definition.automationRequests.where(
        (rule) => rule.collectionId == record['collectionId'],
      )) {
        final rule = rules
            .where((item) => item['ruleId'] == definition.id)
            .firstOrNull;
        final date = data[definition.fieldId] as String?;
        final due = date == null
            ? null
            : DateTime.parse(
                date,
              ).subtract(Duration(seconds: definition.offsetSeconds)).toUtc();
        var state = date == null ? 'unset' : 'disabled';
        var eligible = false;
        var recipients = 0;
        if (remindersEnabled &&
            date != null &&
            rule != null &&
            rule['enabled'] == true) {
          final signature = _scheduleSignature(rule, date, due);
          final runs = await _workerRows('automation_runs', {
            'automationId': rule[r'$id'] as String,
            'recordId': record[r'$id'] as String,
          }, tx);
          final run = runs
              .where(
                (row) =>
                    row['ruleVersion'] == rule['ruleVersion'] &&
                    row['scheduleSignature'] == signature,
              )
              .firstOrNull;
          eligible =
              !access.archived &&
              _condition(definition, data) &&
              await _workerHasAccess(
                access,
                rule['executionActorId'] as String,
                tx,
                builder: true,
              ) &&
              (definition.effect != 'notifyOwner' ||
                  await _workerHasAccess(
                    access,
                    access.app['ownerId'] as String,
                    tx,
                  ));
          state = run == null
              ? (await _enrolled(access, rule, record, tx)
                    ? 'pending'
                    : 'unenrolled')
              : switch (run['status']) {
                  'succeeded' => 'delivered',
                  'suppressed' => 'suppressed',
                  'failed' => 'failed',
                  _ => 'pending',
                };
          recipients = (run?['recipientCount'] as int?) ?? 0;
          if (access.archived && state == 'pending') state = 'suppressed';
        }
        states.add({
          'ruleId': definition.id,
          'state': state,
          'scheduledAt': due?.toIso8601String(),
          'eligible': eligible,
          'recipientCount': recipients,
        });
      }
      return {'states': states, 'versionId': versionId};
    });
  }
}
