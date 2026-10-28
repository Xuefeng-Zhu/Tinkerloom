import 'package:appnest_client/appnest_client.dart';
import 'package:flutter/material.dart';

import 'idea_guidance.dart';

class BuilderMessage {
  final String text;
  final bool fromUser;
  final List<String> changes;
  const BuilderMessage({
    required this.text,
    this.fromUser = false,
    this.changes = const [],
  });
}

String builderStageLabel(String stage) => switch (stage) {
  'queued' => 'Getting started',
  'generating' => 'Building your app',
  'validating' => 'Checking your app',
  'preview ready' => 'Preview ready',
  'failed' => 'Let’s try that again',
  'stale' => 'This draft has changed',
  _ => 'Draft saved',
};

/// Diagnostics also contain instructions for an AI repair attempt. Translate
/// recognized failures into user guidance; do not promote raw diagnostics or
/// model-supplied text into the main failure message.
String builderFailureMessage(
  List<String> diagnostics, {
  required bool hasPreview,
}) {
  final details = diagnostics.join(' ').toLowerCase();
  final requestedUnsupported = details.contains(
    'requested capability is unavailable',
  );
  final String reason;
  if (details.contains('token limit')) {
    reason = 'The AI response ended before AppNest could finish your app.';
  } else if (details.contains('definition is too large') ||
      details.contains('response exceeded the size limit')) {
    reason = 'The AI response was too large for AppNest to use.';
  } else if (details.contains('timed out') ||
      details.contains('response limit')) {
    reason = 'The AI service took too long to respond.';
  } else if (details.contains('not valid json') ||
      details.contains('invalid json response') ||
      details.contains('must be a json object')) {
    reason = 'The AI returned a response AppNest couldn’t read.';
  } else if (details.contains('ai provider')) {
    reason = 'The AI service couldn’t complete the request.';
  } else if (requestedUnsupported) {
    reason = 'This request needs a feature AppNest doesn’t support yet.';
  } else if (details.contains('unsupported capability') ||
      details.contains('unsupported capabilities')) {
    reason = 'The AI used a feature AppNest doesn’t support.';
  } else if (details.contains('could not be validated') ||
      details.contains('could not validate')) {
    reason = 'AppNest couldn’t validate the generated app.';
  } else {
    reason = 'AppNest couldn’t finish building this preview.';
  }
  return [
    reason,
    if (hasPreview) 'Your last preview is still here.',
    requestedUnsupported
        ? 'Adjust the requested features, then try again.'
        : 'Try again with the same request.',
  ].join(' ');
}

class BuilderChat extends StatelessWidget {
  final List<BuilderMessage> messages;
  final ScrollController scrollController;
  final TextEditingController controller;
  final String stage;
  final bool generating;
  final bool busy;
  final bool assessing;
  final bool? aiAvailable;
  final bool hasPreview;
  final String? error;
  final List<String> diagnostics;
  final VoidCallback onSend;
  final VoidCallback? onShapeIdea;
  final VoidCallback? onKeepPreview;
  final int jobAttempts;
  final DateTime? jobCreatedAt;
  final List<GuidanceQuestion>? guidanceQuestions;
  final Key guidancePanelKey;
  final String? guidanceSource;
  final String? guidanceContextId;
  final bool guidanceFallback;
  final String? guidanceNotice;
  final String Function() guidanceContext;
  final ValueChanged<String> onUseGuidanceAnswers;
  final VoidCallback onContinueOriginal;
  final VoidCallback onEditIdea;
  final VoidCallback? onRetry;
  final VoidCallback onReconnect;

  const BuilderChat({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.controller,
    required this.stage,
    required this.generating,
    required this.busy,
    required this.assessing,
    required this.aiAvailable,
    required this.hasPreview,
    required this.error,
    required this.diagnostics,
    required this.onSend,
    this.onShapeIdea,
    this.onKeepPreview,
    this.jobAttempts = 0,
    this.jobCreatedAt,
    required this.guidanceQuestions,
    required this.guidancePanelKey,
    required this.guidanceSource,
    required this.guidanceContextId,
    required this.guidanceFallback,
    required this.guidanceNotice,
    required this.guidanceContext,
    required this.onUseGuidanceAnswers,
    required this.onContinueOriginal,
    required this.onEditIdea,
    required this.onRetry,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xfffafbf8),
      child: LayoutBuilder(
        builder: (context, bounds) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xffe2eeea),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome_outlined, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Build with AppNest',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Text(
                          'Describe. Try. Make it yours.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  for (final message in messages)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.fromUser ? 'You' : 'AppNest',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: message.fromUser
                                ? const EdgeInsets.all(14)
                                : EdgeInsets.zero,
                            decoration: message.fromUser
                                ? BoxDecoration(
                                    color: const Color(0xffedf0e9),
                                    borderRadius: BorderRadius.circular(14),
                                  )
                                : null,
                            child: SelectableText(message.text),
                          ),
                          if (message.changes.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Current preview',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            for (final change in message.changes.take(4))
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.check,
                                      size: 16,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        change,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  if (generating)
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xffdce4db)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const LinearProgressIndicator(minHeight: 2),
                            const SizedBox(height: 16),
                            Text(
                              builderStageLabel(stage),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (jobAttempts > 1)
                              Text('Attempt $jobAttempts of 3'),
                            if (jobCreatedAt != null)
                              Text(
                                '${DateTime.now().difference(jobCreatedAt!).inSeconds.clamp(0, 3600)} seconds since your request was saved',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 6),
                            Text(switch (stage) {
                              'queued' =>
                                'Your request is saved and waiting to start.',
                              'validating' => 'Checking the pages, data and actions before updating your preview.',
                              _ => 'Turning your request into pages, data and actions. This can take a minute.',
                            }),
                          ],
                        ),
                      ),
                    ),
                  if (!generating &&
                      (stage == 'failed' || stage == 'stale')) ...[
                    Text(
                      builderStageLabel(stage),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      stage == 'stale'
                          ? 'A newer draft or published version replaced this request. Go back and reopen the app to continue from its latest version.'
                          : builderFailureMessage(
                              diagnostics,
                              hasPreview: hasPreview,
                            ),
                    ),
                    if (onRetry != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: busy ? null : onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      ),
                    if (onKeepPreview != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: busy ? null : onKeepPreview,
                          child: const Text('Keep previous preview'),
                        ),
                      ),
                  ],
                  if (diagnostics.isNotEmpty && !generating)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Build details',
                        style: TextStyle(fontSize: 13),
                      ),
                      children: diagnostics.map((d) => Text(d)).toList(),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: TextStyle(color: colors.error)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: busy ? null : onReconnect,
                        child: const Text('Refresh connection'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (aiAvailable == false)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Template mode · AI provider not configured. Use Customize to shape your app.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (bounds.maxHeight * .68).clamp(100.0, 640.0),
                ),
                child: SingleChildScrollView(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xffcfd9cf)),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const ValueKey('builder-prompt'),
                          controller: controller,
                          enabled:
                              aiAvailable == true &&
                              !busy &&
                              !generating &&
                              stage != 'stale',
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 4000,
                          decoration: InputDecoration(
                            hintText: hasPreview
                                ? 'Ask AppNest to make a change…'
                                : 'Describe the app you want to build…',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            counterText: '',
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                        if (guidanceQuestions != null &&
                            guidanceSource != null &&
                            guidanceContextId != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                            child: IdeaGuidancePanel(
                              key: guidancePanelKey,
                              composer: controller,
                              sourceText: guidanceSource!,
                              contextId: guidanceContextId!,
                              currentContext: guidanceContext,
                              questions: guidanceQuestions!,
                              usedFallback: guidanceFallback,
                              notice: guidanceNotice,
                              onUseAnswers: onUseGuidanceAnswers,
                              onContinueOriginal: onContinueOriginal,
                              onEditIdea: onEditIdea,
                            ),
                          ),
                        if (onShapeIdea != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: controller,
                              builder: (context, value, _) => TextButton.icon(
                                key: const ValueKey('shape-idea'),
                                onPressed:
                                    busy ||
                                        generating ||
                                        aiAvailable != true ||
                                        stage == 'stale' ||
                                        value.text.trim().isEmpty
                                    ? null
                                    : onShapeIdea,
                                icon: const Icon(
                                  Icons.lightbulb_outline,
                                  size: 16,
                                ),
                                label: const Text('Help shape my idea'),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 10, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  assessing
                                      ? 'Checking whether a few details would help'
                                      : generating
                                      ? 'Working on your request'
                                      : 'Ready when you are',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: controller,
                                builder: (context, value, _) =>
                                    IconButton.filled(
                                      tooltip: generating
                                          ? 'Building your app'
                                          : 'Send message',
                                      onPressed:
                                          busy ||
                                              assessing ||
                                              generating ||
                                              aiAvailable != true ||
                                              value.text.trim().isEmpty ||
                                              stage == 'stale'
                                          ? null
                                          : onSend,
                                      icon: busy || assessing
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.arrow_upward,
                                              size: 20,
                                            ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Try changes here. Apply them when you’re ready.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
