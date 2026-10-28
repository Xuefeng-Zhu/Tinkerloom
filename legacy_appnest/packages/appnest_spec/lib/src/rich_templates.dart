part of '../appnest_spec.dart';

Map<String, AppSpec> richStarterTemplates() => {
  'projectHub': projectHubTemplate(),
  'photoJournal': photoJournalTemplate(),
  'habitTracker': habitTrackerTemplate(),
};

AppSpec _richTemplate({
  required String name,
  required String theme,
  required String collection,
  required List<Map<String, dynamic>> fields,
  required List<Map<String, dynamic>> views,
  required List<Map<String, dynamic>> pages,
  required List<Map<String, dynamic>> tabs,
  List<Map<String, dynamic>> behaviors = const [],
  List<Map<String, dynamic>> extraActions = const [],
  String policy = 'personalTracker.v1',
}) {
  final actions = [
    _action('addRecord', 'Add entry', 'records.create.v1', collection),
    _action('editRecord', 'Edit entry', 'records.patch.v1', collection),
    ...extraActions,
  ];
  final required = <String>{
    'collections.v1',
    'navigation.v1',
    ...behaviors.map((b) => b['type'] as String),
    ...actions.map((a) => a['capability'] as String),
    if (fields.any((f) => f['type'] == 'image')) 'fields.image.v1',
    for (final v in views) 'views.${v['type']}.v1',
    if (views.any((v) => ViewSpec.fromJson(v).configured))
      'views.configured.v1',
    if (views.any(
      (v) =>
          {'form', 'board'}.contains(v['type']) &&
          (v['options'] as Map? ?? {}).isNotEmpty,
    ))
      'views.interactive.v1',
  };
  return AppSpec.parse(
    jsonEncode({
      'formatVersion': 1,
      'name': name,
      'theme': theme,
      'icon': 'spark',
      'requires': required.toList(),
      'policyPresetRequest': policy,
      'collections': [
        {
          'id': collection,
          'label': 'Entries',
          'fields': fields,
          'behaviors': behaviors,
        },
      ],
      'actions': actions,
      'views': views,
      'automationRequests': [],
      'navigation': {
        'entryPageId': tabs.first['pageId'],
        'pages': pages,
        'tabs': tabs,
      },
    }),
  );
}

Map<String, dynamic> _richView(
  String id,
  String type,
  String collection,
  String label, {
  Map<String, dynamic> options = const {},
  List<String> fields = const [],
  String? group,
  List<String> actions = const ['addRecord', 'editRecord'],
}) => {
  'id': id,
  'type': type,
  'collectionId': collection,
  'label': label,
  'titleFieldId': 'title',
  'actionIds': actions,
  if (fields.isNotEmpty) 'fieldIds': fields,
  if (group != null) 'groupByFieldId': group,
  if (options.isNotEmpty) 'options': options,
  if (!{'form', 'details', 'chart', 'metric', 'summary'}.contains(type)) ...{
    'detailPageId': 'detailPage',
    'formPageId': 'formPage',
  },
};
Map<String, dynamic> _richPage(String id, String title, List<String> views) => {
  'id': id,
  'title': title,
  'viewIds': views,
};
Map<String, dynamic> _richTab(String id, String label, String icon) => {
  'pageId': id,
  'label': label,
  'icon': icon,
};

AppSpec projectHubTemplate() {
  const collection = 'projects';
  return _richTemplate(
    name: 'Project Hub',
    theme: 'blue',
    collection: collection,
    policy: 'groupWorkflow.v1',
    fields: [
      _field('title', 'Task', 'text', required: true),
      _field(
        'status',
        'Status',
        'choice',
        required: true,
        choices: ['Open', 'Done'],
      ),
      _field('dueAt', 'Due date', 'timestamp'),
      _field(
        'priority',
        'Priority',
        'choice',
        choices: ['Low', 'Normal', 'High'],
      ),
      _field('effort', 'Effort', 'integer'),
      _field('notes', 'Notes', 'text'),
    ],
    behaviors: [
      {
        'id': 'workflow',
        'type': 'workflow.v1',
        'fieldId': 'status',
        'transitions': {
          'Open': ['Done'],
          'Done': ['Open'],
        },
      },
    ],
    extraActions: [
      _action(
        'moveRecord',
        'Change status',
        'workflow.transition.v1',
        collection,
        behavior: 'workflow',
      ),
    ],
    views: [
      {
        'id': 'welcome',
        'type': 'banner',
        'label': 'Project overview',
        'options': {
          'title': 'Make progress together',
          'body':
              'Plan the next step, share the work, and celebrate what is done.',
          'tone': 'accent',
        },
      },
      _richView(
        'taskBoard',
        'board',
        collection,
        'Team board',
        group: 'status',
        options: {'draggable': true, 'moveActionId': 'moveRecord'},
        actions: ['addRecord', 'editRecord', 'moveRecord'],
      ),
      _richView(
        'taskTable',
        'table',
        collection,
        'All tasks',
        fields: ['title', 'priority', 'dueAt', 'effort'],
      ),
      _richView(
        'taskCalendar',
        'calendar',
        collection,
        'Calendar',
        options: {'dateFieldId': 'dueAt'},
      ),
      _richView(
        'taskTimeline',
        'timeline',
        collection,
        'Coming up',
        options: {'dateFieldId': 'dueAt'},
      ),
      _richView(
        'taskChecklist',
        'checklist',
        collection,
        'Quick check-in',
        options: {
          'fieldId': 'status',
          'actionId': 'moveRecord',
          'checkedValue': 'Done',
          'uncheckedValue': 'Open',
        },
        actions: ['addRecord', 'editRecord', 'moveRecord'],
      ),
      _richView(
        'details',
        'details',
        collection,
        'Task details',
        actions: ['editRecord', 'moveRecord'],
      ),
      _richView(
        'editor',
        'form',
        collection,
        'Task editor',
        options: {
          'controls': [
            {'fieldId': 'priority', 'control': 'segmented'},
            {
              'fieldId': 'effort',
              'control': 'stepper',
              'min': 1,
              'max': 20,
              'step': 1,
            },
            {'fieldId': 'notes', 'control': 'multiline'},
          ],
        },
      ),
    ],
    pages: [
      _richPage('boardPage', 'Workspace', ['welcome', 'taskBoard']),
      _richPage('tablePage', 'Tasks', ['taskTable', 'taskChecklist']),
      _richPage('calendarPage', 'Schedule', ['taskCalendar', 'taskTimeline']),
      _richPage('detailPage', 'Task details', ['details']),
      _richPage('formPage', 'Task editor', ['editor']),
    ],
    tabs: [
      _richTab('boardPage', 'Board', 'board'),
      _richTab('tablePage', 'Tasks', 'list'),
      _richTab('calendarPage', 'Schedule', 'today'),
    ],
  );
}

AppSpec photoJournalTemplate() {
  const collection = 'memories';
  return _richTemplate(
    name: 'Photo Journal',
    theme: 'rose',
    collection: collection,
    fields: [
      _field('title', 'Title', 'text', required: true),
      _field('photo', 'Photo', 'image'),
      _field('caption', 'Caption', 'text'),
      _field('takenAt', 'Moment', 'timestamp'),
      _field('rating', 'Rating', 'integer'),
      _field('favorite', 'Favorite', 'boolean'),
    ],
    views: [
      {
        'id': 'intro',
        'type': 'richText',
        'label': 'Your journal',
        'options': {
          'markdown': '## Small moments, kept close\nCollect the places, people, and everyday details you want to remember.\n\n- Add a photo\n- Write a few words\n- Make it your own',
        },
      },
      _richView(
        'photoCards',
        'imageCards',
        collection,
        'Recent moments',
        options: {'imageFieldId': 'photo', 'captionFieldId': 'caption'},
        fields: ['takenAt', 'rating'],
      ),
      _richView(
        'photoGallery',
        'gallery',
        collection,
        'Gallery',
        options: {'imageFieldId': 'photo', 'captionFieldId': 'caption'},
      ),
      _richView('details', 'details', collection, 'Memory details'),
      _richView(
        'editor',
        'form',
        collection,
        'Add a moment',
        options: {
          'controls': [
            {'fieldId': 'photo', 'control': 'imageUpload'},
            {'fieldId': 'caption', 'control': 'multiline'},
            {'fieldId': 'rating', 'control': 'rating'},
            {'fieldId': 'favorite', 'control': 'switch'},
          ],
          'steps': [
            {
              'id': 'moment',
              'title': 'The moment',
              'fieldIds': ['title', 'photo', 'takenAt'],
            },
            {
              'id': 'story',
              'title': 'The story',
              'fieldIds': ['caption', 'rating', 'favorite'],
            },
          ],
        },
      ),
    ],
    pages: [
      _richPage('journalPage', 'Journal', ['intro', 'photoCards']),
      _richPage('galleryPage', 'Your collection', ['photoGallery']),
      _richPage('detailPage', 'Memory', ['details']),
      _richPage('formPage', 'Capture a moment', ['editor']),
    ],
    tabs: [
      _richTab('journalPage', 'Journal', 'book'),
      _richTab('galleryPage', 'Gallery', 'spark'),
    ],
  );
}

AppSpec habitTrackerTemplate() {
  const collection = 'checkins';
  return _richTemplate(
    name: 'Habit Tracker',
    theme: 'teal',
    collection: collection,
    fields: [
      _field('title', 'Activity', 'text', required: true),
      _field('loggedAt', 'Logged at', 'timestamp', required: true),
      _field('minutes', 'Minutes', 'number'),
      _field('energy', 'Energy', 'integer'),
      _field(
        'category',
        'Category',
        'choice',
        choices: ['Move', 'Learn', 'Rest'],
      ),
      _field('completed', 'Completed', 'boolean'),
      _field('notes', 'Notes', 'text'),
    ],
    views: [
      _richView(
        'minutesMetric',
        'metric',
        collection,
        'Minutes invested',
        options: {'metric': 'sum', 'valueFieldId': 'minutes', 'target': 150},
        actions: [],
      ),
      _richView(
        'dailyMinutes',
        'chart',
        collection,
        'Minutes over time',
        options: {
          'style': 'line',
          'metric': 'sum',
          'valueFieldId': 'minutes',
          'dateFieldId': 'loggedAt',
          'bucket': 'day',
          'periods': 14,
        },
        actions: [],
      ),
      _richView(
        'energyChart',
        'chart',
        collection,
        'Average energy by week',
        options: {
          'style': 'bar',
          'metric': 'average',
          'valueFieldId': 'energy',
          'dateFieldId': 'loggedAt',
          'bucket': 'week',
          'periods': 8,
        },
        actions: [],
      ),
      _richView(
        'categoryChart',
        'chart',
        collection,
        'Balance',
        group: 'category',
        options: {'style': 'donut', 'metric': 'count'},
        actions: [],
      ),
      _richView(
        'checkins',
        'checklist',
        collection,
        'Check-ins',
        options: {'fieldId': 'completed', 'actionId': 'editRecord'},
        fields: ['loggedAt', 'minutes'],
      ),
      _richView('details', 'details', collection, 'Check-in details'),
      _richView(
        'editor',
        'form',
        collection,
        'Check-in',
        options: {
          'controls': [
            {
              'fieldId': 'minutes',
              'control': 'slider',
              'min': 0,
              'max': 180,
              'step': 5,
            },
            {'fieldId': 'energy', 'control': 'rating'},
            {'fieldId': 'category', 'control': 'segmented'},
            {'fieldId': 'completed', 'control': 'checkbox'},
            {'fieldId': 'notes', 'control': 'multiline'},
          ],
        },
      ),
    ],
    pages: [
      _richPage('overviewPage', 'Your progress', [
        'minutesMetric',
        'dailyMinutes',
      ]),
      _richPage('patternsPage', 'Patterns', ['energyChart', 'categoryChart']),
      _richPage('checkinsPage', 'Daily check-ins', ['checkins']),
      _richPage('detailPage', 'Check-in details', ['details']),
      _richPage('formPage', 'Add check-in', ['editor']),
    ],
    tabs: [
      _richTab('overviewPage', 'Progress', 'chart'),
      _richTab('patternsPage', 'Patterns', 'spark'),
      _richTab('checkinsPage', 'Check-ins', 'check'),
    ],
  );
}
