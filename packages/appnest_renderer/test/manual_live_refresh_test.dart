import 'dart:async';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class OfflineLiveAdapter extends PreviewRuntimeAdapter {
  OfflineLiveAdapter(super.spec);
  @override
  bool get preview => false;
  int reads = 0;
  int subscriptions = 0;
  StreamController<void>? events;
  @override
  Stream<void> watch() {
    subscriptions++;
    events = StreamController<void>.broadcast();
    return events!.stream;
  }

  @override
  Future<RuntimePage> query(String collectionId, Map<String, dynamic> query) {
    reads++;
    return super.query(collectionId, query);
  }

  @override
  Future<RuntimeSummary> summary(
    String collectionId,
    Map<String, dynamic> query,
    String groupFieldId,
  ) {
    reads++;
    return super.summary(collectionId, query, groupFieldId);
  }

  @override
  Future<Map<String, dynamic>> aggregate(
    String collectionId,
    Map<String, dynamic> query,
    Map<String, dynamic> aggregate,
  ) {
    reads++;
    return super.aggregate(collectionId, query, aggregate);
  }

  @override
  Future<RuntimeItem> get(String recordId) {
    reads++;
    return super.get(recordId);
  }
}

void main() {
  for (final entry in <String, AppSpec>{
    'legacy': starterTemplates()['reading']!,
    'rich': dailyPlannerTemplate(),
  }.entries) {
    testWidgets('${entry.key} closed live stream does not auto-reconnect', (
      tester,
    ) async {
      final adapter = OfflineLiveAdapter(entry.value);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
        ),
      );
      await tester.pumpAndSettle();
      final initial = adapter.reads;
      await adapter.events!.close();
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(adapter.reads, initial);
      expect(adapter.subscriptions, 1);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    });
    testWidgets(
      '${entry.key} live runtime refreshes and reconnects only on explicit action',
      (tester) async {
        final adapter = OfflineLiveAdapter(entry.value);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
          ),
        );
        await tester.pumpAndSettle();
        expect(adapter.reads, greaterThan(0));
        var initial = adapter.reads;
        await tester.pump(const Duration(seconds: 90));
        await tester.pumpAndSettle();
        expect(adapter.reads, initial, reason: 'foreground idle must not poll');
        final refresh = entry.key == 'legacy'
            ? find.byTooltip('Refresh records')
            : find.byTooltip('Refresh page');
        expect(refresh, findsOneWidget);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(
          adapter.reads,
          greaterThan(initial),
          reason: 'manual refresh reads current data',
        );
        initial = adapter.reads;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        adapter.events!.add(null);
        await tester.pump(const Duration(seconds: 90));
        await tester.pumpAndSettle();
        expect(
          adapter.reads,
          initial,
          reason: 'background events must not poll',
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(adapter.reads, initial, reason: 'resume must not poll');
        expect(adapter.subscriptions, 1);
        adapter.events!.addError(StateError('offline'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 15));
        await tester.pumpAndSettle();
        expect(adapter.reads, initial, reason: 'stream error must not poll');
        expect(
          adapter.subscriptions,
          1,
          reason: 'stream error must not reconnect automatically',
        );
        if (entry.key == 'legacy') {
          await tester.tap(find.text('Reconnecting — refresh connection'));
        } else {
          await tester.tap(find.text('Refresh').first);
        }
        await tester.pumpAndSettle();
        expect(adapter.subscriptions, 2);
        expect(adapter.reads, greaterThan(initial));
        await tester.pumpWidget(const SizedBox());
        await adapter.events?.close();
        adapter.dispose();
      },
    );
  }
  testWidgets('rich live manual refresh is disabled while a form is dirty', (
    tester,
  ) async {
    final adapter = OfflineLiveAdapter(dailyPlannerTemplate());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiniAppRuntime(
            adapter: adapter,
            initialLocation: const MiniAppLocation(
              'taskEditorPage',
              recordId: '2',
              editing: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final refresh = find.byKey(const ValueKey('refresh-runtime-page'));
    expect(refresh, findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Unsaved local edit');
    await tester.pump();
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    await adapter.events?.close();
    adapter.dispose();
  });
}
