part of 'service.dart';

extension _ActivityRuntime on PlatformService {
  /// All currently authorized roles may inspect the same committed metadata,
  /// including after archival. Audit payloads and principals are never DTOs.
  Future<Row> _listActivity(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'cursor', 'limit'});
    final appId = _validId(input['appId']), limit = input['limit'] ?? 50;
    if (limit is! int || limit < 1 || limit > 50)
      throw const ServiceException('invalid_request', 400);
    Row? cursor;
    if (input['cursor'] != null) {
      try {
        final encoded = input['cursor'];
        if (encoded is! String || encoded.length > 1024) {
          throw const FormatException();
        }
        final decoded = spec.object(
          jsonDecode(utf8.decode(base64Url.decode(encoded))),
          'invalid_request',
        );
        if (decoded.length != 3 ||
            !decoded.keys.toSet().containsAll({'scope', 'revision', 'id'}) ||
            decoded['scope'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(decoded['scope'] as String) ||
            decoded['revision'] is! int ||
            (decoded['revision'] as int) < 0 ||
            (decoded['revision'] as int) >= 2147483647) {
          throw const FormatException();
        }
        _validId(decoded['id']);
        cursor = decoded;
      } catch (_) {
        throw const ServiceException('invalid_request', 400);
      }
    }
    final savedCursor = cursor;
    return _specRead(actor, appId, (access, tx) async {
      final scope = spec.hashJson({
        'actor': actor,
        'app': appId,
        'workspace': access.app['workspaceId'],
        'limit': limit,
        'kind': 'activity.v1',
      });
      final revision = _storedRevision(access.app, 'controlRevision');
      String? after;
      if (savedCursor != null) {
        if (savedCursor['scope'] != scope)
          throw const ServiceException('invalid_request', 400);
        if (savedCursor['revision'] != revision)
          throw const ServiceException('revision_conflict', 409);
        after = savedCursor['id'] as String;
        final anchor = await store.get('audit', after, transactionId: tx);
        if (anchor == null ||
            anchor['appId'] != appId ||
            anchor['workspaceId'] != access.app['workspaceId'])
          throw const ServiceException('revision_conflict', 409);
      }
      // The existing app index plus the RowStore's stable $id ordering permits
      // one bounded page. This is not a claim of chronological ID ordering.
      final rows = await store.list(
        'audit',
        {'appId': appId},
        transactionId: tx,
        limit: limit + 1,
        afterId: after,
        detectOverflow: false,
        select: [r'$id', 'workspaceId', 'appId', 'action', 'createdAt'],
      );
      if (rows.length > limit + 1)
        throw const ServiceException('integrity_error', 500);
      final items = <Row>[];
      var previous = after;
      for (final row in rows) {
        final id = row[r'$id'], action = row['action'];
        if (row['appId'] != appId ||
            row['workspaceId'] != access.app['workspaceId'] ||
            id is! String ||
            !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$').hasMatch(id) ||
            (previous != null && id.compareTo(previous) <= 0) ||
            action is! String ||
            !RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,127}$').hasMatch(action))
          throw const ServiceException('integrity_error', 500);
        previous = id;
        String createdAt;
        try {
          createdAt = spec.strictTimestamp(row['createdAt'], 'Activity time');
        } on spec.SpecException {
          throw const ServiceException('integrity_error', 500);
        }
        if (items.length < limit)
          items.add({
            'id': id,
            'action': action,
            'createdAt': createdAt,
            'status': 'committed',
          });
      }
      return {
        'appId': appId,
        'items': items,
        'nextCursor': rows.length > limit
            ? base64Url.encode(
                utf8.encode(
                  jsonEncode({
                    'scope': scope,
                    'revision': revision,
                    'id': items.last['id'],
                  }),
                ),
              )
            : null,
      };
    });
  }
}
