import 'dart:convert';
import 'dart:io';

import 'package:appnest_server/src/modules/builder/nemotron_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_prompt.dart';
import 'package:appnest_server/src/modules/builder/nemotron_routes.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

const _super = 'nvidia/nemotron-3-super-120b-a12b';
const _ultra = 'nvidia/nemotron-3-ultra-550b-a55b';
const _publisher = NvidiaNemotronProfile.publisherCreation;

ChatCompletionProvider _provider(String model, NvidiaNemotronProfile profile) =>
    ChatCompletionProvider(
      Uri.parse(nvidiaEvaluationBase),
      model,
      'synthetic-unused-key',
      nvidiaModelEvaluation: true,
      nemotronProfile: profile,
    );

void main() {
  final baseline = starterTemplates()['reading']!;

  for (final entry in {_super: 'low', _ultra: 'medium'}.entries) {
    test(
      '${entry.value} publisher creation changes efficient sampling only',
      () {
        for (final repair in [false, true]) {
          final authored = buildAiRequest(
            entry.key,
            'A photo journal',
            baseline,
            editing: false,
            diagnostics: repair
                ? const [
                    'AI output reached the token limit before finishing. Return smaller JSON.',
                  ]
                : const [],
          );
          final original = jsonEncode(authored);
          final expected = _provider(
            entry.key,
            NvidiaNemotronProfile.efficientCreation,
          ).adaptRequestForTransport(authored, generation: true);
          expected['temperature'] = 1.0;
          expected['top_p'] = 0.95;
          final actual = _provider(
            entry.key,
            _publisher,
          ).adaptRequestForTransport(authored, generation: true);
          expect(jsonEncode(actual), jsonEncode(expected));
          expect(jsonEncode(authored), original);
          expect(actual['reasoning_effort'], entry.value);
          expect(actual.containsKey('reasoning_budget'), isFalse);
          expect(actual.containsKey('chat_template_kwargs'), isFalse);
          expect(actual.containsKey('response_format'), isFalse);
          expect(jsonEncode(actual), contains(nemotronCreationChecklist));
          expect(actual['max_tokens'], repair ? 12000 : 8000);
          expect(
            _provider(entry.key, _publisher).generationDeadline,
            const Duration(seconds: 90),
          );
        }
      },
    );

    test('${entry.value} edit/sequence/guidance preserve baseline bytes', () {
      for (final operation in ['edit', 'sequence', 'guidance']) {
        final body = operation == 'guidance'
            ? buildGuidanceRequest(entry.key, 'Organize my life')
            : buildAiRequest(
                entry.key,
                'Rename the app',
                baseline,
                editing: true,
              );
        final generation = operation != 'guidance';
        final expected = _provider(
          entry.key,
          NvidiaNemotronProfile.baseline,
        ).adaptRequestForTransport(body, generation: generation);
        final actual = _provider(
          entry.key,
          _publisher,
        ).adaptRequestForTransport(body, generation: generation);
        expect(jsonEncode(actual), jsonEncode(expected));
        if (generation) {
          expect(actual['temperature'], 0);
        } else {
          expect(actual.containsKey('temperature'), isFalse);
        }
        expect(actual.containsKey('top_p'), isFalse);
        expect(actual.containsKey('reasoning_effort'), isFalse);
        expect(actual['chat_template_kwargs'], {'enable_thinking': false});
        expect(jsonEncode(actual), isNot(contains(nemotronCreationChecklist)));
        expect(actual['max_tokens'], generation ? 8000 : 2048);
      }
    });
  }

  test('unsupported ideas use publisher creation with the unchanged strict response contract', () {
    final scenario = nemotronScenarios().firstWhere(
      (scenario) => scenario.operation == 'unsupported',
    );
    final body = _provider(_super, _publisher).adaptRequestForTransport(
      buildAiRequest(_super, scenario.prompt, baseline, editing: false),
      generation: true,
    );
    expect(body['temperature'], 1.0);
    expect(body['top_p'], 0.95);
    expect(body['reasoning_effort'], 'low');
    expect(body.containsKey('reasoning_budget'), isFalse);
    expect(
      scoreNemotronResult(
        scenario,
        '{"unsupported":"AppNest cannot execute arbitrary code."}',
        baseline,
      ),
      isNull,
    );
    expect(
      () => scoreNemotronResult(
        scenario,
        '{"unsupported":"Unsupported.","patches":[]}',
        baseline,
      ),
      throwsA(isA<SpecException>()),
    );
  });

  test('both GLM controls preserve all operation payloads and metadata', () {
    for (final model in ['z-ai/glm-5.3', 'z-ai/glm-5.3-flash']) {
      expect(
        nvidiaEvaluationProfile(model, nemotronProfile: _publisher).toJson(),
        nvidiaEvaluationProfile(model).toJson(),
      );
      for (final operation in ['create', 'edit', 'guidance']) {
        final body = operation == 'guidance'
            ? buildGuidanceRequest(model, 'Organize my life')
            : buildAiRequest(
                model,
                'A notebook',
                baseline,
                editing: operation == 'edit',
              );
        final generation = operation != 'guidance';
        expect(
          jsonEncode(
            _provider(
              model,
              _publisher,
            ).adaptRequestForTransport(body, generation: generation),
          ),
          jsonEncode(
            _provider(
              model,
              NvidiaNemotronProfile.baseline,
            ).adaptRequestForTransport(body, generation: generation),
          ),
        );
      }
    }
  });

  test(
    'only new profile metadata reports creation sampling and fixed limits',
    () {
      final profile = nvidiaEvaluationProfile(
        _super,
        nemotronProfile: _publisher,
      );
      final metadata = profile.toJson();
      final off = nvidiaEvaluationProfile(_super).transportOverrides();
      const creation = {
        'stream': false,
        'reasoning_effort': 'low',
        'temperature': 1.0,
        'top_p': 0.95,
      };
      expect(metadata['operationOverrides'], {
        'create': creation,
        'unsupported': creation,
        'edit': off,
        'sequence': off,
        'guidance': off,
      });
      expect(
        metadata['topP'],
        'creation/unsupported: 0.95; '
        'edit/sequence/guidance: model default; omitted',
      );
      expect(metadata['guidanceDeadlineSeconds'], 20);
      expect(metadata['guidanceMaxTokens'], 2048);
      expect(metadata['generationMaxTokens'], {
        'initial': 8000,
        'recognizedCreationTruncation': 12000,
      });
      expect(metadata['promptContract'], 'nemotron-creation-checklist-v1');
      expect(
        metadata['parameterSources']['temperature'],
        contains('modelcard'),
      );
      expect(metadata['parameterSources']['top_p'], contains('modelcard'));
      (metadata['creationRequestOverrides'] as Map)['temperature'] = 0;
      expect(profile.transportOverrides(creation: true), creation);
      for (final mode in NvidiaNemotronProfile.values.where(
        (mode) => mode != _publisher,
      )) {
        expect(
          nvidiaEvaluationProfile(
            _super,
            nemotronProfile: mode,
          ).toJson()['topP'],
          'model default; omitted',
        );
      }
    },
  );

  test('explicit selection, constructor guard and fingerprint isolate publisher mode', () {
    expect(parseNvidiaNemotronProfile('publisher-creation'), _publisher);
    validateNvidiaNemotronProfileSelection(
      [_super, 'z-ai/glm-5.3'],
      'nvidia',
      _publisher,
    );
    expect(
      () => validateNvidiaNemotronProfileSelection(
        nvidiaNemotronModels,
        'nvidia',
        _publisher,
      ),
      throwsFormatException,
    );
    expect(
      () => validateNvidiaNemotronProfileSelection(
        freeNemotronModels,
        'openrouter',
        _publisher,
      ),
      throwsFormatException,
    );
    expect(
      () => ChatCompletionProvider(
        Uri.parse(nvidiaEvaluationBase),
        _super,
        'synthetic-unused-key',
        nvidiaNemotronEvaluation: true,
        nemotronProfile: _publisher,
      ),
      throwsArgumentError,
    );
    Map<String, dynamic> checkpoint(NvidiaNemotronProfile mode) =>
        newNemotronCheckpoint(
          models: [_super, 'z-ai/glm-5.3'],
          scenarios: [nemotronScenarios().first],
          catalog: const [],
          source: const {
            'commit': 'synthetic',
            'contractSourceSha256': 'fixed',
          },
          provider: 'nvidia',
          nemotronProfile: mode,
        );
    final publisher = checkpoint(_publisher);
    final efficient = checkpoint(NvidiaNemotronProfile.efficientCreation);
    expect(publisher['maxAttempts'], 3);
    expect(publisher['runFingerprint'], isNot(efficient['runFingerprint']));
    expect(
      () => validateNemotronResume(publisher, efficient),
      throwsFormatException,
    );
  });

  test(
    'CLI rejects wrong publisher route before catalog or credential access',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        '--suppress-analytics',
        'run',
        'scripts/nemotron_eval.dart',
        '--catalog',
        '--provider=openrouter',
        '--nemotron-profile=publisher-creation',
      ], workingDirectory: Directory.current.parent.path);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('Reasoning experiments require NVIDIA'));
      expect(result.stdout, isEmpty);
    },
  );
}
