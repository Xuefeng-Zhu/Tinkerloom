part of 'service.dart';

extension _SpecActions on PlatformService {
  bool _specAllowed(
    AppAccess access,
    spec.AppSpec definition,
    spec.ActionSpec action, {
    bool writable = true,
  }) {
    if (access.role == 'viewer' || (writable && access.archived)) return false;
    if (access.builder) return true;
    if (action.capability == 'records.create.v1' &&
        definition
            .collection(action.collectionId)
            .behaviors
            .any((behavior) => behavior.type == 'capacity.v1'))
      return false;
    return switch (definition.policyPresetRequest) {
      'groupCapacitySignup.v1' => {
        'capacity.claim.v1',
        'capacity.release.v1',
      }.contains(action.capability),
      'groupWorkflow.v1' => {
        'records.create.v1',
        'records.patch.v1',
        'assignment.assign.v1',
        'workflow.transition.v1',
      }.contains(action.capability),
      _ => false,
    };
  }

  Future<Row> _specRecord(AppAccess access, String id, String? tx) async {
    final record = await store.get('spec_records', id, transactionId: tx);
    if (record == null ||
        record['appId'] != access.app[r'$id'] ||
        record['workspaceId'] != access.app['workspaceId'] ||
        record['deleted'] != false)
      throw const ServiceException('not_found', 404);
    return record;
  }

  Future<Row?> _pool(
    AppAccess access,
    String recordId,
    String? tx, {
    String? behaviorId,
  }) async {
    final rows = await store.list(
      'spec_pools',
      {'appId': access.app[r'$id'] as String, 'recordId': recordId},
      transactionId: tx,
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final pool = rows.single;
    if (pool['workspaceId'] != access.app['workspaceId'] ||
        (behaviorId != null && pool['behaviorId'] != behaviorId))
      throw const ServiceException('not_found', 404);
    final capacity = pool['capacity'] as int,
        allocated = pool['allocated'] as int;
    if (capacity < 0 ||
        capacity > 10000 ||
        allocated < 0 ||
        allocated > capacity)
      throw const ServiceException('integrity_error', 500);
    return pool;
  }

  Future<Row> _specRecordDto(
    String actor,
    AppAccess access,
    spec.AppSpec definition,
    Row record,
    String? tx,
  ) async {
    final pool = await _pool(access, record[r'$id'] as String, tx);
    final claim = pool == null
        ? null
        : await store.get(
            'spec_claims',
            _identity('c', [pool[r'$id'] as String, actor]),
            transactionId: tx,
          );
    if (claim != null &&
        (claim['appId'] != access.app[r'$id'] ||
            claim['workspaceId'] != access.app['workspaceId'] ||
            claim['poolId'] != pool![r'$id'] ||
            claim['actorId'] != actor))
      throw const ServiceException('integrity_error', 500);
    final collection = definition.collection(record['collectionId'] as String);
    final data = collection.normalizeRecord(
      jsonObject(jsonDecode(record['dataJson'] as String), 'invalid_values'),
    );
    return {
      'id': record[r'$id'],
      'collectionId': record['collectionId'],
      'data': data,
      'revision': record['revision'],
      'writtenUnderVersionId': record['writtenUnderVersionId'],
      'capacity': pool?['capacity'],
      'allocated': pool?['allocated'],
      'claimed': claim?['active'] == true,
      'allowedActions': definition.actions
          .where(
            (action) =>
                action.collectionId == collection.id &&
                _specAllowed(access, definition, action),
          )
          .map((action) => action.id)
          .toList(),
    };
  }

  Row _normalizeSpecData(spec.CollectionSpec collection, Object? data) {
    try {
      final result = collection.normalizeRecord(
        jsonObject(data, 'invalid_values'),
      );
      if (utf8.encode(jsonEncode(result)).length > _specRequestBytes)
        throw const ServiceException('request_too_large', 413);
      return result;
    } on spec.SpecException {
      throw const ServiceException('invalid_values', 400);
    }
  }

  Future<void> _specReferences(
    String actor,
    AppAccess access,
    spec.CollectionSpec collection,
    Row data,
    String tx, {
    Row? previous,
    String? assignedField,
  }) async {
    for (final field in collection.fields) {
      final value = data[field.id];
      if (value == null) continue;
      if (field.type == spec.FieldType.image) {
        await _validateMedia(actor, access, {value as String}, tx);
        continue;
      }
      if (field.type != spec.FieldType.member) continue;
      // An unchanged revoked assignee is historical data. It must not block an
      // unrelated note/status edit, but a create/change/assignment rechecks it.
      if (field.id != assignedField && previous?[field.id] == value) continue;
      try {
        await _access(
          value as String,
          access.app[r'$id'] as String,
          transactionId: tx,
        );
      } on ServiceException {
        throw const ServiceException('invalid_values', 400);
      }
    }
  }

  Future<void> _specProject(
    AppAccess access,
    Row record,
    spec.CollectionSpec collection,
    Row data,
    String tx,
  ) async {
    for (final field in collection.fields) {
      final value = data[field.id];
      final id = _identity('f', [record[r'$id'] as String, field.id]);
      final prior = await store.get('spec_values', id, transactionId: tx);
      if (prior != null &&
          (prior['appId'] != access.app[r'$id'] ||
              prior['recordId'] != record[r'$id'] ||
              prior['collectionId'] != collection.id ||
              prior['fieldId'] != field.id ||
              prior['workspaceId'] != access.app['workspaceId']))
        throw const ServiceException('integrity_error', 500);
      final row = <String, dynamic>{
        'workspaceId': access.app['workspaceId'],
        'appId': access.app[r'$id'],
        'recordId': record[r'$id'],
        'collectionId': collection.id,
        'fieldId': field.id,
        'present': value != null,
        'textValue': value is String && field.type != spec.FieldType.timestamp
            ? value
            : null,
        'numberValue': value is num ? value : null,
        'boolValue': value is bool ? value : null,
        'timestampValue': field.type == spec.FieldType.timestamp ? value : null,
      };
      // Stable projection identity plus an explicit absent marker replaces SQL
      // delete/reinsert. Every type column is reset on every update.
      if (prior == null) {
        await store.create('spec_values', id, row, transactionId: tx);
      } else {
        await store.update('spec_values', id, row, transactionId: tx);
      }
    }
  }

  int _capacity(Object? value) {
    if (value is! int || value < 0 || value > 10000)
      throw const ServiceException('invalid_values', 400);
    return value;
  }

  Future<void> _specCapacity(
    String actor,
    AppAccess access,
    Row record,
    spec.ActionSpec action,
    Row input,
    String tx,
  ) async {
    final pool = await _pool(
      access,
      record[r'$id'] as String,
      tx,
      behaviorId: action.behaviorId,
    );
    if (pool == null) throw const ServiceException('invalid_values', 400);
    if (action.capability == 'capacity.configure.v1') {
      _require(access, 'build');
      spec.keys(input, {'capacity'}, 'capacity input');
      final capacity = _capacity(input['capacity']);
      if (capacity < (pool['allocated'] as int))
        throw const ServiceException('invalid_values', 400);
      await store.update('spec_pools', pool[r'$id'] as String, {
        'capacity': capacity,
      }, transactionId: tx);
      return;
    }
    spec.keys(input, {}, 'claim input');
    final claimId = _identity('c', [pool[r'$id'] as String, actor]);
    final claim = await store.get('spec_claims', claimId, transactionId: tx);
    if (claim != null &&
        (claim['actorId'] != actor ||
            claim['appId'] != access.app[r'$id'] ||
            claim['workspaceId'] != access.app['workspaceId'] ||
            claim['poolId'] != pool[r'$id']))
      throw const ServiceException('integrity_error', 500);
    final now = clock().toUtc().toIso8601String();
    var allocated = pool['allocated'] as int;
    if (action.capability == 'capacity.claim.v1') {
      if (claim?['active'] == true) return;
      if (allocated >= (pool['capacity'] as int))
        throw const ServiceException('exhausted_capacity', 409);
      if (claim == null) {
        await store.create('spec_claims', claimId, {
          'workspaceId': access.app['workspaceId'],
          'appId': access.app[r'$id'],
          'poolId': pool[r'$id'],
          'actorId': actor,
          'active': true,
          'createdAt': now,
          'updatedAt': now,
        }, transactionId: tx);
      } else {
        await store.update('spec_claims', claimId, {
          'active': true,
          'updatedAt': now,
        }, transactionId: tx);
      }
      allocated++;
    } else {
      if (claim?['active'] != true) return;
      await store.update('spec_claims', claimId, {
        'active': false,
        'updatedAt': now,
      }, transactionId: tx);
      allocated--;
    }
    await store.update('spec_pools', pool[r'$id'] as String, {
      'allocated': allocated,
    }, transactionId: tx);
  }

  Future<Row> _specExecute(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'operationId',
      'versionId',
      'actionId',
      'targetRecordId',
      'expectedRecordRevision',
      'input',
    });
    final versionId = _validId(input['versionId']);
    final actionId = spec.stableId(input['actionId']);
    final arguments = jsonObject(input['input'], 'invalid_values');
    Future<void> authorize(AppAccess access, String? tx) async {
      _specEngine(access);
      final historical = await _specVersion(access, versionId, tx);
      final action = historical.definition.action(actionId);
      if (!_specAllowed(access, historical.definition, action, writable: false))
        throw const ServiceException('forbidden', 403);
    }

    return _mutate(
      actor,
      input,
      'read',
      (tx, access) async {
        final version = await _activeSpec(access, tx, expected: versionId);
        final definition = version.definition,
            action = definition.action(actionId);
        if (!_specAllowed(access, definition, action))
          throw const ServiceException('forbidden', 403);
        final collection = definition.collection(action.collectionId);
        final now = clock().toUtc().toIso8601String();
        Row record;
        if (action.capability == 'records.create.v1') {
          if (input['targetRecordId'] != null ||
              input['expectedRecordRevision'] != null)
            throw const ServiceException('invalid_request', 400);
          spec.keys(arguments, {'data', 'capacity'}, 'create input');
          final data = _normalizeSpecData(collection, arguments['data']);
          await _specReferences(actor, access, collection, data, tx);
          for (final behavior in collection.behaviors.where(
            (item) => item.type == 'workflow.v1',
          )) {
            if (data[behavior.fieldId] !=
                collection.field(behavior.fieldId!).choices.first)
              throw const ServiceException('invalid_values', 400);
          }
          final capacityBehavior = collection.behaviors
              .where((item) => item.type == 'capacity.v1')
              .firstOrNull;
          if (capacityBehavior != null) _require(access, 'build');
          if (capacityBehavior == null && arguments.containsKey('capacity'))
            throw const ServiceException('invalid_values', 400);
          record = await store.create('spec_records', _nonce(), {
            'workspaceId': access.app['workspaceId'],
            'appId': access.app[r'$id'],
            'collectionId': collection.id,
            'dataJson': jsonEncode(data),
            'creatorId': actor,
            'createdControlRevision':
                _storedRevision(access.app, 'controlRevision') + 1,
            'revision': 1,
            'writtenUnderVersionId': versionId,
            'deleted': false,
            'createdAt': now,
            'updatedAt': now,
          }, transactionId: tx);
          if (capacityBehavior != null)
            await store.create(
              'spec_pools',
              _identity('p', [record[r'$id'] as String, capacityBehavior.id]),
              {
                'workspaceId': access.app['workspaceId'],
                'appId': access.app[r'$id'],
                'recordId': record[r'$id'],
                'collectionId': collection.id,
                'behaviorId': capacityBehavior.id,
                'capacity': _capacity(arguments['capacity']),
                'allocated': 0,
              },
              transactionId: tx,
            );
          await _specProject(access, record, collection, data, tx);
        } else {
          record = await _specRecord(
            access,
            _validId(input['targetRecordId']),
            tx,
          );
          if (record['collectionId'] != collection.id)
            throw const ServiceException('not_found', 404);
          if (action.capability.startsWith('capacity.')) {
            await _specCapacity(actor, access, record, action, arguments, tx);
          } else {
            final expected = _revision(input['expectedRecordRevision']);
            if (expected != record['revision'] || expected >= 2147483646)
              throw const ServiceException('revision_conflict', 409);
            final previous = jsonObject(
              jsonDecode(record['dataJson'] as String),
              'invalid_values',
            );
            final data = <String, dynamic>{...previous};
            String? assigned;
            if (action.capability == 'records.patch.v1') {
              spec.keys(arguments, {'data'}, 'patch input');
              final patch = jsonObject(arguments['data'], 'invalid_values');
              final protected = collection.behaviors
                  .where(
                    (behavior) =>
                        behavior.type == 'workflow.v1' ||
                        behavior.type == 'assignment.v1',
                  )
                  .map((behavior) => behavior.fieldId)
                  .toSet();
              if (patch.keys.any(protected.contains))
                throw const ServiceException('forbidden', 403);
              data.addAll(patch);
            } else {
              spec.keys(arguments, {'value'}, 'action input');
              final behavior = collection.behavior(action.behaviorId!);
              if (action.capability == 'assignment.assign.v1')
                assigned = behavior.fieldId;
              if (action.capability == 'workflow.transition.v1' &&
                  !(behavior.transitions[data[behavior.fieldId]] ?? [])
                      .contains(arguments['value']))
                throw const ServiceException('invalid_values', 400);
              data[behavior.fieldId!] = arguments['value'];
            }
            final normalized = _normalizeSpecData(collection, data);
            await _specReferences(
              actor,
              access,
              collection,
              normalized,
              tx,
              previous: previous,
              assignedField: assigned,
            );
            record = await store
                .update('spec_records', record[r'$id'] as String, {
                  'dataJson': jsonEncode(normalized),
                  'revision': expected + 1,
                  'writtenUnderVersionId': versionId,
                  'updatedAt': now,
                }, transactionId: tx);
            await _specProject(access, record, collection, normalized, tx);
          }
        }
        if (!action.capability.startsWith('capacity.')) {
          final data = jsonDecode(record['dataJson'] as String) as Row;
          await _syncMedia(
            actor,
            access,
            {
              for (final field in collection.fields)
                if (field.type == spec.FieldType.image &&
                    data[field.id] != null)
                  data[field.id] as String,
            },
            'record',
            record[r'$id'] as String,
            tx,
          );
        }
        await _specChanged(
          actor,
          access,
          input['operationId'] as String,
          action.capability,
          tx,
          recordId: record[r'$id'] as String,
        );
        return {
          'outcome': {
            'recordId': record[r'$id'],
            'revision': record['revision'],
            'message': 'Saved',
          },
        };
      },
      requestBytes: _specRequestBytes,
      responseBytes: _specResponseBytes,
      authorize: authorize,
    );
  }
}
