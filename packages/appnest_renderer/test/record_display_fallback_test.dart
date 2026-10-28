import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppSpec recordSpec({
  bool navigation = true,
  String type = 'list',
  String? label,
  String? titleFieldId,
}) {
  final json = starterTemplates()['chores']!.toJson();
  json['views'] = [
    {
      'id': 'choresList',
      'type': type,
      'collectionId': 'chores',
      if (label != null) 'label': label,
      if (titleFieldId != null) 'titleFieldId': titleFieldId,
      if (navigation) 'detailPageId': 'detailsPage',
      'actionIds': <String>[],
    },
    if (navigation)
      {
        'id': 'choreDetails',
        'type': 'details',
        'collectionId': 'chores',
        if (titleFieldId != null) 'titleFieldId': titleFieldId,
        'actionIds': <String>[],
      },
  ];
  if (navigation) {
    json['requires'] = {
      ...json['requires'] as List,
      'navigation.v1',
      'views.details.v1',
      'views.$type.v1',
      'views.configured.v1',
    }.toList();
    json['navigation'] = {
      'entryPageId': 'home',
      'pages': [
        {
          'id': 'home',
          'title': 'Household',
          'viewIds': ['choresList'],
        },
        {
          'id': 'detailsPage',
          'title': 'Chore details',
          'viewIds': ['choreDetails'],
        },
      ],
      'tabs': [
        {'pageId': 'home', 'label': 'Household', 'icon': 'check'},
      ],
    };
  }
  return AppSpec.parse(jsonEncode(json));
}

Future<void> mount(
  WidgetTester tester,
  RuntimeAdapter adapter, {
  MiniAppController? controller,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MiniAppRuntime(adapter: adapter, controller: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'omitted labels and title fields render clean lists and details',
    (tester) async {
      final spec = recordSpec();
      final canonical = spec.canonical;
      final adapter = PreviewRuntimeAdapter(spec);
      final controller = MiniAppController();
      final item = (await adapter.query('chores', {})).items.first;
      final originalData = Map<String, dynamic>.of(item.data);
      final title = item.data['title'] as String;
      expect(spec.view('choresList').label, 'choresList');
      expect(spec.view('choresList').titleFieldId, isNull);

      await mount(tester, adapter, controller: controller);
      expect(find.text('Chores'), findsOneWidget);
      expect(find.text('choresList'), findsNothing);
      expect(find.text(title), findsOneWidget);

      await controller.navigate(
        MiniAppLocation('detailsPage', recordId: item.id),
      );
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text('Chore'), findsNothing);
      expect(find.text('Assigned to'), findsOneWidget);
      expect(spec.canonical, canonical);
      expect((await adapter.get(item.id)).data, originalData);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      adapter.dispose();
    },
  );

  testWidgets(
    'custom section labels and explicit title bindings remain intact',
    (tester) async {
      final spec = recordSpec(label: 'Today at home', titleFieldId: 'notes');
      final adapter = PreviewRuntimeAdapter(spec);
      final controller = MiniAppController();
      final item = (await adapter.query('chores', {})).items.first;
      final title = item.data['title'] as String;
      final notes = item.data['notes'] as String;
      await mount(tester, adapter, controller: controller);
      expect(find.text('Today at home'), findsOneWidget);
      expect(find.text('Chores'), findsNothing);
      expect(find.text('Chore: $title'), findsOneWidget);
      final row = find
          .ancestor(
            of: find.text('Chore: $title'),
            matching: find.byType(InkWell),
          )
          .first;
      expect(
        find.descendant(of: row, matching: find.text(notes)),
        findsOneWidget,
      );
      await controller.navigate(
        MiniAppLocation('detailsPage', recordId: item.id),
      );
      await tester.pumpAndSettle();
      expect(find.text(notes), findsOneWidget);
      expect(find.text('Notes'), findsNothing);
      expect(find.text('Chore'), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      adapter.dispose();
    },
  );

  testWidgets('table sections use the same omitted-label fallback', (
    tester,
  ) async {
    final adapter = PreviewRuntimeAdapter(recordSpec(type: 'table'));
    await mount(tester, adapter);
    expect(find.text('Chores'), findsOneWidget);
    expect(find.text('choresList'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
  });

  testWidgets('legacy record cards omit the fallback title from metadata', (
    tester,
  ) async {
    final spec = recordSpec(navigation: false);
    final adapter = PreviewRuntimeAdapter(spec);
    final item = (await adapter.query('chores', {})).items.first;
    final title = item.data['title'] as String;
    await mount(tester, adapter);
    expect(find.text('Chores'), findsOneWidget);
    expect(find.text('choresList'), findsNothing);
    expect(find.text(title), findsOneWidget);
    expect(find.text('Chore: $title'), findsNothing);
    expect(find.textContaining('Assigned to:'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
  });
}
