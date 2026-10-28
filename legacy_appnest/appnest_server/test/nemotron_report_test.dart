import 'package:appnest_server/src/modules/builder/nemotron_report.dart';
import 'package:test/test.dart';

const _modelA = 'nvidia/model-a:free';
const _modelB = 'nvidia/model-b:free';

Map<String, dynamic> _attempt({
  bool success = true,
  String kind = 'received',
  Map<String, dynamic>? usage,
}) => {
  'number': 1,
  'elapsedMs': 100,
  'success': success,
  'kind': kind,
  'usage': ?usage,
};

Map<String, dynamic> _operation({
  String model = _modelA,
  String id = 'create-1',
  String operation = 'create',
  String status = 'passed',
  int totalMs = 100,
  List<Map<String, dynamic>>? attempts,
}) => {
  'model': model,
  'case': id,
  'operation': operation,
  'status': status,
  'success': status == 'passed',
  'totalMs': totalMs,
  'attempts': attempts ?? [_attempt()],
};

Map<String, dynamic> _checkpoint(
  List<Map<String, dynamic>> operations, {
  List<Map<String, dynamic>>? scenarios,
}) => {
  'schemaVersion': 1,
  'benchmarkVersion': 'test-v1',
  'createdAt': '2026-10-08T00:00:00Z',
  'updatedAt': '2026-10-08T00:00:00Z',
  'status': 'completed',
  'models': [_modelA, _modelB],
  'source': {'commit': 'abc', 'dirtyTrackedSha256': 'def'},
  'runFingerprint': 'frozen',
  'scenarios':
      scenarios ??
      [
        {'id': 'create-1', 'operation': 'create'},
      ],
  'operations': operations,
};

Map<String, dynamic> _model(
  Map<String, dynamic> result, [
  String id = _modelA,
]) => (result['models'] as Map)[id] as Map<String, dynamic>;

Map<String, dynamic> _recommendation(
  Map<String, dynamic> result, [
  String category = 'create',
]) => (result['recommendations'] as Map)[category] as Map<String, dynamic>;

void main() {
  test(
    'all retry attempts contribute usage, first and eventual rates differ',
    () {
      final result = summarizeNemotronEvaluation(
        _checkpoint([
          _operation(
            totalMs: 300,
            attempts: [
              _attempt(
                success: false,
                kind: 'validation',
                usage: {
                  'prompt_tokens': 10,
                  'completion_tokens': 20,
                  'total_tokens': 30,
                  'completion_tokens_details': {'reasoning_tokens': 4},
                  'cost': 0,
                },
              ),
              _attempt(
                usage: {
                  'prompt_tokens': 40,
                  'completion_tokens': 50,
                  'total_tokens': 90,
                  'completion_tokens_details': {'reasoning_tokens': 6},
                  'cost': 0,
                },
              ),
            ],
          ),
        ]),
      );
      final model = _model(result);
      expect(model['attemptCount'], 2);
      expect(model['firstAttemptPassRateObserved'], 0);
      expect(model['eventualPassRateObserved'], 1);
      expect(model['eventualPassRatePlanned'], 1);
      expect(model['latencyMs']['median'], 300);
      expect(model['usage']['promptTokens'], 50);
      expect(model['usage']['completionTokens'], 70);
      expect(model['usage']['totalTokens'], 120);
      expect(model['usage']['reasoningTokens'], 10);
      expect(model['usage']['complete'], isTrue);
      expect(model['usage']['costReportedUsd'], 0);
      expect(model['usage']['costComplete'], isTrue);
    },
  );

  test(
    'omitted usage is unknown, while partial sums retain known attempts',
    () {
      final result = summarizeNemotronEvaluation(
        _checkpoint([
          _operation(
            attempts: [
              _attempt(success: false, kind: 'timeout'),
              _attempt(
                usage: {
                  'prompt_tokens': 12,
                  'completion_tokens': 7,
                  'total_tokens': 19,
                },
              ),
            ],
          ),
        ]),
      );
      final usage = _model(result)['usage'];
      expect(usage['totalTokens'], 19);
      expect(usage['missingUsageAttempts'], 1);
      expect(usage['complete'], isFalse);
      expect(usage['reasoningTokens'], isNull);
      expect(usage['reasoningComplete'], isFalse);
      expect(usage['costReportedUsd'], isNull);
      expect(usage['costComplete'], isFalse);
      final empty = _model(result, _modelB)['usage'];
      expect(empty['totalTokens'], isNull);
      expect(empty['complete'], isFalse);
      expect(renderNemotronReport(_checkpoint([])), contains('unknown'));
    },
  );

  test(
    'latency quantiles are deterministic and exclude pending and skipped',
    () {
      final rows = [
        for (var i = 1; i <= 20; i++) _operation(id: 'c$i', totalMs: i * 10),
        _operation(status: 'pending', totalMs: 9999, attempts: []),
        _operation(operation: 'sequence', status: 'skipped', totalMs: 9999),
      ];
      final result = summarizeNemotronEvaluation(
        _checkpoint(
          rows.reversed.toList(),
          scenarios: [
            for (var i = 1; i <= 21; i++) {'id': 'c$i', 'operation': 'create'},
            {'id': 's1', 'operation': 'sequence'},
          ],
        ),
      );
      final model = _model(result);
      expect(model['latencyMs']['sampleCount'], 20);
      expect(model['latencyMs']['median'], 105);
      expect(model['latencyMs']['p95'], 190);
    },
  );

  test('skips and absent operations retain the planned denominator', () {
    final result = summarizeNemotronEvaluation(
      _checkpoint(
        [
          _operation(),
          _operation(
            id: 'seq-1',
            operation: 'sequence',
            status: 'skipped',
            attempts: [],
          ),
        ],
        scenarios: [
          {'id': 'create-1', 'operation': 'create'},
          {'id': 'edit-1', 'operation': 'edit'},
          {'id': 'seq-1', 'operation': 'sequence'},
        ],
      ),
    );
    final model = _model(result);
    expect(model['planned'], 3);
    expect(model['completed'], 1);
    expect(model['skipped'], 1);
    expect(model['pending'], 1);
    expect(model['eventualPassRateObserved'], 1);
    expect(model['eventualPassRatePlanned'], closeTo(1 / 3, .0001));
    expect(model['resolvedCoverage'], closeTo(2 / 3, .0001));
    expect(model['categories']['sequence']['planned'], 1);
    expect(model['categories']['sequence']['skipped'], 1);
    expect(_recommendation(result)['status'], 'incomplete_evidence');
  });

  test('transport-only failures do not become model correctness failures', () {
    final result = summarizeNemotronEvaluation(
      _checkpoint([
        _operation(
          status: 'failed',
          attempts: [
            _attempt(success: false, kind: 'http_error')..['httpStatus'] = 503,
            _attempt(success: false, kind: 'timeout'),
          ],
        ),
        _operation(model: _modelB),
      ]),
    );
    final model = _model(result);
    expect(model['failed'], 1);
    expect(model['correctnessFailed'], 0);
    expect(model['correctnessCompleted'], 0);
    expect(model['eventualPassRateObserved'], isNull);
    expect(model['eventualPassRatePlanned'], 0);
    expect(model['availabilityOnlyFailures'], 1);
    expect(model['availabilityFailureAttempts'], 2);
    expect(_recommendation(result)['status'], 'incomplete_evidence');
  });

  test('quota blocks and ambiguous in-flight attempts remain incomplete', () {
    final result = summarizeNemotronEvaluation(
      _checkpoint([
        _operation(
          status: 'blocked',
          attempts: [_attempt(success: false, kind: 'quota_exhausted')],
        ),
        _operation(model: _modelB, status: 'indeterminate'),
      ])..['status'] = 'blocked',
    );
    final model = _model(result);
    expect(model['completed'], 0);
    expect(model['correctnessFailed'], 0);
    expect(model['blocked'], 1);
    expect(model['availabilityFailureAttempts'], 1);
    expect(_model(result, _modelB)['indeterminate'], 1);
    expect(_recommendation(result)['model'], isNull);
    expect(_recommendation(result)['status'], 'incomplete_evidence');
  });

  test('complete category coverage recommends correctness over speed', () {
    final result = summarizeNemotronEvaluation(
      _checkpoint([
        _operation(totalMs: 500),
        _operation(
          model: _modelB,
          status: 'failed',
          totalMs: 10,
          attempts: [_attempt(success: false, kind: 'validation')],
        ),
      ]),
    );
    expect(_recommendation(result)['model'], _modelA);
    expect(_recommendation(result)['status'], 'exploratory_recommendation');
    expect(_recommendation(result, 'edit')['status'], 'incomplete_evidence');
    final markdown = renderNemotronReport(
      _checkpoint([
        _operation(),
        _operation(
          model: _modelB,
          status: 'failed',
          attempts: [
            _attempt(success: false, kind: 'validation')
              ..['diagnostic'] = 'Requested form absent | retry\nneeded',
          ],
        ),
      ]),
    );
    expect(markdown, contains('Failure examples'));
    expect(markdown, contains(r'absent \| retry needed'));
    expect(markdown, contains('Frozen run fingerprint: `frozen`'));
  });

  test('unknown usage does not falsely break an otherwise exact tie', () {
    final result = summarizeNemotronEvaluation(
      _checkpoint([
        _operation(),
        _operation(
          model: _modelB,
          attempts: [
            _attempt(
              usage: {
                'prompt_tokens': 2,
                'completion_tokens': 2,
                'total_tokens': 4,
              },
            ),
          ],
        ),
      ]),
    );
    expect(_recommendation(result)['status'], 'tie');
    expect(_recommendation(result)['model'], isNull);
  });

  test('creation and edit recommendations can choose different models', () {
    final result = summarizeNemotronEvaluation(
      _checkpoint(
        [
          _operation(totalMs: 10),
          _operation(model: _modelB, totalMs: 20),
          _operation(id: 'edit-1', operation: 'edit', totalMs: 40),
          _operation(
            model: _modelB,
            id: 'edit-1',
            operation: 'edit',
            totalMs: 20,
          ),
        ],
        scenarios: [
          {'id': 'create-1', 'operation': 'create'},
          {'id': 'edit-1', 'operation': 'edit'},
        ],
      ),
    );
    expect(_recommendation(result)['model'], _modelA);
    expect(_recommendation(result, 'edit')['model'], _modelB);
  });

  test(
    'frozen catalog and transport adaptations are retained in both reports',
    () {
      final checkpoint = _checkpoint([])
        ..['catalog'] = [
          {
            'id': _modelA,
            'pricing': {'prompt': '0', 'completion': '0'},
            'supported_parameters': ['response_format'],
          },
        ]
        ..['transportProfiles'] = {
          _modelA: 'json_schema',
          _modelB: 'schema_in_instructions',
        };
      final summary = summarizeNemotronEvaluation(checkpoint);
      expect(summary['catalog'], checkpoint['catalog']);
      expect(summary['transportProfiles'], checkpoint['transportProfiles']);
      final markdown = renderNemotronReport(checkpoint);
      expect(markdown, contains('Frozen route configuration'));
      expect(markdown, contains('schema_in_instructions'));
      expect(markdown, contains('response_format'));
    },
  );

  test('historical checkpoints retain explicit OpenRouter behavior', () {
    final historical = _checkpoint([_operation(), _operation(model: _modelB)])
      ..['catalog'] = [
        {
          'id': _modelA,
          'pricing': {'prompt': '0', 'completion': '0'},
          'supportedParameters': ['response_format'],
        },
      ];
    final explicit = {...historical, 'provider': 'openrouter'};
    final summary = summarizeNemotronEvaluation(historical);
    expect(summary, summarizeNemotronEvaluation(explicit));
    expect(renderNemotronReport(historical), renderNemotronReport(explicit));
    expect(summary['provider'], 'openrouter');
    expect(summary['expectedPriceUsd'], 0);
    expect(summary['pricingVerified'], isTrue);
    expect(summary['expectedCostBasis'], 'zero_priced_openrouter_free_route');
    expect(
      renderNemotronReport(historical),
      contains('evaluation (openrouter)'),
    );
    expect(
      renderNemotronReport(historical),
      contains('Expected route price: USD 0'),
    );
    expect(renderNemotronReport(historical), contains('response_format'));
  });

  test(
    'NVIDIA free endpoint metadata does not invent verified cost or quota',
    () {
      const nvidiaModel = 'nvidia/nemotron-super';
      const sourceUrl = 'https://build.nvidia.com/nvidia/nemotron-super';
      final checkpoint =
          _checkpoint([
              _operation(model: nvidiaModel),
            ])
            ..['provider'] = 'nvidia'
            ..['apiBase'] = 'https://integrate.api.nvidia.com/v1'
            ..['models'] = [nvidiaModel]
            ..['catalog'] = [
              {
                'id': nvidiaModel,
                'freeEndpoint': true,
                'sourceUrl': sourceUrl,
                'pricingVerified': false,
                'supportedParameters': null,
              },
            ]
            ..['transportProfiles'] = {
              nvidiaModel: 'nvidia-instruction-schema-v1',
            };
      final summary = summarizeNemotronEvaluation(checkpoint);
      expect(summary['provider'], 'nvidia');
      expect(summary['apiBase'], checkpoint['apiBase']);
      expect(summary['catalog'], checkpoint['catalog']);
      expect(summary['catalog'][0]['freeEndpoint'], isTrue);
      expect(summary['catalog'][0]['sourceUrl'], sourceUrl);
      expect(summary['expectedPriceUsd'], isNull);
      expect(summary['pricingVerified'], isFalse);
      expect(summary['accountLimitsKnown'], isFalse);
      expect(summary['expectedCostBasis'], 'free_developer_endpoint');
      expect(_model(summary, nvidiaModel)['usage']['costReportedUsd'], isNull);
      expect(_model(summary, nvidiaModel)['usage']['costComplete'], isFalse);
      expect(_recommendation(summary)['status'], 'incomplete_evidence');
      final report = renderNemotronReport(checkpoint);
      expect(report, contains('evaluation (nvidia)'));
      expect(
        report,
        contains('free developer endpoint, account limits unknown'),
      );
      expect(report, contains('freeEndpoint: true; pricingVerified: false'));
      expect(report, contains(sourceUrl));
      expect(report, contains('nvidia-instruction-schema-v1'));
      expect(
        report,
        contains('does not infer provider-side schema enforcement'),
      );
      expect(report, isNot(contains('Expected route price: USD 0')));
    },
  );
}
