import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

import 'client_test.dart' show Fixture;

void main() {
  test(
    'recovery fetch uses the flagged authorized snapshot and keeps validation',
    () async {
      final fixture = Fixture();
      final (_, draft) = await fixture.draft();
      fixture.calls.clear();
      final recovered = await fixture.client.builder.getForRecovery(
        draft.draftId,
      );
      expect(fixture.calls, hasLength(1));
      expect(fixture.calls.single['op'], 'spec.getApp');
      expect(fixture.calls.single['suppressWakeups'], true);
      expect(recovered.candidateHash, draft.candidateHash);
      await fixture.client.close();
    },
  );

  test(
    'recovery fetch rejects an app that does not match the request',
    () async {
      final client = Client(
        'https://offline.invalid/v1',
        transport: (_) async => {
          'app': {
            'id': 'other',
            'workspaceId': 'workspace',
            'name': 'wrong',
            'archived': false,
            'role': 'owner',
          },
        },
      );
      await expectLater(
        () => client.builder.getForRecovery('app'),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'invalid_response',
          ),
        ),
      );
      await client.close();
    },
  );
}
