import 'dart:convert';
import 'dart:io';

import 'package:appnest_server/src/modules/builder/nemotron_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_prompt.dart';
import 'package:appnest_server/src/modules/builder/nemotron_routes.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart' show Session;
import 'package:test/test.dart';

const _super = 'nvidia/nemotron-3-super-120b-a12b';
const _ultra = 'nvidia/nemotron-3-ultra-550b-a55b';
const _glm = 'z-ai/glm-5.3';
const _models = [_super, _ultra, _glm];

class _PasswordSession implements Session {
  @override
  final Map<String, String> passwords;
  _PasswordSession(this.passwords);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ChatCompletionProvider _provider(
  String model,
  NvidiaNemotronProfile profile,
) => ChatCompletionProvider(
  Uri.parse(nvidiaEvaluationBase),
  model,
  'synthetic-unused-key',
  nvidiaModelEvaluation: true,
  nemotronProfile: profile,
);

void main() {
  final baseline = starterTemplates()['reading']!;
  final scenarios = [nemotronScenarios().first];
  const experiments = [
    NvidiaNemotronProfile.boundedReasoning,
    NvidiaNemotronProfile.contractReasoning,
  ];

  test('profile parser accepts only explicit reviewed modes', () {
    for (final profile in NvidiaNemotronProfile.values) {
      expect(parseNvidiaNemotronProfile(profile.id), profile);
    }
    for (final value in ['', 'medium', 'BOUNDED-REASONING', ' high ']) {
      expect(() => parseNvidiaNemotronProfile(value), throwsFormatException);
    }
  });

  test('all default and configured NVIDIA models retain thinking-off', () {
    for (final model in nvidiaNemotronModels) {
      final configured = ChatCompletionProvider.configured(
        _PasswordSession({
          'AI_BASE_URL': nvidiaEvaluationBase,
          'AI_MODEL': model,
          'NVIDIA_API_KEY': 'synthetic-unused-key',
        }),
      )!;
      expect(configured.nemotronProfile, NvidiaNemotronProfile.baseline);
      expect(
        configured.transportProfile,
        'nvidia-instruction-schema-thinking-off-v1',
      );
      final request = buildAiRequest(
        model,
        'Create a reading log.',
        baseline,
        editing: false,
      );
      final adapted = configured.adaptRequestForTransport(
        request,
        generation: true,
      );
      expect(adapted['chat_template_kwargs'], {'enable_thinking': false});
      expect(adapted.containsKey('reasoning_effort'), isFalse);
      expect(adapted.containsKey('reasoning_budget'), isFalse);
      expect(jsonEncode(adapted), isNot(contains(nemotronCreationChecklist)));
    }
  });

  for (final profile in experiments) {
    test('${profile.id} rejects other routes and unsupported model sets', () {
      validateNvidiaNemotronProfileSelection(_models, 'nvidia', profile);
      validateNvidiaNemotronProfileSelection([_super], 'nvidia', profile);
      for (final models in [
        nvidiaNemotronModels,
        [_glm],
        [_super, 'moonshotai/kimi-k3'],
        [_ultra, 'nvidia/nemotron-3.5-lightning-30b-a3b'],
      ]) {
        expect(
          () =>
              validateNvidiaNemotronProfileSelection(models, 'nvidia', profile),
          throwsFormatException,
        );
      }
      expect(
        () => validateNvidiaNemotronProfileSelection(
          freeNemotronModels,
          'openrouter',
          profile,
        ),
        throwsFormatException,
      );
      expect(
        () => ChatCompletionProvider(
          Uri.parse(nvidiaEvaluationBase),
          _super,
          'synthetic-unused-key',
          nvidiaNemotronEvaluation: true,
          nemotronProfile: profile,
        ),
        throwsArgumentError,
      );
      expect(
        () => _provider('nvidia/nemotron-3.5-lightning-30b-a3b', profile),
        throwsArgumentError,
      );
    });

    test(
      '${profile.id} emits documented fixed effort/budget and immutable input',
      () {
        for (final entry in {_super: 'low', _ultra: 'medium'}.entries) {
          final provider = _provider(entry.key, profile);
          final request = buildAiRequest(
            entry.key,
            'Create a reading log with title and author.',
            baseline,
            editing: false,
          );
          final original = jsonEncode(request);
          final body = provider.adaptRequestForTransport(
            request,
            generation: true,
          );
          expect(jsonEncode(request), original);
          expect(body['reasoning_effort'], entry.value);
          expect(body['reasoning_budget'], 1024);
          expect(body.containsKey('chat_template_kwargs'), isFalse);
          expect(body.containsKey('response_format'), isFalse);
          expect(body['stream'], isFalse);
          expect(body['temperature'], 0);
          expect(body['max_tokens'], 8000);
          expect(provider.generationDeadline, const Duration(seconds: 90));
          final description = nvidiaEvaluationProfile(
            entry.key,
            nemotronProfile: profile,
          ).toJson();
          expect(description['profile'], provider.transportProfile);
          expect(description['generationMaxTokens'], {
            'initial': 8000,
            'recognizedCreationTruncation': 12000,
          });
          expect(description['guidanceDeadlineSeconds'], 20);
          expect(description['guidanceMaxTokens'], 2048);
          expect(
            jsonEncode(body).contains(nemotronCreationChecklist),
            profile == NvidiaNemotronProfile.contractReasoning,
          );
          final repair = provider.adaptRequestForTransport(
            buildAiRequest(
              entry.key,
              'Create a reading log.',
              baseline,
              editing: false,
              diagnostics: const [
                'AI output reached the token limit before finishing. Return smaller JSON.',
              ],
            ),
            generation: true,
          );
          expect(repair['max_tokens'], 12000);
          expect(repair['reasoning_budget'], 1024);
        }
      },
    );

    test('${profile.id} preserves GLM control payload byte for byte', () {
      final request = buildAiRequest(
        _glm,
        'Create a reading log.',
        baseline,
        editing: false,
      );
      final control = _provider(_glm, NvidiaNemotronProfile.baseline);
      final experimental = _provider(_glm, profile);
      expect(
        jsonEncode(
          experimental.adaptRequestForTransport(request, generation: true),
        ),
        jsonEncode(control.adaptRequestForTransport(request, generation: true)),
      );
      expect(experimental.transportProfile, control.transportProfile);
    });

    test('${profile.id} guidance uses the fixed small response allowance', () {
      final body = _provider(_super, profile).adaptRequestForTransport(
        buildGuidanceRequest(_super, 'Help organize things.'),
        generation: false,
      );
      expect(body['max_tokens'], 2048);
      expect(body['reasoning_budget'], 1024);
      expect(body['reasoning_effort'], 'low');
      expect(jsonEncode(body), isNot(contains(nemotronCreationChecklist)));
    });
  }

  test('profile and contract emphasis change fingerprint and cannot resume another mode', () {
    Map<String, dynamic> checkpoint(NvidiaNemotronProfile profile) =>
        newNemotronCheckpoint(
          models: _models,
          scenarios: scenarios,
          catalog: const [],
          source: const {
            'commit': 'synthetic',
            'contractSourceSha256': 'fixed',
          },
          provider: 'nvidia',
          nemotronProfile: profile,
        );
    final states = {
      for (final profile in NvidiaNemotronProfile.values)
        profile: checkpoint(profile),
    };
    expect(
      states.values.map((state) => state['runFingerprint']).toSet(),
      hasLength(NvidiaNemotronProfile.values.length),
    );
    for (final entry in states.entries) {
      expect(entry.value['nemotronProfile'], entry.key.id);
      expect(entry.value['maxAttempts'], 3);
      validateNemotronResume(entry.value, checkpoint(entry.key));
      for (final other in states.entries.where(
        (other) => other.key != entry.key,
      )) {
        expect(
          () => validateNemotronResume(entry.value, other.value),
          throwsFormatException,
        );
      }
    }
    final contract = states[NvidiaNemotronProfile.contractReasoning]!;
    expect(
      contract['transportProfiles'][_super]['promptContract'],
      'nemotron-creation-checklist-v1',
    );
    expect(
      contract['transportProfiles'][_glm].containsKey('promptContract'),
      isFalse,
    );
  });

  test(
    'CLI rejects invalid profile selection before public catalog calls',
    () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--suppress-analytics',
          'run',
          'scripts/nemotron_eval.dart',
          '--catalog',
          '--provider=openrouter',
          '--nemotron-profile=bounded-reasoning',
        ],
        workingDirectory: Directory.current.parent.path,
      );
      expect(result.exitCode, 2);
      expect(result.stderr, contains('Reasoning experiments require NVIDIA'));
      expect(result.stdout, isEmpty);
    },
  );
}
