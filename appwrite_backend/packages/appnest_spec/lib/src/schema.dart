part of '../appnest_spec.dart';

Map<String, dynamic> appSpecSchema() {
  Map<String, dynamic> obj(
    Map<String, dynamic> properties,
    List<String> required,
  ) => {
    'type': 'object',
    'additionalProperties': false,
    'properties': properties,
    'required': required,
  };
  Map<String, dynamic> arr(Object items, int max) => {
    'type': 'array',
    'items': items,
    'maxItems': max,
  };
  final id = {
        'type': 'string',
        'pattern': r'^[a-zA-Z][a-zA-Z0-9_]*$',
        'maxLength': 64,
      },
      label = {'type': 'string', 'minLength': 1, 'maxLength': 160};
  final field = obj(
    {
      'id': id,
      'label': label,
      'type': {'enum': FieldType.values.map((t) => t.name).toList()},
      'required': {'type': 'boolean'},
      'choices': arr({'type': 'string', 'minLength': 1, 'maxLength': 80}, 30),
    },
    ['id', 'label', 'type', 'required'],
  );
  final behavior = obj(
    {
      'id': id,
      'type': {
        'enum': ['capacity.v1', 'workflow.v1', 'assignment.v1'],
      },
      'fieldId': id,
      'transitions': {
        'type': 'object',
        'maxProperties': 30,
        'additionalProperties': arr(label, 30),
      },
    },
    ['id', 'type'],
  );
  final collection = obj(
    {
      'id': id,
      'label': label,
      'fields': {...arr(field, Limits.fields), 'minItems': 1},
      'behaviors': arr(behavior, 8),
    },
    ['id', 'label', 'fields'],
  );
  final view = obj(
    {
      'id': id,
      'type': {
        'enum': [
          'list',
          'form',
          'details',
          'board',
          'summary',
          'capacity',
          'action',
          ...richViewTypes,
        ],
      },
      'collectionId': id,
      'label': label,
      'titleFieldId': id,
      'groupByFieldId': id,
      'actionIds': arr(id, 32),
      'presentation': {
        'enum': ['compact', 'cards'],
      },
      'fieldIds': arr(id, Limits.fields),
      'filterFieldIds': arr(id, Limits.filters),
      'query': obj({
        'filters': arr(
          obj(
            {
              'fieldId': id,
              'operator': {
                'enum': ['eq', 'in', 'gte', 'lte', 'lt', 'contains'],
              },
              'value': {},
            },
            ['fieldId', 'operator', 'value'],
          ),
          Limits.filters,
        ),
        'sort': arr(
          obj(
            {
              'fieldId': id,
              'descending': {'type': 'boolean'},
            },
            ['fieldId', 'descending'],
          ),
          2,
        ),
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': Limits.pageSize},
      }, []),
      'dateFilter': obj(
        {
          'fieldId': id,
          'period': {
            'enum': ['today', 'overdue'],
          },
        },
        ['fieldId', 'period'],
      ),
      'detailPageId': id,
      'formPageId': id,
      'options': {'type': 'object'},
    },
    ['id', 'type'],
  );
  view['allOf'] = [
    {
      'if': {
        'properties': {
          'type': {
            'enum': [
              'richText',
              'banner',
              'clock',
              'timer',
              'deviceInfo',
              'deviceControl',
            ],
          },
        },
      },
      'then': {
        'not': {
          'required': ['collectionId'],
        },
      },
      'else': {
        'required': ['collectionId'],
      },
    },
    for (final type in [
      'list',
      'form',
      'details',
      'board',
      'summary',
      'capacity',
      'action',
      ...richViewTypes,
    ])
      {
        'if': {
          'properties': {
            'type': {'const': type},
          },
        },
        'then': {
          'properties': {'options': _richOptionsSchema(type)},
          if (richViewTypes.contains(type) &&
              !{'table', 'clock', 'timer'}.contains(type))
            'required': ['options'],
        },
      },
  ];
  final action = obj(
    {
      'id': id,
      'label': label,
      'capability': {'enum': actionCapabilities.toList()},
      'collectionId': id,
      'behaviorId': id,
    },
    ['id', 'label', 'capability', 'collectionId'],
  );
  final rule = obj(
    {
      'id': id,
      'trigger': obj(
        {
          'type': {'const': 'beforeTimestamp'},
          'collectionId': id,
          'fieldId': id,
          'offsetSeconds': {'type': 'integer', 'minimum': 0, 'maximum': 604800},
        },
        ['type', 'collectionId', 'fieldId', 'offsetSeconds'],
      ),
      'effect': obj(
        {
          'type': {
            'enum': ['notifyActiveClaimants', 'notifyAssignee', 'notifyOwner'],
          },
          'channel': {'const': 'inApp'},
        },
        ['type', 'channel'],
      ),
      'condition': obj(
        {
          'fieldId': id,
          'value': {'type': 'string', 'minLength': 1, 'maxLength': 80},
        },
        ['fieldId', 'value'],
      ),
    },
    ['id', 'trigger', 'effect'],
  );
  final page = obj(
    {
      'id': id,
      'title': label,
      'viewIds': {...arr(id, 8), 'minItems': 1, 'uniqueItems': true},
      'showDate': {'type': 'boolean'},
      'primaryActionId': id,
      'layout': {'enum': pageLayouts.toList()},
    },
    ['id', 'title', 'viewIds'],
  );
  final tab = obj(
    {
      'pageId': id,
      'label': {'type': 'string', 'minLength': 1, 'maxLength': 40},
      'icon': {'enum': navigationIcons.toList()},
    },
    ['pageId', 'label', 'icon'],
  );
  final navigation = obj(
    {
      'entryPageId': id,
      'pages': {...arr(page, 16), 'minItems': 1},
      'tabs': {...arr(tab, 5), 'minItems': 1},
    },
    ['entryPageId', 'pages', 'tabs'],
  );
  return {
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    r'$id': 'https://appnest.local/schema/appspec-v1.json',
    'title': 'AppNest AppSpec v1',
    ...obj(
      {
        'formatVersion': {'const': 1},
        'name': {'type': 'string', 'minLength': 1, 'maxLength': 80},
        'theme': {
          'enum': ['teal', 'amber', 'blue', 'rose', 'sage'],
        },
        'icon': {
          'enum': ['book', 'board', 'people', 'spark', 'check'],
        },
        'requires': arr({'enum': capabilities.toList()}, 40),
        'collections': arr(collection, Limits.collections),
        'views': {...arr(view, Limits.views), 'minItems': 1},
        'actions': arr(action, Limits.actions),
        'policyPresetRequest': {'enum': policyPresets.toList()},
        'automationRequests': arr(rule, Limits.rules),
        'navigation': navigation,
        'appearance': obj(
          {
            'style': {'enum': appearanceStyles.toList()},
            'accentColor': {'type': 'string', 'pattern': r'^#[0-9a-fA-F]{6}$'},
            'typography': {'enum': appearanceTypographies.toList()},
            'density': {'enum': appearanceDensities.toList()},
            'corners': {'enum': appearanceCorners.toList()},
          },
          ['style'],
        ),
      },
      [
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
      ],
    ),
  };
}
