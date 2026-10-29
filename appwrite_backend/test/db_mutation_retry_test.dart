import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import '../lib/service.dart';
import 'confirmed_abort_test.dart' as fixtures;
import 'workers_test.dart' as workers;
import 'media_check.dart' as media;

String identity(String kind, List<String> parts) =>
    '$kind${sha256.convert(utf8.encode(jsonEncode(parts))).toString().substring(0, 32)}';
Future<void> join(
  fixtures.LocalDatabase f,
  String actor,
  String appId, {
  String role = 'member',
}) async {
  final seed = actor.length + appId.length;
  final token = base64Url
      .encode(List.generate(32, (n) => n + seed))
      .replaceAll('=', '');
  final id = 'invite-$actor-$appId';
  await f.service.execute('alice', {
    'op': 'createInvitation',
    'appId': appId,
    'id': id,
    'operationId': id,
    'role': role,
    'recipientId': actor,
    'token': token,
  });
  await f.service.execute(actor, {
    'op': 'acceptInvitation',
    'token': token,
    'operationId': 'accept-$actor-$appId',
  });
}

String version(fixtures.LocalDatabase f, String appId) =>
    f.memory.rows['apps']![appId]!['specVersionId'] as String;
Row privateDraft(fixtures.LocalDatabase f) {
  final row = f.memory.rows['spec_versions']!.values.firstWhere(
    (row) => row['appId'] == 'app-one',
  );
  return {
    'op': 'spec.saveDraft',
    'appId': 'app-one',
    'operationId': 'prepare-draft',
    'expectedRevision': 0,
    'expectedVersionId': row[r'$id'],
    'spec': jsonDecode(row['specJson'] as String),
  };
}

Row command(
  fixtures.LocalDatabase f,
  String appId,
  String action,
  Row data, {
  String? record,
  int? revision,
  String op = 'tested-command',
}) => {
  'op': 'spec.execute',
  'appId': appId,
  'versionId': version(f, appId),
  'operationId': op,
  'actionId': action,
  'input': data,
  if (record != null) 'targetRecordId': record,
  if (revision != null) 'expectedRecordRevision': revision,
};
Future<Row> record(fixtures.LocalDatabase f, String actor, Row input) async =>
    (await f.service.execute(actor, input))['outcome'] as Row;

Future<(String, Row)> scenario(fixtures.LocalDatabase f, String kind) async {
  if (kind.startsWith('capacity.')) {
    await f.service.execute('alice', {
      'op': 'spec.instantiate',
      'id': 'capacity-app',
      'workspaceId': 'ws',
      'templateKey': 'volunteer',
      'operationId': 'capacity-app',
    });
    await join(f, 'bob', 'capacity-app');
    final made = await record(
      f,
      'alice',
      command(f, 'capacity-app', 'addShift', {
        'data': {
          'title': 'Synthetic shift',
          'startsAt': '2031-01-01T00:00:00.000Z',
        },
        'capacity': 1,
      }, op: 'prepare-shift'),
    );
    final id = made['recordId'] as String;
    if (kind == 'capacity.release.v1')
      await record(
        f,
        'bob',
        command(f, 'capacity-app', 'join', {}, record: id, op: 'prepare-claim'),
      );
    return (
      kind == 'capacity.configure.v1' ? 'alice' : 'bob',
      command(
        f,
        'capacity-app',
        switch (kind) {
          'capacity.configure.v1' => 'configure',
          'capacity.claim.v1' => 'join',
          _ => 'leave',
        },
        kind == 'capacity.configure.v1' ? {'capacity': 2} : {},
        record: id,
      ),
    );
  }
  if ({
    'records.create.v1',
    'records.patch.v1',
    'assignment.assign.v1',
    'workflow.transition.v1',
  }.contains(kind)) {
    await join(f, 'bob', 'app-one');
    if (kind == 'records.create.v1')
      return (
        'bob',
        command(f, 'app-one', 'addChore', {
          'data': {'title': 'Synthetic chore', 'status': 'Open'},
        }),
      );
    final made = await record(
      f,
      'bob',
      command(f, 'app-one', 'addChore', {
        'data': {'title': 'Synthetic chore', 'status': 'Open'},
      }, op: 'prepare-record'),
    );
    return (
      'bob',
      command(
        f,
        'app-one',
        switch (kind) {
          'records.patch.v1' => 'editChore',
          'assignment.assign.v1' => 'assignChore',
          _ => 'moveChore',
        },
        switch (kind) {
          'records.patch.v1' => {
            'data': {'notes': 'Synthetic edit'},
          },
          'assignment.assign.v1' => {'value': 'bob'},
          _ => {'value': 'Doing'},
        },
        record: made['recordId'] as String,
        revision: 1,
      ),
    );
  }
  if (kind == 'setGrant') {
    await join(f, 'bob', 'app-one');
    return (
      'alice',
      {
        'op': kind,
        'appId': 'app-one',
        'actorId': 'bob',
        'role': 'viewer',
        'expectedRevision': 1,
        'operationId': 'tested-command',
      },
    );
  }
  if (kind == 'revokeInvitation') {
    final token = base64Url
        .encode(List.generate(32, (n) => n + 41))
        .replaceAll('=', '');
    await f.service.execute('alice', {
      'op': 'createInvitation',
      'appId': 'app-one',
      'id': 'pending',
      'operationId': 'prepare-invitation',
      'role': 'member',
      'recipientId': 'bob',
      'token': token,
    });
    return (
      'alice',
      {
        'op': kind,
        'appId': 'app-one',
        'invitationId': 'pending',
        'operationId': 'tested-command',
      },
    );
  }
  if (kind == 'archiveApp')
    return (
      'alice',
      {'op': kind, 'appId': 'app-one', 'operationId': 'tested-command'},
    );
  if (kind == 'spec.setPinned') {
    await join(f, 'bob', 'app-one');
    return (
      'bob',
      {
        'op': kind,
        'appId': 'app-one',
        'operationId': 'tested-command',
        'expectedRevision': 0,
        'pinned': true,
      },
    );
  }
  // Generate a real local in-app reminder through the trusted worker. No provider.
  final app =
      (await f.service.execute('alice', {
            'op': 'spec.instantiate',
            'id': 'notification-app',
            'workspaceId': 'ws',
            'templateKey': 'reminders',
            'operationId': 'notification-app',
          }))['app']
          as Row;
  await f.service.execute('alice', {
    'op': 'spec.saveDraft',
    'appId': app['id'],
    'operationId': 'notification-draft',
    'expectedRevision': 0,
    'expectedVersionId': (app['version'] as Row)['id'],
    'spec': (app['version'] as Row)['spec'],
  });
  final review =
      (await f.service.execute('alice', {
            'op': 'spec.review',
            'appId': app['id'],
            'expectedRevision': 1,
            'enabledRuleIds': ['taskReminder'],
            'activateExistingRecordIds': [],
          }))['review']
          as Row;
  await f.service.execute('alice', {
    'op': 'spec.publish',
    'appId': app['id'],
    'operationId': 'notification-publish',
    'expectedRevision': 1,
    'expectedVersionId': (app['version'] as Row)['id'],
    'candidateHash': review['candidateHash'],
    'reviewHash': review['reviewHash'],
    'enabledRuleIds': ['taskReminder'],
    'activateExistingRecordIds': [],
  });
  await record(
    f,
    'alice',
    command(f, app['id'] as String, 'addTask', {
      'data': {
        'title': 'Synthetic reminder',
        'status': 'Open',
        'reminderAt': '2029-12-31T00:00:00.000Z',
      },
    }, op: 'notification-record'),
  );
  await WorkerEngine(f.service).reminders();
  final notice =
      ((await f.service.execute('alice', {'op': 'spec.inbox'}))['items']
                  as List)
              .single
          as Row;
  return (
    'alice',
    {
      'op': 'spec.readNotification',
      'appId': notice['appId'],
      'runId': notice['runId'],
      'notificationId': notice['id'],
      'operationId': 'tested-command',
    },
  );
}

const kinds = [
  'records.create.v1',
  'records.patch.v1',
  'assignment.assign.v1',
  'workflow.transition.v1',
  'capacity.configure.v1',
  'capacity.claim.v1',
  'capacity.release.v1',
  'setGrant',
  'revokeInvitation',
  'archiveApp',
  'spec.setPinned',
  'spec.readNotification',
];
void main() {
  test(
    'generation remains opted out and an aborted enqueue never repeats or invokes its provider',
    () async {
      final f = await fixtures.LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      final provider = workers.ScriptProvider();
      final api = PlatformService(
        f.rest,
        aiProvider: provider,
        clock: () => DateTime.utc(2030, 1, 2),
        remindersEnabled: true,
      );
      final before = f.commits.length;
      f.forcedAborts = 1;
      await expectLater(
        api.execute('alice', {
          'op': 'spec.generate',
          'appId': 'app-one',
          'operationId': 'excluded-generation',
          'expectedRevision': 0,
          'expectedVersionId': version(f, 'app-one'),
          'request': 'Synthetic edit',
          'startFromScratch': false,
        }),
        throwsA(
          isA<ServiceException>().having(
            (e) => e.code,
            'code',
            'transaction_conflict',
          ),
        ),
      );
      expect(f.commits.length - before, 1);
      expect(provider.calls, isEmpty);
      expect(f.memory.rows['generation_jobs'] ?? {}, isEmpty);
    },
  );
  test(
    'media reservation and chunk lease remain opted out without repeating Storage IO',
    () async {
      final f = await fixtures.LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      await f.service.execute('alice', privateDraft(f));
      final files = media.Files();
      final api = PlatformService(
        f.rest,
        media: files,
        clock: () => DateTime.utc(2030, 1, 2),
      );
      final bytes = [1], hash = sha256.convert([1]).toString();
      final begin = {
        'op': 'spec.media.begin',
        'appId': 'app-one',
        'operationId': 'excluded-media',
        'draftRevision': 1,
        'byteLength': 1,
        'contentType': 'image/png',
        'sha256': hash,
      };
      final before = f.commits.length;
      f.forcedAborts = 1;
      await expectLater(
        api.execute('alice', begin),
        throwsA(
          isA<ServiceException>().having(
            (e) => e.code,
            'code',
            'transaction_conflict',
          ),
        ),
      );
      expect(f.commits.length - before, 1);
      expect(files.puts, 0);
      expect(f.memory.rows['media_assets'] ?? {}, isEmpty);
      final asset =
          ((await api.execute('alice', {
                ...begin,
                'operationId': 'prepare-media',
              }))['asset']
              as Row)['assetId'];
      final chunkBefore = f.commits.length;
      f.forcedAborts = 1;
      await expectLater(
        api.execute('alice', {
          'op': 'spec.media.chunk',
          'appId': 'app-one',
          'assetId': asset,
          'offset': 0,
          'dataBase64': base64Encode(bytes),
          'sha256': hash,
        }),
        throwsA(
          isA<ServiceException>().having(
            (e) => e.code,
            'code',
            'transaction_conflict',
          ),
        ),
      );
      expect(f.commits.length - chunkBefore, 1);
      expect(files.puts, 0);
      expect(f.memory.rows['media_assets']![asset]!['uploadedBytes'], 0);
    },
  );
  for (final kind in kinds) {
    test(
      'worker race: $kind commits once with exact authorized receipt',
      () async {
        final f = await fixtures.LocalDatabase.create();
        addTearDown(f.close);
        await f.setup();
        final (actor, input) = await scenario(f, kind);
        // Guarantees pending genuine worker work even after inbox setup drained it.
        await f.instantiate('noise');
        final audits = f.memory.rows['audit']!.length,
            outbox = f.memory.rows['outbox']!.length;
        f.memory.arm();
        final pending = f.service.execute(actor, input);
        await f.memory.paused!.future;
        try {
          await WorkerEngine(f.service).reminders();
        } finally {
          f.memory.resume!.complete();
        }
        final result = await pending;
        expect(f.getStates, hasLength(1));
        expect(f.memory.rows['receipts']!['tested-command'], isNotNull);
        expect(
          jsonEncode(await f.service.execute(actor, input)),
          jsonEncode(result),
        );
        expect(
          f.memory.rows['audit']!.length - audits,
          kind == 'spec.setPinned' ? 0 : 1,
        );
        expect(
          f.memory.rows['outbox']!.length - outbox,
          kind == 'spec.setPinned' ? 0 : 1,
        );
        if (kind.startsWith('capacity.')) {
          final pool = f.memory.rows['spec_pools']!.values.single;
          expect(pool['allocated'], kind == 'capacity.claim.v1' ? 1 : 0);
          expect(
            f.memory.rows['spec_records']!.values.singleWhere(
              (row) => row['appId'] == 'capacity-app',
            )['revision'],
            1,
          );
        } else if (kind == 'records.create.v1') {
          expect(
            f.memory.rows['spec_records']!.values.where(
              (row) => row['appId'] == 'app-one',
            ),
            hasLength(1),
          );
        } else if ({
          'records.patch.v1',
          'assignment.assign.v1',
          'workflow.transition.v1',
        }.contains(kind)) {
          expect(
            f
                .memory
                .rows['spec_records']![input['targetRecordId']]!['revision'],
            2,
          );
        } else if (kind == 'spec.readNotification') {
          expect(f.memory.rows['notification_reads'], hasLength(1));
        }
      },
    );
  }
  test(
    'record CAS and current publication are rechecked after confirmed abort',
    () async {
      for (final change in ['revision', 'version']) {
        final f = await fixtures.LocalDatabase.create();
        addTearDown(f.close);
        await f.setup();
        final (actor, input) = await scenario(f, 'records.patch.v1');
        f.forcedAborts = 1;
        f.afterAbort = () async {
          if (change == 'revision') {
            await f.memory.update(
              'spec_records',
              input['targetRecordId'] as String,
              {'revision': 2},
            );
          } else {
            await f.memory.update('apps', 'app-one', {
              'specVersionId': 'newer-version',
              'specVersionNumber': 2,
            });
          }
        };
        await expectLater(
          f.service.execute(actor, input),
          throwsA(
            isA<ServiceException>().having(
              (e) => e.code,
              'code',
              change == 'revision'
                  ? 'revision_conflict'
                  : 'definition_conflict',
            ),
          ),
        );
        expect(f.memory.rows['receipts']?['tested-command'], isNull);
      }
    },
  );
  test('assignment rechecks target app authority before retry', () async {
    final f = await fixtures.LocalDatabase.create();
    addTearDown(f.close);
    await f.setup();
    final (_, input) = await scenario(f, 'assignment.assign.v1');
    f.forcedAborts = 1;
    f.afterAbort = () async {
      final grant = f.memory.rows['grants']!.values.singleWhere(
        (row) => row['actorId'] == 'bob',
      );
      await f.memory.update('grants', grant[r'$id'] as String, {
        'revoked': true,
        'revision': 2,
      });
    };
    await expectLater(
      f.service.execute('alice', input),
      throwsA(
        isA<ServiceException>().having((e) => e.code, 'code', 'invalid_values'),
      ),
    );
    expect(
      f.memory.rows['spec_records']![input['targetRecordId']]!['revision'],
      1,
    );
  });
  test(
    'capacity retry uses current allocation and never overbooks or underflows',
    () async {
      for (final action in [
        'capacity.claim.v1',
        'capacity.configure.v1',
        'capacity.release.v1',
      ]) {
        final f = await fixtures.LocalDatabase.create();
        addTearDown(f.close);
        await f.setup();
        final (actor, input) = await scenario(f, action);
        f.forcedAborts = 1;
        if (action == 'capacity.configure.v1') input['input'] = {'capacity': 0};
        f.afterAbort = () async {
          final pool = f.memory.rows['spec_pools']!.values.single;
          if (action == 'capacity.release.v1') {
            final claim = f.memory.rows['spec_claims']!.values.single;
            await f.memory.update('spec_claims', claim[r'$id'] as String, {
              'active': false,
            });
            await f.memory.update('spec_pools', pool[r'$id'] as String, {
              'allocated': 0,
            });
          } else {
            await f.memory.update('spec_pools', pool[r'$id'] as String, {
              'allocated': 1,
            });
          }
        };
        if (action == 'capacity.release.v1') {
          await f.service.execute(actor, input);
          expect(f.memory.rows['spec_pools']!.values.single['allocated'], 0);
        } else {
          await expectLater(
            f.service.execute(actor, input),
            throwsA(
              isA<ServiceException>().having(
                (e) => e.code,
                'code',
                action == 'capacity.claim.v1'
                    ? 'exhausted_capacity'
                    : 'invalid_values',
              ),
            ),
          );
          expect(f.memory.rows['receipts']?['tested-command'], isNull);
        }
      }
    },
  );
  test('grant and shortcut revisions remain exact across retries', () async {
    for (final kind in ['setGrant', 'spec.setPinned']) {
      final f = await fixtures.LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      final (actor, input) = await scenario(f, kind);
      if (kind == 'spec.setPinned') {
        await f.service.execute(actor, {
          ...input,
          'operationId': 'prepare-pin',
        });
        input['expectedRevision'] = 1;
        input['pinned'] = false;
      }
      f.forcedAborts = 1;
      f.afterAbort = () async {
        if (kind == 'setGrant') {
          final grant = f.memory.rows['grants']!.values.single;
          await f.memory.update('grants', grant[r'$id'] as String, {
            'revision': 2,
          });
        } else {
          await f.memory.update(
            'shortcuts',
            identity('k', ['app-one', 'bob']),
            {'revision': 2},
          );
        }
      };
      await expectLater(
        f.service.execute(actor, input),
        throwsA(
          isA<ServiceException>().having(
            (e) => e.code,
            'code',
            'revision_conflict',
          ),
        ),
      );
      expect(f.memory.rows['receipts']?['tested-command'], isNull);
    }
  });
  test(
    'current grant loss rejects new commands and committed record receipts',
    () async {
      final f = await fixtures.LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      final (actor, input) = await scenario(f, 'records.create.v1');
      await f.service.execute(actor, input);
      final grant = f.memory.rows['grants']!.values.single;
      await f.memory.update('grants', grant[r'$id'] as String, {
        'revoked': true,
        'revision': 2,
      });
      await expectLater(
        f.service.execute(actor, input),
        throwsA(
          isA<ServiceException>().having((e) => e.code, 'code', 'not_found'),
        ),
      );
      expect(f.memory.rows['spec_records'], hasLength(1));
    },
  );
  test('notification retry rechecks batch recipient authority', () async {
    final f = await fixtures.LocalDatabase.create();
    addTearDown(f.close);
    await f.setup();
    final (actor, input) = await scenario(f, 'spec.readNotification');
    f.forcedAborts = 1;
    f.afterAbort = () async {
      final batch = f.memory.rows['notification_batches']!.values.single;
      await f.memory.update('notification_batches', batch[r'$id'] as String, {
        'recipientIdsJson': '[]',
      });
    };
    await expectLater(
      f.service.execute(actor, input),
      throwsA(
        isA<ServiceException>().having((e) => e.code, 'code', 'not_found'),
      ),
    );
    expect(f.memory.rows['notification_reads'] ?? {}, isEmpty);
    expect(f.memory.rows['receipts']?['tested-command'], isNull);
  });
}
