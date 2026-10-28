import 'dart:convert';

import 'package:appnest_server/src/modules/builder/nemotron_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_routes.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:serverpod/serverpod.dart' show Session;
import 'package:test/test.dart';

const _selected = [
  'moonshotai/kimi-k3',
  'z-ai/glm-5.3',
  'deepseek-ai/deepseek-v4.1-flash',
  'z-ai/glm-5.3-flash',
  'google/gemma-4-31b-it',
  'poolside/laguna-xs-2.1',
];

const _catalogPaths = {
  'moonshotai/kimi-k3': 'moonshotai/kimi-k3',
  'z-ai/glm-5.3': 'z-ai/glm-5-3',
  'deepseek-ai/deepseek-v4.1-flash': 'deepseek-ai/deepseek-v4.1-flash',
  'z-ai/glm-5.3-flash': 'z-ai/glm-5-3-flash',
  'google/gemma-4-31b-it': 'google/gemma-4-31b-it',
  'poolside/laguna-xs-2.1': 'poolside/laguna-xs-2.1',
};

const _newProfiles = {
  'z-ai/glm-5.3-flash': {
    'family': 'GLM',
    'profile': 'nvidia-glm-5.3-flash-instruction-schema-low-v1',
    'reasoning':
        'always enabled; low effort requested; previous thinking cleared',
    'requestOverrides': {
      'stream': false,
      'temperature': 0,
      'reasoning_effort': 'low',
      'chat_template_kwargs': {'clear_thinking': true},
    },
  },
  'google/gemma-4-31b-it': {
    'family': 'Gemma',
    'profile': 'nvidia-gemma-4-31b-it-instruction-schema-thinking-off-v1',
    'reasoning': 'thinking disabled',
    'requestOverrides': {
      'stream': false,
      'temperature': 0,
      'chat_template_kwargs': {'enable_thinking': false},
    },
  },
  'poolside/laguna-xs-2.1': {
    'family': 'Laguna',
    'profile': 'nvidia-laguna-xs-2.1-instruction-schema-default-v1',
    'reasoning': 'model default; no documented NVIDIA HTTP override sent',
    'requestOverrides': {'stream': false, 'temperature': 0},
  },
};

class _PasswordSession implements Session {
  @override
  final Map<String, String> passwords;
  _PasswordSession(this.passwords);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

String _page(String model) =>
    '''
<h1>${_catalogPaths[model]!.split('/').last}</h1>
<p>Start building with a free API endpoint.</p>
<h2>Model Availability</h2><span>Free Endpoint</span><span>Available</span>
''';

ChatCompletionProvider _provider(
  String model, {
  http.Client Function()? clientFactory,
}) => ChatCompletionProvider(
  Uri.parse(nvidiaEvaluationBase),
  model,
  'synthetic-nvidia-only-key',
  nvidiaModelEvaluation: true,
  clientFactory: clientFactory,
);

void _controls(String model, Map body) {
  expect(body['stream'], isFalse);
  expect(body.containsKey('response_format'), isFalse);
  for (final key in ['provider', 'models', 'plugins', 'tools', 'reasoning']) {
    expect(body.containsKey(key), isFalse, reason: '$model $key');
  }
  if (model == 'deepseek-ai/deepseek-v4.1-flash' ||
      model == 'poolside/laguna-xs-2.1') {
    expect(body.containsKey('reasoning_effort'), isFalse);
    expect(body.containsKey('chat_template_kwargs'), isFalse);
  } else if (model == 'google/gemma-4-31b-it') {
    expect(body.containsKey('reasoning_effort'), isFalse);
    expect(body['chat_template_kwargs'], {'enable_thinking': false});
  } else {
    expect(body['reasoning_effort'], 'low');
    if (model == 'z-ai/glm-5.3' || model == 'z-ai/glm-5.3-flash') {
      expect(body['chat_template_kwargs'], {'clear_thinking': true});
    } else {
      expect(body.containsKey('chat_template_kwargs'), isFalse);
    }
  }
}

void main() {
  final route = nemotronRoute('nvidia');
  final baseline = starterTemplates()['reading']!;
  final guidance = NemotronScenario(
    id: 'guidance-actionable-model-extension',
    operation: 'guidance',
    prompt: 'Create a personal notebook with title, body and add/edit forms.',
    baseline: baseline,
  );

  test(
    'comparison IDs stay opt-in except configured Flash; benchmark defaults stay fixed',
    () {
      expect(nvidiaComparisonModels, _selected);
      expect(route.models, nvidiaNemotronModels);
      expect(route.models, hasLength(4));
      expect(route.allowedModels.toSet(), {
        ...nvidiaNemotronModels,
        ..._selected,
      });
      validateNemotronModelSelection(_selected, route);
      for (final model in _selected) {
        expect(_provider(model).nvidiaEvaluation, isTrue);
        expect(
          () => ChatCompletionProvider(
            Uri.parse(nvidiaEvaluationBase),
            model,
            'synthetic-key',
            nvidiaNemotronEvaluation: true,
          ),
          throwsArgumentError,
        );
        expect(
          ChatCompletionProvider.configured(
            _PasswordSession({
              'AI_BASE_URL': nvidiaEvaluationBase,
              'AI_MODEL': model,
              'NVIDIA_API_KEY': 'synthetic-nvidia-only-key',
              'AI_API_KEY': 'synthetic-other-provider-key',
            }),
          ),
          model == 'z-ai/glm-5.3-flash'
              ? isA<ChatCompletionProvider>()
              : isNull,
        );
      }
      expect(
        () => validateNemotronModelSelection(
          _selected,
          nemotronRoute('openrouter'),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'configured Flash reuses its baseline create/edit/guidance contract',
    () {
      const model = 'z-ai/glm-5.3-flash';
      final configured = ChatCompletionProvider.configured(
        _PasswordSession({
          'AI_BASE_URL': nvidiaEvaluationBase,
          'AI_MODEL': model,
          'NVIDIA_API_KEY': 'synthetic-nvidia-only-key',
          'AI_API_KEY': 'synthetic-other-provider-key',
        }),
      )!;
      final evaluator = _provider(model);
      expect(configured.model, model);
      expect(configured.base, Uri.parse(nvidiaEvaluationBase));
      expect(configured.key, 'synthetic-nvidia-only-key');
      expect(configured.nvidiaModelEvaluation, isTrue);
      expect(configured.nvidiaNemotronEvaluation, isFalse);
      expect(configured.nemotronProfile, NvidiaNemotronProfile.baseline);
      expect(
        configured.transportProfile,
        'nvidia-glm-5.3-flash-instruction-schema-low-v1',
      );
      expect(configured.generationDeadline, const Duration(seconds: 90));
      for (final editing in [false, true]) {
        final authored = buildAiRequest(
          model,
          'A personal reading journal',
          baseline,
          editing: editing,
        );
        final before = jsonEncode(authored);
        final actual = configured.adaptRequestForTransport(
          authored,
          generation: true,
        );
        expect(
          jsonEncode(actual),
          jsonEncode(
            evaluator.adaptRequestForTransport(authored, generation: true),
          ),
        );
        expect(jsonEncode(authored), before);
        _controls(model, actual);
        expect(actual['max_tokens'], 8000);
        expect(actual['messages'][1], authored['messages'][1]);
        expect(
          actual['messages'][0]['content'],
          isNot(contains('nemotron-creation-checklist-v1')),
        );
        expect(
          actual['messages'][0]['content'],
          isNot(contains('appnest-creation-patch-v1')),
        );
        expect(
          actual['messages'][0]['content'],
          isNot(contains('creationPlanVersion')),
        );
      }
      final guidance = buildGuidanceRequest(
        model,
        'A personal reading journal',
      );
      final adapted = configured.adaptRequestForTransport(
        guidance,
        generation: false,
      );
      expect(
        jsonEncode(adapted),
        jsonEncode(
          evaluator.adaptRequestForTransport(guidance, generation: false),
        ),
      );
      _controls(model, adapted);
      expect(adapted['max_tokens'], 2048);
      expect(adapted['messages'], guidance['messages']);
    },
  );

  test(
    'configured Flash permits only the fixed recognized truncation allowance',
    () {
      const model = 'z-ai/glm-5.3-flash';
      final provider = ChatCompletionProvider.configured(
        _PasswordSession({
          'AI_BASE_URL': '$nvidiaEvaluationBase/',
          'AI_MODEL': model,
          'NVIDIA_API_KEY': 'synthetic-nvidia-only-key',
        }),
      )!;
      for (final entry in {
        <String>[]: 8000,
        ['Fix the form controls.']: 8000,
        ['AI output reached the token limit before finishing.']: 12000,
      }.entries) {
        final request = buildAiRequest(
          model,
          'A reading journal',
          baseline,
          editing: false,
          diagnostics: entry.key,
        );
        expect(
          provider.adaptRequestForTransport(
            request,
            generation: true,
          )['max_tokens'],
          entry.value,
        );
      }
      final edit = buildAiRequest(
        model,
        'Rename the journal',
        baseline,
        editing: true,
        diagnostics: ['AI output reached the token limit before finishing.'],
      );
      expect(
        provider.adaptRequestForTransport(edit, generation: true)['max_tokens'],
        8000,
      );
    },
  );

  test(
    'configured Flash isolates NVIDIA credentials and rejects missing values',
    () {
      const valid = {
        'AI_BASE_URL': nvidiaEvaluationBase,
        'AI_MODEL': 'z-ai/glm-5.3-flash',
        'NVIDIA_API_KEY': 'synthetic-nvidia-only-key',
        'AI_API_KEY': 'synthetic-other-provider-key',
      };
      for (final key in ['AI_BASE_URL', 'AI_MODEL', 'NVIDIA_API_KEY']) {
        final missing = {...valid}..remove(key);
        expect(
          ChatCompletionProvider.configured(_PasswordSession(missing)),
          isNull,
        );
        for (final empty in ['', '   ']) {
          expect(
            ChatCompletionProvider.configured(
              _PasswordSession({...valid, key: empty}),
            ),
            isNull,
          );
        }
      }
      expect(
        ChatCompletionProvider.configured(
          _PasswordSession({...valid}..remove('AI_API_KEY')),
        )!.key,
        'synthetic-nvidia-only-key',
      );
      final standard = ChatCompletionProvider.configured(
        _PasswordSession({
          ...valid,
          'AI_BASE_URL': 'https://example.invalid/v1',
        }),
      )!;
      expect(standard.key, 'synthetic-other-provider-key');
      expect(standard.nvidiaEvaluation, isFalse);
      expect(standard.generationDeadline, const Duration(seconds: 45));
      expect(
        ChatCompletionProvider.configured(
          _PasswordSession(
            {
              ...valid,
              'AI_BASE_URL': 'https://example.invalid/v1',
            }..remove('AI_API_KEY'),
          ),
        ),
        isNull,
      );
    },
  );

  test('configured NVIDIA Flash rejects lookalikes, foreign paths and routing parameters', () {
    const valid = {
      'AI_BASE_URL': nvidiaEvaluationBase,
      'AI_MODEL': 'z-ai/glm-5.3-flash',
      'NVIDIA_API_KEY': 'synthetic-nvidia-only-key',
    };
    for (final model in [
      'z-ai/glm-5.3',
      'z-ai/glm-5.3-flash:free',
      'z-ai/glm-5.3-flash-custom',
      'Z-AI/GLM-5.3-FLASH',
      'z-ai/glm-5.3-flash ',
      'other/model',
    ]) {
      expect(
        ChatCompletionProvider.configured(
          _PasswordSession({...valid, 'AI_MODEL': model}),
        ),
        isNull,
      );
    }
    for (final base in [
      'http://integrate.api.nvidia.com/v1',
      'https://integrate.api.nvidia.com/v2',
      'https://integrate.api.nvidia.com/v1/chat/completions',
      'https://integrate.api.nvidia.com/v1?model=other',
      'https://integrate.api.nvidia.com/v1#other',
      'https://user@integrate.api.nvidia.com/v1',
      'https://integrate.api.nvidia.com:444/v1',
      'https://integrate.api.nvidia.com.evil.test/v1',
    ]) {
      expect(
        ChatCompletionProvider.configured(
          _PasswordSession({...valid, 'AI_BASE_URL': base}),
        ),
        isNull,
      );
    }
  });

  test('all original NVIDIA runtime transports remain byte-identical', () {
    for (final model in nvidiaNemotronModels) {
      final configured = ChatCompletionProvider.configured(
        _PasswordSession({
          'AI_BASE_URL': nvidiaEvaluationBase,
          'AI_MODEL': model,
          'NVIDIA_API_KEY': 'synthetic-nvidia-only-key',
        }),
      )!;
      final legacy = ChatCompletionProvider(
        Uri.parse(nvidiaEvaluationBase),
        model,
        'synthetic-nvidia-only-key',
        nvidiaNemotronEvaluation: true,
      );
      expect(configured.nvidiaNemotronEvaluation, isTrue);
      expect(configured.nvidiaModelEvaluation, isFalse);
      expect(configured.nemotronProfile, NvidiaNemotronProfile.baseline);
      expect(configured.generationDeadline, legacy.generationDeadline);
      for (final editing in [false, true]) {
        final request = buildAiRequest(
          model,
          'A reading journal',
          baseline,
          editing: editing,
        );
        expect(
          jsonEncode(
            configured.adaptRequestForTransport(request, generation: true),
          ),
          jsonEncode(
            legacy.adaptRequestForTransport(request, generation: true),
          ),
        );
      }
      final guidance = buildGuidanceRequest(model, 'A reading journal');
      expect(
        jsonEncode(
          configured.adaptRequestForTransport(guidance, generation: false),
        ),
        jsonEncode(
          legacy.adaptRequestForTransport(guidance, generation: false),
        ),
      );
    }
  });

  test(
    'model lookalikes and foreign hosts fail before a completion can start',
    () {
      for (final model in [
        for (final model in _selected) ...[
          model.toUpperCase(),
          '$model:free',
          '$model/extra',
        ],
        '${_selected[1]}-custom',
        'other-vendor/${_selected.last.split('/').last}',
        'deepseek-ai/deepseek-v4.1-flash/extra',
      ]) {
        expect(() => _provider(model), throwsArgumentError);
        expect(
          () => validateNemotronModelSelection([model], route),
          throwsFormatException,
        );
      }
      for (final base in [
        'https://integrate.api.nvidia.com.evil.test/v1',
        'https://user@integrate.api.nvidia.com/v1',
        'https://integrate.api.nvidia.com/v1?model=other',
        'https://openrouter.ai/api/v1',
      ]) {
        expect(
          () => ChatCompletionProvider(
            Uri.parse(base),
            _selected.first,
            'synthetic-key',
            nvidiaModelEvaluation: true,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('new public catalog pages use exact declared paths and retain unknown pricing', () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      final model = _selected[seen.length];
      seen.add(model);
      expect(request.method, 'GET');
      expect(request.followRedirects, isFalse);
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(
        request.url.toString(),
        'https://build.nvidia.com/${_catalogPaths[model]}',
      );
      return http.Response(_page(model), 200);
    });
    final catalog = await readNvidiaNemotronCatalog(client, _selected);
    expect(seen, _selected);
    expect(catalog.map((entry) => entry['id']), _selected);
    for (final entry in catalog) {
      expect(entry['freeEndpoint'], isTrue);
      expect(entry['pricingVerified'], isFalse);
      expect(entry.containsKey('pricing'), isFalse);
    }
    for (final model in _selected) {
      expect(
        () => validateNvidiaFreeEndpointPage(
          model,
          _page(model).replaceAll('Free Endpoint', 'Paid Endpoint'),
        ),
        throwsFormatException,
      );
    }
  });

  test('authenticated access checks selected new IDs without claiming account credits', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), '$nvidiaEvaluationBase/models');
      expect(request.method, 'GET');
      expect(request.followRedirects, isFalse);
      expect(
        request.headers['Authorization'],
        'Bearer synthetic-nvidia-only-key',
      );
      return http.Response(
        jsonEncode({
          'data': [
            for (final model in _selected) {'id': model},
          ],
          'balance': 'private-account-field',
          'free_model_daily_requests': {'remaining': 123456},
        }),
        200,
      );
    });
    final access = await readNvidiaNemotronAccess(
      client,
      'synthetic-nvidia-only-key',
      _selected,
    );
    expect(access['authenticatedCatalogVerified'], isTrue);
    expect(access['accountLimitsKnown'], isFalse);
    expect(access['freeRequests'], isNull);
    expect(access['completionCallsMade'], isFalse);
    expect(jsonEncode(access), isNot(contains('private-account-field')));
    final missing = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'data': [
            for (final model in _selected.take(2)) {'id': model},
          ],
        }),
        200,
      ),
    );
    await expectLater(
      readNvidiaNemotronAccess(missing, 'synthetic-key', _selected),
      throwsFormatException,
    );
  });

  for (final model in _selected) {
    test('$model has an explicit immutable create/edit transport profile', () {
      final evaluator = _provider(model);
      for (final editing in [false, true]) {
        final source = buildAiRequest(
          model,
          'A personal reading journal',
          baseline,
          editing: editing,
        );
        final before = jsonEncode(source);
        final adapted = evaluator.adaptRequestForTransport(
          source,
          generation: true,
        );
        expect(jsonEncode(source), before);
        expect(adapted['model'], model);
        expect(adapted['temperature'], 0);
        expect(adapted['max_tokens'], 8000);
        expect(adapted['messages'].skip(1), source['messages'].skip(1));
        expect(
          adapted['messages'].first['content'],
          contains('Complete response schema:'),
        );
        _controls(model, adapted);
        final injected = evaluator.adaptRequestForTransport({
          ...source,
          'reasoning_effort': 'high',
        }, generation: true);
        _controls(model, injected);
      }
      expect(evaluator.generationDeadline, const Duration(seconds: 90));
      expect(nvidiaEvaluationProfile(model).documentationUrls, isNotEmpty);
      final repair = buildAiRequest(
        model,
        'A personal reading journal',
        baseline,
        editing: false,
        diagnostics: ['AI output reached the token limit before finishing.'],
      );
      expect(
        evaluator.adaptRequestForTransport(
          repair,
          generation: true,
        )['max_tokens'],
        12000,
      );
    });

    test('$model rejects caller-controlled routing or thinking extensions', () {
      final evaluator = _provider(model);
      final source = buildAiRequest(
        model,
        'A notebook',
        baseline,
        editing: false,
      );
      for (final key in [
        'provider',
        'models',
        'plugins',
        'tools',
        'stream',
        'chat_template_kwargs',
        'reasoning',
      ]) {
        expect(
          () => evaluator.adaptRequestForTransport({
            ...source,
            key: [],
          }, generation: true),
          throwsArgumentError,
          reason: key,
        );
      }
      expect(
        () => evaluator.adaptRequestForTransport({
          ...source,
          'model': _selected.first == model ? _selected.last : _selected.first,
        }, generation: true),
        throwsArgumentError,
      );
    });

    test(
      '$model guidance retains its decision grammar and provider profile',
      () async {
        final source = buildGuidanceRequest(model, guidance.prompt);
        final before = jsonEncode(source);
        final client = MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(
            request.headers['Authorization'],
            'Bearer synthetic-nvidia-only-key',
          );
          expect(request.headers['Accept'], 'application/json');
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], model);
          expect(body['max_tokens'], 2048);
          expect(body['messages'], source['messages']);
          _controls(model, body);
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
              'usage': {'prompt_tokens': 7, 'completion_tokens': 3},
            }),
            200,
          );
        });
        final result = await invokeNemotronGuidance(
          _provider(model),
          guidance,
          client: client,
        );
        expect(result.usage['completion_tokens'], 3);
        guidance.validate(parseAiOutput(result.text), null);
        expect(jsonEncode(source), before);
      },
    );

    test(
      '$model asynchronous responses remain indeterminate without retries',
      () async {
        final evaluator = _provider(
          model,
          clientFactory: () => MockClient((_) async => http.Response('', 202)),
        );
        final indeterminate = isA<AiResponseException>()
            .having((error) => error.statusCode, 'HTTP status', 202)
            .having((error) => error.retryable, 'automatic retry', isFalse);
        await expectLater(
          evaluator.generate('A notebook', baseline, editing: false),
          throwsA(indeterminate),
        );
        await expectLater(
          invokeNemotronGuidance(
            evaluator,
            guidance,
            client: MockClient((_) async => http.Response('', 202)),
          ),
          throwsA(indeterminate),
        );
      },
    );
  }

  for (final entry in _newProfiles.entries) {
    test('${entry.key} freezes reviewed parameters and AppNest limits', () {
      final profile = nvidiaEvaluationProfile(entry.key);
      expect(profile.model, entry.key);
      expect(profile.catalogPath, _catalogPaths[entry.key]);
      final manifest = profile.toJson();
      for (final expected in entry.value.entries) {
        expect(manifest[expected.key], expected.value, reason: expected.key);
      }
      expect(
        manifest['catalogUrl'],
        'https://build.nvidia.com/${_catalogPaths[entry.key]}',
      );
      expect(manifest['generationDeadlineSeconds'], 90);
      expect(manifest['guidanceDeadlineSeconds'], 20);
      expect(manifest['generationMaxTokens'], {
        'initial': 8000,
        'recognizedCreationTruncation': 12000,
      });
      expect(manifest['guidanceMaxTokens'], 2048);
      expect(manifest['topP'], 'model default; omitted');
      expect(
        manifest['responseContract'],
        'complete JSON schema supplied as instructions',
      );
      expect(manifest['limitations'], isNotEmpty);
      for (final key in profile.requestOverrides.keys) {
        if (key == 'chat_template_kwargs') {
          for (final templateKey
              in (profile.requestOverrides[key] as Map).keys) {
            expect(profile.parameterSources['$key.$templateKey'], isNotEmpty);
          }
        } else {
          expect(profile.parameterSources[key], isNotEmpty);
        }
      }
      final transport = profile.transportOverrides();
      transport['temperature'] = 1;
      if (transport['chat_template_kwargs'] case final Map kwargs) {
        kwargs['injected'] = true;
      }
      (manifest['requestOverrides'] as Map).clear();
      (manifest['documentationUrls'] as List).clear();
      (manifest['parameterSources'] as Map).clear();
      (manifest['limitations'] as List).clear();
      expect(profile.transportOverrides(), entry.value['requestOverrides']);
      expect(profile.toJson()['documentationUrls'], isNotEmpty);
      expect(profile.toJson()['parameterSources'], isNotEmpty);
      expect(profile.toJson()['limitations'], isNotEmpty);
    });
  }

  test('checkpoint profiles describe actual adapters and resume rejects altered execution', () {
    Map<String, dynamic> checkpoint({
      List<String> models = _selected,
      int concurrency = 3,
    }) => newNemotronCheckpoint(
      models: models,
      scenarios: [guidance],
      catalog: const [],
      source: const {'commit': 'synthetic', 'contractSourceSha256': 'fixed'},
      provider: 'nvidia',
      concurrency: concurrency,
      requestInterval: Duration.zero,
    );
    final state = checkpoint();
    for (final model in _selected) {
      expect(
        state['transportProfiles'][model]['profile'],
        _provider(model).transportProfile,
      );
    }
    expect(
      _selected.map((model) => _provider(model).transportProfile).toSet(),
      hasLength(_selected.length),
    );
    validateNemotronResume(state, checkpoint());
    expect(
      () => validateNemotronResume(state, checkpoint(concurrency: 1)),
      throwsFormatException,
    );
    expect(
      () => validateNemotronResume(
        state,
        checkpoint(models: _selected.reversed.toList()),
      ),
      throwsFormatException,
    );
    final changed = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    changed['transportProfiles'][_selected.first]['profile'] =
        'unreviewed-new-profile';
    expect(
      () => validateNemotronResume(changed, checkpoint()),
      throwsFormatException,
    );
    for (final model in _newProfiles.keys) {
      final altered = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
      altered['transportProfiles'][model]['requestOverrides']['temperature'] =
          1;
      expect(
        () => validateNemotronResume(altered, checkpoint()),
        throwsFormatException,
        reason: model,
      );
    }
  });
}
