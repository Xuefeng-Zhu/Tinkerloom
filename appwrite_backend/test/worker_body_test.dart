import 'dart:convert';
import 'package:test/test.dart';
import '../lib/service.dart';
import '../lib/worker_http.dart';

void main() {
  final now = DateTime.utc(2026, 10, 29);
  final wakeups = AppwriteWorkerWakeups(
    Uri.parse('https://example.test/v1'),
    'synthetic-project',
    'synthetic-worker',
    'not-a-real-key',
    clock: () => now,
  );
  tearDownAll(wakeups.close);
  final proof = List.filled(43, 'a').join();
  test('interval empty bodies reconcile without manufacturing a dispatch', () {
    for (final body in ['', '  ', '{}', ' \n{} ']) {
      expect(decodePrivateWorkerBody('schedule', body), isNull);
    }
  });
  test(
    'future Appwrite wakeup retains its proof under the schedule trigger',
    () {
      final body = wakeups.body(
        'synthetic-dispatch',
        proof,
        now.add(const Duration(minutes: 2)),
      );
      expect(body['scheduledAt'], isNotNull);
      expect(body['async'], isTrue);
      final decoded = decodePrivateWorkerBody(
        'schedule',
        body['body'] as String,
      );
      expect(decoded, {'dispatchId': 'synthetic-dispatch', 'proof': proof});
    },
  );
  test('immediate HTTP wakeup has the same strict dispatch shape', () {
    final body = wakeups.body('synthetic-dispatch', proof, now);
    expect(body.containsKey('scheduledAt'), isFalse);
    expect(decodePrivateWorkerBody('http', body['body'] as String), {
      'dispatchId': 'synthetic-dispatch',
      'proof': proof,
    });
  });
  test('empty HTTP body never becomes a privileged reconciliation request', () {
    expect(() => decodePrivateWorkerBody('http', ''), throwsFormatException);
    expect(
      () => decodePrivateWorkerBody('http', '{}'),
      throwsA(isA<ServiceException>()),
    );
  });
  test('unknown trigger, missing proof and extra fields remain rejected', () {
    for (final trigger in ['event', 'http', 'schedule']) {
      for (final body in [
        '[]',
        'null',
        '{"dispatchId":"d"}',
        '{"proof":"p"}',
        '{"dispatchId":"d","proof":"p","reconcile":true}',
      ]) {
        expect(
          () => decodePrivateWorkerBody(trigger, body),
          throwsA(isA<ServiceException>()),
        );
      }
    }
  });
  test('actual UTF8 byte limit rejects before parsing an oversized body', () {
    final body = jsonEncode({
      'dispatchId': 'd',
      'proof': List.filled(2100, 'é').join(),
    });
    expect(body.length, lessThan(4096));
    expect(
      () => decodePrivateWorkerBody('schedule', body),
      throwsA(
        isA<ServiceException>().having(
          (e) => e.code,
          'code',
          'request_too_large',
        ),
      ),
    );
  });
}
