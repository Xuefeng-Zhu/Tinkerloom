import 'dart:convert';
import 'dart:io';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:test/test.dart';
import '../lib/service.dart';
import '../lib/providers/provider.dart' as ai;
import 'media_check.dart' as media;
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
