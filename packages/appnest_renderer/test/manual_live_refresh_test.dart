import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class OfflineLiveAdapter extends PreviewRuntimeAdapter {
  OfflineLiveAdapter(super.spec);
  @override
  bool get preview => false;
  int reads = 0;
  final queries = <Map<String, dynamic>>[];
  int imageReads = 0;
  bool failGet = false;
  Completer<void>? queryGate;
  Completer<void>? executeGate;
  int writes = 0;
  int subscriptions = 0;
  StreamController<void>? events;
  @override
  Stream<void> watch() {
    subscriptions++;
    events = StreamController<void>.broadcast();
    return events!.stream;
  }

  @override
  Future<RuntimePage> query(
    String collectionId,
    Map<String, dynamic> query,
  ) async {
    reads++;
    queries.add(Map<String, dynamic>.from(query));
    if (queryGate != null) await queryGate!.future;
    return super.query(collectionId, query);
  }

  @override
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  ) async {
    writes++;
    if (executeGate != null) await executeGate!.future;
    return super.execute(action, record, input, key);
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
    if (failGet) return Future.error(StateError('synthetic read failure'));
    return super.get(recordId);
  }

  @override
  Future<Uint8List> readImage(String assetId, {bool thumbnail = true}) async {
    imageReads++;
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
  }
}

class OfflinePagingAdapter extends OfflineLiveAdapter {
  OfflinePagingAdapter(super.spec);

  @override
  Future<RuntimePage> query(
    String collectionId,
    Map<String, dynamic> query,
  ) async {
    final withoutCursor = Map<String, dynamic>.from(query)..remove('cursor');
    final result = await super.query(collectionId, withoutCursor);
    if (query['cursor'] != null) queries.last['cursor'] = query['cursor'];
    return RuntimePage(
      result.items,
      result.total,
      query['cursor'] == null ? 'next-page' : null,
    );
  }
}

void main() {
  for (final entry in <String, AppSpec>{
    'legacy': starterTemplates()['reading']!,
    'rich': dailyPlannerTemplate(),
  }.entries) {
    testWidgets('${entry.key} covered initial mount loads when visible', (
      tester,
    ) async {
      final adapter = OfflineLiveAdapter(entry.value);
      final show = ValueNotifier<bool>(false);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, enabled, __) =>
                  enabled ? MiniAppRuntime(adapter: adapter) : const SizedBox(),
            ),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Cover')),
        ),
      );
      await tester.pumpAndSettle();
      show.value = true;
      await tester.pumpAndSettle();
      expect(adapter.reads, 0);
      expect(adapter.subscriptions, 0);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(adapter.reads, greaterThan(0));
      expect(adapter.subscriptions, 1);
      await tester.pumpWidget(const SizedBox());
      await adapter.events?.close();
      adapter.dispose();
      show.dispose();
    });
    if (entry.key == 'rich') {
      testWidgets(
        '${entry.key} covered adapter change waits for visible route',
        (tester) async {
          final first = OfflineLiveAdapter(entry.value);
          final second = OfflineLiveAdapter(entry.value);
          final current = ValueNotifier<RuntimeAdapter>(first);
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: Scaffold(
                body: ValueListenableBuilder<RuntimeAdapter>(
                  valueListenable: current,
                  builder: (_, adapter, __) => MiniAppRuntime(adapter: adapter),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(first.reads, greaterThan(0));
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover')),
            ),
          );
          await tester.pumpAndSettle();
          current.value = second;
          await tester.pumpAndSettle();
          expect(second.reads, 0);
          expect(second.subscriptions, 0);
          first.events!.addError(StateError('old adapter revoked'));
          await tester.pump();
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          expect(second.reads, greaterThan(0));
          expect(second.subscriptions, 1);
          expect(find.text('This page is unavailable'), findsNothing);
          await tester.pumpWidget(const SizedBox());
          await first.events?.close();
          await second.events?.close();
          first.dispose();
          second.dispose();
          current.dispose();
        },
      );
    }
    testWidgets('${entry.key} first read waits until foreground', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final adapter = OfflineLiveAdapter(entry.value);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
        ),
      );
      await tester.pump();
      expect(adapter.reads, 0);
      expect(adapter.subscriptions, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(adapter.reads, greaterThan(0));
      expect(adapter.subscriptions, 1);
      await tester.pumpWidget(const SizedBox());
      await adapter.events?.close();
      adapter.dispose();
    });
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

  testWidgets(
    'dirty rich form ignores automatic invalidations and preserves input',
    (tester) async {
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
      await tester.enterText(
        find.byType(TextField).first,
        'Unsaved local edit',
      );
      await tester.pump();
      final before = adapter.reads;
      adapter.failGet = true;
      adapter.events!.add(null);
      await tester.pumpAndSettle();
      expect(adapter.reads, before);
      expect(find.text('Unsaved local edit'), findsOneWidget);
      expect(find.text('This page is unavailable'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await adapter.events?.close();
      adapter.dispose();
    },
  );

  testWidgets(
    'private images ignore background events and reload on explicit refresh',
    (tester) async {
      final adapter = OfflineLiveAdapter(photoJournalTemplate());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
        ),
      );
      await tester.pumpAndSettle();
      expect(adapter.imageReads, greaterThan(0));
      final before = adapter.imageReads;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      adapter.events!.add(null);
      await tester.pumpAndSettle();
      expect(adapter.imageReads, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(adapter.imageReads, before);
      await tester.tap(find.byTooltip('Refresh page'));
      await tester.pumpAndSettle();
      expect(adapter.imageReads, greaterThan(before));
      await tester.pumpWidget(const SizedBox());
      await adapter.events?.close();
      adapter.dispose();
    },
  );

  testWidgets('debounced search does not dispatch after backgrounding', (
    tester,
  ) async {
    final adapter = OfflineLiveAdapter(projectHubTemplate());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
    final before = adapter.reads;
    await tester.enterText(find.byType(TextField).first, 'pending search');
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(adapter.reads, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(adapter.reads, before);
    await tester.tap(find.byTooltip('Refresh page'));
    await tester.pumpAndSettle();
    expect(adapter.reads, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    await adapter.events?.close();
    adapter.dispose();
  });

  testWidgets('rich live invalidation bursts share the in-flight refresh', (
    tester,
  ) async {
    final adapter = OfflineLiveAdapter(projectHubTemplate());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();
    final before = adapter.reads;
    adapter.queryGate = Completer<void>();
    adapter.events!.add(null);
    await tester.pump();
    expect(adapter.reads, greaterThan(before));
    final afterFirst = adapter.reads;
    adapter.events!
      ..add(null)
      ..add(null)
      ..add(null);
    await tester.pump();
    expect(
      adapter.reads,
      afterFirst,
      reason: 'no overlapping refresh for burst',
    );
    adapter.queryGate!.complete();
    await tester.pumpAndSettle();
    expect(adapter.reads, afterFirst);
    await tester.pumpWidget(const SizedBox());
    await adapter.events?.close();
    adapter.dispose();
  });
  testWidgets(
    'visible user search still dispatches while an older refresh is in flight',
    (tester) async {
      final adapter = OfflineLiveAdapter(projectHubTemplate());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
        ),
      );
      await tester.pumpAndSettle();
      adapter.queryGate = Completer<void>();
      await tester.tap(find.byTooltip('Refresh page'));
      await tester.pump();
      final beforeSearch = adapter.reads;
      await tester.enterText(find.byType(TextField).first, 'new search');
      await tester.pump(const Duration(milliseconds: 300));
      expect(adapter.reads, greaterThan(beforeSearch));
      adapter.queryGate!.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await adapter.events?.close();
      adapter.dispose();
    },
  );
  testWidgets(
    'rich media search does not dispatch after its route is covered',
    (tester) async {
      final adapter = OfflineLiveAdapter(photoJournalTemplate());
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('search-photoCards'));
      expect(search, findsOneWidget);
      final before = adapter.reads;
      await tester.enterText(search, 'pending search');
      await tester.pump(const Duration(milliseconds: 100));
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Cover')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(adapter.reads, before);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(adapter.reads, before);
      await tester.tap(find.byTooltip('Refresh page'));
      await tester.pumpAndSettle();
      expect(adapter.reads, greaterThan(before));
      await tester.pumpWidget(const SizedBox());
      await adapter.events?.close();
      adapter.dispose();
    },
  );
  testWidgets('legacy queued search does not read after app backgrounds', (
    tester,
  ) async {
    final adapter = OfflineLiveAdapter(starterTemplates()['reading']!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();
    adapter.queryGate = Completer<void>();
    await tester.tap(find.byTooltip('Refresh records'));
    await tester.pump();
    final readsBeforeSearch = adapter.reads;
    await tester.enterText(find.byType(TextField).first, 'reading');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(adapter.reads, readsBeforeSearch);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    adapter.queryGate!.complete();
    await tester.pumpAndSettle();
    expect(
      adapter.reads,
      readsBeforeSearch,
      reason: 'queued search must not dispatch while paused',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      adapter.reads,
      readsBeforeSearch,
      reason: 'resume must not dispatch automatically',
    );
    adapter.events!.add(null);
    await tester.pumpAndSettle();
    expect(
      adapter.reads,
      readsBeforeSearch,
      reason: 'an invalidation must not apply deferred input automatically',
    );
    expect(
      find.text('Refresh records to apply pending updates.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Refresh records'));
    await tester.pumpAndSettle();
    expect(adapter.reads, readsBeforeSearch + 1);
    expect(
      adapter.queries.last['filters'],
      contains(containsPair('value', 'reading')),
    );
    expect(
      find.text('Refresh records to apply pending updates.'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    await adapter.events?.close();
    adapter.dispose();
  });

  testWidgets('legacy queued search does not read under a covered route', (
    tester,
  ) async {
    final adapter = OfflineLiveAdapter(starterTemplates()['reading']!);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();
    adapter.queryGate = Completer<void>();
    await tester.tap(find.byTooltip('Refresh records'));
    await tester.pump();
    final readsBeforeSearch = adapter.reads;
    await tester.enterText(find.byType(TextField).first, 'covered');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cover')),
      ),
    );
    await tester.pumpAndSettle();
    adapter.queryGate!.complete();
    await tester.pumpAndSettle();
    expect(
      adapter.reads,
      readsBeforeSearch,
      reason: 'covered route must not dispatch queued search',
    );
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(
      adapter.reads,
      readsBeforeSearch,
      reason: 'returning must not dispatch automatically',
    );
    adapter.events!.add(null);
    await tester.pumpAndSettle();
    expect(
      adapter.reads,
      readsBeforeSearch,
      reason: 'an invalidation must not apply deferred input automatically',
    );
    expect(
      find.text('Refresh records to apply pending updates.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Refresh records'));
    await tester.pumpAndSettle();
    expect(adapter.reads, readsBeforeSearch + 1);
    expect(
      adapter.queries.last['filters'],
      contains(containsPair('value', 'covered')),
    );
    await tester.pumpWidget(const SizedBox());
    await adapter.events?.close();
    adapter.dispose();
  });

  testWidgets('legacy queued search refreshes once while visible', (
    tester,
  ) async {
    final adapter = OfflineLiveAdapter(starterTemplates()['reading']!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();
    adapter.queryGate = Completer<void>();
    await tester.tap(find.byTooltip('Refresh records'));
    await tester.pump();
    final readsBeforeSearch = adapter.reads;
    await tester.enterText(find.byType(TextField).first, 'visible');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(adapter.reads, readsBeforeSearch);
    adapter.queryGate!.complete();
    await tester.pumpAndSettle();
    expect(adapter.reads, readsBeforeSearch + 1);
    expect(
      adapter.queries.last['filters'],
      contains(containsPair('value', 'visible')),
    );
    await tester.pumpWidget(const SizedBox());
    await adapter.events?.close();
    adapter.dispose();
  });
  testWidgets(
    'legacy initial load queued search does not stay loading while paused',
    (tester) async {
      final adapter = OfflineLiveAdapter(starterTemplates()['reading']!);
      adapter.queryGate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(adapter.reads, 1);
      await tester.enterText(find.byType(TextField).first, 'initial');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      adapter.queryGate!.complete();
      await tester.pumpAndSettle();
      expect(adapter.reads, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('Refresh records to apply pending updates.'),
        findsOneWidget,
      );
      expect(find.text('Loading…'), findsNothing);
      await tester.tap(find.byTooltip('Refresh records'));
      await tester.pumpAndSettle();
      expect(adapter.reads, 2);
      expect(
        adapter.queries.last['filters'],
        contains(containsPair('value', 'initial')),
      );
      await tester.pumpWidget(const SizedBox());
      await adapter.events?.close();
      adapter.dispose();
    },
  );
  testWidgets(
    'legacy pagination cannot queue another request during a refresh',
    (tester) async {
      final adapter = OfflinePagingAdapter(starterTemplates()['reading']!);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Next page'), findsOneWidget);
      adapter.queryGate = Completer<void>();
      await tester.tap(find.byTooltip('Refresh records'));
      await tester.pump();
      final before = adapter.reads;
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Next page'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Next page'), warnIfMissed: false);
      await tester.pump();
      expect(adapter.reads, before);
      adapter.queryGate!.complete();
      await tester.pumpAndSettle();
      expect(
        adapter.reads,
        before,
        reason: 'disabled next page must not queue a replacement read',
      );
      await tester.ensureVisible(find.text('Next page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next page'));
      await tester.pumpAndSettle();
      expect(adapter.reads, before + 1);
      expect(adapter.queries.last['cursor'], 'next-page');
      await tester.pumpWidget(const SizedBox());
      await adapter.events?.close();
      adapter.dispose();
    },
  );

  testWidgets(
    'legacy choice change invalidates old results before hidden refresh settles',
    (tester) async {
      final adapter = OfflineLiveAdapter(starterTemplates()['reading']!);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
        ),
      );
      await tester.pumpAndSettle();
      adapter.queryGate = Completer<void>();
      await tester.tap(find.byTooltip('Refresh records'));
      await tester.pump();
      final before = adapter.reads;
      await tester.tap(
        find.byKey(const ValueKey('legacy-choice-filter-status')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reading').last);
      await tester.pumpAndSettle();
      expect(find.text('Refresh to try again.'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      adapter.queryGate!.complete();
      await tester.pumpAndSettle();
      expect(adapter.reads, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('Refresh records to apply pending updates.'),
        findsOneWidget,
      );
      expect(
        find.text('Refresh to try again.'),
        findsOneWidget,
        reason: 'the stale response must not replace the changed choice',
      );
      await tester.tap(find.byTooltip('Refresh records'));
      await tester.pumpAndSettle();
      expect(adapter.reads, before + 1);
      expect(
        adapter.queries.last['filters'],
        contains(containsPair('value', 'Reading')),
      );
      await tester.pumpWidget(const SizedBox());
      await adapter.events?.close();
      adapter.dispose();
    },
  );
  testWidgets('late legacy save after disposal does not refresh', (
    tester,
  ) async {
    final adapter = OfflineLiveAdapter(starterTemplates()['reading']!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();
    adapter.executeGate = Completer<void>();
    await tester.tap(find.widgetWithText(FilledButton, 'Add book'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Pending save',
    );
    await tester.tap(find.text('Save').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(adapter.writes, 1);
    final before = adapter.reads;
    await tester.pumpWidget(const SizedBox());
    adapter.executeGate!.complete();
    await tester.pumpAndSettle();
    expect(
      adapter.reads,
      before,
      reason: 'disposed runtime must not issue a late refresh',
    );
    expect(tester.takeException(), isNull);
    await adapter.events?.close();
    adapter.dispose();
  });
}
