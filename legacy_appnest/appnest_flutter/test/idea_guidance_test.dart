import 'dart:ui' as ui;

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/features/builder/idea_guidance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GuidanceQuestion question(String text, List<String> options) =>
      GuidanceQuestion(question: text, options: options);

  test('guidance limit is smaller than the generation limit', () {
    expect(canAssessIdea('A club app'), isTrue);
    expect(canAssessIdea(List.filled(2001, 'a').join()), isFalse);
    expect(canAssessIdea(List.filled(1500, '€').join()), isFalse);
  });

  test('malformed nonempty choices require fallback, not direct creation', () {
    expect(cleanGuidanceQuestions([]), isEmpty);
    expect(
      cleanGuidanceQuestions([
        question('Who will join?', ['Friends', 'friends', 'Neighbors']),
        question('What will they do?', ['Plan', 'Share', 'Track']),
      ]),
      isNull,
    );
  });

  testWidgets('answers compose an editable request without submitting it', (
    tester,
  ) async {
    final composer = TextEditingController(text: 'A club app');
    addTearDown(composer.dispose);
    String? prepared;
    var continued = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: IdeaGuidancePanel(
              composer: composer,
              sourceText: 'A club app',
              contextId: 'workspace:1',
              currentContext: () => 'workspace:1',
              questions: [
                question('Who joins?', ['Neighbors', 'Friends', 'Colleagues']),
                question('What can they do?', ['Plan', 'Discuss', 'Track']),
              ],
              usedFallback: false,
              onUseAnswers: (value) => prepared = value,
              onContinueOriginal: () => continued++,
              onEditIdea: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(TextFormField), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('guidance-use')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('guidance-option-0-0')));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('guidance-option-0-0')))
          .selected,
      isTrue,
    );
    final selectedSemantics = tester.getSemantics(
      find.byKey(const ValueKey('guidance-option-semantics-0-0')),
    );
    expect(selectedSemantics.label, contains('Who joins? Neighbors'));
    expect(selectedSemantics.flagsCollection.isSelected, ui.Tristate.isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('guidance-use')));
    await tester.tap(find.byKey(const ValueKey('guidance-use')));
    await tester.pump();
    expect(prepared, 'A club app\n\nMore details:\n- Who joins? Neighbors');
    expect(composer.text, 'A club app');
    expect(continued, 0);
  });

  testWidgets('new questions clear old selections in the same panel', (
    tester,
  ) async {
    final composer = TextEditingController(text: 'A club app');
    addTearDown(composer.dispose);
    final panelKey = GlobalKey();
    Widget screen(List<GuidanceQuestion> questions) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: IdeaGuidancePanel(
            key: panelKey,
            composer: composer,
            sourceText: 'A club app',
            contextId: 'workspace:1',
            currentContext: () => 'workspace:1',
            questions: questions,
            usedFallback: false,
            onUseAnswers: (_) {},
            onContinueOriginal: () {},
            onEditIdea: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      screen([
        question('Who joins?', ['Neighbors', 'Friends', 'Colleagues']),
      ]),
    );
    await tester.tap(find.byKey(const ValueKey('guidance-option-0-0')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('guidance-use')))
          .onPressed,
      isNotNull,
    );

    await tester.pumpWidget(
      screen([
        question('What changes?', ['Layout', 'Fields', 'Colors']),
      ]),
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('guidance-option-0-0')))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('guidance-use')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('choosing another option replaces the previous selection', (
    tester,
  ) async {
    final composer = TextEditingController(text: 'A club app');
    addTearDown(composer.dispose);
    String? prepared;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: IdeaGuidancePanel(
              composer: composer,
              sourceText: 'A club app',
              contextId: 'workspace:1',
              currentContext: () => 'workspace:1',
              questions: [
                question('Who joins?', ['Neighbors', 'Friends', 'Colleagues']),
              ],
              usedFallback: false,
              onUseAnswers: (value) => prepared = value,
              onContinueOriginal: () {},
              onEditIdea: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('guidance-option-0-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guidance-option-0-1')));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('guidance-option-0-0')))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('guidance-option-0-1')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('guidance-use')));
    expect(prepared, contains('Who joins? Friends'));
    expect(prepared, isNot(contains('Neighbors')));
  });

  testWidgets('stale idea or context cannot apply questions', (tester) async {
    final composer = TextEditingController(text: 'A club app');
    addTearDown(composer.dispose);
    var contextId = 'workspace:1';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: IdeaGuidancePanel(
              composer: composer,
              sourceText: 'A club app',
              contextId: 'workspace:1',
              currentContext: () => contextId,
              questions: [
                question('Who joins?', ['Neighbors', 'Friends', 'Colleagues']),
                question('What can they do?', ['Plan', 'Discuss', 'Track']),
              ],
              usedFallback: false,
              onUseAnswers: (_) => fail('stale answers were applied'),
              onContinueOriginal: () => fail('stale request was sent'),
              onEditIdea: () {},
            ),
          ),
        ),
      ),
    );
    contextId = 'workspace:2';
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guidance-continue')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guidance-use')));
    await tester.pump();
    contextId = 'workspace:1';
    composer.text = 'A different app';
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guidance-use')));
    await tester.pump();
  });

  testWidgets('built-in questions fit a phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final composer = TextEditingController(text: 'A club app');
    addTearDown(composer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: IdeaGuidancePanel(
                composer: composer,
                sourceText: 'A club app',
                contextId: 'workspace:1',
                currentContext: () => 'workspace:1',
                questions: builtInGuidanceQuestions,
                usedFallback: true,
                notice: 'AI questions are unavailable.',
                onUseAnswers: (_) {},
                onContinueOriginal: () {},
                onEditIdea: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Built-in questions'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('guidance-continue')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
