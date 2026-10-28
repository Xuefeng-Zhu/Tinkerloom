import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'design entry discards a guarded form once and keeps field selection available',
    (tester) async {
      final adapter = PreviewRuntimeAdapter(dailyPlannerTemplate());
      final controller = MiniAppController();
      MiniAppEditTarget? selected;
      var editing = false;
      Future<void> mount() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MiniAppRuntime(
                adapter: adapter,
                controller: controller,
                initialLocation: const MiniAppLocation(
                  'taskEditorPage',
                  editing: true,
                ),
                editConfiguration: editing
                    ? MiniAppEditConfiguration(
                        onSelect: (value) => selected = value,
                      )
                    : null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      await tester.enterText(find.byType(TextField).first, 'Unsaved task');
      final leave = controller.canLeave();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(await leave, true);
      editing = true;
      await mount();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byType(InputDecorator).first);
      await tester.pump();
      expect(selected?.kind, MiniAppEditKind.field);
      expect(await controller.canLeave(), true);
      expect(find.text('Discard your changes?'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      controller.dispose();
    },
  );

  test(
    'presentation edits preserve sample records, receipts and stable IDs',
    () async {
      final adapter = PreviewRuntimeAdapter(starterTemplates()['volunteer']!);
      final before = (await adapter.query('shifts', {})).items.first;
      await adapter.execute(
        adapter.spec.action('join'),
        before,
        {},
        'join-once',
      );
      adapter.applyPresentationPatch({
        'type': 'RenameField',
        'collectionId': 'shifts',
        'fieldId': 'title',
        'label': 'Opportunity',
      });
      adapter.applyPresentationPatch({
        'type': 'SetTheme',
        'theme': 'rose',
        'icon': 'people',
      });
      final after = (await adapter.query('shifts', {})).items.first;
      expect(after.id, before.id);
      expect(after.data, before.data);
      expect(after.claimed, true);
      await adapter.execute(
        adapter.spec.action('join'),
        before,
        {},
        'join-once',
      );
      expect((await adapter.query('shifts', {})).items.first.allocated, 1);
      final view = adapter.spec.views.first;
      expect(
        () => adapter.applyPresentationPatch({
          'type': 'UpdateView',
          'viewId': view.id,
          'view': (view.toJson()..remove('id'))..['actionIds'] = [],
        }),
        throwsArgumentError,
      );
      adapter.dispose();
    },
  );

  for (final template in ['reading', 'planner']) {
    testWidgets(
      '$template selects deepest field, blocks actions and preserves location',
      (tester) async {
        final spec = starterTemplates()[template]!;
        final adapter = PreviewRuntimeAdapter(spec);
        final controller = MiniAppController();
        MiniAppEditTarget? selected;
        final collection = spec.collections.first;
        final records = await adapter.query(collection.id, {});
        final record = records.items.first;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MiniAppRuntime(
                adapter: adapter,
                controller: controller,
                initialLocation: template == 'planner'
                    ? const MiniAppLocation('tasksPage')
                    : null,
                editConfiguration: MiniAppEditConfiguration(
                  onSelect: (value) => selected = value,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = find.text(record.data['title'] as String).first;
        await tester.ensureVisible(title);
        await tester.tap(title);
        await tester.pump();
        expect(selected?.kind, MiniAppEditKind.field);
        expect(selected?.id, 'title');
        expect(selected?.collectionId, collection.id);
        if (template == 'planner') {
          expect(selected?.pageId, 'tasksPage');
          expect(controller.location, const MiniAppLocation('tasksPage'));
        }
        final create = find
            .widgetWithText(
              FilledButton,
              template == 'reading' ? 'Add book' : 'Add task',
            )
            .first;
        await tester.ensureVisible(create);
        await tester.tap(create);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect((await adapter.query(collection.id, {})).total, records.total);
        final location = controller.location;
        adapter.applyPresentationPatch({
          'type': 'RenameField',
          'collectionId': collection.id,
          'fieldId': 'title',
          'label': 'My title',
        });
        await tester.pumpAndSettle();
        expect(controller.location, location);
        expect(find.text(record.data['title'] as String), findsWidgets);
        // Edit targets participate in normal keyboard focus traversal.
        await tester.tap(title);
        Focus.of(tester.element(title)).requestFocus();
        await tester.pump();
        selected = null;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(selected?.kind, MiniAppEditKind.field);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        adapter.dispose();
        controller.dispose();
      },
    );
  }

  testWidgets('live adapters ignore edit configuration', (tester) async {
    final adapter = _LiveLikeAdapter(starterTemplates()['reading']!);
    var selections = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiniAppRuntime(
            adapter: adapter,
            editConfiguration: MiniAppEditConfiguration(
              onSelect: (_) => selections++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add book'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(selections, 0);
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
  });
}

class _LiveLikeAdapter extends PreviewRuntimeAdapter {
  _LiveLikeAdapter(super.spec);
  @override
  bool get preview => false;
}
