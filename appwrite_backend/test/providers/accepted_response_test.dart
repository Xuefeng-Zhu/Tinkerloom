import 'dart:io';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../lib/providers/provider.dart';
import '../../lib/service.dart';
import '../memory_store.dart';

class _DenyNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Network disabled in provider response tests');
}

void main() {
  late HttpOverrides? previous;
  setUpAll(() {
    previous = HttpOverrides.current;
    HttpOverrides.global = _DenyNetwork();
  });
  tearDownAll(() => HttpOverrides.global = previous);

  test(
    'generic provider 202 means unknown completion, never retryable',
    () async {
      var requests = 0;
      final provider = ChatCompletionProvider(
        Uri.parse('https://api.tokenfactory.nebius.com/v1'),
        'nvidia/nemotron-3-super-120b-a12b',
        'fixture-only',
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response('fixture body must not be propagated', 202);
        }),
      );
      await expectLater(
        provider.generate(
          'A reading list',
          starterTemplates()['reading']!,
          editing: false,
        ),
        throwsA(
          isA<AiResponseException>()
              .having((e) => e.kind, 'category', 'indeterminate')
              .having((e) => e.statusCode, 'status', 202)
              .having((e) => e.retryable, 'retryable', false)
              .having(
                (e) => e.message,
                'safe message',
                isNot(contains('fixture body')),
              ),
        ),
      );
      expect(requests, 1);
    },
  );

  test(
    '202 makes worker job terminal and cannot cause another dispatch',
    () async {
      var requests = 0;
      final provider = ChatCompletionProvider(
        Uri.parse('https://api.tokenfactory.nebius.com/v1'),
        'nvidia/nemotron-3-super-120b-a12b',
        'fixture-only',
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response('accepted', 202);
        }),
      );
      final memory = MemoryStore();
      final service = PlatformService(memory, aiProvider: provider);
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
      final queued = await service.execute('alice', {
        'op': 'spec.generate',
        'appId': 'app',
        'operationId': 'generate',
        'expectedRevision': 0,
        'expectedVersionId': null,
        'request': 'A reading list',
        'startFromScratch': true,
      });
      final jobId = (queued['generation'] as Row)['id'] as String;
      final initialDispatches = memory.rows['worker_dispatches']?.length ?? 0;
      final worker = WorkerEngine(service);
      await worker.generate(jobId);
      final job = memory.rows['generation_jobs']![jobId]!;
      expect(job['status'], 'failed');
      expect(job['failureCategory'], 'indeterminate');
      expect(job['attempts'], 1);
      expect(memory.rows['worker_dispatches']?.length ?? 0, initialDispatches);
      await worker.generate(jobId);
      expect(requests, 1);
      expect(memory.rows['generation_jobs']![jobId]!['attempts'], 1);
    },
  );
}
