import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

void main() {
  test(
    'field rename is collection scoped and preserves schema and bindings',
    () {
      final json = starterTemplates()['reading']!.toJson();
      final first = (json['collections'] as List).first as Map<String, dynamic>;
      (json['collections'] as List).add({
        ...first,
        'id': 'otherBooks',
        'behaviors': [],
      });
      final before = AppSpec.parse(jsonEncode(json));
      final collection = before.collections.first;
      final field = collection.fields.first;
      final patch = {
        'type': 'RenameField',
        'collectionId': collection.id,
        'fieldId': field.id,
        'label': 'Book title',
      };
      final after = before.patch(
        patch,
        () => throw StateError('No allocation'),
      );
      expect(
        after.collection(collection.id).field(field.id).label,
        'Book title',
      );
      expect(after.collection('otherBooks').field(field.id).label, field.label);
      expect(after.compatibilityErrors(before), isEmpty);
      expect(
        after.views.map((v) => v.toJson()),
        before.views.map((v) => v.toJson()),
      );
      for (final invalid in [
        {...patch, 'collectionId': 'missing'},
        {...patch, 'fieldId': 'missing'},
        {...patch, 'label': ' '},
        {...patch, 'label': 'x' * 161},
        {...patch, 'targetId': 'app'},
      ]) {
        expect(
          () => before.patch(invalid, () => 'unused'),
          throwsA(isA<SpecException>()),
        );
      }
      expect(
        () => before.patch({
          'type': 'RenameLabel',
          'targetId': field.id,
          'label': 'Ambiguous',
        }, () => 'unused'),
        throwsA(isA<SpecException>()),
      );
    },
  );
}
