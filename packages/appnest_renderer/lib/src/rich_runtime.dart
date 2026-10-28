part of '../appnest_renderer.dart';

class _RichMiniAppRuntime extends StatefulWidget {
  final RuntimeAdapter adapter;
  final MiniAppController? controller;
  final MiniAppLocation? initialLocation;
  final ValueChanged<MiniAppLocation>? onLocationChanged;
  final DateTime Function() clock;
  const _RichMiniAppRuntime({
    required this.adapter,
    required this.clock,
    this.controller,
    this.initialLocation,
    this.onLocationChanged,
  });
  @override
  State<_RichMiniAppRuntime> createState() => _RichMiniAppRuntimeState();
}

class _ViewState {
  String search = '';
  final Map<String, String> filters = {};
  RuntimePage? records;
  RuntimeSummary? summary;
  Map<String, dynamic>? aggregate;
  String? sortField;
  bool descending = false, undated = false;
  DateTime? month, day;
}

class _RichMiniAppRuntimeState extends State<_RichMiniAppRuntime>
    with WidgetsBindingObserver {
  final _views = <String, _ViewState>{};
  final _history = <MiniAppLocation>[];
  final _storage = PageStorageBucket();
  late MiniAppLocation _location;
  RuntimeItem? _record;
  _RuntimeCommand? _pendingCommand;
  List<RuntimeReminderState>? _reminder;
  Object? _error;
  ModalRoute<void>? _editorRoute;
  int? _editorRecordId;
  bool _loading = true,
      _saving = false,
      _formDirty = false,
      _reconnecting = false;
  int _request = 0, _navigationAttempt = 0;
  int? _navigationGuard;
  Timer? _timer, _reconnectTimer, _searchTimer;
  StreamSubscription<void>? _subscription;
  RuntimeAdapter get adapter => widget.adapter;
  AppSpec get spec => adapter.spec;
  PageSpec get page => spec.page(_location.pageId);
  DateTime get now => widget.clock();
  void _update(VoidCallback callback) => setState(callback);
  bool get _formPage => page.viewIds.any((id) => spec.view(id).type == 'form');
  _ViewState state(ViewSpec view) =>
      _views.putIfAbsent(view.id, _ViewState.new);

  @override
  void initState() {
    super.initState();
    _location = _validLocation(widget.initialLocation);
    _attach();
    WidgetsBinding.instance.addObserver(this);
    _connect();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  MiniAppLocation _validLocation(MiniAppLocation? location) =>
      location != null &&
          spec.navigation!.pages.any((p) => p.id == location.pageId)
      ? location
      : MiniAppLocation(spec.navigation!.entryPageId);

  void _attach() {
    final controller = widget.controller;
    controller?._navigate = (location) =>
        _navigate(location, kind: MiniAppNavigationKind.external);
    controller?._back = _back;
    controller?._canLeave = _hostCanLeave;
    controller?._location = _location;
    controller?._navigationKind = MiniAppNavigationKind.external;
  }

  @override
  void didUpdateWidget(covariant _RichMiniAppRuntime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      _attach();
    }
    if (oldWidget.adapter != adapter || oldWidget.adapter.spec != spec) {
      _pendingCommand = null;
      _request++;
      _views.clear();
      _record = null;
      _reminder = null;
      _formDirty = false;
      _location = _validLocation(_location);
      _attach();
      _connect();
    }
  }

  void _connect() {
    _subscription?.cancel();
    _reconnectTimer?.cancel();
    _subscription = adapter.watch().listen(
      (_) => _refresh(),
      onError: (Object error) => _connectionFailed(error),
      onDone: () =>
          _connectionFailed(StateError('The connection was interrupted.')),
    );
    _refresh();
  }

  void _connectionFailed(Object error) {
    if (!mounted) return;
    _dismissLegacyEditor();
    _request++;
    setState(() {
      _error = error;
      _record = null;
      _reminder = null;
      _views.clear();
      _loading = false;
      _reconnecting = true;
    });
    _reconnectTimer = Timer(const Duration(seconds: 5), _connect);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) _connect();
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _subscription?.cancel();
    _timer?.cancel();
    _reconnectTimer?.cancel();
    _searchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _dismissLegacyEditor() {
    final route = _editorRoute;
    _editorRoute = null;
    _editorRecordId = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
    if (route != null) _formDirty = false;
  }

  Future<bool> _hostCanLeave() async {
    final result = await _canLeave();
    if (result) _dismissLegacyEditor();
    return result;
  }

  bool _editingPresentation = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final editing = _VisualEditScope.of(context) != null;
    // The host guards entry through controller.canLeave(). Once the record
    // editor is replaced, do not retain a phantom unsaved-form flag.
    if (editing && !_editingPresentation) _formDirty = false;
    _editingPresentation = editing;
  }

  Future<bool> _canLeave() async {
    if (_saving) return false;
    if (_pendingCommand != null) {
      final leave =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Save outcome unconfirmed'),
              content: const Text(
                'Your changes may already be saved. Retry to check the original request, or leave without retrying. Reopening will not retry this request automatically.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Return to save'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Leave without retrying'),
                ),
              ],
            ),
          ) ??
          false;
      if (leave && mounted) {
        setState(() {
          _pendingCommand = null;
          _formDirty = false;
        });
      }
      return leave;
    }
    if (!_formDirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard your changes?'),
            content: const Text('Your unsaved changes will be lost.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _navigate(
    MiniAppLocation location, {
    MiniAppNavigationKind kind = MiniAppNavigationKind.push,
  }) async {
    final attempt = ++_navigationAttempt;
    if (_location == location) return true;
    if (_navigationGuard != null) return false;
    _navigationGuard = attempt;
    try {
      if (!await _canLeave() || !mounted || attempt != _navigationAttempt)
        return false;
      _dismissLegacyEditor();
      final next = _validLocation(location);
      final previous = _history.lastIndexOf(next);
      if (kind == MiniAppNavigationKind.pop ||
          (kind == MiniAppNavigationKind.external && previous >= 0)) {
        if (previous >= 0) {
          _history.removeRange(previous, _history.length);
        } else {
          _history.clear();
        }
      } else if (spec.navigation!.tabs.any((t) => t.pageId == next.pageId)) {
        _history.clear();
      } else {
        _history.add(_location);
      }
      _searchTimer?.cancel();
      setState(() {
        _location = next;
        _formDirty = false;
        _record = null;
        _reminder = null;
        _error = null;
        _loading = true;
      });
      widget.controller?._update(next, kind);
      widget.onLocationChanged?.call(next);
      _navigationGuard = null;
      await _refresh();
      return true;
    } finally {
      if (_navigationGuard == attempt) _navigationGuard = null;
    }
  }

  Future<bool> _back() async {
    if (_history.isEmpty &&
        _location == MiniAppLocation(spec.navigation!.entryPageId))
      return false;
    final target =
        _history.lastOrNull ?? MiniAppLocation(spec.navigation!.entryPageId);
    return _navigate(target, kind: MiniAppNavigationKind.pop);
  }

  String? _textSearchField(ViewSpec view) {
    final fieldId = view.titleFieldId;
    if (view.contentOnly ||
        view.type == 'summary' ||
        fieldId == null ||
        spec.collection(view.collectionId).field(fieldId).type !=
            FieldType.text)
      return null;
    final filters = resolveViewQuery(spec, view, now: now)['filters'] as List;
    final componentFilters = view.type == 'calendar'
        ? 2
        : view.type == 'timeline' &&
              !spec
                  .collection(view.collectionId)
                  .field(view.options['dateFieldId'] as String)
                  .required
        ? 1
        : 0;
    if (filters.length + view.filterFieldIds.length + componentFilters >=
        Limits.filters)
      return null;
    return fieldId;
  }

  Map<String, dynamic> _query(ViewSpec view, {String? cursor}) {
    final stored = state(view);
    final query = resolveViewQuery(spec, view, now: now);
    final searchField = _textSearchField(view);
    return {
      ...query,
      'filters': [
        ...query['filters'] as List,
        if (stored.search.isNotEmpty && searchField != null)
          {
            'fieldId': searchField,
            'operator': 'contains',
            'value': stored.search,
          },
        for (final filter in stored.filters.entries)
          {'fieldId': filter.key, 'operator': 'eq', 'value': filter.value},
      ],
      if (stored.sortField != null)
        'sort': [
          {'fieldId': stored.sortField, 'descending': stored.descending},
        ],
      if (view.type == 'timeline')
        'sort': [
          {'fieldId': view.options['dateFieldId'], 'descending': false},
        ],
      if (cursor != null) 'cursor': cursor,
    };
  }

  Future<void> _refresh({String? nextView}) async {
    if (!mounted || _saving) return;
    final request = ++_request, location = _location;
    try {
      if (_editorRecordId != null) await adapter.get(_editorRecordId!);
      if (location.recordId != null) {
        final record = await adapter.get(location.recordId!);
        if (page.viewIds.any(
          (id) => spec.view(id).collectionId != record.collectionId,
        )) {
          throw const SpecException('This record is unavailable on this page.');
        }
        List<RuntimeReminderState>? reminder;
        if (spec.automationRequests.any(
          (r) => r.collectionId == record.collectionId,
        )) {
          reminder = await adapter.reminderState(record.id);
        }
        if (!mounted || request != _request || location != _location) return;
        if (_formDirty) return;
        setState(() {
          _record = record;
          _reminder = reminder;
          _error = null;
          _loading = false;
          _reconnecting = false;
        });
      } else {
        final results = await Future.wait(
          page.viewIds.map((id) async {
            final view = spec.view(id), stored = state(spec.view(id));
            if (view.type == 'form' ||
                view.type == 'details' ||
                view.contentOnly)
              return (id, null);
            if (nextView != null && id != nextView) return (id, null);
            final query = _query(
              view,
              cursor: nextView == id ? stored.records?.cursor : null,
            );
            final Object result =
                {'chart', 'metric', 'calendar', 'timeline'}.contains(view.type)
                ? await _loadRichData(
                    view,
                    query,
                    nextView == id ? 0 : stored.records?.items.length ?? 0,
                  )
                : view.type == 'summary'
                ? view.groupByFieldId == null
                      ? RuntimeSummary(
                          (await adapter.query(view.collectionId, query)).total,
                          const {},
                        )
                      : await adapter.summary(
                          view.collectionId,
                          query,
                          view.groupByFieldId!,
                        )
                : await _readRecords(
                    view,
                    query,
                    nextView == id ? 0 : stored.records?.items.length ?? 0,
                  );
            return (id, result);
          }),
        );
        if (!mounted || request != _request || location != _location) return;
        setState(() {
          for (final (id, result) in results) {
            final stored = state(spec.view(id));
            if (result is _RichData) {
              stored.aggregate = result.aggregate;
              if (result.records != null)
                stored.records = nextView == id && stored.records != null
                    ? RuntimePage(
                        [...stored.records!.items, ...result.records!.items],
                        result.records!.total,
                        result.records!.cursor,
                      )
                    : result.records;
            }
            if (result is RuntimeSummary) stored.summary = result;
            if (result is RuntimePage) {
              stored.records = nextView == id && stored.records != null
                  ? RuntimePage(
                      [...stored.records!.items, ...result.items],
                      result.total,
                      result.cursor,
                    )
                  : result;
            }
          }
          _error = null;
          _loading = false;
          _reconnecting = false;
        });
      }
    } catch (error) {
      if (!mounted || request != _request) return;
      _dismissLegacyEditor();
      setState(() {
        _error = error;
        _record = null;
        _reminder = null;
        _views.clear();
        _loading = false;
      });
    }
  }

  Future<RuntimePage> _readRecords(
    ViewSpec view,
    Map<String, dynamic> query,
    int retainCount,
  ) async {
    var result = await adapter.query(view.collectionId, query);
    final items = [...result.items];
    while (result.cursor != null && items.length < retainCount) {
      result = await adapter.query(view.collectionId, {
        ...query,
        'cursor': result.cursor,
      });
      items.addAll(result.items);
    }
    return RuntimePage(items, result.total, result.cursor);
  }

  bool _permitted(ActionSpec action, RuntimeItem? record) =>
      !adapter.readOnly &&
      adapter.permits(action) &&
      (record == null || record.allowedActions.contains(action.id));

  Future<void> _run(
    ActionSpec action,
    RuntimeItem? item, {
    ViewSpec? source,
  }) async {
    if (!_permitted(action, item) || _saving || _pendingCommand != null) return;
    final edit = _VisualEditScope.of(context);
    if (edit != null) {
      edit.onSelect(
        source == null
            ? MiniAppEditTarget(MiniAppEditKind.page, page.id)
            : MiniAppEditTarget(
                MiniAppEditKind.section,
                source.id,
                pageId: page.id,
              ),
      );
      return;
    }
    if (action.capability == 'records.create.v1' ||
        action.capability == 'records.patch.v1') {
      final destination =
          source?.formPageId ??
          spec.navigation!.pages
              .where(
                (p) => p.viewIds.any((id) {
                  final view = spec.view(id);
                  return view.type == 'form' &&
                      view.collectionId == action.collectionId &&
                      view.actionIds.contains(action.id);
                }),
              )
              .firstOrNull
              ?.id;
      if (destination != null) {
        await _navigate(
          MiniAppLocation(destination, recordId: item?.id, editing: true),
        );
      } else {
        await _legacyEditor(action, item);
      }
      return;
    }
    Map<String, dynamic>? input = {};
    if (action.capability == 'workflow.transition.v1' ||
        action.capability == 'assignment.assign.v1') {
      final behavior = spec
          .collection(action.collectionId)
          .behavior(action.behaviorId!);
      final values = action.capability == 'assignment.assign.v1'
          ? await adapter.members()
          : behavior.transitions[item?.data[behavior.fieldId]] ?? [];
      if (!mounted || values.isEmpty) return;
      input = values.length == 1
          ? {'value': values.single}
          : await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (context) =>
                  _ChoiceDialog(label: action.label, values: values),
            );
    } else if (action.capability == 'capacity.configure.v1') {
      input = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ValueDialog(
          label: 'Capacity',
          numeric: true,
          initial: '${item?.capacity ?? 1}',
        ),
      );
      if (input != null)
        input = {'capacity': int.tryParse('${input['value']}')};
    }
    if (input != null) await _execute(action, item, input);
  }

  Future<void> _legacyEditor(ActionSpec action, RuntimeItem? item) async {
    // Existing views can opt into navigation without having to add a form page.
    // Preserve their editing capability while keeping the same guarded editor.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _editorRoute = ModalRoute.of<void>(dialogContext);
        _editorRecordId = item?.id;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop && await _canLeave() && dialogContext.mounted) {
              Navigator.pop(dialogContext);
            }
          },
          child: Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                child: _RecordEditor(
                  action: action,
                  collection: spec.collection(action.collectionId),
                  initial: item?.data,
                  capacity: item?.capacity,
                  members: adapter.members,
                  clock: widget.clock,
                  fieldIds: const [],
                  adapter: adapter,
                  record: item,
                  onDirtyChanged: (dirty) => _formDirty = dirty,
                  onCancel: () async {
                    if (!await _canLeave() || !dialogContext.mounted)
                      return false;
                    Navigator.pop(dialogContext);
                    return true;
                  },
                  onSave: (command) async {
                    await _execute(
                      command.action,
                      command.record,
                      command.input,
                      command: command,
                      propagateError: true,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
    _editorRoute = null;
    _editorRecordId = null;
    _formDirty = false;
  }

  Future<void> _execute(
    ActionSpec action,
    RuntimeItem? item,
    Map<String, dynamic> input, {
    bool editor = false,
    bool propagateError = false,
    _RuntimeCommand? command,
  }) async {
    if (_VisualEditScope.of(context) != null) return;
    final recovering = command != null && _pendingCommand?.key == command.key;
    if (_saving || (_pendingCommand != null && !recovering)) {
      const message =
          'Resolve the unconfirmed save before making another change.';
      if (editor || propagateError) throw const SpecException(message);
      _showFeedback(message);
      return;
    }
    if (!recovering && !_permitted(action, item))
      throw const SpecException('This action is unavailable.');
    final request = command ?? _RuntimeCommand(action, item, input);
    setState(() => _saving = true);
    try {
      await request.execute(adapter);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formDirty = false;
        _pendingCommand = null;
      });
      _showFeedback(adapter.preview ? 'Simulated in preview' : 'Saved');
      if (editor) {
        await _back();
      } else {
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _pendingCommand = recovering || adapter.commandMayHaveSucceeded(error)
              ? request
              : null;
        });
      }
      if (editor || propagateError) rethrow;
      if (mounted) {
        _showFeedback(
          adapter.errorMessage(error, fallback: 'Could not save. Try again.'),
        );
      }
    }
  }

  void _showFeedback(String message) {
    // The host Scaffold cannot measure this renderer-owned navigation bar.
    // Reserve its actual theme height even while saving an editor: returning
    // from that editor immediately restores the bar below the feedback.
    final mobile =
        (context.size?.width ?? MediaQuery.sizeOf(context).width) < 760;
    final bottom = mobile && spec.navigation!.tabs.length > 1
        ? (NavigationBarTheme.of(context).height ?? 80) +
              MediaQuery.paddingOf(context).bottom +
              16
        : 16.0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottom),
        content: Text(message),
      ),
    );
  }

  Future<void> _retryPending() async {
    final command = _pendingCommand;
    if (command == null || _saving) return;
    await _execute(
      command.action,
      command.record,
      command.input,
      command: command,
    );
    if (mounted && _pendingCommand == null && !_formDirty && _formPage) {
      await _back();
    }
  }

  String _actionLabel(ActionSpec action, RuntimeItem? item) {
    if (action.capability == 'workflow.transition.v1' && item != null) {
      final behavior = spec
          .collection(action.collectionId)
          .behavior(action.behaviorId!);
      final targets = behavior.transitions[item.data[behavior.fieldId]] ?? [];
      if (targets.length == 1) return 'Mark ${targets.single.toLowerCase()}';
    }
    return action.label;
  }

  IconData _workflowIcon(ActionSpec action, RuntimeItem item) {
    final collection = spec.collection(action.collectionId);
    final field = collection.field(
      collection.behavior(action.behaviorId!).fieldId!,
    );
    // Choice order does not give arbitrary workflows a completion meaning.
    if (field.choices.length == 2 &&
        field.choices.contains('Open') &&
        field.choices.contains('Done')) {
      return item.data[field.id] == 'Done'
          ? Icons.check_circle
          : Icons.radio_button_unchecked;
    }
    return Icons.swap_horiz;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = spec.appearance != null
        ? Theme.of(context).colorScheme
        : ColorScheme.fromSeed(
            seedColor: _appColor(spec.theme),
            brightness: Theme.of(context).brightness,
          );
    final theme = spec.appearance != null
        ? Theme.of(context)
        : Theme.of(context).copyWith(
            colorScheme: colorScheme,
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: colorScheme.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: colorScheme.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 760;
            final tabs = spec.navigation!.tabs;
            final active = tabs.indexWhere((t) => t.pageId == _location.pageId);
            final fallback = tabs.indexWhere(
              (t) => _history.any((h) => h.pageId == t.pageId),
            );
            final selected = active >= 0
                ? active
                : (fallback >= 0 ? fallback : 0);
            final destinations = [
              for (final tab in tabs)
                NavigationDestination(
                  icon: Icon(_pageIcon(tab.icon)),
                  label: tab.label,
                ),
            ];
            final body = Expanded(
              child: Column(
                children: [
                  if (adapter.preview)
                    _notice(
                      context,
                      'Preview · Synthetic records. Actions stay in this preview.',
                      Icons.science_outlined,
                    ),
                  if (adapter.readOnly)
                    _notice(
                      context,
                      adapter.readOnlyMessage,
                      Icons.lock_outline,
                    ),
                  if (_loading || _saving)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_pendingCommand != null &&
                      (!_formPage ||
                          _error != null ||
                          !_permitted(_pendingCommand!.action, _record)))
                    MaterialBanner(
                      content: Semantics(
                        liveRegion: true,
                        child: const Text(
                          'Save outcome unconfirmed. Your changes may already be saved.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: _saving ? null : _retryPending,
                          child: Text(
                            _saving ? 'Checking save…' : 'Retry save',
                          ),
                        ),
                      ],
                    ),
                  Expanded(child: _content(context)),
                ],
              ),
            );
            return ColoredBox(
              color: colorScheme.surfaceContainerLow,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (desktop && tabs.length > 1)
                          NavigationRail(
                            selectedIndex: selected,
                            labelType: NavigationRailLabelType.all,
                            onDestinationSelected: (i) =>
                                _navigate(MiniAppLocation(tabs[i].pageId)),
                            destinations: [
                              for (final tab in tabs)
                                NavigationRailDestination(
                                  icon: Icon(_pageIcon(tab.icon)),
                                  label: Text(tab.label),
                                ),
                            ],
                          ),
                        body,
                      ],
                    ),
                  ),
                  if (!desktop && tabs.length > 1 && !_formPage)
                    NavigationBar(
                      selectedIndex: selected,
                      onDestinationSelected: (i) =>
                          _navigate(MiniAppLocation(tabs[i].pageId)),
                      destinations: destinations,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _notice(BuildContext context, String message, IconData icon) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );

  Widget _content(BuildContext context) {
    final primary = page.primaryActionId == null
        ? null
        : spec.action(page.primaryActionId!);
    final nested = !spec.navigation!.tabs.any((t) => t.pageId == page.id);
    return PageStorage(
      bucket: _storage,
      child: SingleChildScrollView(
        key: PageStorageKey('page-${page.id}-${_location.recordId ?? "root"}'),
        padding: EdgeInsets.fromLTRB(
          _space(context, 24),
          _space(context, 24),
          _space(context, 24),
          _space(context, 32),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (nested)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _back,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (page.showDate)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              MaterialLocalizations.of(context)
                                  .formatFullDate(now),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                            ),
                          ),
                        _EditTarget(
                          target: MiniAppEditTarget(
                            MiniAppEditKind.page,
                            page.id,
                          ),
                          child: Semantics(
                            header: true,
                            child: Text(
                              page.title,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: spec.appearance == null
                                        ? FontWeight.w700
                                        : null,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (primary != null && _permitted(primary, null))
                      FilledButton.icon(
                        onPressed: _saving || _pendingCommand != null
                            ? null
                            : () => _run(primary, null),
                        icon: const Icon(Icons.add),
                        label: Text(primary.label),
                      ),
                  ],
                ),
                SizedBox(height: _space(context, 24)),
                if (_error != null)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(_space(context, 24)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This page is unavailable',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            adapter.errorMessage(
                              _error!,
                              fallback: 'Your access or this app may have changed. Refresh to try again.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _reconnecting ? _connect : _refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_loading &&
                    _record == null &&
                    _location.recordId != null)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Loading record…'),
                    ),
                  )
                else
                  _pageSections(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageSections(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = _space(context, 24);
      final paired =
          (page.layout == 'twoColumn' || page.layout == 'featuredFirst') &&
          constraints.maxWidth >= 960 &&
          MediaQuery.textScalerOf(context).scale(100) < 150;
      final views = page.viewIds.map(spec.view).toList();
      Widget section(ViewSpec view) => _EditTarget(
        key: ValueKey('section-${view.id}'),
        target: MiniAppEditTarget(
          MiniAppEditKind.section,
          view.id,
          pageId: page.id,
        ),
        child: _section(context, view),
      );
      bool fullWidth(ViewSpec view) =>
          {
            'table',
            'calendar',
            'board',
            'form',
            'details',
          }.contains(view.type) ||
          _location.recordId != null;
      final rows = <Widget>[];
      for (var index = 0; index < views.length; index++) {
        final first = views[index];
        final canPair =
            paired &&
            !(index == 0 && page.layout == 'featuredFirst') &&
            !fullWidth(first) &&
            index + 1 < views.length &&
            !fullWidth(views[index + 1]);
        rows.add(
          Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: canPair
                ? Row(
                    key: ValueKey('section-pair-${first.id}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: section(first)),
                      SizedBox(width: gap),
                      Expanded(child: section(views[++index])),
                    ],
                  )
                : section(first),
          ),
        );
      }
      return FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      );
    },
  );

  Widget _section(BuildContext context, ViewSpec view) {
    if (view.type == 'form') {
      if (_VisualEditScope.of(context) != null)
        return _editForm(spec, view, pageId: page.id);
      final capability = _location.recordId == null
          ? 'records.create.v1'
          : 'records.patch.v1';
      final action = view.actionIds
          .map(spec.action)
          .where((a) => a.capability == capability && _permitted(a, _record))
          .firstOrNull;
      if (action == null)
        return const Text('You have read-only access to this record.');
      return _RecordEditor(
        key: ValueKey('editor-${view.id}-${_location.recordId}'),
        action: action,
        collection: spec.collection(view.collectionId),
        initial: _record?.data,
        capacity: _record?.capacity,
        members: adapter.members,
        clock: widget.clock,
        fieldIds: view.fieldIds,
        options: view.options,
        adapter: adapter,
        record: _record,
        pendingCommand: _pendingCommand,
        onDirtyChanged: (value) => _formDirty = value,
        onSave: (command) => _execute(
          command.action,
          command.record,
          command.input,
          command: command,
          editor: true,
        ),
        onCancel: _back,
      );
    }
    if (view.type == 'details' || _location.recordId != null) {
      if (_record == null)
        return const Text('Choose a record to open its details.');
      return _details(context, view, _record!);
    }
    if (view.type == 'deviceInfo' || view.type == 'deviceControl')
      return _DeviceComponent(
        key: ValueKey(view.id),
        view: view,
        adapter: adapter.deviceCapabilities,
      );
    if (view.type == 'clock')
      return _UtilityClock(
        key: ValueKey(view.id),
        view: view,
        clock: widget.clock,
      );
    if (view.type == 'timer')
      return _UtilityTimer(
        key: ValueKey(view.id),
        view: view,
        controller: adapter.timerController,
        preview: adapter.preview,
      );
    if (view.contentOnly) return _contentSection(context, view);
    if ({
      'table',
      'calendar',
      'timeline',
      'chart',
      'metric',
      'imageCards',
      'gallery',
      'checklist',
    }.contains(view.type))
      return _richSection(context, view);
    final stored = state(view);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _recordSectionLabel(spec, view),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: spec.appearance == null ? FontWeight.w700 : null,
          ),
        ),
        const SizedBox(height: 12),
        if (page.primaryActionId == null) ...[
          for (final action
              in view.actionIds
                  .map(spec.action)
                  .where(
                    (a) =>
                        a.capability == 'records.create.v1' &&
                        _permitted(a, null),
                  ))
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: _saving || _pendingCommand != null
                      ? null
                      : () => _run(action, null, source: view),
                  icon: const Icon(Icons.add),
                  label: Text(action.label),
                ),
              ),
            ),
        ],
        if (view.type == 'summary')
          stored.summary == null
              ? const Text('Loading summary…')
              : _summary(
                  context,
                  stored.summary!,
                  spec.collection(view.collectionId).label,
                )
        else ...[
          if (_textSearchField(view) != null) ...[
            TextFormField(
              key: ValueKey('search-${view.id}'),
              initialValue: stored.search,
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                stored.search = value;
                stored.records = null;
                _searchTimer?.cancel();
                _searchTimer = Timer(
                  const Duration(milliseconds: 250),
                  _refresh,
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          if (view.filterFieldIds.isNotEmpty) ...[
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                for (final fieldId in view.filterFieldIds)
                  DropdownButton<String>(
                    key: ValueKey('filter-${view.id}-$fieldId'),
                    value: stored.filters[fieldId] ?? '',
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(
                          'All ${spec.collection(view.collectionId).field(fieldId).label.toLowerCase()}',
                        ),
                      ),
                      for (final choice
                          in spec
                              .collection(view.collectionId)
                              .field(fieldId)
                              .choices)
                        DropdownMenuItem(value: choice, child: Text(choice)),
                    ],
                    onChanged: (value) {
                      setState(() {
                        stored.records = null;
                        if (value == null || value.isEmpty) {
                          stored.filters.remove(fieldId);
                        } else {
                          stored.filters[fieldId] = value;
                        }
                      });
                      _refresh();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (stored.records == null)
            const Padding(padding: EdgeInsets.all(24), child: Text('Loading…'))
          else if (stored.records!.items.isEmpty)
            Card(
              child: Padding(
                padding: EdgeInsets.all(_space(context, 24)),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Nothing here right now. A little room to breathe.',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (view.type == 'board')
            _board(context, view, stored.records!.items)
          else if (view.presentation == 'cards')
            Column(
              children: [
                for (final item in stored.records!.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: _row(context, view, item),
                    ),
                  ),
              ],
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < stored.records!.items.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 20, endIndent: 20),
                    _row(context, view, stored.records!.items[i]),
                  ],
                ],
              ),
            ),
          if (stored.records != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${spec.collection(view.collectionId).label} · ${stored.records!.total}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (stored.records!.cursor != null)
                    TextButton(
                      onPressed: () => _refresh(nextView: view.id),
                      child: const Text('Load more'),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _board(BuildContext context, ViewSpec view, List<RuntimeItem> items) =>
      view.options['draggable'] == true
      ? _movableBoard(context, view, items)
      : LayoutBuilder(
          builder: (context, constraints) {
            final choices = spec
                .collection(view.collectionId)
                .field(view.groupByFieldId!)
                .choices;
            final columns = constraints.maxWidth < 700
                ? 1
                : choices.length.clamp(1, 3);
            final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 20,
              children: [
                for (final choice in choices)
                  SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            choice,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        for (final item in items.where(
                          (r) => r.data[view.groupByFieldId] == choice,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Card(child: _row(context, view, item)),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );

  Iterable<ActionSpec> _recordActions(ViewSpec view, RuntimeItem item) => view
      .actionIds
      .map(spec.action)
      .where(
        (action) =>
            action.capability != 'records.create.v1' &&
            _permitted(action, item) &&
            !(action.capability == 'capacity.claim.v1' && item.claimed) &&
            !(action.capability == 'capacity.release.v1' && !item.claimed) &&
            !(action.capability == 'workflow.transition.v1' &&
                (spec
                            .collection(item.collectionId)
                            .behavior(action.behaviorId!)
                            .transitions[item.data[spec
                            .collection(item.collectionId)
                            .behavior(action.behaviorId!)
                            .fieldId]] ??
                        [])
                    .isEmpty),
      );

  Widget _summary(
    BuildContext context,
    RuntimeSummary summary,
    String collectionLabel,
  ) => Card(
    child: Padding(
      padding: EdgeInsets.all(_space(context, 20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${summary.total}',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: spec.appearance == null ? FontWeight.w700 : null,
            ),
          ),
          Text(collectionLabel),
          const SizedBox(height: 20),
          for (final group in summary.groups.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(group.key)),
                      Text(
                        '${group.value} · ${summary.total == 0 ? 0 : (group.value / summary.total * 100).round()}%',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: summary.total == 0
                          ? 0
                          : group.value / summary.total,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _row(BuildContext context, ViewSpec view, RuntimeItem item) {
    final collection = spec.collection(view.collectionId);
    final titleFieldId = view.titleFieldId ?? collection.fields.first.id;
    final actions = _recordActions(view, item).toList();
    final workflow = actions
        .where((a) => a.capability == 'workflow.transition.v1')
        .firstOrNull;
    final detailActionIds = view.detailPageId == null
        ? <String>{}
        : spec
              .page(view.detailPageId!)
              .viewIds
              .map(spec.view)
              .expand((destination) => destination.actionIds)
              .toSet();
    final fields =
        (view.fieldIds.isEmpty && !{'capacity', 'action'}.contains(view.type)
                ? collection.fields.map((field) => field.id)
                : view.fieldIds)
            .where(
              (id) =>
                  id != titleFieldId &&
                  item.data[id] != null &&
                  (!{'gallery', 'imageCards'}.contains(view.type) ||
                      id != view.options['imageFieldId']),
            )
            .map(collection.field);
    final inlineActions = actions
        .where(
          (a) =>
              a.id != workflow?.id &&
              (!detailActionIds.contains(a.id) ||
                  {'capacity', 'action'}.contains(view.type)),
        )
        .toList();
    return InkWell(
      onTap: _VisualEditScope.of(context) != null
          ? () => _VisualEditScope.of(context)!.onSelect(
              MiniAppEditTarget(
                MiniAppEditKind.section,
                view.id,
                pageId: page.id,
              ),
            )
          : view.detailPageId == null
          ? null
          : () => _navigate(
              MiniAppLocation(view.detailPageId!, recordId: item.id),
            ),
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 760 ? 14 : 18,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (workflow != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: IconButton(
                  tooltip: _actionLabel(workflow, item),
                  onPressed: _saving || _pendingCommand != null
                      ? null
                      : () => _run(workflow, item),
                  icon: Icon(
                    _workflowIcon(workflow, item),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _editableField(
                    context,
                    view,
                    titleFieldId,
                    Text(
                      collection.field(titleFieldId).type == FieldType.image
                          ? 'Image record'
                          : '${item.data[titleFieldId] ?? 'Untitled'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    pageId: page.id,
                  ),
                  if (item.capacity != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: CapacitySummary(item: item),
                    ),
                  if (fields.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        for (final field in fields)
                          _editableField(
                            context,
                            view,
                            field.id,
                            field.type == FieldType.image
                                ? SizedBox(
                                    width: 80,
                                    child: _PrivateImage(
                                      adapter: adapter,
                                      assetId: '${item.data[field.id]}',
                                      label: field.label,
                                      height: 64,
                                    ),
                                  )
                                : Text(
                                    field.type == FieldType.timestamp
                                        ? '${field.label}: ${_displayDate(context, '${item.data[field.id]}')}'
                                        : '${field.label}: ${item.data[field.id]}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                            pageId: page.id,
                          ),
                      ],
                    ),
                  ],
                  if (inlineActions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final action in inlineActions)
                            OutlinedButton(
                              onPressed: _saving || _pendingCommand != null
                                  ? null
                                  : () => _run(action, item, source: view),
                              child: Text(_actionLabel(action, item)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (view.detailPageId != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(Icons.chevron_right, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _details(BuildContext context, ViewSpec view, RuntimeItem item) {
    final collection = spec.collection(item.collectionId);
    final titleFieldId = view.titleFieldId ?? collection.fields.first.id;
    final fields = view.fieldIds.isEmpty
        ? collection.fields
        : view.fieldIds.map(collection.field);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(_space(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _editableField(
              context,
              view,
              titleFieldId,
              Text(
                collection.field(titleFieldId).type == FieldType.image
                    ? 'Image record'
                    : '${item.data[titleFieldId] ?? 'Untitled'}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              pageId: page.id,
            ),
            const SizedBox(height: 24),
            if (item.capacity != null)
              Padding(
                padding: EdgeInsets.only(bottom: _space(context, 20)),
                child: CapacitySummary(item: item),
              ),
            for (final field in fields.where((f) => f.id != titleFieldId))
              Padding(
                padding: EdgeInsets.only(bottom: _space(context, 20)),
                child: _editableField(
                  context,
                  view,
                  field.id,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field.label,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      if (field.type == FieldType.image &&
                          item.data[field.id] != null)
                        _PrivateImage(
                          adapter: adapter,
                          assetId: '${item.data[field.id]}',
                          label: field.label,
                          thumbnail: false,
                        )
                      else
                        Text(
                          item.data[field.id] == null
                              ? 'Not set'
                              : field.type == FieldType.timestamp
                              ? _displayDate(context, '${item.data[field.id]}')
                              : '${item.data[field.id]}',
                        ),
                    ],
                  ),
                  pageId: page.id,
                ),
              ),
            if (_reminder != null)
              for (final reminder in _reminder!)
                Padding(
                  padding: EdgeInsets.only(bottom: _space(context, 20)),
                  child: Text(_reminderText(reminder)),
                ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final action in _recordActions(view, item))
                  OutlinedButton(
                    onPressed: _saving || _pendingCommand != null
                        ? null
                        : () => _run(action, item, source: view),
                    child: Text(_actionLabel(action, item)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _reminderText(RuntimeReminderState reminder) {
    final description = switch (reminder.state) {
      'unset' => 'No reminder set',
      'disabled' =>
        'Reminders are off. Enable this rule in publication review.',
      'unenrolled' => 'This record is not enrolled. Review existing records when publishing the rule.',
      'pending' =>
        reminder.eligible
            ? 'Reminder scheduled'
            : 'Reminder pending · delivery requires an eligible status',
      'delivered' => 'Reminder delivered to your AppNest inbox',
      'suppressed' => 'Reminder suppressed',
      'failed' => 'Reminder could not be delivered',
      _ => 'Reminder status unavailable',
    };
    return '${adapter.preview ? 'Simulated preview · ' : ''}$description';
  }
}
