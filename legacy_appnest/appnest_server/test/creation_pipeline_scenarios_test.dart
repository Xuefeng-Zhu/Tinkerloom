import 'dart:convert';

import 'package:appnest_server/src/modules/builder/creation_pipeline_scenarios.dart';
import 'package:appnest_server/src/modules/builder/creation_plan.dart';
import 'package:appnest_server/src/modules/builder/generation_quality.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

Map<String, dynamic> _field(
  String id,
  String label,
  String type,
  bool required, {
  List<String>? choices,
}) => {
  'id': id,
  'label': label,
  'type': type,
  'required': required,
  'choices': ?choices,
};

/// Independent test authoring, never a candidate supplied to live evaluation.
Map<String, dynamic> _plan({required bool team}) => {
  'creationPlanVersion': 1,
  'plan': {
    'name': team ? 'Repair queue' : 'Reading journal',
    'theme': 'sage',
    'icon': team ? 'board' : 'book',
    'policyPresetRequest': team ? 'groupWorkflow.v1' : 'personalTracker.v1',
    'appearance': {'style': team ? 'clean' : 'editorial'},
    'collections': [
      {
        'id': 'items',
        'label': team ? 'Repairs' : 'Books',
        'fields': [
          _field('title', 'Title', 'text', true),
          if (team) ...[
            _field(
              'stage',
              'Stage',
              'choice',
              true,
              choices: ['Queued', 'Resolved'],
            ),
            _field('estimate', 'Estimate', 'integer', false),
            _field('writing', 'Notes', 'text', false),
          ] else ...[
            _field('author', 'Author', 'text', false),
            _field('finished', 'Finished', 'boolean', true),
            _field('writing', 'Review', 'text', false),
          ],
        ],
        'behaviors': [
          if (team)
            {
              'type': 'workflow.v1',
              'fieldId': 'stage',
              'transitions': {
                'Queued': ['Resolved'],
                'Resolved': ['Queued'],
              },
            },
        ],
        'operations': [
          {'type': 'create', 'label': 'Add item'},
          {'type': 'edit', 'label': 'Edit item'},
          if (team)
            {'type': 'transition', 'label': 'Change stage', 'fieldId': 'stage'},
        ],
        'form': {
          'type': 'form',
          'label': 'Item editor',
          'fieldIds': team
              ? ['title', 'estimate', 'writing']
              : ['title', 'author', 'finished', 'writing'],
          'options': {
            'controls': [
              {'fieldId': 'writing', 'control': 'multiline'},
            ],
          },
        },
        'details': {'type': 'details', 'label': 'Item details'},
      },
    ],
    'pages': [
      {
        'key': 'home',
        'title': 'Items',
        'tab': {'label': 'Items', 'icon': 'list'},
        'components': [
          {
            'type': 'list',
            'collectionId': 'items',
            'label': 'Items',
            'titleFieldId': 'title',
          },
          if (team)
            {
              'type': 'board',
              'collectionId': 'items',
              'label': 'Stages',
              'groupByFieldId': 'stage',
              'options': {'draggable': true},
            }
          else
            {
              'type': 'checklist',
              'collectionId': 'items',
              'label': 'Finished books',
              'options': {'fieldId': 'finished'},
            },
        ],
      },
    ],
    'entryPageKey': 'home',
    'automationRequests': [],
  },
};

Map<String, dynamic> _definition({required bool team}) =>
    compileCreationPlan(_plan(team: team));

NemotronScenario _scenario({required bool team}) =>
    creationPipelineTransferScenarios().singleWhere(
      (scenario) =>
          scenario.id == 'create-transfer-${team ? 'team' : 'reading'}',
    );

void _validate(Map<String, dynamic> definition, {required bool team}) {
  // Negative transfer cases below are real valid AppSpecs; the extra request
  // scorer, rather than syntax/graph rejection, must catch each lost feature.
  final spec = AppSpec.parse(jsonEncode(definition));
  validateGeneratedExperience(spec);
  _scenario(team: team).validate(definition, spec);
}

Map<String, dynamic> _view(Map<String, dynamic> definition, String type) =>
    (definition['views'] as List).cast<Map<String, dynamic>>().singleWhere(
      (view) => view['type'] == type,
    );

Map<String, dynamic> _home(Map<String, dynamic> definition) =>
    (definition['navigation']['pages'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (page) => page['id'] == definition['navigation']['entryPageId'],
        );

Matcher get _transferFailure => throwsA(isA<SpecException>());

void main() {
  for (final team in [false, true]) {
    final label = team ? 'team' : 'reading';
    final feature = team ? 'board' : 'checklist';

    test('$label transfer accepts the complete independently authored app', () {
      expect(
        () => _validate(_definition(team: team), team: team),
        returnsNormally,
      );
    });

    for (final orphan in [false, true]) {
      test('$label rejects ${orphan ? 'orphaned' : 'hidden'} $feature', () {
        final definition = _definition(team: team);
        final view = _view(definition, feature);
        (_home(definition)['viewIds'] as List).remove(view['id']);
        if (!orphan) {
          (definition['navigation']['pages'] as List).add({
            'id': 'hiddenFeature',
            'title': 'Hidden feature',
            'viewIds': [view['id']],
          });
        }
        final valid = AppSpec.parse(jsonEncode(definition));
        expect(() => validateGeneratedExperience(valid), returnsNormally);
        expect(
          () => _scenario(team: team).validate(definition, valid),
          _transferFailure,
        );
      });
    }

    test(
      '$label rejects a plain text control instead of multiline writing',
      () {
        final definition = _definition(team: team);
        _view(definition, 'form')['options']['controls'][0]['control'] = 'text';
        final valid = AppSpec.parse(jsonEncode(definition));
        expect(() => validateGeneratedExperience(valid), returnsNormally);
        expect(
          () => _scenario(team: team).validate(definition, valid),
          throwsA(
            isA<SpecException>().having(
              (error) => error.message,
              'writing requirement',
              contains('multiline'),
            ),
          ),
        );
      },
    );

    test('$label rejects wrong optional writing-field requiredness', () {
      final definition = _definition(team: team);
      final field = (definition['collections'][0]['fields'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((field) => field['id'] == 'writing');
      field['required'] = true;
      final valid = AppSpec.parse(jsonEncode(definition));
      expect(() => validateGeneratedExperience(valid), returnsNormally);
      expect(
        () => _scenario(team: team).validate(definition, valid),
        throwsA(
          isA<SpecException>().having(
            (error) => error.message,
            'literal field requiredness',
            contains('requiredness'),
          ),
        ),
      );
    });
  }

  test('reading rejects a hidden searchable list with a visible checklist', () {
    final definition = _definition(team: false);
    final list = _view(definition, 'list');
    (_home(definition)['viewIds'] as List).remove(list['id']);
    final valid = AppSpec.parse(jsonEncode(definition));
    expect(() => validateGeneratedExperience(valid), returnsNormally);
    expect(
      () => _scenario(team: false).validate(definition, valid),
      _transferFailure,
    );
  });

  test(
    'reading rejects a create-only shared form despite a valid edit route',
    () {
      final definition = _definition(team: false);
      final form = _view(definition, 'form');
      final create = (definition['actions'] as List).singleWhere(
        (action) => action['capability'] == 'records.create.v1',
      )['id'];
      final edit = (definition['actions'] as List).singleWhere(
        (action) => action['capability'] == 'records.patch.v1',
      )['id'];
      final editForm = jsonDecode(jsonEncode(form)) as Map<String, dynamic>;
      editForm['id'] = 'separateEditForm';
      (definition['views'] as List).add(editForm);
      (definition['navigation']['pages'] as List).add({
        'id': 'separateEditPage',
        'title': 'Separate editor',
        'viewIds': [editForm['id']],
      });
      form['actionIds'] = [create];
      _view(definition, 'list')['actionIds'] = [create];
      _view(definition, 'details')['formPageId'] = 'separateEditPage';
      final checklist = _view(definition, 'checklist');
      checklist['actionIds'] = [edit];
      checklist['formPageId'] = 'separateEditPage';
      final valid = AppSpec.parse(jsonEncode(definition));
      expect(() => validateGeneratedExperience(valid), returnsNormally);
      expect(
        () => _scenario(team: false).validate(definition, valid),
        throwsA(
          isA<SpecException>().having(
            (error) => error.message,
            'shared form',
            contains('shared form'),
          ),
        ),
      );
    },
  );

  test(
    'team rejects reordered choices even with otherwise valid transitions',
    () {
      final definition = _definition(team: true);
      final stage = (definition['collections'][0]['fields'] as List)
          .singleWhere(
            (field) => field['id'] == 'stage',
          );
      stage['choices'] = ['Resolved', 'Queued'];
      final valid = AppSpec.parse(jsonEncode(definition));
      expect(() => validateGeneratedExperience(valid), returnsNormally);
      expect(
        () => _scenario(team: true).validate(definition, valid),
        _transferFailure,
      );
    },
  );

  test('team rejects a one-way workflow instead of reversible transitions', () {
    final definition = _definition(team: true);
    definition['collections'][0]['behaviors'][0]['transitions']['Resolved'] =
        <String>[];
    final valid = AppSpec.parse(jsonEncode(definition));
    expect(() => validateGeneratedExperience(valid), returnsNormally);
    expect(
      () => _scenario(team: true).validate(definition, valid),
      _transferFailure,
    );
  });
}
