import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/home/home_screen.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_recovery_test.dart' show TestClient;

class LauncherClient extends TestClient {
  final templates = <TemplateInfo>[];
  final notifications = <InboxItem>[];

  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    expectSync(authenticated, isTrue);
    if ('$endpoint.$method' == 'apps.templates') return templates as T;
    if ('$endpoint.$method' == 'runtime.inbox') return notifications as T;
    return super.callServerEndpoint<T>(
      endpoint,
      method,
      args,
      authenticated: authenticated,
    );
  }
}

void main() {
  final client = LauncherClient();
  setUpAll(() => transport.client = client);
  tearDownAll(client.close);
  setUp(() {
    client.manifests.clear();
    client.templates.clear();
    client.notifications.clear();
    client.beginRequests.clear();
    client.generationRequests.clear();
    client.methods.clear();
    client.aiAvailable = true;
    client.currentDraft = null;
  });

  AppManifest app({int id = 1, bool draft = false, bool pinned = true}) =>
      AppManifest(
        appId: id,
        workspaceId: 1,
        name: draft ? 'Saved planner' : 'Daily Planner',
        versionId: draft ? null : 1,
        specJson: dailyPlannerTemplate().canonical,
        role: 'owner',
        archived: false,
        pinned: pinned,
        recordCount: 3,
        availablePlaces: 0,
      );

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    Future<void> Function(int)? onResumeDraft,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: HomeScreen(onResumeDraft: onResumeDraft),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('returning users see apps first and can reveal creation', (
    tester,
  ) async {
    client.manifests.add(app());
    await mount(tester);
    expect(tester.getRect(find.text('Daily Planner')).bottom, lessThan(700));
    expect(find.byKey(const ValueKey('app-idea')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('toggle-creation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-idea')), findsOneWidget);
    expect(client.beginRequests, isEmpty);
  });

  testWidgets('unpinned apps remain visible when no apps are pinned', (
    tester,
  ) async {
    client.manifests.add(app(pinned: false));
    await mount(tester);
    expect(tester.getRect(find.text('Daily Planner')).bottom, lessThan(700));
    expect(find.text('Your next idea belongs here.'), findsNothing);
  });

  testWidgets('saved drafts are rediscovered after launcher recreation', (
    tester,
  ) async {
    final opened = <int>[];
    client.manifests.add(app(id: 17, draft: true));
    await mount(tester, onResumeDraft: (id) async => opened.add(id));
    expect(find.text('Saved planner'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, onResumeDraft: (id) async => opened.add(id));
    await tester.tap(find.byKey(const ValueKey('resume-app-draft-17')));
    await tester.pumpAndSettle();
    expect(opened, [17]);
    expect(client.beginRequests, isEmpty);
    expect(client.generationRequests, isEmpty);
  });

  testWidgets(
    'saved drafts retain name and resume action at 320px and 200% text',
    (
      tester,
    ) async {
      final opened = <int>[];
      client.manifests.add(app(id: 17, draft: true));
      await mount(
        tester,
        width: 320,
        scale: 2,
        onResumeDraft: (id) async => opened.add(id),
      );
      final title = find.text('Saved planner');
      await tester.ensureVisible(title);
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(paragraph.didExceedMaxLines, isFalse);
      final resume = find.byKey(const ValueKey('resume-app-draft-17'));
      await tester.ensureVisible(resume);
      expect(resume.hitTestable(), findsOneWidget);
      expect(tester.getRect(resume).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(resume).right, lessThanOrEqualTo(320));
      expect(tester.getSize(resume).height, greaterThanOrEqualTo(48));
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(opened, [17]);
      expect(client.beginRequests, isEmpty);
      expect(client.generationRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile templates retain descriptions and preview without writes',
    (
      tester,
    ) async {
      final spec = notesTemplate();
      client.templates.add(
        TemplateInfo(
          key: 'notes',
          name: spec.name,
          specJson: spec.canonical,
          description: 'Capture notes and organize them by category.',
        ),
      );
      final semantics = tester.ensureSemantics();
      await mount(tester, width: 320, scale: 2);
      await tester.tap(find.text('Templates').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Capture notes and organize them by category.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Preview My Notes'), findsOneWidget);
      expect(find.bySemanticsLabel('Use My Notes template'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('preview-template-notes')),
      );
      await tester.tap(find.byKey(const ValueKey('preview-template-notes')));
      await tester.pumpAndSettle();
      expect(find.text('My Notes preview'), findsOneWidget);
      expect(
        find.text('Sample data only. Your new app will start empty.'),
        findsOneWidget,
      );
      expect(client.beginRequests, isEmpty);
      expect(client.generationRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets('the account menu is available on mobile without signing out', (
    tester,
  ) async {
    client.manifests.add(app());
    await mount(tester);
    expect(find.byTooltip('Sign out'), findsNothing);
    await tester.tap(find.byTooltip('Your account'));
    await tester.pumpAndSettle();
    expect(find.text('Copy my account ID'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('inbox uses readable local time and announces unread status', (
    tester,
  ) async {
    client.notifications.add(
      InboxItem(
        id: 1,
        appId: 1,
        title: 'A reminder from Planner',
        body: 'Open your task.',
        createdAt: DateTime.now().toUtc(),
        isRead: false,
      ),
    );
    final semantics = tester.ensureSemantics();
    await mount(tester);
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Today,'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Unread reminder')), findsWidgets);
    expect(client.methods, isNot(contains('runtime.readNotification')));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
