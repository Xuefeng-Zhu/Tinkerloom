import 'dart:convert';

import 'package:appnest_flutter/features/builder/component_options_editor.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppSpec checklistChoices() {
  final json =
      jsonDecode(projectHubTemplate().canonical) as Map<String, dynamic>;
  final collection = (json['collections'] as List).single;
  (collection['fields'] as List).addAll([
    {'id': 'flag', 'label': 'Flag', 'type': 'boolean', 'required': false},
    {
      'id': 'oneWay',
      'label': 'One way',
      'type': 'choice',
      'required': false,
      'choices': ['No', 'Yes'],
    },
  ]);
  (collection['behaviors'] as List).add({
    'id': 'oneWayWorkflow',
    'type': 'workflow.v1',
    'fieldId': 'oneWay',
    'transitions': {
      'No': ['Yes'],
      'Yes': [],
    },
  });
  (json['actions'] as List).add({
    'id': 'advance',
    'label': 'Advance',
    'collectionId': 'projects',
    'capability': 'workflow.transition.v1',
    'behaviorId': 'oneWayWorkflow',
  });
  return AppSpec.parse(jsonEncode(json));
}

Future<Map<String, dynamic> Function()> mountOptions(
  WidgetTester tester,
  AppSpec spec,
  String id,
) async {
  final view = spec.view(id);
  var options = Map<String, dynamic>.from(view.options);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: ComponentOptionsEditor(
              spec: spec,
              type: view.type,
              collectionId: view.collectionId,
              options: options,
              onChanged: (next) => setState(() => options = next),
            ),
          ),
        ),
      ),
    ),
  );
  return () => options;
}

Future<void> selectOption(
  WidgetTester tester,
  String key,
  String? current,
  String label,
) async {
  final select = find.byKey(ValueKey('component-$key-$current'));
  await tester.ensureVisible(select);
  await tester.tap(select);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'checklist offers only usable fields and switches compatible actions and values',
    (tester) async {
      final spec = checklistChoices();
      final options = await mountOptions(tester, spec, 'taskChecklist');
      await tester.tap(find.byKey(const ValueKey('component-fieldId-status')));
      await tester.pumpAndSettle();
      expect(find.text('Priority'), findsNothing);
      expect(find.text('One way'), findsNothing);
      await tester.tap(find.text('Flag').last);
      await tester.pumpAndSettle();
      expect(options(), {'fieldId': 'flag', 'actionId': 'editRecord'});
      await tester.tap(
        find.byKey(const ValueKey('component-actionId-editRecord')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Change status'), findsNothing);
      expect(find.text('Advance'), findsNothing);
      await tester.tap(find.text('Edit entry').last);
      await tester.pumpAndSettle();
      expect(
        () => spec.patch({
          'type': 'UpdateView',
          'viewId': 'taskChecklist',
          'view': (spec.view('taskChecklist').toJson()..remove('id'))
            ..['options'] = options(),
        }, () => throw StateError('No new ID')),
        returnsNormally,
      );
      await selectOption(tester, 'fieldId', 'flag', 'Status');
      expect(options()['actionId'], 'moveRecord');
      await selectOption(tester, 'checkedValue', 'Done', 'Open');
      expect(options()['uncheckedValue'], 'Done');
      expect(
        () => spec.patch({
          'type': 'UpdateView',
          'viewId': 'taskChecklist',
          'view': (spec.view('taskChecklist').toJson()..remove('id'))
            ..['options'] = options(),
        }, () => throw StateError('No new ID')),
        returnsNormally,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bar charts expose date buckets and clear dependent options for categorical grouping',
    (tester) async {
      final spec = habitTrackerTemplate();
      final options = await mountOptions(tester, spec, 'energyChart');
      expect(
        find.byKey(const ValueKey('component-dateFieldId-loggedAt')),
        findsOneWidget,
      );
      await selectOption(tester, 'bucket', 'week', 'Monthly');
      final periods = find.byKey(const ValueKey('component-text-periods'));
      await tester.ensureVisible(periods);
      await tester.enterText(periods, '12');
      expect(options()['bucket'], 'month');
      expect(options()['periods'], 12);
      expect(
        () => spec.patch({
          'type': 'UpdateView',
          'viewId': 'energyChart',
          'view': (spec.view('energyChart').toJson()..remove('id'))
            ..['options'] = options(),
        }, () => throw StateError('No new ID')),
        returnsNormally,
      );
      await selectOption(tester, 'dateFieldId', 'loggedAt', 'Choose…');
      expect(options().keys, isNot(contains('dateFieldId')));
      expect(options().keys, isNot(contains('bucket')));
      expect(options().keys, isNot(contains('periods')));
      expect(
        () => spec.patch({
          'type': 'UpdateView',
          'viewId': 'energyChart',
          'view': (spec.view('energyChart').toJson()..remove('id'))
            ..addAll({
              'options': options(),
              'groupByFieldId': 'category',
            }),
        }, () => throw StateError('No new ID')),
        returnsNormally,
      );
      await selectOption(tester, 'dateFieldId', null, 'Logged at');
      expect(options()['bucket'], 'day');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('donut offers only record counts and no date configuration', (
    tester,
  ) async {
    final spec = habitTrackerTemplate();
    await mountOptions(tester, spec, 'categoryChart');
    expect(find.text('Date field (optional)'), findsNothing);
    expect(find.text('Time buckets'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('component-metric-count')));
    await tester.pumpAndSettle();
    expect(find.text('Sum'), findsNothing);
    expect(find.text('Average'), findsNothing);
    expect(find.text('Record count'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
