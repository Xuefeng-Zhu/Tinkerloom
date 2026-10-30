// Explicit Cloud bootstrap runner. Normal tests and CI never run this file.
// Supply credentials through the ignored local environment; never Dart defines.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

import 'new_project_flow.dart';
import 'real_http.dart';

class _EphemeralCookies extends PathProviderPlatform {
  _EphemeralCookies(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  test(
    'one explicitly authorized fresh development project smoke',
    () => withRealHttp(() async {
      if (env['TINKERLOOM_ALLOW_ACCOUNT_CREATION'] != '1') {
        throw StateError('Explicit new-account authorization flag required.');
      }
      String requiredValue(String key) {
        final value = env[key];
        if (value == null || value.isEmpty) {
          throw StateError('Missing new-project smoke configuration: $key');
        }
        return value;
      }

      final endpoint = requiredValue('TINKERLOOM_SMOKE_ENDPOINT'),
          project = requiredValue('TINKERLOOM_SMOKE_PROJECT'),
          function = requiredValue('TINKERLOOM_SMOKE_FUNCTION'),
          email = requiredValue('TINKERLOOM_SMOKE_EMAIL'),
          password = requiredValue('TINKERLOOM_SMOKE_PASSWORD');
      if (Uri.tryParse(endpoint)?.scheme != 'https') {
        throw StateError('An explicit HTTPS Appwrite endpoint is required.');
      }
      final cookies = await Directory.systemTemp.createTemp(
        'tinkerloom-new-project-session-',
      );
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _EphemeralCookies(cookies.path);
      final budget = RequestBudget(
        maxFunctions: 10,
        maxAccounts: 3,
        maxMutations: 3,
      );
      final client = Client(
        endpoint,
        projectId: project,
        functionId: function,
        budget: budget,
      );
      var passed = false;
      NewProjectRecovery? recovery;
      try {
        recovery = await NewProjectRecovery.prepare(
          directory: Directory(
            env['TINKERLOOM_NEW_PROJECT_RECOVERY'] ??
                'output/new-project-smoke-recovery',
          ),
          client: client,
          endpoint: endpoint,
          projectId: project,
          functionId: function,
        );
        await runNewProjectSmoke(
          client: client,
          budget: budget,
          recovery: recovery,
          email: email,
          password: password,
          endpoint: endpoint,
          projectId: project,
          functionId: function,
        );
        passed = true;
      } finally {
        await client.close();
        PathProviderPlatform.instance = previous;
        await cookies.delete(recursive: true);
        final receipt = {
          'scope': 'One fresh development setup and Flutter SDK/Cloud service smoke; not rendered UI or native device proof',
          'passed': passed,
          'stage': recovery?.stage ?? 'prepare',
          'requestCounts': budget.counts,
          'clientRequestLimits': {
            'functions': 10,
            'accounts': 3,
            'mutations': 3,
          },
          'expectedPrivateWorkerExecutions': passed ? 2 : null,
          'privateWorkerCountVerified': false,
          'workerQualification': 'With reminders enabled, one reconcile delivery per instantiate and record create is expected. Background dispatch retries and hourly recovery are outside the client budget. Verify actual private Function executions separately in Console; this is not a global execution cap or a database-operation count.',
          'maximumNewAccounts': 1,
          'maximumNewWorkspaces': 1,
          'maximumNewApps': 1,
          'maximumNewTextRecords': 1,
          'imageUploads': 0,
          'aiCalls': 0,
          'reminderRulesEnabled': 0,
          'clientAutomaticRetries': 0,
          if (recovery != null) 'bootstrapRecovery': recovery.sanitized,
        };
        final report = env['TINKERLOOM_SMOKE_REPORT'];
        if (report != null && report.isNotEmpty) {
          final file = File(report);
          await file.parent.create(recursive: true);
          await file.create(exclusive: true);
          final result = await Process.run('/bin/chmod', ['600', file.path]);
          if (result.exitCode != 0) {
            throw StateError('Could not restrict the smoke report.');
          }
          await file.writeAsString('${jsonEncode(receipt)}\n', flush: true);
        }
        // Credentials, sessions, identities, record data and raw bodies omitted.
        // ignore: avoid_print
        print(jsonEncode(receipt));
      }
    }),
    skip: env['TINKERLOOM_NEW_PROJECT_SMOKE'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
