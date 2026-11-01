import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../lib/service.dart';
import 'confirmed_abort_test.dart' as fixture;

class _Files implements PrivateFileStore {
  int calls = 0;
  Uint8List? bytes;
  Future<void> Function()? beforeRead;

  @override
  Future<void> put(String id, Uint8List bytes, String contentType) async {
    calls++;
    throw StateError('Unexpected Storage put');
  }

  @override
  Future<Uint8List> read(String id, {required int maximumBytes}) async {
    calls++;
    if (beforeRead != null) await beforeRead!();
    final result = bytes;
    if (result == null) throw StateError('Unexpected Storage read');
    return result;
  }

  @override
  Future<void> remove(String id) async {
    calls++;
    throw StateError('Unexpected Storage remove');
  }
}

class _Wakeups implements WorkerWakeups {
  int calls = 0;

  @override
  Future<String> schedule({
    required String dispatchId,
    required String proof,
    required DateTime at,
  }) async {
    calls++;
    throw StateError('Unexpected wakeup');
  }
}

void main() {
  test(
    'overlapping workspace reads recover only the confirmed abort',
    () async {
      final f = await fixture.LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      final beforeCommits = f.commits.length;
      final beforeLookups = f.getStates.length;
      f.memory.arm();
      final first = f.service.execute('alice', {
        'op': 'spec.getApp',
        'appId': 'app-one',
      });
      await f.memory.paused!.future;
      try {
        await f.service.execute('alice', {
          'op': 'spec.getApp',
          'appId': 'app-two',
        });
      } finally {
        f.memory.resume!.complete();
      }
      final result = await first;
      expect((result['app'] as Row)['id'], 'app-one');
      expect(f.commits.length - beforeCommits, 3);
      expect(f.getStates.length - beforeLookups, 1);
    },
  );

  test('confirmed aborts are bounded at three total attempts', () async {
    final f = await fixture.LocalDatabase.create();
    addTearDown(f.close);
    await f.setup();
    final before = f.commits.length;
    f.forcedAborts = 4;
    await expectLater(
      f.service.execute('alice', {'op': 'spec.getApp', 'appId': 'app-one'}),
      throwsA(
        isA<ServiceException>().having(
          (e) => e.code,
          'code',
          'transaction_conflict',
        ),
      ),
    );
    expect(f.commits.length - before, 3);
    expect(f.getStates, hasLength(3));
  });

  for (final failure in ['staging', 'unconfirmed', 'lostReply']) {
    test('$failure conflict or lost result never repeats a read', () async {
      final f = await fixture.LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      final before = f.commits.length;
      if (failure == 'staging') f.failStagedWorkspaceUpdate = true;
      if (failure == 'unconfirmed') {
        f.forcedAborts = 1;
        f.terminalStatusOverride = 'pending';
      }
      if (failure == 'lostReply') f.loseCommitReply = true;
      await expectLater(
        f.service.execute('alice', {'op': 'spec.getApp', 'appId': 'app-one'}),
        throwsA(anything),
      );
      expect(f.commits.length - before, failure == 'staging' ? 0 : 1);
      expect(f.getStates.length, failure == 'unconfirmed' ? 1 : 0);
    });
  }

  test('fresh snapshot rechecks workspace authority after abort', () async {
    final f = await fixture.LocalDatabase.create();
    addTearDown(f.close);
    await f.setup();
    final before = f.commits.length;
    f.forcedAborts = 1;
    f.afterAbort = () async {
      await f.memory.update('workspaces', 'ws', {'ownerId': 'outsider'});
      for (final row in f.memory.rows['memberships']!.values.toList()) {
        if (row['actorId'] == 'alice') {
          await f.memory.update('memberships', row[r'$id'] as String, {
            'active': false,
          });
        }
      }
    };
    await expectLater(
      f.service.execute('alice', {'op': 'spec.getApp', 'appId': 'app-one'}),
      throwsA(
        isA<ServiceException>().having((e) => e.code, 'code', 'not_found'),
      ),
    );
    expect(f.commits.length - before, 1);
  });

  test('retried media status uses no Storage or wakeup calls', () async {
    final f = await fixture.LocalDatabase.create();
    addTearDown(f.close);
    await f.setup();
    final files = _Files();
    final wakeups = _Wakeups();
    final service = PlatformService(f.rest, media: files, wakeups: wakeups);
    final before = f.commits.length;
    f.forcedAborts = 1;
    final result = await service.execute('alice', {
      'op': 'spec.media.usage',
      'appId': 'app-one',
    });
    expect(result['assetCount'], 0);
    expect(f.commits.length - before, 2);
    expect(files.calls, 0);
    expect(wakeups.calls, 0);
  });

  test(
    'media bytes are fetched once across retried authorization checks',
    () async {
      final f = await fixture.LocalDatabase.create();
      addTearDown(f.close);
      await f.setup();
      final content = Uint8List.fromList([1, 2, 3, 4]);
      final hash = sha256.convert(content).toString();
      await f.memory.create('media_assets', 'test-asset', {
        'appId': 'app-one',
        'workspaceId': 'ws',
        'status': 'ready',
        'displayBytes': content.length,
        'displayHash': hash,
        'contentType': 'image/png',
        'width': 1,
        'height': 1,
      });
      final files = _Files()..bytes = content;
      files.beforeRead = () async {
        f.forcedAborts = 1;
      };
      final service = PlatformService(f.rest, media: files);
      final before = f.commits.length;
      f.forcedAborts = 1;
      final result = await service.execute('alice', {
        'op': 'spec.media.read',
        'appId': 'app-one',
        'assetId': 'test-asset',
        'variant': 'display',
        'offset': 0,
      });
      expect(result['sha256'], hash);
      expect(f.commits.length - before, 4);
      expect(files.calls, 1);
    },
  );
}
