import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

void main() {
  final invalid = throwsA(isA<SpecException>());

  test('AddField binds the allocated identity to selected form and details atomically', () {
    final before = notesTemplate(), beforeJson = notesTemplate().canonical;
    var allocations = 0;
    final after = before.patch(
      {
        'type': 'AddField',
        'collectionId': 'notes',
        'field': {'label': 'Source', 'type': 'text'},
        'viewIds': ['entryEditor', 'entryDetails'],
      },
      () {
        allocations++;
        return 'allocatedSource';
      },
    );

    expect(allocations, 1);
    final field = after.collection('notes').field('allocatedSource');
    expect(field.label, 'Source');
    expect(field.required, isFalse);
    for (final id in ['entryEditor', 'entryDetails']) {
      expect(after.view(id).fieldIds, [...before.view(id).fieldIds, field.id]);
      final expected = before.view(id).toJson();
      expected['fieldIds'] = [...before.view(id).fieldIds, field.id];
      expect(after.view(id).toJson(), expected);
    }
    expect(
      after.view('allEntries').toJson(),
      before.view('allEntries').toJson(),
    );
    expect(after.navigation!.toJson(), before.navigation!.toJson());
    expect(before.compatibilityErrors(after), isEmpty);
    expect(before.canonical, beforeJson);
  });

  for (final type in ['list', 'table']) {
    for (final implicit in [false, true]) {
      test(
        'AddField binds Priority to $type, details and editor with ${implicit ? 'implicit' : 'explicit'} fields',
        () {
          final json = notesTemplate().toJson();
          final overview = (json['views'] as List).singleWhere(
            (view) => view['id'] == 'allEntries',
          );
          overview['type'] = type;
          if (implicit) overview.remove('fieldIds');
          if (type == 'table') (json['requires'] as List).add('views.table.v1');
          final before = AppSpec.parse(jsonEncode(json));
          var allocations = 0;
          final renamed = before.patch({
            'type': 'RenameLabel',
            'targetId': 'app',
            'label': 'Priority Notes',
          }, () => throw StateError('Rename must not allocate an ID'));
          final after = renamed.patch(
            {
              'type': 'AddField',
              'collectionId': 'notes',
              'field': {
                'label': 'Priority',
                'type': 'choice',
                'required': false,
                'choices': ['Low', 'Normal', 'High'],
              },
              'viewIds': ['allEntries', 'entryDetails', 'entryEditor'],
            },
            () {
              allocations++;
              return 'allocatedPriority';
            },
          );

          expect(allocations, 1);
          expect(after.name, 'Priority Notes');
          expect(after.collection('notes').fields.last.toJson(), {
            'id': 'allocatedPriority',
            'label': 'Priority',
            'type': 'choice',
            'required': false,
            'choices': ['Low', 'Normal', 'High'],
          });
          final expected = renamed.toJson();
          (expected['collections'][0]['fields'] as List).add(
            after.collection('notes').fields.last.toJson(),
          );
          for (final target in expected['views'] as List) {
            if (target['fieldIds'] != null) {
              (target['fieldIds'] as List).add('allocatedPriority');
            }
          }
          // Complete equality protects existing IDs, field order, options,
          // query/filter bindings, actions and navigation from collateral edits.
          expect(after.canonical, canonicalJson(expected));
          expect(before.compatibilityErrors(after), isEmpty);
          expect(before.canonical, canonicalJson(json));
          expect(AppSpec.parse(after.canonical).hash, after.hash);
        },
      );
    }
  }

  test(
    'AddField extends the final step while preserving implicit all-field views',
    () {
      final before = photoJournalTemplate();
      expect(before.view('editor').fieldIds, isEmpty);
      expect(before.view('details').fieldIds, isEmpty);
      final oldSteps = before.view('editor').options['steps'] as List;
      final after = before.patch({
        'type': 'AddField',
        'collectionId': 'memories',
        'field': {'label': 'Source', 'type': 'text'},
        'viewIds': ['editor', 'details'],
      }, () => 'allocatedSource');
      final steps = after.view('editor').options['steps'] as List;
      expect(steps.length, oldSteps.length);
      expect(steps.take(steps.length - 1), oldSteps.take(oldSteps.length - 1));
      expect(steps.last, {
        ...oldSteps.last as Map,
        'fieldIds': [...oldSteps.last['fieldIds'] as List, 'allocatedSource'],
      });
      expect(
        after.view('editor').options['controls'],
        before.view('editor').options['controls'],
      );
      for (final id in ['editor', 'details']) {
        expect(after.view(id).fieldIds, isEmpty);
        expect(after.view(id).toJson().containsKey('fieldIds'), isFalse);
      }
      expect(before.compatibilityErrors(after), isEmpty);
      expect(AppSpec.parse(after.canonical).hash, after.hash);
    },
  );

  test('AddField maintains every implicit stepped form when binding selected views', () {
    final json = photoJournalTemplate().toJson();
    final editor = (json['views'] as List).singleWhere(
      (view) => view['id'] == 'editor',
    );
    (json['views'] as List).add({
      ...jsonDecode(jsonEncode(editor)) as Map<String, dynamic>,
      'id': 'secondEditor',
    });
    (json['views'] as List).add({
      ...jsonDecode(jsonEncode(editor)) as Map<String, dynamic>,
      'id': 'explicitEditor',
      'fieldIds': [
        for (final field in json['collections'][0]['fields']) field['id'],
      ],
    });
    final before = AppSpec.parse(jsonEncode(json));
    final patch = {
      'type': 'AddField',
      'collectionId': 'memories',
      'field': {'label': 'Source', 'type': 'text'},
    };
    for (final targets in [
      ['editor', 'details'],
      ['details'],
      <String>[],
    ]) {
      final after = before.patch({
        ...patch,
        'viewIds': targets,
      }, () => 'allocatedSource');
      for (final id in ['editor', 'secondEditor']) {
        final originalSteps = before.view(id).options['steps'] as List;
        final steps = after.view(id).options['steps'] as List;
        expect(after.view(id).fieldIds, isEmpty);
        expect(
          steps.take(steps.length - 1),
          originalSteps.take(steps.length - 1),
        );
        expect(steps.last, {
          ...originalSteps.last as Map,
          'fieldIds': [
            ...originalSteps.last['fieldIds'] as List,
            'allocatedSource',
          ],
        });
      }
      expect(
        after.view('explicitEditor').toJson(),
        before.view('explicitEditor').toJson(),
      );
      expect(after.navigation!.toJson(), before.navigation!.toJson());
      expect(before.compatibilityErrors(after), isEmpty);
      expect(AppSpec.parse(after.canonical).hash, after.hash);
    }
    // Omitting the atomic-binding contract retains the legacy validation.
    expect(() => before.patch(patch, () => 'allocatedSource'), invalid);
    expect(before.canonical, canonicalJson(json));
  });

  test(
    'AddField preserves the existing behavior when viewIds is omitted or empty',
    () {
      final before = notesTemplate();
      final patch = {
        'type': 'AddField',
        'collectionId': 'notes',
        'field': {'label': 'Source', 'type': 'text'},
      };
      final omitted = before.patch(patch, () => 'allocatedSource');
      final empty = before.patch({
        ...patch,
        'viewIds': <String>[],
      }, () => 'allocatedSource');
      expect(omitted.hash, empty.hash);
      expect(
        omitted.views.map((v) => v.toJson()),
        before.views.map((v) => v.toJson()),
      );
      final expected = before.toJson();
      (expected['collections'][0]['fields'] as List).add({
        'id': 'allocatedSource',
        'label': 'Source',
        'type': 'text',
        'required': false,
      });
      expect(omitted.canonical, canonicalJson(expected));
    },
  );

  test('AddField validates target references before allocating a field', () {
    final json = notesTemplate().toJson();
    (json['collections'] as List).add(<String, dynamic>{
      ...json['collections'][0] as Map<String, dynamic>,
      'id': 'otherNotes',
    });
    (json['views'] as List).add({
      'id': 'otherDetails',
      'type': 'details',
      'collectionId': 'otherNotes',
    });
    (json['views'] as List).add({
      'id': 'otherList',
      'type': 'list',
      'collectionId': 'otherNotes',
    });
    (json['views'] as List).add({
      'id': 'summary',
      'type': 'summary',
      'collectionId': 'notes',
    });
    (json['requires'] as List).add('views.summary.v1');
    final before = AppSpec.parse(jsonEncode(json));
    for (final viewIds in [
      ['entryEditor', 'entryEditor'],
      ['missingView'],
      ['otherDetails'],
      ['otherList'],
      ['summary'],
      ['entryEditor', 'summary'],
      ['bad id'],
      List.generate(Limits.views + 1, (index) => 'view$index'),
      'entryEditor',
      null,
    ]) {
      var allocations = 0;
      expect(
        () => before.patch(
          {
            'type': 'AddField',
            'collectionId': 'notes',
            'field': {'label': 'Source', 'type': 'text'},
            'viewIds': viewIds,
          },
          () {
            allocations++;
            return 'allocatedSource';
          },
        ),
        invalid,
        reason: '$viewIds',
      );
      expect(allocations, 0, reason: '$viewIds');
    }
  });

  test(
    'AddField binding keeps field limits and compatibility checks intact',
    () {
      final json = notesTemplate().toJson();
      final fields = json['collections'][0]['fields'] as List;
      while (fields.length < Limits.fields) {
        fields.add({
          'id': 'extra${fields.length}',
          'label': 'Extra',
          'type': 'text',
          'required': false,
        });
      }
      final full = AppSpec.parse(jsonEncode(json)),
          unchanged = canonicalJson(json);
      expect(
        () => full.patch({
          'type': 'AddField',
          'collectionId': 'notes',
          'field': {'label': 'Too many', 'type': 'text'},
          'viewIds': ['entryEditor'],
        }, () => 'allocatedSource'),
        invalid,
      );
      expect(full.canonical, unchanged);

      final before = notesTemplate();
      final required = before.patch({
        'type': 'AddField',
        'collectionId': 'notes',
        'field': {'label': 'Source', 'type': 'text', 'required': true},
        'viewIds': ['entryEditor', 'entryDetails'],
      }, () => 'allocatedSource');
      expect(
        before.compatibilityErrors(required),
        contains('Required field Source needs a backfill'),
      );
    },
  );
}
