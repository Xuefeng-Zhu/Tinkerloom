import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

import '../../../appwrite_backend/lib/service.dart' as backend;
import '../../../appwrite_backend/test/memory_store.dart';
import '../live_smoke/initial_read_resume.dart';
import '../live_smoke/new_project_flow.dart';

class _Fixture {
  final store = MemoryStore();
  late final service = backend.PlatformService(store, remindersEnabled: true);
  late Directory directory, recoveryDirectory;
  late File report;
  late NewProjectRecovery original;
  late String originalBootstrap, originalReport;
  final clients = <Client>[];
  final resumeCalls = <String>[];
  int createdAccounts = 0, signouts = 0, quietPeriods = 0;

  Future<void> prepareSource() async {
    directory = await Directory.systemTemp.createTemp(
      'initial-read-resume-test-',
    );
    recoveryDirectory = Directory('${directory.path}/bootstrap');
    final budget = RequestBudget(
      maxFunctions: 10,
      maxAccounts: 3,
      maxMutations: 3,
    );
    final client = Client(
      resumeEndpoint,
      budget: budget,
      auth: ClientAuth(
        signUp: (email, password) async {
          budget.account();
          createdAccounts++;
          return {'id': 'synthetic-actor'};
        },
        signIn: (email, password) async {
          budget.account();
          return {'id': 'synthetic-actor'};
        },
        signOut: () async {
          budget.account();
          signouts++;
        },
      ),
      transport: (input) async {
        if (input['op'] == 'spec.query')
          throw NestError(
            category: 'transaction_conflict',
            message: 'Synthetic rejected initial snapshot',
            status: 409,
          );
        return service.execute('synthetic-actor', input);
      },
    );
    clients.add(client);
    original = await NewProjectRecovery.prepare(
      directory: recoveryDirectory,
      client: client,
      endpoint: resumeEndpoint,
      projectId: resumeProject,
      functionId: resumeFunction,
    );
    await expectLater(
      runNewProjectSmoke(
        client: client,
        budget: budget,
        recovery: original,
        email: 'synthetic@example.invalid',
        password: 'offline-only',
        endpoint: resumeEndpoint,
        projectId: resumeProject,
        functionId: resumeFunction,
      ),
      throwsA(isA<NestError>()),
    );
    report = File('${directory.path}/original-report.json');
    await report.writeAsString(
      jsonEncode({
        'passed': false,
        'stage': 'initial-read',
        'requestCounts': budget.counts,
        'clientRequestLimits': {'functions': 10, 'accounts': 3, 'mutations': 3},
        'bootstrapRecovery': original.sanitized,
      }),
    );
    originalBootstrap = await original.file.readAsString();
    originalReport = await report.readAsString();
  }

  Future<InitialReadResume> prepare({
    String confirmedError = 'transaction_conflict',
    String projectId = resumeProject,
  }) => InitialReadResume.prepare(
    directory: recoveryDirectory,
    originalReport: report,
    endpoint: resumeEndpoint,
    projectId: projectId,
    functionId: resumeFunction,
    confirmedError: confirmedError,
  );
  Client resumedClient(
    InitialReadResume resume, {
    bool loseRecordReply = false,
    bool wrongActor = false,
  }) {
    final client = Client(
      resumeEndpoint,
      budget: resume.budget,
      auth: ClientAuth(
        signIn: (email, password) async {
          resume.budget.account();
          return {'id': wrongActor ? 'other-actor' : 'synthetic-actor'};
        },
        signOut: () async {
          resume.budget.account();
          signouts++;
        },
      ),
      transport: (input) async {
        resumeCalls.add(input['op'] as String);
        final result = await service.execute('synthetic-actor', input);
        if (loseRecordReply && input['op'] == 'spec.execute')
          throw BackendNetworkException(
            'Synthetic lost record reply',
            uncertain: true,
          );
        return result;
      },
    );
    clients.add(client);
    return client;
  }

  Future<void> run(Client client, InitialReadResume resume) =>
      runInitialReadResume(
        client: client,
        resume: resume,
        email: 'synthetic@example.invalid',
        password: 'offline-only',
        recordReadQuietPeriod: () async {
          quietPeriods++;
        },
      ).then((_) {});
  Future<void> changeReport(void Function(Map<String, dynamic>) edit) async {
    final value =
        jsonDecode(await report.readAsString()) as Map<String, dynamic>;
    edit(value);
    await report.writeAsString(jsonEncode(value));
  }

  Future<void> changeJournal(void Function(Map<String, dynamic>) edit) async {
    final value =
        jsonDecode(await original.file.readAsString()) as Map<String, dynamic>;
    edit(value);
    await original.file.writeAsString(jsonEncode(value));
  }

  Future<void> dispose() async {
    for (final client in clients) {
      await client.close();
    }
    await directory.delete(recursive: true);
  }
}

void main() {
  Future<_Fixture> fixture() async {
    final value = _Fixture();
    await value.prepareSource();
    addTearDown(value.dispose);
    return value;
  }

  test('one continuation uses the six remaining Core slots and one Account slot without bootstrapping', () async {
    final f = await fixture();
    final resume = await f.prepare();
    final client = f.resumedClient(resume);
    await f.run(client, resume);
    expect(f.resumeCalls, [
      'spec.getApp',
      'spec.query',
      'spec.execute',
      'spec.getRecord',
      'spec.getApp',
      'spec.getRecord',
    ]);
    expect(resume.budget.counts, {
      'functions': 10,
      'accounts': 3,
      'mutations': 3,
      'stopped': false,
    });
    expect(f.createdAccounts, 1);
    expect(f.signouts, 0);
    expect(f.quietPeriods, 1);
    expect(f.store.rows['workspaces']!.keys, [f.original.workspaceId]);
    expect(f.store.rows['apps']!.keys, [f.original.appId]);
    expect(f.store.rows['spec_records']!.length, 1);
    expect(await f.original.file.readAsString(), f.originalBootstrap);
    expect(await f.report.readAsString(), f.originalReport);
    final value = jsonDecode(await resume.file.readAsString()) as Map;
    expect(value['status'], 'confirmed');
    expect(value['stage'], 'complete');
    expect(
      value['originalBootstrapSha256'],
      sha256.convert(utf8.encode(f.originalBootstrap)).toString(),
    );
    expect((await resume.file.stat()).mode & 0x1ff, 0x180);
    expect(value['signOutRequested'], false);
    await expectLater(
      f.prepare(),
      throwsA(isA<StateError>()),
    ); // A retained record attempt blocks it too.
    await expectLater(
      client.apps.manifest(f.original.appId),
      throwsA(isA<NestError>()),
    );
    expect(f.resumeCalls.length, 6);
    expect(resume.budget.functions, 10);
  });

  test('uncertain first-run status cannot be resumed', () async {
    final f = await fixture();
    await f.changeJournal((v) => v['status'] = 'uncertain');
    await expectLater(f.prepare(), throwsA(isA<StateError>()));
    expect(f.resumeCalls, isEmpty);
    expect(f.createdAccounts, 1);
  });
  test(
    'a quota category cannot be relabeled as a transaction conflict',
    () async {
      final f = await fixture();
      await f.changeReport((v) => v['errorCategory'] = 'quota_exceeded');
      await expectLater(f.prepare(), throwsA(isA<StateError>()));
      expect(f.resumeCalls, isEmpty);
    },
  );
  test('different original counts cannot receive a fresh budget', () async {
    final f = await fixture();
    await f.changeReport((v) => v['requestCounts']['functions'] = 5);
    await expectLater(f.prepare(), throwsA(isA<StateError>()));
  });
  test('wrong project and missing explicit error confirmation are refused before login', () async {
    final f = await fixture();
    await expectLater(
      f.prepare(projectId: 'different-project'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      f.prepare(confirmedError: ''),
      throwsA(isA<StateError>()),
    );
    expect(f.resumeCalls, isEmpty);
  });
  test('an incomplete bootstrap cannot be converted into a resume', () async {
    final f = await fixture();
    await f.changeJournal((v) => v['confirmed'].remove('instantiate-notes'));
    await expectLater(f.prepare(), throwsA(isA<StateError>()));
  });
  test(
    'unknown record reply stops after its sole write and retains the operation',
    () async {
      final f = await fixture();
      final resume = await f.prepare();
      final client = f.resumedClient(resume, loseRecordReply: true);
      await expectLater(
        f.run(client, resume),
        throwsA(isA<BackendNetworkException>()),
      );
      expect(f.resumeCalls, ['spec.getApp', 'spec.query', 'spec.execute']);
      expect(resume.budget.counts, {
        'functions': 7,
        'accounts': 3,
        'mutations': 3,
        'stopped': true,
      });
      expect(f.store.rows['spec_records']!.length, 1);
      expect(f.quietPeriods, 0);
      expect(f.signouts, 0);
      final files = await Directory('${f.recoveryDirectory.path}/record-create')
          .list()
          .toList();
      final record =
          jsonDecode(await (files.single as File).readAsString()) as Map;
      expect(record['status'], 'uncertain');
      expect(record['wireRequest']['appId'], f.original.appId);
      await expectLater(f.prepare(), throwsA(isA<StateError>()));
    },
  );
  test(
    'exclusive resume journal blocks a second start even before login',
    () async {
      final f = await fixture();
      await f.prepare();
      await expectLater(f.prepare(), throwsA(isA<FileSystemException>()));
      expect(f.resumeCalls, isEmpty);
      expect(f.createdAccounts, 1);
    },
  );
  test('a different authenticated actor stops before a Core call', () async {
    final f = await fixture();
    final resume = await f.prepare();
    await expectLater(
      f.run(f.resumedClient(resume, wrongActor: true), resume),
      throwsA(isA<StateError>()),
    );
    expect(f.resumeCalls, isEmpty);
    expect(resume.budget.accounts, 3);
    expect(resume.budget.stopped, true);
    expect(f.signouts, 0);
  });
}
