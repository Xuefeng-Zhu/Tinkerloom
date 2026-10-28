import 'dart:async';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/builder/builder_screen.dart';
import 'package:appnest_flutter/features/mini_app/mini_app_screen.dart';
import 'package:appnest_flutter/navigation/app_router.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

import 'mini_app_navigation_test.dart'
    show MemoryAuthStorage, NavigationClient, TestBrowserHistory;

class DraftNavigationClient extends NavigationClient {
  bool published = false;
  Object? manifestFailure;
  final resumes = <Map<String, dynamic>>[];

  // Synthetic streams do not need the SDK's real WebSocket shutdown lock.
  @override
  Future<void> closeStreamingMethodConnections({Object? exception}) async {}
  @override
  AppManifest get manifest => super.manifest.copyWith(
    workspaceId: 5,
    versionId: published ? 1 : null,
  );

  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    expectSync(authenticated, isTrue);
    if ('$endpoint.$method' == 'apps.manifest' && manifestFailure != null) {
      throw manifestFailure!;
    }
    if ('$endpoint.$method' == 'builder.begin') {
      resumes.add(Map<String, dynamic>.from(args));
      return BuilderSnapshot(
        appId: 1,
        draftId: 21,
        mutation: 3,
        stage: 'preview ready',
        candidateJson: preview.spec.canonical,
        candidateHash: preview.spec.hash,
        diagnostics: [],
        changes: [],
        enabledRuleIds: [],
        candidateReady: true,
        latestRequest: 'Make notes for my garden',
      ) as T;
    }
    if ('$endpoint.$method' == 'builder.publish') published = true;
    return super.callServerEndpoint<T>(
      endpoint,
      method,
      args,
      authenticated: authenticated,
    );
  }
}

void main() {
  final client = DraftNavigationClient();
  Future<void> authenticate() => client.auth.updateSignedInUser(
    AuthSuccess.fromJson({
      'authStrategy': 'session',
      'token': 'synthetic-test-only',
      'authUserId': '11111111-1111-4111-8111-111111111111',
      'scopeNames': <String>[],
    }),
  );
  setUpAll(() async {
    final font = FontLoader('Lora')
      ..addFont(rootBundle.load('assets/fonts/Lora.ttf'));
    await font.load();
    transport.client = client;
    client.authSessionManager = FlutterAuthSessionManager(
      storage: MemoryAuthStorage(),
    );
    await authenticate();
  });
  setUp(() {
    client.preview = PreviewRuntimeAdapter(notesTemplate());
    client.published = false;
    client.manifestFailure = null;
    client.resumes.clear();
    client.calls.clear();
    client.publications.clear();
  });
  tearDown(() => client.preview.dispose());
  tearDownAll(() async {
    client.close();
    await client.events.close();
  });

  test('draft links contain only a valid app identifier and round trip', () {
    final location = AppNestLocation.fromUri(Uri.parse('/drafts/12'));
    expect(location.appId, isNull);
    expect(location.draftAppId, 12);
    expect(location.uri.toString(), '/drafts/12');
    expect(location.withHistory('session', 2).draftAppId, 12);
    for (final invalid in [
      '/drafts/0',
      '/drafts/-1',
      '/drafts/nope',
      '/drafts/1/more',
    ]) {
      expect(AppNestLocation.fromUri(Uri.parse(invalid)).draftAppId, isNull);
    }
  });

  Future<(AppNestRouterDelegate, TestBrowserHistory)> mount(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final history = TestBrowserHistory(Uri.parse('/drafts/1'));
    final router = AppNestRouterDelegate(browserGo: history.go);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: ThemeData(fontFamily: 'Lora'),
        routerDelegate: router,
        routeInformationProvider: history,
        routeInformationParser: const AppNestRouteParser(),
      ),
    );
    await tester.pumpAndSettle();
    return (router, history);
  }

  testWidgets(
    'direct draft link authorizes then resumes with persisted workspace',
    (tester) async {
      final (router, history) = await mount(tester);
      expect(find.byType(BuilderScreen), findsOneWidget);
      expect(client.resumes.single['workspaceId'], 5);
      expect(client.resumes.single['appId'], 1);
      expect(
        tester
            .widget<BuilderScreen>(find.byType(BuilderScreen))
            .initial
            .draftId,
        21,
      );
      expect(find.text('Make notes for my garden'), findsOneWidget);
      expect(router.currentConfiguration.draftAppId, 1);
      expect(history.value.uri.path, '/drafts/1');
      await router.closeApp();
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.uri.path, '/');
      expect(find.byType(BuilderScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh uses server draft again without starting generation', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await mount(tester);
    expect(client.resumes, hasLength(2));
    expect(client.resumes.every((request) => request['appId'] == 1), isTrue);
    expect(client.calls, isNot(contains('builder.generate')));
    expect(find.byType(BuilderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable draft hides diagnostic and never begins a draft', (
    tester,
  ) async {
    client.manifestFailure = NestError(
      category: 'notFound',
      message: 'private diagnostic',
    );
    final (router, _) = await mount(tester);
    expect(find.text('This draft is unavailable.'), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
    expect(client.resumes, isEmpty);
    await tester.tap(find.text('Back to your apps'));
    await tester.pumpAndSettle();
    expect(router.currentConfiguration.uri.path, '/');
    expect(tester.takeException(), isNull);
  });

  testWidgets('transient load error retries same durable app identifier', (
    tester,
  ) async {
    client.manifestFailure = TimeoutException('private transport details');
    await mount(tester);
    expect(
      find.text('Your draft could not be loaded. Try again.'),
      findsOneWidget,
    );
    expect(client.resumes, isEmpty);
    client.manifestFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(client.resumes.single['appId'], 1);
    expect(find.byType(BuilderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'browser Back and Forward restore the durable draft without creating an app',
    (tester) async {
      final history = TestBrowserHistory(Uri.parse('/'));
      final router = AppNestRouterDelegate(browserGo: history.go);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: ThemeData(fontFamily: 'Lora'),
          routerDelegate: router,
          routeInformationProvider: history,
          routeInformationParser: const AppNestRouteParser(),
        ),
      );
      await tester.pumpAndSettle();
      await router.openDraft(1);
      await tester.pumpAndSettle();
      expect(history.value.uri.path, '/drafts/1');
      await history.go(-1);
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.uri.path, '/');
      expect(find.byType(BuilderScreen), findsNothing);
      await history.go(1);
      await tester.pumpAndSettle();
      expect(router.currentConfiguration.draftAppId, 1);
      expect(find.byType(BuilderScreen), findsOneWidget);
      expect(client.resumes, hasLength(2));
      expect(client.resumes.every((request) => request['appId'] == 1), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'publication replaces draft URL with the app and submits existing draft',
    (tester) async {
      final (router, history) = await mount(tester);
      await tester.tap(find.text('Use app'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Use app'),
        ),
      );
      await tester.pumpAndSettle();
      expect(client.publications.single.draftId, 21);
      expect(router.currentConfiguration.draftAppId, isNull);
      expect(router.currentConfiguration.appId, 1);
      expect(history.entries, hasLength(1));
      expect(history.value.uri.path, startsWith('/apps/1'));
      expect(find.byType(MiniAppScreen), findsOneWidget);
      expect(find.byType(BuilderScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('published draft link opens the live app without a new draft', (
    tester,
  ) async {
    client.published = true;
    final (router, history) = await mount(tester);
    expect(client.resumes, isEmpty);
    expect(router.currentConfiguration.draftAppId, isNull);
    expect(router.currentConfiguration.appId, 1);
    expect(history.value.uri.path, startsWith('/apps/1'));
    expect(find.byType(MiniAppScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unpublished manifest cannot render a draft through the live app route',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MiniAppScreen(appId: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This app or item is unavailable. Try again to check your access.',
        ),
        findsOneWidget,
      );
      expect(find.byType(MiniAppRuntime), findsNothing);
      expect(client.calls, isNot(contains('runtime.query')));
      expect(client.resumes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sign in gate preserves draft URL and resolves after authentication',
    (tester) async {
      await client.auth.updateSignedInUser(null);
      final (router, _) = await mount(tester);
      expect(client.resumes, isEmpty);
      expect(client.calls, isEmpty);
      expect(router.currentConfiguration.uri.path, '/drafts/1');
      await authenticate();
      await tester.pumpAndSettle();
      expect(find.byType(BuilderScreen), findsOneWidget);
      expect(client.resumes.single['appId'], 1);
      expect(tester.takeException(), isNull);
    },
  );
}
