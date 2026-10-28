import 'dart:async';
import 'dart:convert';

import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/builder/builder_screen.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'builder_creation_test.dart' show CreationClient, draft;

class VisualClient extends CreationClient {
  final writes = <Map<String, dynamic>>[];
  Completer<void>? pause;
  bool failWrite = false;
  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    if (endpoint != 'builder' || method != 'patch') {
      return super.callServerEndpoint(
        endpoint,
        method,
        args,
        authenticated: authenticated,
      );
    }
    expectSync(authenticated, true);
    writes.add(args);
    if (failWrite) throw StateError('offline');
    if (pause != null) await pause!.future;
    expectSync(args['mutation'], current.mutation);
    final spec = AppSpec.parse(current.candidateJson)
        .patch(jsonDecode(args['patchJson'] as String), () => 'unused');
    current = draft(spec: spec, mutation: current.mutation + 1);
    return current as T;
  }
}

void main() {
  final client = VisualClient();
  setUpAll(() => transport.client = client);
  tearDownAll(client.close);
  setUp(() {
    client.current = draft(spec: starterTemplates()['reading']);
    client.writes.clear();
    client.pause = null;
    client.failWrite = false;
    client.pendingGeneration = null;
  });
  Future<void> mount(WidgetTester tester, {bool mobile = false}) async {
    tester.view.physicalSize = mobile
        ? const Size(390, 844)
        : const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(mobile ? 1.5 : 1)),
          child: child!,
        ),
        home: BuilderScreen(initial: client.current),
      ),
    );
    await tester.pumpAndSettle();
    if (mobile) {
      await tester.tap(find.text('Try'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'desktop autosaves without replacing preview or overwriting newer text',
    (tester) async {
      await mount(tester);
      final original = tester
          .widget<MiniAppRuntime>(find.byType(MiniAppRuntime))
          .adapter;
      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit app'), findsOneWidget);
      client.pause = Completer();
      await tester.enterText(
        find.byKey(const ValueKey('visual-label')),
        'First name',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(
        find.byKey(const ValueKey('visual-label')),
        'Final name',
      );
      client.pause!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Final name'), findsWidgets);
      expect(AppSpec.parse(client.current.candidateJson).name, 'Final name');
      expect(client.writes.length, 2);
      expect(
        tester.widget<MiniAppRuntime>(find.byType(MiniAppRuntime).last).adapter,
        same(original),
      );
      await tester.tap(find.text('Done editing'));
      await tester.pumpAndSettle();
      expect(find.text('Edit app'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'mobile inspector closes to selectable preview at 150 percent text',
    (tester) async {
      await mount(tester, mobile: true);
      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('visual-label')),
        'Mobile library',
      );
      await tester.tap(find.text('Back to preview'));
      await tester.pumpAndSettle();
      expect(
        AppSpec.parse(client.current.candidateJson).name,
        'Mobile library',
      );
      final adapter = tester
          .widget<MiniAppRuntime>(find.byType(MiniAppRuntime))
          .adapter;
      final record = (await adapter.query('books', {})).items.first;
      final title = find.text(record.data['title'] as String);
      await tester.ensureVisible(title);
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(find.text('Edit field'), findsOneWidget);
      tester.view.physicalSize = const Size(390, 600);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const ValueKey('visual-label')),
        'Book name',
      );
      tester.view.viewInsets = const FakeViewPadding();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to preview'));
      await tester.pumpAndSettle();
      expect(
        AppSpec.parse(client.current.candidateJson)
            .collection('books')
            .field('title')
            .label,
        'Book name',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('discarding a failed app rename restores acknowledged input', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    client.failWrite = true;
    await tester.enterText(
      find.byKey(const ValueKey('visual-label')),
      'Unsaved name',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard local changes'));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('visual-label')),
    );
    expect(input.controller!.text, 'Reading Journal');
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'invalid text blocks leaving edit mode until explicitly discarded',
    (tester) async {
      await mount(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('visual-label')), '');
      await tester.tap(find.text('Done editing'));
      await tester.pumpAndSettle();
      expect(find.text('Your changes haven’t saved'), findsOneWidget);
      expect(client.writes, isEmpty);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Edit app'), findsOneWidget);
      await tester.tap(find.text('Done editing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard local changes'));
      await tester.pumpAndSettle();
      expect(find.text('Edit app'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('AI presentation result keeps preview records and navigation', (
    tester,
  ) async {
    client.current = draft(spec: dailyPlannerTemplate());
    await mount(tester);
    final runtime = tester.widget<MiniAppRuntime>(find.byType(MiniAppRuntime));
    final original = runtime.adapter;
    final row = (await original.query('tasks', {})).items.first;
    await original.execute(
      original.spec.actions.firstWhere(
        (action) =>
            action.collectionId == 'tasks' &&
            action.capability == 'records.patch.v1',
      ),
      row,
      {
        'data': {'title': 'My sample task'},
      },
      'preserve-ai-sample',
    );
    await runtime.controller!.navigate(const MiniAppLocation('tasksPage'));
    await tester.pumpAndSettle();
    final next = original.spec.patch({
      'type': 'SetAppearance',
      'appearance': {'style': 'editorial'},
    }, () => 'unused');
    client.current = draft(spec: next, mutation: 1);
    await tester.enterText(
      find.byKey(const ValueKey('builder-prompt')),
      'Use an editorial style',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    final updated = tester.widget<MiniAppRuntime>(find.byType(MiniAppRuntime));
    expect(updated.adapter, same(original));
    expect(updated.adapter.spec.appearance!.style, 'editorial');
    expect((await updated.adapter.get(row.id)).data['title'], 'My sample task');
    expect(updated.controller!.location, const MiniAppLocation('tasksPage'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
