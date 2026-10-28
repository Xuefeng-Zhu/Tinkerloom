part of '../appnest_spec.dart';

const richViewTypes = {
  'deviceInfo',
  'deviceControl',
  'clock',
  'timer',
  'table',
  'calendar',
  'timeline',
  'chart',
  'metric',
  'imageCards',
  'gallery',
  'richText',
  'banner',
  'checklist',
};
const _numericTypes = {FieldType.integer, FieldType.number};
const formControls = {
  'text',
  'multiline',
  'switch',
  'checkbox',
  'select',
  'segmented',
  'slider',
  'stepper',
  'rating',
  'dateTime',
  'imageUpload',
};

void _validateOptionsShape(String type, Map<String, dynamic> o) {
  final allowed = switch (type) {
    'deviceInfo' => {'fields'},
    'deviceControl' => {'control'},
    'clock' => {'style', 'hourFormat', 'showSeconds', 'showDate'},
    'timer' => {'durationMinutes'},
    'calendar' || 'timeline' => {'dateFieldId'},
    'chart' => {
      'style',
      'metric',
      'valueFieldId',
      'dateFieldId',
      'bucket',
      'periods',
    },
    'metric' => {'metric', 'valueFieldId', 'target'},
    'imageCards' || 'gallery' => {'imageFieldId', 'captionFieldId'},
    'richText' => {'markdown'},
    'banner' => {
      'title',
      'body',
      'imageAssetId',
      'imageAlt',
      'tone',
      'imagePlacement',
      'targetPageId',
    },
    'form' => {'controls', 'steps'},
    'checklist' => {'fieldId', 'actionId', 'checkedValue', 'uncheckedValue'},
    'board' => {'draggable', 'moveActionId'},
    _ => <String>{},
  };
  keys(o, allowed, '$type options');
  if (type == 'deviceInfo') DeviceInfoOptions.fromJson(o);
  if (type == 'deviceControl') DeviceControlOptions.fromJson(o);
  if (type == 'clock') ClockOptions.fromJson(o);
  if (type == 'timer') TimerOptions.fromJson(o);
  for (final key in [
    'dateFieldId',
    'valueFieldId',
    'imageFieldId',
    'captionFieldId',
    'targetPageId',
    'fieldId',
    'actionId',
    'moveActionId',
  ]) {
    if (o.containsKey(key)) stableId(o[key]);
  }
  if (type == 'richText') str(o['markdown'], 'rich text', max: 8192);
  if (type == 'banner') {
    if (o.containsKey('imagePlacement') &&
        !bannerImagePlacements.contains(o['imagePlacement'])) {
      throw const SpecException('Choose an approved banner image placement');
    }
    str(o['title'], 'banner title');
    if (o.containsKey('body')) str(o['body'], 'banner body', max: 2048);
    if (o.containsKey('imageAssetId')) {
      _imageId(o['imageAssetId']);
      str(o['imageAlt'], 'banner image description', max: 500);
    }
    if (o.containsKey('imageAlt'))
      str(o['imageAlt'], 'banner image description', max: 500);
    if (o.containsKey('tone') &&
        !{
          'neutral',
          'accent',
          'info',
          'success',
          'warning',
        }.contains(o['tone'])) {
      throw const SpecException('Unsupported banner tone');
    }
  }
  if (type == 'form') {
    final controls = array(o['controls'] ?? [], 'form controls', Limits.fields);
    final ids = <String>[];
    for (final value in controls) {
      final c = object(value, 'form control');
      keys(c, {
        'fieldId',
        'control',
        'hint',
        'min',
        'max',
        'step',
      }, 'form control');
      ids.add(stableId(c['fieldId']));
      if (!formControls.contains(c['control']))
        throw const SpecException('Unsupported form control');
      if (c.containsKey('hint')) str(c['hint'], 'control hint', max: 500);
      final numeric = {'slider', 'stepper', 'rating'}.contains(c['control']);
      for (final key in ['min', 'max', 'step']) {
        if (c.containsKey(key) &&
            (!numeric || c[key] is! num || !(c[key] as num).isFinite)) {
          throw const SpecException('Numeric bounds need a numeric control');
        }
      }
      if ({'slider', 'stepper'}.contains(c['control']) &&
          (c['min'] is! num ||
              c['max'] is! num ||
              c['step'] is! num ||
              c['min'] >= c['max'] ||
              c['step'] <= 0 ||
              c['step'] > c['max'] - c['min'] ||
              !((c['max'] as num) - (c['min'] as num)).isFinite ||
              !(((c['max'] as num) - (c['min'] as num)) / (c['step'] as num))
                  .isFinite)) {
        throw const SpecException(
          'Sliders and steppers need finite min, max and positive step',
        );
      }
      if (c['control'] == 'rating' &&
          (c.containsKey('min') ||
              c.containsKey('max') ||
              c.containsKey('step'))) {
        throw const SpecException(
          'Ratings use integer values from one to five',
        );
      }
    }
    unique(ids, 'form control fields');
    if (o.containsKey('steps')) {
      final steps = array(o['steps'], 'form steps', 8);
      if (steps.isEmpty)
        throw const SpecException('A stepped form needs at least one step');
      final ids = <String>[];
      final fields = <String>[];
      for (final value in steps) {
        final step = object(value, 'form step');
        keys(step, {'id', 'title', 'fieldIds'}, 'form step');
        ids.add(stableId(step['id']));
        str(step['title'], 'step title');
        final stepFields = array(
          step['fieldIds'],
          'step fields',
          Limits.fields,
        ).map(stableId).toList();
        if (stepFields.isEmpty)
          throw const SpecException('Each form step needs a field');
        fields.addAll(stepFields);
      }
      unique(ids, 'form steps');
      unique(fields, 'step fields');
    }
  }
  if (type == 'board' &&
      o.isNotEmpty &&
      (o['draggable'] != true || o['moveActionId'] == null)) {
    throw const SpecException(
      'Interactive boards need draggable true and a move action',
    );
  }
}

String _imageId(Object? value) {
  if (value is! String || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
    throw const SpecException(
      'Images must reference an opaque private asset ID',
    );
  }
  return value;
}

void _validateRichView(AppSpec spec, ViewSpec view) {
  final o = view.options;
  if (view.contentOnly) {
    if (view.titleFieldId != null ||
        view.groupByFieldId != null ||
        view.fieldIds.isNotEmpty ||
        view.filterFieldIds.isNotEmpty ||
        view.actionIds.isNotEmpty ||
        view.query != null ||
        view.dateFilter != null ||
        view.detailPageId != null ||
        view.formPageId != null ||
        view.presentation != null) {
      throw const SpecException(
        'Content blocks cannot bind records, actions or queries',
      );
    }
    if (o['targetPageId'] != null &&
        !spec.navigation!.tabs.any((tab) => tab.pageId == o['targetPageId'])) {
      throw const SpecException('Banner destinations must be app tabs');
    }
    return;
  }
  final col = spec.collection(view.collectionId);
  FieldSpec typed(String key, Set<FieldType> types) {
    final f = col.field(stableId(o[key]));
    if (!types.contains(f.type))
      throw SpecException('$key has an incompatible field type');
    return f;
  }

  if (view.type == 'calendar' || view.type == 'timeline')
    typed('dateFieldId', {FieldType.timestamp});
  if (view.type == 'imageCards' || view.type == 'gallery') {
    typed('imageFieldId', {FieldType.image});
    if (o['captionFieldId'] != null) typed('captionFieldId', {FieldType.text});
  }
  if (view.type == 'chart' || view.type == 'metric') {
    if (!{'count', 'sum', 'average'}.contains(o['metric']))
      throw const SpecException('Choose count, sum or average');
    if (o['metric'] == 'count') {
      if (o.containsKey('valueFieldId'))
        throw const SpecException('Count does not take a value field');
    } else {
      typed('valueFieldId', _numericTypes);
    }
    if (view.type == 'metric') {
      if (view.groupByFieldId != null)
        throw const SpecException('Metric tiles cannot group records');
      if (o.containsKey('target') &&
          (o['target'] is! num ||
              !(o['target'] as num).isFinite ||
              o['target'] <= 0))
        throw const SpecException(
          'Metric targets must be finite positive numbers',
        );
    } else {
      if (!{'bar', 'donut', 'line'}.contains(o['style']))
        throw const SpecException('Unsupported chart style');
      final timeSeries = o['dateFieldId'] != null;
      if (timeSeries) {
        typed('dateFieldId', {FieldType.timestamp});
        if (view.groupByFieldId != null)
          throw const SpecException(
            'Choose date buckets or choice groups, not both',
          );
        if (!{'day', 'week', 'month'}.contains(o['bucket']))
          throw const SpecException(
            'Date charts need day, week or month buckets',
          );
        if (o.containsKey('periods') &&
            (o['periods'] is! int || o['periods'] < 1 || o['periods'] > 366))
          throw const SpecException('Chart periods must be one to 366');
      } else {
        if (view.groupByFieldId == null ||
            col.field(view.groupByFieldId!).type != FieldType.choice)
          throw const SpecException('Grouped charts need a choice field');
        if (o.containsKey('bucket') || o.containsKey('periods'))
          throw const SpecException('Only date charts use buckets');
      }
      if (o['style'] == 'line' && !timeSeries)
        throw const SpecException('Line charts need date buckets');
      if (o['style'] == 'donut' && (timeSeries || o['metric'] != 'count'))
        throw const SpecException('Donut charts show choice counts');
    }
  }
  if (view.type == 'form') {
    final visible = view.fieldIds.isEmpty
        ? col.fields.map((f) => f.id).toSet()
        : view.fieldIds.toSet();
    final workflowFields = col.behaviors
        .where((b) => b.type == 'workflow.v1')
        .map((b) => b.fieldId)
        .toSet();
    final editable = visible.difference(workflowFields.cast<String>().toSet());
    for (final value in o['controls'] as List? ?? []) {
      final c = object(value, 'form control');
      final f = col.field(c['fieldId']);
      if (!editable.contains(f.id)) {
        throw SpecException(
          workflowFields.contains(f.id)
              ? 'Form ${view.id} must remove the control for workflow-managed '
                    'field ${f.id}; change its state through the workflow action.'
              : 'Form ${view.id} control ${f.id} must reference a field included '
                    'in fieldIds, or be removed.',
        );
      }
      final types = switch (c['control']) {
        'text' || 'multiline' => {FieldType.text},
        'switch' || 'checkbox' => {FieldType.boolean},
        'select' => {FieldType.choice, FieldType.member},
        'segmented' => {FieldType.choice},
        'slider' || 'stepper' => _numericTypes,
        'rating' => {FieldType.integer},
        'dateTime' => {FieldType.timestamp},
        'imageUpload' => {FieldType.image},
        _ => <FieldType>{},
      };
      if (!types.contains(f.type))
        throw SpecException(
          'Form ${view.id} field ${f.id} has type ${f.type.name}, but control '
          '${c['control']} requires ${types.map((type) => type.name).join(' or ')}.',
        );
      if (c['control'] == 'segmented' && f.choices.length > 6)
        throw const SpecException(
          'Segmented controls support at most six choices',
        );
      if (f.type == FieldType.integer &&
          [
            'min',
            'max',
            'step',
          ].any((key) => c[key] != null && c[key] != (c[key] as num).round()))
        throw const SpecException(
          'Integer controls need integral bounds and steps',
        );
      if (_numericTypes.contains(f.type)) {
        for (final key in ['min', 'max']) {
          final bound = c[key];
          if (bound != null) {
            f.normalize(
              f.type == FieldType.integer ? (bound as num).toInt() : bound,
            );
          }
        }
      }
    }
    if (o['steps'] != null) {
      final fields = <String>{};
      for (final step in o['steps']) {
        for (final id in step['fieldIds']) {
          col.field(id);
          fields.add(id);
        }
      }
      if (fields.length != editable.length || !fields.containsAll(editable))
        throw const SpecException(
          'Form steps must include each editable field exactly once',
        );
    }
  }
  if (view.type == 'checklist' || view.type == 'board' && o.isNotEmpty) {
    final checklist = view.type == 'checklist';
    if (!checklist && view.groupByFieldId == null) {
      throw SpecException(
        'Board ${view.id} needs groupByFieldId referencing a choice field in ${col.id}.',
      );
    }
    final field = col.field(
      checklist ? stableId(o['fieldId']) : view.groupByFieldId ?? '',
    );
    final action = spec.action(
      stableId(o[checklist ? 'actionId' : 'moveActionId']),
    );
    if (action.collectionId != col.id || !view.actionIds.contains(action.id))
      throw SpecException(
        'View ${view.id} must include action ${action.id} in actionIds, and that action must belong to collection ${col.id}.',
      );
    if (checklist && field.type == FieldType.boolean) {
      if (action.capability != 'records.patch.v1' ||
          o.containsKey('checkedValue') ||
          o.containsKey('uncheckedValue'))
        throw const SpecException(
          'Boolean checklists need a record patch action',
        );
    } else {
      if (field.type != FieldType.choice ||
          action.capability != 'workflow.transition.v1' ||
          action.behaviorId == null)
        throw const SpecException(
          'Workflow components need a choice field and transition action',
        );
      final behavior = col.behavior(action.behaviorId!);
      if (behavior.type != 'workflow.v1' || behavior.fieldId != field.id)
        throw const SpecException(
          'The move action must bind the component workflow field',
        );
      if (checklist) {
        final checked = o['checkedValue'], unchecked = o['uncheckedValue'];
        if (field.choices.length != 2 ||
            checked == unchecked ||
            !field.choices.contains(checked) ||
            !field.choices.contains(unchecked) ||
            !(behavior.transitions[checked] ?? []).contains(unchecked) ||
            !(behavior.transitions[unchecked] ?? []).contains(checked))
          throw const SpecException(
            'Workflow checklists need two explicit reversible states',
          );
      }
    }
  }
}

/// A bounded, authenticated-runtime aggregation request. Buckets are explicit
/// UTC instants so callers can resolve each local calendar boundary across DST.
class AggregateQuery {
  final String metric;
  final String? fieldId, groupFieldId, dateFieldId;
  final List<Map<String, dynamic>> buckets;
  AggregateQuery._(
    this.metric,
    this.fieldId,
    this.groupFieldId,
    this.dateFieldId,
    this.buckets,
  );
  factory AggregateQuery.parse(
    CollectionSpec collection,
    Map<String, dynamic> j,
  ) {
    keys(j, {
      'metric',
      'fieldId',
      'groupFieldId',
      'dateFieldId',
      'buckets',
    }, 'aggregate');
    final metric = j['metric'];
    if (!{'count', 'sum', 'average'}.contains(metric))
      throw const SpecException('Unsupported aggregate metric');
    final fieldId = j['fieldId'] == null ? null : stableId(j['fieldId']);
    if (metric == 'count'
        ? fieldId != null
        : fieldId == null ||
              !_numericTypes.contains(collection.field(fieldId).type))
      throw const SpecException(
        'Numeric aggregates require a number field; counts do not',
      );
    final group = j['groupFieldId'] == null
        ? null
        : stableId(j['groupFieldId']);
    final date = j['dateFieldId'] == null ? null : stableId(j['dateFieldId']);
    if (group != null && collection.field(group).type != FieldType.choice)
      throw const SpecException('Aggregate groups need a choice field');
    if (date != null && collection.field(date).type != FieldType.timestamp)
      throw const SpecException('Aggregate buckets need a timestamp field');
    if (group != null && date != null)
      throw const SpecException('Choose choice groups or date buckets');
    final buckets = <Map<String, dynamic>>[];
    DateTime? previousEnd;
    final ids = <String>[];
    for (final value in array(j['buckets'] ?? [], 'aggregate buckets', 366)) {
      final b = object(value, 'aggregate bucket');
      keys(b, {'key', 'start', 'end'}, 'aggregate bucket');
      final key = str(b['key'], 'bucket key', max: 80);
      DateTime parse(String name) {
        final value = b[name];
        if (value is! String || !value.endsWith('Z'))
          throw const SpecException(
            'Bucket boundaries must be UTC ISO timestamps',
          );
        final parsed = DateTime.tryParse(value);
        if (parsed == null || !parsed.isUtc)
          throw const SpecException('Invalid bucket boundary');
        return parsed;
      }

      final start = parse('start'), end = parse('end');
      if (!end.isAfter(start) ||
          previousEnd != null && start.isBefore(previousEnd))
        throw const SpecException(
          'Buckets must be ordered and non-overlapping',
        );
      previousEnd = end;
      ids.add(key);
      buckets.add({
        'key': key,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      });
    }
    unique(ids, 'bucket keys');
    if ((date != null) != buckets.isNotEmpty)
      throw const SpecException('Date aggregates need one to 366 buckets');
    return AggregateQuery._(
      metric,
      fieldId,
      group,
      date,
      List.unmodifiable(buckets),
    );
  }
  Map<String, dynamic> toJson() => {
    'metric': metric,
    if (fieldId != null) 'fieldId': fieldId,
    if (groupFieldId != null) 'groupFieldId': groupFieldId,
    if (dateFieldId != null) 'dateFieldId': dateFieldId,
    if (buckets.isNotEmpty) 'buckets': buckets,
  };
}

Map<String, dynamic> _richOptionsSchema(String type) {
  Map<String, dynamic> obj(
    Map<String, dynamic> properties, [
    List<String> required = const [],
  ]) => {
    'type': 'object',
    'additionalProperties': false,
    'properties': properties,
    if (required.isNotEmpty) 'required': required,
  };
  Map<String, dynamic> arr(Object items, int max, {int min = 0}) => {
    'type': 'array',
    'items': items,
    'minItems': min,
    'maxItems': max,
  };
  const id = {
    'type': 'string',
    'pattern': r'^[a-zA-Z][a-zA-Z0-9_]*$',
    'maxLength': 64,
  };
  const label = {'type': 'string', 'minLength': 1, 'maxLength': 160};
  const metric = {
    'enum': ['count', 'sum', 'average'],
  };
  const asset = {'type': 'string', 'pattern': r'^[A-Za-z0-9_-]{1,128}$'};
  return switch (type) {
    'deviceInfo' => obj(
      {
        'fields': arr(
          {'enum': deviceInfoFields.keys.toList()},
          deviceInfoFields.length,
          min: 1,
        ),
      },
      ['fields'],
    ),
    'deviceControl' => obj(
      {
        'control': {'enum': deviceControlLabels.keys.toList()},
      },
      ['control'],
    ),
    'clock' => obj({
      'style': {
        'enum': ['analog', 'digital'],
      },
      'hourFormat': {
        'enum': ['system', '12', '24'],
      },
      'showSeconds': {'type': 'boolean'},
      'showDate': {'type': 'boolean'},
    }),
    'timer' => obj({
      'durationMinutes': {'type': 'integer', 'minimum': 1, 'maximum': 180},
    }),
    'calendar' || 'timeline' => obj({'dateFieldId': id}, ['dateFieldId']),
    'chart' => obj(
      {
        'style': {
          'enum': ['bar', 'donut', 'line'],
        },
        'metric': metric,
        'valueFieldId': id,
        'dateFieldId': id,
        'bucket': {
          'enum': ['day', 'week', 'month'],
        },
        'periods': {'type': 'integer', 'minimum': 1, 'maximum': 366},
      },
      ['style', 'metric'],
    ),
    'metric' => obj(
      {
        'metric': metric,
        'valueFieldId': id,
        'target': {'type': 'number', 'exclusiveMinimum': 0},
      },
      ['metric'],
    ),
    'imageCards' || 'gallery' => obj(
      {'imageFieldId': id, 'captionFieldId': id},
      ['imageFieldId'],
    ),
    'richText' => obj(
      {
        'markdown': {'type': 'string', 'minLength': 1, 'maxLength': 8192},
      },
      ['markdown'],
    ),
    'banner' => obj(
      {
        'title': label,
        'body': {'type': 'string', 'minLength': 1, 'maxLength': 2048},
        'imageAssetId': asset,
        'imageAlt': {'type': 'string', 'minLength': 1, 'maxLength': 500},
        'tone': {
          'enum': ['neutral', 'accent', 'info', 'success', 'warning'],
        },
        'imagePlacement': {'enum': bannerImagePlacements.toList()},
        'targetPageId': id,
      },
      ['title'],
    ),
    'form' => obj({
      'controls': arr(
        obj(
          {
            'fieldId': id,
            'control': {'enum': formControls.toList()},
            'hint': {'type': 'string', 'minLength': 1, 'maxLength': 500},
            'min': {'type': 'number'},
            'max': {'type': 'number'},
            'step': {'type': 'number', 'exclusiveMinimum': 0},
          },
          ['fieldId', 'control'],
        ),
        Limits.fields,
      ),
      'steps': arr(
        obj(
          {
            'id': id,
            'title': label,
            'fieldIds': arr(id, Limits.fields, min: 1),
          },
          ['id', 'title', 'fieldIds'],
        ),
        8,
        min: 1,
      ),
    }),
    'checklist' => obj(
      {
        'fieldId': id,
        'actionId': id,
        'checkedValue': {'type': 'string', 'minLength': 1, 'maxLength': 80},
        'uncheckedValue': {'type': 'string', 'minLength': 1, 'maxLength': 80},
      },
      ['fieldId', 'actionId'],
    ),
    'board' => {
      'oneOf': [
        obj({}),
        obj(
          {
            'draggable': {'const': true},
            'moveActionId': id,
          },
          ['draggable', 'moveActionId'],
        ),
      ],
    },
    _ => obj({}),
  };
}
