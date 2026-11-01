import 'dart:async';
import 'dart:convert';

import '../lib/providers/runtime_limits.dart' as limits;
import 'dart:io';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:test/test.dart';
import '../lib/service.dart';
import '../lib/providers/provider.dart' as ai;
import 'media_check.dart' as media;
import 'memory_store.dart';
import 'spec_engine_check.dart' as base;

class Wakeups implements WorkerWakeups {
  final calls = <Row>[];
  @override
  Future<String> schedule({
    required String dispatchId,
    required String proof,
    required DateTime at,
  }) async {
    calls.add({
      'id': dispatchId,
      'proof': proof,
      'at': at.toUtc().toIso8601String(),
    });
    return 'synthetic-execution-${calls.length}';
  }
}

class MediaClaimOutcomeStore extends MemoryStore {
  bool armed = false;
  bool confirmedAbort = false;
  int claims = 0;
  final stagedClaims = <String>{};
  @override
  Future<Row> update(
    String table,
    String id,
    Row data, {
    String? transactionId,
  }) async {
    if (armed &&
        table == 'media_assets' &&
        data['status'] == 'processing' &&
        transactionId != null) {
      stagedClaims.add(transactionId);
    }
    return super.update(table, id, data, transactionId: transactionId);
  }

  @override
  Future<void> finishTransaction(String id, {required bool commit}) async {
    if (commit && stagedClaims.remove(id)) {
      claims++;
      armed = false;
      if (confirmedAbort) {
        await super.finishTransaction(id, commit: false);
        throw const ConfirmedTransactionAbort();
      }
      await super.finishTransaction(id, commit: true);
      throw const RestException(409);
    }
    return super.finishTransaction(id, commit: commit);
  }
}

class Provider implements ai.AiProvider {
  final answers = <String>[];
  final inputs = <spec.AppSpec>[];
  @override
  Future<ai.AiResult> generate(
    String request,
    spec.AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
    String? rejectedOutput,
  }) async {
    inputs.add(current);
    return ai.AiResult(answers.removeAt(0), 'synthetic', 'no-network', {});
  }
}

PlatformService service(
  media.Fixture f, {
  Wakeups? wakeups,
  Provider? provider,
}) => PlatformService(
  f.store,
  clock: () => f.now,
  media: f.files,
  wakeups: wakeups,
  aiProvider: provider,
);
Row callFor(media.Fixture f, Wakeups wakeups, String mode) =>
    wakeups.calls.lastWhere(
      (call) => f.store.rows['worker_dispatches']![call['id']]!['mode'] == mode,
    );
Future<Row> deliver(WorkerEngine worker, Row call) =>
    worker.dispatch(call['id'] as String, call['proof'] as String);

Future<String> generate(
  PlatformService api,
  media.Fixture f,
  String operation,
  int revision,
) async {
  final response = await api.execute('alice', {
    'op': 'spec.generate',
    'appId': 'app',
    'operationId': operation,
    'expectedRevision': revision,
    'expectedVersionId': f.version,
    'request': 'Keep my photo journal and improve the cover label.',
    'startFromScratch': false,
  });
  return (response['generation'] as Row)['id'] as String;
}

Future<String> imageDraft(media.Fixture f) async {
  final id = await f.ready('existing-image', media.png());
  final definition = media.banner(spec.photoJournalTemplate(), id);
  ((((definition['navigation'] as Map)['pages'] as List).first
              as Map)['viewIds']
          as List)
      .add('cover');
  await f.api.execute('alice', {
    'op': 'spec.saveDraft',
    'appId': 'app',
    'operationId': 'image-draft',
    'expectedRevision': 1,
    'expectedVersionId': f.version,
    'spec': definition,
  });
  return id;
}

void main() {
  test(
    'complete queues proof-bound one-asset work and ready queues actual future cleanup',
    () async {
      final manifest =
          jsonDecode(await File('schema.json').readAsString()) as Row;
      expect(
        manifest['functionScopes'],
        containsAll([
          'rows.read',
          'rows.write',
          'executions.write',
          'files.read',
          'files.write',
        ]),
      );
      final workerConfig = manifest['workerFunction'] as Row;
      expect(workerConfig['execute'], isEmpty);
      expect(
        workerConfig['scopes'],
        containsAll([
          'rows.read',
          'rows.write',
          'executions.write',
          'files.read',
          'files.write',
        ]),
      );

      final f = media.Fixture();
      await f.setup();
      final wakeups = Wakeups(),
          api = service(f, wakeups: wakeups),
          worker = WorkerEngine(service(f, wakeups: wakeups));
      final id = await f.reserve('dispatch', media.png());
      await f.upload(id, media.png());
      await f.complete(id);
      expect(f.store.rows['media_assets']![id]!['status'], 'queued');
      expect(f.store.rows['worker_dispatches']!.values.single['mode'], 'media');
      await worker.flushWakeups();
      final call = callFor(f, wakeups, 'media');
      await base.error(
        () => worker.dispatch(call['id'] as String, 'a' * 43),
        'not_found',
      );
      await deliver(worker, call);
      expect(f.store.rows['media_assets']![id]!['status'], 'ready');
      final cleanup = callFor(f, wakeups, 'media_cleanup');
      expect(
        DateTime.parse(cleanup['at'] as String),
        f.now.add(MediaLimits.deletionQuietPeriod),
      );
      await base.error(() => deliver(worker, cleanup), 'work_not_due');
      expect(f.store.rows['media_assets']![id]!['originalRemoved'], false);
      final before = await api.execute('alice', {
        'op': 'spec.media.usage',
        'appId': 'app',
      });
      expect(before['pendingReleaseBytes'], greaterThan(0));
      f.now = f.now.add(
        MediaLimits.deletionQuietPeriod + const Duration(seconds: 1),
      );
      await deliver(worker, cleanup);
      expect(f.store.rows['media_assets']![id]!['originalRemoved'], true);
      expect(
        (await api.execute('alice', {
          'op': 'spec.media.usage',
          'appId': 'app',
        }))['pendingReleaseBytes'],
        0,
      );
      expect((await deliver(worker, call))['duplicate'], true);
    },
  );
  test(
    'unknown committed media claim does not replay or touch storage',
    () async {
      final store = MediaClaimOutcomeStore();
      final f = media.Fixture(memory: store);
      await f.setup();
      final id = await f.reserve('unknown-media-claim', media.png());
      await f.upload(id, media.png());
      await f.complete(id);
      var reads = 0;
      f.files.beforeRead = (_) async {
        reads++;
      };
      store.armed = true;
      await expectLater(
        f.api.processMedia(id),
        throwsA(
          isA<ServiceException>().having(
            (e) => e.code,
            'code',
            'transaction_conflict',
          ),
        ),
      );
      expect(store.claims, 1);
      expect(reads, 0);
      expect(store.rows['media_assets']![id]!['status'], 'processing');
      expect(
        DateTime.parse(
          store.rows['media_assets']![id]!['leaseUntil'] as String,
        ).difference(f.now),
        limits.workerMediaLease,
      );
    },
  );
  test('confirmed-abort media claim retries only its DB transaction', () async {
    final store = MediaClaimOutcomeStore()..confirmedAbort = true;
    final f = media.Fixture(memory: store);
    await f.setup();
    final id = await f.reserve('aborted-media-claim', media.png());
    await f.upload(id, media.png());
    await f.complete(id);
    var reads = 0;
    f.files.beforeRead = (_) async {
      reads++;
    };
    store.armed = true;
    await f.api.processMedia(id);
    expect(store.claims, 1);
    expect(reads, 1);
    expect(store.rows['media_assets']![id]!['status'], 'ready');
  });
  test('client chunk uploads retain their two-minute lease', () async {
    final f = media.Fixture();
    await f.setup();
    final bytes = media.png();
    final id = await f.reserve('chunk-lease-unchanged', bytes);
    final started = Completer<void>();
    final resume = Completer<void>();
    f.files.beforePut = (_) async {
      started.complete();
      await resume.future;
    };
    final write = f.api.execute('alice', f.chunk(id, bytes));
    await started.future;
    expect(
      DateTime.parse(
        f.store.rows['media_assets']![id]!['leaseUntil'] as String,
      ).difference(f.now),
      MediaLimits.leaseLifetime,
    );
    expect(MediaLimits.leaseLifetime, const Duration(minutes: 2));
    resume.complete();
    await write;
  });
  test(
    'active media worker may finish after its upload intent expires',
    () async {
      final f = media.Fixture();
      await f.setup();
      final wakeups = Wakeups();
      final api = service(f, wakeups: wakeups);
      final worker = WorkerEngine(api);
      final id = await f.reserve('intent-expiry-worker', media.png());
      await f.upload(id, media.png());
      await f.complete(id);
      await worker.flushWakeups();
      final call = callFor(f, wakeups, 'media');
      // The pending upload is still valid when processing begins.
      f.now = f.now.add(const Duration(seconds: 200));
      final started = Completer<void>();
      final resume = Completer<void>();
      f.files.beforeRead = (_) async {
        if (!started.isCompleted) started.complete();
        await resume.future;
      };
      final processing = deliver(worker, call);
      await started.future;
      f.now = f.now.add(const Duration(seconds: 401));
      expect(
        f.now.isAfter(
          DateTime.parse(
            f.store.rows['media_assets']![id]!['expiresAt'] as String,
          ),
        ),
        isTrue,
      );
      expect(await api.cleanupMedia(limit: 1, assetId: id), 0);
      expect(f.store.rows['media_assets']![id]!['status'], 'processing');
      resume.complete();
      await processing;
      expect(f.store.rows['media_assets']![id]!['status'], 'ready');
    },
  );
  test('an expired media worker cannot mark its old attempt failed', () async {
    final f = media.Fixture();
    await f.setup();
    final id = await f.reserve('expired-failure', media.png());
    await f.upload(id, media.png());
    await f.complete(id);
    final started = Completer<void>();
    final resume = Completer<void>();
    String? chunkId;
    f.files.beforeRead = (key) async {
      chunkId = key;
      started.complete();
      await resume.future;
    };
    final processing = f.api.processMedia(id);
    await started.future;
    // Force invalid bytes after the worker lease has expired, without a new
    // owner. A stale attempt must not set terminal failure on its old token.
    f.now = f.now.add(limits.workerMediaLease + const Duration(seconds: 1));
    f.files.values[chunkId!]![0] ^= 1;
    resume.complete();
    await expectLater(processing, throwsA(isA<ServiceException>()));
    expect(f.store.rows['media_assets']![id]!['status'], 'processing');
  });
  test('an expired cleanup lease cannot finalize or count deletion', () async {
    final f = media.Fixture();
    await f.setup();
    final id = await f.ready('expired-cleanup', media.png());
    f.now = f.now.add(
      MediaLimits.deletionQuietPeriod + const Duration(seconds: 1),
    );
    await f.api.cleanupMedia(limit: 1, assetId: id);
    expect(f.store.rows['media_assets']![id]!['originalRemoved'], isTrue);
    f.now = f.now.add(
      MediaLimits.unreferencedGrace + const Duration(seconds: 1),
    );
    final started = Completer<void>();
    final resume = Completer<void>();
    f.files.beforeRemove = (_) async {
      if (!started.isCompleted) {
        started.complete();
        await resume.future;
      }
    };
    final cleanup = f.api.cleanupMedia(limit: 1, assetId: id);
    await started.future;
    expect(f.store.rows['media_assets']![id]!['status'], 'deleting');
    f.now = f.now.add(limits.workerMediaLease + const Duration(seconds: 1));
    resume.complete();
    expect(await cleanup, 0);
    expect(f.store.rows['media_assets']![id]!['status'], 'deleting');
    expect(f.store.rows['media_assets']![id]!['storedBytes'], greaterThan(0));
  });
  test(
    'expired Worker media lease fences stale dispatch completion after reclaim',
    () async {
      final f = media.Fixture();
      await f.setup();
      final wakeups = Wakeups();
      final api = service(f, wakeups: wakeups);
      final worker = WorkerEngine(api);
      final id = await f.reserve('media-lease-fence', media.png());
      await f.upload(id, media.png());
      await f.complete(id);
      await worker.flushWakeups();
      final call = callFor(f, wakeups, 'media');
      final dispatchId = call['id'] as String;
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final releaseSecond = Completer<void>();
      var reads = 0;
      f.files.beforeRead = (_) async {
        reads++;
        if (reads == 1) {
          firstStarted.complete();
          await releaseFirst.future;
        } else if (reads == 2) {
          secondStarted.complete();
          await releaseSecond.future;
        }
      };
      final first = deliver(worker, call);
      await firstStarted.future;
      final initial = f.store.rows['worker_dispatches']![dispatchId]!;
      final firstGeneration = initial['generation'];
      expect(
        DateTime.parse(initial['leaseUntil'] as String).difference(f.now),
        limits.workerDispatchLease,
      );
      expect(
        DateTime.parse(
          f.store.rows['media_assets']![id]!['leaseUntil'] as String,
        ).difference(f.now),
        limits.workerMediaLease,
      );
      // The old 130s dispatch and 120s media deadlines are still fenced.
      f.now = f.now.add(const Duration(seconds: 131));
      expect((await deliver(worker, call))['duplicate'], isTrue);
      expect(reads, 1);
      // After both new leases, but before the 600s upload intent expires,
      // simulate reclaim while an old worker is delayed beyond its runtime.
      f.now = f.now.add(
        limits.workerDispatchLease - const Duration(seconds: 130),
      );
      final second = deliver(worker, call);
      await secondStarted.future;
      final reclaimed = f.store.rows['worker_dispatches']![dispatchId]!;
      expect(reclaimed['generation'], greaterThan(firstGeneration as int));
      final secondGeneration = reclaimed['generation'];
      releaseFirst.complete();
      await expectLater(
        first,
        throwsA(
          isA<ServiceException>().having(
            (e) => e.code,
            'code',
            'media_state_conflict',
          ),
        ),
      );
      expect(
        f.store.rows['worker_dispatches']![dispatchId]!['status'],
        'running',
      );
      expect(
        f.store.rows['worker_dispatches']![dispatchId]!['generation'],
        secondGeneration,
      );
      expect(f.store.rows['media_assets']![id]!['status'], 'processing');
      releaseSecond.complete();
      await second;
      expect(
        f.store.rows['worker_dispatches']![dispatchId]!['status'],
        'delivered',
      );
      expect(f.store.rows['media_assets']![id]!['status'], 'ready');
      expect(reads, 2);
    },
  );
  test(
    'hourly reconciliation schedules expired cleanup without decoding or reading Storage',
    () async {
      final f = media.Fixture();
      await f.setup();
      final id = await f.reserve('expired-work', media.png());
      await f.upload(id, media.png());
      final wakeups = Wakeups(),
          worker = WorkerEngine(service(f, wakeups: wakeups));
      f.now = f.now.add(const Duration(minutes: 11));
      f.files.beforeRead = (_) async {
        throw StateError('Reconciliation read private bytes');
      };
      final result = await worker.reconcile(limit: 1);
      expect((result['media'] as Map)['scheduled'], 1);
      expect(f.files.values, isNotEmpty);
      await deliver(worker, callFor(f, wakeups, 'media_cleanup'));
      expect(f.store.rows['media_assets']![id]!['status'], 'deleting');
      expect(f.files.values, isEmpty);
      final quiet = callFor(f, wakeups, 'media_cleanup');
      f.now = f.now.add(
        MediaLimits.deletionQuietPeriod + const Duration(seconds: 1),
      );
      await deliver(worker, quiet);
      expect(f.store.rows['media_assets']![id]!['status'], 'deleted');
      expect(f.store.rows['media_quotas']!['global']!['bytes'], 0);
    },
  );
  test(
    'handled malformed image work remains failed and never claims a ready image',
    () async {
      final f = media.Fixture();
      await f.setup();
      final bytes = media.png();
      final response = await f.api.execute(
        'alice',
        f.begin('bad-mime', bytes, mime: 'image/jpeg'),
      );
      final id = (response['asset'] as Row)['assetId'] as String;
      await f.upload(id, bytes);
      await f.complete(id);
      final wakeups = Wakeups(),
          worker = WorkerEngine(service(f, wakeups: wakeups));
      await worker.flushWakeups();
      await deliver(worker, callFor(f, wakeups, 'media'));
      expect((await f.status(id))['status'], 'failed');
      await base.error(() => f.read(id), 'not_found');
      expect(f.store.rows['media_assets']![id]!['displayHash'], isNull);
    },
  );
  test(
    'AI edits preserve a ready source image and retain the resulting private candidate atomically',
    () async {
      final f = media.Fixture();
      await f.setup();
      final id = await imageDraft(f);
      final provider = Provider()
        ..answers.add(
          jsonEncode({
            'patches': [
              {
                'type': 'RenameLabel',
                'targetId': 'cover',
                'label': 'Treasured moments',
              },
            ],
          }),
        );
      final api = service(f, provider: provider),
          worker = WorkerEngine(service(f, provider: provider));
      final job = await generate(api, f, 'edit-existing-image', 2);
      await worker.generate(job);
      expect(f.store.rows['generation_jobs']![job]!['status'], 'preview ready');
      final draft =
          (await api.execute('alice', {
                'op': 'spec.getApp',
                'appId': 'app',
              }))['app']
              as Row;
      expect(jsonEncode((draft['draft'] as Row)['spec']), contains(id));
      expect(
        f.store.rows['media_refs']!.values
            .where((r) => r['ownerKind'] == 'draft')
            .single['assetIdsJson'],
        contains(id),
      );
      expect(
        provider.inputs.single.views.any(
          (v) => v.options['imageAssetId'] == id,
        ),
        true,
      );
      expect(provider.inputs.single.canonical, isNot(contains('data:image')));
    },
  );
  test(
    'AI cannot substitute another ready same-app image absent from its captured source',
    () async {
      final f = media.Fixture();
      await f.setup();
      final existing = await imageDraft(f),
          other = await f.ready('other-ready', media.png());
      final provider = Provider()
        ..answers.add(
          jsonEncode({
            'patches': [
              {
                'type': 'UpdateView',
                'viewId': 'cover',
                'view': {
                  'type': 'banner',
                  'label': 'Cover',
                  'options': {
                    'title': 'Private image',
                    'imageAssetId': other,
                    'imageAlt': 'QA image',
                  },
                },
              },
            ],
          }),
        );
      final api = service(f, provider: provider),
          worker = WorkerEngine(service(f, provider: provider));
      final job = await generate(api, f, 'invent-image', 2);
      await worker.generate(job);
      expect(
        f.store.rows['generation_jobs']![job]!['status'],
        isNot('preview ready'),
      );
      expect(
        f.store.rows['generation_jobs']![job]!['failureCategory'],
        'media_reference',
      );
      final draft = f.store.rows['spec_drafts']!.values.single;
      expect(draft['specJson'], contains(existing));
      expect(draft['specJson'], isNot(contains(other)));
    },
  );
}
