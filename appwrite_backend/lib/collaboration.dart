part of 'service.dart';

extension _Collaboration on PlatformService {
  String _role(Object? value) {
    if (value is! String || !{'builder', 'member', 'viewer'}.contains(value))
      throw const ServiceException('invalid_role', 400);
    return value;
  }

  Future<void> _ensureMembership(
    Row workspace,
    String actor,
    String tx, {
    bool owner = false,
  }) async {
    final workspaceId = workspace[r'$id'] as String;
    final id = _identity('m', [workspaceId, actor]);
    final old = await store.get('memberships', id, transactionId: tx);
    if (old != null &&
        (old['workspaceId'] != workspaceId || old['actorId'] != actor))
      throw const ServiceException('id_conflict', 409);
    if (_validMembership(old, workspaceId, actor)) return;
    if ((old?['revision'] as int? ?? 0) >= 2147483646)
      throw const ServiceException('revision_conflict', 409);
    final data = <String, dynamic>{
      'workspaceId': workspaceId,
      'actorId': actor,
      'role': owner ? 'owner' : 'member',
      'active': true,
      'revision': (old?['revision'] as int? ?? 0) + 1,
    };
    if (old == null) {
      await store.create('memberships', id, data, transactionId: tx);
    } else {
      await store.update('memberships', id, data, transactionId: tx);
    }
  }

  String _hashToken(Object? raw) {
    if (raw is! String || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(raw))
      throw const ServiceException('invitation_unavailable', 404);
    try {
      final bytes = base64Url.decode('$raw=');
      if (bytes.length != 32 ||
          base64Url.encode(bytes).replaceAll('=', '') != raw)
        throw const FormatException();
    } on FormatException {
      throw const ServiceException('invitation_unavailable', 404);
    }
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Row _publicInvitation(Row row) => {
    'id': row[r'$id'],
    'appId': row['appId'],
    'issuerId': row['issuerId'],
    'role': row['role'],
    'recipientId': row['recipientId'],
    'createdAt': row['createdAt'],
    'expiresAt': row['expiresAt'],
    'revoked': row['revoked'],
    'acceptedBy': row['acceptedBy'],
  };

  Future<Row> _stageActorLimit(String actor, String tx) async {
    final id = _identity('q', [actor]);
    var limit = await store.get('actor_limits', id, transactionId: tx);
    if (limit != null && limit['actorId'] != actor)
      throw const ServiceException('id_conflict', 409);
    if (limit == null) {
      limit = await store.create('actor_limits', id, {
        'actorId': actor,
        'guard': _nonce(),
        'invitationTimesJson': '[]',
      }, transactionId: tx);
    } else {
      // An actor-level affected row serializes the rolling-day quota across
      // invitations issued concurrently in different workspaces/apps.
      limit = await store.update('actor_limits', id, {
        'guard': _nonce(),
      }, transactionId: tx);
    }
    return limit;
  }

  Future<void> _reserveWorkspace(String actor, String tx) async {
    await _stageActorLimit(actor, tx);
    final owned = await store.list('workspaces', {
      'ownerId': actor,
    }, transactionId: tx);
    final members = await store.list('memberships', {
      'actorId': actor,
    }, transactionId: tx);
    final ids = {
      ...owned.map((row) => row[r'$id']),
      ...members
          .where((row) => row['active'] == true)
          .map((row) => row['workspaceId']),
    };
    if (ids.length >= 100) throw const ServiceException('quota_exceeded', 429);
  }

  Future<void> _reserveInvitation(String actor, String tx) async {
    final id = _identity('q', [actor]);
    final limit = await _stageActorLimit(actor, tx);
    final now = clock().toUtc();
    final since = now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    final times = (jsonDecode(limit['invitationTimesJson'] as String) as List)
        .cast<int>()
        .where((time) => time > since)
        .toList();
    if (times.length >= 50) throw const ServiceException('quota_exceeded', 429);
    times.add(now.millisecondsSinceEpoch);
    await store.update('actor_limits', id, {
      'invitationTimesJson': jsonEncode(times),
    }, transactionId: tx);
  }

  Future<Row> _createInvitation(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'id',
      'operationId',
      'role',
      'recipientId',
      'token',
    });
    final id = _validId(input['id']);
    final role = _role(input['role']);
    final recipient = input['recipientId'] == null
        ? null
        : _validId(input['recipientId']);
    final tokenHash = _hashToken(input['token']);
    // Neither plaintext bearer tokens nor their original input enter a receipt.
    final normalized = <String, dynamic>{
      ...input,
      'role': role,
      'recipientId': recipient,
    }..remove('token');
    normalized['tokenHash'] = tokenHash;
    return _mutate(actor, normalized, 'share', (tx, access) async {
      if (await store.get('invitations', id, transactionId: tx) != null)
        throw const ServiceException('id_conflict', 409);
      final duplicate = await store.list(
        'invitations',
        {'tokenHash': tokenHash},
        transactionId: tx,
        limit: 1,
      );
      if (duplicate.isNotEmpty)
        throw const ServiceException('id_conflict', 409);
      await _reserveInvitation(actor, tx);
      final issuerGrant = access.role == 'owner'
          ? null
          : await _grant(
              access.app[r'$id'] as String,
              actor,
              transactionId: tx,
            );
      final now = clock().toUtc();
      final row = await store.create('invitations', id, {
        'workspaceId': access.app['workspaceId'],
        'appId': access.app[r'$id'],
        'issuerId': actor,
        'issuerGrantRevision': issuerGrant?['revision'] ?? 0,
        'tokenHash': tokenHash,
        'role': role,
        'recipientId': recipient,
        'createdAt': now.toIso8601String(),
        'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
        'revoked': false,
        'acceptedBy': null,
        'acceptedAt': null,
      }, transactionId: tx);
      return {'invitation': _publicInvitation(row)};
    });
  }

  Future<(Row, AppAccess)> _invitationContext(
    String actor,
    String tokenHash, {
    String? transactionId,
  }) async {
    final matches = await store.list(
      'invitations',
      {'tokenHash': tokenHash},
      transactionId: transactionId,
      limit: 1,
    );
    if (matches.isEmpty)
      throw const ServiceException('invitation_unavailable', 404);
    final invitation = matches.single;
    final app = await store.get(
      'apps',
      invitation['appId'] as String,
      transactionId: transactionId,
    );
    if (app == null ||
        app['workspaceId'] != invitation['workspaceId'] ||
        app['archived'] == true ||
        invitation['revoked'] != false ||
        !DateTime.parse(
          invitation['expiresAt'] as String,
        ).isAfter(clock().toUtc()) ||
        (invitation['recipientId'] != null &&
            invitation['recipientId'] != actor) ||
        (invitation['acceptedBy'] != null && invitation['acceptedBy'] != actor))
      throw const ServiceException('invitation_unavailable', 404);
    AppAccess issuer;
    try {
      issuer = await _access(
        invitation['issuerId'] as String,
        app[r'$id'] as String,
        transactionId: transactionId,
      );
      _require(issuer, 'share');
      if (issuer.role != 'owner') {
        final grant = await _grant(
          app[r'$id'] as String,
          invitation['issuerId'] as String,
          transactionId: transactionId,
        );
        if (grant?['revision'] != invitation['issuerGrantRevision'])
          throw const ServiceException('invitation_unavailable', 404);
      }
      // A previously consumed token can confirm a current membership, but must
      // never recreate a grant or workspace membership that was later revoked.
      if (invitation['acceptedBy'] == actor)
        await _access(
          actor,
          app[r'$id'] as String,
          transactionId: transactionId,
        );
    } on ServiceException {
      throw const ServiceException('invitation_unavailable', 404);
    }
    return (invitation, issuer);
  }

  Future<Row?> _invitationReceipt(
    String actor,
    String tokenHash,
    String operationId,
    String request,
  ) async {
    final (invitation, _) = await _invitationContext(actor, tokenHash);
    final response = await _receipt(
      actor,
      invitation['appId'] as String,
      operationId,
      request,
    );
    if (response != null) await _invitationContext(actor, tokenHash);
    return response;
  }

  Future<Row> _inspectInvitation(String actor, Row input) async {
    _inputKeys(input, {'op', 'token'});
    final tokenHash = _hashToken(input['token']);
    final (_, before) = await _invitationContext(actor, tokenHash);
    final (invitation, current) = await _invitationContext(actor, tokenHash);
    if (before.app['guard'] != current.app['guard'] ||
        before.workspace['guard'] != current.workspace['guard'])
      throw const ServiceException('invitation_unavailable', 404);
    // Return only the app identity and the terms the recipient will accept.
    // Inspection never creates membership, consumes a token, or stores a receipt.
    return {
      'invitation': {
        'appId': invitation['appId'],
        'appName': current.app['name'],
        'role': invitation['role'],
        'expiresAt': invitation['expiresAt'],
        'accepted': invitation['acceptedBy'] == actor,
      },
    };
  }

  Future<Row> _acceptInvitation(String actor, Row input) async {
    _inputKeys(input, {'op', 'operationId', 'token'});
    final tokenHash = _hashToken(input['token']);
    final operationId = _validId(input['operationId']);
    final (initial, issuer) = await _invitationContext(actor, tokenHash);
    final request = _request({
      'op': 'acceptInvitation',
      'operationId': operationId,
      'appId': initial['appId'],
      'tokenHash': tokenHash,
    });
    final previous = await _invitationReceipt(
      actor,
      tokenHash,
      operationId,
      request,
    );
    if (previous != null) return previous;
    try {
      return await _transaction((tx) async {
        await store.update('workspaces', issuer.workspace[r'$id'] as String, {
          'guard': _nonce(),
        }, transactionId: tx);
        await store.update('apps', initial['appId'] as String, {
          'guard': _nonce(),
        }, transactionId: tx);
        final (invite, currentIssuer) = await _invitationContext(
          actor,
          tokenHash,
          transactionId: tx,
        );
        final access = await _adoptLegacyDraft(currentIssuer, tx);
        final oldReceipt = await _receipt(
          actor,
          invite['appId'] as String,
          operationId,
          request,
          transactionId: tx,
        );
        if (oldReceipt != null) return oldReceipt;
        if (invite['acceptedBy'] == null) {
          final workspaceId = access.workspace[r'$id'] as String;
          final membership = await _membership(
            workspaceId,
            actor,
            transactionId: tx,
          );
          if (access.workspace['ownerId'] != actor &&
              !_validMembership(membership, workspaceId, actor))
            await _reserveWorkspace(actor, tx);
          await _ensureMembership(
            access.workspace,
            actor,
            tx,
            owner: access.workspace['ownerId'] == actor,
          );
          if (actor != access.app['ownerId']) {
            final id = _identity('g', [access.app[r'$id'] as String, actor]);
            final old = await store.get('grants', id, transactionId: tx);
            if (old != null &&
                (old['appId'] != access.app[r'$id'] ||
                    old['workspaceId'] != access.app['workspaceId'] ||
                    old['actorId'] != actor))
              throw const ServiceException('id_conflict', 409);
            if ((old?['revision'] as int? ?? 0) >= 2147483646)
              throw const ServiceException('revision_conflict', 409);
            final data = <String, dynamic>{
              'workspaceId': access.app['workspaceId'],
              'appId': access.app[r'$id'],
              'actorId': actor,
              'role': invite['role'],
              'revoked': false,
              'revision': (old?['revision'] as int? ?? 0) + 1,
            };
            if (old == null) {
              await store.create('grants', id, data, transactionId: tx);
            } else {
              await store.update('grants', id, data, transactionId: tx);
            }
          }
          await store.update('invitations', invite[r'$id'] as String, {
            'acceptedBy': actor,
            'acceptedAt': clock().toUtc().toIso8601String(),
          }, transactionId: tx);
        }
        final response = <String, dynamic>{'appId': invite['appId']};
        if (access.app['engine'] == 'appspec.v1')
          await _specChanged(actor, access, operationId, 'join', tx);
        await _saveReceipt(
          actor,
          invite['appId'] as String,
          operationId,
          request,
          response,
          tx,
        );
        return response;
      });
    } on ServiceException catch (error) {
      if (error.code == 'transaction_conflict') {
        final old = await _invitationReceipt(
          actor,
          tokenHash,
          operationId,
          request,
        );
        if (old != null) return old;
      }
      rethrow;
    }
  }

  Future<Row> _listInvitations(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'afterId'});
    final access = await _access(actor, _validId(input['appId']));
    _require(access, 'share', writable: false);
    final afterId = input['afterId'] == null
        ? null
        : _validId(input['afterId']);
    if (afterId != null) {
      final cursor = await store.get('invitations', afterId);
      if (cursor == null ||
          cursor['appId'] != access.app[r'$id'] ||
          cursor['workspaceId'] != access.app['workspaceId'])
        throw const ServiceException('not_found', 404);
    }
    final rows = await store.list(
      'invitations',
      {'appId': access.app[r'$id'] as String},
      limit: 26,
      afterId: afterId,
      detectOverflow: false,
    );
    _require(await _readAgain(actor, access), 'share', writable: false);
    final page = rows.take(25).toList();
    return {
      'invitations': page.map(_publicInvitation).toList(),
      'nextCursor': rows.length > 25 ? page.last[r'$id'] : null,
    };
  }

  Future<Row> _revokeInvitation(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'invitationId', 'operationId'});
    final id = _validId(input['invitationId']);
    return _mutate(actor, input, 'share', (tx, access) async {
      final row = await store.get('invitations', id, transactionId: tx);
      if (row == null ||
          row['appId'] != access.app[r'$id'] ||
          row['workspaceId'] != access.app['workspaceId'])
        throw const ServiceException('not_found', 404);
      final updated = await store.update('invitations', id, {
        'revoked': true,
      }, transactionId: tx);
      return {'invitation': _publicInvitation(updated)};
    }, writable: false);
  }

  Future<Row> _listMembers(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'afterId'});
    final access = await _access(actor, _validId(input['appId']));
    final afterId = input['afterId'] == null
        ? null
        : _validId(input['afterId']);
    if (afterId != null) {
      final cursor = await store.get('grants', afterId);
      if (cursor == null ||
          cursor['appId'] != access.app[r'$id'] ||
          cursor['workspaceId'] != access.app['workspaceId'])
        throw const ServiceException('not_found', 404);
    }
    final rows = await store.list(
      'grants',
      {'appId': access.app[r'$id'] as String},
      limit: 51,
      afterId: afterId,
      detectOverflow: false,
    );
    final page = rows.take(50).toList();
    final members = <Row>[
      if (afterId == null)
        {'actorId': access.app['ownerId'], 'role': 'owner', 'revision': 0},
    ];
    for (final grant in page) {
      final memberActor = grant['actorId'] as String;
      if (memberActor == access.app['ownerId'] ||
          !_validGrant(grant, access.app, memberActor))
        continue;
      // A stale active app grant is insufficient after workspace revocation.
      final member = await _membership(
        access.app['workspaceId'] as String,
        memberActor,
      );
      if (access.workspace['ownerId'] != memberActor &&
          !_validMembership(
            member,
            access.app['workspaceId'] as String,
            memberActor,
          ))
        continue;
      members.add({
        'actorId': memberActor,
        'role': grant['role'],
        'revision': grant['revision'],
      });
    }
    await _readAgain(actor, access);
    return {
      'members': members,
      'nextCursor': rows.length > 50 ? page.last[r'$id'] : null,
    };
  }

  Future<Row> _setGrant(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'actorId',
      'role',
      'expectedRevision',
      'operationId',
    });
    final target = _validId(input['actorId']);
    if (!input.containsKey('role'))
      throw const ServiceException('invalid_request', 400);
    final role = input['role'] == null ? null : _role(input['role']);
    final expected = _revision(input['expectedRevision']);
    return _mutate(actor, input, 'share', (tx, access) async {
      if (target == access.app['ownerId'])
        throw const ServiceException('forbidden', 403);
      final grant = await _grant(
        access.app[r'$id'] as String,
        target,
        transactionId: tx,
      );
      if (grant == null ||
          grant['appId'] != access.app[r'$id'] ||
          grant['workspaceId'] != access.app['workspaceId'] ||
          grant['actorId'] != target)
        throw const ServiceException('not_found', 404);
      if (grant['revision'] != expected)
        throw const ServiceException('revision_conflict', 409);
      if (expected >= 2147483646)
        throw const ServiceException('revision_conflict', 409);
      final row = await store.update('grants', grant[r'$id'] as String, {
        'role': role ?? grant['role'],
        'revoked': role == null,
        'revision': expected + 1,
      }, transactionId: tx);
      return {
        'member': {
          'actorId': target,
          'role': role,
          'revision': row['revision'],
        },
      };
    }, writable: role != null);
  }
}
