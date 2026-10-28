import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';

import 'generation_quality.dart';

/// Assertions for the eight fixed synthetic customization benchmark scenarios.
/// This is deliberately stricter than general platform schema validation.
/// Passing it proves definition intent, not rendering, delivery, or persistence.
void validateCustomizationScenario(
  String caseId,
  AppSpec candidate, {
  AppSpec? baseline,
}) {
  _require(_cases.contains(caseId), 'Unknown customization scenario: $caseId.');
  validateGeneratedExperience(candidate, baseline: baseline);
  if (baseline == null) {
    _validateCreate(caseId, candidate);
    return;
  }
  _validateCreate(caseId, baseline);
  final errors = baseline.compatibilityErrors(candidate);
  _require(errors.isEmpty, errors.join(' '));
  switch (caseId) {
    case 'notes-fields':
      _validateSource(baseline, candidate);
    case 'notes-appearance':
    case 'calendar-appearance':
      final appearance = {
        'style': caseId == 'notes-appearance' ? 'editorial' : 'playful',
        if (baseline.appearance?.accentColor != null)
          'accentColor': baseline.appearance!.accentColor,
        if (caseId == 'notes-appearance') 'accentColor': '#3B6B5A',
      };
      _same(
        baseline.patch({
          'type': 'SetAppearance',
          'appearance': appearance,
        }, _noIds),
        candidate,
      );
    case 'reminders-name':
      _same(
        baseline.patch({
          'type': 'RenameLabel',
          'targetId': 'app',
          'label': 'Gentle Reminders',
        }, _noIds),
        candidate,
      );
    case 'reminders-timing':
      final rule = baseline.automationRequests.single;
      final json = rule.toJson()..remove('id');
      (json['trigger'] as Map)['offsetSeconds'] = 600;
      _same(
        baseline.patch({
          'type': 'UpdateReminder',
          'ruleId': rule.id,
          'rule': json,
        }, _noIds),
        candidate,
      );
    case 'calendar-category':
      final collection = _mainCollection(baseline);
      final category = _category(collection);
      _same(
        baseline.patch({
          'type': 'AddChoice',
          'collectionId': collection.id,
          'fieldId': category.id,
          'choice': 'Travel',
        }, _noIds),
        candidate,
      );
    case 'focus-duration':
    case 'focus-clock':
      final view = baseline.views.singleWhere(
        (v) => v.type == (caseId == 'focus-duration' ? 'timer' : 'clock'),
      );
      final json = view.toJson()..remove('id');
      json['options'] = {
        ...view.options,
        if (caseId == 'focus-duration') 'durationMinutes': 40,
        if (caseId == 'focus-clock') ...{
          'style': 'analog',
          'showSeconds': false,
        },
      };
      _same(
        baseline.patch({
          'type': 'UpdateView',
          'viewId': view.id,
          'view': json,
        }, _noIds),
        candidate,
      );
  }
}

const _cases = {
  'notes-fields',
  'notes-appearance',
  'reminders-timing',
  'reminders-name',
  'calendar-category',
  'calendar-appearance',
  'focus-duration',
  'focus-clock',
};

const _recordTypes = {
  'list',
  'board',
  'capacity',
  'action',
  'table',
  'calendar',
  'timeline',
  'imageCards',
  'gallery',
  'checklist',
};

void _validateCreate(String id, AppSpec spec) {
  _require(
    spec.policyPresetRequest == 'personalTracker.v1',
    'Use the personal tracker policy for this personal app.',
  );
  if (id.startsWith('focus')) {
    _require(
      spec.collections.isEmpty &&
          spec.actions.isEmpty &&
          spec.automationRequests.isEmpty,
      'The focus app needs no records, record actions, or reminder rules.',
    );
    final clocks = spec.views.where((v) => v.type == 'clock').toList();
    final timers = spec.views.where((v) => v.type == 'timer').toList();
    _require(
      clocks.length == 1 && timers.length == 1,
      'Include one local clock and one focus timer.',
    );
    final visible = _mainViews(spec).map((v) => v.id).toSet();
    _require(
      visible.contains(clocks.single.id) && visible.contains(timers.single.id),
      'Show both the clock and timer on an entry page or tab.',
    );
    _require(
      clocks.single.clockOptions.style == 'digital' &&
          timers.single.timerOptions.durationMinutes == 25 &&
          (id != 'focus-clock' || clocks.single.clockOptions.showSeconds),
      'Start with a digital clock, a 25-minute timer, and seconds when requested.',
    );
    return;
  }

  final collection = _mainCollection(spec);
  for (final collection in spec.collections) {
    for (final capability in ['records.create.v1', 'records.patch.v1']) {
      _require(
        _reachableForms(spec, collection.id, capability).isNotEmpty,
        '${collection.label} needs a reachable add/edit action and matching form.',
      );
    }
  }
  final records = _mainViews(spec)
      .where(
        (v) => _recordTypes.contains(v.type) && v.collectionId == collection.id,
      )
      .toList();
  final titles = records.map((v) => v.titleFieldId).whereType<String>().toSet();
  _require(
    titles.any(
      (field) =>
          collection.field(field).type == FieldType.text &&
          _editableField(spec, collection.id, field),
    ),
    'Include an editable text title displayed on a reachable record view.',
  );
  if (id.startsWith('notes')) {
    final category = _category(collection);
    _require(
      _editableField(spec, collection.id, category.id),
      'Include the category field in the reachable add and edit forms.',
    );
    final bodies = collection.fields.where(
      (f) => f.type == FieldType.text && !titles.contains(f.id),
    );
    _require(
      bodies.any(
        (f) => _editableField(spec, collection.id, f.id, multiline: true),
      ),
      'Use a text body field distinct from the title. In the reachable add/edit '
      'form view, include that field in fieldIds (or omit fieldIds to show all) '
      'and set options.controls to include '
      '${jsonEncode({'fieldId': bodies.firstOrNull?.id ?? 'EXISTING_BODY_FIELD_ID', 'control': 'multiline'})}. '
      'The full shape is form.options.controls:[{fieldId:EXISTING_BODY_FIELD_ID,control:"multiline"}]. '
      'Include views.interactive.v1 and views.configured.v1 in requires. '
      'Preserve controls for other fields.',
    );
    if (id == 'notes-fields') {
      _require(
        records.any(
          (v) =>
              {'list', 'table', 'checklist'}.contains(v.type) &&
              v.titleFieldId != null &&
              collection.field(v.titleFieldId!).type == FieldType.text &&
              (resolveViewQuery(spec, v)['filters'] as List).length +
                      v.filterFieldIds.length <
                  Limits.filters,
        ),
        'On a reachable record view such as ${records.first.id}, set '
        'titleFieldId:${jsonEncode(titles.first)} on a list, table, or checklist. '
        'Text search uses the existing text title; choice filters are optional. '
        'Leave one filter slot available for text search. '
        'Include views.configured.v1 in requires; do not create another title or category field.',
      );
      _require(
        _recordSources(spec).any(
          (view) =>
              view.type == 'details' && view.collectionId == collection.id,
        ),
        'Add a details view bound to collectionId:${jsonEncode(collection.id)}, '
        'place it in a navigation.pages entry, and set the reachable notes '
        'record view.detailPageId to that page ID. An unlinked details page '
        'does not expose note details. Include views.details.v1 in requires.',
      );
    }
  } else if (id.startsWith('calendar')) {
    final calendars = records.where((v) => v.type == 'calendar');
    _require(
      calendars.any(
        (v) => _editableField(
          spec,
          collection.id,
          v.options['dateFieldId'] as String,
        ),
      ),
      'Include a reachable calendar with an editable event timestamp.',
    );
    _require(
      collection.fields.any(
        (f) =>
            f.type == FieldType.text &&
            !titles.contains(f.id) &&
            _editableField(spec, collection.id, f.id),
      ),
      'Include editable event notes separate from the title.',
    );
    if (id == 'calendar-category') {
      final category = _category(collection);
      _require(
        category.choices.contains('Personal') &&
            category.choices.contains('Work') &&
            _editableField(spec, collection.id, category.id),
        'Include an editable Category choice with Personal and Work.',
      );
    }
  } else {
    _require(
      spec.automationRequests.length == 1,
      'Include one owner inbox reminder rule for open tasks.',
    );
    final rule = spec.automationRequests.single;
    final status = rule.condition == null
        ? null
        : collection.fields
              .where(
                (f) => f.id == rule.condition!.fieldId,
              )
              .firstOrNull;
    _require(
      rule.collectionId == collection.id &&
          rule.effect == 'notifyOwner' &&
          rule.offsetSeconds == 0 &&
          rule.condition?.value == 'Open' &&
          status?.type == FieldType.choice &&
          status!.choices.contains('Done'),
      'Notify the owner at the reminder timestamp only while status is Open; include Open and Done states.',
    );
    final timestamp = collection.field(rule.fieldId);
    _require(
      !timestamp.required && _editableField(spec, collection.id, timestamp.id),
      'Make the reminder timestamp optional and editable in add/edit forms.',
    );
    final statusId = status!.id;
    _require(
      !collection.behaviors.any(
            (b) => b.type == 'workflow.v1' && b.fieldId == statusId,
          ) ||
          status.choices.first == 'Open',
      'Put Open first in the workflow status choices so new tasks start Open.',
    );
    final statusEditable =
        !collection.behaviors.any((b) => b.fieldId == statusId) &&
        _reachableForms(
          spec,
          collection.id,
          'records.patch.v1',
        ).any((v) => _showsField(v, statusId));
    final transitionReachable = _recordSources(spec).any(
      (v) =>
          v.collectionId == collection.id &&
          v.actionIds.any((id) {
            final action = spec.action(id);
            if (action.capability != 'workflow.transition.v1') return false;
            final behavior = collection.behavior(action.behaviorId!);
            return behavior.fieldId == statusId &&
                (behavior.transitions['Open'] ?? []).contains('Done');
          }),
    );
    _require(
      statusEditable || transitionReachable,
      'Expose a record action or edit field that can mark an Open task Done.',
    );
    if (id == 'reminders-name') {
      _require(
        collection.fields.any(
          (f) =>
              f.type == FieldType.timestamp &&
              f.id != timestamp.id &&
              !f.required &&
              _editableField(spec, collection.id, f.id),
        ),
        'Include an optional editable due date independent of the reminder timestamp.',
      );
    } else {
      _require(
        collection.fields.any(
          (f) =>
              f.type == FieldType.text &&
              !titles.contains(f.id) &&
              _editableField(spec, collection.id, f.id),
        ),
        'Include editable reminder notes separate from the title.',
      );
    }
  }
}

CollectionSpec _mainCollection(AppSpec spec) {
  final records = _mainViews(spec).where((v) => _recordTypes.contains(v.type));
  _require(
    records.isNotEmpty,
    'Expose the requested records on an entry page or tab.',
  );
  return spec.collection(records.first.collectionId);
}

FieldSpec _category(CollectionSpec collection) {
  final fields = collection.fields
      .where(
        (f) =>
            f.type == FieldType.choice &&
            '${f.id} ${f.label}'.toLowerCase().contains('categor'),
      )
      .toList();
  _require(fields.length == 1, 'Include one Category choice field.');
  return fields.single;
}

List<ViewSpec> _mainViews(AppSpec spec) => spec.navigation == null
    ? spec.views
    : spec.navigation!.tabs
          .expand((t) => spec.page(t.pageId).viewIds.map(spec.view))
          .toList();

List<ViewSpec> _recordSources(AppSpec spec) {
  final records = _mainViews(spec)
      .where((v) => _recordTypes.contains(v.type))
      .toList();
  return [
    ...records,
    for (final view in records)
      if (view.detailPageId != null)
        ...spec
            .page(view.detailPageId!)
            .viewIds
            .map(spec.view)
            .where((v) => v.type == 'details'),
  ];
}

List<ViewSpec> _reachableForms(
  AppSpec spec,
  String collection,
  String capability,
) {
  final forms = <ViewSpec>[];
  void add(String actionId, [ViewSpec? source]) {
    final action = spec.action(actionId);
    if (action.collectionId != collection || action.capability != capability) {
      return;
    }
    final pageId =
        source?.formPageId ??
        spec.navigation?.pages
            .where(
              (p) => p.viewIds
                  .map(spec.view)
                  .any(
                    (v) =>
                        v.type == 'form' &&
                        v.collectionId == collection &&
                        v.actionIds.contains(actionId),
                  ),
            )
            .firstOrNull
            ?.id;
    final candidates = pageId == null
        ? spec.views
        : spec.page(pageId).viewIds.map(spec.view);
    forms.addAll(
      candidates.where(
        (v) =>
            v.type == 'form' &&
            v.collectionId == collection &&
            v.actionIds.contains(actionId),
      ),
    );
  }

  if (capability == 'records.patch.v1') {
    for (final view in _recordSources(spec)) {
      for (final action in view.actionIds) {
        add(action, view);
      }
    }
  } else if (spec.navigation != null) {
    for (final tab in spec.navigation!.tabs) {
      final page = spec.page(tab.pageId);
      if (page.primaryActionId != null) {
        if (page.viewIds
            .map(spec.view)
            .any((v) => v.type != 'form' && v.type != 'details')) {
          add(page.primaryActionId!);
        }
      } else {
        for (final view
            in page.viewIds
                .map(spec.view)
                .where(
                  (v) =>
                      !v.contentOnly && v.type != 'form' && v.type != 'details',
                )) {
          for (final action in view.actionIds) {
            add(action, view);
          }
        }
      }
    }
  } else {
    for (final view in _mainViews(
      spec,
    ).where((v) => _recordTypes.contains(v.type))) {
      for (final action in view.actionIds) {
        add(action, view);
      }
    }
  }
  return forms;
}

bool _showsField(ViewSpec view, String field) =>
    view.fieldIds.isEmpty || view.fieldIds.contains(field);

bool _editableField(
  AppSpec spec,
  String collection,
  String field, {
  bool multiline = false,
}) =>
    !spec.collection(collection).behaviors.any((b) => b.fieldId == field) &&
    ['records.create.v1', 'records.patch.v1'].every(
      (capability) => _reachableForms(spec, collection, capability).any(
        (view) =>
            _showsField(view, field) &&
            (!multiline ||
                (view.options['controls'] as List? ?? []).any(
                  (c) => c['fieldId'] == field && c['control'] == 'multiline',
                )),
      ),
    );

void _validateSource(AppSpec baseline, AppSpec candidate) {
  final collection = _mainCollection(baseline);
  final oldIds = collection.fields.map((f) => f.id).toSet();
  final added = candidate
      .collection(collection.id)
      .fields
      .where((f) => !oldIds.contains(f.id))
      .toList();
  _require(
    added.length == 1 &&
        added.single.label == 'Source' &&
        added.single.type == FieldType.text &&
        !added.single.required,
    'Add exactly one optional text field named Source to the existing notes collection.',
  );
  final source = added.single.id;
  _require(
    _editableField(candidate, collection.id, source),
    'Include Source in reachable add and edit forms for the notes collection.',
  );
  _require(
    _recordSources(candidate).any(
      (v) =>
          v.type == 'details' &&
          v.collectionId == collection.id &&
          _showsField(v, source),
    ),
    'Include Source in the reachable notes details.',
  );
  final stripped = _json(candidate);
  ((stripped['collections'] as List).firstWhere(
            (c) => c['id'] == collection.id,
          )['fields']
          as List)
      .removeWhere((f) => f['id'] == source);
  for (final view in stripped['views'] as List) {
    if (view['collectionId'] != collection.id ||
        !{'form', 'details'}.contains(view['type'])) {
      continue;
    }
    final old = baseline.views.where((v) => v.id == view['id']).firstOrNull;
    if (old == null) continue;
    final fields = view['fieldIds'] as List?;
    fields?.remove(source);
    if (old.fieldIds.isEmpty &&
        fields != null &&
        fields.length == oldIds.length &&
        fields.toSet().containsAll(oldIds)) {
      view.remove('fieldIds');
    }
    final options = view['options'] as Map?;
    (options?['controls'] as List?)?.removeWhere((c) => c['fieldId'] == source);
    for (final step in options?['steps'] as List? ?? []) {
      (step['fieldIds'] as List).remove(source);
    }
    if (options?['controls'] is List &&
        (options!['controls'] as List).isEmpty &&
        !old.options.containsKey('controls')) {
      options.remove('controls');
    }
    if (options != null && options.isEmpty) view.remove('options');
  }
  final before = _json(baseline);
  // A newly configured form may need these capabilities solely for Source.
  (stripped['requires'] as List).removeWhere(
    (r) =>
        {'views.configured.v1', 'views.interactive.v1'}.contains(r) &&
        !baseline.requires.contains(r),
  );
  _sameJson(before, stripped);
}

String _noIds() =>
    throw StateError('This customization does not allocate IDs.');
Map<String, dynamic> _json(AppSpec spec) =>
    jsonDecode(spec.canonical) as Map<String, dynamic>;
void _same(AppSpec expected, AppSpec actual) =>
    _sameJson(_json(expected), _json(actual));

void _sameJson(Map<String, dynamic> expected, Map<String, dynamic> actual) {
  // Capability ordering and explicit runtime defaults are semantically neutral.
  void normalize(Map<String, dynamic> json) {
    (json['requires'] as List).sort();
    for (final view in json['views'] as List) {
      if (view['type'] == 'clock') {
        final o = ClockOptions.fromJson(
          Map<String, dynamic>.from(view['options'] ?? {}),
        );
        view['options'] = {
          'style': o.style,
          'hourFormat': o.hourFormat,
          'showSeconds': o.showSeconds,
          'showDate': o.showDate,
        };
      } else if (view['type'] == 'timer') {
        final o = TimerOptions.fromJson(
          Map<String, dynamic>.from(view['options'] ?? {}),
        );
        view['options'] = {'durationMinutes': o.durationMinutes};
      }
    }
  }

  normalize(expected);
  normalize(actual);
  _require(
    canonicalJson(expected) == canonicalJson(actual),
    'Change only the requested existing field, rule, component, name, or appearance; preserve all other settings and identities.',
  );
}

void _require(bool value, String message) {
  if (!value) throw SpecException(message);
}
