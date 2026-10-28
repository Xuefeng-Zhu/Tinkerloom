import 'dart:convert';
import 'dart:io';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

AppSpec changedPlanner(void Function(Map<String, dynamic>) change) {
  final json = dailyPlannerTemplate().toJson();
  change(json);
  return AppSpec.parse(jsonEncode(json));
}

void main() {
  test('legacy canonical hashes and omitted additions stay unchanged', () {
    const hashes = {
      'reading':
          '088381c74ddad7c22e34784f621c38e74b967f8c78657ce8302c4fb72e786706',
      'chores':
          '2992181af41ad84ff7ccdb6a3335a0d738743f88ae956d0f72a980fb36252d70',
      'volunteer':
          '1955dfd39f12d4c307e67a31cc3fe2bd4c18c619203e69878e72b00ecb737599',
    };
    for (final entry in hashes.entries) {
      final template = starterTemplates()[entry.key]!;
      expect(template.hash, entry.value);
      expect(
        AppSpec.parse(File('fixtures/${entry.key}.json').readAsStringSync())
            .hash,
        entry.value,
      );
      expect(template.toJson().containsKey('navigation'), false);
      expect(template.views.first.toJson().containsKey('fieldIds'), false);
      expect(
        template.automationRequests.every(
          (r) => !r.toJson().containsKey('condition'),
        ),
        true,
      );
    }
  });
  test('only optional equality filters accept null', () {
    final collection = dailyPlannerTemplate().collection('tasks');
    for (final operator in ['gte', 'lte', 'lt', 'contains', 'in']) {
      final fieldId = operator == 'contains' ? 'notes' : 'dueAt';
      expect(
        () => RecordQuery.parse(collection, {
          'filters': [
            {
              'fieldId': fieldId,
              'operator': operator,
              'value': operator == 'in' ? [null] : null,
            },
          ],
        }),
        throwsA(isA<SpecException>()),
      );
    }
    expect(
      RecordQuery.parse(collection, {
        'filters': [
          {'fieldId': 'dueAt', 'operator': 'eq', 'value': null},
        ],
      }).filters.single['value'],
      isNull,
    );
    expect(
      () => RecordQuery.parse(collection, {
        'filters': [
          {'fieldId': 'title', 'operator': 'eq', 'value': null},
        ],
      }),
      throwsA(isA<SpecException>()),
    );
  });
  test(
    'configured views reserve query space for search and all choice filters',
    () {
      final valid = changedPlanner(
        (j) => j['views'][3]['query']['filters'] = List.generate(
          5,
          (_) => {'fieldId': 'status', 'operator': 'eq', 'value': 'Open'},
        ),
      );
      expect(valid.view('allTasks').filterFieldIds.length, 2);
      expect(
        () => changedPlanner(
          (j) => j['views'][3]['query']['filters'] = List.generate(
            6,
            (_) => {'fieldId': 'status', 'operator': 'eq', 'value': 'Open'},
          ),
        ),
        throwsA(isA<SpecException>()),
      );
      expect(
        () => changedPlanner((j) => j['views'][3]['titleFieldId'] = 'priority'),
        throwsA(isA<SpecException>()),
      );
      final query = resolveViewQuery(valid, valid.view('allTasks'));
      final allControls = RecordQuery.parse(valid.collection('tasks'), {
        ...query,
        'filters': [
          ...query['filters'] as List,
          {'fieldId': 'title', 'operator': 'contains', 'value': 'plan'},
          {'fieldId': 'status', 'operator': 'eq', 'value': 'Open'},
          {'fieldId': 'priority', 'operator': 'eq', 'value': 'High'},
        ],
      });
      expect(allControls.filters.length, Limits.filters);
    },
  );
  test(
    'an atomic AI page patch creates and reaches server-allocated views',
    () {
      final legacy = starterTemplates()['reading']!;
      final originalHash = legacy.hash;
      var counter = 0;
      final result = legacy.patch({
        'type': 'AddPage',
        'page': {
          'title': 'Reading home',
          'viewIds': ['readingSummary'],
        },
        'newViews': [
          {
            'type': 'list',
            'collectionId': 'books',
            'label': 'Books',
            'titleFieldId': 'title',
            'presentation': 'cards',
          },
        ],
        'tab': {'label': 'Home', 'icon': 'book'},
      }, () => 'allocated${++counter}');
      final page = result.page('allocated1');
      expect(page.viewIds, ['readingSummary', 'allocated2']);
      expect(result.view('allocated2').presentation, 'cards');
      expect(result.navigation!.entryPageId, page.id);
      expect(result.navigation!.tabs.single.pageId, page.id);
      expect(result.navigation!.tabs.single.label, 'Home');
      expect(
        result.requires,
        containsAll(['navigation.v1', 'views.configured.v1']),
      );
      expect(legacy.hash, originalHash);
      final second = result.patch({
        'type': 'AddPage',
        'page': {'title': 'New summary'},
        'newViews': [
          {
            'type': 'summary',
            'collectionId': 'books',
            'label': 'Summary',
            'groupByFieldId': 'status',
          },
        ],
        'tab': {'label': 'Summary', 'icon': 'chart'},
      }, () => 'allocated${++counter}');
      expect(second.page('allocated3').viewIds, ['allocated4']);
      expect(second.navigation!.tabs.last.pageId, 'allocated3');
    },
  );
  test(
    'atomic page additions reject untrusted identities and combined bounds',
    () {
      final spec = dailyPlannerTemplate();
      for (final patch in [
        {
          'type': 'AddPage',
          'page': {'title': 'Empty'},
          'newViews': [],
        },
        {
          'type': 'AddPage',
          'page': {'title': 'New'},
          'newViews': [
            {'id': 'untrusted', 'type': 'list', 'collectionId': 'tasks'},
          ],
        },
        {
          'type': 'AddPage',
          'page': {
            'title': 'New',
            'viewIds': ['allTasks'],
          },
          'tab': {'pageId': 'todayPage', 'label': 'Hijack', 'icon': 'list'},
        },
        {
          'type': 'AddPage',
          'page': {
            'title': 'New',
            'viewIds': ['allTasks'],
          },
          'newViews': List.generate(
            8,
            (_) => {'type': 'summary', 'collectionId': 'tasks'},
          ),
        },
        {
          'type': 'AddPage',
          'page': {
            'title': 'New',
            'viewIds': ['allTasks', 'allTasks'],
          },
        },
      ]) {
        var counter = 0;
        expect(
          () => spec.patch(patch, () => 'newId${++counter}'),
          throwsA(isA<SpecException>()),
        );
      }
    },
  );
  test('rich create forms include required inputs and may omit initialized workflow fields', () {
    expect(
      () => changedPlanner((j) => j['views'][7]['fieldIds'] = ['notes']),
      throwsA(isA<SpecException>()),
    );
    final allFields = changedPlanner((j) => j['views'][7]['fieldIds'] = []);
    expect(allFields.view('taskEditor').fieldIds, isEmpty);
    expect(
      dailyPlannerTemplate().view('taskEditor').fieldIds,
      isNot(contains('status')),
    );
    expect(
      () => changedPlanner((j) {
        j['collections'][0]['fields'].add({
          'id': 'assignee',
          'label': 'Assignee',
          'type': 'member',
          'required': true,
        });
        j['collections'][0]['behaviors'].add({
          'id': 'assignment',
          'type': 'assignment.v1',
          'fieldId': 'assignee',
        });
        j['requires'].add('assignment.v1');
      }),
      throwsA(isA<SpecException>()),
    );
  });
  test('form destinations support all routed create and edit capabilities', () {
    expect(
      () => changedPlanner((j) => j['views'][7]['actionIds'] = ['addTask']),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => changedPlanner((j) => j['views'][7]['actionIds'] = ['editTask']),
      throwsA(isA<SpecException>()),
    );
    final aliases = changedPlanner((j) {
      j['actions'].add({
        'id': 'createAlias',
        'label': 'Create task',
        'capability': 'records.create.v1',
        'collectionId': 'tasks',
      });
      j['actions'].add({
        'id': 'editAlias',
        'label': 'Save task',
        'capability': 'records.patch.v1',
        'collectionId': 'tasks',
      });
      j['views'][7]['actionIds'] = ['createAlias', 'editAlias'];
    });
    expect(aliases.page('todayPage').primaryActionId, 'addTask');
    expect(aliases.view('taskEditor').actionIds, ['createAlias', 'editAlias']);
    final createOnly = changedPlanner((j) {
      for (final view in j['views']) {
        if (view['formPageId'] != null)
          view['actionIds'] = (view['actionIds'] as List)
              .where((id) => id != 'editTask')
              .toList();
      }
      j['views'][7]['actionIds'] = ['addTask'];
    });
    expect(createOnly.view('taskEditor').actionIds, ['addTask']);
  });
  test('legacy forms keep their previous field presentation validation', () {
    final json = starterTemplates()['reading']!.toJson();
    json['views'].add({
      'id': 'legacyForm',
      'label': 'Add book',
      'type': 'form',
      'collectionId': 'books',
      'fieldIds': ['notes'],
      'actionIds': ['addBook'],
    });
    json['requires'].addAll(['views.form.v1', 'views.configured.v1']);
    expect(AppSpec.parse(jsonEncode(json)).view('legacyForm').fieldIds, [
      'notes',
    ]);
  });
  test('legacy summary group types remain parseable', () {
    final old = starterTemplates()['reading']!.toJson();
    old['views'][1]['groupByFieldId'] = 'rating';
    final spec = AppSpec.parse(jsonEncode(old));
    expect(spec.navigation, isNull);
    expect(spec.view('readingSummary').groupByFieldId, 'rating');
  });
  test(
    'synthetic planner records survive custom required fields and choices',
    () {
      final changed = changedPlanner((j) {
        j['collections'][0]['fields'].add({
          'id': 'location',
          'label': 'Location',
          'type': 'text',
          'required': true,
        });
        j['views'][7]['fieldIds'].add('location');
        j['collections'][0]['fields'][2]['choices'] = ['Urgent', 'Later'];
      });
      final records = syntheticRecords(changed.collection('tasks'));
      expect(records.length, 4);
      expect(records.every((r) => r['location'] is String), true);
      expect(
        records.every((r) => ['Urgent', 'Later'].contains(r['priority'])),
        true,
      );
    },
  );
  test('planner binds ordinary collections, reversible workflow, tabs and owner reminders', () {
    final spec = starterTemplates()['planner']!;
    expect(spec.navigation!.tabs.map((t) => t.label), [
      'Today',
      'Tasks',
      'Progress',
    ]);
    expect(spec.navigation!.pages.length, 5);
    expect(spec.collection('tasks').behavior('taskProgress').transitions, {
      'Open': ['Done'],
      'Done': ['Open'],
    });
    expect(spec.automationRequests.single.fieldId, 'reminderAt');
    expect(spec.automationRequests.single.effect, 'notifyOwner');
    expect(spec.automationRequests.single.condition!.toJson(), {
      'fieldId': 'status',
      'value': 'Open',
    });
    expect(spec.collection('tasks').field('dueAt').required, false);
    expect(spec.collection('tasks').field('reminderAt').required, false);
    expect(AppSpec.parse(spec.canonical).hash, spec.hash);
  });
  test('new behavior requires each capability', () {
    for (final capability in [
      'navigation.v1',
      'views.configured.v1',
      'notifications.owner.v1',
      'automations.conditions.v1',
    ]) {
      expect(
        () => changedPlanner((j) => (j['requires'] as List).remove(capability)),
        throwsA(isA<SpecException>()),
      );
    }
  });
  test('primary action errors name the missing action binding', () {
    expect(
      () => changedPlanner((j) {
        final page = (j['navigation']['pages'] as List).first as Map;
        for (final view in j['views'] as List) {
          if ((page['viewIds'] as List).contains(view['id'])) {
            view['actionIds'] = <String>[];
          }
        }
      }),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'actionable primary action diagnostic',
          allOf(
            contains('Page todayPage primaryActionId addTask'),
            contains('Include addTask in actionIds'),
            contains('formPageId'),
          ),
        ),
      ),
    );
  });
  test(
    'navigation rejects invalid references, record pages and query bindings',
    () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (j) => j['navigation']['entryPageId'] = 'missing',
        (j) => j['navigation']['tabs'][0]['pageId'] = 'missing',
        (j) => j['navigation']['tabs'][0]['icon'] = 'customScript',
        (j) => j['navigation']['pages'][0]['viewIds'] = ['missing'],
        (j) => j['navigation']['pages'][0]['viewIds'] = [
          'todayTasks',
          'todayTasks',
        ],
        (j) => j['navigation']['pages'][0]['primaryActionId'] = 'moveTask',
        (j) => j['navigation']['pages'][0]['primaryActionId'] = 'missing',
        (j) => j['navigation']['pages'][0]['showDate'] = 'yes',
        (j) => j['navigation']['tabs'] = [],
        (j) => j['navigation']['tabs'].add({
          'pageId': 'taskDetailPage',
          'label': 'Details',
          'icon': 'list',
        }),
        (j) => j['navigation']['pages'][3]['viewIds'] = [
          'taskDetails',
          'allTasks',
        ],
        (j) => j['views'][1]['detailPageId'] = 'taskEditorPage',
        (j) => j['views'][1]['formPageId'] = 'taskDetailPage',
        (j) => j['views'][1]['fieldIds'] = ['missing'],
        (j) => j['views'][1]['filterFieldIds'] = ['notes'],
        (j) => j['views'][1]['dateFilter']['fieldId'] = 'priority',
        (j) => j['views'][1]['dateFilter']['period'] = 'arbitrary',
        (j) => j['views'][1]['query']['cursor'] = 'transient',
        (j) => j['views'][1]['query']['limit'] = 101,
        (j) => j['views'][1]['query']['filters'] = List.generate(
          7,
          (_) => {'fieldId': 'status', 'operator': 'eq', 'value': 'Open'},
        ),
        (j) => j['views'][0]['groupByFieldId'] = 'notes',
        (j) => j['policyPresetRequest'] = 'groupWorkflow.v1',
        (j) => j['automationRequests'][0]['condition']['fieldId'] = 'notes',
        (j) => j['automationRequests'][0]['condition']['value'] = 'Doing',
        (j) => j['automationRequests'][0]['condition']['operator'] = 'script',
        (j) => j['automationRequests'][0]['effect']['channel'] = 'email',
      ]) {
        expect(() => changedPlanner(change), throwsA(isA<SpecException>()));
      }
    },
  );
  test('pages tabs and sections are bounded', () {
    expect(
      () => changedPlanner(
        (j) => j['navigation']['pages'] = List.generate(
          17,
          (i) => {
            'id': 'page$i',
            'title': 'Page $i',
            'viewIds': ['allTasks'],
          },
        ),
      ),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => changedPlanner(
        (j) => j['navigation']['tabs'] = List.generate(
          6,
          (i) => {'pageId': 'page$i', 'label': 'Page $i', 'icon': 'list'},
        ),
      ),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => changedPlanner(
        (j) =>
            j['navigation']['pages'][0]['viewIds'] = List.filled(9, 'allTasks'),
      ),
      throwsA(isA<SpecException>()),
    );
  });
  test('semantic pages attach generated views sequentially on legacy apps', () {
    final legacy = starterTemplates()['reading']!;
    final oldHash = legacy.hash;
    var spec = legacy.patch({
      'type': 'AddView',
      'view': {
        'type': 'list',
        'collectionId': 'books',
        'label': 'Reading',
        'titleFieldId': 'title',
        'presentation': 'compact',
      },
    }, () => 'newList');
    spec = spec.patch({
      'type': 'AddPage',
      'page': {
        'title': 'Library',
        'viewIds': ['newList'],
      },
    }, () => 'libraryPage');
    expect(spec.navigation!.entryPageId, 'libraryPage');
    expect(spec.navigation!.tabs.single.pageId, 'libraryPage');
    expect(
      spec.requires,
      containsAll(['navigation.v1', 'views.configured.v1']),
    );
    spec = spec.patch({
      'type': 'AddPage',
      'page': {
        'title': 'Progress',
        'viewIds': ['readingSummary'],
      },
    }, () => 'progressPage');
    spec = spec.patch({
      'type': 'SetNavigation',
      'entryPageId': 'libraryPage',
      'tabs': [
        {'pageId': 'libraryPage', 'label': 'Library', 'icon': 'book'},
        {'pageId': 'progressPage', 'label': 'Progress', 'icon': 'chart'},
      ],
    }, () => 'unused');
    spec = spec.patch({
      'type': 'ReorderPages',
      'pageIds': ['progressPage', 'libraryPage'],
    }, () => 'unused');
    spec = spec.patch({
      'type': 'UpdatePage',
      'pageId': 'libraryPage',
      'page': {
        'title': 'My library',
        'viewIds': ['newList', 'readingSummary'],
        'showDate': true,
      },
    }, () => 'unused');
    spec = spec.patch({
      'type': 'RenameLabel',
      'targetId': 'progressPage',
      'label': 'Reading progress',
    }, () => 'unused');
    expect(spec.navigation!.pages.first.id, 'progressPage');
    expect(spec.page('libraryPage').showDate, true);
    expect(spec.page('progressPage').title, 'Reading progress');
    expect(legacy.compatibilityErrors(spec), isEmpty);
    expect(
      spec.collection('books').toJson(),
      legacy.collection('books').toJson(),
    );
    expect(legacy.hash, oldHash);
    expect(spec.diff(legacy), contains('Update pages or tab navigation'));
  });
  test('view and theme edits preserve identity with reviewable diffs', () {
    final old = dailyPlannerTemplate();
    final view = old.view('allTasks').toJson()..remove('id');
    view['presentation'] = 'compact';
    var next = old.patch({
      'type': 'UpdateView',
      'viewId': 'allTasks',
      'view': view,
    }, () => throw StateError('No allocation'));
    next = next.patch({
      'type': 'SetTheme',
      'theme': 'sage',
      'icon': 'spark',
    }, () => throw StateError('No allocation'));
    expect(next.view('allTasks').presentation, 'compact');
    expect(next.theme, 'sage');
    expect(
      next.diff(old),
      containsAll(['Update views or view order', 'Update app theme or icon']),
    );
    expect(old.compatibilityErrors(next), isEmpty);
    expect(
      () => next.patch({
        'type': 'UpdatePage',
        'pageId': 'tasksPage',
        'page': {
          'id': 'hijack',
          'title': 'Tasks',
          'viewIds': ['allTasks'],
        },
      }, () => 'unused'),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => next.patch({
        'type': 'ReorderPages',
        'pageIds': ['tasksPage'],
      }, () => 'unused'),
      throwsA(isA<SpecException>()),
    );
  });
  test(
    'local day boundaries are exclusive and survive daylight-saving changes',
    () {
      final spec = dailyPlannerTemplate();
      for (final now in [
        DateTime(2026, 3, 8, 12),
        DateTime(2026, 11, 1, 12),
        DateTime(2026, 9, 22, 23, 59),
      ]) {
        final filters =
            resolveViewQuery(spec, spec.view('todayTasks'), now: now)['filters']
                as List;
        expect(filters[0]['operator'], 'gte');
        expect(filters[1]['operator'], 'lt');
        final start = DateTime.parse(filters[0]['value']);
        final end = DateTime.parse(filters[1]['value']);
        expect(start, DateTime(now.year, now.month, now.day).toUtc());
        expect(end, DateTime(now.year, now.month, now.day + 1).toUtc());
        if (Platform.environment['TZ'] == 'America/Los_Angeles') {
          if (now.month == 3) expect(end.difference(start).inHours, 23);
          if (now.month == 11) expect(end.difference(start).inHours, 25);
        }
        final overdue =
            resolveViewQuery(
                  spec,
                  spec.view('overdueTasks'),
                  now: now,
                )['filters']
                as List;
        expect(
          overdue,
          contains(
            equals({
              'fieldId': 'dueAt',
              'operator': 'lt',
              'value': start.toIso8601String(),
            }),
          ),
        );
        expect(
          overdue,
          contains(
            equals({'fieldId': 'status', 'operator': 'eq', 'value': 'Open'}),
          ),
        );
      }
    },
  );
  test(
    'range and membership timestamps normalize without changing caller data',
    () {
      final col = dailyPlannerTemplate().collection('tasks');
      final source = {
        'filters': [
          {
            'fieldId': 'dueAt',
            'operator': 'lt',
            'value': '2026-09-23T00:00:00-07:00',
          },
          {
            'fieldId': 'dueAt',
            'operator': 'in',
            'value': ['2026-09-22T00:00:00-07:00'],
          },
        ],
      };
      final query = RecordQuery.parse(col, source);
      expect(query.filters[0]['value'], '2026-09-23T07:00:00.000Z');
      expect(query.filters[1]['value'], ['2026-09-22T07:00:00.000Z']);
      expect(source['filters']!.first['value'], '2026-09-23T00:00:00-07:00');
      expect(
        () => RecordQuery.parse(col, {
          'filters': [
            {'fieldId': 'title', 'operator': 'lt', 'value': 'x'},
          ],
        }),
        throwsA(isA<SpecException>()),
      );
    },
  );
  test('synthetic planner data has today, overdue and undated records with reminders off', () {
    final now = DateTime(2026, 9, 22, 12);
    final records = syntheticRecords(
      dailyPlannerTemplate().collection('tasks'),
      now: now,
    );
    final today = records.where(
      (r) =>
          r['dueAt'] != null &&
          DateTime.parse(r['dueAt'] as String).toLocal().day == now.day,
    );
    expect(today.length, 2);
    expect(records.any((r) => r['dueAt'] == null), true);
    expect(records.every((r) => r['reminderAt'] == null), true);
    expect(
      records.any(
        (r) =>
            r['dueAt'] != null &&
            DateTime.parse(r['dueAt'] as String).toLocal().day < now.day &&
            r['status'] == 'Open',
      ),
      true,
    );
  });
}
