import 'dart:async';

import 'package:tinkerloom_client/tinkerloom_client.dart';

import 'package:tinkerloom_flutter/client.dart' as transport;
import 'package:tinkerloom_flutter/features/builder/builder_screen.dart';
import 'package:tinkerloom_flutter/features/mini_app/mini_app_screen.dart';
import 'package:tinkerloom_flutter/main.dart';
import 'package:tinkerloom_flutter/screens/sign_in_screen.dart';
import 'package:tinkerloom_flutter/screens/startup_screen.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'draft_navigation_test.dart' show DraftNavigationClient;
import 'mini_app_navigation_test.dart' show TestBrowserHistory;

class _AuthStorage {
  _AuthStorage(this.value);
  Map<String, dynamic>? value;
  int reads = 0, clears = 0;
  Object? readFailure;
  Future<Map<String, dynamic>?> get() async {
    reads++;
    if (readFailure != null) throw readFailure!;
    return value;
  }

  Future<void> set(Map<String, dynamic>? data) async {
    if (data == null) clears++;
    value = data;
  }
}

class _StartupClient extends DraftNavigationClient {
  factory _StartupClient() {
    late _StartupClient result;
    result = _StartupClient._(
      ClientAuth(
        restore: () async {
          final user = await result.storage.get();
          if (user == null) return null;
          result.validations++;
          if (result.validationFailure != null) throw result.validationFailure!;
          final valid = result.pendingValidation == null
              ? result.sessionAccepted
              : await result.pendingValidation!.future;
          if (!valid) await result.storage.set(null);
          return valid ? user : null;
        },
      ),
    );
    return result;
  }
  _StartupClient._(ClientAuth auth) : super(auth: auth);
  late _AuthStorage storage;
  Completer<bool>? pendingValidation;
  Object? validationFailure;
  int validations = 0;
  bool sessionAccepted = true;
}

Map<String, dynamic> _session() => {
  'id': '11111111-1111-4111-8111-111111111111',
  'email': 'synthetic@example.test',
};

void main() {
  late _StartupClient client;
  late _AuthStorage storage;
  late transport.ClientInitialization initialization;
  var creations = 0;

  setUpAll(() async {
    // Match the existing auth overlay fixture; Ahem makes compact links wider.
    await (FontLoader(
      'Lora',
    )..addFont(rootBundle.load('assets/fonts/Lora.ttf'))).load();
  });

  setUp(() {
    client = _StartupClient();
    transport.client = client;
    client
      ..preview = PreviewRuntimeAdapter(notesTemplate())
      ..pendingValidation = null
      ..validationFailure = null
      ..validations = 0
      ..sessionAccepted = true;
    client.calls.clear();
    client.resumes.clear();
    storage = _AuthStorage(_session());
    client.storage = storage;
    client.auth.setSession(storage.value);
    creations = 0;
    initialization = transport.ClientInitialization(() async {
      creations++;
      return client.auth;
    });
  });

  tearDown(() async {
    client.preview.dispose();
    client.close();
    await client.events.close();
  });

  Future<void> mount(WidgetTester tester, {Widget? child}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Lora'),
        home: StartupScreen(
          initialize: initialization.initialize,
          child: child ?? const Scaffold(body: Text('Authenticated workspace')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'authenticated validation beyond two seconds keeps a visible app',
    (
      tester,
    ) async {
      client.pendingValidation = Completer<bool>();
      await mount(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Opening Tinkerloom'), findsOneWidget);
      expect(find.text('Checking your session…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Authenticated workspace'), findsNothing);
      expect(find.byType(SignInScreen), findsNothing);
      expect(client.auth.isAuthenticated, isTrue);
      expect(storage.clears, 0);
      expect(tester.takeException(), isNull);

      client.pendingValidation!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Authenticated workspace'), findsOneWidget);
      expect(creations, 1);
      expect(client.validations, 1);
    },
  );

  testWidgets('raw SDK validation timeout is recoverable without losing auth', (
    tester,
  ) async {
    initialization = transport.ClientInitialization(() async {
      creations++;
      return client.auth;
    }, validationTimeout: const Duration(milliseconds: 100));
    client.pendingValidation = Completer<bool>();
    await mount(tester);
    await tester.pump(const Duration(milliseconds: 101));
    expect(find.text('Can’t connect to Tinkerloom'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('saved session has been kept'), findsOneWidget);
    expect(client.auth.isAuthenticated, isTrue);
    expect(storage.value?['id'], _session()['id']);
    expect(storage.clears, 0);
    expect(tester.takeException(), isNull);

    // Future.timeout does not cancel the SDK request. Settle that request before
    // making the explicit retry; its late success must not dismiss recovery.
    client.pendingValidation!.complete(true);
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    client.pendingValidation = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Authenticated workspace'), findsOneWidget);
    expect(creations, 1);
    expect(storage.reads, 1);
    expect(client.validations, 1);
    expect(storage.clears, 0);
  });

  testWidgets('Appwrite session retry reuses transport and coalesces restore', (
    tester,
  ) async {
    storage.value = _session();
    client.validationFailure = BackendNetworkException(
      'private transport diagnostic',
    );
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Can’t connect to Tinkerloom'), findsOneWidget);
    expect(find.textContaining('private transport diagnostic'), findsNothing);
    expect(client.auth.isAuthenticated, isTrue);
    expect(storage.clears, 0);

    client.validationFailure = null;
    client.pendingValidation = Completer<bool>();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    // A competing caller observes the same active restore attempt.
    final sameAttempt = initialization.initialize();
    expect(client.validations, 2);
    expect(creations, 1);
    expect(find.text('Retry'), findsNothing);
    client.pendingValidation!.complete(true);
    await sameAttempt;
    await tester.pumpAndSettle();
    expect(find.text('Authenticated workspace'), findsOneWidget);
    // Two explicit attempts; no background session or database requests.
    expect(storage.reads, 2);
    expect(storage.clears, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed local restore can retry without recreating transport', (
    tester,
  ) async {
    storage.readFailure = StateError('private setup diagnostic');
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t open Tinkerloom'), findsOneWidget);
    expect(find.textContaining('private setup diagnostic'), findsNothing);
    storage.readFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Authenticated workspace'), findsOneWidget);
    expect(creations, 1);
    expect(storage.reads, 2);
    expect(client.validations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first visit renders sign-in without a validation request', (
    tester,
  ) async {
    storage.value = null;
    await mount(
      tester,
      child: const SignInScreen(child: Text('Private app')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SignInWidget), findsOneWidget);
    expect(find.text('Opening Tinkerloom'), findsNothing);
    expect(client.validations, 0);
    expect(client.calls, isEmpty);
    expect(creations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a server-rejected session reaches sign-in before private routes',
    (
      tester,
    ) async {
      client.sessionAccepted = false;
      await mount(
        tester,
        child: const SignInScreen(child: Text('Private app')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SignInWidget), findsOneWidget);
      expect(client.auth.isAuthenticated, isFalse);
      expect(storage.clears, 1);
      expect(client.calls, isEmpty);
      expect(find.text('Private app'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final path in ['/apps/1/pages/homePage', '/drafts/1']) {
    testWidgets('startup retry retains the original $path route', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      client.published = path.startsWith('/apps');
      client.pendingValidation = Completer<bool>();
      final history = TestBrowserHistory(Uri.parse(path));
      addTearDown(history.dispose);
      await tester.pumpWidget(
        MyApp(
          initialize: initialization.initialize,
          routeInformationProvider: history,
        ),
      );
      await tester.pump();
      expect(find.text('Opening Tinkerloom'), findsOneWidget);
      expect(history.value.uri.path, path);
      expect(client.calls, isEmpty);
      client.pendingValidation!.completeError(
        TimeoutException('private validation diagnostic'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(history.value.uri.path, path);
      expect(find.byType(SignInScreen), findsNothing);
      expect(storage.clears, 0);

      client.pendingValidation = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(history.value.uri.path, path);
      expect(
        path.startsWith('/apps')
            ? find.byType(MiniAppScreen)
            : find.byType(BuilderScreen),
        findsOneWidget,
      );
      expect(creations, 1);
      expect(client.validations, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
