import 'dart:async';
import 'dart:convert';

import 'package:appnest_client/appnest_client.dart';
import 'package:flutter/material.dart';

/// Guidance has a smaller input limit than generation. Longer valid requests
/// bypass the assessment and still reach the normal generation endpoint.
bool canAssessIdea(String idea) =>
    idea.length <= 2000 && utf8.encode(idea).length <= 4000;

bool canOfferBuiltInGuidance(Object error) =>
    error is ServerpodClientNetworkException ||
    error is TimeoutException ||
    (error is NestError &&
        {'providerUnavailable', 'quotaExceeded'}.contains(error.category));

final builtInGuidanceQuestions = <GuidanceQuestion>[
  GuidanceQuestion(
    question: 'Who will use this app?',
    options: [
      'Just me',
      'A small team or club',
      'People in my community',
      'Customers or clients',
    ],
  ),
  GuidanceQuestion(
    question: 'What should it keep track of?',
    options: [
      'Tasks and due dates',
      'Events and attendance',
      'Members and contacts',
      'Notes and updates',
    ],
  ),
  GuidanceQuestion(
    question: 'What should people do most often?',
    options: [
      'Add and update entries',
      'Plan and schedule',
      'Share and discuss',
      'View progress',
    ],
  ),
];

final builtInEditGuidanceQuestions = <GuidanceQuestion>[
  GuidanceQuestion(
    question: 'What should change first?',
    options: [
      'Layout and navigation',
      'Fields and forms',
      'Colors and wording',
      'Rules or reminders',
    ],
  ),
  GuidanceQuestion(
    question: 'Who should this change help most?',
    options: [
      'App owners',
      'People adding records',
      'People viewing records',
      'Everyone',
    ],
  ),
  GuidanceQuestion(
    question: 'How much should change?',
    options: [
      'One screen or section',
      'Several screens',
      'Only the appearance',
      'I am not sure yet',
    ],
  ),
];

/// Null means a malformed nonempty response; [] is the provider's explicit
/// decision that the request needs no clarification.
List<GuidanceQuestion>? cleanGuidanceQuestions(
  List<GuidanceQuestion> questions,
) {
  if (questions.isEmpty) return [];
  if (questions.length < 2 || questions.length > 3) return null;
  final cleaned = <GuidanceQuestion>[];
  final seenQuestions = <String>{};
  for (final item in questions) {
    final question = item.question.trim();
    final options = item.options.map((option) => option.trim()).toList();
    if (question.length < 8 ||
        question.length > 120 ||
        !question.endsWith('?') ||
        !seenQuestions.add(question.toLowerCase()) ||
        options.length < 3 ||
        options.length > 4 ||
        options.any((option) => option.length < 2 || option.length > 80) ||
        options.map((option) => option.toLowerCase()).toSet().length !=
            options.length) {
      return null;
    }
    cleaned.add(GuidanceQuestion(question: question, options: options));
  }
  return cleaned;
}

/// Questions are supplied by the submit gate, so this never makes a second AI
/// request or creates a draft. The surrounding composer remains editable.
class IdeaGuidancePanel extends StatefulWidget {
  final TextEditingController composer;
  final String sourceText;
  final String contextId;
  final String Function() currentContext;
  final List<GuidanceQuestion> questions;
  final bool usedFallback;
  final String? notice;
  final ValueChanged<String> onUseAnswers;
  final VoidCallback onContinueOriginal;
  final VoidCallback onEditIdea;

  const IdeaGuidancePanel({
    super.key,
    required this.composer,
    required this.sourceText,
    required this.contextId,
    required this.currentContext,
    required this.questions,
    required this.usedFallback,
    this.notice,
    required this.onUseAnswers,
    required this.onContinueOriginal,
    required this.onEditIdea,
  });

  @override
  State<IdeaGuidancePanel> createState() => _IdeaGuidancePanelState();
}

class _IdeaGuidancePanelState extends State<IdeaGuidancePanel> {
  final selections = <int, int>{};
  String? localNotice;

  @override
  void didUpdateWidget(covariant IdeaGuidancePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sourceText != oldWidget.sourceText ||
        widget.contextId != oldWidget.contextId ||
        !identical(widget.questions, oldWidget.questions)) {
      selections.clear();
      localNotice = null;
    }
  }

  bool get contextIsCurrent =>
      widget.currentContext() == widget.contextId &&
      widget.composer.text.trim() == widget.sourceText;

  void selectOption(int questionIndex, int optionIndex, bool selected) {
    setState(() {
      if (selected) {
        selections[questionIndex] = optionIndex;
      } else {
        selections.remove(questionIndex);
      }
      localNotice = null;
    });
  }

  void useAnswers() {
    if (!contextIsCurrent) return;
    final details = <String>[
      for (var i = 0; i < widget.questions.length; i++)
        if (selections[i] != null)
          '- ${widget.questions[i].question} ${widget.questions[i].options[selections[i]!]}',
    ];
    if (details.isEmpty) {
      setState(() => localNotice = 'Choose at least one option first.');
      return;
    }
    final combined =
        '${widget.sourceText}\n\nMore details:\n${details.join('\n')}';
    if (combined.length > 4000 || utf8.encode(combined).length > 16384) {
      setState(() => localNotice = 'These choices exceed the request limit.');
      return;
    }
    widget.onUseAnswers(combined);
  }

  @override
  Widget build(BuildContext context) {
    final current = contextIsCurrent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfff5f8f4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffd7e1d8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.usedFallback
                  ? 'Built-in questions'
                  : 'A few details would help',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.notice ??
                  (widget.usedFallback
                      ? 'Choose what fits, or continue with your original description.'
                      : 'Choose what fits, then review your description before building.'),
            ),
            if (!current) ...[
              const SizedBox(height: 8),
              const Text(
                'Your idea or app changed. Submit it again for fresh questions.',
              ),
            ],
            const SizedBox(height: 12),
            for (var i = 0; i < widget.questions.length; i++) ...[
              Text(
                '${i + 1}. ${widget.questions[i].question}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var j = 0; j < widget.questions[i].options.length; j++)
                    Semantics(
                      key: ValueKey('guidance-option-semantics-$i-$j'),
                      container: true,
                      label:
                          '${widget.questions[i].question} ${widget.questions[i].options[j]}',
                      selected: selections[i] == j,
                      button: true,
                      enabled: current,
                      onTap: current
                          ? () => selectOption(i, j, selections[i] != j)
                          : null,
                      child: ExcludeSemantics(
                        child: ChoiceChip(
                          key: ValueKey('guidance-option-$i-$j'),
                          label: Text(widget.questions[i].options[j]),
                          selected: selections[i] == j,
                          onSelected: current
                              ? (selected) => selectOption(i, j, selected)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (localNotice != null)
              Semantics(liveRegion: true, child: Text(localNotice!)),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: widget.onEditIdea,
                  child: const Text('Edit idea'),
                ),
                TextButton(
                  key: const ValueKey('guidance-continue'),
                  onPressed: current
                      ? () {
                          if (contextIsCurrent) widget.onContinueOriginal();
                        }
                      : null,
                  child: const Text('Continue with original idea'),
                ),
                FilledButton(
                  key: const ValueKey('guidance-use'),
                  onPressed: current && selections.isNotEmpty
                      ? useAnswers
                      : null,
                  child: const Text('Use selections'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
