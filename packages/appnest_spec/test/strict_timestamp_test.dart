import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

void main() {
  test('offset conversion preserves leap-day microseconds', () {
    expect(
      strictTimestamp('2024-02-29T23:59:59.123456-01:30', 'When'),
      '2024-03-01T01:29:59.123456Z',
    );
  });

  test('invalid civil dates and over-precise timestamps are rejected', () {
    for (final invalid in [
      '2025-02-29T00:00:00Z',
      '2026-04-31T00:00:00Z',
      '2026-01-01T24:00:00Z',
      '2026-01-01T00:00:60Z',
      '2026-01-01T00:00:00.1234567Z',
      '2026-01-01T00:00:00',
    ]) {
      expect(
        () => strictTimestamp(invalid, 'When'),
        throwsA(isA<SpecException>()),
      );
    }
  });

  test('field validation uses the backend timestamp contract', () {
    final field = FieldSpec('when', 'When', FieldType.timestamp, false, []);
    expect(
      field.normalize('2026-01-01T01:00:00+01:00'),
      '2026-01-01T00:00:00.000Z',
    );
    expect(
      () => field.normalize('2026-02-30T00:00:00Z'),
      throwsA(isA<SpecException>()),
    );
  });
}
