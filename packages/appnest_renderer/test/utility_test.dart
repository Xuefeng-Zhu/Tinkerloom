import 'dart:async';
import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FaultStore extends MemoryUtilityTimerStore {
  bool failRead = false, failWrite = false;
  Completer<void>? gate;
  final phases = <String>[];
  @override
  Future<Map<String, dynamic>?> read(String viewId) async {
    if (failRead) throw StateError('storage read failed');
    return super.read(viewId);
  }

  @override
  Future<void> write(String viewId, Map<String, dynamic> value) async {
    await gate?.future;
    if (failWrite) throw StateError('storage write failed');
    phases.add(value['phase'] as String);
    return super.write(viewId, value);
  }
}

class TimedPreview extends PreviewRuntimeAdapter {
  @override
  final UtilityTimerController timerController;
  TimedPreview(super.spec, this.timerController);
}

AppSpec clockStyle(String style) {
  final spec = focusTemplate();
  final view = spec.view('localClock').toJson()..remove('id');
  view['options'] = {'style': style, 'hourFormat': '24', 'showSeconds': true};
  return spec.patch({
    'type': 'UpdateView',
    'viewId': 'localClock',
    'view': view,
  }, () => 'unused');
}

Widget screen(
  RuntimeAdapter adapter,
  DateTime Function() now, {
  double scale = 1,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: MiniAppRuntime(adapter: adapter, clock: now),
    ),
  ),
);

void main() {
  test('timer pauses, resumes and restores exact deadlines across controller lifetimes', () async {
    var now = DateTime.utc(2026, 9, 23, 10);
    final store = MemoryUtilityTimerStore();
    var controller = UtilityTimerController(store: store, now: () => now);
    await controller.start('timer', durationMinutes: 25);
    now = now.add(const Duration(minutes: 5));
    await controller.pause('timer');
    expect(controller.stateFor('timer')!.remainingAt(now), 20 * 60000);
    now = now.add(const Duration(minutes: 15));
    expect(controller.stateFor('timer')!.remainingAt(now), 20 * 60000);
    controller.dispose();
    controller = UtilityTimerController(store: store, now: () => now);
    expect((await controller.load('timer')).phase, 'paused');
    await controller.resume('timer');
    now = now.add(const Duration(minutes: 2));
    controller.dispose();
    controller = UtilityTimerController(store: store, now: () => now);
    expect((await controller.load('timer')).remainingAt(now), 18 * 60000);
    now = now.add(const Duration(minutes: 30));
    expect(controller.stateFor('timer')!.phaseAt(now), 'complete');
    expect(controller.stateFor('timer')!.remainingAt(now), 0);
    await controller.reset('timer', durationMinutes: 45);
    expect(controller.stateFor('timer')!.remainingAt(now), 45 * 60000);
    controller.dispose();
  });
  test('deadline rollback is clamped and new config does not change an active timer', () async {
    var now = DateTime.utc(2026, 9, 23, 10);
    final controller = UtilityTimerController(now: () => now);
    await controller.start('timer', durationMinutes: 1);
    final deadline = controller.stateFor('timer')!.deadline;
    await controller.load('timer', durationMinutes: 180);
    expect(controller.stateFor('timer')!.deadline, deadline);
    now = now.subtract(const Duration(days: 1));
    expect(controller.stateFor('timer')!.remainingAt(now), 60000);
    await controller.reset('timer', durationMinutes: 180);
    expect(controller.stateFor('timer')!.durationSeconds, 10800);
    controller.dispose();
  });
  test(
    'load/write failures are retryable without invented successful state',
    () async {
      final store = FaultStore()..failRead = true;
      final controller = UtilityTimerController(store: store);
      await expectLater(controller.load('timer'), throwsStateError);
      expect(controller.stateFor('timer'), isNull);
      store.failRead = false;
      await controller.load('timer');
      store.failWrite = true;
      await expectLater(controller.start('timer'), throwsStateError);
      expect(controller.stateFor('timer')!.phase, 'ready');
      store.failWrite = false;
      await controller.start('timer');
      expect(controller.stateFor('timer')!.phase, 'running');
      controller.dispose();
    },
  );
  test(
    'corrupt persisted state is visible instead of silently resetting',
    () async {
      final store = MemoryUtilityTimerStore();
      await store.write('timer', {
        'version': 1,
        'phase': 'running',
        'durationSeconds': 1500,
        'remainingMilliseconds': 1500000,
        'deadline': 'not a date',
      });
      final controller = UtilityTimerController(store: store);
      await expectLater(controller.load('timer'), throwsFormatException);
      expect(controller.stateFor('timer'), isNull);
      await controller.resetSaved('timer', durationMinutes: 10);
      expect(controller.stateFor('timer')!.phase, 'ready');
      await controller.start('timer');
      expect(controller.stateFor('timer')!.durationSeconds, 600);
      expect(controller.stateFor('timer')!.phase, 'running');
      controller.dispose();
    },
  );
  test('rapid operations serialize writes and disposal tolerates pending persistence', () async {
    final store = FaultStore()..gate = Completer<void>();
    final controller = UtilityTimerController(store: store);
    final start = controller.start('timer');
    final pause = controller.pause('timer');
    final reset = controller.reset('timer', durationMinutes: 10);
    store.gate!.complete();
    await Future.wait([start, pause, reset]);
    expect(store.phases, ['running', 'paused', 'ready']);
    expect((await store.read('timer'))!['durationSeconds'], 600);
    store.gate = Completer<void>();
    final pending = controller.start('timer');
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    store.gate!.complete();
    await pending;
    expect((await store.read('timer'))!['phase'], 'running');
  });
  test(
    'preview timers are isolated across adapters and appearance forks',
    () async {
      final a = PreviewRuntimeAdapter(focusTemplate()),
          b = PreviewRuntimeAdapter(focusTemplate());
      await a.timerController.start('focusTimer');
      expect((await b.timerController.load('focusTimer')).phase, 'ready');
      final styled = a.spec.patch({
        'type': 'SetTheme',
        'theme': 'amber',
      }, () => 'unused');
      a.applyPresentationSpec(styled);
      expect(a.timerController.stateFor('focusTimer')!.phase, 'running');
      final fork = a.forkPresentation(styled);
      expect((await fork.timerController.load('focusTimer')).phase, 'ready');
      a.dispose();
      b.dispose();
      fork.dispose();
    },
  );
  testWidgets(
    'utility-only runtime retains timer across navigation, appearance and resume',
    (tester) async {
      var now = DateTime(2026, 9, 23, 10);
      final json =
          jsonDecode(focusTemplate().canonical) as Map<String, dynamic>;
      (json['navigation']['pages'] as List).add({
        'id': 'clockPage',
        'title': 'Clock',
        'viewIds': ['localClock'],
      });
      (json['navigation']['tabs'] as List).add({
        'pageId': 'clockPage',
        'label': 'Clock',
        'icon': 'today',
      });
      final adapter = TimedPreview(
        AppSpec.parse(jsonEncode(json)),
        UtilityTimerController(now: () => now),
      );
      await tester.pumpWidget(screen(adapter, () => now));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      final deadline = adapter.timerController.stateFor('focusTimer')!.deadline;
      await tester.tap(find.text('Clock').last);
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 5));
      await tester.tap(find.text('Focus').last);
      await tester.pumpAndSettle();
      expect(find.text('20:00'), findsOneWidget);
      adapter.applyPresentationSpec(
        adapter.spec.patch({
          'type': 'SetTheme',
          'theme': 'amber',
        }, () => 'unused'),
      );
      await tester.pumpAndSettle();
      expect(
        adapter.timerController.stateFor('focusTimer')!.deadline,
        deadline,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Focus complete'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );
  testWidgets(
    'timer shows loading and action failures with an actionable retry',
    (tester) async {
      final store = FaultStore()..failRead = true;
      final adapter = TimedPreview(
        focusTemplate(),
        UtilityTimerController(store: store),
      );
      await tester.pumpWidget(screen(adapter, DateTime.now));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load this timer. Try again.'),
        findsOneWidget,
      );
      store.failRead = false;
      await tester.ensureVisible(find.text('Retry timer'));
      await tester.tap(find.text('Retry timer'));
      await tester.pumpAndSettle();
      store.failWrite = true;
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save the timer change. Try the action again.'),
        findsOneWidget,
      );
      expect(find.text('Start'), findsOneWidget);
      store.failWrite = false;
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );
  testWidgets(
    'explicit saved-timer reset recovers corrupt storage and exposes write failure',
    (tester) async {
      final store = FaultStore();
      await store.write('focusTimer', {'version': 999, 'phase': 'corrupt'});
      final adapter = TimedPreview(
        focusTemplate(),
        UtilityTimerController(store: store),
      );
      await tester.pumpWidget(screen(adapter, DateTime.now));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load this timer. Try again.'),
        findsOneWidget,
      );
      store.failWrite = true;
      await tester.ensureVisible(find.text('Reset saved timer'));
      await tester.tap(find.text('Reset saved timer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save the timer change. Try the action again.'),
        findsOneWidget,
      );
      expect(adapter.timerController.stateFor('focusTimer'), isNull);
      store.failWrite = false;
      await tester.tap(find.text('Reset saved timer'));
      await tester.pumpAndSettle();
      expect(find.text('25:00'), findsOneWidget);
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );

  for (final style in ['analog', 'digital']) {
    testWidgets(
      '$style clock is accessible at phone width and 200 percent text',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        final adapter = PreviewRuntimeAdapter(clockStyle(style));
        await tester.pumpWidget(
          screen(adapter, () => DateTime(2026, 9, 23, 17, 6, 9), scale: 2),
        );
        await tester.pumpAndSettle();
        expect(find.text('17:06:09'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Local time: 17:06:09')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('analog-clock-localClock')),
          style == 'analog' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
        adapter.dispose();
      },
    );
  }
}
