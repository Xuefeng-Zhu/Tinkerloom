import 'package:appnest_spec/appnest_spec.dart';

/// Generation must produce an app that can be used from its visible pages.
/// These checks supplement schema validation without changing old definitions.
void validateGeneratedExperience(AppSpec spec, {AppSpec? baseline}) {
  final existing = baseline == null ? <String, String>{} : _issues(baseline);
  final added = _issues(spec).entries
      .where((issue) => !existing.containsKey(issue.key));
  if (added.isNotEmpty) {
    throw SpecException(added.map((issue) => issue.value).join(' '));
  }
}

const _recordViewTypes = {
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

/// Forms reached by actual record create/edit controls, rather than forms that
/// merely exist on an orphaned page. This mirrors the renderer's main record
/// views and their single-hop details/form routes; aggregates are not routes.
List<ViewSpec> reachableGeneratedRecordForms(
  AppSpec spec,
  String collectionId, {
  bool creationOnly = false,
}) {
  final navigation = spec.navigation;
  if (navigation == null) return const [];
  final mainViews = {
    navigation.entryPageId,
    ...navigation.tabs.map((tab) => tab.pageId),
  }.expand((id) => spec.page(id).viewIds.map(spec.view));
  final sources = mainViews
      .where(
        (view) =>
            view.collectionId == collectionId &&
            _recordViewTypes.contains(view.type),
      )
      .toList();
  final routes = [
    ...sources,
    for (final view in sources)
      if (view.detailPageId != null)
        ...spec
            .page(view.detailPageId!)
            .viewIds
            .map(spec.view)
            .where(
              (detail) =>
                  detail.type == 'details' &&
                  detail.collectionId == collectionId,
            ),
  ];
  final forms = <String, ViewSpec>{};
  // Add controls belong to visible record sources, not a details-only edit
  // route whose shared form also happens to declare a create action.
  for (final route in creationOnly ? sources : routes) {
    if (route.formPageId == null) continue;
    final capabilities = route.actionIds
        .map(spec.action)
        .where(
          (action) =>
              {
                'records.create.v1',
                'records.patch.v1',
              }.contains(action.capability) &&
              (!creationOnly || action.capability == 'records.create.v1'),
        )
        .map((action) => action.capability)
        .toSet();
    if (capabilities.isEmpty) continue;
    for (final form in spec.page(route.formPageId!).viewIds.map(spec.view)) {
      if (form.type == 'form' &&
          form.collectionId == collectionId &&
          form.actionIds
              .map(spec.action)
              .any(
                (action) => capabilities.contains(action.capability),
              )) {
        forms[form.id] = form;
      }
    }
  }
  return forms.values.toList();
}

Map<String, String> _issues(AppSpec spec) {
  final issues = <String, String>{};
  final navigation = spec.navigation;
  final mainPages = navigation == null
      ? <PageSpec>[]
      : {
          navigation.entryPageId,
          ...navigation.tabs.map((tab) => tab.pageId),
        }.map(spec.page).toList();
  final mainViews = navigation == null
      ? spec.views
      : mainPages.expand((page) => page.viewIds.map(spec.view)).toList();
  if (spec.collections.isEmpty &&
      spec.views.any(
        (view) => {
          'clock',
          'timer',
          'deviceInfo',
          'deviceControl',
        }.contains(view.type),
      ) &&
      !mainViews.any(
        (view) => {
          'clock',
          'timer',
          'deviceInfo',
          'deviceControl',
        }.contains(view.type),
      )) {
    issues['utility:unreachable'] = 'A utility app needs a clock, timer or device component on its entry page or tabs.';
  }
  for (final collection in spec.collections) {
    final actions = spec.actions
        .where((action) => action.collectionId == collection.id)
        .toList();
    final editable = actions.any(
      (action) => {
        'records.create.v1',
        'records.patch.v1',
      }.contains(action.capability),
    );
    if (editable) {
      for (final capability in ['records.create.v1', 'records.patch.v1']) {
        if (!actions.any((action) => action.capability == capability)) {
          issues['${collection.id}:missing:$capability'] =
              '${collection.label} needs both create and edit actions to be usable.';
        }
      }
    }
    bool exposes(ViewSpec view, String capability) =>
        view.collectionId == collection.id &&
        view.actionIds.any((id) => spec.action(id).capability == capability);
    final canCreate = navigation == null
        ? mainViews.any((view) => exposes(view, 'records.create.v1'))
        : mainPages.any((page) {
            final id = page.primaryActionId;
            if (id == null) {
              // Renderer sections expose their own create buttons when there
              // is no page-level primary action.
              return page.viewIds
                  .map(spec.view)
                  .any(
                    (view) =>
                        view.type != 'details' &&
                        view.type != 'form' &&
                        exposes(view, 'records.create.v1'),
                  );
            }
            final action = spec.action(id);
            return action.collectionId == collection.id &&
                action.capability == 'records.create.v1' &&
                page.viewIds
                    .map(spec.view)
                    .any(
                      (view) => view.type != 'details' && view.type != 'form',
                    );
          });
    final recordViews = [
      ...mainViews.where((view) => _recordViewTypes.contains(view.type)),
      for (final view in mainViews.where(
        (view) => _recordViewTypes.contains(view.type),
      ))
        if (view.detailPageId != null)
          ...spec
              .page(view.detailPageId!)
              .viewIds
              .map(spec.view)
              .where(
                (destination) => destination.type == 'details',
              ),
    ];
    if (navigation != null) {
      final sources = mainViews
          .where(
            (view) =>
                view.collectionId == collection.id &&
                _recordViewTypes.contains(view.type),
          )
          .toList();
      final source = _unambiguousSource(spec, sources);
      for (final page in navigation.pages.where(
        (page) => page.viewIds.any(
          (id) =>
              spec.view(id).type == 'details' &&
              spec.view(id).collectionId == collection.id,
        ),
      )) {
        if (!sources.any((view) => view.detailPageId == page.id)) {
          issues['${collection.id}:unreachable:details:${page.id}'] =
              'The dedicated details page "${page.id}" is unreachable. '
              '${source == null ? 'A visible same-collection record view' : 'Visible view "${source.id}"'} '
              'must set view.detailPageId:"${page.id}". Preserve its actions and formPageId.';
        }
      }
      for (final action in actions.where(
        (action) => {
          'workflow.transition.v1',
          'assignment.assign.v1',
          'capacity.configure.v1',
          'capacity.claim.v1',
          'capacity.release.v1',
        }.contains(action.capability),
      )) {
        if (!recordViews.any(
          (view) =>
              view.collectionId == collection.id &&
              view.actionIds.contains(action.id),
        )) {
          issues['${collection.id}:unreachable:action:${action.id}'] =
              'Action "${action.id}" (${action.capability}) has no visible record route. '
              'Include it in actionIds on ${source == null ? 'a visible same-collection record view' : 'visible view "${source.id}"'} '
              'or a details view reached through source.detailPageId. A hidden details page does not expose the action.';
        }
      }
    }
    if (editable && !canCreate) {
      issues['${collection.id}:unreachable:create'] =
          '${collection.label} needs a reachable add control on the entry page or a tab.';
    }
    if (editable &&
        !recordViews.any((view) => exposes(view, 'records.patch.v1'))) {
      issues['${collection.id}:unreachable:edit'] =
          '${collection.label} needs a reachable edit control on a record view '
          'or linked details page, with a matching form. '
          '${_editRouteHint(spec, collection, mainViews)}';
    }
  }
  return issues;
}

/// Repair the graph using the response's own stable IDs. Generic "make editing
/// reachable" errors leave a model guessing which otherwise valid page/view
/// bindings are missing; these hints never mutate the candidate or add IDs.
String _editRouteHint(
  AppSpec spec,
  CollectionSpec collection,
  List<ViewSpec> mainViews,
) {
  final edit = spec.actions
      .where(
        (action) =>
            action.collectionId == collection.id &&
            action.capability == 'records.patch.v1',
      )
      .singleOrNull;
  final sources = mainViews
      .where(
        (view) =>
            view.collectionId == collection.id &&
            _recordViewTypes.contains(view.type),
      )
      .toList();
  final source = _unambiguousSource(spec, sources);
  if (edit == null || source == null) return '';
  final forms = spec.views
      .where(
        (view) =>
            view.collectionId == collection.id &&
            view.type == 'form' &&
            view.actionIds.contains(edit.id),
      )
      .map((view) => view.id)
      .toSet();
  final formPages =
      spec.navigation?.pages
          .where((page) => page.viewIds.any(forms.contains))
          .toList() ??
      <PageSpec>[];
  final formPage =
      formPages.where((page) => page.id == source.formPageId).singleOrNull ??
      formPages.singleOrNull;
  final form = formPage == null ? '' : ' and formPageId:"${formPage.id}"';
  return 'On visible view "${source.id}", include edit action "${edit.id}" in actionIds$form. '
      'A form elsewhere does not expose editing. If routing through details instead, '
      'source.detailPageId must reference the dedicated details page, whose view exposes '
      'the same edit action and formPageId. Preserve the existing create action and other bindings.';
}

ViewSpec? _unambiguousSource(AppSpec spec, Iterable<ViewSpec> sources) {
  final unique = {for (final view in sources) view.id: view}.values.toList();
  final entryIds = spec.navigation == null
      ? <String>{}
      : spec.page(spec.navigation!.entryPageId).viewIds.toSet();
  final entry = unique.where((view) => entryIds.contains(view.id)).toList();
  final candidates = entry.isEmpty ? unique : entry;
  final lists = candidates.where((view) => view.type == 'list').toList();
  return lists.isEmpty ? candidates.singleOrNull : lists.singleOrNull;
}
