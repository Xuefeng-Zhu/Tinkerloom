import 'dart:async';

import 'package:appnest_server/src/evaluation/nemotron_parallel_scheduler.dart';
import 'package:appnest_server/src/modules/builder/nemotron_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue, reason: 'Expected asynchronous transition');
}

void main() {
  test('fair lanes overlap distinct models and serialize each model', () async {
    final started = <String>[];
    final active = <String>{};
    final gates = {
      for (final id in ['a1', 'a2', 'b1', 'b2', 'c1', 'c2'])
        id: Completer<void>(),
    };
    var peak = 0;
    final running = runNemotronModelLanes<String>(
      [
        ['a1', 'a2'],
        ['b1', 'b2'],
        ['c1', 'c2'],
      ],
      concurrency: 2,
      shouldStop: () => false,
      execute: (id) async {
        expect(active.add(id[0]), isTrue);
        started.add(id);
        if (active.length > peak) peak = active.length;
        await gates[id]!.future;
        active.remove(id[0]);
        return true;
      },
    );
    await until(() => started.length == 2);
    expect(started, ['a1', 'b1']);
    gates['a1']!.complete();
    await until(() => started.length == 3);
    expect(started.last, 'c1');
    gates['b1']!.complete();
    await until(() => started.length == 4);
    expect(started.last, 'a2');
    gates['c1']!.complete();
    await until(() => started.length == 5);
    expect(started.last, 'b2');
    gates['a2']!.complete();
    await until(() => started.length == 6);
    gates['b2']!.complete();
    gates['c2']!.complete();
    await running;
    expect(peak, 2);
    expect(active, isEmpty);
  });

  test('retry retains its lane head and yields to other models', () async {
    final started = <String>[];
    await runNemotronModelLanes<String>(
      [
        ['a1', 'a2'],
        ['b1', 'b2'],
      ],
      concurrency: 1,
      shouldStop: () => false,
      execute: (id) async {
        started.add(id);
        return id != 'a1' || started.where((item) => item == id).length > 1;
      },
    );
    expect(started, ['a1', 'b1', 'a1', 'b2', 'a2']);
  });

  test('errors stop queued lanes and drain already-started work', () async {
    final failGate = Completer<void>();
    final drainGate = Completer<void>();
    final started = <String>[];
    var ended = false;
    final running = runNemotronModelLanes<String>(
      [
        ['a'],
        ['b'],
        ['c'],
      ],
      concurrency: 2,
      shouldStop: () => false,
      execute: (id) async {
        started.add(id);
        if (id == 'a') {
          await failGate.future;
          throw StateError('save failed');
        }
        await drainGate.future;
        return true;
      },
    );
    final checked = expectLater(
      running,
      throwsStateError,
    ).whenComplete(() => ended = true);
    await until(() => started.length == 2);
    failGate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(ended, isFalse);
    expect(started, ['a', 'b']);
    drainGate.complete();
    await checked;
    expect(ended, isTrue);
    expect(started, ['a', 'b']);
  });

  final scenarios = [
    for (var i = 0; i < 3; i++)
      NemotronScenario(
        id: 'unsupported-$i',
        operation: 'unsupported',
        prompt: 'Execute arbitrary code.',
        baseline: starterTemplates()['reading']!,
      ),
  ];
  Map<String, dynamic> checkpoint({
    int concurrency = 1,
    Duration interval = const Duration(seconds: 4),
  }) => newNemotronCheckpoint(
    models: freeNemotronModels.take(2).toList(),
    scenarios: scenarios,
    catalog: const [],
    source: const {'commit': 'test', 'contractSourceSha256': 'fixed'},
    concurrency: concurrency,
    requestInterval: interval,
  );

  test('execution parameters freeze resume identity', () {
    final serial = checkpoint();
    expect(serial['execution']['pacing'], 'serial-delay');
    final parallel = checkpoint(concurrency: 4);
    expect(parallel['execution']['pacing'], 'global-dispatch');
    expect(parallel['execution']['perModelSequential'], isTrue);
    expect(parallel['runFingerprint'], isNot(serial['runFingerprint']));
    expect(
      () => validateNemotronResume(serial, parallel),
      throwsFormatException,
    );
    final differentPacing = checkpoint(interval: const Duration(seconds: 5));
    expect(
      () => validateNemotronResume(serial, differentPacing),
      throwsFormatException,
    );
    for (final invalid in [0, 5]) {
      expect(() => checkpoint(concurrency: invalid), throwsArgumentError);
    }
  });

  test(
    'default retains serial scenario/model rotation and timestamps',
    () async {
      final state = checkpoint();
      final called = <String>[];
      await NemotronEvaluationRunner(
        checkpoint: state,
        scenarios: scenarios,
        requestInterval: Duration.zero,
        delay: (_) async {},
        save: (_) async {},
        invoke: (model, scenario, _, _, _) async {
          called.add('${scenario.id}:${freeNemotronModels.indexOf(model)}');
          return AiResult(
            '{"unsupported":"Cannot execute arbitrary code."}',
            'test',
            model,
            const {},
          );
        },
      ).run();
      expect(called, [
        'unsupported-0:0',
        'unsupported-0:1',
        'unsupported-1:1',
        'unsupported-1:0',
        'unsupported-2:0',
        'unsupported-2:1',
      ]);
      expect(state['status'], 'completed');
      expect(
        state['operations'][0]['attempts'][0]['dispatchedAt'],
        isA<String>(),
      );
      expect(
        state['operations'][0]['attempts'][0]['completedAt'],
        isA<String>(),
      );
    },
  );

  test('runner rejects concurrency differing from frozen checkpoint', () async {
    await expectLater(
      NemotronEvaluationRunner(
        checkpoint: checkpoint(),
        scenarios: scenarios,
        concurrency: 4,
        save: (_) async {},
        invoke: (_, _, _, _, _) async => throw StateError('must not dispatch'),
      ).run(),
      throwsFormatException,
    );
  });

  test(
    'a guard observed during global pacing cancels queued dispatch',
    () async {
      final state = checkpoint(concurrency: 2);
      final response = Completer<AiResult>();
      final pacing = Completer<void>();
      var pacingCalls = 0;
      var calls = 0;
      final evaluation = NemotronEvaluationRunner(
        checkpoint: state,
        scenarios: scenarios,
        concurrency: 2,
        delay: (duration) async {
          expect(duration, greaterThan(Duration.zero));
          expect(duration, lessThanOrEqualTo(const Duration(seconds: 4)));
          pacingCalls++;
          await pacing.future;
        },
        save: (_) async {},
        invoke: (_, _, _, _, _) {
          calls++;
          return response.future;
        },
      ).run();
      await until(() => pacingCalls == 1);
      response.completeError(
        const AiResponseException(
          'http_error',
          'Rate limited.',
          statusCode: 429,
        ),
      );
      await until(() => state['status'] == 'blocked');
      pacing.complete();
      await evaluation;
      expect(calls, 1);
      final rows = (state['operations'] as List).cast<Map>();
      expect(rows.where((r) => r['status'] == 'in_flight'), isEmpty);
      expect(rows.where((r) => r['inFlightAttempt'] != null), isEmpty);
      expect(state['executionObserved']['requestsDispatchedThisInvocation'], 1);
    },
  );

  test(
    'resume resets latest invocation stats when no new call is sent',
    () async {
      final state = checkpoint(concurrency: 2);
      for (final row in state['operations'] as List) {
        row['status'] = 'in_flight';
      }
      state['executionObserved'] = {
        'requestsDispatchedThisInvocation': 999,
        'peakConcurrentRequestsThisInvocation': 4,
      };
      await NemotronEvaluationRunner(
        checkpoint: state,
        scenarios: scenarios,
        concurrency: 2,
        requestInterval: Duration.zero,
        save: (_) async {},
        invoke: (_, _, _, _, _) async => throw StateError('must not replay'),
      ).run();
      expect(state['executionObserved'], {
        'requestsDispatchedThisInvocation': 0,
        'peakConcurrentRequestsThisInvocation': 0,
      });
      expect(state['status'], 'incomplete');
    },
  );
}
