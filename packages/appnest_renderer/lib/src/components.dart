part of '../appnest_renderer.dart';

typedef RecordAction = Future<void> Function(ActionSpec, RuntimeItem?);

String _recordSectionLabel(AppSpec spec, ViewSpec view) => view.label == view.id
    ? spec.collection(view.collectionId).label
    : view.label;

String _displayDate(BuildContext context, String value) {
  final date = DateTime.parse(value).toLocal(),
      l = MaterialLocalizations.of(context);
  return '${l.formatMediumDate(date)} · ${l.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

class RecordList extends StatelessWidget {
  final AppSpec spec;
  final ViewSpec view;
  final List<RuntimeItem> items;
  final RecordAction onAction;
  const RecordList({
    super.key,
    required this.spec,
    required this.view,
    required this.items,
    required this.onAction,
  });
  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RecordDetails(
                spec: spec,
                view: view,
                item: item,
                onAction: onAction,
              ),
            ),
          )
          .toList(),
    );
    return view.presentation == 'compact' ? Card(child: content) : content;
  }
}

class RecordDetails extends StatelessWidget {
  final AppSpec spec;
  final ViewSpec view;
  final RuntimeItem item;
  final RecordAction onAction;
  const RecordDetails({
    super.key,
    required this.spec,
    required this.view,
    required this.item,
    required this.onAction,
  });
  @override
  Widget build(BuildContext context) {
    final col = spec.collection(item.collectionId);
    final titleFieldId = view.titleFieldId ?? col.fields.first.id;
    final compact = view.presentation == 'compact';
    final content = Padding(
      padding: EdgeInsets.all(_space(context, compact ? 12 : 20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _editableField(
            context,
            view,
            titleFieldId,
            Text(
              col.field(titleFieldId).type == FieldType.image
                  ? 'Image record'
                  : '${item.data[titleFieldId] ?? 'Untitled'}',
              style: compact
                  ? Theme.of(context).textTheme.titleMedium
                  : Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          for (final f
              in (view.fieldIds.isEmpty
                      ? col.fields
                      : view.fieldIds.map(col.field))
                  .where(
                    (f) =>
                        !{'capacity', 'action'}.contains(view.type) &&
                        f.id != titleFieldId &&
                        item.data[f.id] != null,
                  ))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _editableField(
                context,
                view,
                f.id,
                Text(
                  '${f.label}: ${f.type == FieldType.image
                      ? 'Image attached'
                      : f.type == FieldType.timestamp
                      ? _displayDate(context, item.data[f.id] as String)
                      : item.data[f.id]}',
                ),
              ),
            ),
          if (item.capacity != null) CapacitySummary(item: item),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: view.actionIds
                .where(item.allowedActions.contains)
                .map(spec.action)
                .where(
                  (a) =>
                      a.capability != 'records.create.v1' &&
                      !(a.capability == 'capacity.claim.v1' && item.claimed) &&
                      !(a.capability == 'capacity.release.v1' && !item.claimed),
                )
                .map(
                  (a) => ActionButton(
                    action: a,
                    onPressed: () => onAction(a, item),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
    return compact ? content : Card(child: content);
  }
}

class ActionButton extends StatelessWidget {
  final ActionSpec action;
  final VoidCallback? onPressed;
  const ActionButton({super.key, required this.action, this.onPressed});
  @override
  Widget build(BuildContext context) =>
      OutlinedButton(onPressed: onPressed, child: Text(action.label));
}

class CapacitySummary extends StatelessWidget {
  final RuntimeItem item;
  const CapacitySummary({super.key, required this.item});
  @override
  Widget build(BuildContext context) => Text(
    '${(item.capacity ?? 0) - (item.allocated ?? 0)} of ${item.capacity} places available${item.claimed ? ' · Your place is confirmed' : ''}',
    style: const TextStyle(fontWeight: FontWeight.w600),
  );
}

class Summary extends StatelessWidget {
  final List<RuntimeItem> items;
  final int total;
  final String? groupField;
  const Summary({
    super.key,
    required this.items,
    required this.total,
    this.groupField,
  });
  @override
  Widget build(BuildContext context) {
    final groups = <String, int>{};
    for (final i in items) {
      final key = '${i.data[groupField] ?? 'Records'}';
      groups[key] = (groups[key] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$total records',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if (items.length < total) const Text('Groups below cover this page.'),
        ...groups.entries.map(
          (e) => ListTile(title: Text(e.key), trailing: Text('${e.value}')),
        ),
      ],
    );
  }
}

class StatusBoard extends StatelessWidget {
  final AppSpec spec;
  final ViewSpec view;
  final List<RuntimeItem> items;
  final RecordAction onAction;
  const StatusBoard({
    super.key,
    required this.spec,
    required this.view,
    required this.items,
    required this.onAction,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final statuses = spec
          .collection(view.collectionId)
          .field(view.groupByFieldId!)
          .choices;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: statuses
            .map(
              (status) => SizedBox(
                width: c.maxWidth < 700 ? c.maxWidth : (c.maxWidth - 32) / 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        status,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    RecordList(
                      spec: spec,
                      view: view,
                      items: items
                          .where((r) => r.data[view.groupByFieldId] == status)
                          .toList(),
                      onAction: onAction,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
    },
  );
}

class RecordForm extends StatefulWidget {
  final CollectionSpec collection;
  final Map<String, dynamic>? initial;
  final Future<List<String>> Function() members;
  final int? capacity;
  final RuntimeAdapter? adapter;
  final RuntimeItem? record;
  final List<String> fieldIds;
  const RecordForm({
    super.key,
    required this.collection,
    this.initial,
    required this.members,
    this.capacity,
    this.adapter,
    this.record,
    this.fieldIds = const [],
  });
  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final controllers = <String, TextEditingController>{};
  final values = <String, dynamic>{};
  List<String> members = [];
  String? error;
  bool _uploading = false;
  final _pendingImages = <String, PendingImageUpload>{};
  final _imageMessages = <String, String>{};
  int _imageGeneration = 0;
  Object? _lastImageContext;
  Object get _imageContext => (
    widget.adapter,
    widget.adapter?.spec.hash,
    widget.collection.id,
    widget.record?.id,
    widget.record?.revision,
    widget.adapter?.readOnly,
    widget.adapter?.archived,
    widget.fieldIds.join(','),
  );
  late final TextEditingController capacity;
  bool get creating => widget.initial == null;
  List<FieldSpec> get fields {
    final selected = widget.fieldIds.isEmpty
        ? widget.collection.fields
        : widget.fieldIds.map(widget.collection.field).toList();
    // Legacy definitions may omit required inputs in fieldIds. Keep those
    // definitions usable without changing their serialization or hashes.
    return [
      ...selected.where(
        (field) =>
            creating ||
            !widget.collection.behaviors.any((b) => b.fieldId == field.id),
      ),
      if (creating && widget.fieldIds.isNotEmpty)
        ...widget.collection.fields.where(
          (field) =>
              field.required &&
              !widget.fieldIds.contains(field.id) &&
              !widget.collection.behaviors.any(
                (b) => b.type == 'workflow.v1' && b.fieldId == field.id,
              ),
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _lastImageContext = _imageContext;
    capacity = TextEditingController(text: '${widget.capacity ?? 1}');
    for (final f in fields) {
      final value = widget.initial?[f.id];
      controllers[f.id] = TextEditingController(text: value?.toString() ?? '');
      values[f.id] =
          value ??
          (f.required
              ? (f.type == FieldType.choice
                    ? f.choices.first
                    : f.type == FieldType.boolean
                    ? false
                    : null)
              : null);
    }
    widget.members().then(
      (list) {
        if (mounted) setState(() => members = list);
      },
      onError: (Object issue) {
        if (mounted) {
          setState(
            () => error =
                widget.adapter?.errorMessage(
                  issue,
                  fallback: 'Could not load eligible members. Try again.',
                ) ??
                'Could not load eligible members. Try again.',
          );
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant RecordForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastImageContext != _imageContext) {
      _lastImageContext = _imageContext;
      _imageGeneration++;
      _pendingImages.clear();
      _imageMessages.clear();
      _uploading = false;
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    capacity.dispose();
    super.dispose();
  }

  void save() {
    if (_uploading || _pendingImages.isNotEmpty) return;
    try {
      final data = <String, dynamic>{};
      for (final f in fields) {
        final text = controllers[f.id]!.text;
        data[f.id] = switch (f.type) {
          FieldType.choice ||
          FieldType.boolean ||
          FieldType.member ||
          FieldType.image => values[f.id],
          FieldType.integer => text.isEmpty ? null : int.parse(text),
          FieldType.number => text.isEmpty ? null : double.parse(text),
          FieldType.timestamp =>
            text.isEmpty
                ? null
                : DateTime.parse(text).toUtc().toIso8601String(),
          _ => text.isEmpty ? null : text,
        };
        f.normalize(data[f.id]);
      }
      if (creating) {
        for (final behavior in widget.collection.behaviors.where(
          (behavior) => behavior.type == 'workflow.v1',
        )) {
          data.putIfAbsent(
            behavior.fieldId!,
            () => widget.collection.field(behavior.fieldId!).choices.first,
          );
        }
      }
      final input = <String, dynamic>{'data': data};
      if (creating &&
          widget.collection.behaviors.any((b) => b.type == 'capacity.v1'))
        input['capacity'] = int.parse(capacity.text);
      Navigator.pop(context, input);
    } catch (e) {
      setState(
        () => error = e is SpecException
            ? e.message
            : 'Check your values and try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      creating ? 'Add ${widget.collection.label.toLowerCase()}' : 'Edit record',
    ),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in fields)
              Padding(
                padding: EdgeInsets.only(bottom: _space(context, 16)),
                child: switch (f.type) {
                  FieldType.image => _imageField(f),
                  FieldType.choice ||
                  FieldType.member => DropdownButtonFormField<String>(
                    isExpanded: true,
                    itemHeight: null,
                    selectedItemBuilder: (context) => [
                      for (final value
                          in (f.type == FieldType.choice ? f.choices : members))
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    initialValue: values[f.id] as String?,
                    decoration: InputDecoration(
                      labelText: '${f.label}${f.required ? ' *' : ''}',
                    ),
                    items: (f.type == FieldType.choice ? f.choices : members)
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => values[f.id] = v,
                  ),
                  FieldType.boolean => CheckboxListTile(
                    title: Text(f.label),
                    tristate: !f.required,
                    value: values[f.id] as bool? ?? (f.required ? false : null),
                    onChanged: (v) => setState(() => values[f.id] = v),
                  ),
                  _ => TextField(
                    controller: controllers[f.id],
                    decoration: InputDecoration(
                      labelText: '${f.label}${f.required ? ' *' : ''}',
                      helperText: f.type == FieldType.timestamp
                          ? 'Local date and time: YYYY-MM-DD HH:MM'
                          : null,
                    ),
                    keyboardType:
                        {FieldType.integer, FieldType.number}.contains(f.type)
                        ? TextInputType.number
                        : TextInputType.text,
                    maxLines: f.type == FieldType.text ? null : 1,
                  ),
                },
              ),
            if (creating &&
                widget.collection.behaviors.any((b) => b.type == 'capacity.v1'))
              TextField(
                controller: capacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Capacity *'),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_uploading)
              const LinearProgressIndicator(semanticsLabel: 'Uploading image'),
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
        onPressed: _uploading || _pendingImages.isNotEmpty ? null : save,
        child: const Text('Save'),
      ),
    ],
  );

  Widget _imageField(FieldSpec field) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${field.label}${field.required ? ' *' : ''}'),
      const SizedBox(height: 8),
      if (values[field.id] != null && widget.adapter != null)
        _PrivateImage(
          adapter: widget.adapter!,
          assetId: values[field.id] as String,
          label: field.label,
        ),
      if (values[field.id] == null) const Text('Not set'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed:
                widget.adapter == null ||
                    widget.adapter!.readOnly ||
                    widget.adapter!.archived ||
                    _uploading ||
                    _pendingImages.containsKey(field.id)
                ? null
                : () => _chooseImage(field),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              values[field.id] == null ? 'Choose image' : 'Replace image',
            ),
          ),
          if (!field.required && values[field.id] != null)
            TextButton(
              onPressed: _uploading || _pendingImages.containsKey(field.id)
                  ? null
                  : () => setState(() {
                      values[field.id] = null;
                      _imageMessages.remove(field.id);
                    }),
              child: const Text('Remove image'),
            ),
        ],
      ),
      if (_pendingImages[field.id] case final pending?)
        PendingImageUploadControls(
          pending: pending,
          busy: _uploading,
          onCheck: () => _checkImage(field),
          onDiscard: () => _discardImage(field),
        ),
      if (_imageMessages[field.id] case final message?)
        Semantics(liveRegion: true, child: Text(message)),
      Text(
        'JPEG, PNG or WebP · up to 5 MiB',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  bool _imageActive(int generation, Object context) =>
      mounted &&
      generation == _imageGeneration &&
      context == _imageContext &&
      widget.adapter?.readOnly == false &&
      widget.adapter?.archived == false;

  void _finishImage(int generation, Object context) {
    if (!mounted || generation != _imageGeneration) return;
    setState(() {
      _uploading = false;
      if (context != _imageContext) {
        _pendingImages.clear();
        _imageMessages.clear();
      }
    });
  }

  void _discardImage(FieldSpec field) {
    _imageGeneration++;
    setState(() {
      _pendingImages.remove(field.id);
      _imageMessages.remove(field.id);
      _uploading = false;
      error = null;
    });
  }

  Future<void> _checkImage(FieldSpec field) async {
    final pending = _pendingImages[field.id];
    if (pending == null || _uploading) return;
    final generation = ++_imageGeneration, context = _imageContext;
    setState(() {
      _uploading = true;
      error = null;
    });
    try {
      final id = await pending.checkReady();
      if (!_imageActive(generation, context)) return;
      if (id != pending.assetId) {
        throw const SpecException(
          'The image response belongs to another upload.',
        );
      }
      setState(() {
        values[field.id] = id;
        _pendingImages.remove(field.id);
        _imageMessages[field.id] = 'Image attached. Save the form to keep it.';
        error = null;
      });
    } on PendingImageUpload catch (next) {
      if (_imageActive(generation, context)) {
        setState(() {
          if (next.assetId == pending.assetId) _pendingImages[field.id] = next;
        });
      }
    } catch (issue) {
      if (_imageActive(generation, context)) {
        setState(
          () => error = widget.adapter!.errorMessage(
            issue,
            fallback:
                'Could not check the image. Your other values are retained.',
          ),
        );
      }
    } finally {
      _finishImage(generation, context);
    }
  }

  Future<void> _chooseImage(FieldSpec field) async {
    if (_uploading || _pendingImages.containsKey(field.id)) return;
    final generation = ++_imageGeneration, context = _imageContext;
    setState(() {
      _uploading = true;
      error = null;
      _imageMessages.remove(field.id);
    });
    try {
      final bytes = await widget.adapter!.pickImage();
      if (bytes == null || !_imageActive(generation, context)) return;
      final id = await widget.adapter!.uploadImage(
        bytes,
        collectionId: widget.collection.id,
        fieldId: field.id,
        record: widget.record,
      );
      if (!_imageActive(generation, context)) return;
      setState(() {
        values[field.id] = id;
        _imageMessages[field.id] = 'Image attached. Save the form to keep it.';
        error = null;
      });
    } on PendingImageUpload catch (pending) {
      if (_imageActive(generation, context)) {
        setState(() {
          _pendingImages[field.id] = pending;
          error = null;
        });
      }
    } catch (issue) {
      if (_imageActive(generation, context)) {
        setState(
          () => error = widget.adapter!.errorMessage(
            issue,
            fallback: 'Could not upload image. Your other values are retained.',
          ),
        );
      }
    } finally {
      _finishImage(generation, context);
    }
  }
}

class _ValueDialog extends StatefulWidget {
  final String label, initial;
  final bool numeric;
  const _ValueDialog({
    required this.label,
    this.initial = '',
    this.numeric = false,
  });
  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<_ValueDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.label),
    content: TextField(
      controller: controller,
      keyboardType: widget.numeric ? TextInputType.number : TextInputType.text,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {'value': controller.text}),
        child: const Text('Save'),
      ),
    ],
  );
}

class _ChoiceDialog extends StatelessWidget {
  final String label;
  final List<String> values;
  const _ChoiceDialog({required this.label, required this.values});
  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: Text(label),
    children: values
        .map(
          (v) => SimpleDialogOption(
            onPressed: () => Navigator.pop(context, {'value': v}),
            child: Text(v),
          ),
        )
        .toList(),
  );
}
