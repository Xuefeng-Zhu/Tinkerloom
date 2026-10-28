import 'dart:async';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'repeated invalidations, stream reconnect and resume recover current state',
    (tester) async {
      final adapter = ObservedPreview(starterTemplates()['volunteer']!);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
        ),
      );
      await tester.pumpAndSettle();
      adapter.events.add(null);
      adapter.events.add(null);
      adapter.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('3 records'), findsOneWidget);
      await adapter.events.close();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(adapter.subscriptions, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(adapter.subscriptions, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await adapter.events.close();
      adapter.dispose();
    },
  );
  test(
    'preview mutations are local to an adapter and never alter definitions',
    () async {
      final spec = starterTemplates()['volunteer']!,
          a = PreviewRuntimeAdapter(spec),
          b = PreviewRuntimeAdapter(spec);
      final record = (await a.query('shifts', {})).items.first;
      await a.execute(spec.action('join'), record, {}, 'test');
      expect((await a.query('shifts', {})).items.first.claimed, true);
      expect((await b.query('shifts', {})).items.first.claimed, false);
      expect(a.preview, true);
      a.dispose();
      b.dispose();
    },
  );
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    for (final entry in starterTemplates().entries) {
      testWidgets('${entry.key} semantic runtime at $size with large text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final adapter = PreviewRuntimeAdapter(entry.value);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.5),
              ),
              child: Scaffold(body: MiniAppRuntime(adapter: adapter)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Synthetic records'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        adapter.dispose();
      });
    }
  }
}

class ObservedPreview extends PreviewRuntimeAdapter {
  ObservedPreview(super.spec);
  late StreamController<void> events;
  int subscriptions = 0;
  @override
  Stream<void> watch() {
    subscriptions++;
    events = StreamController<void>.broadcast();
    return events.stream;
  }
}
