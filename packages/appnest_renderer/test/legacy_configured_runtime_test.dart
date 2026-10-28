import 'dart:async';
import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledLegacyPreview extends PreviewRuntimeAdapter {
  ControlledLegacyPreview(super.spec);
  final requests = <Map<String, dynamic>>[];
  final events = StreamController<void>.broadcast();
  Completer<RuntimePage>? pending;
  int writes = 0;

  @override
  Stream<void> watch() => events.stream;

  @override
  Future<RuntimePage> query(String collectionId, Map<String, dynamic> input) {
    requests.add(jsonDecode(jsonEncode(input)) as Map<String, dynamic>);
    return pending?.future ?? super.query(collectionId, input);
  }

  @override
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  ) {
    writes++;
    return super.execute(action, record, input, key);
  }

  @override
  void dispose() {
    events.close();
    super.dispose();
  }
}

Future<void> mount(WidgetTester tester, ControlledLegacyPreview adapter) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
  });
}

void main() {
  testWidgets(
    'legacy configured lists honor predicates, sort, limit, fields and filters',
    (tester) async {
      final json = starterTemplates()['reading']!.toJson();
      (json['requires'] as List).add('views.configured.v1');
      final view = (json['views'] as List).first as Map<String, dynamic>;
      view.addAll({
        'query': {
          'limit': 2,
          'sort': [
            {'fieldId': 'title', 'descending': true},
          ],
          'filters': [
            {'fieldId': 'status', 'operator': 'eq', 'value': 'Finished'},
          ],
        },
        'fieldIds': ['status'],
        'filterFieldIds': ['status'],
        'presentation': 'compact',
      });
      final spec = AppSpec.parse(jsonEncode(json));
      expect(spec.navigation, isNull);
      final adapter = ControlledLegacyPreview(spec);
      await mount(tester, adapter);
      final query = adapter.requests.last;
      expect(query['limit'], 2);
      expect(query['sort'], [
        {'fieldId': 'title', 'descending': true},
      ]);
      expect(query['filters'], [
        {'fieldId': 'status', 'operator': 'eq', 'value': 'Finished'},
      ]);
      expect(find.textContaining('Author:'), findsNothing);
      expect(find.textContaining('Status: Finished'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-library-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reading').last);
      await tester.pumpAndSettle();
      expect(adapter.requests.last['filters'], [
        {'fieldId': 'status', 'operator': 'eq', 'value': 'Finished'},
        {'fieldId': 'status', 'operator': 'eq', 'value': 'Reading'},
      ]);
      expect(find.textContaining('Status:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy relative-day bindings are forwarded without changing definition hashes',
    (tester) async {
      final json = starterTemplates()['chores']!.toJson();
      (json['requires'] as List).add('views.configured.v1');
      ((json['views'] as List).first as Map)['dateFilter'] = {
        'fieldId': 'dueAt',
        'period': 'today',
      };
      final spec = AppSpec.parse(jsonEncode(json));
      final hash = spec.hash;
      final adapter = ControlledLegacyPreview(spec);
      await mount(tester, adapter);
      expect(adapter.requests.last['filters'], hasLength(2));
      expect(
        (adapter.requests.last['filters'] as List).map((f) => f['operator']),
        ['gte', 'lt'],
      );
      expect(spec.hash, hash);
      expect(tester.takeException(), isNull);
    },
  );

  for (final streamError in [true, false]) {
    testWidgets(
      'legacy access error dismisses the editor and fences delayed reads (stream=$streamError)',
      (tester) async {
        final adapter = ControlledLegacyPreview(starterTemplates()['reading']!);
        await mount(tester, adapter);
        final previous = await adapter.query('books', {});
        final title = previous.items.first.data['title'] as String;
        adapter.pending = Completer<RuntimePage>();
        adapter.events.add(null);
        await tester.pump();
        await tester.tap(find.text('Edit book').first);
        await tester.pumpAndSettle();
        expect(find.byType(RecordForm), findsOneWidget);
        if (streamError) {
          adapter.events.addError(const SpecException('App access revoked.'));
          await tester.pumpAndSettle();
          adapter.pending!.complete(previous);
        } else {
          adapter.pending!.completeError(
            const SpecException('App access revoked.'),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(RecordForm), findsNothing);
        expect(find.text(title), findsNothing);
        expect(find.text('App access revoked.'), findsOneWidget);
        expect(adapter.writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('legacy configured create forms show only authored fields', (
    tester,
  ) async {
    final json = starterTemplates()['reading']!.toJson();
    (json['requires'] as List<String>).addAll([
      'views.configured.v1',
      'views.form.v1',
    ]);
    final view = (json['views'] as List).first as Map<String, dynamic>;
    view.addAll({
      'type': 'form',
      'fieldIds': ['title', 'status'],
      'actionIds': ['addBook'],
    });
    final adapter = ControlledLegacyPreview(AppSpec.parse(jsonEncode(json)));
    await mount(tester, adapter);
    await tester.tap(find.text('Add book').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Title *'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Author'), findsNothing);
    expect(find.widgetWithText(TextField, 'Notes'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'New authored form book',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(adapter.writes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy configured forms initialize omitted workflow state on create',
    (tester) async {
      final json = starterTemplates()['chores']!.toJson();
      (json['requires'] as List<String>).addAll([
        'views.configured.v1',
        'views.form.v1',
      ]);
      final view = (json['views'] as List).first as Map<String, dynamic>;
      view.addAll({
        'type': 'form',
        'fieldIds': ['title'],
        'actionIds': ['addChore'],
      });
      final spec = AppSpec.parse(jsonEncode(json));
      final originalHash = spec.hash;
      final adapter = ControlledLegacyPreview(spec);
      await mount(tester, adapter);
      await tester.tap(find.text('Add chore').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Chore *'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Chore *'),
        'Configured workflow chore',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(adapter.writes, 1);
      final page = await adapter.query('chores', {
        'filters': [
          {
            'fieldId': 'title',
            'operator': 'eq',
            'value': 'Configured workflow chore',
          },
        ],
      });
      expect(page.items.single.data['status'], 'Open');
      expect(spec.hash, originalHash);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy forms append required inputs without rewriting accepted definitions',
    (tester) async {
      final json = starterTemplates()['reading']!.toJson();
      (json['requires'] as List<String>).addAll([
        'views.configured.v1',
        'views.form.v1',
      ]);
      final view = (json['views'] as List).first as Map<String, dynamic>;
      view.addAll({
        'type': 'form',
        'fieldIds': ['notes'],
        'actionIds': ['addBook'],
      });
      final spec = AppSpec.parse(jsonEncode(json));
      final originalHash = spec.hash;
      final adapter = ControlledLegacyPreview(spec);
      await mount(tester, adapter);
      await tester.tap(find.text('Add book').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Title *'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Notes'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Author'), findsNothing);
      expect(spec.hash, originalHash);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
