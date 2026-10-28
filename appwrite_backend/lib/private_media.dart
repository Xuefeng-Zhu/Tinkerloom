part of 'service.dart';

Set<String> _definitionImages(spec.AppSpec definition) => {
  for (final view in definition.views)
    if (view.type == 'banner' && view.options['imageAssetId'] is String)
      view.options['imageAssetId'] as String,
};

/// Broker-only operations; no provider paths/tokens/URLs are returned. The
/// private scheduled worker calls processMedia/cleanupMedia, never a user body.
extension PrivateMedia on PlatformService {
  PrivateFileStore get _files =>
      media ?? (throw const ServiceException('capability_unavailable', 409));
  String _mediaFile(String assetId, String variant) =>
      _identity('i', [assetId, variant]);
  String _mediaTime() => clock().toUtc().toIso8601String();
  DateTime _mediaDate(Object? value) {
    if (value is! String) throw const ServiceException('integrity_error', 500);
    return DateTime.parse(value).toUtc();
  }

  Future<List<Row>> _mediaRows(
    String table,
    Map<String, String> filters, {
    String? tx,
  }) async {
    final rows = <Row>[];
    String? after;
    while (true) {
      final page = await store.list(
        table,
        filters,
        transactionId: tx,
        afterId: after,
        limit: 100,
        detectOverflow: false,
      );
      rows.addAll(page);
      if (page.length < 100) return rows;
      after = page.last[r'$id'] as String;
    }
  }

  Future<Row> _mediaAsset(AppAccess access, Object? value, String? tx) async {
    final id = _validId(value);
    final row = await store.get('media_assets', id, transactionId: tx);
    if (row == null ||
        row['appId'] != access.app[r'$id'] ||
        row['workspaceId'] != access.app['workspaceId'])
      throw const ServiceException('not_found', 404);
    return row;
  }

  Future<Row> _mediaQuota(String id, String tx) async {
    final existing = await store.get('media_quotas', id, transactionId: tx);
    existing ??
        await store.create('media_quotas', id, {
          'bytes': 0,
          'assets': 0,
          'leasesJson': '[]',
          'guard': _nonce(),
        }, transactionId: tx);
    return store.update('media_quotas', id, {
      'guard': _nonce(),
    }, transactionId: tx);
  }

  Future<void> _mediaUsage(
    String appId,
    int bytes,
    int assets,
    String tx, {
    bool reserve = false,
  }) async {
    if (mediaProjectBytes < 1 || mediaProjectBytes > 2147483647)
      throw const ServiceException('backend_unavailable', 503);
    for (final id in [
      'global',
      _identity('q', [appId]),
    ]) {
      final row = await _mediaQuota(id, tx);
      final totalBytes = (row['bytes'] as int) + bytes,
          totalAssets = (row['assets'] as int) + assets;
      if (totalBytes < 0 || totalAssets < 0)
        throw const ServiceException('integrity_error', 500);
      if (reserve &&
          ((id == 'global' && totalBytes > mediaProjectBytes) ||
              (id != 'global' &&
                  (totalBytes > MediaLimits.maxAppBytes ||
                      totalAssets > MediaLimits.maxAppAssets))))
        throw const ServiceException('quota_exceeded', 429);
      await store.update('media_quotas', id, {
        'bytes': totalBytes,
        'assets': totalAssets,
      }, transactionId: tx);
    }
  }

  Future<void> _mediaUploadAccess(
    String actor,
    AppAccess access,
    Row input,
    String? tx, {
    bool fresh = true,
  }) async {
    _files;
    _specEngine(access);
    _require(access, 'read', writable: fresh);
    if (input.containsKey('draftRevision')) {
      _require(access, 'build', writable: fresh);
      if ([
        'versionId',
        'actionId',
        'fieldId',
        'targetRecordId',
        'expectedRecordRevision',
      ].any(input.containsKey))
        throw const ServiceException('invalid_request', 400);
      final revision = _revision(input['draftRevision']);
      if (fresh) {
        final draft = await _specDraft(actor, access, tx);
        if (draft == null ||
            draft['revision'] != revision ||
            draft['publishedVersionId'] != null)
          throw const ServiceException('revision_conflict', 409);
      }
      return;
    }
    final versionId = _validId(input['versionId']);
    final version = fresh
        ? await _activeSpec(access, tx, expected: versionId)
        : await _specVersion(access, versionId, tx);
    final action = version.definition.action(spec.stableId(input['actionId']));
    if (!{
          'records.create.v1',
          'records.patch.v1',
        }.contains(action.capability) ||
        !_specAllowed(access, version.definition, action, writable: fresh))
      throw const ServiceException('forbidden', 403);
    final collection = version.definition.collection(action.collectionId);
    if (collection.field(spec.stableId(input['fieldId'])).type !=
        spec.FieldType.image)
      throw const ServiceException('invalid_media', 400);
    if (action.capability == 'records.create.v1') {
      if (input.containsKey('targetRecordId') ||
          input.containsKey('expectedRecordRevision'))
        throw const ServiceException('invalid_request', 400);
    } else {
      final id = _validId(input['targetRecordId']);
      final revision = _revision(input['expectedRecordRevision']);
      if (fresh) {
        final record = await _specRecord(access, id, tx);
        if (record['collectionId'] != collection.id)
          throw const ServiceException('not_found', 404);
        if (record['revision'] != revision)
          throw const ServiceException('revision_conflict', 409);
      }
    }
  }

  Row _mediaInfo(Row asset) => {
    'assetId': asset[r'$id'],
    'status': asset['status'],
    if (asset['status'] == 'ready') ...{
      'contentType': asset['contentType'],
      'byteLength': asset['displayBytes'],
      'width': asset['width'],
      'height': asset['height'],
      'sha256': asset['displayHash'],
    },
    if (asset['status'] != 'ready') ...{
      'uploadedBytes': asset['uploadedBytes'],
      'inputBytes': asset['inputBytes'],
    },
    if (asset['status'] == 'failed') 'error': asset['failureCategory'],
  };

  Future<Row> _mediaBegin(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'operationId',
      'byteLength',
      'contentType',
      'sha256',
      'draftRevision',
      'versionId',
      'actionId',
      'fieldId',
      'targetRecordId',
      'expectedRecordRevision',
    });
    final length = input['byteLength'];
    if (length is! int ||
        length < 1 ||
        length > MediaLimits.maxOriginalBytes ||
        !{
          'image/jpeg',
          'image/png',
          'image/webp',
        }.contains(input['contentType']))
      throw const ServiceException('invalid_media', 400);
    _hash(input['sha256']);
    return _mutate(
      actor,
      input,
      'read',
      (tx, access) async {
        await _mediaUploadAccess(actor, access, input, tx);
        final id = _identity('i', [
          access.app[r'$id'] as String,
          actor,
          input['operationId'] as String,
        ]);
        final reserved =
            length +
            MediaLimits.maxOriginalBytes +
            MediaLimits.maxThumbnailBytes;
        await _mediaUsage(
          access.app[r'$id'] as String,
          reserved,
          1,
          tx,
          reserve: true,
        );
        final now = _mediaTime();
        final row = await store.create('media_assets', id, {
          'workspaceId': access.app['workspaceId'],
          'appId': access.app[r'$id'],
          'uploaderId': actor,
          'requestJson': _request(input),
          'inputBytes': length,
          'inputHash': input['sha256'],
          'inputType': input['contentType'],
          'status': 'pending',
          'storedBytes': reserved,
          'uploadedBytes': 0,
          'chunksJson': '[]',
          'originalRemoved': false,
          'leaseToken': null,
          'leaseUntil': null,
          'displayBytes': 0,
          'thumbnailBytes': 0,
          'displayHash': null,
          'thumbnailHash': null,
          'contentType': null,
          'width': 0,
          'height': 0,
          'failureCategory': null,
          'maintenanceAt': null,
          'originalDeleteAfter': null,
          'deleteAfter': null,
          'expiresAt': clock()
              .toUtc()
              .add(MediaLimits.uploadLifetime)
              .toIso8601String(),
          'createdAt': now,
          'updatedAt': now,
        }, transactionId: tx);
        return {
          'asset': _mediaInfo(row),
          'chunkBytes': MediaLimits.chunkBytes,
          'expiresAt': row['expiresAt'],
        };
      },
      authorize: (access, tx) =>
          _mediaUploadAccess(actor, access, input, tx, fresh: false),
    );
  }

  Future<Row> _mediaOwned(
    String actor,
    AppAccess access,
    String assetId,
    String tx, {
    bool fresh = true,
  }) async {
    final row = await _mediaAsset(access, assetId, tx);
    if (row['uploaderId'] != actor)
      throw const ServiceException('not_found', 404);
    await _mediaUploadAccess(
      actor,
      access,
      jsonDecode(row['requestJson'] as String) as Row,
      tx,
      fresh: fresh,
    );
    return row;
  }

  void _mediaPending(Row asset) {
    if (asset['status'] != 'pending')
      throw const ServiceException('media_state_conflict', 409);
    if (!_mediaDate(asset['expiresAt']).isAfter(clock().toUtc()))
      throw const ServiceException('media_expired', 409);
  }

  Future<Row> _mediaChunk(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'assetId',
      'offset',
      'sha256',
      'dataBase64',
    });
    final appId = _validId(input['appId']),
        assetId = _validId(input['assetId']);
    final offset = input['offset'], text = input['dataBase64'];
    if (offset is! int ||
        offset < 0 ||
        offset % MediaLimits.chunkBytes != 0 ||
        offset >= MediaLimits.maxOriginalBytes ||
        text is! String ||
        text.length > ((MediaLimits.chunkBytes + 2) ~/ 3) * 4)
      throw const ServiceException('invalid_media', 400);
    final Uint8List bytes;
    try {
      bytes = base64Decode(text);
    } on FormatException {
      throw const ServiceException('invalid_media', 400);
    }
    final hash = _hash(input['sha256']);
    if (bytes.isEmpty ||
        bytes.length > MediaLimits.chunkBytes ||
        base64Encode(bytes) != text ||
        sha256.convert(bytes).toString() != hash)
      throw const ServiceException('invalid_media', 400);
    final initial = await _access(actor, appId);
    final leased = await _transaction((tx) async {
      final access = await _stageAccess(actor, initial, tx);
      final asset = await _mediaOwned(actor, access, assetId, tx);
      _mediaPending(asset);
      final expected = min(
        MediaLimits.chunkBytes,
        (asset['inputBytes'] as int) - offset,
      );
      if (bytes.length != expected)
        throw const ServiceException('invalid_media', 400);
      final chunks = (jsonDecode(asset['chunksJson'] as String) as List)
          .cast<String>();
      final index = offset ~/ MediaLimits.chunkBytes;
      if (index < chunks.length) {
        if (chunks[index] != hash)
          throw const ServiceException('operation_conflict', 409);
        return asset;
      }
      if (index != chunks.length || offset != asset['uploadedBytes'])
        throw const ServiceException('revision_conflict', 409);
      if (asset['leaseUntil'] != null &&
          _mediaDate(asset['leaseUntil']).isAfter(clock().toUtc()))
        throw const ServiceException('media_busy', 409);
      return store.update('media_assets', assetId, {
        'leaseToken': _nonce(),
        'leaseUntil': clock()
            .toUtc()
            .add(MediaLimits.leaseLifetime)
            .toIso8601String(),
      }, transactionId: tx);
    });
    if ((leased['uploadedBytes'] as int) > offset)
      return {'assetId': assetId, 'uploadedBytes': leased['uploadedBytes']};
    try {
      await _files.put(
        _mediaFile(assetId, 'chunk-${offset ~/ MediaLimits.chunkBytes}'),
        bytes,
        'application/octet-stream',
      );
      return await _transaction((tx) async {
        final access = await _stageAccess(actor, initial, tx);
        final asset = await _mediaOwned(actor, access, assetId, tx);
        _mediaPending(asset);
        if (asset['leaseToken'] != leased['leaseToken'] ||
            asset['uploadedBytes'] != offset ||
            !_mediaDate(asset['leaseUntil']).isAfter(clock().toUtc()))
          throw const ServiceException('media_state_conflict', 409);
        final chunks = (jsonDecode(asset['chunksJson'] as String) as List)
          ..add(hash);
        await store.update('media_assets', assetId, {
          'chunksJson': jsonEncode(chunks),
          'uploadedBytes': offset + bytes.length,
          'leaseToken': null,
          'leaseUntil': null,
          'updatedAt': _mediaTime(),
        }, transactionId: tx);
        return {'assetId': assetId, 'uploadedBytes': offset + bytes.length};
      });
    } finally {
      await _mediaRelease(assetId, leased['leaseToken'] as String);
    }
  }

  Future<Row> _mediaComplete(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'assetId', 'operationId'});
    final assetId = _validId(input['assetId']);
    return _mutate(
      actor,
      input,
      'read',
      (tx, access) async {
        final row = await _mediaOwned(actor, access, assetId, tx);
        if (row['status'] == 'ready' ||
            row['status'] == 'queued' ||
            row['status'] == 'processing')
          return {'asset': _mediaInfo(row)};
        _mediaPending(row);
        if (row['uploadedBytes'] != row['inputBytes'])
          throw const ServiceException('media_incomplete', 409);
        if (row['leaseUntil'] != null &&
            _mediaDate(row['leaseUntil']).isAfter(clock().toUtc()))
          throw const ServiceException('media_busy', 409);
        final updated = await store.update('media_assets', assetId, {
          'status': 'queued',
          'updatedAt': _mediaTime(),
        }, transactionId: tx);
        await _queueDispatch(
          'media',
          assetId,
          access.app[r'$id'] as String,
          clock(),
          tx,
        );
        return {'asset': _mediaInfo(updated)};
      },
      authorize: (access, tx) async {
        final row = await _mediaAsset(access, assetId, tx);
        if (row['uploaderId'] != actor)
          throw const ServiceException('not_found', 404);
        await _mediaUploadAccess(
          actor,
          access,
          jsonDecode(row['requestJson'] as String) as Row,
          tx,
          fresh: false,
        );
      },
    );
  }

  Future<bool> _mediaVisible(
    String actor,
    AppAccess access,
    Row asset,
    String tx,
  ) async {
    if (access.builder) return true;
    final references =
        (await _mediaRows('media_refs', {
          'appId': access.app[r'$id'] as String,
        }, tx: tx)).where(
          (row) => (jsonDecode(row['assetIdsJson'] as String) as List).contains(
            asset[r'$id'],
          ),
        );
    if (references.isEmpty) return asset['uploaderId'] == actor;
    for (final ref in references) {
      if (ref['workspaceId'] != access.app['workspaceId'])
        throw const ServiceException('integrity_error', 500);
      if (ref['ownerKind'] == 'version' &&
          ref['ownerId'] == access.app['specVersionId'])
        return true;
      if (ref['ownerKind'] == 'record') {
        final record = await store.get(
          'spec_records',
          ref['ownerId'] as String,
          transactionId: tx,
        );
        if (record != null &&
            record['appId'] == access.app[r'$id'] &&
            record['workspaceId'] == access.app['workspaceId'] &&
            record['deleted'] == false)
          return true;
      }
    }
    return false;
  }

  Future<Row> _mediaReadAsset(
    String actor,
    String appId,
    String assetId, {
    bool status = false,
  }) => _specRead(actor, appId, (access, tx) async {
    _files;
    final asset = await _mediaAsset(access, assetId, tx);
    if (asset['status'] == 'ready') {
      if (!await _mediaVisible(actor, access, asset, tx))
        throw const ServiceException('not_found', 404);
    } else if (!status ||
        asset['uploaderId'] != actor ||
        {'deleting', 'deleted'}.contains(asset['status'])) {
      throw const ServiceException('not_found', 404);
    }
    return asset;
  });

  Future<Row> _mediaRead(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'assetId', 'variant', 'offset'});
    final appId = _validId(input['appId']),
        assetId = _validId(input['assetId']);
    final variant = input['variant'], offset = input['offset'];
    if (!{'display', 'thumbnail'}.contains(variant) ||
        offset is! int ||
        offset < 0 ||
        offset % MediaLimits.chunkBytes != 0)
      throw const ServiceException('invalid_media', 400);
    final before = await _mediaReadAsset(actor, appId, assetId);
    final length = before['${variant}Bytes'] as int;
    if (offset >= length) throw const ServiceException('invalid_media', 400);
    final bytes = await _files.read(
      _mediaFile(assetId, variant as String),
      maximumBytes: variant == 'display'
          ? MediaLimits.maxOriginalBytes
          : MediaLimits.maxThumbnailBytes,
    );
    if (bytes.length != length ||
        sha256.convert(bytes).toString() != before['${variant}Hash'])
      throw const ServiceException('media_integrity', 502);
    // Membership/grant AND current publication/reference authorization are
    // checked again after bytes leave Storage, before any response is exposed.
    final after = await _mediaReadAsset(actor, appId, assetId);
    if (after['${variant}Hash'] != before['${variant}Hash'])
      throw const ServiceException('media_state_conflict', 409);
    final end = min(offset + MediaLimits.chunkBytes, bytes.length);
    final chunk = Uint8List.sublistView(bytes, offset, end);
    return {
      'assetId': assetId,
      'variant': variant,
      'offset': offset,
      'nextOffset': end == length ? null : end,
      'byteLength': length,
      'contentType': before['contentType'],
      'sha256': before['${variant}Hash'],
      'chunkSha256': sha256.convert(chunk).toString(),
      'dataBase64': base64Encode(chunk),
      'width': before['width'],
      'height': before['height'],
      'cacheControl': 'private, no-store',
    };
  }

  Future<void> _validateMedia(
    String actor,
    AppAccess access,
    Set<String> ids,
    String tx,
  ) async {
    if (ids.isNotEmpty) _files;
    for (final id in ids) {
      final row = await _mediaAsset(access, id, tx);
      if (row['status'] != 'ready' ||
          !await _mediaVisible(actor, access, row, tx))
        throw const ServiceException('invalid_media', 400);
    }
  }

  /// Validation and retention stay in the same transaction as the owning draft,
  /// immutable version, or record. Empty rows are tombstones, not live refs.
  Future<void> _syncMedia(
    String actor,
    AppAccess access,
    Set<String> ids,
    String ownerKind,
    String ownerId,
    String tx,
  ) async {
    if (!{'draft', 'version', 'record'}.contains(ownerKind))
      throw StateError('Unsupported media reference owner');
    await _validateMedia(actor, access, ids, tx);
    final id = _identity('r', [
      access.app[r'$id'] as String,
      ownerKind,
      ownerId,
    ]);
    final old = await store.get('media_refs', id, transactionId: tx);
    final previous = old == null
        ? <String>{}
        : (jsonDecode(old['assetIdsJson'] as String) as List)
              .cast<String>()
              .toSet();
    if (old != null &&
        (old['appId'] != access.app[r'$id'] ||
            old['workspaceId'] != access.app['workspaceId'] ||
            old['ownerKind'] != ownerKind ||
            old['ownerId'] != ownerId))
      throw const ServiceException('integrity_error', 500);
    // No table operation is necessary for applications that never use media.
    if (old == null && ids.isEmpty) return;
    final data = {
      'appId': access.app[r'$id'],
      'workspaceId': access.app['workspaceId'],
      'ownerKind': ownerKind,
      'ownerId': ownerId,
      'assetIdsJson': jsonEncode(ids.toList()..sort()),
    };
    if (old == null) {
      await store.create('media_refs', id, data, transactionId: tx);
    } else {
      await store.update('media_refs', id, data, transactionId: tx);
    }
    // Only last-reference removals need a new grace start. Touching additions
    // would exceed the Free transaction budget for a 40-field record.
    for (final removed in previous.difference(ids)) {
      final row = await _mediaAsset(access, removed, tx);
      await store.update('media_assets', row[r'$id'] as String, {
        'updatedAt': _mediaTime(),
      }, transactionId: tx);
    }
  }

  /// The generator may preserve only references present in its exact captured
  /// source. A current unrelated draft, another app, or another ready asset is
  /// never an authority to invent a new opaque reference. Call after the final
  /// generation lease/base check and before saving, within that transaction.
  Future<void> validateGeneratedMedia(
    String actor,
    AppAccess access,
    spec.AppSpec? source,
    spec.AppSpec candidate,
    String tx,
  ) async {
    final ids = _definitionImages(candidate);
    if (!(_definitionImages(source ?? candidate).containsAll(ids)) ||
        (source == null && ids.isNotEmpty))
      throw const ServiceException('invalid_media', 400);
    await _validateMedia(actor, access, ids, tx);
  }

  Future<void> syncGeneratedMedia(
    String actor,
    AppAccess access,
    spec.AppSpec candidate,
    String tx,
  ) => _syncMedia(
    actor,
    access,
    _definitionImages(candidate),
    'draft',
    _identity('s', [access.app[r'$id'] as String, actor]),
    tx,
  );

  // Trusted maintenance may retry a confirmed optimistic conflict. Never retry
  // an unknown transport/commit result or replay external Storage work here.
  Future<T> _mediaTransaction<T>(Future<T> Function(String) action) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _transaction(action);
      } on ServiceException catch (error) {
        if (error.code != 'transaction_conflict' || attempt >= 3) rethrow;
      }
    }
  }

  Future<void> _mediaRelease(String assetId, String token) async {
    try {
      await _mediaTransaction((tx) async {
        final row = await store.get('media_assets', assetId, transactionId: tx);
        if (row == null || row['leaseToken'] != token) return;
        final global = await _mediaQuota('global', tx);
        final slots = (jsonDecode(global['leasesJson'] as String) as List)
            .where((slot) => (slot as Map)['token'] != token)
            .toList();
        await store.update('media_quotas', 'global', {
          'leasesJson': jsonEncode(slots),
        }, transactionId: tx);
        await store.update('media_assets', assetId, {
          'leaseToken': null,
          'leaseUntil': null,
        }, transactionId: tx);
      });
    } catch (_) {
      // Expiring durable leases and scheduled recovery, never an in-memory lock,
      // make process death or a failed release recoverable.
    }
  }

  Future<Row> _mediaWorkerLease(String assetId) async {
    _files;
    final initial = await store.get('media_assets', _validId(assetId));
    if (initial == null) throw const ServiceException('not_found', 404);
    final actor = initial['uploaderId'] as String;
    final initialAccess = await _access(actor, initial['appId'] as String);
    return _mediaTransaction((tx) async {
      final access = await _stageAccess(actor, initialAccess, tx);
      final row = await _mediaOwned(actor, access, assetId, tx);
      if (!{'queued', 'processing'}.contains(row['status']) ||
          !_mediaDate(row['expiresAt']).isAfter(clock().toUtc()))
        throw const ServiceException('media_expired', 409);
      if (row['leaseUntil'] != null &&
          _mediaDate(row['leaseUntil']).isAfter(clock().toUtc()))
        throw const ServiceException('media_busy', 409);
      final global = await _mediaQuota('global', tx);
      final slots = (jsonDecode(global['leasesJson'] as String) as List)
          .where(
            (slot) =>
                _mediaDate((slot as Map)['until']).isAfter(clock().toUtc()),
          )
          .map((slot) => Map<String, dynamic>.from(slot as Map))
          .toList();
      if (slots.length >= 2 || slots.any((slot) => slot['actorId'] == actor))
        throw const ServiceException('media_busy', 409);
      final token = _nonce(),
          until = clock()
              .toUtc()
              .add(MediaLimits.leaseLifetime)
              .toIso8601String();
      slots.add({
        'actorId': actor,
        'assetId': assetId,
        'token': token,
        'until': until,
      });
      await store.update('media_quotas', 'global', {
        'leasesJson': jsonEncode(slots),
      }, transactionId: tx);
      return store.update('media_assets', assetId, {
        'status': 'processing',
        'leaseToken': token,
        'leaseUntil': until,
        'updatedAt': _mediaTime(),
      }, transactionId: tx);
    });
  }

  Future<Row> _mediaRenew(
    Row lease, {
    Future<void> Function(AppAccess, Row, String)? action,
  }) async {
    final actor = lease['uploaderId'] as String,
        assetId = lease[r'$id'] as String;
    final before = await _access(actor, lease['appId'] as String);
    return _mediaTransaction((tx) async {
      final access = await _stageAccess(actor, before, tx);
      final current = await _mediaOwned(actor, access, assetId, tx);
      if (current['status'] != 'processing' ||
          current['leaseToken'] != lease['leaseToken'] ||
          current['leaseUntil'] == null ||
          !_mediaDate(current['leaseUntil']).isAfter(clock().toUtc()))
        throw const ServiceException('media_state_conflict', 409);
      final global = await _mediaQuota('global', tx);
      final slots = (jsonDecode(global['leasesJson'] as String) as List)
          .map((slot) => Map<String, dynamic>.from(slot as Map))
          .toList();
      final slot = slots
          .where(
            (slot) =>
                slot['token'] == lease['leaseToken'] &&
                slot['actorId'] == actor &&
                slot['assetId'] == assetId,
          )
          .firstOrNull;
      if (slot == null || !_mediaDate(slot['until']).isAfter(clock().toUtc()))
        throw const ServiceException('media_state_conflict', 409);
      final until = clock()
          .toUtc()
          .add(MediaLimits.leaseLifetime)
          .toIso8601String();
      slot['until'] = until;
      await store.update('media_quotas', 'global', {
        'leasesJson': jsonEncode(slots),
      }, transactionId: tx);
      if (action != null) await action(access, current, tx);
      return store.update('media_assets', assetId, {
        'leaseUntil': until,
      }, transactionId: tx);
    });
  }

  /// Trusted worker entry. A stale/revoked worker can never publish bytes as
  /// ready: role, upload intent, revision, generation and lease are rechecked.
  Future<void> processMedia(String assetId) async {
    Row? lease;
    try {
      lease = await _mediaWorkerLease(assetId);
      final manifest = (jsonDecode(lease['chunksJson'] as String) as List)
          .cast<String>();
      final original = BytesBuilder(copy: false);
      for (var i = 0; i < manifest.length; i++) {
        await _mediaRenew(lease);
        final chunk = await _files.read(
          _mediaFile(assetId, 'chunk-$i'),
          maximumBytes: MediaLimits.chunkBytes,
        );
        final expected = min(
          MediaLimits.chunkBytes,
          (lease['inputBytes'] as int) - original.length,
        );
        if (chunk.length != expected ||
            sha256.convert(chunk).toString() != manifest[i])
          throw const ServiceException('invalid_media', 400);
        original.add(chunk);
      }
      final bytes = original.takeBytes();
      if (bytes.length != lease['inputBytes'] ||
          sha256.convert(bytes).toString() != lease['inputHash'])
        throw const ServiceException('invalid_media', 400);
      // The full header/structure/expansion preflight runs inside the isolated
      // sanitizer, before decoder allocation, under its 30-second hard deadline.
      final mime = bytes.length >= 12 && bytes[0] == 0x89 && bytes[1] == 0x50
          ? 'image/png'
          : bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8
          ? 'image/jpeg'
          : bytes.length >= 12 &&
                ascii.decode(bytes.sublist(0, 4), allowInvalid: true) ==
                    'RIFF' &&
                ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP'
          ? 'image/webp'
          : null;
      if (mime != lease['inputType'])
        throw const ServiceException('invalid_media', 400);
      await _mediaRenew(lease);
      final clean = await sanitizeOffThread(bytes);
      await _mediaRenew(lease);
      await _files.put(
        _mediaFile(assetId, 'display'),
        clean.display,
        clean.contentType,
      );
      await _mediaRenew(lease);
      await _files.put(
        _mediaFile(assetId, 'thumbnail'),
        clean.thumbnail,
        clean.contentType,
      );
      await _mediaRenew(
        lease,
        action: (access, row, tx) async {
          final actual =
              clean.display.length +
              clean.thumbnail.length +
              (row['inputBytes'] as int);
          await _mediaUsage(
            row['appId'] as String,
            actual - (row['storedBytes'] as int),
            0,
            tx,
          );
          await store.update('media_assets', assetId, {
            'status': 'ready',
            'originalDeleteAfter': clock()
                .toUtc()
                .add(MediaLimits.deletionQuietPeriod)
                .toIso8601String(),
            'storedBytes': actual,
            'displayBytes': clean.display.length,
            'thumbnailBytes': clean.thumbnail.length,
            'displayHash': sha256.convert(clean.display).toString(),
            'thumbnailHash': sha256.convert(clean.thumbnail).toString(),
            'contentType': clean.contentType,
            'width': clean.width,
            'height': clean.height,
            'failureCategory': null,
            'updatedAt': _mediaTime(),
          }, transactionId: tx);
          await _queueDispatch(
            'media_cleanup',
            assetId,
            row['appId'] as String,
            clock().toUtc().add(MediaLimits.deletionQuietPeriod),
            tx,
          );
          await _specChanged(
            row['uploaderId'] as String,
            access,
            _identity('e', [assetId, 'ready']),
            'media.ready',
            tx,
          );
        },
      );
      await _mediaRemoveOriginals(assetId);
    } on spec.SpecException {
      if (lease != null) await _mediaFail(lease, 'invalid_media');
    } on ServiceException catch (error) {
      if (lease != null &&
          {
            'invalid_media',
            'not_found',
            'forbidden',
            'app_archived',
            'revision_conflict',
            'definition_conflict',
          }.contains(error.code))
        await _mediaFail(
          lease,
          error.code == 'invalid_media' ? 'invalid_media' : 'access_changed',
        );
      rethrow;
    } finally {
      if (lease != null)
        await _mediaRelease(assetId, lease['leaseToken'] as String);
    }
  }

  Future<void> _mediaFail(Row lease, String category) async {
    try {
      await _mediaTransaction((tx) async {
        final row = await store.get(
          'media_assets',
          lease[r'$id'] as String,
          transactionId: tx,
        );
        if (row == null ||
            row['status'] != 'processing' ||
            row['leaseToken'] != lease['leaseToken'])
          return;
        await store.update('media_assets', row[r'$id'] as String, {
          'status': 'failed',
          'failureCategory': category,
          'updatedAt': _mediaTime(),
        }, transactionId: tx);
      });
    } catch (_) {
      /* Scheduled recovery preserves the reservation on failure. */
    }
  }

  Future<void> _mediaRemoveOriginals(String assetId) async {
    final initial = await store.get('media_assets', assetId);
    if (initial == null ||
        initial['status'] != 'ready' ||
        initial['originalRemoved'] == true)
      return;
    try {
      for (
        var i = 0;
        i < ((initial['inputBytes'] as int) / MediaLimits.chunkBytes).ceil();
        i++
      ) {
        await _files.remove(_mediaFile(assetId, 'chunk-$i'));
      }
      if (initial['originalDeleteAfter'] == null ||
          _mediaDate(initial['originalDeleteAfter']).isAfter(clock().toUtc()))
        return;
      await _mediaTransaction((tx) async {
        await store.update('apps', initial['appId'] as String, {
          'guard': _nonce(),
        }, transactionId: tx);
        final row = await store.get('media_assets', assetId, transactionId: tx);
        if (row == null ||
            row['status'] != 'ready' ||
            row['originalRemoved'] == true)
          return;
        await _mediaUsage(
          row['appId'] as String,
          -(row['inputBytes'] as int),
          0,
          tx,
        );
        await store.update('media_assets', assetId, {
          'originalRemoved': true,
          'storedBytes':
              (row['storedBytes'] as int) - (row['inputBytes'] as int),
        }, transactionId: tx);
      });
    } catch (_) {
      /* Paths and bytes remain reserved until a later successful retry. */
    }
  }

  /// Trusted scheduled recovery. Tombstones retain deterministic file identities
  /// so a late Storage write from an expired execution is swept on later runs.
  /// Delivered client bytes cannot be recalled; subsequent broker reads reauth.
  Future<int> cleanupMedia({int limit = 10, String? assetId}) async {
    _files;
    if (limit < 1 || limit > 50) throw ArgumentError.value(limit);
    var removed = 0, attempted = 0;
    final selected = assetId == null
        ? null
        : await store.get('media_assets', _validId(assetId));
    final candidates = assetId == null
        ? await _mediaRows('media_assets', {})
        : [if (selected != null) selected];
    candidates.sort((a, b) {
      final retired = (a['status'] == 'deleted' ? 1 : 0).compareTo(
        b['status'] == 'deleted' ? 1 : 0,
      );
      return retired != 0
          ? retired
          : ((a['maintenanceAt'] ?? a['updatedAt']) as String).compareTo(
              (b['maintenanceAt'] ?? b['updatedAt']) as String,
            );
    });
    for (final candidate in candidates) {
      if (attempted >= limit) break;
      final id = candidate[r'$id'] as String;
      final originalPending =
          candidate['status'] == 'ready' &&
          candidate['originalRemoved'] != true;
      if (originalPending) {
        attempted++;
        await _mediaTransaction((tx) async {
          await store.update('apps', candidate['appId'] as String, {
            'guard': _nonce(),
          }, transactionId: tx);
          await store.update('media_assets', id, {
            'maintenanceAt': _mediaTime(),
          }, transactionId: tx);
        });
        await _mediaRemoveOriginals(id);
      }
      final now = clock().toUtc();
      if (candidate['status'] != 'deleted' &&
          candidate['status'] != 'deleting' &&
          (candidate['status'] == 'ready'
              ? !_mediaDate(
                  candidate['updatedAt'],
                ).isBefore(now.subtract(MediaLimits.unreferencedGrace))
              : !_mediaDate(candidate['expiresAt']).isBefore(now)))
        continue;
      if (!originalPending) attempted++;
      final token = _nonce();
      final deleting = await _mediaTransaction((tx) async {
        await store.update('apps', candidate['appId'] as String, {
          'guard': _nonce(),
        }, transactionId: tx);
        final row = await store.get('media_assets', id, transactionId: tx);
        if (row == null ||
            (row['leaseUntil'] != null &&
                _mediaDate(row['leaseUntil']).isAfter(clock().toUtc())))
          return null;
        final refs = await _mediaRows('media_refs', {
          'appId': row['appId'] as String,
        }, tx: tx);
        if (refs.any(
          (ref) =>
              (jsonDecode(ref['assetIdsJson'] as String) as List).contains(id),
        ))
          return null;
        if (row['status'] == 'ready' &&
            !_mediaDate(
              row['updatedAt'],
            ).isBefore(clock().toUtc().subtract(MediaLimits.unreferencedGrace)))
          return null;
        if (!{'ready', 'deleting', 'deleted'}.contains(row['status']) &&
            !_mediaDate(row['expiresAt']).isBefore(clock().toUtc()))
          return null;
        final deleteAt = row['deleteAfter'] == null
            ? clock().toUtc().add(MediaLimits.deletionQuietPeriod)
            : _mediaDate(row['deleteAfter']);
        if (deleteAt.isAfter(clock().toUtc()))
          await _queueDispatch(
            'media_cleanup',
            id,
            row['appId'] as String,
            deleteAt,
            tx,
          );
        return store.update('media_assets', id, {
          'status': 'deleting',
          'maintenanceAt': _mediaTime(),
          'deleteAfter':
              row['deleteAfter'] ??
              clock()
                  .toUtc()
                  .add(MediaLimits.deletionQuietPeriod)
                  .toIso8601String(),
          'leaseToken': token,
          'leaseUntil': clock()
              .toUtc()
              .add(MediaLimits.leaseLifetime)
              .toIso8601String(),
        }, transactionId: tx);
      });
      if (deleting == null) continue;
      try {
        for (
          var i = 0;
          i < ((deleting['inputBytes'] as int) / MediaLimits.chunkBytes).ceil();
          i++
        ) {
          await _files.remove(_mediaFile(id, 'chunk-$i'));
        }
        for (final variant in ['display', 'thumbnail'])
          await _files.remove(_mediaFile(id, variant));
        if (_mediaDate(deleting['deleteAfter']).isAfter(clock().toUtc())) {
          await _mediaRelease(id, token);
          continue;
        }
        await _mediaTransaction((tx) async {
          await store.update('apps', deleting['appId'] as String, {
            'guard': _nonce(),
          }, transactionId: tx);
          final row = await store.get('media_assets', id, transactionId: tx);
          if (row == null ||
              row['status'] != 'deleting' ||
              row['leaseToken'] != token)
            return;
          if ((row['storedBytes'] as int) > 0)
            await _mediaUsage(
              row['appId'] as String,
              -(row['storedBytes'] as int),
              -1,
              tx,
            );
          await store.update('media_assets', id, {
            'status': 'deleted',
            'storedBytes': 0,
            'leaseToken': null,
            'leaseUntil': null,
            'updatedAt': _mediaTime(),
          }, transactionId: tx);
        });
        removed++;
      } catch (_) {
        await _mediaRelease(id, token);
      }
    }
    return removed;
  }

  /// Recovery is bounded by a caller-controlled batch, without user-selected
  /// modes or provider work. Expired jobs are left for cleanup, never extended.
  Future<int> recoverMedia({int limit = 10}) async {
    if (limit < 1 || limit > 50) throw ArgumentError.value(limit);
    var processed = 0, attempted = 0;
    for (final row in await _mediaRows('media_assets', {})) {
      if (attempted >= limit) break;
      if (!{'queued', 'processing'}.contains(row['status']) ||
          !_mediaDate(row['expiresAt']).isAfter(clock().toUtc()) ||
          (row['leaseUntil'] != null &&
              _mediaDate(row['leaseUntil']).isAfter(clock().toUtc())))
        continue;
      attempted++;
      try {
        await processMedia(row[r'$id'] as String);
        processed++;
      } on ServiceException {
        /* Each durable state remains available to recovery. */
      } on RestException {
        /* Do not hide global provider failure as a completed batch. */
        rethrow;
      }
    }
    return processed;
  }

  Future<Row> _executeMedia(String actor, Row input) async {
    switch (input['op']) {
      case 'spec.media.begin':
        return _mediaBegin(actor, input);
      case 'spec.media.chunk':
        return _mediaChunk(actor, input);
      case 'spec.media.complete':
        return _mediaComplete(actor, input);
      case 'spec.media.status':
        _inputKeys(input, {'op', 'appId', 'assetId'});
        return {
          'asset': _mediaInfo(
            await _mediaReadAsset(
              actor,
              _validId(input['appId']),
              _validId(input['assetId']),
              status: true,
            ),
          ),
        };
      case 'spec.media.read':
        return _mediaRead(actor, input);
      case 'spec.media.usage':
        _inputKeys(input, {'op', 'appId'});
        return _specRead(actor, _validId(input['appId']), (access, tx) async {
          _files;
          _require(access, 'build', writable: false);
          final row = await store.get(
            'media_quotas',
            _identity('q', [access.app[r'$id'] as String]),
            transactionId: tx,
          );
          final assets = await _mediaRows('media_assets', {
            'appId': access.app[r'$id'] as String,
          }, tx: tx);
          var pending = 0;
          for (final asset in assets) {
            if (asset['status'] == 'deleting')
              pending += asset['storedBytes'] as int;
            else if (asset['status'] == 'ready' &&
                asset['originalRemoved'] != true)
              pending += asset['inputBytes'] as int;
          }
          return {
            'reservedBytes': row?['bytes'] ?? 0,
            'assetCount': row?['assets'] ?? 0,
            'pendingReleaseBytes': pending,
            'maximumBytes': MediaLimits.maxAppBytes,
            'maximumAssets': MediaLimits.maxAppAssets,
          };
        });
      default:
        throw const ServiceException('unknown_operation', 400);
    }
  }
}
