import 'dart:convert';

import 'package:appnest_server/src/modules/builder/creation_pipeline_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_report.dart';
import 'package:appnest_server/src/modules/builder/nemotron_routes.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

http.Response _response(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {'content': content},
      },
    ],
    'usage': {
      'prompt_tokens': 101,
      'completion_tokens': 11,
      'total_tokens': 112,
    },
  }),
  200,
);

void main() {
  final baseline = starterTemplates()['reading']!;
  final base = Uri.parse(nvidiaEvaluationBase);

  test('repair unsupported-only remains strict and invalid patch retries use full generation', () async {
    final bodies = <Map>[];
    var call = 0;
    final provider = ExperimentalCreationProvider(
      base,
      pipelineTargetModel,
      'synthetic-unused-key',
      pipeline: CreationPipeline.repair,
      clientFactory: () => MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map);
        return _response(
          call++ == 0 ? '{"changes":[]}' : jsonEncode(baseline.toJson()),
        );
      }),
    );
    final evidence = <String, dynamic>{
      'responseProtocol': 'boundedCreationChanges',
      'repairBase': baseline.toJson(),
    };
    const unsupported =
        '{"unsupported":"External integration is unavailable."}';
    expect(deriveCreationPipelineResponse(unsupported, evidence), unsupported);
    expect(
      () => deriveCreationPipelineResponse(
        '{"unsupported":"x","changes":[]}',
        evidence,
      ),
      throwsA(isA<SpecException>()),
    );
    String? rejected;
    try {
      await provider.generate(
        'A reading app.',
        baseline,
        editing: false,
        diagnostics: ['Correct definition'],
        rejectedOutput: jsonEncode(baseline.toJson()),
      );
    } on AiResponseException catch (error) {
      rejected = error.syntheticResponse;
    }
    expect(rejected, '{"changes":[]}');
    final result = await provider.generate(
      'A reading app.',
      baseline,
      editing: false,
      diagnostics: ['Empty patch rejected'],
      rejectedOutput: rejected,
    );
    expect(result.pipelineEvidence!['responseProtocol'], 'AppSpec');
    expect(
      bodies[1]['messages'][0]['content'],
      isNot(contains('supersedes the')),
    );
  });

  test(
    'scoped transport is smaller and raw output survives exact replay',
    () async {
      late Map body;
      final raw = jsonEncode(baseline.toJson());
      final provider = ExperimentalCreationProvider(
        base,
        pipelineTargetModel,
        'synthetic-unused-key',
        pipeline: CreationPipeline.scoped,
        clientFactory: () => MockClient((request) async {
          body = jsonDecode(request.body) as Map;
          return _response(raw);
        }),
      );
      final result = await provider.generate(
        'Create a personal notes app.',
        baseline,
        editing: false,
      );
      expect(result.text, raw);
      expect(result.rawText, raw);
      expect(body['reasoning_effort'], 'low');
      expect(body.containsKey('response_format'), isFalse);
      final evidence = result.pipelineEvidence!;
      expect(
        evidence['requestBytes'] as int,
        lessThan(evidence['controlRequestBytes'] as int),
      );
      expect(deriveCreationPipelineResponse(raw, evidence), raw);
      expect(
        () => deriveCreationPipelineResponse('$raw ', evidence),
        throwsA(isA<SpecException>()),
      );
    },
  );

  test(
    'plan failures retain raw response, usage and compiler diagnostic',
    () async {
      final provider = ExperimentalCreationProvider(
        base,
        pipelineTargetModel,
        'synthetic-unused-key',
        pipeline: CreationPipeline.plan,
        clientFactory: () => MockClient((request) async {
          expect(request.body, contains('creationPlanVersion'));
          expect(
            request.body,
            isNot(contains('Final creation contract check')),
          );
          return _response('{"creationPlanVersion":2,"plan":{}}');
        }),
      );
      try {
        await provider.generate('Create a journal.', baseline, editing: false);
        fail('Invalid plan must fail');
      } on AiResponseException catch (error) {
        expect(error.kind, 'pipeline_validation');
        expect(error.message, contains('version'));
        expect(error.syntheticResponse, '{"creationPlanVersion":2,"plan":{}}');
        expect(error.usage!['total_tokens'], 112);
        expect(error.pipelineEvidence!['servedByModel'], pipelineTargetModel);
      }
    },
  );

  test(
    'bounded repair preserves base and derives full response for scoring',
    () async {
      final rejected = baseline.toJson()..['icon'] = 'unsupportedIcon';
      const rawPatch =
          '{"changes":[{"op":"set","path":["icon"],"value":"book"}]}';
      final provider = ExperimentalCreationProvider(
        base,
        pipelineTargetModel,
        'synthetic-unused-key',
        pipeline: CreationPipeline.repair,
        clientFactory: () => MockClient((request) async {
          expect(request.body, contains('appnest-creation-patch-v1'));
          expect(
            request.body,
            isNot(contains('Final creation contract check')),
          );
          return _response(rawPatch);
        }),
      );
      final result = await provider.generate(
        'Create a personal reading app.',
        baseline,
        editing: false,
        diagnostics: ['Unsupported icon'],
        rejectedOutput: jsonEncode(rejected),
      );
      expect(result.rawText, rawPatch);
      final candidate = AppSpec.parse(result.text);
      expect(candidate.icon, 'book');
      expect(
        candidate.collections.map((c) => c.toJson()),
        baseline.collections.map((c) => c.toJson()),
      );
      expect(
        deriveCreationPipelineResponse(rawPatch, result.pipelineEvidence!),
        result.text,
      );
      expect(rejected['icon'], 'unsupportedIcon');
    },
  );

  test(
    'malformed patch counts as correctness failure and keeps raw evidence',
    () async {
      final provider = ExperimentalCreationProvider(
        base,
        pipelineTargetModel,
        'synthetic-unused-key',
        pipeline: CreationPipeline.repair,
        clientFactory: () =>
            MockClient((_) async => _response('{"changes":[]}')),
      );
      try {
        await provider.generate(
          'A personal reading app.',
          baseline,
          editing: false,
          diagnostics: ['Correct icon'],
          rejectedOutput: jsonEncode(baseline.toJson()),
        );
        fail('Empty patch must fail');
      } on AiResponseException catch (error) {
        expect(error.kind, 'pipeline_validation');
        expect(error.syntheticResponse, '{"changes":[]}');
        expect(error.usage!['total_tokens'], 112);
      }
      final summary = summarizeNemotronEvaluation({
        'models': [pipelineTargetModel],
        'scenarios': [
          {'id': 'create-test', 'operation': 'create'},
        ],
        'operations': [
          {
            'model': pipelineTargetModel,
            'case': 'create-test',
            'operation': 'create',
            'status': 'failed',
            'success': false,
            'totalMs': 1,
            'attempts': [
              {'kind': 'pipeline_validation', 'success': false},
            ],
          },
        ],
      });
      expect(summary['models'][pipelineTargetModel]['correctnessFailed'], 1);
      expect(
        summary['models'][pipelineTargetModel]['availabilityOnlyFailures'],
        0,
      );
    },
  );

  test(
    'cascade uses one call per attempt and records actual serving model',
    () async {
      final calls = <String>[];
      final requests = <Map>[];
      ChatCompletionProvider provider(String model) => ChatCompletionProvider(
        base,
        model,
        'synthetic-unused-key',
        nvidiaModelEvaluation: true,
        nemotronProfile: NvidiaNemotronProfile.efficientCreation,
        clientFactory: () => MockClient((request) async {
          calls.add(model);
          requests.add(jsonDecode(request.body) as Map);
          return _response('{"unsupported":"Unsupported executable app."}');
        }),
      );
      final cascade = CreationCascade(
        provider(pipelineTargetModel),
        provider(pipelineFallbackModel),
      );
      final first = await cascade.generate(
        'unsupported',
        baseline,
        editing: false,
      );
      final fallback = await cascade.generate(
        'unsupported',
        baseline,
        editing: false,
        diagnostics: ['First attempt failed'],
        rejectedOutput: '{"bad":"Nemotron"}',
      );
      await cascade.generate(
        'unsupported',
        baseline,
        editing: false,
        diagnostics: ['GLM needs repair'],
        rejectedOutput: '{"bad":"GLM"}',
        fallbackPreviouslyUsed: true,
      );
      expect(calls, [
        pipelineTargetModel,
        pipelineFallbackModel,
        pipelineFallbackModel,
      ]);
      expect(first.pipelineEvidence!['servedByModel'], pipelineTargetModel);
      expect(
        fallback.pipelineEvidence!['servedByModel'],
        pipelineFallbackModel,
      );
      final firstFallbackEnvelope =
          jsonDecode(requests[1]['messages'][1]['content'] as String) as Map;
      expect(firstFallbackEnvelope.containsKey('repairContext'), isFalse);
      final repairEnvelope =
          jsonDecode(requests[2]['messages'][1]['content'] as String) as Map;
      expect(
        repairEnvelope['repairContext']['rejectedOutput'],
        '{"bad":"GLM"}',
      );
    },
  );

  test('pipeline identity participates in checkpoint and resume guard', () {
    Map<String, dynamic> checkpoint(CreationPipeline pipeline) =>
        newNemotronCheckpoint(
          models: [pipelineTargetModel],
          scenarios: [nemotronScenarios().first],
          catalog: [],
          source: {'commit': 'test', 'contractSourceSha256': 'test'},
          provider: 'nvidia',
          nemotronProfile: NvidiaNemotronProfile.efficientCreation,
          creationPipeline: creationPipelineMetadata(pipeline),
        );
    final scoped = checkpoint(CreationPipeline.scoped);
    expect(
      () => validateNemotronResume(scoped, checkpoint(CreationPipeline.plan)),
      throwsFormatException,
    );
    expect(
      () => validateNemotronResume(scoped, checkpoint(CreationPipeline.scoped)),
      returnsNormally,
    );
  });
}
