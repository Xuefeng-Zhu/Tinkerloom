library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:appwrite/enums.dart' as awe;
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'src/models.dart';
export 'src/models.dart';
part 'src/endpoints.dart';
part 'src/session.dart';
part 'src/adapter.dart';

enum RetainedCommandStatus { none, confirmed, pending }

typedef FunctionTransport = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> request,
);

/// Opaque evidence of one uncertain guidance request in one client session.
/// It does not prove whether the provider completed or consumed quota.
class PendingGuidanceAcknowledgement {
  PendingGuidanceAcknowledgement._(this._envelope, this._epoch);
  final Map<String, dynamic> _envelope;
  final int _epoch;
  String get request => _envelope['request'] as String;
  String? get workspaceId => _envelope['workspaceId'] as String?;
  String? get appId => _envelope['appId'] as String?;
}

/// Counts actual dispatches, including failed requests. Function calls are not
/// database-operation counts: a trusted function can perform several DB reads.
class RequestBudget {
  RequestBudget({
    this.maxFunctions = 12,
    this.maxAccounts = 2,
    this.maxMutations = 1,
  });
  final int maxFunctions, maxAccounts, maxMutations;
  int functions = 0, accounts = 0, mutations = 0;
  bool stopped = false;
  void account() {
    if (stopped || accounts >= maxAccounts) {
      stopped = true;
      throw NestError(
        category: 'request_budget',
        message: 'The authentication request budget is exhausted.',
      );
    }
    accounts++;
  }

  void function(bool mutation) {
    if (stopped ||
        functions >= maxFunctions ||
        (mutation && mutations >= maxMutations)) {
      stopped = true;
      throw NestError(
        category: 'request_budget',
        message: 'The Cloud smoke request budget is exhausted.',
      );
    }
    functions++;
    if (mutation) mutations++;
  }

  Map<String, Object> get counts => {
    'functions': functions,
    'accounts': accounts,
    'mutations': mutations,
    'stopped': stopped,
  };
}

class BackendNetworkException extends NestError {
  BackendNetworkException(String message, {bool uncertain = false})
    : super(category: 'network', message: message, uncertain: uncertain);
}

class BackendUnauthorized extends NestError {
  BackendUnauthorized(String message)
    : super(category: 'unauthenticated', message: message, status: 401);
}

class BackendForbidden extends NestError {
  BackendForbidden(String message)
    : super(category: 'forbidden', message: message, status: 403);
}

class BackendNotFound extends NestError {
  BackendNotFound(String message)
    : super(category: 'not_found', message: message, status: 404);
}

class BackendMediaProcessing extends NestError {
  BackendMediaProcessing(this.appId, this.assetId)
    : super(
        category: 'media_processing',
        message: 'The image is processing. Check its status to attach it when ready.',
      );
  final String appId, assetId;
}

/// A builder command whose outcome is being recovered during this client session.
/// Its exact original envelope remains private and is never reconstructed by UI.
class RetainedBuilderRecovery {
  const RetainedBuilderRecovery._(
    this.appId,
    this.operation,
    this.receiptConfirmed,
    this._command,
    this._epoch,
  );
  final String appId;
  final String operation;
  final bool receiptConfirmed;
  final Map<String, dynamic> _command;
  final int _epoch;
}

/// Compatibility at the presentation boundary, not Serverpod's wire protocol.
/// The only live data path is authenticated Appwrite Functions.
class Client {
  Client(
    String endpoint, {
    String projectId = '',
    String functionId = '',
    FunctionTransport? transport,
    ClientAuth? auth,
    this.budget,
    Duration? connectionTimeout,
    Duration? streamingConnectionTimeout,
  }) : host = endpoint {
    late final sdk = aw.Client()
        .setEndpoint(
          endpoint.isEmpty ? 'https://unconfigured.invalid/v1' : endpoint,
        )
        .setProject(projectId);
    late final account = aw.Account(sdk);
    late final functions = aw.Functions(sdk);
    void requireConfiguration() {
      if (endpoint.isEmpty || projectId.isEmpty || functionId.isEmpty) {
        throw NestError(
          category: 'configuration',
          message: 'Configure the Appwrite endpoint, project and Function before connecting.',
        );
      }
    }

    this.auth =
        auth ??
        ClientAuth(
          restore: () async {
            requireConfiguration();
            budget?.account();
            try {
              final user = await account.get();
              return {'id': user.$id, 'email': user.email};
            } on aw.AppwriteException catch (e) {
              if (e.code == 401) return null;
              _accountFailure(e);
            }
          },
          signIn: (email, password) async {
            requireConfiguration();
            budget?.account();
            try {
              final session = await account.createEmailPasswordSession(
                email: email,
                password: password,
              );
              return {'id': session.userId, 'email': email};
            } on aw.AppwriteException catch (e) {
              _accountFailure(e);
            }
          },
          signUp: (email, password) async {
            requireConfiguration();
            budget?.account();
            try {
              final user = await account.create(
                userId: aw.ID.unique(),
                email: email,
                password: password,
              );
              return {'id': user.$id, 'email': user.email};
            } on aw.AppwriteException catch (e) {
              _accountFailure(e);
            }
          },
          signOut: () async {
            requireConfiguration();
            budget?.account();
            try {
              await account.deleteSession(sessionId: 'current');
            } on aw.AppwriteException catch (e) {
              if (e.code != 401) _accountFailure(e);
            }
          },
        );
    _transport =
        transport ??
        (input) async {
          if (endpoint.isEmpty || projectId.isEmpty || functionId.isEmpty) {
            throw NestError(
              category: 'configuration',
              message: 'Configure the Appwrite endpoint, project and Function before connecting.',
            );
          }
          final mutation = !_readOps.contains(input['op']);
          try {
            final execution = await functions.createExecution(
              functionId: functionId,
              body: jsonEncode(input),
              xasync: false,
              headers: {'content-type': 'application/json'},
            );
            // Quota can be reported even when the Function body is empty,
            // malformed, or the execution did not complete normally.
            final status = execution.responseStatusCode;
            if (status == 429 || status == 402) budget?.stopped = true;
            if (execution.status != awe.ExecutionStatus.completed)
              throw BackendNetworkException(
                'The server result is unknown. Retain this operation before retrying.',
                uncertain: mutation,
              );
            Object? body;
            try {
              body = jsonDecode(execution.responseBody);
            } catch (_) {
              throw BackendNetworkException(
                'The server returned an unreadable response.',
                uncertain: mutation,
              );
            }
            if (body is! Map<String, dynamic>)
              throw BackendNetworkException(
                'The server returned an unreadable response.',
                uncertain: mutation,
              );
            if (execution.responseStatusCode < 200 ||
                execution.responseStatusCode >= 300) {
              final code = body['error'] is String
                  ? body['error'] as String
                  : 'backend_unavailable';
              if (code == 'quota_exceeded') budget?.stopped = true;
              if (status == 408 || status == 425 || status >= 500)
                throw BackendNetworkException(
                  'The server could not confirm this request.',
                  uncertain: mutation,
                );
              throw _failure(code, status);
            }
            return body;
          } on aw.AppwriteException catch (e) {
            // The SDK can lose the HTTP status while decoding a malformed
            // gateway response. A bounded smoke must stop when quota cannot be
            // ruled out; ordinary clients have no budget to reset or stop.
            if (e.code == null || e.code == 429 || e.code == 402)
              budget?.stopped = true;
            // Gateway timeout and too-early responses cannot prove that a
            // submitted mutation did not reach or commit in the Function.
            if (e.code == 408 || e.code == 425)
              throw BackendNetworkException(
                'The server could not confirm this request.',
                uncertain: mutation,
              );
            if (e.code != null && e.code! >= 400 && e.code! < 500)
              throw _failure('appwrite_${e.code}', e.code!);
            throw BackendNetworkException(
              'Could not reach Appwrite. Your current values are retained.',
              uncertain: mutation,
            );
          }
        };
    apps = EndpointApps(this);
    builder = EndpointBuilder(this);
    runtime = EndpointRuntime(this);
    media = EndpointMedia(this);
    this.auth.addListener(_sessionChanged);
  }
  final String host;
  final RequestBudget? budget;
  late final ClientAuth auth;
  late final FunctionTransport _transport;
  late final EndpointApps apps;
  late final EndpointBuilder builder;
  late final EndpointRuntime runtime;
  late final EndpointMedia media;
  final Map<String, Map<String, dynamic>> _apps = {},
      _summaries = {},
      _inbox = {},
      _tickets = {};
  final Map<String, String> _commandIds = {};
  final Map<String, Future<Map<String, dynamic>>> _reads = {};
  final Map<String, StreamController<AppEvent>> _events = {};
  Map<String, dynamic>? _retained;
  Future<void> _readTail = Future.value();
  int _epoch = 0, _eventRevision = 0;
  bool _closed = false;
  bool _mutationInFlight = false;
  bool _receiptInFlight = false;
  bool _recoveryReadInFlight = false;
  RetainedBuilderRecovery? _builderRecovery;
  final ValueNotifier<int> _builderRecoveryRevision = ValueNotifier<int>(0);
  PendingGuidanceAcknowledgement? _pendingGuidance;
  final ValueNotifier<int> _guidanceRevision = ValueNotifier<int>(0);

  /// Local state only: subscribing never checks a server or repeats a request.
  Listenable get guidanceRecoveryChanges => _guidanceRevision;
  PendingGuidanceAcknowledgement? get pendingGuidanceAcknowledgement =>
      _pendingGuidance;

  void _setPendingGuidance(PendingGuidanceAcknowledgement? value) {
    if (identical(_pendingGuidance, value)) return;
    _pendingGuidance = value;
    _guidanceRevision.value++;
  }

  /// State only; listening never performs a network call or retries a command.
  Listenable get builderRecoveryChanges => _builderRecoveryRevision;
  RetainedBuilderRecovery? get pendingBuilderRecovery => _builderRecovery;

  void _setBuilderRecovery(RetainedBuilderRecovery? value) {
    if (identical(value, _builderRecovery)) return;
    _builderRecovery = value;
    _builderRecoveryRevision.value++;
  }

  void _retainBuilderRecovery(Map<String, dynamic> command) {
    if (!{'spec.generate', 'spec.saveDraft'}.contains(command['op']) ||
        command['appId'] is! String) {
      _setBuilderRecovery(null);
      return;
    }
    _setBuilderRecovery(
      RetainedBuilderRecovery._(
        command['appId'] as String,
        command['op'] as String,
        false,
        command,
        _epoch,
      ),
    );
  }

  void _finishBuilderRecoveryRead(
    RetainedBuilderRecovery? checkpoint,
    int epoch,
  ) {
    if (checkpoint != null &&
        checkpoint.receiptConfirmed &&
        identical(_builderRecovery, checkpoint) &&
        epoch == _epoch) {
      _setBuilderRecovery(null);
    }
  }

  /// Changes whenever this client observes an authentication-session change.
  int get sessionEpoch => _epoch;
  static final _random = Random.secure();
  String newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  static const _readOps = {
    'listWorkspaces',
    'listApps',
    'listMembers',
    'spec.capabilities',
    'spec.templates',
    'spec.getApp',
    'spec.commandReceipt',
    'spec.review',
    'spec.getGeneration',
    'spec.watch',
    'spec.query',
    'spec.getRecord',
    'spec.summary',
    'spec.aggregate',
    'spec.reminderState',
    'spec.runs',
    'spec.listActivity',
    'spec.inbox',
    'spec.launcher',
    'spec.listDrafts',
    'spec.listVersions',
    'spec.getVersion',
    'spec.appAccess',
    'spec.media.status',
    'spec.media.read',
    'spec.media.usage',
  };
  Never _accountFailure(aw.AppwriteException e) {
    // The SDK can lose the status while decoding an invalid gateway body.
    // A bounded smoke must stop if a quota response cannot be ruled out.
    if (e.code == null || e.code == 429 || e.code == 402)
      budget?.stopped = true;
    throw _failure(
      e.code == 401 ? 'unauthenticated' : 'account_unavailable',
      e.code ?? 503,
    );
  }

  void _sessionChanged() {
    _epoch++;
    _apps.clear();
    _summaries.clear();
    _inbox.clear();
    _tickets.clear();
    _commandIds.clear();
    _retained = null;
    _setBuilderRecovery(null);
    _setPendingGuidance(null);
    _reads.clear();
    for (final events in _events.values) {
      events.addError(
        BackendUnauthorized('Your session changed. Reopen the app.'),
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _epoch++;
    _setBuilderRecovery(null);
    _setPendingGuidance(null);
    auth.removeListener(_sessionChanged);
    for (final events in _events.values) {
      await events.close();
    }
    _events.clear();
    _apps.clear();
    _summaries.clear();
    _inbox.clear();
    _tickets.clear();
  }

  Future<void> dispose() => close();
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async => await _endpoint(endpoint, method, args) as T;
  dynamic callStreamingServerEndpoint<T, R>(
    String endpoint,
    String method,
    Map<String, dynamic> args,
    Map<String, Stream> connectionArgs, {
    bool authenticated = true,
  }) {
    if (endpoint != 'runtime' || method != 'events')
      return Stream.error(UnsupportedError('Streaming is unavailable.'));
    final appId = _id(args['appId']);
    return (_events[appId] ??= StreamController<AppEvent>.broadcast()).stream
        .cast<R>();
  }

  Future<void> closeStreamingMethodConnections({Object? exception}) async {}

  /// Capture only the exact guidance operation initiated by this screen.
  /// This does not perform network I/O or clear any pending operation.
  PendingGuidanceAcknowledgement? capturePendingGuidance({
    required int sessionEpoch,
    required String request,
    String? workspaceId,
    String? appId,
  }) {
    if (_closed || sessionEpoch != _epoch) {
      throw BackendUnauthorized('Your session changed. Reopen the app.');
    }
    if (_mutationInFlight ||
        _receiptInFlight ||
        _recoveryReadInFlight ||
        _builderRecovery?.receiptConfirmed == true) {
      throw NestError(
        category: 'command_in_progress',
        message: 'Wait for the current request to finish.',
      );
    }
    final pending = _retained;
    if (pending == null || pending['op'] != 'spec.guidance') return null;
    final workspace = pending['workspaceId'];
    final matchesScope = appId == null
        ? workspaceId != null &&
              workspace == workspaceId &&
              pending['appId'] == null
        : pending['appId'] == appId &&
              workspace is String &&
              workspace.isNotEmpty &&
              (workspaceId == null || workspace == workspaceId);
    if (!matchesScope || pending['request'] != request) return null;
    return PendingGuidanceAcknowledgement._(pending, _epoch);
  }

  /// After explicit user acknowledgment, abandon only this retained guidance
  /// result. The request may still consume provider or Appwrite quota.
  void acknowledgePendingGuidance(PendingGuidanceAcknowledgement token) {
    if (_closed || token._epoch != _epoch) {
      throw BackendUnauthorized('Your session changed. Reopen the app.');
    }
    if (_mutationInFlight ||
        _receiptInFlight ||
        _recoveryReadInFlight ||
        _builderRecovery?.receiptConfirmed == true) {
      throw NestError(
        category: 'command_in_progress',
        message: 'Wait for the current request to finish.',
      );
    }
    if (!identical(token._envelope, _retained) ||
        token._envelope['op'] != 'spec.guidance') {
      throw NestError(
        category: 'pending_command',
        message: 'This guidance request is no longer the pending operation.',
      );
    }
    _retained = null;
    _setPendingGuidance(null);
  }

  /// Manually check an opaque, session-bound retained builder command. A null
  /// result means no receipt was found, which does not rule out a later commit.
  /// The original write is never replayed; failures preserve the checkpoint.
  Future<BuilderSnapshot?> checkPendingBuilderRecovery(
    RetainedBuilderRecovery handle,
  ) async {
    if (_closed ||
        handle._epoch != _epoch ||
        !identical(_builderRecovery, handle)) {
      throw BackendUnauthorized(
        'This recovery belongs to an expired session or request.',
      );
    }
    if (_mutationInFlight || _receiptInFlight || _recoveryReadInFlight) {
      throw NestError(
        category: 'command_in_progress',
        message:
            'Wait for the current request to finish before checking status.',
      );
    }
    _recoveryReadInFlight = true;
    final epoch = _epoch;
    try {
      if (!handle.receiptConfirmed) {
        final command = handle._command;
        final status = await confirmRetainedBuilderCommand(
          appId: handle.appId,
          operation: handle.operation,
          expectedRevision: command['expectedRevision'] as int,
          request: command['request'] as String?,
          startFromScratch: command['startFromScratch'] as bool?,
          candidateHash: handle.operation == 'spec.saveDraft'
              ? spec.AppSpec.parse(jsonEncode(command['spec'])).hash
              : null,
        );
        if (status != RetainedCommandStatus.confirmed) return null;
      }
      final checkpoint = _builderRecovery;
      if (_closed ||
          epoch != _epoch ||
          checkpoint == null ||
          !checkpoint.receiptConfirmed ||
          !identical(checkpoint._command, handle._command)) {
        throw BackendUnauthorized(
          'This recovery belongs to an expired session or request.',
        );
      }
      final snapshot = await builder.getForRecovery(handle.appId);
      if (_closed || epoch != _epoch) {
        throw BackendUnauthorized(
          'This recovery belongs to an expired session.',
        );
      }
      return snapshot;
    } finally {
      _recoveryReadInFlight = false;
    }
  }

  /// Explicitly set aside a committed builder request when its draft can no
  /// longer be opened. This neither retries the operation nor resets a budget.
  void setAsideConfirmedBuilderRecovery(RetainedBuilderRecovery handle) {
    if (_closed ||
        handle._epoch != _epoch ||
        !identical(_builderRecovery, handle)) {
      throw BackendUnauthorized(
        'This recovery belongs to an expired session or request.',
      );
    }
    if (_mutationInFlight || _receiptInFlight || _recoveryReadInFlight) {
      throw NestError(
        category: 'command_in_progress',
        message: 'Wait for the current request to finish.',
      );
    }
    if (!handle.receiptConfirmed || _retained != null) {
      throw NestError(
        category: 'pending_command',
        message: 'The request has not been confirmed and cannot be set aside.',
      );
    }
    _setBuilderRecovery(null);
  }

  /// Explicitly check an exact retained builder command without replaying it.
  /// A missing receipt is not proof that an in-flight command will not commit.
  Future<RetainedCommandStatus> confirmRetainedBuilderCommand({
    required String appId,
    required String operation,
    required int expectedRevision,
    String? request,
    bool? startFromScratch,
    String? candidateHash,
  }) async {
    final pending = _retained;
    if (pending == null) return RetainedCommandStatus.none;
    final matchesBase =
        pending['appId'] == appId &&
        pending['op'] == operation &&
        pending['expectedRevision'] == expectedRevision;
    final matchesDetails = !matchesBase
        ? false
        : switch (operation) {
            'spec.generate' =>
              request != null &&
                  startFromScratch != null &&
                  pending['request'] == request &&
                  pending['startFromScratch'] == startFromScratch,
            'spec.saveDraft' =>
              candidateHash != null &&
                  spec.AppSpec.parse(jsonEncode(pending['spec'])).hash ==
                      candidateHash,
            _ => false,
          };
    if (!matchesBase || !matchesDetails) {
      throw NestError(
        category: 'pending_command',
        message:
            'Resolve the retained operation before submitting another change.',
      );
    }
    if (_mutationInFlight || _receiptInFlight) {
      throw NestError(
        category: 'command_in_progress',
        message:
            'Wait for the current request to finish before checking status.',
      );
    }
    final epoch = _epoch;
    _receiptInFlight = true;
    try {
      final result = await this.request({
        'op': 'spec.commandReceipt',
        'command': pending,
      });
      if (_closed || epoch != _epoch || !identical(_retained, pending)) {
        throw BackendUnauthorized('This result belongs to an expired session.');
      }
      if (result['confirmed'] is! bool) {
        throw NestError(
          category: 'invalid_response',
          message: 'The operation receipt could not be confirmed.',
        );
      }
      if (result['confirmed'] == true) {
        final id = pending['operationId'];
        final recovery = _builderRecovery;
        if (recovery != null &&
            identical(recovery._command, pending) &&
            recovery._epoch == epoch) {
          _setBuilderRecovery(
            RetainedBuilderRecovery._(
              recovery.appId,
              recovery.operation,
              true,
              pending,
              epoch,
            ),
          );
        }
        _retained = null;
        _commandIds.removeWhere((key, value) => value == id);
        return RetainedCommandStatus.confirmed;
      }
      return RetainedCommandStatus.pending;
    } finally {
      _receiptInFlight = false;
    }
  }

  String _operation(String logical) => _commandIds.putIfAbsent(logical, newId);
  Future<Map<String, dynamic>> request(Map<String, dynamic> input) {
    final frozen = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(input)) as Map,
    );
    final read = _readOps.contains(frozen['op']);
    final key = jsonEncode(frozen), epoch = _epoch;
    if (read && _reads[key] != null) return _reads[key]!;
    Future<Map<String, dynamic>> send() async {
      if (_closed || epoch != _epoch)
        throw BackendUnauthorized(
          'This request belongs to an expired session.',
        );
      if (!read && _retained != null && jsonEncode(_retained) != key)
        throw NestError(
          category: 'pending_command',
          message: 'Resolve the retained operation before submitting another change.',
        );
      if (!read &&
          (_mutationInFlight || _receiptInFlight || _recoveryReadInFlight)) {
        throw NestError(
          category: 'command_in_progress',
          message: 'Wait for the current change to finish before submitting another.',
        );
      }
      if (!read && _builderRecovery?.receiptConfirmed == true) {
        throw NestError(
          category: 'pending_command',
          message: 'Check the current draft before submitting another change.',
        );
      }
      budget?.function(!read);
      if (!read) _mutationInFlight = true;
      try {
        final response = await _transport(frozen);
        _validateResponse(frozen, response);
        if (_closed || epoch != _epoch)
          throw BackendUnauthorized(
            'This response belongs to an expired session.',
          );
        if (!read) {
          if (_retained?['op'] == 'spec.guidance') {
            _setPendingGuidance(null);
          }
          final previous = _retained;
          final recovery = _builderRecovery;
          if (previous != null &&
              recovery != null &&
              identical(recovery._command, previous) &&
              jsonEncode(previous) == key) {
            _setBuilderRecovery(null);
          }
          _retained = null;
          final appId = frozen['appId'] ?? frozen['id'];
          if (appId is String)
            _events[appId]?.add(
              AppEvent(
                appId: appId,
                revision: ++_eventRevision,
                kind: 'changed',
              ),
            );
        }
        return response;
      } catch (error) {
        if (_closed || epoch != _epoch) {
          throw BackendUnauthorized(
            'This result belongs to an expired session.',
          );
        }
        if (error is NestError &&
            (error.status == 429 ||
                error.status == 402 ||
                error.category == 'quota_exceeded'))
          budget?.stopped = true;
        if (!read &&
            (error is! NestError ||
                error.uncertain ||
                error.category == 'invalid_response')) {
          _retained = frozen;
          _retainBuilderRecovery(frozen);
          if (frozen['op'] == 'spec.guidance' &&
              frozen['request'] is String &&
              (frozen['workspaceId'] == null ||
                  frozen['workspaceId'] is String) &&
              (frozen['appId'] == null || frozen['appId'] is String)) {
            _setPendingGuidance(
              PendingGuidanceAcknowledgement._(frozen, _epoch),
            );
          }
          budget?.stopped = true;
          if (error is! NestError || !error.uncertain) {
            throw BackendNetworkException(
              'The submitted change could not be confirmed. Retain this operation before retrying.',
              uncertain: true,
            );
          }
        }
        rethrow;
      } finally {
        if (!read) _mutationInFlight = false;
      }
    }

    if (!read) return send();
    final result = _readTail.then((_) => send());
    _readTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _reads[key] = result;
    result.then<void>(
      (_) {
        if (identical(_reads[key], result)) _reads.remove(key);
      },
      onError: (Object _, StackTrace __) {
        if (identical(_reads[key], result)) _reads.remove(key);
      },
    );
    return result;
  }

  Future<Map<String, dynamic>> _command(
    String logical,
    Map<String, dynamic> input,
  ) async {
    final result = await request({
      ...input,
      'operationId': _operation(logical),
    });
    _commandIds.remove(logical);
    return result;
  }
}

NestError _failure(String code, int status) {
  if (status == 401)
    return BackendUnauthorized('Your session has expired. Sign in again.');
  if (status == 403)
    return BackendForbidden('You do not have permission for this action.');
  if (status == 404)
    return BackendNotFound('This item is unavailable or your access changed.');
  return NestError(
    category: code,
    status: status,
    message: switch (code) {
      'revision_conflict' || 'definition_conflict' =>
        'This item changed. Refresh before editing again.',
      'quota_exceeded' || 'appwrite_429' =>
        'The free development quota is exhausted. Try again after it resets.',
      'provider_unavailable' =>
        'AI is not configured. Use templates or manual editing.',
      'generation_pending' =>
        'Finish or resolve the current generation before publishing.',
      'invalid_values' => 'Check the submitted field values.',
      _ => 'The request could not be completed ($code).',
    },
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map)
    throw NestError(
      category: 'invalid_response',
      message: 'The backend returned an invalid response.',
    );
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _rows(Object? value) {
  if (value is! List)
    throw NestError(
      category: 'invalid_response',
      message: 'The backend returned an invalid list.',
    );
  return value.map(_map).toList();
}

String _id(Object? value) {
  if (value is! String ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$').hasMatch(value))
    throw NestError(
      category: 'invalid_response',
      message: 'The backend returned an invalid identifier.',
    );
  return value;
}
