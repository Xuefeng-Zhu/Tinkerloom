import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';

const componentGroups = <String, Map<String, String>>{
  'Mobile features': {
    'deviceInfo': 'Device information',
    'deviceControl': 'Phone control',
  },
  'Everyday utilities': {'clock': 'Clock', 'timer': 'Focus timer'},
  'Data and planning': {
    'list': 'List',
    'table': 'Table',
    'calendar': 'Calendar',
    'timeline': 'Timeline',
    'chart': 'Chart',
    'metric': 'Metric & progress',
    'summary': 'Summary',
  },
  'Visual content': {
    'imageCards': 'Image cards',
    'gallery': 'Gallery',
    'banner': 'Banner',
    'richText': 'Formatted text',
  },
  'Forms and interaction': {
    'form': 'Form',
    'details': 'Details',
    'checklist': 'Checklist',
    'board': 'Workflow board',
    'capacity': 'Capacity',
    'action': 'Actions',
  },
};

bool isContentComponent(String type) => const {
  'banner',
  'richText',
  'clock',
  'timer',
  'deviceInfo',
  'deviceControl',
}.contains(type);

Future<String?> chooseComponent(
  BuildContext context, {
  bool hasCollections = true,
}) => showDialog<String>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Choose a component'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in componentGroups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  group.key,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final component in group.value.entries)
                    if (hasCollections || isContentComponent(component.key))
                      ActionChip(
                        label: Text(component.value),
                        onPressed: () => Navigator.pop(context, component.key),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  ),
);

/// The same bounded configuration controls are used in the page editor and
/// inspector. Its owner decides whether changes are local or revision queued.
class ComponentOptionsEditor extends StatefulWidget {
  final AppSpec spec;
  final String type;
  final String collectionId;
  final List<String> fieldIds;
  final Map<String, dynamic> options;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Future<String?> Function()? uploadImage;
  final bool enabled;
  const ComponentOptionsEditor({
    super.key,
    required this.spec,
    required this.type,
    required this.collectionId,
    required this.options,
    required this.onChanged,
    this.fieldIds = const [],
    this.uploadImage,
    this.enabled = true,
  });
  @override
  State<ComponentOptionsEditor> createState() => _ComponentOptionsEditorState();
}

class _ComponentOptionsEditorState extends State<ComponentOptionsEditor> {
  bool uploading = false;
  String? error;
  late Map<String, dynamic> _options;
  Map<String, dynamic> get options => _options;
  @override
  void initState() {
    super.initState();
    _options = Map<String, dynamic>.from(widget.options);
  }

  @override
  void didUpdateWidget(ComponentOptionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (canonicalJson(oldWidget.options) != canonicalJson(widget.options) &&
        (canonicalJson(_options) == canonicalJson(oldWidget.options) ||
            canonicalJson(_options) == canonicalJson(widget.options))) {
      _options = Map<String, dynamic>.from(widget.options);
    }
  }

  void notify(Map<String, dynamic> value) {
    setState(() => _options = value);
    widget.onChanged(value);
  }

  CollectionSpec? get collection => isContentComponent(widget.type)
      ? null
      : widget.spec.collection(widget.collectionId);
  List<FieldSpec> get editableFields =>
      collection?.fields
          .where(
            (f) =>
                (widget.fieldIds.isEmpty || widget.fieldIds.contains(f.id)) &&
                !collection!.behaviors.any(
                  (b) => b.type == 'workflow.v1' && b.fieldId == f.id,
                ),
          )
          .toList() ??
      [];

  List<ActionSpec> checklistActions(String? fieldId) {
    final field = collection?.fields.where((f) => f.id == fieldId).firstOrNull;
    if (field == null) return [];
    if (field.type == FieldType.boolean) {
      return widget.spec.actions
          .where(
            (a) =>
                a.collectionId == widget.collectionId &&
                a.capability == 'records.patch.v1',
          )
          .toList();
    }
    if (field.type != FieldType.choice || field.choices.length != 2) return [];
    final workflows = collection!.behaviors.where(
      (behavior) =>
          behavior.type == 'workflow.v1' &&
          behavior.fieldId == field.id &&
          (behavior.transitions[field.choices.first] ?? []).contains(
            field.choices.last,
          ) &&
          (behavior.transitions[field.choices.last] ?? []).contains(
            field.choices.first,
          ),
    );
    return widget.spec.actions
        .where(
          (action) =>
              action.collectionId == widget.collectionId &&
              action.capability == 'workflow.transition.v1' &&
              workflows.any((behavior) => behavior.id == action.behaviorId),
        )
        .toList();
  }

  void change(String key, Object? value) {
    final next = Map<String, dynamic>.from(options);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    if (key == 'metric' && value == 'count') next.remove('valueFieldId');
    if (widget.type == 'chart' && key == 'dateFieldId') {
      if (value == null) {
        next.remove('bucket');
        next.remove('periods');
      } else {
        next['bucket'] ??= 'day';
      }
    }
    if (key == 'style' && value == 'line') next['bucket'] ??= 'day';
    if (key == 'style' && value == 'bar' && next['dateFieldId'] == null) {
      next.remove('bucket');
      next.remove('periods');
    }
    if (key == 'style' && value == 'donut') {
      next['metric'] = 'count';
      for (final field in [
        'dateFieldId',
        'bucket',
        'periods',
        'valueFieldId',
      ]) {
        next.remove(field);
      }
    }
    if (widget.type == 'checklist' && key == 'fieldId') {
      final field = collection?.fields.where((f) => f.id == value).firstOrNull;
      if (field?.type == FieldType.choice) {
        next['checkedValue'] = field!.choices.last;
        next['uncheckedValue'] = field.choices.first;
      } else {
        next.remove('checkedValue');
        next.remove('uncheckedValue');
      }
      final actions = checklistActions(value as String?);
      if (!actions.any((a) => a.id == next['actionId'])) {
        if (actions.isEmpty) {
          next.remove('actionId');
        } else {
          next['actionId'] = actions.first.id;
        }
      }
    }
    if (widget.type == 'checklist' &&
        {'checkedValue', 'uncheckedValue'}.contains(key) &&
        value != null) {
      final field = collection!.field(next['fieldId'] as String);
      next[key == 'checkedValue' ? 'uncheckedValue' : 'checkedValue'] = field
          .choices
          .firstWhere((choice) => choice != value);
    }
    notify(next);
  }

  Widget select(
    String label,
    String key,
    Map<String, String> values, {
    String? fallback,
  }) {
    final value = options[key] as String? ?? fallback;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('component-$key-$value'),
        initialValue: values.containsKey(value) ? value : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: '', child: Text('Choose…')),
          for (final entry in values.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: widget.enabled
            ? (v) => change(key, v == '' ? null : v)
            : null,
      ),
    );
  }

  Widget field(String label, String key, Set<FieldType> types) =>
      select(label, key, {
        for (final f in collection?.fields ?? <FieldSpec>[])
          if (types.contains(f.type)) f.id: f.label,
      });

  Widget text(
    String label,
    String key, {
    bool multiline = false,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey('component-text-$key'),
      initialValue: options[key]?.toString() ?? '',
      enabled: widget.enabled,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 8 : 1,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.multiline,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => change(
        key,
        v.isEmpty
            ? null
            : numeric
            ? num.tryParse(v)
            : v,
      ),
    ),
  );

  Future<void> upload() async {
    setState(() {
      uploading = true;
      error = null;
    });
    try {
      final id = await widget.uploadImage?.call();
      if (id != null && mounted) {
        notify({
          ...options,
          'imageAssetId': id,
          'imageAlt': options['imageAlt'] ?? options['title'] ?? 'Banner image',
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Couldn’t upload the image. Check its format and size, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  List<Map<String, dynamic>> get controls => [
    for (final c in options['controls'] as List? ?? [])
      Map<String, dynamic>.from(c as Map),
  ];
  void setControl(String id, String? kind, [Map<String, dynamic>? values]) {
    final next = controls;
    final index = next.indexWhere((c) => c['fieldId'] == id);
    if (kind == null) {
      if (index >= 0) next.removeAt(index);
    } else {
      final value = <String, dynamic>{
        'fieldId': id,
        'control': kind,
        ...?values,
      };
      if (index < 0) {
        next.add(value);
      } else {
        next[index] = value;
      }
    }
    change('controls', next.isEmpty ? null : next);
  }

  List<Map<String, dynamic>> get steps => [
    for (final s in options['steps'] as List? ?? [])
      Map<String, dynamic>.from(jsonDecode(jsonEncode(s)) as Map),
  ];

  void moveStep(String id, int delta) {
    final next = steps;
    final from = next.indexWhere((step) => step['id'] == id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= next.length) return;
    next.insert(to, next.removeAt(from));
    change('steps', next);
  }

  void removeStep(String id) {
    final next = steps;
    final index = next.indexWhere((step) => step['id'] == id);
    if (index < 0 || next.length < 2) return;
    final removed = next.removeAt(index);
    final destination = next[(index - 1).clamp(0, next.length - 1)];
    (destination['fieldIds'] as List).addAll(removed['fieldIds'] as List);
    change('steps', next);
  }

  Widget forms() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final f in editableFields) control(f),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Multi-step form'),
        subtitle: const Text('Save once, after the last step.'),
        value: steps.isNotEmpty,
        onChanged: !widget.enabled
            ? null
            : (v) {
                if (!v) {
                  change('steps', null);
                  return;
                }
                change('steps', [
                  {
                    'id': 'step1',
                    'title': 'Details',
                    'fieldIds': editableFields.map((f) => f.id).toList(),
                  },
                ]);
              },
      ),
      if (steps.isNotEmpty) ...[
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              key: ValueKey('step-title-${step['id']}'),
              initialValue: step['title'] as String,
              enabled: widget.enabled,
              decoration: const InputDecoration(labelText: 'Step title'),
              onChanged: (v) {
                final next = steps;
                next.firstWhere((s) => s['id'] == step['id'])['title'] = v;
                change('steps', next);
              },
            ),
          ),
        for (var index = 0; index < steps.length; index++)
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(steps[index]['title'] as String),
              IconButton(
                tooltip: 'Move step up',
                onPressed: !widget.enabled || index == 0
                    ? null
                    : () => moveStep(steps[index]['id'] as String, -1),
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                tooltip: 'Move step down',
                onPressed: !widget.enabled || index == steps.length - 1
                    ? null
                    : () => moveStep(steps[index]['id'] as String, 1),
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              IconButton(
                tooltip: 'Remove step',
                onPressed: !widget.enabled || steps.length < 2
                    ? null
                    : () => removeStep(steps[index]['id'] as String),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        for (final f in editableFields)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                'step-field-${f.id}-${steps.map((s) => s['fieldIds']).join()}',
              ),
              initialValue:
                  steps
                          .where((s) => (s['fieldIds'] as List).contains(f.id))
                          .firstOrNull?['id']
                      as String?,
              decoration: InputDecoration(labelText: '${f.label} step'),
              isExpanded: true,
              items: [
                for (final s in steps)
                  DropdownMenuItem(
                    value: s['id'] as String,
                    child: Text(s['title'] as String),
                  ),
              ],
              onChanged: !widget.enabled
                  ? null
                  : (v) {
                      final next = steps;
                      for (final s in next) {
                        (s['fieldIds'] as List).remove(f.id);
                      }
                      (next.firstWhere((s) => s['id'] == v)['fieldIds'] as List)
                          .add(f.id);
                      change('steps', next);
                    },
            ),
          ),
        OutlinedButton.icon(
          onPressed:
              !widget.enabled ||
                  steps.length >= 8 ||
                  !steps.any((s) => (s['fieldIds'] as List).length > 1)
              ? null
              : () {
                  final next = steps;
                  final source = next.firstWhere(
                    (s) => (s['fieldIds'] as List).length > 1,
                  );
                  final moved = (source['fieldIds'] as List).removeLast();
                  var id = next.length + 1;
                  while (next.any((s) => s['id'] == 'step$id')) {
                    id++;
                  }
                  next.add({
                    'id': 'step$id',
                    'title': 'Step ${next.length + 1}',
                    'fieldIds': [moved],
                  });
                  change('steps', next);
                },
          icon: const Icon(Icons.add),
          label: const Text('Add step'),
        ),
      ],
    ],
  );

  Widget control(FieldSpec f) {
    final configured = controls.where((c) => c['fieldId'] == f.id).firstOrNull;
    final kinds = switch (f.type) {
      FieldType.text => ['text', 'multiline'],
      FieldType.integer => ['stepper', 'slider', 'rating'],
      FieldType.number => ['stepper', 'slider'],
      FieldType.boolean => ['checkbox', 'switch'],
      FieldType.choice => ['select', if (f.choices.length <= 6) 'segmented'],
      FieldType.timestamp => ['dateTime'],
      FieldType.member => ['select'],
      FieldType.image => ['imageUpload'],
    };
    final kind = configured?['control'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            key: ValueKey('control-${f.id}-$kind'),
            initialValue: kind ?? '',
            isExpanded: true,
            decoration: InputDecoration(labelText: '${f.label} control'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Default')),
              for (final value in kinds)
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: !widget.enabled
                ? null
                : (v) => setControl(
                    f.id,
                    v == '' ? null : v,
                    v == 'slider' || v == 'stepper'
                        ? {'min': 0, 'max': 100, 'step': 1}
                        : null,
                  ),
          ),
        ),
        if (kind == 'slider' || kind == 'stepper')
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in ['min', 'max', 'step'])
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    key: ValueKey('control-${f.id}-$kind-$key'),
                    initialValue: configured?[key]?.toString() ?? '',
                    enabled: widget.enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(labelText: key),
                    onChanged: (v) {
                      final value = Map<String, dynamic>.from(
                        controls.firstWhere((c) => c['fieldId'] == f.id),
                      );
                      value[key] = num.tryParse(v);
                      value.remove('fieldId');
                      value.remove('control');
                      setControl(f.id, kind, value);
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.type == 'deviceControl')
        select(
          'Phone control',
          'control',
          deviceControlLabels,
          fallback: 'flashlight',
        ),
      if (widget.type == 'deviceInfo') ...[
        const Text(
          'Information stays on the phone. Each person enables access in their mini-app.',
        ),
        for (final field in deviceInfoFields.entries)
          CheckboxListTile(
            title: Text(field.value),
            value:
                (options['fields'] as List? ??
                        const ['batteryLevel', 'charging'])
                    .contains(field.key),
            onChanged: widget.enabled
                ? (enabled) {
                    final fields = List<String>.from(
                      options['fields'] as List? ??
                          const ['batteryLevel', 'charging'],
                    );
                    if (enabled == true) {
                      fields.add(field.key);
                    } else {
                      fields.remove(field.key);
                    }
                    change('fields', fields);
                  }
                : null,
          ),
      ],
      if (widget.type == 'clock') ...[
        select('Clock display', 'style', const {
          'digital': 'Digital',
          'analog': 'Analog',
        }, fallback: 'digital'),
        select('Time format', 'hourFormat', const {
          'system': 'Device setting',
          '12': '12-hour',
          '24': '24-hour',
        }, fallback: 'system'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show seconds'),
          value: options['showSeconds'] as bool? ?? false,
          onChanged: widget.enabled ? (v) => change('showSeconds', v) : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show date'),
          value: options['showDate'] as bool? ?? true,
          onChanged: widget.enabled ? (v) => change('showDate', v) : null,
        ),
      ],
      if (widget.type == 'timer') ...[
        TextFormField(
          key: const ValueKey('timer-duration'),
          initialValue: (options['durationMinutes'] ?? 25).toString(),
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Focus minutes',
            helperText: '1–180 minutes. Applies to the next focus session.',
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) {
            final minutes = int.tryParse(value ?? '');
            return minutes == null || minutes < 1 || minutes > 180
                ? 'Enter a whole number from 1 to 180.'
                : null;
          },
          onChanged: (value) => change('durationMinutes', int.tryParse(value)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Your focus session stays on this device. Completion appears when AppNest is open; phone alerts are not included.',
          ),
        ),
      ],
      if (['calendar', 'timeline'].contains(widget.type))
        field('Date field', 'dateFieldId', {FieldType.timestamp}),
      if (['chart', 'metric'].contains(widget.type)) ...[
        if (widget.type == 'chart')
          select('Chart style', 'style', const {
            'bar': 'Bars',
            'donut': 'Donut',
            'line': 'Line',
          }, fallback: 'bar'),
        select('Metric', 'metric', {
          'count': 'Record count',
          if (options['style'] != 'donut') ...{
            'sum': 'Sum',
            'average': 'Average',
          },
        }, fallback: 'count'),
        if (options['metric'] == 'sum' || options['metric'] == 'average')
          field('Number field', 'valueFieldId', {
            FieldType.number,
            FieldType.integer,
          }),
        if (widget.type == 'chart' && options['style'] != 'donut')
          field(
            options['style'] == 'line' ? 'Date field' : 'Date field (optional)',
            'dateFieldId',
            {FieldType.timestamp},
          ),
        if (widget.type == 'chart' &&
            options['style'] != 'donut' &&
            (options['style'] == 'line' || options['dateFieldId'] != null)) ...[
          select('Time buckets', 'bucket', const {
            'day': 'Daily',
            'week': 'Weekly',
            'month': 'Monthly',
          }, fallback: 'day'),
          text('Number of periods (1–366)', 'periods', numeric: true),
        ],
        if (widget.type == 'metric')
          text('Target (optional)', 'target', numeric: true),
      ],
      if (['imageCards', 'gallery'].contains(widget.type)) ...[
        field('Image field', 'imageFieldId', {FieldType.image}),
        field('Caption field (optional)', 'captionFieldId', {FieldType.text}),
      ],
      if (widget.type == 'richText') ...[
        text('Formatted text', 'markdown', multiline: true),
        const Text(
          'Use # headings, **bold**, *italic*, lists, > quotations, and `inline code`.',
        ),
      ],
      if (widget.type == 'banner') ...[
        text('Banner title', 'title'),
        text('Banner body', 'body', multiline: true),
        select('Tone', 'tone', const {
          'neutral': 'Neutral',
          'accent': 'Accent',
          'info': 'Information',
          'success': 'Success',
          'warning': 'Warning',
        }, fallback: 'neutral'),
        if (widget.uploadImage != null)
          OutlinedButton.icon(
            onPressed: !widget.enabled || uploading ? null : upload,
            icon: const Icon(Icons.image_outlined),
            label: Text(
              uploading
                  ? 'Uploading…'
                  : options['imageAssetId'] == null
                  ? 'Upload banner image'
                  : 'Replace banner image',
            ),
          ),
        if (options['imageAssetId'] != null) ...[
          text('Image description', 'imageAlt'),
          select('Image placement', 'imagePlacement', const {
            'above': 'Image above text',
            'beside': 'Image beside text',
          }, fallback: 'above'),
          TextButton(
            onPressed: !widget.enabled
                ? null
                : () => change('imageAssetId', null),
            child: const Text('Remove image'),
          ),
        ],
        select('Link to page (optional)', 'targetPageId', {
          for (final tab in widget.spec.navigation?.tabs ?? <TabSpec>[])
            tab.pageId: tab.label,
        }),
      ],
      if (widget.type == 'form') forms(),
      if (widget.type == 'checklist') ...[
        select('Checked field', 'fieldId', {
          for (final field in collection!.fields)
            if (checklistActions(field.id).isNotEmpty) field.id: field.label,
        }),
        select('Update action', 'actionId', {
          for (final action in checklistActions(options['fieldId'] as String?))
            action.id: action.label,
        }),
        if (collection?.fields
                .where((f) => f.id == options['fieldId'])
                .firstOrNull
                ?.type ==
            FieldType.choice) ...[
          select('Checked value', 'checkedValue', {
            for (final v
                in collection!.field(options['fieldId'] as String).choices)
              v: v,
          }),
          select('Unchecked value', 'uncheckedValue', {
            for (final v
                in collection!.field(options['fieldId'] as String).choices)
              v: v,
          }),
        ],
      ],
      if (widget.type == 'board') ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Drag cards between columns'),
          value: options['draggable'] == true,
          onChanged: !widget.enabled
              ? null
              : (v) {
                  if (v) {
                    change('draggable', true);
                  } else {
                    notify(
                      Map<String, dynamic>.from(options)
                        ..remove('draggable')
                        ..remove('moveActionId'),
                    );
                  }
                },
        ),
        if (options['draggable'] == true)
          select('Move action', 'moveActionId', {
            for (final a in widget.spec.actions)
              if (a.collectionId == widget.collectionId &&
                  a.capability == 'workflow.transition.v1')
                a.id: a.label,
          }),
      ],
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
