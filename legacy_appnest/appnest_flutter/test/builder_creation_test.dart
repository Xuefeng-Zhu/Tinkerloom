import 'dart:async';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/builder/builder_screen.dart';
import 'package:appnest_flutter/features/builder/builder_chat.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic authenticated transport. The production builder uses the generated
/// Serverpod client and its normal authentication checks.
class CreationClient extends Client {
  CreationClient() : super('http://localhost:8180/');

  final generations = <Map<String, dynamic>>[];
  final gets = <int>[];
  final abandoned = <Map<String, dynamic>>[];
  final patches = <Map<String, dynamic>>[];
  Object? getFailure;
  late BuilderSnapshot current;
  Completer<BuilderSnapshot>? pendingGet;
  Completer<BuilderSnapshot>? pendingGeneration;
  Object? generationFailure;
  Object? platformFailure;
  int platformRequests = 0;
  bool aiAvailable = true;
  final questionRequests = <Map<String, dynamic>>[];
  Completer<List<GuidanceQuestion>>? pendingQuestions;
  Object? questionFailure;
  List<GuidanceQuestion> questionResponse = const [];

  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    expectSync(authenticated, isTrue);
    Object? result;
    switch ('$endpoint.$method') {
      case 'builder.platform':
        platformRequests++;
        if (platformFailure != null) throw platformFailure!;
        result = PlatformInfo(
          aiAvailable: aiAvailable,
          aiMode: aiAvailable ? 'Live AI' : 'Template mode',
          development: true,
          actorId: 'synthetic-builder-test',
        );
      case 'builder.get':
        gets.add(args['draftId'] as int);
        if (getFailure != null) throw getFailure!;
        result = pendingGet == null ? current : await pendingGet!.future;
      case 'builder.generate':
        generations.add(Map<String, dynamic>.from(args));
        if (generationFailure != null) throw generationFailure!;
        result = pendingGeneration == null
            ? current
            : await pendingGeneration!.future;
      case 'builder.abandonFailedEdit':
        abandoned.add(Map<String, dynamic>.from(args));
        result = current.copyWith(
          stage: 'preview ready',
          mutation: current.mutation + 1,
          jobId: null,
        );
      case 'builder.patch':
        patches.add(Map<String, dynamic>.from(args));
        result = current;
      case 'builder.suggestQuestions':
        questionRequests.add(Map<String, dynamic>.from(args));
        if (questionFailure != null) throw questionFailure!;
        result = pendingQuestions == null
            ? questionResponse
            : await pendingQuestions!.future;
      default:
        throw StateError('Unexpected endpoint: $endpoint.$method');
    }
    return result as T;
  }
}

BuilderSnapshot draft({
  AppSpec? spec,
  String stage = 'preview ready',
  int mutation = 0,
  int? jobId,
  List<String> diagnostics = const [],
  bool? candidateReady,
  String? latestRequest,
}) {
  final candidate = spec ?? starterTemplates()['volunteer']!;
  return BuilderSnapshot(
    appId: 1,
    draftId: 9,
    jobId: jobId,
    mutation: mutation,
    stage: stage,
    candidateJson: candidate.canonical,
    candidateHash: candidate.hash,
    diagnostics: diagnostics,
    changes: candidate.diff(null),
    enabledRuleIds: [],
    candidateReady:
        candidateReady ?? (stage == 'preview ready' || jobId == null),
    latestRequest: latestRequest,
  );
}

void main() {
  GuidanceQuestion question(String text, List<String> options) =>
      GuidanceQuestion(question: text, options: options);

  final client = CreationClient();
  setUpAll(() => transport.client = client);
  tearDownAll(client.close);
  setUp(() {
    client.generations.clear();
    client.gets.clear();
    client.abandoned.clear();
    client.patches.clear();
    client.getFailure = null;
    client.current = draft();
    client.pendingGet = null;
    client.pendingGeneration = null;
    client.generationFailure = null;
    client.platformFailure = null;
    client.platformRequests = 0;
    client.aiAvailable = true;
    client.questionRequests.clear();
    client.pendingQuestions = null;
    client.questionFailure = null;
    client.questionResponse = const [];
  });

  Future<void> showBuilder(
    WidgetTester tester, {
    required BuilderSnapshot initial,
    String? initialPrompt,
    bool startFromScratch = false,
    Size size = const Size(1440, 1000),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: BuilderScreen(
          initial: initial,
          initialPrompt: initialPrompt,
          startFromScratch: startFromScratch,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> closeBuilder(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Finder composer() => find.byKey(const ValueKey('builder-prompt'));

  testWidgets('send creates directly without optional guidance', (
    tester,
  ) async {
    await showBuilder(tester, initial: draft());
    await tester.enterText(composer(), 'Make my notes blue');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(client.generations, hasLength(1));
    expect(client.questionRequests, isEmpty);
    await closeBuilder(tester);
  });

  testWidgets('rapid Use app taps open one review', (tester) async {
    await showBuilder(tester, initial: draft());
    final submit = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Use app'),
        )
        .onPressed!;
    submit();
    submit();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Back to preview'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Use app'))
          .onPressed,
      isNotNull,
    );
    await closeBuilder(tester);
  });

  testWidgets('a lost accepted response recovers the existing job', (
    tester,
  ) async {
    await showBuilder(tester, initial: draft());
    const request = 'Make my notes blue';
    client.current = draft(
      stage: 'queued',
      mutation: 1,
      jobId: 7,
      candidateReady: true,
      latestRequest: request,
    );
    client.generationFailure = const ServerpodClientNetworkException(
      'response lost',
    );
    await tester.enterText(composer(), request);
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(client.generations, hasLength(1));
    expect(client.gets, [9]);
    expect(tester.widget<TextField>(composer()).controller!.text, isEmpty);
    expect(find.byType(MiniAppRuntime), findsOneWidget);
    await closeBuilder(tester);
  });

  testWidgets('an uncertain submission reads before any retry', (tester) async {
    await showBuilder(tester, initial: draft());
    const request = 'Make my notes blue';
    client.generationFailure = const ServerpodClientNetworkException('offline');
    client.getFailure = const ServerpodClientNetworkException('offline');
    await tester.enterText(composer(), request);
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(client.generations, hasLength(1));
    client.getFailure = null;
    client.current = draft(
      stage: 'queued',
      mutation: 1,
      jobId: 7,
      candidateReady: true,
      latestRequest: request,
    );
    await tester.enterText(composer(), 'A different unsent change');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(client.generations, hasLength(1));
    expect(client.gets, [9, 9]);
    expect(
      tester.widget<TextField>(composer()).controller!.text,
      'A different unsent change',
    );
    await closeBuilder(tester);
  });

  testWidgets('a lost response recovers an already completed follow-up', (
    tester,
  ) async {
    final before = dailyPlannerTemplate();
    await showBuilder(tester, initial: draft(spec: before));
    const request = 'Use an editorial style';
    final after = before.patch({
      'type': 'SetAppearance',
      'appearance': {'style': 'editorial'},
    }, () => 'unused');
    client.current = draft(
      spec: after,
      mutation: 1,
      jobId: 7,
      latestRequest: request,
    );
    client.generationFailure = const ServerpodClientNetworkException(
      'response lost',
    );
    await tester.enterText(composer(), request);
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(client.generations, hasLength(1));
    expect(client.gets, [9]);
    expect(tester.widget<TextField>(composer()).controller!.text, isEmpty);
    expect(find.text(request), findsOneWidget);
    expect(
      find.text(
        'Your preview is ready. Try it out, or tell me what to adjust next.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<MiniAppRuntime>(find.byType(MiniAppRuntime))
          .adapter
          .spec
          .hash,
      after.hash,
    );
    expect(find.text('Refresh connection'), findsNothing);
    await closeBuilder(tester);
  });

  testWidgets(
    'later recovery acknowledges completion once and preserves an unsent change',
    (tester) async {
      final before = dailyPlannerTemplate();
      await showBuilder(tester, initial: draft(spec: before));
      const request = 'Use an editorial style';
      const unsent = 'Rename the calendar to Team schedule';
      const acknowledgement =
          'Your preview is ready. Try it out, or tell me what to adjust next.';
      client.generationFailure = const ServerpodClientNetworkException(
        'response lost',
      );
      client.getFailure = const ServerpodClientNetworkException(
        'still offline',
      );
      await tester.enterText(composer(), request);
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(client.generations, hasLength(1));
      expect(client.gets, [9]);
      expect(tester.widget<TextField>(composer()).controller!.text, request);

      final after = before.patch({
        'type': 'SetAppearance',
        'appearance': {'style': 'editorial'},
      }, () => 'unused');
      client.getFailure = null;
      client.current = draft(
        spec: after,
        mutation: 1,
        jobId: 7,
        latestRequest: request,
      );
      await tester.enterText(composer(), unsent);
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();

      final state = tester.state<BuilderScreenState>(
        find.byType(BuilderScreen),
      );
      expect(client.generations, hasLength(1));
      expect(client.gets, [9, 9]);
      expect(tester.widget<TextField>(composer()).controller!.text, unsent);
      expect(state.uncertainGeneration, isNull);
      expect(state.draft.candidateHash, after.hash);
      expect(state.conversation.map((message) => message.text), [
        'Your app is ready to shape. Try the preview, then tell me what you would like to change.',
        request,
        acknowledgement,
      ]);
      expect(state.conversation[1].fromUser, isTrue);
      expect(state.conversation[2].fromUser, isFalse);

      await state.poll();
      await tester.pumpAndSettle();
      expect(
        state.conversation.where((message) => message.text == acknowledgement),
        hasLength(1),
      );
      expect(client.generations, hasLength(1));
      expect(tester.widget<TextField>(composer()).controller!.text, unsent);
      expect(find.text('Refresh connection'), findsNothing);
      await closeBuilder(tester);
    },
  );

  for (final unsent in [null, 'Rename the calendar to Team schedule']) {
    testWidgets(
      'Refresh connection acknowledges a completed uncertain request and ${unsent == null ? 'clears the original prompt' : 'preserves a different prompt'}',
      (tester) async {
        final before = dailyPlannerTemplate();
        await showBuilder(tester, initial: draft(spec: before));
        const request = 'Use an editorial style';
        const acknowledgement =
            'Your preview is ready. Try it out, or tell me what to adjust next.';
        client.generationFailure = const ServerpodClientNetworkException(
          'response lost',
        );
        client.getFailure = const ServerpodClientNetworkException(
          'still offline',
        );
        await tester.enterText(composer(), request);
        await tester.pump();
        await tester.tap(find.byTooltip('Send message'));
        await tester.pumpAndSettle();
        expect(client.generations, hasLength(1));
        expect(client.gets, [9]);
        expect(find.text('Refresh connection'), findsOneWidget);

        final after = before.patch({
          'type': 'SetAppearance',
          'appearance': {'style': 'editorial'},
        }, () => 'unused');
        client.getFailure = null;
        client.current = draft(
          spec: after,
          mutation: 1,
          jobId: 7,
          latestRequest: request,
        );
        if (unsent != null) {
          await tester.enterText(composer(), unsent);
          await tester.pump();
        }
        await tester.tap(find.text('Refresh connection'));
        await tester.pumpAndSettle();

        final state = tester.state<BuilderScreenState>(
          find.byType(BuilderScreen),
        );
        expect(client.generations, hasLength(1));
        expect(client.gets, [9, 9]);
        expect(client.platformRequests, 2);
        expect(state.uncertainGeneration, isNull);
        expect(state.draft.candidateHash, after.hash);
        expect(state.conversation.map((message) => message.text), [
          'Your app is ready to shape. Try the preview, then tell me what you would like to change.',
          request,
          acknowledgement,
        ]);
        expect(state.conversation[1].fromUser, isTrue);
        expect(state.conversation[2].fromUser, isFalse);
        expect(
          tester.widget<TextField>(composer()).controller!.text,
          unsent ?? '',
        );
        expect(find.text('Refresh connection'), findsNothing);

        await state.poll();
        await tester.pumpAndSettle();
        expect(
          state.conversation.where(
            (message) => message.text == acknowledgement,
          ),
          hasLength(1),
        );
        expect(client.generations, hasLength(1));
        expect(
          tester.widget<TextField>(composer()).controller!.text,
          unsent ?? '',
        );
        await closeBuilder(tester);
      },
    );
  }

  testWidgets('Refresh connection accepts a queued uncertain request once', (
    tester,
  ) async {
    final before = dailyPlannerTemplate();
    await showBuilder(tester, initial: draft(spec: before));
    const request = 'Use an editorial style';
    const acknowledgement =
        'Your preview is ready. Try it out, or tell me what to adjust next.';
    client.generationFailure = const ServerpodClientNetworkException(
      'response lost',
    );
    client.getFailure = const ServerpodClientNetworkException('still offline');
    await tester.enterText(composer(), request);
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh connection'), findsOneWidget);

    client.getFailure = null;
    client.current = draft(
      spec: before,
      stage: 'queued',
      mutation: 1,
      jobId: 7,
      candidateReady: true,
      latestRequest: request,
    );
    await tester.tap(find.text('Refresh connection'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final state = tester.state<BuilderScreenState>(find.byType(BuilderScreen));
    expect(state.uncertainGeneration, isNull);
    expect(state.draft.stage, 'queued');
    expect(tester.widget<TextField>(composer()).controller!.text, isEmpty);
    expect(
      state.conversation
          .where((message) => message.fromUser)
          .map(
            (message) => message.text,
          ),
      [request],
    );
    expect(
      state.conversation.where((message) => message.text == acknowledgement),
      isEmpty,
    );

    final after = before.patch({
      'type': 'SetAppearance',
      'appearance': {'style': 'editorial'},
    }, () => 'unused');
    client.current = draft(
      spec: after,
      mutation: 1,
      jobId: 7,
      latestRequest: request,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(state.draft.candidateHash, after.hash);
    expect(
      state.conversation.where((message) => message.text == acknowledgement),
      hasLength(1),
    );
    await state.poll();
    await tester.pumpAndSettle();
    expect(
      state.conversation.where((message) => message.text == acknowledgement),
      hasLength(1),
    );
    expect(client.generations, hasLength(1));
    expect(tester.widget<TextField>(composer()).controller!.text, isEmpty);
    expect(find.text('Refresh connection'), findsNothing);
    await closeBuilder(tester);
  });

  testWidgets('a stale failed poll cannot replace an accepted follow-up', (
    tester,
  ) async {
    await showBuilder(tester, initial: draft());
    final pendingGet = Completer<BuilderSnapshot>();
    client.pendingGet = pendingGet;
    final state = tester.state<BuilderScreenState>(find.byType(BuilderScreen));
    final oldPoll = state.poll();
    await tester.pump();
    expect(client.gets, [9]);

    const request = 'Use a calmer style';
    client.current = draft(
      stage: 'queued',
      mutation: 1,
      jobId: 7,
      candidateReady: true,
      latestRequest: request,
    );
    await tester.enterText(composer(), request);
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(client.generations, hasLength(1));
    expect(state.draft.mutation, 1);

    pendingGet.completeError(
      const ServerpodClientNetworkException('obsolete poll failed'),
    );
    await oldPoll;
    await tester.pump();
    expect(state.error, isNull);
    expect(state.draft.stage, 'queued');
    expect(find.text('Refresh connection'), findsNothing);
    expect(tester.widget<TextField>(composer()).controller!.text, isEmpty);
    await closeBuilder(tester);
  });

  testWidgets(
    'reopening a failed edit preserves and restores its last preview',
    (tester) async {
      client.current = draft(
        stage: 'failed',
        mutation: 4,
        jobId: 10,
        candidateReady: true,
        latestRequest: 'Make the colors warmer',
      );
      await showBuilder(
        tester,
        initial: client.current,
        startFromScratch: true,
      );
      expect(find.byType(MiniAppRuntime), findsOneWidget);
      expect(find.text('Make the colors warmer'), findsOneWidget);
      await tester.ensureVisible(find.text('Keep previous preview'));
      await tester.tap(find.text('Keep previous preview'));
      await tester.pumpAndSettle();
      expect(client.abandoned.single, {
        'draftId': 9,
        'mutation': 4,
        'jobId': 10,
      });
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Use app'))
            .onPressed,
        isNotNull,
      );
      await closeBuilder(tester);
    },
  );

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('Customize exposes four categories at ${size.width}', (
      tester,
    ) async {
      await showBuilder(tester, initial: draft(), size: size);
      await tester.tap(find.byKey(const ValueKey('customize-app')));
      await tester.pumpAndSettle();
      expect(find.text('Content'), findsOneWidget);
      expect(find.text('Layout'), findsOneWidget);
      expect(find.text('Behavior'), findsOneWidget);
      expect(find.text('Appearance'), findsWidgets);
      expect(tester.takeException(), isNull);
      await closeBuilder(tester);
    });
  }

  testWidgets('pure utility Content opens without creating dummy collections', (
    tester,
  ) async {
    await showBuilder(tester, initial: draft(spec: focusTemplate()));
    await tester.tap(find.byKey(const ValueKey('customize-app')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Content'));
    await tester.pumpAndSettle();
    expect(find.text('Make a small edit'), findsOneWidget);
    expect(find.text('Rename app or field'), findsOneWidget);
    expect(find.text('Add a field'), findsNothing);
    expect(tester.takeException(), isNull);
    await closeBuilder(tester);
  });

  testWidgets('changed reminders need approval again in the single review', (
    tester,
  ) async {
    final spec = dailyPlannerTemplate();
    final original = spec.automationRequests.single;
    await showBuilder(
      tester,
      initial: draft(spec: spec).copyWith(enabledRuleIds: [original.id]),
    );
    final rule = original.toJson()..remove('id');
    (rule['trigger'] as Map)['offsetSeconds'] = 900;
    final changed = spec.patch({
      'type': 'UpdateReminder',
      'ruleId': original.id,
      'rule': rule,
    }, () => throw StateError('Must retain identity'));
    final dynamic state = tester.state(find.byType(BuilderScreen));
    state.update(
      draft(spec: changed, mutation: 1).copyWith(enabledRuleIds: [original.id]),
    );
    await tester.pump();
    await tester.tap(find.text('Use app'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(find.text('Review & publish'), findsNothing);
    await closeBuilder(tester);
  });

  testWidgets('builder guidance prepares but does not send a change', (
    tester,
  ) async {
    client.questionResponse = [
      question('What should change?', [
        'Show fewer fields',
        'Simplify navigation',
        'Update styling',
      ]),
      question('Who will use it?', [
        'Neighbors',
        'Club members',
        'Everyone',
      ]),
    ];
    await showBuilder(tester, initial: draft());
    await tester.enterText(composer(), 'Make it easier for neighbors');
    await tester.pump();
    expect(client.questionRequests, isEmpty);
    expect(find.byKey(const ValueKey('shape-idea')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    expect(client.questionRequests, hasLength(1));
    expect(client.questionRequests.single['draftId'], 9);
    expect(client.questionRequests.single['workspaceId'], isNull);
    expect(client.generations, isEmpty);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Send message'),
              matching: find.byType(IconButton),
            ),
          )
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
    final prepared = tester.widget<TextField>(composer()).controller!.text;
    expect(prepared, contains('Show fewer fields'));
    expect(client.generations, isEmpty);
    await tester.enterText(composer(), '$prepared\nKeep the calendar.');
    await tester.pump();
    client.current = draft(stage: 'queued', mutation: 1, jobId: 7);
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(client.questionRequests, hasLength(1));
    expect(
      client.generations.single['request'],
      contains('Keep the calendar.'),
    );
    await closeBuilder(tester);
  });

  testWidgets('inline guidance scrolls in compact builder with larger text', (
    tester,
  ) async {
    client.questionResponse = [
      question('Who will use it?', [
        'Family members',
        'Friends',
        'Colleagues',
      ]),
      question('What should it track?', [
        'Tasks',
        'Events',
        'Notes',
      ]),
    ];
    await showBuilder(
      tester,
      initial: draft(),
      size: const Size(390, 844),
      textScale: 1.5,
    );
    await tester.enterText(composer(), 'A shared task app');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    expect(find.text('A few details would help'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('guidance-option-0-0')),
    );
    await tester.tap(find.byKey(const ValueKey('guidance-option-0-0')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('guidance-use')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guidance-use')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(composer()).controller!.text,
      contains('Family members'),
    );
    expect(tester.takeException(), isNull);
    await closeBuilder(tester);
  });

  testWidgets('guidance failure offers built-in questions and original send', (
    tester,
  ) async {
    client.questionFailure = const ServerpodClientNetworkException('offline');
    await showBuilder(tester, initial: draft());
    await tester.enterText(composer(), 'A simpler app');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    expect(find.text('Built-in questions'), findsOneWidget);
    expect(find.text('1. What should change first?'), findsOneWidget);
    expect(find.byKey(const ValueKey('guidance-use')), findsOneWidget);
    expect(client.generations, isEmpty);
    client.pendingGeneration = Completer<BuilderSnapshot>();
    await tester.ensureVisible(find.byKey(const ValueKey('guidance-continue')));
    await tester.tap(find.byKey(const ValueKey('guidance-continue')));
    await tester.pump();
    expect(client.generations, hasLength(1));
    expect(client.questionRequests, hasLength(1));
    expect(find.byKey(const ValueKey('guidance-use')), findsNothing);
    client.pendingGeneration!.complete(
      draft(stage: 'queued', mutation: 1, jobId: 7),
    );
    await tester.pump();
    await closeBuilder(tester);
  });

  testWidgets('late questions for a changed request cannot generate', (
    tester,
  ) async {
    client.pendingQuestions = Completer<List<GuidanceQuestion>>();
    await showBuilder(tester, initial: draft());
    await tester.enterText(composer(), 'A club app');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pump();
    tester.widget<TextField>(composer()).controller!.text = 'A new idea';
    client.pendingQuestions!.complete([
      question('Who uses it?', ['Neighbors', 'Friends', 'Colleagues']),
      question('What do they do?', ['Plan', 'Share', 'Track']),
    ]);
    await tester.pump();
    expect(find.text('A few details would help'), findsNothing);
    expect(client.generations, isEmpty);
    await closeBuilder(tester);
  });

  testWidgets('draft access errors cannot bypass guidance into generation', (
    tester,
  ) async {
    client.questionFailure = NestError(
      category: 'forbidden',
      message: 'Draft access changed.',
    );
    await showBuilder(tester, initial: draft());
    await tester.enterText(composer(), 'A club app');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    expect(find.text('Built-in questions'), findsNothing);
    expect(find.byKey(const ValueKey('guidance-continue')), findsNothing);
    expect(find.text('Draft access changed.'), findsOneWidget);
    expect(client.generations, isEmpty);
    await closeBuilder(tester);
  });

  testWidgets('a new idea can optionally ask for fresh guidance', (
    tester,
  ) async {
    client.questionResponse = [
      question('Who uses it?', ['Neighbors', 'Friends', 'Colleagues']),
      question('What do they do?', ['Plan', 'Share', 'Track']),
    ];
    await showBuilder(tester, initial: draft());
    await tester.enterText(composer(), 'A club app');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guidance-option-0-0')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('guidance-use')));
    await tester.tap(find.byKey(const ValueKey('guidance-use')));
    await tester.pumpAndSettle();
    await tester.enterText(composer(), 'A new app for gardeners');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shape-idea')));
    await tester.pumpAndSettle();
    expect(client.questionRequests, hasLength(2));
    expect(client.generations, isEmpty);
    await closeBuilder(tester);
  });

  testWidgets(
    'a successful draft refresh retains a failed platform connection',
    (
      tester,
    ) async {
      client.platformFailure = const ServerpodClientNetworkException('offline');
      await showBuilder(tester, initial: draft());
      expect(tester.widget<TextField>(composer()).enabled, isFalse);
      expect(find.text('Refresh connection'), findsOneWidget);

      await tester.tap(find.text('Refresh connection'));
      await tester.pumpAndSettle();
      expect(client.platformRequests, 2);
      expect(client.gets, [9]);
      expect(tester.widget<TextField>(composer()).enabled, isFalse);
      expect(find.text('Refresh connection'), findsOneWidget);

      client.platformFailure = null;
      await tester.tap(find.text('Refresh connection'));
      await tester.pumpAndSettle();
      expect(client.platformRequests, 3);
      expect(client.gets, [9, 9]);
      expect(tester.widget<TextField>(composer()).enabled, isTrue);
      expect(find.text('Refresh connection'), findsNothing);
      await closeBuilder(tester);
    },
  );

  for (final example in [
    (
      dailyPlannerTemplate(),
      'Tasks · Remind me',
      'App owner · At the selected time · In-app only · When Status is Open',
    ),
    (
      starterTemplates()['volunteer']!,
      'Shifts · Starts',
      'Members with an active place · 60 minutes before · In-app only',
    ),
  ]) {
    testWidgets('reminder approval explains ${example.$2} and recipients', (
      tester,
    ) async {
      await showBuilder(tester, initial: draft(spec: example.$1));
      await tester.tap(find.text('Use app'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      expect(find.text(example.$2), findsOneWidget);
      expect(find.text(example.$3), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await closeBuilder(tester);
    });
  }

  testWidgets(
    'a first generation hides the starter until the validated result',
    (
      tester,
    ) async {
      const request = 'Build a planner for our volunteer group';
      final queued = draft(stage: 'queued', mutation: 1, jobId: 7);
      client.current = queued;
      await showBuilder(
        tester,
        initial: queued,
        initialPrompt: request,
        startFromScratch: true,
      );
      expect(find.text('Your app is taking shape'), findsOneWidget);
      expect(find.byType(MiniAppRuntime), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Use app'))
            .onPressed,
        isNull,
      );
      expect(find.text(request), findsOneWidget);
      expect(tester.widget<TextField>(composer()).enabled, isFalse);

      client.current = draft(
        spec: dailyPlannerTemplate(),
        mutation: 1,
        jobId: 7,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(client.gets, [9]);
      expect(find.byType(MiniAppRuntime), findsOneWidget);
      expect(find.text('Your app is taking shape'), findsNothing);
      expect(find.text(request), findsOneWidget);
      expect(tester.widget<TextField>(composer()).enabled, isNot(isFalse));
      expect(find.byTooltip('Mobile preview'), findsOneWidget);
      expect(find.byTooltip('Desktop preview'), findsOneWidget);
      await tester.tap(find.byTooltip('Mobile preview'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(MiniAppRuntime)).width, 390);
      await tester.tap(find.byTooltip('Desktop preview'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(MiniAppRuntime)).width,
        greaterThan(390),
      );
      await closeBuilder(tester);
    },
  );

  testWidgets(
    'a fresh creation accepts a follow-up and preserves preview data',
    (tester) async {
      const creationRequest = 'Make a planner for our volunteer team';
      client.current = draft(
        stage: 'queued',
        mutation: 1,
        jobId: 7,
        latestRequest: creationRequest,
      );
      await showBuilder(
        tester,
        initial: client.current,
        initialPrompt: creationRequest,
        startFromScratch: true,
      );
      expect(find.byType(MiniAppRuntime), findsNothing);
      expect(tester.widget<TextField>(composer()).enabled, isFalse);

      final created = dailyPlannerTemplate();
      client.current = draft(
        spec: created,
        mutation: 1,
        jobId: 7,
        latestRequest: creationRequest,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final runtime = tester.widget<MiniAppRuntime>(
        find.byType(MiniAppRuntime),
      );
      final original = runtime.adapter;
      final row = (await original.query('tasks', {})).items.first;
      await original.execute(
        original.spec.actions.firstWhere(
          (action) =>
              action.collectionId == 'tasks' &&
              action.capability == 'records.patch.v1',
        ),
        row,
        {
          'data': {'title': 'Keep this sample task'},
        },
        'follow-up-preserves-sample',
      );
      await runtime.controller!.navigate(const MiniAppLocation('tasksPage'));
      await tester.pumpAndSettle();

      const followUp = 'Use an editorial style';
      client.current = draft(
        spec: created,
        stage: 'queued',
        mutation: 2,
        jobId: 8,
        candidateReady: true,
        latestRequest: followUp,
      );
      await tester.enterText(composer(), followUp);
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(client.generations.single, {
        'draftId': 9,
        'mutation': 1,
        'request': followUp,
        'startFromScratch': true,
      });
      expect(client.questionRequests, isEmpty);
      expect(tester.widget<TextField>(composer()).controller!.text, isEmpty);
      expect(tester.widget<TextField>(composer()).enabled, isFalse);
      expect(
        tester.widget<MiniAppRuntime>(find.byType(MiniAppRuntime)).adapter,
        same(original),
      );

      final changed = created.patch({
        'type': 'SetAppearance',
        'appearance': {'style': 'editorial'},
      }, () => 'unused');
      client.current = draft(
        spec: changed,
        mutation: 2,
        jobId: 8,
        latestRequest: followUp,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final updated = tester.widget<MiniAppRuntime>(
        find.byType(MiniAppRuntime),
      );
      expect(updated.adapter, same(original));
      expect(updated.adapter.spec.hash, changed.hash);
      expect(updated.adapter.spec.appearance!.style, 'editorial');
      expect(
        (await updated.adapter.get(row.id)).data['title'],
        'Keep this sample task',
      );
      expect(updated.controller!.location, const MiniAppLocation('tasksPage'));
      final state = tester.state<BuilderScreenState>(
        find.byType(BuilderScreen),
      );
      expect(
        state.conversation
            .where((message) => message.fromUser)
            .map(
              (message) => message.text,
            ),
        [creationRequest, followUp],
      );
      expect(tester.widget<TextField>(composer()).enabled, isTrue);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Use app'))
            .onPressed,
        isNotNull,
      );
      expect(client.generations, hasLength(1));
      expect(client.gets, [9, 9]);
      await closeBuilder(tester);
    },
  );

  testWidgets(
    'a resumed ready draft accepts a follow-up at its saved revision',
    (
      tester,
    ) async {
      final created = dailyPlannerTemplate();
      const originalRequest = 'Create a shared team planner';
      client.current = draft(
        spec: created,
        mutation: 4,
        jobId: 10,
        latestRequest: originalRequest,
      );
      await showBuilder(tester, initial: client.current);
      expect(find.text(originalRequest), findsOneWidget);
      expect(find.byType(MiniAppRuntime), findsOneWidget);

      const followUp = 'Use an editorial style';
      client.current = draft(
        spec: created,
        stage: 'queued',
        mutation: 5,
        jobId: 11,
        candidateReady: true,
        latestRequest: followUp,
      );
      await tester.enterText(composer(), followUp);
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(client.generations.single, {
        'draftId': 9,
        'mutation': 4,
        'request': followUp,
        'startFromScratch': false,
      });

      final changed = created.patch({
        'type': 'SetAppearance',
        'appearance': {'style': 'editorial'},
      }, () => 'unused');
      client.current = draft(
        spec: changed,
        mutation: 5,
        jobId: 11,
        latestRequest: followUp,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MiniAppRuntime>(find.byType(MiniAppRuntime))
            .adapter
            .spec
            .hash,
        changed.hash,
      );
      expect(find.text(followUp), findsOneWidget);
      expect(tester.widget<TextField>(composer()).enabled, isTrue);
      expect(client.generations, hasLength(1));
      await closeBuilder(tester);
    },
  );

  testWidgets(
    'blank requests are disabled and accepted requests are sent once',
    (
      tester,
    ) async {
      await showBuilder(tester, initial: draft());
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(client.generations, isEmpty);

      const request = 'Add a Notes field';
      client.pendingGeneration = Completer<BuilderSnapshot>();
      await tester.enterText(composer(), request);
      await tester.pump();
      final send = find.byTooltip('Send message');
      // Two clicks before the next frame must still dispatch only one mutation.
      await tester.tap(send);
      await tester.tap(send);
      await tester.pump();
      expect(client.generations, hasLength(1));
      expect(client.generations.single['request'], request);
      expect(client.generations.single['startFromScratch'], false);
      expect(client.generations.single['mutation'], 0);

      client.current = draft(
        stage: 'queued',
        mutation: 1,
        jobId: 7,
        candidateReady: true,
      );
      client.pendingGeneration!.complete(client.current);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<TextField>(composer()).controller!.text, isEmpty);
      expect(find.text(request), findsOneWidget);
      expect(find.byType(MiniAppRuntime), findsOneWidget);
      expect(find.byTooltip('Building your app'), findsOneWidget);
      await closeBuilder(tester);
    },
  );

  testWidgets(
    'a rejected request retains the composer for a deliberate retry',
    (
      tester,
    ) async {
      await showBuilder(tester, initial: draft());
      const request = 'Rename this app to Our Team';
      client.generationFailure = NestError(
        category: 'providerUnavailable',
        message: 'AI is temporarily unavailable.',
      );
      await tester.enterText(composer(), request);
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(client.generations, hasLength(1));
      expect(tester.widget<TextField>(composer()).controller!.text, request);
      expect(find.byType(MiniAppRuntime), findsOneWidget);

      client.generationFailure = null;
      client.current = draft(stage: 'queued', mutation: 1, jobId: 7);
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(client.generations, hasLength(2));
      expect(client.generations.last['request'], request);
      expect(tester.widget<TextField>(composer()).controller!.text, isEmpty);
      await closeBuilder(tester);
    },
  );

  testWidgets('a failed first generation retries the original fresh request', (
    tester,
  ) async {
    const request = 'Create a shared garden planner';
    client.current = draft(
      stage: 'failed',
      mutation: 1,
      jobId: 7,
      diagnostics: ['The generated definition could not be validated.'],
    );
    await showBuilder(
      tester,
      initial: client.current,
      initialPrompt: request,
      startFromScratch: true,
    );
    expect(find.byType(MiniAppRuntime), findsNothing);
    expect(
      find.text(
        builderFailureMessage(client.current.diagnostics, hasPreview: false),
      ),
      findsNWidgets(2),
    );
    expect(find.text('Try again'), findsOneWidget);
    client.current = draft(stage: 'queued', mutation: 2, jobId: 8);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(client.generations, hasLength(1));
    expect(client.generations.single['request'], request);
    expect(client.generations.single['startFromScratch'], true);
    expect(client.generations.single['mutation'], 1);
    expect(find.byType(MiniAppRuntime), findsNothing);
    await closeBuilder(tester);
  });

  testWidgets('a failed follow-up keeps the validated preview available', (
    tester,
  ) async {
    final created = draft(spec: dailyPlannerTemplate(), mutation: 1, jobId: 7);
    await showBuilder(
      tester,
      initial: created,
      initialPrompt: 'Make a team planner',
      startFromScratch: true,
    );
    final original = tester
        .widget<MiniAppRuntime>(find.byType(MiniAppRuntime))
        .adapter;
    const request = 'Add another calendar';
    client.current = draft(
      spec: dailyPlannerTemplate(),
      stage: 'queued',
      mutation: 2,
      jobId: 8,
      candidateReady: true,
    );
    await tester.enterText(composer(), request);
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(find.byType(MiniAppRuntime), findsOneWidget);

    client.current = draft(
      spec: dailyPlannerTemplate(),
      stage: 'failed',
      mutation: 2,
      jobId: 8,
      candidateReady: true,
      diagnostics: ['This requested capability is unavailable.'],
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MiniAppRuntime), findsOneWidget);
    expect(
      tester.widget<MiniAppRuntime>(find.byType(MiniAppRuntime)).adapter,
      same(original),
    );
    final failureMessage = builderFailureMessage(
      client.current.diagnostics,
      hasPreview: true,
    );
    expect(find.text(failureMessage), findsWidgets);
    expect(find.text(request), findsOneWidget);
    expect(tester.widget<TextField>(composer()).enabled, isNot(isFalse));
    expect(client.generations.single['startFromScratch'], true);
    await closeBuilder(tester);
  });

  testWidgets(
    'a late generation response is ignored after leaving the builder',
    (
      tester,
    ) async {
      await showBuilder(tester, initial: draft());
      client.pendingGeneration = Completer<BuilderSnapshot>();
      await tester.enterText(composer(), 'Add a Notes field');
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(client.generations, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      client.pendingGeneration!.complete(
        draft(stage: 'queued', mutation: 1, jobId: 7),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile creation fits with large text before and after generation',
    (
      tester,
    ) async {
      client.current = draft(stage: 'generating', mutation: 1, jobId: 7);
      await showBuilder(
        tester,
        initial: client.current,
        initialPrompt:
            'Create a planner for our neighborhood garden volunteers',
        startFromScratch: true,
        size: const Size(390, 844),
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
      client.current = draft(
        spec: dailyPlannerTemplate(),
        mutation: 1,
        jobId: 7,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(Tab, 'Try'));
      await tester.pumpAndSettle();
      expect(find.byType(MiniAppRuntime), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Use app'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Use app').last,
      );
      expect(tester.takeException(), isNull);
      await closeBuilder(tester);
    },
  );
  testWidgets(
    'JSON generation failure explains response problem without exposing repair instructions',
    (tester) async {
      const details =
          'The AI response was not valid JSON. Return exactly one complete JSON object without commentary or markdown.';
      const request = 'Create a custom reading journal';
      client.current = draft(stage: 'queued', mutation: 1, jobId: 7);
      await showBuilder(
        tester,
        initial: client.current,
        initialPrompt: request,
        startFromScratch: true,
      );
      client.current = draft(
        stage: 'failed',
        mutation: 1,
        jobId: 7,
        diagnostics: [details],
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      final message = builderFailureMessage([details], hasPreview: false);
      expect(find.text(message), findsNWidgets(2));
      expect(find.textContaining('simpler first version'), findsNothing);
      expect(
        find.textContaining('smaller, more specific request'),
        findsNothing,
      );
      expect(find.text(details), findsNothing);
      expect(find.byType(MiniAppRuntime), findsNothing);
      final buildDetails = find.text('Build details');
      await tester.ensureVisible(buildDetails);
      await tester.tap(buildDetails);
      await tester.pumpAndSettle();
      expect(find.text(details), findsOneWidget);
      final retry = find.text('Try again');
      await tester.ensureVisible(retry);
      client.current = draft(stage: 'queued', mutation: 2, jobId: 8);
      await tester.tap(retry);
      await tester.pump();
      expect(client.generations.single['request'], request);
      await closeBuilder(tester);
    },
  );
}
