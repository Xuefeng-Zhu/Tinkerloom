import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('planner complete page flow at $size with 150% text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 9, 22, 12);
      final adapter = PreviewRuntimeAdapter(dailyPlannerTemplate(), now: now);
      final controller = MiniAppController();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: EdgeInsets.only(bottom: size.width < 760 ? 34 : 0),
              viewPadding: EdgeInsets.only(bottom: size.width < 760 ? 34 : 0),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: MiniAppRuntime(
                adapter: adapter,
                controller: controller,
                clock: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'todayPage');
      expect(tester.takeException(), isNull);
      expect(find.text('Today at a glance'), findsOneWidget);
      expect(find.text('Add task').hitTestable(), findsOneWidget);
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(MiniAppRuntime)))
            .scale(20),
        30,
      );

      Finder tab(String label) => find.descendant(
        of: find.byType(size.width < 760 ? NavigationBar : NavigationRail),
        matching: find.text(label),
      );
      await tester.tap(tab('Tasks'));
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'tasksPage');
      expect(tester.takeException(), isNull);
      expect(find.text('All status').hitTestable(), findsOneWidget);
      expect(find.text('All priority').hitTestable(), findsOneWidget);

      await tester.ensureVisible(find.text('Make time for a walk'));
      await tester.tap(find.text('Make time for a walk'));
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'taskDetailPage');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Edit task'));
      expect(find.text('Edit task').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Edit task'));
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'taskEditorPage');
      expect(tester.takeException(), isNull);

      final notes = find.widgetWithText(TextField, 'Notes');
      await tester.ensureVisible(notes);
      await tester.enterText(notes, 'A comfortable edit with larger text.');
      await tester.ensureVisible(find.text('Choose date and time'));
      expect(find.text('Choose date and time').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Save'));
      expect(find.text('Save').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'taskDetailPage');
      expect(
        (await adapter.get(2)).data['notes'],
        'A comfortable edit with larger text.',
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Back'));
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'tasksPage');
      // Save feedback remains visible, but must not cover the app's tabs.
      expect(find.text('Simulated in preview'), findsOneWidget);
      expect(tab('Progress').hitTestable(), findsOneWidget);
      await tester.tap(tab('Progress'));
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'progressPage');
      expect(find.text('Today’s scheduled tasks'), findsOneWidget);
      await tester.ensureVisible(find.text('All tasks'));
      expect(find.text('All tasks').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      controller.dispose();
    });
  }
}
