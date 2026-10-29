import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

/// Durable local evidence for the one approved synthetic create. The exact
/// request is frozen before dispatch; SDK session storage is a separate folder.
/// This helper never dispatches, retries or reconstructs credentials.
class SmokeCreateRecovery {
  SmokeCreateRecovery._(this.file, this._requestJson, this._context);
  final File file;
  final String _requestJson;
  final Map<String, String> _context;
  String _status = 'unconfirmed';
  String? _confirmedRecordId;
  String get status => _status;
  String get requestSha256 =>
      sha256.convert(utf8.encode(_requestJson)).toString();

  /// Always returns a new copy, so mutations of the original UI object or a
  /// previous returned command cannot change the persisted operation envelope.
  ActionRequest get request {
    final value = jsonDecode(_requestJson) as Map<String, dynamic>;
    return ActionRequest(
      appId: value['appId'] as String,
      actionId: value['actionId'] as String,
      expectedDefinitionVersionId:
          value['expectedDefinitionVersionId'] as String,
      expectedRecordRevision: value['expectedRecordRevision'] as int?,
      targetRecordId: value['targetRecordId'] as String?,
      input: value['input'],
      idempotencyKey: value['idempotencyKey'] as String,
    );
  }

  Map<String, Object> get sanitized => {
    'status': _status,
    'path': file.absolute.path,
    'requestSha256': requestSha256,
  };

  static Future<SmokeCreateRecovery> prepare({
    required Directory directory,
    required ActionRequest request,
    required String endpoint,
    required String projectId,
    required String functionId,
    required String actorId,
    required String collectionId,
  }) async {
    if (await FileSystemEntity.isLink(directory.path)) {
      throw StateError('Smoke recovery directory must not be a symbolic link.');
    }
    await directory.create(recursive: true);
    await _mode(directory.path, '700');
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final previous = jsonDecode(await entry.readAsString());
      if (previous is! Map ||
          !{'confirmed', 'rejected'}.contains(previous['status'])) {
        throw StateError(
          'An unconfirmed smoke create is already retained. Inspect its local recovery receipt before starting another smoke run.',
        );
      }
    }
    final encoded = jsonEncode(request.toJson());
    final operationId =
        'o${sha256.convert(utf8.encode(request.idempotencyKey)).toString().substring(0, 32)}';
    final file = File('${directory.path}/smoke-create-$operationId.json');
    await file.create(exclusive: true);
    await _mode(file.path, '600');
    final recovery = SmokeCreateRecovery._(file, encoded, {
      'endpoint': endpoint,
      'projectId': projectId,
      'functionId': functionId,
      'actorId': actorId,
      'collectionId': collectionId,
    });
    await recovery._save();
    return recovery;
  }

  Future<void> markUncertain() async {
    if (_status == 'confirmed') return;
    _status = 'uncertain';
    await _save();
  }

  Future<void> markConfirmed(ActionOutcome outcome) async {
    final previous = _status;
    _status = 'confirmed';
    _confirmedRecordId = outcome.recordId;
    try {
      await _save();
    } catch (_) {
      _status = previous;
      _confirmedRecordId = null;
      rethrow;
    }
  }

  Future<void> _save() async {
    final command = request;
    final wire = <String, dynamic>{
      'op': 'spec.execute',
      'appId': command.appId,
      'operationId':
          'o${sha256.convert(utf8.encode(command.idempotencyKey)).toString().substring(0, 32)}',
      'versionId': command.expectedDefinitionVersionId,
      'actionId': command.actionId,
      if (command.targetRecordId != null)
        'targetRecordId': command.targetRecordId,
      if (command.expectedRecordRevision != null)
        'expectedRecordRevision': command.expectedRecordRevision,
      'input': command.input,
    };
    final value = {
      'schemaVersion': 1,
      'scope': 'One synthetic Flutter smoke record; no credentials or session tokens',
      'status': _status,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'dispatchMayHaveOccurred': true,
      'context': _context,
      'requestSha256': requestSha256,
      'request': jsonDecode(_requestJson),
      'wireRequest': wire,
      if (_confirmedRecordId != null) 'confirmedRecordId': _confirmedRecordId,
      'recoveryPolicy': 'Do not create a new operation or automatically retry. Reauthenticate as the recorded actor and inspect or explicitly recover this exact operation within a separately approved request budget.',
    };
    final temporary = File('${file.path}.tmp');
    await temporary.create(exclusive: true);
    await _mode(temporary.path, '600');
    try {
      await temporary.writeAsString('${jsonEncode(value)}\n', flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

Future<void> _mode(String path, String mode) async {
  final result = await Process.run('/bin/chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw StateError('Could not restrict local smoke recovery permissions.');
  }
}
