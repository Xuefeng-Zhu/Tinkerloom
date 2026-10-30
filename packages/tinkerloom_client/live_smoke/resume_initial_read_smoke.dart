// Explicit one-shot continuation only; never part of normal tests or CI.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

import 'initial_read_resume.dart';
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
    'one explicit continuation of the rejected initial read',
    () => withRealHttp(() async {
      String requiredValue(String key) {
        final value = env[key];
        if (value == null || value.isEmpty)
          throw StateError('Missing continuation configuration: $key');
        return value;
      }

      final endpoint = requiredValue('TINKERLOOM_SMOKE_ENDPOINT'),
          project = requiredValue('TINKERLOOM_SMOKE_PROJECT'),
          function = requiredValue('TINKERLOOM_SMOKE_FUNCTION'),
          email = requiredValue('TINKERLOOM_SMOKE_EMAIL'),
          password = requiredValue('TINKERLOOM_SMOKE_PASSWORD');
      final resume = await InitialReadResume.prepare(
        directory: Directory(requiredValue('TINKERLOOM_NEW_PROJECT_RECOVERY')),
        originalReport: File(requiredValue('TINKERLOOM_SMOKE_ORIGINAL_REPORT')),
        endpoint: endpoint,
        projectId: project,
        functionId: function,
        confirmedError: requiredValue('TINKERLOOM_RESUME_CONFIRMED_ERROR'),
      );
      final report = File(requiredValue('TINKERLOOM_SMOKE_REPORT'));
      await report.parent.create(recursive: true);
      await report.create(exclusive: true);
      final mode = await Process.run('/bin/chmod', ['600', report.path]);
      if (mode.exitCode != 0)
        throw StateError('Could not restrict continuation report.');
      final cookies = await Directory.systemTemp.createTemp(
        'tinkerloom-read-resume-session-',
      );
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _EphemeralCookies(cookies.path);
      final client = Client(
        endpoint,
        projectId: project,
        functionId: function,
        budget: resume.budget,
      );
      var passed = false;
      try {
        await runInitialReadResume(
          client: client,
          resume: resume,
          email: email,
          password: password,
          recordReadQuietPeriod: () =>
              Future<void>.delayed(const Duration(seconds: 30)),
        );
        passed = true;
      } finally {
        await client.close();
        PathProviderPlatform.instance = previous;
        await cookies.delete(recursive: true);
        final receipt = {
          'scope': 'One explicit continuation of the same rejected initial read; cumulative counts include the original failed run',
          'passed': passed,
          'stage': resume.stage,
          'requestCounts': resume.budget.counts,
          'clientRequestLimits': {
            'functions': 10,
            'accounts': 3,
            'mutations': 3,
          },
          'initialRequestCounts': {
            'functions': 4,
            'accounts': 2,
            'mutations': 2,
          },
          'automaticRetries': 0,
          'newAccounts': 0,
          'newWorkspaces': 0,
          'newApps': 0,
          'maximumAdditionalTextRecords': 1,
          'imageUploads': 0,
          'aiCalls': 0,
          'reminderRulesEnabled': 0,
          'recordReadQuietPeriodSeconds': 30,
          'signOutRequested': false,
          'serverSessionMayRemain': resume.budget.accounts > 2,
          'sessionQualification': 'One remaining Account slot is used for existing-account sign-in. No signout request is allowed by the cumulative cap. Local session files are deleted; this does not revoke server sessions.',
          'expectedCumulativePrivateWorkerExecutions': passed ? 2 : null,
          'privateWorkerCountVerified': false,
          'workerQualification': 'Two normal one-shot private reconciliations are expected across both runs. Background retries and hourly recovery are outside the client budget; verify actual executions separately in Console.',
          'resumeRecovery': resume.sanitized,
        };
        await report.writeAsString('${jsonEncode(receipt)}\n', flush: true);
        // No credentials, session tokens, identities or record values are printed.
        // ignore: avoid_print
        print(jsonEncode(receipt));
      }
    }),
    skip: env['TINKERLOOM_INITIAL_READ_RESUME'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
