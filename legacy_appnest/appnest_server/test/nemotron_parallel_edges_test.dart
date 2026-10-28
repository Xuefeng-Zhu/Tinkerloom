import 'dart:async';
import 'dart:convert';

import 'package:appnest_server/src/modules/builder/nemotron_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

final _models = freeNemotronModels.take(3).toList();
final _simpleCases = [
  for (final id in ['first', 'next'])
    NemotronScenario(
      id: 'unsupported-$id',
      operation: 'unsupported',
      prompt: 'Run arbitrary executable code.',
      baseline: starterTemplates()['reading']!,
    ),
];

Map<String, dynamic> _state({
  List<String>? models,
  List<NemotronScenario>? scenarios,
  int concurrency = 2,
}) => newNemotronCheckpoint(
  models: models ?? _models,
  scenarios: scenarios ?? _simpleCases,
  catalog: const [],
  source: const {'commit': 'synthetic-test', 'contractSourceSha256': 'fixed'},
  concurrency: concurrency,
  requestInterval: Duration.zero,
);

AiResult _answer(String model, {Map<String, dynamic> usage = const {}}) =>
    AiResult(
      '{"unsupported":"AppNest does not execute arbitrary code."}',
      'synthetic-test',
      model,
      usage,
    );

Map<String, dynamic> _row(
  Map<String, dynamic> state,
  String model,
  String scenario,
) => (state['operations'] as List).cast<Map<String, dynamic>>().singleWhere(
  (row) => row['model'] == model && row['case'] == scenario,
);

Future<T> _bounded<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 5));

NemotronEvaluationRunner _runner(
  Map<String, dynamic> state,
  NemotronInvocation invoke, {
  List<NemotronScenario>? scenarios,
  Future<void> Function(Map<String, dynamic>)? save,
  int concurrency = 2,
}) => NemotronEvaluationRunner(
  checkpoint: state,
  scenarios: scenarios ?? _simpleCases,
  invoke: invoke,
  save: save ?? (_) async {},
  requestInterval: Duration.zero,
  delay: (_) async {},
  concurrency: concurrency,
);

void main() {
  test(
    'global cap reserves one request before delayed in-flight saving',
    () async {
      final state = _state();
      final saving = Completer<void>();
      final releaseSave = Completer<void>();
      final calls = <String>[];
      final evaluation = _runner(
        state,
        (model, scenario, _, _, _) async {
          calls.add('$model/${scenario.id}');
          return _answer(model);
        },
        save: (snapshot) async {
          if ((snapshot['operations'] as List).any(
                (row) => row['status'] == 'in_flight',
              ) &&
              !saving.isCompleted) {
            saving.complete();
            await releaseSave.future;
          }
        },
      );
      final running = evaluation.run(maxRequests: 1);
      await _bounded(saving.future);
      expect(calls, isEmpty);
      releaseSave.complete();
      await _bounded(running);
      expect(calls, hasLength(1));
      expect(state['status'], 'blocked');
      final rows = (state['operations'] as List).cast<Map>();
      expect(rows.expand((row) => row['attempts'] as List), hasLength(1));
      expect(rows.where((row) => row['status'] == 'in_flight'), isEmpty);
      expect(rows.where((row) => row.containsKey('inFlightAttempt')), isEmpty);
      expect(rows.where((row) => row['status'] == 'failed'), isEmpty);
    },
  );

  for (final guard in ['billing', 'quota', 'asynchronous']) {
    test('$guard stops new dispatch while draining an active response', () async {
      final state = _state();
      final first = Completer<AiResult>();
      final other = Completer<AiResult>();
      final bothStarted = Completer<void>();
      final stopSaved = Completer<void>();
      final calls = <String>[];
      final evaluation = _runner(
        state,
        (model, scenario, _, _, _) {
          calls.add('$model/${scenario.id}');
          if (calls.length == 2) bothStarted.complete();
          if (model == _models[0]) return first.future;
          if (model == _models[1]) return other.future;
          fail('No third model may dispatch after the stop guard.');
        },
        save: (snapshot) async {
          if ({'blocked', 'incomplete'}.contains(snapshot['status']) &&
              !stopSaved.isCompleted) {
            stopSaved.complete();
          }
        },
      );
      final running = evaluation.run();
      await _bounded(bothStarted.future);
      if (guard == 'billing') {
        first.complete(_answer(_models[0], usage: {'cost': 0.01}));
      } else {
        first.completeError(
          AiResponseException(
            'http_error',
            'Synthetic provider stop.',
            statusCode: guard == 'quota' ? 429 : 202,
          ),
        );
      }
      await _bounded(stopSaved.future);
      expect(calls, hasLength(2));
      if (guard == 'quota') {
        // A drained validation failure must be retained without a repair call.
        other.complete(
          AiResult('invalid JSON', 'synthetic-test', _models[1], {
            'completion_tokens': 3,
          }),
        );
      } else {
        other.complete(_answer(_models[1], usage: {'completion_tokens': 5}));
      }
      await _bounded(running);
      expect(calls, hasLength(2));
      expect(
        state['status'],
        guard == 'asynchronous' ? 'incomplete' : 'blocked',
      );
      expect(
        _row(state, _models[0], 'unsupported-first')['status'],
        guard == 'asynchronous' ? 'indeterminate' : 'blocked',
      );
      final drained = _row(state, _models[1], 'unsupported-first');
      expect(drained['attempts'], hasLength(1));
      expect(
        (drained['attempts'] as List).single['usage']['completion_tokens'],
        guard == 'quota' ? 3 : 5,
      );
      expect(drained['status'], guard == 'quota' ? 'pending' : 'passed');
      expect(_row(state, _models[2], 'unsupported-first')['status'], 'pending');
      expect(_row(state, _models[0], 'unsupported-next')['attempts'], isEmpty);
      if (guard == 'billing') {
        expect(state['billingGuardTripped'], isTrue);
        await expectLater(evaluation.run(), throwsFormatException);
      }
    });
  }

  for (final firstStatus in [429, 202]) {
    test(
      'billing evidence wins after an earlier HTTP $firstStatus stop',
      () async {
        final state = _state();
        final earlier = Completer<AiResult>();
        final later = Completer<AiResult>();
        final bothStarted = Completer<void>();
        final earlierStopSaved = Completer<void>();
        var calls = 0;
        final evaluation = _runner(
          state,
          (model, _, _, _, _) {
            calls++;
            if (calls == 2) bothStarted.complete();
            return model == _models.first ? earlier.future : later.future;
          },
          save: (snapshot) async {
            if ({'blocked', 'incomplete'}.contains(snapshot['status']) &&
                !earlierStopSaved.isCompleted) {
              earlierStopSaved.complete();
            }
          },
        );
        final running = evaluation.run();
        await _bounded(bothStarted.future);
        earlier.completeError(
          AiResponseException(
            'http_error',
            'Synthetic earlier stop.',
            statusCode: firstStatus,
          ),
        );
        await _bounded(earlierStopSaved.future);
        later.complete(_answer(_models[1], usage: {'cost': 0.01}));
        await _bounded(running);
        expect(calls, 2);
        expect(state['billingGuardTripped'], isTrue);
        expect(state['status'], 'blocked');
        expect(state['blockedReason'], contains('nonzero cost'));
        expect(
          _row(state, _models[1], 'unsupported-first')['status'],
          'blocked',
        );
        await expectLater(evaluation.run(), throwsFormatException);
      },
    );
  }

  test(
    'failed pre-dispatch save stops queued work and drains a started call',
    () async {
      final state = _state();
      final activeResponse = Completer<AiResult>();
      final failedSaveObserved = Completer<void>();
      final calls = <String>[];
      var failed = false;
      final evaluation = _runner(
        state,
        (model, _, _, _, _) {
          calls.add(model);
          return activeResponse.future;
        },
        save: (snapshot) async {
          final unsent = _row(snapshot, _models[1], 'unsupported-first');
          if (!failed && unsent['status'] == 'in_flight') {
            failed = true;
            failedSaveObserved.complete();
            throw StateError('Synthetic checkpoint write failure');
          }
        },
      );
      final running = evaluation.run();
      final failure = expectLater(running, throwsA(isA<StateError>()));
      await _bounded(failedSaveObserved.future);
      expect(calls, [_models.first]);
      expect(
        _row(state, _models.first, 'unsupported-first')['status'],
        'in_flight',
      );
      activeResponse.complete(
        _answer(_models.first, usage: {'completion_tokens': 7}),
      );
      await _bounded(failure);
      expect(calls, [_models.first]);
      expect(
        _row(state, _models.first, 'unsupported-first')['status'],
        'passed',
      );
      final unsent = _row(state, _models[1], 'unsupported-first');
      expect(unsent['attempts'], isEmpty);
      expect(unsent['status'], 'pending');
      expect(unsent.containsKey('inFlightAttempt'), isFalse);
      expect(_row(state, _models[2], 'unsupported-first')['status'], 'pending');
      expect(state['status'], 'incomplete');
      expect(state['blockedReason'], contains('Checkpoint write failed'));
    },
  );

  test(
    'model lane finishes repairs before its own dependent sequence',
    () async {
      final create = nemotronScenarios().singleWhere(
        (scenario) => scenario.id == 'create-focus-clock',
      );
      final sequence = nemotronSequences().singleWhere(
        (scenario) => scenario.id == 'sequence-focus-clock',
      );
      final scenarios = [create, sequence];
      final models = _models.take(2).toList();
      final state = _state(models: models, scenarios: scenarios);
      final slowCreation = Completer<AiResult>();
      final fastSequenceStarted = Completer<void>();
      final active = <String, int>{};
      final creates = <String, int>{};
      final calls = <String>[];
      AppSpec generated(String model) => create.baseline.patch({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': 'Synthetic ${models.indexOf(model)} focus',
      }, () => throw StateError('No IDs'));
      final evaluation = _runner(
        state,
        (model, scenario, baseline, diagnostics, rejected) async {
          active[model] = (active[model] ?? 0) + 1;
          expect(
            active[model],
            1,
            reason: 'Same-model calls must not overlap.',
          );
          calls.add('$model/${scenario.id}');
          try {
            if (scenario.operation == 'create') {
              creates[model] = (creates[model] ?? 0) + 1;
              if (model == models.first && creates[model] == 1) {
                return AiResult('invalid JSON', 'synthetic-test', model, {});
              }
              if (model == models.first) {
                expect(creates[model], 2);
                expect(rejected, 'invalid JSON');
                expect(diagnostics.single, contains('valid JSON'));
                return AiResult(
                  jsonEncode(generated(model).toJson()),
                  'synthetic-test',
                  model,
                  {},
                );
              }
              return await slowCreation.future;
            }
            expect(baseline.name, generated(model).name);
            expect(_row(state, model, create.id)['status'], 'passed');
            final clock = baseline.views.singleWhere((v) => v.type == 'clock');
            if (model == models.first) fastSequenceStarted.complete();
            return AiResult(
              jsonEncode({
                'patches': [
                  {
                    'type': 'UpdateView',
                    'viewId': clock.id,
                    'view': {
                      ...clock.toJson()..remove('id'),
                      'options': {
                        ...clock.options,
                        'style': 'analog',
                        'showSeconds': false,
                      },
                    },
                  },
                ],
              }),
              'synthetic-test',
              model,
              {},
            );
          } finally {
            active[model] = active[model]! - 1;
          }
        },
        scenarios: scenarios,
      );
      final running = evaluation.run();
      await _bounded(fastSequenceStarted.future);
      expect(
        calls.where((call) => call == '${models.last}/${sequence.id}'),
        isEmpty,
      );
      expect(_row(state, models.last, sequence.id)['status'], 'pending');
      slowCreation.complete(
        AiResult(
          jsonEncode(generated(models.last).toJson()),
          'synthetic-test',
          models.last,
          {},
        ),
      );
      await _bounded(running);
      expect(state['status'], 'completed');
      expect(creates, {models.first: 2, models.last: 1});
      expect(calls, hasLength(5));
      expect(
        (state['operations'] as List).every((row) => row['status'] == 'passed'),
        isTrue,
      );
    },
  );

  test(
    'all interrupted model lanes remain indeterminate without replay',
    () async {
      final models = _models.take(2).toList();
      final state = _state(models: models);
      for (final model in models) {
        final interrupted = _row(state, model, 'unsupported-first');
        interrupted['status'] = 'in_flight';
        interrupted['inFlightAttempt'] = 1;
      }
      final calledCases = <String>[];
      await _runner(state, (model, scenario, _, _, _) async {
        calledCases.add(scenario.id);
        return _answer(model);
      }).run();
      expect(calledCases, ['unsupported-next', 'unsupported-next']);
      for (final model in models) {
        expect(
          _row(state, model, 'unsupported-first')['status'],
          'indeterminate',
        );
        expect(_row(state, model, 'unsupported-first')['attempts'], isEmpty);
        expect(_row(state, model, 'unsupported-next')['status'], 'passed');
      }
      expect(state['status'], 'incomplete');
    },
  );
}
