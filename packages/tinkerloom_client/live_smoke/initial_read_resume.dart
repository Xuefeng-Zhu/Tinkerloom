// One explicitly authorized continuation of a definitively rejected first read.
// No application imports this tool; it never bootstraps an account or app.
import 'dart:convert';
import 'dart:io';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:crypto/crypto.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

import 'create_recovery.dart';

const resumeEndpoint = 'https://fra.cloud.appwrite.io/v1';
const resumeProject = '6ae4175600137449b25e';
const resumeFunction = 'tinkerloom-core';

class InitialReadResume {
  InitialReadResume._(this.file, this._value, this.budget);
  final File file;
  final Map<String, dynamic> _value;
  final RequestBudget budget;
  String get appId => _value['appId'] as String;
  String get workspaceId => _value['workspaceId'] as String;
  String get actorId => _value['actorId'] as String;
  String get stage => _value['stage'] as String;
  Map<String, Object> get sanitized => {
    'path': file.absolute.path,
    'stage': stage,
    'status': _value['status'] as String,
  };

  /// This narrowly accepts the observed 4/2/2 initial-read rejection only.
  /// It seeds cumulative counters; it does not grant a replacement budget.
  static Future<InitialReadResume> prepare({
    required Directory directory,
    required File originalReport,
    required String endpoint,
    required String projectId,
    required String functionId,
    required String confirmedError,
  }) async {
    void require(bool value) {
      if (!value)
        throw StateError(
          'The retained run is not eligible for this one-shot read continuation.',
        );
    }

    require(
      endpoint == resumeEndpoint &&
          projectId == resumeProject &&
          functionId == resumeFunction,
    );
    require(confirmedError == 'transaction_conflict');
    require(!await FileSystemEntity.isLink(directory.path));
    require(!await FileSystemEntity.isLink(originalReport.path));
    final bootstrap = File('${directory.path}/new-project-bootstrap.json');
    require(!await FileSystemEntity.isLink(bootstrap.path));
    final bootstrapBytes = await bootstrap.readAsBytes();
    final reportBytes = await originalReport.readAsBytes();
    final journal =
        jsonDecode(utf8.decode(bootstrapBytes)) as Map<String, dynamic>;
    final report = jsonDecode(utf8.decode(reportBytes)) as Map<String, dynamic>;
    require(
      journal['schemaVersion'] == 1 &&
          journal['stage'] == 'initial-read' &&
          journal['status'] == 'rejected',
    );
    require(
      journal['endpoint'] == endpoint &&
          journal['projectId'] == projectId &&
          journal['functionId'] == functionId,
    );
    require(report['passed'] == false && report['stage'] == 'initial-read');
    final counts = report['requestCounts'];
    require(
      counts is Map &&
          counts['functions'] == 4 &&
          counts['accounts'] == 2 &&
          counts['mutations'] == 2 &&
          counts['stopped'] == true,
    );
    final limits = report['clientRequestLimits'];
    require(
      limits is Map &&
          limits['functions'] == 10 &&
          limits['accounts'] == 3 &&
          limits['mutations'] == 3,
    );
    final priorRecovery = report['bootstrapRecovery'];
    require(
      priorRecovery is Map &&
          priorRecovery['path'] is String &&
          priorRecovery['stage'] == 'initial-read' &&
          priorRecovery['status'] == 'rejected',
    );
    require(
      await File(priorRecovery['path'] as String).resolveSymbolicLinks() ==
          await bootstrap.resolveSymbolicLinks(),
    );
    // The first report did not record an error category. A separate explicit
    // operator-confirmed reason is mandatory; a recorded contradictory category
    // is never overridden by that flag.
    for (final source in [journal, report]) {
      for (final key in ['errorCategory', 'failureCode']) {
        require(source[key] == null || source[key] == 'transaction_conflict');
      }
    }
    final confirmed = journal['confirmed'];
    require(
      confirmed is Map &&
          confirmed['account'] is Map &&
          confirmed['workspace'] == true &&
          confirmed['instantiate-notes'] == true &&
          !confirmed.containsKey('single-create'),
    );
    final actor = (confirmed['account'] as Map)['actorId'];
    final workspace = journal['workspaceId'], app = journal['appId'];
    bool id(Object? value) =>
        value is String &&
        RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,35}$').hasMatch(value);
    require(id(actor) && id(workspace) && id(app));
    final workspaceRequest = journal['workspaceRequest'],
        instantiate = journal['instantiateRequest'];
    require(
      workspaceRequest is Map &&
          workspaceRequest['op'] == 'createWorkspace' &&
          workspaceRequest['id'] == workspace,
    );
    require(
      instantiate is Map &&
          instantiate['op'] == 'spec.instantiate' &&
          instantiate['id'] == app &&
          instantiate['workspaceId'] == workspace &&
          instantiate['templateKey'] == 'notes' &&
          id(instantiate['operationId']),
    );
    // Any retained record attempt makes this pre-create-only mode ineligible.
    require(!await Directory('${directory.path}/record-create').exists());
    final budget =
        RequestBudget(maxFunctions: 10, maxAccounts: 3, maxMutations: 3)
          ..functions = 4
          ..accounts = 2
          ..mutations = 2;
    final file = File('${directory.path}/initial-read-resume.json');
    await file.create(exclusive: true);
    await _mode(file.path, '600');
    final resume = InitialReadResume._(file, {
      'schemaVersion': 1,
      'scope': 'One manual continuation after a definitive initial-read conflict; no new account, workspace or app',
      'originalBootstrapPath': bootstrap.absolute.path,
      'originalBootstrapSha256': sha256.convert(bootstrapBytes).toString(),
      'originalReportPath': originalReport.absolute.path,
      'originalReportSha256': sha256.convert(reportBytes).toString(),
      'approvedReason': confirmedError,
      'reasonEvidence': 'Explicit operator confirmation of the rejected read; original source receipts preserved',
      'endpoint': endpoint,
      'projectId': projectId,
      'functionId': functionId,
      'actorId': actor,
      'workspaceId': workspace,
      'appId': app,
      'initialRequestCounts': {'functions': 4, 'accounts': 2, 'mutations': 2},
      'stage': 'prepared',
      'status': 'prepared',
      'confirmed': <String, dynamic>{},
      'signOutRequested': false,
      'recoveryPolicy': 'Do not repeat this continuation. Preserve this receipt after any error or unknown reply; no retry, new bootstrap, or replacement operation is authorized by this tool.',
    }, budget);
    await resume._save();
    return resume;
  }

  Future<void> before(String stage) async {
    _value['stage'] = stage;
    _value['status'] = 'unconfirmed';
    await _save();
  }

  Future<void> confirmed(String stage, [Map<String, dynamic>? result]) async {
    (_value['confirmed'] as Map<String, dynamic>)[stage] = result ?? true;
    _value['status'] = 'confirmed';
    await _save();
  }

  Future<void> failed(Object error) async {
    _value['status'] = error is NestError && !error.uncertain
        ? 'rejected'
        : 'uncertain';
    if (error is NestError) _value['errorCategory'] = error.category;
    await _save();
  }

  Future<void> _save() async {
    _value['requestCounts'] = budget.counts;
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

Future<SmokeCreateRecovery> runInitialReadResume({
  required Client client,
  required InitialReadResume resume,
  required String email,
  required String password,
  required Future<void> Function() recordReadQuietPeriod,
}) async {
  if (!identical(client.budget, resume.budget)) {
    throw StateError('Continuation must share its cumulative request budget.');
  }
  try {
    await resume.before('sign-in');
    await client.auth.signIn(email, password);
    if (client.auth.actorId != resume.actorId) {
      throw StateError('The session does not match the retained actor.');
    }
    await resume.confirmed('sign-in');
    await resume.before('manifest');
    final app = await client.apps.manifest(resume.appId);
    if (app.appId != resume.appId ||
        app.workspaceId != resume.workspaceId ||
        app.role != 'owner' ||
        app.archived ||
        app.versionId == null ||
        app.specJson == null) {
      throw StateError('The existing retained app is no longer eligible.');
    }
    final definition = AppSpec.parse(app.specJson!);
    if (definition.automationRequests.isNotEmpty)
      throw StateError('Automation is excluded.');
    final action = definition.actions
        .where(
          (item) =>
              item.capability == 'records.create.v1' &&
              item.collectionId == 'notes',
        )
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
    if (action == null)
      throw StateError('Expected the existing safe notes action.');
    final collection = definition.collection(action.collectionId);
    await resume.before('initial-read');
    final initial = await client.runtime.query(
      resume.appId,
      collection.id,
      '{"limit":1}',
    );
    if (initial.records.isNotEmpty || initial.total != 0)
      throw StateError('The retained app is no longer empty.');
    final marker =
        'Synthetic Flutter smoke ${DateTime.now().toUtc().toIso8601String()}';
    final data = <String, dynamic>{
      for (final field in collection.fields.where((field) => field.required))
        field.id: marker,
    };
    final recovery = await SmokeCreateRecovery.prepare(
      directory: Directory('${resume.file.parent.path}/record-create'),
      request: ActionRequest(
        appId: resume.appId,
        actionId: action.id,
        expectedDefinitionVersionId: app.versionId!,
        input: {'data': data},
        idempotencyKey: client.newId(),
      ),
      endpoint: resumeEndpoint,
      projectId: resumeProject,
      functionId: resumeFunction,
      actorId: resume.actorId,
      collectionId: collection.id,
    );
    await resume.before('single-create');
    late final ActionOutcome outcome;
    try {
      outcome = await client.runtime.execute(recovery.request);
      await recovery.markConfirmed(outcome);
    } catch (_) {
      await recovery.markUncertain();
      rethrow;
    }
    await resume.confirmed('single-create', {
      'recordId': outcome.recordId,
      'recoveryPath': recovery.file.absolute.path,
    });
    await resume.before('record-worker-quiet-period');
    // One local pause, no polling or retries. It reduces guard contention from
    // the create's asynchronous reconciliation; any later conflict still stops.
    await recordReadQuietPeriod();
    await resume.before('read-back');
    final saved = await client.runtime.get(resume.appId, outcome.recordId);
    if (!data.entries.every((entry) => saved.data[entry.key] == entry.value))
      throw StateError('Readback differs from the retained record command.');
    await resume.before('reload');
    await client.apps.manifest(resume.appId);
    final reloaded = await client.runtime.get(resume.appId, outcome.recordId);
    if (!data.entries.every((entry) => reloaded.data[entry.key] == entry.value))
      throw StateError('Reload differs from the retained record command.');
    // The original two Account requests leave room for sign-in only. Local
    // cookie deletion is performed by the runner and is not server signout.
    await resume.before('complete');
    await resume.confirmed('complete');
    return recovery;
  } catch (error) {
    resume.budget.stopped = true;
    await resume.failed(error);
    rethrow;
  }
}

Future<void> _mode(String path, String mode) async {
  final result = await Process.run('/bin/chmod', [mode, path]);
  if (result.exitCode != 0)
    throw StateError('Could not restrict continuation recovery permissions.');
}
