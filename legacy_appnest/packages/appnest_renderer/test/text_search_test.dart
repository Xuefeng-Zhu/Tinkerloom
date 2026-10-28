import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppSpec inventorySpec({
  String? titleFieldId = 'name',
  String type = 'list',
  bool choiceFilter = false,
  bool fullFilterBudget = false,
}) => AppSpec.parse(
  jsonEncode({
    'formatVersion': 1,
    'name': 'Candle inventory',
    'theme': 'sage',
    'icon': 'check',
    'requires': [
      'collections.v1',
      'navigation.v1',
      'views.$type.v1',
      'views.details.v1',
      'views.configured.v1',
      'records.create.v1',
    ],
    'collections': [
      {
        'id': 'items',
        'label': 'Candles',
        'fields': [
          {
            'id': 'name',
            'label': 'Item name',
            'type': 'text',
            'required': true,
          },
          {
            'id': 'quantity',
            'label': 'Quantity',
            'type': 'integer',
            'required': false,
          },
          if (type == 'calendar')
            {
              'id': 'madeAt',
              'label': 'Made on',
              'type': 'timestamp',
              'required': false,
            },
          if (choiceFilter)
            {
              'id': 'category',
              'label': 'Location',
              'type': 'choice',
              'required': true,
              'choices': ['Studio', 'Fair'],
            },
        ],
        'behaviors': <Object>[],
      },
    ],
    'actions': [
      {
        'id': 'addItem',
        'label': 'Add item',
        'capability': 'records.create.v1',
        'collectionId': 'items',
      },
    ],
    'views': [
      {
        'id': 'itemsList',
        'type': type,
        'collectionId': 'items',
        'label': 'Stock',
        if (titleFieldId != null) 'titleFieldId': titleFieldId,
        'filterFieldIds': [if (choiceFilter) 'category'],
        'detailPageId': 'detailsPage',
        'actionIds': ['addItem'],
        if (type == 'calendar') 'options': {'dateFieldId': 'madeAt'},
        'query': {
          'limit': 2,
          if (fullFilterBudget)
            'filters': List.generate(
              Limits.filters - (type == 'calendar' ? 2 : 0),
              (_) => {'fieldId': 'quantity', 'operator': 'gte', 'value': 0},
            ),
        },
      },
      {
        'id': 'itemDetails',
        'type': 'details',
        'collectionId': 'items',
        'titleFieldId': 'name',
        'actionIds': <String>[],
      },
    ],
    'navigation': {
      'entryPageId': 'stockPage',
      'pages': [
        {
          'id': 'stockPage',
          'title': 'Stock',
          'viewIds': ['itemsList'],
        },
        {
          'id': 'detailsPage',
          'title': 'Item details',
          'viewIds': ['itemDetails'],
        },
      ],
      'tabs': [
        {'pageId': 'stockPage', 'label': 'Stock', 'icon': 'check'},
      ],
    },
    'policyPresetRequest': 'personalTracker.v1',
    'automationRequests': <Object>[],
  }),
);

class ObservedInventory extends PreviewRuntimeAdapter {
  ObservedInventory(super.spec);
  final queries = <Map<String, dynamic>>[];
  bool viewer = false;
  @override
  bool get readOnly => viewer;
  @override
  String get role => viewer ? 'viewer' : 'owner';
  @override
  bool permits(ActionSpec action) => !viewer;
  @override
  Future<RuntimePage> query(String collectionId, Map<String, dynamic> query) {
    queries.add(jsonDecode(jsonEncode(query)) as Map<String, dynamic>);
    return super.query(collectionId, query);
  }
}

Future<ObservedInventory> inventory(AppSpec spec) async {
  final adapter = ObservedInventory(spec);
  final choice = spec.collection('items').fields.any((f) => f.id == 'category');
  final date = spec.collection('items').fields.any((f) => f.id == 'madeAt');
  for (final (name, location) in [
    ('Lavender candle', 'Studio'),
    ('Vanilla candle', 'Fair'),
    ('Lavender gift tin', 'Fair'),
  ]) {
    await adapter.execute(spec.action('addItem'), null, {
      'data': {
        'name': name,
        'quantity': 4,
        if (choice) 'category': location,
        if (date) 'madeAt': DateTime.now().toUtc().toIso8601String(),
      },
    }, 'create-$name');
  }
  return adapter;
}

Future<void> mount(
  WidgetTester tester,
  ObservedInventory adapter, {
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
    'read-only mobile list searches without choice filters and resets pagination',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final spec = inventorySpec();
      final canonical = spec.canonical;
      final adapter = await inventory(spec);
      adapter.viewer = true;
      final controller = MiniAppController();
      await mount(tester, adapter, controller: controller);
      expect(find.byKey(const ValueKey('search-itemsList')), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.text('Add item'), findsNothing);
      await tester.ensureVisible(find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(adapter.queries.last['cursor'], isNotNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('search-itemsList')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('search-itemsList')),
        'lavender',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(adapter.queries.last.containsKey('cursor'), false);
      expect(adapter.queries.last['filters'], [
        {'fieldId': 'name', 'operator': 'contains', 'value': 'lavender'},
      ]);
      expect(find.text('Lavender candle'), findsOneWidget);
      expect(find.text('Lavender gift tin'), findsOneWidget);
      expect(find.text('Vanilla candle'), findsNothing);
      expect(find.text('Candles · 2'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      await tester.tap(find.text('Lavender candle'));
      await tester.pumpAndSettle();
      await controller.back();
      await tester.pumpAndSettle();
      expect(find.text('lavender'), findsOneWidget);
      expect(find.text('Candles · 2'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('search-itemsList')),
        '',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(adapter.queries.last['filters'], isEmpty);
      expect(adapter.queries.last.containsKey('cursor'), false);
      expect(find.text('Load more'), findsOneWidget);
      expect(spec.canonical, canonical);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      adapter.dispose();
    },
  );

  testWidgets('text search combines with existing typed choice filters', (
    tester,
  ) async {
    final adapter = await inventory(inventorySpec(choiceFilter: true));
    await mount(tester, adapter);
    await tester.enterText(
      find.byKey(const ValueKey('search-itemsList')),
      'Lavender',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-itemsList-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fair').last);
    await tester.pumpAndSettle();
    expect(adapter.queries.last['filters'], [
      {'fieldId': 'name', 'operator': 'contains', 'value': 'Lavender'},
      {'fieldId': 'category', 'operator': 'eq', 'value': 'Fair'},
    ]);
    expect(find.text('Lavender gift tin'), findsOneWidget);
    expect(find.text('Lavender candle'), findsNothing);
    expect(find.text('Candles · 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
  });

  testWidgets(
    'navigated table searches without choice filters through the real adapter',
    (tester) async {
      final adapter = await inventory(inventorySpec(type: 'table'));
      adapter.viewer = true;
      await mount(tester, adapter);
      expect(find.byKey(const ValueKey('search-itemsList')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('search-itemsList')),
        'lavender',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(adapter.queries.last['filters'], [
        {'fieldId': 'name', 'operator': 'contains', 'value': 'lavender'},
      ]);
      expect(find.text('Lavender candle'), findsOneWidget);
      expect(find.text('Lavender gift tin'), findsOneWidget);
      expect(find.text('Vanilla candle'), findsNothing);
      expect(find.text('2 records'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );

  for (final type in ['list', 'table']) {
    for (final titleFieldId in <String?>['quantity', null]) {
      testWidgets(
        '$type unsupported or implicit title $titleFieldId does not offer text search',
        (tester) async {
          final adapter = await inventory(
            inventorySpec(type: type, titleFieldId: titleFieldId),
          );
          await mount(tester, adapter);
          expect(find.byKey(const ValueKey('search-itemsList')), findsNothing);
          expect(adapter.queries.last['filters'], isEmpty);
          expect(find.text('This page is unavailable'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          adapter.dispose();
        },
      );
    }
  }

  for (final type in ['list', 'table', 'calendar']) {
    testWidgets('$type search respects fixed and component filter budgets', (
      tester,
    ) async {
      final adapter = await inventory(
        inventorySpec(type: type, fullFilterBudget: true),
      );
      await mount(tester, adapter);
      expect(find.byKey(const ValueKey('search-itemsList')), findsNothing);
      expect(adapter.queries.last['filters'], hasLength(Limits.filters));
      expect(find.text('This page is unavailable'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    });
  }
}
