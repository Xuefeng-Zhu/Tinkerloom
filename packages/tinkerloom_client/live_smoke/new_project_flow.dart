// Explicit new-project preparation only. Never imported by the application.
import 'dart:convert';
import 'dart:io';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

import 'create_recovery.dart';

/// Freezes setup identities before any account or business write. An existing
/// receipt always blocks a second bootstrap, including after an unknown reply.
class NewProjectRecovery {
  NewProjectRecovery._(this.file, this._value);
  final File file;
  final Map<String, dynamic> _value;
  String get workspaceId => _value['workspaceId'] as String;
  String get appId => _value['appId'] as String;
  String get stage => _value['stage'] as String;
  String get status => _value['status'] as String;
  Map<String, dynamic> get workspaceRequest =>
      _copy(_value['workspaceRequest'] as Map<String, dynamic>);
  Map<String, dynamic> get instantiateRequest =>
      _copy(_value['instantiateRequest'] as Map<String, dynamic>);
  Map<String, Object> get sanitized => {
    'path': file.absolute.path,
    'stage': stage,
    'status': status,
  };

  static Future<NewProjectRecovery> prepare({
    required Directory directory,
    required Client client,
    required String endpoint,
    required String projectId,
    required String functionId,
  }) async {
    if (await FileSystemEntity.isLink(directory.path)) {
      throw StateError('Bootstrap recovery must not be a symbolic link.');
    }
    await directory.create(recursive: true);
    await _mode(directory.path, '700');
    final file = File('${directory.path}/new-project-bootstrap.json');
    // Exclusive creation also closes the check/create race between runners.
    await file.create(exclusive: true);
    await _mode(file.path, '600');
    final workspace = client.newId(), app = client.newId();
    final recovery = NewProjectRecovery._(file, {
      'schemaVersion': 1,
      'scope': 'One explicitly authorized fresh development account/workspace/notes app',
      'endpoint': endpoint,
      'projectId': projectId,
      'functionId': functionId,
      'workspaceId': workspace,
      'appId': app,
      'workspaceRequest': {
        'op': 'createWorkspace',
        'id': workspace,
        'name': 'Tinkerloom development',
      },
      'instantiateRequest': {
        'op': 'spec.instantiate',
        'id': app,
        'workspaceId': workspace,
        'operationId': client.newId(),
        'templateKey': 'notes',
      },
      'stage': 'prepared',
      'status': 'prepared',
      'confirmed': <String, dynamic>{},
      'recoveryPolicy': 'Never bootstrap again automatically. Inspect these exact identities and operation after any failed or unknown response. No credentials or session tokens are retained here.',
    });
    await recovery._save();
    return recovery;
  }

  Future<void> before(String stage) async {
    _value['stage'] = stage;
    _value['status'] = 'unconfirmed';
    await _save();
  }

  Future<void> confirmed(String stage, [Map<String, dynamic>? value]) async {
    (_value['confirmed'] as Map<String, dynamic>)[stage] = value ?? true;
    _value['status'] = 'confirmed';
    await _save();
  }

  Future<void> failed(Object error) async {
    // signUp also signs in: Account.create may already be acknowledged when
    // session creation is rejected. A failed combined stage cannot prove that
    // the account was not created, even when the last request failed clearly.
    _value['status'] =
        stage != 'sign-up-and-sign-in' && error is NestError && !error.uncertain
        ? 'rejected'
        : 'uncertain';
    await _save();
  }

  Future<void> _save() async {
    _value['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    final temporary = File('${file.path}.tmp');
    await temporary.create(exclusive: true);
    await _mode(temporary.path, '600');
    try {
      await temporary.writeAsString('${jsonEncode(_value)}\n', flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

/// Uses one client and one budget throughout: 8 Core dispatches, 3 Account
/// requests, and 3 mutations. Private worker executions are outside that client
/// budget; two one-shot reconcile deliveries are expected with reminders on.
Future<SmokeCreateRecovery> runNewProjectSmoke({
  required Client client,
  required RequestBudget budget,
  required NewProjectRecovery recovery,
  required String email,
  required String password,
  required String endpoint,
  required String projectId,
  required String functionId,
}) async {
  try {
    await recovery.before('sign-up-and-sign-in');
    await client.auth.signUp(email, password);
    await recovery.confirmed('account', {'actorId': client.auth.actorId});

    await recovery.before('workspace');
    await client.request(recovery.workspaceRequest);
    await recovery.confirmed('workspace');
    await recovery.before('instantiate-notes');
    // Exact envelope is durable before dispatch. This is the same operation
    // used by apps.instantiate, without hiding generated identities in memory.
    await client.request(recovery.instantiateRequest);
    await recovery.confirmed('instantiate-notes');

    await recovery.before('manifest');
    final appId = recovery.appId;
    final manifest = await client.apps.manifest(appId);
    if (manifest.versionId == null ||
        manifest.specJson == null ||
        manifest.archived ||
        manifest.role != 'owner') {
      throw StateError('Expected the authorized private published notes app.');
    }
    final definition = AppSpec.parse(manifest.specJson!);
    if (definition.automationRequests.isNotEmpty) {
      throw StateError('The bootstrap template must not request automation.');
    }
    final action = definition.actions
        .where((item) => item.capability == 'records.create.v1')
        .where((item) {
          final collection = definition.collection(item.collectionId);
          return collection.behaviors.isEmpty &&
              collection.fields.any(
                (field) => field.required && field.type == FieldType.text,
              ) &&
              collection.fields.every(
                (field) => !field.required || field.type == FieldType.text,
              );
        })
        .firstOrNull;
    if (action == null) throw StateError('Expected a safe text-only action.');
    final collection = definition.collection(action.collectionId);
    await recovery.before('initial-read');
    final initial = await client.runtime.query(
      appId,
      collection.id,
      '{"limit":1}',
    );
    if (initial.records.isNotEmpty) {
      throw StateError('The new notes app unexpectedly contains records.');
    }
    final marker =
        'Synthetic Flutter smoke ${DateTime.now().toUtc().toIso8601String()}';
    final data = <String, dynamic>{
      for (final field in collection.fields.where((field) => field.required))
        field.id: marker,
    };
    final recordRecovery = await SmokeCreateRecovery.prepare(
      directory: Directory('${recovery.file.parent.path}/record-create'),
      request: ActionRequest(
        appId: appId,
        actionId: action.id,
        expectedDefinitionVersionId: manifest.versionId!,
        input: {'data': data},
        idempotencyKey: client.newId(),
      ),
      endpoint: endpoint,
      projectId: projectId,
      functionId: functionId,
      actorId: client.auth.actorId!,
      collectionId: collection.id,
    );
    await recovery.before('single-create');
    late final ActionOutcome outcome;
    try {
      outcome = await client.runtime.execute(recordRecovery.request);
      await recordRecovery.markConfirmed(outcome);
    } catch (_) {
      await recordRecovery.markUncertain();
      rethrow;
    }
    await recovery.confirmed('single-create', {'recordId': outcome.recordId});
    await recovery.before('read-back');
    final saved = await client.runtime.get(appId, outcome.recordId);
    if (!data.entries.every((entry) => saved.data[entry.key] == entry.value)) {
      throw StateError('Saved record does not match the retained command.');
    }
    await recovery.before('reload');
    await client.apps.manifest(appId);
    final reloaded = await client.runtime.get(appId, outcome.recordId);
    if (!data.entries.every(
      (entry) => reloaded.data[entry.key] == entry.value,
    )) {
      throw StateError('Reloaded record does not match the retained command.');
    }
    await recovery.before('sign-out');
    await client.auth.signOutDevice();
    await recovery.before('complete');
    await recovery.confirmed('complete');
    return recordRecovery;
  } catch (error) {
    // No cleanup request, signout request, retry, or replacement operation after
    // a quota response or uncertain write. Recovery remains a manual decision.
    budget.stopped = true;
    await recovery.failed(error);
    rethrow;
  }
}

Future<void> _mode(String path, String mode) async {
  final result = await Process.run('/bin/chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw StateError('Could not restrict bootstrap recovery permissions.');
  }
}
