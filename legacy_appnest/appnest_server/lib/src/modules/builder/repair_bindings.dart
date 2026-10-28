import 'dart:collection';
import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';

import 'generation_requirements.dart';

/// Authoring-envelope and size/depth bounds only, never AppSpec acceptance.
bool isBoundedCreationRepairCandidate(Map<String, dynamic> candidate) =>
    candidate['formatVersion'] == 1 && _boundedCandidate(candidate);

/// A bounded, non-executable retry checklist derived from the rejected
/// definition's existing IDs and the original request. It never constructs,
/// repairs, publishes or returns an AppSpec candidate.
Map<String, dynamic> creationRepairBindings(
  Map<String, dynamic> rejected,
  GenerationRequirements requirements, {
  String request = '',
}) {
  if (rejected['formatVersion'] != 1 || !_boundedCandidate(rejected)) return {};
  final collections = _uniqueMaps(rejected['collections'], Limits.collections);
  final views = _uniqueMaps(rejected['views'], Limits.views);
  final navigation = rejected['navigation'];
  final pages = navigation is Map
      ? _uniqueMaps(navigation['pages'], 16)
      : <Map>[];
  final tabs = navigation is Map ? _maps(navigation['tabs'], 5) : <Map>[];
  final visiblePages = {
    if (navigation is Map && _id(navigation['entryPageId']))
      navigation['entryPageId'],
    ...tabs.where((tab) => _id(tab['pageId'])).map((tab) => tab['pageId']),
  };
  final visibleIds = pages
      .where((page) => visiblePages.contains(page['id']))
      .expand((page) => _ids(page['viewIds']))
      .toSet();
  final entryIds = navigation is Map
      ? pages
            .where((page) => page['id'] == navigation['entryPageId'])
            .expand((page) => _ids(page['viewIds']))
            .toSet()
      : <String>{};
  final bindings = <String, Map<String, dynamic>>{};
  Map<String, dynamic> forView(Map view) => bindings.putIfAbsent(
    view['id'] as String,
    () => {'viewId': view['id']},
  );
  for (final collection in collections.where(
    (collection) => _id(collection['id']),
  )) {
    final fields = _maps(collection['fields'], Limits.fields)
        .where(
          (field) =>
              _id(field['id']) &&
              field['label'] is String &&
              (field['label'] as String).length <= 160 &&
              FieldType.values.any((type) => type.name == field['type']),
        )
        .toList();
    final fieldIds = fields.map((field) => field['id']).toSet();
    if (fieldIds.length != fields.length) continue;
    final ownViews = views
        .where(
          (view) => _id(view['id']) && view['collectionId'] == collection['id'],
        )
        .toList();
    final mainLists = ownViews
        .where(
          (view) =>
              view['type'] == 'list' &&
              (navigation == null || visibleIds.contains(view['id'])),
        )
        .toList();
    final entryLists = mainLists
        .where((view) => entryIds.contains(view['id']))
        .toList();
    final source = entryLists.isEmpty
        ? mainLists.singleOrNull
        : entryLists.singleOrNull;
    Map? namedChoice(String label) {
      final matches = [
        for (final candidate in collections)
          for (final field in _maps(candidate['fields'], Limits.fields))
            if (_id(field['id']) &&
                field['label'] is String &&
                (field['label'] as String).toLowerCase() == label.toLowerCase())
              (candidate, field),
      ];
      if (matches.length != 1 ||
          matches.single.$1['id'] != collection['id'] ||
          matches.single.$2['type'] != 'choice') {
        return null;
      }
      return fields
          .where((field) => identical(field, matches.single.$2))
          .singleOrNull;
    }

    if (source != null) {
      final filterIds = requirements.filters
          .take(Limits.filters)
          .map(namedChoice)
          .whereType<Map>()
          .map((field) => field['id'] as String)
          .toList();
      if (filterIds.isNotEmpty) {
        forView(source)['includeFilterFieldIds'] = filterIds;
      }
      if (requirements.searchableList && filterIds.isNotEmpty) {
        final requiredText = fields
            .where(
              (field) => field['type'] == 'text' && field['required'] == true,
            )
            .toList();
        final title =
            fields
                .where(
                  (field) =>
                      field['id'] == source['titleFieldId'] &&
                      field['type'] == 'text',
                )
                .firstOrNull ??
            requiredText.singleOrNull;
        if (title != null) forView(source)['titleFieldId'] = title['id'];
      }
    }
    final managed = _maps(collection['behaviors'], 8)
        .where(
          (behavior) =>
              behavior['type'] == 'workflow.v1' &&
              fieldIds.contains(behavior['fieldId']),
        )
        .map((behavior) => behavior['fieldId'])
        .toSet();
    for (final form in ownViews.where((view) => view['type'] == 'form')) {
      final options = form['options'];
      if (options is! Map) continue;
      final invalid = _maps(options['controls'], Limits.fields)
          .where((control) => managed.contains(control['fieldId']))
          .map((control) => control['fieldId'] as String)
          .toSet();
      if (invalid.isNotEmpty) {
        forView(form)['removeControlsForFieldIds'] = invalid.toList();
      }
      final stepFields = _maps(options['steps'], 8)
          .expand((step) => _ids(step['fieldIds']))
          .where(managed.contains)
          .toSet();
      if (stepFields.isNotEmpty) {
        forView(form)['removeStepFieldIds'] = stepFields.toList();
      }
    }
    for (final label in requirements.groupedSummaries.take(Limits.fields)) {
      final field = namedChoice(label);
      final summaries = ownViews
          .where(
            (view) =>
                view['type'] == 'summary' &&
                (navigation == null || visibleIds.contains(view['id'])),
          )
          .toList();
      final summary =
          summaries
              .where((view) => view['groupByFieldId'] == field?['id'])
              .singleOrNull ??
          summaries.singleOrNull;
      if (field != null && summary != null) {
        forView(summary)['groupByFieldId'] = field['id'];
      }
    }
    for (final entry in requirements.filteredTabs.entries.take(5)) {
      final fieldsForValue = [
        for (final candidate in collections)
          for (final field in _maps(candidate['fields'], Limits.fields))
            if (_id(field['id']) &&
                field['type'] == 'choice' &&
                field['choices'] is List &&
                (field['choices'] as List).length <= 30 &&
                (field['choices'] as List).contains(entry.value))
              (candidate, field),
      ];
      if (fieldsForValue.length != 1 ||
          fieldsForValue.single.$1['id'] != collection['id'] ||
          !fieldIds.contains(fieldsForValue.single.$2['id'])) {
        continue;
      }
      final matchingTabs = tabs
          .where(
            (tab) =>
                tab['label'] is String &&
                (tab['label'] as String).toLowerCase() ==
                    entry.key.toLowerCase(),
          )
          .toList();
      if (matchingTabs.length != 1 || !_id(matchingTabs.single['pageId'])) {
        continue;
      }
      final pageIds = {matchingTabs.single['pageId']};
      final targets = pages
          .where((page) => pageIds.contains(page['id']))
          .expand((page) => _ids(page['viewIds']))
          .toSet();
      for (final view in ownViews.where(
        (view) =>
            targets.contains(view['id']) &&
            {
              'list',
              'board',
              'table',
              'calendar',
              'timeline',
              'imageCards',
              'gallery',
              'checklist',
            }.contains(view['type']),
      )) {
        forView(view)['includeQueryFilters'] = [
          {
            'fieldId': fieldsForValue.single.$2['id'],
            'operator': 'eq',
            'value': entry.value,
          },
        ];
      }
    }
  }
  final routes = creationRecordRouteBindings(rejected, request: request);
  for (final route in routes) {
    final view = views.singleWhere((view) => view['id'] == route['viewId']);
    final hint = forView(view);
    for (final key in ['detailPageId', 'formPageId']) {
      if (route.containsKey(key)) hint[key] = route[key];
    }
    hint['includeActionIds'] = route['requiredActionIds'];
  }
  final fieldBindings = creationFieldBindings(rejected);
  final actionDeclarations = creationDuplicateActionDeclarations(
    rejected,
    request: request,
  );
  final rawMetadata = creationRawRepairMetadata(rejected, request: request);
  return {
    if (bindings.isNotEmpty) 'views': bindings.values.toList(),
    if (routes.isNotEmpty) 'recordRoutes': routes,
    if (fieldBindings.isNotEmpty) 'fieldBindings': fieldBindings,
    if (actionDeclarations.isNotEmpty) 'actionDeclarations': actionDeclarations,
    ...rawMetadata,
  };
}

/// Retry evidence from a bounded rejected object, before whole-AppSpec parsing
/// can hide later defects behind the first invalid route. The AI still authors
/// every action role and the complete definition; these notes never repair it.
Map<String, dynamic> creationRawRepairMetadata(
  Map<String, dynamic> rejected, {
  String request = '',
}) {
  if (rejected['formatVersion'] != 1 ||
      !_boundedCandidate(rejected) ||
      request.length > Limits.promptBytes ||
      _negativeRouteInstruction(request)) {
    return {};
  }
  final collections = _strictIdentifiedMaps(
    rejected['collections'],
    Limits.collections,
  );
  final views = _strictIdentifiedMaps(rejected['views'], Limits.views);
  final rawActions = _strictIdentifiedMaps(rejected['actions'], Limits.actions);
  if (collections == null || views == null || rawActions == null) return {};
  final collectionIds = collections
      .map((collection) => collection['id'])
      .toSet();
  final actions = <ActionSpec>[];
  try {
    for (final raw in rawActions) {
      final action = ActionSpec.fromJson(Map<String, dynamic>.from(raw));
      if (!collectionIds.contains(action.collectionId)) return {};
      actions.add(action);
    }
  } on SpecException {
    return {};
  }
  // Duplicate field/behavior IDs also make raw references ambiguous. Do not
  // turn a malformed declaration into a unique identity by filtering it out.
  for (final collection in collections) {
    if (_strictIdentifiedMaps(collection['fields'], Limits.fields) == null ||
        _strictIdentifiedMaps(collection['behaviors'] ?? [], 8) == null) {
      return {};
    }
  }
  final diagnostics = <String>[];
  for (final collection in collections) {
    final id = collection['id'] as String;
    final ownActions = actions
        .where((action) => action.collectionId == id)
        .toList();
    final forms = views
        .where((view) => view['collectionId'] == id && view['type'] == 'form')
        .toList();
    if (forms.isNotEmpty ||
        ownActions.any((action) => action.capability.startsWith('records.'))) {
      final missing = [
        for (final capability in ['records.create.v1', 'records.patch.v1'])
          if (!ownActions.any((action) => action.capability == capability))
            capability,
      ];
      if (missing.isNotEmpty) {
        diagnostics.add(
          'Collection "$id" has forms or editable records and needs both '
          'records.create.v1 and records.patch.v1 actions. Missing capabilities: '
          '${missing.join(', ')}. Author the action roles; their IDs or labels '
          'do not determine their capabilities.',
        );
      }
    }
    for (final form in forms) {
      final ids = _ids(form['actionIds']);
      if (!ownActions.any(
        (action) =>
            ids.contains(action.id) && action.capability == 'records.create.v1',
      )) {
        diagnostics.add(
          'Form "${form['id']}" in collection "$id" must expose a '
          'same-collection records.create.v1 action in its actionIds.',
        );
      }
    }
    // Validate behavior declarations together with their real collection
    // fields. A status-looking field alone never implies a workflow.
    CollectionSpec? parsed;
    try {
      parsed = CollectionSpec.fromJson(Map<String, dynamic>.from(collection));
    } on SpecException {
      if ((collection['behaviors'] as List? ?? []).isNotEmpty) {
        diagnostics.add(
          'Collection "$id" has invalid behavior declarations. Behaviors must '
          'match their declared fields and supported behavior schema.',
        );
      }
    }
    for (final action in ownActions) {
      final expected = action.capability.startsWith('workflow.')
          ? 'workflow.v1'
          : action.capability.startsWith('assignment.')
          ? 'assignment.v1'
          : action.capability.startsWith('capacity.')
          ? 'capacity.v1'
          : null;
      if (expected == null) {
        if (action.behaviorId != null) {
          diagnostics.add(
            'Record action "${action.id}" must omit behaviorId; record '
            'create/edit actions do not bind behaviors.',
          );
        }
      } else if (parsed == null ||
          !parsed.behaviors.any(
            (behavior) =>
                behavior.id == action.behaviorId && behavior.type == expected,
          )) {
        diagnostics.add(
          'Action "${action.id}" (${action.capability}) needs behaviorId '
          'referencing a valid declared $expected behavior in collection "$id". '
          'Author a capability matching the intended operation; this checklist '
          'does not assign one to this action ID.',
        );
      }
    }
    for (final behavior in parsed?.behaviors ?? <BehaviorSpec>[]) {
      if (behavior.type == 'workflow.v1' &&
          !ownActions.any(
            (action) =>
                action.capability == 'workflow.transition.v1' &&
                action.behaviorId == behavior.id,
          )) {
        diagnostics.add(
          'Collection "$id" declares workflow "${behavior.id}" but has no '
          'workflow.transition.v1 action bound to that behavior. Author an '
          'appropriate action and expose it on a reachable record route.',
        );
      }
    }
  }
  final pageRoutes = _rawPageRoutes(rejected, collections, views, actions);
  if (diagnostics.isNotEmpty || pageRoutes.isNotEmpty) {
    diagnostics.add(
      'Recompute requires from every capability used by the complete corrected '
      'definition, including actions, behaviors, navigation and configured views.',
    );
  }
  return {
    if (diagnostics.isNotEmpty) 'rawDiagnostics': diagnostics,
    if (pageRoutes.isNotEmpty) 'rawPageRoutes': pageRoutes,
  };
}

List<Map<String, dynamic>> _rawPageRoutes(
  Map<String, dynamic> rejected,
  List<Map> collections,
  List<Map> views,
  List<ActionSpec> actions,
) {
  NavigationSpec navigation;
  try {
    navigation = NavigationSpec.fromJson(
      Map<String, dynamic>.from(rejected['navigation'] as Map),
    );
  } on SpecException {
    return [];
  } on TypeError {
    return [];
  }
  final byId = {for (final view in views) view['id'] as String: view};
  if (navigation.pages.any(
    (page) => page.viewIds.any((id) => !byId.containsKey(id)),
  )) {
    return [];
  }
  final visible = {
    navigation.entryPageId,
    ...navigation.tabs.map((tab) => tab.pageId),
  };
  final result = <Map<String, dynamic>>[];
  for (final collection in collections) {
    final collectionId = collection['id'] as String;
    final own = views
        .where((view) => view['collectionId'] == collectionId)
        .toList();
    final sources = own
        .where((view) => _routeRecordTypes.contains(view['type']))
        .where(
          (view) => navigation.pages.any(
            (page) =>
                visible.contains(page.id) && page.viewIds.contains(view['id']),
          ),
        )
        .toList();
    final forms = own.where((view) => view['type'] == 'form').toList();
    final details = own.where((view) => view['type'] == 'details').toList();
    if (sources.isEmpty || forms.length != 1 || details.length > 1) continue;
    PageSpec? pageFor(Map view) => navigation.pages
        .where((page) => page.viewIds.contains(view['id']))
        .singleOrNull;
    PageSpec? dedicated(Map view) {
      final page = pageFor(view);
      return page != null &&
              page.viewIds.length == 1 &&
              !visible.contains(page.id)
          ? page
          : null;
    }

    final formPage = dedicated(forms.single);
    final detailPage = details.isEmpty ? null : dedicated(details.single);
    if (formPage == null ||
        (details.isNotEmpty && detailPage == null) ||
        sources.any((source) => pageFor(source) == null)) {
      continue;
    }
    final ownActions = {
      for (final action in actions.where(
        (action) => action.collectionId == collectionId,
      ))
        action.id: action,
    };
    // Existing authored destinations and references must agree. A conflicting
    // editor, cross-collection action or unknown route is ordinary AI repair.
    if (own.any((view) {
      final actionIds = view['actionIds'] ?? [];
      return actionIds is! List ||
          actionIds.length > Limits.actions ||
          actionIds.any((id) => !_id(id) || !ownActions.containsKey(id)) ||
          (view['formPageId'] != null && view['formPageId'] != formPage.id) ||
          (view['detailPageId'] != null &&
              view['detailPageId'] != detailPage?.id);
    })) {
      continue;
    }
    final unreachableDetails =
        detailPage != null &&
        !sources.any((source) => source['detailPageId'] == detailPage.id);
    for (final source in sources) {
      final page = pageFor(source)!;
      final primary = page.primaryActionId;
      if (primary != null && !ownActions.containsKey(primary)) continue;
      final actionable =
          primary != null || _ids(source['actionIds']).isNotEmpty;
      final missingForm = actionable && source['formPageId'] == null;
      if (!missingForm && !unreachableDetails) continue;
      result.add({
        'viewId': source['id'],
        'type': source['type'],
        'collectionId': collectionId,
        if (detailPage != null) 'detailPageId': detailPage.id,
        if (actionable) 'formPageId': formPage.id,
      });
    }
    if (details.isNotEmpty &&
        _ids(details.single['actionIds']).isNotEmpty &&
        details.single['formPageId'] == null) {
      result.add({
        'viewId': details.single['id'],
        'type': 'details',
        'collectionId': collectionId,
        'formPageId': formPage.id,
      });
    }
  }
  return result;
}

List<Map>? _strictIdentifiedMaps(Object? value, int limit) {
  if (value is! List ||
      value.length > limit ||
      value.any((entry) => entry is! Map || !_id(entry['id']))) {
    return null;
  }
  final entries = value.cast<Map>();
  return entries.map((entry) => entry['id']).toSet().length == entries.length
      ? entries
      : null;
}

/// Type-correct references already declared by a rejected creation response.
/// Include only views with a concrete incompatible typed binding, so an
/// unrelated retry does not pin otherwise freely authored identities.
List<Map<String, dynamic>> creationFieldBindings(
  Map<String, dynamic> rejected,
) {
  if (rejected['formatVersion'] != 1 || !_boundedCandidate(rejected)) return [];
  final collections = _uniqueMaps(rejected['collections'], Limits.collections);
  final views = _uniqueMaps(rejected['views'], Limits.views);
  final result = <Map<String, dynamic>>[];
  for (final collection in collections) {
    final rawFields = collection['fields'];
    if (rawFields is! List ||
        rawFields.length > Limits.fields ||
        rawFields.any((field) => field is! Map)) {
      continue;
    }
    final fields = <FieldSpec>[];
    try {
      for (final field in rawFields.cast<Map>()) {
        fields.add(FieldSpec.fromJson(Map<String, dynamic>.from(field)));
      }
    } on SpecException {
      continue;
    }
    if (fields.isEmpty ||
        fields.map((field) => field.id).toSet().length != fields.length) {
      continue;
    }
    List<String> ids(Set<FieldType> types) => fields
        .where((field) => types.contains(field.type))
        .map((field) => field.id)
        .toList();
    final choice = ids({FieldType.choice}),
        numeric = ids({FieldType.integer, FieldType.number}),
        timestamp = ids({FieldType.timestamp}),
        text = ids({FieldType.text});
    final invalid = <String>[];
    for (final view in views.where(
      (view) => view['collectionId'] == collection['id'],
    )) {
      final filters = view['filterFieldIds'];
      final options = view['options'];
      final metric = options is Map ? options['metric'] : null;
      final dateFilter = view['dateFilter'];
      final badFilters =
          filters is List &&
          filters.length <= Limits.filters &&
          filters.any((id) => !choice.contains(id));
      final badMetric =
          options is Map &&
          ((metric == 'count' && options.containsKey('valueFieldId')) ||
              ({'sum', 'average'}.contains(metric) &&
                  !numeric.contains(options['valueFieldId'])));
      final badDate =
          options is Map &&
          options.containsKey('dateFieldId') &&
          !timestamp.contains(options['dateFieldId']);
      final badTitle =
          view.containsKey('titleFieldId') &&
          {'list', 'table'}.contains(view['type']) &&
          !text.contains(view['titleFieldId']);
      final badGroup =
          view.containsKey('groupByFieldId') &&
          !choice.contains(view['groupByFieldId']);
      final badDateFilter =
          dateFilter is Map && !timestamp.contains(dateFilter['fieldId']);
      if (badFilters ||
          badMetric ||
          badDate ||
          badTitle ||
          badGroup ||
          badDateFilter) {
        invalid.add(view['id'] as String);
      }
    }
    if (invalid.isNotEmpty) {
      result.add({
        'collectionId': collection['id'],
        'choiceFieldIds': choice,
        'numericFieldIds': numeric,
        'timestampFieldIds': timestamp,
        'textFieldIds': text,
        'viewIds': invalid,
      });
    }
  }
  return result;
}

/// A repeated identical declaration has one unambiguous existing identity.
/// Distinct labels/capabilities/behavior bindings with the same ID require the
/// AI to author its own resolution and never receive a guessed replacement ID.
List<Map<String, dynamic>> creationDuplicateActionDeclarations(
  Map<String, dynamic> rejected, {
  String request = '',
}) {
  if (rejected['formatVersion'] != 1 ||
      !_boundedCandidate(rejected) ||
      request.length > 16384 ||
      _negativeRouteInstruction(request)) {
    return [];
  }
  final rawActions = rejected['actions'];
  if (rawActions is! List ||
      rawActions.isEmpty ||
      rawActions.length > Limits.actions ||
      rawActions.any((action) => action is! Map)) {
    return [];
  }
  final collections = <String, CollectionSpec>{};
  try {
    for (final raw in _uniqueMaps(
      rejected['collections'],
      Limits.collections,
    )) {
      final collection = CollectionSpec.fromJson(
        Map<String, dynamic>.from(raw),
      );
      collections[collection.id] = collection;
    }
  } on SpecException {
    return [];
  }
  final unique = <String, ActionSpec>{};
  var duplicate = false;
  try {
    for (final raw in rawActions.cast<Map>()) {
      final action = ActionSpec.fromJson(Map<String, dynamic>.from(raw));
      final collection = collections[action.collectionId];
      if (collection == null) return [];
      if (action.capability.startsWith('records.')) {
        if (action.behaviorId != null) return [];
      } else {
        final behavior = collection.behaviors
            .where((behavior) => behavior.id == action.behaviorId)
            .singleOrNull;
        final expectedType = action.capability.startsWith('workflow.')
            ? 'workflow.v1'
            : action.capability.startsWith('assignment.')
            ? 'assignment.v1'
            : 'capacity.v1';
        if (behavior?.type != expectedType) return [];
      }
      final previous = unique[action.id];
      if (previous != null) {
        if (canonicalJson(previous.toJson()) !=
            canonicalJson(action.toJson())) {
          return [];
        }
        duplicate = true;
      } else {
        unique[action.id] = action;
      }
    }
  } on SpecException {
    return [];
  }
  return !duplicate
      ? []
      : [
          for (final action in unique.values)
            {
              'id': action.id,
              'collectionId': action.collectionId,
              'capability': action.capability,
              'behaviorId': ?action.behaviorId,
            },
        ];
}

const _routeRecordTypes = {
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

/// Existing identities for retry grammar, never a repaired definition. Resolve
/// only one visible source and dedicated destination pages for each collection.
/// An ambiguous graph remains ordinary AI repair under the strict quality gate.
List<Map<String, dynamic>> creationRecordRouteBindings(
  Map<String, dynamic> rejected, {
  String request = '',
}) {
  if (rejected['formatVersion'] != 1 ||
      !_boundedCandidate(rejected) ||
      request.length > 16384 ||
      _negativeRouteInstruction(request)) {
    return [];
  }
  AppSpec spec;
  try {
    spec = AppSpec.parse(jsonEncode(rejected));
  } on SpecException {
    return [];
  }
  final navigation = spec.navigation;
  if (navigation == null) return [];
  final visiblePages = {
    navigation.entryPageId,
    ...navigation.tabs.map((tab) => tab.pageId),
  };
  final visibleIds = navigation.pages
      .where((page) => visiblePages.contains(page.id))
      .expand((page) => page.viewIds)
      .toSet();
  final entryIds = spec.page(navigation.entryPageId).viewIds.toSet();
  final result = <Map<String, dynamic>>[];
  for (final collection in spec.collections) {
    final actions = spec.actions
        .where((action) => action.collectionId == collection.id)
        .toList();
    final creates = actions
        .where((action) => action.capability == 'records.create.v1')
        .toList();
    final patches = actions
        .where((action) => action.capability == 'records.patch.v1')
        .toList();
    if (creates.length != 1 || patches.length != 1) continue;
    final ownViews = spec.views
        .where((view) => view.collectionId == collection.id)
        .toList();
    final sources = ownViews
        .where(
          (view) =>
              visibleIds.contains(view.id) &&
              _routeRecordTypes.contains(view.type),
        )
        .toList();
    ViewSpec? chooseSource(List<ViewSpec> candidates) {
      final lists = candidates.where((view) => view.type == 'list').toList();
      return lists.isNotEmpty ? lists.singleOrNull : candidates.singleOrNull;
    }

    final entrySources = sources
        .where((view) => entryIds.contains(view.id))
        .toList();
    final source = chooseSource(
      entrySources.isNotEmpty ? entrySources : sources,
    );
    if (source == null ||
        navigation.pages
                .where((page) => page.viewIds.contains(source.id))
                .length !=
            1) {
      continue;
    }
    final sourcePage = navigation.pages.singleWhere(
      (page) => page.viewIds.contains(source.id),
    );
    if (sourcePage.primaryActionId != null &&
        sourcePage.primaryActionId != creates.single.id) {
      // A different page-level add control suppresses section add controls.
      // Resolving that layout needs newly authored routes, not ID pinning.
      continue;
    }
    final ownForms = ownViews
        .where(
          (view) =>
              view.type == 'form' &&
              view.actionIds.contains(creates.single.id) &&
              view.actionIds.contains(patches.single.id),
        )
        .toList();
    PageSpec? dedicatedPage(ViewSpec view) {
      final pages = navigation.pages
          .where((page) => page.viewIds.contains(view.id))
          .toList();
      final page = pages.singleOrNull;
      return page != null &&
              page.viewIds.length == 1 &&
              !visiblePages.contains(page.id)
          ? page
          : null;
    }

    final forms = ownForms
        .where((view) => dedicatedPage(view) != null)
        .toList();
    ViewSpec? linkedView(List<ViewSpec> candidates, String? pageId) =>
        candidates
            .where((view) => dedicatedPage(view)?.id == pageId)
            .singleOrNull ??
        candidates.singleOrNull;
    final form = linkedView(forms, source.formPageId);
    if (form == null) continue;
    final formPage = dedicatedPage(form)!;
    final details = ownViews
        .where((view) => view.type == 'details' && dedicatedPage(view) != null)
        .toList();
    final detail = linkedView(details, source.detailPageId);
    // With multiple orphaned details pages the platform cannot choose which
    // one the user meant, nor satisfy the gate without newly authored routes.
    if (details.length > 1 || (details.isNotEmpty && detail == null)) continue;
    final detailPage = detail == null ? null : dedicatedPage(detail);
    // A valid alternative editor on details is an authored choice. Do not
    // override it merely to force one shared editor during route repair.
    if (detail?.formPageId != null && detail!.formPageId != formPage.id) {
      continue;
    }
    final reachable = <ViewSpec>[
      ...sources,
      for (final visible in sources)
        if (visible.detailPageId != null)
          ...spec
              .page(visible.detailPageId!)
              .viewIds
              .map(spec.view)
              .where((view) => view.type == 'details'),
    ];
    final missingDetail =
        detailPage != null &&
        !sources.any((view) => view.detailPageId == detailPage.id);
    final missingEdit = !reachable.any(
      (view) => view.actionIds.contains(patches.single.id),
    );
    final missingCreate = !sources.any((view) {
      return navigation.pages
          .where(
            (page) =>
                visiblePages.contains(page.id) &&
                page.viewIds.contains(view.id),
          )
          .any(
            (page) =>
                page.primaryActionId == creates.single.id ||
                (page.primaryActionId == null &&
                    view.actionIds.contains(creates.single.id)),
          );
    });
    final behaviors = actions
        .where((action) => !action.capability.startsWith('records.'))
        .toList();
    final missingBehavior = behaviors.any(
      (action) => !reachable.any((view) => view.actionIds.contains(action.id)),
    );
    if (!missingDetail && !missingEdit && !missingBehavior && !missingCreate) {
      continue;
    }
    final requiredActions = actions.map((action) => action.id).toList();
    Map<String, dynamic> bind(
      ViewSpec view, {
      String? detailsPageId,
      String? formPageId,
      required List<String> include,
    }) => {
      'viewId': view.id,
      'type': view.type,
      'collectionId': collection.id,
      'detailPageId': ?detailsPageId,
      'formPageId': ?formPageId,
      'requiredActionIds': {...view.actionIds, ...include}.toList(),
    };
    result.add(
      bind(
        source,
        detailsPageId: detailPage?.id,
        formPageId: formPage.id,
        include: requiredActions,
      ),
    );
    if (detail != null) {
      result.add(
        bind(
          detail,
          formPageId: formPage.id,
          include: [patches.single.id, ...behaviors.map((action) => action.id)],
        ),
      );
    }
    result.add(bind(form, include: [creates.single.id, patches.single.id]));
  }
  return result;
}

bool _negativeRouteInstruction(String request) => RegExp(
  r"\b(?:do not|don't|without|avoid|no|never)\b[^.;\n]{0,100}\b(?:edit(?:ing)?|details?|forms?|links?|routes?|pages?)\b",
  caseSensitive: false,
).hasMatch(request);

bool _id(Object? value) =>
    value is String &&
    value.length <= 64 &&
    RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(value);
List<Map> _maps(Object? value, int limit) =>
    value is List && value.length <= limit
    ? value.whereType<Map>().toList()
    : [];
List<Map> _uniqueMaps(Object? value, int limit) {
  final entries = _maps(
    value,
    limit,
  ).where((entry) => _id(entry['id'])).toList();
  final counts = <String, int>{};
  for (final entry in entries) {
    final id = entry['id'] as String;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  return entries.where((entry) => counts[entry['id']] == 1).toList();
}

bool _boundedCandidate(Map<String, dynamic> candidate) {
  final pending = <(Object?, int)>[(candidate, 0)];
  final seen = HashSet<Object>.identity();
  var nodes = 0, bytes = 0;
  while (pending.isNotEmpty) {
    final (value, depth) = pending.removeLast();
    if (++nodes > 32768 || depth > Limits.depth) return false;
    if (value is String) {
      if (value.length > Limits.definitionBytes) return false;
      bytes += utf8.encode(value).length;
    } else if (value is Map) {
      if (!seen.add(value) || value.length > 4096) return false;
      for (final entry in value.entries) {
        if (entry.key is! String) return false;
        pending.add((entry.key, depth + 1));
        pending.add((entry.value, depth + 1));
      }
    } else if (value is List) {
      if (!seen.add(value) || value.length > 32768) return false;
      pending.addAll(value.map((item) => (item, depth + 1)));
    } else if (value != null &&
        value is! bool &&
        (value is! num || !value.isFinite)) {
      return false;
    }
    if (bytes > Limits.definitionBytes) return false;
  }
  return utf8.encode(jsonEncode(candidate)).length <= Limits.definitionBytes;
}

List<String> _ids(Object? value) =>
    value is List && value.length <= Limits.fields
    ? value.where(_id).cast<String>().toList()
    : [];
