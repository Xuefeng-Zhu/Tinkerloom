import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

import '../../../appwrite_backend/lib/service.dart' as backend;
import '../../../appwrite_backend/test/memory_store.dart';
import '../live_smoke/new_project_flow.dart';

class _LocalWakeups implements backend.WorkerWakeups {
  final queued = <({String id, String proof})>[];
  int executions = 0;
  @override
  Future<String> schedule({
    required String dispatchId,
    required String proof,
    required DateTime at,
  }) async {
    queued.add((id: dispatchId, proof: proof));
    return 'synthetic-execution-${++executions}';
  }
}

class _Fixture {
  _Fixture({
    this.loseWorkspaceReply = false,
    this.rejectInstantiation = false,
    this.rejectSignIn = false,
  }) {
    service = backend.PlatformService(
      store,
      remindersEnabled: true,
      wakeups: wakeups,
      clock: () => DateTime.utc(2030),
    );
    client = Client(
      'https://offline.invalid/v1',
      budget: budget,
      auth: ClientAuth(
        signUp: (email, password) async {
          budget.account();
          accountsCreated++;
          return {'id': 'synthetic-actor'};
        },
        signIn: (email, password) async {
          budget.account();
          if (rejectSignIn) {
            throw NestError(
              category: 'account_unavailable',
              message: 'Synthetic session rejection after account creation',
              status: 401,
            );
          }
          return {'id': 'synthetic-actor'};
        },
        signOut: () async => budget.account(),
      ),
      transport: (input) async {
        calls.add(input['op'] as String);
        if (rejectInstantiation && input['op'] == 'spec.instantiate') {
          throw NestError(
            category: 'quota_exceeded',
            message: 'Synthetic quota rejection',
            status: 429,
          );
        }
        try {
          final response = await service.execute('synthetic-actor', input);
          if (loseWorkspaceReply && input['op'] == 'createWorkspace') {
            throw BackendNetworkException(
              'Synthetic lost workspace reply',
              uncertain: true,
            );
          }
          final worker = backend.WorkerEngine(service);
          await worker.flushWakeups(limit: 3);
          // Simulate successful one-shot delivery locally, not a Cloud call.
          while (wakeups.queued.isNotEmpty) {
            final dispatch = wakeups.queued.removeAt(0);
            await worker.dispatch(dispatch.id, dispatch.proof);
          }
          return response;
        } on backend.ServiceException catch (error) {
          throw NestError(
            category: error.code,
            message: 'Synthetic service rejection',
            status: error.status,
          );
        }
      },
    );
  }
  final bool loseWorkspaceReply, rejectInstantiation, rejectSignIn;
  int accountsCreated = 0;
  final budget = RequestBudget(
    maxFunctions: 10,
    maxAccounts: 3,
    maxMutations: 3,
  );
  final store = MemoryStore();
  final wakeups = _LocalWakeups();
  final calls = <String>[];
  late final backend.PlatformService service;
  late final Client client;
  Future<NewProjectRecovery> prepare(Directory directory) =>
      NewProjectRecovery.prepare(
        directory: directory,
        client: client,
        endpoint: 'https://offline.invalid/v1',
        projectId: 'synthetic-project',
        functionId: 'synthetic-core',
      );
  Future<void> run(NewProjectRecovery recovery) => runNewProjectSmoke(
    client: client,
    budget: budget,
    recovery: recovery,
    email: 'synthetic@example.invalid',
    password: 'offline-only-test-value',
    endpoint: 'https://offline.invalid/v1',
    projectId: 'synthetic-project',
    functionId: 'synthetic-core',
  ).then((_) {});
}

void main() {
  test('fresh setup uses 8 Core/3 Account requests and only two local worker deliveries', () async {
    final directory = await Directory.systemTemp.createTemp(
      'new-project-local-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final fixture = _Fixture();
    addTearDown(fixture.client.close);
    final recovery = await fixture.prepare(directory);
    final workspaceRequest = recovery.workspaceRequest;
    workspaceRequest['id'] = 'altered-after-freeze';
    await fixture.run(recovery);
    expect(fixture.calls, [
      'createWorkspace',
      'spec.instantiate',
      'spec.getApp',
      'spec.query',
      'spec.execute',
      'spec.getRecord',
      'spec.getApp',
      'spec.getRecord',
    ]);
    expect(fixture.budget.counts, {
      'functions': 8,
      'accounts': 3,
      'mutations': 3,
      'stopped': false,
    });
    expect(fixture.wakeups.executions, 2);
    expect(fixture.store.rows['workspaces']!.keys, [recovery.workspaceId]);
    expect(fixture.store.rows['apps']!.keys, [recovery.appId]);
    expect(fixture.store.rows['spec_records']!.length, 1);
    expect(fixture.store.rows['automations'] ?? {}, isEmpty);
    expect(fixture.store.rows['automation_runs'] ?? {}, isEmpty);
    expect(fixture.store.rows['media_assets'] ?? {}, isEmpty);
    expect(
      fixture.store.rows['outbox']!.values.every(
        (row) => row['planningDone'] == true && row['invalidationDone'] == true,
      ),
      true,
    );
    expect(
      fixture.store.rows['worker_dispatches']!.values.every(
        (row) => row['status'] == 'delivered',
      ),
      true,
    );
    expect(recovery.stage, 'complete');
    expect(recovery.status, 'confirmed');
    expect((await recovery.file.stat()).mode & 0x1ff, 0x180);
    expect((await directory.stat()).mode & 0x1ff, 0x1c0);
    expect(
      await recovery.file.readAsString(),
      isNot(contains('offline-only-test-value')),
    );
    // Even a completed receipt prevents accidentally creating another account.
    await expectLater(
      fixture.prepare(directory),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'unknown committed workspace stops once and retains its exact identity',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'new-project-lost-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final fixture = _Fixture(loseWorkspaceReply: true);
      addTearDown(fixture.client.close);
      final recovery = await fixture.prepare(directory);
      await expectLater(
        fixture.run(recovery),
        throwsA(isA<BackendNetworkException>()),
      );
      expect(fixture.calls, ['createWorkspace']);
      expect(fixture.budget.accounts, 2);
      expect(fixture.budget.stopped, true);
      expect(fixture.store.rows['workspaces']!.keys, [recovery.workspaceId]);
      expect(fixture.store.rows['apps'] ?? {}, isEmpty);
      final value = jsonDecode(await recovery.file.readAsString()) as Map;
      expect(value['workspaceRequest']['id'], recovery.workspaceId);
      expect(value['stage'], 'workspace');
      expect(value['status'], 'uncertain');
      expect(fixture.wakeups.executions, 0);
      await expectLater(
        fixture.prepare(directory),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('acknowledged account creation and rejected sign-in stay uncertain and block another bootstrap', () async {
    final directory = await Directory.systemTemp.createTemp(
      'new-project-account-partial-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final fixture = _Fixture(rejectSignIn: true);
    addTearDown(fixture.client.close);
    final recovery = await fixture.prepare(directory);
    await expectLater(fixture.run(recovery), throwsA(isA<NestError>()));
    expect(fixture.accountsCreated, 1);
    expect(fixture.budget.accounts, 2);
    expect(fixture.budget.functions, 0);
    expect(fixture.budget.stopped, true);
    expect(fixture.calls, isEmpty);
    expect(recovery.stage, 'sign-up-and-sign-in');
    expect(recovery.status, 'uncertain');
    final value = jsonDecode(await recovery.file.readAsString()) as Map;
    expect(value['stage'], 'sign-up-and-sign-in');
    expect(value['status'], 'uncertain');
    await expectLater(
      fixture.prepare(directory),
      throwsA(isA<FileSystemException>()),
    );
    expect(fixture.accountsCreated, 1);
    expect(fixture.budget.accounts, 2);
  });

  test('quota rejection stops before record or cleanup requests', () async {
    final directory = await Directory.systemTemp.createTemp(
      'new-project-quota-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final fixture = _Fixture(rejectInstantiation: true);
    addTearDown(fixture.client.close);
    final recovery = await fixture.prepare(directory);
    await expectLater(fixture.run(recovery), throwsA(isA<NestError>()));
    expect(fixture.calls, ['createWorkspace', 'spec.instantiate']);
    expect(fixture.budget.functions, 2);
    expect(fixture.budget.accounts, 2);
    expect(fixture.budget.stopped, true);
    expect(fixture.store.rows['spec_records'] ?? {}, isEmpty);
    expect(recovery.status, 'rejected');
    expect(recovery.stage, 'instantiate-notes');
  });
}
