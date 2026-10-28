import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _priorityId = 'allocatedPriority';
final _now = DateTime(2026, 10, 10, 12);

AppSpec _withPriority({bool implicit = false, bool table = false}) {
  final json = notesTemplate().toJson();
  if (table) {
    (json['views'] as List).add({
      'id': 'notesTable',
      'type': 'table',
      'collectionId': 'notes',
      'label': 'Notes table',
      'titleFieldId': 'title',
      'fieldIds': ['title', 'body', 'category'],
      'detailPageId': 'detailPage',
      'formPageId': 'formPage',
      'actionIds': ['editRecord'],
    });
    (json['requires'] as List).add('views.table.v1');
    (json['navigation']['pages'] as List).add({
      'id': 'tablePage',
      'title': 'Notes table',
      'viewIds': ['notesTable'],
    });
  }
  if (implicit) {
    for (final view in json['views'] as List) {
      view.remove('fieldIds');
    }
  }
  final before = AppSpec.parse(jsonEncode(json));
  return before.patch({
    'type': 'AddField',
    'collectionId': 'notes',
    'field': {
      'label': 'Priority',
      'type': 'choice',
      'choices': ['Low', 'Normal', 'High'],
    },
    'viewIds': [
      'allEntries',
      'entryDetails',
      'entryEditor',
      if (table) 'notesTable',
    ],
  }, () => _priorityId);
}

Future<void> _mount(
  WidgetTester tester,
  PreviewRuntimeAdapter adapter,
  MiniAppController controller, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MiniAppRuntime(
          adapter: adapter,
          controller: controller,
          clock: () => _now,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(DropdownButtonFormField<String>, label);
  expect(field, findsOneWidget);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(save);
  await tester.tap(save);
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
  for (final implicit in [false, true]) {
    testWidgets(
      'allocated Priority survives create edit details and list with implicit=$implicit',
      (tester) async {
        final spec = _withPriority(implicit: implicit);
        final adapter = PreviewRuntimeAdapter(spec, now: _now);
        final controller = MiniAppController();
        final originalRecords = {
          for (final item in (await adapter.query('notes', {})).items)
            item.id: Map<String, dynamic>.of(item.data),
        };
        await _mount(tester, adapter, controller);

        await tester.tap(find.widgetWithText(FilledButton, 'Add entry'));
        await tester.pumpAndSettle();
        expect(controller.location!.pageId, 'formPage');
        expect(
          find.widgetWithText(DropdownButtonFormField<String>, 'Priority'),
          findsOneWidget,
        );
        const title = 'Priority regression note';
        const body = 'Keep this note body';
        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == 'Title *',
          ),
          title,
        );
        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == 'Note',
          ),
          body,
        );
        await _choose(tester, 'Category', 'Work');
        await _choose(tester, 'Priority', 'High');
        await _save(tester);

        final created = (await adapter.query(
          'notes',
          {},
        )).items.singleWhere((item) => item.data['title'] == title);
        expect(created.data, {
          'title': title,
          'body': body,
          'category': 'Work',
          _priorityId: 'High',
        });
        expect(controller.location!.pageId, 'homePage');
        expect(find.text('Priority: High'), findsWidgets);
        await tester.ensureVisible(find.text(title));
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(
          controller.location,
          MiniAppLocation('detailPage', recordId: created.id),
        );
        expect(find.text('Priority'), findsOneWidget);
        expect(find.text('High'), findsOneWidget);
        expect(find.text('Note'), findsOneWidget);
        expect(find.text(body), findsOneWidget);
        expect(find.text('Category'), findsOneWidget);
        expect(find.text('Work'), findsOneWidget);

        final edit = find.widgetWithText(OutlinedButton, 'Edit entry');
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(controller.location!.recordId, created.id);
        expect(controller.location!.pageId, 'formPage');
        expect(
          find.descendant(
            of: find.widgetWithText(
              DropdownButtonFormField<String>,
              'Priority',
            ),
            matching: find.text('High'),
          ),
          findsWidgets,
        );
        await _choose(tester, 'Priority', 'Low');
        await _save(tester);
        expect(controller.location!.pageId, 'detailPage');
        expect(find.text('Priority'), findsOneWidget);
        expect(find.text('Low'), findsOneWidget);
        expect((await adapter.get(created.id)).data, {
          ...created.data,
          _priorityId: 'Low',
        });

        await controller.navigate(const MiniAppLocation('homePage'));
        await tester.pumpAndSettle();
        final row = find
            .ancestor(of: find.text(title), matching: find.byType(InkWell))
            .first;
        for (final metadata in [
          'Note: $body',
          'Category: Work',
          'Priority: Low',
        ]) {
          expect(
            find.descendant(of: row, matching: find.text(metadata)),
            findsOneWidget,
          );
        }
        for (final original in originalRecords.entries) {
          expect((await adapter.get(original.key)).data, original.value);
        }
        expect(find.text('This page is unavailable'), findsNothing);
        expect(tester.takeException(), isNull);
        await _close(tester, adapter, controller);
      },
    );
  }

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('allocated Priority keeps existing table fields at $size', (
      tester,
    ) async {
      final spec = _withPriority(table: true);
      final adapter = PreviewRuntimeAdapter(spec, now: _now);
      final controller = MiniAppController();
      final records = (await adapter.query('notes', {})).items;
      final first = records.first;
      final unset = records[1];
      await adapter.execute(spec.action('editRecord'), first, {
        'data': {_priorityId: 'High'},
      }, 'set-table-priority');
      await adapter.execute(spec.action('editRecord'), unset, {
        'data': {_priorityId: null},
      }, 'unset-table-priority');
      await _mount(tester, adapter, controller, size: size);
      await controller.navigate(const MiniAppLocation('tablePage'));
      await tester.pumpAndSettle();

      if (size.width < 640) {
        expect(find.byType(DataTable), findsNothing);
        final card = find.byKey(
          ValueKey('table-record-notesTable-${first.id}'),
        );
        for (final value in [
          first.data['title'] as String,
          'Note: ${first.data['body']}',
          'Category: ${first.data['category']}',
          'Priority: High',
        ]) {
          expect(
            find.descendant(
              of: card,
              matching: find.text(value, findRichText: true),
            ),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(
            of: find.byKey(ValueKey('table-record-notesTable-${unset.id}')),
            matching: find.text('Priority: Not set', findRichText: true),
          ),
          findsOneWidget,
        );
      } else {
        final table = tester.widget<DataTable>(find.byType(DataTable));
        expect(table.columns.map((column) => (column.label as Text).data), [
          'Title',
          'Note',
          'Category',
          'Priority',
          'Actions',
        ]);
        for (final entry in [
          first.data['title'],
          first.data['body'],
          first.data['category'],
          'High',
        ].indexed) {
          expect(
            find.descendant(
              of: find.byWidget(table.rows.first.cells[entry.$1].child),
              matching: find.text(entry.$2 as String),
            ),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(
            of: find.byWidget(table.rows[1].cells[3].child),
            matching: find.text('Not set'),
          ),
          findsOneWidget,
        );
      }
      expect((await adapter.get(first.id)).data, {
        ...first.data,
        _priorityId: 'High',
      });
      expect(tester.takeException(), isNull);
      await _close(tester, adapter, controller);
    });
  }
}
