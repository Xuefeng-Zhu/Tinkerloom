import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

import '../live_smoke/create_recovery.dart';

ActionRequest command() => ActionRequest(
  appId: 'synthetic-app',
  actionId: 'addNote',
  expectedDefinitionVersionId: 'synthetic-version',
  input: {
    'data': {'title': 'Synthetic retained smoke record'},
  },
  idempotencyKey: 'synthetic-fixed-operation',
);

Future<SmokeCreateRecovery> prepare(
  Directory directory,
  ActionRequest request,
) => SmokeCreateRecovery.prepare(
  directory: directory,
  request: request,
  endpoint: 'https://appwrite.invalid/v1',
  projectId: 'synthetic-project',
  functionId: 'synthetic-function',
  actorId: 'synthetic-actor',
  collectionId: 'notes',
);

void main() {
  test('lost reply freezes budget and keeps the exact restricted predispatch receipt after disposal', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tinkerloom-recovery-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final original = command();
    final recovery = await prepare(directory, original);
    final before =
        jsonDecode(await recovery.file.readAsString()) as Map<String, dynamic>;
    expect(before['status'], 'unconfirmed');
    expect(before['request'], original.toJson());
    expect(
      before['wireRequest']['operationId'],
      'o${sha256.convert(utf8.encode(original.idempotencyKey)).toString().substring(0, 32)}',
    );
    expect((await recovery.file.stat()).mode & 0x1ff, 0x180); // 0600
    expect((await directory.stat()).mode & 0x1ff, 0x1c0); // 0700
    original.input['data']['title'] = 'Changed after freezing';
    final budget = RequestBudget();
    var dispatches = 0;
    Map<String, dynamic>? dispatched;
    final client = Client(
      'https://offline.invalid',
      budget: budget,
      transport: (input) async {
        dispatches++;
        dispatched = input;
        throw BackendNetworkException(
          'Synthetic reply lost after commit',
          uncertain: true,
        );
      },
    );
    await expectLater(() async {
      try {
        await client.runtime.execute(recovery.request);
      } catch (_) {
        await recovery.markUncertain();
        rethrow;
      }
    }(), throwsA(isA<BackendNetworkException>()));
    await client.close();
    expect(dispatches, 1);
    expect(budget.stopped, true);
    expect(dispatched, before['wireRequest']);
    expect(
      recovery.request.input['data']['title'],
      'Synthetic retained smoke record',
    );
    final after =
        jsonDecode(await recovery.file.readAsString()) as Map<String, dynamic>;
    expect(after['status'], 'uncertain');
    expect(after['request'], before['request']);
    expect(after['wireRequest'], before['wireRequest']);
    expect(after['requestSha256'], before['requestSha256']);
    expect(after.containsKey('confirmedRecordId'), false);
    expect(
      recovery.sanitized.keys,
      unorderedEquals(['status', 'path', 'requestSha256']),
    );
    expect(
      jsonEncode(recovery.sanitized),
      isNot(contains('Synthetic retained smoke record')),
    );
    await expectLater(
      prepare(directory, command()),
      throwsA(isA<StateError>()),
    );
  });

  test('acknowledged create marks the retained envelope confirmed without changing its operation', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tinkerloom-recovery-ack-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final recovery = await prepare(directory, command());
    final hash = recovery.requestSha256;
    await recovery.markConfirmed(
      ActionOutcome(
        recordId: 'synthetic-record',
        revision: 1,
        message: 'Saved',
      ),
    );
    final receipt =
        jsonDecode(await recovery.file.readAsString()) as Map<String, dynamic>;
    expect(receipt['status'], 'confirmed');
    expect(receipt['confirmedRecordId'], 'synthetic-record');
    expect(receipt['requestSha256'], hash);
    expect(receipt['request']['idempotencyKey'], 'synthetic-fixed-operation');
    expect((await recovery.file.stat()).mode & 0x1ff, 0x180);
    await recovery.markUncertain();
    expect(recovery.status, 'confirmed');
    expect(
      jsonDecode(await recovery.file.readAsString())['status'],
      'confirmed',
    );
  });
}
