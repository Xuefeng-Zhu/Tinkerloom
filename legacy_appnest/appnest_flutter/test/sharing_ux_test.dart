import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/mini_app/mini_app_screen.dart';
import 'package:appnest_flutter/features/mini_app/invitation_link.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mini_app_navigation_test.dart' show NavigationClient;

class SharingClient extends NavigationClient {
  String backend = 'http://192.168.1.20:8180/';
  @override
  String get host => backend;

  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    if ('$endpoint.$method' == 'apps.invite') {
      calls.add('apps.invite');
      expectSync(authenticated, isTrue);
      return 'synthetic-token+with/slash' as T;
    }
    return super.callServerEndpoint<T>(
      endpoint,
      method,
      args,
      authenticated: authenticated,
    );
  }
}

void main() {
  final client = SharingClient();
  setUpAll(() => transport.client = client);
  setUp(() {
    client.preview = PreviewRuntimeAdapter(dailyPlannerTemplate());
    client.calls.clear();
    client.backend = 'http://192.168.1.20:8180/';
  });
  tearDown(() => client.preview.dispose());
  tearDownAll(() async {
    client.close();
    await client.events.close();
  });

  Future<void> openInvitation(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      const MaterialApp(home: MiniAppScreen(appId: 1)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mini-app menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite to app'));
    await tester.pumpAndSettle();
  }

  testWidgets('phone creates and copies a reachable web invitation', (
    tester,
  ) async {
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openInvitation(tester);
    await tester.tap(find.text('Create invitation'));
    await tester.pumpAndSettle();
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    final link = Uri.parse(text.data!);
    expect(link.origin, 'http://192.168.1.20:8182');
    expect(link.queryParameters['invite'], 'synthetic-token+with/slash');
    expect(client.calls.where((c) => c == 'apps.invite'), hasLength(1));
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(clipboard, [text.data]);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('invalid phone connection fails before creating a token', (
    tester,
  ) async {
    client.backend = 'http://localhost:8180/';
    await openInvitation(tester);
    await tester.tap(find.text('Create invitation'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Sharing links are unavailable'),
      findsOneWidget,
    );
    expect(client.calls, isNot(contains('apps.invite')));
    expect(find.text('Copy link'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  test('browser sharing preserves the browser origin', () {
    expect(
      invitationWebOrigin(
        backendUrl: 'https://api.example.com/',
        currentPage: Uri.parse('https://app.example.com/apps/1?other=value'),
        web: true,
      ).toString(),
      'https://app.example.com/',
    );
  });

  test('native production sharing requires a validated public web origin', () {
    Uri resolve(String configured) => invitationWebOrigin(
      backendUrl: 'https://api.example.com/',
      currentPage: Uri.file('/native/bundle'),
      web: false,
      phone: true,
      publicWebUrl: configured,
    );
    expect(
      resolve('https://app.example.com/').origin,
      'https://app.example.com',
    );
    for (final invalid in [
      '',
      'appnest://app.example.com',
      'https://account:password@app.example.com',
      'https://app.example.com/path',
      'https://app.example.com/?invite=stale',
      'https://app.example.com/#fragment',
      'http://127.0.0.1:8182/',
    ]) {
      expect(
        () => resolve(invalid),
        throwsA(isA<InvitationLinkConfigurationError>()),
      );
    }
  });

  testWidgets('invitation explains roles without creating a link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: MiniAppScreen(appId: 1)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mini-app menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite to app'));
    await tester.pumpAndSettle();
    expect(find.text('Access level'), findsOneWidget);
    expect(
      find.textContaining('Cannot change app structure or sharing.'),
      findsOneWidget,
    );
    expect(find.text('Recipient account ID'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewer').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Can view shared records.'), findsOneWidget);
    await tester.tap(find.text('Invite a specific account (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('Recipient account ID'), findsOneWidget);
    expect(find.text('They can copy this from Your account.'), findsOneWidget);
    expect(client.calls, isNot(contains('apps.invite')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
