import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';

import 'appearance_editor.dart';
import 'visual_edit_session.dart';
import 'component_options_editor.dart';

Map<String, dynamic> editPage(
  AppSpec spec,
  String id,
  Map<String, dynamic> values,
) => {
  'type': 'UpdatePage',
  'pageId': id,
  'page': (spec.page(id).toJson()..remove('id'))..addAll(values),
};
Map<String, dynamic> editView(
  AppSpec spec,
  String id,
  Map<String, dynamic> values,
) => {
  'type': 'UpdateView',
  'viewId': id,
  'view': (spec.view(id).toJson()..remove('id'))..addAll(values),
};

class VisualInspector extends StatefulWidget {
  final MiniAppEditTarget target;
  final VisualEditSession session;
  final VoidCallback onClose, onReload;
  final bool mobile;
  final PreviewRuntimeAdapter? preview;
  final MiniAppLocation? location;
  final ValueChanged<MiniAppEditTarget>? onSelectTarget;
  final Future<String?> Function()? uploadImage;
  const VisualInspector({
    super.key,
    required this.target,
    required this.session,
    required this.onClose,
    required this.onReload,
    this.mobile = false,
    this.preview,
    this.location,
    this.onSelectTarget,
    this.uploadImage,
  });
  @override
  State<VisualInspector> createState() => _VisualInspectorState();
}

class _VisualInspectorState extends State<VisualInspector> {
  late final TextEditingController label;
  final _optionEdits = <String, dynamic>{};
  bool _groupEdited = false;
  String? _group;
  MiniAppEditTarget get target => widget.target;
  VisualEditSession get session => widget.session;
  String name(AppSpec spec) => switch (target.kind) {
    MiniAppEditKind.app => spec.name,
    MiniAppEditKind.page => spec.page(target.id).title,
    MiniAppEditKind.section => spec.view(target.id).label,
    MiniAppEditKind.field =>
      spec.collection(target.collectionId!).field(target.id).label,
  };
  @override
  void initState() {
    super.initState();
    label = TextEditingController(text: name(session.spec));
  }

  @override
  void dispose() {
    label.dispose();
    super.dispose();
  }

  void change(
    String property,
    VisualPatch patch, {
    bool immediate = true,
  }) => session.enqueue(
    '${target.kind.name}:${target.collectionId}:${target.pageId}:${target.id}:$property',
    patch,
    immediate: immediate,
  );
  void rename(String value) => change(
    'label',
    (spec) => switch (target.kind) {
      MiniAppEditKind.app => {
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': value.trim(),
      },
      MiniAppEditKind.field => {
        'type': 'RenameField',
        'collectionId': target.collectionId,
        'fieldId': target.id,
        'label': value.trim(),
      },
      MiniAppEditKind.page => editPage(spec, target.id, {
        'title': value.trim(),
      }),
      MiniAppEditKind.section => editView(spec, target.id, {
        'label': value.trim(),
      }),
    },
    immediate: false,
  );

  void move(int delta) {
    change('order', (spec) {
      final ids = target.pageId == null
          ? spec.views.map((v) => v.id).toList()
          : [...spec.page(target.pageId!).viewIds];
      final index = ids.indexOf(target.id),
          next = ids.indexOf(target.id) + delta;
      if (index < 0 || next < 0 || next >= ids.length) {
        throw const SpecException('Section cannot move further');
      }
      ids.removeAt(index);
      ids.insert(next, target.id);
      return target.pageId == null
          ? {'type': 'ReorderView', 'viewIds': ids}
          : editPage(spec, target.pageId!, {'viewIds': ids});
    });
  }

  Map<String, dynamic> componentOptions(ViewSpec view) {
    final options = Map<String, dynamic>.from(view.options);
    for (final edit in _optionEdits.entries) {
      if (edit.value == null) {
        options.remove(edit.key);
      } else {
        options[edit.key] = edit.value;
      }
    }
    return options;
  }

  // Bindings and options can be temporarily invalid while edited together.
  // Keep one cumulative intent so the final configuration validates atomically,
  // and rapid changes do not replace earlier edits still awaiting a save.
  void saveComponent() {
    final edits = Map<String, dynamic>.from(_optionEdits);
    final groupEdited = _groupEdited, group = _group;
    change('component', (latest) {
      final view = latest.view(target.id).toJson()..remove('id');
      final options = Map<String, dynamic>.from(view['options'] as Map? ?? {});
      for (final edit in edits.entries) {
        if (edit.value == null) {
          options.remove(edit.key);
        } else {
          options[edit.key] = edit.value;
        }
      }
      if (options.isEmpty) {
        view.remove('options');
      } else {
        view['options'] = options;
      }
      final actionId = switch (view['type']) {
        'checklist' => options['actionId'],
        'board' => options['moveActionId'],
        _ => null,
      };
      if (actionId != null) {
        view['actionIds'] = {
          ...view['actionIds'] as List? ?? [],
          actionId,
        }.toList();
      }
      if (groupEdited) {
        if (group == null) {
          view.remove('groupByFieldId');
        } else {
          view['groupByFieldId'] = group;
        }
      }
      return {'type': 'UpdateView', 'viewId': target.id, 'view': view};
    }, immediate: false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      AppSpec spec;
      try {
        spec = session.projected;
      } catch (_) {
        spec = session.spec;
      }
      final section = target.kind == MiniAppEditKind.section
          ? spec.view(target.id)
          : null;
      final options = section == null
          ? <String, dynamic>{}
          : componentOptions(section);
      final group = _groupEdited ? _group : section?.groupByFieldId;
      final order = target.pageId == null
          ? spec.views.map((v) => v.id).toList()
          : spec.page(target.pageId!).viewIds;
      return Material(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(
                    widget.mobile ? 'Back to preview' : 'Back to chat',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Edit ${target.kind.name}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                session.status,
                semanticsLabel: 'Save status: ${session.status}',
                style: TextStyle(
                  color:
                      session.error != null || session.validationError != null
                      ? Theme.of(context).colorScheme.error
                      : const Color(0xff507963),
                ),
              ),
              if (session.error != null)
                Wrap(
                  spacing: 8,
                  children: [
                    if (!session.conflict)
                      TextButton(
                        onPressed: session.saving
                            ? null
                            : () => session.flush(retry: true),
                        child: const Text('Retry'),
                      ),
                    TextButton(
                      onPressed: session.saving ? null : widget.onReload,
                      child: Text(
                        session.conflict
                            ? 'Reload latest draft'
                            : 'Discard local changes',
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              Focus(
                onFocusChange: (focused) {
                  if (!focused) session.flush();
                },
                child: TextField(
                  key: const ValueKey('visual-label'),
                  controller: label,
                  enabled: !session.conflict,
                  decoration: InputDecoration(
                    labelText: target.kind == MiniAppEditKind.app
                        ? 'App name'
                        : target.kind == MiniAppEditKind.page
                        ? 'Page title'
                        : 'Label',
                    errorText: label.text.trim().isEmpty
                        ? 'Enter a label'
                        : label.text.length > 160
                        ? 'Use 160 characters or fewer'
                        : null,
                  ),
                  onChanged: rename,
                  onSubmitted: (_) => session.flush(),
                ),
              ),
              const SizedBox(height: 12),
              if (target.kind == MiniAppEditKind.field)
                const Text(
                  'This label changes everywhere this field appears. Sample values stay the same.',
                ),
              if (target.kind == MiniAppEditKind.page) ...[
                const Text('Your tab label stays the same.'),
                const SizedBox(height: 20),
                PageLayoutPicker(
                  value: spec.page(target.id).layout,
                  onChanged: session.conflict
                      ? null
                      : (layout) => change(
                          'layout',
                          (s) => editPage(s, target.id, {'layout': layout}),
                        ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show date'),
                  value: spec.page(target.id).showDate,
                  onChanged: session.conflict
                      ? null
                      : (v) => change(
                          'date',
                          (s) => editPage(s, target.id, {'showDate': v}),
                        ),
                ),
              ],
              if (target.kind == MiniAppEditKind.app) ...[
                const SizedBox(height: 20),
                AppearanceEditor(
                  spec: spec,
                  preview: widget.preview,
                  location: widget.location,
                  enabled: !session.conflict,
                  onChanged: (appearance) => change(
                    'appearance',
                    (_) => {'type': 'SetAppearance', 'appearance': appearance},
                    immediate: false,
                  ),
                ),
                const SizedBox(height: 20),
                const Text('App icon'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final icon in [
                      'book',
                      'board',
                      'people',
                      'spark',
                      'check',
                    ])
                      ChoiceChip(
                        label: Text(icon),
                        selected: spec.icon == icon,
                        onSelected: session.conflict
                            ? null
                            : (_) => change(
                                'icon',
                                (s) => {
                                  'type': 'SetTheme',
                                  'theme': s.theme,
                                  'icon': icon,
                                },
                              ),
                      ),
                  ],
                ),
                if (widget.onSelectTarget != null &&
                    spec.views.any((view) => view.type == 'banner')) ...[
                  const SizedBox(height: 20),
                  const Text('Banners & images'),
                  for (final banner in spec.views.where(
                    (view) => view.type == 'banner',
                  ))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: session.conflict
                            ? null
                            : () => widget.onSelectTarget!(
                                MiniAppEditTarget(
                                  MiniAppEditKind.section,
                                  banner.id,
                                  pageId: spec.navigation?.pages
                                      .where(
                                        (page) =>
                                            page.viewIds.contains(banner.id),
                                      )
                                      .firstOrNull
                                      ?.id,
                                ),
                              ),
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: Text('Edit ${banner.label}'),
                      ),
                    ),
                ],
              ],
              if (section != null) ...[
                ComponentOptionsEditor(
                  key: ValueKey('inspector-options-${section.id}'),
                  spec: spec,
                  type: section.type,
                  collectionId: section.collectionId,
                  fieldIds: section.fieldIds,
                  options: options,
                  enabled: !session.conflict,
                  uploadImage: widget.uploadImage,
                  onChanged: (next) {
                    final previous = options;
                    final changedKeys = {...previous.keys, ...next.keys}
                        .where(
                          (key) =>
                              canonicalJson(previous[key]) !=
                              canonicalJson(next[key]),
                        )
                        .toSet();
                    for (final key in changedKeys) {
                      _optionEdits[key] = next[key];
                    }
                    if (section.type == 'chart' &&
                        (next['dateFieldId'] != null ||
                            next['style'] == 'line')) {
                      _groupEdited = true;
                      _group = null;
                    }
                    saveComponent();
                  },
                ),
                if (!section.contentOnly &&
                    {'chart', 'board', 'summary'}.contains(section.type))
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'inspector-group-$group',
                      ),
                      initialValue: group ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Group by'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('None')),
                        for (final field
                            in spec
                                .collection(section.collectionId)
                                .fields
                                .where(
                                  (f) =>
                                      f.type == FieldType.choice ||
                                      f.id == section.groupByFieldId,
                                ))
                          DropdownMenuItem(
                            value: field.id,
                            child: Text(field.label),
                          ),
                      ],
                      onChanged: session.conflict
                          ? null
                          : (value) {
                              _groupEdited = true;
                              _group = value == null || value.isEmpty
                                  ? null
                                  : value;
                              if (_group != null && section.type == 'chart') {
                                for (final key in [
                                  'dateFieldId',
                                  'bucket',
                                  'periods',
                                ]) {
                                  _optionEdits[key] = null;
                                }
                                if (options['style'] == 'line') {
                                  _optionEdits['style'] = 'bar';
                                }
                              }
                              saveComponent();
                            },
                    ),
                  ),
                if (!section.contentOnly &&
                    {
                      'table',
                      'imageCards',
                      'gallery',
                      'timeline',
                    }.contains(section.type)) ...[
                  const SizedBox(height: 12),
                  const Text('Visible fields'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final field
                          in spec.collection(section.collectionId).fields)
                        FilterChip(
                          label: Text(field.label),
                          selected: section.fieldIds.contains(field.id),
                          onSelected: session.conflict
                              ? null
                              : (selected) => change('field-${field.id}', (
                                  latest,
                                ) {
                                  final fields = [
                                    ...latest.view(target.id).fieldIds,
                                  ];
                                  if (selected && !fields.contains(field.id)) {
                                    fields.add(field.id);
                                  }
                                  if (!selected) fields.remove(field.id);
                                  return editView(latest, target.id, {
                                    'fieldIds': fields,
                                  });
                                }),
                        ),
                    ],
                  ),
                ],
                if (spec.navigation != null &&
                    {'list', 'capacity', 'action'}.contains(section.type)) ...[
                  const SizedBox(height: 20),
                  const Text('Layout'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final style in ['compact', 'cards'])
                        ChoiceChip(
                          label: Text(style),
                          selected:
                              (section.presentation ?? 'compact') == style,
                          onSelected: session.conflict
                              ? null
                              : (_) => change(
                                  'presentation',
                                  (s) => editView(s, target.id, {
                                    'presentation': style,
                                  }),
                                ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  target.pageId == null
                      ? 'View order'
                      : 'Section order on this page',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          session.pending ||
                              session.conflict ||
                              order.indexOf(target.id) <= 0
                          ? null
                          : () => move(-1),
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('Move up'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          session.pending ||
                              session.conflict ||
                              order.indexOf(target.id) >= order.length - 1
                          ? null
                          : () => move(1),
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('Move down'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Changes save automatically to this draft. Publish when you’re ready.',
              ),
            ],
          ),
        ),
      );
    },
  );
}
