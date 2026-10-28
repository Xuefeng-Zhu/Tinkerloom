import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 7, 12);

class _RecordingPreview extends PreviewRuntimeAdapter {
  _RecordingPreview(super.spec) : super(now: _now);
  final queries = <Map<String, dynamic>>[];
  Object? get tableSort => queries.lastWhere(
    (query) => (query['sort'] as List? ?? []).isNotEmpty,
  )['sort'];

  @override
  Future<RuntimePage> query(String collectionId, Map<String, dynamic> query) {
    queries.add(query);
    return super.query(collectionId, query);
  }
}

Future<void> _mount(
  WidgetTester tester,
  RuntimeAdapter adapter,
  MiniAppController controller, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: MiniAppRuntime(
            adapter: adapter,
            controller: controller,
            clock: () => _now,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _close(
  WidgetTester tester,
  PreviewRuntimeAdapter adapter,
  MiniAppController controller,
) async {
  await tester.pumpWidget(const SizedBox());
  adapter.dispose();
  controller.dispose();
}

void main() {
  testWidgets(
    'phone tables keep record identity, metadata and actions together',
    (tester) async {
      final adapter = _RecordingPreview(projectHubTemplate());
      final controller = MiniAppController();
      final item = (await adapter.query('projects', {})).items.first;
      final title = item.data['title'] as String;
      final semantics = tester.ensureSemantics();
      await _mount(tester, adapter, controller);
      await controller.navigate(const MiniAppLocation('tablePage'));
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsNothing);
      final card = find.byKey(ValueKey('table-record-taskTable-${item.id}'));
      expect(
        find.descendant(of: card, matching: find.text(title)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Priority: ', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Effort: ', findRichText: true),
        ),
        findsOneWidget,
      );
      final open = find.descendant(of: card, matching: find.text('Open'));
      final edit = find.descendant(of: card, matching: find.text('Edit entry'));
      expect(open, findsOneWidget);
      expect(edit, findsOneWidget);
      expect(tester.getSemantics(open).label, 'Open $title');
      expect(tester.getSemantics(edit).label, 'Edit entry for $title');
      final cardRect = tester.getRect(card);
      for (final action in [open, edit]) {
        final actionRect = tester.getRect(action);
        expect(actionRect.left, greaterThanOrEqualTo(cardRect.left));
        expect(actionRect.right, lessThanOrEqualTo(cardRect.right));
      }
      for (final button in [TextButton, OutlinedButton]) {
        final target = find.descendant(of: card, matching: find.byType(button));
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      }
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );

      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(controller.location!.recordId, item.id);
      expect(controller.location!.pageId, 'detailPage');
      await controller.navigate(const MiniAppLocation('tablePage'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(controller.location!.recordId, item.id);
      expect(controller.location!.pageId, 'formPage');
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await _close(tester, adapter, controller);
    },
  );

  testWidgets(
    'phone table sorting remains available without horizontal scroll',
    (tester) async {
      final adapter = _RecordingPreview(projectHubTemplate());
      final controller = MiniAppController();
      await _mount(tester, adapter, controller);
      await controller.navigate(const MiniAppLocation('tablePage'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Task'));
      await tester.pumpAndSettle();
      expect(adapter.tableSort, [
        {'fieldId': 'title', 'descending': false},
      ]);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Task'));
      await tester.pumpAndSettle();
      expect(adapter.tableSort, [
        {'fieldId': 'title', 'descending': true},
      ]);
      expect(tester.takeException(), isNull);
      await _close(tester, adapter, controller);
    },
  );

  testWidgets('phone table cards reflow with large text on a small screen', (
    tester,
  ) async {
    final adapter = _RecordingPreview(projectHubTemplate());
    final controller = MiniAppController();
    await _mount(
      tester,
      adapter,
      controller,
      size: const Size(320, 844),
      textScale: 2,
    );
    await controller.navigate(const MiniAppLocation('tablePage'));
    await tester.pumpAndSettle();
    final table = find.byKey(const ValueKey('mobile-table-taskTable'));
    expect(table, findsOneWidget);
    expect(tester.getRect(table).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(table).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
    final open = find.text('Open').first;
    await tester.ensureVisible(open);
    expect(open.hitTestable(), findsOneWidget);
    final edit = find.text('Edit entry').first;
    await tester.ensureVisible(edit);
    expect(edit.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester, adapter, controller);
  });

  testWidgets('desktop keeps the sortable table', (tester) async {
    final adapter = _RecordingPreview(projectHubTemplate());
    final controller = MiniAppController();
    await _mount(tester, adapter, controller, size: const Size(1440, 1000));
    await controller.navigate(const MiniAppLocation('tablePage'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-table-taskTable')), findsNothing);
    await tester.tap(find.text('Task'));
    await tester.pumpAndSettle();
    expect(adapter.tableSort, [
      {'fieldId': 'title', 'descending': false},
    ]);
    expect(tester.takeException(), isNull);
    await _close(tester, adapter, controller);
  });

  testWidgets(
    'phone welcome banner starts compact and its content is recoverable',
    (tester) async {
      final adapter = PreviewRuntimeAdapter(projectHubTemplate(), now: _now);
      final controller = MiniAppController();
      final canonical = adapter.spec.canonical;
      const body =
          'Plan the next step, share the work, and celebrate what is done.';
      await _mount(tester, adapter, controller);
      final banner = find.byKey(const PageStorageKey('compact-banner-welcome'));
      expect(banner, findsOneWidget);
      expect(find.text(body), findsNothing);
      expect(tester.getSize(banner).height, lessThan(100));
      await tester.tap(find.text('Make progress together'));
      await tester.pumpAndSettle();
      expect(find.text(body), findsOneWidget);
      expect(tester.getSize(banner).height, greaterThan(100));
      await controller.navigate(const MiniAppLocation('tablePage'));
      await controller.navigate(const MiniAppLocation('boardPage'));
      await tester.pumpAndSettle();
      expect(find.text(body), findsOneWidget);
      expect(adapter.spec.canonical, canonical);
      expect(tester.takeException(), isNull);
      await _close(tester, adapter, controller);
    },
  );

  testWidgets('desktop banner keeps its visible explanatory content', (
    tester,
  ) async {
    final adapter = PreviewRuntimeAdapter(projectHubTemplate(), now: _now);
    final controller = MiniAppController();
    await _mount(tester, adapter, controller, size: const Size(1440, 1000));
    expect(
      find.text(
        'Plan the next step, share the work, and celebrate what is done.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const PageStorageKey('compact-banner-welcome')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await _close(tester, adapter, controller);
  });

  testWidgets('phone warning banner keeps important content visible', (
    tester,
  ) async {
    final initial = projectHubTemplate();
    final banner = initial.view('welcome');
    final spec = initial.patch({
      'type': 'UpdateView',
      'viewId': banner.id,
      'view': (banner.toJson()..remove('id'))
        ..['options'] = {...banner.options, 'tone': 'warning'},
    }, () => 'unused');
    final adapter = PreviewRuntimeAdapter(spec, now: _now);
    final controller = MiniAppController();
    await _mount(tester, adapter, controller);
    expect(
      find.text(
        'Plan the next step, share the work, and celebrate what is done.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const PageStorageKey('compact-banner-welcome')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await _close(tester, adapter, controller);
  });
}
