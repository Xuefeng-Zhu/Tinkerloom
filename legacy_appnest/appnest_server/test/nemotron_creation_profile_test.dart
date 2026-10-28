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
const _controls = ['z-ai/glm-5.3', 'z-ai/glm-5.3-flash'];
const _profiles = [
  NvidiaNemotronProfile.contractOnly,
  NvidiaNemotronProfile.efficientCreation,
];

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

  test(
    'authored creation detection excludes edit/guidance and never mutates',
    () {
      final create = buildAiRequest(
        _super,
        'A notebook',
        baseline,
        editing: false,
      );
      final edit = buildAiRequest(
        _super,
        'Rename the app',
        baseline,
        editing: true,
      );
      final guidance = buildGuidanceRequest(_super, 'Organize my life');
      for (final entry in {
        create: true,
        edit: false,
        guidance: false,
      }.entries) {
        final messages = entry.key['messages'] as List;
        final before = jsonEncode(messages);
        expect(isNemotronCreationRequest(messages), entry.value);
        expect(jsonEncode(messages), before);
      }
      for (final messages in <List>[
        [],
        [1],
        [
          {'role': 'user', 'content': '{"request":"A notebook"}'},
        ],
        [
          {'role': 'user', 'content': 'not JSON'},
        ],
        [
          {
            'role': 'user',
            'content': '{"request":"A notebook","currentDefinition":null}',
          },
        ],
        [
          {'role': 'user', 'content': '{"request":1}'},
        ],
      ]) {
        expect(isNemotronCreationRequest(messages), isFalse);
      }
    },
  );

  for (final profile in _profiles) {
    test(
      '${profile.id} unsupported ideas use creation controls; sequences use baseline',
      () {
        final unsupported = nemotronScenarios().firstWhere(
          (scenario) => scenario.operation == 'unsupported',
        );
        final provider = _provider(_super, profile);
        final unsupportedRequest = buildAiRequest(
          _super,
          unsupported.prompt,
          baseline,
          editing: false,
        );
        expect(
          isNemotronCreationRequest(unsupportedRequest['messages'] as List),
          isTrue,
        );
        final unsupportedBody = provider.adaptRequestForTransport(
          unsupportedRequest,
          generation: true,
        );
        expect(
          jsonEncode(unsupportedBody),
          contains(nemotronCreationChecklist),
        );
        expect(unsupportedBody.containsKey('reasoning_budget'), isFalse);
        expect(
          unsupportedBody['reasoning_effort'],
          profile == NvidiaNemotronProfile.efficientCreation ? 'low' : null,
        );
        expect(
          scoreNemotronResult(
            unsupported,
            '{"unsupported":"AppNest cannot execute arbitrary code."}',
            baseline,
          ),
          isNull,
        );
        expect(
          () => scoreNemotronResult(
            unsupported,
            '{"unsupported":"Unsupported feature.","patches":[]}',
            baseline,
          ),
          throwsA(isA<SpecException>()),
        );

        final sequence = nemotronSequences().first;
        final sequenceRequest = buildAiRequest(
          _super,
          sequence.prompt,
          sequence.baseline,
          editing: true,
        );
        expect(
          isNemotronCreationRequest(sequenceRequest['messages'] as List),
          isFalse,
        );
        expect(
          jsonEncode(
            provider.adaptRequestForTransport(
              sequenceRequest,
              generation: true,
            ),
          ),
          jsonEncode(
            _provider(
              _super,
              NvidiaNemotronProfile.baseline,
            ).adaptRequestForTransport(sequenceRequest, generation: true),
          ),
        );
      },
    );

    for (final entry in {_super: 'low', _ultra: 'medium'}.entries) {
      test(
        '${profile.id} ${entry.value} creation changes only declared controls/checklist',
        () {
          final original = buildAiRequest(
            entry.key,
            'A notebook with title and multiline writing',
            baseline,
            editing: false,
          );
          final before = jsonEncode(original);
          final expected = _provider(
            entry.key,
            NvidiaNemotronProfile.baseline,
          ).adaptRequestForTransport(original, generation: true);
          expected['messages'] = emphasizeNemotronCreationContract(
            expected['messages'] as List,
          );
          if (profile == NvidiaNemotronProfile.efficientCreation) {
            expected.remove('chat_template_kwargs');
            expected['reasoning_effort'] = entry.value;
          }
          final actual = _provider(entry.key, profile).adaptRequestForTransport(
            original,
            generation: true,
          );
          expect(jsonEncode(actual), jsonEncode(expected));
          expect(jsonEncode(original), before);
          expect(actual.containsKey('reasoning_budget'), isFalse);
          expect(actual['max_tokens'], 8000);
          expect(actual['temperature'], 0);
          expect(actual['stream'], isFalse);
          expect(actual.containsKey('response_format'), isFalse);
          expect(
            actual.containsKey('chat_template_kwargs'),
            profile == NvidiaNemotronProfile.contractOnly,
          );
          expect(
            _provider(entry.key, profile).generationDeadline,
            const Duration(seconds: 90),
          );
        },
      );

      test(
        '${profile.id} ${entry.value} edits and guidance are byte equivalent to baseline',
        () {
          for (final editing in [false, true]) {
            final body = editing
                ? buildAiRequest(
                    entry.key,
                    'Rename the app',
                    baseline,
                    editing: true,
                    diagnostics: const ['Synthetic validation diagnostic'],
                    rejectedOutput: '{"unsupported":"Synthetic rejected edit"}',
                  )
                : buildGuidanceRequest(entry.key, 'Organize my life');
            final expected = _provider(
              entry.key,
              NvidiaNemotronProfile.baseline,
            ).adaptRequestForTransport(body, generation: editing);
            final actual = _provider(entry.key, profile)
                .adaptRequestForTransport(
                  body,
                  generation: editing,
                );
            expect(jsonEncode(actual), jsonEncode(expected));
            expect(actual['chat_template_kwargs'], {'enable_thinking': false});
            expect(actual.containsKey('reasoning_effort'), isFalse);
            expect(actual.containsKey('reasoning_budget'), isFalse);
            expect(
              jsonEncode(actual),
              isNot(contains(nemotronCreationChecklist)),
            );
            expect(actual['max_tokens'], editing ? 8000 : 2048);
          }
        },
      );
    }

    test(
      '${profile.id} GLM controls retain byte equivalent creation/edit/guidance',
      () {
        for (final model in _controls) {
          for (final operation in ['create', 'edit', 'guidance']) {
            final body = operation == 'guidance'
                ? buildGuidanceRequest(model, 'Organize my life')
                : buildAiRequest(
                    model,
                    'A notebook',
                    baseline,
                    editing: operation == 'edit',
                  );
            final control = _provider(model, NvidiaNemotronProfile.baseline);
            final experimental = _provider(model, profile);
            expect(
              jsonEncode(
                experimental.adaptRequestForTransport(
                  body,
                  generation: operation != 'guidance',
                ),
              ),
              jsonEncode(
                control.adaptRequestForTransport(
                  body,
                  generation: operation != 'guidance',
                ),
              ),
            );
            expect(experimental.transportProfile, control.transportProfile);
          }
        }
      },
    );

    test(
      '${profile.id} creation repair keeps the same fixed higher allowance',
      () {
        final body = _provider(_super, profile).adaptRequestForTransport(
          buildAiRequest(
            _super,
            'A notebook',
            baseline,
            editing: false,
            diagnostics: const [
              'AI output reached the token limit before finishing. Return smaller JSON.',
            ],
          ),
          generation: true,
        );
        expect(body['max_tokens'], 12000);
        expect(body.containsKey('reasoning_budget'), isFalse);
        expect(jsonEncode(body), contains(nemotronCreationChecklist));
      },
    );

    test(
      '${profile.id} freezes complete per-operation maps and detached metadata',
      () {
        final description = nvidiaEvaluationProfile(
          _super,
          nemotronProfile: profile,
        );
        final off = nvidiaEvaluationProfile(_super).transportOverrides();
        final creation = profile == NvidiaNemotronProfile.contractOnly
            ? off
            : {'stream': false, 'reasoning_effort': 'low'};
        final manifest = description.toJson();
        expect(manifest['promptContract'], 'nemotron-creation-checklist-v1');
        expect(manifest['requestOverrides'], off);
        expect(manifest['creationRequestOverrides'], creation);
        expect(manifest['operationOverrides'], {
          'create': creation,
          'unsupported': creation,
          'edit': off,
          'sequence': off,
          'guidance': off,
        });
        expect(manifest['generationMaxTokens'], {
          'initial': 8000,
          'recognizedCreationTruncation': 12000,
        });
        expect(manifest['guidanceDeadlineSeconds'], 20);
        expect(manifest['guidanceMaxTokens'], 2048);
        (manifest['creationRequestOverrides'] as Map)['stream'] = true;
        (manifest['operationOverrides']['edit']['chat_template_kwargs']
                as Map)['enable_thinking'] =
            true;
        expect(description.transportOverrides(), off);
        expect(description.transportOverrides(creation: true), creation);
      },
    );

    test(
      '${profile.id} rejects unsupported routes/models and ordinary app construction',
      () {
        validateNvidiaNemotronProfileSelection(
          [_super, ..._controls],
          'nvidia',
          profile,
        );
        for (final models in [
          nvidiaNemotronModels,
          _controls,
          [_super, 'moonshotai/kimi-k3'],
        ]) {
          expect(
            () => validateNvidiaNemotronProfileSelection(
              models,
              'nvidia',
              profile,
            ),
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
      },
    );

    test(
      '${profile.id} CLI rejects other providers before catalog/credential access',
      () async {
        final result = await Process.run(Platform.resolvedExecutable, [
          '--suppress-analytics',
          'run',
          'scripts/nemotron_eval.dart',
          '--catalog',
          '--provider=openrouter',
          '--nemotron-profile=${profile.id}',
        ], workingDirectory: Directory.current.parent.path);
        expect(result.exitCode, 2);
        expect(result.stderr, contains('Reasoning experiments require NVIDIA'));
        expect(result.stdout, isEmpty);
      },
    );
  }

  test('new modes and actual operation override changes reject resume', () {
    Map<String, dynamic> checkpoint(NvidiaNemotronProfile profile) =>
        newNemotronCheckpoint(
          models: [_super, _ultra, ..._controls],
          scenarios: [nemotronScenarios().first],
          catalog: const [],
          source: const {
            'commit': 'synthetic',
            'contractSourceSha256': 'fixed',
          },
          provider: 'nvidia',
          nemotronProfile: profile,
        );
    final contract = checkpoint(NvidiaNemotronProfile.contractOnly);
    final efficient = checkpoint(NvidiaNemotronProfile.efficientCreation);
    expect(contract['runFingerprint'], isNot(efficient['runFingerprint']));
    expect(contract['maxAttempts'], 3);
    expect(efficient['maxAttempts'], 3);
    expect(
      () => validateNemotronResume(contract, efficient),
      throwsFormatException,
    );
    final changed = jsonDecode(jsonEncode(efficient)) as Map<String, dynamic>;
    changed['transportProfiles'][_super]['operationOverrides']['create']['reasoning_budget'] =
        1024;
    expect(
      () => validateNemotronResume(changed, efficient),
      throwsFormatException,
    );
  });
}
