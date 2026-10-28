import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'providers/provider.dart' as ai;
import 'providers/creation_compiler.dart' as compiler;
import 'providers/generation_quality.dart' as quality;
import 'providers/generation_requirements.dart' as requirements;
import 'providers/repair_bindings.dart' as repair;

import 'definition.dart';
import 'errors.dart';
import 'store.dart';
import 'image_sanitizer.dart';
import 'media_store.dart';

export 'errors.dart';
export 'rest.dart';
export 'store.dart';
export 'media_store.dart';
export 'media_rest.dart';

part 'collaboration.dart';
part 'drafts.dart';
part 'spec_runtime.dart';
part 'spec_actions.dart';
part 'spec_queries.dart';
part 'spec_lifecycle.dart';
part 'spec_watch.dart';
part 'private_media.dart';
part 'worker_support.dart';
part 'reminders.dart';
part 'generation.dart';
part 'inbox.dart';
part 'worker_dispatch.dart';

typedef Row = Map<String, dynamic>;

class AppAccess {
  const AppAccess(this.app, this.workspace, this.role);
  final Row app;
  final Row workspace;
  final String role;
  bool get builder => role == 'owner' || role == 'builder';
  bool get archived => app['archived'] == true;
  Row get capabilities => {
    'editDefinition': builder && !archived,
    'share': builder && !archived,
    // The bounded definition has personal-tracker policy. Workflow/capacity
    // member actions must go through their future registered handlers.
    'writeRecords': builder && !archived,
    'archive': role == 'owner' && !archived,
    'revokeAccess': builder,
  };
}

/// Private tables are accessed exclusively through this authenticated service.
/// Membership and app grants are independent requirements. Every supported app
/// mutation stages the workspace and app guards before rechecking authority.
class PlatformService {
  PlatformService(
    this.store, {
    DateTime Function()? clock,
    this.media,
    this.mediaProjectBytes = MediaLimits.maxProjectBytes,
    this.aiProvider,
    ai.GuidanceProvider? guidanceProvider,
    this.remindersEnabled = false,
    this.wakeups,
  }) : clock = clock ?? (() => DateTime.now().toUtc()),
       guidanceProvider =
           guidanceProvider ??
           (aiProvider is ai.GuidanceProvider
               ? aiProvider as ai.GuidanceProvider
               : null);
  final RowStore store;
  final PrivateFileStore? media;
  final int mediaProjectBytes;
  final DateTime Function() clock;
  final ai.AiProvider? aiProvider;
  final ai.GuidanceProvider? guidanceProvider;
  final bool remindersEnabled;
  final WorkerWakeups? wakeups;
  static final _id = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,35}$');
  static final _random = Random.secure();
  String _nonce() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String _identity(String kind, List<String> parts) =>
      '$kind${sha256.convert(utf8.encode(jsonEncode(parts))).toString().substring(0, 32)}';

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

  int _storedRevision(Row row, String key) => (row[key] as int?) ?? 0;

  Future<Row?> _membership(
    String workspaceId,
    String actor, {
    String? transactionId,
  }) => store.get(
    'memberships',
    _identity('m', [workspaceId, actor]),
    transactionId: transactionId,
  );

  bool _validMembership(Row? member, String workspaceId, String actor) =>
      member != null &&
      member['workspaceId'] == workspaceId &&
      member['actorId'] == actor &&
      member['active'] == true;

  Future<Row> _workspace(
    String actor,
    Object? id, {
    String? transactionId,
  }) async {
    final workspaceId = _validId(id);
    final row = await store.get(
      'workspaces',
      workspaceId,
      transactionId: transactionId,
    );
    if (row == null) throw const ServiceException('not_found', 404);
    // Existing v1 owners have implicit membership until their first guarded
    // operation creates a membership row. Other actors always need a real row.
    if (row['ownerId'] != actor &&
        !_validMembership(
          await _membership(workspaceId, actor, transactionId: transactionId),
          workspaceId,
          actor,
        ))
      throw const ServiceException('not_found', 404);
    return row;
  }

  Future<Row?> _grant(String appId, String actor, {String? transactionId}) =>
      store.get(
        'grants',
        _identity('g', [appId, actor]),
        transactionId: transactionId,
      );

  bool _validGrant(Row? grant, Row app, String actor) =>
      grant != null &&
      grant['appId'] == app[r'$id'] &&
      grant['workspaceId'] == app['workspaceId'] &&
      grant['actorId'] == actor &&
      grant['revoked'] == false &&
      {'builder', 'member', 'viewer'}.contains(grant['role']);

  Future<AppAccess> _access(
    String actor,
    String appId, {
    String? transactionId,
  }) async {
    final app = await store.get('apps', appId, transactionId: transactionId);
    if (app == null) throw const ServiceException('not_found', 404);
    final workspace = await _workspace(
      actor,
      app['workspaceId'],
      transactionId: transactionId,
    );
    if (app['ownerId'] == actor) return AppAccess(app, workspace, 'owner');
    final grant = await _grant(appId, actor, transactionId: transactionId);
    if (!_validGrant(grant, app, actor))
      throw const ServiceException('not_found', 404);
    return AppAccess(app, workspace, grant!['role'] as String);
  }

  void _require(AppAccess access, String capability, {bool writable = true}) {
    if ((capability == 'owner' && access.role != 'owner') ||
        ({'build', 'share', 'write'}.contains(capability) && !access.builder)) {
      throw const ServiceException('forbidden', 403);
    }
    if (writable && access.archived)
      throw const ServiceException('app_archived', 403);
  }

  Row _publicRow(Row row, {bool app = false}) => {
    'id': row[r'$id'],
    'name': row['name'],
    if (app) 'workspaceId': row['workspaceId'],
  };

  Row _publicWorkspace(Row row, String actor) => {
    ..._publicRow(row),
    'role': row['ownerId'] == actor ? 'owner' : 'member',
  };

  Row _appSummary(AppAccess access) => {
    ..._publicRow(access.app, app: true),
    'role': access.role,
    'archived': access.archived,
    'capabilities': access.capabilities,
    'engine': access.app['engine'] == 'appspec.v1'
        ? 'appspec.v1'
        : 'bounded.v1',
  };

  Row? _definition(Row row, String key) {
    final text = row[key];
    return text == null || text == ''
        ? null
        : validateDefinition(jsonDecode(text as String));
  }

  Row _publicRecord(Row row, Row definition) => {
    'id': row[r'$id'],
    'revision': row['revision'],
    'values': validateValues(
      definition,
      jsonDecode(row['valuesJson'] as String),
    ),
  };

  Future<T> _transaction<T>(
    Future<T> Function(String transactionId) action,
  ) async {
    final transactionId = await store.beginTransaction();
    var committed = false;
    try {
      final response = await action(transactionId);
      await store.finishTransaction(transactionId, commit: true);
      committed = true;
      return response;
    } on RestException catch (error) {
      if (error.status == 409)
        throw const ServiceException('transaction_conflict', 409);
      rethrow;
    } finally {
      if (!committed) {
        try {
          await store.finishTransaction(transactionId, commit: false);
        } catch (_) {
          // A lost commit response cannot undo the authoritative receipt.
        }
      }
    }
  }

  Future<AppAccess> _stageAccess(
    String actor,
    AppAccess initial,
    String transactionId,
  ) async {
    await store.update('workspaces', initial.workspace[r'$id'] as String, {
      'guard': _nonce(),
    }, transactionId: transactionId);
    await store.update('apps', initial.app[r'$id'] as String, {
      'guard': _nonce(),
    }, transactionId: transactionId);
    final current = await _access(
      actor,
      initial.app[r'$id'] as String,
      transactionId: transactionId,
    );
    if (current.app['workspaceId'] != initial.workspace[r'$id'])
      throw const ServiceException('not_found', 404);
    return _adoptLegacyDraft(current, transactionId);
  }

  Future<Row?> _receipt(
    String actor,
    String appId,
    String operationId,
    String request, {
    String? transactionId,
  }) async {
    final receipt = await store.get(
      'receipts',
      operationId,
      transactionId: transactionId,
    );
    if (receipt == null) return null;
    if (receipt['actorId'] != actor ||
        receipt['appId'] != appId ||
        receipt['requestJson'] != request)
      throw const ServiceException('operation_conflict', 409);
    return Map<String, dynamic>.from(
      jsonDecode(receipt['responseJson'] as String) as Map,
    );
  }

  Future<void> _saveReceipt(
    String actor,
    String appId,
    String operationId,
    String request,
    Row response,
    String transactionId, {
    int maximumBytes = 65536,
  }) async {
    final encoded = jsonEncode(response);
    if (utf8.encode(encoded).length > maximumBytes)
      throw const ServiceException('response_too_large', 500);
    await store.create('receipts', operationId, {
      'actorId': actor,
      'appId': appId,
      'requestJson': request,
      'responseJson': encoded,
    }, transactionId: transactionId);
  }

  String _request(Row input, {int maximumBytes = 32768}) {
    final request = canonicalJson(input);
    if (utf8.encode(request).length > maximumBytes)
      throw const ServiceException('request_too_large', 413);
    return request;
  }

  Future<Row?> _authorizedReceipt(
    String actor,
    String appId,
    String operationId,
    String request,
    String capability, {
    Future<void> Function(AppAccess, String?)? authorize,
  }) async {
    final initial = await _access(actor, appId);
    _require(initial, capability, writable: false);
    if (authorize != null) await authorize(initial, null);
    final receipt = await _receipt(actor, appId, operationId, request);
    // Do not let a receipt read bypass a grant/workspace revocation occurring
    // during hydration, including the conflict/error recovery paths below.
    if (receipt != null) {
      final current = await _access(actor, appId);
      _require(current, capability, writable: false);
      if (authorize != null) await authorize(current, null);
    }
    return receipt;
  }

  Future<Row> _mutate(
    String actor,
    Row input,
    String capability,
    Future<Row> Function(String transactionId, AppAccess access) action, {
    bool writable = true,
    int requestBytes = 32768,
    int responseBytes = 65536,
    Future<void> Function(AppAccess, String?)? authorize,
  }) async {
    final appId = _validId(input['appId']);
    final operationId = _validId(input['operationId']);
    final request = _request(input, maximumBytes: requestBytes);
    final initial = await _access(actor, appId);
    final receiptResponseBytes = initial.app['engine'] == 'appspec.v1'
        ? max(responseBytes, _specResponseBytes)
        : responseBytes;
    if (initial.app['engine'] == 'appspec.v1' &&
        {'saveDraft', 'publishApp', 'saveRecord'}.contains(input['op']))
      throw const ServiceException('unsupported_runtime', 400);
    _require(initial, capability, writable: false);
    final previous = await _authorizedReceipt(
      actor,
      appId,
      operationId,
      request,
      capability,
      authorize: authorize,
    );
    if (previous != null) return previous;
    try {
      return await _transaction((transactionId) async {
        final access = await _stageAccess(actor, initial, transactionId);
        _require(access, capability, writable: false);
        if (authorize != null) await authorize(access, transactionId);
        final old = await _receipt(
          actor,
          appId,
          operationId,
          request,
          transactionId: transactionId,
        );
        if (old != null) return old;
        // Archive suppresses new work, while a currently authorized actor may
        // still recover the exact result of a previously committed command.
        _require(access, capability, writable: writable);
        final response = await action(transactionId, access);
        if (access.app['engine'] == 'appspec.v1' &&
            !(input['op'] as String).startsWith('spec.')) {
          await _specChanged(
            actor,
            access,
            operationId,
            input['op'] as String,
            transactionId,
          );
          if (response.containsKey('app'))
            response['app'] = await _publicSpecApp(
              actor,
              await _access(actor, appId, transactionId: transactionId),
              transactionId,
            );
        }
        await _saveReceipt(
          actor,
          appId,
          operationId,
          request,
          response,
          transactionId,
          maximumBytes: receiptResponseBytes,
        );
        return response;
      });
    } on ServiceException catch (error) {
      if ({
        'revision_conflict',
        'definition_conflict',
        'not_published',
        'transaction_conflict',
        'id_conflict',
        'app_archived',
      }.contains(error.code)) {
        final old = await _authorizedReceipt(
          actor,
          appId,
          operationId,
          request,
          capability,
          authorize: authorize,
        );
        if (old != null) return old;
      }
      rethrow;
    }
  }

  Future<AppAccess> _readAgain(String actor, AppAccess before) async {
    final current = await _access(actor, before.app[r'$id'] as String);
    if (current.app['guard'] != before.app['guard'] ||
        current.workspace['guard'] != before.workspace['guard'] ||
        current.role != before.role)
      throw const ServiceException('definition_conflict', 409);
    return current;
  }

  void _inputKeys(Row input, Set<String> keys) {
    if (input.keys.any((key) => !keys.contains(key)))
      throw const ServiceException('invalid_request', 400);
  }

  Future<Row> execute(String actor, Row input) async {
    if (actor.isEmpty) throw const ServiceException('unauthenticated', 401);
    _validId(actor);
    if (input['op'] is String && (input['op'] as String).startsWith('spec.')) {
      try {
        return await _executeSpec(actor, input);
      } on spec.SpecException {
        throw const ServiceException('invalid_spec', 400);
      }
    }
    switch (input['op']) {
      case 'createWorkspace':
        _inputKeys(input, {'op', 'id', 'name'});
        final id = _validId(input['id']);
        final name = boundedText(input['name'], 128, 'invalid_name');
        final old = await store.get('workspaces', id);
        if (old != null) {
          if (old['ownerId'] != actor || old['name'] != name)
            throw const ServiceException('id_conflict', 409);
          return {'workspace': _publicWorkspace(old, actor)};
        }
        return _transaction((tx) async {
          await _reserveWorkspace(actor, tx);
          final row = await store.create('workspaces', id, {
            'ownerId': actor,
            'name': name,
            'guard': _nonce(),
          }, transactionId: tx);
          await _ensureMembership(row, actor, tx, owner: true);
          return {'workspace': _publicWorkspace(row, actor)};
        });
      case 'listWorkspaces':
        _inputKeys(input, {'op'});
        final owned = await store.list('workspaces', {'ownerId': actor});
        final members = await store.list('memberships', {'actorId': actor});
        final rows = {for (final row in owned) row[r'$id'] as String: row};
        for (final member in members) {
          if (member['active'] != true) continue;
          final id = member['workspaceId'] as String;
          if (!_validMembership(member, id, actor)) continue;
          try {
            rows[id] = await _workspace(actor, id);
          } on ServiceException catch (error) {
            if (error.code != 'not_found') rethrow;
          }
        }
        if (rows.length > 100)
          throw const ServiceException('too_many_results', 409);
        final sorted = rows.values.toList()
          ..sort(
            (a, b) => (a[r'$id'] as String).compareTo(b[r'$id'] as String),
          );
        final visible = <Row>[];
        for (final row in sorted) {
          try {
            visible.add(
              _publicWorkspace(await _workspace(actor, row[r'$id']), actor),
            );
          } on ServiceException catch (error) {
            if (error.code != 'not_found') rethrow;
          }
        }
        return {'workspaces': visible};
      case 'createApp':
        _inputKeys(input, {'op', 'id', 'workspaceId', 'name'});
        final workspace = await _workspace(actor, input['workspaceId']);
        final id = _validId(input['id']);
        final name = boundedText(input['name'], 128, 'invalid_name');
        return _transaction((tx) async {
          await store.update('workspaces', workspace[r'$id'] as String, {
            'guard': _nonce(),
          }, transactionId: tx);
          final current = await _workspace(
            actor,
            workspace[r'$id'],
            transactionId: tx,
          );
          await _ensureMembership(
            current,
            actor,
            tx,
            owner: current['ownerId'] == actor,
          );
          final old = await store.get('apps', id, transactionId: tx);
          if (old != null) {
            if (old['ownerId'] != actor ||
                old['workspaceId'] != current[r'$id'] ||
                old['name'] != name)
              throw const ServiceException('id_conflict', 409);
            return {
              'app': _appSummary(await _access(actor, id, transactionId: tx)),
            };
          }
          final apps = await store.list('apps', {
            'workspaceId': current[r'$id'] as String,
          }, transactionId: tx);
          if (apps.length >= 100)
            throw const ServiceException('quota_exceeded', 429);
          final row = await store.create('apps', id, {
            'ownerId': actor,
            'workspaceId': current[r'$id'],
            'name': name,
            'draftRevision': 0,
            'publishedRevision': 0,
            'headRevision': 0,
            'guard': _nonce(),
            'archived': false,
          }, transactionId: tx);
          return {'app': _appSummary(AppAccess(row, current, 'owner'))};
        });
      case 'listApps':
        _inputKeys(input, {'op', 'workspaceId'});
        final workspace = await _workspace(actor, input['workspaceId']);
        final rows = await store.list('apps', {
          'workspaceId': workspace[r'$id'] as String,
        });
        final result = <Row>[];
        for (final row in rows) {
          try {
            final access = await _access(actor, row[r'$id'] as String);
            if (access.role != 'owner' &&
                (row['engine'] == 'appspec.v1'
                    ? row['specVersionId'] == null
                    : _storedRevision(row, 'publishedRevision') == 0))
              continue;
            result.add(_appSummary(access));
          } on ServiceException catch (error) {
            if (error.code != 'not_found') rethrow;
          }
        }
        final currentWorkspace = await _workspace(actor, workspace[r'$id']);
        if (currentWorkspace['guard'] != workspace['guard'])
          throw const ServiceException('definition_conflict', 409);
        return {'apps': result};
      case 'getAppAccess':
        _inputKeys(input, {'op', 'appId'});
        final access = await _access(actor, _validId(input['appId']));
        final app = _appSummary(access);
        await _readAgain(actor, access);
        return {'app': app};
      case 'getApp':
        _inputKeys(input, {'op', 'appId'});
        final access = await _access(actor, _validId(input['appId']));
        if (access.app['engine'] == 'appspec.v1')
          throw const ServiceException('unsupported_runtime', 400);
        if (access.role != 'owner' &&
            _storedRevision(access.app, 'publishedRevision') == 0)
          throw const ServiceException('not_found', 404);
        final app = await _publicApp(actor, access);
        await _readAgain(actor, access);
        return {'app': app};
      case 'saveDraft':
        return _saveDraft(actor, input);
      case 'publishApp':
        return _publishApp(actor, input);
      case 'listRecords':
        _inputKeys(input, {'op', 'appId', 'definitionRevision', 'afterId'});
        final appId = _validId(input['appId']);
        final access = await _access(actor, appId);
        if (access.app['engine'] == 'appspec.v1')
          throw const ServiceException('unsupported_runtime', 400);
        final expected = _revision(input['definitionRevision']);
        final published = _storedRevision(access.app, 'publishedRevision');
        if (published == 0) throw const ServiceException('not_published', 409);
        if (expected != published)
          throw const ServiceException('definition_conflict', 409);
        final afterId = input['afterId'] == null
            ? null
            : _validId(input['afterId']);
        if (afterId != null) {
          final cursor = await store.get('records', afterId);
          if (cursor == null ||
              cursor['ownerId'] != access.app['ownerId'] ||
              cursor['appId'] != appId)
            throw const ServiceException('not_found', 404);
        }
        final rows = await store.list(
          'records',
          {'ownerId': access.app['ownerId'] as String, 'appId': appId},
          limit: 11,
          afterId: afterId,
          detectOverflow: false,
        );
        await _readAgain(actor, access);
        final definition = _definition(access.app, 'publishedJson')!;
        final page = rows.take(10).toList();
        return {
          'records': page.map((row) => _publicRecord(row, definition)).toList(),
          'definitionRevision': published,
          'nextCursor': rows.length > 10 ? page.last[r'$id'] : null,
        };
      case 'saveRecord':
        _inputKeys(input, {
          'op',
          'appId',
          'id',
          'operationId',
          'expectedRevision',
          'definitionRevision',
          'values',
        });
        final expected = _revision(input['expectedRevision']);
        final definitionRevision = _revision(input['definitionRevision']);
        final recordId = _validId(input['id']);
        return _mutate(actor, input, 'write', (tx, access) async {
          final published = _storedRevision(access.app, 'publishedRevision');
          if (published == 0)
            throw const ServiceException('not_published', 409);
          if (published != definitionRevision)
            throw const ServiceException('definition_conflict', 409);
          final definition = _definition(access.app, 'publishedJson')!;
          final values = validateValues(definition, input['values']);
          final old = await store.get('records', recordId, transactionId: tx);
          if (old != null &&
              (old['ownerId'] != access.app['ownerId'] ||
                  old['appId'] != access.app[r'$id']))
            throw const ServiceException('not_found', 404);
          if ((old?['revision'] ?? 0) != expected)
            throw const ServiceException('revision_conflict', 409);
          if (expected >= 2147483646)
            throw const ServiceException('revision_conflict', 409);
          final data = <String, dynamic>{
            'ownerId': access.app['ownerId'],
            'appId': access.app[r'$id'],
            'revision': expected + 1,
            'definitionRevision': published,
            'valuesJson': jsonEncode(values),
          };
          final row = old == null
              ? await store.create('records', recordId, data, transactionId: tx)
              : await store.update(
                  'records',
                  recordId,
                  data,
                  transactionId: tx,
                );
          return {
            'record': _publicRecord(row, definition),
            'definitionRevision': published,
          };
        });
      case 'createInvitation':
        return _createInvitation(actor, input);
      case 'acceptInvitation':
        return _acceptInvitation(actor, input);
      case 'inspectInvitation':
        return _inspectInvitation(actor, input);
      case 'listInvitations':
        return _listInvitations(actor, input);
      case 'revokeInvitation':
        return _revokeInvitation(actor, input);
      case 'listMembers':
        return _listMembers(actor, input);
      case 'setGrant':
        return _setGrant(actor, input);
      case 'archiveApp':
        _inputKeys(input, {'op', 'appId', 'operationId'});
        return _mutate(actor, input, 'owner', (tx, access) async {
          final app = await store.update('apps', access.app[r'$id'] as String, {
            'archived': true,
          }, transactionId: tx);
          return {
            'app': await _publicApp(
              actor,
              AppAccess(app, access.workspace, access.role),
              transactionId: tx,
            ),
          };
        }, writable: false);
      default:
        throw const ServiceException('unknown_operation', 400);
    }
  }
}
