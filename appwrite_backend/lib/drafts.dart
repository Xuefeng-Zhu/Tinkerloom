part of 'service.dart';

extension _PrivateDrafts on PlatformService {
  String _draftId(String appId, String actor) => _identity('d', [appId, actor]);

  Future<Row?> _privateDraft(String actor, AppAccess access,
      {String? transactionId}) async {
    final draft = await store.get(
        'drafts', _draftId(access.app[r'$id'] as String, actor),
        transactionId: transactionId);
    if (draft != null) {
      if (draft['actorId'] != actor ||
          draft['appId'] != access.app[r'$id'] ||
          draft['workspaceId'] != access.app['workspaceId'])
        throw const ServiceException('not_found', 404);
      return draft;
    }
    // An unadopted v1 candidate belongs solely to its original app owner.
    if (access.app['headRevision'] == null &&
        actor == access.app['ownerId'] &&
        _storedRevision(access.app, 'draftRevision') > 0) {
      final definition = _definition(access.app, 'draftJson');
      if (definition != null)
        return {
          'actorId': actor,
          'appId': access.app[r'$id'],
          'workspaceId': access.app['workspaceId'],
          'revision': _storedRevision(access.app, 'draftRevision'),
          'candidateRevision': _storedRevision(access.app, 'draftRevision'),
          'basePublishedRevision':
              _storedRevision(access.app, 'publishedRevision'),
          'definitionJson': jsonEncode(definition),
        };
    }
    return null;
  }

  Future<AppAccess> _adoptLegacyDraft(AppAccess access, String tx) async {
    if (access.app['headRevision'] != null) return access;
    final owner = access.app['ownerId'] as String;
    final ownerAccess = AppAccess(access.app, access.workspace, 'owner');
    final draft = await _privateDraft(owner, ownerAccess, transactionId: tx);
    if (draft != null && draft[r'$id'] == null) {
      await store.create(
          'drafts', _draftId(access.app[r'$id'] as String, owner), draft,
          transactionId: tx);
    }
    final head = max(_storedRevision(access.app, 'draftRevision'),
        _storedRevision(access.app, 'publishedRevision'));
    final app = await store.update(
        'apps', access.app[r'$id'] as String, {'headRevision': head},
        transactionId: tx);
    return AppAccess(app, access.workspace, access.role);
  }

  Future<Row> _publicApp(String actor, AppAccess access,
      {String? transactionId}) async {
    final draft = access.builder
        ? await _privateDraft(actor, access, transactionId: transactionId)
        : null;
    return {
      ..._appSummary(access),
      'draftRevision': draft?['revision'] ?? 0,
      'candidateRevision': draft?['candidateRevision'] ?? 0,
      'basePublishedRevision': draft?['basePublishedRevision'] ??
          _storedRevision(access.app, 'publishedRevision'),
      'publishedRevision': _storedRevision(access.app, 'publishedRevision'),
      'definition': draft == null ? null : _definition(draft, 'definitionJson'),
      'publishedDefinition': _definition(access.app, 'publishedJson'),
    };
  }

  Future<Row> _saveDraft(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'operationId',
      'expectedRevision',
      'expectedPublishedRevision',
      'definition'
    });
    final expected = _revision(input['expectedRevision']);
    final expectedPublished = input.containsKey('expectedPublishedRevision')
        ? _revision(input['expectedPublishedRevision'])
        : null;
    final definition = validateDefinition(input['definition']);
    final normalized = {...input, 'definition': definition};
    return _mutate(actor, normalized, 'build', (tx, access) async {
      final published = _storedRevision(access.app, 'publishedRevision');
      if (actor != access.app['ownerId'] && published == 0)
        throw const ServiceException('not_found', 404);
      if (expectedPublished == null && access.role != 'owner')
        throw const ServiceException('invalid_request', 400);
      final draft = await _privateDraft(actor, access, transactionId: tx);
      if ((draft?['revision'] ?? 0) != expected)
        throw const ServiceException('revision_conflict', 409);
      if ((expectedPublished != null && expectedPublished != published) ||
          (expectedPublished == null &&
              draft != null &&
              draft['basePublishedRevision'] != published))
        throw const ServiceException('definition_conflict', 409);
      final head = _storedRevision(access.app, 'headRevision');
      if (head >= 2147483646)
        throw const ServiceException('revision_conflict', 409);
      final data = <String, dynamic>{
        'workspaceId': access.app['workspaceId'],
        'appId': access.app[r'$id'],
        'actorId': actor,
        'revision': expected + 1,
        'candidateRevision': head + 1,
        'basePublishedRevision': published,
        'definitionJson': jsonEncode(definition),
      };
      if (draft == null) {
        await store.create(
            'drafts', _draftId(access.app[r'$id'] as String, actor), data,
            transactionId: tx);
      } else {
        await store.update(
            'drafts', _draftId(access.app[r'$id'] as String, actor), data,
            transactionId: tx);
      }
      final app = await store.update(
          'apps',
          access.app[r'$id'] as String,
          {
            'headRevision': head + 1,
            // Preserve v1 owner state for explicit migration and old clients; these
            // columns are never exposed to another builder or used as their draft.
            if (access.role == 'owner') 'draftRevision': expected + 1,
            if (access.role == 'owner') 'draftJson': jsonEncode(definition),
          },
          transactionId: tx);
      return {
        'app': await _publicApp(
            actor, AppAccess(app, access.workspace, access.role),
            transactionId: tx)
      };
    });
  }

  Future<Row> _publishApp(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'operationId',
      'expectedRevision',
      'expectedPublishedRevision',
      'candidateRevision'
    });
    final expected = _revision(input['expectedRevision']);
    final expectedPublished = input.containsKey('expectedPublishedRevision')
        ? _revision(input['expectedPublishedRevision'])
        : null;
    final candidate = input.containsKey('candidateRevision')
        ? _revision(input['candidateRevision'])
        : null;
    return _mutate(actor, input, 'build', (tx, access) async {
      final draft = await _privateDraft(actor, access, transactionId: tx);
      if ((draft?['revision'] ?? 0) != expected)
        throw const ServiceException('revision_conflict', 409);
      if (draft == null || expected == 0)
        throw const ServiceException('not_published', 409);
      if (access.role != 'owner' &&
          (expectedPublished == null || candidate == null))
        throw const ServiceException('invalid_request', 400);
      final published = _storedRevision(access.app, 'publishedRevision');
      if (draft['basePublishedRevision'] != published ||
          (expectedPublished != null && expectedPublished != published) ||
          (candidate != null && candidate != draft['candidateRevision']))
        throw const ServiceException('definition_conflict', 409);
      final definition = _definition(draft, 'definitionJson')!;
      final prior = _definition(access.app, 'publishedJson');
      if (prior != null) requireCompatible(prior, definition);
      final revision = draft['candidateRevision'] as int;
      // A published candidate is immutable; all later saves allocate a fresh
      // global candidate identity, independent of the author's local counter.
      final app = await store.update(
          'apps',
          access.app[r'$id'] as String,
          {
            'publishedRevision': revision,
            'publishedJson': jsonEncode(definition),
          },
          transactionId: tx);
      await store.update(
          'drafts',
          _draftId(access.app[r'$id'] as String, actor),
          {'basePublishedRevision': revision},
          transactionId: tx);
      return {
        'app': await _publicApp(
            actor, AppAccess(app, access.workspace, access.role),
            transactionId: tx)
      };
    });
  }
}
