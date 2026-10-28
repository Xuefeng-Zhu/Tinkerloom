import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';

import 'customization_evaluation.dart';
import 'generation_quality.dart';
import 'provider.dart';

/// Fixed synthetic definition-level benchmark. These assertions do not prove
/// rendering, authenticated persistence, reminder delivery, or device behavior.
class NemotronScenario {
  final String id, operation, prompt;
  final AppSpec baseline;
  final String? sequenceSourceId;

  NemotronScenario({
    required this.id,
    required this.operation,
    required this.prompt,
    required this.baseline,
    this.sequenceSourceId,
  });

  void validate(
    Map<String, dynamic> output,
    AppSpec? candidate, {
    AppSpec? baselineOverride,
  }) {
    if (operation == 'unsupported') {
      _require(
        candidate == null &&
            output.length == 1 &&
            output['unsupported'] is String &&
            (output['unsupported'] as String).trim().isNotEmpty &&
            (output['unsupported'] as String).length <= 500,
        'Return only an unsupported explanation of 1–500 characters.',
      );
      return;
    }
    if (operation == 'guidance') {
      _require(candidate == null, 'Guidance must not produce an app.');
      final questions = parseGuidanceOutput(jsonEncode(output));
      final actionable = id.startsWith('guidance-actionable-');
      _require(
        actionable ? questions.isEmpty : questions.length >= 2,
        actionable
            ? 'This request is actionable; return no clarification questions.'
            : 'This request needs two or three actionable clarification questions.',
      );
      return;
    }
    _require(
      {'create', 'edit', 'sequence'}.contains(operation),
      'Unknown evaluation operation: $operation.',
    );
    _require(
      candidate != null && !output.containsKey('unsupported'),
      'Return a functional definition for this supported request.',
    );
    final accepted = candidate!;
    final editing = operation != 'create';
    final original = baselineOverride ?? baseline;
    if (editing) {
      _require(
        output.length == 1 &&
            output['patches'] is List &&
            (output['patches'] as List).isNotEmpty &&
            (output['patches'] as List).length <= 10,
        'Return only a nonempty bounded patches array for an edit.',
      );
      final errors = original.compatibilityErrors(accepted);
      _require(errors.isEmpty, errors.join(' '));
    }
    final key = id.substring(id.indexOf('-') + 1);
    if (_customizations.any((row) => row.$1 == key)) {
      validateCustomizationScenario(
        key,
        accepted,
        baseline: editing ? original : null,
      );
      return;
    }
    validateGeneratedExperience(accepted, baseline: editing ? original : null);
    if (editing) {
      _validateEdit(key, original, accepted);
    } else {
      _validateCreate(key, accepted);
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'operation': operation,
    'prompt': prompt,
    'baseline': baseline.toJson(),
    if (sequenceSourceId != null) 'sequenceSourceId': sequenceSourceId,
  };
}

// Kept verbatim from scripts/customization_eval.dart so historical scenarios
// remain comparable, while scored edits always use the fixed fixture below.
const _customizations = <(String, String, String)>[
  (
    'notes-fields',
    'Make a personal notes app with titles, multiline notes, categories, search, add/edit forms, and a details page for each note.',
    'Add an optional text field named Source to my notes. Include it in the add/edit form and details. Preserve every existing field and page.',
  ),
  (
    'notes-appearance',
    'Build a simple notebook to capture my ideas with titles, long notes, and categories. I need to add and edit notes.',
    'Give this app an editorial appearance with accent color #3B6B5A. Keep all content and behavior unchanged.',
  ),
  (
    'reminders-timing',
    'Create a personal reminder list with title, notes, Open/Done status, and an optional Remind me timestamp. Remind the owner in the AppNest inbox at that time only while Open. Include add/edit screens.',
    'Update the existing reminder rule to fire 10 minutes before its existing timestamp. Preserve its rule ID, condition, and recipient.',
  ),
  (
    'reminders-name',
    'I want a simple personal task reminder app with optional due dates and independent reminder times, Open and Done states, and owner inbox reminders only for open tasks. Let me add and edit tasks.',
    'Rename this app to Gentle Reminders and change nothing else.',
  ),
  (
    'calendar-category',
    'Create a personal calendar for my events with title, start time, notes, and a Category choice of Personal or Work. Include monthly calendar with daily agenda and add/edit screens.',
    'Add Travel as another choice in the existing Category field. Preserve all existing choices, fields, and views.',
  ),
  (
    'calendar-appearance',
    'Make an events calendar with a monthly calendar and selected-day agenda, event titles, date and time, notes, and add/edit screens.',
    'Change this app to the playful appearance style. Keep its content and behavior unchanged.',
  ),
  (
    'focus-duration',
    'Make a minimal clock and focus timer app. Show a local digital clock and a 25-minute focus countdown with start, pause, resume, and reset. No record collections are needed.',
    'Change the existing focus timer default duration to 40 minutes. Keep the clock and all other settings unchanged.',
  ),
  (
    'focus-clock',
    'Build my focus app with a digital local clock showing seconds and a 25-minute countdown timer. It needs no notes, tasks, or record collections.',
    'Change the existing clock to analog and hide its seconds hand. Preserve the timer and all other settings.',
  ),
];

List<NemotronScenario> nemotronScenarios() {
  final templates = starterTemplates();
  AppSpec fixture(String key) {
    final base = templates[key.split('-').first]!;
    return key == 'focus-clock'
        ? _options(base, base.views.singleWhere((v) => v.type == 'clock'), {
            'showSeconds': true,
          })
        : base;
  }

  return [
    for (final row in _customizations)
      NemotronScenario(
        id: 'create-${row.$1}',
        operation: 'create',
        prompt: row.$2,
        baseline: fixture(row.$1),
      ),
    NemotronScenario(
      id: 'create-rich-dashboard',
      operation: 'create',
      prompt: 'Create a personal activity dashboard. Log a title, timestamp, numeric minutes, a Category choice, and multiline notes through reachable add/edit forms. Show a checklist of entries, a metric summing minutes with target 150, and a daily line chart summing minutes over the most recent 14 days. Include entry details. No reminders.',
      baseline: templates['habitTracker']!,
    ),
    NemotronScenario(
      id: 'create-multistep-form',
      operation: 'create',
      prompt: 'Create a personal photo journal with title, private photo, moment timestamp, caption, rating and favorite fields. Use a two-step add/edit form: first title, photo and moment timestamp; then multiline caption, rating and favorite. Include image cards, a gallery and linked entry details. No reminders.',
      baseline: templates['photoJournal']!,
    ),
    NemotronScenario(
      id: 'create-shared-workflow',
      operation: 'create',
      prompt: 'Build a shared team task workflow using the group workflow policy. Tasks have title, optional due date, Priority choices Low/Normal/High, integer effort and multiline notes. Include reachable add/edit forms and linked details. Show a draggable board grouped by Open/Done status, with supported transitions from Open to Done and back. No reminders.',
      baseline: templates['projectHub']!,
    ),
    NemotronScenario(
      id: 'create-capacity-signup',
      operation: 'create',
      prompt: 'Build shared volunteer shift signups using the group capacity signup policy. Each shift has a title, required start timestamp and preparation notes. Expose shift list, capacity summary, reachable add/edit form, set-capacity, join and cancel-signup controls. Use one capacity pool per shift and an AppNest inbox reminder for active claimants one hour before the start.',
      baseline: _capacityFixture(templates['volunteer']!),
    ),
    for (final row in _customizations)
      NemotronScenario(
        id: 'edit-${row.$1}',
        operation: 'edit',
        prompt: row.$3,
        baseline: fixture(row.$1),
      ),
    NemotronScenario(
      id: 'edit-navigation',
      operation: 'edit',
      prompt: 'Make the existing Schedule page the entry page. Reorder the existing tabs to Calendar, Board, Tasks, preserving their labels and icons. Change no pages, views, actions, fields, appearance or other settings.',
      baseline: templates['projectHub']!,
    ),
    NemotronScenario(
      id: 'edit-rich-config',
      operation: 'edit',
      prompt: 'Change only the existing Minutes over time daily chart from 14 to 30 periods. Preserve its style, metric, numeric and date fields, bucket and every other component and setting.',
      baseline: templates['habitTracker']!,
    ),
    NemotronScenario(
      id: 'edit-workflow-label',
      operation: 'edit',
      prompt: 'Rename the existing workflow Status field label to Stage. Keep its stable field ID, Open/Done choice values, transitions, actions, board bindings and all other definition settings unchanged.',
      baseline: templates['projectHub']!,
    ),
    NemotronScenario(
      id: 'edit-shared-field',
      operation: 'edit',
      prompt: 'Add exactly one optional text field named Location to the existing shared tasks collection and expose it in the existing add/edit form and task details. Preserve all existing IDs, fields, pages, settings, workflow and group workflow permission policy.',
      baseline: templates['projectHub']!,
    ),
    for (final row in <(String, String)>[
      (
        'actionable-notes',
        'Create a personal notes app with title, multiline body and Category choices Ideas/Work/Personal, search, add/edit forms and note details.',
      ),
      (
        'actionable-focus',
        'Create a personal focus clock with local digital time and a 25-minute countdown with start, pause, resume and reset. No records or background alerts.',
      ),
      ('ambiguous-organize', 'Help me organize things.'),
      ('ambiguous-team', 'Build something useful for my team.'),
    ])
      NemotronScenario(
        id: 'guidance-${row.$1}',
        operation: 'guidance',
        prompt: row.$2,
        baseline: templates['reading']!,
      ),
    for (final row in <(String, String)>[
      (
        'executable',
        'Build an app whose required core feature is executing arbitrary JavaScript entered by users, with filesystem and shell access. Do not replace this with a notes app.',
      ),
      (
        'external-automation',
        'Build an app whose required core feature posts each saved record to any external webhook URL entered by a user and automatically sends email through their SMTP server.',
      ),
      (
        'payments',
        'Build a checkout app that charges customers real credit cards and issues refunds. Payment processing is the required core feature.',
      ),
      (
        'background-device',
        'Build a phone alarm app that reliably sounds a loud alarm at scheduled times while the app is closed and the phone is locked. Background phone alarms are the required core feature.',
      ),
    ])
      NemotronScenario(
        id: 'unsupported-${row.$1}',
        operation: 'unsupported',
        prompt: row.$2,
        baseline: templates['reading']!,
      ),
  ];
}

/// Optional sequences are scored separately from fixed-baseline edit results.
/// The runner replaces the placeholder with the corresponding model's accepted
/// creation and skips the sequence when that creation was not successful.
List<NemotronScenario> nemotronSequences() {
  final scenarios = nemotronScenarios();
  return [
    for (final key in [
      'notes-fields',
      'reminders-timing',
      'calendar-category',
      'focus-clock',
    ])
      NemotronScenario(
        id: 'sequence-$key',
        operation: 'sequence',
        prompt: scenarios.singleWhere((s) => s.id == 'edit-$key').prompt,
        baseline: scenarios.singleWhere((s) => s.id == 'edit-$key').baseline,
        sequenceSourceId: 'create-$key',
      ),
  ];
}

void _validateCreate(String key, AppSpec spec) {
  _require(spec.collections.length == 1, 'Use one collection for this app.');
  final collection = spec.collections.single;
  final visible = _visible(spec);
  final forms = reachableGeneratedRecordForms(spec, collection.id);
  _require(
    forms.isNotEmpty &&
        ['records.create.v1', 'records.patch.v1'].every(
          (capability) => forms.any(
            (form) => form.actionIds.any(
              (id) => spec.action(id).capability == capability,
            ),
          ),
        ),
    'Include reachable matching add and edit forms.',
  );
  bool editable(FieldSpec field, {String? control}) =>
      ['records.create.v1', 'records.patch.v1'].every(
        (capability) => forms.any(
          (form) =>
              form.actionIds.any(
                (id) => spec.action(id).capability == capability,
              ) &&
              _shows(form, field.id) &&
              (control == null ||
                  (form.options['controls'] as List? ?? []).any(
                    (c) => c['fieldId'] == field.id && c['control'] == control,
                  )),
        ),
      );
  FieldSpec field(FieldType type, String label) {
    final matches = collection.fields.where(
      (f) =>
          f.type == type &&
          '${f.id} ${f.label}'.toLowerCase().contains(label.toLowerCase()),
    );
    _require(
      matches.length == 1,
      'Include one $label field of type ${type.name}.',
    );
    return matches.single;
  }

  void details() => _require(
    visible.any(
      (v) =>
          v.collectionId == collection.id &&
          v.detailPageId != null &&
          spec
              .page(v.detailPageId!)
              .viewIds
              .map(spec.view)
              .any(
                (detail) =>
                    detail.type == 'details' &&
                    detail.collectionId == collection.id,
              ),
    ),
    'Expose linked record details from a visible record view.',
  );

  final titleIds = visible
      .where((view) => view.collectionId == collection.id)
      .map((view) => view.titleFieldId)
      .whereType<String>()
      .where((id) => collection.field(id).type == FieldType.text)
      .toSet();
  _require(
    titleIds.any((id) => editable(collection.field(id))),
    'Display an editable text title on a visible record view.',
  );
  switch (key) {
    case 'rich-dashboard':
      _require(
        spec.policyPresetRequest == 'personalTracker.v1' &&
            spec.automationRequests.isEmpty,
        'Use the personal tracker policy without reminders.',
      );
      final minutes = collection.fields.where(
        (f) =>
            {FieldType.number, FieldType.integer}.contains(f.type) &&
            '${f.id} ${f.label}'.toLowerCase().contains('minute'),
      );
      _require(minutes.length == 1, 'Include one numeric Minutes field.');
      final date = collection.fields.where(
        (f) => f.type == FieldType.timestamp,
      );
      _require(date.length == 1, 'Include one activity timestamp.');
      _require(
        editable(minutes.single) &&
            editable(date.single) &&
            editable(field(FieldType.choice, 'categor')) &&
            editable(field(FieldType.text, 'note'), control: 'multiline'),
        'Expose minutes, timestamp, category and multiline notes in the form.',
      );
      _require(
        visible.any(
              (v) =>
                  v.type == 'metric' &&
                  v.options['metric'] == 'sum' &&
                  v.options['valueFieldId'] == minutes.single.id &&
                  v.options['target'] == 150 &&
                  (v.query?['filters'] as List? ?? []).isEmpty &&
                  v.dateFilter == null,
            ) &&
            visible.any(
              (v) =>
                  v.type == 'chart' &&
                  v.options['style'] == 'line' &&
                  v.options['metric'] == 'sum' &&
                  v.options['valueFieldId'] == minutes.single.id &&
                  v.options['dateFieldId'] == date.single.id &&
                  v.options['bucket'] == 'day' &&
                  v.options['periods'] == 14 &&
                  (v.query?['filters'] as List? ?? []).isEmpty &&
                  v.dateFilter == null,
            ) &&
            visible.any((v) => v.type == 'checklist'),
        'Show the requested total-minutes target, daily 14-period line chart and checklist.',
      );
      details();
    case 'multistep-form':
      _require(
        spec.policyPresetRequest == 'personalTracker.v1' &&
            spec.automationRequests.isEmpty,
        'Use the personal tracker policy without reminders.',
      );
      final photo = collection.fields.where((f) => f.type == FieldType.image);
      final date = collection.fields.where(
        (f) => f.type == FieldType.timestamp,
      );
      _require(
        photo.length == 1 && date.length == 1,
        'Include one private photo field and one moment timestamp.',
      );
      final caption = field(FieldType.text, 'caption');
      final rating = field(FieldType.integer, 'rating');
      final favorite = field(FieldType.boolean, 'favorite');
      _require(
        editable(photo.single, control: 'imageUpload') &&
            editable(date.single) &&
            editable(caption, control: 'multiline') &&
            editable(rating, control: 'rating') &&
            editable(favorite),
        'Expose private image upload, timestamp, multiline caption, rating and favorite controls.',
      );
      _require(
        ['records.create.v1', 'records.patch.v1'].every(
              (capability) => forms.any((form) {
                final steps = form.options['steps'] as List? ?? [];
                return form.actionIds.any(
                      (id) => spec.action(id).capability == capability,
                    ) &&
                    steps.length == 2 &&
                    titleIds.any(
                      (id) => (steps.first['fieldIds'] as List).contains(id),
                    ) &&
                    (steps.first['fieldIds'] as List).contains(
                      photo.single.id,
                    ) &&
                    (steps.first['fieldIds'] as List).contains(
                      date.single.id,
                    ) &&
                    (steps.last['fieldIds'] as List).contains(caption.id) &&
                    (steps.last['fieldIds'] as List).contains(rating.id) &&
                    (steps.last['fieldIds'] as List).contains(favorite.id);
              }),
            ) &&
            ['imageCards', 'gallery'].every(
              (type) => visible.any(
                (v) =>
                    v.type == type &&
                    v.options['imageFieldId'] == photo.single.id,
              ),
            ),
        'Expose the requested two-step form, image cards and photo gallery.',
      );
      details();
    case 'shared-workflow':
      _require(
        spec.policyPresetRequest == 'groupWorkflow.v1' &&
            spec.automationRequests.isEmpty,
        'Use the shared group workflow policy without reminders.',
      );
      final workflow = collection.behaviors.where(
        (b) => b.type == 'workflow.v1',
      );
      _require(workflow.length == 1, 'Include one typed workflow.');
      final status = collection.field(workflow.single.fieldId!);
      _require(
        status.type == FieldType.choice &&
            status.choices.length == 2 &&
            status.choices.first == 'Open' &&
            status.choices.last == 'Done' &&
            (workflow.single.transitions['Open'] ?? []).contains('Done') &&
            (workflow.single.transitions['Done'] ?? []).contains('Open'),
        'Preserve Open/Done states and transitions in both directions.',
      );
      _require(
        visible.any(
          (v) =>
              v.type == 'board' &&
              v.groupByFieldId == status.id &&
              v.options['draggable'] == true &&
              v.options['moveActionId'] is String &&
              v.actionIds.contains(v.options['moveActionId']) &&
              spec.action(v.options['moveActionId']).capability ==
                  'workflow.transition.v1' &&
              spec.action(v.options['moveActionId']).behaviorId ==
                  workflow.single.id,
        ),
        'Expose a draggable workflow board with the matching transition action.',
      );
      final priority = field(FieldType.choice, 'priority');
      final due = collection.fields.where((f) => f.type == FieldType.timestamp);
      _require(
        priority.choices.toSet().containsAll({'Low', 'Normal', 'High'}) &&
            editable(priority) &&
            due.any((f) => !f.required && editable(f)) &&
            editable(field(FieldType.integer, 'effort')) &&
            editable(field(FieldType.text, 'note'), control: 'multiline'),
        'Include editable priority, optional due date, integer effort and multiline notes.',
      );
      details();
    case 'capacity-signup':
      _require(
        spec.policyPresetRequest == 'groupCapacitySignup.v1' &&
            collection.behaviors.where((b) => b.type == 'capacity.v1').length ==
                1,
        'Use the shared capacity signup policy and one typed capacity pool.',
      );
      final capacity = collection.behaviors.singleWhere(
        (b) => b.type == 'capacity.v1',
      );
      _require(
        ['list', 'capacity'].every(
              (type) => visible.any((v) => v.type == type),
            ) &&
            [
              'capacity.configure.v1',
              'capacity.claim.v1',
              'capacity.release.v1',
            ].every(
              (capability) => visible.any(
                (v) => v.actionIds.any(
                  (id) =>
                      spec.action(id).capability == capability &&
                      spec.action(id).behaviorId == capacity.id,
                ),
              ),
            ),
        'Expose shift list, capacity summary, configure, join and release controls.',
      );
      final dates = collection.fields.where(
        (f) => f.type == FieldType.timestamp && f.required && editable(f),
      );
      _require(
        dates.length == 1 &&
            editable(field(FieldType.text, 'note')) &&
            spec.automationRequests.length == 1,
        'Include an editable required start timestamp, preparation notes and one reminder.',
      );
      final rule = spec.automationRequests.single;
      _require(
        rule.collectionId == collection.id &&
            rule.fieldId == dates.single.id &&
            rule.offsetSeconds == 3600 &&
            rule.effect == 'notifyActiveClaimants' &&
            rule.condition == null,
        'Remind active claimants one hour before the shift starts.',
      );
    default:
      throw SpecException('Unknown creation benchmark: $key.');
  }
}

void _validateEdit(String key, AppSpec baseline, AppSpec candidate) {
  AppSpec expected;
  switch (key) {
    case 'navigation':
      final navigation = baseline.navigation!;
      expected = baseline.patch({
        'type': 'SetNavigation',
        'entryPageId': 'calendarPage',
        'tabs': [
          for (final page in ['calendarPage', 'boardPage', 'tablePage'])
            navigation.tabs.singleWhere((t) => t.pageId == page).toJson(),
        ],
      }, _noIds);
    case 'rich-config':
      expected = _options(baseline, baseline.view('dailyMinutes'), {
        'periods': 30,
      });
    case 'workflow-label':
      expected = baseline.patch({
        'type': 'RenameLabel',
        'targetId': 'status',
        'label': 'Stage',
      }, _noIds);
    case 'shared-field':
      final collection = baseline.collections.single;
      final ids = collection.fields.map((f) => f.id).toSet();
      final added = candidate
          .collection(collection.id)
          .fields
          .where((f) => !ids.contains(f.id))
          .toList();
      _require(
        added.length == 1 &&
            added.single.label == 'Location' &&
            added.single.type == FieldType.text &&
            !added.single.required,
        'Add exactly one optional text Location field to the existing collection.',
      );
      expected = baseline.patch({
        'type': 'AddField',
        'collectionId': collection.id,
        'field': {'label': 'Location', 'type': 'text', 'required': false},
        'viewIds': [
          for (final view in baseline.views)
            if (view.collectionId == collection.id &&
                {'form', 'details'}.contains(view.type))
              view.id,
        ],
      }, () => added.single.id);
    default:
      throw SpecException('Unknown edit benchmark: $key.');
  }
  final expectedJson = _normalized(expected);
  final actualJson = _normalized(candidate);
  _require(
    canonicalJson(expectedJson) == canonicalJson(actualJson),
    'Apply exactly the requested edit; preserve all unrelated settings and stable identities.',
  );
}

Map<String, dynamic> _normalized(AppSpec spec) {
  final json = jsonDecode(spec.canonical) as Map<String, dynamic>;
  (json['requires'] as List).sort();
  return json;
}

List<ViewSpec> _visible(AppSpec spec) => spec.navigation == null
    ? spec.views
    : {
        spec.navigation!.entryPageId,
        ...spec.navigation!.tabs.map((t) => t.pageId),
      }.expand((id) => spec.page(id).viewIds.map(spec.view)).toList();

bool _shows(ViewSpec view, String field) =>
    view.fieldIds.isEmpty || view.fieldIds.contains(field);

AppSpec _options(AppSpec spec, ViewSpec view, Map<String, dynamic> options) =>
    spec.patch({
      'type': 'UpdateView',
      'viewId': view.id,
      'view': {
        ...view.toJson()..remove('id'),
        'options': {...view.options, ...options},
      },
    }, _noIds);

AppSpec _capacityFixture(AppSpec spec) {
  var candidate = spec.patch({
    'type': 'AddPage',
    'page': {
      'title': 'Shifts',
      'viewIds': ['allShifts', 'placesSummary'],
    },
  }, () => 'shiftHome');
  final ids = ['shiftFormPage', 'shiftEditor'].iterator;
  candidate = candidate.patch(
    {
      'type': 'AddPage',
      'page': {'title': 'Shift editor'},
      'newViews': [
        {
          'type': 'form',
          'collectionId': 'shifts',
          'label': 'Shift editor',
          'actionIds': ['addShift', 'editShift'],
        },
      ],
    },
    () {
      ids.moveNext();
      return ids.current;
    },
  );
  final view = candidate.view('allShifts');
  return candidate.patch({
    'type': 'UpdateView',
    'viewId': view.id,
    'view': {...view.toJson()..remove('id'), 'formPageId': 'shiftFormPage'},
  }, _noIds);
}

String _noIds() => throw StateError('This operation does not allocate IDs.');

void _require(bool condition, String message) {
  if (!condition) throw SpecException(message);
}
