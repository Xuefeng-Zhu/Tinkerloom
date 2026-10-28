import 'package:appnest_spec/appnest_spec.dart';

import 'generation_quality.dart';
import 'generation_requirements.dart';
import 'nemotron_scenarios.dart';

/// Fresh transfer requests, authored before the pipeline pilot. They contain
/// no starting candidate and do not change the historical 36-case benchmark.
List<NemotronScenario> creationPipelineTransferScenarios() => [
  _TransferScenario(
    id: 'create-transfer-reading',
    prompt:
        'Create a personal reading journal using personalTracker.v1. Use one '
        'Books collection with Title (required text), Author (optional text), '
        'Finished (required boolean) and Review (optional text). Include a '
        'searchable book list, linked details, reachable add/edit forms with '
        'multiline Review, and a checklist that toggles the Finished boolean. '
        'Use editorial appearance. No reminders.',
    check: _reading,
  ),
  _TransferScenario(
    id: 'create-transfer-team',
    prompt:
        'Create a shared repair queue using groupWorkflow.v1. Use one Repairs '
        'collection with Title (required text), Stage (required choice: '
        'Queued, Resolved), Estimate (optional integer) and Notes (optional '
        'text). Include a draggable board grouped by Stage, with reversible '
        'transitions Queued to Resolved and Resolved to Queued, linked details '
        'and reachable add/edit forms with multiline Notes. No reminders.',
    check: _team,
  ),
];

class _TransferScenario extends NemotronScenario {
  final void Function(AppSpec) check;
  _TransferScenario({
    required super.id,
    required super.prompt,
    required this.check,
  }) : super(operation: 'create', baseline: starterTemplates()['reading']!);

  @override
  void validate(
    Map<String, dynamic> output,
    AppSpec? candidate, {
    AppSpec? baselineOverride,
  }) {
    _require(
      candidate != null && !output.containsKey('unsupported'),
      'Return a functional definition for this supported transfer request.',
    );
    validateGeneratedExperience(candidate!);
    GenerationRequirements.fromRequest(prompt).validate(candidate);
    _require(
      candidate.automationRequests.isEmpty,
      'No reminders were requested.',
    );
    check(candidate);
  }
}

void _require(bool condition, String message) {
  if (!condition) throw SpecException(message);
}

FieldSpec _field(
  CollectionSpec collection,
  String label,
  FieldType type,
  bool required,
) {
  final matches = collection.fields
      .where(
        (field) => field.label.toLowerCase() == label.toLowerCase(),
      )
      .toList();
  _require(matches.length == 1, 'Include exactly one $label field.');
  final field = matches.single;
  _require(
    field.type == type && field.required == required,
    '$label must have the requested type and requiredness.',
  );
  return field;
}

void _forms(AppSpec spec, CollectionSpec collection, FieldSpec writing) {
  final forms = reachableGeneratedRecordForms(
    spec,
    collection.id,
    creationOnly: true,
  );
  _require(forms.isNotEmpty, 'Include reachable add/edit forms.');
  _require(
    forms.every(
      (form) =>
          form.actionIds
              .map(spec.action)
              .any((action) => action.capability == 'records.patch.v1') &&
          (form.options['controls'] as List? ?? []).whereType<Map>().any(
            (control) =>
                control['fieldId'] == writing.id &&
                control['control'] == 'multiline',
          ),
    ),
    'Each reachable shared form needs editing and the multiline writing control.',
  );
  _require(
    _visible(spec).any(
      (view) =>
          view.collectionId == collection.id &&
          view.detailPageId != null &&
          spec
              .page(view.detailPageId!)
              .viewIds
              .map(spec.view)
              .any(
                (detail) =>
                    detail.type == 'details' &&
                    detail.collectionId == collection.id,
              ),
    ),
    'Include linked record details.',
  );
}

Iterable<ViewSpec> _visible(AppSpec spec) {
  final nav = spec.navigation!;
  return {
    nav.entryPageId,
    ...nav.tabs.map((tab) => tab.pageId),
  }.expand((id) => spec.page(id).viewIds.map(spec.view));
}

void _reading(AppSpec spec) {
  _require(spec.collections.length == 1, 'Use one Books collection.');
  _require(
    spec.policyPresetRequest == 'personalTracker.v1',
    'Use the requested personal policy.',
  );
  final collection = spec.collections.single;
  _require(
    collection.label.toLowerCase() == 'books',
    'Label the collection Books.',
  );
  _require(
    collection.fields.length == 4,
    'Keep exactly the four requested fields.',
  );
  final title = _field(collection, 'Title', FieldType.text, true);
  _field(collection, 'Author', FieldType.text, false);
  final finished = _field(collection, 'Finished', FieldType.boolean, true);
  final review = _field(collection, 'Review', FieldType.text, false);
  _forms(spec, collection, review);
  _require(
    _visible(spec).any(
      (view) => view.type == 'list' && view.titleFieldId == title.id,
    ),
    'Include a searchable title-bound book list.',
  );
  _require(
    _visible(spec).any(
      (view) =>
          view.type == 'checklist' &&
          view.collectionId == collection.id &&
          view.options['fieldId'] == finished.id &&
          spec.action(view.options['actionId'] as String).capability ==
              'records.patch.v1',
    ),
    'The checklist must toggle the Finished boolean.',
  );
  _require(spec.appearance?.style == 'editorial', 'Use editorial appearance.');
}

void _team(AppSpec spec) {
  _require(spec.collections.length == 1, 'Use one Repairs collection.');
  _require(
    spec.policyPresetRequest == 'groupWorkflow.v1',
    'Use the requested shared policy.',
  );
  final collection = spec.collections.single;
  _require(
    collection.label.toLowerCase() == 'repairs',
    'Label the collection Repairs.',
  );
  _require(
    collection.fields.length == 4,
    'Keep exactly the four requested fields.',
  );
  _field(collection, 'Title', FieldType.text, true);
  final stage = _field(collection, 'Stage', FieldType.choice, true);
  _require(
    stage.choices.join('|') == 'Queued|Resolved',
    'Preserve exact Stage choices and order.',
  );
  _field(collection, 'Estimate', FieldType.integer, false);
  final notes = _field(collection, 'Notes', FieldType.text, false);
  _forms(spec, collection, notes);
  _require(
    collection.behaviors.any(
      (behavior) =>
          behavior.type == 'workflow.v1' &&
          behavior.fieldId == stage.id &&
          (behavior.transitions['Queued'] ?? []).contains('Resolved') &&
          (behavior.transitions['Resolved'] ?? []).contains('Queued'),
    ),
    'Include the requested reversible workflow.',
  );
  _require(
    _visible(spec).any(
      (view) =>
          view.type == 'board' &&
          view.groupByFieldId == stage.id &&
          view.options['moveActionId'] is String,
    ),
    'Configure a draggable Stage board.',
  );
}
