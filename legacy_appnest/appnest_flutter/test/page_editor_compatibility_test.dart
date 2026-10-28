import 'dart:convert';

import 'package:appnest_flutter/features/builder/page_editor.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppSpec firstView(AppSpec spec, String id) => spec.patch({
  'type': 'ReorderView',
  'viewIds': [id, ...spec.views.where((v) => v.id != id).map((v) => v.id)],
}, () => throw StateError('Reordering must not allocate IDs'));

Future<AppSpec> editView(
  WidgetTester tester,
  AppSpec spec, {
  Future<void> Function()? edit,
}) async {
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
  if (edit != null) {
    await edit();
  } else {
    final label = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'View label',
    );
    await tester.ensureVisible(label);
    await tester.enterText(label, 'Renamed view');
  }
  await tester.tap(find.text('Update preview'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(result, isNotNull, reason: 'The edited definition must remain valid');
  final updated = spec.patch(
    result!,
    () => throw StateError('Editing must retain IDs'),
  );
  await tester.pumpWidget(const SizedBox());
  return updated;
}

void main() {
  testWidgets(
    'legacy view label changes preserve absent presentation and query',
    (tester) async {
      final spec = starterTemplates()['reading']!;
      final original = spec.view('library').toJson();
      final originalHash = spec.hash;
      final updated = await editView(tester, spec);
      expect(updated.view('library').toJson(), {
        ...original,
        'label': 'Renamed view',
      });
      expect(updated.requires, spec.requires);
      expect(updated.navigation, isNull);
      expect(spec.hash, originalHash);
    },
  );

  testWidgets(
    'legacy non-choice grouping opens safely and survives a label edit',
    (tester) async {
      final json = starterTemplates()['reading']!.toJson();
      json['views'][1]['groupByFieldId'] = 'rating';
      final spec = firstView(AppSpec.parse(jsonEncode(json)), 'readingSummary');
      final original = spec.view('readingSummary').toJson();
      final updated = await editView(tester, spec);
      expect(updated.view('readingSummary').toJson(), {
        ...original,
        'label': 'Renamed view',
      });
      expect(updated.requires, spec.requires);
    },
  );

  testWidgets(
    'label edits preserve all repeated choice predicates and sorting',
    (tester) async {
      final json = dailyPlannerTemplate().toJson();
      json['views'][3]['query'] = {
        'filters': [
          {'fieldId': 'status', 'operator': 'eq', 'value': 'Open'},
          {
            'fieldId': 'dueAt',
            'operator': 'gte',
            'value': '2026-09-22T00:00:00.000Z',
          },
          {'fieldId': 'status', 'operator': 'eq', 'value': 'Done'},
        ],
        'sort': [
          {'fieldId': 'dueAt', 'descending': false},
          {'fieldId': 'title', 'descending': true},
        ],
        'limit': 7,
      };
      final spec = firstView(AppSpec.parse(jsonEncode(json)), 'allTasks');
      final original = spec.view('allTasks').toJson();
      final originalHash = spec.hash;
      final updated = await editView(tester, spec);
      expect(updated.view('allTasks').toJson(), {
        ...original,
        'label': 'Renamed view',
      });
      expect(spec.hash, originalHash);
    },
  );

  testWidgets(
    'unchanged query controls preserve omitted sort and filter keys',
    (tester) async {
      final json = dailyPlannerTemplate().toJson();
      json['views'][3]['query'] = {'limit': 7};
      final spec = firstView(AppSpec.parse(jsonEncode(json)), 'allTasks');
      final updated = await editView(tester, spec);
      expect(updated.view('allTasks').query, {'limit': 7});
    },
  );

  testWidgets('changing a choice filter replaces only its own equalities', (
    tester,
  ) async {
    final json = dailyPlannerTemplate().toJson();
    final dueFilter = {
      'fieldId': 'dueAt',
      'operator': 'gte',
      'value': '2026-09-22T00:00:00.000Z',
    };
    json['views'][3]['query'] = {
      'filters': [
        {'fieldId': 'status', 'operator': 'eq', 'value': 'Open'},
        dueFilter,
        {'fieldId': 'status', 'operator': 'eq', 'value': 'Done'},
      ],
      'sort': [
        {'fieldId': 'dueAt', 'descending': false},
      ],
      'limit': 7,
    };
    final spec = firstView(AppSpec.parse(jsonEncode(json)), 'allTasks');
    final updated = await editView(
      tester,
      spec,
      edit: () async {
        final filter = find.byKey(const ValueKey('Only status:Open'));
        await tester.ensureVisible(filter);
        await tester.tap(filter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done').last);
        await tester.pumpAndSettle();
      },
    );
    expect(updated.view('allTasks').query, {
      'filters': [
        dueFilter,
        {'fieldId': 'status', 'operator': 'eq', 'value': 'Done'},
      ],
      'sort': [
        {'fieldId': 'dueAt', 'descending': false},
      ],
      'limit': 7,
    });
  });
}
