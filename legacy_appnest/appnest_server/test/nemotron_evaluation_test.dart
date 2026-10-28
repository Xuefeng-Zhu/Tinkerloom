import 'dart:convert';

import 'package:appnest_server/src/modules/builder/nemotron_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final scenario = NemotronScenario(
    id: 'unsupported-test',
    operation: 'unsupported',
    prompt: 'Execute arbitrary code.',
    baseline: starterTemplates()['reading']!,
  );
  Map<String, dynamic> state({List<String>? models}) => newNemotronCheckpoint(
    models: models ?? [freeNemotronModels.first],
    scenarios: [scenario],
    catalog: const [],
    source: const {'commit': 'test', 'contractSourceSha256': 'fixed'},
  );
  AiResult answer([Map<String, dynamic> usage = const {}]) => AiResult(
    '{"unsupported":"AppNest cannot execute arbitrary code."}',
    'openrouter.ai',
    freeNemotronModels.first,
    usage,
  );
  NemotronEvaluationRunner runner(
    Map<String, dynamic> checkpoint,
    NemotronInvocation invoke, {
    Future<void> Function(Map<String, dynamic>)? save,
  }) => NemotronEvaluationRunner(
    checkpoint: checkpoint,
    scenarios: [scenario],
    invoke: invoke,
    save: save ?? (_) async {},
    requestInterval: Duration.zero,
    delay: (_) async {},
  );

  test('catalog rejects paid, absent, duplicate and unrecognized routes', () {
    Map<String, dynamic> catalog(Map<String, dynamic> pricing) => {
      'data': [
        {'id': freeNemotronModels.first, 'pricing': pricing},
      ],
    };
    expect(
      selectFreeNemotronModels(catalog({'prompt': '0', 'completion': '0'}), [
        freeNemotronModels.first,
      ]),
      hasLength(1),
    );
    for (final price in [
      {'prompt': '0', 'completion': '0.001'},
      {'prompt': '0', 'completion': '0', 'request': '0.01'},
      {'prompt': '0', 'completion': '0', 'request': 'unknown'},
      {'prompt': '0', 'completion': '0', 'overrides': []},
    ]) {
      expect(
        () => selectFreeNemotronModels(catalog(price), [
          freeNemotronModels.first,
        ]),
        throwsFormatException,
      );
    }
    expect(
      () => selectFreeNemotronModels({'data': []}, [freeNemotronModels.first]),
      throwsFormatException,
    );
    expect(
      () => selectFreeNemotronModels(
        catalog({'prompt': '0', 'completion': '0'}),
        [freeNemotronModels.first, freeNemotronModels.first],
      ),
      throwsFormatException,
    );
    expect(
      () => selectFreeNemotronModels({'data': []}, ['openrouter/free']),
      throwsFormatException,
    );
  });

  test('resume requires the frozen contract and operation identities', () {
    final original = state();
    validateNemotronResume(original, state());
    final changed = state()..['runFingerprint'] = 'changed';
    expect(
      () => validateNemotronResume(original, changed),
      throwsFormatException,
    );
    final corrupt = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
    corrupt['operations'][0]['model'] = 'paid/model';
    expect(
      () => validateNemotronResume(corrupt, original),
      throwsFormatException,
    );
  });

  test(
    'dispatch persists in-flight then success; resume never repeats it',
    () async {
      final checkpoint = state();
      var calls = 0;
      final statuses = <String>[];
      final evaluation = runner(
        checkpoint,
        (_, _, _, _, _) async {
          calls++;
          expect(statuses.last, 'in_flight');
          return answer({
            'prompt_tokens': 4,
            'completion_tokens': 8,
            'cost': 0,
          });
        },
        save: (s) async => statuses.add(s['operations'][0]['status'] as String),
      );
      await evaluation.run();
      await evaluation.run();
      expect(calls, 1);
      expect(checkpoint['status'], 'completed');
      expect(checkpoint['operations'][0]['status'], 'passed');
    },
  );

  test(
    'interrupted in-flight request stays indeterminate and is never replayed',
    () async {
      final checkpoint = state();
      checkpoint['operations'][0]['status'] = 'in_flight';
      await runner(
        checkpoint,
        (_, _, _, _, _) async => fail('Must not dispatch'),
      ).run();
      expect(checkpoint['operations'][0]['status'], 'indeterminate');
      expect(checkpoint['status'], 'incomplete');
    },
  );

  test(
    'repair receives bounded diagnostics and retains failed-attempt usage',
    () async {
      final checkpoint = state();
      var calls = 0;
      await runner(checkpoint, (_, _, _, diagnostics, rejected) async {
        calls++;
        if (calls == 1) {
          return AiResult(
            '{"patches":[]}',
            'openrouter.ai',
            freeNemotronModels.first,
            {'prompt_tokens': 9, 'completion_tokens': 7},
          );
        }
        expect(diagnostics.single, contains('unsupported'));
        expect(rejected, '{"patches":[]}');
        return answer({'prompt_tokens': 10, 'completion_tokens': 8});
      }).run();
      expect(calls, 2);
      final attempts = checkpoint['operations'][0]['attempts'] as List;
      expect(attempts[0]['usage']['prompt_tokens'], 9);
      expect(attempts[1]['success'], isTrue);
    },
  );

  test(
    'quota pauses without switching models and resumes without replay',
    () async {
      final checkpoint = state(models: freeNemotronModels.take(2).toList());
      var calls = 0;
      await runner(checkpoint, (_, _, _, _, _) async {
        calls++;
        if (calls == 2) {
          throw const AiResponseException(
            'http_error',
            'Free quota exhausted.',
            statusCode: 429,
          );
        }
        return answer();
      }).run();
      expect(calls, 2);
      expect(checkpoint['status'], 'blocked');
      final repeated = <String>[];
      await runner(checkpoint, (model, _, _, _, _) async {
        repeated.add(model);
        return answer();
      }).run();
      expect(repeated, [freeNemotronModels[1]]);
      expect(checkpoint['operations'][1]['attempts'], hasLength(2));
    },
  );

  test('per-invocation cap preserves work for explicit resume', () async {
    final checkpoint = state(models: freeNemotronModels.take(2).toList());
    final evaluation = runner(checkpoint, (_, _, _, _, _) async => answer());
    await evaluation.run(maxRequests: 1);
    expect(checkpoint['status'], 'blocked');
    expect(checkpoint['operations'][0]['status'], 'passed');
    expect(checkpoint['operations'][1]['attempts'], isEmpty);
  });

  test('unexpected nonzero reported cost stops all further dispatch', () async {
    final checkpoint = state(models: freeNemotronModels.take(2).toList());
    var calls = 0;
    await runner(checkpoint, (_, _, _, _, _) async {
      calls++;
      return answer({'cost': 0.01});
    }).run();
    expect(calls, 1);
    expect(checkpoint['status'], 'blocked');
    expect(checkpoint['blockedReason'], contains('nonzero cost'));
  });

  test('permanent provider error does not consume three requests', () async {
    final checkpoint = state();
    var calls = 0;
    await runner(checkpoint, (_, _, _, _, _) async {
      calls++;
      throw const AiResponseException(
        'http_error',
        'Profile unsupported.',
        statusCode: 400,
        retryable: false,
      );
    }).run();
    expect(calls, 1);
    expect(checkpoint['operations'][0]['status'], 'failed');
  });

  test('guidance uses guarded transport and retains usage', () async {
    final provider = ChatCompletionProvider(
      Uri.parse(nemotronEvaluationBase),
      freeNemotronModels.first,
      'test-only',
      freeNemotronEvaluation: true,
    );
    final guidance = NemotronScenario(
      id: 'guidance-actionable-test',
      operation: 'guidance',
      prompt: 'Make notes.',
      baseline: scenario.baseline,
    );
    final result = await invokeNemotronGuidance(
      provider,
      guidance,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(request.followRedirects, isFalse);
        expect(body['provider']['max_price'], {'prompt': 0, 'completion': 0});
        expect(body.containsKey('response_format'), isFalse);
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
            'usage': {'prompt_tokens': 11, 'completion_tokens': 5, 'cost': 0},
          }),
          200,
        );
      }),
    );
    expect(result.usage['prompt_tokens'], 11);
    guidance.validate(parseAiOutput(result.text), null);
  });

  test(
    'guidance 429 keeps retry metadata without provider error body',
    () async {
      final provider = ChatCompletionProvider(
        Uri.parse(nemotronEvaluationBase),
        freeNemotronModels.first,
        'test-only',
        freeNemotronEvaluation: true,
      );
      await expectLater(
        invokeNemotronGuidance(
          provider,
          scenario,
          client: MockClient(
            (_) async => http.Response(
              'private provider text',
              429,
              headers: {'retry-after': '30'},
            ),
          ),
        ),
        throwsA(
          isA<AiResponseException>()
              .having((e) => e.statusCode, 'HTTP', 429)
              .having(
                (e) => e.retryAfter,
                'retry-after',
                const Duration(seconds: 30),
              )
              .having(
                (e) => e.message,
                'safe message',
                isNot(contains('private provider text')),
              ),
        ),
      );
    },
  );

  test('malformed model JSON is scored as a correctness failure', () async {
    final checkpoint = state();
    await runner(
      checkpoint,
      (_, _, _, _, _) async => AiResult(
        'invalid JSON',
        'openrouter.ai',
        freeNemotronModels.first,
        {'prompt_tokens': 8, 'completion_tokens': 2},
      ),
    ).run();
    final row = checkpoint['operations'][0];
    expect(row['status'], 'failed');
    expect(row['attempts'], hasLength(3));
    expect(row['attempts'][0]['kind'], 'validation');
  });

  test('billing guard cannot be cleared by resume', () async {
    final checkpoint = state()..['billingGuardTripped'] = true;
    await expectLater(
      runner(checkpoint, (_, _, _, _, _) async => fail('No calls')).run(),
      throwsFormatException,
    );
  });

  test('guidance helper rejects an ordinary provider before network', () async {
    final provider = ChatCompletionProvider(
      Uri.parse('https://example.invalid'),
      'ordinary',
      'test-only',
    );
    await expectLater(
      invokeNemotronGuidance(
        provider,
        scenario,
        client: MockClient((_) async => fail('No calls')),
      ),
      throwsArgumentError,
    );
  });

  test('guidance embedded quota error is preserved', () async {
    final provider = ChatCompletionProvider(
      Uri.parse(nemotronEvaluationBase),
      freeNemotronModels.first,
      'test-only',
      freeNemotronEvaluation: true,
    );
    await expectLater(
      invokeNemotronGuidance(
        provider,
        scenario,
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"code":429,"message":"private text"}}',
            200,
          ),
        ),
      ),
      throwsA(
        isA<AiResponseException>().having((e) => e.statusCode, 'HTTP', 429),
      ),
    );
  });

  test('resume rejects corrupted attempt counts and manifest contents', () {
    final expected = state();
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (s) => s['operations'][0]['attempts'] = List.generate(
        4,
        (n) => {'number': n + 1},
      ),
      (s) => s['operations'][0]['status'] = 'made_up',
      (s) => s['operations'][0]['status'] = 'passed',
      (s) => s['scenarios'][0]['prompt'] = 'changed prompt',
    ]) {
      final corrupted =
          jsonDecode(jsonEncode(expected)) as Map<String, dynamic>;
      mutate(corrupted);
      expect(
        () => validateNemotronResume(corrupted, expected),
        throwsFormatException,
      );
    }
  });
}
