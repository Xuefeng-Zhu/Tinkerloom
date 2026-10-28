import 'dart:async';
import 'dart:convert';

import '../lib/service.dart';
import 'memory_store.dart';

const _definition = <String, dynamic>{
  'title': 'Notes',
  'description': '',
  'primaryFieldId': 'title',
  'fields': [
    {'id': 'title', 'label': 'Title', 'kind': 'text', 'required': true},
    {'id': 'body', 'label': 'Body', 'kind': 'longText'},
  ],
};

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _error(Future<dynamic> Function() action, String code) async {
  try {
    await action();
    throw StateError('Expected $code');
  } on ServiceException catch (error) {
    _check(error.code == code, 'Expected $code, received ${error.code}');
  }
}

String _token(int seed) => base64Url
    .encode(List.generate(32, (i) => (i + seed) % 256))
    .replaceAll('=', '');

Map<String, dynamic> _save(String actor, int revision, int base,
        {Map<String, dynamic> definition = _definition}) =>
    {
      'op': 'saveDraft',
      'appId': 'app',
      'operationId': 'save-$actor-$revision-$base',
      'expectedRevision': revision,
      'expectedPublishedRevision': base,
      'definition': definition,
    };

Map<String, dynamic> _publish(
        String actor, int revision, int base, int candidate) =>
    {
      'op': 'publishApp',
      'appId': 'app',
      'operationId': 'publish-$actor-$revision-$base',
      'expectedRevision': revision,
      'expectedPublishedRevision': base,
      'candidateRevision': candidate,
    };

Future<(MemoryStore, PlatformService)> _fixture(
    {MemoryStore? store,
    DateTime Function()? clock,
    bool publish = true}) async {
  final memory = store ?? MemoryStore();
  final api = PlatformService(memory, clock: clock);
  await api.execute(
      'alice', {'op': 'createWorkspace', 'id': 'ws', 'name': 'Workspace'});
  await api.execute('alice',
      {'op': 'createApp', 'id': 'app', 'workspaceId': 'ws', 'name': 'Notes'});
  if (publish) {
    await api.execute('alice', _save('alice', 0, 0));
    await api.execute('alice', _publish('alice', 1, 0, 1));
  }
  return (memory, api);
}

Future<Map<String, dynamic>> _invite(PlatformService api, int seed,
        {String issuer = 'alice',
        String role = 'builder',
        String? recipient}) async =>
    api.execute(issuer, {
      'op': 'createInvitation',
      'appId': 'app',
      'id': 'invite-$seed',
      'operationId': 'issue-$seed',
      'role': role,
      'recipientId': recipient,
      'token': _token(seed)
    });

Future<void> _join(PlatformService api, String actor, int seed,
    {String role = 'builder', String issuer = 'alice'}) async {
  await _invite(api, seed, issuer: issuer, role: role);
  await api.execute(actor, {
    'op': 'acceptInvitation',
    'token': _token(seed),
    'operationId': 'join-$actor-$seed'
  });
}

Map<String, dynamic> _record(String operation,
        {int expected = 0, int definition = 1, String title = 'Shared'}) =>
    {
      'op': 'saveRecord',
      'appId': 'app',
      'id': 'record',
      'operationId': operation,
      'expectedRevision': expected,
      'definitionRevision': definition,
      'values': {'title': title, 'body': ''},
    };

class _ControlledStore extends MemoryStore {
  int remaining = 0;
  Completer<void>? gate;
  Future<void> Function()? onReceiptRead;

  void barrier(int count) {
    remaining = count;
    gate = Completer<void>();
  }

  @override
  Future<Map<String, dynamic>?> get(String table, String id,
      {String? transactionId}) async {
    if (table == 'receipts' && transactionId == null && onReceiptRead != null) {
      final hook = onReceiptRead!;
      onReceiptRead = null;
      await hook();
    }
    return super.get(table, id, transactionId: transactionId);
  }

  @override
  Future<void> finishTransaction(String transactionId,
      {required bool commit}) async {
    if (commit && remaining > 0) {
      final wait = gate!;
      remaining--;
      if (remaining == 0) wait.complete();
      await wait.future;
    }
    return super.finishTransaction(transactionId, commit: commit);
  }
}

Future<int> runCollaborationChecks() async {
  var passed = 0;
  Future<void> test(String label, Future<void> Function() run) async {
    await run();
    passed++;
    print('PASS $label');
  }

  await test(
      'invitations persist hashes only and retain exact sanitized receipts',
      () async {
    final (store, api) = await _fixture();
    final issued = await _invite(api, 1, recipient: 'bob');
    final retry = await _invite(api, 1, recipient: 'bob');
    _check(jsonEncode(issued) == jsonEncode(retry),
        'Issue retry changed response');
    _check(!jsonEncode(store.rows).contains(_token(1)),
        'Plaintext token persisted');
    final invitation = (issued['invitation'] as Map);
    _check(
        !invitation.containsKey('tokenHash') &&
            !invitation.containsKey('token'),
        'Hash/token exposed');
    final created = DateTime.parse(invitation['createdAt'] as String);
    final expires = DateTime.parse(invitation['expiresAt'] as String);
    _check(
        expires.difference(created) == const Duration(days: 7), 'Wrong expiry');
    await _error(
        () => api.execute('alice', {
              'op': 'createInvitation',
              'appId': 'app',
              'id': 'invite-1',
              'operationId': 'issue-1',
              'role': 'viewer',
              'recipientId': 'bob',
              'token': _token(1)
            }),
        'operation_conflict');
  });

  await test(
      'bound single-use invitation adds workspace membership and one app grant',
      () async {
    final (store, api) = await _fixture();
    await api.execute('alice', {
      'op': 'createApp',
      'id': 'private-app',
      'workspaceId': 'ws',
      'name': 'Hidden'
    });
    await _invite(api, 2, recipient: 'bob', role: 'viewer');
    await _error(
        () => api.execute('mallory', {
              'op': 'acceptInvitation',
              'token': _token(2),
              'operationId': 'wrong'
            }),
        'invitation_unavailable');
    final command = {
      'op': 'acceptInvitation',
      'token': _token(2),
      'operationId': 'join-bob'
    };
    final accepted = await api.execute('bob', command);
    _check(accepted['appId'] == 'app', 'Joined wrong app');
    _check(
        jsonEncode(await api.execute('bob', command)) == jsonEncode(accepted),
        'Join retry changed');
    await _error(
        () => api.execute('mallory', {
              'op': 'acceptInvitation',
              'token': _token(2),
              'operationId': 'used'
            }),
        'invitation_unavailable');
    final apps = (await api.execute(
        'bob', {'op': 'listApps', 'workspaceId': 'ws'}))['apps'] as List;
    _check(apps.length == 1 && (apps.single as Map)['id'] == 'app',
        'Membership leaked another app');
    _check(
        (await api.execute('bob', {'op': 'listWorkspaces'}))['workspaces']
            is List,
        'Shared workspace missing');
    _check(store.rows['grants']!.length == 1, 'Duplicate grant');
    await _error(
        () => api.execute('bob', {'op': 'getApp', 'appId': 'private-app'}),
        'not_found');
  });

  await test(
      'all roles read published records but member and viewer cannot perform generic writes',
      () async {
    final (_, api) = await _fixture();
    await api.execute('alice', _record('initial'));
    for (final entry
        in {'bob': 'builder', 'carol': 'member', 'dave': 'viewer'}.entries) {
      await _join(api, entry.key, entry.key.codeUnitAt(0), role: entry.value);
      final app = (await api
          .execute(entry.key, {'op': 'getApp', 'appId': 'app'}))['app'] as Map;
      _check(app['definition'] == null && app['draftRevision'] == 0,
          'Owner draft leaked');
      _check(app['role'] == entry.value && app['publishedDefinition'] != null,
          'Role/publication missing');
      final page = await api.execute(entry.key,
          {'op': 'listRecords', 'appId': 'app', 'definitionRevision': 1});
      _check(
          (page['records'] as List).length == 1, 'Published record unreadable');
      if (entry.value != 'builder') {
        await _error(
            () => api.execute(
                entry.key, _record('denied-${entry.key}', expected: 1)),
            'forbidden');
        await _error(
            () => api.execute(entry.key, _save(entry.key, 0, 1)), 'forbidden');
        await _error(
            () => _invite(api, entry.key.codeUnitAt(0) + 1, issuer: entry.key),
            'forbidden');
        await _error(
            () => api
                .execute(entry.key, {'op': 'listInvitations', 'appId': 'app'}),
            'forbidden');
      }
    }
    await api.execute(
        'bob', _record('builder-edit', expected: 1, title: 'Builder edit'));
    final members = (await api.execute(
        'dave', {'op': 'listMembers', 'appId': 'app'}))['members'] as List;
    _check(members.length == 4, 'Authorized member directory incomplete');
  });

  await test('shared editors preserve the original record tenant owner',
      () async {
    final (store, api) = await _fixture();
    await _join(api, 'bob', 4);
    await api.execute('bob', _record('builder-create'));
    _check(store.rows['records']!['record']!['ownerId'] == 'alice',
        'Editor replaced tenant owner');
    await api.execute('alice', _record('owner-edit', expected: 1));
    _check(store.rows['records']!['record']!['ownerId'] == 'alice',
        'Owner identity changed');
  });

  await test(
      'workspace membership is necessary even for an active app grant and app owner',
      () async {
    final (store, api) = await _fixture();
    await _join(api, 'bob', 5);
    await api.execute('bob', {
      'op': 'createApp',
      'id': 'bobs-app',
      'workspaceId': 'ws',
      'name': 'Bob owns this'
    });
    _check(
        (await api.execute(
            'alice', {'op': 'listApps', 'workspaceId': 'ws'}))['apps'] is List,
        'Owner workspace unavailable');
    await _error(
        () => api.execute('alice', {'op': 'getApp', 'appId': 'bobs-app'}),
        'not_found');
    final membership = store.rows['memberships']!.values
        .singleWhere((row) => row['actorId'] == 'bob');
    await store
        .update('memberships', membership[r'$id'] as String, {'active': false});
    for (final id in ['app', 'bobs-app']) {
      await _error(
          () => api.execute('bob', {'op': 'getApp', 'appId': id}), 'not_found');
    }
    await _error(
        () => api.execute('bob', {'op': 'listApps', 'workspaceId': 'ws'}),
        'not_found');
  });

  await test(
      'private builder candidates and publication bases cannot overwrite another publication',
      () async {
    final (_, api) = await _fixture();
    await _join(api, 'bob', 6);
    await _join(api, 'carol', 7);
    final bobDef = {..._definition, 'title': 'Bob private'};
    final carolDef = {..._definition, 'title': 'Carol private'};
    final bob = (await api.execute(
        'bob', _save('bob', 0, 1, definition: bobDef)))['app'] as Map;
    final carol = (await api.execute(
        'carol', _save('carol', 0, 1, definition: carolDef)))['app'] as Map;
    _check(bob['candidateRevision'] != carol['candidateRevision'],
        'Candidate identity reused');
    final alice = (await api
        .execute('alice', {'op': 'getApp', 'appId': 'app'}))['app'] as Map;
    _check((alice['definition'] as Map)['title'] == 'Notes',
        'Builder draft leaked to owner');
    _check((bob['definition'] as Map)['title'] == 'Bob private',
        'Private candidate changed');
    final published = (await api.execute('carol',
            _publish('carol', 1, 1, carol['candidateRevision'] as int)))['app']
        as Map;
    _check(published['publishedRevision'] == carol['candidateRevision'],
        'Wrong candidate published');
    await _error(
        () => api.execute(
            'bob', _publish('bob', 1, 1, bob['candidateRevision'] as int)),
        'definition_conflict');
    await _error(
        () => api.execute('bob', _save('bob', 1, 1, definition: bobDef)),
        'definition_conflict');
    final nextBase = published['publishedRevision'] as int;
    final rebased = (await api.execute(
        'bob', _save('bob', 1, nextBase, definition: bobDef)))['app'] as Map;
    await _error(
        () => api.execute('bob', {
              ..._publish(
                  'bob', 2, nextBase, rebased['candidateRevision'] as int),
              'candidateRevision': (rebased['candidateRevision'] as int) - 1
            }),
        'definition_conflict');
    await api.execute('bob',
        _publish('bob', 2, nextBase, rebased['candidateRevision'] as int));
  });

  await test(
      'v1 owner state is adopted before sharing while old receipt responses remain exact',
      () async {
    final store = MemoryStore();
    final api = PlatformService(store);
    await store
        .create('workspaces', 'ws', {'ownerId': 'alice', 'name': 'Legacy'});
    await store.create('apps', 'app', {
      'ownerId': 'alice',
      'workspaceId': 'ws',
      'name': 'Legacy',
      'guard': 'old',
      'draftRevision': 2,
      'publishedRevision': 1,
      'draftJson': jsonEncode({..._definition, 'title': 'Owner private'}),
      'publishedJson': jsonEncode(_definition)
    });
    final rawResponse = {
      'app': {
        'id': 'app',
        'workspaceId': 'ws',
        'name': 'Legacy',
        'draftRevision': 1,
        'publishedRevision': 0,
        'definition': _definition,
        'publishedDefinition': null
      }
    };
    final oldCommand = {
      'op': 'saveDraft',
      'appId': 'app',
      'operationId': 'old-save',
      'expectedRevision': 0,
      'definition': _definition
    };
    // Canonical request normalization is copied from an actual service receipt.
    final (_, normal) = await _fixture(publish: false);
    await normal.execute('alice', {...oldCommand, 'appId': 'app'});
    final request = (normal.store as MemoryStore)
        .rows['receipts']!['old-save']!['requestJson'];
    await store.create('receipts', 'old-save', {
      'actorId': 'alice',
      'appId': 'app',
      'requestJson': request,
      'responseJson': jsonEncode(rawResponse)
    });
    await _join(api, 'bob', 8);
    final adopted = store.rows['drafts']!.values
        .singleWhere((row) => row['actorId'] == 'alice');
    _check(adopted['revision'] == 2 && adopted['basePublishedRevision'] == 1,
        'Legacy draft not adopted');
    final bob = (await api
        .execute('bob', {'op': 'getApp', 'appId': 'app'}))['app'] as Map;
    _check(bob['definition'] == null && bob['draftRevision'] == 0,
        'Legacy owner candidate leaked');
    final saved = (await api.execute('bob', _save('bob', 0, 1)))['app'] as Map;
    await api.execute(
        'bob', _publish('bob', 1, 1, saved['candidateRevision'] as int));
    await _error(
        () => api.execute('alice', {
              'op': 'publishApp',
              'appId': 'app',
              'expectedRevision': 2,
              'operationId': 'stale-owner'
            }),
        'definition_conflict');
    _check(
        jsonEncode(await api.execute('alice', oldCommand)) ==
            jsonEncode(rawResponse),
        'Legacy receipt response changed');
  });

  await test(
      'grant changes check revisions protect owners and reauthorize old receipts',
      () async {
    final (_, api) = await _fixture();
    await _join(api, 'bob', 9);
    final saved = await api.execute('bob', _save('bob', 0, 1));
    _check(saved['app'] != null, 'Builder save failed');
    await _error(
        () => api.execute('bob', {
              'op': 'setGrant',
              'appId': 'app',
              'actorId': 'alice',
              'role': 'viewer',
              'expectedRevision': 0,
              'operationId': 'owner-change'
            }),
        'forbidden');
    await _error(
        () => api.execute('alice', {
              'op': 'setGrant',
              'appId': 'app',
              'actorId': 'missing',
              'role': 'viewer',
              'expectedRevision': 0,
              'operationId': 'missing-change'
            }),
        'not_found');
    final demote = {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'bob',
      'role': 'viewer',
      'expectedRevision': 1,
      'operationId': 'demote'
    };
    await api.execute('alice', demote);
    _check((await api.execute('alice', demote))['member'] != null,
        'Exact grant retry failed');
    await _error(() => api.execute('bob', _save('bob', 0, 1)), 'forbidden');
    await _error(
        () => api.execute('alice', {...demote, 'operationId': 'stale-grant'}),
        'revision_conflict');
    await api.execute('alice', {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'bob',
      'role': null,
      'expectedRevision': 2,
      'operationId': 'revoke'
    });
    await _error(() => api.execute('bob', {'op': 'getApp', 'appId': 'app'}),
        'not_found');
    await _error(
        () => api.execute('bob', {
              'op': 'acceptInvitation',
              'token': _token(9),
              'operationId': 'join-bob-9'
            }),
        'invitation_unavailable');
  });

  await test(
      'receipt hydration cannot bypass a concurrent permission revocation',
      () async {
    final store = _ControlledStore();
    final (_, api) = await _fixture(store: store);
    await _join(api, 'bob', 10);
    final command = _record('receipt-race');
    await api.execute('bob', command);
    store.onReceiptRead = () async {
      await api.execute('alice', {
        'op': 'setGrant',
        'appId': 'app',
        'actorId': 'bob',
        'role': null,
        'expectedRevision': 1,
        'operationId': 'receipt-revoke'
      });
    };
    await _error(() => api.execute('bob', command), 'not_found');
  });

  await test(
      'builder demotion permanently invalidates already issued invitation generation',
      () async {
    final (_, api) = await _fixture();
    await _join(api, 'bob', 11);
    await _invite(api, 12, issuer: 'bob', recipient: 'carol');
    await api.execute('alice', {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'bob',
      'role': 'viewer',
      'expectedRevision': 1,
      'operationId': 'demote-issuer'
    });
    await api.execute('alice', {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'bob',
      'role': 'builder',
      'expectedRevision': 2,
      'operationId': 'restore-issuer'
    });
    await _error(
        () => api.execute('carol', {
              'op': 'acceptInvitation',
              'token': _token(12),
              'operationId': 'old-invite'
            }),
        'invitation_unavailable');
    await _join(api, 'carol', 13, issuer: 'bob');
  });

  await test(
      'expiry and invitation revocation cannot restore existing consumed authority',
      () async {
    var now = DateTime.utc(2026, 10, 28);
    final (_, api) = await _fixture(clock: () => now);
    await _invite(api, 14);
    now = now.add(const Duration(days: 7));
    await _error(
        () => api.execute('bob', {
              'op': 'acceptInvitation',
              'token': _token(14),
              'operationId': 'expired'
            }),
        'invitation_unavailable');
    await _join(api, 'bob', 15);
    await api.execute('alice', {
      'op': 'revokeInvitation',
      'appId': 'app',
      'invitationId': 'invite-15',
      'operationId': 'revoke-invite'
    });
    await _error(
        () => api.execute('bob', {
              'op': 'acceptInvitation',
              'token': _token(15),
              'operationId': 'join-bob-15'
            }),
        'invitation_unavailable');
    _check(
        (await api.execute('bob', {'op': 'getApp', 'appId': 'app'}))['app'] !=
            null,
        'Invite revocation incorrectly removed an accepted grant');
  });

  await test(
      'rolling-day invitation quota counts exact retries once and permits later issuance',
      () async {
    var now = DateTime.utc(2026, 10, 28);
    final (store, api) = await _fixture(clock: () => now);
    for (var i = 30; i < 80; i++) await _invite(api, i);
    await _invite(api, 30);
    await _error(() => _invite(api, 80), 'quota_exceeded');
    _check(store.rows['invitations']!.length == 50,
        'Quota failure wrote invitation');
    _check(store.rows['receipts']!['issue-80'] == null,
        'Quota failure wrote receipt');
    now = now.add(const Duration(days: 1));
    await _invite(api, 80);
    _check(store.rows['invitations']!.length == 51,
        'Rolling quota failed to expire');
  });

  await test(
      'concurrent acceptance has one winner and atomic membership grant receipt',
      () async {
    final store = _ControlledStore();
    final (_, api) = await _fixture(store: store);
    await _invite(api, 90);
    store.barrier(2);
    final results = await Future.wait(['bob', 'carol'].map((actor) async {
      try {
        await api.execute(actor, {
          'op': 'acceptInvitation',
          'token': _token(90),
          'operationId': 'race-$actor'
        });
        return actor;
      } on ServiceException catch (error) {
        _check(
            {'transaction_conflict', 'invitation_unavailable'}
                .contains(error.code),
            'Unexpected race error');
        return null;
      }
    }));
    _check(results.whereType<String>().length == 1,
        'More than one recipient accepted');
    final winner = results.whereType<String>().single;
    _check(
        store.rows['grants']!.length == 1 &&
            store.rows['grants']!.values.single['actorId'] == winner,
        'Grant diverged');
    _check(
        store.rows['memberships']!.values
                .where((row) => row['actorId'] != 'alice')
                .length ==
            1,
        'Failed acceptance left membership');
  });

  await test('grant revocation races share the same guard as record writes',
      () async {
    final store = _ControlledStore();
    final (_, api) = await _fixture(store: store);
    await _join(api, 'bob', 91);
    store.barrier(2);
    final results = await Future.wait([
      () => api.execute('bob', _record('write-race')),
      () => api.execute('alice', {
            'op': 'setGrant',
            'appId': 'app',
            'actorId': 'bob',
            'role': null,
            'expectedRevision': 1,
            'operationId': 'revoke-race'
          }),
    ].map((action) async {
      try {
        await action();
        return true;
      } on ServiceException catch (error) {
        _check({'transaction_conflict', 'not_found'}.contains(error.code),
            'Unexpected revoke/write race');
        return false;
      }
    }));
    _check(results.where((ok) => ok).length == 1,
        'Both conflicting writes committed');
    if (results[0]) {
      await api.execute('alice', {
        'op': 'setGrant',
        'appId': 'app',
        'actorId': 'bob',
        'role': null,
        'expectedRevision': 1,
        'operationId': 'revoke-race'
      });
    }
    await _error(
        () => api.execute(
            'bob',
            _record('after-revoke',
                expected:
                    store.rows['records']?['record']?['revision'] as int? ??
                        0)),
        'not_found');
  });

  await test(
      'failed acceptance rolls back all business rows and lost response uses the receipt',
      () async {
    final (store, api) = await _fixture();
    await _invite(api, 92);
    store.failBeforeCommit = true;
    try {
      await api.execute('bob', {
        'op': 'acceptInvitation',
        'token': _token(92),
        'operationId': 'join-rollback'
      });
      throw StateError('Expected rollback');
    } on RestException {/* deliberate local store failure */}
    store.failBeforeCommit = false;
    _check(
        (store.rows['grants'] ?? {}).isEmpty &&
            store.rows['invitations']!['invite-92']!['acceptedBy'] == null,
        'Failed admission leaked state');
    _check(store.rows['receipts']!['join-rollback'] == null,
        'Failed admission wrote receipt');
    final command = {
      'op': 'acceptInvitation',
      'token': _token(92),
      'operationId': 'join-rollback'
    };
    store.loseCommitResponse = true;
    try {
      await api.execute('bob', command);
      throw StateError('Expected uncertain response');
    } on RestException {/* committed unknown */}
    _check((await api.execute('bob', command))['appId'] == 'app',
        'Receipt did not resolve admission');
    _check(store.rows['grants']!.length == 1, 'Retry duplicated grant');
  });

  await test(
      'only owners archive and archived apps preserve authorized reads while blocking writes',
      () async {
    final (_, api) = await _fixture();
    await _join(api, 'bob', 93);
    await _error(
        () => api.execute('bob', {
              'op': 'archiveApp',
              'appId': 'app',
              'operationId': 'builder-archive'
            }),
        'forbidden');
    await api.execute('alice',
        {'op': 'archiveApp', 'appId': 'app', 'operationId': 'archive'});
    final app = (await api
        .execute('bob', {'op': 'getApp', 'appId': 'app'}))['app'] as Map;
    _check(app['archived'] == true, 'Archived app unreadable');
    await _error(
        () => api.execute('bob', _record('archived-write')), 'app_archived');
    await _error(() => _invite(api, 94), 'app_archived');
    await api.execute('alice',
        {'op': 'archiveApp', 'appId': 'app', 'operationId': 'archive'});
  });

  await test(
      'collaboration listings paginate without exposing token hashes or private drafts',
      () async {
    final (_, api) = await _fixture();
    for (var i = 100; i < 127; i++) await _invite(api, i);
    final first =
        await api.execute('alice', {'op': 'listInvitations', 'appId': 'app'});
    final second = await api.execute('alice', {
      'op': 'listInvitations',
      'appId': 'app',
      'afterId': first['nextCursor']
    });
    _check(
        (first['invitations'] as List).length == 25 &&
            (second['invitations'] as List).length == 2 &&
            second['nextCursor'] == null,
        'Invitation paging lost rows');
    _check(
        !jsonEncode(first).contains('tokenHash') &&
            !jsonEncode(first).contains('definition'),
        'Management listing leaked private data');
    await api.execute('alice', {
      'op': 'createApp',
      'id': 'other',
      'workspaceId': 'ws',
      'name': 'Other'
    });
    await _error(
        () => api.execute('alice', {
              'op': 'listInvitations',
              'appId': 'other',
              'afterId': 'invite-100'
            }),
        'not_found');
  });

  await test(
      'cross-app invitation issuance serializes one remaining rolling quota slot',
      () async {
    final store = _ControlledStore();
    final (_, api) = await _fixture(store: store);
    for (var i = 140; i < 189; i++) await _invite(api, i);
    await api.execute('alice', {
      'op': 'createApp',
      'id': 'other',
      'workspaceId': 'ws',
      'name': 'Other'
    });
    final commands = [
      {
        'op': 'createInvitation',
        'appId': 'app',
        'id': 'quota-race1',
        'operationId': 'quota-race1',
        'role': 'viewer',
        'recipientId': null,
        'token': _token(189)
      },
      {
        'op': 'createInvitation',
        'appId': 'other',
        'id': 'quota-race2',
        'operationId': 'quota-race2',
        'role': 'viewer',
        'recipientId': null,
        'token': _token(190)
      },
    ];
    store.barrier(2);
    final outcomes = await Future.wait(commands.map((command) async {
      try {
        await api.execute('alice', command);
        return true;
      } on ServiceException catch (error) {
        _check(error.code == 'transaction_conflict', 'Wrong quota-race error');
        return false;
      }
    }));
    _check(
        outcomes.where((ok) => ok).length == 1 &&
            store.rows['invitations']!.length == 50,
        'Rolling quota was exceeded');
    final loser = commands[outcomes[0] ? 1 : 0];
    await _error(() => api.execute('alice', loser), 'quota_exceeded');
  });

  await test(
      'invitation revocation and acceptance cannot both use the prior authorization state',
      () async {
    final store = _ControlledStore();
    final (_, api) = await _fixture(store: store);
    await _invite(api, 191);
    final accept = {
      'op': 'acceptInvitation',
      'token': _token(191),
      'operationId': 'accept-revoke-race'
    };
    final revoke = {
      'op': 'revokeInvitation',
      'appId': 'app',
      'invitationId': 'invite-191',
      'operationId': 'revoke-accept-race'
    };
    store.barrier(2);
    final outcomes = await Future.wait([
      () => api.execute('bob', accept),
      () => api.execute('alice', revoke),
    ].map((action) async {
      try {
        await action();
        return true;
      } on ServiceException catch (error) {
        _check(
            {'transaction_conflict', 'invitation_unavailable'}
                .contains(error.code),
            'Wrong invite/revoke race error');
        return false;
      }
    }));
    _check(outcomes.where((ok) => ok).length == 1,
        'Conflicting invitation decisions both committed');
    if (outcomes[0]) {
      await api.execute('alice', revoke);
      _check((store.rows['grants'] ?? {}).length == 1,
          'Committed acceptance lost its grant');
    } else {
      await _error(() => api.execute('bob', accept), 'invitation_unavailable');
      _check((store.rows['grants'] ?? {}).isEmpty,
          'Revoked invitation created a grant');
    }
  });

  await test(
      'concurrent private publications have one winner and a stale candidate cannot retry over it',
      () async {
    final store = _ControlledStore();
    final (_, api) = await _fixture(store: store);
    await _join(api, 'bob', 192);
    await _join(api, 'carol', 193);
    final bob = (await api.execute(
        'bob',
        _save('bob', 0, 1,
            definition: {..._definition, 'title': 'Bob'})))['app'] as Map;
    final carol = (await api.execute(
        'carol',
        _save('carol', 0, 1,
            definition: {..._definition, 'title': 'Carol'})))['app'] as Map;
    final commands = [
      _publish('bob', 1, 1, bob['candidateRevision'] as int),
      _publish('carol', 1, 1, carol['candidateRevision'] as int)
    ];
    store.barrier(2);
    final outcomes = await Future.wait([0, 1].map((index) async {
      try {
        await api.execute(index == 0 ? 'bob' : 'carol', commands[index]);
        return true;
      } on ServiceException catch (error) {
        _check(
            {'transaction_conflict', 'definition_conflict'}
                .contains(error.code),
            'Wrong publication race error');
        return false;
      }
    }));
    _check(outcomes.where((ok) => ok).length == 1,
        'Both incompatible publication bases committed');
    final loser = outcomes[0] ? 1 : 0;
    await _error(
        () => api.execute(loser == 0 ? 'bob' : 'carol', commands[loser]),
        'definition_conflict');
  });

  await test(
      'workspace and app creation limits include legacy and unpublished rows',
      () async {
    final (store, api) = await _fixture();
    for (var i = 0; i < 99; i++) {
      await store.create(
          'workspaces', 'legacy-ws-$i', {'ownerId': 'alice', 'name': 'Legacy'});
      await store.create('apps', 'unpublished-$i',
          {'ownerId': 'alice', 'workspaceId': 'ws', 'name': 'Unpublished'});
    }
    await _error(
        () => api.execute('alice',
            {'op': 'createWorkspace', 'id': 'too-many', 'name': 'Extra'}),
        'quota_exceeded');
    await _error(
        () => api.execute('alice', {
              'op': 'createApp',
              'id': 'too-many-apps',
              'workspaceId': 'ws',
              'name': 'Extra'
            }),
        'quota_exceeded');
    _check(
        store.rows['workspaces']!['too-many'] == null &&
            store.rows['apps']!['too-many-apps'] == null,
        'Quota wrote business rows');
    // Existing identical creation remains a safe retry at the capacity bound.
    await api.execute(
        'alice', {'op': 'createWorkspace', 'id': 'ws', 'name': 'Workspace'});
    await api.execute('alice',
        {'op': 'createApp', 'id': 'app', 'workspaceId': 'ws', 'name': 'Notes'});
  });

  await test(
      'invitation inspection is read-only and reveals only recipient acceptance terms',
      () async {
    final (store, api) = await _fixture();
    await _invite(api, 201, recipient: 'bob', role: 'viewer');
    final before = jsonEncode(store.rows);
    final inspected = (await api.execute('bob', {
      'op': 'inspectInvitation',
      'token': _token(201)
    }))['invitation'] as Map;
    _check(
        inspected.keys.toSet().difference({
              'appId',
              'appName',
              'role',
              'expiresAt',
              'accepted'
            }).isEmpty &&
            inspected.length == 5,
        'Preview exposed extra fields');
    _check(
        inspected['appId'] == 'app' &&
            inspected['appName'] == 'Notes' &&
            inspected['role'] == 'viewer' &&
            inspected['accepted'] == false,
        'Wrong invitation terms');
    _check(jsonEncode(store.rows) == before && store.transactions.isEmpty,
        'Inspection wrote state');
    await _error(
        () => api.execute(
            'mallory', {'op': 'inspectInvitation', 'token': _token(201)}),
        'invitation_unavailable');
    await _error(
        () =>
            api.execute('bob', {'op': 'inspectInvitation', 'token': 'invalid'}),
        'invitation_unavailable');
    await _error(
        () =>
            api.execute('', {'op': 'inspectInvitation', 'token': _token(201)}),
        'unauthenticated');
    await api.execute('bob', {
      'op': 'acceptInvitation',
      'token': _token(201),
      'operationId': 'inspected-accept'
    });
    final accepted = (await api.execute('bob', {
      'op': 'inspectInvitation',
      'token': _token(201)
    }))['invitation'] as Map;
    _check(accepted['accepted'] == true,
        'Accepted recipient cannot open current app');
    await _error(
        () => api.execute(
            'carol', {'op': 'inspectInvitation', 'token': _token(201)}),
        'invitation_unavailable');
    await api.execute('alice', {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'bob',
      'role': null,
      'expectedRevision': 1,
      'operationId': 'preview-revoke'
    });
    await _error(
        () => api
            .execute('bob', {'op': 'inspectInvitation', 'token': _token(201)}),
        'invitation_unavailable');
  });

  await test(
      'invitation previews reject expired revoked or stale-issuer tokens without metadata',
      () async {
    var now = DateTime.utc(2026, 10, 28);
    final (_, api) = await _fixture(clock: () => now);
    await _join(api, 'bob', 202);
    await _invite(api, 203, issuer: 'bob', recipient: 'carol');
    await api.execute('alice', {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'bob',
      'role': 'viewer',
      'expectedRevision': 1,
      'operationId': 'preview-demote'
    });
    await _error(
        () => api.execute(
            'carol', {'op': 'inspectInvitation', 'token': _token(203)}),
        'invitation_unavailable');
    await _invite(api, 204, recipient: 'carol');
    await api.execute('alice', {
      'op': 'revokeInvitation',
      'appId': 'app',
      'invitationId': 'invite-204',
      'operationId': 'preview-invite-revoke'
    });
    await _error(
        () => api.execute(
            'carol', {'op': 'inspectInvitation', 'token': _token(204)}),
        'invitation_unavailable');
    await _invite(api, 205, recipient: 'carol');
    now = now.add(const Duration(days: 7));
    await _error(
        () => api.execute(
            'carol', {'op': 'inspectInvitation', 'token': _token(205)}),
        'invitation_unavailable');
  });

  await test(
      'archived apps retain revocation capability while blocking grant creation promotion and invites',
      () async {
    final (_, api) = await _fixture();
    await _join(api, 'bob', 206);
    await _join(api, 'carol', 207, role: 'viewer');
    await _invite(api, 208, recipient: 'dave');
    await api.execute('alice', {
      'op': 'archiveApp',
      'appId': 'app',
      'operationId': 'archive-for-revocation'
    });
    for (final actor in ['alice', 'bob', 'carol']) {
      final app = (await api
          .execute(actor, {'op': 'getApp', 'appId': 'app'}))['app'] as Map;
      final caps = app['capabilities'] as Map;
      _check(caps['revokeAccess'] == (actor != 'carol'),
          'Wrong archived revocation capability');
      _check(
          ['share', 'editDefinition', 'writeRecords', 'archive']
              .every((key) => caps[key] == false),
          'Archived write capability remained enabled');
    }
    await _error(
        () => api.execute('bob', {
              'op': 'setGrant',
              'appId': 'app',
              'actorId': 'carol',
              'role': 'builder',
              'expectedRevision': 1,
              'operationId': 'archived-promote'
            }),
        'app_archived');
    await _error(() => _invite(api, 209, issuer: 'bob'), 'app_archived');
    await api.execute('bob', {
      'op': 'revokeInvitation',
      'appId': 'app',
      'invitationId': 'invite-208',
      'operationId': 'archived-invite-revoke'
    });
    final listed =
        await api.execute('bob', {'op': 'listInvitations', 'appId': 'app'});
    _check((listed['invitations'] as List).isNotEmpty,
        'Archived management metadata unavailable');
    await api.execute('bob', {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'carol',
      'role': null,
      'expectedRevision': 1,
      'operationId': 'archived-reader-revoke'
    });
    await _error(() => api.execute('carol', {'op': 'getApp', 'appId': 'app'}),
        'not_found');
    await api.execute('alice', {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'bob',
      'role': null,
      'expectedRevision': 1,
      'operationId': 'archived-builder-revoke'
    });
    await _error(() => api.execute('bob', {'op': 'getApp', 'appId': 'app'}),
        'not_found');
  });

  await test(
      'committed draft publication and record receipts remain exact after archival',
      () async {
    final (_, api) = await _fixture(publish: false);
    final save = _save('alice', 0, 0);
    final saved = await api.execute('alice', save);
    final publish = _publish('alice', 1, 0, 1);
    final published = await api.execute('alice', publish);
    final record = _record('archived-exact-record');
    final written = await api.execute('alice', record);
    final archive = {
      'op': 'archiveApp',
      'appId': 'app',
      'operationId': 'archived-exact'
    };
    final archived = await api.execute('alice', archive);
    for (final pair in [
      (save, saved),
      (publish, published),
      (record, written),
      (archive, archived)
    ]) {
      _check(
          jsonEncode(await api.execute('alice', pair.$1)) ==
              jsonEncode(pair.$2),
          'Archive changed a committed receipt');
    }
    await _error(
        () => api.execute('alice', {
              ...record,
              'operationId': 'new-after-archive',
              'expectedRevision': 1
            }),
        'app_archived');
  });

  await test(
      'unknown record commits recover after archive but current revoked actors remain denied',
      () async {
    final store = _ControlledStore();
    final (_, api) = await _fixture(store: store);
    await _join(api, 'bob', 210);
    final command = _record('unknown-then-archive');
    store.loseCommitResponse = true;
    try {
      await api.execute('bob', command);
      throw StateError('Expected unknown commit');
    } on RestException {/* committed response intentionally lost */}
    store.onReceiptRead = () async {
      await api.execute('alice', {
        'op': 'archiveApp',
        'appId': 'app',
        'operationId': 'archive-during-recovery'
      });
    };
    final resolved = await api.execute('bob', command);
    _check((resolved['record'] as Map)['revision'] == 1,
        'Unknown commit did not resolve');
    await api.execute('alice', {
      'op': 'setGrant',
      'appId': 'app',
      'actorId': 'bob',
      'role': null,
      'expectedRevision': 1,
      'operationId': 'revoke-after-recovery'
    });
    await _error(() => api.execute('bob', command), 'not_found');
  });

  await test(
      'invitation admission enforces workspace quota atomically without double counting current membership',
      () async {
    final (store, api) = await _fixture();
    for (var i = 0; i < 100; i++) {
      await store.create('workspaces', 'bobs-existing-$i',
          {'ownerId': 'bob', 'name': 'Existing'});
    }
    await _invite(api, 211, recipient: 'bob');
    final command = {
      'op': 'acceptInvitation',
      'token': _token(211),
      'operationId': 'join-over-quota'
    };
    final oldInvitation = jsonEncode(store.rows['invitations']!['invite-211']);
    await _error(() => api.execute('bob', command), 'quota_exceeded');
    _check(
        (store.rows['grants'] ?? {}).isEmpty &&
            store.rows['receipts']!['join-over-quota'] == null,
        'Quota failure committed admission');
    _check(
        jsonEncode(store.rows['invitations']!['invite-211']) == oldInvitation,
        'Quota failure consumed token');
    _check(
        store.rows['memberships']!.values
            .every((row) => row['actorId'] != 'bob'),
        'Quota failure created membership');
    _check(
        ((await api.execute('bob', {'op': 'listWorkspaces'}))['workspaces']
                    as List)
                .length ==
            100,
        'Quota rejection broke workspace listing');

    final (memberStore, memberApi) = await _fixture();
    await _join(memberApi, 'bob', 212, role: 'viewer');
    for (var i = 0; i < 99; i++) {
      await memberStore.create('workspaces', 'already-member-$i',
          {'ownerId': 'bob', 'name': 'Existing'});
    }
    await _invite(memberApi, 213, recipient: 'bob', role: 'builder');
    await memberApi.execute('bob', {
      'op': 'acceptInvitation',
      'token': _token(213),
      'operationId': 'same-workspace-at-quota'
    });
    _check(
        ((await memberApi.execute(
                    'bob', {'op': 'listWorkspaces'}))['workspaces'] as List)
                .length ==
            100,
        'Existing membership counted twice');
  });

  await test(
      'concurrent invitation admissions across workspaces serialize the actors last slot',
      () async {
    final store = _ControlledStore();
    final (_, api) = await _fixture(store: store);
    await api.execute('alice',
        {'op': 'createWorkspace', 'id': 'second-ws', 'name': 'Second'});
    await api.execute('alice', {
      'op': 'createApp',
      'id': 'second-app',
      'workspaceId': 'second-ws',
      'name': 'Second'
    });
    for (var i = 0; i < 99; i++) {
      await store.create(
          'workspaces', 'last-slot-$i', {'ownerId': 'bob', 'name': 'Existing'});
    }
    await _invite(api, 214, recipient: 'bob', role: 'viewer');
    await api.execute('alice', {
      'op': 'createInvitation',
      'appId': 'second-app',
      'id': 'second-invite',
      'operationId': 'second-invite',
      'role': 'viewer',
      'recipientId': 'bob',
      'token': _token(215)
    });
    final commands = [
      {
        'op': 'acceptInvitation',
        'token': _token(214),
        'operationId': 'first-last-slot'
      },
      {
        'op': 'acceptInvitation',
        'token': _token(215),
        'operationId': 'second-last-slot'
      },
    ];
    store.barrier(2);
    final outcomes = await Future.wait(commands.map((command) async {
      try {
        await api.execute('bob', command);
        return true;
      } on ServiceException catch (error) {
        _check(error.code == 'transaction_conflict',
            'Wrong last-slot race result');
        return false;
      }
    }));
    _check(outcomes.where((ok) => ok).length == 1,
        'Two workspace admissions used the same final slot');
    await _error(() => api.execute('bob', commands[outcomes[0] ? 1 : 0]),
        'quota_exceeded');
    _check(
        ((await api.execute('bob', {'op': 'listWorkspaces'}))['workspaces']
                    as List)
                .length ==
            100,
        'Concurrent admission exceeded workspace bound');
    _check(
        store.rows['grants']!.values
                .where((row) => row['actorId'] == 'bob')
                .length ==
            1,
        'Failed admission left extra grant');
  });

  await test(
      'grant and record increments cannot escape the client revision bound',
      () async {
    final (store, api) = await _fixture();
    await _join(api, 'bob', 216, role: 'viewer');
    final grant = store.rows['grants']!.values.single;
    await store
        .update('grants', grant[r'$id'] as String, {'revision': 2147483646});
    await _error(
        () => api.execute('alice', {
              'op': 'setGrant',
              'appId': 'app',
              'actorId': 'bob',
              'role': 'builder',
              'expectedRevision': 2147483646,
              'operationId': 'grant-overflow'
            }),
        'revision_conflict');
    await api.execute('alice', _record('overflow-record-base'));
    await store.update('records', 'record', {'revision': 2147483646});
    await _error(
        () => api.execute(
            'alice', _record('record-overflow', expected: 2147483646)),
        'revision_conflict');
    _check(
        store.rows['records']!['record']!['revision'] == 2147483646 &&
            store.rows['grants']![grant[r'$id']]!['revision'] == 2147483646,
        'Bounded revision overflowed');
    _check(
        store.rows['receipts']!['grant-overflow'] == null &&
            store.rows['receipts']!['record-overflow'] == null,
        'Rejected overflow wrote receipt');
  });

  return passed;
}

Future<void> main() async {
  final passed = await runCollaborationChecks();
  print(
      '$passed collaboration checks passed (simulated transaction store; live proof is separate).');
}
