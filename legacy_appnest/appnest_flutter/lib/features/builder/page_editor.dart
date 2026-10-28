import 'package:appnest_spec/appnest_spec.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:flutter/material.dart';

import 'appearance_editor.dart';
import 'component_options_editor.dart';

/// Edits semantic definitions; no widget code or executable expressions.
class PageEditor extends StatefulWidget {
  final AppSpec spec;
  final PreviewRuntimeAdapter? preview;
  final MiniAppLocation? location;
  final Future<String?> Function()? uploadImage;
  const PageEditor({
    super.key,
    required this.spec,
    this.uploadImage,
    this.preview,
    this.location,
  });
  @override
  State<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  String mode = 'Pages';
  String? selectedPage, selectedView, primaryAction, entryPage;
  String? pageLayout;
  Map<String, dynamic>? appearance;
  String viewType = 'list', collectionId = '';
  String? presentation = 'compact';
  String? titleField, groupField, detailPage, formPage;
  String? sortField, dateField;
  String datePeriod = 'today';
  bool descending = false, addTab = false;
  bool filtersChanged = false, sortChanged = false;
  final defaultFilters = <String, String>{};
  final extraFilters = <Map<String, dynamic>>[];
  final secondarySort = <Map<String, dynamic>>[];
  final title = TextEditingController();
  final viewLabel = TextEditingController();
  final sectionIds = <String>[];
  final fieldIds = <String>[], filterIds = <String>[], actionIds = <String>[];
  final pageOrder = <String>[];
  final tabs = <Map<String, dynamic>>[];
  Map<String, dynamic> componentOptions = {};
  bool showDate = false, ordering = false;
  String? failure;
  AppSpec get spec => widget.spec;

  @override
  void initState() {
    super.initState();
    appearance = spec.appearance?.toJson();
    final nav = spec.navigation;
    entryPage = nav?.entryPageId;
    pageOrder.addAll(nav?.pages.map((p) => p.id) ?? []);
    tabs.addAll(
      nav?.tabs.map((t) => Map<String, dynamic>.from(t.toJson())) ?? [],
    );
    _selectPage(nav?.pages.firstOrNull?.id);
    _selectView(spec.views.first.id);
  }

  @override
  void dispose() {
    title.dispose();
    viewLabel.dispose();
    super.dispose();
  }

  void _selectPage(String? id) {
    selectedPage = id;
    final p = id == null ? null : spec.page(id);
    title.text = p?.title ?? '';
    sectionIds
      ..clear()
      ..addAll(p?.viewIds ?? []);
    showDate = p?.showDate ?? false;
    pageLayout = p?.layout;
    addTab = false;
    primaryAction = p?.primaryActionId;
    failure = null;
  }

  void _selectView(String? id) {
    selectedView = id;
    final v = id == null ? null : spec.view(id);
    collectionId = v == null || v.collectionId.isEmpty
        ? spec.collections.firstOrNull?.id ?? ''
        : v.collectionId;
    viewType = v?.type ?? (spec.collections.isEmpty ? 'clock' : 'list');
    componentOptions = Map<String, dynamic>.from(v?.options ?? {});
    viewLabel.text = v?.label ?? '';
    titleField = v?.titleFieldId;
    groupField = v?.groupByFieldId;
    presentation = v == null ? 'compact' : v.presentation;
    filtersChanged = false;
    sortChanged = false;
    detailPage = v?.detailPageId;
    formPage = v?.formPageId;
    sortField =
        (v?.query?['sort'] as List?)?.firstOrNull?['fieldId'] as String?;
    descending =
        (v?.query?['sort'] as List?)?.firstOrNull?['descending'] == true;
    secondarySort
      ..clear()
      ..addAll(
        (v?.query?['sort'] as List? ?? [])
            .skip(1)
            .map((s) => Map<String, dynamic>.from(s as Map)),
      );
    dateField = v?.dateFilter?.fieldId;
    datePeriod = v?.dateFilter?.period ?? 'today';
    defaultFilters.clear();
    extraFilters.clear();
    for (final filter in v?.query?['filters'] as List? ?? []) {
      final f = Map<String, dynamic>.from(filter as Map);
      if (f['operator'] == 'eq' &&
          f['value'] is String &&
          spec.collection(collectionId).field(f['fieldId'] as String).type ==
              FieldType.choice) {
        final fieldId = f['fieldId'] as String;
        if (defaultFilters.containsKey(fieldId)) {
          extraFilters.add(f);
        } else {
          defaultFilters[fieldId] = f['value'] as String;
        }
      } else {
        extraFilters.add(f);
      }
    }
    fieldIds
      ..clear()
      ..addAll(v?.fieldIds ?? []);
    filterIds
      ..clear()
      ..addAll(v?.filterFieldIds ?? []);
    actionIds
      ..clear()
      ..addAll(v?.actionIds ?? []);
  }

  void _move(List<dynamic> list, int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= list.length) return;
    setState(() {
      final item = list.removeAt(index);
      list.insert(target, item);
    });
  }

  void _changeType(String value) {
    if (value == viewType) return;
    viewType = value;
    componentOptions = _defaultOptions(value);
    if (isContentComponent(value)) {
      titleField = groupField = detailPage = formPage = dateField = sortField =
          null;
      fieldIds.clear();
      filterIds.clear();
      actionIds.clear();
      defaultFilters.clear();
      extraFilters.clear();
      secondarySort.clear();
      presentation = null;
      filtersChanged = sortChanged = true;
    }
  }

  Map<String, dynamic> _defaultOptions(String type) => switch (type) {
    'chart' => {'style': 'bar', 'metric': 'count'},
    'metric' => {'metric': 'count'},
    'banner' => {
      'title': viewLabel.text.isEmpty ? 'Welcome' : viewLabel.text,
    },
    'richText' => {'markdown': 'Write something helpful for your app.'},
    'clock' => {
      'style': 'digital',
      'hourFormat': 'system',
      'showSeconds': false,
      'showDate': true,
    },
    'timer' => {'durationMinutes': 25},
    'deviceInfo' => {
      'fields': ['batteryLevel', 'charging'],
    },
    'deviceControl' => {'control': 'flashlight'},
    _ => {},
  };

  void _reconcileFormFields() {
    if (viewType != 'form') return;
    final collection = spec.collection(collectionId);
    final editable = collection.fields
        .where(
          (field) =>
              (fieldIds.isEmpty || fieldIds.contains(field.id)) &&
              !collection.behaviors.any(
                (behavior) =>
                    behavior.type == 'workflow.v1' &&
                    behavior.fieldId == field.id,
              ),
        )
        .map((field) => field.id)
        .toSet();
    final options = Map<String, dynamic>.from(componentOptions);
    if (options['controls'] case final List controls) {
      final retained = [
        for (final control in controls)
          if (editable.contains(control['fieldId']))
            Map<String, dynamic>.from(control as Map),
      ];
      if (retained.isEmpty) {
        options.remove('controls');
      } else {
        options['controls'] = retained;
      }
    }
    if (options['steps'] case final List steps) {
      final assigned = <String>{};
      final retained = <Map<String, dynamic>>[];
      for (final step in steps) {
        final fields = [
          for (final id in step['fieldIds'] as List)
            if (editable.contains(id) && assigned.add(id as String)) id,
        ];
        if (fields.isNotEmpty) {
          retained.add({
            ...Map<String, dynamic>.from(step as Map),
            'fieldIds': fields,
          });
        }
      }
      final added = editable.difference(assigned).toList();
      if (retained.isEmpty && added.isNotEmpty) {
        retained.add({'id': 'step1', 'title': 'Details', 'fieldIds': added});
      } else if (added.isNotEmpty) {
        (retained.last['fieldIds'] as List).addAll(added);
      }
      if (retained.isEmpty) {
        options.remove('steps');
      } else {
        options['steps'] = retained;
      }
    }
    componentOptions = options;
  }

  void _save() {
    final Map<String, dynamic> patch;
    switch (mode) {
      case 'Pages':
        if (ordering) {
          patch = {'type': 'ReorderPages', 'pageIds': pageOrder};
        } else {
          final page = {
            'title': title.text.trim(),
            'viewIds': sectionIds,
            'showDate': showDate,
            if (pageLayout != null) 'layout': pageLayout,
            if (primaryAction != null) 'primaryActionId': primaryAction,
          };
          patch = selectedPage == null
              ? {
                  'type': 'AddPage',
                  'page': page,
                  if (addTab)
                    'tab': {'label': title.text.trim(), 'icon': 'list'},
                }
              : {'type': 'UpdatePage', 'pageId': selectedPage, 'page': page};
        }
      case 'Navigation':
        patch = {
          'type': 'SetNavigation',
          'entryPageId': entryPage,
          'tabs': tabs,
        };
      case 'Views':
        final old = selectedView == null
            ? <String, dynamic>{}
            : spec.view(selectedView!).toJson();
        final query = Map<String, dynamic>.from(
          old['query'] as Map? ?? const {},
        );
        if (filtersChanged) {
          final filters = [
            ...extraFilters,
            for (final f in defaultFilters.entries)
              {'fieldId': f.key, 'operator': 'eq', 'value': f.value},
          ];
          if (filters.isEmpty) {
            query.remove('filters');
          } else {
            query['filters'] = filters;
          }
        }
        if (sortChanged) {
          final sort = [
            if (sortField != null)
              {'fieldId': sortField, 'descending': descending},
            ...secondarySort.where((s) => s['fieldId'] != sortField),
          ];
          if (sort.isEmpty) {
            query.remove('sort');
          } else {
            query['sort'] = sort;
          }
        }
        final view = <String, dynamic>{
          ...old,
          'label': viewLabel.text.trim(),
          'type': viewType,
          'collectionId': collectionId,
          'actionIds': actionIds,
          if (presentation != null) 'presentation': presentation,
          'fieldIds': fieldIds,
          'filterFieldIds': filterIds,
          if (query.isNotEmpty || old.containsKey('query')) 'query': query,
          if (dateField != null)
            'dateFilter': {'fieldId': dateField, 'period': datePeriod},
          if (titleField != null) 'titleFieldId': titleField,
          if (groupField != null) 'groupByFieldId': groupField,
          if (detailPage != null) 'detailPageId': detailPage,
          if (formPage != null) 'formPageId': formPage,
          if (componentOptions.isNotEmpty) 'options': componentOptions,
        }..remove('id');
        if (componentOptions.isEmpty) view.remove('options');
        if (isContentComponent(viewType)) {
          view.removeWhere(
            (key, _) => !{'type', 'label', 'options'}.contains(key),
          );
        }
        if (presentation == null) view.remove('presentation');
        if (titleField == null) view.remove('titleFieldId');
        if (groupField == null) view.remove('groupByFieldId');
        if (detailPage == null) view.remove('detailPageId');
        if (formPage == null) view.remove('formPageId');
        if (dateField == null) view.remove('dateFilter');
        patch = selectedView == null
            ? {'type': 'AddView', 'view': view}
            : {'type': 'UpdateView', 'viewId': selectedView, 'view': view};
      default:
        patch = {'type': 'SetAppearance', 'appearance': appearance};
    }
    try {
      var nextId = 0;
      spec.patch(patch, () => 'editorPreview${nextId++}');
      Navigator.pop(context, patch);
    } catch (e) {
      setState(() => failure = e.toString());
    }
  }

  Widget _select(
    String label,
    String? value,
    Map<String, String> values,
    ValueChanged<String?> changed, {
    bool nullable = false,
    String emptyLabel = 'None',
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value ?? '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (nullable || value == null)
          DropdownMenuItem(value: '', child: Text(emptyLabel)),
        ...values.entries.map(
          (e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (v) => setState(() => changed(v == '' ? null : v)),
    ),
  );

  Widget _ordered(
    List<String> ids,
    Map<String, String> labels, {
    bool removable = true,
  }) => Column(
    children: [
      for (var i = 0; i < ids.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(labels[ids[i]] ?? ids[i]),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Move up',
                onPressed: i == 0 ? null : () => _move(ids, i, -1),
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed: i == ids.length - 1 ? null : () => _move(ids, i, 1),
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              if (removable)
                IconButton(
                  tooltip: 'Remove section',
                  onPressed: () => setState(() => ids.removeAt(i)),
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
        ),
    ],
  );

  Widget _pages() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (spec.navigation != null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reorder pages'),
          value: ordering,
          onChanged: (v) => setState(() => ordering = v),
        ),
      if (ordering)
        _ordered(pageOrder, {
          for (final p in spec.navigation!.pages) p.id: p.title,
        }, removable: false)
      else ...[
        _select(
          'Page',
          selectedPage,
          {
            for (final p in spec.navigation?.pages ?? <PageSpec>[])
              p.id: p.title,
          },
          (v) => _selectPage(v),
          nullable: true,
          emptyLabel: 'New page',
        ),
        if (selectedPage == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Create a page from existing views. Add new views in the Views tab.',
            ),
          ),
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Page title'),
        ),
        if (selectedPage == null && spec.navigation != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Add to tab bar'),
            value: addTab,
            onChanged: spec.navigation!.tabs.length >= 5
                ? null
                : (v) => setState(() => addTab = v),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show local date'),
          value: showDate,
          onChanged: (v) => setState(() => showDate = v),
        ),
        _select(
          'Primary action',
          primaryAction,
          {
            for (final a in spec.actions.where(
              (a) => a.capability == 'records.create.v1',
            ))
              a.id: a.label,
          },
          (v) => primaryAction = v,
          nullable: true,
        ),
        PageLayoutPicker(
          value: pageLayout,
          onChanged: (value) => setState(() => pageLayout = value),
        ),
        const SizedBox(height: 20),
        const Text('Page sections · displayed in this order'),
        _ordered(sectionIds, {
          for (final v in spec.views) v.id: '${v.label} (${v.type})',
        }),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: spec.views
              .where((v) => !sectionIds.contains(v.id))
              .map(
                (v) => ActionChip(
                  key: ValueKey('add-section-${v.id}'),
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text('${v.label} (${v.type})'),
                  onPressed: sectionIds.length >= 8
                      ? null
                      : () => setState(() => sectionIds.add(v.id)),
                ),
              )
              .toList(),
        ),
      ],
    ],
  );

  Widget _navigation() {
    final pages = spec.navigation?.pages ?? <PageSpec>[];
    if (pages.isEmpty) {
      return const Text('Create your first page to configure navigation.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _select('Opening page', entryPage, {
          for (final p in pages) p.id: p.title,
        }, (v) => entryPage = v),
        const Text('Tabs · choose up to five destination pages'),
        const SizedBox(height: 12),
        for (var i = 0; i < tabs.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pages
                              .firstWhere((p) => p.id == tabs[i]['pageId'])
                              .title,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Move tab up',
                        onPressed: i == 0 ? null : () => _move(tabs, i, -1),
                        icon: const Icon(Icons.arrow_upward, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Move tab down',
                        onPressed: i == tabs.length - 1
                            ? null
                            : () => _move(tabs, i, 1),
                        icon: const Icon(Icons.arrow_downward, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Remove tab',
                        onPressed: () => setState(() => tabs.removeAt(i)),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                  TextFormField(
                    key: ValueKey('label-${tabs[i]['pageId']}'),
                    initialValue: tabs[i]['label'] as String,
                    decoration: const InputDecoration(labelText: 'Tab label'),
                    onChanged: (v) => tabs[i]['label'] = v,
                  ),
                  const SizedBox(height: 12),
                  _select('Tab icon', tabs[i]['icon'] as String, {
                    for (final s in [
                      'today',
                      'list',
                      'chart',
                      'book',
                      'board',
                      'people',
                      'spark',
                      'check',
                    ])
                      s: s,
                  }, (v) => tabs[i]['icon'] = v),
                ],
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          children: pages
              .where((p) => !tabs.any((t) => t['pageId'] == p.id))
              .map(
                (p) => ActionChip(
                  label: Text('Add ${p.title}'),
                  onPressed: tabs.length >= 5
                      ? null
                      : () => setState(
                          () => tabs.add({
                            'pageId': p.id,
                            'label': p.title,
                            'icon': 'list',
                          }),
                        ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _views() {
    final col = collectionId.isEmpty ? null : spec.collection(collectionId);
    final pages = {
      for (final p in spec.navigation?.pages ?? <PageSpec>[]) p.id: p.title,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _select(
          'View',
          selectedView,
          {for (final v in spec.views) v.id: v.label},
          (v) => _selectView(v),
          nullable: true,
          emptyLabel: 'New view',
        ),
        TextField(
          controller: viewLabel,
          decoration: const InputDecoration(labelText: 'View label'),
        ),
        const SizedBox(height: 14),
        if (!isContentComponent(viewType))
          _select(
            'Collection',
            collectionId,
            {for (final c in spec.collections) c.id: c.label},
            (v) {
              collectionId = v!;
              componentOptions = _defaultOptions(viewType);
              titleField = null;
              groupField = null;
              detailPage = null;
              formPage = null;
              fieldIds.clear();
              filterIds.clear();
              actionIds.clear();
              sortField = null;
              dateField = null;
              defaultFilters.clear();
              extraFilters.clear();
              secondarySort.clear();
              filtersChanged = true;
              sortChanged = true;
            },
          ),
        _select('Display', viewType, {
          for (final group in componentGroups.values)
            for (final entry in group.entries)
              if (spec.collections.isNotEmpty || isContentComponent(entry.key))
                entry.key: entry.value,
        }, (v) => _changeType(v!)),
        OutlinedButton.icon(
          onPressed: () async {
            final type = await chooseComponent(
              context,
              hasCollections: spec.collections.isNotEmpty,
            );
            if (type != null && mounted) setState(() => _changeType(type));
          },
          icon: const Icon(Icons.widgets_outlined),
          label: const Text('Choose component'),
        ),
        const SizedBox(height: 14),
        ComponentOptionsEditor(
          key: ValueKey(
            'component-options-$selectedView-$viewType-$collectionId',
          ),
          spec: spec,
          type: viewType,
          collectionId: collectionId,
          fieldIds: fieldIds,
          options: componentOptions,
          uploadImage: widget.uploadImage,
          onChanged: (value) => setState(() {
            componentOptions = value;
            final interactiveAction = viewType == 'checklist'
                ? value['actionId']
                : viewType == 'board'
                ? value['moveActionId']
                : null;
            if (interactiveAction is String &&
                !actionIds.contains(interactiveAction)) {
              actionIds.add(interactiveAction);
            }
            if (viewType == 'chart' &&
                (value['dateFieldId'] != null || value['style'] == 'line')) {
              groupField = null;
            }
          }),
        ),
        if (!isContentComponent(viewType)) ...[
          _select(
            'List style',
            presentation,
            const {
              'compact': 'Compact rows',
              'cards': 'Cards',
            },
            (v) => presentation = v,
            nullable: true,
            emptyLabel: 'Default',
          ),
          _select(
            'Title field',
            titleField,
            {for (final f in col!.fields) f.id: f.label},
            (v) => titleField = v,
            nullable: true,
          ),
          _select(
            'Group by',
            groupField,
            {
              for (final f in col.fields.where(
                (f) => f.type == FieldType.choice || f.id == groupField,
              ))
                f.id: f.label,
            },
            (v) => groupField = v,
            nullable: true,
          ),
          _select(
            'Open details page',
            detailPage,
            pages,
            (v) => detailPage = v,
            nullable: true,
          ),
          _select(
            'Sort by',
            sortField,
            {for (final f in col.fields) f.id: f.label},
            (v) {
              sortField = v;
              sortChanged = true;
              if (v == null) secondarySort.clear();
            },
            nullable: true,
          ),
          if (sortField != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Descending order'),
              value: descending,
              onChanged: (v) => setState(() {
                descending = v;
                sortChanged = true;
              }),
            ),
          _select(
            'Date window',
            dateField,
            {
              for (final f in col.fields.where(
                (f) => f.type == FieldType.timestamp,
              ))
                f.id: f.label,
            },
            (v) => dateField = v,
            nullable: true,
          ),
          if (dateField != null)
            _select('Show dates', datePeriod, const {
              'today': 'Today in device timezone',
              'overdue': 'Before today',
            }, (v) => datePeriod = v!),
          for (final f in col.fields.where((f) => f.type == FieldType.choice))
            _select(
              'Only ${f.label.toLowerCase()}',
              defaultFilters[f.id],
              {for (final choice in f.choices) choice: choice},
              (v) {
                filtersChanged = true;
                extraFilters.removeWhere(
                  (filter) =>
                      filter['fieldId'] == f.id && filter['operator'] == 'eq',
                );
                if (v == null) {
                  defaultFilters.remove(f.id);
                } else {
                  defaultFilters[f.id] = v;
                }
              },
              nullable: true,
            ),
          _select(
            'Open editor page',
            formPage,
            pages,
            (v) => formPage = v,
            nullable: true,
          ),
          const Text('Visible fields (empty uses the default)'),
          Wrap(
            spacing: 6,
            children: col.fields
                .map(
                  (f) => FilterChip(
                    label: Text(f.label),
                    selected: fieldIds.contains(f.id),
                    onSelected: (v) => setState(() {
                      v ? fieldIds.add(f.id) : fieldIds.remove(f.id);
                      _reconcileFormFields();
                    }),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          const Text('Filter controls'),
          Wrap(
            spacing: 6,
            children: col.fields
                .where((f) => f.type == FieldType.choice)
                .map(
                  (f) => FilterChip(
                    label: Text(f.label),
                    selected: filterIds.contains(f.id),
                    onSelected: (v) => setState(
                      () => v ? filterIds.add(f.id) : filterIds.remove(f.id),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          const Text('Available actions'),
          Wrap(
            spacing: 6,
            children: spec.actions
                .where((a) => a.collectionId == collectionId)
                .map(
                  (a) => FilterChip(
                    label: Text(a.label),
                    selected: actionIds.contains(a.id),
                    onSelected: (v) => setState(
                      () => v ? actionIds.add(a.id) : actionIds.remove(a.id),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Design your mini-app'),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              children: ['Pages', 'Views', 'Navigation', 'Appearance']
                  .map(
                    (m) => ChoiceChip(
                      label: Text(m),
                      selected: mode == m,
                      onSelected: (_) => setState(() {
                        mode = m;
                        failure = null;
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            switch (mode) {
              'Pages' => _pages(),
              'Views' => _views(),
              'Navigation' => _navigation(),
              _ => AppearanceEditor(
                spec: spec,
                initialValue: appearance,
                preview: widget.preview,
                location: widget.location,
                onChanged: (next) => appearance = next,
              ),
            },
            if (failure != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  failure!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
      FilledButton(onPressed: _save, child: const Text('Update preview')),
    ],
  );
}
