import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:tinkerloom_client/tinkerloom_client.dart';
import 'package:tinkerloom_flutter/client.dart' as transport;
import 'package:tinkerloom_flutter/navigation/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthClient extends Client {
  factory _AuthClient() {
    late _AuthClient result;
    result = _AuthClient._(ClientAuth(signIn: (_, _) => result.login!.future));
    return result;
  }
  _AuthClient._(ClientAuth auth) : super('http://localhost:8180/', auth: auth);
  Completer<Map<String, dynamic>>? login;
  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async => switch ('$endpoint.$method') {
    'apps.workspaces' => <WorkspaceInfo>[] as T,
    'builder.platform' => PlatformInfo(
      aiAvailable: false,
      aiMode: 'Template mode',
      development: true,
      actorId: 'test',
    ) as T,
    _ => throw StateError('Unexpected test request: $endpoint.$method'),
  };
}

Map<String, dynamic> _session() => {
  'id': '11111111-1111-4111-8111-111111111111',
  'email': 'synthetic@example.test',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _AuthClient client;
  setUpAll(() async {
    // Use the app's bundled proportional font; Ahem makes the SDK's compact
    // account links artificially wider than their 400-pixel form container.
    final font = FontLoader('Lora')
      ..addFont(rootBundle.load('assets/fonts/Lora.ttf'));
    await font.load();
    client = _AuthClient();
    transport.client = client;
  });
  setUp(() async {
    client.login = null;
    client.auth.setSession(null);
  });
  tearDownAll(() => client.close());

  Future<TinkerloomRouterDelegate> mount(WidgetTester tester) async {
    final router = TinkerloomRouterDelegate();
    await tester.pumpWidget(
      MaterialApp.router(
        theme: ThemeData(fontFamily: 'Lora'),
        routerDelegate: router,
        routeInformationParser: const TinkerloomRouteParser(),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(router.dispose);
    return router;
  }

  Future<void> focusEmail(WidgetTester tester) async {
    final editable = find.byType(EditableText).first;
    await tester.enterText(editable, 'morgan@appnest.local');
    final state = tester.state<EditableTextState>(editable);
    state.selectAll(SelectionChangedCause.keyboard);
    state.showToolbar();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      Overlay.maybeOf(tester.element(editable), rootOverlay: true),
      isNotNull,
    );
  }

  testWidgets('router login fields can focus and show selection overlays', (
    tester,
  ) async {
    await mount(tester);
    await focusEmail(tester);
  });

  testWidgets('Appwrite email login opens the authenticated navigator', (
    tester,
  ) async {
    final router = await mount(tester);
    await tester.enterText(
      find.byType(EditableText).at(0),
      'morgan@appnest.local',
    );
    await tester.enterText(
      find.byType(EditableText).at(1),
      'synthetic-test-password',
    );
    await tester.pump(const Duration(milliseconds: 600));
    client.login = Completer<Map<String, dynamic>>();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    client.login!.complete(_session());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(client.auth.isAuthenticated, isTrue);
    expect(router.navigatorKey.currentState, isNotNull);
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('sign-out removes an open editor and restores usable login', (
    tester,
  ) async {
    client.auth.setSession(_session());
    final router = await mount(tester);
    final navigator = router.navigatorKey.currentState!;
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: TextField()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'unfinished edit');
    final departingFocus = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    client.auth.setSession(null);
    // A native focus-gained event can arrive before Navigator deactivation has
    // finished. Departing fields must already be excluded from traversal.
    expect(departingFocus.canRequestFocus, isFalse);
    expect(departingFocus.skipTraversal, isTrue);
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.forward,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('unfinished edit'), findsNothing);
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: tester.view.viewId,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.forward,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await focusEmail(tester);
  });
}
