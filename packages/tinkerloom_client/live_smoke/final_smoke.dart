// Explicit live runner. Not in test/ and never invoked by normal verification.
// Credentials are read only from the process environment, not Dart defines.
import 'dart:convert';
import 'dart:io';

import 'real_http.dart';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

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
    'one explicitly enabled capped Appwrite smoke',
    () => withRealHttp(() async {
      String requiredValue(String key) {
        final value = env[key];
        if (value == null || value.isEmpty)
          throw StateError('Missing live-smoke configuration: $key');
        return value;
      }

      final endpoint = requiredValue('TINKERLOOM_SMOKE_ENDPOINT'),
          project = requiredValue('TINKERLOOM_SMOKE_PROJECT'),
          function = requiredValue('TINKERLOOM_SMOKE_FUNCTION'),
          appId = requiredValue('TINKERLOOM_SMOKE_APP_ID');
      final email = requiredValue('TINKERLOOM_SMOKE_EMAIL'),
          password = requiredValue('TINKERLOOM_SMOKE_PASSWORD');
      if (!endpoint.startsWith('https://'))
        throw StateError('Cloud smoke requires an explicit HTTPS endpoint.');
      final directory = await Directory.systemTemp.createTemp(
        'tinkerloom-flutter-smoke-session-',
      );
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _EphemeralCookies(directory.path);
      final budget = RequestBudget(),
          client = Client(
            endpoint,
            projectId: project,
            functionId: function,
            budget: budget,
          );
      var passed = false, stage = 'sign-in';
      try {
        await client.auth.signIn(email, password);
        stage = 'manifest';
        final manifest = await client.apps.manifest(appId);
        if (manifest.versionId == null ||
            manifest.specJson == null ||
            manifest.archived ||
            !{'owner', 'builder'}.contains(manifest.role))
          throw StateError('Existing writable published app required.');
        final definition = AppSpec.parse(manifest.specJson!);
        // The single business mutation is limited to an existing text-only note
        // collection without workflows, capacity, assignments or effects.
        final add = definition.actions
            .where((a) => a.capability == 'records.create.v1')
            .where((a) {
              final collection = definition.collection(a.collectionId);
              return collection.behaviors.isEmpty &&
                  !definition.automationRequests.any(
                    (rule) => rule.collectionId == collection.id,
                  ) &&
                  collection.fields.any(
                    (field) => field.type == FieldType.text && field.required,
                  ) &&
                  collection.fields.every(
                    (field) => !field.required || field.type == FieldType.text,
                  );
            })
            .firstOrNull;
        if (add == null)
          throw StateError(
            'No safe text-record action in the selected existing app.',
          );
        final collection = definition.collection(add.collectionId);
        stage = 'initial-read';
        await client.runtime.query(appId, collection.id, '{"limit":1}');
        final marker =
            'Synthetic Flutter smoke ${DateTime.now().toUtc().toIso8601String()}';
        final data = <String, dynamic>{
          for (final field in collection.fields.where((f) => f.required))
            field.id: marker,
        };
        stage = 'single-create';
        final outcome = await client.runtime.execute(
          ActionRequest(
            appId: appId,
            actionId: add.id,
            expectedDefinitionVersionId: manifest.versionId!,
            input: {'data': data},
            idempotencyKey: client.newId(),
          ),
        );
        stage = 'read-back';
        final saved = await client.runtime.get(appId, outcome.recordId);
        if (!data.entries.every(
          (entry) => saved.data[entry.key] == entry.value,
        ))
          throw StateError('Saved record did not match the submitted text.');
        // Reload server state through a fresh manifest read, without reconstructing
        // SDK clients or issuing an additional session validation request.
        stage = 'reload';
        await client.apps.manifest(appId);
        final reloaded = await client.runtime.get(appId, outcome.recordId);
        if (!data.entries.every(
          (entry) => reloaded.data[entry.key] == entry.value,
        ))
          throw StateError('Reloaded record did not match.');
        stage = 'sign-out';
        await client.auth.signOutDevice();
        passed = true;
        stage = 'complete';
      } finally {
        await client.close();
        PathProviderPlatform.instance = previous;
        await directory.delete(recursive: true);
        final receipt = {
          'scope': 'One bounded Flutter SDK/Cloud service smoke; not rendered UI or native device proof',
          'passed': passed,
          'stage': stage,
          'requestCounts': budget.counts,
          'maxFunctions': 12,
          'maxAccounts': 2,
          'maxBusinessMutations': 1,
          'newAccounts': 0,
          'newApps': 0,
          'imageUploads': 0,
          'aiCalls': 0,
          'automaticRetries': 0,
        };
        final report = env['TINKERLOOM_SMOKE_REPORT'];
        if (report != null && report.isNotEmpty)
          await File(report).writeAsString('${jsonEncode(receipt)}\n');
        // Identifiers, credentials, request bodies and record values are omitted.
        // ignore: avoid_print
        print(jsonEncode(receipt));
      }
    }),
    skip: env['TINKERLOOM_LIVE_SMOKE'] != '1',
  );
}
