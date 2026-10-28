import 'package:appnest_spec/appnest_spec.dart';

import 'generation_quality.dart';

/// A deliberately narrow extraction of explicit creation requirements. It does
/// not infer a product from keywords or substitute a template. Ambiguous prose
/// remains the provider's responsibility; supported, literal contracts can be
/// checked before an otherwise schema-valid definition reaches preview.
class GenerationRequirements {
  final String? policy;
  final Map<String, List<String>> choices;
  final List<String> filters, groupedSummaries;
  final Map<String, String> filteredTabs;
  final bool searchableList, singleRecordCollection, dedicatedRecordRoutes;
  final bool sharedRecordCreation;
  final OwnerInboxReminderRequirement? ownerInboxReminder;
  final List<NumericInputRangeRequirement> numericInputRanges;
  final List<RecordCheckboxRequirement> recordCheckboxes;

  const GenerationRequirements({
    this.policy,
    this.choices = const {},
    this.filters = const [],
    this.groupedSummaries = const [],
    this.filteredTabs = const {},
    this.searchableList = false,
    this.singleRecordCollection = false,
    this.dedicatedRecordRoutes = false,
    this.sharedRecordCreation = false,
    this.ownerInboxReminder,
    this.numericInputRanges = const [],
    this.recordCheckboxes = const [],
  });

  factory GenerationRequirements.fromRequest(String request) {
    final singleCollections =
        RegExp(
              r'\b(?:use|using)\s+(?:one|a single|single)\s+[A-Za-z][A-Za-z0-9 -]{0,60}?\s+collection\s+with\b',
              caseSensitive: false,
            )
            .allMatches(request)
            .where(
              (match) => _affirmativeClause(request, match.start),
            )
            .toList();
    final otherCollections =
        RegExp(
              r'\b(?:another|second|two|multiple)\s+(?:[A-Za-z][A-Za-z0-9 -]{0,40}?\s+)?collections?\b',
              caseSensitive: false,
            )
            .allMatches(request)
            .any(
              (match) => _affirmativeClause(request, match.start),
            );
    // More than one affirmative mention is ambiguous even when a second
    // collection is introduced as "add a People collection", not "another".
    // Falling back to the general grammar is safer than constraining that app.
    final collectionMentions =
        RegExp(
              r'\bcollections?\b',
              caseSensitive: false,
            )
            .allMatches(request)
            .where(
              (match) => _affirmativeClause(request, match.start),
            )
            .length;
    final singleRecordCollection =
        singleCollections.length == 1 &&
        collectionMentions == 1 &&
        !otherCollections;
    final dedicatedRecordRoutes =
        singleRecordCollection &&
        RegExp(
              r'\b(?:include|use|add)\s+(?:a\s+)?dedicated\s+[A-Za-z][A-Za-z0-9 -]{0,40}?\s+details(?:\s+page)?\s+and\s+(?:a\s+)?shared\s+add/edit\s+[A-Za-z][A-Za-z0-9 -]{0,40}?\s+(?:form\s+)?pages?\b',
              caseSensitive: false,
            )
            .allMatches(request)
            .any(
              (match) => _affirmativeClause(request, match.start),
            );
    final policies =
        RegExp(
              r'\b(?:use|using|with)\s+(?:the\s+)?(personalTracker\.v1|groupWorkflow\.v1|groupCapacitySignup\.v1)\b',
              caseSensitive: false,
            )
            .allMatches(request)
            .where((match) => _affirmativeClause(request, match.start))
            .map(
              (match) => policyPresets.firstWhere(
                (value) => value.toLowerCase() == match.group(1)!.toLowerCase(),
              ),
            )
            .toSet();
    final choices = <String, List<String>>{};
    for (final match in RegExp(
      r'(?:^|[,.;]|\band\b|\bwith\b|\blabeled\b)\s*([A-Za-z][A-Za-z0-9 -]{0,60}?)\s*\((?:required|optional)\s+choice:\s*([^()]+)\)',
      caseSensitive: false,
    ).allMatches(request)) {
      // Include the field-label prefix when checking a negative example such
      // as "Do not add Status (required choice: Open, Done)".
      if (!_affirmativeClause(
        request,
        match.start + match.group(0)!.indexOf('('),
      )) {
        continue;
      }
      final label = match
          .group(1)!
          .trim()
          .replaceFirst(
            RegExp(r'^(?:(?:and|fields|field)\s+)+', caseSensitive: false),
            '',
          );
      final values = match
          .group(2)!
          .split(',')
          .map((value) => value.trim())
          .toList();
      if (values.isNotEmpty &&
          values.length <= 30 &&
          values.every((value) => value.isNotEmpty && value.length <= 80) &&
          values.toSet().length == values.length) {
        choices[label] = values;
      }
    }
    final filters = <String>[];
    final summaries = <String>[];
    for (final label in choices.keys) {
      final escaped = RegExp.escape(label);
      // Covers literal field lists such as "Category/Packing status filters".
      final filterPattern = RegExp(
        '\\b$escaped(?:(?:\\s*/\\s*|\\s+and\\s+)[A-Za-z][A-Za-z0-9 /-]{0,60})?\\s+filters?\\b',
        caseSensitive: false,
      );
      if (filterPattern
          .allMatches(request)
          .any(
            (match) => _affirmativeClause(request, match.start),
          )) {
        filters.add(label);
      }
      if (RegExp(
            '(?:grouped (?:count )?summary|grouped counts?|grouping saved (?:entries|records)|summary(?: grouped)?)\\s+by\\s+$escaped\\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .any((match) => _affirmativeClause(request, match.start))) {
        summaries.add(label);
      }
    }
    final tabs = <String, String>{};
    for (final match in RegExp(
      r'\b(?:a|an|the)\s+([A-Za-z][A-Za-z0-9 -]{0,40}?)\s+(?:tab|page)\s+filtered\s+to\s+([^.;]+)',
      caseSensitive: false,
    ).allMatches(request)) {
      if (!_affirmativeClause(request, match.start)) continue;
      final text = match.group(2)!.trim();
      final values = choices.values
          .expand((value) => value)
          .where(
            (value) => RegExp(
              '^${RegExp.escape(value)}(?:\\b|\$)',
              caseSensitive: false,
            ).hasMatch(text),
          )
          .toSet();
      if (values.length == 1) tabs[match.group(1)!.trim()] = values.single;
    }
    return GenerationRequirements(
      policy: policies.length == 1 && !_ambiguousPolicyAlternatives(request)
          ? policies.single
          : null,
      choices: choices,
      filters: filters,
      groupedSummaries: summaries,
      filteredTabs: tabs,
      singleRecordCollection: singleRecordCollection,
      dedicatedRecordRoutes: dedicatedRecordRoutes,
      searchableList:
          RegExp(
                r'\bsearchable(?:\s+[A-Za-z][A-Za-z-]*){0,3}\s+(?:list|table)\b',
                caseSensitive: false,
              )
              .allMatches(request)
              .any(
                (match) => _literalAffirmativeSpan(
                  request,
                  match.start,
                  match.end,
                ),
              ),
      ownerInboxReminder: _ownerInboxReminder(request),
      sharedRecordCreation: _sharedRecordCreation(request, policies),
      numericInputRanges: _numericInputRanges(request),
      recordCheckboxes: _recordCheckboxes(request),
    );
  }

  bool get isEmpty =>
      policy == null &&
      choices.isEmpty &&
      filters.isEmpty &&
      groupedSummaries.isEmpty &&
      filteredTabs.isEmpty &&
      !searchableList &&
      !singleRecordCollection &&
      !dedicatedRecordRoutes &&
      !sharedRecordCreation &&
      ownerInboxReminder == null &&
      numericInputRanges.isEmpty &&
      recordCheckboxes.isEmpty;

  String? get preferredPolicy =>
      policy ?? (sharedRecordCreation ? 'groupWorkflow.v1' : null);

  Map<String, dynamic> toJson() => {
    if (preferredPolicy != null) 'policyPresetRequest': preferredPolicy,
    if (sharedRecordCreation) 'sharedRecordCreation': true,
    if (choices.isNotEmpty) 'exactChoiceFields': choices,
    if (filters.isNotEmpty) 'visibleChoiceFilters': filters,
    if (groupedSummaries.isNotEmpty) 'groupedSummaries': groupedSummaries,
    if (filteredTabs.isNotEmpty) 'filteredTabs': filteredTabs,
    if (searchableList) 'searchableRecordList': true,
    if (singleRecordCollection) 'singleRecordCollection': true,
    if (dedicatedRecordRoutes) 'dedicatedRecordRoutes': true,
    if (ownerInboxReminder != null)
      'ownerInboxReminder': ownerInboxReminder!.toJson(),
    if (numericInputRanges.isNotEmpty)
      'numericInputRanges': numericInputRanges
          .map((range) => range.toJson())
          .toList(),
    if (recordCheckboxes.isNotEmpty)
      'recordCheckboxes': recordCheckboxes
          .map((value) => value.toJson())
          .toList(),
  };

  void validate(AppSpec spec) {
    final issues = <String>[];
    if (singleRecordCollection && spec.collections.length != 1) {
      issues.add('Use exactly one collection as explicitly requested.');
    }
    if (policy != null && spec.policyPresetRequest != policy) {
      issues.add('Use the explicitly requested policyPresetRequest $policy.');
    }
    if (sharedRecordCreation &&
        spec.policyPresetRequest != 'groupWorkflow.v1') {
      issues.add(
        'The explicitly requested participant record creation needs '
        'policyPresetRequest groupWorkflow.v1 so approved members can add '
        'their records. A personalTracker.v1 app restricts writes to its owner.',
      );
    }
    final visibleViews = spec.navigation == null
        ? spec.views
        : {
                spec.navigation!.entryPageId,
                ...spec.navigation!.tabs.map((tab) => tab.pageId),
              }
              .expand((pageId) => spec.page(pageId).viewIds.map(spec.view))
              .toList();
    if (searchableList &&
        !visibleViews.any(
          (view) =>
              {'list', 'table'}.contains(view.type) &&
              view.titleFieldId != null &&
              spec
                      .collection(view.collectionId)
                      .field(view.titleFieldId!)
                      .type ==
                  FieldType.text,
        )) {
      issues.add(
        'A requested searchable record list needs a text titleFieldId on a visible list or table. Choice filters are optional.',
      );
    }
    ownerInboxReminder?.validate(spec, issues);
    for (final range in numericInputRanges) {
      range.validate(spec, issues);
    }
    for (final checkbox in recordCheckboxes) {
      checkbox.validate(spec, visibleViews, issues);
    }
    for (final entry in choices.entries) {
      final matches = [
        for (final collection in spec.collections)
          for (final field in collection.fields)
            if (field.label.toLowerCase() == entry.key.toLowerCase())
              (collection, field),
      ];
      if (matches.length != 1) {
        issues.add(
          'Include the explicitly requested ${entry.key} choice field.',
        );
        continue;
      }
      final (collection, field) = matches.single;
      if (field.type != FieldType.choice ||
          field.choices.length != entry.value.length ||
          field.choices.asMap().entries.any(
            (item) => item.value != entry.value[item.key],
          )) {
        issues.add(
          '${entry.key} must preserve the requested choices in order: ${entry.value.join(', ')}.',
        );
      }
      if (filters.contains(entry.key) &&
          !visibleViews.any(
            (view) =>
                {
                  'list',
                  'board',
                  'table',
                  'calendar',
                  'timeline',
                  'imageCards',
                  'gallery',
                  'checklist',
                }.contains(view.type) &&
                view.collectionId == collection.id &&
                view.filterFieldIds.contains(field.id),
          )) {
        issues.add(
          'Expose ${entry.key} with filterFieldIds on its visible record list.',
        );
      }
      if (groupedSummaries.contains(entry.key) &&
          !visibleViews.any(
            (view) =>
                view.type == 'summary' &&
                view.collectionId == collection.id &&
                view.groupByFieldId == field.id,
          )) {
        issues.add(
          'A visible summary must groupByFieldId the requested ${entry.key} field.',
        );
      }
    }
    for (final entry in filteredTabs.entries) {
      final navigation = spec.navigation;
      final tabs =
          navigation?.tabs
              .where(
                (tab) => tab.label.toLowerCase() == entry.key.toLowerCase(),
              )
              .toList() ??
          [];
      final fields = [
        for (final collection in spec.collections)
          for (final field in collection.fields)
            if (field.type == FieldType.choice &&
                field.choices.contains(entry.value))
              (collection, field),
      ];
      // Do not guess which field was intended when two fields share this value.
      if (fields.length != 1) continue;
      final (collection, field) = fields.single;
      final views = tabs
          .expand((tab) => spec.page(tab.pageId).viewIds.map(spec.view))
          .where(
            (view) =>
                view.collectionId == collection.id &&
                !{'summary', 'metric', 'chart'}.contains(view.type),
          )
          .toList();
      if (views.isEmpty ||
          views.any(
            (view) => !(view.query?['filters'] as List? ?? []).any(
              (filter) =>
                  filter is Map &&
                  filter['fieldId'] == field.id &&
                  filter['operator'] == 'eq' &&
                  filter['value'] == entry.value,
            ),
          )) {
        issues.add(
          '${entry.key} must query only ${entry.value} records using an equality filter on ${field.label}.',
        );
      }
    }
    if (issues.isNotEmpty) throw SpecException(issues.join(' '));
  }
}

/// A form-input contract, not a record-schema range invariant. The current
/// numeric field schema remains unchanged; authenticated API writes continue
/// to use its existing safe-number/type validation.
class NumericInputRangeRequirement {
  final String label;
  final num min, max;
  final bool integer;

  const NumericInputRangeRequirement(
    this.label,
    this.min,
    this.max, {
    required this.integer,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'type': integer ? 'integer' : 'number',
    'min': min,
    'max': max,
    'reachableCreateAndEditForms': true,
  };

  void validate(AppSpec spec, List<String> issues) {
    final matches = [
      for (final collection in spec.collections)
        for (final field in collection.fields)
          if (field.label.toLowerCase() == label.toLowerCase())
            (collection, field),
    ];
    if (matches.length != 1) {
      issues.add(
        'Include one unambiguous $label numeric field for the explicit input range.',
      );
      return;
    }
    final (collection, field) = matches.single;
    if (field.type != (integer ? FieldType.integer : FieldType.number)) {
      issues.add(
        '$label must preserve its requested ${integer ? 'integer' : 'number'} input type.',
      );
      return;
    }
    final forms = reachableGeneratedRecordForms(spec, collection.id);
    bool bounded(ViewSpec form) {
      if (form.fieldIds.isNotEmpty && !form.fieldIds.contains(field.id)) {
        return false;
      }
      final controls = (form.options['controls'] as List? ?? []).cast<Map>();
      final control = controls
          .where((item) => item['fieldId'] == field.id)
          .singleOrNull;
      if (control == null) return false;
      if (control['control'] == 'rating') {
        return integer && min == 1 && max == 5;
      }
      return {'slider', 'stepper'}.contains(control['control']) &&
          control['min'] == min &&
          control['max'] == max &&
          (!integer || control['step'] == 1);
    }

    if (forms.isEmpty || forms.any((form) => !bounded(form))) {
      issues.add(
        '$label needs a bounded numeric control from $min to $max '
        'on every reachable create/edit form, using its authored field ID. '
        '${integer && min == 1 && max == 5 ? 'Use rating, or a slider/stepper with min:1, max:5, step:1.' : 'Use a slider/stepper with the exact requested min/max${integer ? ' and step:1' : ''}.'} '
        'An unbounded default numeric input or an orphaned form does not satisfy the request.',
      );
    }
  }
}

/// A requested record checkbox is a reachable checklist interaction, not just
/// a field or menu label. Both supported storage representations use the
/// platform's strictly validated toggle path.
class RecordCheckboxRequirement {
  final String label;
  final bool requireBinaryInitialization;
  const RecordCheckboxRequirement(
    this.label, {
    this.requireBinaryInitialization = true,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'reachableChecklist': true,
    'requireBinaryInitialization': requireBinaryInitialization,
  };

  void validate(
    AppSpec spec,
    List<ViewSpec> visibleViews,
    List<String> issues,
  ) {
    final matches = [
      for (final collection in spec.collections)
        for (final field in collection.fields)
          if (field.type == FieldType.boolean &&
                  field.label.toLowerCase() == label.toLowerCase() ||
              field.type == FieldType.choice &&
                  field.choices.length == 2 &&
                  field.choices.any(
                    (value) => value.toLowerCase() == label.toLowerCase(),
                  ))
            (collection, field),
    ];
    if (matches.length != 1) {
      issues.add(
        'Resolve the explicitly requested $label checkbox to one unambiguous boolean field label or two-state checked value.',
      );
      return;
    }
    final (collection, field) = matches.single;
    if (field.type == FieldType.boolean && requireBinaryInitialization) {
      if (!field.required) {
        issues.add(
          'The $label checkbox needs a required boolean field so new items have '
          'a checked or unchecked value rather than an unset third state.',
        );
      }
      final forms = reachableGeneratedRecordForms(spec, collection.id);
      final createForms = reachableGeneratedRecordForms(
        spec,
        collection.id,
        creationOnly: true,
      );
      if (createForms.isEmpty ||
          forms.any(
            (form) =>
                form.fieldIds.isNotEmpty && !form.fieldIds.contains(field.id),
          )) {
        issues.add(
          'Include the $label boolean field on every reachable create/edit '
          'form, with an actual reachable create route. The existing editor '
          'initializes a visible required boolean to false; do not invent '
          'a stored default or leave the field out of the form.',
        );
      }
    }
    final controls = visibleViews.where(
      (view) =>
          view.type == 'checklist' &&
          view.collectionId == collection.id &&
          view.options['fieldId'] == field.id &&
          (field.type == FieldType.boolean ||
              (view.options['checkedValue'] as String).toLowerCase() ==
                  label.toLowerCase()),
    );
    if (controls.isEmpty) {
      issues.add(
        'Expose a reachable $label checklist checkbox on the entry page or a tab. '
        'Bind checklist.options.fieldId to the authored field and options.actionId to its actual toggle action, also in actionIds. '
        'Use a boolean with records.patch.v1, or a reversible two-choice workflow checklist with explicit checkedValue:$label and uncheckedValue. '
        'A stored status, workflow menu, checkbox in a hidden form or orphaned checklist does not provide the requested tick interaction.',
      );
      return;
    }
    for (final control in controls) {
      final action = spec.action(control.options['actionId'] as String);
      if (!control.actionIds.contains(action.id) ||
          action.collectionId != collection.id ||
          action.capability !=
              (field.type == FieldType.boolean
                  ? 'records.patch.v1'
                  : 'workflow.transition.v1')) {
        issues.add(
          'The $label checkbox must use its validated same-collection toggle action.',
        );
      }
    }
  }
}

List<RecordCheckboxRequirement> _recordCheckboxes(String request) {
  if (!_unambiguousRequirementScope(request)) return const [];
  final found = <String, RecordCheckboxRequirement>{};
  final initializationDeclarations = <String, bool>{};
  final ambiguous = <String>{};
  final patterns = [
    RegExp(
      r'\b(?:a|an|the)\s+([A-Za-z][A-Za-z0-9 -]{0,40}?)\s+checkbox\b',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:^|[,.;]|\band\b|\bwith\b)\s*([A-Za-z][A-Za-z0-9 -]{0,40}?)\s*\((?:required|optional)\s+checkbox\)',
      caseSensitive: false,
    ),
  ];
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(request)) {
      final declaredLabel = match
          .group(1)!
          .trim()
          .replaceFirst(
            RegExp(r'^.*\bcollection\s+with\s+', caseSensitive: false),
            '',
          )
          .replaceFirst(
            RegExp(
              r"^(?:do not|don't|never|avoid|without|no)\s+",
              caseSensitive: false,
            ),
            '',
          )
          .replaceFirst(
            RegExp(
              r'^(?:include|add|save|record|track|use)\s+',
              caseSensitive: false,
            ),
            '',
          );
      final prefix = RegExp(
        r'^(optional|required)\s+',
        caseSensitive: false,
      ).firstMatch(declaredLabel)?.group(1)?.toLowerCase();
      final annotation = RegExp(
        r'\((optional|required)\s+checkbox\)',
        caseSensitive: false,
      ).firstMatch(match.group(0)!)?.group(1)?.toLowerCase();
      // Only an immediate same-checkbox modifier at a clause boundary is a
      // declaration. A later unqualified reference is not "required" prose.
      final suffixMatch = RegExp(
        r'^\s*(?:\((optional|required)\)|that\s+is\s+(optional|required))(?=\s*(?:[.,;!?]|$))',
        caseSensitive: false,
      ).firstMatch(request.substring(match.end));
      final suffix = (suffixMatch?.group(1) ?? suffixMatch?.group(2))
          ?.toLowerCase();
      final declarations = <bool>{
        if (prefix != null) prefix == 'required',
        if (annotation != null) annotation == 'required',
        if (suffix != null) suffix == 'required',
      };
      final label = declaredLabel.replaceFirst(
        RegExp(r'^(?:optional|required)\s+', caseSensitive: false),
        '',
      );
      final key = label.toLowerCase();
      if (!_literalExplicitSpan(request, match.start, match.end) ||
          declarations.length > 1) {
        ambiguous.add(key);
      } else {
        if (declarations.singleOrNull case final declaration?) {
          if (initializationDeclarations[key] case final previous?
              when previous != declaration) {
            ambiguous.add(key);
          }
          initializationDeclarations[key] = declaration;
        }
        found[key] = RecordCheckboxRequirement(
          label,
          requireBinaryInitialization: initializationDeclarations[key] ?? true,
        );
      }
    }
  }
  return [
    for (final entry in found.entries)
      if (!ambiguous.contains(entry.key)) entry.value,
  ];
}

List<NumericInputRangeRequirement> _numericInputRanges(String request) {
  // Only literal field declarations and explicitly named rating phrases are
  // supported. Multiple collection/app scopes or alternatives stay with the
  // provider; no field is selected from its ID, position or approximate label.
  if (!_unambiguousRequirementScope(request)) return const [];
  const number = r'(-?\d+(?:\.\d+)?)';
  final found = <String, NumericInputRangeRequirement>{};
  final ambiguous = <String>{};
  void add(
    RegExpMatch match,
    String label,
    String type,
    String low,
    String high,
  ) {
    if (!_literalExplicitSpan(request, match.start, match.end)) return;
    final min = num.tryParse(low), max = num.tryParse(high);
    final integer = type.toLowerCase() == 'integer';
    if (min == null ||
        max == null ||
        !min.isFinite ||
        !max.isFinite ||
        min >= max ||
        min.abs() > 1e15 ||
        max.abs() > 1e15 ||
        integer && (min != min.round() || max != max.round())) {
      return;
    }
    label = label
        .trim()
        .replaceFirst(
          RegExp(r'^.*\bcollection\s+with\s+', caseSensitive: false),
          '',
        )
        .replaceFirst(
          RegExp(r'^(?:(?:and|fields|field)\s+)+', caseSensitive: false),
          '',
        )
        .replaceFirst(
          RegExp(
            r'^(?:include|add|save|record|track|use)\s+',
            caseSensitive: false,
          ),
          '',
        );
    final key = label.toLowerCase();
    final value = NumericInputRangeRequirement(
      label,
      min,
      max,
      integer: integer,
    );
    final previous = found[key];
    if (previous != null &&
        (previous.min != min ||
            previous.max != max ||
            previous.integer != integer)) {
      ambiguous.add(key);
    }
    found[key] = value;
  }

  final fields = RegExp(
    r'(?:^|[,.;]|\band\b|\bwith\b|\blabeled\b)\s*([A-Za-z][A-Za-z0-9 -]{0,60}?)\s*\((?:required|optional)\s+(integer|number)\s+from\s+' +
        number +
        r'\s+to\s+' +
        number +
        r'\s*\)',
    caseSensitive: false,
  );
  for (final match in fields.allMatches(request)) {
    add(
      match,
      match.group(1)!,
      match.group(2)!,
      match.group(3)!,
      match.group(4)!,
    );
  }
  final ratings = RegExp(
    r'\b(?:a|the)\s+((?:[A-Za-z][A-Za-z-]*\s+){0,3}rating)\s+from\s+' +
        number +
        r'\s+to\s+' +
        number +
        r'\b',
    caseSensitive: false,
  );
  for (final match in ratings.allMatches(request)) {
    add(match, match.group(1)!, 'integer', match.group(2)!, match.group(3)!);
  }
  return [
    for (final entry in found.entries)
      if (!ambiguous.contains(entry.key)) entry.value,
  ];
}

bool _unambiguousRequirementScope(String request) {
  final scopes = RegExp(r'\b(?:apps?|collections?)\b', caseSensitive: false)
      .allMatches(request)
      .where((m) => _literalAffirmativeSpan(request, m.start, m.end));
  return scopes
              .where((m) => m.group(0)!.toLowerCase().startsWith('app'))
              .length <=
          1 &&
      scopes
              .where((m) => m.group(0)!.toLowerCase().startsWith('collection'))
              .length <=
          1 &&
      !RegExp(
            r'\b(?:another|second|multiple|two)\s+(?:[A-Za-z][A-Za-z-]*\s+){0,3}(?:apps?|collections?)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .any((m) => _literalAffirmativeSpan(request, m.start, m.end));
}

bool _literalExplicitSpan(String request, int start, int end) {
  if (!_literalAffirmativeSpan(request, start, end)) return false;
  final clause = _clauseAt(request, start, end);
  if (RegExp(
    r"\b(?:or|either|not|no|without|avoid|don't|never|example|sample|hypothetical|maybe|perhaps|consider|later|eventually)\b",
    caseSensitive: false,
  ).hasMatch(clause)) {
    return false;
  }
  for (final pattern in [
    r'"[^"]*"',
    r'`[^`]*`',
    r'“[^”]*”',
    r'‘[^’]*’',
    r"(?<![A-Za-z])'[^']*'(?![A-Za-z])",
  ]) {
    if (RegExp(pattern)
        .allMatches(request)
        .any(
          (quote) => start < quote.end && end > quote.start,
        )) {
      return false;
    }
  }
  return true;
}

bool _sharedRecordCreation(String request, Set<String> explicitPolicies) {
  // Preserve engineered policy contracts and leave contradictory/undecided
  // policy prose to the provider. Sharing words alone never grant access.
  if (explicitPolicies.isNotEmpty ||
      RegExp(
            r'\b(?:personalTracker\.v1|groupWorkflow\.v1|groupCapacitySignup\.v1)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .any(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          )) {
    return false;
  }
  final scopes =
      RegExp(
            r'\b(?:apps?|collections?)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .where(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          );
  if (scopes
              .where((match) => match.group(0)!.toLowerCase().startsWith('app'))
              .length >
          1 ||
      scopes
              .where(
                (match) =>
                    match.group(0)!.toLowerCase().startsWith('collection'),
              )
              .length >
          1 ||
      RegExp(
            r'\b(?:another|second|multiple|two)\s+(?:[A-Za-z][A-Za-z-]*\s+){0,3}(?:apps?|collections?|trackers?)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .any(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          )) {
    return false;
  }
  return RegExp(
        r'\b(?:everyone|(?:all\s+)?(?:members|friends|participants|neighbors|people|teammates|family\s+members))\s+(?:(?:to|can|should|must|will)\s+|will\s+be\s+able\s+to\s+)?(?:add|create|submit|enter)s?\s+(?:their|our)\s+(?:own\s+)?[A-Za-z][A-Za-z-]{0,60}\b',
        caseSensitive: false,
      )
      .allMatches(request)
      .any(
        (match) => _literalAffirmativeSpan(request, match.start, match.end),
      );
}

bool _ambiguousPolicyAlternatives(String request) {
  const name =
      r'(personalTracker\.v1|groupWorkflow\.v1|groupCapacitySignup\.v1)';
  return RegExp(
        '$name\\s+(?:or|versus|vs\\.?)\\s+(?:(?:use|using|with)\\s+)?$name',
        caseSensitive: false,
      )
      .allMatches(request)
      .any(
        (match) =>
            match.group(1)!.toLowerCase() != match.group(2)!.toLowerCase() &&
            _literalAffirmativeSpan(request, match.start, match.end),
      );
}

/// Literal owner-inbox scheduling requirements, independent of authored IDs or
/// field labels. AppSpec has already validated every rule's references/types.
class OwnerInboxReminderRequirement {
  final bool optionalTimestamp, distinctOptionalDueDate, openCompletedCondition;
  const OwnerInboxReminderRequirement({
    this.optionalTimestamp = false,
    this.distinctOptionalDueDate = false,
    this.openCompletedCondition = false,
  });

  Map<String, dynamic> toJson() => {
    'effect': 'notifyOwner',
    'optionalTimestamp': optionalTimestamp,
    'distinctOptionalDueDate': distinctOptionalDueDate,
    'openCompletedCondition': openCompletedCondition,
  };

  void validate(AppSpec spec, List<String> issues) {
    if (spec.policyPresetRequest != 'personalTracker.v1') {
      issues.add(
        'Explicit personal inbox reminders need policyPresetRequest personalTracker.v1.',
      );
    }
    final rules = spec.automationRequests
        .where((rule) => rule.effect == 'notifyOwner')
        .toList();
    if (rules.isEmpty) {
      issues.add(
        'The explicit AppNest inbox reminder needs an automationRequests rule '
        'with a beforeTimestamp trigger and notifyOwner inApp effect; a stored '
        'reminder-time field or an Inbox record view alone does not deliver reminders.',
      );
      return;
    }
    bool optional(AutomationSpec rule) =>
        !spec.collection(rule.collectionId).field(rule.fieldId).required;
    bool separateDueDate(AutomationSpec rule) {
      final collection = spec.collection(rule.collectionId);
      final separate = collection.fields.any(
        (field) =>
            field.id != rule.fieldId &&
            field.type == FieldType.timestamp &&
            !field.required,
      );
      final calendarFields = spec.views
          .where(
            (view) =>
                view.collectionId == collection.id && view.type == 'calendar',
          )
          .map((view) => view.options['dateFieldId']);
      return separate &&
          calendarFields.every(
            (id) =>
                id != rule.fieldId &&
                id is String &&
                !collection.field(id).required,
          );
    }

    bool openCondition(AutomationSpec rule) {
      final condition = rule.condition;
      if (condition == null || condition.value.toLowerCase() != 'open') {
        return false;
      }
      final field = spec.collection(rule.collectionId).field(condition.fieldId);
      final choices = field.choices.map((value) => value.toLowerCase()).toSet();
      return field.type == FieldType.choice &&
          choices.containsAll({'open', 'completed'});
    }

    if (!rules.any(
      (rule) =>
          (!optionalTimestamp || optional(rule)) &&
          (!distinctOptionalDueDate || separateDueDate(rule)) &&
          (!openCompletedCondition || openCondition(rule)),
    )) {
      issues.add(
        'The owner inbox reminder rule must use '
        '${optionalTimestamp ? 'an optional' : 'a'} timestamp field'
        '${distinctOptionalDueDate ? ', distinct from a second optional due-date timestamp and any due-date calendar binding' : ''}'
        '${openCompletedCondition ? ', with a condition on the declared Open/Completed choice field equal to its Open value so completed items do not notify' : ''}. '
        'Use the authored collection/field IDs and actual declared choice casing.',
      );
    }
  }
}

OwnerInboxReminderRequirement? _ownerInboxReminder(String request) {
  // This gate addresses one explicit personal scheduling scope. Multiple apps,
  // collections, recipients or shared workflows need provider interpretation.
  final scopes =
      RegExp(
            r'\b(?:apps?|collections?)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .where(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          );
  if (scopes
              .where((match) => match.group(0)!.toLowerCase().startsWith('app'))
              .length >
          1 ||
      scopes
              .where(
                (match) =>
                    match.group(0)!.toLowerCase().startsWith('collection'),
              )
              .length >
          1 ||
      RegExp(
            r'\b(?:another|second|multiple|two)\s+(?:[A-Za-z][A-Za-z-]*\s+){0,3}(?:apps?|collections?|trackers?)\b|\b(?:shared|team|household|everyone|members|colleagues)\b',
            caseSensitive: false,
          )
          .allMatches(request)
          .any(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          )) {
    return null;
  }
  final inboxes =
      RegExp(
            r"\b(?:my\s+(?:AppNest\s+)?|personal\s+(?:AppNest\s+)?|owner(?:'s)?\s+|AppNest\s+)inbox\b",
            caseSensitive: false,
          )
          .allMatches(request)
          .where(
            (match) => _literalAffirmativeSpan(request, match.start, match.end),
          )
          .toList();
  if (inboxes.length != 1) return null;
  final inbox = inboxes.single;
  final clause = _clauseAt(request, inbox.start, inbox.end);
  if (!RegExp(
        r'\b(?:reminders?|remind\s+me)\b',
        caseSensitive: false,
      ).hasMatch(clause) ||
      (!RegExp(
        r'\b(?:my|personal|owner)\b',
        caseSensitive: false,
      ).hasMatch(clause))) {
    return null;
  }
  bool explicit(String pattern) => RegExp(pattern, caseSensitive: false)
      .allMatches(request)
      .any((match) => _literalAffirmativeSpan(request, match.start, match.end));
  final optionalReminder = explicit(
    r'\boptional\s+(?:[A-Za-z][A-Za-z-]*\s+){0,2}reminder\s+(?:time|date|timestamp)s?\b|\breminder\s+(?:time|date|timestamp)s?\s+(?:is\s+)?optional\b',
  );
  final optionalDue = explicit(r'\boptional\s+due\s+dates?\b');
  final separate = explicit(
    r'\b(?:separate|distinct|different)\s+(?:[A-Za-z][A-Za-z-]*\s+){0,3}reminder\s+(?:time|date|timestamp)s?\b|\breminder\s+(?:time|date|timestamp)s?\s+(?:[A-Za-z][A-Za-z-]*\s+){0,3}(?:separate|distinct|different)\b',
  );
  return OwnerInboxReminderRequirement(
    optionalTimestamp: optionalReminder,
    distinctOptionalDueDate: optionalDue && separate,
    openCompletedCondition: explicit(
      r'\b(?:open\s*(?:and|or|/|,)\s*completed|completed\s*(?:and|or|/|,)\s*open)\b',
    ),
  );
}

String _clauseAt(String request, int start, int end) {
  final before = request.substring(0, start);
  final from = before.lastIndexOf(RegExp(r'[.;\n]')) + 1;
  final following = RegExp(r'[.;\n]').firstMatch(request.substring(end));
  return request.substring(
    from,
    following == null ? request.length : end + following.start,
  );
}

bool _literalAffirmativeSpan(String request, int start, int end) {
  final before = request.substring(0, start);
  final from = before.lastIndexOf(RegExp(r'[.;\n]')) + 1;
  final clause = _clauseAt(request, start, end);
  final prefix = request.substring(from, start);
  final suffix = clause.substring(end - from);
  return !RegExp(
        r'\b(?:example|examples|sample|hypothetical|maybe|perhaps|consider|later|eventually)\b',
        caseSensitive: false,
      ).hasMatch(clause) &&
      !RegExp(
        r"\b(?:do not|don't|never|without|no|not|avoid)\b",
        caseSensitive: false,
      ).hasMatch(prefix) &&
      !RegExp(
        r'^\s*(?:is|are|would be)?\s*(?:not\s+(?:needed|required|wanted)|unnecessary|only\s+an?\s+example)\b',
        caseSensitive: false,
      ).hasMatch(suffix);
}

bool _affirmativeClause(String request, int at) {
  final before = request.substring(0, at);
  final start = before.lastIndexOf(RegExp(r'[.;]')) + 1;
  return !RegExp(
    r"\b(?:do not|don't|never|without|no)\b",
    caseSensitive: false,
  ).hasMatch(before.substring(start));
}
