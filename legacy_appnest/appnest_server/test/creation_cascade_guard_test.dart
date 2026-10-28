import 'dart:convert';

import 'package:appnest_server/src/modules/builder/creation_pipeline_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_routes.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _unsupported = '{"unsupported":"AppNest cannot execute arbitrary code."}';
const _wrong = '{"patches":[]}';

http.Response _completion(String content, {num cost = 0}) => http.Response(
  jsonEncode({
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {'content': content},
      },
    ],
    'usage': {
      'prompt_tokens': 10,
      'completion_tokens': 5,
      'total_tokens': 15,
      'cost': cost,
    },
  }),
  200,
);

class _Harness {
  final scenario = NemotronScenario(
    id: 'unsupported-cascade-guard',
    operation: 'unsupported',
    prompt: 'Execute arbitrary code.',
    baseline: starterTemplates()['reading']!,
  );
  final List<http.Response> primaryResponses, fallbackResponses;
  final calls = <String>[];
  final envelopes = <Map<String, dynamic>>[];
  late final Map<String, dynamic> checkpoint;

  _Harness({
    required this.primaryResponses,
    this.fallbackResponses = const [],
  }) {
    checkpoint = newNemotronCheckpoint(
      models: [pipelineTargetModel],
      scenarios: [scenario],
      catalog: [],
      source: {
        'commit': 'synthetic-test',
        'contractSourceSha256': 'frozen-test',
      },
      provider: 'nvidia',
      requestInterval: Duration.zero,
      nemotronProfile: NvidiaNemotronProfile.efficientCreation,
      creationPipeline: creationPipelineMetadata(CreationPipeline.cascade),
    );
  }

  Map<String, dynamic> get row =>
      (checkpoint['operations'] as List).single as Map<String, dynamic>;

  List<dynamic> get attempts => row['attempts'] as List;

  /// Build fresh provider/cascade objects on each run, as a checkpoint resume
  /// in a new process would. No process-local fallback phase is retained.
  Future<void> run({int? maxRequests}) async {
    ChatCompletionProvider provider(
      String model,
      List<http.Response> responses,
    ) => ChatCompletionProvider(
      Uri.parse(nvidiaEvaluationBase),
      model,
      'synthetic-unused-key',
      nvidiaModelEvaluation: true,
      nemotronProfile: NvidiaNemotronProfile.efficientCreation,
      clientFactory: () => MockClient((request) async {
        expect(row['status'], 'in_flight');
        calls.add(model);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final user = (body['messages'] as List)
            .where(
              (message) => message['role'] == 'user',
            )
            .last;
        envelopes.add(
          jsonDecode(user['content'] as String) as Map<String, dynamic>,
        );
        expect(responses, isNotEmpty, reason: 'Unexpected extra $model call');
        return responses.removeAt(0);
      }),
    );
    final cascade = CreationCascade(
      provider(pipelineTargetModel, primaryResponses),
      provider(pipelineFallbackModel, fallbackResponses),
    );
    await NemotronEvaluationRunner(
      checkpoint: checkpoint,
      scenarios: [scenario],
      requestInterval: Duration.zero,
      delay: (_) async {},
      save: (_) async {},
      invoke: (_, scenario, baseline, diagnostics, rejected) =>
          cascade.generate(
            scenario.prompt,
            baseline,
            editing: false,
            diagnostics: diagnostics,
            rejectedOutput: rejected,
            fallbackPreviouslyUsed: attempts.whereType<Map>().any(
              (attempt) =>
                  attempt['pipelineEvidence']?['servedByModel'] ==
                  pipelineFallbackModel,
            ),
          ),
    ).run(maxRequests: maxRequests);
  }
}

void main() {
  test(
    'HTTP 202 remains indeterminate without fallback or resubmission',
    () async {
      final harness = _Harness(primaryResponses: [http.Response('{}', 202)]);
      await harness.run();
      expect(harness.calls, [pipelineTargetModel]);
      expect(harness.checkpoint['status'], 'incomplete');
      expect(harness.row['status'], 'indeterminate');
      expect(harness.attempts, hasLength(1));
      expect(harness.attempts.single['httpStatus'], 202);
      expect(
        harness.attempts.single['pipelineEvidence']['servedByModel'],
        pipelineTargetModel,
      );
      await harness.run();
      expect(harness.calls, [pipelineTargetModel]);
      expect(harness.checkpoint['status'], 'incomplete');
    },
  );

  for (final status in [401, 402, 403, 429]) {
    test('HTTP $status blocks before GLM can consume a call', () async {
      final harness = _Harness(primaryResponses: [http.Response('{}', status)]);
      await harness.run();
      expect(harness.calls, [pipelineTargetModel]);
      expect(harness.checkpoint['status'], 'blocked');
      expect(harness.row['status'], 'blocked');
      expect(harness.attempts, hasLength(1));
      expect(harness.attempts.single['httpStatus'], status);
      expect(
        harness.attempts.single['pipelineEvidence']['servedByModel'],
        pipelineTargetModel,
      );
    });
  }

  test(
    'reported nonzero cost blocks fallback and prevents a later resume',
    () async {
      final harness = _Harness(
        primaryResponses: [_completion(_wrong, cost: 0.01)],
      );
      await harness.run();
      expect(harness.calls, [pipelineTargetModel]);
      expect(harness.checkpoint['status'], 'blocked');
      expect(harness.checkpoint['billingGuardTripped'], isTrue);
      expect(harness.attempts.single['usage']['cost'], 0.01);
      expect(harness.attempts.single['providerResponse'], _wrong);
      await expectLater(harness.run(), throwsFormatException);
      expect(harness.calls, [pipelineTargetModel]);
    },
  );

  test(
    'one-call cap counts primary and defers fallback to explicit resume',
    () async {
      final harness = _Harness(
        primaryResponses: [_completion(_wrong)],
        fallbackResponses: [_completion(_unsupported)],
      );
      await harness.run(maxRequests: 1);
      expect(harness.calls, [pipelineTargetModel]);
      expect(harness.checkpoint['status'], 'blocked');
      expect(harness.attempts, hasLength(1));
      expect(harness.row['status'], 'pending');
      await harness.run(maxRequests: 1);
      expect(harness.calls, [pipelineTargetModel, pipelineFallbackModel]);
      expect(harness.checkpoint['status'], 'completed');
      expect(harness.row['status'], 'passed');
      expect(harness.attempts, hasLength(2));
      expect(harness.envelopes.last.containsKey('repairContext'), isFalse);
    },
  );

  test(
    'failed primary then successful GLM uses two recorded attempts',
    () async {
      final harness = _Harness(
        primaryResponses: [_completion(_wrong)],
        fallbackResponses: [_completion(_unsupported)],
      );
      await harness.run();
      expect(harness.calls, [pipelineTargetModel, pipelineFallbackModel]);
      expect(harness.attempts, hasLength(2));
      expect(harness.attempts.map((attempt) => attempt['success']), [
        false,
        true,
      ]);
      expect(
        harness.attempts.map(
          (attempt) => attempt['pipelineEvidence']['servedByModel'],
        ),
        harness.calls,
      );
      expect(harness.attempts.last['providerResponse'], _unsupported);
      expect(harness.attempts.last['usage']['total_tokens'], 15);
      expect(harness.envelopes.last.containsKey('repairContext'), isFalse);
      expect(harness.row['status'], 'passed');
      expect(harness.checkpoint['status'], 'completed');
    },
  );

  test(
    'persistent correctness failures spend exactly the original three calls',
    () async {
      final harness = _Harness(
        primaryResponses: [_completion(_wrong)],
        fallbackResponses: [
          _completion('{"invalid":"glm"}'),
          _completion(_wrong),
        ],
      );
      await harness.run();
      expect(harness.calls, [
        pipelineTargetModel,
        pipelineFallbackModel,
        pipelineFallbackModel,
      ]);
      expect(harness.attempts, hasLength(3));
      expect(harness.row['status'], 'failed');
      expect(harness.envelopes[1].containsKey('repairContext'), isFalse);
      expect(
        harness.envelopes[2]['repairContext']['rejectedOutput'],
        '{"invalid":"glm"}',
      );
      await harness.run();
      expect(harness.calls, hasLength(3));
    },
  );

  test(
    'new-process resume keeps the preceding GLM response as repair context',
    () async {
      const glmRejected = '{"invalid":"previous GLM attempt"}';
      final harness = _Harness(
        primaryResponses: [_completion(_wrong)],
        fallbackResponses: [
          _completion(glmRejected),
          _completion(_unsupported),
        ],
      );
      await harness.run(maxRequests: 2);
      expect(harness.checkpoint['status'], 'blocked');
      expect(harness.calls, [pipelineTargetModel, pipelineFallbackModel]);
      expect(harness.attempts, hasLength(2));
      await harness.run(maxRequests: 1);
      expect(harness.calls, [
        pipelineTargetModel,
        pipelineFallbackModel,
        pipelineFallbackModel,
      ]);
      expect(
        harness.envelopes.last['repairContext']['rejectedOutput'],
        glmRejected,
      );
      expect(
        harness.attempts.last['pipelineEvidence']['servedByModel'],
        pipelineFallbackModel,
      );
      expect(harness.attempts.last['success'], isTrue);
      expect(harness.attempts, hasLength(3));
      expect(harness.checkpoint['status'], 'completed');
    },
  );
}
