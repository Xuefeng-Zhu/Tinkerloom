part of 'service.dart';

extension _InboxRuntime on PlatformService {
  Future<Row> _inbox(String actor, Row input) async {
    _inputKeys(input, {'op', 'afterId'});
    final after = input['afterId'] == null ? null : _validId(input['afterId']);
    final batches = await _workerRows('notification_batches', {}, null);
    final items = <Row>[], authorized = <String, AppAccess>{};
    for (final batch in batches) {
      final recipients =
          (jsonDecode(batch['recipientIdsJson'] as String) as List)
              .cast<String>();
      if (!recipients.contains(actor)) continue;
      AppAccess access;
      try {
        access = await _access(actor, batch['appId'] as String);
      } on ServiceException catch (error) {
        if (error.code == 'not_found') continue;
        rethrow;
      }
      if (batch['workspaceId'] != access.app['workspaceId'])
        throw const ServiceException('integrity_error', 500);
      final run = await store.get('automation_runs', batch['runId'] as String);
      if (run == null ||
          run['appId'] != access.app[r'$id'] ||
          run['status'] != 'succeeded' ||
          run['leaseGeneration'] != batch['leaseGeneration'])
        continue;
      final id = _identity('n', [batch['runId'] as String, actor]);
      final read = await store.get(
        'notification_reads',
        _identity('h', [id, actor]),
      );
      if (read != null &&
          (read['actorId'] != actor ||
              read['notificationId'] != id ||
              read['appId'] != access.app[r'$id']))
        throw const ServiceException('integrity_error', 500);
      final record = await store.get(
        'spec_records',
        batch['recordId'] as String,
      );
      final recordAvailable =
          record != null &&
          record['appId'] == access.app[r'$id'] &&
          record['workspaceId'] == access.app['workspaceId'] &&
          record['deleted'] == false;
      items.add({
        'id': id,
        'appId': access.app[r'$id'],
        'runId': run[r'$id'],
        'recordId': recordAvailable ? record[r'$id'] : null,
        'collectionId': recordAvailable ? record['collectionId'] : null,
        'title': batch['title'],
        'body': batch['body'],
        'createdAt': batch['createdAt'],
        'isRead': read != null,
      });
      authorized[access.app[r'$id'] as String] = access;
    }
    items.sort((a, b) {
      final time = _time(b['createdAt']).compareTo(_time(a['createdAt']));
      return time == 0
          ? (a['id'] as String).compareTo(b['id'] as String)
          : time;
    });
    var offset = 0;
    if (after != null) {
      final index = items.indexWhere((item) => item['id'] == after);
      if (index < 0) throw const ServiceException('revision_conflict', 409);
      offset = index + 1;
    }
    final selected = items.skip(offset).take(100).toList();
    for (final access in authorized.values) await _readAgain(actor, access);
    return {
      'items': selected,
      'nextCursor': offset + selected.length < items.length
          ? selected.last['id']
          : null,
    };
  }

  Future<Row> _readNotification(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'runId',
      'notificationId',
      'operationId',
    });
    final runId = _validId(input['runId']),
        notificationId = _validId(input['notificationId']);
    return _mutate(actor, input, 'read', (tx, access) async {
      _specEngine(access);
      if (notificationId != _identity('n', [runId, actor]))
        throw const ServiceException('not_found', 404);
      final batch = await store.get(
        'notification_batches',
        _identity('b', [runId]),
        transactionId: tx,
      );
      final run = await store.get('automation_runs', runId, transactionId: tx);
      if (batch == null ||
          run == null ||
          batch['appId'] != access.app[r'$id'] ||
          batch['workspaceId'] != access.app['workspaceId'] ||
          run['appId'] != access.app[r'$id'] ||
          run['status'] != 'succeeded' ||
          run['leaseGeneration'] != batch['leaseGeneration'] ||
          !(jsonDecode(batch['recipientIdsJson'] as String) as List).contains(
            actor,
          ))
        throw const ServiceException('not_found', 404);
      final id = _identity('h', [notificationId, actor]);
      if (await store.get('notification_reads', id, transactionId: tx) == null)
        await store.create('notification_reads', id, {
          'workspaceId': access.app['workspaceId'],
          'appId': access.app[r'$id'],
          'actorId': actor,
          'notificationId': notificationId,
          'runId': runId,
          'readAt': _now(),
        }, transactionId: tx);
      await _specChanged(
        actor,
        access,
        input['operationId'] as String,
        'notification.read',
        tx,
      );
      return {'notificationId': notificationId, 'isRead': true};
    }, writable: false);
  }

  Future<Row> _runHistory(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'afterId'});
    final after = input['afterId'] == null ? null : _validId(input['afterId']);
    return _specRead(actor, _validId(input['appId']), (access, tx) async {
      _require(access, 'build', writable: false);
      if (after != null) {
        final cursor = await store.get(
          'automation_runs',
          after,
          transactionId: tx,
        );
        if (cursor == null ||
            cursor['appId'] != access.app[r'$id'] ||
            cursor['workspaceId'] != access.app['workspaceId'])
          throw const ServiceException('not_found', 404);
      }
      final rows = await store.list(
        'automation_runs',
        {'appId': access.app[r'$id'] as String},
        transactionId: tx,
        limit: 51,
        afterId: after,
        detectOverflow: false,
      );
      final page = rows.take(50).toList(), runs = <Row>[];
      for (final run in page) {
        if (run['workspaceId'] != access.app['workspaceId'])
          throw const ServiceException('integrity_error', 500);
        final rule = await store.get(
          'automations',
          run['automationId'] as String,
          transactionId: tx,
        );
        runs.add({
          'id': run[r'$id'],
          'ruleId': rule?['ruleId'],
          'recordId': run['recordId'],
          'status': run['status'],
          'dueAt': run['dueAt'],
          'nextAttemptAt': run['nextAttemptAt'],
          'attempts': run['attempts'],
          'errorCategory': run['errorCategory'],
          'recipientCount': run['recipientCount'] ?? 0,
        });
      }
      return {
        'runs': runs,
        'nextCursor': rows.length > 50 ? page.last[r'$id'] : null,
      };
    });
  }
}
