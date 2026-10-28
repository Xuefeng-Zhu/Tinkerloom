import 'dart:convert';

import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

AppSpec _change(AppSpec spec, void Function(Map<String, dynamic>) change) {
  final json = jsonDecode(spec.canonical) as Map<String, dynamic>;
  change(json);
  return AppSpec.parse(jsonEncode(json));
}

Map<String, dynamic> _viewPatch(
  AppSpec spec,
  String id,
  Map<String, dynamic> options,
) {
  final view = spec.view(id);
  return {
    'type': 'UpdateView',
    'viewId': id,
    'view': {
      ...view.toJson()..remove('id'),
      'options': {...view.options, ...options},
    },
  };
}

Map<String, dynamic> _edit(NemotronScenario scenario) {
  final baseline = scenario.baseline;
  final key = scenario.id.substring(scenario.id.indexOf('-') + 1);
  final patch = switch (key) {
    'notes-fields' || 'shared-field' => {
      'type': 'AddField',
      'collectionId': baseline.collections.single.id,
      'field': {
        'label': key == 'notes-fields' ? 'Source' : 'Location',
        'type': 'text',
        'required': false,
      },
      'viewIds': [
        for (final view in baseline.views)
          if ({'form', 'details'}.contains(view.type)) view.id,
      ],
    },
    'notes-appearance' => {
      'type': 'SetAppearance',
      'appearance': {'style': 'editorial', 'accentColor': '#3B6B5A'},
    },
    'calendar-appearance' => {
      'type': 'SetAppearance',
      'appearance': {'style': 'playful'},
    },
    'reminders-name' => {
      'type': 'RenameLabel',
      'targetId': 'app',
      'label': 'Gentle Reminders',
    },
    'reminders-timing' => {
      'type': 'UpdateReminder',
      'ruleId': baseline.automationRequests.single.id,
      'rule': {
        ...baseline.automationRequests.single.toJson()..remove('id'),
        'trigger': {
          ...(baseline.automationRequests.single.toJson()['trigger'] as Map),
          'offsetSeconds': 600,
        },
      },
    },
    'calendar-category' => {
      'type': 'AddChoice',
      'collectionId': baseline.collections.single.id,
      'fieldId': 'category',
      'choice': 'Travel',
    },
    'focus-duration' => _viewPatch(baseline, 'focusTimer', {
      'durationMinutes': 40,
    }),
    'focus-clock' => _viewPatch(baseline, 'localClock', {
      'style': 'analog',
      'showSeconds': false,
    }),
    'navigation' => {
      'type': 'SetNavigation',
      'entryPageId': 'calendarPage',
      'tabs': [
        for (final id in ['calendarPage', 'boardPage', 'tablePage'])
          baseline.navigation!.tabs.singleWhere((t) => t.pageId == id).toJson(),
      ],
    },
    'rich-config' => _viewPatch(baseline, 'dailyMinutes', {'periods': 30}),
    'workflow-label' => {
      'type': 'RenameLabel',
      'targetId': 'status',
      'label': 'Stage',
    },
    _ => throw StateError('Unknown test edit $key'),
  };
  return {
    'patches': [patch],
  };
}

AppSpec _apply(AppSpec baseline, Map<String, dynamic> output) {
  var result = baseline;
  var id = 0;
  for (final patch in output['patches'] as List) {
    result = result.patch(
      jsonDecode(jsonEncode(patch)) as Map<String, dynamic>,
      () => 'test_added_${++id}',
    );
  }
  return result;
}

Map<String, dynamic> _questions(bool clarify) => {
  'needsClarification': clarify,
  'questions': [
    if (clarify) ...[
      {
        'question': 'What would you like to organize?',
        'options': ['Tasks', 'Notes', 'Events'],
      },
      {
        'question': 'Who will use this app?',
        'options': ['Just me', 'My team', 'A volunteer group'],
      },
    ],
  ],
};

void main() {
  final scenarios = nemotronScenarios();
  NemotronScenario scenario(String id) =>
      scenarios.singleWhere((s) => s.id == id);

  test('suite has exactly the fixed operation coverage and stable IDs', () {
    expect(scenarios, hasLength(32));
    expect(scenarios.map((s) => s.id).toSet(), hasLength(32));
    for (final operation in ['create', 'edit']) {
      expect(scenarios.where((s) => s.operation == operation), hasLength(12));
    }
    for (final operation in ['guidance', 'unsupported']) {
      expect(scenarios.where((s) => s.operation == operation), hasLength(4));
    }
    expect(
      jsonEncode(scenarios.map((s) => s.toJson()).toList()),
      jsonEncode(nemotronScenarios().map((s) => s.toJson()).toList()),
    );
  });

  for (final item in scenarios) {
    test('${item.id} accepts its intended synthetic output', () {
      switch (item.operation) {
        case 'create':
          item.validate(item.baseline.toJson(), item.baseline);
        case 'edit':
          final output = _edit(item);
          item.validate(output, _apply(item.baseline, output));
        case 'guidance':
          item.validate(
            _questions(item.id.startsWith('guidance-ambiguous-')),
            null,
          );
        case 'unsupported':
          item.validate({
            'unsupported':
                'This requires a capability AppNest does not support.',
          }, null);
      }
    });
  }

  test('dashboard rejects a valid chart with the wrong numeric measure', () {
    final item = scenario('create-rich-dashboard');
    final changed = _change(item.baseline, (json) {
      final chart = (json['views'] as List).singleWhere(
        (v) => v['id'] == 'dailyMinutes',
      );
      chart['options']['valueFieldId'] = 'energy';
    });
    expect(
      () => item.validate(changed.toJson(), changed),
      throwsA(isA<SpecException>()),
    );
  });

  test('multistep form rejects requested fields moved to the wrong step', () {
    final item = scenario('create-multistep-form');
    final changed = _change(item.baseline, (json) {
      final editor = (json['views'] as List).singleWhere(
        (v) => v['id'] == 'editor',
      );
      (editor['options']['steps'][0]['fieldIds'] as List).remove('photo');
      (editor['options']['steps'][1]['fieldIds'] as List).add('photo');
    });
    expect(
      () => item.validate(changed.toJson(), changed),
      throwsA(isA<SpecException>()),
    );
  });

  test('workflow creation requires actual drag controls and transitions', () {
    final item = scenario('create-shared-workflow');
    final changed = _change(item.baseline, (json) {
      final board = (json['views'] as List).singleWhere(
        (v) => v['id'] == 'taskBoard',
      );
      board.remove('options');
    });
    expect(
      () => item.validate(changed.toJson(), changed),
      throwsA(isA<SpecException>()),
    );
  });

  test(
    'capacity reminder must target active claimants at the requested time',
    () {
      final item = scenario('create-capacity-signup');
      final changed = _change(item.baseline, (json) {
        json['automationRequests'][0]['trigger']['offsetSeconds'] = 600;
      });
      expect(
        () => item.validate(changed.toJson(), changed),
        throwsA(isA<SpecException>()),
      );
    },
  );

  for (final key in [
    'navigation',
    'rich-config',
    'workflow-label',
    'shared-field',
  ]) {
    test('$key rejects a no-op and unrelated compatible changes', () {
      final item = scenario('edit-$key');
      final output = _edit(item);
      expect(
        () => item.validate(output, item.baseline),
        throwsA(isA<SpecException>()),
      );
      final edited = _apply(item.baseline, output);
      final unrelated = edited.patch({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': 'Unexpected rename',
      }, () => throw StateError('No IDs'));
      expect(
        () => item.validate(output, unrelated),
        throwsA(isA<SpecException>()),
      );
    });
  }

  test('guidance distinguishes actionable requests from ambiguous ideas', () {
    expect(
      () => scenario(
        'guidance-actionable-notes',
      ).validate(_questions(true), null),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => scenario(
        'guidance-ambiguous-team',
      ).validate(_questions(false), null),
      throwsA(isA<SpecException>()),
    );
  });

  test('unsupported responses require exactly one bounded explanation', () {
    final item = scenario('unsupported-executable');
    for (final output in <Map<String, dynamic>>[
      {'unsupported': ''},
      {'unsupported': '   '},
      {'unsupported': 'x' * 501},
      {'unsupported': 1},
      {'unsupported': 'Cannot execute code', 'patches': []},
      {'patches': []},
    ]) {
      expect(
        () => item.validate(output, null),
        throwsA(isA<SpecException>()),
      );
    }
  });

  test('four separate sequence edits use their model-specific baseline', () {
    final sequences = nemotronSequences();
    expect(sequences, hasLength(4));
    for (final item in sequences) {
      expect(item.operation, 'sequence');
      expect(
        scenarios.singleWhere((s) => s.id == item.sequenceSourceId).operation,
        'create',
      );
      final generated = item.baseline.patch({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': 'Synthetic model-created app',
      }, () => throw StateError('No IDs'));
      final descriptor = NemotronScenario(
        id: item.id,
        operation: item.operation,
        prompt: item.prompt,
        baseline: generated,
      );
      final output = _edit(descriptor);
      final edited = _apply(generated, output);
      item.validate(output, edited, baselineOverride: generated);
      expect(
        () => item.validate(output, edited),
        throwsA(isA<SpecException>()),
      );
    }
  });
}
