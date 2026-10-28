import 'dart:convert';

import 'package:appnest_server/src/modules/builder/customization_evaluation.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

AppSpec _change(AppSpec spec, void Function(Map<String, dynamic>) change) {
  final json = jsonDecode(spec.canonical) as Map<String, dynamic>;
  change(json);
  return AppSpec.parse(jsonEncode(json));
}

AppSpec _viewOptions(AppSpec spec, String type, Map<String, dynamic> options) {
  final view = spec.views.singleWhere((v) => v.type == type);
  return spec.patch({
    'type': 'UpdateView',
    'viewId': view.id,
    'view': {
      ...view.toJson()..remove('id'),
      'options': {...view.options, ...options},
    },
  }, () => throw StateError('No IDs'));
}

AppSpec _source(AppSpec spec, {bool details = true, String type = 'text'}) =>
    _change(spec, (json) {
      (json['collections'][0]['fields'] as List).add({
        'id': 'source',
        'label': 'Source',
        'type': type,
        'required': false,
      });
      for (final view in json['views'] as List) {
        if (view['type'] == 'form' || details && view['type'] == 'details') {
          final fields = view['fieldIds'] as List?;
          if (fields != null && fields.isNotEmpty) fields.add('source');
          final steps = view['options']?['steps'] as List?;
          if (steps != null) (steps.last['fieldIds'] as List).add('source');
        }
      }
    });

void main() {
  final templates = starterTemplates();
  final bases = <String, AppSpec>{
    'notes-fields': templates['notes']!,
    'notes-appearance': templates['notes']!,
    'reminders-timing': templates['reminders']!,
    'reminders-name': templates['reminders']!,
    'calendar-category': templates['calendar']!,
    'calendar-appearance': templates['calendar']!,
    'focus-duration': templates['focus']!,
    'focus-clock': _viewOptions(templates['focus']!, 'clock', {
      'showSeconds': true,
    }),
  };
  void rejects(String id, AppSpec candidate, {AppSpec? baseline}) => expect(
    () => validateCustomizationScenario(id, candidate, baseline: baseline),
    throwsA(isA<SpecException>()),
  );

  for (final entry in bases.entries) {
    test('${entry.key} accepts a complete create definition', () {
      expect(
        () => validateCustomizationScenario(entry.key, entry.value),
        returnsNormally,
      );
    });
  }

  test('notes require category, usable search and multiline note editing', () {
    final original = bases['notes-fields']!;
    final noFilters = _change(original, (json) {
      for (final view in json['views']) {
        view.remove('filterFieldIds');
      }
    });
    expect(
      () => validateCustomizationScenario('notes-fields', noFilters),
      returnsNormally,
      reason: 'Text search does not require a category dropdown.',
    );
    final noSearch = _change(original, (json) {
      json['requires'].add('views.board.v1');
      for (final view in json['views']) {
        if (view['type'] == 'list') {
          view['type'] = 'board';
          view['groupByFieldId'] = 'category';
        }
      }
    });
    rejects('notes-fields', noSearch);
    expect(
      () => validateCustomizationScenario('notes-fields', noSearch),
      throwsA(
        isA<SpecException>().having(
          (e) => e.message,
          'actionable search repair',
          allOf(
            contains('titleFieldId:"title"'),
            contains('list, table, or checklist'),
            contains('views.configured.v1'),
          ),
        ),
      ),
    );
    final noCategory = _change(noFilters, (json) {
      final field = (json['collections'][0]['fields'] as List).firstWhere(
        (f) => f['id'] == 'category',
      );
      field['type'] = 'text';
      field.remove('choices');
    });
    rejects('notes-appearance', noCategory);
    final noMultiline = _change(original, (json) {
      for (final view in json['views']) {
        if (view['type'] == 'form') view['options'] = {'controls': []};
      }
    });
    rejects('notes-fields', noMultiline);
    expect(
      () => validateCustomizationScenario('notes-fields', noMultiline),
      throwsA(
        isA<SpecException>().having(
          (e) => e.message,
          'actionable multiline repair',
          allOf(
            contains('"fieldId":"body"'),
            contains('"control":"multiline"'),
            contains('form.options.controls'),
            contains('views.interactive.v1'),
            contains('views.configured.v1'),
          ),
        ),
      ),
    );
  });

  test('notes text search requires an available resolved filter slot', () {
    AppSpec withFilters(int count) => _change(bases['notes-fields']!, (json) {
      for (final view in json['views']) {
        view.remove('filterFieldIds');
        if (view['type'] == 'list') {
          view['query'] = {
            'filters': [
              for (var i = 0; i < count; i++)
                {'fieldId': 'title', 'operator': 'contains', 'value': 'a'},
            ],
          };
        }
      }
    });
    rejects('notes-fields', withFilters(Limits.filters));
    expect(
      () => validateCustomizationScenario(
        'notes-fields',
        withFilters(Limits.filters - 1),
      ),
      returnsNormally,
    );
  });

  test('notes fields creation requires linked per-record details', () {
    final unlinked = _change(bases['notes-fields']!, (json) {
      for (final view in json['views']) {
        view.remove('detailPageId');
      }
    });
    expect(
      () => validateCustomizationScenario('notes-fields', unlinked),
      throwsA(
        isA<SpecException>().having(
          (e) => e.message,
          'details repair',
          contains('view.detailPageId'),
        ),
      ),
    );
    final absent = _change(unlinked, (json) {
      (json['views'] as List).removeWhere((view) => view['type'] == 'details');
      (json['navigation']['pages'] as List).removeWhere(
        (page) => page['id'] == 'detailPage',
      );
    });
    rejects('notes-fields', absent);
    // The simpler appearance scenario does not request details.
    validateCustomizationScenario('notes-appearance', absent);
  });

  test(
    'schema-valid read-only record apps fail requested add/edit support',
    () {
      final readOnly = _change(bases['notes-fields']!, (json) {
        json['actions'] = [];
        (json['views'] as List).removeWhere((v) => v['type'] == 'form');
        (json['navigation']['pages'] as List).removeWhere(
          (p) => p['id'] == 'formPage',
        );
        for (final view in json['views']) {
          view['actionIds'] = [];
          view.remove('formPageId');
        }
        for (final page in json['navigation']['pages']) {
          page.remove('primaryActionId');
        }
      });
      rejects('notes-fields', readOnly);
    },
  );

  test(
    'unreachable forms and summary edit declarations do not fulfill CRUD',
    () {
      final hidden = _change(bases['reminders-name']!, (json) {
        for (final view in json['views']) {
          if (view['type'] != 'form') {
            (view['actionIds'] as List).remove('editTask');
          }
          if (view['type'] == 'summary') {
            (view['actionIds'] as List).add('editTask');
          }
        }
      });
      rejects('reminders-name', hidden);
    },
  );

  test('reminders check Open condition, exact time and optional independent timestamps', () {
    final original = bases['reminders-timing']!;
    rejects(
      'reminders-timing',
      _change(original, (json) {
        (json['collections'][0]['fields'] as List).firstWhere(
          (f) => f['id'] == 'status',
        )['choices'] = [
          'Done',
          'Open',
        ];
      }),
    );
    rejects(
      'reminders-timing',
      _change(original, (json) {
        json['automationRequests'][0]['condition']['value'] = 'Done';
      }),
    );
    rejects(
      'reminders-timing',
      _change(original, (json) {
        json['automationRequests'][0]['trigger']['offsetSeconds'] = 60;
      }),
    );
    rejects(
      'reminders-timing',
      _change(original, (json) {
        (json['collections'][0]['fields'] as List).firstWhere(
          (f) => f['id'] == 'reminderAt',
        )['required'] = true;
      }),
    );
    rejects(
      'reminders-name',
      _change(original, (json) {
        (json['collections'][0]['fields'] as List).firstWhere(
          (f) => f['id'] == 'dueAt',
        )['required'] = true;
      }),
    );
  });

  test(
    'calendar category requires the requested Personal and Work choices',
    () {
      rejects(
        'calendar-category',
        _change(bases['calendar-category']!, (json) {
          (json['collections'][0]['fields'] as List).firstWhere(
            (f) => f['id'] == 'category',
          )['choices'] = [
            'Home',
            'Office',
          ];
        }),
      );
    },
  );

  test('focus creates require digital, 25 minutes and requested seconds', () {
    final original = templates['focus']!;
    rejects(
      'focus-duration',
      _viewOptions(original, 'timer', {'durationMinutes': 5}),
    );
    rejects(
      'focus-duration',
      _viewOptions(original, 'clock', {'style': 'analog'}),
    );
    rejects('focus-clock', original);
    final hidden = _change(original, (json) {
      (json['navigation']['pages'][0]['viewIds'] as List).remove('localClock');
      (json['navigation']['pages'] as List).add({
        'id': 'hiddenClock',
        'title': 'Clock',
        'viewIds': ['localClock'],
      });
    });
    rejects('focus-duration', hidden);
  });

  test('Source edit adds optional text to the existing form and details', () {
    final original = bases['notes-fields']!;
    validateCustomizationScenario(
      'notes-fields',
      _source(original),
      baseline: original,
    );
    rejects(
      'notes-fields',
      _source(original, details: false),
      baseline: original,
    );
    rejects(
      'notes-fields',
      _source(original, type: 'integer'),
      baseline: original,
    );
    rejects(
      'notes-fields',
      _change(_source(original), (json) {
        json['navigation']['pages'][0]['title'] = 'Unrequested page rename';
      }),
      baseline: original,
    );
  });

  test(
    'Source recognizes implicit fields and preserves stepped form bindings',
    () {
      final implicit = _change(bases['notes-fields']!, (json) {
        for (final view in json['views']) {
          if ({'form', 'details'}.contains(view['type'])) {
            view.remove('fieldIds');
          }
        }
      });
      validateCustomizationScenario(
        'notes-fields',
        _source(implicit),
        baseline: implicit,
      );
      final stepped = _change(bases['notes-fields']!, (json) {
        for (final view in json['views']) {
          if (view['type'] == 'form') {
            view['options']['steps'] = [
              {
                'id': 'entry',
                'title': 'Entry',
                'fieldIds': ['title', 'body', 'category'],
              },
            ];
          }
        }
      });
      validateCustomizationScenario(
        'notes-fields',
        _source(stepped),
        baseline: stepped,
      );
    },
  );

  test('appearance edits preserve nonrequested settings and content', () {
    for (final id in ['notes-appearance', 'calendar-appearance']) {
      final original = bases[id]!;
      final edited = original.patch({
        'type': 'SetAppearance',
        'appearance': {
          'style': id == 'notes-appearance' ? 'editorial' : 'playful',
          if (id == 'notes-appearance') 'accentColor': '#3B6B5A',
        },
      }, () => 'unused');
      validateCustomizationScenario(id, edited, baseline: original);
      rejects(
        id,
        _change(edited, (json) {
          json['name'] = 'Also renamed';
        }),
        baseline: original,
      );
    }
  });

  test('style switches reset overrides and retain the existing accent', () {
    final original = bases['calendar-appearance']!.patch({
      'type': 'SetAppearance',
      'appearance': {
        'style': 'clean',
        'accentColor': '#123456',
        'typography': 'serif',
        'density': 'compact',
        'corners': 'square',
      },
    }, () => 'unused');
    final edited = original.patch({
      'type': 'SetAppearance',
      'appearance': {'style': 'playful', 'accentColor': '#123456'},
    }, () => 'unused');
    validateCustomizationScenario(
      'calendar-appearance',
      edited,
      baseline: original,
    );
    rejects(
      'calendar-appearance',
      original.patch({
        'type': 'SetAppearance',
        'appearance': {...original.appearance!.toJson(), 'style': 'playful'},
      }, () => 'unused'),
      baseline: original,
    );
  });

  test(
    'Source omitted from a stepped form is rejected by schema validation',
    () {
      final original = _change(bases['notes-fields']!, (json) {
        for (final view in json['views']) {
          if (view['type'] == 'form') {
            view['options']['steps'] = [
              {
                'id': 'entry',
                'title': 'Entry',
                'fieldIds': ['title', 'body', 'category'],
              },
            ];
          }
        }
      });
      expect(
        () => _change(_source(original), (json) {
          for (final view in json['views']) {
            if (view['type'] == 'form') {
              (view['options']['steps'][0]['fieldIds'] as List).remove(
                'source',
              );
            }
          }
        }),
        throwsA(isA<SpecException>()),
      );
    },
  );

  test('rename is exact and cannot also change theme or reminder behavior', () {
    final original = bases['reminders-name']!;
    final edited = original.patch({
      'type': 'RenameLabel',
      'targetId': 'app',
      'label': 'Gentle Reminders',
    }, () => 'unused');
    validateCustomizationScenario('reminders-name', edited, baseline: original);
    rejects(
      'reminders-name',
      _change(edited, (json) {
        json['theme'] = 'amber';
      }),
      baseline: original,
    );
    rejects(
      'reminders-name',
      _change(edited, (json) {
        json['automationRequests'][0]['condition']['value'] = 'Done';
      }),
      baseline: original,
    );
  });

  test(
    'timing edits preserve existing rule identity, field and Open condition',
    () {
      final original = bases['reminders-timing']!;
      final edited = _change(original, (json) {
        json['automationRequests'][0]['trigger']['offsetSeconds'] = 600;
      });
      validateCustomizationScenario(
        'reminders-timing',
        edited,
        baseline: original,
      );
      for (final change in <void Function(Map<String, dynamic>)>[
        (json) {
          json['automationRequests'][0]['id'] = 'differentRule';
        },
        (json) {
          json['automationRequests'][0]['trigger']['fieldId'] = 'dueAt';
        },
        (json) {
          json['automationRequests'][0]['condition']['value'] = 'Done';
        },
        (json) {
          (json['automationRequests'] as List).add({
            ...original.automationRequests.single.toJson(),
            'id': 'extraRule',
          });
        },
      ]) {
        rejects(
          'reminders-timing',
          _change(edited, change),
          baseline: original,
        );
      }
    },
  );

  test(
    'Travel is added to existing Category without other choice or view changes',
    () {
      final original = bases['calendar-category']!;
      final edited = original.patch({
        'type': 'AddChoice',
        'collectionId': 'events',
        'fieldId': 'category',
        'choice': 'Travel',
      }, () => 'unused');
      validateCustomizationScenario(
        'calendar-category',
        edited,
        baseline: original,
      );
      rejects(
        'calendar-category',
        _change(edited, (json) {
          (json['collections'][0]['fields'] as List).firstWhere(
            (f) => f['id'] == 'category',
          )['label'] = 'Trip type';
        }),
        baseline: original,
      );
      final unrelated = original.patch({
        'type': 'AddField',
        'collectionId': 'events',
        'field': {
          'label': 'Category',
          'type': 'choice',
          'choices': ['Travel'],
        },
      }, () => 'newCategory');
      rejects('calendar-category', unrelated, baseline: original);
    },
  );

  test(
    'timer edit preserves the clock and changes the existing timer only',
    () {
      final original = bases['focus-duration']!;
      final edited = _viewOptions(original, 'timer', {'durationMinutes': 40});
      validateCustomizationScenario(
        'focus-duration',
        edited,
        baseline: original,
      );
      rejects(
        'focus-duration',
        _viewOptions(edited, 'clock', {'style': 'analog'}),
        baseline: original,
      );
      rejects(
        'focus-duration',
        _change(edited, (json) {
          (json['views'] as List).singleWhere(
            (v) => v['type'] == 'timer',
          )['label'] = 'Different timer label';
        }),
        baseline: original,
      );
    },
  );

  test(
    'clock edit preserves timer and accepts explicit unchanged clock defaults',
    () {
      final original = bases['focus-clock']!;
      final edited = _viewOptions(original, 'clock', {
        'style': 'analog',
        'showSeconds': false,
        'hourFormat': 'system',
        'showDate': true,
      });
      validateCustomizationScenario('focus-clock', edited, baseline: original);
      rejects(
        'focus-clock',
        _viewOptions(edited, 'timer', {'durationMinutes': 40}),
        baseline: original,
      );
      rejects(
        'focus-clock',
        _viewOptions(edited, 'clock', {'hourFormat': '24'}),
        baseline: original,
      );
    },
  );
}
