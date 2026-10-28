import 'package:appnest_server/src/evaluation/nemotron_case_selection.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:test/test.dart';

void main() {
  final available = [...nemotronScenarios(), ...nemotronSequences()];

  test('default selection preserves all 36 cases and their order', () {
    final selected = selectNemotronCases(available);
    expect(selected, orderedEquals(available));
    expect(selected, hasLength(36));
    expect(identical(selected, available), isFalse);
  });

  test('smoke selection includes one creation, fixed edit, and guidance', () {
    final selected = selectNemotronCases(
      available,
      cases:
          'create-notes-fields,edit-notes-fields,guidance-ambiguous-organize',
    );
    expect(selected.map((s) => s.operation), ['create', 'edit', 'guidance']);
    expect(available, hasLength(36));
  });

  test(
    'selection preserves requested order and trims surrounding whitespace',
    () {
      final selected = selectNemotronCases(
        available,
        cases: ' guidance-ambiguous-organize, edit-notes-fields ,create-notes-fields ',
      );
      expect(selected.map((s) => s.id), [
        'guidance-ambiguous-organize',
        'edit-notes-fields',
        'create-notes-fields',
      ]);
    },
  );

  for (final cases in [
    '',
    ',create-notes-fields',
    'create-notes-fields,',
    ' , ',
  ]) {
    test('rejects empty case IDs in "$cases"', () {
      expect(
        () => selectNemotronCases(available, cases: cases),
        throwsA(isA<FormatException>()),
      );
    });
  }

  test('rejects duplicate case IDs after whitespace normalization', () {
    expect(
      () => selectNemotronCases(
        available,
        cases: 'create-notes-fields, create-notes-fields',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unknown IDs instead of silently selecting no cases', () {
    expect(
      () => selectNemotronCases(available, cases: 'create-unknown'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('create-unknown'),
        ),
      ),
    );
  });

  for (final cases in [
    'sequence-notes-fields',
    'sequence-notes-fields,create-notes-fields',
    'create-focus-clock,sequence-notes-fields',
  ]) {
    test('rejects missing or later sequence source in "$cases"', () {
      expect(
        () => selectNemotronCases(available, cases: cases),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('include create-notes-fields before sequence'),
          ),
        ),
      );
    });
  }

  test('accepts a sequence after its corresponding source creation', () {
    final selected = selectNemotronCases(
      available,
      cases: 'create-notes-fields,edit-notes-fields,sequence-notes-fields',
    );
    expect(selected.map((s) => s.id), [
      'create-notes-fields',
      'edit-notes-fields',
      'sequence-notes-fields',
    ]);
    expect(selected.last.sequenceSourceId, selected.first.id);
  });
}
