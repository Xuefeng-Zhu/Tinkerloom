import 'dart:async';
import 'dart:convert';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/builder/page_editor.dart';
import 'package:appnest_flutter/features/builder/builder_screen.dart';
import 'package:appnest_flutter/navigation/app_router.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

class MemoryAuthStorage implements ClientAuthSuccessStorage {
  AuthSuccess? value;
  @override
  Future<AuthSuccess?> get() async => value;
  @override
  Future<void> set(AuthSuccess? data) async {
    value = data;
  }
}

/// Synthetic test transport; production routing still passes through auth.
class NavigationClient extends Client {
  NavigationClient() : super('http://localhost:8180/');
  late PreviewRuntimeAdapter preview;
  final events = StreamController<AppEvent>.broadcast();
  bool denied = false;
  Completer<void>? blockedGet;
  Completer<void>? blockedBegin;
  final calls = <String>[];
  final publications = <PublishRequest>[];
  AppManifest get manifest => AppManifest(
    appId: 1,
    workspaceId: 1,
    name: preview.spec.name,
    versionId: 1,
    specJson: preview.spec.canonical,
    role: 'owner',
    archived: false,
    pinned: true,
    recordCount: 4,
    availablePlaces: 0,
    approvedRuleIds: ['taskReminder'],
  );
  RuntimeRecord dto(RuntimeItem r) => RuntimeRecord(
    id: r.id,
    collectionId: r.collectionId,
    data: r.data,
    revision: r.revision,
    claimed: r.claimed,
    allowedActions: r.allowedActions,
  );

  @override
  dynamic callStreamingServerEndpoint<T, G>(
    String endpoint,
    String method,
    Map<String, dynamic> args,
    Map<String, Stream> streams, {
    bool authenticated = true,
  }) {
    expectSync(authenticated, isTrue);
    return events.stream;
  }

  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    expectSync(authenticated, isTrue);
    calls.add('$endpoint.$method');
    if (denied && (method == 'manifest' || endpoint == 'runtime')) {
      throw NestError(category: 'forbidden', message: 'private diagnostic');
    }
    Object? result;
    switch ('$endpoint.$method') {
      case 'apps.manifest':
        result = manifest;
      case 'apps.workspaces':
        result = [WorkspaceInfo(id: 1, name: 'Personal', role: 'owner')];
      case 'apps.list':
        result = [manifest];
      case 'apps.templates':
        result = <TemplateInfo>[];
      case 'builder.platform':
        result = PlatformInfo(
          aiAvailable: false,
          aiMode: 'Template mode',
          development: true,
          actorId: 'test',
        );
      case 'builder.begin':
        await blockedBegin?.future;
        result = BuilderSnapshot(
          appId: 1,
          draftId: 1,
          baseVersionId: 1,
          mutation: 0,
          stage: 'preview ready',
          candidateJson: preview.spec.canonical,
          candidateHash: preview.spec.hash,
          diagnostics: [],
          changes: [],
          enabledRuleIds: [],
          candidateReady: true,
        );
      case 'runtime.inbox':
        result = <InboxItem>[];
      case 'runtime.get':
        if (blockedGet != null) await blockedGet!.future;
        result = dto(await preview.get(args['recordId'] as int));
      case 'runtime.query':
        final page = await preview.query(
          args['collectionId'] as String,
          jsonDecode(args['queryJson'] as String),
        );
        result = RecordPage(
          records: page.items.map(dto).toList(),
          total: page.total,
          nextCursor: page.cursor,
        );
      case 'runtime.summary':
        final summary = await preview.summary(
          args['collectionId'] as String,
          jsonDecode(args['queryJson'] as String),
          args['groupFieldId'] as String,
        );
        result = RecordSummary(total: summary.total, groups: summary.groups);
      case 'runtime.reminderState':
        result = [
          ReminderState(ruleId: 'taskReminder', state: 'unset', eligible: true),
        ];
      case 'runtime.execute':
        final request = args['request'] as ActionRequest;
        final record = request.targetRecordId == null
            ? null
            : await preview.get(request.targetRecordId!);
        await preview.execute(
          preview.spec.action(request.actionId),
          record,
          Map<String, dynamic>.from(request.input as Map),
          request.idempotencyKey,
        );
        final saved = record == null
            ? (await preview.query('tasks', {})).items.last
            : await preview.get(record.id);
        result = ActionOutcome(
          recordId: saved.id,
          revision: saved.revision,
          message: 'Saved',
        );
      case 'builder.publish':
        publications.add(args['request'] as PublishRequest);
        result = 1;
      default:
        throw StateError('Unexpected $endpoint.$method');
    }
    return result as T;
  }
}

/// Models the browser stack, including replacement and back/forward events.
class TestBrowserHistory extends RouteInformationProvider with ChangeNotifier {
  TestBrowserHistory(Uri initial) : entries = [RouteInformation(uri: initial)];
  final List<RouteInformation> entries;
  final List<int> traversals = [];
  int index = 0;
  @override
  RouteInformation get value => entries[index];
  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    if (type == RouteInformationReportingType.neglect ||
        routeInformation.uri == value.uri) {
      entries[index] = routeInformation;
    } else {
      entries.removeRange(index + 1, entries.length);
      entries.add(routeInformation);
      index++;
    }
  }

  Future<bool> go(int delta) async {
    final next = index + delta;
    if (next < 0 || next >= entries.length) return false;
    traversals.add(delta);
    index = next;
    notifyListeners();
    return true;
  }
}

void main() {
  final client = NavigationClient();
  setUpAll(() async {
    transport.client = client;
    client.authSessionManager = FlutterAuthSessionManager(
      storage: MemoryAuthStorage(),
    );
    await client.auth.updateSignedInUser(
      AuthSuccess.fromJson({
        'authStrategy': 'session',
        'token': 'synthetic-test-only',
        'authUserId': '11111111-1111-4111-8111-111111111111',
        'scopeNames': <String>[],
      }),
    );
  });
  setUp(() {
    client.preview = PreviewRuntimeAdapter(dailyPlannerTemplate());
    client.denied = false;
    client.blockedGet = null;
    client.blockedBegin = null;
    client.calls.clear();
    client.publications.clear();
  });
  tearDown(() => client.preview.dispose());
  tearDownAll(() async {
    client.close();
    await client.events.close();
  });

  test(
    'route identifiers round-trip; malformed routes never become destinations',
    () {
      final location = AppNestLocation.fromUri(
        Uri.parse('/apps/12/pages/taskEditorPage?record=9&edit=true'),
      );
      expect(location.appId, 12);
      expect(
        location.miniAppLocation,
        const MiniAppLocation('taskEditorPage', recordId: 9, editing: true),
      );
      expect(
        location.uri.toString(),
        '/apps/12/pages/taskEditorPage?record=9&edit=true',
      );
      for (final route in [
        '/apps/nope',
        '/apps/-1',
        '/apps/1/unknown/page',
        '/apps/1/pages/x-y',
        '/?invite=keep-existing',
      ]) {
        expect(AppNestLocation.fromUri(Uri.parse(route)).appId, isNull);
      }
    },
  );

  Future<AppNestRouterDelegate> mount(
    WidgetTester tester,
    AppNestLocation location,
  ) async {
    final router = AppNestRouterDelegate();
    await router.setNewRoutePath(location);
    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: router,
        routeInformationParser: const AppNestRouteParser(),
        routeInformationProvider: PlatformRouteInformationProvider(
          initialRouteInformation: RouteInformation(uri: location.uri),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(router.dispose);
    return router;
  }

  Future<(AppNestRouterDelegate, TestBrowserHistory)> mountBrowser(
    WidgetTester tester,
    AppNestLocation location,
  ) async {
    final history = TestBrowserHistory(location.uri);
    final router = AppNestRouterDelegate(browserGo: history.go);
    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: router,
        routeInformationParser: const AppNestRouteParser(),
        routeInformationProvider: history,
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(router.dispose);
    addTearDown(history.dispose);
    return (router, history);
  }

  testWidgets('rapid Customize taps open a single builder', (tester) async {
    await mount(tester, const AppNestLocation(appId: 1));
    client.blockedBegin = Completer<void>();
    final customize = tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == 'Customize app',
          ),
        )
        .onPressed!;
    customize();
    customize();
    await tester.pump();
    expect(client.calls.where((call) => call == 'builder.begin'), hasLength(1));
    client.blockedBegin!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BuilderScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(BuilderScreen), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Customize app',
            ),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'browser stack retains parent across rejected Back, Cancel, and renderer Back',
    (tester) async {
      final (router, history) = await mountBrowser(
        tester,
        const AppNestLocation(appId: 1, pageId: 'tasksPage'),
      );
      expect(
        history.entries.length,
        1,
        reason: history.entries.map((e) => e.uri.toString()).join(' -> '),
      );
      await tester.ensureVisible(find.text('Make time for a walk'));
      await tester.tap(find.text('Make time for a walk'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit task'));
      await tester.tap(find.text('Edit task'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Unsaved');
      expect(history.entries.length, 3);
      await history.go(-1);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.pageId, 'taskEditorPage');
      expect(history.index, 2);
      expect(history.entries.length, 3);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.pageId, 'taskDetailPage');
      expect(history.index, 1);
      expect(
        history.entries.length,
        3,
      ); // Editor remains only in forward history.
      await history.go(-1);
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.pageId, 'tasksPage');
      await history.go(1);
      await tester.pumpAndSettle();
      await history.go(1);
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.pageId, 'taskEditorPage');
      await history.go(-1);
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.pageId, 'taskDetailPage');
      await tester.ensureVisible(find.text('Back'));
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.pageId, 'tasksPage');
      expect(history.index, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('rapid browser Back supersedes the earlier discard destination', (
    tester,
  ) async {
    final (router, history) = await mountBrowser(
      tester,
      const AppNestLocation(appId: 1, pageId: 'tasksPage'),
    );
    await tester.ensureVisible(find.text('Make time for a walk'));
    await tester.tap(find.text('Make time for a walk'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit task'));
    await tester.tap(find.text('Edit task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Keep this draft');
    await history.go(-1);
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);
    await history.go(-1);
    await tester.pumpAndSettle();
    expect(history.index, 2);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(router.currentConfiguration.pageId, 'taskEditorPage');
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(history.value.uri.path, '/apps/1/pages/taskEditorPage');
    expect(history.entries.length, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'late record navigation cannot read a screen removed by a newer route',
    (tester) async {
      final (router, _) = await mountBrowser(
        tester,
        const AppNestLocation(appId: 1, pageId: 'tasksPage'),
      );
      final gate = Completer<void>();
      client.blockedGet = gate;
      final pending = router.setNewRoutePath(
        const AppNestLocation(appId: 1, pageId: 'taskDetailPage', recordId: 2),
      );
      await tester.pump();
      await router.setNewRoutePath(const AppNestLocation());
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.appId, isNull);
      gate.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.appId, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Save traverses to existing details and browser Back reaches Tasks',
    (tester) async {
      final (router, history) = await mountBrowser(
        tester,
        const AppNestLocation(appId: 1, pageId: 'tasksPage'),
      );
      await tester.ensureVisible(find.text('Make time for a walk'));
      await tester.tap(find.text('Make time for a walk'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit task'));
      await tester.tap(find.text('Edit task'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Saved title');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.pageId, 'taskDetailPage');
      expect(history.index, 1);
      expect(history.traversals, [-1]);
      await history.go(-1);
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.pageId, 'tasksPage');
      expect(find.text('Saved title'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'direct editor links return by replacement without leaving the site',
    (tester) async {
      final (router, history) = await mountBrowser(
        tester,
        const AppNestLocation(
          appId: 1,
          pageId: 'taskEditorPage',
          recordId: 2,
          editing: true,
        ),
      );
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.pageId, 'todayPage');
      expect(
        history.entries.length,
        1,
        reason: history.entries.map((e) => e.uri.toString()).join(' -> '),
      );
      expect(history.traversals, isEmpty);
      expect(history.value.uri.path, '/apps/1/pages/todayPage');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'record-only inbox location resolves authenticated details and close returns launcher',
    (tester) async {
      final router = await mount(
        tester,
        const AppNestLocation(appId: 1, recordId: 2),
      );
      expect(find.text('Make time for a walk'), findsOneWidget);
      expect(router.currentConfiguration.pageId, 'taskDetailPage');
      expect(client.calls, contains('runtime.get'));
      await tester.tap(find.byTooltip('Close mini-app'));
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.appId, isNull);
      expect(find.text('Your apps'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'browser navigation and system back respect one discard decision',
    (tester) async {
      final router = await mount(tester, const AppNestLocation(appId: 1));
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Unsaved private task',
      );
      final route = router.setNewRoutePath(
        const AppNestLocation(appId: 1, pageId: 'tasksPage'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await route;
      expect(router.currentConfiguration.pageId, 'taskEditorPage');
      final back = router.popRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await back;
      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('Unsaved private task'), findsOneWidget);
      expect(router.currentConfiguration.pageId, 'taskEditorPage');
      final leave = router.setNewRoutePath(const AppNestLocation());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await leave;
      expect(router.currentConfiguration.appId, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unknown page falls back and unavailable app hides transport diagnostics',
    (tester) async {
      final router = await mount(
        tester,
        const AppNestLocation(appId: 1, pageId: 'removedPage'),
      );
      expect(router.currentConfiguration.pageId, 'todayPage');
      client.denied = true;
      await router.openApp(2);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This app or item is unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('private diagnostic'), findsNothing);
      expect(find.text('Make time for a walk'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'publication submits only the exact reviewed candidate and approved rules',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final spec = dailyPlannerTemplate();
      BuilderSnapshot snapshot(AppSpec s, int mutation) => BuilderSnapshot(
        candidateReady: true,
        appId: 1,
        draftId: 1,
        mutation: mutation,
        stage: 'preview ready',
        candidateJson: s.canonical,
        candidateHash: s.hash,
        diagnostics: [],
        changes: s.diff(null),
        enabledRuleIds: [],
      );
      int? published;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Build'),
                onPressed: () async {
                  published = await Navigator.push<int>(
                    context,
                    MaterialPageRoute<int>(
                      builder: (_) => BuilderScreen(initial: snapshot(spec, 0)),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use app'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      final changed = spec.patch({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': 'Changed while reviewing',
      }, () => 'unused');
      final dynamic state = tester.state(find.byType(BuilderScreen));
      state.update(snapshot(changed, 1));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Use app'),
        ),
      );
      await tester.pumpAndSettle();
      expect(client.publications, isEmpty);
      expect(
        find.textContaining('The preview changed during review'),
        findsOneWidget,
      );
      await tester.tap(find.text('Use app'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Use app'),
        ),
      );
      await tester.pumpAndSettle();
      expect(published, 1);
      expect(client.publications.single.candidateHash, changed.hash);
      expect(client.publications.single.enabledRuleIds, ['taskReminder']);
      expect(
        client.publications.single.reviewHash,
        hashJson({
          'candidateHash': changed.hash,
          'enabledRuleIds': ['taskReminder'],
          'activateExistingRecordIds': <int>[],
        }),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'page editor creates a reachable tab and preserves selected section order',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? result;
      final spec = dailyPlannerTemplate();
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
      await tester.tap(find.byKey(const ValueKey('Page:todayPage')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New page').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'My overview');
      await tester.tap(find.text('Add to tab bar'));
      for (final id in ['allTasks', 'todayTasks']) {
        final section = find.byKey(ValueKey('add-section-$id'));
        await tester.ensureVisible(section);
        await tester.pumpAndSettle();
        expect(section.hitTestable(), findsOneWidget);
        await tester.tap(section);
        await tester.pumpAndSettle();
      }
      final moveUp = find.byTooltip('Move up').last;
      await tester.ensureVisible(moveUp);
      await tester.pumpAndSettle();
      expect(moveUp.hitTestable(), findsOneWidget);
      await tester.tap(moveUp);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update preview'));
      await tester.pumpAndSettle();
      expect(result?['type'], 'AddPage');
      final updated = spec.patch(result!, () => 'myOverview');
      expect(updated.page('myOverview').viewIds, ['todayTasks', 'allTasks']);
      expect(updated.navigation!.tabs.last.pageId, 'myOverview');
      expect(updated.navigation!.tabs.last.label, 'My overview');
      expect(spec.compatibilityErrors(updated), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'page editor edits ordered tab labels with a validated semantic patch',
    (tester) async {
      Map<String, dynamic>? result;
      final spec = dailyPlannerTemplate();
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
      await tester.tap(find.text('Navigation').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'My day');
      await tester.tap(find.text('Update preview'));
      await tester.pumpAndSettle();
      expect(result?['type'], 'SetNavigation');
      final updated = spec.patch(result!, () => 'allocatedId');
      expect(updated.navigation!.tabs.first.label, 'My day');
      expect(spec.compatibilityErrors(updated), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
