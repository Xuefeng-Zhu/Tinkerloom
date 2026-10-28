part of '../appnest_renderer.dart';

// Keep every receipt-bound value from the original attempt. A refreshed record
// may have a newer revision precisely because the original command committed.
class _RuntimeCommand {
  final ActionSpec action;
  final RuntimeItem? record;
  final Map<String, dynamic> input;
  final String key;
  _RuntimeCommand(this.action, RuntimeItem? item, Map<String, dynamic> data)
    : record = item == null
          ? null
          : RuntimeItem(
              item.id,
              item.collectionId,
              Map<String, dynamic>.from(_copyPreviewValue(item.data) as Map),
              revision: item.revision,
              capacity: item.capacity,
              allocated: item.allocated,
              claimed: item.claimed,
              allowedActions: List.of(item.allowedActions),
            ),
      input = Map<String, dynamic>.from(_copyPreviewValue(data) as Map),
      key = 'ui-${DateTime.now().microsecondsSinceEpoch}-${item?.id ?? 0}';

  Future<void> execute(RuntimeAdapter adapter) => adapter.execute(
    action,
    record,
    Map<String, dynamic>.from(_copyPreviewValue(input) as Map),
    key,
  );
}

class _LegacyMiniAppRuntime extends StatefulWidget {
  final RuntimeAdapter adapter;
  const _LegacyMiniAppRuntime({required this.adapter});
  @override
  State<_LegacyMiniAppRuntime> createState() => __LegacyMiniAppRuntimeState();
}

class __LegacyMiniAppRuntimeState extends State<_LegacyMiniAppRuntime>
    with WidgetsBindingObserver {
  late String viewId;
  RuntimePage? page;
  Object? error;
  bool loading = true, fetching = false, dirty = false, reconnecting = false;
  StreamSubscription<void>? subscription;
  Timer? refreshTimer;
  Timer? reconnectTimer;
  String? filterChoice;
  final filterChoices = <String, String>{};
  String search = '';
  int _request = 0, _accessGeneration = 0;
  ModalRoute<Map<String, dynamic>>? _editorRoute;
  _RuntimeCommand? _pendingCommand;
  RuntimeAdapter get adapter => widget.adapter;
  ViewSpec get view => adapter.spec.views.firstWhere((v) => v.id == viewId);
  @override
  void initState() {
    super.initState();
    viewId = adapter.spec.views.first.id;
    WidgetsBinding.instance.addObserver(this);
    connect();
    refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => refresh(),
    );
  }

  void connect() {
    _request++;
    reconnectTimer?.cancel();
    subscription?.cancel();
    subscription = adapter.watch().listen(
      (_) {
        if (fetching) {
          dirty = true;
        } else {
          refresh();
        }
      },
      onError: (Object e) {
        _invalidate(e);
        if (mounted)
          setState(() {
            reconnecting = true;
          });
        reconnectTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) connect();
        });
      },
      onDone: () {
        _invalidate(StateError('The connection was interrupted.'));
        if (mounted) setState(() => reconnecting = true);
        reconnectTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) connect();
        });
      },
    );
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) connect();
  }

  @override
  void dispose() {
    _dismissEditor();
    subscription?.cancel();
    refreshTimer?.cancel();
    reconnectTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> refresh({bool next = false}) async {
    if (fetching) {
      dirty = true;
      return;
    }
    fetching = true;
    final request = ++_request;
    try {
      dirty = false;
      final col = adapter.spec.collection(view.collectionId);
      final choice = col.fields
          .where((f) => f.type == FieldType.choice)
          .firstOrNull;
      final configured = view.configured;
      final configuredQuery = resolveViewQuery(adapter.spec, view);
      final result = await adapter.query(view.collectionId, {
        ...configuredQuery,
        if (!configured) 'limit': 50,
        'filters': [
          ...configuredQuery['filters'] as List,
          if (search.isNotEmpty && _searchAllowed)
            {
              'fieldId': view.titleFieldId,
              'operator': 'contains',
              'value': search,
            },
          if (!configured && filterChoice != null && choice != null)
            {'fieldId': choice.id, 'operator': 'eq', 'value': filterChoice},
          if (configured)
            for (final entry in filterChoices.entries)
              {'fieldId': entry.key, 'operator': 'eq', 'value': entry.value},
        ],
        if (next && page?.cursor != null) 'cursor': page!.cursor,
      });
      if (mounted && request == _request)
        setState(() {
          page = result;
          error = null;
          loading = false;
          reconnecting = false;
        });
    } catch (e) {
      if (mounted && request == _request) _invalidate(e);
    } finally {
      fetching = false;
      if (dirty && mounted) refresh();
    }
  }

  bool get _searchAllowed {
    if (view.type == 'summary' || view.titleFieldId == null) return false;
    if (adapter.spec
            .collection(view.collectionId)
            .field(view.titleFieldId!)
            .type !=
        FieldType.text)
      return false;
    final filters = resolveViewQuery(adapter.spec, view)['filters'] as List;
    return filters.length + (view.configured ? view.filterFieldIds.length : 1) <
        Limits.filters;
  }

  void _dismissEditor() {
    final route = _editorRoute;
    _editorRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  void _invalidate(Object issue) {
    _request++;
    _accessGeneration++;
    dirty = false;
    _dismissEditor();
    if (!mounted) return;
    setState(() {
      error = issue;
      loading = false;
      page = null;
    });
  }

  Future<Map<String, dynamic>?> _actionDialog(WidgetBuilder builder) async {
    try {
      return await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) {
          _editorRoute = ModalRoute.of<Map<String, dynamic>>(dialogContext);
          return builder(dialogContext);
        },
      );
    } finally {
      _editorRoute = null;
    }
  }

  Future<void> run(ActionSpec action, RuntimeItem? item) async {
    if (_pendingCommand != null || loading) return;
    final accessGeneration = _accessGeneration;
    final edit = _VisualEditScope.of(context);
    if (edit != null) {
      edit.onSelect(MiniAppEditTarget(MiniAppEditKind.section, view.id));
      return;
    }
    Map<String, dynamic>? input;
    final col = adapter.spec.collection(action.collectionId);
    if (action.capability == 'records.create.v1' ||
        action.capability == 'records.patch.v1') {
      input = await _actionDialog(
        (context) => RecordForm(
          collection: col,
          adapter: adapter,
          record: item,
          initial: item?.data,
          fieldIds: view.type == 'form' ? view.fieldIds : const [],
          members: adapter.members,
          capacity: item?.capacity,
        ),
      );
    } else if (action.capability == 'capacity.configure.v1') {
      input = await _actionDialog(
        (context) => _ValueDialog(
          label: 'Capacity',
          initial: '${item?.capacity ?? 1}',
          numeric: true,
        ),
      );
      if (input != null)
        input = {'capacity': int.tryParse(input['value'].toString())};
    } else if (action.capability == 'assignment.assign.v1' ||
        action.capability == 'workflow.transition.v1') {
      final b = col.behavior(action.behaviorId!);
      final values = action.capability == 'assignment.assign.v1'
          ? await adapter.members()
          : b.transitions[item?.data[b.fieldId]] ?? [];
      if (!mounted || accessGeneration != _accessGeneration) return;
      input = await _actionDialog(
        (context) => _ChoiceDialog(label: action.label, values: values),
      );
    } else {
      input = {};
    }
    if (input == null || !mounted || accessGeneration != _accessGeneration)
      return;
    await _execute(_RuntimeCommand(action, item, input));
  }

  Future<void> _execute(_RuntimeCommand command) async {
    // Never imply a place is reserved until execute has returned successfully.
    final recovering = _pendingCommand != null;
    setState(() => loading = true);
    try {
      await command.execute(adapter);
      _pendingCommand = null;
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(adapter.preview ? 'Simulated in preview' : 'Saved'),
          ),
        );
      await refresh();
    } catch (e) {
      if (mounted)
        setState(() {
          error = e;
          loading = false;
          _pendingCommand = recovering || adapter.commandMayHaveSucceeded(e)
              ? command
              : null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = adapter.spec.collection(view.collectionId),
        choice = col.fields
            .where((f) => f.type == FieldType.choice)
            .firstOrNull;
    final create = adapter.spec.actions
        .where(
          (a) =>
              a.collectionId == col.id &&
              a.capability == 'records.create.v1' &&
              adapter.permits(a),
        )
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_pendingCommand case final command?)
          MaterialBanner(
            content: Semantics(
              liveRegion: true,
              child: const Text(
                'Save outcome unconfirmed. Retry the original request to check whether it was saved.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => _execute(command),
                child: Text(loading ? 'Checking save…' : 'Retry save'),
              ),
            ],
          ),
        if (adapter.preview && _VisualEditScope.of(context) == null)
          const MaterialBanner(
            content: Text(
              'Preview · Synthetic records. Actions stay in this preview.',
            ),
            actions: [SizedBox.shrink()],
          ),
        if (adapter.readOnly)
          MaterialBanner(
            content: Text(adapter.readOnlyMessage),
            actions: const [SizedBox.shrink()],
          ),
        if (reconnecting)
          TextButton.icon(
            onPressed: connect,
            icon: const Icon(Icons.sync),
            label: const Text('Reconnecting — refresh connection'),
          ),
        Padding(
          padding: EdgeInsets.all(_space(context, 16)),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: viewId,
                items: adapter.spec.views
                    .map(
                      (v) => DropdownMenuItem(
                        value: v.id,
                        child: Text(_recordSectionLabel(adapter.spec, v)),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id != null)
                    setState(() {
                      viewId = id;
                      _request++;
                      page = null;
                      filterChoice = null;
                      filterChoices.clear();
                      search = '';
                    });
                  refresh();
                },
              ),
              if (create != null)
                FilledButton.icon(
                  onPressed: loading || _pendingCommand != null
                      ? null
                      : () => run(create, null),
                  icon: const Icon(Icons.add),
                  label: Text(create.label),
                ),
              if (!view.configured &&
                  choice != null &&
                  _VisualEditScope.of(context) == null)
                DropdownButton<String>(
                  hint: const Text('All statuses'),
                  value: filterChoice,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All statuses'),
                    ),
                    ...choice.choices.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => filterChoice = v == '' ? null : v);
                    refresh();
                  },
                ),
              if (view.configured && _VisualEditScope.of(context) == null)
                for (final id in view.filterFieldIds)
                  DropdownButton<String>(
                    key: ValueKey('filter-${view.id}-$id'),
                    hint: Text('All ${col.field(id).label.toLowerCase()}'),
                    value: filterChoices[id] ?? '',
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text('All ${col.field(id).label.toLowerCase()}'),
                      ),
                      for (final value in col.field(id).choices)
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) {
                      setState(() {
                        if (value == null || value.isEmpty)
                          filterChoices.remove(id);
                        else
                          filterChoices[id] = value;
                        page = null;
                        _request++;
                      });
                      refresh();
                    },
                  ),
              IconButton(
                tooltip: 'Refresh records',
                onPressed: () => refresh(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_VisualEditScope.of(context) == null && _searchAllowed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter records…',
              ),
              onSubmitted: (v) {
                search = v;
                page = null;
                _request++;
                refresh();
              },
            ),
          ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: EdgeInsets.all(_space(context, 16)),
            child: Text(
              adapter.errorMessage(error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _EditTarget(
            target: MiniAppEditTarget(MiniAppEditKind.section, view.id),
            child: _VisualEditScope.of(context) != null && view.type == 'form'
                ? SingleChildScrollView(
                    padding: EdgeInsets.all(_space(context, 16)),
                    child: _editForm(adapter.spec, view),
                  )
                : page == null
                ? Center(
                    child: Text(loading ? 'Loading…' : 'Refresh to try again.'),
                  )
                : view.type == 'form'
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _recordSectionLabel(adapter.spec, view),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 16),
                        for (final a
                            in view.actionIds
                                .map(adapter.spec.action)
                                .where(
                                  (a) =>
                                      a.capability == 'records.create.v1' &&
                                      adapter.permits(a),
                                ))
                          ActionButton(
                            action: a,
                            onPressed: loading ? null : () => run(a, null),
                          ),
                      ],
                    ),
                  )
                : page!.items.isEmpty
                ? const Center(
                    child: Text('A fresh start. Add the first record.'),
                  )
                : AbsorbPointer(
                    absorbing: loading || _pendingCommand != null,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(_space(context, 16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (view.type == 'summary')
                            Summary(
                              items: page!.items,
                              total: page!.total,
                              groupField: view.groupByFieldId,
                            )
                          else if (view.type == 'board')
                            StatusBoard(
                              spec: adapter.spec,
                              view: view,
                              items: page!.items,
                              onAction: run,
                            )
                          else
                            RecordList(
                              spec: adapter.spec,
                              view: view,
                              items: page!.items,
                              onAction: run,
                            ),
                          const SizedBox(height: 12),
                          Text('${page!.total} records'),
                          if (page!.cursor != null)
                            TextButton(
                              onPressed: () => refresh(next: true),
                              child: const Text('Next page'),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
