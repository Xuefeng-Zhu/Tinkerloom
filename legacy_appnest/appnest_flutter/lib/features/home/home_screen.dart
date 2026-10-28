import 'dart:async';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

import '../../client.dart';
import '../builder/idea_guidance.dart';
import '../builder/builder_screen.dart';
import '../mini_app/mini_app_screen.dart';
import 'home_load_failure.dart';
import 'template_preview.dart';

class HomeScreen extends StatefulWidget {
  final Future<void> Function(int appId, {int? recordId})? onOpenApp;
  final Future<void> Function(int appId)? onResumeDraft;
  final int refreshToken;
  const HomeScreen({
    super.key,
    this.onOpenApp,
    this.onResumeDraft,
    this.refreshToken = 0,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<WorkspaceInfo> workspaces = [];
  List<AppManifest> apps = [];
  List<TemplateInfo> templates = [];
  List<InboxItem> inbox = [];
  int? workspaceId;
  int page = 0;
  bool loading = true;
  bool creating = false;
  bool showComposer = false;
  Object? error;
  PlatformInfo? platform;
  final prompt = TextEditingController();
  final guidancePanelKey = GlobalKey();
  List<GuidanceQuestion>? guidanceQuestions;
  String? guidanceSource;
  int? guidanceWorkspace;
  bool guidanceFallback = false;
  String? guidanceNotice;
  ({int workspaceId, BuilderSnapshot draft, String request})? pendingCreation;
  final unfinishedCreations =
      <int, ({int workspaceId, BuilderSnapshot draft})>{};
  bool invitationHandled = false;
  int loadGeneration = 0;
  int inboxGeneration = 0;
  bool inboxRefreshing = false;
  bool inboxRefreshQueued = false;
  Object? inboxError;
  Timer? inboxTimer;
  Future<List<InboxItem>>? inboxRequest;
  bool foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool get inboxVisible =>
      mounted &&
      foreground &&
      page == 2 &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  void updateInboxPolling() {
    inboxTimer?.cancel();
    inboxTimer = null;
    if (inboxVisible && !loading && error == null) {
      inboxTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (inboxVisible && !inboxRefreshing) refreshInbox();
      });
    }
  }

  void selectPage(int value) {
    setState(() {
      page = value;
      inboxGeneration++;
    });
    updateInboxPolling();
    if (value == 2) refreshInbox();
  }

  /// Serialize reads with full launcher reloads as well as Inbox refreshes.
  /// A reload waits for an obsolete read and then makes its own fresh request.
  Future<List<InboxItem>> readInbox(int launcherGeneration) async {
    while (inboxRequest != null) {
      try {
        await inboxRequest;
      } catch (_) {
        // The original caller handles its error; this caller performs a new
        // authenticated read rather than accepting the obsolete response.
      }
    }
    if (!mounted || launcherGeneration != loadGeneration) {
      throw StateError('Obsolete launcher read');
    }
    final request = client.runtime.inbox();
    inboxRequest = request;
    try {
      return await request;
    } finally {
      if (identical(inboxRequest, request)) inboxRequest = null;
    }
  }

  Future<void> refreshInbox() async {
    if (!inboxVisible || loading || error != null) return;
    if (inboxRefreshing) {
      inboxRefreshQueued = true;
      return;
    }
    final generation = ++inboxGeneration;
    final launcherGeneration = loadGeneration;
    setState(() => inboxRefreshing = true);
    try {
      final items = await readInbox(launcherGeneration);
      if (!inboxVisible ||
          generation != inboxGeneration ||
          launcherGeneration != loadGeneration) {
        return;
      }
      setState(() {
        inbox = items;
        inboxError = null;
      });
    } catch (e) {
      if (mounted &&
          generation == inboxGeneration &&
          launcherGeneration == loadGeneration) {
        setState(() {
          // A failed authorization check must not retain private Inbox data.
          inbox = [];
          inboxError = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() => inboxRefreshing = false);
        final queued = inboxRefreshQueued;
        inboxRefreshQueued = false;
        if (queued && inboxVisible && !loading) refreshInbox();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    prompt.addListener(onPromptChanged);
    load();
  }

  void onPromptChanged() {
    if (guidanceQuestions != null && prompt.text.trim() != guidanceSource) {
      setState(() => guidanceQuestions = null);
    }
  }

  void showGuidance(
    List<GuidanceQuestion> questions,
    String source,
    int selectedWorkspace, {
    required bool fallback,
    String? notice,
  }) {
    setState(() {
      guidanceQuestions = questions;
      guidanceSource = source;
      guidanceWorkspace = selectedWorkspace;
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

  @override
  void dispose() {
    inboxGeneration++;
    loadGeneration++;
    inboxTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    prompt.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only retry reads. Never replay a business command on reconnect/resume.
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) inboxGeneration++;
    updateInboxPolling();
    if (foreground && !loading) {
      if (error != null) {
        load();
      } else if (page == 2) {
        refreshInbox();
      }
    }
  }

  Future<void> load() async {
    if (!mounted) return;
    final generation = ++loadGeneration;
    inboxGeneration++;
    inboxRefreshQueued = false;
    final requestedWorkspace = workspaceId;
    setState(() => loading = true);
    updateInboxPolling();
    try {
      final ws = await client.apps.workspaces(),
          p = await client.builder.platform();
      if (!mounted || generation != loadGeneration) return;
      final selectedWorkspace = ws.any((w) => w.id == requestedWorkspace)
          ? requestedWorkspace!
          : ws.first.id;
      final results = await Future.wait<dynamic>([
        client.apps.list(selectedWorkspace),
        client.apps.templates(),
        readInbox(generation),
      ]);
      if (!mounted || generation != loadGeneration) return;
      if (mounted) {
        setState(() {
          if (workspaceId != selectedWorkspace) {
            guidanceQuestions = null;
          }
          workspaceId = selectedWorkspace;
          workspaces = ws;
          platform = p;
          apps = results[0] as List<AppManifest>;
          templates = results[1] as List<TemplateInfo>;
          inbox = results[2] as List<InboxItem>;
          inboxError = null;
          loading = false;
          error = null;
        });
      }
      final token = Uri.base.queryParameters['invite'];
      if (token != null && !invitationHandled && mounted) {
        invitationHandled = true;
        await join(token);
      }
    } catch (e) {
      if (mounted && generation == loadGeneration) {
        setState(() {
          // Do not leave private launcher/inbox content cached after a failed
          // authorization or refresh. The next load rechecks every endpoint.
          workspaces = [];
          apps = [];
          inbox = [];
          templates = [];
          platform = null;
          error = e;
          loading = false;
        });
      }
    }
    if (mounted && generation == loadGeneration) updateInboxPolling();
  }

  Future<void> open(int id, {int? recordId}) async {
    if (widget.onOpenApp != null) {
      await widget.onOpenApp!(id, recordId: recordId);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MiniAppScreen(appId: id, initialRecordId: recordId),
      ),
    );
    load();
  }

  Future<void> shapeIdea() async {
    final request = prompt.text.trim();
    final selectedWorkspace = workspaceId;
    if (creating || selectedWorkspace == null || request.isEmpty) return;
    setState(() => creating = true);
    try {
      final questions = canAssessIdea(request)
          ? cleanGuidanceQuestions(
              await client.builder.suggestQuestions(
                request,
                selectedWorkspace,
                null,
              ),
            )
          : null;
      if (!mounted ||
          workspaceId != selectedWorkspace ||
          prompt.text.trim() != request) {
        return;
      }
      showGuidance(
        questions == null || questions.isEmpty
            ? builtInGuidanceQuestions
            : questions,
        request,
        selectedWorkspace,
        fallback: questions == null,
        notice: questions?.isEmpty == true
            ? 'Your idea is ready to build. Add optional details or create it now.'
            : questions == null
            ? 'Try these built-in questions.'
            : null,
      );
    } catch (e) {
      if (!mounted ||
          workspaceId != selectedWorkspace ||
          prompt.text.trim() != request) {
        return;
      }
      if (!canOfferBuiltInGuidance(e)) {
        showError(e);
      } else {
        showGuidance(
          builtInGuidanceQuestions,
          request,
          selectedWorkspace,
          fallback: true,
          notice: 'AI questions are unavailable. Add details or continue with your original idea.',
        );
      }
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> builder(String templateKey, {bool generate = false}) async {
    final request = prompt.text.trim();
    if (creating || workspaceId == null) return;
    if (generate && (platform?.aiAvailable != true || request.isEmpty)) return;
    final selectedWorkspace = workspaceId!;
    setState(() {
      creating = true;
      if (generate) showComposer = true;
    });
    try {
      final pending = pendingCreation;
      BuilderSnapshot? d;
      var submittedRequest = request;
      var alreadyAccepted = false;
      if (generate &&
          pending != null &&
          pending.workspaceId == selectedWorkspace) {
        d = await client.builder.get(pending.draft.draftId);
        // A lost response may hide a successful enqueue. Recover that request
        // instead of creating another app or submitting the same idea twice.
        alreadyAccepted =
            d.jobId != null &&
            d.jobId != pending.draft.jobId &&
            d.mutation > pending.draft.mutation &&
            d.latestRequest == pending.request;
        if (alreadyAccepted) submittedRequest = pending.request;
      }
      if (generate && !alreadyAccepted) {
        if (pending == null || pending.workspaceId != selectedWorkspace) {
          d = await client.builder.begin(selectedWorkspace, templateKey, null);
        }
      }
      if (!generate) {
        d = await client.builder.begin(selectedWorkspace, templateKey, null);
      }
      if (generate && !alreadyAccepted) {
        final startingDraft = d!;
        pendingCreation = (
          workspaceId: selectedWorkspace,
          draft: startingDraft,
          request: request,
        );
        d = await client.builder.generate(
          startingDraft.draftId,
          startingDraft.mutation,
          request,
          startFromScratch: true,
        );
      }
      if (mounted) {
        guidanceQuestions = null;
        pendingCreation = null;
        await visitBuilder(
          d!,
          selectedWorkspace,
          initialPrompt: generate ? submittedRequest : null,
          trackCreation: generate,
        );
      }
      load();
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> visitBuilder(
    BuilderSnapshot draft,
    int selectedWorkspace, {
    String? initialPrompt,
    required bool trackCreation,
  }) async {
    if (trackCreation) {
      unfinishedCreations[draft.draftId] = (
        workspaceId: selectedWorkspace,
        draft: draft,
      );
    }
    if (widget.onResumeDraft != null) {
      await widget.onResumeDraft!(draft.appId);
      return;
    }
    final published = await Navigator.push<int>(
      context,
      MaterialPageRoute<int>(
        builder: (_) => BuilderScreen(
          initial: draft,
          initialPrompt: initialPrompt,
          startFromScratch: trackCreation,
        ),
      ),
    );
    if (published != null) {
      unfinishedCreations.remove(draft.draftId);
      if (mounted) await open(published);
    }
  }

  Future<void> resumeAppDraft(AppManifest app) async {
    if (creating || app.workspaceId != workspaceId) return;
    if (widget.onResumeDraft != null) {
      await widget.onResumeDraft!(app.appId);
      return;
    }
    setState(() => creating = true);
    try {
      final draft = await client.builder.begin(
        app.workspaceId,
        'notes',
        app.appId,
      );
      if (!mounted) return;
      await visitBuilder(
        draft,
        app.workspaceId,
        initialPrompt: draft.latestRequest,
        trackCreation: draft.latestRequest != null,
      );
      await load();
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> previewTemplate(TemplateInfo template) async {
    final useTemplate = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => TemplatePreviewScreen(template: template),
      ),
    );
    if (mounted && useTemplate == true) await builder(template.key);
  }

  Future<void> resumeCreation(int draftId) async {
    final saved = unfinishedCreations[draftId];
    if (creating || saved == null || saved.workspaceId != workspaceId) return;
    setState(() => creating = true);
    try {
      // Refresh and authorize the existing draft before reopening it. Resuming
      // never submits generation or creates another placeholder app.
      final draft = await client.builder.get(draftId);
      if (!mounted) return;
      if (draft.publishedVersionId != null) {
        unfinishedCreations.remove(draftId);
        await open(draft.appId);
      } else if (draft.stage == 'stale') {
        unfinishedCreations.remove(draftId);
        showError(
          'This build was replaced. Open the published app or start a new app.',
        );
      } else {
        await visitBuilder(
          draft,
          saved.workspaceId,
          trackCreation: true,
        );
      }
      await load();
    } catch (e) {
      if (e is NestError &&
          {'notFound', 'forbidden', 'unauthorized'}.contains(e.category)) {
        unfinishedCreations.remove(draftId);
      }
      showError(e);
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  void showError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is NestError
                ? e.message
                : e is String
                ? e
                : 'Couldn’t connect to AppNest. Your idea is still here; try again when connected.',
          ),
        ),
      );
    }
  }

  Future<void> join(String token) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a shared app?'),
        content: const Text(
          'This opens the same app and shared records, using the role chosen by the inviter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Join app'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await open(await client.apps.acceptInvitation(token));
    } catch (e) {
      showError(e);
    }
  }

  Future<void> newWorkspace() async {
    final text = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New shared workspace'),
        content: TextField(
          controller: text,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    text.dispose();
    if (name != null) {
      try {
        final createdWorkspace = await client.apps.createWorkspace(name);
        if (!mounted) return;
        setState(() {
          workspaceId = createdWorkspace;
          guidanceQuestions = null;
        });
        load();
      } catch (e) {
        showError(e);
      }
    }
  }

  Widget workspacePicker() => DropdownButton<int>(
    isExpanded: true,
    value: workspaceId,
    underline: const SizedBox(),
    items: workspaces
        .map(
          (w) => DropdownMenuItem(
            value: w.id,
            child: Text(w.name, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: creating
        ? null
        : (v) {
            setState(() {
              workspaceId = v;
              guidanceQuestions = null;
            });
            load();
          },
  );
  Widget navigation(bool wide) => wide
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              child: Row(
                children: [
                  Icon(Icons.spa_outlined, size: 30),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AppNest',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: workspacePicker(),
            ),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  selected: page == i,
                  selectedTileColor: const Color(0xffe2eeea),
                  leading: Icon(
                    [
                      Icons.home_outlined,
                      Icons.grid_view_outlined,
                      Icons.inbox_outlined,
                    ][i],
                  ),
                  title: Text(['Home', 'Templates', 'Inbox'][i]),
                  onTap: () => selectPage(i),
                ),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: newWorkspace,
              icon: const Icon(Icons.add),
              label: const Text('New workspace'),
            ),
            accountMenu(),
          ],
        )
      : NavigationBar(
          selectedIndex: page,
          onDestinationSelected: selectPage,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              label: 'Templates',
            ),
            NavigationDestination(
              icon: Icon(Icons.inbox_outlined),
              label: 'Inbox',
            ),
          ],
        );
  Widget icon(String? definition, {double size = 48}) {
    final spec = definition == null ? null : AppSpec.parse(definition);
    const colors = {
      'amber': Color(0xffffe8ba),
      'sage': Color(0xffdcece2),
      'blue': Color(0xffdbeafa),
      'teal': Color(0xffdaeeea),
      'rose': Color(0xfff7dfdf),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors[spec?.theme] ?? colors['teal'],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        switch (spec?.icon) {
          'book' => Icons.menu_book_outlined,
          'board' => Icons.view_kanban_outlined,
          'check' => Icons.check_circle_outline,
          'people' => Icons.people_outline,
          _ => Icons.auto_awesome_outlined,
        },
        size: size * .5,
      ),
    );
  }

  Widget accountMenu({bool compact = false}) => PopupMenuButton<String>(
    tooltip: 'Your account',
    enabled: !creating,
    onSelected: (value) async {
      if (value == 'signout') await client.auth.signOutDevice();
      if (value == 'copy') {
        await Clipboard.setData(ClipboardData(text: platform?.actorId ?? ''));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account ID copied')),
          );
        }
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'copy', child: Text('Copy my account ID')),
      PopupMenuItem(value: 'signout', child: Text('Sign out')),
    ],
    icon: compact ? const Icon(Icons.person_outline) : null,
    child: compact
        ? null
        : const Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(child: Icon(Icons.person_outline)),
                SizedBox(width: 12),
                Expanded(child: Text('Your account')),
              ],
            ),
          ),
  );

  Widget sectionHeading(String text, {TextStyle? style}) => Semantics(
    header: true,
    child: Text(
      text,
      style: style ?? Theme.of(context).textTheme.headlineSmall,
    ),
  );

  Widget savedDraftCard({
    required String title,
    required String subtitle,
    required Widget resume,
    VoidCallback? onTap,
  }) => Card(
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(subtitle),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: resume),
              ],
            ),
          );
        }
        return ListTile(
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: onTap,
          trailing: resume,
        );
      },
    ),
  );

  Widget templateList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: templates.map((template) {
      final spec = AppSpec.parse(template.specJson);
      final purpose = switch (spec.policyPresetRequest) {
        'groupCapacitySignup.v1' => 'Group sign-ups',
        'groupWorkflow.v1' => 'Team workflow',
        _ => spec.collections.isEmpty ? 'Personal utility' : 'Personal tracker',
      };
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(template.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(template.description),
          const SizedBox(height: 6),
          Text(purpose, style: Theme.of(context).textTheme.labelMedium),
        ],
      );
      final actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Semantics(
            button: true,
            enabled: !creating,
            excludeSemantics: true,
            label: 'Preview ${template.name}',
            onTap: creating ? null : () => previewTemplate(template),
            child: OutlinedButton(
              key: ValueKey('preview-template-${template.key}'),
              onPressed: creating ? null : () => previewTemplate(template),
              child: const Text('Preview'),
            ),
          ),
          Semantics(
            button: true,
            enabled: !creating,
            excludeSemantics: true,
            label: 'Use ${template.name} template',
            onTap: creating ? null : () => builder(template.key),
            child: OutlinedButton(
              key: ValueKey('use-template-${template.key}'),
              onPressed: creating ? null : () => builder(template.key),
              child: const Text('Use template'),
            ),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 700
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            icon(template.specJson, size: 42),
                            const SizedBox(width: 16),
                            Expanded(child: details),
                          ],
                        ),
                        const SizedBox(height: 12),
                        actions,
                      ],
                    )
                  : Row(
                      children: [
                        icon(template.specJson, size: 42),
                        const SizedBox(width: 20),
                        Expanded(child: details),
                        const SizedBox(width: 20),
                        actions,
                      ],
                    ),
            ),
          ),
        ),
      );
    }).toList(),
  );

  Widget creationEntry() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final canGenerate = platform?.aiAvailable == true;
          final selectedWorkspace = workspaceId;
          final theme = Theme.of(context);
          final createButton = ValueListenableBuilder<TextEditingValue>(
            valueListenable: prompt,
            builder: (context, value, _) => FilledButton.icon(
              key: const ValueKey('create-app'),
              onPressed: creating || (canGenerate && value.text.trim().isEmpty)
                  ? null
                  : () {
                      if (canGenerate) {
                        builder('volunteer', generate: true);
                      } else {
                        setState(() => page = 1);
                      }
                    },
              icon: creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(canGenerate ? Icons.arrow_upward : Icons.grid_view),
              label: Text(
                creating
                    ? 'Creating your app…'
                    : canGenerate
                    ? 'Create app'
                    : 'Browse templates',
              ),
            ),
          );
          return Column(
            children: [
              SizedBox(height: compact ? 12 : 36),
              const Icon(
                Icons.spa_outlined,
                color: Color(0xff276c61),
                size: 34,
              ),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  'What would you like to build?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: compact ? 34 : 46,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Describe the app you want. Try it. Make it yours.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xff617069),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xffd7ddd7)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0825332e),
                      blurRadius: 28,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('app-idea'),
                        controller: prompt,
                        enabled: !creating,
                        minLines: 3,
                        maxLines: 7,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'A notes app with categories, a calendar for my projects, or a clock that helps me focus…',
                          hintMaxLines: 4,
                          semanticCounterText:
                              'Describe the app you want to build',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (guidanceQuestions != null &&
                          guidanceWorkspace == selectedWorkspace)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: IdeaGuidancePanel(
                            key: guidancePanelKey,
                            composer: prompt,
                            sourceText: guidanceSource!,
                            contextId: 'workspace:$guidanceWorkspace',
                            currentContext: () => 'workspace:$workspaceId',
                            questions: guidanceQuestions!,
                            usedFallback: guidanceFallback,
                            notice: guidanceNotice,
                            onUseAnswers: (combined) {
                              setState(() {
                                guidanceQuestions = null;
                              });
                              prompt.value = TextEditingValue(
                                text: combined,
                                selection: TextSelection.collapsed(
                                  offset: combined.length,
                                ),
                              );
                            },
                            onContinueOriginal: () {
                              setState(() {
                                guidanceQuestions = null;
                              });
                              unawaited(builder('volunteer', generate: true));
                            },
                            onEditIdea: () =>
                                setState(() => guidanceQuestions = null),
                          ),
                        ),
                      if (canGenerate)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: prompt,
                            builder: (context, value, _) => TextButton.icon(
                              key: const ValueKey('shape-idea'),
                              onPressed: creating || value.text.trim().isEmpty
                                  ? null
                                  : shapeIdea,
                              icon: const Icon(
                                Icons.lightbulb_outline,
                                size: 18,
                              ),
                              label: const Text('Help shape my idea'),
                            ),
                          ),
                        ),
                      if (compact)
                        Align(
                          alignment: Alignment.centerRight,
                          child: createButton,
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'A useful first version, ready to customize.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xff617069),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            createButton,
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final starter in const [
                    (
                      'Phone Toolkit',
                      Icons.phone_android,
                      'Build a phone toolkit with device information for battery, charging, model, operating system and connection, plus flashlight, brightness, keep-screen-awake and haptic controls. Use local device components with explicit per-app access.',
                    ),
                    (
                      'Notes',
                      Icons.notes_outlined,
                      'Build a personal notes app with titles, multiline notes, categories, search, and easy add and edit.',
                    ),
                    (
                      'Reminders',
                      Icons.notifications_outlined,
                      'Build a personal reminders app with open and completed items, optional due dates, and a separate optional reminder time for my AppNest inbox.',
                    ),
                    (
                      'Calendar',
                      Icons.calendar_month_outlined,
                      'Build a personal event calendar with a month view, selected-day agenda, categories, and easy event creation and editing.',
                    ),
                    (
                      'Clock & focus',
                      Icons.timer_outlined,
                      'Build a personal clock and focus app with a local digital clock and a 25-minute countdown that I can start, pause, resume, and reset.',
                    ),
                  ])
                    ActionChip(
                      avatar: Icon(starter.$2, size: 16),
                      label: Text(starter.$1),
                      onPressed: creating
                          ? null
                          : () {
                              prompt.value = TextEditingValue(
                                text: starter.$3,
                                selection: TextSelection.collapsed(
                                  offset: starter.$3.length,
                                ),
                              );
                            },
                      backgroundColor: const Color(0xfff7f6f2),
                      side: const BorderSide(color: Color(0xffdfe4dc)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (!canGenerate)
                Text(
                  '${platform?.aiMode ?? 'AI creation is unavailable'}. Choose a template to start building.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                )
              else
                TextButton(
                  onPressed: creating ? null : () => setState(() => page = 1),
                  child: const Text('Or start with a template'),
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget appCard(AppManifest app) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => open(app.appId),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            icon(app.specJson),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    app.archived
                        ? 'Archived'
                        : AppSpec.parse(app.specJson!).requires.contains(
                            'capacity.v1',
                          )
                        ? '${app.availablePlaces} places available'
                        : AppSpec.parse(app.specJson!).collections.isEmpty
                        ? 'Personal utility'
                        : '${app.recordCount} ${app.recordCount == 1 ? 'record' : 'records'}',
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );

  Widget home() {
    final published = apps.where((app) => app.versionId != null).toList();
    final drafts = apps
        .where((app) => app.versionId == null && !app.archived)
        .toList();
    final localDrafts = unfinishedCreations.values
        .where(
          (saved) =>
              saved.workspaceId == workspaceId &&
              !apps.any((app) => app.appId == saved.draft.appId),
        )
        .toList();
    final hasWork =
        published.isNotEmpty || drafts.isNotEmpty || localDrafts.isNotEmpty;
    final pinned = published.where((app) => app.pinned).toList();
    final visible = pinned.isEmpty ? published : pinned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasWork) ...[
          creationEntry(),
          const SizedBox(height: 40),
        ],
        Wrap(
          spacing: 20,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            sectionHeading('Your apps'),
            if (hasWork)
              OutlinedButton.icon(
                key: const ValueKey('toggle-creation'),
                onPressed: creating
                    ? null
                    : () => setState(() => showComposer = !showComposer),
                icon: Icon(showComposer ? Icons.close : Icons.add),
                label: Text(showComposer ? 'Hide composer' : 'New app'),
              ),
          ],
        ),
        if (hasWork && showComposer) ...[
          creationEntry(),
          const SizedBox(height: 24),
        ],
        const SizedBox(height: 20),
        if (published.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              hasWork ? 'No published apps yet. Continue a saved build below.' : 'Your next idea belongs here. Create an app to get started.',
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 650 ? 1 : 3;
            return Column(
              children: [
                for (var start = 0; start < visible.length; start += columns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var column = 0; column < columns; column++) ...[
                            if (column > 0) const SizedBox(width: 16),
                            Expanded(
                              child: start + column < visible.length
                                  ? appCard(visible[start + column])
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (pinned.isNotEmpty && published.any((app) => !app.pinned))
          ExpansionTile(
            title: const Text('All apps, including unpinned'),
            children: published
                .where((app) => !app.pinned)
                .map(
                  (app) => ListTile(
                    title: Text(app.name),
                    onTap: () => open(app.appId),
                    trailing: IconButton(
                      tooltip: 'Pin ${app.name}',
                      icon: const Icon(Icons.push_pin_outlined),
                      onPressed: () async {
                        await client.apps.pin(app.appId, true);
                        await load();
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        if (drafts.isNotEmpty || localDrafts.isNotEmpty) ...[
          const SizedBox(height: 24),
          sectionHeading('Continue building'),
          const SizedBox(height: 12),
          for (final app in drafts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: savedDraftCard(
                title: app.name,
                subtitle: 'Unpublished · Saved for your account',
                onTap: creating ? null : () => resumeAppDraft(app),
                resume: Semantics(
                  label: 'Resume ${app.name}',
                  child: TextButton(
                    key: ValueKey('resume-app-draft-${app.appId}'),
                    onPressed: creating ? null : () => resumeAppDraft(app),
                    child: const Text('Resume build'),
                  ),
                ),
              ),
            ),
          for (final saved in localDrafts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: savedDraftCard(
                title: 'Continue building your app',
                subtitle: saved.draft.latestRequest ?? 'Your unfinished app',
                resume: OutlinedButton(
                  key: ValueKey('resume-build-${saved.draft.draftId}'),
                  onPressed: creating
                      ? null
                      : () => resumeCreation(saved.draft.draftId),
                  child: const Text('Resume build'),
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
        if (hasWork)
          TextButton.icon(
            onPressed: creating ? null : () => setState(() => page = 1),
            icon: const Icon(Icons.grid_view_outlined),
            label: const Text('Browse templates'),
          )
        else ...[
          const Divider(),
          const SizedBox(height: 24),
          sectionHeading('Start with a template'),
          const SizedBox(height: 16),
          templateList(),
        ],
      ],
    );
  }

  String inboxTime(DateTime timestamp) {
    final local = timestamp.toLocal(), now = DateTime.now();
    final localization = MaterialLocalizations.of(context);
    final date = DateUtils.isSameDay(local, now)
        ? 'Today'
        : DateUtils.isSameDay(local, DateTime(now.year, now.month, now.day - 1))
        ? 'Yesterday'
        : localization.formatMediumDate(local);
    final time = localization.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$date, $time';
  }

  Widget content() => loading
      ? const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to AppNest…'),
            ],
          ),
        )
      : error != null
      ? HomeLoadFailure(error: error!, onRetry: load)
      : SingleChildScrollView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 700 ? 20 : 48,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1250),
              child: switch (page) {
                0 => home(),
                1 => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeading(
                      'Templates',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A template creates an empty app. Review its structure and permissions before publishing.',
                    ),
                    const SizedBox(height: 32),
                    templateList(),
                  ],
                ),
                _ => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeading(
                      'Inbox',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: inboxRefreshing ? null : refreshInbox,
                      icon: inboxRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        inboxRefreshing ? 'Refreshing…' : 'Refresh inbox',
                      ),
                    ),
                    if (inboxError != null)
                      Semantics(
                        liveRegion: true,
                        child: const Text(
                          'Couldn’t refresh your Inbox. Check your connection or account access and try again.',
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (inbox.isEmpty && inboxError == null)
                      const Text(
                        'All quiet. Approved reminders will appear here.',
                      ),
                    ...inbox.map(
                      (n) => Card(
                        child: ListTile(
                          leading: Icon(
                            n.isRead
                                ? Icons.drafts_outlined
                                : Icons.mark_email_unread_outlined,
                            semanticLabel: n.isRead
                                ? 'Read reminder'
                                : 'Unread reminder',
                          ),
                          title: Text(n.title),
                          isThreeLine: true,
                          subtitle: Text(
                            '${n.body}\n${inboxTime(n.createdAt)}',
                          ),
                          onTap: () async {
                            await client.runtime.readNotification(n.id);
                            open(n.appId, recordId: n.recordId);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              },
            ),
          ),
        );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth >= 900;
      return Scaffold(
        appBar: wide
            ? null
            : AppBar(
                title: const Text('AppNest'),
                actions: [
                  IconButton(
                    tooltip: 'New workspace',
                    onPressed: newWorkspace,
                    icon: const Icon(Icons.add),
                  ),
                  accountMenu(compact: true),
                ],
              ),
        body: wide
            ? Row(
                children: [
                  SizedBox(width: 230, child: navigation(true)),
                  const VerticalDivider(width: 1),
                  Expanded(child: content()),
                ],
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: workspacePicker(),
                  ),
                  Expanded(child: content()),
                ],
              ),
        bottomNavigationBar: wide ? null : navigation(false),
      );
    },
  );
}
