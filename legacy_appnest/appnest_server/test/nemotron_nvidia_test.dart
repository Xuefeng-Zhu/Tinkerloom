import 'dart:convert';

import 'package:appnest_server/src/modules/builder/nemotron_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_routes.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

String _publicPage(String model) =>
    '''
<html><head><script>window.initialState = {"trialCredits":999};</script></head>
<body><h1>${model.split('/').last}</h1>
<p>Start building with a free API endpoint.</p>
<h2>Model Availability</h2><span>Free Endpoint</span><span>Available</span>
</body></html>
''';

void main() {
  final nvidia = nemotronRoute('nvidia');
  final openrouter = nemotronRoute('openrouter');
  final scenario = NemotronScenario(
    id: 'unsupported-nvidia-test',
    operation: 'unsupported',
    prompt: 'Execute arbitrary code.',
    baseline: starterTemplates()['reading']!,
  );
  Map<String, dynamic> checkpoint({
    String provider = 'nvidia',
    List<String>? models,
  }) => newNemotronCheckpoint(
    provider: provider,
    models: models ?? nemotronRoute(provider).models.take(2).toList(),
    scenarios: [scenario],
    catalog: const [],
    source: const {'commit': 'test', 'contractSourceSha256': 'fixed'},
  );

  test(
    'provider routes require exact distinct model IDs and isolate credentials',
    () {
      expect(nvidia.base, 'https://integrate.api.nvidia.com/v1');
      expect(nvidia.credentialName, 'NVIDIA_API_KEY');
      expect(nvidia.models, nvidiaNemotronModels);
      expect(openrouter.base, 'https://openrouter.ai/api/v1');
      expect(openrouter.credentialName, 'OPENROUTER_API_KEY');
      expect(openrouter.outputDirectory, isNot(nvidia.outputDirectory));
      validateNemotronModelSelection(nvidiaNemotronModels.toList(), nvidia);
      for (final name in ['NVIDIA', 'nvidia/', 'unknown']) {
        expect(() => nemotronRoute(name), throwsFormatException);
      }
      for (final models in <List<String>>[
        [],
        [nvidia.models.first, nvidia.models.first],
        [nvidia.models.first.toUpperCase()],
        ['${nvidia.models.first}:free'],
        [freeNemotronModels.first],
        ['${nvidia.models.first}-custom'],
      ]) {
        expect(
          () => validateNemotronModelSelection(models, nvidia),
          throwsFormatException,
        );
      }
      expect(
        () => validateNemotronModelSelection(nvidia.models, openrouter),
        throwsFormatException,
      );
    },
  );

  test('public model pages require visible exact free-endpoint markers', () {
    for (final model in nvidia.models) {
      final entry = validateNvidiaFreeEndpointPage(model, _publicPage(model));
      expect(entry['id'], model);
      expect(entry['freeEndpoint'], isTrue);
      expect(entry['pricingVerified'], isFalse);
      expect(entry['sourceUrl'], 'https://build.nvidia.com/$model');
      expect(entry.containsKey('pricing'), isFalse);
    }
    final model = nvidia.models.first;
    final page = _publicPage(model);
    for (final invalid in [
      page.replaceAll(
        'Start building with a free API endpoint.',
        'Start building with an API endpoint.',
      ),
      page.replaceAll('Free Endpoint', 'Paid Endpoint'),
      page.replaceAll('Available', 'Unavailable'),
      page.replaceAll(model.split('/').last, 'different-model'),
      page.replaceAll(
        'Start building with a free API endpoint.',
        'Start building with a free API endpoint',
      ),
      '<script>${model.split('/').last} Start building with a free API endpoint. Model Availability Free Endpoint Available</script>',
      '<STYLE>${model.split('/').last} Start building with a free API endpoint. Model Availability Free Endpoint Available</STYLE>',
      '${model.split('/').last} <script>Start building with a free API endpoint. Model Availability Free Endpoint Available</script>',
    ]) {
      expect(
        () => validateNvidiaFreeEndpointPage(model, invalid),
        throwsFormatException,
      );
    }
  });

  test(
    'public catalog checks exact page URLs without authorization or redirects',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.followRedirects, isFalse);
        expect(request.headers.containsKey('Authorization'), isFalse);
        requests.add(request.url.toString());
        final model = nvidia.models[requests.length - 1];
        expect(request.url.toString(), 'https://build.nvidia.com/$model');
        return http.Response(_publicPage(model), 200);
      });
      final entries = await readNvidiaNemotronCatalog(client, nvidia.models);
      expect(entries.map((entry) => entry['id']), nvidia.models);
      expect(requests, hasLength(4));
    },
  );

  test('public catalog rejects failed HTTP status and never follows redirected pages', () async {
    for (final status in [301, 302, 401, 429, 500]) {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          'private-provider-detail',
          status,
          headers: {'location': 'https://other.test/paid'},
        );
      });
      await expectLater(
        readNvidiaNemotronCatalog(client, [nvidia.models.first]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'safe error',
            isNot(contains('private-provider-detail')),
          ),
        ),
      );
      expect(requests, 1);
    }
  });

  test(
    'catalog and access reject unrecognized models before any network dispatch',
    () async {
      final client = MockClient(
        (_) async => fail('No network request expected'),
      );
      await expectLater(
        readNvidiaNemotronCatalog(client, [freeNemotronModels.first]),
        throwsFormatException,
      );
      await expectLater(
        readNvidiaNemotronAccess(client, 'synthetic-key', ['other/model']),
        throwsFormatException,
      );
    },
  );

  test('authenticated NVIDIA model listing uses its provided key and keeps quota unknown', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://integrate.api.nvidia.com/v1/models',
      );
      expect(request.followRedirects, isFalse);
      expect(request.headers['Authorization'], 'Bearer synthetic-nvidia-key');
      expect(request.body, isEmpty);
      return http.Response(
        jsonEncode({
          'data': [
            for (final model in nvidia.models) {'id': model},
          ],
          'balance': 'private-account-balance',
          'label': 'private-account-label',
          'free_model_daily_requests': {
            'used': 0,
            'limit': 999,
            'remaining': 999,
          },
        }),
        200,
      );
    });
    final access = await readNvidiaNemotronAccess(
      client,
      'synthetic-nvidia-key',
      nvidia.models,
    );
    expect(access, {
      'authenticatedCatalogVerified': true,
      'accountLimitsKnown': false,
      'freeRequests': null,
      'completionCallsMade': false,
    });
    expect(jsonEncode(access), isNot(contains('private-account')));
    expect(jsonEncode(access), isNot(contains('synthetic-nvidia-key')));
  });

  test(
    'authenticated listing requires every exact selected NVIDIA ID',
    () async {
      for (final data in <Object>[
        [],
        [
          {'id': freeNemotronModels.first},
        ],
        [
          {'id': nvidia.models.first.toUpperCase()},
        ],
        [
          {'id': nvidia.models.first},
        ],
        'invalid-list',
      ]) {
        final client = MockClient(
          (_) async => http.Response(jsonEncode({'data': data}), 200),
        );
        await expectLater(
          readNvidiaNemotronAccess(
            client,
            'synthetic-key',
            nvidia.models.take(2).toList(),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'authenticated failures expose safe status without provider content or key',
    () async {
      for (final status in [302, 401, 403, 429, 500]) {
        final client = MockClient((request) async {
          expect(request.followRedirects, isFalse);
          return http.Response(
            'private-provider-detail synthetic-nvidia-key',
            status,
          );
        });
        await expectLater(
          readNvidiaNemotronAccess(client, 'synthetic-nvidia-key', [
            nvidia.models.first,
          ]),
          throwsA(
            isA<AiResponseException>()
                .having((e) => e.statusCode, 'HTTP status', status)
                .having(
                  (e) => e.message,
                  'safe message',
                  isNot(contains('private-provider-detail')),
                )
                .having(
                  (e) => e.message,
                  'no key',
                  isNot(contains('synthetic-nvidia-key')),
                ),
          ),
        );
      }
    },
  );

  test('malformed authenticated JSON never escapes in diagnostics', () async {
    final client = MockClient(
      (_) async => http.Response('private-provider-detail', 200),
    );
    await expectLater(
      readNvidiaNemotronAccess(client, 'synthetic-key', [nvidia.models.first]),
      throwsA(
        isA<FormatException>().having(
          (e) => e.toString(),
          'safe diagnostic',
          isNot(contains('private-provider-detail')),
        ),
      ),
    );
  });

  test(
    'NVIDIA guidance posts fixed nonstreaming thinking-off requests to NVIDIA',
    () async {
      final provider = ChatCompletionProvider(
        Uri.parse(nvidia.base),
        nvidia.models.first,
        'synthetic-nvidia-key',
        nvidiaNemotronEvaluation: true,
      );
      final guidance = NemotronScenario(
        id: 'guidance-actionable-nvidia',
        operation: 'guidance',
        prompt: 'Make notes with titles and a multiline body.',
        baseline: scenario.baseline,
      );
      final result = await invokeNemotronGuidance(
        provider,
        guidance,
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.toString(), '${nvidia.base}/chat/completions');
          expect(request.followRedirects, isFalse);
          expect(
            request.headers['Authorization'],
            'Bearer synthetic-nvidia-key',
          );
          expect(request.headers['Accept'], 'application/json');
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], nvidia.models.first);
          expect(body['stream'], isFalse);
          expect(body['chat_template_kwargs'], {'enable_thinking': false});
          expect(body['max_tokens'], 2048);
          for (final key in [
            'provider',
            'response_format',
            'reasoning',
            'plugins',
            'tools',
            'models',
          ]) {
            expect(body.containsKey(key), isFalse, reason: key);
          }
          expect(
            body['messages'].first['content'],
            contains('exactly those two keys'),
          );
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {
                    'content': '{"needsClarification":false,"questions":[]}',
                  },
                },
              ],
              'usage': {'prompt_tokens': 8, 'completion_tokens': 5},
            }),
            200,
          );
        }),
      );
      expect(result.provider, 'integrate.api.nvidia.com');
      expect(result.usage['completion_tokens'], 5);
      guidance.validate(parseAiOutput(result.text), null);
    },
  );

  test('checkpoints freeze provider, API base, models and transport profiles across resume', () {
    final original = checkpoint();
    expect(original['provider'], 'nvidia');
    expect(original['apiBase'], nvidia.base);
    expect(
      original['transportProfiles'][nvidia.models.first]['profile'],
      'nvidia-instruction-schema-thinking-off-v1',
    );
    validateNemotronResume(original, checkpoint());
    final other = checkpoint(provider: 'openrouter');
    expect(original['runFingerprint'], isNot(other['runFingerprint']));
    expect(
      () => validateNemotronResume(original, other),
      throwsFormatException,
    );
    for (final entry in {
      'provider': 'openrouter',
      'apiBase': openrouter.base,
    }.entries) {
      final modified = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
      modified[entry.key] = entry.value;
      expect(
        () => validateNemotronResume(modified, original),
        throwsFormatException,
      );
    }
    expect(
      () => checkpoint(models: [freeNemotronModels.first]),
      throwsFormatException,
    );
  });

  for (final status in [202, 429]) {
    test(
      'NVIDIA guidance preserves HTTP $status without consuming its body',
      () async {
        final provider = ChatCompletionProvider(
          Uri.parse(nvidia.base),
          nvidia.models.first,
          'synthetic-nvidia-key',
          nvidiaNemotronEvaluation: true,
        );
        var listened = false;
        final client = MockClient.streaming((request, stream) async {
          await stream.drain<void>();
          return http.StreamedResponse(
            Stream<List<int>>.multi((controller) {
              listened = true;
              controller.addError(
                StateError('Error bodies must not be consumed.'),
              );
              controller.close();
            }),
            status,
            headers: {'retry-after': '30'},
          );
        });
        final error = isA<AiResponseException>()
            .having((e) => e.statusCode, 'HTTP status', status)
            .having(
              (e) => e.kind,
              'kind',
              status == 202 ? 'indeterminate' : 'http_error',
            );
        await expectLater(
          invokeNemotronGuidance(provider, scenario, client: client),
          throwsA(
            status == 202
                ? error.having((e) => e.retryable, 'retryable', isFalse)
                : error.having(
                    (e) => e.retryAfter,
                    'retry-after',
                    const Duration(seconds: 30),
                  ),
          ),
        );
        expect(listened, isFalse);
      },
    );
  }

  test(
    'NVIDIA HTTP 202 pauses and explicit resume never repeats accepted work',
    () async {
      final saved = checkpoint();
      var calls = 0;
      NemotronEvaluationRunner runner(NemotronInvocation invoke) =>
          NemotronEvaluationRunner(
            checkpoint: saved,
            scenarios: [scenario],
            invoke: invoke,
            save: (_) async {},
            requestInterval: Duration.zero,
            delay: (_) async {},
          );
      await runner((_, _, _, _, _) async {
        calls++;
        throw const AiResponseException(
          'indeterminate',
          'Accepted asynchronous work.',
          statusCode: 202,
          retryable: false,
        );
      }).run();
      expect(calls, 1);
      expect(saved['status'], 'incomplete');
      expect(saved['operations'][0]['status'], 'indeterminate');
      expect(saved['operations'][0]['attempts'], hasLength(1));
      expect(saved['operations'][1]['attempts'], isEmpty);
      final resumed = <String>[];
      await runner((model, _, _, _, _) async {
        resumed.add(model);
        return AiResult(
          '{"unsupported":"AppNest cannot execute arbitrary code."}',
          'integrate.api.nvidia.com',
          model,
          {},
        );
      }).run();
      expect(resumed, [nvidia.models[1]]);
      expect(saved['operations'][0]['attempts'], hasLength(1));
      expect(saved['status'], 'incomplete');
    },
  );
}
