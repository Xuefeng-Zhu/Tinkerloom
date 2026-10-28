import 'dart:convert';

import 'package:appnest_flutter/features/builder/page_editor.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppSpec formFirst(AppSpec spec, {String id = 'editor'}) => spec.patch({
  'type': 'ReorderView',
  'viewIds': [id, ...spec.views.where((v) => v.id != id).map((v) => v.id)],
}, () => throw StateError('No new ID'));

Future<AppSpec Function()> openEditor(WidgetTester tester, AppSpec spec) async {
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
  return () {
    expect(result, isNotNull);
    return spec.patch(result!, () => throw StateError('No new ID'));
  };
}

Future<void> toggleField(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(FilterChip, label);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.text('Update preview'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  AppSpec allFieldsForm() {
    final spec = photoJournalTemplate();
    return formFirst(
      spec.patch({
        'type': 'UpdateView',
        'viewId': 'editor',
        'view': (spec.view('editor').toJson()..remove('id'))
          ..['fieldIds'] = spec
              .collection('memories')
              .fields
              .map((f) => f.id)
              .toList(),
      }, () => throw StateError('No new ID')),
    );
  }

  testWidgets('hiding a form field removes its control and step binding', (
    tester,
  ) async {
    final spec = allFieldsForm();
    final original = spec.canonical;
    final result = await openEditor(tester, spec);
    await toggleField(tester, 'Rating');
    // A subsequent component edit must use the parent's reconciled options.
    final caption = find.byKey(const ValueKey('control-caption-multiline'));
    await tester.ensureVisible(caption);
    await tester.tap(caption);
    await tester.pumpAndSettle();
    await tester.tap(find.text('text').last);
    await tester.pumpAndSettle();
    await save(tester);
    final view = result().view('editor');
    expect(view.fieldIds, isNot(contains('rating')));
    final controls = view.options['controls'] as List;
    expect(controls.any((c) => c['fieldId'] == 'rating'), isFalse);
    expect(
      controls.firstWhere((c) => c['fieldId'] == 'caption')['control'],
      'text',
    );
    final steps = view.options['steps'] as List;
    expect(steps.map((s) => s['id']), ['moment', 'story']);
    expect(steps.last['fieldIds'], ['caption', 'favorite']);
    expect(spec.canonical, original);
  });

  testWidgets('choosing a checklist update action also binds it to the view', (
    tester,
  ) async {
    final json =
        jsonDecode(projectHubTemplate().canonical) as Map<String, dynamic>;
    ((json['collections'] as List).single['fields'] as List).add({
      'id': 'flag',
      'label': 'Flag',
      'type': 'boolean',
      'required': false,
    });
    final checklist = (json['views'] as List).firstWhere(
      (v) => v['id'] == 'taskChecklist',
    );
    checklist['actionIds'] = ['moveRecord'];
    final spec = formFirst(
      AppSpec.parse(jsonEncode(json)),
      id: 'taskChecklist',
    );
    final result = await openEditor(tester, spec);
    final field = find.byKey(const ValueKey('component-fieldId-status'));
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flag').last);
    await tester.pumpAndSettle();
    await save(tester);
    final view = result().view('taskChecklist');
    expect(view.options, {'fieldId': 'flag', 'actionId': 'editRecord'});
    expect(view.actionIds, ['moveRecord', 'editRecord']);
  });

  testWidgets(
    'empty steps are removed and newly visible fields are assigned once',
    (tester) async {
      final result = await openEditor(tester, allFieldsForm());
      for (final label in ['Caption', 'Rating', 'Favorite']) {
        await toggleField(tester, label);
      }
      await toggleField(tester, 'Caption');
      await save(tester);
      final options = result().view('editor').options;
      final steps = options['steps'] as List;
      expect(steps, hasLength(1));
      expect(steps.single['id'], 'moment');
      expect(steps.single['fieldIds'], [
        'title',
        'photo',
        'takenAt',
        'caption',
      ]);
      expect((options['controls'] as List).map((c) => c['fieldId']), ['photo']);
    },
  );

  testWidgets(
    'returning to default visible fields restores a complete step partition',
    (tester) async {
      final base = photoJournalTemplate();
      final spec = formFirst(
        base.patch({
          'type': 'UpdateView',
          'viewId': 'editor',
          'view': (base.view('editor').toJson()..remove('id'))
            ..addAll({
              'fieldIds': ['title'],
              'options': {
                'steps': [
                  {
                    'id': 'titleOnly',
                    'title': 'Details',
                    'fieldIds': ['title'],
                  },
                ],
              },
            }),
        }, () => throw StateError('No new ID')),
      );
      final result = await openEditor(tester, spec);
      await toggleField(tester, 'Title');
      await save(tester);
      final view = result().view('editor');
      expect(view.fieldIds, isEmpty);
      expect(
        (view.options['steps'] as List).single['fieldIds'],
        spec.collection('memories').fields.map((f) => f.id).toList(),
      );
    },
  );

  testWidgets(
    'changing collection resets hidden form options and old destinations',
    (tester) async {
      final source = photoJournalTemplate();
      final json = jsonDecode(source.canonical) as Map<String, dynamic>;
      (json['collections'] as List).add({
        'id': 'notes',
        'label': 'Notes collection',
        'fields': [
          {'id': 'body', 'label': 'Body', 'type': 'text', 'required': true},
        ],
        'behaviors': [],
      });
      (json['actions'] as List).add({
        'id': 'addNote',
        'label': 'Add note',
        'capability': 'records.create.v1',
        'collectionId': 'notes',
      });
      (json['views'] as List).add({
        ...source.view('editor').toJson(),
        'id': 'movableForm',
        'detailPageId': 'detailPage',
        'formPageId': 'formPage',
      });
      final spec = formFirst(
        AppSpec.parse(jsonEncode(json)),
        id: 'movableForm',
      );
      final result = await openEditor(tester, spec);
      final collection = find.byKey(const ValueKey('Collection:memories'));
      await tester.ensureVisible(collection);
      await tester.tap(collection);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes collection').last);
      await tester.pumpAndSettle();
      final action = find.widgetWithText(FilterChip, 'Add note');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await save(tester);
      final view = result().view('movableForm');
      expect(view.collectionId, 'notes');
      expect(view.options, isEmpty);
      expect(view.actionIds, ['addNote']);
      expect(view.titleFieldId, isNull);
      expect(view.detailPageId, isNull);
      expect(view.formPageId, isNull);
    },
  );
}
