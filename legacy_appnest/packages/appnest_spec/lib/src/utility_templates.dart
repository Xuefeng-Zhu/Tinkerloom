part of '../appnest_spec.dart';

Map<String, AppSpec> utilityStarterTemplates() => {
  'notes': notesTemplate(),
  'reminders': remindersTemplate(),
  'calendar': calendarTemplate(),
  'focus': focusTemplate(),
  'phoneToolkit': phoneToolkitTemplate(),
};

AppSpec notesTemplate() => _personalUtilityRecords(
  name: 'My Notes',
  collection: 'notes',
  theme: 'amber',
  fields: [
    _field('title', 'Title', 'text', required: true),
    _field('body', 'Note', 'text'),
    _field(
      'category',
      'Category',
      'choice',
      choices: ['Ideas', 'Personal', 'Work'],
    ),
  ],
  overview: {
    ..._richView(
      'allEntries',
      'list',
      'notes',
      'Notes',
      fields: ['body', 'category'],
    ),
    'presentation': 'cards',
    'filterFieldIds': ['category'],
  },
  controls: [
    {'fieldId': 'body', 'control': 'multiline'},
  ],
);

AppSpec calendarTemplate() => _personalUtilityRecords(
  name: 'My Calendar',
  collection: 'events',
  theme: 'blue',
  fields: [
    _field('title', 'Event', 'text', required: true),
    _field('startsAt', 'When', 'timestamp', required: true),
    _field('notes', 'Notes', 'text'),
    _field(
      'category',
      'Category',
      'choice',
      choices: ['Personal', 'Work', 'Family'],
    ),
  ],
  overview: {
    ..._richView(
      'allEntries',
      'calendar',
      'events',
      'Calendar',
      fields: ['startsAt', 'category'],
      options: {'dateFieldId': 'startsAt'},
    ),
    'filterFieldIds': ['category'],
  },
  controls: [
    {'fieldId': 'notes', 'control': 'multiline'},
  ],
);

AppSpec _personalUtilityRecords({
  required String name,
  required String collection,
  required String theme,
  required List<Map<String, dynamic>> fields,
  required Map<String, dynamic> overview,
  required List<Map<String, dynamic>> controls,
}) => _richTemplate(
  name: name,
  theme: theme,
  collection: collection,
  fields: fields,
  views: [
    overview,
    {
      ..._richView(
        'entryDetails',
        'details',
        collection,
        'Details',
        fields: fields.map((f) => f['id'] as String).toList(),
        actions: ['editRecord'],
      ),
      'formPageId': 'formPage',
    },
    _richView(
      'entryEditor',
      'form',
      collection,
      'Edit entry',
      fields: fields.map((f) => f['id'] as String).toList(),
      options: {'controls': controls},
    ),
  ],
  pages: [
    {
      ..._richPage('homePage', name, ['allEntries']),
      'primaryActionId': 'addRecord',
    },
    _richPage('detailPage', 'Details', ['entryDetails']),
    _richPage('formPage', 'Edit entry', ['entryEditor']),
  ],
  tabs: [_richTab('homePage', name, 'list')],
);

AppSpec remindersTemplate() {
  final json = dailyPlannerTemplate().toJson();
  json['name'] = 'My Reminders';
  json['navigation']['entryPageId'] = 'tasksPage';
  json['navigation']['tabs'] = [
    {'pageId': 'tasksPage', 'label': 'Reminders', 'icon': 'list'},
    {'pageId': 'progressPage', 'label': 'Progress', 'icon': 'chart'},
  ];
  for (final page in json['navigation']['pages']) {
    if (page['id'] == 'tasksPage') page['title'] = 'Reminders';
  }
  return AppSpec.parse(jsonEncode(json));
}

AppSpec focusTemplate() => AppSpec.parse(
  jsonEncode({
    'formatVersion': 1,
    'name': 'My Focus Clock',
    'theme': 'teal',
    'icon': 'spark',
    'requires': ['navigation.v1', 'views.clock.v1', 'views.timer.v1'],
    'policyPresetRequest': 'personalTracker.v1',
    'collections': [],
    'actions': [],
    'automationRequests': [],
    'views': [
      {'id': 'localClock', 'type': 'clock', 'label': 'Local time'},
      {'id': 'focusTimer', 'type': 'timer', 'label': 'Focus timer'},
    ],
    'navigation': {
      'entryPageId': 'focusPage',
      'pages': [
        _richPage('focusPage', 'Time for yourself', [
          'localClock',
          'focusTimer',
        ]),
      ],
      'tabs': [_richTab('focusPage', 'Focus', 'today')],
    },
  }),
);
