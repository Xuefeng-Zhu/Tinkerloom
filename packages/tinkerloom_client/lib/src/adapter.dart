part of '../tinkerloom_client.dart';

extension _PresentationAdapter on Client {
  Map<String, dynamic> _remember(Object? value) {
    final app = _map(value), id = _id(app['id']);
    _id(app['workspaceId']);
    if (app['role'] is! String ||
        app['archived'] is! bool ||
        app['name'] is! String)
      throw NestError(
        category: 'invalid_response',
        message: 'The app response is incomplete.',
      );
    final version = app['version'];
    if (version != null) {
      final v = _map(version);
      _id(v['id']);
      if (v['spec'] != null) spec.AppSpec.parse(jsonEncode(v['spec']));
    }
    if (app['draft'] != null && _map(app['draft']).containsKey('spec')) {
      spec.AppSpec.parse(jsonEncode(_map(app['draft'])['spec']));
    }
    if (app.containsKey('controlRevision')) {
      _apps[id] = app;
    } else {
      _summaries[id] = app;
    }
    return app;
  }

  AppManifest _manifest(Map<String, dynamic> app) {
    final version = app['version'] == null ? null : _map(app['version']);
    return AppManifest(
      appId: _id(app['id']),
      workspaceId: _id(app['workspaceId']),
      name: app['name'] as String,
      versionId: version == null ? null : _id(version['id']),
      specJson: version?['spec'] == null ? null : jsonEncode(version!['spec']),
      role: app['role'] as String,
      archived: app['archived'] as bool,
      pinned: app['pinned'] == true,
      recordCount: (app['recordCount'] as int?) ?? 0,
      availablePlaces: (app['availablePlaces'] as int?) ?? 0,
      approvedRuleIds:
          ((version?['approvedRuleIds'] ?? app['approvedRuleIds']) as List?)
              ?.cast<String>(),
    );
  }

  Future<Map<String, dynamic>> _load(String id) async =>
      _remember((await request({'op': 'spec.getApp', 'appId': id}))['app']);
  Future<Map<String, dynamic>> _current(String id) async =>
      _apps[id] ?? await _load(id);
  Future<String> _version(String appId) async {
    final app = await _current(appId), version = app['version'];
    if (version == null)
      throw NestError(
        category: 'unpublished',
        message: 'Publish the app before using live records.',
      );
    return _id(_map(version)['id']);
  }

  BuilderSnapshot _snapshot(Map<String, dynamic> app) {
    final draft = app['draft'] == null ? null : _map(app['draft']);
    final version = app['version'] == null ? null : _map(app['version']);
    final generation = app['generation'] == null
        ? null
        : _map(app['generation']);
    final source = draft?['spec'] ?? version?['spec'];
    final candidate = source == null
        ? null
        : spec.AppSpec.parse(jsonEncode(source));
    final previous = version?['spec'] == null
        ? null
        : spec.AppSpec.parse(jsonEncode(version!['spec']));
    final stage =
        generation?['status'] as String? ??
        (draft?['publishedVersionId'] != null ? 'published' : 'preview ready');
    return BuilderSnapshot(
      appId: _id(app['id']),
      draftId: _id(app['id']),
      jobId: generation?['id'] as String?,
      baseVersionId: draft != null
          ? draft['baseVersionId'] as String?
          : version?['id'] as String?,
      mutation:
          draft?['revision'] as int? ?? generation?['mutation'] as int? ?? 0,
      stage: stage,
      candidateJson: candidate?.canonical ?? '',
      candidateHash:
          draft?['candidateHash'] as String? ?? candidate?.hash ?? '',
      diagnostics: _generationDiagnostics(generation?['diagnostics']),
      changes: candidate?.diff(previous) ?? [],
      enabledRuleIds: [],
      publishedVersionId: draft?['publishedVersionId'] as String?,
      candidateReady:
          candidate != null && (generation == null || stage == 'preview ready'),
      latestRequest: generation?['requestText'] as String?,
      jobAttempts: generation?['attempts'] as int? ?? 0,
      jobCreatedAt: DateTime.tryParse(
        generation?['createdAt'] as String? ?? '',
      ),
      jobUpdatedAt: DateTime.tryParse(
        generation?['updatedAt'] as String? ?? '',
      ),
      failureCategory: generation?['failureCategory'] as String?,
    );
  }

  RuntimeRecord _record(Object? raw) {
    final row = _map(raw);
    return RuntimeRecord(
      id: _id(row['id']),
      collectionId: row['collectionId'] as String,
      data: _map(row['data']),
      revision: row['revision'] as int,
      capacity: row['capacity'] as int?,
      allocated: row['allocated'] as int?,
      claimed: row['claimed'] == true,
      allowedActions: (row['allowedActions'] as List).cast<String>(),
    );
  }

  String _logical(String endpoint, String method, Map<String, dynamic> args) =>
      '$endpoint.$method:${jsonEncode(args.map((k, v) => MapEntry(k, v is ActionRequest
          ? v.toJson()
          : v is PublishRequest
          ? v.toJson()
          : v is MediaUploadRequest
          ? v.toJson()
          : v)))}';
  Future<dynamic> _endpoint(
    String endpoint,
    String method,
    Map<String, dynamic> args,
  ) async {
    final logical = _logical(endpoint, method, args),
        appId = args['appId'] as String?;
    switch ('$endpoint.$method') {
      case 'apps.workspaces':
        return _rows((await request({'op': 'listWorkspaces'}))['workspaces'])
            .map(
              (v) => WorkspaceInfo(
                id: _id(v['id']),
                name: v['name'] as String,
                role: v['role'] as String,
              ),
            )
            .toList();
      case 'apps.createWorkspace':
        final id = _operation('$logical:id');
        final row = _map(
          (await request({
            'op': 'createWorkspace',
            'id': id,
            'name': args['name'],
          }))['workspace'],
        );
        _commandIds.remove('$logical:id');
        return _id(row['id']);
      case 'apps.list':
        final workspaceId = _id(args['workspaceId']);
        final result = <AppManifest>[];
        String? cursor;
        do {
          final page = await request({
            'op': 'spec.launcher',
            'workspaceId': workspaceId,
            'limit': 50,
            if (cursor != null) 'cursor': cursor,
          });
          for (final raw in _rows(page['apps'])) {
            final row = _remember(raw);
            if (row['workspaceId'] != workspaceId)
              throw NestError(
                category: 'invalid_response',
                message: 'The app belongs to another workspace.',
              );
            result.add(_manifest(row));
          }
          cursor = page['nextCursor'] as String?;
        } while (cursor != null);
        return result;
      case 'apps.manifest':
        return _manifest(await _load(appId!));
      case 'apps.templates':
        return _rows((await request({'op': 'spec.templates'}))['templates'])
            .map(
              (v) => TemplateInfo(
                key: v['key'] as String,
                name: v['name'] as String,
                specJson: spec.AppSpec.parse(jsonEncode(v['spec'])).canonical,
                description: (v['description'] as String?) ?? '',
              ),
            )
            .toList();
      case 'apps.instantiate':
        final result = await _command(logical, {
          'op': 'spec.instantiate',
          'id': _operation('$logical:id'),
          'workspaceId': args['workspaceId'],
          'templateKey': args['templateKey'],
        });
        _commandIds.remove('$logical:id');
        return _id(_remember(result['app'])['id']);
      case 'apps.remix':
        final result = await _command(logical, {
          'op': 'spec.remix',
          'id': _operation('$logical:id'),
          'workspaceId': args['workspaceId'],
          'sourceAppId': appId,
          'sourceVersionId': await _version(appId!),
        });
        _commandIds.remove('$logical:id');
        return _id(_remember(result['app'])['id']);
      case 'apps.pin':
        final app = await _current(appId!);
        final result = await _command(logical, {
          'op': 'spec.setPinned',
          'appId': appId,
          'expectedRevision':
              _summaries[appId]?['pinRevision'] ?? app['pinRevision'] ?? 0,
          'pinned': args['pinned'],
        });
        app['pinRevision'] = _map(result['shortcut'])['revision'];
        app['pinned'] = args['pinned'];
        return null;
      case 'apps.archive':
        await _command(logical, {'op': 'archiveApp', 'appId': appId});
        _apps.remove(appId);
        return null;
      case 'apps.invite':
        final tokenHex =
            _operation('$logical:token') + _operation('$logical:token2');
        final token = base64Url
            .encode(
              List<int>.generate(
                32,
                (i) =>
                    int.parse(tokenHex.substring(i * 2, i * 2 + 2), radix: 16),
              ),
            )
            .replaceAll('=', '');
        final result = await _command(logical, {
          'op': 'createInvitation',
          'appId': appId,
          'id': _operation('$logical:id'),
          'role': args['role'],
          'recipientId': args['recipientId'],
          'token': token,
        });
        _tickets['invitation:$token'] = {
          'id': _map(result['invitation'])['id'],
        };
        _commandIds.remove('$logical:token');
        _commandIds.remove('$logical:token2');
        _commandIds.remove('$logical:id');
        return token;
      case 'apps.acceptInvitation':
        return _id(
          (await _command(logical, {
            'op': 'acceptInvitation',
            'token': args['token'],
          }))['appId'],
        );
      case 'apps.revokeInvitation':
        final token = args['token'] as String;
        final known = _tickets['invitation:$token'];
        if (known == null)
          throw NestError(
            category: 'refresh_required',
            message:
                'Refresh the invitation list before revoking this invitation.',
          );
        await _command(logical, {
          'op': 'revokeInvitation',
          'appId': appId,
          'invitationId': known['id'],
        });
        return null;
      case 'apps.members':
        final result = <MemberInfo>[];
        String? after;
        do {
          final response = await request({
            'op': 'listMembers',
            'appId': appId,
            if (after != null) 'afterId': after,
          });
          for (final row in _rows(response['members'])) {
            final actor = _id(row['actorId']);
            _tickets['member:$appId:$actor'] = row;
            result.add(MemberInfo(actorId: actor, role: row['role'] as String));
          }
          after = response['nextCursor'] as String?;
        } while (after != null);
        return result;
      case 'apps.setGrant':
        final target = _id(args['target']);
        final member = _tickets['member:$appId:$target'];
        if (member == null)
          throw NestError(
            category: 'refresh_required',
            message: 'Refresh members before changing access.',
          );
        await _command(logical, {
          'op': 'setGrant',
          'appId': appId,
          'actorId': target,
          'role': args['role'],
          'expectedRevision':
              member['grantRevision'] ?? member['revision'] ?? 0,
        });
        _tickets.remove('member:$appId:$target');
        return null;
      case 'apps.activity':
      case 'builder.runs':
        final response = await request({
          'op': endpoint == 'apps' ? 'spec.listActivity' : 'spec.runs',
          'appId': appId,
        });
        return _rows(response[endpoint == 'apps' ? 'items' : 'runs'])
            .map(
              (v) => ActivityItem(
                id: _id(v['id']),
                action: (v['action'] ?? v['ruleId'] ?? 'reminder') as String,
                createdAt: DateTime.parse(
                  (v['createdAt'] ?? v['dueAt']) as String,
                ),
                status: v['status'] as String,
              ),
            )
            .toList();
      case 'builder.platform':
        final caps = await request({'op': 'spec.capabilities'});
        return PlatformInfo(
          aiAvailable: caps['generation'] == true,
          aiMode: caps['generation'] == true ? 'configured' : 'templates',
          development: true,
          actorId: auth.actorId ?? '',
        );
      case 'builder.begin':
        return _begin(args, logical);
      case 'builder.get':
        return _snapshot(await _load(_id(args['draftId'])));
      case 'builder.suggestQuestions':
        String? workspaceId = args['workspaceId'] as String?;
        final draftId = args['draftId'] as String?;
        if (workspaceId == null && draftId != null)
          workspaceId = (await _current(draftId))['workspaceId'] as String;
        final response = await request({
          'op': 'spec.guidance',
          'workspaceId': workspaceId,
          'appId': draftId,
          'request': args['idea'],
        });
        return _rows(response['questions'])
            .map(
              (v) => GuidanceQuestion(
                question: v['question'] as String,
                options: (v['options'] as List).cast<String>(),
              ),
            )
            .toList();
      case 'builder.patch':
        final id = _id(args['draftId']),
            app = await _current(id),
            draft = _map(app['draft']);
        if (draft['revision'] != args['mutation'])
          throw _failure('revision_conflict', 409);
        var allocation = 0;
        final candidate = spec.AppSpec.parse(jsonEncode(draft['spec'])).patch(
          _map(jsonDecode(args['patchJson'] as String)),
          () =>
              'f${sha256.convert(utf8.encode('${_operation('$logical:field')}:${allocation++}')).toString().substring(0, 16)}',
        );
        final response = await _command(logical, {
          'op': 'spec.saveDraft',
          'appId': id,
          'expectedRevision': args['mutation'],
          'expectedVersionId': _mapOrNull(app['version'])?['id'],
          'spec': candidate.toJson(),
        });
        _commandIds.remove('$logical:field');
        return _snapshot(_remember(response['app']));
      case 'builder.generate':
        final id = _id(args['draftId']), app = await _current(id);
        final response = await _command(logical, {
          'op': 'spec.generate',
          'appId': id,
          'expectedRevision': args['mutation'],
          'expectedVersionId': _mapOrNull(app['version'])?['id'],
          'request': args['request'],
          'startFromScratch': args['startFromScratch'] ?? false,
        });
        return _snapshot(_remember(response['app']));
      case 'builder.publish':
        final r = args['request'] as PublishRequest,
            app = await _current(r.draftId),
            draft = _map(app['draft']);
        final response = await request({
          'op': 'spec.publish',
          'appId': r.draftId,
          'operationId': _normalizeOperation(r.idempotencyKey),
          'expectedRevision': draft['revision'],
          'expectedVersionId': r.expectedCurrentVersionId,
          'candidateHash': r.candidateHash,
          'reviewHash': r.reviewHash,
          'enabledRuleIds': r.enabledRuleIds,
          'activateExistingRecordIds': r.activateExistingRecordIds,
        });
        return _id(_map(_remember(response['app'])['version'])['id']);
      case 'builder.abandonFailedEdit':
        final id = _id(args['draftId']);
        return _snapshot(
          _remember(
            (await _command(logical, {
              'op': 'spec.keepPrevious',
              'appId': id,
              'jobId': args['jobId'],
              'expectedRevision': args['mutation'],
            }))['app'],
          ),
        );
      case 'runtime.query':
        final version = await _version(appId!);
        final response = await request({
          'op': 'spec.query',
          'appId': appId,
          'versionId': version,
          'collectionId': args['collectionId'],
          'query': jsonDecode(args['queryJson'] as String),
        });
        if (response['versionId'] != version)
          throw _failure('definition_conflict', 409);
        return RecordPage(
          records: _rows(response['records']).map(_record).toList(),
          total: response['total'] as int,
          nextCursor: response['nextCursor'] as String?,
        );
      case 'runtime.get':
        final version = await _version(appId!);
        final response = await request({
          'op': 'spec.getRecord',
          'appId': appId,
          'versionId': version,
          'recordId': args['recordId'],
        });
        if (response['versionId'] != version)
          throw _failure('definition_conflict', 409);
        return _record(response['record']);
      case 'runtime.summary':
        final response = await request({
          'op': 'spec.summary',
          'appId': appId,
          'versionId': await _version(appId!),
          'collectionId': args['collectionId'],
          'query': jsonDecode(args['queryJson'] as String),
          'groupFieldId': args['groupFieldId'],
        });
        return RecordSummary(
          total: response['total'] as int,
          groups: Map<String, int>.from(_map(response['groups'])),
        );
      case 'runtime.aggregate':
        return jsonEncode(
          await request({
            'op': 'spec.aggregate',
            'appId': appId,
            'versionId': await _version(appId!),
            'collectionId': args['collectionId'],
            'query': jsonDecode(args['queryJson'] as String),
            'aggregate': jsonDecode(args['aggregateJson'] as String),
          }),
        );
      case 'runtime.reminderState':
        final response = await request({
          'op': 'spec.reminderState',
          'appId': appId,
          'versionId': await _version(appId!),
          'recordId': args['recordId'],
        });
        return _rows(response['states'])
            .map(
              (v) => ReminderState(
                ruleId: v['ruleId'] as String,
                state: v['state'] as String,
                scheduledAt: DateTime.tryParse(
                  v['scheduledAt'] as String? ?? '',
                ),
                eligible: v['eligible'] == true,
              ),
            )
            .toList();
      case 'runtime.execute':
        final r = args['request'] as ActionRequest;
        final response = await request({
          'op': 'spec.execute',
          'appId': r.appId,
          'operationId': _normalizeOperation(r.idempotencyKey),
          'versionId': r.expectedDefinitionVersionId,
          'actionId': r.actionId,
          if (r.targetRecordId != null) 'targetRecordId': r.targetRecordId,
          if (r.expectedRecordRevision != null)
            'expectedRecordRevision': r.expectedRecordRevision,
          'input': r.input,
        });
        final outcome = _map(response['outcome']);
        return ActionOutcome(
          recordId: _id(outcome['recordId']),
          revision: outcome['revision'] as int,
          message: outcome['message'] as String,
        );
      case 'runtime.inbox':
        final response = await request({'op': 'spec.inbox'});
        final rows = _rows(response['items']);
        for (final row in rows) {
          _inbox[_id(row['id'])] = row;
        }
        return rows
            .map(
              (v) => InboxItem(
                id: _id(v['id']),
                appId: _id(v['appId']),
                title: v['title'] as String,
                body: v['body'] as String,
                createdAt: DateTime.parse(
                  (v['createdAt'] ?? v['dueAt']) as String,
                ),
                isRead: v['isRead'] as bool,
                recordId: v['recordId'] as String?,
                collectionId: v['collectionId'] as String?,
              ),
            )
            .toList();
      case 'runtime.readNotification':
        final row = _inbox[_id(args['id'])];
        if (row == null)
          throw NestError(
            category: 'refresh_required',
            message: 'Refresh the inbox before marking this item read.',
          );
        await _command(logical, {
          'op': 'spec.readNotification',
          'appId': row['appId'],
          'runId': row['runId'],
          'notificationId': row['id'],
        });
        return null;
      case 'media.beginUpload':
        final r = args['request'] as MediaUploadRequest;
        return MediaUploadTicket(
          assetId: '',
          uploadDescription: jsonEncode(r.toJson()),
        );
      case 'media.completeUpload':
        final response = await _command(logical, {
          'op': 'spec.media.complete',
          'appId': appId,
          'assetId': args['assetId'],
        });
        return _readyMedia(appId!, _map(response['asset']));
      case 'media.readImage':
        return _readImage(
          appId!,
          _id(args['assetId']),
          args['variant'] as String,
        );
      default:
        throw UnsupportedError(
          'Unknown presentation operation: $endpoint.$method',
        );
    }
  }

  Future<BuilderSnapshot> _begin(
    Map<String, dynamic> args,
    String logical,
  ) async {
    String? id = args['appId'] as String?;
    Map<String, dynamic> app;
    if (id != null)
      app = await _load(id);
    else {
      id = _operation('$logical:app');
      app =
          _apps[id] ??
          _remember(
            (await _command('$logical:create', {
              'op': 'spec.createApp',
              'id': id,
              'workspaceId': args['workspaceId'],
              'name': 'Untitled app',
            }))['app'],
          );
    }
    if (app['draft'] != null &&
        _map(app['draft'])['publishedVersionId'] == null)
      return _snapshot(app);
    final version = _mapOrNull(app['version']);
    Map<String, dynamic> candidate;
    if (version != null)
      candidate = _map(version['spec']);
    else {
      final templates = spec.starterTemplates(),
          template = templates[args['templateKey']];
      if (template == null)
        throw NestError(
          category: 'invalid_template',
          message: 'Choose an available starter template.',
        );
      candidate = template.toJson();
    }
    final response = await _command('$logical:save', {
      'op': 'spec.saveDraft',
      'appId': id,
      'expectedRevision': _mapOrNull(app['draft'])?['revision'] ?? 0,
      'expectedVersionId': version?['id'],
      'spec': candidate,
    });
    _commandIds.remove('$logical:app');
    return _snapshot(_remember(response['app']));
  }

  Future<void> uploadMediaBytes(
    MediaUploadTicket ticket,
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024)
      throw NestError(
        category: 'invalid_media',
        message: 'Choose an image smaller than 5 MiB.',
      );
    final old = _map(jsonDecode(ticket.uploadDescription));
    if (old['byteLength'] != bytes.length)
      throw NestError(
        category: 'invalid_media',
        message: 'The selected image changed.',
      );
    final appId = _id(old['appId']),
        draftId = old['draftId'] as String?,
        target = old['targetRecordId'] as String?;
    int? recordRevision;
    if (target != null)
      recordRevision = (await runtime.get(appId, target)).revision;
    final app = draftId == null ? null : await _current(appId);
    final input = {
      'op': 'spec.media.begin',
      'appId': appId,
      'operationId': _normalizeOperation(old['idempotencyKey'] as String),
      'byteLength': bytes.length,
      'contentType': old['contentType'],
      'sha256': sha256.convert(bytes).toString(),
      if (draftId != null) 'draftRevision': _map(app!['draft'])['revision'],
      if (draftId == null) 'versionId': old['expectedDefinitionVersionId'],
      if (draftId == null && old['actionId'] != null)
        'actionId': old['actionId'],
      if (draftId == null && old['fieldId'] != null) 'fieldId': old['fieldId'],
      if (target != null) 'targetRecordId': target,
      if (target != null) 'expectedRecordRevision': recordRevision,
    };
    final begun = await request(input), asset = _map(begun['asset']);
    ticket.assetId = _id(asset['id'] ?? asset['assetId']);
    final chunkBytes = begun['chunkBytes'] as int;
    if (chunkBytes < 1 || chunkBytes > 262144)
      throw NestError(
        category: 'invalid_response',
        message: 'Invalid image chunk limit.',
      );
    for (
      var offset = asset['uploadedBytes'] as int? ?? 0;
      offset < bytes.length;
      offset += chunkBytes
    ) {
      final chunk = Uint8List.sublistView(
        bytes,
        offset,
        min(offset + chunkBytes, bytes.length),
      );
      final response = await request({
        'op': 'spec.media.chunk',
        'appId': appId,
        'assetId': ticket.assetId,
        'offset': offset,
        'sha256': sha256.convert(chunk).toString(),
        'dataBase64': base64Encode(chunk),
      });
      if (response['uploadedBytes'] != offset + chunk.length)
        throw BackendNetworkException(
          'The image upload result is unknown.',
          uncertain: true,
        );
    }
  }

  Future<MediaInfo> checkMediaUpload(String appId, String assetId) async =>
      _readyMedia(
        appId,
        _map(
          (await request({
            'op': 'spec.media.status',
            'appId': appId,
            'assetId': assetId,
          }))['asset'],
        ),
      );
  MediaInfo _readyMedia(String appId, Map<String, dynamic> asset) {
    final id = _id(asset['id'] ?? asset['assetId']);
    if (asset['status'] != 'ready') {
      if ({'failed', 'expired', 'deleted'}.contains(asset['status']))
        throw NestError(
          category: 'media_failed',
          message: 'The image could not be processed. Choose another image.',
        );
      throw BackendMediaProcessing(appId, id);
    }
    return MediaInfo(
      assetId: id,
      contentType: asset['contentType'] as String,
      width: asset['width'] as int,
      height: asset['height'] as int,
      byteLength: (asset['displayBytes'] ?? asset['byteLength']) as int,
    );
  }

  Future<ByteData> _readImage(
    String appId,
    String assetId,
    String variant,
  ) async {
    final bytes = BytesBuilder(copy: false);
    String? hash;
    int? total;
    int offset = 0;
    while (true) {
      final part = await request({
        'op': 'spec.media.read',
        'appId': appId,
        'assetId': assetId,
        'variant': variant,
        'offset': offset,
      });
      final chunk = base64Decode(part['dataBase64'] as String);
      if (part['assetId'] != assetId ||
          part['variant'] != variant ||
          part['offset'] != offset ||
          part['byteLength'] is! int ||
          chunk.isEmpty ||
          sha256.convert(chunk).toString() != part['chunkSha256'])
        throw NestError(
          category: 'media_integrity',
          message: 'The image response could not be verified.',
        );
      hash ??= part['sha256'] as String;
      total ??= part['byteLength'] as int;
      if (total < 1 ||
          total > 5 * 1024 * 1024 ||
          part['sha256'] != hash ||
          part['byteLength'] != total ||
          bytes.length + chunk.length > total)
        throw NestError(
          category: 'media_integrity',
          message: 'The image response changed.',
        );
      bytes.add(chunk);
      if (part['nextOffset'] == null) break;
      final next = part['nextOffset'];
      if (next != offset + chunk.length)
        throw NestError(
          category: 'media_integrity',
          message: 'The image chunk sequence is invalid.',
        );
      offset = next as int;
    }
    final result = bytes.takeBytes();
    if (result.length != total || sha256.convert(result).toString() != hash)
      throw NestError(
        category: 'media_integrity',
        message: 'The image was incomplete.',
      );
    return ByteData.sublistView(result);
  }
}

Map<String, dynamic>? _mapOrNull(Object? value) =>
    value == null ? null : _map(value);
String _normalizeOperation(String value) =>
    'o${sha256.convert(utf8.encode(value)).toString().substring(0, 32)}';

void _validateResponse(
  Map<String, dynamic> input,
  Map<String, dynamic> response,
) {
  final op = input['op'];
  if ({
    'spec.createApp',
    'spec.saveDraft',
    'spec.publish',
    'spec.instantiate',
    'spec.remix',
    'spec.generate',
    'spec.keepPrevious',
    'spec.getApp',
  }.contains(op)) {
    final app = _map(response['app']);
    _id(app['id']);
    _id(app['workspaceId']);
    if (app['id'] != (input['appId'] ?? input['id']) ||
        app['name'] is! String ||
        app['archived'] is! bool ||
        !{'owner', 'builder', 'member', 'viewer'}.contains(app['role'])) {
      throw NestError(
        category: 'invalid_response',
        message: 'The app response did not match this request.',
      );
    }
  }
  if ({
    'spec.createApp',
    'spec.saveDraft',
    'spec.publish',
    'spec.instantiate',
    'spec.remix',
    'spec.generate',
    'spec.keepPrevious',
    'spec.getApp',
  }.contains(op)) {
    final app = _map(response['app']);
    if (app['version'] != null) {
      final version = _map(app['version']);
      _id(version['id']);
      final definition = spec.AppSpec.parse(jsonEncode(version['spec']));
      if (version['hash'] != definition.hash)
        throw NestError(
          category: 'invalid_response',
          message: 'The published definition could not be verified.',
        );
    }
    if (app['draft'] != null) {
      final draft = _map(app['draft']);
      final definition = spec.AppSpec.parse(jsonEncode(draft['spec']));
      if (draft['revision'] is! int ||
          draft['candidateHash'] != definition.hash)
        throw NestError(
          category: 'invalid_response',
          message: 'The private definition could not be verified.',
        );
    }
    if (op == 'spec.saveDraft' &&
        _map(app['draft'])['revision'] !=
            (input['expectedRevision'] as int) + 1)
      throw NestError(
        category: 'invalid_response',
        message: 'The saved draft revision could not be confirmed.',
      );
    if (op == 'spec.publish' && app['version'] == null)
      throw NestError(
        category: 'invalid_response',
        message: 'Publication could not be confirmed.',
      );
  }
  if ({'createInvitation', 'revokeInvitation'}.contains(op)) {
    final invite = _map(response['invitation']);
    _id(invite['id']);
    if (invite['appId'] != input['appId'])
      throw NestError(
        category: 'invalid_response',
        message: 'The invitation result could not be confirmed.',
      );
  }
  if (op == 'acceptInvitation') _id(response['appId']);
  if (op == 'setGrant') {
    final member = _map(response['member']);
    if (member['actorId'] != input['actorId'] ||
        member['role'] != input['role'] ||
        member['revision'] != (input['expectedRevision'] as int) + 1)
      throw NestError(
        category: 'invalid_response',
        message: 'The access change could not be confirmed.',
      );
  }
  if (op == 'spec.setPinned') {
    final shortcut = _map(response['shortcut']);
    if (shortcut['appId'] != input['appId'] ||
        shortcut['pinned'] != input['pinned'] ||
        shortcut['revision'] != (input['expectedRevision'] as int) + 1)
      throw NestError(
        category: 'invalid_response',
        message: 'The shortcut change could not be confirmed.',
      );
  }
  if (op == 'spec.readNotification' &&
      (response['notificationId'] != input['notificationId'] ||
          response['isRead'] != true))
    throw NestError(
      category: 'invalid_response',
      message: 'The read state could not be confirmed.',
    );
  if ({'spec.media.begin', 'spec.media.complete'}.contains(op)) {
    final asset = _map(response['asset']);
    _id(asset['assetId']);
    if (input['assetId'] != null && input['assetId'] != asset['assetId'])
      throw NestError(
        category: 'invalid_response',
        message: 'The image result could not be confirmed.',
      );
  }
  if (op == 'spec.media.chunk' &&
      (response['assetId'] != input['assetId'] ||
          response['uploadedBytes'] is! int))
    throw NestError(
      category: 'invalid_response',
      message: 'The image upload result could not be confirmed.',
    );
  if (op == 'spec.execute') {
    final outcome = _map(response['outcome']);
    _id(outcome['recordId']);
    if (outcome['revision'] is! int ||
        (outcome['revision'] as int) < 1 ||
        outcome['message'] is! String ||
        (input['targetRecordId'] != null &&
            outcome['recordId'] != input['targetRecordId']))
      throw NestError(
        category: 'invalid_response',
        message: 'The record result could not be confirmed.',
      );
  }
  if (op == 'createWorkspace') {
    final workspace = _map(response['workspace']);
    if (workspace['id'] != input['id'] || workspace['name'] != input['name'])
      throw NestError(
        category: 'invalid_response',
        message: 'The workspace result could not be confirmed.',
      );
  }
}

List<String> _generationDiagnostics(Object? value) {
  if (value == null || value == '') return [];
  if (value is String) return [value];
  if (value is List && value.every((entry) => entry is String))
    return value.cast<String>();
  throw NestError(
    category: 'invalid_response',
    message: 'The generation diagnostics could not be read.',
  );
}
