import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

void main() {
  test(
    'ambiguous generation keeps its exact envelope until receipt confirmation',
    () async {
      final calls = <Map<String, dynamic>>[];
      var confirmed = false;
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (input) async {
          calls.add(jsonDecode(jsonEncode(input)) as Map<String, dynamic>);
          if (input['op'] == 'spec.commandReceipt')
            return {'confirmed': confirmed};
          throw NestError(
            category: 'transaction_conflict',
            message: 'conflict',
            status: 409,
          );
        },
      );
      addTearDown(client.close);
      final command = <String, dynamic>{
        'op': 'spec.generate',
        'appId': 'app',
        'operationId': 'same-operation',
        'expectedRevision': 1,
        'expectedVersionId': null,
        'request': 'Pack for the trip',
        'startFromScratch': true,
      };
      await expectLater(
        client.request(command),
        throwsA(isA<NestError>().having((e) => e.uncertain, 'uncertain', true)),
      );
      final handle = client.pendingBuilderRecovery!;
      expect(handle.operation, 'spec.generate');
      command['request'] = 'changed after send';
      await expectLater(
        client.request({...command, 'operationId': 'other'}),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'pending_command',
          ),
        ),
      );
      expect(
        await client.confirmRetainedBuilderCommand(
          appId: 'app',
          operation: 'spec.generate',
          expectedRevision: 1,
          request: 'Pack for the trip',
          startFromScratch: true,
        ),
        RetainedCommandStatus.pending,
      );
      expect(calls.map((call) => call['op']), [
        'spec.generate',
        'spec.commandReceipt',
      ]);
      expect(calls[1]['command'], calls[0]);
      expect((calls[1]['command'] as Map)['operationId'], 'same-operation');
      confirmed = true;
      expect(
        await client.confirmRetainedBuilderCommand(
          appId: 'app',
          operation: 'spec.generate',
          expectedRevision: 1,
          request: 'Pack for the trip',
          startFromScratch: true,
        ),
        RetainedCommandStatus.confirmed,
      );
      expect(client.pendingBuilderRecovery!.receiptConfirmed, isTrue);
      expect(
        calls.where((call) => call['op'] == 'spec.generate'),
        hasLength(1),
      );
      expect(calls.last['command'], calls.first);
      client.setAsideConfirmedBuilderRecovery(client.pendingBuilderRecovery!);
      expect(client.pendingBuilderRecovery, isNull);
    },
  );

  test(
    'other ambiguous mutations retain and block changed writes without replay',
    () async {
      final calls = <Map<String, dynamic>>[];
      final client = Client(
        'https://offline.invalid',
        auth: ClientAuth()..setSession({'id': 'alice'}),
        transport: (input) async {
          calls.add(input);
          throw NestError(
            category: 'transaction_conflict',
            message: 'conflict',
            status: 409,
          );
        },
      );
      addTearDown(client.close);
      final original = {
        'op': 'spec.execute',
        'appId': 'app',
        'operationId': 'op',
        'value': 'before',
      };
      await expectLater(
        client.request(original),
        throwsA(isA<NestError>().having((e) => e.uncertain, 'uncertain', true)),
      );
      original['value'] = 'after';
      await expectLater(
        client.request({...original}),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'pending_command',
          ),
        ),
      );
      expect(calls, hasLength(1));
      expect(calls.single['value'], 'before');
    },
  );

  test(
    'read conflicts and definite mutation errors do not retain a command',
    () async {
      var count = 0;
      final client = Client(
        'https://offline.invalid',
        auth: ClientAuth()..setSession({'id': 'alice'}),
        transport: (input) async {
          count++;
          if (count == 1)
            throw NestError(
              category: 'transaction_conflict',
              message: 'read conflict',
              status: 409,
            );
          if (count == 2)
            throw NestError(
              category: 'revision_conflict',
              message: 'revision',
              status: 409,
            );
          return {};
        },
      );
      addTearDown(client.close);
      await expectLater(
        client.request({'op': 'spec.capabilities'}),
        throwsA(
          isA<NestError>().having((e) => e.uncertain, 'uncertain', false),
        ),
      );
      await expectLater(
        client.request({
          'op': 'spec.execute',
          'appId': 'app',
          'operationId': 'a',
        }),
        throwsA(
          isA<NestError>().having((e) => e.uncertain, 'uncertain', false),
        ),
      );
      await client.request({'op': 'anotherMutation', 'operationId': 'b'});
      expect(count, 3);
    },
  );

  test('session change fences a conflict recovery handle', () async {
    final auth = ClientAuth()..setSession({'id': 'alice'});
    final calls = <String>[];
    final client = Client(
      'https://offline.invalid',
      auth: auth,
      transport: (input) async {
        calls.add(input['op'] as String);
        throw NestError(
          category: 'transaction_conflict',
          message: 'conflict',
          status: 409,
        );
      },
    );
    addTearDown(client.close);
    await expectLater(
      client.request({
        'op': 'spec.generate',
        'appId': 'app',
        'operationId': 'op',
        'expectedRevision': 1,
        'request': 'idea',
        'startFromScratch': true,
      }),
      throwsA(isA<NestError>().having((e) => e.uncertain, 'uncertain', true)),
    );
    final handle = client.pendingBuilderRecovery!;
    auth.setSession({'id': 'bob'});
    await expectLater(
      client.checkPendingBuilderRecovery(handle),
      throwsA(isA<BackendUnauthorized>()),
    );
    expect(calls, ['spec.generate']);
  });
}
