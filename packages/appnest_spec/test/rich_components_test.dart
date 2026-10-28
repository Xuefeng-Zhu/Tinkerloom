import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

AppSpec mutate(
  AppSpec spec,
  String viewId,
  void Function(Map<String, dynamic>) change,
) {
  final json = jsonDecode(spec.canonical) as Map<String, dynamic>;
  final view = (json['views'] as List).cast<Map<String, dynamic>>().firstWhere(
    (v) => v['id'] == viewId,
  );
  change(view);
  return AppSpec.parse(jsonEncode(json));
}

void main() {
  final projects = projectHubTemplate();
  final journal = photoJournalTemplate();
  final habits = habitTrackerTemplate();
  final invalid = throwsA(isA<SpecException>());

  test(
    'all rich capabilities are represented by usable round-trip templates',
    () {
      final templates = {
        ...richStarterTemplates(),
        ...utilityStarterTemplates(),
      };
      expect(templates.length, 8);
      final types = <String>{};
      for (final spec in templates.values) {
        expect(AppSpec.parse(spec.canonical).canonical, spec.canonical);
        types.addAll(spec.views.map((v) => v.type));
        expect(spec.navigation, isNotNull);
        expect(spec.navigation!.tabs.length, lessThanOrEqualTo(5));
        for (final col in spec.collections) {
          for (final sample in syntheticRecords(col)) {
            expect(col.normalizeRecord(sample), sample);
          }
        }
      }
      expect(types, containsAll(richViewTypes));
    },
  );

  test(
    'rich sample dates remain useful with a deterministic preview clock',
    () {
      final now = DateTime(2026, 9, 23, 12);
      final samples = syntheticRecords(habits.collection('checkins'), now: now);
      expect(samples.length, 14);
      expect(
        DateTime.parse(samples.first['loggedAt'] as String).toLocal().day,
        now.day,
      );
      expect(samples.map((r) => r['minutes']).toSet().length, greaterThan(1));
      expect(
        samples.every(
          (r) => (r['energy'] as int) >= 1 && (r['energy'] as int) <= 5,
        ),
        isTrue,
      );
    },
  );

  test('new capabilities require explicit capability declarations', () {
    for (final spec in [projects, journal, habits]) {
      final json = jsonDecode(spec.canonical) as Map<String, dynamic>;
      (json['requires'] as List).removeWhere(
        (v) => v == 'views.interactive.v1',
      );
      expect(() => AppSpec.parse(jsonEncode(json)), invalid);
    }
    final json = jsonDecode(journal.canonical) as Map<String, dynamic>;
    (json['requires'] as List).remove('fields.image.v1');
    expect(() => AppSpec.parse(jsonEncode(json)), invalid);
  });

  test('rich views require navigation without rewriting legacy options', () {
    final json = (jsonDecode(projects.canonical) as Map<String, dynamic>)
      ..remove('navigation');
    expect(() => AppSpec.parse(jsonEncode(json)), invalid);
    final old = starterTemplates()['reading']!;
    expect(old.views.every((v) => !v.toJson().containsKey('options')), isTrue);
    expect(
      old.hash,
      '088381c74ddad7c22e34784f621c38e74b967f8c78657ce8302c4fb72e786706',
    );
  });

  test(
    'content blocks have no fabricated collection and reject data bindings',
    () {
      final banner = projects.view('welcome');
      expect(banner.contentOnly, isTrue);
      expect(banner.collectionId, '');
      expect(banner.toJson().containsKey('collectionId'), isFalse);
      for (final extra in <String, dynamic>{
        'collectionId': 'projects',
        'titleFieldId': 'title',
        'query': {'limit': 2},
        'presentation': 'cards',
        'actionIds': ['addRecord'],
      }.entries) {
        expect(
          () => mutate(projects, 'welcome', (v) => v[extra.key] = extra.value),
          invalid,
        );
      }
      expect(
        () => mutate(
          projects,
          'welcome',
          (v) => v['options']['targetPageId'] = 'detailPage',
        ),
        invalid,
      );
      expect(
        mutate(
          projects,
          'welcome',
          (v) => v['options']['targetPageId'] = 'tablePage',
        ).view('welcome').options['targetPageId'],
        'tablePage',
      );
    },
  );

  test('rich text and banner content are bounded and strictly keyed', () {
    expect(
      () => mutate(
        journal,
        'intro',
        (v) => v['options']['markdown'] = 'x' * 8193,
      ),
      invalid,
    );
    expect(
      () =>
          mutate(projects, 'welcome', (v) => v['options']['script'] = 'run()'),
      invalid,
    );
    expect(
      () => mutate(projects, 'welcome', (v) => v['options']['tone'] = 'custom'),
      invalid,
    );
    expect(
      () => mutate(
        projects,
        'welcome',
        (v) => v['options']['imageAssetId'] = 'image_1',
      ),
      invalid,
    );
    final withImage = mutate(
      projects,
      'welcome',
      (v) => v['options'].addAll({
        'imageAssetId': 'image_1',
        'imageAlt': 'A quiet desk',
      }),
    );
    expect(withImage.view('welcome').options['imageAssetId'], 'image_1');
  });

  test('image fields accept opaque private tokens and preview IDs only', () {
    final field = journal.collection('memories').field('photo');
    for (final value in ['preview_image_0', '_${'a' * 42}', '-${'b' * 42}']) {
      expect(field.normalize(value), value);
    }
    for (final value in [
      '',
      'https://example.com/photo.jpg',
      'data:image/png;base64,AAAA',
      '../image',
      {'url': 'image'},
      'x' * 129,
    ]) {
      expect(() => field.normalize(value), invalid);
    }
    expect(field.normalize(null), isNull);
    expect(
      () => mutate(
        journal,
        'photoGallery',
        (v) => v['options']['imageFieldId'] = 'caption',
      ),
      invalid,
    );
    expect(
      () => mutate(
        journal,
        'photoGallery',
        (v) => v['options']['captionFieldId'] = 'rating',
      ),
      invalid,
    );
  });

  test('each rich component rejects another component options', () {
    expect(
      () => mutate(
        projects,
        'taskTable',
        (v) => v['options'] = {'dateFieldId': 'dueAt'},
      ),
      invalid,
    );
    expect(
      () => mutate(
        projects,
        'taskCalendar',
        (v) => v['options']['dateFieldId'] = 'title',
      ),
      invalid,
    );
    expect(
      () => mutate(projects, 'taskTimeline', (v) => v['options'] = {}),
      invalid,
    );
    expect(
      () => mutate(
        journal,
        'photoCards',
        (v) => v['options']['dateFieldId'] = 'takenAt',
      ),
      invalid,
    );
  });

  test('calendar reserves two filters in the shared bounded query budget', () {
    expect(
      () => mutate(
        projects,
        'taskCalendar',
        (v) => v['query'] = {
          'filters': List.generate(
            7,
            (_) => {'fieldId': 'priority', 'operator': 'eq', 'value': 'High'},
          ),
        },
      ),
      invalid,
    );
    expect(
      mutate(
        projects,
        'taskCalendar',
        (v) => v['query'] = {
          'filters': List.generate(
            6,
            (_) => {'fieldId': 'priority', 'operator': 'eq', 'value': 'High'},
          ),
        },
      ),
      isA<AppSpec>(),
    );
  });

  test(
    'optional timeline reserves the Undated filter while required dates do not',
    () {
      Map<String, dynamic> query(int count) => {
        'filters': List.generate(
          count,
          (_) => {'fieldId': 'priority', 'operator': 'eq', 'value': 'High'},
        ),
      };
      expect(
        mutate(projects, 'taskTimeline', (v) => v['query'] = query(7)),
        isA<AppSpec>(),
      );
      expect(
        () => mutate(projects, 'taskTimeline', (v) => v['query'] = query(8)),
        invalid,
      );
      final json = jsonDecode(projects.canonical) as Map<String, dynamic>;
      final fields = (json['collections'] as List).first['fields'] as List;
      fields.firstWhere((f) => f['id'] == 'dueAt')['required'] = true;
      final requiredDate = AppSpec.parse(jsonEncode(json));
      expect(
        mutate(requiredDate, 'taskTimeline', (v) => v['query'] = query(8)),
        isA<AppSpec>(),
      );
    },
  );

  test(
    'chart and metric reserve search and choice filters in the query budget',
    () {
      for (final id in ['dailyMinutes', 'minutesMetric']) {
        void configure(Map<String, dynamic> v, int count) {
          v['titleFieldId'] = 'title';
          v['filterFieldIds'] = ['category'];
          v['query'] = {
            'filters': List.generate(
              count,
              (_) => {'fieldId': 'minutes', 'operator': 'gte', 'value': 0},
            ),
          };
        }

        expect(mutate(habits, id, (v) => configure(v, 6)), isA<AppSpec>());
        expect(() => mutate(habits, id, (v) => configure(v, 7)), invalid);
        expect(
          () => mutate(habits, id, (v) {
            configure(v, 0);
            v['titleFieldId'] = 'minutes';
          }),
          invalid,
        );
      }
    },
  );

  test('chart and metric bindings distinguish counts numbers and dates', () {
    final edits = <void Function(Map<String, dynamic>)>[
      (v) => v['options']['metric'] = 'median',
      (v) => v['options']['valueFieldId'] = 'title',
      (v) => v['options']['dateFieldId'] = 'minutes',
      (v) => v['options']['bucket'] = 'year',
      (v) => v['options']['periods'] = 367,
      (v) => v['groupByFieldId'] = 'category',
      (v) => v['options']['style'] = 'donut',
      (v) => v['options']['metric'] = 'count',
    ];
    for (final edit in edits)
      expect(() => mutate(habits, 'dailyMinutes', edit), invalid);
    expect(
      () => mutate(
        habits,
        'categoryChart',
        (v) => v['options']['style'] = 'line',
      ),
      invalid,
    );
    expect(
      () => mutate(habits, 'categoryChart', (v) => v['options']['periods'] = 7),
      invalid,
    );
    expect(
      () => mutate(habits, 'minutesMetric', (v) => v['options']['target'] = 0),
      invalid,
    );
    expect(
      () => mutate(
        habits,
        'minutesMetric',
        (v) => v['groupByFieldId'] = 'category',
      ),
      invalid,
    );
  });

  test('richer controls enforce field compatibility and numeric bounds', () {
    for (final c in [
      {'fieldId': 'title', 'control': 'switch'},
      {'fieldId': 'minutes', 'control': 'rating'},
      {
        'fieldId': 'energy',
        'control': 'slider',
        'min': 0,
        'max': 10,
        'step': .5,
      },
      {
        'fieldId': 'minutes',
        'control': 'slider',
        'min': 10,
        'max': 0,
        'step': 1,
      },
      {
        'fieldId': 'minutes',
        'control': 'slider',
        'min': 0,
        'max': 10,
        'step': 0,
      },
      {'fieldId': 'minutes', 'control': 'slider'},
      {'fieldId': 'title', 'control': 'text', 'min': 0},
      {'fieldId': 'energy', 'control': 'rating', 'max': 10},
      {'fieldId': 'title', 'control': 'html'},
    ]) {
      expect(
        () => mutate(
          habits,
          'editor',
          (v) => v['options'] = {
            'controls': [c],
          },
        ),
        invalid,
      );
    }
    expect(
      () => mutate(
        habits,
        'editor',
        (v) => v['options'] = {
          'controls': [
            {'fieldId': 'title', 'control': 'text'},
            {'fieldId': 'title', 'control': 'multiline'},
          ],
        },
      ),
      invalid,
    );
    expect(
      () => mutate(
        projects,
        'editor',
        (v) => v['options'] = {
          'controls': [
            {'fieldId': 'status', 'control': 'segmented'},
          ],
        },
      ),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'workflow form repair instruction',
          allOf(
            contains('Form editor'),
            contains('workflow-managed field status'),
          ),
        ),
      ),
    );
    // Control bounds do not change stored-value validity or clamp old data.
    expect(habits.collection('checkins').field('minutes').normalize(500), 500);
  });

  test('control mismatch diagnostics identify exact typed bindings without labels or hints', () {
    for (final (control, diagnostic) in <(Map<String, dynamic>, String)>[
      (
        {'fieldId': 'title', 'control': 'switch'},
        'Form editor field title has type text, but control switch requires boolean.',
      ),
      (
        {'fieldId': 'minutes', 'control': 'select'},
        'Form editor field minutes has type number, but control select requires choice or member.',
      ),
      (
        {'fieldId': 'minutes', 'control': 'rating'},
        'Form editor field minutes has type number, but control rating requires integer.',
      ),
      (
        {'fieldId': 'completed', 'control': 'dateTime'},
        'Form editor field completed has type boolean, but control dateTime requires timestamp.',
      ),
      (
        {
          'fieldId': 'title',
          'control': 'slider',
          'min': 0,
          'max': 10,
          'step': 1,
        },
        'Form editor field title has type text, but control slider requires integer or number.',
      ),
    ]) {
      final json = jsonDecode(habits.canonical) as Map<String, dynamic>;
      final form = (json['views'] as List).cast<Map>().singleWhere(
        (view) => view['id'] == 'editor',
      );
      form['label'] = 'Private form label';
      final field = (json['collections'][0]['fields'] as List)
          .cast<Map>()
          .singleWhere((field) => field['id'] == control['fieldId']);
      field['label'] = 'Private field label';
      form['options'] = {
        'controls': [
          {...control, 'hint': 'Private record-like hint content'},
        ],
      };
      expect(
        () => AppSpec.parse(jsonEncode(json)),
        throwsA(
          isA<SpecException>().having(
            (error) => error.message,
            'actionable mismatch with no labels or hint content',
            diagnostic,
          ),
        ),
      );
    }
    // The diagnostic change preserves the accepted control/type combinations.
    final valid = mutate(
      habits,
      'editor',
      (view) => view['options'] = {
        'controls': [
          {'fieldId': 'title', 'control': 'multiline'},
          {
            'fieldId': 'minutes',
            'control': 'stepper',
            'min': 0,
            'max': 100,
            'step': 1,
          },
          {'fieldId': 'completed', 'control': 'checkbox'},
          {'fieldId': 'energy', 'control': 'rating'},
          {'fieldId': 'category', 'control': 'select'},
          {'fieldId': 'loggedAt', 'control': 'dateTime'},
        ],
      },
    );
    expect(AppSpec.parse(valid.canonical).hash, valid.hash);
    expect(habits.collection('checkins').field('minutes').normalize(500), 500);
  });

  test('numeric controls reject overflowing spans and step ratios', () {
    for (final control in ['slider', 'stepper']) {
      for (final bounds in [
        {'min': -1e308, 'max': 1e308, 'step': 1},
        {'min': 0, 'max': 1e308, 'step': 1e-308},
      ]) {
        expect(
          () => mutate(
            habits,
            'editor',
            (v) => v['options'] = {
              'controls': [
                {'fieldId': 'minutes', 'control': control, ...bounds},
              ],
            },
          ),
          invalid,
        );
      }
      for (final bounds in [
        {'min': 0, 'max': 1, 'step': .001},
        {'min': 0, 'max': 10, 'step': 3},
      ]) {
        expect(
          mutate(
            habits,
            'editor',
            (v) => v['options'] = {
              'controls': [
                {'fieldId': 'minutes', 'control': control, ...bounds},
              ],
            },
          ),
          isA<AppSpec>(),
        );
      }
    }
  });

  test('numeric control bounds stay inside the normalized field domain', () {
    for (final control in ['slider', 'stepper']) {
      for (final field in ['minutes', 'energy']) {
        for (final bounds in [
          {'min': 1e16, 'max': 2e16, 'step': 1},
          {'min': -2e16, 'max': -1e16, 'step': 1},
        ]) {
          expect(
            () => mutate(
              habits,
              'editor',
              (v) => v['options'] = {
                'controls': [
                  {'fieldId': field, 'control': control, ...bounds},
                ],
              },
            ),
            invalid,
          );
        }
      }
    }
    final valid = mutate(
      habits,
      'editor',
      (v) => v['options'] = {
        'controls': [
          {
            'fieldId': 'minutes',
            'control': 'stepper',
            'min': -1e15,
            'max': 1e15,
            'step': 1,
          },
          {
            'fieldId': 'energy',
            'control': 'stepper',
            'min': 1.0,
            'max': 5.0,
            'step': 1.0,
          },
        ],
      },
    );
    expect(AppSpec.parse(valid.canonical).canonical, valid.canonical);
  });

  test(
    'multi-step forms partition editable fields without duplicates or holes',
    () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (v) => v['options']['steps'][0]['fieldIds'].remove('title'),
        (v) => v['options']['steps'][1]['fieldIds'].add('title'),
        (v) => v['options']['steps'][0]['fieldIds'].add('missing'),
        (v) => v['options']['steps'][1]['id'] = 'moment',
        (v) => v['options']['steps'] = [],
      ])
        expect(() => mutate(journal, 'editor', change), invalid);
      final reordered = mutate(
        journal,
        'editor',
        (v) => v['options']['steps'] = (v['options']['steps'] as List).reversed
            .toList(),
      );
      expect(reordered.compatibilityErrors(journal), isEmpty);
    },
  );

  test('checklists bind explicit reversible states and approved actions', () {
    expect(
      () => mutate(
        projects,
        'taskChecklist',
        (v) => v['options'].remove('checkedValue'),
      ),
      invalid,
    );
    expect(
      () => mutate(
        projects,
        'taskChecklist',
        (v) => v['options']['actionId'] = 'editRecord',
      ),
      invalid,
    );
    expect(
      () => mutate(
        projects,
        'taskChecklist',
        (v) => v['options']['uncheckedValue'] = 'Done',
      ),
      invalid,
    );
    expect(
      () => mutate(
        habits,
        'checkins',
        (v) => v['options']['checkedValue'] = 'yes',
      ),
      invalid,
    );
    expect(
      () => mutate(habits, 'checkins', (v) => v['actionIds'] = ['addRecord']),
      invalid,
    );
    final json = jsonDecode(projects.canonical) as Map<String, dynamic>;
    json['collections'][0]['behaviors'][0]['transitions']['Done'] = <String>[];
    expect(() => AppSpec.parse(jsonEncode(json)), invalid);
  });

  test('drag boards cannot bypass workflow bindings or permission actions', () {
    expect(
      () => mutate(projects, 'taskBoard', (v) => v.remove('groupByFieldId')),
      throwsA(
        isA<SpecException>().having(
          (e) => e.message,
          'message',
          contains('Board taskBoard needs groupByFieldId'),
        ),
      ),
    );
    expect(
      () => mutate(projects, 'taskBoard', (v) => v['actionIds'] = <String>[]),
      throwsA(
        isA<SpecException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('View taskBoard must include action'),
            contains('in actionIds'),
          ),
        ),
      ),
    );
    expect(
      () => mutate(
        projects,
        'taskBoard',
        (v) => v['options']['draggable'] = false,
      ),
      invalid,
    );
    expect(
      () => mutate(
        projects,
        'taskBoard',
        (v) => v['options']['moveActionId'] = 'editRecord',
      ),
      invalid,
    );
    expect(
      () => mutate(
        projects,
        'taskBoard',
        (v) => v['groupByFieldId'] = 'priority',
      ),
      invalid,
    );
    expect(
      () =>
          mutate(projects, 'taskBoard', (v) => v['actionIds'] = ['addRecord']),
      invalid,
    );
  });

  test('semantic rich patches preserve IDs and infer capabilities', () {
    var counter = 0;
    final next = projects.patch({
      'type': 'AddPage',
      'page': {'title': 'Notes'},
      'newViews': [
        {
          'type': 'richText',
          'label': 'Notes',
          'options': {'markdown': '**Keep going.**'},
        },
      ],
      'tab': {'label': 'Notes', 'icon': 'book'},
    }, () => 'new${counter++}');
    expect(next.requires, contains('views.richText.v1'));
    expect(next.views.last.contentOnly, isTrue);
    expect(projects.compatibilityErrors(next), isEmpty);
    final addedImage = projects.patch({
      'type': 'AddField',
      'collectionId': 'projects',
      'field': {'label': 'Cover', 'type': 'image', 'required': false},
    }, () => 'cover');
    expect(addedImage.requires, contains('fields.image.v1'));
    expect(projects.compatibilityErrors(addedImage), isEmpty);
    final view = projects.view('taskBoard').toJson()..remove('id');
    view['label'] = 'Work board';
    final relabel = projects.patch({
      'type': 'UpdateView',
      'viewId': 'taskBoard',
      'view': view,
    }, () => throw StateError('no IDs'));
    expect(relabel.view('taskBoard').id, 'taskBoard');
    expect(
      relabel.view('taskBoard').options,
      projects.view('taskBoard').options,
    );
    expect(relabel.diff(projects), contains('Update views or view order'));
  });

  group('aggregate requests', () {
    final col = habits.collection('checkins');
    Map<String, dynamic> bucket(String key, String start, String end) => {
      'key': key,
      'start': start,
      'end': end,
    };
    final buckets = [
      bucket('spring', '2026-03-08T08:00:00Z', '2026-03-09T07:00:00Z'),
      bucket('next', '2026-03-09T07:00:00Z', '2026-03-10T07:00:00Z'),
    ];
    test('count numeric choice and UTC bucket requests round trip', () {
      for (final request in <Map<String, dynamic>>[
        {'metric': 'count'},
        {'metric': 'sum', 'fieldId': 'minutes'},
        {'metric': 'average', 'fieldId': 'energy', 'groupFieldId': 'category'},
        {'metric': 'count', 'dateFieldId': 'loggedAt', 'buckets': buckets},
      ]) {
        final parsed = AggregateQuery.parse(col, request);
        expect(
          AggregateQuery.parse(col, parsed.toJson()).toJson(),
          parsed.toJson(),
        );
      }
      final parsed = AggregateQuery.parse(col, {
        'metric': 'count',
        'dateFieldId': 'loggedAt',
        'buckets': buckets,
      });
      expect(
        DateTime.parse(parsed.buckets.first['end'])
            .difference(DateTime.parse(parsed.buckets.first['start']))
            .inHours,
        23,
      );
      expect(buckets.first['start'], '2026-03-08T08:00:00Z');
    });
    test(
      'invalid binding dimensions and arbitrary query keys are rejected',
      () {
        for (final request in <Map<String, dynamic>>[
          {'metric': 'median'},
          {'metric': 'sum'},
          {'metric': 'count', 'fieldId': 'minutes'},
          {'metric': 'average', 'fieldId': 'title'},
          {'metric': 'count', 'groupFieldId': 'title'},
          {'metric': 'count', 'dateFieldId': 'minutes', 'buckets': buckets},
          {'metric': 'count', 'dateFieldId': 'loggedAt'},
          {'metric': 'count', 'buckets': buckets},
          {
            'metric': 'count',
            'dateFieldId': 'loggedAt',
            'groupFieldId': 'category',
            'buckets': buckets,
          },
          {'metric': 'count', 'sql': 'SELECT'},
        ])
          expect(() => AggregateQuery.parse(col, request), invalid);
      },
    );
    test('bucket bounds keys ordering and limits are strict', () {
      final badBuckets = <List<Map<String, dynamic>>>[
        [bucket('a', '2026-01-02T00:00:00Z', '2026-01-01T00:00:00Z')],
        [bucket('a', '2026-01-01T00:00:00', '2026-01-02T00:00:00Z')],
        [bucket('a', '2026-01-01T00:00:00+00:00', '2026-01-02T00:00:00Z')],
        [
          bucket('a', '2026-01-01T00:00:00Z', '2026-01-03T00:00:00Z'),
          bucket('b', '2026-01-02T00:00:00Z', '2026-01-04T00:00:00Z'),
        ],
        [
          bucket('a', '2026-01-01T00:00:00Z', '2026-01-02T00:00:00Z'),
          bucket('a', '2026-01-02T00:00:00Z', '2026-01-03T00:00:00Z'),
        ],
        List.generate(
          367,
          (i) => bucket(
            '$i',
            DateTime.utc(2026, 1, i + 1).toIso8601String(),
            DateTime.utc(2026, 1, i + 2).toIso8601String(),
          ),
        ),
      ];
      for (final list in badBuckets)
        expect(
          () => AggregateQuery.parse(col, {
            'metric': 'count',
            'dateFieldId': 'loggedAt',
            'buckets': list,
          }),
          invalid,
        );
    });
  });

  test('exported schema has strict per-type options and content collection rules', () {
    final schema = appSpecSchema();
    final view = schema['properties']['views']['items'];
    expect(view['properties']['type']['enum'], containsAll(richViewTypes));
    expect(view['required'], isNot(contains('collectionId')));
    expect(view['allOf'], isNotEmpty);
    expect(
      schema['properties']['collections']['items']['properties']['fields']['items']['properties']['type']['enum'],
      contains('image'),
    );
  });
}
