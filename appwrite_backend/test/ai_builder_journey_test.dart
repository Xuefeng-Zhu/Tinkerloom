// Offline integration rehearsal. This proves no real provider compatibility.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../lib/providers/provider.dart' as ai;
import '../lib/service.dart';
import 'memory_store.dart';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('The AI journey test forbids real network calls');
}

void main() {
  test(
    'synthetic provider response creates an isolated draft before explicit publication',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = _NoNetwork();
      addTearDown(() => HttpOverrides.global = previousOverrides);
      var calls = 0;
      final provider = ai.ChatCompletionProvider(
        Uri.parse('https://api.tokenfactory.nebius.com/v1'),
        'nvidia/nemotron-3-super-120b-a12b',
        'fixture-key-only',
        clientFactory: () => MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], 'nvidia/nemotron-3-super-120b-a12b');
          expect((body['response_format'] as Map)['type'], 'json_schema');
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': ai.creationReferenceJson},
                },
              ],
              'usage': {'completion_tokens': 1},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final store = MemoryStore();
      final service = PlatformService(store, aiProvider: provider);
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
        'request': 'A reading list to track books',
        'startFromScratch': true,
      });
      final job = (queued['generation'] as Row)['id'] as String;
      expect(calls, 0);
      await WorkerEngine(service).generate(job);
      expect(calls, 1);
      expect(store.rows['generation_jobs']![job]!['status'], 'preview ready');
      final fetched = await service.execute('alice', {
        'op': 'spec.getApp',
        'appId': 'app',
      });
      final app = fetched['app'] as Row;
      expect(app['version'], isNull);
      final draft = app['draft'] as Row;
      final revision = draft['revision'] as int;
      final review =
          (await service.execute('alice', {
                'op': 'spec.review',
                'appId': 'app',
                'expectedRevision': revision,
                'enabledRuleIds': [],
                'activateExistingRecordIds': [],
              }))['review']
              as Row;
      final published = await service.execute('alice', {
        'op': 'spec.publish',
        'appId': 'app',
        'operationId': 'publish',
        'expectedRevision': revision,
        'expectedVersionId': null,
        'candidateHash': review['candidateHash'],
        'reviewHash': review['reviewHash'],
        'enabledRuleIds': [],
        'activateExistingRecordIds': [],
      });
      final version =
          ((published['app'] as Row)['version'] as Row)['id'] as String;
      final outcome =
          (await service.execute('alice', {
                'op': 'spec.execute',
                'appId': 'app',
                'versionId': version,
                'operationId': 'record',
                'actionId': 'addBook',
                'input': {
                  'data': {'title': 'Synthetic book', 'status': 'To read'},
                },
              }))['outcome']
              as Row;
      final record =
          (await service.execute('alice', {
                'op': 'spec.getRecord',
                'appId': 'app',
                'versionId': version,
                'recordId': outcome['recordId'],
              }))['record']
              as Row;
      expect(jsonEncode(record), contains('Synthetic book'));
      expect(calls, 1);
    },
  );
}
