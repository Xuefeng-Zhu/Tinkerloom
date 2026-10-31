import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/providers/runtime_limits.dart' as limits;
import 'package:crypto/crypto.dart';
import '../lib/service.dart';
import '../lib/worker_http.dart';
import '../lib/providers/provider.dart' as ai;
import 'memory_store.dart';
import 'spec_engine_check.dart' as base;

class Clock {
  DateTime value = DateTime.utc(2030, 1, 1, 10);
  DateTime call() => value;
  void advance([int seconds = 180]) =>
      value = value.add(Duration(seconds: seconds));
}

class ScriptProvider implements ai.AiProvider, ai.GuidanceProvider {
  final calls = <Row>[];
  final answers = <Object>[];
  Future<ai.AiResult> Function()? paused;
  @override
  Future<ai.AiResult> generate(
    String request,
    spec.AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
    String? rejectedOutput,
  }) async {
    calls.add({
      'request': request,
      'editing': editing,
      'diagnostics': diagnostics,
      'rejected': rejectedOutput,
    });
    if (paused != null) return paused!();
    final result = answers.removeAt(0);
    if (result is ai.AiResult) return result;
    throw result;
  }

  @override
  Future<List<ai.GuidanceQuestion>> suggestQuestions(
    String request, {
    spec.AppSpec? definition,
  }) async => [
    ai.GuidanceQuestion(
      question: 'Who uses it?',
      options: ['Me', 'My group', 'Everyone'],
    ),
  ];
}

class UnexpectedResult extends ai.AiResult {
  UnexpectedResult() : super('', 'fixture', 'fixture', {});

  @override
  String get text => throw StateError('private post-response failure');
}

class Wakeups implements WorkerWakeups {
  final calls = <Row>[];
  bool fail = false;
  @override
  Future<String> schedule({
    required String dispatchId,
    required String proof,
    required DateTime at,
  }) async {
    calls.add({'id': dispatchId, 'proof': proof, 'at': at.toIso8601String()});
    if (fail) throw StateError('Unavailable');
    return 'execution-${calls.length}';
  }
}

class CountingStore extends MemoryStore {
  final counts = <String, int>{};
  int largest = 0;
  bool failBatch = false;
  void _count(String? tx) {
    if (tx != null) {
      counts[tx] = (counts[tx] ?? 0) + 1;
      if (counts[tx]! > largest) largest = counts[tx]!;
    }
  }

  @override
  Future<Row> create(
    String table,
    String id,
    Row data, {
    String? transactionId,
  }) {
    _count(transactionId);
    if (table == 'notification_batches' && failBatch) {
      failBatch = false;
      throw const RestException(502);
    }
    return super.create(table, id, data, transactionId: transactionId);
  }

  @override
  Future<Row> update(
    String table,
    String id,
    Row data, {
    String? transactionId,
  }) {
    _count(transactionId);
    return super.update(table, id, data, transactionId: transactionId);
  }
}

class Fixture {
  Fixture(this.store, this.clock, this.service);
  final MemoryStore store;
  final Clock clock;
  final PlatformService service;
  WorkerEngine get worker => WorkerEngine(service);
  Future<Row> app() =>
      service.execute('alice', {'op': 'spec.getApp', 'appId': 'app'});
  Future<String> publish(
    int revision,
    String? previous,
    String op, {
    List<String> enabled = const [],
    List<String> records = const [],
    String actor = 'alice',
  }) async {
    final review =
        (await service.execute(actor, {
              'op': 'spec.review',
              'appId': 'app',
              'expectedRevision': revision,
              'enabledRuleIds': enabled,
              'activateExistingRecordIds': records,
            }))['review']
            as Row;
    final response = await service.execute(actor, {
      'op': 'spec.publish',
      'appId': 'app',
      'operationId': op,
      'expectedRevision': revision,
      'expectedVersionId': previous,
      'candidateHash': review['candidateHash'],
      'reviewHash': review['reviewHash'],
      'enabledRuleIds': enabled,
      'activateExistingRecordIds': records,
    });
    return ((response['app'] as Row)['version'] as Row)['id'] as String;
  }

  Future<void> save(
    spec.AppSpec definition,
    int revision,
    String? version,
    String op,
  ) async {
    await service.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': op,
      'expectedRevision': revision,
      'expectedVersionId': version,
      'spec': definition.toJson(),
    });
  }

  Future<Row> task(String version, String id, {String? date}) async {
    final outcome = await base.run(
      service,
      'alice',
      base.action(id, version, 'addTask', {
        'data': {
          'title': id,
          'status': 'Open',
          if (date != null) 'reminderAt': date,
        },
      }),
    );
    return base.get(service, 'alice', version, outcome['recordId'] as String);
  }

  Future<Row> generation({
    int revision = 0,
    String? version,
    String id = 'generate',
    String request = 'Track books',
    bool fresh = true,
  }) => service.execute('alice', {
    'op': 'spec.generate',
    'appId': 'app',
    'operationId': id,
    'expectedRevision': revision,
    'expectedVersionId': version,
    'request': request,
    'startFromScratch': fresh,
  });
}

Future<Fixture> fixture({
  MemoryStore? store,
  Clock? clock,
  ai.AiProvider? provider,
  Wakeups? wakeups,
  bool reminders = true,
}) async {
  final memory = store ?? MemoryStore(), time = clock ?? Clock();
  final service = PlatformService(
    memory,
    clock: time.call,
    aiProvider: provider,
    remindersEnabled: reminders,
    wakeups: wakeups,
  );
  await service.execute('alice', {
    'op': 'createWorkspace',
    'id': 'ws',
    'name': 'Workspace',
  });
  await service.execute('alice', {
    'op': 'spec.createApp',
    'workspaceId': 'ws',
    'id': 'app',
    'name': 'App',
    'operationId': 'create',
  });
  return Fixture(memory, time, service);
}

ai.AiResult answer(String text) =>
    ai.AiResult(text, 'test-only', 'scripted', {});
Future<Row> state(Fixture f, String version, String record) async =>
    (await f.service.execute('alice', {
          'op': 'spec.reminderState',
          'appId': 'app',
          'versionId': version,
          'recordId': record,
        }))['states'].single
        as Row;

void main() {
  test(
    'reminders require explicit publication approval; new records enroll without timestamp ordering ambiguity',
    () async {
      final f = await fixture();
      final definition = spec.dailyPlannerTemplate();
      await f.save(definition, 0, null, 'draft');
      final v1 = await f.publish(1, null, 'publish');
      final before = await f.task(
        v1,
        'old',
        date: f.clock.value.toIso8601String(),
      );
      await f.worker.reminders();
      expect(f.store.rows['automation_runs'], isNull);
      await f.save(definition, 1, v1, 'approve-draft');
      final v2 = await f.publish(2, v1, 'approve', enabled: ['taskReminder']);
      await f.worker.reminders();
      expect(
        (await state(f, v2, before['id'] as String))['state'],
        'unenrolled',
      );
      final after = await f.task(
        v2,
        'new',
        date: f.clock.value.toIso8601String(),
      );
      await WorkerEngine(
        PlatformService(f.store, clock: f.clock.call, remindersEnabled: true),
      ).reminders();
      expect((await state(f, v2, after['id'] as String))['state'], 'delivered');
      expect(f.store.rows['notification_batches']!.length, 1);
    },
  );
  test(
    'explicit enrollment includes old unset records and survives presentation-only publication',
    () async {
      final f = await fixture();
      final definition = spec.dailyPlannerTemplate();
      await f.save(definition, 0, null, 'd1');
      final v1 = await f.publish(1, null, 'p1');
      final record = await f.task(v1, 'unset');
      final id = record['id'] as String;
      await f.save(definition, 1, v1, 'd2');
      final v2 = await f.publish(
        2,
        v1,
        'p2',
        enabled: ['taskReminder'],
        records: [id],
      );
      await f.worker.reminders();
      expect((await state(f, v2, id))['state'], 'unset');
      final renamed = spec.AppSpec.parse(
        jsonEncode({...definition.toJson(), 'name': 'A new title'}),
      );
      await f.save(renamed, 2, v2, 'd3');
      final v3 = await f.publish(3, v2, 'p3', enabled: ['taskReminder']);
      await base.run(
        f.service,
        'alice',
        base.action(
          'set-date',
          v3,
          'editTask',
          {
            'data': {'reminderAt': f.clock.value.toIso8601String()},
          },
          record: id,
          revision: 1,
        ),
      );
      await f.worker.reminders();
      expect((await state(f, v3, id))['state'], 'delivered');
      expect(f.store.rows['automations']!.values.single['ruleVersion'], 1);
    },
  );
  test(
    'disable and reenable increments generation and does not silently enroll old records',
    () async {
      final f = await fixture();
      final definition = spec.dailyPlannerTemplate();
      await f.save(definition, 0, null, 'd1');
      final v1 = await f.publish(1, null, 'p1', enabled: ['taskReminder']);
      final r = await f.task(
        v1,
        'old',
        date: f.clock.value.add(const Duration(days: 1)).toIso8601String(),
      );
      await f.worker.reminders();
      await f.save(definition, 1, v1, 'd2');
      final v2 = await f.publish(2, v1, 'p2');
      await f.save(definition, 2, v2, 'd3');
      final v3 = await f.publish(3, v2, 'p3', enabled: ['taskReminder']);
      expect((await state(f, v3, r['id'] as String))['state'], 'unenrolled');
      f.clock.advance(90000);
      await f.worker.reminders();
      expect(f.store.rows['notification_batches'], isNull);
      expect(
        f.store.rows['automation_runs']!.values.single['status'],
        'suppressed',
      );
    },
  );
  test(
    'delivery rechecks condition and date signature and duplicate executions do not duplicate inbox',
    () async {
      final f = await fixture();
      await f.save(spec.dailyPlannerTemplate(), 0, null, 'd');
      final version = await f.publish(1, null, 'p', enabled: ['taskReminder']);
      final r = await f.task(
        version,
        'future',
        date: f.clock.value.add(const Duration(minutes: 1)).toIso8601String(),
      );
      final id = r['id'] as String;
      await f.worker.reminders();
      await base.run(
        f.service,
        'alice',
        base.action(
          'move',
          version,
          'moveTask',
          {'value': 'Done'},
          record: id,
          revision: 1,
        ),
      );
      f.clock.advance();
      await f.worker.reminders();
      expect(
        f.store.rows['automation_runs']!.values.single['status'],
        'suppressed',
      );
      await base.run(
        f.service,
        'alice',
        base.action(
          'open',
          version,
          'moveTask',
          {'value': 'Open'},
          record: id,
          revision: 2,
        ),
      );
      await base.run(
        f.service,
        'alice',
        base.action(
          'new-time',
          version,
          'editTask',
          {
            'data': {'reminderAt': f.clock.value.toIso8601String()},
          },
          record: id,
          revision: 3,
        ),
      );
      await f.worker.reminders();
      await f.worker.reminders();
      expect(f.store.rows['notification_batches']!.length, 1);
      final inbox = await f.service.execute('alice', {'op': 'spec.inbox'});
      expect(inbox['items'], hasLength(1));
    },
  );
  test(
    'notification batch and run completion roll back together and obey persisted retry backoff',
    () async {
      final store = CountingStore();
      // Use one store for the injected failure and the service.
      final actual = await fixture(store: store);
      await actual.save(spec.dailyPlannerTemplate(), 0, null, 'd');
      final version = await actual.publish(
        1,
        null,
        'p',
        enabled: ['taskReminder'],
      );
      await actual.task(
        version,
        'due',
        date: actual.clock.value.toIso8601String(),
      );
      store.failBatch = true;
      await actual.worker.reminders();
      expect(store.rows['notification_batches'], isNull);
      final failed = store.rows['automation_runs']!.values.single;
      expect(failed['status'], 'pending');
      expect(failed['attempts'], 1);
      await actual.worker.reminders();
      expect(store.rows['automation_runs']!.values.single['attempts'], 1);
      actual.clock.advance(3);
      await actual.worker.reminders();
      expect(store.rows['notification_batches']!.length, 1);
      expect(
        store.rows['automation_runs']!.values.single['status'],
        'succeeded',
      );
      expect(store.largest, lessThanOrEqualTo(100));
    },
  );
  test(
    'private inbox read receipts reauthorize after grant revocation and never expose other recipients',
    () async {
      final f = await fixture();
      await f.save(spec.dailyPlannerTemplate(), 0, null, 'd');
      final v = await f.publish(1, null, 'p', enabled: ['taskReminder']);
      await f.task(v, 'due', date: f.clock.value.toIso8601String());
      await f.worker.reminders();
      await base.join(f.service, 'bob', 7, role: 'viewer');
      expect(
        (await f.service.execute('bob', {'op': 'spec.inbox'}))['items'],
        isEmpty,
      );
      final item =
          ((await f.service.execute('alice', {'op': 'spec.inbox'}))['items']
                      as List)
                  .single
              as Row;
      final input = {
        'op': 'spec.readNotification',
        'appId': 'app',
        'runId': item['runId'],
        'notificationId': item['id'],
        'operationId': 'read',
      };
      expect((await f.service.execute('alice', input))['isRead'], true);
      expect(await f.service.execute('alice', input), {
        'notificationId': item['id'],
        'isRead': true,
      });
      await base.error(
        () => f.service.execute('bob', {...input, 'operationId': 'not-mine'}),
        'not_found',
      );
      expect(
        (await f.service.execute('alice', {
          'op': 'spec.runs',
          'appId': 'app',
        }))['runs'],
        hasLength(1),
      );
      await base.error(
        () => f.service.execute('bob', {'op': 'spec.runs', 'appId': 'app'}),
        'forbidden',
      );
    },
  );
  test(
    'archive suppresses persisted due reminders without destroying approved rules or records',
    () async {
      final f = await fixture();
      await f.save(spec.dailyPlannerTemplate(), 0, null, 'd');
      final v = await f.publish(1, null, 'p', enabled: ['taskReminder']);
      await f.task(
        v,
        'due',
        date: f.clock.value.add(const Duration(seconds: 60)).toIso8601String(),
      );
      await f.worker.reminders();
      await f.service.execute('alice', {
        'op': 'archiveApp',
        'appId': 'app',
        'operationId': 'archive',
      });
      f.clock.advance();
      await f.worker.reminders();
      expect(
        f.store.rows['automation_runs']!.values.single['status'],
        'suppressed',
      );
      expect(f.store.rows['notification_batches'], isNull);
    },
  );
  test(
    'fresh generation persists a job before optional wakeup and never stores a placeholder candidate',
    () async {
      final provider = ScriptProvider()
        ..answers.add(answer(ai.creationReferenceJson));
      final wakeups = Wakeups()..fail = true;
      final f = await fixture(provider: provider, wakeups: wakeups);
      final response = await f.generation();
      final job = (response['generation'] as Row)['id'] as String;
      expect((response['app'] as Row)['draft'], isNull);
      expect(f.store.rows['generation_jobs']![job]!['status'], 'queued');
      expect(f.store.rows['spec_drafts'], isNull);
      expect(provider.calls, isEmpty);
      await f.worker.generate(job);
      expect(f.store.rows['generation_jobs']![job]!['status'], 'preview ready');
      expect(f.store.rows['spec_drafts']!.length, 1);
      expect(provider.calls.single['editing'], false);
      expect(f.store.rows['generation_jobs']![job]!['repairJson'], isNull);
    },
  );
  test(
    'generation exact receipt replay never schedules a second provider job and current actor quota is global',
    () async {
      final provider = ScriptProvider()
        ..answers.add(answer(ai.creationReferenceJson));
      final f = await fixture(provider: provider);
      final first = await f.generation();
      expect(await f.generation(), first);
      expect(f.store.rows['generation_jobs']!.length, 1);
      await base.error(() => f.generation(id: 'another'), 'generation_active');
      final job = (first['generation'] as Row)['id'] as String;
      await f.worker.generate(job);
      await f.worker.generate(job);
      expect(provider.calls.length, 1);
      expect(f.store.rows['generation_jobs']![job]!['attempts'], 1);
    },
  );
  test(
    'undeclared collection diagnostics reach an existing bounded repair without inventing a graph',
    () async {
      final bad = jsonDecode(ai.creationReferenceJson) as Map<String, dynamic>;
      bad['collections'][0]['id'] = 'bookCatalog';
      final rejected = jsonEncode(bad);
      final provider = ScriptProvider()
        ..answers.addAll([answer(rejected), answer(ai.creationReferenceJson)]);
      final f = await fixture(provider: provider);
      final job =
          ((await f.generation(request: 'A reading list'))['generation']
                  as Row)['id']
              as String;
      await f.worker.generate(job);
      final first = f.store.rows['generation_jobs']![job]!;
      expect(first['status'], 'queued');
      expect(first['failureCategory'], 'spec_validation');
      expect(
        first['diagnostics'],
        contains('View "bookList" references undeclared collection "books"'),
      );
      expect(
        first['diagnostics'],
        contains('never infer fields, permissions or behavior'),
      );
      expect(f.store.rows['spec_drafts'], isNull);
      expect(provider.calls, hasLength(1));
      f.clock.advance(3);
      await f.worker.generate(job);
      expect(provider.calls, hasLength(2));
      expect(
        (provider.calls.last['diagnostics'] as List).single,
        contains('View "bookList" references undeclared collection "books"'),
      );
      expect(provider.calls.last['rejected'], rejected);
      expect(f.store.rows['generation_jobs']![job]!['status'], 'preview ready');
    },
  );
  test(
    'transport loss during a semantic repair is terminal and does not dispatch again',
    () async {
      final provider = ScriptProvider()
        ..answers.addAll([
          answer('{bad'),
          const ai.AiResponseException(
            'transport_error',
            'Temporary transport issue',
            retryable: true,
          ),
          answer(ai.creationReferenceJson),
        ]);
      final f = await fixture(provider: provider);
      final job = ((await f.generation())['generation'] as Row)['id'] as String;
      await f.worker.generate(job);
      expect(f.store.rows['generation_jobs']![job]!['repairJson'], isNotNull);
      f.clock.advance(3);
      await f.worker.generate(job);
      expect(f.store.rows['generation_jobs']![job]!['status'], 'failed');
      expect(
        f.store.rows['generation_jobs']![job]!['failureCategory'],
        'indeterminate',
      );
      expect(provider.calls.last['rejected'], '{bad');
      f.clock.advance(5);
      await f.worker.generate(job);
      expect(provider.calls.length, 2);
      expect(f.store.rows['generation_jobs']![job]!['repairJson'], isNull);
    },
  );
  test(
    'three attempts fail durably and failed fresh generations leave no draft to accidentally publish',
    () async {
      final provider = ScriptProvider()
        ..answers.addAll(List.generate(3, (_) => answer('[]')));
      final f = await fixture(provider: provider);
      final job = ((await f.generation())['generation'] as Row)['id'] as String;
      for (var i = 0; i < 3; i++) {
        await f.worker.generate(job);
        f.clock.advance();
      }
      await f.worker.generate(job);
      expect(provider.calls.length, 3);
      expect(f.store.rows['generation_jobs']![job]!['status'], 'failed');
      expect(f.store.rows['spec_drafts'], isNull);
      expect(
        f.store.rows['actor_limits']!.values.single['activeGenerationJobId'],
        isNull,
      );
    },
  );
  test(
    'manual save fences a late provider response and clears scoped repair data',
    () async {
      final gate = Completer<ai.AiResult>(), started = Completer<void>();
      final provider = ScriptProvider()
        ..paused = () {
          started.complete();
          return gate.future;
        };
      final f = await fixture(provider: provider);
      final job = ((await f.generation())['generation'] as Row)['id'] as String;
      final running = f.worker.generate(job);
      await started.future;
      await f.save(spec.starterTemplates()['reading']!, 0, null, 'manual');
      gate.complete(answer(ai.creationReferenceJson));
      await running;
      expect(f.store.rows['generation_jobs']![job]!['status'], 'stale');
      expect(f.store.rows['spec_drafts']!.values.single['revision'], 1);
      expect(f.store.rows['generation_jobs']![job]!['repairJson'], isNull);
      expect(
        f.store.rows['actor_limits']!.values.single['activeGenerationJobId'],
        isNull,
      );
    },
  );
  test(
    'unexpected failure after provider result does not dispatch twice',
    () async {
      final provider = ScriptProvider()..answers.add(UnexpectedResult());
      final f = await fixture(provider: provider);
      final job = ((await f.generation())['generation'] as Row)['id'] as String;
      await f.worker.generate(job);
      f.clock.advance();
      await f.worker.generate(job);
      final stored = f.store.rows['generation_jobs']![job]!;
      expect(stored['status'], 'failed');
      expect(stored['failureCategory'], 'unexpected');
      expect(
        stored['diagnostics'],
        isNot(contains('private post-response failure')),
      );
      expect(provider.calls.length, 1);
    },
  );
  test('unclassified provider exceptions do not dispatch twice', () async {
    for (final error in [
      StateError('private provider text'),
      const FormatException('private provider text'),
      const spec.SpecException('private provider text'),
    ]) {
      final provider = ScriptProvider()..answers.add(error);
      final f = await fixture(provider: provider);
      final job = ((await f.generation())['generation'] as Row)['id'] as String;
      await f.worker.generate(job);
      f.clock.advance();
      await f.worker.generate(job);
      final stored = f.store.rows['generation_jobs']![job]!;
      expect(stored['status'], 'failed');
      expect(stored['failureCategory'], 'indeterminate');
      expect(stored['diagnostics'], isNot(contains('private provider text')));
      expect(provider.calls.length, 1);
    }
  });
  test(
    'expired in-flight leases fail unknown without a second provider request',
    () async {
      for (final stage in ['generating', 'validating']) {
        final gate = Completer<ai.AiResult>(), started = Completer<void>();
        final provider = ScriptProvider()
          ..paused = () {
            started.complete();
            return gate.future;
          };
        final f = await fixture(provider: provider);
        final job =
            ((await f.generation())['generation'] as Row)['id'] as String;
        final old = f.worker.generate(job);
        await started.future;
        f.store.rows['generation_jobs']![job]!['status'] = stage;
        f.clock.advance(121);
        provider.paused = null;
        provider.answers.add(answer(ai.creationReferenceJson));
        final dispatchCount = f.store.rows['worker_dispatches']?.length ?? 0;
        Future<void> recover() => WorkerEngine(
          PlatformService(f.store, clock: f.clock.call, aiProvider: provider),
        ).generate(job);
        await Future.wait([recover(), recover()]);
        expect(
          f.store.rows['worker_dispatches']?.length ?? 0,
          dispatchCount,
          reason: stage,
        );
        gate.complete(answer('{}'));
        await old;
        final stored = f.store.rows['generation_jobs']![job]!;
        expect(stored['status'], 'failed', reason: stage);
        expect(stored['failureCategory'], 'indeterminate', reason: stage);
        expect(stored['leaseUntil'], isNull, reason: stage);
        expect(provider.calls.length, 1, reason: stage);
        expect(
          f.store.rows['actor_limits']!.values.single['activeGenerationJobId'],
          isNull,
          reason: stage,
        );
      }
    },
  );
  test(
    'failed edit can retain its last valid candidate but cannot be published before explicit keepPrevious',
    () async {
      final provider = ScriptProvider()
        ..answers.add(
          const ai.AiResponseException(
            'unsupported',
            'Unavailable',
            retryable: false,
          ),
        );
      final f = await fixture(provider: provider);
      final definition = spec.starterTemplates()['reading']!;
      await f.save(definition, 0, null, 'd');
      final v = await f.publish(1, null, 'p');
      final job =
          ((await f.generation(
                    revision: 1,
                    version: v,
                    fresh: false,
                    request: 'Change this book app',
                  ))['generation']
                  as Row)['id']
              as String;
      await f.worker.generate(job);
      await base.error(
        () => f.service.execute('alice', {
          'op': 'spec.review',
          'appId': 'app',
          'expectedRevision': 2,
          'enabledRuleIds': [],
          'activateExistingRecordIds': [],
        }),
        'generation_pending',
      );
      await f.service.execute('alice', {
        'op': 'spec.keepPrevious',
        'appId': 'app',
        'jobId': job,
        'expectedRevision': 2,
        'operationId': 'keep',
      });
      expect(f.store.rows['spec_drafts']!.values.single['revision'], 3);
      expect(
        f.store.rows['spec_drafts']!.values.single['candidateHash'],
        definition.hash,
      );
      await f.publish(3, v, 'kept');
    },
  );
  test(
    'guidance is actor limited and writes no draft, generation job or app record',
    () async {
      final f = await fixture(provider: ScriptProvider());
      for (var i = 0; i < 20; i++) {
        final result = await f.service.execute('alice', {
          'op': 'spec.guidance',
          'workspaceId': 'ws',
          'request': 'A club app',
        });
        expect(result['questions'], hasLength(1));
      }
      await base.error(
        () => f.service.execute('alice', {
          'op': 'spec.guidance',
          'workspaceId': 'ws',
          'request': 'A club app',
        }),
        'quota_exceeded',
      );
      expect(f.store.rows['spec_drafts'], isNull);
      expect(f.store.rows['generation_jobs'], isNull);
      expect(f.store.rows['spec_records'], isNull);
    },
  );
  test(
    'unconfigured provider does not block manual templates and capability metadata is truthful',
    () async {
      final f = await fixture(reminders: false);
      await base.error(() => f.generation(), 'provider_unavailable');
      final capabilities = await f.service.execute('alice', {
        'op': 'spec.capabilities',
      });
      expect(capabilities['generation'], false);
      expect(capabilities['effects'], isEmpty);
      await f.save(spec.starterTemplates()['reading']!, 0, null, 'd');
      await f.publish(1, null, 'p');
      await base.error(
        () => f.service.execute('alice', {
          'op': 'worker.generate',
          'jobId': 'anything',
        }),
        'unknown_operation',
      );
    },
  );
  test(
    'wakeup proof is hashed and a failed scheduler keeps planned work with bounded retries',
    () async {
      final wakeups = Wakeups()..fail = true;
      final f = await fixture(provider: ScriptProvider(), wakeups: wakeups);
      final job = ((await f.generation())['generation'] as Row)['id'] as String;
      final dispatch = f.store.rows['worker_dispatches']!.values.singleWhere(
        (r) => r['targetId'] == job,
      );
      expect(dispatch['status'], 'planned');
      expect(dispatch['errorCategory'], 'wakeup_unavailable');
      expect(
        jsonEncode(f.store.rows),
        isNot(contains(wakeups.calls.first['proof'])),
      );
      final count = wakeups.calls.length;
      await f.worker.flushWakeups();
      expect(wakeups.calls.length, count);
      await base.error(
        () => f.worker.dispatch(dispatch[r'$id'] as String, 'A' * 43),
        'not_found',
      );
      expect(f.store.rows['generation_jobs']![job]!['attempts'], 0);
    },
  );
  test(
    'authenticated private dispatch only starts its persisted work and duplicate dispatch is safe',
    () async {
      final wakeups = Wakeups(),
          provider = ScriptProvider()
            ..answers.add(answer(ai.creationReferenceJson));
      final f = await fixture(provider: provider, wakeups: wakeups);
      final job = ((await f.generation())['generation'] as Row)['id'] as String;
      final call = wakeups.calls.singleWhere(
        (c) => f.store.rows['worker_dispatches']![c['id']]!['targetId'] == job,
      );
      expect(
        (await f.worker.dispatch(
          call['id'] as String,
          call['proof'] as String,
        ))['accepted'],
        true,
      );
      expect(
        (await f.worker.dispatch(
          call['id'] as String,
          call['proof'] as String,
        ))['duplicate'],
        true,
      );
      expect(provider.calls.length, 1);
      expect(
        f.store.rows['worker_dispatches']![call['id']]!['status'],
        'delivered',
      );
    },
  );
  test(
    'GLM generation and dispatch leases fence expired requests without replay',
    () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      var requests = 0;
      final provider = ai.ChatCompletionProvider(
        Uri.parse('https://integrate.api.nvidia.com/v1'),
        limits.glmModelId,
        'fixture-key',
        nvidiaModelEvaluation: true,
        clientFactory: () => MockClient((_) {
          requests++;
          started.complete();
          return response.future;
        }),
      );
      final wakeups = Wakeups();
      final f = await fixture(provider: provider, wakeups: wakeups);
      final job = ((await f.generation())['generation'] as Row)['id'] as String;
      final call = wakeups.calls.singleWhere(
        (c) => f.store.rows['worker_dispatches']![c['id']]!['targetId'] == job,
      );
      final work = f.worker.dispatch(
        call['id'] as String,
        call['proof'] as String,
      );
      await started.future;
      final running = f.store.rows['generation_jobs']![job]!;
      final dispatch = f.store.rows['worker_dispatches']![call['id']]!;
      expect(
        DateTime.parse(
          running['leaseUntil'] as String,
        ).difference(f.clock.call()),
        limits.glmGenerationLease,
      );
      expect(
        DateTime.parse(
          dispatch['leaseUntil'] as String,
        ).difference(f.clock.call()),
        limits.glmDispatchLease,
      );
      f.clock.advance(121);
      expect(
        (await f.worker.dispatch(
          call['id'] as String,
          call['proof'] as String,
        ))['duplicate'],
        isTrue,
      );
      await f.worker.generate(job);
      expect(requests, 1);
      f.clock.advance(160);
      await f.worker.generate(job);
      expect(
        f.store.rows['generation_jobs']![job]!['failureCategory'],
        'indeterminate',
      );
      response.complete(
        http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': ai.creationReferenceJson},
              },
            ],
          }),
          200,
        ),
      );
      await work;
      expect(requests, 1);
      expect(f.store.rows['generation_jobs']![job]!['status'], 'failed');
      expect(f.store.rows['spec_drafts'], isNull);
    },
  );

  test(
    'hourly recovery plans/schedules jobs without awaiting a provider and preserves future reminders',
    () async {
      final provider = ScriptProvider(), wakeups = Wakeups();
      final f = await fixture(provider: provider, wakeups: wakeups);
      await f.generation();
      await f.worker.reconcile();
      expect(provider.calls, isEmpty);
      expect(wakeups.calls, isNotEmpty);
    },
  );
  test(
    'reminder execution rechecks the current assignee and skips revoked recipients',
    () async {
      final f = await fixture();
      await f.save(spec.starterTemplates()['chores']!, 0, null, 'd');
      final v = await f.publish(1, null, 'p', enabled: ['dueReminder']);
      await base.join(f.service, 'bob', 11);
      await base.join(f.service, 'carol', 12);
      final out = await base.run(
        f.service,
        'alice',
        base.action('chore', v, 'addChore', {
          'data': {
            'title': 'Chore',
            'status': 'Open',
            'dueAt': f.clock.value
                .add(const Duration(hours: 1, minutes: 1))
                .toIso8601String(),
          },
        }),
      );
      final record = out['recordId'] as String;
      await base.run(
        f.service,
        'alice',
        base.action(
          'assign-bob',
          v,
          'assignChore',
          {'value': 'bob'},
          record: record,
          revision: 1,
        ),
      );
      await f.worker.reminders();
      // Change assignee after planning; the eligible recipient is resolved now.
      await base.run(
        f.service,
        'alice',
        base.action(
          'assign-carol',
          v,
          'assignChore',
          {'value': 'carol'},
          record: record,
          revision: 2,
        ),
      );
      f.clock.advance();
      await f.worker.reminders();
      expect(
        (await f.service.execute('bob', {'op': 'spec.inbox'}))['items'],
        isEmpty,
      );
      expect(
        (await f.service.execute('carol', {'op': 'spec.inbox'}))['items'],
        hasLength(1),
      );
      await f.service.execute('alice', {
        'op': 'setGrant',
        'appId': 'app',
        'actorId': 'carol',
        'role': null,
        'expectedRevision': 1,
        'operationId': 'revoke-carol',
      });
      expect(
        (await f.service.execute('carol', {'op': 'spec.inbox'}))['items'],
        isEmpty,
      );
    },
  );
  test(
    'revoking the approving builder suppresses a persisted reminder even when recipients retain access',
    () async {
      final f = await fixture();
      final definition = spec.starterTemplates()['chores']!;
      await f.save(definition, 0, null, 'd');
      final first = await f.publish(1, null, 'p');
      await base.join(f.service, 'bob', 21, role: 'builder');
      await f.service.execute('bob', {
        'op': 'spec.saveDraft',
        'appId': 'app',
        'expectedRevision': 0,
        'expectedVersionId': first,
        'operationId': 'bob-d',
        'spec': definition.toJson(),
      });
      final version = await f.publish(
        1,
        first,
        'bob-p',
        enabled: ['dueReminder'],
        actor: 'bob',
      );
      final out = await base.run(
        f.service,
        'alice',
        base.action('chore', version, 'addChore', {
          'data': {
            'title': 'Task',
            'status': 'Open',
            'dueAt': f.clock.value
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        }),
      );
      await base.run(
        f.service,
        'alice',
        base.action(
          'assign',
          version,
          'assignChore',
          {'value': 'alice'},
          record: out['recordId'] as String,
          revision: 1,
        ),
      );
      await f.service.execute('alice', {
        'op': 'setGrant',
        'appId': 'app',
        'actorId': 'bob',
        'role': 'viewer',
        'expectedRevision': 1,
        'operationId': 'demote-bob',
      });
      await f.worker.reminders();
      expect(
        f.store.rows['automation_runs']!.values.single['status'],
        'suppressed',
      );
      expect(f.store.rows['notification_batches'], isNull);
    },
  );
  test(
    '500 active claimants deliver in one atomic private batch under Free transaction limits',
    () async {
      final store = CountingStore();
      final actual = await fixture(store: store);
      await actual.save(spec.starterTemplates()['volunteer']!, 0, null, 'd');
      final v = await actual.publish(1, null, 'p', enabled: ['shiftReminder']);
      final out = await base.run(
        actual.service,
        'alice',
        base.action('shift', v, 'addShift', {
          'data': {
            'title': 'Shift',
            'startsAt': actual.clock.value
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
          'capacity': 500,
        }),
      );
      final pool = store.rows['spec_pools']!.values.single;
      final poolId = pool[r'$id'] as String;
      String identity(String kind, List<String> parts) =>
          '$kind${sha256.convert(utf8.encode(jsonEncode(parts))).toString().substring(0, 32)}';
      for (var i = 0; i < 500; i++) {
        final actor = 'claimant-$i';
        // Synthetic imported state: ordinary sharing admission is separately
        // bounded. The legacy runtime fanout must still be atomic at its cap.
        await store.create('memberships', identity('m', ['ws', actor]), {
          'workspaceId': 'ws',
          'actorId': actor,
          'active': true,
          'role': 'member',
          'revision': 1,
        });
        await store.create('grants', identity('g', ['app', actor]), {
          'workspaceId': 'ws',
          'appId': 'app',
          'actorId': actor,
          'role': 'member',
          'revision': 1,
          'revoked': false,
        });
        await store.create('spec_claims', identity('c', [poolId, actor]), {
          'workspaceId': 'ws',
          'appId': 'app',
          'poolId': poolId,
          'actorId': actor,
          'active': true,
          'createdAt': actual.clock.value.toIso8601String(),
          'updatedAt': actual.clock.value.toIso8601String(),
        });
      }
      await store.update('spec_pools', poolId, {'allocated': 500});
      await actual.worker.reminders();
      expect(store.rows['notification_batches']!.length, 1);
      expect(
        jsonDecode(
          store.rows['notification_batches']!.values.single['recipientIdsJson']
              as String,
        ),
        hasLength(500),
      );
      expect(
        store.rows['automation_runs']!.values.single['recipientCount'],
        500,
      );
      expect(store.largest, lessThanOrEqualTo(100));
      expect(
        (await actual.service.execute('claimant-499', {
          'op': 'spec.inbox',
        }))['items'],
        hasLength(1),
      );
      expect(out['revision'], 1);
    },
  );
  test(
    'five reminder write failures exhaust a bounded retry budget without partial notification success',
    () async {
      final store = CountingStore();
      final actual = await fixture(store: store);
      await actual.save(spec.dailyPlannerTemplate(), 0, null, 'd');
      final v = await actual.publish(1, null, 'p', enabled: ['taskReminder']);
      await actual.task(v, 'due', date: actual.clock.value.toIso8601String());
      for (var i = 0; i < 5; i++) {
        store.failBatch = true;
        await actual.worker.reminders();
        actual.clock.advance();
      }
      expect(store.rows['notification_batches'], isNull);
      expect(store.rows['automation_runs']!.values.single['status'], 'failed');
      expect(store.rows['automation_runs']!.values.single['attempts'], 5);
      await actual.worker.reminders();
      expect(store.rows['automation_runs']!.values.single['attempts'], 5);
    },
  );
  test(
    'a provider job loses authority after builder demotion and its author cannot replay the mutation receipt',
    () async {
      final provider = ScriptProvider()
        ..answers.add(answer(ai.creationReferenceJson));
      final f = await fixture(provider: provider);
      await f.save(spec.starterTemplates()['reading']!, 0, null, 'd');
      final v = await f.publish(1, null, 'p');
      await base.join(f.service, 'bob', 32, role: 'builder');
      final command = {
        'op': 'spec.generate',
        'appId': 'app',
        'operationId': 'bob-gen',
        'expectedRevision': 0,
        'expectedVersionId': v,
        'request': 'Improve the book app',
        'startFromScratch': false,
      };
      final job =
          ((await f.service.execute('bob', command))['generation'] as Row)['id']
              as String;
      await f.service.execute('alice', {
        'op': 'setGrant',
        'appId': 'app',
        'actorId': 'bob',
        'role': 'viewer',
        'expectedRevision': 1,
        'operationId': 'demote',
      });
      await f.worker.generate(job);
      expect(provider.calls, isEmpty);
      expect(f.store.rows['generation_jobs']![job]!['status'], 'stale');
      await base.error(() => f.service.execute('bob', command), 'forbidden');
      expect(
        ((await f.service.execute('bob', {
              'op': 'spec.getApp',
              'appId': 'app',
            }))['app']
            as Row)['generation'],
        isNull,
      );
    },
  );
  test(
    'the rolling 30-per-day generation quota is reserved before a job or receipt is written',
    () async {
      final f = await fixture(provider: ScriptProvider());
      final limits = f.store.rows['actor_limits']!.values.single;
      await f.store.update('actor_limits', limits[r'$id'] as String, {
        'generationTimesJson': jsonEncode(
          List.filled(30, f.clock.value.millisecondsSinceEpoch),
        ),
      });
      await base.error(() => f.generation(), 'quota_exceeded');
      expect(f.store.rows['generation_jobs'], isNull);
      expect(await f.store.get('receipts', 'generate'), isNull);
    },
  );
  test(
    'worker schema keeps all state private and uses lossless instants plus Cloud double projections',
    () {
      final schema = jsonDecode(File('schema.json').readAsStringSync()) as Row;
      final tables = (schema['tables'] as List).cast<Row>();
      for (final name in [
        'generation_jobs',
        'generation_sessions',
        'worker_leases',
        'worker_dispatches',
        'automations',
        'enrollments',
        'automation_runs',
        'notification_batches',
        'notification_reads',
      ]) {
        final table = tables.singleWhere((t) => t['tableId'] == name);
        expect(table['permissions'], isEmpty);
        expect(table['rowSecurity'], true);
        for (final column in (table['columns'] as List).cast<Row>().where(
          (c) =>
              (c['key'] as String).endsWith('At') || c['key'] == 'leaseUntil',
        )) {
          expect(column['type'], 'varchar');
          expect(column['size'], 64);
        }
      }
      final values =
          tables.singleWhere((t) => t['tableId'] == 'spec_values')['columns']
              as List;
      expect(
        values.singleWhere((c) => c['key'] == 'numberValue')['type'],
        'double',
      );
      expect(
        values.singleWhere((c) => c['key'] == 'timestampValue')['type'],
        'varchar',
      );
    },
  );
  test(
    'only two provider leases can run, independent actors retain distinct private candidates',
    () async {
      final gates = <Completer<ai.AiResult>>[],
          signals = <Completer<void>>[Completer<void>(), Completer<void>()];
      final provider = ScriptProvider()
        ..paused = () {
          final gate = Completer<ai.AiResult>();
          gates.add(gate);
          signals[gates.length - 1].complete();
          return gate.future;
        };
      final f = await fixture(provider: provider);
      await f.save(spec.starterTemplates()['reading']!, 0, null, 'd');
      final v = await f.publish(1, null, 'p');
      await base.join(f.service, 'bob', 41, role: 'builder');
      await base.join(f.service, 'carol', 42, role: 'builder');
      final ids = <String>[];
      for (final actor in ['alice', 'bob', 'carol']) {
        final result = await f.service.execute(actor, {
          'op': 'spec.generate',
          'appId': 'app',
          'operationId': 'gen-$actor',
          'expectedRevision': actor == 'alice' ? 1 : 0,
          'expectedVersionId': v,
          'request': 'Rename the title',
          'startFromScratch': false,
        });
        ids.add((result['generation'] as Row)['id'] as String);
      }
      final first = f.worker.generate(ids[0]);
      await signals[0].future;
      final second = f.worker.generate(ids[1]);
      await signals[1].future;
      await f.worker.generate(ids[2]);
      expect(provider.calls.length, 2);
      expect(f.store.rows['generation_jobs']![ids[2]]!['attempts'], 0);
      for (final gate in gates)
        gate.complete(
          answer(
            '{"patches":[{"type":"RenameField","collectionId":"books","fieldId":"title","label":"Book title"}]}',
          ),
        );
      await Future.wait([first, second]);
      provider.paused = null;
      provider.answers.add(answer('{"patches":[]}'));
      await f.worker.generate(ids[2]);
      expect(provider.calls.length, 3);
      final drafts = f.store.rows['spec_drafts']!.values.toList();
      expect(drafts, hasLength(3));
      expect(drafts.map((d) => d['actorId']).toSet(), {
        'alice',
        'bob',
        'carol',
      });
      for (final id in ids)
        expect(
          f.store.rows['generation_jobs']![id]!['status'],
          'preview ready',
        );
    },
  );
  test(
    'job, author quota and mutation receipt roll back together and lost commit response recovers one job',
    () async {
      final f = await fixture(provider: ScriptProvider());
      f.store.failBeforeCommit = true;
      await expectLater(f.generation(), throwsA(isA<RestException>()));
      f.store.failBeforeCommit = false;
      expect(f.store.rows['generation_jobs'], isNull);
      expect(await f.store.get('receipts', 'generate'), isNull);
      expect(
        f.store.rows['actor_limits']!.values.single['activeGenerationJobId'],
        isNull,
      );
      f.store.loseCommitResponse = true;
      await expectLater(f.generation(), throwsA(isA<RestException>()));
      final response = await f.generation();
      expect(response['generation'], isA<Row>());
      expect(await f.generation(), response);
      expect(f.store.rows['generation_jobs']!.length, 1);
      expect(
        jsonDecode(
          f.store.rows['actor_limits']!.values.single['generationTimesJson']
              as String,
        ),
        hasLength(1),
      );
    },
  );
  test(
    'Appwrite wakeup transport sends an asynchronous proof envelope using only the injected execution key',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = Completer<Row>();
      final sub = server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Row;
        seen.complete({
          'method': request.method,
          'path': request.uri.path,
          'body': body,
          'key': request.headers.value('X-Appwrite-Key'),
          'jwt': request.headers.value('X-Appwrite-JWT'),
          'project': request.headers.value('X-Appwrite-Project'),
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({r'$id': 'execution1'}));
        await request.response.close();
      });
      final scheduler = AppwriteWorkerWakeups(
        Uri.parse('http://127.0.0.1:${server.port}/v1'),
        'project',
        'private-worker',
        'injected-only',
      );
      try {
        expect(
          await scheduler.schedule(
            dispatchId: 'dispatch',
            proof: 'A' * 43,
            at: DateTime.now().toUtc(),
          ),
          'execution1',
        );
        final request = await seen.future;
        expect(request['method'], 'POST');
        expect(request['path'], '/v1/functions/private-worker/executions');
        expect(request['key'], 'injected-only');
        expect(request['jwt'], isNull);
        expect(request['project'], 'project');
        final body = request['body'] as Row;
        expect(body['async'], true);
        expect(body['method'], 'POST');
        expect(jsonDecode(body['body'] as String), {
          'dispatchId': 'dispatch',
          'proof': 'A' * 43,
        });
        expect(
          body.keys,
          unorderedEquals(['body', 'async', 'method', 'headers']),
        );
      } finally {
        scheduler.close();
        await sub.cancel();
        await server.close(force: true);
      }
    },
  );
  test(
    'private transport gates reject user identity, wrong function, method and trigger; body proof remains required',
    () {
      final env = {
        'APPWRITE_FUNCTION_ID': 'worker',
        'PLATFORM_WORKER_FUNCTION_ID': 'worker',
      };
      final headers = {
        'x-appwrite-key': 'ephemeral',
        'x-appwrite-trigger': 'http',
      };
      expect(privateWorkerRequest(env, headers, 'POST'), true);
      for (final forged in [
        {'x-appwrite-user-jwt': 'jwt'},
        {'x-appwrite-user-id': 'alice'},
        {'x-appwrite-trigger': 'event'},
        {'x-appwrite-key': ''},
      ])
        expect(
          privateWorkerRequest(env, {...headers, ...forged}, 'POST'),
          false,
        );
      expect(
        privateWorkerRequest(
          {...env, 'APPWRITE_FUNCTION_ID': 'core'},
          headers,
          'POST',
        ),
        false,
      );
      expect(privateWorkerRequest(env, headers, 'GET'), false);
    },
  );
  test(
    'actual-work delayed wakeups round up to a future minute and immediate work has no fabricated schedule receipt',
    () {
      final now = DateTime.utc(2030, 1, 1, 10, 0, 30);
      final scheduler = AppwriteWorkerWakeups(
        Uri.parse('https://example.test/v1'),
        'project',
        'worker',
        'ephemeral',
        clock: () => now,
      );
      try {
        final immediate = scheduler.body('id', 'proof', now);
        expect(immediate.containsKey('scheduledAt'), false);
        expect(immediate['async'], true);
        final delayed = scheduler.body(
          'id',
          'proof',
          now.add(const Duration(seconds: 1)),
        );
        expect(delayed['scheduledAt'], '2030-01-01T10:02:00.000Z');
        expect(
          (jsonDecode(delayed['body'] as String) as Map).keys,
          unorderedEquals(['dispatchId', 'proof']),
        );
      } finally {
        scheduler.close();
      }
    },
  );
}
