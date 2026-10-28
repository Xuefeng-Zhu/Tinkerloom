import 'dart:convert';
import 'dart:math';

import 'definition.dart';
import 'errors.dart';
import 'store.dart';

export 'errors.dart';
export 'rest.dart';
export 'store.dart';

/// All rows are private to this backend. This migration slice supports owners,
/// not shared membership. A staged app guard fences all supported app mutations.
class PlatformService {
  PlatformService(this.store);
  final RowStore store;
  static final _id = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,35}$');
  static final _random = Random.secure();
  String _nonce() => List.generate(
      16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  String _validId(Object? value) {
    if (value is! String || !_id.hasMatch(value))
      throw const ServiceException('invalid_id', 400);
    return value;
  }

  int _revision(Object? value) {
    if (value is! int || value < 0 || value >= 2147483647)
      throw const ServiceException('invalid_revision', 400);
    return value;
  }

  Future<Map<String, dynamic>> _workspace(String actor, Object? id,
      {String? transactionId}) async {
    final row = await store.get('workspaces', _validId(id),
        transactionId: transactionId);
    if (row == null || row['ownerId'] != actor)
      throw const ServiceException('not_found', 404);
    return row;
  }

  Future<Map<String, dynamic>> _app(String actor, String id,
      {String? transactionId}) async {
    final row = await store.get('apps', id, transactionId: transactionId);
    if (row == null || row['ownerId'] != actor)
      throw const ServiceException('not_found', 404);
    await _workspace(actor, row['workspaceId'], transactionId: transactionId);
    return row;
  }

  Map<String, dynamic> _publicRow(Map<String, dynamic> row,
          {bool app = false}) =>
      {
        'id': row[r'$id'],
        'name': row['name'],
        if (app) 'workspaceId': row['workspaceId'],
      };

  Map<String, dynamic>? _definition(Map<String, dynamic> row, String key) {
    final text = row[key];
    return text == null || text == ''
        ? null
        : validateDefinition(jsonDecode(text as String));
  }

  int _storedRevision(Map<String, dynamic> row, String key) =>
      (row[key] as int?) ?? 0;

  Map<String, dynamic> _publicApp(Map<String, dynamic> row) => {
        ..._publicRow(row, app: true),
        'draftRevision': _storedRevision(row, 'draftRevision'),
        'publishedRevision': _storedRevision(row, 'publishedRevision'),
        'definition': _definition(row, 'draftJson'),
        'publishedDefinition': _definition(row, 'publishedJson'),
      };

  Map<String, dynamic> _publicRecord(
          Map<String, dynamic> row, Map<String, dynamic> definition) =>
      {
        'id': row[r'$id'],
        'revision': row['revision'],
        'values':
            validateValues(definition, jsonDecode(row['valuesJson'] as String)),
      };

  Future<Map<String, dynamic>> _createOnce(
      String table, String id, Map<String, dynamic> data,
      {Map<String, dynamic>? identity}) async {
    try {
      return await store.create(table, id, data);
    } on RestException catch (error) {
      if (error.status != 409) rethrow;
      final old = await store.get(table, id);
      if (old != null &&
          (identity ?? data)
              .entries
              .every((entry) => old[entry.key] == entry.value)) return old;
      throw const ServiceException('id_conflict', 409);
    }
  }

  Future<Map<String, dynamic>?> _receipt(
      String actor, String appId, String operationId, String request,
      {String? transactionId}) async {
    final receipt =
        await store.get('receipts', operationId, transactionId: transactionId);
    if (receipt == null) return null;
    if (receipt['actorId'] != actor ||
        receipt['appId'] != appId ||
        receipt['requestJson'] != request)
      throw const ServiceException('operation_conflict', 409);
    return Map<String, dynamic>.from(
        jsonDecode(receipt['responseJson'] as String) as Map);
  }

  /// Stage the common row before reading versions, then stage data and receipt.
  /// Appwrite detects changes to affected rows since staging at atomic commit.
  Future<Map<String, dynamic>> _mutate(
      String actor,
      Map<String, dynamic> input,
      Future<Map<String, dynamic>> Function(
              String transactionId, Map<String, dynamic> app)
          action) async {
    final appId = _validId(input['appId']);
    final operationId = _validId(input['operationId']);
    final request = canonicalJson(input);
    if (utf8.encode(request).length > 32768)
      throw const ServiceException('request_too_large', 413);
    // Verify access before touching a transaction or checking a global receipt ID.
    await _app(actor, appId);
    final prior = await _receipt(actor, appId, operationId, request);
    if (prior != null) return prior;
    final transactionId = await store.beginTransaction();
    var finished = false;
    try {
      await store.update('apps', appId, {'guard': _nonce()},
          transactionId: transactionId);
      final app = await _app(actor, appId, transactionId: transactionId);
      final old = await _receipt(actor, appId, operationId, request,
          transactionId: transactionId);
      if (old != null) {
        await store.finishTransaction(transactionId, commit: false);
        finished = true;
        return old;
      }
      final response = await action(transactionId, app);
      final encoded = jsonEncode(response);
      if (utf8.encode(encoded).length > 65536)
        throw const ServiceException('response_too_large', 500);
      await store.create(
          'receipts',
          operationId,
          {
            'actorId': actor,
            'appId': appId,
            'requestJson': request,
            'responseJson': encoded,
          },
          transactionId: transactionId);
      await store.finishTransaction(transactionId, commit: true);
      finished = true;
      return response;
    } on ServiceException catch (error) {
      // An earlier duplicate invocation may have committed the same receipt
      // between the initial check and a stale version observation.
      if ({'revision_conflict', 'definition_conflict', 'not_published'}
          .contains(error.code)) {
        final old = await _receipt(actor, appId, operationId, request);
        if (old != null) return old;
      }
      rethrow;
    } on RestException catch (error) {
      if (error.status == 409) {
        final old = await _receipt(actor, appId, operationId, request);
        if (old != null) return old;
        throw const ServiceException('transaction_conflict', 409);
      }
      rethrow;
    } finally {
      if (!finished) {
        try {
          await store.finishTransaction(transactionId, commit: false);
        } catch (_) {
          /* Commit may already have succeeded; a receipt resolves retries. */
        }
      }
    }
  }

  void _inputKeys(Map<String, dynamic> input, Set<String> keys) {
    if (input.keys.any((key) => !keys.contains(key)))
      throw const ServiceException('invalid_request', 400);
  }

  Future<Map<String, dynamic>> execute(
      String actor, Map<String, dynamic> input) async {
    if (actor.isEmpty) throw const ServiceException('unauthenticated', 401);
    switch (input['op']) {
      case 'createWorkspace':
        final row = await _createOnce('workspaces', _validId(input['id']), {
          'ownerId': actor,
          'name': boundedText(input['name'], 128, 'invalid_name')
        });
        return {'workspace': _publicRow(row)};
      case 'listWorkspaces':
        final rows = await store.list('workspaces', {'ownerId': actor});
        return {'workspaces': rows.map(_publicRow).toList()};
      case 'createApp':
        final workspace = await _workspace(actor, input['workspaceId']);
        final identity = {
          'ownerId': actor,
          'workspaceId': workspace[r'$id'],
          'name': boundedText(input['name'], 128, 'invalid_name')
        };
        final row = await _createOnce(
            'apps',
            _validId(input['id']),
            {
              ...identity,
              'draftRevision': 0,
              'publishedRevision': 0,
              'guard': _nonce()
            },
            identity: identity);
        return {'app': _publicRow(row, app: true)};
      case 'listApps':
        final workspace = await _workspace(actor, input['workspaceId']);
        final rows = await store.list('apps',
            {'ownerId': actor, 'workspaceId': workspace[r'$id'] as String});
        return {'apps': rows.map((row) => _publicRow(row, app: true)).toList()};
      case 'getApp':
        _inputKeys(input, {'op', 'appId'});
        return {'app': _publicApp(await _app(actor, _validId(input['appId'])))};
      case 'saveDraft':
        _inputKeys(input,
            {'op', 'appId', 'operationId', 'expectedRevision', 'definition'});
        final expected = _revision(input['expectedRevision']);
        final definition = validateDefinition(input['definition']);
        final normalized = {...input, 'definition': definition};
        return _mutate(actor, normalized, (transactionId, app) async {
          if (_storedRevision(app, 'draftRevision') != expected)
            throw const ServiceException('revision_conflict', 409);
          final row = await store.update(
              'apps',
              input['appId'] as String,
              {
                'draftRevision': expected + 1,
                'draftJson': jsonEncode(definition)
              },
              transactionId: transactionId);
          return {'app': _publicApp(row)};
        });
      case 'publishApp':
        _inputKeys(input, {'op', 'appId', 'operationId', 'expectedRevision'});
        final expected = _revision(input['expectedRevision']);
        return _mutate(actor, input, (transactionId, app) async {
          if (_storedRevision(app, 'draftRevision') != expected)
            throw const ServiceException('revision_conflict', 409);
          final definition = _definition(app, 'draftJson');
          if (definition == null || expected == 0)
            throw const ServiceException('not_published', 409);
          final published = _definition(app, 'publishedJson');
          if (published != null) requireCompatible(published, definition);
          final row = await store.update(
              'apps',
              input['appId'] as String,
              {
                'publishedRevision': expected,
                'publishedJson': jsonEncode(definition)
              },
              transactionId: transactionId);
          return {'app': _publicApp(row)};
        });
      case 'listRecords':
        _inputKeys(input, {'op', 'appId', 'definitionRevision', 'afterId'});
        final appId = _validId(input['appId']);
        final app = await _app(actor, appId);
        final expected = _revision(input['definitionRevision']);
        final published = _storedRevision(app, 'publishedRevision');
        if (published == 0) throw const ServiceException('not_published', 409);
        if (expected != published)
          throw const ServiceException('definition_conflict', 409);
        final afterId =
            input['afterId'] == null ? null : _validId(input['afterId']);
        if (afterId != null) {
          final cursor = await store.get('records', afterId);
          if (cursor == null ||
              cursor['ownerId'] != actor ||
              cursor['appId'] != appId)
            throw const ServiceException('not_found', 404);
        }
        final rows = await store.list(
            'records', {'ownerId': actor, 'appId': appId},
            limit: 11, afterId: afterId, detectOverflow: false);
        final current = await _app(actor, appId);
        if (_storedRevision(current, 'publishedRevision') != published)
          throw const ServiceException('definition_conflict', 409);
        final definition = _definition(app, 'publishedJson')!;
        final page = rows.take(10).toList();
        return {
          'records': page.map((row) => _publicRecord(row, definition)).toList(),
          'definitionRevision': published,
          'nextCursor': rows.length > 10 ? page.last[r'$id'] : null
        };
      case 'saveRecord':
        _inputKeys(input, {
          'op',
          'appId',
          'id',
          'operationId',
          'expectedRevision',
          'definitionRevision',
          'values'
        });
        final expected = _revision(input['expectedRevision']);
        final definitionRevision = _revision(input['definitionRevision']);
        final recordId = _validId(input['id']);
        // Request identity includes the exact values; validation occurs against
        // the definition inside the guarded transaction, not a stale pre-read.
        return _mutate(actor, input, (transactionId, app) async {
          final published = _storedRevision(app, 'publishedRevision');
          if (published == 0)
            throw const ServiceException('not_published', 409);
          if (published != definitionRevision)
            throw const ServiceException('definition_conflict', 409);
          final definition = _definition(app, 'publishedJson')!;
          final values = validateValues(definition, input['values']);
          final old = await store.get('records', recordId,
              transactionId: transactionId);
          if (old != null &&
              (old['ownerId'] != actor || old['appId'] != input['appId']))
            throw const ServiceException('not_found', 404);
          if ((old?['revision'] ?? 0) != expected)
            throw const ServiceException('revision_conflict', 409);
          final data = <String, dynamic>{
            'ownerId': actor,
            'appId': input['appId'],
            'revision': expected + 1,
            'definitionRevision': published,
            'valuesJson': jsonEncode(values)
          };
          final row = old == null
              ? await store.create('records', recordId, data,
                  transactionId: transactionId)
              : await store.update('records', recordId, data,
                  transactionId: transactionId);
          return {
            'record': _publicRecord(row, definition),
            'definitionRevision': published
          };
        });
      default:
        throw const ServiceException('unknown_operation', 400);
    }
  }
}
