import 'dart:convert';

import 'package:appnest_flutter/features/builder/component_options_editor.dart';
import 'package:appnest_flutter/features/builder/page_editor.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final template in richStarterTemplates().entries) {
    final seen = <String>{};
    for (final view in template.value.views.where((v) => seen.add(v.type))) {
      testWidgets(
        '${template.key} ${view.type} can be edited without losing its configuration',
        (tester) async {
          final spec = template.value.patch({
            'type': 'ReorderView',
            'viewIds': [
              view.id,
              ...template.value.views
                  .where((v) => v.id != view.id)
                  .map((v) => v.id),
            ],
          }, () => throw StateError('No new IDs'));
          Map<String, dynamic>? result;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (_) => PageEditor(spec: spec),
                      );
                    },
                    child: const Text('Design'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Design'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ChoiceChip, 'Views'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final label = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'View label',
          );
          await tester.ensureVisible(label);
          await tester.enterText(label, 'Updated ${view.label}');
          await tester.tap(find.text('Update preview'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(result, isNotNull);
          final after = spec.patch(
            result!,
            () => throw StateError('No new IDs'),
          );
          expect(after.view(view.id).toJson(), {
            ...view.toJson(),
            'label': 'Updated ${view.label}',
          });
        },
      );
    }
  }

  testWidgets(
    'inspector can finish a multi-control change before validation succeeds',
    (tester) async {
      final original = projectHubTemplate();
      final board = original.views.firstWhere((view) => view.type == 'board');
      final spec = original.patch({
        'type': 'UpdateView',
        'viewId': board.id,
        'view': (board.toJson()..remove('id'))..remove('options'),
      }, () => throw StateError('No new IDs'));
      var acknowledged = <String, dynamic>{};
      Map<String, dynamic>? lastAttempt;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: ComponentOptionsEditor(
                  spec: spec,
                  type: 'board',
                  collectionId: board.collectionId,
                  options: acknowledged,
                  onChanged: (next) {
                    lastAttempt = next;
                    try {
                      spec.patch({
                        'type': 'UpdateView',
                        'viewId': board.id,
                        'view': (board.toJson()..remove('id'))
                          ..['options'] = next,
                      }, () => throw StateError('No new IDs'));
                      setState(() => acknowledged = next);
                    } on SpecException {
                      setState(() {});
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Drag cards between columns'));
      await tester.pumpAndSettle();
      expect(acknowledged, isEmpty);
      expect(lastAttempt, {'draggable': true});
      final dropdown = find.byKey(
        const ValueKey('component-moveActionId-null'),
      );
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change status').last);
      await tester.pumpAndSettle();
      expect(acknowledged, {'draggable': true, 'moveActionId': 'moveRecord'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new form steps partition fields and serialize without record changes',
    (tester) async {
      final spec = habitTrackerTemplate();
      final form = spec.views.firstWhere((view) => view.type == 'form');
      var options = <String, dynamic>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: ComponentOptionsEditor(
                  spec: spec,
                  type: 'form',
                  collectionId: form.collectionId,
                  fieldIds: form.fieldIds,
                  options: options,
                  onChanged: (next) => setState(() => options = next),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Multi-step form'));
      await tester.tap(find.text('Multi-step form'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add step'));
      await tester.tap(find.text('Add step'));
      await tester.pumpAndSettle();
      expect((options['steps'] as List).length, 2);
      final after = spec.patch({
        'type': 'UpdateView',
        'viewId': form.id,
        'view': (form.toJson()..remove('id'))..['options'] = options,
      }, () => throw StateError('No new IDs'));
      expect(
        jsonEncode(after.collection(form.collectionId).toJson()),
        jsonEncode(spec.collection(form.collectionId).toJson()),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
