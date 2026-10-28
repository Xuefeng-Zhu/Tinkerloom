import 'dart:convert';

import 'package:appnest_server/src/modules/builder/creation_plan.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

Map<String, dynamic> _planFixture() => {
  'creationPlanVersion': 1,
  'plan': {
    'name': 'Garden journal',
    'theme': 'sage',
    'icon': 'book',
    'policyPresetRequest': 'personalTracker.v1',
    'collections': [
      {
        'id': 'entries',
        'label': 'Entries',
        'fields': [
          {'id': 'title', 'label': 'Title', 'type': 'text', 'required': true},
          {'id': 'body', 'label': 'Body', 'type': 'text', 'required': false},
          {'id': 'done', 'label': 'Done', 'type': 'boolean', 'required': false},
          {
            'id': 'when',
            'label': 'When',
            'type': 'timestamp',
            'required': false,
          },
          {
            'id': 'category',
            'label': 'Category',
            'type': 'choice',
            'required': false,
            'choices': ['Plants', 'Weather'],
          },
        ],
        'behaviors': <dynamic>[],
        'operations': [
          {'type': 'create', 'label': 'New entry'},
          {'type': 'edit', 'label': 'Edit entry'},
        ],
        'form': {
          'type': 'form',
          'label': 'Write entry',
          'fieldIds': ['title', 'body', 'done', 'when', 'category'],
          'options': {
            'controls': [
              {'fieldId': 'body', 'control': 'multiline'},
            ],
          },
        },
        'details': {'type': 'details', 'label': 'Entry'},
      },
    ],
    'pages': [
      {
        'key': 'journal',
        'title': 'Journal',
        'tab': {'label': 'Journal', 'icon': 'book'},
        'components': [
          {
            'type': 'list',
            'collectionId': 'entries',
            'label': 'Entries',
            'titleFieldId': 'title',
            'filterFieldIds': ['category'],
          },
        ],
      },
    ],
    'entryPageKey': 'journal',
    'automationRequests': <dynamic>[],
  },
};

Map<String, dynamic> _plan() =>
    jsonDecode(jsonEncode(_planFixture())) as Map<String, dynamic>;

Map<String, dynamic> _body(Map<String, dynamic> response) =>
    response['plan'] as Map<String, dynamic>;

Map<String, dynamic> _collection(Map<String, dynamic> response) =>
    (_body(response)['collections'] as List).first as Map<String, dynamic>;

List<dynamic> _components(Map<String, dynamic> response) =>
    (_body(response)['pages'] as List).first['components'] as List;

void main() {
  test('plan schema advertises only authored references and correct component placement', () {
    final schema = creationPlanResponseSchema();
    final root = schema['anyOf'][0]['properties']['plan']['properties'];
    final collection = root['collections']['items']['properties'];
    expect(collection['form']['properties']['type'], {'const': 'form'});
    expect(collection['details']['properties']['type'], {'const': 'details'});
    final component =
        root['pages']['items']['properties']['components']['items'];
    expect(component['properties']['type']['enum'], isNot(contains('form')));
    expect(component['properties']['type']['enum'], isNot(contains('details')));
    for (final key in ['id', 'actionIds', 'detailPageId', 'formPageId']) {
      expect((component['properties'] as Map).containsKey(key), false);
    }
    final options = <String, Map>{};
    for (final branch in component['allOf']) {
      final type = branch['if']['properties']['type']['const'];
      if (type is String) {
        options[type] = branch['then']['properties']['options'];
      }
    }
    expect(options['checklist']!['properties'].containsKey('actionId'), false);
    expect(
      options['board']!['oneOf'][1]['properties'].containsKey('moveActionId'),
      false,
    );
    expect(options['board']!['oneOf'][1]['required'], ['draggable']);
    expect(options['banner']!['properties'].containsKey('targetPageId'), false);
    expect(options['banner']!['properties'].containsKey('targetPageKey'), true);
  });

  test(
    'request transformation preserves all original user and repair data',
    () {
      final original = buildAiRequest(
        'test/model',
        'Create a personal writing journal with a multiline body.',
        starterTemplates().values.first,
        editing: false,
        diagnostics: ['Form body needs multiline'],
        rejectedOutput: '{"untrusted":"old AppSpec or plan"}',
      );
      final before = jsonEncode(original);
      final transformed = buildCreationPlanRequest(original);
      expect(jsonEncode(original), before);
      expect(transformed['model'], original['model']);
      expect(transformed['max_tokens'], original['max_tokens']);
      expect(transformed['temperature'], original['temperature']);
      expect(transformed['messages'][1], original['messages'][1]);
      expect(
        transformed['messages'][0]['content'],
        contains('creationPlanVersion'),
      );
      expect(
        transformed['response_format']['json_schema']['name'],
        'appnest_creation_plan_response',
      );
      expect(
        transformed['messages'][0]['content'],
        isNot(contains('Reading List')),
      );
    },
  );

  test('edit and malformed request envelopes fail without transformation', () {
    final edit = buildAiRequest(
      'test/model',
      'Rename this app.',
      starterTemplates().values.first,
      editing: true,
    );
    expect(() => buildCreationPlanRequest(edit), throwsA(isA<SpecException>()));
    final malformed = {
      'messages': [
        {'role': 'system', 'content': 'system'},
        {'role': 'user', 'content': 'plain text'},
      ],
    };
    expect(
      () => buildCreationPlanRequest(malformed),
      throwsA(isA<SpecException>()),
    );
  });

  test(
    'compiler constructs deterministic CRUD routes and capability closure',
    () {
      final raw = _plan();
      final before = jsonEncode(raw);
      final result = compileCreationPlan(raw);
      expect(jsonEncode(raw), before);
      final spec = AppSpec.parse(jsonEncode(result));
      expect(
        spec.hash,
        AppSpec.parse(jsonEncode(compileCreationPlan(raw))).hash,
      );
      expect(spec.policyPresetRequest, 'personalTracker.v1');
      expect(spec.actions.map((a) => a.label), ['New entry', 'Edit entry']);
      final list = spec.views.singleWhere((v) => v.type == 'list');
      final form = spec.views.singleWhere((v) => v.type == 'form');
      final details = spec.views.singleWhere((v) => v.type == 'details');
      expect(spec.page(list.formPageId!).viewIds, [form.id]);
      expect(spec.page(list.detailPageId!).viewIds, [details.id]);
      expect(details.formPageId, list.formPageId);
      final main = spec.page(spec.navigation!.entryPageId);
      final create = spec.actions.singleWhere(
        (a) => a.capability == 'records.create.v1',
      );
      expect(main.primaryActionId, create.id);
      expect(list.actionIds, contains(create.id));
      expect(form.actionIds, contains(create.id));
      expect(
        spec.navigation!.tabs.map((t) => t.pageId),
        isNot(contains(list.formPageId)),
      );
      expect(
        spec.requires,
        containsAll([
          'collections.v1',
          'navigation.v1',
          'records.create.v1',
          'records.patch.v1',
          'views.interactive.v1',
          'views.configured.v1',
        ]),
      );
    },
  );

  test(
    'compiler preserves literal fields, choice order, form controls and steps',
    () {
      final raw = _plan();
      final form = _collection(raw)['form'] as Map<String, dynamic>;
      form['options']['steps'] = [
        {
          'id': 'writing',
          'title': 'Write',
          'fieldIds': ['title', 'body'],
        },
        {
          'id': 'context',
          'title': 'Context',
          'fieldIds': ['done', 'when', 'category'],
        },
      ];
      final spec = AppSpec.parse(jsonEncode(compileCreationPlan(raw)));
      expect(spec.collection('entries').field('category').choices, [
        'Plants',
        'Weather',
      ]);
      expect(spec.collection('entries').field('when').required, false);
      final compiled = spec.views.singleWhere((v) => v.type == 'form');
      expect(compiled.options, form['options']);
    },
  );

  test(
    'boolean checklist binds only an explicitly declared edit operation',
    () {
      final raw = _plan();
      _components(raw).add({
        'type': 'checklist',
        'collectionId': 'entries',
        'label': 'Finished',
        'titleFieldId': 'title',
        'options': {'fieldId': 'done'},
      });
      final spec = AppSpec.parse(jsonEncode(compileCreationPlan(raw)));
      final checklist = spec.views.singleWhere((v) => v.type == 'checklist');
      expect(
        spec.action(checklist.options['actionId']).capability,
        'records.patch.v1',
      );
      (_collection(raw)['operations'] as List).removeWhere(
        (o) => o['type'] == 'edit',
      );
      expect(() => compileCreationPlan(raw), throwsA(isA<SpecException>()));
    },
  );

  test('workflow checklist and board bind declared behavior without changing transitions', () {
    final raw = _plan();
    final col = _collection(raw);
    (col['fields'] as List).add({
      'id': 'status',
      'label': 'Status',
      'type': 'choice',
      'required': true,
      'choices': ['To do', 'Done'],
    });
    col['behaviors'] = [
      {
        'type': 'workflow.v1',
        'fieldId': 'status',
        'transitions': {
          'To do': ['Done'],
          'Done': ['To do'],
        },
      },
    ];
    (col['operations'] as List).add({
      'type': 'transition',
      'label': 'Change progress',
      'fieldId': 'status',
    });
    _components(raw).addAll([
      {
        'type': 'checklist',
        'collectionId': 'entries',
        'label': 'Progress',
        'options': {
          'fieldId': 'status',
          'checkedValue': 'Done',
          'uncheckedValue': 'To do',
        },
      },
      {
        'type': 'board',
        'collectionId': 'entries',
        'label': 'Board',
        'groupByFieldId': 'status',
        'options': {'draggable': true},
      },
    ]);
    final spec = AppSpec.parse(jsonEncode(compileCreationPlan(raw)));
    final behavior = spec.collection('entries').behaviors.single;
    final checklist = spec.views.singleWhere((v) => v.type == 'checklist');
    final board = spec.views.singleWhere((v) => v.type == 'board');
    expect(behavior.transitions, col['behaviors'][0]['transitions']);
    expect(spec.action(checklist.options['actionId']).behaviorId, behavior.id);
    expect(board.options['moveActionId'], checklist.options['actionId']);
  });

  test('capacity semantics, exact policy and unconditional reminders are preserved', () {
    final raw = _plan();
    _body(raw)['policyPresetRequest'] = 'groupCapacitySignup.v1';
    _collection(raw)['behaviors'] = [
      {'type': 'capacity.v1'},
    ];
    (_collection(raw)['operations'] as List).addAll([
      {'type': 'configureCapacity', 'label': 'Set places'},
      {'type': 'claim', 'label': 'Sign up'},
      {'type': 'release', 'label': 'Cancel signup'},
    ]);
    _components(
      raw,
    ).add({'type': 'capacity', 'collectionId': 'entries', 'label': 'Places'});
    _body(raw)['automationRequests'] = [
      {
        'collectionId': 'entries',
        'fieldId': 'when',
        'offsetSeconds': 900,
        'effect': 'notifyActiveClaimants',
      },
    ];
    final spec = AppSpec.parse(jsonEncode(compileCreationPlan(raw)));
    expect(spec.policyPresetRequest, 'groupCapacitySignup.v1');
    expect(spec.automationRequests.single.condition, isNull);
    expect(spec.automationRequests.single.offsetSeconds, 900);
    expect(
      spec.actions.where((a) => a.capability.startsWith('capacity.')).length,
      3,
    );
    expect(spec.automationRequests.single.effect, 'notifyActiveClaimants');
  });

  test('rich chart and calendar options remain model-authored and strictly checked', () {
    final raw = _plan();
    _components(raw).addAll([
      {
        'type': 'chart',
        'collectionId': 'entries',
        'label': 'Entries by week',
        'options': {
          'metric': 'count',
          'style': 'line',
          'dateFieldId': 'when',
          'bucket': 'week',
          'periods': 8,
        },
      },
      {
        'type': 'calendar',
        'collectionId': 'entries',
        'label': 'Calendar',
        'options': {'dateFieldId': 'when'},
      },
    ]);
    final spec = AppSpec.parse(jsonEncode(compileCreationPlan(raw)));
    expect(
      spec.views.singleWhere((v) => v.type == 'chart').options['periods'],
      8,
    );
    _components(raw).last['options']['dateFieldId'] = 'body';
    expect(() => compileCreationPlan(raw), throwsA(isA<SpecException>()));
  });

  test(
    'collection-free clocks, device components and banner tab links compile',
    () {
      final raw = _plan();
      _body(raw)['collections'] = <dynamic>[];
      _body(raw)['pages'][0]['components'] = [
        {
          'type': 'clock',
          'label': 'Clock',
          'options': {
            'style': 'digital',
            'hourFormat': '24',
            'showSeconds': true,
            'showDate': false,
          },
        },
        {
          'type': 'deviceInfo',
          'label': 'Battery',
          'options': {
            'fields': ['batteryLevel', 'charging'],
          },
        },
        {
          'type': 'deviceControl',
          'label': 'Light',
          'options': {'control': 'flashlight'},
        },
        {
          'type': 'banner',
          'label': 'Welcome',
          'options': {'title': 'Home', 'targetPageKey': 'journal'},
        },
      ];
      final spec = AppSpec.parse(jsonEncode(compileCreationPlan(raw)));
      expect(spec.collections, isEmpty);
      expect(spec.actions, isEmpty);
      expect(spec.requires, isNot(contains('collections.v1')));
      expect(
        spec.views
            .singleWhere((v) => v.type == 'banner')
            .options['targetPageId'],
        spec.navigation!.entryPageId,
      );
    },
  );

  test('unsupported remains unsupported and arbitrary AppSpec is rejected', () {
    final unsupported = {'unsupported': 'External payments are unsupported.'};
    expect(compileCreationPlan(unsupported), unsupported);
    expect(
      () => compileCreationPlan(starterTemplates().values.first.toJson()),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => compileCreationPlan({...unsupported, 'creationPlanVersion': 1}),
      throwsA(isA<SpecException>()),
    );
  });

  test('malformed interactive components fail with a bounded diagnostic', () {
    for (final type in ['checklist', 'board']) {
      final raw = _plan();
      _body(raw)['pages'][0]['components'] = [
        {
          'type': type,
          'label': 'Broken',
          'options': type == 'checklist'
              ? {'fieldId': 'done'}
              : {'draggable': true},
          if (type == 'board') 'groupByFieldId': 'category',
        },
      ];
      expect(() => compileCreationPlan(raw), throwsA(isA<SpecException>()));
    }
  });

  test(
    'compiler preserves authored appearance and adds no default appearance',
    () {
      final raw = _plan();
      expect(compileCreationPlan(raw).containsKey('appearance'), false);
      _body(raw)['appearance'] = {
        'style': 'editorial',
        'accentColor': '#123456',
      };
      final result = compileCreationPlan(raw);
      expect(result['appearance'], _body(raw)['appearance']);
      expect(result['requires'], contains('appearance.v1'));
    },
  );

  test(
    'unknown keys, action references and unsupported operations fail closed',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (raw) => raw['extra'] = true,
        (raw) => _body(raw)['requires'] = ['collections.v1'],
        (raw) => _collection(raw)['policy'] = 'public',
        (raw) => _collection(
          raw,
        )['behaviors'].add({'type': 'capacity.v1', 'id': 'injected'}),
        (raw) => _collection(
          raw,
        )['operations'].add({'type': 'delete', 'label': 'Delete'}),
        (raw) => _components(raw).first['actionIds'] = ['injected'],
        (raw) => _components(raw).first['options'] = {'secret': true},
        (raw) => _body(raw)['pages'][0]['primaryActionId'] = 'injected',
      ]) {
        final raw = _plan();
        mutate(raw);
        expect(() => compileCreationPlan(raw), throwsA(isA<SpecException>()));
      }
    },
  );

  test(
    'compiler never invents missing operations, behaviors or policy privileges',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (raw) => _collection(raw).remove('form'),
        (raw) => _collection(raw)['operations'].add({
          'type': 'assign',
          'label': 'Assign',
          'fieldId': 'body',
        }),
        (raw) => _collection(
          raw,
        )['operations'].add({'type': 'claim', 'label': 'Claim'}),
        (raw) => _collection(
          raw,
        )['operations'].add({'type': 'edit', 'label': 'Another edit'}),
        (raw) => _collection(raw)['operations'].first['fieldId'] = 'body',
        (raw) => _body(raw)['policyPresetRequest'] = 'publicAdmin.v1',
        (raw) => _body(raw)['automationRequests'] = [
          {
            'collectionId': 'entries',
            'fieldId': 'when',
            'offsetSeconds': 60,
            'effect': 'notifyAssignee',
          },
        ],
      ]) {
        final raw = _plan();
        mutate(raw);
        expect(() => compileCreationPlan(raw), throwsA(isA<SpecException>()));
      }
      final raw = _plan();
      _collection(raw)['operations'] = <dynamic>[];
      _collection(raw).remove('form');
      final spec = AppSpec.parse(jsonEncode(compileCreationPlan(raw)));
      expect(spec.actions, isEmpty);
      expect(spec.policyPresetRequest, 'personalTracker.v1');
      expect(
        spec.views.singleWhere((v) => v.type == 'list').formPageId,
        isNull,
      );
    },
  );

  test('all collection routes stay in their own collection', () {
    final raw = _plan();
    final other =
        jsonDecode(jsonEncode(_collection(raw))) as Map<String, dynamic>;
    other['id'] = 'observations';
    other['label'] = 'Observations';
    (_body(raw)['collections'] as List).add(other);
    _components(raw).add({
      'type': 'list',
      'collectionId': 'observations',
      'label': 'Observations',
    });
    _body(raw)['pages'][0]['primaryCollectionId'] = 'observations';
    final spec = AppSpec.parse(jsonEncode(compileCreationPlan(raw)));
    for (final view in spec.views.where((v) => v.type == 'list')) {
      final form = spec.view(spec.page(view.formPageId!).viewIds.single);
      expect(form.collectionId, view.collectionId);
      for (final action in view.actionIds.map(spec.action)) {
        expect(action.collectionId, view.collectionId);
      }
    }
    expect(
      spec
          .action(spec.page(spec.navigation!.entryPageId).primaryActionId!)
          .collectionId,
      'observations',
    );
  });

  test(
    'raw and expanded definitions obey bounds and reject malformed types',
    () {
      final tooLarge = _plan()..['padding'] = 'x' * Limits.definitionBytes;
      expect(
        () => compileCreationPlan(tooLarge),
        throwsA(isA<SpecException>()),
      );
      final raw = _plan();
      _body(raw)['pages'][0]['components'] = List.generate(
        8,
        (_) => {'type': 'list', 'collectionId': 'entries', 'label': 'List'},
      );
      _body(raw)['pages'].add({
        'key': 'second',
        'title': 'Second',
        'components': List.generate(
          8,
          (_) => {'type': 'list', 'collectionId': 'entries', 'label': 'List'},
        ),
      });
      expect(() => compileCreationPlan(raw), throwsA(isA<SpecException>()));
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (raw) => raw['creationPlanVersion'] = 1.0,
        (raw) => _body(raw)['pages'][0]['showDate'] = 'true',
        (raw) => _body(raw)['pages'][0]['tab']['extra'] = true,
        (raw) => _collection(raw)['operations'] = 'create',
        (raw) => _collection(raw)['form'] = null,
        (raw) => _collection(raw)['fields'][0]['choices'] = null,
        (raw) => _components(raw).first['label'] = null,
        (raw) => _components(raw).first['query'] = {'unknown': true},
        (raw) =>
            _components(raw).first['options'] = {'unbounded': double.infinity},
      ]) {
        final candidate = _plan();
        mutate(candidate);
        expect(
          () => compileCreationPlan(candidate),
          throwsA(isA<SpecException>()),
        );
      }
    },
  );
}
