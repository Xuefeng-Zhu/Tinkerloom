part of '../appnest_spec.dart';

enum FieldType {
  text,
  integer,
  number,
  boolean,
  choice,
  timestamp,
  member,
  image,
}

class FieldSpec {
  final String id, label;
  final FieldType type;
  final bool required;
  final List<String> choices;
  FieldSpec(this.id, this.label, this.type, this.required, this.choices);
  factory FieldSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'id', 'label', 'type', 'required', 'choices'}, 'field');
    final id = stableId(j['id']);
    final type = FieldType.values.where((t) => t.name == j['type']).firstOrNull;
    if (type == null) throw const SpecException('Unsupported field type');
    if (j['required'] is! bool)
      throw const SpecException('Field required must be boolean');
    final choices = array(
      j['choices'] ?? [],
      'choices',
      30,
    ).map((c) => str(c, 'choice', max: 80)).toList();
    unique(choices, 'choices');
    if (type == FieldType.choice && choices.isEmpty) {
      throw SpecException('Choice field $id requires at least one choice.');
    }
    if (type != FieldType.choice && choices.isNotEmpty) {
      throw SpecException(
        'Field $id has type ${type.name}; only choice fields can define nonempty choices.',
      );
    }
    return FieldSpec(
      id,
      str(j['label'], 'label'),
      type,
      j['required'],
      choices,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.name,
    'required': required,
    if (choices.isNotEmpty) 'choices': choices,
  };
  Object? normalize(Object? value) {
    if (value == null) {
      if (required) throw SpecException('$label is required');
      return null;
    }
    switch (type) {
      case FieldType.text:
        if (value is! String ||
            value.length > 10000 ||
            (required && value.trim().isEmpty))
          throw SpecException('$label must be text');
      case FieldType.integer:
        if (value is! int || value.abs() > 9007199254740991)
          throw SpecException('$label must be a safe integer');
      case FieldType.number:
        if (value is! num || !value.isFinite || value.abs() > 1e15)
          throw SpecException('$label must be a finite number');
      case FieldType.boolean:
        if (value is! bool) throw SpecException('$label must be true or false');
      case FieldType.choice:
        if (value is! String || !choices.contains(value))
          throw SpecException('$label has an unsupported choice');
      case FieldType.timestamp:
        if (value is! String || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value))
          throw SpecException('$label needs a timestamp with timezone');
        final date = DateTime.tryParse(value);
        if (date == null)
          throw SpecException('$label must be a valid timestamp');
        return date.toUtc().toIso8601String();
      case FieldType.image:
        _imageId(value);
      case FieldType.member:
        if (value is! String || value.isEmpty || value.length > 100)
          throw SpecException('$label must reference an eligible member');
    }
    return value;
  }
}

class BehaviorSpec {
  final String id, type;
  final String? fieldId;
  final Map<String, List<String>> transitions;
  BehaviorSpec(this.id, this.type, this.fieldId, this.transitions);
  factory BehaviorSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'id', 'type', 'fieldId', 'transitions'}, 'behavior');
    final type = str(j['type'], 'behavior type');
    if (!{'capacity.v1', 'workflow.v1', 'assignment.v1'}.contains(type))
      throw const SpecException('Unsupported behavior');
    final transitions = <String, List<String>>{};
    if (j['transitions'] != null) {
      final map = object(j['transitions'], 'transitions');
      if (map.length > 30) throw const SpecException('Too many transitions');
      for (final e in map.entries) {
        transitions[e.key] = array(
          e.value,
          'transition targets',
          30,
        ).map((x) => str(x, 'target')).toList();
      }
    }
    if (type == 'capacity.v1' &&
        (j['fieldId'] != null || transitions.isNotEmpty))
      throw const SpecException('Capacity is typed state, not a payload field');
    return BehaviorSpec(
      stableId(j['id']),
      type,
      j['fieldId'] == null ? null : stableId(j['fieldId']),
      transitions,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    if (fieldId != null) 'fieldId': fieldId,
    if (transitions.isNotEmpty) 'transitions': transitions,
  };
}

class CollectionSpec {
  final String id, label;
  final List<FieldSpec> fields;
  final List<BehaviorSpec> behaviors;
  CollectionSpec(this.id, this.label, this.fields, this.behaviors);
  factory CollectionSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'id', 'label', 'fields', 'behaviors'}, 'collection');
    final f = array(
      j['fields'],
      'fields',
      Limits.fields,
    ).map((v) => FieldSpec.fromJson(object(v, 'field'))).toList();
    if (f.isEmpty) throw const SpecException('A collection needs fields');
    final b = array(
      j['behaviors'] ?? [],
      'behaviors',
      8,
    ).map((v) => BehaviorSpec.fromJson(object(v, 'behavior'))).toList();
    unique(f.map((v) => v.id), 'fields');
    unique(b.map((v) => v.id), 'behaviors');
    if (b.where((v) => v.type == 'capacity.v1').length > 1)
      throw const SpecException(
        'Only one capacity pool per collection is supported by this renderer.',
      );
    final result = CollectionSpec(
      stableId(j['id']),
      str(j['label'], 'collection label'),
      f,
      b,
    );
    for (final behavior in b) {
      if (behavior.type == 'capacity.v1') continue;
      final field = result.field(behavior.fieldId ?? '');
      if (behavior.type == 'assignment.v1' && field.type != FieldType.member)
        throw const SpecException('Assignment needs a member field');
      if (behavior.type == 'workflow.v1') {
        if (field.type != FieldType.choice || behavior.transitions.isEmpty)
          throw const SpecException(
            'Workflow needs a choice field and transitions',
          );
        for (final e in behavior.transitions.entries) {
          if (!field.choices.contains(e.key) ||
              e.value.any((x) => !field.choices.contains(x)))
            throw const SpecException('Unknown transition status');
        }
      }
    }
    return result;
  }
  FieldSpec field(String id) =>
      fields.where((f) => f.id == id).firstOrNull ??
      (throw SpecException('Unknown field $id'));
  BehaviorSpec behavior(String id) =>
      behaviors.where((b) => b.id == id).firstOrNull ??
      (throw SpecException('Unknown behavior $id'));
  Map<String, dynamic> normalizeRecord(Map<String, dynamic> data) {
    keys(data, fields.map((x) => x.id).toSet(), 'record');
    return {
      for (final f in fields)
        if (f.normalize(data[f.id]) != null) f.id: f.normalize(data[f.id]),
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'fields': fields.map((f) => f.toJson()).toList(),
    'behaviors': behaviors.map((b) => b.toJson()).toList(),
  };
}

const navigationIcons = {
  'book',
  'board',
  'people',
  'spark',
  'check',
  'today',
  'list',
  'chart',
};

class DateFilterSpec {
  final String fieldId, period;
  const DateFilterSpec(this.fieldId, this.period);
  factory DateFilterSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'fieldId', 'period'}, 'date filter');
    if (!{'today', 'overdue'}.contains(j['period'])) {
      throw const SpecException('Unsupported relative day period');
    }
    return DateFilterSpec(stableId(j['fieldId']), j['period']);
  }
  Map<String, dynamic> toJson() => {'fieldId': fieldId, 'period': period};
}

class PageSpec {
  final String id, title;
  final List<String> viewIds;
  final bool showDate;
  final String? primaryActionId;
  final String? layout;
  const PageSpec(
    this.id,
    this.title,
    this.viewIds, {
    this.showDate = false,
    this.primaryActionId,
    this.layout,
  });
  factory PageSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {
      'id',
      'title',
      'viewIds',
      'showDate',
      'primaryActionId',
      'layout',
    }, 'page');
    if (j.containsKey('showDate') && j['showDate'] is! bool) {
      throw const SpecException('Page showDate must be boolean');
    }
    if (j.containsKey('layout') && !pageLayouts.contains(j['layout']))
      throw const SpecException('Choose an approved page layout');
    final ids = array(j['viewIds'], 'page views', 8).map(stableId).toList();
    if (ids.isEmpty)
      throw const SpecException('A page needs at least one view');
    unique(ids, 'page views');
    return PageSpec(
      stableId(j['id']),
      str(j['title'], 'page title'),
      ids,
      showDate: j['showDate'] ?? false,
      primaryActionId: j['primaryActionId'] == null
          ? null
          : stableId(j['primaryActionId']),
      layout: j['layout'] as String?,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'viewIds': viewIds,
    if (showDate) 'showDate': true,
    if (primaryActionId != null) 'primaryActionId': primaryActionId,
    if (layout != null) 'layout': layout,
  };
}

class TabSpec {
  final String pageId, label, icon;
  const TabSpec(this.pageId, this.label, this.icon);
  factory TabSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'pageId', 'label', 'icon'}, 'tab');
    if (!navigationIcons.contains(j['icon']))
      throw const SpecException('Choose an approved tab icon');
    return TabSpec(
      stableId(j['pageId']),
      str(j['label'], 'tab label', max: 40),
      j['icon'],
    );
  }
  Map<String, dynamic> toJson() => {
    'pageId': pageId,
    'label': label,
    'icon': icon,
  };
}

class NavigationSpec {
  final String entryPageId;
  final List<PageSpec> pages;
  final List<TabSpec> tabs;
  const NavigationSpec(this.entryPageId, this.pages, this.tabs);
  factory NavigationSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'entryPageId', 'pages', 'tabs'}, 'navigation');
    final pages = array(
      j['pages'],
      'pages',
      16,
    ).map((v) => PageSpec.fromJson(object(v, 'page'))).toList();
    final tabs = array(
      j['tabs'],
      'tabs',
      5,
    ).map((v) => TabSpec.fromJson(object(v, 'tab'))).toList();
    if (pages.isEmpty || tabs.isEmpty)
      throw const SpecException('Navigation needs pages and one to five tabs');
    unique(pages.map((v) => v.id), 'pages');
    unique(tabs.map((v) => v.pageId), 'tabs');
    final entry = stableId(j['entryPageId']);
    if (!tabs.any((tab) => tab.pageId == entry))
      throw const SpecException('Entry page must be a tab');
    final ids = pages.map((v) => v.id).toSet();
    if (tabs.any((t) => !ids.contains(t.pageId)))
      throw const SpecException('Unknown tab page');
    return NavigationSpec(entry, pages, tabs);
  }
  Map<String, dynamic> toJson() => {
    'entryPageId': entryPageId,
    'pages': pages.map((v) => v.toJson()).toList(),
    'tabs': tabs.map((v) => v.toJson()).toList(),
  };
}

class ViewSpec {
  final String id, type, collectionId, label;
  final String? titleFieldId, groupByFieldId;
  final String? presentation, detailPageId, formPageId;
  final List<String> fieldIds, filterFieldIds;
  final Map<String, dynamic>? query;
  final DateFilterSpec? dateFilter;
  final Map<String, dynamic> options;
  bool get contentOnly => const {
    'richText',
    'banner',
    'clock',
    'timer',
    'deviceInfo',
    'deviceControl',
  }.contains(type);
  ClockOptions get clockOptions => ClockOptions.fromJson(options);
  TimerOptions get timerOptions => TimerOptions.fromJson(options);
  bool get configured =>
      options.isNotEmpty ||
      presentation != null ||
      fieldIds.isNotEmpty ||
      filterFieldIds.isNotEmpty ||
      query != null ||
      dateFilter != null ||
      detailPageId != null ||
      formPageId != null;
  final List<String> actionIds;
  ViewSpec(
    this.id,
    this.type,
    this.collectionId,
    this.label,
    this.titleFieldId,
    this.groupByFieldId,
    this.actionIds, {
    this.presentation,
    this.fieldIds = const [],
    this.filterFieldIds = const [],
    this.query,
    this.dateFilter,
    this.detailPageId,
    this.formPageId,
    this.options = const {},
  });
  factory ViewSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {
      'id',
      'type',
      'collectionId',
      'label',
      'titleFieldId',
      'groupByFieldId',
      'actionIds',
      'presentation',
      'fieldIds',
      'filterFieldIds',
      'query',
      'dateFilter',
      'detailPageId',
      'formPageId',
      'options',
    }, 'view');
    if (j['presentation'] != null &&
        !{'compact', 'cards'}.contains(j['presentation']))
      throw const SpecException('Unsupported view presentation');
    final fieldIds = array(
      j['fieldIds'] ?? [],
      'view fields',
      Limits.fields,
    ).map(stableId).toList();
    final filterFieldIds = array(
      j['filterFieldIds'] ?? [],
      'filter fields',
      Limits.filters,
    ).map(stableId).toList();
    unique(fieldIds, 'view fields');
    unique(filterFieldIds, 'filter fields');
    final query = j['query'] == null ? null : object(j['query'], 'view query');
    if (query != null) keys(query, {'filters', 'sort', 'limit'}, 'view query');
    final type = str(j['type'], 'view type');
    if (!{
      'list',
      'form',
      'details',
      'board',
      'summary',
      'capacity',
      'action',
      ...richViewTypes,
    }.contains(type))
      throw const SpecException('Unsupported view');
    final options = j['options'] == null
        ? <String, dynamic>{}
        : object(j['options'], 'view options');
    _validateOptionsShape(type, options);
    final contentOnly = const {
      'richText',
      'banner',
      'clock',
      'timer',
      'deviceInfo',
      'deviceControl',
    }.contains(type);
    if (contentOnly && j.containsKey('collectionId'))
      throw const SpecException('Content blocks must omit collectionId');
    return ViewSpec(
      stableId(j['id']),
      type,
      contentOnly ? '' : stableId(j['collectionId']),
      str(j['label'] ?? j['id'], 'view label'),
      j['titleFieldId'] == null ? null : stableId(j['titleFieldId']),
      j['groupByFieldId'] == null ? null : stableId(j['groupByFieldId']),
      array(j['actionIds'] ?? [], 'view actions', 32).map(stableId).toList(),
      presentation: j['presentation'],
      fieldIds: fieldIds,
      filterFieldIds: filterFieldIds,
      query: query,
      dateFilter: j['dateFilter'] == null
          ? null
          : DateFilterSpec.fromJson(object(j['dateFilter'], 'date filter')),
      detailPageId: j['detailPageId'] == null
          ? null
          : stableId(j['detailPageId']),
      formPageId: j['formPageId'] == null ? null : stableId(j['formPageId']),
      options: Map<String, dynamic>.unmodifiable(options),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    if (!contentOnly) 'collectionId': collectionId,
    'label': label,
    if (options.isNotEmpty) 'options': options,
    if (titleFieldId != null) 'titleFieldId': titleFieldId,
    if (groupByFieldId != null) 'groupByFieldId': groupByFieldId,
    'actionIds': actionIds,
    if (presentation != null) 'presentation': presentation,
    if (fieldIds.isNotEmpty) 'fieldIds': fieldIds,
    if (filterFieldIds.isNotEmpty) 'filterFieldIds': filterFieldIds,
    if (query != null) 'query': query,
    if (dateFilter != null) 'dateFilter': dateFilter!.toJson(),
    if (detailPageId != null) 'detailPageId': detailPageId,
    if (formPageId != null) 'formPageId': formPageId,
  };
}

class ActionSpec {
  final String id, label, capability, collectionId;
  final String? behaviorId;
  ActionSpec(
    this.id,
    this.label,
    this.capability,
    this.collectionId,
    this.behaviorId,
  );
  factory ActionSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {
      'id',
      'label',
      'capability',
      'collectionId',
      'behaviorId',
    }, 'action');
    final capability = str(j['capability'], 'capability');
    if (!actionCapabilities.contains(capability))
      throw SpecException('Unsupported capability $capability');
    return ActionSpec(
      stableId(j['id']),
      str(j['label'], 'action label'),
      capability,
      stableId(j['collectionId']),
      j['behaviorId'] == null ? null : stableId(j['behaviorId']),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'capability': capability,
    'collectionId': collectionId,
    if (behaviorId != null) 'behaviorId': behaviorId,
  };
}

const actionCapabilities = {
  'records.create.v1',
  'records.patch.v1',
  'assignment.assign.v1',
  'workflow.transition.v1',
  'capacity.configure.v1',
  'capacity.claim.v1',
  'capacity.release.v1',
};
const capabilities = {
  'collections.v1',
  'views.list.v1',
  'views.form.v1',
  'views.details.v1',
  'views.board.v1',
  'views.summary.v1',
  'views.capacity.v1',
  'views.action.v1',
  'views.table.v1',
  'views.calendar.v1',
  'views.timeline.v1',
  'views.chart.v1',
  'views.metric.v1',
  'views.imageCards.v1',
  'views.gallery.v1',
  'views.richText.v1',
  'views.banner.v1',
  'views.checklist.v1',
  'views.clock.v1',
  'views.timer.v1',
  'views.deviceInfo.v1',
  'views.deviceControl.v1',
  'fields.image.v1',
  'views.interactive.v1',
  'capacity.v1',
  'workflow.v1',
  'assignment.v1',
  'notifications.inApp.v1',
  'navigation.v1',
  'appearance.v1',
  'navigation.layouts.v1',
  'views.configured.v1',
  'notifications.owner.v1',
  'automations.conditions.v1',
  ...actionCapabilities,
};
const policyPresets = {
  'personalTracker.v1',
  'groupWorkflow.v1',
  'groupCapacitySignup.v1',
};

class RuleCondition {
  final String fieldId, value;
  const RuleCondition(this.fieldId, this.value);
  factory RuleCondition.fromJson(Map<String, dynamic> j) {
    keys(j, {'fieldId', 'value'}, 'condition');
    return RuleCondition(
      stableId(j['fieldId']),
      str(j['value'], 'condition value', max: 80),
    );
  }
  Map<String, dynamic> toJson() => {'fieldId': fieldId, 'value': value};
}

class AutomationSpec {
  final String id, collectionId, fieldId, effect;
  final int offsetSeconds;
  final RuleCondition? condition;
  AutomationSpec(
    this.id,
    this.collectionId,
    this.fieldId,
    this.offsetSeconds,
    this.effect, {
    this.condition,
  });
  factory AutomationSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {'id', 'trigger', 'effect', 'condition'}, 'automation');
    final t = object(j['trigger'], 'trigger'),
        e = object(j['effect'], 'effect');
    keys(t, {'type', 'collectionId', 'fieldId', 'offsetSeconds'}, 'trigger');
    keys(e, {'type', 'channel'}, 'effect');
    if (t['type'] != 'beforeTimestamp' ||
        t['offsetSeconds'] is! int ||
        t['offsetSeconds'] < 0 ||
        t['offsetSeconds'] > 604800)
      throw const SpecException(
        'Only bounded one-time reminders are supported',
      );
    if (e['channel'] != 'inApp' ||
        !{
          'notifyActiveClaimants',
          'notifyAssignee',
          'notifyOwner',
        }.contains(e['type']))
      throw const SpecException('Only approved in-app effects are supported');
    return AutomationSpec(
      stableId(j['id']),
      stableId(t['collectionId']),
      stableId(t['fieldId']),
      t['offsetSeconds'],
      e['type'],
      condition: j['condition'] == null
          ? null
          : RuleCondition.fromJson(object(j['condition'], 'condition')),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'trigger': {
      'type': 'beforeTimestamp',
      'collectionId': collectionId,
      'fieldId': fieldId,
      'offsetSeconds': offsetSeconds,
    },
    'effect': {'type': effect, 'channel': 'inApp'},
    if (condition != null) 'condition': condition!.toJson(),
  };
}

class AppSpec {
  final String name, theme, icon, policyPresetRequest;
  final List<String> requires;
  final List<CollectionSpec> collections;
  final List<ViewSpec> views;
  final List<ActionSpec> actions;
  final List<AutomationSpec> automationRequests;
  final NavigationSpec? navigation;
  final AppearanceSpec? appearance;
  AppSpec._(
    this.name,
    this.theme,
    this.icon,
    this.policyPresetRequest,
    this.requires,
    this.collections,
    this.views,
    this.actions,
    this.automationRequests,
    this.navigation,
    this.appearance,
  );
  factory AppSpec.parse(String source) {
    if (utf8.encode(source).length > Limits.definitionBytes)
      throw const SpecException('Definition is too large');
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const SpecException('Definition must be valid JSON');
    }
    void depth(Object? x, int d) {
      if (d > Limits.depth)
        throw const SpecException('Definition is too deeply nested');
      if (x is Map)
        for (final v in x.values) {
          depth(v, d + 1);
        }
      if (x is List)
        for (final v in x) {
          depth(v, d + 1);
        }
    }

    depth(decoded, 0);
    final j = object(decoded, 'AppSpec');
    keys(j, {
      'formatVersion',
      'name',
      'theme',
      'icon',
      'requires',
      'collections',
      'views',
      'actions',
      'policyPresetRequest',
      'automationRequests',
      'navigation',
      'appearance',
    }, 'AppSpec');
    if (j['formatVersion'] is! int || j['formatVersion'] != 1)
      throw const SpecException('Unsupported AppSpec format version');
    final theme = str(j['theme'], 'theme'),
        icon = str(j['icon'], 'icon'),
        policy = str(j['policyPresetRequest'], 'policy');
    if (!{'teal', 'amber', 'blue', 'rose', 'sage'}.contains(theme) ||
        !{'book', 'board', 'people', 'spark', 'check'}.contains(icon))
      throw const SpecException('Choose an approved theme and icon');
    if (!policyPresets.contains(policy))
      throw const SpecException('Unsupported policy request');
    final requires = array(
      j['requires'],
      'requires',
      40,
    ).map((v) => str(v, 'capability')).toList();
    final unsupported = requires
        .where((value) => !capabilities.contains(value))
        .toSet();
    if (unsupported.isNotEmpty) {
      final names = unsupported
          .take(5)
          .map((name) {
            final quoted = jsonEncode(name);
            return quoted.length <= 120
                ? quoted
                : '${quoted.substring(0, 116)}..."';
          })
          .join(', ');
      final remaining = unsupported.length > 5
          ? ' (and ${unsupported.length - 5} more)'
          : '';
      final policyHint = unsupported.any(policyPresets.contains)
          ? ' Policy presets belong in policyPresetRequest, not requires.'
          : '';
      throw SpecException(
        'Unsupported required capabilities: $names$remaining. '
        'Use only capability names listed in the AppSpec schema requires enum.$policyHint',
      );
    }
    final c = array(
      j['collections'],
      'collections',
      Limits.collections,
    ).map((v) => CollectionSpec.fromJson(object(v, 'collection'))).toList();
    final v = array(
      j['views'],
      'views',
      Limits.views,
    ).map((v) => ViewSpec.fromJson(object(v, 'view'))).toList();
    final a = array(
      j['actions'],
      'actions',
      Limits.actions,
    ).map((v) => ActionSpec.fromJson(object(v, 'action'))).toList();
    final r = array(
      j['automationRequests'],
      'automationRequests',
      Limits.rules,
    ).map((v) => AutomationSpec.fromJson(object(v, 'rule'))).toList();
    if (v.isEmpty) throw const SpecException('An app needs at least one view');
    unique(c.map((x) => x.id), 'collections');
    unique(v.map((x) => x.id), 'views');
    unique(a.map((x) => x.id), 'actions');
    unique(r.map((x) => x.id), 'automations');
    final spec = AppSpec._(
      str(j['name'], 'name', max: 80),
      theme,
      icon,
      policy,
      requires,
      c,
      v,
      a,
      r,
      j['navigation'] == null
          ? null
          : NavigationSpec.fromJson(object(j['navigation'], 'navigation')),
      j.containsKey('appearance')
          ? AppearanceSpec.fromJson(object(j['appearance'], 'appearance'))
          : null,
    );
    final needed = <String>{
      if (c.isNotEmpty) 'collections.v1',
      if (spec.navigation != null) 'navigation.v1',
      if (spec.appearance != null) 'appearance.v1',
      if (spec.navigation?.pages.any((p) => p.layout != null) ?? false)
        'navigation.layouts.v1',
    };
    for (final col in c) {
      needed.addAll(col.behaviors.map((b) => b.type));
      if (col.fields.any((f) => f.type == FieldType.image))
        needed.add('fields.image.v1');
    }
    for (final view in v) {
      needed.add('views.${view.type}.v1');
      if (view.type == 'banner' && view.options.containsKey('imagePlacement'))
        needed.add('appearance.v1');
      if (view.configured) needed.add('views.configured.v1');
      if (richViewTypes.contains(view.type) || view.options.isNotEmpty) {
        if (spec.navigation == null)
          throw const SpecException('Rich components need app navigation');
        _validateRichView(spec, view);
      }
      if ((view.type == 'form' || view.type == 'board') &&
          view.options.isNotEmpty)
        needed.add('views.interactive.v1');
      if (view.contentOnly) continue;
      final col = spec.collection(view.collectionId);
      if (view.titleFieldId != null) col.field(view.titleFieldId!);
      if (view.groupByFieldId != null) col.field(view.groupByFieldId!);
      if ((view.configured || spec.navigation != null) &&
          view.type == 'summary' &&
          view.groupByFieldId != null &&
          col.field(view.groupByFieldId!).type != FieldType.choice)
        throw const SpecException('Grouped summaries need a choice field');
      for (final id in view.fieldIds) {
        col.field(id);
      }
      for (final id in view.filterFieldIds) {
        if (col.field(id).type != FieldType.choice)
          throw const SpecException('View filters need choice fields');
      }
      if (view.query != null) RecordQuery.parse(col, view.query!);
      if (view.dateFilter != null &&
          col.field(view.dateFilter!.fieldId).type != FieldType.timestamp)
        throw const SpecException('Relative day filters need a timestamp');
      final hasSearch =
          view.type != 'summary' &&
          view.filterFieldIds.isNotEmpty &&
          view.titleFieldId != null;
      if (hasSearch && col.field(view.titleFieldId!).type != FieldType.text)
        throw const SpecException('Search needs a text title field');
      final relativeFilters = view.dateFilter == null
          ? 0
          : view.dateFilter!.period == 'today'
          ? 2
          : 1;
      final interactiveFilters = view.type == 'summary'
          ? 0
          : view.filterFieldIds.length + (hasSearch ? 1 : 0);
      final componentFilters = view.type == 'calendar'
          ? 2
          : view.type == 'timeline' &&
                !col.field(view.options['dateFieldId'] as String).required
          ? 1
          : 0;
      if ((view.query?['filters'] as List? ?? []).length +
              relativeFilters +
              componentFilters +
              interactiveFilters >
          Limits.filters)
        throw const SpecException(
          'Too many combined view filters, including search and choices',
        );
      for (final target in [
        (view.detailPageId, 'details'),
        (view.formPageId, 'form'),
      ]) {
        if (target.$1 == null) continue;
        final page = spec.page(target.$1!);
        final destinationViews = page.viewIds
            .map(spec.view)
            .where(
              (destination) =>
                  destination.type == target.$2 &&
                  destination.collectionId == col.id,
            )
            .toList();
        if (destinationViews.isEmpty)
          throw const SpecException(
            'Navigation destination needs a matching collection view',
          );
        if (target.$2 == 'form') {
          for (final action
              in view.actionIds
                  .map(spec.action)
                  .where(
                    (action) => {
                      'records.create.v1',
                      'records.patch.v1',
                    }.contains(action.capability),
                  )) {
            if (!destinationViews.any(
              (destination) => destination.actionIds
                  .map(spec.action)
                  .any(
                    (bound) =>
                        bound.collectionId == col.id &&
                        bound.capability == action.capability,
                  ),
            ))
              throw SpecException(
                'Form destination must support ${action.capability} for ${action.label}',
              );
          }
        }
      }
      if (view.type == 'form' &&
          !view.actionIds.any(
            (id) => spec.action(id).capability == 'records.create.v1',
          ))
        throw const SpecException('Form views need a record creation action');
      if (spec.navigation != null &&
          view.type == 'form' &&
          view.fieldIds.isNotEmpty) {
        final initializedFields = col.behaviors
            .where((behavior) => behavior.type == 'workflow.v1')
            .map((behavior) => behavior.fieldId)
            .toSet();
        final missing = col.fields
            .where(
              (field) =>
                  field.required &&
                  !initializedFields.contains(field.id) &&
                  !view.fieldIds.contains(field.id),
            )
            .map((field) => field.label)
            .toList();
        if (missing.isNotEmpty)
          throw SpecException(
            'Create forms must include required fields: ${missing.join(', ')}',
          );
      }
      if (view.type == 'action' && view.actionIds.isEmpty)
        throw const SpecException('Action views need an action');
      if (view.type == 'board' &&
          (view.groupByFieldId == null ||
              col.field(view.groupByFieldId!).type != FieldType.choice))
        throw const SpecException('Boards need a choice field');
      if (view.type == 'capacity' &&
          !col.behaviors.any((x) => x.type == 'capacity.v1'))
        throw const SpecException('Capacity view needs capacity behavior');
      for (final id in view.actionIds) {
        if (spec.action(id).collectionId != col.id)
          throw const SpecException(
            'View action belongs to another collection',
          );
      }
    }
    for (final action in a) {
      needed.add(action.capability);
      final col = spec.collection(action.collectionId);
      final expected = action.capability.startsWith('capacity.')
          ? 'capacity.v1'
          : action.capability.startsWith('workflow.')
          ? 'workflow.v1'
          : action.capability.startsWith('assignment.')
          ? 'assignment.v1'
          : null;
      if (expected != null &&
          (action.behaviorId == null ||
              !col.behaviors.any(
                (behavior) =>
                    behavior.id == action.behaviorId &&
                    behavior.type == expected,
              )))
        throw SpecException(
          'Action ${action.id} requires behaviorId referencing a declared '
          '$expected behavior in collection ${col.id}. '
          'Phone controls such as flashlight belong in collection-free '
          'deviceControl views, not record actions or behaviors.',
        );
      if (expected == null && action.behaviorId != null)
        throw const SpecException('Record actions do not bind behaviors');
    }
    for (final rule in r) {
      needed.add('notifications.inApp.v1');
      final col = spec.collection(rule.collectionId);
      if (col.field(rule.fieldId).type != FieldType.timestamp)
        throw const SpecException('Reminder needs a timestamp');
      if (rule.condition != null) {
        needed.add('automations.conditions.v1');
        final field = col.field(rule.condition!.fieldId);
        if (field.type != FieldType.choice ||
            !field.choices.contains(rule.condition!.value))
          throw const SpecException(
            'Reminder condition needs a valid choice value',
          );
      }
      if (rule.effect == 'notifyOwner') {
        needed.add('notifications.owner.v1');
        if (policy != 'personalTracker.v1')
          throw const SpecException(
            'Owner reminders need the personal tracker policy',
          );
      } else {
        final behavior = rule.effect == 'notifyActiveClaimants'
            ? 'capacity.v1'
            : 'assignment.v1';
        if (!col.behaviors.any((b) => b.type == behavior))
          throw SpecException(
            'Reminder effect ${rule.effect} requires a $behavior behavior on '
            'collection ${col.id}. For owner inbox reminders, use notifyOwner '
            'with the personalTracker.v1 policy.',
          );
      }
    }
    for (final page in spec.navigation?.pages ?? <PageSpec>[]) {
      final pageViews = page.viewIds.map(spec.view).toList();
      if (page.primaryActionId != null) {
        final action = spec.action(page.primaryActionId!);
        if (action.capability != 'records.create.v1' ||
            !pageViews.any(
              (v) =>
                  v.actionIds.contains(action.id) &&
                  (v.type == 'form' || v.formPageId != null),
            ))
          throw SpecException(
            'Page ${page.id} primaryActionId ${action.id} must reference a '
            'records.create.v1 action. Include ${action.id} in actionIds of a '
            'view on this page and set that view formPageId to its form page '
            '(unless the view is itself a form).',
          );
      }
      final recordViews = pageViews.where(
        (v) => v.type == 'details' || v.type == 'form',
      );
      if (recordViews.isNotEmpty &&
          (pageViews.length != 1 ||
              spec.navigation!.tabs.any((t) => t.pageId == page.id)))
        throw const SpecException(
          'Record details and forms need dedicated non-tab pages',
        );
    }
    if (!requires.toSet().containsAll(needed))
      throw SpecException(
        'Missing required capabilities: ${needed.difference(requires.toSet()).join(", ")}',
      );
    return spec;
  }
  ViewSpec view(String id) =>
      views.where((v) => v.id == id).firstOrNull ??
      (throw SpecException('Unknown view $id'));
  PageSpec page(String id) =>
      navigation?.pages.where((p) => p.id == id).firstOrNull ??
      (throw SpecException('Unknown page $id'));
  CollectionSpec collection(String id) =>
      collections.where((c) => c.id == id).firstOrNull ??
      (throw SpecException('Unknown collection $id'));
  ActionSpec action(String id) =>
      actions.where((a) => a.id == id).firstOrNull ??
      (throw SpecException('Unknown action $id'));
  Map<String, dynamic> toJson() => {
    'formatVersion': 1,
    'name': name,
    'theme': theme,
    'icon': icon,
    'requires': requires,
    'collections': collections.map((x) => x.toJson()).toList(),
    'views': views.map((x) => x.toJson()).toList(),
    'actions': actions.map((x) => x.toJson()).toList(),
    'policyPresetRequest': policyPresetRequest,
    'automationRequests': automationRequests.map((x) => x.toJson()).toList(),
    if (navigation != null) 'navigation': navigation!.toJson(),
    if (appearance != null) 'appearance': appearance!.toJson(),
  };
  String get canonical => canonicalJson(toJson());
  String get hash => hashJson(toJson());

  List<String> compatibilityErrors(AppSpec next) {
    final errors = <String>[];
    if (policyPresetRequest != next.policyPresetRequest)
      errors.add('Changing the permission preset is unsupported');
    for (final old in collections) {
      final col = next.collections.where((c) => c.id == old.id).firstOrNull;
      if (col == null) {
        errors.add('Removing collection ${old.label} is unsupported');
        continue;
      }
      for (final field in old.fields) {
        final f = col.fields.where((x) => x.id == field.id).firstOrNull;
        if (f == null ||
            f.type != field.type ||
            (!field.required && f.required) ||
            !f.choices.toSet().containsAll(field.choices))
          errors.add('Destructive change to ${field.label}');
      }
      for (final f in col.fields) {
        if (f.required && !old.fields.any((x) => x.id == f.id))
          errors.add('Required field ${f.label} needs a backfill');
      }
      if (canonicalJson(old.behaviors.map((b) => b.toJson()).toList()) !=
          canonicalJson(col.behaviors.map((b) => b.toJson()).toList()))
        errors.add('Changing existing behaviors is unsupported');
    }
    return errors;
  }

  List<String> diff(AppSpec? previous) {
    if (previous == null)
      return [
        'Create $name',
        'Policy: $policyPresetRequest',
        ...requires.map((r) => 'Capability: $r'),
        ...automationRequests.map((r) => 'Request reminder: ${r.id}'),
      ];
    final result = <String>[];
    if (name != previous.name) result.add('Rename ${previous.name} to $name');
    if (theme != previous.theme || icon != previous.icon)
      result.add('Update app theme or icon');
    if (canonicalJson(appearance?.toJson()) !=
        canonicalJson(previous.appearance?.toJson())) {
      result.add(
        appearance == null
            ? 'Restore original app appearance'
            : appearance!.style != previous.appearance?.style
            ? 'Change app style to ${appearance!.style}'
            : 'Update app appearance',
      );
    }
    for (final page in navigation?.pages ?? <PageSpec>[]) {
      final old = previous.navigation?.pages
          .where((p) => p.id == page.id)
          .firstOrNull;
      if (old != null && page.layout != old.layout) {
        final label = switch (page.layout) {
          'stacked' => 'Stacked',
          'twoColumn' => 'Two columns',
          'featuredFirst' => 'Featured first',
          _ => 'Original',
        };
        result.add('Change ${page.title} layout to $label');
      }
    }
    if (canonicalJson(navigation?.toJson()) !=
        canonicalJson(previous.navigation?.toJson()))
      result.add('Update pages or tab navigation');
    for (final col in collections) {
      final old = previous.collections.where((x) => x.id == col.id).firstOrNull;
      for (final f in col.fields) {
        final before = old?.fields.where((x) => x.id == f.id).firstOrNull;
        if (before == null)
          result.add('Add ${f.required ? "required" : "optional"} ${f.label}');
        else if (canonicalJson(before.toJson()) != canonicalJson(f.toJson()))
          result.add('Update ${before.label}: ${f.label}');
      }
    }
    if (canonicalJson(views.map((v) => v.toJson()).toList()) !=
        canonicalJson(previous.views.map((v) => v.toJson()).toList()))
      result.add('Update views or view order');
    for (final view in views.where((v) => v.type == 'banner')) {
      final old = previous.views.where((v) => v.id == view.id).firstOrNull;
      if (old != null &&
          view.options['imagePlacement'] != old.options['imagePlacement']) {
        final label = switch (view.options['imagePlacement']) {
          'beside' => 'Beside text',
          'above' => 'Above text',
          _ => 'Original',
        };
        result.add('Change ${view.label} image placement to $label');
      }
    }
    for (final action in actions) {
      final before = previous.actions
          .where((a) => a.id == action.id)
          .firstOrNull;
      if (before != null && before.label != action.label)
        result.add('Rename action ${before.label} to ${action.label}');
    }
    for (final c in requires.toSet().difference(previous.requires.toSet()))
      result.add('Request capability: $c');
    if (canonicalJson(automationRequests.map((r) => r.toJson()).toList()) !=
        canonicalJson(
          previous.automationRequests.map((r) => r.toJson()).toList(),
        ))
      result.add('Change requested reminders');
    return result.isEmpty ? ['No structural changes'] : result;
  }

  AppSpec patch(Map<String, dynamic> patch, String Function() allocateId) {
    final j = object(jsonDecode(canonical), 'AppSpec'), type = patch['type'];
    void requireCapability(String value) {
      if (!(j['requires'] as List).contains(value))
        (j['requires'] as List).add(value);
    }

    void viewCapabilities(Map<String, dynamic> view) {
      requireCapability('views.${view['type']}.v1');
      if (ViewSpec.fromJson(view).configured)
        requireCapability('views.configured.v1');
      if ({'form', 'board'}.contains(view['type']) &&
          (view['options'] as Map? ?? {}).isNotEmpty)
        requireCapability('views.interactive.v1');
    }

    switch (type) {
      case 'RenameField':
        keys(patch, {
          'type',
          'collectionId',
          'fieldId',
          'label',
        }, 'RenameField');
        final label = str(patch['label'], 'label');
        final collection = (j['collections'] as List)
            .where((c) => c['id'] == patch['collectionId'])
            .firstOrNull;
        if (collection == null)
          throw const SpecException('Collection not found');
        final field = (collection['fields'] as List)
            .where((f) => f['id'] == patch['fieldId'])
            .firstOrNull;
        if (field == null) throw const SpecException('Field not found');
        field['label'] = label;
      case 'RenameLabel':
        keys(patch, {'type', 'targetId', 'label'}, 'RenameLabel');
        final label = str(patch['label'], 'label');
        if (patch['targetId'] == 'app') {
          j['name'] = label;
          break;
        }
        var found = 0;
        for (final c in j['collections']) {
          if (c['id'] == patch['targetId']) {
            c['label'] = label;
            found++;
          }
          for (final f in c['fields']) {
            if (f['id'] == patch['targetId']) {
              f['label'] = label;
              found++;
            }
          }
        }
        for (final key in ['views', 'actions']) {
          for (final x in j[key]) {
            if (x['id'] == patch['targetId']) {
              x['label'] = label;
              found++;
            }
          }
        }
        for (final p in (j['navigation']?['pages'] as List? ?? [])) {
          if (p['id'] == patch['targetId']) {
            p['title'] = label;
            found++;
          }
        }
        if (found == 0) throw const SpecException('Label target not found');
        if (found > 1)
          throw const SpecException(
            'Label target is ambiguous; use globally distinct IDs for manual label editing.',
          );
      case 'AddField':
        keys(patch, {'type', 'collectionId', 'field', 'viewIds'}, 'AddField');
        final col = (j['collections'] as List)
            .cast<Map<String, dynamic>>()
            .where((c) => c['id'] == patch['collectionId'])
            .firstOrNull;
        if (col == null) throw const SpecException('Collection not found');
        final viewIds = array(
          patch.containsKey('viewIds') ? patch['viewIds'] : [],
          'field views',
          Limits.views,
        ).map(stableId).toList();
        unique(viewIds, 'field views');
        for (final id in viewIds) {
          final target = view(id);
          if (target.collectionId != col['id'] ||
              !fieldBindingViewTypes.contains(target.type)) {
            throw const SpecException(
              'New fields can bind only to lists, tables, forms and details in the same collection',
            );
          }
        }
        final f = Map<String, dynamic>.from(object(patch['field'], 'field'))
          ..['id'] = allocateId();
        f['required'] ??= false;
        final field = FieldSpec.fromJson(f);
        (col['fields'] as List).add(field.toJson());
        for (final target in j['views'] as List) {
          final selected = viewIds.contains(target['id']);
          // Empty/absent fieldIds already displays all collection fields. Keep
          // that behavior instead of narrowing the view to only the new field.
          final visible = target['fieldIds'] as List?;
          final implicit = visible == null || visible.isEmpty;
          // With atomic binding, every implicit stepped form exposes the new
          // field, including unselected forms. Extend their step coverage too.
          final implicitForm =
              patch.containsKey('viewIds') &&
              target['type'] == 'form' &&
              target['collectionId'] == col['id'] &&
              implicit;
          if (!selected && !implicitForm) continue;
          if (selected && !implicit) visible.add(field.id);
          final steps = target['options']?['steps'] as List?;
          if (steps != null) (steps.last['fieldIds'] as List).add(field.id);
        }
        if (f['type'] == 'image') requireCapability('fields.image.v1');
      case 'AddChoice':
        keys(patch, {'type', 'collectionId', 'fieldId', 'choice'}, 'AddChoice');
        collection(patch['collectionId']).field(patch['fieldId']);
        final col = (j['collections'] as List).firstWhere(
          (c) => c['id'] == patch['collectionId'],
        );
        final f = (col['fields'] as List).firstWhere(
          (f) => f['id'] == patch['fieldId'],
        );
        (f['choices'] as List).add(str(patch['choice'], 'choice'));
      case 'AddView':
        keys(patch, {'type', 'view'}, 'AddView');
        final view = Map<String, dynamic>.from(object(patch['view'], 'view'))
          ..['id'] = allocateId();
        (j['views'] as List).add(view);
        viewCapabilities(view);
      case 'UpdateView':
        keys(patch, {'type', 'viewId', 'view'}, 'UpdateView');
        final id = stableId(patch['viewId']);
        view(id);
        final changed = Map<String, dynamic>.from(
          object(patch['view'], 'view'),
        );
        if (changed.containsKey('id'))
          throw const SpecException('View identity cannot be changed');
        changed['id'] = id;
        viewCapabilities(changed);
        j['views'] = (j['views'] as List)
            .map((v) => v['id'] == id ? changed : v)
            .toList();
      case 'AddPage':
        keys(patch, {'type', 'page', 'newViews', 'tab'}, 'AddPage');
        final page = Map<String, dynamic>.from(object(patch['page'], 'page'));
        if (page.containsKey('id'))
          throw const SpecException('Page IDs are allocated by the server');
        page['id'] = allocateId();
        final viewIds = array(
          page['viewIds'] ?? [],
          'page views',
          8,
        ).map(stableId).toList();
        for (final value in array(
          patch['newViews'] ?? [],
          'new page views',
          8,
        )) {
          final view = Map<String, dynamic>.from(
            object(value, 'new page view'),
          );
          if (view.containsKey('id'))
            throw const SpecException('View IDs are allocated by the server');
          view['id'] = allocateId();
          viewCapabilities(view);
          (j['views'] as List).add(view);
          viewIds.add(view['id'] as String);
        }
        page['viewIds'] = viewIds;
        final parsed = PageSpec.fromJson(page);
        Map<String, dynamic>? tab;
        if (patch['tab'] != null) {
          final tabData = object(patch['tab'], 'new page tab');
          keys(tabData, {'label', 'icon'}, 'new page tab');
          tab = TabSpec.fromJson({...tabData, 'pageId': parsed.id}).toJson();
        }
        if (j['navigation'] == null) {
          j['navigation'] = {
            'entryPageId': parsed.id,
            'pages': [parsed.toJson()],
            'tabs': [
              tab ??
                  {
                    'pageId': parsed.id,
                    'label': parsed.title.length > 40
                        ? parsed.title.substring(0, 40)
                        : parsed.title,
                    'icon': 'spark',
                  },
            ],
          };
        } else {
          (j['navigation']['pages'] as List).add(parsed.toJson());
          if (tab != null) (j['navigation']['tabs'] as List).add(tab);
        }
        requireCapability('navigation.v1');
      case 'UpdatePage':
        keys(patch, {'type', 'pageId', 'page'}, 'UpdatePage');
        final id = stableId(patch['pageId']);
        page(id);
        final changed = Map<String, dynamic>.from(
          object(patch['page'], 'page'),
        );
        if (changed.containsKey('id'))
          throw const SpecException('Page identity cannot be changed');
        changed['id'] = id;
        final parsed = PageSpec.fromJson(changed);
        j['navigation']['pages'] = (j['navigation']['pages'] as List)
            .map((p) => p['id'] == id ? parsed.toJson() : p)
            .toList();
      case 'ReorderPages':
        keys(patch, {'type', 'pageIds'}, 'ReorderPages');
        final ids = array(
          patch['pageIds'],
          'pageIds',
          16,
        ).map(stableId).toList();
        final pages = navigation?.pages ?? <PageSpec>[];
        if (pages.isEmpty ||
            ids.length != pages.length ||
            ids.toSet().length != pages.length ||
            !ids.toSet().containsAll(pages.map((p) => p.id)))
          throw const SpecException('Page order must include each page once');
        j['navigation']['pages'] = ids
            .map(
              (id) => (j['navigation']['pages'] as List).firstWhere(
                (p) => p['id'] == id,
              ),
            )
            .toList();
      case 'SetNavigation':
        keys(patch, {'type', 'entryPageId', 'tabs'}, 'SetNavigation');
        if (navigation == null)
          throw const SpecException('Add a page before configuring navigation');
        j['navigation']['entryPageId'] = patch['entryPageId'];
        j['navigation']['tabs'] = patch['tabs'];
      case 'SetTheme':
        keys(patch, {'type', 'theme', 'icon'}, 'SetTheme');
        j['theme'] = patch['theme'];
        if (patch.containsKey('icon')) j['icon'] = patch['icon'];
      case 'SetAppearance':
        keys(patch, {'type', 'appearance'}, 'SetAppearance');
        if (!patch.containsKey('appearance'))
          throw const SpecException('SetAppearance needs an appearance value');
        if (patch['appearance'] == null) {
          j.remove('appearance');
        } else {
          j['appearance'] = AppearanceSpec.fromJson(
            object(patch['appearance'], 'appearance'),
          ).toJson();
        }
      case 'ReorderView':
        keys(patch, {'type', 'viewIds'}, 'ReorderView');
        final ids = array(
          patch['viewIds'],
          'viewIds',
          Limits.views,
        ).cast<String>();
        if (ids.length != views.length ||
            ids.toSet().length != views.length ||
            !ids.toSet().containsAll(views.map((v) => v.id)))
          throw const SpecException('View order must include each view once');
        j['views'] = ids
            .map((id) => (j['views'] as List).firstWhere((v) => v['id'] == id))
            .toList();
      case 'UpdateReminder':
        keys(patch, {'type', 'ruleId', 'rule'}, 'UpdateReminder');
        final id = stableId(patch['ruleId']);
        if (!automationRequests.any((rule) => rule.id == id))
          throw const SpecException('Reminder not found');
        final rule = Map<String, dynamic>.from(object(patch['rule'], 'rule'));
        if (rule.containsKey('id'))
          throw const SpecException('Reminder identity cannot be changed');
        rule['id'] = id;
        final validated = AutomationSpec.fromJson(rule).toJson();
        j['automationRequests'] = (j['automationRequests'] as List)
            .map((existing) => existing['id'] == id ? validated : existing)
            .toList();
        requireCapability('notifications.inApp.v1');
        if (rule['effect']?['type'] == 'notifyOwner')
          requireCapability('notifications.owner.v1');
        if (rule['condition'] != null)
          requireCapability('automations.conditions.v1');
      case 'ProposeReminder':
        keys(patch, {'type', 'rule'}, 'ProposeReminder');
        final rule = Map<String, dynamic>.from(object(patch['rule'], 'rule'))
          ..['id'] = allocateId();
        (j['automationRequests'] as List).add(rule);
        requireCapability('notifications.inApp.v1');
        if (rule['effect']?['type'] == 'notifyOwner')
          requireCapability('notifications.owner.v1');
        if (rule['condition'] != null)
          requireCapability('automations.conditions.v1');
      default:
        throw const SpecException('Unsupported semantic patch');
    }
    // These presentation capabilities follow their actual use. Restoring one
    // appearance option must not disable a different option that still uses it.
    if ({
      'SetAppearance',
      'AddView',
      'UpdateView',
      'AddPage',
      'UpdatePage',
    }.contains(type)) {
      void reconcileCapability(String capability, bool used) {
        if (used) {
          requireCapability(capability);
        } else {
          (j['requires'] as List).removeWhere((value) => value == capability);
        }
      }

      reconcileCapability(
        'appearance.v1',
        j.containsKey('appearance') ||
            (j['views'] as List).any(
              (v) =>
                  v['type'] == 'banner' &&
                  (v['options'] as Map? ?? {}).containsKey('imagePlacement'),
            ),
      );
      reconcileCapability(
        'navigation.layouts.v1',
        (j['navigation']?['pages'] as List? ?? []).any(
          (p) => (p as Map).containsKey('layout'),
        ),
      );
    }
    return AppSpec.parse(jsonEncode(j));
  }
}

class RecordQuery {
  final List<Map<String, dynamic>> filters, sort;
  final int limit;
  final String? cursor;
  RecordQuery(this.filters, this.sort, this.limit, this.cursor);
  factory RecordQuery.parse(CollectionSpec collection, Map<String, dynamic> j) {
    keys(j, {'filters', 'sort', 'limit', 'cursor'}, 'query');
    final limit = j['limit'] ?? 50;
    if (limit is! int || limit < 1 || limit > Limits.pageSize)
      throw const SpecException('Page size must be 1–100');
    final filters = array(
      j['filters'] ?? [],
      'filters',
      Limits.filters,
    ).map((f) => Map<String, dynamic>.from(object(f, 'filter'))).toList();
    for (final f in filters) {
      keys(f, {'fieldId', 'operator', 'value'}, 'filter');
      final field = collection.field(str(f['fieldId'], 'fieldId'));
      final op = f['operator'];
      if (!{'eq', 'in', 'gte', 'lte', 'lt', 'contains'}.contains(op))
        throw const SpecException('Unsupported query operator');
      if (op == 'contains' && field.type != FieldType.text)
        throw const SpecException('Contains requires text');
      if ((op == 'gte' || op == 'lte' || op == 'lt') &&
          !{
            FieldType.integer,
            FieldType.number,
            FieldType.timestamp,
          }.contains(field.type))
        throw const SpecException('Range requires number or timestamp');
      if (op == 'in') {
        final values = array(f['value'], 'filter values', 30);
        if (values.any((v) => v == null))
          throw const SpecException(
            'Membership filters cannot include null; use equality for unset values',
          );
        f['value'] = values
            .map((value) => _normalizeFilter(field, value))
            .toList();
      } else {
        if (op != 'eq' && f['value'] == null)
          throw const SpecException(
            'Only equality filters can compare unset values',
          );
        f['value'] = _normalizeFilter(field, f['value']);
      }
    }
    final sorts = array(
      j['sort'] ?? [],
      'sort',
      2,
    ).map((s) => object(s, 'sort')).toList();
    for (final s in sorts) {
      keys(s, {'fieldId', 'descending'}, 'sort');
      collection.field(str(s['fieldId'], 'fieldId'));
      if (s['descending'] is! bool)
        throw const SpecException('Sort descending must be boolean');
    }
    if (j['cursor'] != null) str(j['cursor'], 'cursor', max: 4096);
    return RecordQuery(filters, sorts, limit, j['cursor']);
  }

  static Object? _normalizeFilter(FieldSpec field, Object? value) {
    try {
      return field.normalize(value);
    } on SpecException {
      if (field.type != FieldType.timestamp || value == null) rethrow;
      throw SpecException(
        'Query filter ${field.id} needs a valid ISO timestamp with timezone. '
        'For relative days, remove this query filter and set the view property '
        'dateFilter: {"fieldId":"${field.id}","period":"today"} '
        '(or period "overdue"). Relative words and date-only values are not timestamps.',
      );
    }
  }
}

/// Resolves local calendar days by constructing both boundaries independently.
/// This intentionally avoids adding 24 hours across daylight-saving changes.
Map<String, dynamic> resolveViewQuery(
  AppSpec spec,
  ViewSpec view, {
  DateTime? now,
}) {
  final source = <String, dynamic>{...?view.query};
  final filters = <Map<String, dynamic>>[
    for (final f in (source['filters'] as List? ?? []))
      Map<String, dynamic>.from(f as Map),
  ];
  final binding = view.dateFilter;
  if (binding != null) {
    final local = (now ?? DateTime.now()).toLocal();
    final start = DateTime(local.year, local.month, local.day).toUtc();
    final end = DateTime(local.year, local.month, local.day + 1).toUtc();
    if (binding.period == 'today') {
      filters.add({
        'fieldId': binding.fieldId,
        'operator': 'gte',
        'value': start.toIso8601String(),
      });
      filters.add({
        'fieldId': binding.fieldId,
        'operator': 'lt',
        'value': end.toIso8601String(),
      });
    } else {
      filters.add({
        'fieldId': binding.fieldId,
        'operator': 'lt',
        'value': start.toIso8601String(),
      });
    }
  }
  final query = RecordQuery.parse(spec.collection(view.collectionId), {
    ...source,
    'filters': filters,
  });
  return {'filters': query.filters, 'sort': query.sort, 'limit': query.limit};
}
