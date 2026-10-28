import 'dart:async';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_recovery_test.dart' show TestClient;

class InboxClient extends TestClient {
  List<InboxItem> notifications = [];
  Completer<List<InboxItem>>? pendingInbox;
  Object? inboxFailure;
  int inboxReads = 0, activeInboxReads = 0, maximumInboxReads = 0;

  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    if ('$endpoint.$method' != 'runtime.inbox') {
      return super.callServerEndpoint<T>(
        endpoint,
        method,
        args,
        authenticated: authenticated,
      );
    }
    expectSync(authenticated, isTrue);
    methods.add('runtime.inbox');
    inboxReads++;
    activeInboxReads++;
    if (activeInboxReads > maximumInboxReads) {
      maximumInboxReads = activeInboxReads;
    }
    try {
      if (pendingInbox != null) {
        return await pendingInbox!.future as T;
      }
      if (inboxFailure != null) throw inboxFailure!;
      return List<InboxItem>.of(notifications) as T;
    } finally {
      activeInboxReads--;
    }
  }
}

void main() {
  final client = InboxClient();
  setUpAll(() => transport.client = client);
  tearDownAll(client.close);
  setUp(() {
    client.notifications = [];
    client.pendingInbox = null;
    client.inboxFailure = null;
    client.inboxReads = 0;
    client.activeInboxReads = 0;
    client.maximumInboxReads = 0;
    client.methods.clear();
  });

  InboxItem reminder(String title, {int id = 1}) => InboxItem(
    id: id,
    appId: 1,
    title: title,
    body: 'Open your task.',
    createdAt: DateTime.utc(2026, 10, 11),
    isRead: false,
  );

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(key: ValueKey('launcher'))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Inbox refreshes on entry, manually, on resume and while visible',
    (
      tester,
    ) async {
      await mount(tester);
      expect(client.inboxReads, 1);
      client.notifications = [reminder('Delivered after loading')];
      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Delivered after loading'), findsOneWidget);
      expect(client.inboxReads, 2);

      client.notifications = [reminder('Delivered after entering')];
      await tester.tap(find.text('Refresh inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Delivered after entering'), findsOneWidget);
      expect(client.inboxReads, 3);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 30));
      expect(client.inboxReads, 3);
      client.notifications = [reminder('Delivered in background')];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Delivered in background'), findsOneWidget);
      expect(client.inboxReads, 4);

      client.notifications = [reminder('Delivered while reading')];
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Delivered while reading'), findsOneWidget);
      expect(client.inboxReads, 5);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      expect(client.inboxReads, 5);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
      expect(client.inboxReads, 5);
      expect(client.methods, isNot(contains('runtime.readNotification')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending reads do not overlap or restore an obsolete tab response',
    (
      tester,
    ) async {
      await mount(tester);
      final pending = Completer<List<InboxItem>>();
      client.pendingInbox = pending;
      await tester.tap(find.text('Inbox'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(client.inboxReads, 2);
      await tester.tap(find.text('Home'));
      await tester.pump();
      await tester.tap(find.text('Inbox').last);
      await tester.pump();
      client.pendingInbox = null;
      client.notifications = [reminder('Current response')];
      pending.complete([reminder('Obsolete response')]);
      await tester.pumpAndSettle();
      expect(client.maximumInboxReads, 1);
      expect(client.inboxReads, 3);
      expect(find.text('Current response'), findsOneWidget);
      expect(find.text('Obsolete response'), findsNothing);
    },
  );

  testWidgets('full reload waits for the old Inbox read then reads afresh', (
    tester,
  ) async {
    await mount(tester);
    final pending = Completer<List<InboxItem>>();
    client.pendingInbox = pending;
    await tester.tap(find.text('Inbox'));
    await tester.pump();
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(key: ValueKey('launcher'), refreshToken: 1),
      ),
    );
    await tester.pump();
    expect(client.inboxReads, 2);
    client.pendingInbox = null;
    client.notifications = [reminder('Reload response')];
    pending.complete([reminder('Before reload')]);
    await tester.pumpAndSettle();
    expect(client.maximumInboxReads, 1);
    expect(client.inboxReads, 3);
    expect(find.text('Reload response'), findsOneWidget);
    expect(find.text('Before reload'), findsNothing);
  });

  testWidgets(
    'authorization failure clears cached Inbox and manual retry recovers',
    (
      tester,
    ) async {
      client.notifications = [reminder('Private cached reminder')];
      await mount(tester);
      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();
      client.inboxFailure = NestError(
        category: 'forbidden',
        message: 'Private server diagnostic',
      );
      await tester.tap(find.text('Refresh inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Private cached reminder'), findsNothing);
      expect(
        find.textContaining('Couldn’t refresh your Inbox'),
        findsOneWidget,
      );
      expect(find.textContaining('Private server diagnostic'), findsNothing);
      client.inboxFailure = null;
      client.notifications = [reminder('Authorized fresh reminder')];
      await tester.tap(find.text('Refresh inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Authorized fresh reminder'), findsOneWidget);
      expect(find.textContaining('Couldn’t refresh your Inbox'), findsNothing);
    },
  );

  testWidgets(
    'disposing a launcher with a queued reload starts no later read',
    (
      tester,
    ) async {
      await mount(tester);
      final pending = Completer<List<InboxItem>>();
      client.pendingInbox = pending;
      await tester.tap(find.text('Inbox'));
      await tester.pump();
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(key: ValueKey('launcher'), refreshToken: 1),
        ),
      );
      await tester.pump();
      expect(client.inboxReads, 2);
      await tester.pumpWidget(const SizedBox());
      client.pendingInbox = null;
      pending.complete([reminder('Late private response')]);
      await tester.pumpAndSettle();
      expect(client.inboxReads, 2);
      expect(find.text('Late private response'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a covered Inbox does not poll and disposed reads are ignored', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another screen')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final previous = client.inboxReads;
    await tester.pump(const Duration(seconds: 30));
    expect(client.inboxReads, previous);
    navigator.pop();
    await tester.pumpAndSettle();
    final pending = Completer<List<InboxItem>>();
    client.pendingInbox = pending;
    await tester.tap(find.text('Refresh inbox'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete([reminder('Late private response')]);
    await tester.pumpAndSettle();
    expect(find.text('Late private response'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
