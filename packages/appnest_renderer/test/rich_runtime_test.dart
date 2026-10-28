import 'dart:async';
import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final moment = DateTime(2026, 9, 22, 12);

Future<void> mount(
  WidgetTester tester,
  RuntimeAdapter adapter, {
  MiniAppController? controller,
  MiniAppLocation? initialLocation,
  DateTime Function()? clock,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MiniAppRuntime(
          adapter: adapter,
          controller: controller,
          initialLocation: initialLocation,
          clock: clock ?? () => moment,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'accepted external Back trims editor history before in-app Back',
    (tester) async {
      final adapter = PreviewRuntimeAdapter(
        dailyPlannerTemplate(),
        now: moment,
      );
      final controller = MiniAppController();
      await mount(
        tester,
        adapter,
        controller: controller,
        initialLocation: const MiniAppLocation('tasksPage'),
      );
      await controller.navigate(
        const MiniAppLocation('taskDetailPage', recordId: 2),
      );
      await tester.pumpAndSettle();
      await controller.navigate(
        const MiniAppLocation('taskEditorPage', recordId: 2, editing: true),
      );
      await tester.pumpAndSettle();
      await controller.navigate(
        const MiniAppLocation('taskDetailPage', recordId: 2),
      );
      await tester.pumpAndSettle();
      expect(controller.navigationKind, MiniAppNavigationKind.external);
      await controller.back();
      await tester.pumpAndSettle();
      expect(controller.location, const MiniAppLocation('tasksPage'));
      expect(controller.navigationKind, MiniAppNavigationKind.pop);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      controller.dispose();
    },
  );

  AppSpec wrapViews(String template, List<String> views) {
    final json = starterTemplates()[template]!.toJson();
    (json['requires'] as List).add('navigation.v1');
    json['navigation'] = {
      'entryPageId': 'home',
      'pages': [
        {'id': 'home', 'title': 'Home', 'viewIds': views},
      ],
      'tabs': [
        {'pageId': 'home', 'label': 'Home', 'icon': 'check'},
      ],
    };
    return AppSpec.parse(jsonEncode(json));
  }

  for (final choices in [
    ['Healthy', 'Needs care'],
    ['To pack', 'Packed'],
    ['Open', 'Done'],
  ]) {
    testWidgets('workflow ${choices.join('/')} preserves declared meaning', (
      tester,
    ) async {
      final spec = AppSpec.parse(
        jsonEncode(dailyPlannerTemplate().toJson())
            .replaceAll('"Open"', jsonEncode(choices.first))
            .replaceAll('"Done"', jsonEncode(choices.last)),
      );
      final adapter = PreviewRuntimeAdapter(spec, now: moment);
      final item = (await adapter.query(
        'tasks',
        {},
      )).items.firstWhere((item) => item.data['status'] == choices.first);
      await mount(
        tester,
        adapter,
        initialLocation: const MiniAppLocation('tasksPage'),
      );
      final row = find
          .ancestor(
            of: find.text(item.data['title'] as String),
            matching: find.byType(InkWell),
          )
          .first;
      final button = find.descendant(
        of: row,
        matching: find.byTooltip('Mark ${choices.last.toLowerCase()}'),
      );
      await tester.ensureVisible(button);
      expect(
        find.descendant(
          of: button,
          matching: find.byIcon(
            choices.first == 'Open'
                ? Icons.radio_button_unchecked
                : Icons.swap_horiz,
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect((await adapter.get(item.id)).data['status'], choices.last);
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(
            choices.first == 'Open' ? Icons.check_circle : Icons.swap_horiz,
          ),
        ),
        findsOneWidget,
      );
      if (choices.first != 'Open')
        expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    });
  }

  testWidgets('list edit remains reachable when details omit that action', (
    tester,
  ) async {
    final json = dailyPlannerTemplate().toJson();
    ((json['views'] as List).firstWhere(
              (view) => view['id'] == 'taskDetails',
            )['actionIds']
            as List)
        .remove('editTask');
    final adapter = PreviewRuntimeAdapter(
      AppSpec.parse(jsonEncode(json)),
      now: moment,
    );
    final controller = MiniAppController();
    await mount(
      tester,
      adapter,
      controller: controller,
      initialLocation: const MiniAppLocation('tasksPage'),
    );
    await tester.ensureVisible(find.text('Edit task').first);
    await tester.tap(find.text('Edit task').first);
    await tester.pumpAndSettle();
    expect(
      controller.location,
      const MiniAppLocation('taskEditorPage', recordId: 3, editing: true),
    );
    await tester.enterText(find.byType(TextField).first, 'Edited from list');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.location, const MiniAppLocation('tasksPage'));
    expect((await adapter.get(3)).data['title'], 'Edited from list');
    await tester.ensureVisible(find.text('Edited from list'));
    await tester.tap(find.text('Edited from list'));
    await tester.pumpAndSettle();
    expect(controller.location!.pageId, 'taskDetailPage');
    expect(find.text('Edit task'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
    controller.dispose();
  });

  for (final linksToDetails in [false, true]) {
    testWidgets(
      'secondary workflow remains reachable with details=$linksToDetails',
      (tester) async {
        final json = dailyPlannerTemplate().toJson();
        final collection = (json['collections'] as List).single;
        (collection['fields'] as List).add({
          'id': 'packing',
          'label': 'Packing',
          'type': 'choice',
          'required': true,
          'choices': ['To pack', 'Packed'],
        });
        (collection['behaviors'] as List).add({
          'id': 'packingFlow',
          'type': 'workflow.v1',
          'fieldId': 'packing',
          'transitions': {
            'To pack': ['Packed'],
            'Packed': ['To pack'],
          },
        });
        (json['actions'] as List).add({
          'id': 'packTask',
          'label': 'Change packing status',
          'collectionId': 'tasks',
          'capability': 'workflow.transition.v1',
          'behaviorId': 'packingFlow',
        });
        final view = (json['views'] as List).firstWhere(
          (view) => view['id'] == 'allTasks',
        );
        (view['actionIds'] as List).add('packTask');
        if (!linksToDetails) view.remove('detailPageId');
        final adapter = PreviewRuntimeAdapter(
          AppSpec.parse(jsonEncode(json)),
          now: moment,
        );
        await mount(
          tester,
          adapter,
          initialLocation: const MiniAppLocation('tasksPage'),
        );
        final item = await adapter.get(3);
        expect(item.data['packing'], 'To pack');
        await tester.ensureVisible(find.text('Mark packed').first);
        await tester.tap(find.text('Mark packed').first);
        await tester.pumpAndSettle();
        final updated = await adapter.get(3);
        expect(updated.data['packing'], 'Packed');
        expect(updated.data['status'], item.data['status']);
        expect(find.text('Mark to pack'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        adapter.dispose();
      },
    );
  }

  test(
    'preview command retries and query cursors retain request identity',
    () async {
      final adapter = PreviewRuntimeAdapter(
        dailyPlannerTemplate(),
        now: moment,
      );
      final add = adapter.spec.action('addTask');
      const data = {
        'data': {'title': 'Only once', 'status': 'Open'},
      };
      await adapter.execute(add, null, data, 'same-key');
      await adapter.execute(add, null, data, 'same-key');
      expect((await adapter.query('tasks', {})).total, 5);
      await expectLater(
        adapter.execute(add, null, {
          'data': {'title': 'Changed', 'status': 'Open'},
        }, 'same-key'),
        throwsA(isA<SpecException>()),
      );
      final first = await adapter.query('tasks', {'limit': 1});
      expect(
        (await adapter.query('tasks', {
          'limit': 2,
          'cursor': first.cursor,
        })).items.length,
        2,
      );
      await expectLater(
        adapter.query('tasks', {
          'limit': 1,
          'cursor': first.cursor,
          'sort': [
            {'fieldId': 'dueAt', 'descending': true},
          ],
        }),
        throwsA(isA<SpecException>()),
      );
      adapter.dispose();
    },
  );

  test('preview timestamp precision and descending null placement match PostgreSQL', () async {
    final spec = dailyPlannerTemplate(),
        adapter = PreviewRuntimeAdapter(dailyPlannerTemplate(), now: moment);
    final add = adapter.spec.action('addTask');
    await adapter.execute(add, null, {
      'data': {
        'title': 'Exact second',
        'status': 'Open',
        'dueAt': '2026-09-23T08:00:00.000Z',
      },
    }, 'second');
    await adapter.execute(add, null, {
      'data': {
        'title': 'One microsecond later',
        'status': 'Open',
        'dueAt': '2026-09-23T08:00:00.000001Z',
      },
    }, 'micro');
    final descending = await adapter.query('tasks', {
      'sort': [
        {'fieldId': 'dueAt', 'descending': true},
      ],
    });
    expect(descending.items.first.data['title'], 'One microsecond later');
    expect(descending.items.last.data['dueAt'], isNull);
    final before = await adapter.query('tasks', {
      'filters': [
        {
          'fieldId': 'dueAt',
          'operator': 'lt',
          'value': '2026-09-23T08:00:00.000001Z',
        },
      ],
    });
    expect(
      before.items.any((item) => item.data['title'] == 'Exact second'),
      true,
    );
    expect(
      before.items.any((item) => item.data['title'] == 'One microsecond later'),
      false,
    );
    final same = await adapter.query('tasks', {
      'filters': [
        {
          'fieldId': 'dueAt',
          'operator': 'in',
          'value': ['2026-09-23T01:00:00-07:00'],
        },
      ],
    });
    expect(same.items.single.data['title'], 'Exact second');
    expect(spec.name, adapter.spec.name);
    adapter.dispose();
  });

  testWidgets(
    'navigation-wrapped capacity views retain claim, release and create editing',
    (tester) async {
      final base = starterTemplates()['volunteer']!;
      final spec = wrapViews('volunteer', [base.views.first.id]);
      final adapter = PreviewRuntimeAdapter(spec, now: moment);
      await mount(tester, adapter);
      expect(find.textContaining('4 of 4 places available'), findsWidgets);
      await tester.tap(find.text('Join shift').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Your place is confirmed'), findsOneWidget);
      expect(find.text('Cancel sign-up'), findsOneWidget);
      await tester.tap(find.text('Create shift'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextField),
            )
            .first,
        'Unsaved shift',
      );
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );

  testWidgets(
    'navigation-wrapped boards retain status columns and assignment actions',
    (tester) async {
      final adapter = PreviewRuntimeAdapter(
        wrapViews('chores', ['board']),
        now: moment,
      );
      await mount(tester, adapter);
      expect(find.text('Open'), findsWidgets);
      expect(find.text('Doing'), findsWidgets);
      expect(find.text('Done'), findsWidgets);
      expect(find.text('Assign'), findsWidgets);
      expect(find.text('Edit notes'), findsWidgets);
      expect(find.text('Add chore'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );

  testWidgets('ungrouped rich summary shows exact total without crashing', (
    tester,
  ) async {
    final json = wrapViews('reading', ['readingSummary']).toJson();
    (json['views'] as List)
        .firstWhere((view) => view['id'] == 'readingSummary')
        .remove('groupByFieldId');
    final adapter = PreviewRuntimeAdapter(
      AppSpec.parse(jsonEncode(json)),
      now: moment,
    );
    await mount(tester, adapter);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('This page is unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
  });

  test('preview exact summaries span pages, UTC-normalize filters, and isolate writes', () async {
    final spec = dailyPlannerTemplate();
    final adapter = PreviewRuntimeAdapter(spec, now: moment);
    final untouched = PreviewRuntimeAdapter(spec, now: moment);
    for (var i = 0; i < 105; i++) {
      await adapter.execute(spec.action('addTask'), null, {
        'data': {
          'title': 'Added $i',
          'status': 'Open',
          'dueAt': '2026-09-22T14:00:00Z',
        },
      }, 'create-$i');
    }
    final summary = await adapter.summary('tasks', {'limit': 1}, 'status');
    expect(summary.total, 109);
    expect(summary.groups, {'Open': 108, 'Done': 1});
    expect((await untouched.summary('tasks', {}, 'status')).total, 4);
    final page = await adapter.query('tasks', {
      'filters': [
        {
          'fieldId': 'dueAt',
          'operator': 'eq',
          'value': '2026-09-22T07:00:00-07:00',
        },
      ],
    });
    expect(page.total, 105);
    adapter.dispose();
    untouched.dispose();
  });

  test(
    'preview enforces protected workflow, revision and approved transitions',
    () async {
      final spec = dailyPlannerTemplate(),
          adapter = PreviewRuntimeAdapter(dailyPlannerTemplate(), now: moment);
      // Actions belong to the active definition, as in the live action catalog.
      final active = adapter.spec;
      final item = (await adapter.query('tasks', {})).items.first;
      await expectLater(
        adapter.execute(active.action('editTask'), item, {
          'data': {'status': 'Open'},
        }, 'patch'),
        throwsA(isA<SpecException>()),
      );
      await expectLater(
        adapter.execute(active.action('moveTask'), item, {
          'value': 'Done',
        }, 'invalid'),
        throwsA(isA<SpecException>()),
      );
      await adapter.execute(active.action('moveTask'), item, {
        'value': 'Open',
      }, 'reopen');
      await expectLater(
        adapter.execute(active.action('editTask'), item, {
          'data': {'notes': 'stale'},
        }, 'stale'),
        throwsA(isA<SpecException>()),
      );
      await expectLater(
        adapter.execute(active.action('addTask'), null, {
          'data': {'title': 'invalid', 'status': 'Done'},
        }, 'bad-start'),
        throwsA(isA<SpecException>()),
      );
      expect(spec.name, active.name);
      expect((await adapter.get(item.id)).data['status'], 'Open');
      adapter.dispose();
    },
  );

  testWidgets(
    'dedicated editor initializes status, guards close and browser navigation, saves locally',
    (tester) async {
      final adapter = PreviewRuntimeAdapter(
            dailyPlannerTemplate(),
            now: moment,
          ),
          controller = MiniAppController();
      await mount(tester, adapter, controller: controller);
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      expect(
        controller.location,
        const MiniAppLocation('taskEditorPage', editing: true),
      );
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Status'),
        findsNothing,
      );
      await tester.enterText(find.byType(TextField).first, 'A considered day');
      final pending = controller.navigate(const MiniAppLocation('tasksPage'));
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(await pending, false);
      expect(controller.location!.pageId, 'taskEditorPage');
      final close = controller.canLeave();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(await close, false);
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'todayPage');
      final created = (await adapter.query('tasks', {
        'filters': [
          {'fieldId': 'title', 'operator': 'contains', 'value': 'considered'},
        ],
      })).items.single;
      expect(created.data['status'], 'Open');
      expect(created.data.containsKey('reminderAt'), false);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'returning from details retains loaded pages and scroll position',
    (tester) async {
      final adapter = PreviewRuntimeAdapter(
            dailyPlannerTemplate(),
            now: moment,
          ),
          controller = MiniAppController();
      for (var i = 0; i < 35; i++) {
        await adapter.execute(adapter.spec.action('addTask'), null, {
          'data': {'title': 'Extra $i', 'status': 'Open'},
        }, 'extra-$i');
      }
      await mount(
        tester,
        adapter,
        controller: controller,
        initialLocation: const MiniAppLocation('tasksPage'),
      );
      await tester.ensureVisible(find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Extra 34'));
      await tester.pumpAndSettle();
      final position = tester.getTopLeft(find.text('Extra 34'));
      await tester.tap(find.text('Extra 34'));
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'taskDetailPage');
      await controller.back();
      await tester.pumpAndSettle();
      expect(find.text('Extra 34'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Extra 34')).dy,
        closeTo(position.dy, 1),
      );
      expect(find.text('Load more'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'revocation removes the legacy form modal as well as underlying records',
    (tester) async {
      final base = starterTemplates()['volunteer']!;
      final adapter = RevocablePreview(
        wrapViews('volunteer', [base.views.first.id]),
        now: moment,
      );
      await mount(tester, adapter);
      await tester.tap(find.text('Edit shift').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Private modal title',
      );
      adapter.revoked = true;
      adapter.events.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Private modal title'), findsNothing);
      expect(find.text('This page is unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await adapter.events.close();
      adapter.dispose();
    },
  );

  testWidgets(
    'detail and editor return to preserved search/filter and workflow toggles directly',
    (tester) async {
      final adapter = PreviewRuntimeAdapter(
            dailyPlannerTemplate(),
            now: moment,
          ),
          controller = MiniAppController();
      await mount(
        tester,
        adapter,
        controller: controller,
        initialLocation: const MiniAppLocation('tasksPage'),
      );
      await tester.enterText(find.byType(TextFormField).first, 'walk');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Tasks · 1'), findsOneWidget);
      await tester.tap(find.text('Make time for a walk'));
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'taskDetailPage');
      expect(find.text('Simulated preview · No reminder set'), findsOneWidget);
      await tester.ensureVisible(find.text('Mark done'));
      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();
      expect(find.text('Mark open'), findsOneWidget);
      await tester.ensureVisible(find.text('Back'));
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Tasks · 1'), findsOneWidget);
      expect(find.text('walk'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      controller.dispose();
    },
  );

  testWidgets('newest tab response wins when earlier queries finish late', (
    tester,
  ) async {
    final adapter = DelayedPreview(dailyPlannerTemplate(), now: moment),
        controller = MiniAppController();
    await mount(tester, adapter, controller: controller);
    adapter.delay = true;
    final first = controller.navigate(const MiniAppLocation('tasksPage'));
    await tester.pump();
    final second = controller.navigate(const MiniAppLocation('progressPage'));
    await tester.pumpAndSettle();
    expect(await second, true);
    expect(controller.location!.pageId, 'progressPage');
    adapter.release.complete();
    await tester.pumpAndSettle();
    expect(await first, true);
    expect(controller.location!.pageId, 'progressPage');
    expect(find.text('Today’s scheduled tasks'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
    controller.dispose();
  });

  testWidgets(
    'midnight refresh moves scheduled items using injectable local clock',
    (tester) async {
      var clock = moment;
      final adapter = PreviewRuntimeAdapter(
        dailyPlannerTemplate(),
        now: moment,
      );
      await mount(tester, adapter, clock: () => clock);
      expect(find.text('Make time for a walk'), findsOneWidget);
      clock = DateTime(2026, 9, 23, 0, 1);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      expect(
        find.text('Make time for a walk'),
        findsOneWidget,
      ); // Now in overdue.
      expect(
        find.text('Plan the day'),
        findsNothing,
      ); // Completed, therefore not overdue.
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );

  testWidgets(
    'revoked access clears sensitive details including dirty editor',
    (tester) async {
      final adapter = RevocablePreview(dailyPlannerTemplate(), now: moment),
          controller = MiniAppController();
      await mount(
        tester,
        adapter,
        controller: controller,
        initialLocation: const MiniAppLocation(
          'taskEditorPage',
          recordId: 2,
          editing: true,
        ),
      );
      await tester.enterText(
        find.byType(TextField).first,
        'Private unsaved title',
      );
      adapter.revoked = true;
      adapter.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Private unsaved title'), findsNothing);
      expect(find.text('This page is unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await adapter.events.close();
      adapter.dispose();
      controller.dispose();
    },
  );

  testWidgets('read-only roles show records without mutation actions', (
    tester,
  ) async {
    final adapter = ReadOnlyPreview(dailyPlannerTemplate(), now: moment);
    await mount(
      tester,
      adapter,
      initialLocation: const MiniAppLocation('tasksPage'),
    );
    expect(find.text('Read-only · Viewer access'), findsOneWidget);
    expect(find.text('Add task'), findsNothing);
    expect(find.byTooltip('Mark done'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
  });
}

class DelayedPreview extends PreviewRuntimeAdapter {
  DelayedPreview(super.spec, {super.now});
  final release = Completer<void>();
  bool delay = false;
  @override
  Future<RuntimePage> query(
    String collectionId,
    Map<String, dynamic> query,
  ) async {
    if (delay && query['limit'] == 25) await release.future;
    return super.query(collectionId, query);
  }
}

class RevocablePreview extends PreviewRuntimeAdapter {
  RevocablePreview(super.spec, {super.now});
  bool revoked = false;
  final events = StreamController<void>.broadcast();
  @override
  Stream<void> watch() => events.stream;
  @override
  Future<RuntimeItem> get(int recordId) async {
    if (revoked) throw const SpecException('Record unavailable.');
    return super.get(recordId);
  }
}

class ReadOnlyPreview extends PreviewRuntimeAdapter {
  ReadOnlyPreview(super.spec, {super.now});
  @override
  bool get readOnly => true;
  @override
  String get role => 'viewer';
}
