import 'package:test/test.dart';

import '../lib/main.dart' as entrypoint;
import '../lib/service.dart';
import 'spec_engine_check.dart' as fixture;

void main() {
  test('recovery snapshots preserve authorization and validation', () async {
    final (_, service, _) = await fixture.fixture('reading');
    final ordinary = await service.execute('alice', {
      'op': 'spec.getApp',
      'appId': 'app',
    });
    final recovery = await service.execute('alice', {
      'op': 'spec.getApp',
      'appId': 'app',
      'suppressWakeups': true,
    });
    expect(recovery, ordinary);
    await expectLater(
      () => service.execute('alice', {
        'op': 'spec.getApp',
        'appId': 'app',
        'suppressWakeups': 'true',
      }),
      throwsA(
        isA<ServiceException>().having(
          (e) => e.code,
          'code',
          'invalid_request',
        ),
      ),
    );
    await expectLater(
      () => service.execute('bob', {
        'op': 'spec.getApp',
        'appId': 'app',
        'suppressWakeups': true,
      }),
      throwsA(isA<ServiceException>()),
    );
  });

  test('only receipt and flagged snapshot suppress deferred wakeups', () {
    expect(
      entrypoint.shouldFlushWakeups({'op': 'spec.commandReceipt'}),
      isFalse,
    );
    expect(
      entrypoint.shouldFlushWakeups({
        'op': 'spec.getApp',
        'suppressWakeups': true,
      }),
      isFalse,
    );
    expect(entrypoint.shouldFlushWakeups({'op': 'spec.getApp'}), isTrue);
    expect(
      entrypoint.shouldFlushWakeups({
        'op': 'spec.generate',
        'suppressWakeups': true,
      }),
      isTrue,
    );
  });
}
