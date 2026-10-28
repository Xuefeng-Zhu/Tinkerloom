part of 'service.dart';

const _specRequestBytes = 6291456;
const _specResponseBytes = 8388608;

class _SpecVersion {
  const _SpecVersion(this.row, this.definition);
  final Row row;
  final spec.AppSpec definition;
}

extension _SpecRuntime on PlatformService {
  void _specEngine(AppAccess access) {
    if (access.app['engine'] != 'appspec.v1')
      throw const ServiceException('unsupported_runtime', 400);
  }

  String? _versionId(Object? value) => value == null ? null : _validId(value);
  String _hash(Object? value) {
    if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value))
      throw const ServiceException('invalid_request', 400);
    return value;
  }

  Future<_SpecVersion> _specVersion(
    AppAccess access,
    String id,
    String? tx,
  ) async {
    final row = await store.get('spec_versions', id, transactionId: tx);
    if (row == null ||
        row['appId'] != access.app[r'$id'] ||
        row['workspaceId'] != access.app['workspaceId'])
      throw const ServiceException('not_found', 404);
    final definition = spec.AppSpec.parse(row['specJson'] as String);
    if (definition.hash != row['hash'] ||
        definition.canonical != row['specJson'])
      throw const ServiceException('integrity_error', 500);
    return _SpecVersion(row, definition);
  }

  Future<_SpecVersion> _activeSpec(
    AppAccess access,
    String? tx, {
    String? expected,
  }) async {
    _specEngine(access);
    final id = access.app['specVersionId'] as String?;
    if (id == null) throw const ServiceException('not_published', 409);
    if (expected != null && expected != id)
      throw const ServiceException('definition_conflict', 409);
    return _specVersion(access, id, tx);
  }

  Future<Row?> _specDraft(String actor, AppAccess access, String? tx) async {
    final draft = await store.get(
      'spec_drafts',
      _identity('s', [access.app[r'$id'] as String, actor]),
      transactionId: tx,
    );
    if (draft != null &&
        (draft['appId'] != access.app[r'$id'] ||
            draft['workspaceId'] != access.app['workspaceId'] ||
            draft['actorId'] != actor))
      throw const ServiceException('not_found', 404);
    return draft;
  }

  Future<Row> _publicSpecApp(String actor, AppAccess access, String? tx) async {
    _specEngine(access);
    final currentId = access.app['specVersionId'] as String?;
    final version = currentId == null
        ? null
        : await _specVersion(access, currentId, tx);
    final draft = access.builder ? await _specDraft(actor, access, tx) : null;
    final allowedActions =
        version?.definition.actions
            .where((action) => _specAllowed(access, version.definition, action))
            .map((action) => action.id)
            .toList() ??
        <String>[];
    return {
      ..._appSummary(access),
      'capabilities': {
        ...access.capabilities,
        'writeRecords': allowedActions.isNotEmpty,
      },
      'allowedActions': allowedActions,
      'generation': await _generationForApp(actor, access, tx),
      'controlRevision': _storedRevision(access.app, 'controlRevision'),
      'version': version == null
          ? null
          : {
              'id': version.row[r'$id'],
              'number': version.row['number'],
              'hash': version.row['hash'],
              'spec': version.definition.toJson(),
            },
      'draft': draft == null
          ? null
          : {
              'revision': draft['revision'],
              'baseVersionId': draft['baseVersionId'],
              'candidateHash': draft['candidateHash'],
              'publishedVersionId': draft['publishedVersionId'],
              'spec': spec.AppSpec.parse(draft['specJson'] as String).toJson(),
            },
    };
  }

  Future<AppAccess> _specChanged(
    String actor,
    AppAccess access,
    String operationId,
    String kind,
    String tx, {
    String? recordId,
    Row? payload,
  }) async {
    final current = await store.get(
      'apps',
      access.app[r'$id'] as String,
      transactionId: tx,
    );
    final revision = _storedRevision(current!, 'controlRevision');
    if (revision >= 2147483646)
      throw const ServiceException('revision_conflict', 409);
    final app = await store.update('apps', access.app[r'$id'] as String, {
      'controlRevision': revision + 1,
    }, transactionId: tx);
    final now = clock().toUtc().toIso8601String();
    await store.create(
      'audit',
      _identity('a', [access.app[r'$id'] as String, operationId]),
      {
        'workspaceId': access.app['workspaceId'],
        'appId': access.app[r'$id'],
        'actorId': actor,
        'action': kind,
        'recordId': recordId,
        'requestId': operationId,
        'createdAt': now,
      },
      transactionId: tx,
    );
    await store.create(
      'outbox',
      _identity('o', [access.app[r'$id'] as String, operationId]),
      {
        'workspaceId': access.app['workspaceId'],
        'appId': access.app[r'$id'],
        'recordId': recordId,
        'kind': kind,
        'payloadJson': jsonEncode({
          'versionId': app['specVersionId'],
          ...?payload,
        }),
        'planningDone': false,
        'invalidationDone': false,
        'nextAttemptAt': now,
        'createdAt': now,
      },
      transactionId: tx,
    );
    if (remindersEnabled)
      await _queueDispatch(
        'reconcile',
        _identity('o', [access.app[r'$id'] as String, operationId]),
        access.app[r'$id'] as String,
        clock().toUtc(),
        tx,
      );
    return AppAccess(app, access.workspace, access.role);
  }

  Future<Row> _specRead(
    String actor,
    String appId,
    Future<Row> Function(AppAccess, String) action,
  ) async {
    final initial = await _access(actor, appId);
    _specEngine(initial);
    // A committed guard update makes multi-page reads conflict rather than
    // return a mixed authorized snapshot after a concurrent supported write.
    return _transaction((tx) async {
      final access = await _stageAccess(actor, initial, tx);
      _specEngine(access);
      final response = await action(access, tx);
      if (utf8.encode(jsonEncode(response)).length > _specResponseBytes)
        throw const ServiceException('response_too_large', 413);
      return response;
    });
  }

  List<String> _selected(Object? value, int maximum, {bool records = false}) {
    if (value is! List || value.length > maximum)
      throw const ServiceException('invalid_request', 400);
    final result = value
        .map((item) => records ? _validId(item) : spec.stableId(item))
        .toList();
    if (result.toSet().length != result.length)
      throw const ServiceException('invalid_request', 400);
    return result;
  }

  String _reviewHash(
    String candidateHash,
    List<String> rules,
    List<String> records,
  ) => spec.hashJson({
    'candidateHash': candidateHash,
    'enabledRuleIds': [...rules]..sort(),
    'activateExistingRecordIds': [...records]..sort(),
  });

  Future<Row> _specCreate(String actor, Row input) async {
    _inputKeys(input, {'op', 'id', 'workspaceId', 'name', 'operationId'});
    final id = _validId(input['id']);
    final operationId = _validId(input['operationId']);
    final name = boundedText(input['name'], 128, 'invalid_name');
    final workspace = await _workspace(actor, input['workspaceId']);
    final request = _request({
      ...input,
      'name': name,
    }, maximumBytes: _specRequestBytes);
    final prior = await _receipt(actor, id, operationId, request);
    if (prior != null) {
      _require(await _access(actor, id), 'owner', writable: false);
      return prior;
    }
    final existing = await store.get('apps', id);
    if (existing != null) {
      final access = await _access(actor, id);
      if (existing['engine'] != 'appspec.v1' ||
          existing['ownerId'] != actor ||
          existing['workspaceId'] != workspace[r'$id'])
        throw const ServiceException('id_conflict', 409);
      final receipt = await _authorizedReceipt(
        actor,
        id,
        operationId,
        request,
        'owner',
      );
      if (receipt != null) return receipt;
      _require(access, 'owner');
      throw const ServiceException('id_conflict', 409);
    }
    try {
      return await _transaction((tx) async {
        await store.update('workspaces', workspace[r'$id'] as String, {
          'guard': _nonce(),
        }, transactionId: tx);
        final current = await _workspace(
          actor,
          workspace[r'$id'],
          transactionId: tx,
        );
        await _ensureMembership(
          current,
          actor,
          tx,
          owner: current['ownerId'] == actor,
        );
        final apps = await store.list('apps', {
          'workspaceId': workspace[r'$id'] as String,
        }, transactionId: tx);
        if (apps.length >= 100)
          throw const ServiceException('quota_exceeded', 429);
        final app = await store.create('apps', id, {
          'workspaceId': current[r'$id'],
          'ownerId': actor,
          'name': name,
          'guard': _nonce(),
          'draftRevision': 0,
          'publishedRevision': 0,
          'headRevision': 0,
          'archived': false,
          'engine': 'appspec.v1',
          'specVersionId': null,
          'specVersionNumber': 0,
          'controlRevision': 0,
        }, transactionId: tx);
        final access = await _specChanged(
          actor,
          AppAccess(app, current, 'owner'),
          operationId,
          'spec.createApp',
          tx,
        );
        final response = <String, dynamic>{
          'app': await _publicSpecApp(actor, access, tx),
        };
        await _saveReceipt(
          actor,
          id,
          operationId,
          request,
          response,
          tx,
          maximumBytes: _specResponseBytes,
        );
        return response;
      });
    } on ServiceException catch (error) {
      if (error.code == 'transaction_conflict' &&
          await store.get('apps', id) != null) {
        final old = await _authorizedReceipt(
          actor,
          id,
          operationId,
          request,
          'owner',
        );
        if (old != null) return old;
      }
      rethrow;
    }
  }

  Future<Row> _specSave(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'operationId',
      'expectedRevision',
      'expectedVersionId',
      'spec',
    });
    final revision = _revision(input['expectedRevision']);
    if (!input.containsKey('expectedVersionId'))
      throw const ServiceException('invalid_request', 400);
    final base = _versionId(input['expectedVersionId']);
    final candidate = spec.AppSpec.parse(
      jsonEncode(jsonObject(input['spec'], 'invalid_spec')),
    );
    final normalized = {...input, 'spec': candidate.toJson()};
    return _mutate(
      actor,
      normalized,
      'build',
      (tx, access) async {
        _specEngine(access);
        if (access.role != 'owner' && access.app['specVersionId'] == null)
          throw const ServiceException('not_found', 404);
        final draft = await _specDraft(actor, access, tx);
        if ((draft?['revision'] ?? 0) != revision || revision >= 2147483646)
          throw const ServiceException('revision_conflict', 409);
        if (access.app['specVersionId'] != base)
          throw const ServiceException('definition_conflict', 409);
        await _manualSupersede(actor, access, tx);
        final id = _identity('s', [access.app[r'$id'] as String, actor]);
        final data = <String, dynamic>{
          'workspaceId': access.app['workspaceId'],
          'appId': access.app[r'$id'],
          'actorId': actor,
          'revision': revision + 1,
          'baseVersionId': base,
          'candidateHash': candidate.hash,
          'publishedVersionId': null,
          'updatedAt': clock().toUtc().toIso8601String(),
          'specJson': candidate.canonical,
        };
        if (draft == null) {
          await store.create('spec_drafts', id, data, transactionId: tx);
        } else {
          await store.update('spec_drafts', id, data, transactionId: tx);
        }
        await _syncMedia(
          actor,
          access,
          _definitionImages(candidate),
          'draft',
          id,
          tx,
        );
        final current = await _specChanged(
          actor,
          access,
          input['operationId'] as String,
          'spec.saveDraft',
          tx,
        );
        return {'app': await _publicSpecApp(actor, current, tx)};
      },
      requestBytes: _specRequestBytes,
      responseBytes: _specResponseBytes,
    );
  }

  Future<Row> _specReview(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'expectedRevision',
      'enabledRuleIds',
      'activateExistingRecordIds',
    });
    final revision = _revision(input['expectedRevision']);
    final rules = _selected(input['enabledRuleIds'], spec.Limits.rules);
    final records = _selected(
      input['activateExistingRecordIds'],
      spec.Limits.activationScope,
      records: true,
    );
    return _specRead(actor, _validId(input['appId']), (access, tx) async {
      _require(access, 'build', writable: false);
      final draft = await _specDraft(actor, access, tx);
      if (draft == null || draft['revision'] != revision)
        throw const ServiceException('revision_conflict', 409);
      if (draft['publishedVersionId'] != null)
        throw const ServiceException('definition_conflict', 409);
      final generation = await _generationForApp(actor, access, tx);
      if (generation != null && generation['status'] != 'preview ready')
        throw const ServiceException('generation_pending', 409);
      final candidate = spec.AppSpec.parse(draft['specJson'] as String);
      await _validateMedia(actor, access, _definitionImages(candidate), tx);
      if (rules.any(
        (id) => !candidate.automationRequests.any((rule) => rule.id == id),
      ))
        throw const ServiceException('invalid_request', 400);
      final prior = access.app['specVersionId'] == null
          ? null
          : await _activeSpec(access, tx);
      for (final id in records) await _specRecord(access, id, tx);
      return {
        'review': {
          'candidateHash': candidate.hash,
          'expectedRevision': revision,
          'baseVersionId': draft['baseVersionId'],
          'currentVersionId': access.app['specVersionId'],
          'reviewHash': _reviewHash(candidate.hash, rules, records),
          'changes': candidate.diff(prior?.definition),
          'compatibilityErrors':
              prior?.definition.compatibilityErrors(candidate) ?? <String>[],
          'enabledRuleIds': rules,
          'activateExistingRecordIds': records,
        },
      };
    });
  }

  Future<Row> _specPublish(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'operationId',
      'expectedRevision',
      'expectedVersionId',
      'candidateHash',
      'reviewHash',
      'enabledRuleIds',
      'activateExistingRecordIds',
    });
    final revision = _revision(input['expectedRevision']);
    if (!input.containsKey('expectedVersionId'))
      throw const ServiceException('invalid_request', 400);
    final base = _versionId(input['expectedVersionId']);
    final hash = _hash(input['candidateHash']),
        reviewHash = _hash(input['reviewHash']);
    final rules = _selected(input['enabledRuleIds'], spec.Limits.rules);
    final records = _selected(
      input['activateExistingRecordIds'],
      spec.Limits.activationScope,
      records: true,
    );
    return _mutate(
      actor,
      input,
      'build',
      (tx, access) async {
        _specEngine(access);
        final draft = await _specDraft(actor, access, tx);
        if (draft == null || draft['revision'] != revision)
          throw const ServiceException('revision_conflict', 409);
        if (draft['publishedVersionId'] != null)
          throw const ServiceException('definition_conflict', 409);
        final generation = await _generationForApp(actor, access, tx);
        if (generation != null && generation['status'] != 'preview ready')
          throw const ServiceException('generation_pending', 409);
        if (access.app['specVersionId'] != base ||
            draft['baseVersionId'] != base ||
            draft['candidateHash'] != hash)
          throw const ServiceException('definition_conflict', 409);
        final candidate = spec.AppSpec.parse(draft['specJson'] as String);
        if (candidate.hash != hash)
          throw const ServiceException('integrity_error', 500);
        if (_reviewHash(hash, rules, records) != reviewHash)
          throw const ServiceException('invalid_review', 400);
        if (rules.any(
          (id) => !candidate.automationRequests.any((rule) => rule.id == id),
        ))
          throw const ServiceException('invalid_request', 400);
        // Enabling effects requires the configured worker. Private media is
        // validated and retained atomically below, independently of reminders.
        if (rules.isNotEmpty && !remindersEnabled)
          throw const ServiceException('capability_unavailable', 409);
        if (base != null) {
          final prior = await _activeSpec(access, tx, expected: base);
          if (prior.definition.compatibilityErrors(candidate).isNotEmpty)
            throw const ServiceException('incompatible_definition', 409);
        }
        for (final id in records) await _specRecord(access, id, tx);
        final number = _storedRevision(access.app, 'specVersionNumber');
        if (number >= 2147483646)
          throw const ServiceException('revision_conflict', 409);
        final versionId = _identity('v', [
          access.app[r'$id'] as String,
          '${number + 1}',
        ]);
        await store.create('spec_versions', versionId, {
          'workspaceId': access.app['workspaceId'],
          'appId': access.app[r'$id'],
          'number': number + 1,
          'specJson': candidate.canonical,
          'hash': candidate.hash,
          'publisherId': actor,
          'createdAt': clock().toUtc().toIso8601String(),
        }, transactionId: tx);
        await _syncMedia(
          actor,
          access,
          _definitionImages(candidate),
          'version',
          versionId,
          tx,
        );
        if (remindersEnabled)
          await _reconcileRules(
            actor,
            access,
            candidate,
            versionId,
            rules,
            records,
            input['operationId'] as String,
            tx,
          );
        final app = await store.update('apps', access.app[r'$id'] as String, {
          'specVersionId': versionId,
          'specVersionNumber': number + 1,
          'name': candidate.name,
        }, transactionId: tx);
        await store.update('spec_drafts', draft[r'$id'] as String, {
          'publishedVersionId': versionId,
        }, transactionId: tx);
        final current = await _specChanged(
          actor,
          AppAccess(app, access.workspace, access.role),
          input['operationId'] as String,
          'spec.publish',
          tx,
          payload: {
            'enabledRuleIds': rules,
            'activateExistingRecordIds': records,
          },
        );
        return {'app': await _publicSpecApp(actor, current, tx)};
      },
      requestBytes: _specRequestBytes,
      responseBytes: _specResponseBytes,
    );
  }

  Future<Row> _executeSpec(String actor, Row input) async {
    if ((input['op'] as String).startsWith('spec.media.'))
      return _executeMedia(actor, input);
    switch (input['op']) {
      case 'spec.capabilities':
        _inputKeys(input, {'op'});
        return {
          'apiVersion': 1,
          'formatVersions': [1],
          'parserCapabilities': spec.capabilities.toList(),
          'actionCapabilities': spec.actionCapabilities.toList(),
          'queryOperators': ['eq', 'in', 'contains', 'gte', 'lte', 'lt'],
          'effects': remindersEnabled
              ? ['notifyOwner', 'notifyAssignee', 'notifyActiveClaimants']
              : <String>[],
          'generation': aiProvider != null,
          'guidance': guidanceProvider != null,
          'privateMedia': media != null,
          'invalidations': {'mode': 'poll.v1', 'minimumIntervalMs': 15000},
        };
      case 'spec.templates':
        _inputKeys(input, {'op'});
        return {
          'templates': spec
              .starterTemplates()
              .entries
              .map(
                (entry) => {
                  'key': entry.key,
                  'name': entry.value.name,
                  'spec': entry.value.toJson(),
                },
              )
              .toList(),
        };
      case 'spec.createApp':
        return _specCreate(actor, input);
      case 'spec.instantiate':
        return _specInstantiate(actor, input);
      case 'spec.remix':
        return _specRemix(actor, input);
      case 'spec.launcher':
        return _specLauncher(actor, input);
      case 'spec.appAccess':
        return _specAppAccess(actor, input);
      case 'spec.listDrafts':
        return _specListDrafts(actor, input);
      case 'spec.listVersions':
        return _specListVersions(actor, input);
      case 'spec.getVersion':
        return _specGetVersion(actor, input);
      case 'spec.setPinned':
        return _specSetPinned(actor, input);
      case 'spec.saveDraft':
        return _specSave(actor, input);
      case 'spec.review':
        return _specReview(actor, input);
      case 'spec.publish':
        return _specPublish(actor, input);
      case 'spec.watch':
        return _specWatch(actor, input);
      case 'spec.getApp':
        _inputKeys(input, {'op', 'appId'});
        return _specRead(actor, _validId(input['appId']), (access, tx) async {
          if (access.role != 'owner' && access.app['specVersionId'] == null)
            throw const ServiceException('not_found', 404);
          return {'app': await _publicSpecApp(actor, access, tx)};
        });
      case 'spec.execute':
        return _specExecute(actor, input);
      case 'spec.query':
        return _specQuery(actor, input);
      case 'spec.summary':
        return _specSummary(actor, input);
      case 'spec.aggregate':
        return _specAggregate(actor, input);
      case 'spec.getRecord':
        _inputKeys(input, {'op', 'appId', 'versionId', 'recordId'});
        final versionId = _validId(input['versionId']);
        return _specRead(actor, _validId(input['appId']), (access, tx) async {
          final version = await _activeSpec(access, tx, expected: versionId);
          final record = await _specRecord(
            access,
            _validId(input['recordId']),
            tx,
          );
          return {
            'record': await _specRecordDto(
              actor,
              access,
              version.definition,
              record,
              tx,
            ),
            'versionId': versionId,
          };
        });
      case 'spec.generate':
        return _generate(actor, input);
      case 'spec.getGeneration':
        return _getGeneration(actor, input);
      case 'spec.keepPrevious':
        return _keepPrevious(actor, input);
      case 'spec.guidance':
        return _guidance(actor, input);
      case 'spec.reminderState':
        return _reminderStates(actor, input);
      case 'spec.inbox':
        return _inbox(actor, input);
      case 'spec.readNotification':
        return _readNotification(actor, input);
      case 'spec.runs':
        return _runHistory(actor, input);
      default:
        throw const ServiceException('unknown_operation', 400);
    }
  }
}
