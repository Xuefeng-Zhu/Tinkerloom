import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../lib/providers/provider.dart';
import '../../lib/service.dart';
import '../memory_store.dart';

class _DenyNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Network disabled in provider budget tests');
}

void main() {
  late HttpOverrides? previous;
  setUpAll(() {
    previous = HttpOverrides.current;
    HttpOverrides.global = _DenyNetwork();
  });
  tearDownAll(() => HttpOverrides.global = previous);

  test(
    'uncertain and quota provider failures stop the real worker after one send',
    () async {
      for (final scenario in [
        '202',
        '408',
        '425',
        '429',
        '500',
        '503',
        'timeout',
        'transport',
        'socket',
        'envelope429',
        'envelope503',
        'finish_error',
        'oversize',
        'invalid_envelope',
        'empty_envelope',
        'missing_content',
        'content_filter',
        'truncated',
      ]) {
        var sends = 0;
        final provider = ChatCompletionProvider(
          Uri.parse('https://provider.invalid/v1'),
          'fixture-model',
          'fixture-only',
          generationTimeout: const Duration(milliseconds: 250),
          clientFactory: () => MockClient((_) async {
            sends++;
            if (scenario == 'timeout') {
              await Future<void>.delayed(const Duration(milliseconds: 400));
              return http.Response('late', 200);
            }
            if (scenario == 'transport')
              throw http.ClientException('private details');
            if (scenario == 'socket')
              throw const SocketException('private details');
            if (scenario == 'envelope429' || scenario == 'envelope503') {
              final code = scenario == 'envelope429' ? 429 : 503;
              return http.Response(
                jsonEncode({
                  'error': {'code': code, 'message': 'private details'},
                }),
                200,
              );
            }
            if (scenario == 'finish_error')
              return http.Response(
                jsonEncode({
                  'choices': [
                    {
                      'finish_reason': 'error',
                      'message': {'content': ''},
                    },
                  ],
                }),
                200,
              );
            if (scenario == 'oversize') return http.Response('x' * 400000, 200);
            if (scenario == 'invalid_envelope')
              return http.Response('not-json', 200);
            if (scenario == 'empty_envelope') return http.Response('{}', 200);
            if (scenario == 'missing_content' ||
                scenario == 'content_filter' ||
                scenario == 'truncated') {
              final reason = scenario == 'missing_content'
                  ? 'stop'
                  : scenario == 'content_filter'
                  ? 'content_filter'
                  : 'length';
              return http.Response(
                jsonEncode({
                  'choices': [
                    {
                      'finish_reason': reason,
                      'message': {'content': ''},
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response('private details', int.parse(scenario));
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
        final worker = WorkerEngine(service);
        await worker.generate(jobId);
        final job = memory.rows['generation_jobs']![jobId]!;
        final category = switch (scenario) {
          '429' || 'envelope429' => 'rate_limited',
          'content_filter' => 'completion_stopped',
          'truncated' => 'truncated',
          _ => 'indeterminate',
        };
        expect(job['status'], 'failed', reason: scenario);
        expect(job['failureCategory'], category, reason: scenario);
        expect(job['attempts'], 1, reason: scenario);
        expect(
          job['diagnostics'],
          isNot(contains('private details')),
          reason: scenario,
        );
        await worker.generate(jobId);
        expect(sends, 1, reason: scenario);
        expect(
          memory.rows['generation_jobs']![jobId]!['attempts'],
          1,
          reason: scenario,
        );
      }
    },
  );
}
