import 'dart:convert';

import 'package:appnest_server/src/modules/builder/generation_quality.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

void main() {
  test('device-only generated apps need visible device components', () {
    expect(
      () => validateGeneratedExperience(phoneToolkitTemplate()),
      returnsNormally,
    );
    final json = phoneToolkitTemplate().toJson();
    json['views'].add({
      'id': 'intro',
      'type': 'richText',
      'label': 'Intro',
      'options': {'markdown': 'Hello'},
    });
    json['requires'].add('views.richText.v1');
    json['navigation']['pages'].add({
      'id': 'introPage',
      'title': 'Intro',
      'viewIds': ['intro'],
    });
    json['navigation']['entryPageId'] = 'introPage';
    json['navigation']['tabs'] = [
      {'pageId': 'introPage', 'label': 'Intro', 'icon': 'today'},
    ];
    final hidden = AppSpec.parse(jsonEncode(json));
    expect(
      () => validateGeneratedExperience(hidden),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => validateGeneratedExperience(hidden, baseline: hidden),
      returnsNormally,
    );
  });

  test('existing starter experiences expose their editable collections', () {
    for (final entry in starterTemplates().entries) {
      expect(
        () => validateGeneratedExperience(entry.value),
        returnsNormally,
        reason: entry.key,
      );
    }
  });

  test('a schema-valid hidden create control is rejected for generation', () {
    final json = starterTemplates()['planner']!.toJson();
    for (final page in json['navigation']['pages'] as List) {
      (page as Map).remove('primaryActionId');
    }
    for (final view in json['views'] as List) {
      if (view['type'] != 'form') {
        (view['actionIds'] as List).remove('addTask');
      }
    }
    final spec = AppSpec.parse(jsonEncode(json));
    expect(
      () => validateGeneratedExperience(spec),
      throwsA(isA<SpecException>()),
    );
  });

  test('a hidden edit form alone is not a reachable record edit', () {
    final json = starterTemplates()['planner']!.toJson();
    for (final view in json['views'] as List) {
      if (view['type'] != 'form') {
        (view['actionIds'] as List).remove('editTask');
      }
    }
    final spec = AppSpec.parse(jsonEncode(json));
    expect(
      () => validateGeneratedExperience(spec),
      throwsA(isA<SpecException>()),
    );
  });

  test('unreachable edit diagnostics name an unambiguous candidate route', () {
    final json = jsonDecode(creationReferenceJson) as Map<String, dynamic>;
    for (final view in json['views'] as List) {
      if (view['type'] != 'form') {
        (view['actionIds'] as List).remove('editBook');
      }
    }
    final spec = AppSpec.parse(jsonEncode(json));
    expect(
      () => validateGeneratedExperience(spec),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'repair graph',
          allOf(
            contains('include edit action "editBook" in actionIds'),
            contains('formPageId:"bookFormPage"'),
            contains('source.detailPageId'),
          ),
        ),
      ),
    );
  });

  test('ambiguous visible sources are rejected without selecting a binding by order', () {
    final json = jsonDecode(creationReferenceJson) as Map<String, dynamic>;
    final otherList = jsonDecode(jsonEncode(json['views'][0])) as Map;
    otherList['id'] = 'otherBookList';
    json['views'].add(otherList);
    json['navigation']['pages'][0]['viewIds'].add('otherBookList');
    for (final view in json['views'] as List) {
      if (view['type'] != 'form') {
        (view['actionIds'] as List).remove('editBook');
      }
    }
    final ambiguous = AppSpec.parse(jsonEncode(json));
    expect(
      () => validateGeneratedExperience(ambiguous),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'no guessed route',
          allOf(
            contains('reachable edit control'),
            isNot(contains('On visible view "bookList"')),
            isNot(contains('On visible view "otherBookList"')),
          ),
        ),
      ),
    );
    expect(
      () => validateGeneratedExperience(ambiguous, baseline: ambiguous),
      returnsNormally,
    );
  });

  test('direct list editing cannot conceal an orphaned details page', () {
    final json = dailyPlannerTemplate().toJson();
    for (final view in json['views'] as List) {
      if (view['type'] != 'summary') {
        (view as Map).remove('detailPageId');
      }
    }
    final orphaned = AppSpec.parse(jsonEncode(json));
    expect(
      () => validateGeneratedExperience(orphaned),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'route',
          allOf(
            contains('dedicated details page'),
            contains('detailPageId:"taskDetailPage"'),
          ),
        ),
      ),
    );
    expect(
      () => validateGeneratedExperience(orphaned, baseline: orphaned),
      returnsNormally,
    );
    expect(
      () => validateGeneratedExperience(
        orphaned,
        baseline: dailyPlannerTemplate(),
      ),
      throwsA(isA<SpecException>()),
    );
  });

  test('a declared workflow action must be exposed on a main or linked record view', () {
    final json = dailyPlannerTemplate().toJson();
    final workflow = (json['actions'] as List).singleWhere(
      (action) => action['capability'] == 'workflow.transition.v1',
    )['id'];
    for (final view in json['views'] as List) {
      (view['actionIds'] as List).remove(workflow);
    }
    // An aggregate is not a record action route even if it declares the ID.
    (json['views'] as List)
        .firstWhere((view) => view['type'] == 'summary')['actionIds']
        .add(workflow);
    final hidden = AppSpec.parse(jsonEncode(json));
    expect(
      () => validateGeneratedExperience(hidden),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'action route',
          allOf(
            contains('Action "$workflow"'),
            contains('visible record route'),
          ),
        ),
      ),
    );
    expect(
      () => validateGeneratedExperience(hidden, baseline: hidden),
      returnsNormally,
    );
  });

  test(
    'member assignment on an orphaned details page is not a visible route',
    () {
      final json = jsonDecode(creationReferenceJson) as Map<String, dynamic>;
      json['policyPresetRequest'] = 'groupWorkflow.v1';
      json['requires'].addAll(['assignment.v1', 'assignment.assign.v1']);
      json['collections'][0]['fields'].add({
        'id': 'assignee',
        'label': 'Assignee',
        'type': 'member',
        'required': false,
      });
      json['collections'][0]['behaviors'].add({
        'id': 'assign',
        'type': 'assignment.v1',
        'fieldId': 'assignee',
      });
      json['actions'].add({
        'id': 'assignBook',
        'label': 'Assign',
        'capability': 'assignment.assign.v1',
        'collectionId': 'books',
        'behaviorId': 'assign',
      });
      json['views'][1]['actionIds'].add('assignBook');
      (json['views'][0] as Map).remove('detailPageId');
      final hidden = AppSpec.parse(jsonEncode(json));
      expect(
        () => validateGeneratedExperience(hidden),
        throwsA(
          isA<SpecException>().having(
            (error) => error.message,
            'complete repair diagnostics',
            allOf(
              contains('detailPageId:"bookDetailsPage"'),
              contains('Action "assignBook"'),
            ),
          ),
        ),
      );
      json['views'][0]['detailPageId'] = 'bookDetailsPage';
      expect(
        () => validateGeneratedExperience(AppSpec.parse(jsonEncode(json))),
        returnsNormally,
      );
    },
  );

  test(
    'capacity actions require a visible route in navigation-backed apps',
    () {
      final json = jsonDecode(creationReferenceJson) as Map<String, dynamic>;
      json['policyPresetRequest'] = 'groupCapacitySignup.v1';
      json['requires'].addAll(['capacity.v1', 'capacity.claim.v1']);
      json['collections'][0]['behaviors'].add({
        'id': 'places',
        'type': 'capacity.v1',
      });
      json['actions'].add({
        'id': 'join',
        'label': 'Join',
        'capability': 'capacity.claim.v1',
        'collectionId': 'books',
        'behaviorId': 'places',
      });
      final hidden = AppSpec.parse(jsonEncode(json));
      expect(
        () => validateGeneratedExperience(hidden),
        throwsA(
          isA<SpecException>().having(
            (error) => error.message,
            'capacity route',
            contains('Action "join"'),
          ),
        ),
      );
      json['views'][1]['actionIds'].add('join');
      expect(
        () => validateGeneratedExperience(AppSpec.parse(jsonEncode(json))),
        returnsNormally,
      );
    },
  );

  test('read-only collections are not required to offer CRUD', () {
    final json = starterTemplates()['reading']!.toJson();
    json['actions'] = <Object>[];
    for (final view in json['views'] as List) {
      view['actionIds'] = <Object>[];
    }
    // The legacy list/details fixture renders read-only records directly.
    (json['views'] as List).removeWhere((view) => view['type'] == 'form');
    final spec = AppSpec.parse(jsonEncode(json));
    expect(() => validateGeneratedExperience(spec), returnsNormally);
  });

  test(
    'behavior-only collections still require reachable declared actions',
    () {
      final json = jsonDecode(creationReferenceJson) as Map<String, dynamic>;
      json['policyPresetRequest'] = 'groupCapacitySignup.v1';
      json['requires'].addAll(['capacity.v1', 'capacity.claim.v1']);
      json['collections'][0]['behaviors'].add({
        'id': 'places',
        'type': 'capacity.v1',
      });
      final removed = (json['actions'] as List)
          .where(
            (action) => (action['capability'] as String).startsWith('records.'),
          )
          .map((action) => action['id'])
          .toSet();
      (json['actions'] as List).removeWhere(
        (action) => removed.contains(action['id']),
      );
      json['actions'].add({
        'id': 'join',
        'label': 'Join',
        'capability': 'capacity.claim.v1',
        'collectionId': 'books',
        'behaviorId': 'places',
      });
      (json['views'] as List).removeWhere((view) => view['type'] == 'form');
      (json['navigation']['pages'] as List).removeWhere(
        (page) => page['id'] == 'bookFormPage',
      );
      for (final page in json['navigation']['pages'] as List) {
        (page as Map).remove('primaryActionId');
      }
      for (final view in json['views'] as List) {
        (view['actionIds'] as List).removeWhere(removed.contains);
        (view as Map).remove('formPageId');
      }
      final hidden = AppSpec.parse(jsonEncode(json));
      expect(
        () => validateGeneratedExperience(hidden),
        throwsA(
          isA<SpecException>().having(
            (error) => error.message,
            'behavior route without CRUD',
            allOf(
              contains('Action "join"'),
              isNot(contains('both create and edit')),
            ),
          ),
        ),
      );
      json['views'][1]['actionIds'].add('join');
      expect(
        () => validateGeneratedExperience(AppSpec.parse(jsonEncode(json))),
        returnsNormally,
      );
    },
  );

  test(
    'summary action IDs and summary detail links do not expose a record editor',
    () {
      final json = starterTemplates()['planner']!.toJson();
      for (final view in json['views'] as List) {
        if (view['type'] != 'form') {
          (view['actionIds'] as List).remove('editTask');
        }
      }
      final summary = (json['views'] as List).firstWhere(
        (view) => view['id'] == 'todaySummary',
      );
      (summary['actionIds'] as List).add('editTask');
      summary['detailPageId'] = 'taskDetailPage';
      final hidden = AppSpec.parse(jsonEncode(json));
      expect(
        () => validateGeneratedExperience(hidden),
        throwsA(isA<SpecException>()),
      );
      expect(
        () => validateGeneratedExperience(
          hidden,
          baseline: starterTemplates()['planner']!,
        ),
        throwsA(isA<SpecException>()),
      );
    },
  );

  test(
    'existing append-only apps can be renamed without new CRUD requirements',
    () {
      final json = starterTemplates()['reading']!.toJson();
      final removed = (json['actions'] as List)
          .where((action) => action['capability'] == 'records.patch.v1')
          .map((action) => action['id'])
          .toSet();
      (json['actions'] as List).removeWhere(
        (action) => removed.contains(action['id']),
      );
      for (final view in json['views'] as List) {
        (view['actionIds'] as List).removeWhere(removed.contains);
      }
      final original = AppSpec.parse(jsonEncode(json));
      final renamed = original.patch({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': 'My existing collection',
      }, () => throw StateError('No IDs'));
      expect(
        () => validateGeneratedExperience(renamed),
        throwsA(isA<SpecException>()),
      );
      expect(
        () => validateGeneratedExperience(renamed, baseline: original),
        returnsNormally,
      );
    },
  );
}
