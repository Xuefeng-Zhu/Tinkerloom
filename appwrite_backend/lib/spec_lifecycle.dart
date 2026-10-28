part of 'service.dart';

extension _SpecLifecycle on PlatformService {
  Future<AppAccess> _metadataAccess(
      String actor, String appId, String? tx) async {
    final rows = await store.list('apps', {r'$id': appId},
        transactionId: tx,
        limit: 1,
        select: [
          r'$id',
          'workspaceId',
          'ownerId',
          'name',
          'engine',
          'archived',
          'guard',
          'publishedRevision',
          'specVersionId'
        ]);
    if (rows.isEmpty) throw const ServiceException('not_found', 404);
    final app = rows.single;
    if (app[r'$id'] != appId)
      throw const ServiceException('integrity_error', 500);
    final workspace =
        await _workspace(actor, app['workspaceId'], transactionId: tx);
    if (app['ownerId'] == actor) return AppAccess(app, workspace, 'owner');
    final grant = await _grant(appId, actor, transactionId: tx);
    if (!_validGrant(grant, app, actor))
      throw const ServiceException('not_found', 404);
    return AppAccess(app, workspace, grant!['role'] as String);
  }

  Future<Row> _specAppAccess(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId'});
    final appId = _validId(input['appId']),
        initial = await _metadataAccess(actor, appId, null);
    _publishedOrOwner(initial);
    return _workspaceCatalog(actor, initial.workspace[r'$id'] as String,
        (workspace, tx) async {
      final access = await _metadataAccess(actor, appId, tx);
      _publishedOrOwner(access);
      if (access.app['workspaceId'] != workspace[r'$id'])
        throw const ServiceException('not_found', 404);
      final response = _appSummary(access);
      if (access.app['engine'] == 'appspec.v1') {
        final version = access.app['specVersionId'] == null
            ? null
            : await _activeSpec(access, tx);
        response['capabilities'] = {
          ...access.capabilities,
          'writeRecords': version?.definition.actions.any((action) =>
                  _specAllowed(access, version.definition, action)) ??
              false
        };
      }
      return {'app': response};
    });
  }

  int _lifecycleLimit(Object? value, {int maximum = 50}) {
    if (value == null) return 20;
    if (value is! int || value < 1 || value > maximum)
      throw const ServiceException('invalid_request', 400);
    return value;
  }

  String? _lifecycleTime(Object? value) {
    if (value == null) return null;
    if (value is! String) throw const ServiceException('integrity_error', 500);
    final instant = DateTime.tryParse(value);
    if (instant == null) throw const ServiceException('integrity_error', 500);
    // Service-owned metadata can arrive from Appwrite as +00:00. This does not
    // change the strict, lossless AppSpec timestamp-field contract.
    return instant.toUtc().toIso8601String();
  }

  void _publishedOrOwner(AppAccess access) {
    if (access.role != 'owner' &&
        (access.app['engine'] == 'appspec.v1'
            ? access.app['specVersionId'] == null
            : _storedRevision(access.app, 'publishedRevision') == 0))
      throw const ServiceException('not_found', 404);
  }

  Row _versionSummary(_SpecVersion version) => {
        'id': version.row[r'$id'],
        'number': version.row['number'],
        'hash': version.row['hash'],
        'name': version.definition.name,
        'theme': version.definition.theme,
        'icon': version.definition.icon,
        'publisherId': version.row['publisherId'],
        'createdAt': _lifecycleTime(version.row['createdAt']),
      };

  Future<Row> _specListVersions(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'beforeNumber', 'limit'});
    final limit = _lifecycleLimit(input['limit']);
    return _specRead(actor, _validId(input['appId']), (access, tx) async {
      _publishedOrOwner(access);
      final current = _storedRevision(access.app, 'specVersionNumber');
      final before = input['beforeNumber'] ?? current + 1;
      if (before is! int || before < 1 || before > current + 1)
        throw const ServiceException('invalid_request', 400);
      final versions = <Row>[];
      var number = before - 1;
      for (; number >= 1 && versions.length < limit; number--) {
        final version = await _specVersion(access,
            _identity('v', [access.app[r'$id'] as String, '$number']), tx);
        if (version.row['number'] != number)
          throw const ServiceException('integrity_error', 500);
        versions.add(_versionSummary(version));
      }
      return {
        'versions': versions,
        'currentVersionId': access.app['specVersionId'],
        'nextBeforeNumber': number >= 1 ? number + 1 : null,
      };
    });
  }

  Future<Row> _specGetVersion(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'versionId'});
    final versionId = _validId(input['versionId']);
    return _specRead(actor, _validId(input['appId']), (access, tx) async {
      _publishedOrOwner(access);
      final version = await _specVersion(access, versionId, tx);
      return {
        'version': {
          ..._versionSummary(version),
          'spec': version.definition.toJson()
        },
        'currentVersionId': access.app['specVersionId'],
      };
    });
  }

  /// Every mutation in a workspace stages this affected row. One workspace
  /// guard protects a catalog snapshot without >100 staged app-guard writes.
  Future<Row> _workspaceCatalog(String actor, String workspaceId,
      Future<Row> Function(Row workspace, String tx) read) async {
    final initial = await _workspace(actor, workspaceId);
    return _transaction((tx) async {
      await store.update(
          'workspaces', initial[r'$id'] as String, {'guard': _nonce()},
          transactionId: tx);
      final current = await _workspace(actor, workspaceId, transactionId: tx);
      final response = await read(current, tx);
      if (utf8.encode(jsonEncode(response)).length > _specResponseBytes)
        throw const ServiceException('response_too_large', 413);
      return response;
    });
  }

  Future<List<AppAccess>> _lifecycleApps(
      String actor, Row workspace, String tx) async {
    final workspaceId = workspace[r'$id'] as String;
    final apps = await store.list('apps', {'workspaceId': workspaceId},
        transactionId: tx,
        select: [
          r'$id',
          'workspaceId',
          'ownerId',
          'name',
          'engine',
          'archived',
          'specVersionId',
          'specVersionNumber',
          'controlRevision',
          r'$createdAt',
          'publishedRevision',
          'draftRevision',
          'headRevision',
          'draftJson',
        ]);
    final grants = await store.list(
        'grants', {'workspaceId': workspaceId, 'actorId': actor},
        transactionId: tx);
    final byApp = <String, Row>{};
    for (final grant in grants) {
      if (grant['workspaceId'] != workspaceId ||
          grant['actorId'] != actor ||
          grant['appId'] is! String ||
          byApp.containsKey(grant['appId']))
        throw const ServiceException('integrity_error', 500);
      byApp[grant['appId'] as String] = grant;
    }
    final result = <AppAccess>[];
    for (final app in apps) {
      if (app['workspaceId'] != workspaceId)
        throw const ServiceException('integrity_error', 500);
      if (app['ownerId'] == actor) {
        result.add(AppAccess(app, workspace, 'owner'));
      } else if (_validGrant(byApp[app[r'$id']], app, actor) &&
          (app['engine'] == 'appspec.v1'
              ? app['specVersionId'] != null
              : _storedRevision(app, 'publishedRevision') > 0)) {
        result.add(
            AppAccess(app, workspace, byApp[app[r'$id']]!['role'] as String));
      }
    }
    result.sort((a, b) {
      final at = _lifecycleTime(a.app[r'$createdAt']),
          bt = _lifecycleTime(b.app[r'$createdAt']);
      if (at == null || bt == null) {
        if (at != bt) return at == null ? 1 : -1;
      } else {
        final order = DateTime.parse(bt).compareTo(DateTime.parse(at));
        if (order != 0) return order;
      }
      return (b.app[r'$id'] as String).compareTo(a.app[r'$id'] as String);
    });
    return result;
  }

  String? _catalogAfter(
      Row input, String actor, String workspaceId, String kind) {
    if (input['cursor'] == null) return null;
    try {
      final cursor = jsonObject(
          jsonDecode(utf8.decode(base64Url
              .decode(boundedText(input['cursor'], 4096, 'invalid_request')))),
          'invalid_request');
      if (cursor.keys.toSet().difference({'scope', 'after'}).isNotEmpty ||
          cursor['scope'] !=
              spec.hashJson({
                'actor': actor,
                'workspace': workspaceId,
                'kind': kind,
                'pinnedOnly': input['pinnedOnly'] == true
              })) throw const FormatException();
      return _validId(cursor['after']);
    } catch (_) {
      throw const ServiceException('invalid_request', 400);
    }
  }

  String _catalogCursor(String actor, String workspaceId, String kind,
          String after, bool pinnedOnly) =>
      base64Url.encode(utf8.encode(jsonEncode({
        'scope': spec.hashJson({
          'actor': actor,
          'workspace': workspaceId,
          'kind': kind,
          'pinnedOnly': pinnedOnly
        }),
        'after': after,
      })));

  Future<Map<String, Row>> _ownDraftMetadata(
      String actor, String workspaceId, String tx,
      {String table = 'spec_drafts'}) async {
    final rows =
        await store.list(table, {'workspaceId': workspaceId, 'actorId': actor},
            transactionId: tx,
            select: [
              r'$id',
              'workspaceId',
              'appId',
              'actorId',
              'revision',
              if (table == 'spec_drafts') ...[
                'baseVersionId',
                'candidateHash',
                'publishedVersionId',
                'updatedAt'
              ] else ...[
                'candidateRevision',
                'basePublishedRevision'
              ],
              r'$updatedAt',
            ]);
    final result = <String, Row>{};
    for (final row in rows) {
      if (row['workspaceId'] != workspaceId ||
          row['actorId'] != actor ||
          row['appId'] is! String ||
          result.containsKey(row['appId']))
        throw const ServiceException('integrity_error', 500);
      result[row['appId'] as String] = row;
    }
    return result;
  }

  Future<Row?> _ownShortcut(String actor, AppAccess access, String tx) async {
    final shortcut = await store.get(
        'shortcuts', _identity('k', [access.app[r'$id'] as String, actor]),
        transactionId: tx);
    if (shortcut != null &&
        (shortcut['actorId'] != actor ||
            shortcut['appId'] != access.app[r'$id'] ||
            shortcut['workspaceId'] != access.app['workspaceId']))
      throw const ServiceException('integrity_error', 500);
    return shortcut;
  }

  Future<Row?> _draftSummary(String actor, AppAccess access, String tx) async {
    if (!access.builder || access.archived) return null;
    if (access.app['engine'] != 'appspec.v1') {
      final draft = await _privateDraft(actor, access, transactionId: tx);
      if (draft == null ||
          draft['candidateRevision'] == draft['basePublishedRevision'])
        return null;
      final definition = _definition(draft, 'definitionJson')!;
      return {
        'engine': 'bounded.v1',
        'appId': access.app[r'$id'],
        'workspaceId': access.app['workspaceId'],
        'name': definition['title'],
        'revision': draft['revision'],
        'candidateRevision': draft['candidateRevision'],
        'basePublishedRevision': draft['basePublishedRevision'],
        'currentPublishedRevision':
            _storedRevision(access.app, 'publishedRevision'),
        'stale': draft['basePublishedRevision'] !=
            _storedRevision(access.app, 'publishedRevision'),
        'updatedAt': _lifecycleTime(draft[r'$updatedAt'])
      };
    }
    final draft = await _specDraft(actor, access, tx);
    if (draft == null || draft['publishedVersionId'] != null) return null;
    final definition = spec.AppSpec.parse(draft['specJson'] as String);
    if (definition.hash != draft['candidateHash'] ||
        definition.canonical != draft['specJson'])
      throw const ServiceException('integrity_error', 500);
    return {
      'engine': 'appspec.v1',
      'appId': access.app[r'$id'],
      'workspaceId': access.app['workspaceId'],
      'name': definition.name,
      'revision': draft['revision'],
      'candidateHash': draft['candidateHash'],
      'baseVersionId': draft['baseVersionId'],
      'currentVersionId': access.app['specVersionId'],
      'stale': draft['baseVersionId'] != access.app['specVersionId'],
      'updatedAt': _lifecycleTime(draft['updatedAt'] ?? draft[r'$updatedAt'])
    };
  }

  Future<Map<String, Row>> _ownShortcuts(
      String actor, String workspaceId, String tx) async {
    final rows = await store.list(
        'shortcuts', {'actorId': actor, 'workspaceId': workspaceId},
        transactionId: tx);
    final result = <String, Row>{};
    for (final row in rows) {
      if (row['actorId'] != actor ||
          row['workspaceId'] != workspaceId ||
          row['appId'] is! String ||
          row['pinned'] is! bool ||
          result.containsKey(row['appId']))
        throw const ServiceException('integrity_error', 500);
      result[row['appId'] as String] = row;
    }
    return result;
  }

  int _catalogStart(List<AppAccess> apps, String? after) {
    if (after == null) return 0;
    final index = apps.indexWhere((access) => access.app[r'$id'] == after);
    if (index < 0) throw const ServiceException('revision_conflict', 409);
    return index + 1;
  }

  Future<Row> _launcherStats(AppAccess access, String tx) async {
    final appId = access.app[r'$id'] as String;
    if (access.app['engine'] != 'appspec.v1') {
      final records = await _scanSpecRows('records',
          {'appId': appId, 'ownerId': access.app['ownerId'] as String}, tx,
          select: [r'$id', 'appId', 'ownerId']);
      if (records.any((row) =>
          row['appId'] != appId || row['ownerId'] != access.app['ownerId']))
        throw const ServiceException('integrity_error', 500);
      return {'recordCount': records.length, 'availablePlaces': 0};
    }
    final records = await _scanSpecRows('spec_records', {'appId': appId}, tx,
        select: [r'$id', 'appId', 'workspaceId', 'deleted']);
    if (records.any((row) =>
        row['appId'] != appId ||
        row['workspaceId'] != access.app['workspaceId']))
      throw const ServiceException('integrity_error', 500);
    final live = {
      for (final row in records)
        if (row['deleted'] == false) row[r'$id']
    };
    final pools = await _scanSpecRows('spec_pools', {'appId': appId}, tx,
        select: [
          r'$id',
          'appId',
          'workspaceId',
          'recordId',
          'capacity',
          'allocated'
        ]);
    var available = 0;
    for (final pool in pools) {
      if (pool['appId'] != appId ||
          pool['workspaceId'] != access.app['workspaceId'] ||
          pool['capacity'] is! int ||
          pool['allocated'] is! int ||
          pool['capacity'] < 0 ||
          pool['capacity'] > 10000 ||
          pool['allocated'] < 0 ||
          pool['allocated'] > pool['capacity'])
        throw const ServiceException('integrity_error', 500);
      if (live.contains(pool['recordId']))
        available += (pool['capacity'] as int) - (pool['allocated'] as int);
    }
    return {'recordCount': live.length, 'availablePlaces': available};
  }

  Future<Row> _specLauncher(String actor, Row input) async {
    _inputKeys(input, {'op', 'workspaceId', 'cursor', 'limit', 'pinnedOnly'});
    if (input.containsKey('pinnedOnly') && input['pinnedOnly'] is! bool)
      throw const ServiceException('invalid_request', 400);
    final workspaceId = _validId(input['workspaceId']),
        limit = _lifecycleLimit(input['limit']),
        after = _catalogAfter(input, actor, workspaceId, 'launcher');
    return _workspaceCatalog(actor, workspaceId, (workspace, tx) async {
      final shortcuts = await _ownShortcuts(actor, workspaceId, tx);
      final apps = (await _lifecycleApps(actor, workspace, tx))
          .where((access) =>
              input['pinnedOnly'] != true ||
              shortcuts[access.app[r'$id']]?['pinned'] == true)
          .toList();
      final selected =
              apps.skip(_catalogStart(apps, after)).take(limit + 1).toList(),
          visible = <Row>[];
      for (final access in selected.take(limit)) {
        final full = access.app['engine'] == 'appspec.v1';
        final versionId = access.app['specVersionId'] as String?;
        final version = !full || versionId == null
            ? null
            : await _specVersion(access, versionId, tx);
        final allowed = version?.definition.actions
                .where((action) =>
                    _specAllowed(access, version.definition, action))
                .map((action) => action.id)
                .toList() ??
            <String>[];
        final shortcut = shortcuts[access.app[r'$id']];
        visible.add({
          ..._appSummary(access),
          'capabilities': {
            ...access.capabilities,
            'writeRecords':
                full ? allowed.isNotEmpty : access.capabilities['writeRecords']
          },
          if (full) 'allowedActions': allowed,
          'pinned': shortcut?['pinned'] == true,
          'pinRevision': shortcut?['revision'] ?? 0,
          'createdAt': _lifecycleTime(access.app[r'$createdAt']),
          ...await _launcherStats(access, tx),
          'version': version == null ? null : _versionSummary(version),
          if (!full)
            'publishedRevision':
                _storedRevision(access.app, 'publishedRevision'),
          'draft': await _draftSummary(actor, access, tx)
        });
      }
      return {
        'apps': visible,
        'nextCursor': selected.length > limit
            ? _catalogCursor(actor, workspaceId, 'launcher',
                visible.last['id'] as String, input['pinnedOnly'] == true)
            : null
      };
    });
  }

  Future<Row> _specListDrafts(String actor, Row input) async {
    _inputKeys(input, {'op', 'workspaceId', 'cursor', 'limit'});
    final workspaceId = _validId(input['workspaceId']),
        limit = _lifecycleLimit(input['limit']),
        after = _catalogAfter(input, actor, workspaceId, 'drafts');
    return _workspaceCatalog(actor, workspaceId, (workspace, tx) async {
      final fullDrafts = await _ownDraftMetadata(actor, workspaceId, tx),
          boundedDrafts =
              await _ownDraftMetadata(actor, workspaceId, tx, table: 'drafts');
      final eligible =
          (await _lifecycleApps(actor, workspace, tx)).where((access) {
        if (!access.builder || access.archived) return false;
        if (access.app['engine'] == 'appspec.v1')
          return fullDrafts[access.app[r'$id']] != null &&
              fullDrafts[access.app[r'$id']]!['publishedVersionId'] == null;
        final meta = boundedDrafts[access.app[r'$id']];
        return meta != null
            ? meta['candidateRevision'] != meta['basePublishedRevision']
            : access.app['ownerId'] == actor &&
                access.app['headRevision'] == null &&
                _storedRevision(access.app, 'draftRevision') > 0 &&
                _storedRevision(access.app, 'draftRevision') !=
                    _storedRevision(access.app, 'publishedRevision');
      }).toList();
      final selected = eligible
              .skip(_catalogStart(eligible, after))
              .take(limit + 1)
              .toList(),
          result = <Row>[];
      for (final access in selected.take(limit)) {
        final summary = await _draftSummary(actor, access, tx);
        if (summary == null)
          throw const ServiceException('integrity_error', 500);
        result.add(summary);
      }
      return {
        'drafts': result,
        'nextCursor': selected.length > limit
            ? _catalogCursor(actor, workspaceId, 'drafts',
                result.last['appId'] as String, false)
            : null
      };
    });
  }

  Future<Row> _specSetPinned(String actor, Row input) async {
    _inputKeys(
        input, {'op', 'appId', 'operationId', 'expectedRevision', 'pinned'});
    final expected = _revision(input['expectedRevision']);
    if (input['pinned'] is! bool)
      throw const ServiceException('invalid_request', 400);
    return _mutate(actor, input, 'read', (tx, access) async {
      _publishedOrOwner(access);
      final old = await _ownShortcut(actor, access, tx);
      if ((old?['revision'] ?? 0) != expected || expected >= 2147483646)
        throw const ServiceException('revision_conflict', 409);
      final id = _identity('k', [access.app[r'$id'] as String, actor]);
      final data = {
        'workspaceId': access.app['workspaceId'],
        'appId': access.app[r'$id'],
        'actorId': actor,
        'pinned': input['pinned'],
        'revision': expected + 1,
        'updatedAt': clock().toUtc().toIso8601String()
      };
      if (old == null) {
        await store.create('shortcuts', id, data, transactionId: tx);
      } else {
        await store.update('shortcuts', id, data, transactionId: tx);
      }
      // A shortcut is actor-private preference state, not a business mutation or
      // an effect-enrollment event. Its exact private receipt commits atomically.
      return {
        'shortcut': {
          'appId': access.app[r'$id'],
          'pinned': input['pinned'],
          'revision': expected + 1
        }
      };
    }, writable: false);
  }

  spec.AppSpec _withoutAssets(spec.AppSpec source) {
    final json = jsonObject(jsonDecode(source.canonical), 'invalid_spec');
    for (final view in (json['views'] as List).cast<Map>()) {
      if (view['type'] == 'banner' && view['options'] is Map)
        (view['options'] as Map).remove('imageAssetId');
    }
    return spec.AppSpec.parse(jsonEncode(json));
  }

  Future<Row> _structureCreate(String actor, Row input,
      {spec.AppSpec? template}) async {
    final id = _validId(input['id']),
        operationId = _validId(input['operationId']),
        workspaceId = _validId(input['workspaceId']);
    final sourceId = template == null ? _validId(input['sourceAppId']) : null;
    final sourceVersionId =
        template == null ? _validId(input['sourceVersionId']) : null;
    final request = _request(input, maximumBytes: _specRequestBytes);
    Future<AppAccess?> source(String? tx, {bool active = false}) async {
      if (sourceId == null) return null;
      final access = await _access(actor, sourceId, transactionId: tx);
      _specEngine(access);
      _publishedOrOwner(access);
      if (active) {
        await _activeSpec(access, tx, expected: sourceVersionId);
      } else {
        await _specVersion(access, sourceVersionId!, tx);
      }
      return access;
    }

    final destination = await _workspace(actor, workspaceId);
    final initialSource = await source(null);
    Future<Row?> receipt() async {
      await source(null);
      await _workspace(actor, workspaceId);
      final response = await _receipt(actor, id, operationId, request);
      if (response != null) {
        final target = await _access(actor, id);
        _require(target, 'owner', writable: false);
        if (target.app['workspaceId'] != workspaceId ||
            target.app['engine'] != 'appspec.v1')
          throw const ServiceException('not_found', 404);
        await source(null);
        await _workspace(actor, workspaceId);
      }
      return response;
    }

    final prior = await receipt();
    if (prior != null) return prior;
    try {
      return await _transaction((tx) async {
        AppAccess? currentSource;
        if (initialSource != null)
          currentSource = await _stageAccess(actor, initialSource, tx);
        if (initialSource?.workspace[r'$id'] != workspaceId)
          await store.update(
              'workspaces', destination[r'$id'] as String, {'guard': _nonce()},
              transactionId: tx);
        final workspace =
            await _workspace(actor, workspaceId, transactionId: tx);
        await _ensureMembership(workspace, actor, tx,
            owner: workspace['ownerId'] == actor);
        if (currentSource != null) await source(tx, active: true);
        final existing = await store.get('apps', id, transactionId: tx);
        if (existing != null) {
          final target = await _access(actor, id, transactionId: tx);
          _require(target, 'owner', writable: false);
          final old = await _receipt(actor, id, operationId, request,
              transactionId: tx);
          if (old != null) return old;
          throw const ServiceException('id_conflict', 409);
        }
        if ((await store.list('apps', {'workspaceId': workspaceId},
                    transactionId: tx))
                .length >=
            100) throw const ServiceException('quota_exceeded', 429);
        final definition = _withoutAssets(template ??
            (await _specVersion(currentSource!, sourceVersionId!, tx))
                .definition);
        final versionId = _identity('v', [id, '1']);
        final app = await store.create(
            'apps',
            id,
            {
              'workspaceId': workspaceId,
              'ownerId': actor,
              'name': definition.name,
              'guard': _nonce(),
              'draftRevision': 0,
              'publishedRevision': 0,
              'headRevision': 0,
              'archived': false,
              'engine': 'appspec.v1',
              'specVersionId': versionId,
              'specVersionNumber': 1,
              'controlRevision': 0,
            },
            transactionId: tx);
        await store.create(
            'spec_versions',
            versionId,
            {
              'workspaceId': workspaceId,
              'appId': id,
              'number': 1,
              'hash': definition.hash,
              'specJson': definition.canonical,
              'publisherId': actor,
              'createdAt': clock().toUtc().toIso8601String()
            },
            transactionId: tx);
        await store.create(
            'shortcuts',
            _identity('k', [id, actor]),
            {
              'workspaceId': workspaceId,
              'appId': id,
              'actorId': actor,
              'pinned': true,
              'revision': 1,
              'updatedAt': clock().toUtc().toIso8601String(),
            },
            transactionId: tx);
        final access = await _specChanged(
            actor,
            AppAccess(app, workspace, 'owner'),
            operationId,
            input['op'] as String,
            tx,
            payload: {
              'enabledRuleIds': <String>[],
              'activateExistingRecordIds': <String>[]
            });
        final response = <String, dynamic>{
          'app': await _publicSpecApp(actor, access, tx)
        };
        await _saveReceipt(actor, id, operationId, request, response, tx,
            maximumBytes: _specResponseBytes);
        return response;
      });
    } on ServiceException catch (error) {
      if (error.code == 'transaction_conflict' ||
          error.code == 'definition_conflict') {
        final old = await receipt();
        if (old != null) return old;
      }
      rethrow;
    }
  }

  Future<Row> _specInstantiate(String actor, Row input) async {
    _inputKeys(
        input, {'op', 'id', 'workspaceId', 'operationId', 'templateKey'});
    final template = spec.starterTemplates()[input['templateKey']];
    if (template == null) throw const ServiceException('invalid_request', 400);
    return _structureCreate(actor, input, template: template);
  }

  Future<Row> _specRemix(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'id',
      'workspaceId',
      'operationId',
      'sourceAppId',
      'sourceVersionId'
    });
    return _structureCreate(actor, input);
  }
}
