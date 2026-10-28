import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:flutter/material.dart';

import '../../client.dart';
import '../media/image_upload.dart';
import 'builder_chat.dart';
import 'reminder_editor.dart';
import 'idea_guidance.dart';
import 'page_editor.dart';
import 'visual_edit_session.dart';
import 'visual_inspector.dart';

class BuilderScreen extends StatefulWidget {
  final BuilderSnapshot initial;
  final String? initialPrompt;
  final bool startFromScratch;
  final Future<void> Function()? onClose;
  final Future<void> Function(int appId)? onPublished;
  const BuilderScreen({
    super.key,
    required this.initial,
    this.initialPrompt,
    this.startFromScratch = false,
    this.onClose,
    this.onPublished,
  });
  @override
  State<BuilderScreen> createState() => BuilderScreenState();
}

class BuilderScreenState extends State<BuilderScreen> {
  late BuilderSnapshot draft;
  late PreviewRuntimeAdapter preview;
  final prompt = TextEditingController();
  final guidancePanelKey = GlobalKey();
  final conversationScroll = ScrollController();
  final conversation = <BuilderMessage>[];
  Timer? timer;
  Object? error;
  Object? platformError;
  bool busy = false;
  bool _reviewing = false;
  bool assessing = false;
  List<GuidanceQuestion>? guidanceQuestions;
  String? guidanceSource;
  String? guidanceContextId;
  bool guidanceFallback = false;
  String? guidanceNotice;
  bool polling = false;
  bool mobilePreview = false;
  bool customizing = false;
  ({int mutation, int? jobId, String request})? uncertainGeneration;
  late bool hasPreview;
  String? lastRequest;
  bool? ai;
  final enabled = <String>{};
  final previewController = MiniAppController();
  VisualEditSession? visualSession;
  MiniAppEditTarget? visualTarget;
  bool visualEditing = false;
  bool changingTarget = false;
  bool allowPop = false;
  BuildContext? inspectorSheet;
  final inspectorRevision = ValueNotifier(0);
  int inspectorReset = 0;
  final _previewImages = <String, Uint8List>{};
  final _loadingPreviewImages = <String>{};

  PreviewRuntimeAdapter newPreview(AppSpec spec) {
    final adapter = PreviewRuntimeAdapter(
      spec,
      pickImage: pickAppImage,
      imageAssets: _previewImages,
    );
    unawaited(loadPreviewImages(spec));
    return adapter;
  }

  Future<void> loadPreviewImages(AppSpec spec) async {
    for (final id
        in spec.views
            .map((view) => view.options['imageAssetId'])
            .whereType<String>()
            .toSet()) {
      if (_previewImages.containsKey(id) || !_loadingPreviewImages.add(id)) {
        continue;
      }
      try {
        final bytes = await client.media.readImage(draft.appId, id, 'display');
        if (!mounted) return;
        final image = Uint8List.sublistView(bytes);
        _previewImages[id] = image;
        preview.setImageAsset(id, image);
      } catch (_) {
        // The shared renderer shows an unavailable image; no public URL fallback.
      } finally {
        _loadingPreviewImages.remove(id);
      }
    }
  }

  Future<String?> uploadDraftImage() async {
    final bytes = await pickAppImage();
    if (bytes == null || !mounted) return null;
    final id = await uploadAppImage(
      client,
      bytes,
      appId: draft.appId,
      draftId: draft.draftId,
    );
    final sanitized = await client.media.readImage(draft.appId, id, 'display');
    if (mounted) {
      final image = Uint8List.sublistView(sanitized);
      _previewImages[id] = image;
      preview.setImageAsset(id, image);
    }
    return id;
  }

  bool get generating =>
      {'queued', 'generating', 'validating'}.contains(draft.stage);
  bool get canEdit =>
      !busy &&
      !generating &&
      hasPreview &&
      draft.stage != 'stale' &&
      draft.publishedVersionId == null;
  bool get canPublish =>
      !_reviewing &&
      canEdit &&
      draft.stage == 'preview ready' &&
      draft.publishedVersionId == null;

  @override
  void initState() {
    super.initState();
    draft = widget.initial;
    enabled.addAll(draft.enabledRuleIds);
    preview = newPreview(AppSpec.parse(draft.candidateJson));
    hasPreview = draft.candidateReady;
    lastRequest = widget.initialPrompt ?? draft.latestRequest;
    prompt.addListener(onPromptChanged);
    if (lastRequest?.isNotEmpty == true) {
      conversation.add(BuilderMessage(text: lastRequest!, fromUser: true));
    }
    if (draft.stage == 'failed') {
      conversation.add(
        BuilderMessage(
          text: builderFailureMessage(
            draft.diagnostics,
            hasPreview: hasPreview,
          ),
        ),
      );
    } else if (hasPreview) {
      conversation.add(
        BuilderMessage(
          text: widget.initialPrompt == null
              ? 'Your app is ready to shape. Try the preview, then tell me what you would like to change.'
              : 'Your first preview is ready. Try it out, then ask for a change.',
          changes: widget.initialPrompt == null
              ? const []
              : describeChanges(draft),
        ),
      );
    }
    loadPlatform();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (generating) poll();
    });
  }

  Future<void> loadPlatform() async {
    try {
      final platform = await client.builder.platform();
      if (mounted) {
        setState(() {
          ai = platform.aiAvailable;
          platformError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => platformError = e);
    }
  }

  void update(BuilderSnapshot d, {bool acceptedRequest = false}) {
    if (!mounted || d.mutation < draft.mutation) return;
    final completed =
        (generating || acceptedRequest) && d.stage == 'preview ready';
    final failed =
        d.stage == 'failed' &&
        (draft.stage != 'failed' ||
            d.jobId != draft.jobId ||
            d.mutation != draft.mutation);
    setState(() {
      if (d.mutation != draft.mutation ||
          d.candidateHash != draft.candidateHash) {
        guidanceQuestions = null;
      }
      if (d.candidateHash != draft.candidateHash) {
        final nextSpec = AppSpec.parse(d.candidateJson);
        final previousRules = {
          for (final rule in preview.spec.automationRequests)
            rule.id: canonicalJson(rule.toJson()),
        };
        enabled.removeWhere((id) {
          final next = nextSpec.automationRequests
              .where((rule) => rule.id == id)
              .firstOrNull;
          return next == null ||
              previousRules[id] != canonicalJson(next.toJson());
        });
        try {
          // AI changes and direct controls share the same presentation guard.
          // Keeping this adapter retains sample data, location and filters.
          preview.applyPresentationSpec(nextSpec);
          unawaited(loadPreviewImages(nextSpec));
        } on Object catch (issue) {
          if (issue is! SpecException && issue is! ArgumentError) rethrow;
          preview.dispose();
          preview = newPreview(nextSpec);
        }
        enabled.removeWhere(
          (id) => !preview.spec.automationRequests.any((r) => r.id == id),
        );
      }
      draft = d;
      hasPreview = d.candidateReady;
      lastRequest = d.latestRequest ?? lastRequest;
      if (completed) {
        conversation.add(
          BuilderMessage(
            text: 'Your preview is ready. Try it out, or tell me what to adjust next.',
            changes: describeChanges(d),
          ),
        );
      } else if (failed) {
        conversation.add(
          BuilderMessage(
            text: builderFailureMessage(d.diagnostics, hasPreview: hasPreview),
          ),
        );
      }
    });
    if (completed || failed) scrollConversation();
  }

  Future<void> poll() async {
    if (polling || busy) return;
    polling = true;
    final mutation = draft.mutation;
    try {
      final next = await client.builder.get(draft.draftId);
      if (!mounted || busy || mutation != draft.mutation) return;
      if (!recoverAcceptedRequest(next)) update(next);
      setState(() => error = null);
    } catch (e) {
      if (mounted && !busy && mutation == draft.mutation) {
        setState(() => error = e);
      }
    } finally {
      polling = false;
    }
  }

  void scrollConversation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && conversationScroll.hasClients) {
        conversationScroll.animateTo(
          conversationScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String currentGuidanceContext() =>
      '${draft.draftId}:${draft.mutation}:${draft.candidateHash}';

  void onPromptChanged() {
    if (guidanceQuestions != null && prompt.text.trim() != guidanceSource) {
      setState(() => guidanceQuestions = null);
    }
  }

  void showGuidance(
    List<GuidanceQuestion> questions,
    String request,
    String contextId, {
    required bool fallback,
    String? notice,
  }) {
    setState(() {
      guidanceQuestions = questions;
      guidanceSource = request;
      guidanceContextId = contextId;
      guidanceFallback = fallback;
      guidanceNotice = notice;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final panelContext = guidancePanelKey.currentContext;
      if (mounted && panelContext != null) {
        Scrollable.ensureVisible(
          panelContext,
          alignment: 0,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  Future<void> send({String? retry}) async {
    final request = (retry ?? prompt.text).trim();
    if (busy ||
        assessing ||
        generating ||
        draft.stage == 'stale' ||
        ai != true ||
        request.isEmpty) {
      return;
    }
    if (!await finishVisualEdit() || !mounted) return;
    await perform(() async {
      if (uncertainGeneration != null) {
        final recovered = await client.builder.get(draft.draftId);
        if (!mounted || recoverAcceptedRequest(recovered)) return;
        update(recovered);
        uncertainGeneration = null;
        if (generating || draft.stage == 'stale') return;
      }
      final previousMutation = draft.mutation;
      final previousJobId = draft.jobId;
      uncertainGeneration = (
        mutation: previousMutation,
        jobId: previousJobId,
        request: request,
      );
      try {
        final next = await client.builder.generate(
          draft.draftId,
          previousMutation,
          request,
          startFromScratch: widget.startFromScratch,
        );
        acceptRequest(next, request);
      } catch (issue) {
        // A response can be lost after the server accepts the request. Read the
        // durable job before offering another write, including on the next send.
        try {
          final recovered = await client.builder.get(draft.draftId);
          if (!mounted || recoverAcceptedRequest(recovered)) return;
          update(recovered);
          uncertainGeneration = null;
        } catch (_) {
          // Keep the uncertain submission until a later read succeeds.
        }
        rethrow;
      }
    });
  }

  bool recoverAcceptedRequest(BuilderSnapshot next) {
    final uncertain = uncertainGeneration;
    if (uncertain == null ||
        next.mutation <= uncertain.mutation ||
        next.latestRequest != uncertain.request ||
        next.jobId == null ||
        next.jobId == uncertain.jobId) {
      return false;
    }
    acceptRequest(next, uncertain.request);
    return true;
  }

  void acceptRequest(BuilderSnapshot next, String request) {
    if (!mounted) return;
    setState(() {
      uncertainGeneration = null;
      conversation.add(BuilderMessage(text: request, fromUser: true));
      lastRequest = request;
      guidanceQuestions = null;
      if (prompt.text.trim() == request) prompt.clear();
    });
    update(next, acceptedRequest: true);
    scrollConversation();
  }

  Future<void> shapeIdea() async {
    final request = prompt.text.trim();
    if (busy || assessing || generating || request.isEmpty || ai != true) {
      return;
    }
    setState(() => assessing = true);
    try {
      if (!await finishVisualEdit() || !mounted) return;
      final contextId = currentGuidanceContext();
      try {
        final questions = canAssessIdea(request)
            ? cleanGuidanceQuestions(
                await client.builder.suggestQuestions(
                  request,
                  null,
                  draft.draftId,
                ),
              )
            : null;
        if (!mounted ||
            currentGuidanceContext() != contextId ||
            prompt.text.trim() != request) {
          return;
        }
        showGuidance(
          questions == null || questions.isEmpty
              ? builtInEditGuidanceQuestions
              : questions,
          request,
          contextId,
          fallback: questions == null,
          notice: questions?.isEmpty == true
              ? 'Your idea is ready. Add optional details or send it now.'
              : questions == null
              ? 'Try these built-in questions.'
              : null,
        );
      } catch (issue) {
        if (!mounted ||
            currentGuidanceContext() != contextId ||
            prompt.text.trim() != request) {
          return;
        }
        if (!canOfferBuiltInGuidance(issue)) {
          setState(() => error = issue);
          return;
        }
        showGuidance(
          builtInEditGuidanceQuestions,
          request,
          contextId,
          fallback: true,
          notice: 'AI questions are unavailable. Add details or continue with your original idea.',
        );
      }
    } finally {
      if (mounted) setState(() => assessing = false);
    }
  }

  Future<void> keepPreviousPreview() async {
    final jobId = draft.jobId;
    if (jobId == null || !hasPreview || draft.stage != 'failed') return;
    await perform(() async {
      update(
        await client.builder.abandonFailedEdit(
          draft.draftId,
          draft.mutation,
          jobId,
        ),
      );
      conversation.add(
        const BuilderMessage(
          text: 'Your last working preview is ready to customize or use.',
        ),
      );
    });
  }

  @override
  void dispose() {
    inspectorRevision.dispose();
    visualSession?.dispose();
    previewController.dispose();
    timer?.cancel();
    preview.dispose();
    prompt.dispose();
    conversationScroll.dispose();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> manual() async {
    if (!await finishVisualEdit() || !mounted) return;
    final label = TextEditingController(), choice = TextEditingController();
    var type = 'RenameLabel',
        target = 'app',
        collection = preview.spec.collections.firstOrNull?.id ?? '',
        fieldType = 'text';
    final route = DialogRoute<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Make a small edit'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    value: type,
                    items:
                        {
                              'RenameLabel': 'Rename app or field',
                              if (preview.spec.collections.isNotEmpty)
                                'AddField': 'Add a field',
                              if (preview.spec.collections.any(
                                (c) => c.fields.any(
                                  (f) => f.type == FieldType.choice,
                                ),
                              ))
                                'AddChoice': 'Add a category or choice',
                              if (preview.spec.views.length > 1)
                                'ReorderView': 'Move last section to top',
                            }.entries
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => set(() {
                      type = v!;
                      target = 'app';
                      if (type == 'AddChoice') {
                        final choiceCollection = preview.spec.collections
                            .firstWhere(
                              (c) => c.fields.any(
                                (f) => f.type == FieldType.choice,
                              ),
                            );
                        collection = choiceCollection.id;
                        target = choiceCollection.fields
                            .firstWhere((f) => f.type == FieldType.choice)
                            .id;
                      }
                    }),
                  ),
                  if (type == 'RenameLabel')
                    DropdownButtonFormField<String>(
                      initialValue: target,
                      items: [
                        const DropdownMenuItem(
                          value: 'app',
                          child: Text('App name'),
                        ),
                        ...preview.spec.collections.expand(
                          (c) => c.fields.map(
                            (f) => DropdownMenuItem(
                              value: f.id,
                              child: Text(f.label),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => target = v!,
                    ),
                  if (type == 'AddField' || type == 'AddChoice')
                    DropdownButton<String>(
                      value: collection,
                      items: preview.spec.collections
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => set(() => collection = v!),
                    ),
                  if (type == 'AddField')
                    DropdownButton<String>(
                      value: fieldType,
                      items: FieldType.values
                          .map(
                            (t) => DropdownMenuItem(
                              value: t.name,
                              child: Text(t.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => set(() => fieldType = v!),
                    ),
                  if (type == 'AddChoice')
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Choice field',
                      ),
                      items: preview.spec
                          .collection(collection)
                          .fields
                          .where((f) => f.type == FieldType.choice)
                          .map(
                            (f) => DropdownMenuItem(
                              value: f.id,
                              child: Text(f.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => target = v!,
                    ),
                  if (type != 'ReorderView')
                    TextField(
                      controller: label,
                      decoration: InputDecoration(
                        labelText: type == 'AddChoice' ? 'New choice' : 'Label',
                      ),
                    ),
                  if (type == 'AddField' && fieldType == 'choice')
                    TextField(
                      controller: choice,
                      decoration: const InputDecoration(
                        labelText: 'Choices, separated by commas',
                      ),
                    ),
                  if (type == 'ReorderView')
                    const Text(
                      'Move the last view to the first position. Existing view IDs stay unchanged.',
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, switch (type) {
                  'RenameLabel' => {
                    'type': type,
                    'targetId': target,
                    'label': label.text,
                  },
                  'AddField' => {
                    'type': type,
                    'collectionId': collection,
                    'viewIds': [
                      for (final view in preview.spec.views)
                        if (view.collectionId == collection &&
                            {'form', 'details'}.contains(view.type))
                          view.id,
                    ],
                    'field': {
                      'label': label.text,
                      'type': fieldType,
                      'required': false,
                      if (fieldType == 'choice')
                        'choices': choice.text
                            .split(',')
                            .map((x) => x.trim())
                            .toList(),
                    },
                  },
                  'AddChoice' => {
                    'type': type,
                    'collectionId': collection,
                    'fieldId': target,
                    'choice': label.text,
                  },
                  _ => {
                    'type': 'ReorderView',
                    'viewIds': [
                      preview.spec.views.last.id,
                      ...preview.spec.views
                          .take(preview.spec.views.length - 1)
                          .map((v) => v.id),
                    ],
                  },
                });
              },
              child: const Text('Update preview'),
            ),
          ],
        ),
      ),
    );
    final patch = await Navigator.of(context, rootNavigator: true).push(route);
    // Dialog results arrive before the closing animation releases TextFields.
    await route.completed;
    label.dispose();
    choice.dispose();
    if (patch != null && mounted) {
      await perform(
        () async => update(
          await client.builder.patch(
            draft.draftId,
            draft.mutation,
            jsonEncode(patch),
          ),
        ),
      );
    }
  }

  Future<void> publish() async {
    if (!canPublish) return;
    setState(() => _reviewing = true);
    try {
      await _reviewAndPublish();
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Future<void> _reviewAndPublish() async {
    if (!await finishVisualEdit()) return;
    final reviewed = draft;
    final reviewedSpec = AppSpec.parse(reviewed.candidateJson);
    final selectedRules = {...enabled};
    final scope = <int>{};
    final candidates = <RuntimeRecord>[];
    if (reviewed.baseVersionId != null &&
        reviewedSpec.automationRequests.isNotEmpty) {
      try {
        final collections = reviewedSpec.automationRequests
            .map((r) => r.collectionId)
            .toSet();
        for (final collection in collections) {
          candidates.addAll(
            (await client.runtime.query(
              reviewed.appId,
              collection,
              jsonEncode({'limit': 50}),
            )).records,
          );
        }
      } catch (e) {
        if (mounted) setState(() => error = e);
        return;
      }
    }
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setReview) => AlertDialog(
          title: Text(
            reviewed.baseVersionId == null
                ? 'Ready to use your app?'
                : 'Review your changes',
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...describeChanges(reviewed).map((c) => Text('• $c')),
                  if (requestedDeviceCapabilities(reviewedSpec).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Mobile features'),
                    for (final capability in requestedDeviceCapabilities(
                      reviewedSpec,
                    ))
                      Text('• ${deviceCapabilityLabels[capability]}'),
                    const Text(
                      'Publishing does not enable device access. Each person chooses access on their phone. Device values stay local.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(switch (reviewedSpec.policyPresetRequest) {
                    'personalTracker.v1' => 'Personal app · You manage its records. Shared members can view them.',
                    'groupWorkflow.v1' => 'Shared workflow · Members can create and update records and use approved actions.',
                    _ => 'Shared sign-ups · Members can claim and release their own places.',
                  }),
                  const SizedBox(height: 16),
                  Text(
                    'Reminders',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (reviewedSpec.automationRequests.isEmpty)
                    const Text('No reminders requested by this app.'),
                  for (final rule in reviewedSpec.automationRequests)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(reminderName(rule.id)),
                      subtitle: Text(reminderDescription(rule, reviewedSpec)),
                      value: selectedRules.contains(rule.id),
                      onChanged: (value) => setReview(() {
                        if (value == true) {
                          selectedRules.add(rule.id);
                        } else {
                          selectedRules.remove(rule.id);
                        }
                        final collections = reviewedSpec.automationRequests
                            .where((r) => selectedRules.contains(r.id))
                            .map((r) => r.collectionId)
                            .toSet();
                        scope.removeWhere(
                          (id) => !candidates.any(
                            (r) =>
                                r.id == id &&
                                collections.contains(r.collectionId),
                          ),
                        );
                      }),
                    ),
                  const Text(
                    'Existing records are preserved. Unchanged, enabled reminders retain their schedules. New or changed rules enroll only new records and the records you explicitly select below.',
                  ),
                  if (candidates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Optional: enroll existing records (up to 50 per collection shown). This may create a reminder immediately if its due time has passed.',
                    ),
                    for (final record in candidates.where(
                      (record) => reviewedSpec.automationRequests.any(
                        (rule) =>
                            selectedRules.contains(rule.id) &&
                            rule.collectionId == record.collectionId,
                      ),
                    ))
                      CheckboxListTile(
                        value: scope.contains(record.id),
                        title: Text(
                          '#${record.id} · ${(record.data as Map).values.firstOrNull ?? record.collectionId}',
                        ),
                        onChanged: (v) => setReview(() {
                          if (v == true) {
                            scope.add(record.id);
                          } else {
                            scope.remove(record.id);
                          }
                        }),
                      ),
                  ],
                  const Text(
                    'This publishes structure only. Synthetic preview records are never copied.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back to preview'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                reviewed.baseVersionId == null ? 'Use app' : 'Apply changes',
              ),
            ),
          ],
        ),
      ),
    );
    if (yes != true) return;
    if (draft.candidateHash != reviewed.candidateHash ||
        draft.mutation != reviewed.mutation) {
      setState(
        () => error = 'The preview changed during review. Review the updated preview before publishing.',
      );
      return;
    }
    final rules = selectedRules.toList()..sort();
    enabled
      ..clear()
      ..addAll(rules);
    await perform(() async {
      await client.builder.publish(
        PublishRequest(
          draftId: reviewed.draftId,
          candidateHash: reviewed.candidateHash,
          expectedCurrentVersionId: reviewed.baseVersionId,
          enabledRuleIds: rules,
          activateExistingRecordIds: scope.toList()..sort(),
          reviewHash: hashJson({
            'candidateHash': reviewed.candidateHash,
            'enabledRuleIds': rules,
            'activateExistingRecordIds': scope.toList()..sort(),
          }),
          idempotencyKey:
              'publish-${reviewed.draftId}-${hashJson({'candidateHash': reviewed.candidateHash, 'enabledRuleIds': rules, 'activateExistingRecordIds': scope.toList()..sort()})}',
        ),
      );
      if (mounted) {
        if (widget.onPublished != null) {
          await widget.onPublished!(reviewed.appId);
        } else {
          Navigator.pop(context, reviewed.appId);
        }
      }
    });
  }

  String? get errorMessage {
    final issue = error ?? platformError;
    if (issue == null) return null;
    if (issue is NestError) return issue.message;
    if (issue is String) return issue;
    return 'Couldn’t connect to AppNest. Your request is still here. Check your connection and try again.';
  }

  Future<void> editPages() async {
    if (!await finishVisualEdit() || !mounted) return;
    final patch = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => PageEditor(
        spec: preview.spec,
        uploadImage: uploadDraftImage,
        preview: preview,
        location: previewController.location,
      ),
    );
    if (patch != null && mounted) {
      await perform(
        () async => update(
          await client.builder.patch(
            draft.draftId,
            draft.mutation,
            jsonEncode(patch),
          ),
        ),
      );
    }
  }

  Future<void> editReminder(AutomationSpec rule) async {
    if (!await finishVisualEdit() || !mounted) return;
    final patch = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ReminderEditor(spec: preview.spec, rule: rule),
    );
    if (patch != null && mounted) {
      await perform(
        () async => update(
          await client.builder.patch(
            draft.draftId,
            draft.mutation,
            jsonEncode(patch),
          ),
        ),
      );
    }
  }

  Future<void> openCustomize() async {
    if (!await finishVisualEdit() || !mounted) return;
    if (MediaQuery.sizeOf(context).width >= 850) {
      setState(() => customizing = !customizing);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .76,
          child: customizationPanel(
            onChoose: (action) {
              Navigator.pop(sheetContext);
              action();
            },
            onClose: () => Navigator.pop(sheetContext),
          ),
        ),
      ),
    );
  }

  Widget customizationPanel({
    void Function(VoidCallback action)? onChoose,
    VoidCallback? onClose,
  }) {
    void choose(VoidCallback action) {
      if (onChoose != null) {
        onChoose(action);
      } else {
        action();
      }
    }

    return Material(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Customize',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Back to chat',
                onPressed: onClose ?? () => setState(() => customizing = false),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Text('Make this app feel and work the way you like.'),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance'),
            subtitle: const Text('Colors, typography, spacing, and corners'),
            onTap: () => choose(
              () => selectVisualTarget(
                const MiniAppEditTarget(MiniAppEditKind.app, 'app'),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Content'),
            subtitle: const Text('App name, fields, categories, and labels'),
            onTap: () => choose(manual),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: const Text('Layout'),
            subtitle: const Text('Pages, sections, navigation, and components'),
            onTap: () => choose(editPages),
          ),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Mobile features'),
            subtitle: const Text('Device information and phone controls'),
            onTap: () => choose(editPages),
          ),
          for (final view in preview.spec.views.where(
            (v) => v.type == 'deviceInfo' || v.type == 'deviceControl',
          ))
            ListTile(
              title: Text(view.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => choose(
                () => selectVisualTarget(
                  MiniAppEditTarget(MiniAppEditKind.section, view.id),
                ),
              ),
            ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Behavior'),
            subtitle: const Text('Reminder timing, clocks, and focus sessions'),
          ),
          for (final rule in preview.spec.automationRequests)
            ListTile(
              title: Text(reminderName(rule.id)),
              subtitle: Text(reminderDescription(rule, preview.spec)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => choose(() => editReminder(rule)),
            ),
          for (final view in preview.spec.views.where(
            (v) => v.type == 'clock' || v.type == 'timer',
          ))
            ListTile(
              title: Text(view.label),
              subtitle: Text(
                view.type == 'clock'
                    ? 'Clock display and time format'
                    : 'Default focus duration',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => choose(
                () => selectVisualTarget(
                  MiniAppEditTarget(MiniAppEditKind.section, view.id),
                ),
              ),
            ),
          if (preview.spec.automationRequests.isEmpty &&
              !preview.spec.views.any(
                (v) => v.type == 'clock' || v.type == 'timer',
              ))
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Ask AppNest to add a reminder or add a clock or focus timer in Layout.',
              ),
            ),
          if (preview.spec.automationRequests.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Choose which reminders to enable when you review your app.',
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => choose(
              () => selectVisualTarget(
                const MiniAppEditTarget(MiniAppEditKind.app, 'app'),
              ),
            ),
            icon: const Icon(Icons.ads_click),
            label: const Text('Edit directly on preview'),
          ),
        ],
      ),
    );
  }

  Widget chat() {
    return BuilderChat(
      messages: conversation,
      scrollController: conversationScroll,
      controller: prompt,
      stage: draft.stage,
      generating: generating,
      busy: busy || assessing,
      assessing: assessing,
      aiAvailable: ai,
      hasPreview: hasPreview,
      error: errorMessage,
      diagnostics: draft.diagnostics,
      onSend: send,
      onShapeIdea: shapeIdea,
      onKeepPreview: hasPreview && draft.stage == 'failed'
          ? keepPreviousPreview
          : null,
      jobAttempts: draft.jobAttempts,
      jobCreatedAt: draft.jobCreatedAt,
      guidanceQuestions: guidanceQuestions,
      guidancePanelKey: guidancePanelKey,
      guidanceSource: guidanceSource,
      guidanceContextId: guidanceContextId,
      guidanceFallback: guidanceFallback,
      guidanceNotice: guidanceNotice,
      guidanceContext: currentGuidanceContext,
      onUseGuidanceAnswers: (combined) {
        setState(() {
          guidanceQuestions = null;
        });
        prompt.value = TextEditingValue(
          text: combined,
          selection: TextSelection.collapsed(offset: combined.length),
        );
      },
      onContinueOriginal: () {
        setState(() {
          guidanceQuestions = null;
        });
        unawaited(send());
      },
      onEditIdea: () => setState(() => guidanceQuestions = null),
      onRetry:
          !generating &&
              draft.stage != 'stale' &&
              ai == true &&
              lastRequest != null
          ? () => send(retry: lastRequest)
          : null,
      onReconnect: () async {
        await loadPlatform();
        await poll();
      },
    );
  }

  String reminderName(String id) {
    final rule = preview.spec.automationRequests.firstWhere((r) => r.id == id);
    final collection = preview.spec.collection(rule.collectionId);
    return '${collection.label} · ${collection.field(rule.fieldId).label}';
  }

  List<String> describeChanges(BuilderSnapshot snapshot) {
    final spec = AppSpec.parse(snapshot.candidateJson);
    if (snapshot.baseVersionId == null) {
      return [
        'Create ${spec.name}',
        if (spec.collections.isNotEmpty)
          'Track ${spec.collections.map((collection) => collection.label).join(', ')}',
        if (spec.navigation != null)
          'Pages: ${spec.navigation!.pages.map((page) => page.title).join(', ')}'
        else
          'Views: ${spec.views.map((view) => view.label).join(', ')}',
        if (spec.automationRequests.isNotEmpty)
          '${spec.automationRequests.length} ${spec.automationRequests.length == 1 ? 'reminder' : 'reminders'} available for your approval',
      ];
    }
    return {
      for (final change in snapshot.changes)
        change.startsWith('Request capability:')
            ? 'Update supported app features'
            : change,
    }.toList();
  }

  String reminderDescription(AutomationSpec rule, AppSpec spec) {
    final recipient = switch (rule.effect) {
      'notifyOwner' => 'App owner',
      'notifyAssignee' => 'Assigned member',
      _ => 'Members with an active place',
    };
    final seconds = rule.offsetSeconds;
    final timing = seconds == 0
        ? 'At the selected time'
        : seconds % 60 == 0
        ? '${seconds ~/ 60} minutes before'
        : '$seconds seconds before';
    final condition = rule.condition;
    final when = condition == null
        ? ''
        : ' · When ${spec.collection(rule.collectionId).field(condition.fieldId).label} is ${condition.value}';
    return '$recipient · $timing · In-app only$when';
  }

  Future<bool> flushVisualEdit() async {
    final session = visualSession;
    if (session == null || await session.flush()) return true;
    if (!mounted) return false;
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your changes haven’t saved'),
        content: Text(session.status),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep editing'),
          ),
          if (!session.conflict && session.validationError == null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'retry'),
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard local changes'),
          ),
        ],
      ),
    );
    if (decision == 'retry') return session.flush(retry: true);
    if (decision == 'discard') return reloadVisualEdit();
    return false;
  }

  Future<bool> reloadVisualEdit() async {
    try {
      final latest = await visualSession!.reload();
      if (!mounted) return false;
      update(latest);
      if (!canEdit) return await finishVisualEdit();
      setState(() {
        visualTarget = const MiniAppEditTarget(MiniAppEditKind.app, 'app');
        inspectorReset++;
      });
      inspectorRevision.value++;
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Couldn’t reload the draft. Your local edits are still here.',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> finishVisualEdit() async {
    if (!await flushVisualEdit() || !mounted) return false;
    final sheet = inspectorSheet;
    inspectorSheet = null;
    if (sheet != null && sheet.mounted) Navigator.of(sheet).pop();
    setState(() {
      visualEditing = false;
      visualTarget = null;
    });
    visualSession?.dispose();
    visualSession = null;
    return true;
  }

  Future<void> closeMobileInspector() async {
    if (!await flushVisualEdit() || !mounted) return;
    final sheet = inspectorSheet;
    inspectorSheet = null;
    if (sheet != null && sheet.mounted) Navigator.of(sheet).pop();
  }

  Future<void> selectVisualTarget(MiniAppEditTarget target) async {
    if (changingTarget || !canEdit) return;
    changingTarget = true;
    try {
      if (!await flushVisualEdit() || !mounted) return;
      if (!canEdit) return;
      // An explicit reload can remove the definition the user had clicked.
      try {
        switch (target.kind) {
          case MiniAppEditKind.app:
            break;
          case MiniAppEditKind.page:
            preview.spec.page(target.id);
          case MiniAppEditKind.section:
            preview.spec.view(target.id);
          case MiniAppEditKind.field:
            preview.spec.collection(target.collectionId!).field(target.id);
        }
        if (target.pageId != null) preview.spec.page(target.pageId!);
      } catch (_) {
        target = const MiniAppEditTarget(MiniAppEditKind.app, 'app');
      }
      if (!visualEditing) {
        if (!await previewController.canLeave() || !mounted) return;
        visualSession = VisualEditSession(
          snapshot: draft,
          read: () => client.builder.get(draft.draftId),
          write: (mutation, patch) =>
              client.builder.patch(draft.draftId, mutation, patch),
          onSaved: (next, _) => update(next),
        );
      }
      setState(() {
        visualEditing = true;
        visualTarget = target;
      });
      inspectorRevision.value++;
      if (MediaQuery.sizeOf(context).width < 850 && inspectorSheet == null) {
        unawaited(
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            isDismissible: false,
            enableDrag: false,
            constraints: const BoxConstraints(maxWidth: 640),
            builder: (sheetContext) {
              inspectorSheet = sheetContext;
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) closeMobileInspector();
                },
                child: SafeArea(
                  child: SizedBox(
                    height: MediaQuery.sizeOf(sheetContext).height * .8,
                    child: ListenableBuilder(
                      listenable: inspectorRevision,
                      builder: (_, _) => inspector(mobile: true),
                    ),
                  ),
                ),
              );
            },
          ).whenComplete(() => inspectorSheet = null),
        );
      }
    } finally {
      changingTarget = false;
    }
  }

  Widget inspector({bool mobile = false}) =>
      visualSession == null || visualTarget == null
      ? const SizedBox.shrink()
      : VisualInspector(
          key: ValueKey((visualTarget, inspectorReset)),
          target: visualTarget!,
          session: visualSession!,
          mobile: mobile,
          onClose: () => mobile ? closeMobileInspector() : finishVisualEdit(),
          onReload: () => reloadVisualEdit(),
          uploadImage: uploadDraftImage,
          preview: preview,
          location: previewController.location,
          onSelectTarget: selectVisualTarget,
        );

  Widget previewPane() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xffe2e5df))),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 500) {
              return Row(
                children: [
                  if (visualEditing)
                    IconButton(
                      tooltip: 'Done editing',
                      onPressed: canEdit ? finishVisualEdit : null,
                      icon: const Icon(Icons.check, size: 18),
                    )
                  else
                    TextButton.icon(
                      onPressed: canEdit
                          ? () => selectVisualTarget(
                              const MiniAppEditTarget(
                                MiniAppEditKind.app,
                                'app',
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.ads_click, size: 18),
                      label: const Text('Edit'),
                    ),
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('open-appearance'),
                      onPressed: canEdit
                          ? () => selectVisualTarget(
                              const MiniAppEditTarget(
                                MiniAppEditKind.app,
                                'app',
                              ),
                            )
                          : null,
                      child: const Text('Appearance'),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Preview options',
                    onSelected: (value) => setState(() {
                      if (value == 'desktop') mobilePreview = false;
                      if (value == 'mobile') mobilePreview = true;
                      if (value == 'reset') {
                        preview.dispose();
                        preview = newPreview(
                          AppSpec.parse(draft.candidateJson),
                        );
                      }
                    }),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'desktop',
                        child: Text('Desktop preview'),
                      ),
                      const PopupMenuItem(
                        value: 'mobile',
                        child: Text('Mobile preview'),
                      ),
                      if (hasPreview)
                        PopupMenuItem(
                          value: 'reset',
                          enabled: !busy && !visualEditing,
                          child: const Text('Reset sample data'),
                        ),
                    ],
                  ),
                ],
              );
            }
            return Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: canEdit
                          ? () => visualEditing
                                ? finishVisualEdit()
                                : selectVisualTarget(
                                    const MiniAppEditTarget(
                                      MiniAppEditKind.app,
                                      'app',
                                    ),
                                  )
                          : null,
                      icon: Icon(
                        visualEditing ? Icons.check : Icons.ads_click,
                        size: 18,
                      ),
                      label: Text(visualEditing ? 'Done editing' : 'Edit'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('open-appearance'),
                      onPressed: canEdit
                          ? () => selectVisualTarget(
                              const MiniAppEditTarget(
                                MiniAppEditKind.app,
                                'app',
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: const Text('Appearance'),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Desktop preview',
                      isSelected: !mobilePreview,
                      onPressed: () => setState(() => mobilePreview = false),
                      icon: const Icon(
                        Icons.desktop_windows_outlined,
                        size: 20,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mobile preview',
                      isSelected: mobilePreview,
                      onPressed: () => setState(() => mobilePreview = true),
                      icon: const Icon(Icons.smartphone_outlined, size: 20),
                    ),
                    if (hasPreview)
                      IconButton(
                        tooltip: 'Reset sample data',
                        onPressed: busy || visualEditing
                            ? null
                            : () => setState(() {
                                preview.dispose();
                                preview = newPreview(
                                  AppSpec.parse(draft.candidateJson),
                                );
                              }),
                        icon: const Icon(Icons.refresh, size: 20),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      Expanded(
        child: hasPreview
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final inset = constraints.maxWidth > 600 ? 24.0 : 10.0;
                  return Container(
                    color: const Color(0xffe9ede7),
                    padding: EdgeInsets.all(inset),
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: mobilePreview ? 390 : double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          mobilePreview ? 24 : 12,
                        ),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(color: Colors.white),
                          child: MiniAppRuntime(
                            key: ObjectKey(preview),
                            adapter: preview,
                            controller: previewController,
                            editConfiguration: visualEditing
                                ? MiniAppEditConfiguration(
                                    selected: visualTarget,
                                    onSelect: selectVisualTarget,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              )
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 390),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: const BoxDecoration(
                            color: Color(0xffe2eeea),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            generating
                                ? Icons.auto_awesome_outlined
                                : Icons.edit_note,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          generating
                              ? 'Your app is taking shape'
                              : 'Let’s shape your first preview',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          generating
                              ? 'Your interactive preview will appear here when it’s ready. Then you can try it and keep building together.'
                              : 'Send a description in the chat to build your app. A ready preview will appear here.',
                          textAlign: TextAlign.center,
                        ),
                        if (generating) ...[
                          const SizedBox(height: 32),
                          const LinearProgressIndicator(minHeight: 3),
                          const SizedBox(height: 12),
                          Text(builderStageLabel(draft.stage)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
      if (hasPreview)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            generating
                ? 'Building your changes · Showing your last ready preview'
                : visualEditing
                ? 'Click a heading, section or field to edit · Autosaved to draft'
                : 'Interactive preview · Sample data · Only published changes reach your app',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop || !visualEditing,
    onPopInvokedWithResult: (didPop, _) async {
      // Declarative draft routes own the back operation and consult canLeave.
      if (widget.onClose != null) return;
      if (!didPop && await finishVisualEdit() && mounted) {
        setState(() => allowPop = true);
        if (context.mounted) Navigator.of(context).pop();
      }
    },
    child: Scaffold(
      // The inspector sheet scrolls around the keyboard itself. Keep the
      // underlying preview at full height while that keyboard is open.
      resizeToAvoidBottomInset: !visualEditing,
      appBar: AppBar(
        leading: widget.onClose == null
            ? null
            : BackButton(
                onPressed: () async {
                  if (await canLeave() && mounted) await widget.onClose!();
                },
              ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: canEdit
                  ? () => selectVisualTarget(
                      const MiniAppEditTarget(MiniAppEditKind.app, 'app'),
                    )
                  : null,
              child: Text(
                hasPreview ? preview.spec.name : 'New app',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              draft.stage == 'preview ready'
                  ? 'Unpublished changes'
                  : builderStageLabel(draft.stage),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (MediaQuery.sizeOf(context).width < 600)
            IconButton(
              key: const ValueKey('customize-app'),
              tooltip: 'Customize',
              onPressed: canEdit ? openCustomize : null,
              icon: const Icon(Icons.tune_outlined),
            )
          else
            TextButton.icon(
              key: const ValueKey('customize-app'),
              onPressed: canEdit ? openCustomize : null,
              icon: const Icon(Icons.tune_outlined, size: 18),
              label: const Text('Customize'),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: canPublish ? publish : null,
              child: Text(
                draft.baseVersionId == null ? 'Use app' : 'Apply changes',
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 850) {
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Chat'),
                      Tab(text: 'Try'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(children: [chat(), previewPane()]),
                  ),
                ],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: constraints.maxWidth < 1100 ? 330 : 380,
                child: visualEditing
                    ? inspector()
                    : customizing
                    ? customizationPanel()
                    : chat(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: previewPane()),
            ],
          );
        },
      ),
    ),
  );

  Future<bool> canLeave() => finishVisualEdit();
}
