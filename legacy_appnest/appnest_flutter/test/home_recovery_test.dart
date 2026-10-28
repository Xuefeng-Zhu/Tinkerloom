import 'dart:async';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/builder/builder_screen.dart';
import 'package:appnest_flutter/features/home/home_load_failure.dart';
import 'package:appnest_flutter/features/home/home_screen.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Test-only transport. Production HomeScreen still uses authenticated endpoints.
class TestClient extends Client {
  TestClient() : super('http://localhost:8180/');
  Object? failure;
  Completer<void>? pending;
  int workspaceRequests = 0;
  bool aiAvailable = false;
  final methods = <String>[];
  Completer<void>? pendingCreation;
  Object? creationFailure;
  Object? generationFailure;
  Object? draftFailure;
  bool acceptBeforeGenerationFailure = false;
  BuilderSnapshot? currentDraft;
  final beginRequests = <Map<String, dynamic>>[];
  final generationRequests = <Map<String, dynamic>>[];
  final questionRequests = <Map<String, dynamic>>[];
  Completer<List<GuidanceQuestion>>? pendingQuestions;
  Object? questionFailure;
  List<GuidanceQuestion> questionResponse = const [];
  final manifests = <AppManifest>[];

  BuilderSnapshot snapshot() {
    final spec = dailyPlannerTemplate();
    return BuilderSnapshot(
      appId: 1,
      draftId: 1,
      mutation: 0,
      stage: 'preview ready',
      candidateJson: spec.canonical,
      candidateHash: spec.hash,
      diagnostics: [],
      changes: spec.diff(null),
      enabledRuleIds: [],
      candidateReady: true,
    );
  }

  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    methods.add('$endpoint.$method');
    expectSync(authenticated, isTrue);
    if (method == 'workspaces') {
      workspaceRequests++;
      await pending?.future;
      if (failure != null) throw failure!;
    }
    if ('$endpoint.$method' == 'builder.begin') {
      beginRequests.add(Map<String, dynamic>.from(args));
      await pendingCreation?.future;
      if (creationFailure != null) throw creationFailure!;
      currentDraft = snapshot();
    }
    if ('$endpoint.$method' == 'builder.generate') {
      generationRequests.add(Map<String, dynamic>.from(args));
      if (generationFailure == null || acceptBeforeGenerationFailure) {
        currentDraft = snapshot().copyWith(
          mutation: (args['mutation'] as int) + 1,
          jobId: 42,
          latestRequest: args['request'] as String,
        );
      }
      if (generationFailure != null) throw generationFailure!;
    }
    if ('$endpoint.$method' == 'builder.get' && draftFailure != null) {
      throw draftFailure!;
    }
    if ('$endpoint.$method' == 'builder.suggestQuestions') {
      questionRequests.add(Map<String, dynamic>.from(args));
      if (questionFailure != null) throw questionFailure!;
      return (pendingQuestions == null
              ? questionResponse
              : await pendingQuestions!.future)
          as T;
    }
    return switch ('$endpoint.$method') {
      'apps.workspaces' => [
        WorkspaceInfo(id: 1, name: 'Recovered workspace', role: 'owner'),
      ],
      'builder.platform' => PlatformInfo(
        aiAvailable: aiAvailable,
        aiMode: aiAvailable
            ? 'Live AI'
            : 'Template mode — AI provider not configured',
        development: true,
        actorId: 'test-actor',
      ),
      'apps.list' => manifests,
      'apps.templates' => <TemplateInfo>[],
      'runtime.inbox' => <InboxItem>[],
      'builder.begin' || 'builder.generate' || 'builder.get' => currentDraft!,
      _ => throw StateError('Unexpected endpoint: $endpoint.$method'),
    } as T;
  }
}

void main() {
  GuidanceQuestion question(String text, List<String> options) =>
      GuidanceQuestion(question: text, options: options);

  final testClient = TestClient();
  setUpAll(() => transport.client = testClient);
  tearDownAll(testClient.close);
  setUp(() {
    testClient.failure = null;
    testClient.pending = null;
    testClient.workspaceRequests = 0;
    testClient.aiAvailable = false;
    testClient.methods.clear();
    testClient.pendingCreation = null;
    testClient.creationFailure = null;
    testClient.generationFailure = null;
    testClient.draftFailure = null;
    testClient.acceptBeforeGenerationFailure = false;
    testClient.currentDraft = null;
    testClient.beginRequests.clear();
    testClient.generationRequests.clear();
    testClient.questionRequests.clear();
    testClient.pendingQuestions = null;
    testClient.questionFailure = null;
    testClient.questionResponse = const [];
    testClient.manifests.clear();
  });

  Future<void> home(
    WidgetTester tester, {
    Future<void> Function(int appId, {int? recordId})? onOpenApp,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(onOpenApp: onOpenApp)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('configured AI keeps creation controls without a Live AI label', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    await home(tester);
    expect(find.text('Live AI'), findsNothing);
    expect(find.textContaining('Template mode'), findsNothing);
    expect(find.text('What would you like to build?'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-idea')), findsOneWidget);
    expect(find.text('Create app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconfigured AI still explains template mode', (tester) async {
    await home(tester);
    expect(
      find.textContaining('Template mode — AI provider not configured'),
      findsOneWidget,
    );
    expect(find.text('Live AI'), findsNothing);
    expect(find.text('Browse templates'), findsOneWidget);
    await tester.tap(find.text('Browse templates'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('A template creates an empty app.'),
      findsOneWidget,
    );
    expect(testClient.methods, isNot(contains('builder.begin')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty prompts cannot begin a draft and starters remain editable',
    (
      tester,
    ) async {
      testClient.aiAvailable = true;
      await home(tester);
      final create = find.byKey(const ValueKey('create-app'));
      final idea = find.byKey(const ValueKey('app-idea'));
      expect(tester.widget<FilledButton>(create).onPressed, isNull);
      await tester.enterText(idea, '   \n  ');
      await tester.pump();
      expect(tester.widget<FilledButton>(create).onPressed, isNull);
      expect(testClient.methods, isNot(contains('builder.begin')));

      await tester.tap(find.text('Notes'));
      await tester.pump();
      final input = tester.widget<TextField>(idea);
      expect(input.controller!.text, contains('notes app'));
      expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
      await tester.enterText(idea, 'My own reading club idea');
      expect(input.controller!.text, 'My own reading club idea');
      expect(testClient.methods, isNot(contains('builder.begin')));
    },
  );

  testWidgets('all four examples only fill the editable composer', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    await home(tester);
    final idea = find.byKey(const ValueKey('app-idea'));
    for (final example in const {
      'Notes': 'personal notes app',
      'Reminders': 'separate optional reminder time',
      'Calendar': 'selected-day agenda',
      'Clock & focus': '25-minute countdown',
    }.entries) {
      await tester.ensureVisible(find.widgetWithText(ActionChip, example.key));
      await tester.tap(find.widgetWithText(ActionChip, example.key));
      await tester.pump();
      expect(
        tester.widget<TextField>(idea).controller!.text,
        contains(example.value),
      );
    }
    expect(testClient.beginRequests, isEmpty);
    expect(testClient.generationRequests, isEmpty);
    expect(testClient.questionRequests, isEmpty);
  });

  testWidgets('creation guards repeat taps and keeps the idea after failure', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    testClient.pendingCreation = Completer<void>();
    testClient.creationFailure = const ServerpodClientNetworkException(
      'offline',
    );
    await home(tester);
    final idea = find.byKey(const ValueKey('app-idea'));
    final create = find.byKey(const ValueKey('create-app'));
    await tester.enterText(idea, 'A shared reading journal');
    await tester.pump();
    // A second invocation before Flutter has rebuilt must also be ignored.
    final submit = tester.widget<FilledButton>(create).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(testClient.methods.where((m) => m == 'builder.begin'), hasLength(1));
    expect(find.text('Creating your app…'), findsOneWidget);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    testClient.pendingCreation!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(idea).controller!.text,
      'A shared reading journal',
    );
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);

    // An explicit retry can begin again after the failed request settles.
    testClient.pendingCreation = null;
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(testClient.methods.where((m) => m == 'builder.begin'), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('creation carries the submitted idea into the builder', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    await home(tester);
    await tester.enterText(
      find.byKey(const ValueKey('app-idea')),
      '  A planner for our family  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-app')));
    await tester.pumpAndSettle();
    expect(testClient.generationRequests, hasLength(1));
    expect(
      testClient.generationRequests.single['request'],
      'A planner for our family',
    );
    expect(testClient.generationRequests.single['startFromScratch'], isTrue);
    final builder = tester.widget<BuilderScreen>(find.byType(BuilderScreen));
    expect(builder.initialPrompt, 'A planner for our family');
    expect(builder.startFromScratch, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('guidance fills an editable idea without creating an app', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    testClient.questionResponse = [
      question('Who is this for?', [
        'Neighborhood readers',
        'Friends',
        'A school club',
      ]),
      question('What should they record?', [
        'Books',
        'Meeting dates',
        'Member notes',
      ]),
    ];
    await home(tester);
    final idea = find.byKey(const ValueKey('app-idea'));
    await tester.enterText(idea, 'A book club app');
    await tester.pump();
    expect(testClient.questionRequests, isEmpty);
    expect(find.byKey(const ValueKey('shape-idea')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    expect(testClient.questionRequests, hasLength(1));
    expect(testClient.questionRequests.single['idea'], 'A book club app');
    expect(testClient.questionRequests.single['workspaceId'], 1);
    expect(testClient.questionRequests.single['draftId'], isNull);
    expect(testClient.beginRequests, isEmpty);
    expect(testClient.generationRequests, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('create-app')))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const ValueKey('guidance-answer-0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('guidance-option-0-0')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('guidance-use')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guidance-use')));
    await tester.pumpAndSettle();
    final combined = tester.widget<TextField>(idea).controller!.text;
    expect(combined, contains('A book club app'));
    expect(combined, contains('Neighborhood readers'));
    expect(testClient.beginRequests, isEmpty);
    await tester.enterText(idea, '$combined\nWe meet monthly.');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-app')));
    await tester.pumpAndSettle();
    expect(testClient.questionRequests, hasLength(1));
    expect(
      testClient.generationRequests.single['request'],
      contains('We meet monthly.'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('clear ideas create directly and quota failure offers a choice', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    await home(tester);
    final idea = find.byKey(const ValueKey('app-idea'));
    await tester.enterText(idea, 'Build a planner with tasks and due dates');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-app')));
    await tester.pumpAndSettle();
    expect(testClient.questionRequests, isEmpty);
    expect(testClient.beginRequests, hasLength(1));
    expect(testClient.generationRequests, hasLength(1));

    await tester.pageBack();
    await tester.pumpAndSettle();
    testClient.questionFailure = NestError(
      category: 'quotaExceeded',
      message: 'Guidance quota reached.',
    );
    await tester.enterText(idea, 'A club app');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    expect(find.text('Built-in questions'), findsOneWidget);
    expect(testClient.beginRequests, hasLength(1));
    expect(testClient.generationRequests, hasLength(1));
    await tester.ensureVisible(find.byKey(const ValueKey('guidance-continue')));
    await tester.tap(find.byKey(const ValueKey('guidance-continue')));
    await tester.pumpAndSettle();
    expect(testClient.questionRequests, hasLength(1));
    expect(testClient.beginRequests, hasLength(2));
    expect(testClient.generationRequests.last['request'], 'A club app');
  });

  testWidgets('malformed choices fall back before any app is created', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    testClient.questionResponse = [
      question('Who will join?', ['Friends', 'friends', 'Neighbors']),
      question('What will they do?', ['Plan', 'Share', 'Track']),
    ];
    await home(tester);
    await tester.enterText(
      find.byKey(const ValueKey('app-idea')),
      'A club app',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    expect(find.text('Built-in questions'), findsOneWidget);
    expect(find.byKey(const ValueKey('guidance-option-0-0')), findsOneWidget);
    expect(testClient.beginRequests, isEmpty);
    expect(testClient.generationRequests, isEmpty);
  });

  testWidgets('a different idea can request fresh optional guidance', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    testClient.questionResponse = [
      question('Who uses it?', ['Neighbors', 'Friends', 'Colleagues']),
      question('What should it do?', [
        'Plan events',
        'Share notes',
        'Track tasks',
      ]),
    ];
    await home(tester);
    final idea = find.byKey(const ValueKey('app-idea'));
    await tester.enterText(idea, 'A club app');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guidance-option-0-0')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('guidance-use')));
    await tester.tap(find.byKey(const ValueKey('guidance-use')));
    await tester.pumpAndSettle();

    await tester.enterText(idea, 'A different app for gardeners');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    expect(testClient.questionRequests, hasLength(2));
    expect(testClient.beginRequests, isEmpty);
    expect(find.text('A few details would help'), findsOneWidget);
  });

  testWidgets('an outdated guidance result never creates a draft', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    testClient.pendingQuestions = Completer<List<GuidanceQuestion>>();
    await home(tester);
    final idea = find.byKey(const ValueKey('app-idea'));
    await tester.enterText(idea, 'A club app');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pump();
    tester.widget<TextField>(idea).controller!.text = 'A different app';
    testClient.pendingQuestions!.complete([
      question('Who joins?', ['Neighbors', 'Friends', 'Colleagues']),
      question('What happens?', ['Events', 'Chats', 'Tasks']),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('A few details would help'), findsNothing);
    expect(testClient.beginRequests, isEmpty);
    expect(testClient.generationRequests, isEmpty);
    expect(tester.widget<TextField>(idea).controller!.text, 'A different app');
  });

  testWidgets('access errors do not offer a guidance bypass', (tester) async {
    testClient.aiAvailable = true;
    testClient.questionFailure = NestError(
      category: 'forbidden',
      message: 'Workspace access changed.',
    );
    await home(tester);
    await tester.enterText(
      find.byKey(const ValueKey('app-idea')),
      'A club app',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    expect(find.text('Built-in questions'), findsNothing);
    expect(find.byKey(const ValueKey('guidance-continue')), findsNothing);
    expect(testClient.beginRequests, isEmpty);
    expect(testClient.generationRequests, isEmpty);
  });

  testWidgets('a long generation request bypasses guidance', (tester) async {
    testClient.aiAvailable = true;
    await home(tester);
    final request =
        'Build a planner with tasks, due dates, and notes. '
        '${List.filled(125, 'Detailed workflow. ').join()}';
    await tester.enterText(find.byKey(const ValueKey('app-idea')), request);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-app')));
    await tester.pumpAndSettle();
    expect(testClient.questionRequests, isEmpty);
    expect(testClient.generationRequests.single['request'], request.trim());
  });

  testWidgets('rejected generation reuses the draft with the edited idea', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    testClient.generationFailure = NestError(
      category: 'quotaExceeded',
      message: 'One generation at a time.',
    );
    await home(tester);
    final idea = find.byKey(const ValueKey('app-idea'));
    final create = find.byKey(const ValueKey('create-app'));
    await tester.enterText(idea, 'A reading journal');
    await tester.pump();
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.byType(BuilderScreen), findsNothing);
    expect(testClient.beginRequests, hasLength(1));

    await tester.enterText(idea, 'A reading journal with ratings');
    testClient.generationFailure = null;
    await tester.pump();
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(testClient.beginRequests, hasLength(1));
    expect(testClient.methods.where((m) => m == 'builder.get'), hasLength(1));
    expect(testClient.generationRequests, hasLength(2));
    expect(testClient.generationRequests.last['draftId'], 1);
    expect(
      testClient.generationRequests.last['request'],
      'A reading journal with ratings',
    );
    expect(
      tester.widget<BuilderScreen>(find.byType(BuilderScreen)).initialPrompt,
      'A reading journal with ratings',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'lost generation response recovers the accepted original request',
    (
      tester,
    ) async {
      testClient.aiAvailable = true;
      testClient.generationFailure = const ServerpodClientNetworkException(
        'response lost',
      );
      testClient.acceptBeforeGenerationFailure = true;
      await home(tester);
      final idea = find.byKey(const ValueKey('app-idea'));
      final create = find.byKey(const ValueKey('create-app'));
      await tester.enterText(idea, 'A reading journal');
      await tester.pump();
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.byType(BuilderScreen), findsNothing);

      await tester.enterText(idea, 'A newer idea I have not submitted');
      await tester.pump();
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(testClient.beginRequests, hasLength(1));
      expect(testClient.generationRequests, hasLength(1));
      expect(testClient.methods.where((m) => m == 'builder.get'), hasLength(1));
      final builder = tester.widget<BuilderScreen>(find.byType(BuilderScreen));
      expect(builder.initialPrompt, 'A reading journal');
      expect(builder.initial.jobId, 42);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(idea).controller!.text,
        'A newer idea I have not submitted',
      );
      // Opening the recovered builder completes recovery. A later creation is new.
      testClient.generationFailure = null;
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(testClient.beginRequests, hasLength(2));
      expect(testClient.generationRequests, hasLength(2));
      expect(
        testClient.generationRequests.last['request'],
        'A newer idea I have not submitted',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  Future<void> leaveCreation(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('app-idea')),
      'A reading journal',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('create-app')));
    await tester.tap(find.byKey(const ValueKey('create-app')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('resume-build-1')));
  }

  testWidgets('resume reads the latest failed build without repeating writes', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    await home(tester, size: const Size(390, 844));
    await leaveCreation(tester);
    expect(find.text('Resume build'), findsOneWidget);
    testClient.currentDraft = testClient.currentDraft!.copyWith(
      stage: 'failed',
      mutation: 2,
      jobId: 43,
      candidateReady: false,
      diagnostics: ['The generated definition could not be validated.'],
    );

    await tester.tap(find.byKey(const ValueKey('resume-build-1')));
    await tester.pumpAndSettle();
    final builder = tester.widget<BuilderScreen>(find.byType(BuilderScreen));
    expect(builder.initial.stage, 'failed');
    expect(builder.initial.jobId, 43);
    expect(builder.initial.mutation, 2);
    expect(find.text('Try again'), findsOneWidget);
    expect(testClient.methods.where((m) => m == 'builder.get'), hasLength(1));
    expect(testClient.beginRequests, hasLength(1));
    expect(testClient.generationRequests, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resume retains the build after a connection failure', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    await home(tester);
    await leaveCreation(tester);
    testClient.draftFailure = const ServerpodClientNetworkException('offline');
    await tester.tap(find.byKey(const ValueKey('resume-build-1')));
    await tester.pumpAndSettle();
    expect(find.byType(BuilderScreen), findsNothing);
    expect(find.text('Resume build'), findsOneWidget);

    testClient.draftFailure = null;
    await tester.tap(find.byKey(const ValueKey('resume-build-1')));
    await tester.pumpAndSettle();
    expect(find.byType(BuilderScreen), findsOneWidget);
    expect(testClient.beginRequests, hasLength(1));
    expect(testClient.generationRequests, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resume removes a replaced build with an explanation', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    await home(tester);
    await leaveCreation(tester);
    testClient.currentDraft = testClient.currentDraft!.copyWith(stage: 'stale');
    await tester.tap(find.byKey(const ValueKey('resume-build-1')));
    await tester.pumpAndSettle();
    expect(find.byType(BuilderScreen), findsNothing);
    expect(find.text('Resume build'), findsNothing);
    expect(find.textContaining('This build was replaced.'), findsOneWidget);
    expect(testClient.beginRequests, hasLength(1));
    expect(testClient.generationRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume opens an already published app and removes its handle', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    final opened = <int>[];
    await home(
      tester,
      onOpenApp: (appId, {recordId}) async => opened.add(appId),
    );
    await leaveCreation(tester);
    testClient.currentDraft = testClient.currentDraft!.copyWith(
      publishedVersionId: 12,
    );
    await tester.tap(find.byKey(const ValueKey('resume-build-1')));
    await tester.pumpAndSettle();
    expect(opened, [1]);
    expect(find.byType(BuilderScreen), findsNothing);
    expect(find.text('Resume build'), findsNothing);
    expect(testClient.beginRequests, hasLength(1));
    expect(testClient.generationRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume clears inaccessible work without opening or writing', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    await home(tester);
    await leaveCreation(tester);
    testClient.draftFailure = NestError(
      category: 'forbidden',
      message: 'Draft access changed.',
    );
    await tester.tap(find.byKey(const ValueKey('resume-build-1')));
    await tester.pumpAndSettle();
    expect(find.byType(BuilderScreen), findsNothing);
    expect(find.text('Resume build'), findsNothing);
    expect(find.text('Draft access changed.'), findsOneWidget);
    expect(testClient.beginRequests, hasLength(1));
    expect(testClient.generationRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('publishing from a resumed build removes its home shortcut', (
    tester,
  ) async {
    testClient.aiAvailable = true;
    final opened = <int>[];
    await home(
      tester,
      onOpenApp: (appId, {recordId}) async => opened.add(appId),
    );
    await leaveCreation(tester);
    await tester.tap(find.byKey(const ValueKey('resume-build-1')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(BuilderScreen))).pop<int>(1);
    await tester.pumpAndSettle();
    expect(opened, [1]);
    expect(find.text('Resume build'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prompt entry fits a phone with larger text', (tester) async {
    testClient.aiAvailable = true;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What would you like to build?'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-idea')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned app cards stretch to the tallest card in each row', (
    tester,
  ) async {
    final spec = dailyPlannerTemplate().canonical;
    for (final (index, name) in [
      'Club Activities',
      'Trip Kit',
      'Daily Planner · Live check',
      'Plant Corner',
    ].indexed) {
      testClient.manifests.add(
        AppManifest(
          appId: index + 1,
          versionId: index + 1,
          workspaceId: 1,
          name: name,
          specJson: spec,
          role: 'owner',
          archived: false,
          pinned: true,
          recordCount: 2,
          availablePlaces: 0,
        ),
      );
    }
    await home(tester);

    Rect cardBounds(String name) => tester.getRect(
      find.ancestor(of: find.text(name), matching: find.byType(Card)),
    );
    final first = cardBounds('Club Activities');
    final second = cardBounds('Trip Kit');
    final long = cardBounds('Daily Planner · Live check');
    final nextRow = cardBounds('Plant Corner');
    expect(first.top, long.top);
    expect(second.top, long.top);
    expect(first.bottom, long.bottom);
    expect(second.bottom, long.bottom);
    expect(nextRow.top, greaterThan(long.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'network failure retries reads and replaces error with workspace',
    (
      tester,
    ) async {
      testClient.failure = const ServerpodClientNetworkException(
        'Unknown server response code. private diagnostic',
      );
      await home(tester);
      expect(find.text('Can’t connect to AppNest'), findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      expect(find.textContaining('Unknown server response'), findsNothing);

      testClient.failure = null;
      testClient.pending = Completer<void>();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text('Connecting to AppNest…'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(testClient.workspaceRequests, 2);
      testClient.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Recovered workspace'), findsOneWidget);
      expect(find.text('What would you like to build?'), findsOneWidget);
      expect(find.byType(HomeLoadFailure), findsNothing);
      expect(testClient.methods, [
        'apps.workspaces',
        'apps.workspaces',
        'builder.platform',
        'apps.list',
        'apps.templates',
        'runtime.inbox',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed launcher recovers when returning to the app', (
    tester,
  ) async {
    testClient.failure = const ServerpodClientNetworkException('offline');
    await home(tester);
    testClient.failure = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(testClient.workspaceRequests, 2);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(HomeLoadFailure), findsNothing);
    expect(find.text('Recovered workspace'), findsOneWidget);
    expect(testClient.workspaceRequests, 2);
  });

  testWidgets('disposing during a retry ignores its late response', (
    tester,
  ) async {
    testClient.failure = const ServerpodClientNetworkException('offline');
    await home(tester);
    testClient.failure = null;
    testClient.pending = Completer<void>();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    testClient.pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(testClient.methods, isNot(contains('apps.list')));
  });

  testWidgets('permission errors are not mislabeled as connection failures', (
    tester,
  ) async {
    testClient.failure = NestError(
      category: 'forbidden',
      message: 'Private server detail',
    );
    await home(tester);
    expect(find.text('Workspace access changed'), findsOneWidget);
    expect(find.text('Can’t connect to AppNest'), findsNothing);
    expect(find.textContaining('Private server detail'), findsNothing);
  });

  testWidgets('unauthorized and unknown failures have safe recovery copy', (
    tester,
  ) async {
    testClient.failure = ServerpodClientUnauthorized();
    await home(tester);
    expect(find.text('Please sign in again'), findsOneWidget);
    testClient.failure = StateError('Private implementation detail');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t load your workspace'), findsOneWidget);
    expect(find.textContaining('Private implementation'), findsNothing);
  });

  testWidgets('error and keyboard retry fit a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: HomeLoadFailure(
              error: TimeoutException('private URL'),
              onRetry: () => retries++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Can’t connect to AppNest'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Focus the sole action and activate it through the keyboard.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(retries, 1);
  });
}
