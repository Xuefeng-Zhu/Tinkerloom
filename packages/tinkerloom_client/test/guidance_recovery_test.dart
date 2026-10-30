import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

import 'client_test.dart' show Fixture, OfflineRejectedProvider;

void main() {
  final guidance = <String, dynamic>{
    'op': 'spec.guidance',
    'workspaceId': 'ws',
    'appId': null,
    'request': 'Help with my idea',
  };
  final other = <String, dynamic>{
    'op': 'createWorkspace',
    'id': 'other',
    'name': 'Other',
  };

  test('explicit guidance acknowledgment clears only the captured envelope without a call', () async {
    final calls = <Map<String, dynamic>>[];
    final auth = ClientAuth()..setSession({'id': 'alice'});
    final client = Client(
      'https://offline.invalid',
      auth: auth,
      transport: (input) async {
        calls.add(input);
        if (input['op'] == 'spec.guidance') {
          throw BackendNetworkException('unknown', uncertain: true);
        }
        return {
          'workspace': {'id': input['id'], 'name': input['name']},
        };
      },
    );
    addTearDown(client.close);
    final epoch = client.sessionEpoch;
    await expectLater(
      client.request(guidance),
      throwsA(isA<BackendNetworkException>()),
    );
    expect(
      client.capturePendingGuidance(
        sessionEpoch: epoch,
        request: 'different',
        workspaceId: 'ws',
      ),
      isNull,
    );
    expect(
      client.capturePendingGuidance(
        sessionEpoch: epoch,
        request: 'Help with my idea',
        workspaceId: 'wrong',
      ),
      isNull,
    );
    await expectLater(
      client.request(other),
      throwsA(
        isA<NestError>().having(
          (e) => e.category,
          'category',
          'pending_command',
        ),
      ),
    );
    final token = client.capturePendingGuidance(
      sessionEpoch: epoch,
      request: 'Help with my idea',
      workspaceId: 'ws',
    );
    expect(token, isNotNull);
    expect(calls, hasLength(1));
    client.acknowledgePendingGuidance(token!);
    expect(calls, hasLength(1));
    await client.request(other);
    expect(calls, hasLength(2));
    expect(
      () => client.acknowledgePendingGuidance(token),
      throwsA(isA<NestError>()),
    );
  });

  test(
    'other uncertain mutations cannot be acknowledged as guidance',
    () async {
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (_) async =>
            throw BackendNetworkException('unknown', uncertain: true),
      );
      addTearDown(client.close);
      final epoch = client.sessionEpoch;
      await expectLater(
        client.request(other),
        throwsA(isA<BackendNetworkException>()),
      );
      expect(
        client.capturePendingGuidance(
          sessionEpoch: epoch,
          request: 'Help with my idea',
          workspaceId: 'ws',
        ),
        isNull,
      );
      await expectLater(
        client.request(guidance),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'pending_command',
          ),
        ),
      );
    },
  );

  test(
    'an old token cannot clear a later identical guidance envelope',
    () async {
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (_) async =>
            throw BackendNetworkException('unknown', uncertain: true),
      );
      addTearDown(client.close);
      final epoch = client.sessionEpoch;
      await expectLater(
        client.request(guidance),
        throwsA(isA<BackendNetworkException>()),
      );
      final first = client.capturePendingGuidance(
        sessionEpoch: epoch,
        request: 'Help with my idea',
        workspaceId: 'ws',
      )!;
      client.acknowledgePendingGuidance(first);
      await expectLater(
        client.request(guidance),
        throwsA(isA<BackendNetworkException>()),
      );
      expect(
        () => client.acknowledgePendingGuidance(first),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'pending_command',
          ),
        ),
      );
      final second = client.capturePendingGuidance(
        sessionEpoch: epoch,
        request: 'Help with my idea',
        workspaceId: 'ws',
      );
      expect(second, isNotNull);
      client.acknowledgePendingGuidance(second!);
    },
  );

  test(
    'acknowledgment is fenced on sign out and same-account sign in',
    () async {
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (_) async =>
            throw BackendNetworkException('unknown', uncertain: true),
      );
      addTearDown(client.close);
      final epoch = client.sessionEpoch;
      await expectLater(
        client.request(guidance),
        throwsA(isA<BackendNetworkException>()),
      );
      final token = client.capturePendingGuidance(
        sessionEpoch: epoch,
        request: 'Help with my idea',
        workspaceId: 'ws',
      )!;
      auth.setSession(null);
      auth.setSession({'id': 'alice'});
      expect(
        () => client.acknowledgePendingGuidance(token),
        throwsA(isA<BackendUnauthorized>()),
      );
    },
  );

  test('acknowledgment never resets a stopped smoke budget', () async {
    final budget = RequestBudget(maxFunctions: 5, maxMutations: 5);
    final auth = ClientAuth()..setSession({'id': 'alice'});
    final client = Client(
      'https://offline.invalid',
      auth: auth,
      budget: budget,
      transport: (_) async =>
          throw BackendNetworkException('unknown', uncertain: true),
    );
    addTearDown(client.close);
    final epoch = client.sessionEpoch;
    await expectLater(
      client.request(guidance),
      throwsA(isA<BackendNetworkException>()),
    );
    final token = client.capturePendingGuidance(
      sessionEpoch: epoch,
      request: 'Help with my idea',
      workspaceId: 'ws',
    )!;
    expect(budget.stopped, isTrue);
    client.acknowledgePendingGuidance(token);
    expect(budget.stopped, isTrue);
    await expectLater(
      client.request(other),
      throwsA(
        isA<NestError>().having(
          (e) => e.category,
          'category',
          'request_budget',
        ),
      ),
    );
    expect(budget.functions, 1);
  });

  test(
    'capture refuses in-flight guidance and edit context cannot be confused',
    () async {
      final response = Completer<Map<String, dynamic>>();
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (_) => response.future,
      );
      addTearDown(client.close);
      final epoch = client.sessionEpoch;
      final running = client.request({...guidance, 'appId': 'app'});
      final failed = expectLater(
        running,
        throwsA(isA<BackendNetworkException>()),
      );
      expect(
        () => client.capturePendingGuidance(
          sessionEpoch: epoch,
          request: 'Help with my idea',
          appId: 'app',
        ),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'command_in_progress',
          ),
        ),
      );
      response.completeError(
        BackendNetworkException('unknown', uncertain: true),
      );
      await failed;
      expect(
        client.capturePendingGuidance(
          sessionEpoch: epoch,
          request: 'Help with my idea',
          workspaceId: 'ws',
        ),
        isNull,
      );
      expect(
        client.capturePendingGuidance(
          sessionEpoch: epoch,
          request: 'Help with my idea',
          appId: 'wrong',
        ),
        isNull,
      );
      final token = client.capturePendingGuidance(
        sessionEpoch: epoch,
        request: 'Help with my idea',
        appId: 'app',
      );
      expect(token, isNotNull);
      client.acknowledgePendingGuidance(token!);
    },
  );
  test(
    'guidance acknowledgment cannot interfere with builder recovery',
    () async {
      final fixture = Fixture(provider: OfflineRejectedProvider());
      addTearDown(fixture.client.close);
      final (_, initial) = await fixture.draft();
      final entered = Completer<void>();
      final release = Completer<void>();
      final calls = <String>[];
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (input) async {
          calls.add(input['op'] as String);
          if (input['op'] == 'spec.guidance') {
            throw BackendNetworkException('lost guidance', uncertain: true);
          }
          if (input['op'] == 'spec.getApp' &&
              input['suppressWakeups'] == true) {
            entered.complete();
            await release.future;
            throw BackendNetworkException('read failed');
          }
          final result = await fixture.service.execute('alice', input);
          if (input['op'] == 'spec.generate') {
            throw BackendNetworkException('lost generation', uncertain: true);
          }
          return result;
        },
      );
      addTearDown(client.close);
      await expectLater(
        client.request(guidance),
        throwsA(isA<BackendNetworkException>()),
      );
      final old = client.pendingGuidanceAcknowledgement!;
      client.acknowledgePendingGuidance(old);
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
      final check = client.checkPendingBuilderRecovery(
        client.pendingBuilderRecovery!,
      );
      final assertion = expectLater(
        check,
        throwsA(isA<BackendNetworkException>()),
      );
      await entered.future;
      expect(client.pendingBuilderRecovery?.receiptConfirmed, isTrue);
      expect(
        () => client.acknowledgePendingGuidance(old),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'command_in_progress',
          ),
        ),
      );
      expect(
        () => client.capturePendingGuidance(
          sessionEpoch: client.sessionEpoch,
          request: 'Help with my idea',
          workspaceId: 'ws',
        ),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'command_in_progress',
          ),
        ),
      );
      release.complete();
      await assertion;
      expect(client.pendingBuilderRecovery?.receiptConfirmed, isTrue);
      expect(
        () => client.acknowledgePendingGuidance(old),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'command_in_progress',
          ),
        ),
      );
      expect(calls.where((op) => op == 'spec.guidance'), hasLength(1));
      expect(calls.where((op) => op == 'spec.generate'), hasLength(1));
    },
  );
}
