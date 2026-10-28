part of '../appnest_spec.dart';

Map<String, dynamic> _field(
  String id,
  String label,
  String type, {
  bool required = false,
  List<String>? choices,
}) => {
  'id': id,
  'label': label,
  'type': type,
  'required': required,
  if (choices != null) 'choices': choices,
};
Map<String, dynamic> _action(
  String id,
  String label,
  String capability,
  String collection, {
  String? behavior,
}) => {
  'id': id,
  'label': label,
  'capability': capability,
  'collectionId': collection,
  if (behavior != null) 'behaviorId': behavior,
};

AppSpec _template(
  String name,
  String theme,
  String icon,
  String policy,
  String collection,
  String label,
  List<Map<String, dynamic>> fields,
  List<Map<String, dynamic>> behaviors,
  List<Map<String, dynamic>> actions,
  List<Map<String, dynamic>> views,
  List<Map<String, dynamic>> rules,
) {
  final required = <String>{
    'collections.v1',
    ...behaviors.map((b) => b['type'] as String),
    ...actions.map((a) => a['capability'] as String),
    ...views.map((v) => 'views.${v['type']}.v1'),
    if (rules.isNotEmpty) 'notifications.inApp.v1',
  };
  return AppSpec.parse(
    jsonEncode({
      'formatVersion': 1,
      'name': name,
      'theme': theme,
      'icon': icon,
      'requires': required.toList(),
      'collections': [
        {
          'id': collection,
          'label': label,
          'fields': fields,
          'behaviors': behaviors,
        },
      ],
      'actions': actions,
      'views': views,
      'policyPresetRequest': policy,
      'automationRequests': rules,
    }),
  );
}

Map<String, AppSpec> starterTemplates() => {
  ...utilityStarterTemplates(),
  ...richStarterTemplates(),
  'planner': dailyPlannerTemplate(),
  'reading': _template(
    'Reading Journal',
    'amber',
    'book',
    'personalTracker.v1',
    'books',
    'Books',
    [
      _field('title', 'Title', 'text', required: true),
      _field('author', 'Author', 'text'),
      _field(
        'status',
        'Status',
        'choice',
        required: true,
        choices: ['Want to read', 'Reading', 'Finished'],
      ),
      _field('rating', 'Rating', 'integer'),
      _field('notes', 'Notes', 'text'),
    ],
    [],
    [
      _action('addBook', 'Add book', 'records.create.v1', 'books'),
      _action('editBook', 'Edit book', 'records.patch.v1', 'books'),
    ],
    [
      {
        'id': 'library',
        'type': 'list',
        'collectionId': 'books',
        'label': 'Library',
        'titleFieldId': 'title',
        'actionIds': ['addBook', 'editBook'],
      },
      {
        'id': 'readingSummary',
        'type': 'summary',
        'collectionId': 'books',
        'label': 'Overview',
        'groupByFieldId': 'status',
      },
    ],
    [],
  ),
  'chores': _template(
    'Chore Board',
    'sage',
    'board',
    'groupWorkflow.v1',
    'chores',
    'Chores',
    [
      _field('title', 'Chore', 'text', required: true),
      _field('assignee', 'Assigned to', 'member'),
      _field('dueAt', 'Due date', 'timestamp'),
      _field(
        'status',
        'Status',
        'choice',
        required: true,
        choices: ['Open', 'Doing', 'Done'],
      ),
      _field('notes', 'Notes', 'text'),
    ],
    [
      {
        'id': 'progress',
        'type': 'workflow.v1',
        'fieldId': 'status',
        'transitions': {
          'Open': ['Doing'],
          'Doing': ['Open', 'Done'],
          'Done': ['Open'],
        },
      },
      {'id': 'assignment', 'type': 'assignment.v1', 'fieldId': 'assignee'},
    ],
    [
      _action('addChore', 'Add chore', 'records.create.v1', 'chores'),
      _action('editChore', 'Edit notes', 'records.patch.v1', 'chores'),
      _action(
        'assignChore',
        'Assign',
        'assignment.assign.v1',
        'chores',
        behavior: 'assignment',
      ),
      _action(
        'moveChore',
        'Change status',
        'workflow.transition.v1',
        'chores',
        behavior: 'progress',
      ),
    ],
    [
      {
        'id': 'board',
        'type': 'board',
        'collectionId': 'chores',
        'label': 'Board',
        'titleFieldId': 'title',
        'groupByFieldId': 'status',
        'actionIds': ['addChore', 'editChore', 'assignChore', 'moveChore'],
      },
      {
        'id': 'allChores',
        'type': 'list',
        'collectionId': 'chores',
        'label': 'All chores',
        'titleFieldId': 'title',
        'actionIds': ['addChore', 'editChore', 'assignChore', 'moveChore'],
      },
    ],
    [
      {
        'id': 'dueReminder',
        'trigger': {
          'type': 'beforeTimestamp',
          'collectionId': 'chores',
          'fieldId': 'dueAt',
          'offsetSeconds': 3600,
        },
        'effect': {'type': 'notifyAssignee', 'channel': 'inApp'},
      },
    ],
  ),
  'volunteer': _template(
    'Volunteer Shifts',
    'teal',
    'people',
    'groupCapacitySignup.v1',
    'shifts',
    'Shifts',
    [
      _field('title', 'Shift', 'text', required: true),
      _field('startsAt', 'Starts', 'timestamp', required: true),
      _field('notes', 'Preparation notes', 'text'),
    ],
    [
      {'id': 'places', 'type': 'capacity.v1'},
    ],
    [
      _action('addShift', 'Create shift', 'records.create.v1', 'shifts'),
      _action('editShift', 'Edit shift', 'records.patch.v1', 'shifts'),
      _action(
        'configure',
        'Set capacity',
        'capacity.configure.v1',
        'shifts',
        behavior: 'places',
      ),
      _action(
        'join',
        'Join shift',
        'capacity.claim.v1',
        'shifts',
        behavior: 'places',
      ),
      _action(
        'leave',
        'Cancel sign-up',
        'capacity.release.v1',
        'shifts',
        behavior: 'places',
      ),
    ],
    [
      {
        'id': 'allShifts',
        'type': 'list',
        'collectionId': 'shifts',
        'label': 'Shifts',
        'titleFieldId': 'title',
        'actionIds': ['addShift', 'editShift', 'join', 'leave', 'configure'],
      },
      {
        'id': 'placesSummary',
        'type': 'capacity',
        'collectionId': 'shifts',
        'label': 'Places',
        'titleFieldId': 'title',
        'actionIds': ['join', 'leave'],
      },
    ],
    [
      {
        'id': 'shiftReminder',
        'trigger': {
          'type': 'beforeTimestamp',
          'collectionId': 'shifts',
          'fieldId': 'startsAt',
          'offsetSeconds': 3600,
        },
        'effect': {'type': 'notifyActiveClaimants', 'channel': 'inApp'},
      },
    ],
  ),
};

AppSpec dailyPlannerTemplate() => AppSpec.parse(
  jsonEncode({
    'formatVersion': 1,
    'name': 'Daily Planner',
    'theme': 'blue',
    'icon': 'check',
    'policyPresetRequest': 'personalTracker.v1',
    'requires': [
      'collections.v1',
      'workflow.v1',
      'records.create.v1',
      'records.patch.v1',
      'workflow.transition.v1',
      'views.list.v1',
      'views.summary.v1',
      'views.details.v1',
      'views.form.v1',
      'navigation.v1',
      'views.configured.v1',
      'notifications.inApp.v1',
      'notifications.owner.v1',
      'automations.conditions.v1',
    ],
    'collections': [
      {
        'id': 'tasks',
        'label': 'Tasks',
        'fields': [
          _field('title', 'Task', 'text', required: true),
          _field(
            'status',
            'Status',
            'choice',
            required: true,
            choices: ['Open', 'Done'],
          ),
          _field(
            'priority',
            'Priority',
            'choice',
            choices: ['Low', 'Normal', 'High'],
          ),
          _field('notes', 'Notes', 'text'),
          _field('dueAt', 'Due', 'timestamp'),
          _field('reminderAt', 'Remind me', 'timestamp'),
        ],
        'behaviors': [
          {
            'id': 'taskProgress',
            'type': 'workflow.v1',
            'fieldId': 'status',
            'transitions': {
              'Open': ['Done'],
              'Done': ['Open'],
            },
          },
        ],
      },
    ],
    'actions': [
      _action('addTask', 'Add task', 'records.create.v1', 'tasks'),
      _action('editTask', 'Edit task', 'records.patch.v1', 'tasks'),
      _action(
        'moveTask',
        'Complete or reopen',
        'workflow.transition.v1',
        'tasks',
        behavior: 'taskProgress',
      ),
    ],
    'views': [
      {
        'id': 'todaySummary',
        'type': 'summary',
        'collectionId': 'tasks',
        'label': 'Today at a glance',
        'groupByFieldId': 'status',
        'dateFilter': {'fieldId': 'dueAt', 'period': 'today'},
      },
      {
        'id': 'todayTasks',
        'type': 'list',
        'collectionId': 'tasks',
        'label': 'Scheduled today',
        'titleFieldId': 'title',
        'presentation': 'compact',
        'fieldIds': ['status', 'priority', 'dueAt'],
        'dateFilter': {'fieldId': 'dueAt', 'period': 'today'},
        'query': {
          'sort': [
            {'fieldId': 'dueAt', 'descending': false},
          ],
          'limit': 25,
        },
        'actionIds': ['addTask', 'editTask', 'moveTask'],
        'detailPageId': 'taskDetailPage',
        'formPageId': 'taskEditorPage',
      },
      {
        'id': 'overdueTasks',
        'type': 'list',
        'collectionId': 'tasks',
        'label': 'Overdue',
        'titleFieldId': 'title',
        'presentation': 'compact',
        'fieldIds': ['priority', 'dueAt'],
        'dateFilter': {'fieldId': 'dueAt', 'period': 'overdue'},
        'query': {
          'filters': [
            {'fieldId': 'status', 'operator': 'eq', 'value': 'Open'},
          ],
          'sort': [
            {'fieldId': 'dueAt', 'descending': false},
          ],
          'limit': 25,
        },
        'actionIds': ['editTask', 'moveTask'],
        'detailPageId': 'taskDetailPage',
        'formPageId': 'taskEditorPage',
      },
      {
        'id': 'allTasks',
        'type': 'list',
        'collectionId': 'tasks',
        'label': 'All tasks',
        'titleFieldId': 'title',
        'presentation': 'cards',
        'fieldIds': ['status', 'priority', 'dueAt'],
        'filterFieldIds': ['status', 'priority'],
        'query': {
          'sort': [
            {'fieldId': 'dueAt', 'descending': false},
          ],
          'limit': 25,
        },
        'actionIds': ['addTask', 'editTask', 'moveTask'],
        'detailPageId': 'taskDetailPage',
        'formPageId': 'taskEditorPage',
      },
      {
        'id': 'todayProgress',
        'type': 'summary',
        'collectionId': 'tasks',
        'label': 'Today’s scheduled tasks',
        'groupByFieldId': 'status',
        'dateFilter': {'fieldId': 'dueAt', 'period': 'today'},
      },
      {
        'id': 'allProgress',
        'type': 'summary',
        'collectionId': 'tasks',
        'label': 'All tasks',
        'groupByFieldId': 'status',
      },
      {
        'id': 'taskDetails',
        'type': 'details',
        'collectionId': 'tasks',
        'label': 'Task details',
        'titleFieldId': 'title',
        'fieldIds': ['status', 'priority', 'notes', 'dueAt', 'reminderAt'],
        'actionIds': ['editTask', 'moveTask'],
        'formPageId': 'taskEditorPage',
      },
      {
        'id': 'taskEditor',
        'type': 'form',
        'collectionId': 'tasks',
        'label': 'Task editor',
        'titleFieldId': 'title',
        'fieldIds': ['title', 'priority', 'notes', 'dueAt', 'reminderAt'],
        'actionIds': ['addTask', 'editTask'],
      },
    ],
    'navigation': {
      'entryPageId': 'todayPage',
      'pages': [
        {
          'id': 'todayPage',
          'title': 'Today',
          'showDate': true,
          'viewIds': ['todaySummary', 'todayTasks', 'overdueTasks'],
          'primaryActionId': 'addTask',
        },
        {
          'id': 'tasksPage',
          'title': 'Tasks',
          'viewIds': ['allTasks'],
          'primaryActionId': 'addTask',
        },
        {
          'id': 'progressPage',
          'title': 'Progress',
          'viewIds': ['todayProgress', 'allProgress'],
        },
        {
          'id': 'taskDetailPage',
          'title': 'Task details',
          'viewIds': ['taskDetails'],
        },
        {
          'id': 'taskEditorPage',
          'title': 'Task editor',
          'viewIds': ['taskEditor'],
        },
      ],
      'tabs': [
        {'pageId': 'todayPage', 'label': 'Today', 'icon': 'today'},
        {'pageId': 'tasksPage', 'label': 'Tasks', 'icon': 'list'},
        {'pageId': 'progressPage', 'label': 'Progress', 'icon': 'chart'},
      ],
    },
    'automationRequests': [
      {
        'id': 'taskReminder',
        'trigger': {
          'type': 'beforeTimestamp',
          'collectionId': 'tasks',
          'fieldId': 'reminderAt',
          'offsetSeconds': 0,
        },
        'effect': {'type': 'notifyOwner', 'channel': 'inApp'},
        'condition': {'fieldId': 'status', 'value': 'Open'},
      },
    ],
  }),
);

Object _syntheticValue(FieldSpec field, int index) => switch (field.type) {
  FieldType.text =>
    field.id == 'title'
        ? [
            'Community morning',
            'A small beginning',
            'Make room for good',
          ][index % 3]
        : 'Example ${field.label.toLowerCase()}',
  FieldType.integer => index + 1,
  FieldType.number => (index + 1) * 1.5,
  FieldType.boolean => index.isEven,
  FieldType.choice => field.choices[index % field.choices.length],
  FieldType.timestamp => DateTime.utc(2030, 1, 5 + index, 10).toIso8601String(),
  FieldType.member => 'preview_member',
  FieldType.image => 'preview_image_${index % 3}',
};

List<Map<String, dynamic>> syntheticRecords(CollectionSpec c, {DateTime? now}) {
  if (c.id == 'tasks' &&
      c.fields.any((f) => f.id == 'reminderAt') &&
      c.fields.any(
        (f) =>
            f.id == 'status' &&
            f.choices.contains('Open') &&
            f.choices.contains('Done'),
      )) {
    final local = (now ?? DateTime.now()).toLocal();
    String at(int day, int hour) => DateTime(
      local.year,
      local.month,
      local.day + day,
      hour,
    ).toUtc().toIso8601String();
    final examples = [
      {
        'title': 'Plan the day',
        'status': 'Done',
        'priority': 'Normal',
        'notes': 'Choose a few things that matter.',
        'dueAt': at(0, 9),
      },
      {
        'title': 'Make time for a walk',
        'status': 'Open',
        'priority': 'High',
        'notes': 'A short break outdoors.',
        'dueAt': at(0, 17),
      },
      {
        'title': 'Finish yesterday’s notes',
        'status': 'Open',
        'priority': 'Normal',
        'dueAt': at(-1, 16),
      },
      {'title': 'An idea for later', 'status': 'Open', 'priority': 'Low'},
    ];
    return examples.indexed.map((entry) {
      final data = <String, dynamic>{};
      for (final field in c.fields) {
        if (entry.$2.containsKey(field.id)) {
          try {
            data[field.id] = field.normalize(entry.$2[field.id]);
          } on SpecException {
            data[field.id] = _syntheticValue(field, entry.$1);
          }
        } else if (field.required) {
          data[field.id] = _syntheticValue(field, entry.$1);
        }
      }
      return c.normalizeRecord(data);
    }).toList();
  }
  if ({'projects', 'memories', 'checkins', 'events'}.contains(c.id)) {
    final local = (now ?? DateTime.now()).toLocal();
    final count = c.id == 'checkins' ? 14 : 6;
    return List.generate(count, (i) {
      final data = <String, dynamic>{};
      for (final field in c.fields) {
        var value = _syntheticValue(field, i);
        if (field.type == FieldType.timestamp) {
          value = DateTime(
            local.year,
            local.month,
            local.day + (c.id == 'projects' ? i - 1 : -i),
            10,
          ).toUtc().toIso8601String();
        } else if (field.type == FieldType.integer &&
            {'rating', 'energy'}.contains(field.id)) {
          value = i % 5 + 1;
        } else if (field.type == FieldType.number && field.id == 'minutes') {
          value = [20, 35, 45, 15, 60, 30, 25][i % 7];
        }
        data[field.id] = field.normalize(value);
      }
      return c.normalizeRecord(data);
    });
  }
  return List.generate(
    3,
    (i) => {for (final field in c.fields) field.id: _syntheticValue(field, i)},
  );
}
