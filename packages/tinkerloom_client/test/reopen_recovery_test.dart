import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:tinkerloom_client/tinkerloom_client.dart';

import 'client_test.dart' show Fixture, OfflineRejectedProvider;

void main() {
  for (final operation in ['spec.saveDraft', 'spec.generate']) {
    test(
      'reopened $operation recovers exact receipt and quiet snapshot',
      () async {
        final provider = OfflineRejectedProvider();
        final fixture = Fixture(provider: provider);
        final client = fixture.client;
        addTearDown(client.close);
        final (_, initial) = await fixture.draft();
        var notifications = 0;
        void changed() => notifications++;
        client.builderRecoveryChanges.addListener(changed);
        addTearDown(
          () => client.builderRecoveryChanges.removeListener(changed),
        );
        fixture.loseNextOp = operation;
        await expectLater(
          operation == 'spec.saveDraft'
              ? client.builder.patch(
                  initial.draftId,
                  initial.mutation,
                  jsonEncode({
                    'type': 'RenameLabel',
                    'targetId': 'title',
                    'label': 'Book title',
                  }),
                )
              : client.builder.generate(
                  initial.draftId,
                  initial.mutation,
                  'Offline edit',
                  startFromScratch: false,
                ),
          throwsA(isA<BackendNetworkException>()),
        );
        final pending = client.pendingBuilderRecovery!;
        expect(pending.appId, initial.appId);
        expect(pending.operation, operation);
        expect(pending.receiptConfirmed, isFalse);
        expect(notifications, 1);
        final before = fixture.calls.length;
        final beforeWrites = fixture.calls
            .where((v) => v['op'] == operation)
            .length;
        final latest = await client.checkPendingBuilderRecovery(pending);
        expect(latest?.mutation, initial.mutation + 1);
        expect(client.pendingBuilderRecovery, isNull);
        expect(notifications, 3);
        final sent = fixture.calls.skip(before).toList();
        expect(sent.map((v) => v['op']), [
          'spec.commandReceipt',
          'spec.getApp',
        ]);
        expect(sent.last['suppressWakeups'], true);
        expect(
          fixture.calls.where((v) => v['op'] == operation),
          hasLength(beforeWrites),
        );
        expect(provider.calls, 0);
        await client.builder.patch(
          latest!.draftId,
          latest.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'title',
            'label': 'Next',
          }),
        );
      },
    );
  }

  test(
    'unresolved receipt keeps exact command and makes no new mutation',
    () async {
      final fixture = Fixture(provider: OfflineRejectedProvider());
      final client = fixture.client;
      addTearDown(client.close);
      final (_, initial) = await fixture.draft();
      fixture.loseBeforeOp = 'spec.generate';
      await expectLater(
        client.builder.generate(
          initial.draftId,
          initial.mutation,
          'Offline edit',
          startFromScratch: false,
        ),
        throwsA(isA<BackendNetworkException>()),
      );
      final handle = client.pendingBuilderRecovery!;
      final before = fixture.calls.length;
      expect(
        () => client.setAsideConfirmedBuilderRecovery(handle),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'pending_command',
          ),
        ),
      );
      expect(fixture.calls.length, before);
      expect(await client.checkPendingBuilderRecovery(handle), isNull);
      expect(identical(client.pendingBuilderRecovery, handle), isTrue);
      expect(fixture.calls.skip(before).map((v) => v['op']), [
        'spec.commandReceipt',
      ]);
      await expectLater(
        client.builder.patch(
          initial.draftId,
          initial.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'title',
            'label': 'Next',
          }),
        ),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'pending_command',
          ),
        ),
      );
      expect(
        fixture.calls.where((v) => v['op'] == 'spec.generate'),
        hasLength(1),
      );
    },
  );

  test(
    'confirmed receipt survives a failed quiet read for manual recheck',
    () async {
      final fixture = Fixture(provider: OfflineRejectedProvider());
      final client = fixture.client;
      addTearDown(client.close);
      final (_, initial) = await fixture.draft();
      fixture.loseNextOp = 'spec.generate';
      await expectLater(
        client.builder.generate(
          initial.draftId,
          initial.mutation,
          'Offline edit',
          startFromScratch: false,
        ),
        throwsA(isA<BackendNetworkException>()),
      );
      fixture.loseBeforeOp = 'spec.getApp';
      await expectLater(
        client.checkPendingBuilderRecovery(client.pendingBuilderRecovery!),
        throwsA(isA<BackendNetworkException>()),
      );
      final confirmed = client.pendingBuilderRecovery!;
      expect(confirmed.receiptConfirmed, isTrue);
      expect(
        fixture.calls.where((v) => v['op'] == 'spec.commandReceipt'),
        hasLength(1),
      );
      final before = fixture.calls.length;
      await expectLater(
        client.request({
          'op': 'createWorkspace',
          'id': 'other',
          'name': 'Other',
        }),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'pending_command',
          ),
        ),
      );
      expect(fixture.calls.length, before);
      expect(identical(client.pendingBuilderRecovery, confirmed), isTrue);
      final latest = await client.checkPendingBuilderRecovery(confirmed);
      expect(latest?.mutation, initial.mutation + 1);
      expect(fixture.calls.skip(before).map((v) => v['op']), ['spec.getApp']);
      expect(client.pendingBuilderRecovery, isNull);
      expect(
        fixture.calls.where((v) => v['op'] == 'spec.generate'),
        hasLength(1),
      );
    },
  );

  test(
    'downgraded builder cannot read or clear a confirmed recovery',
    () async {
      final fixture = Fixture();
      addTearDown(fixture.client.close);
      final (app, _) = await fixture.published();
      final workspace = (await fixture.client.apps.manifest(app)).workspaceId;
      final bob = fixture.forActor('bob');
      addTearDown(bob.close);
      final token = await fixture.client.apps.invite(app, 'builder', 'bob');
      await bob.apps.acceptInvitation(token);
      final initial = await bob.builder.begin(workspace, 'reading', app);
      final patch = {
        'type': 'RenameLabel',
        'targetId': 'title',
        'label': 'Private',
      };
      final expected = spec.AppSpec.parse(initial.candidateJson)
          .patch(patch, () => 'unused');
      fixture.loseNextOp = 'spec.saveDraft';
      await expectLater(
        bob.builder.patch(initial.draftId, initial.mutation, jsonEncode(patch)),
        throwsA(isA<BackendNetworkException>()),
      );
      expect(
        await bob.confirmRetainedBuilderCommand(
          appId: app,
          operation: 'spec.saveDraft',
          expectedRevision: initial.mutation,
          candidateHash: expected.hash,
        ),
        RetainedCommandStatus.confirmed,
      );
      final pending = bob.pendingBuilderRecovery!;
      expect(pending.receiptConfirmed, isTrue);
      await fixture.client.apps.members(app);
      await fixture.client.apps.setGrant(app, 'bob', 'viewer');
      await expectLater(
        bob.checkPendingBuilderRecovery(pending),
        throwsA(isA<BackendForbidden>()),
      );
      expect(identical(bob.pendingBuilderRecovery, pending), isTrue);
      final before = fixture.calls.length;
      bob.setAsideConfirmedBuilderRecovery(pending);
      expect(fixture.calls.length, before);
      expect(bob.pendingBuilderRecovery, isNull);
      await bob.apps.createWorkspace('Continue elsewhere');
    },
  );

  test(
    'confirmed recovery may be set aside after the app is archived',
    () async {
      final fixture = Fixture();
      final client = fixture.client;
      addTearDown(client.close);
      final (_, initial) = await fixture.draft();
      final patch = {
        'type': 'RenameLabel',
        'targetId': 'title',
        'label': 'Private',
      };
      final expected = spec.AppSpec.parse(initial.candidateJson)
          .patch(patch, () => 'unused');
      fixture.loseNextOp = 'spec.saveDraft';
      await expectLater(
        client.builder.patch(
          initial.draftId,
          initial.mutation,
          jsonEncode(patch),
        ),
        throwsA(isA<BackendNetworkException>()),
      );
      await client.confirmRetainedBuilderCommand(
        appId: initial.appId,
        operation: 'spec.saveDraft',
        expectedRevision: initial.mutation,
        candidateHash: expected.hash,
      );
      final pending = client.pendingBuilderRecovery!;
      await fixture.store.update('apps', initial.appId, {'archived': true});
      await expectLater(
        client.checkPendingBuilderRecovery(pending),
        throwsA(isA<BackendForbidden>()),
      );
      final before = fixture.calls.length;
      client.setAsideConfirmedBuilderRecovery(pending);
      expect(fixture.calls.length, before);
      expect(client.pendingBuilderRecovery, isNull);
      await client.apps.createWorkspace('Continue elsewhere');
    },
  );

  test('session change invalidates retained recovery handle', () async {
    final fixture = Fixture(provider: OfflineRejectedProvider());
    final client = fixture.client;
    addTearDown(client.close);
    final (_, initial) = await fixture.draft();
    fixture.loseNextOp = 'spec.generate';
    await expectLater(
      client.builder.generate(
        initial.draftId,
        initial.mutation,
        'Offline edit',
        startFromScratch: false,
      ),
      throwsA(isA<BackendNetworkException>()),
    );
    final old = client.pendingBuilderRecovery!;
    final before = fixture.calls.length;
    client.auth.setSession({'id': 'bob'});
    expect(client.pendingBuilderRecovery, isNull);
    expect(
      () => client.setAsideConfirmedBuilderRecovery(old),
      throwsA(isA<BackendUnauthorized>()),
    );
    await expectLater(
      client.checkPendingBuilderRecovery(old),
      throwsA(isA<BackendUnauthorized>()),
    );
    expect(fixture.calls.length, before);
  });

  test('late recovery read is fenced and blocks another mutation', () async {
    final fixture = Fixture(provider: OfflineRejectedProvider());
    addTearDown(fixture.client.close);
    final (_, initial) = await fixture.draft();
    final entered = Completer<void>();
    final release = Completer<void>();
    var lose = true;
    final auth = ClientAuth()..setSession({'id': 'alice'});
    final calls = <String>[];
    final client = Client(
      'https://offline.invalid',
      auth: auth,
      transport: (input) async {
        calls.add(input['op'] as String);
        if (input['op'] == 'spec.getApp' && input['suppressWakeups'] == true) {
          entered.complete();
          await release.future;
        }
        final result = await fixture.service.execute('alice', input);
        if (input['op'] == 'spec.generate' && lose) {
          lose = false;
          throw BackendNetworkException('lost', uncertain: true);
        }
        return result;
      },
    );
    addTearDown(client.close);
    await client.builder.get(initial.appId);
    await expectLater(
      client.builder.generate(
        initial.draftId,
        initial.mutation,
        'Offline edit',
        startFromScratch: false,
      ),
      throwsA(isA<BackendNetworkException>()),
    );
    final recovery = client.checkPendingBuilderRecovery(
      client.pendingBuilderRecovery!,
    );
    final assertion = expectLater(
      recovery,
      throwsA(isA<BackendUnauthorized>()),
    );
    await entered.future;
    expect(
      () => client.setAsideConfirmedBuilderRecovery(
        client.pendingBuilderRecovery!,
      ),
      throwsA(
        isA<NestError>().having(
          (e) => e.category,
          'category',
          'command_in_progress',
        ),
      ),
    );
    await expectLater(
      client.request({'op': 'createWorkspace', 'id': 'other', 'name': 'Other'}),
      throwsA(
        isA<NestError>().having(
          (e) => e.category,
          'category',
          'command_in_progress',
        ),
      ),
    );
    auth.setSession({'id': 'bob'});
    expect(client.pendingBuilderRecovery, isNull);
    release.complete();
    await assertion;
    expect(calls.where((op) => op == 'spec.generate'), hasLength(1));
    expect(calls.where((op) => op == 'spec.commandReceipt'), hasLength(1));
  });

  test(
    'screen ownership ends but pending notification remains until manual check',
    () async {
      final fixture = Fixture(provider: OfflineRejectedProvider());
      addTearDown(fixture.client.close);
      final (_, initial) = await fixture.draft();
      final entered = Completer<void>();
      final release = Completer<void>();
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (input) async {
          final result = await fixture.service.execute('alice', input);
          if (input['op'] == 'spec.generate') {
            entered.complete();
            await release.future;
            throw BackendNetworkException('lost', uncertain: true);
          }
          return result;
        },
      );
      addTearDown(client.close);
      await client.builder.get(initial.appId);
      var notifications = 0;
      void observer() => notifications++;
      client.builderRecoveryChanges.addListener(observer);
      final flight = client.builder.generate(
        initial.draftId,
        initial.mutation,
        'Offline edit',
        startFromScratch: false,
      );
      final assertion = expectLater(
        flight,
        throwsA(isA<BackendNetworkException>()),
      );
      await entered.future;
      expect(client.pendingBuilderRecovery, isNull);
      client.builderRecoveryChanges.removeListener(observer);
      release.complete();
      await assertion;
      expect(notifications, 0);
      final pending = client.pendingBuilderRecovery;
      expect(pending, isNotNull);
      expect(
        (await client.checkPendingBuilderRecovery(pending!))?.mutation,
        initial.mutation + 1,
      );
      expect(client.pendingBuilderRecovery, isNull);
    },
  );

  test(
    'revoked builder access retains pending handle without revealing result',
    () async {
      final fixture = Fixture();
      addTearDown(fixture.client.close);
      final (appId, _) = await fixture.published();
      final workspace = (await fixture.client.apps.manifest(appId)).workspaceId;
      final bob = fixture.forActor('bob');
      addTearDown(bob.close);
      final token = await fixture.client.apps.invite(appId, 'builder', 'bob');
      await bob.apps.acceptInvitation(token);
      final initial = await bob.builder.begin(workspace, 'reading', appId);
      fixture.loseNextOp = 'spec.saveDraft';
      await expectLater(
        bob.builder.patch(
          initial.draftId,
          initial.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'title',
            'label': 'Private',
          }),
        ),
        throwsA(isA<BackendNetworkException>()),
      );
      final pending = bob.pendingBuilderRecovery!;
      await fixture.client.apps.members(appId);
      await fixture.client.apps.setGrant(appId, 'bob', null);
      final before = fixture.calls.length;
      await expectLater(
        bob.checkPendingBuilderRecovery(pending),
        throwsA(isA<NestError>()),
      );
      expect(identical(bob.pendingBuilderRecovery, pending), isTrue);
      expect(fixture.calls.skip(before).map((v) => v['op']), [
        'spec.commandReceipt',
      ]);
    },
  );
}
