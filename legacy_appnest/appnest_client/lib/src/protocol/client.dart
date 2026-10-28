/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _ida;
import 'dart:typed_data' as _idt;
import 'package:appnest_client/src/protocol/action_outcome.dart' as _ik2rv6uc;
import 'package:appnest_client/src/protocol/action_request.dart' as _ijhj5a9o;
import 'package:appnest_client/src/protocol/activity_item.dart' as _ihdhb6mh;
import 'package:appnest_client/src/protocol/app_event.dart' as _ioi01lgx;
import 'package:appnest_client/src/protocol/app_manifest.dart' as _igbv6cp9;
import 'package:appnest_client/src/protocol/builder_snapshot.dart' as _i3ykup7f;
import 'package:appnest_client/src/protocol/greetings/greeting.dart'
    as _ip90moho;
import 'package:appnest_client/src/protocol/guidance_question.dart'
    as _ir7xtg43;
import 'package:appnest_client/src/protocol/inbox_item.dart' as _ic0zicoc;
import 'package:appnest_client/src/protocol/media_info.dart' as _i7y3k4w3;
import 'package:appnest_client/src/protocol/media_upload_request.dart'
    as _iwc6jxej;
import 'package:appnest_client/src/protocol/media_upload_ticket.dart'
    as _if8lxgor;
import 'package:appnest_client/src/protocol/member_info.dart' as _iqjsfrnp;
import 'package:appnest_client/src/protocol/platform_info.dart' as _iulf0zlt;
import 'package:appnest_client/src/protocol/publish_request.dart' as _iqanq366;
import 'package:appnest_client/src/protocol/record_page.dart' as _iwu2xk3k;
import 'package:appnest_client/src/protocol/record_summary.dart' as _i4pq30c6;
import 'package:appnest_client/src/protocol/reminder_state.dart' as _i1a6ysmx;
import 'package:appnest_client/src/protocol/runtime_record.dart' as _itbezqp1;
import 'package:appnest_client/src/protocol/template_info.dart' as _ik25ew2o;
import 'package:appnest_client/src/protocol/workspace_info.dart' as _i1i173ve;
import 'package:http/http.dart' as _i85jenna;
import 'package:serverpod_auth_core_client/serverpod_auth_core_client.dart'
    as _iacc;
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart'
    as _iaic;
import 'package:serverpod_client/serverpod_client.dart' as _isc;
import 'protocol.dart' as _il2as5qe;

/// By extending [EmailIdpBaseEndpoint], the email identity provider endpoints
/// are made available on the server and enable the corresponding sign-in widget
/// on the client.
/// {@category Endpoint}
class EndpointEmailIdp extends _iaic.EndpointEmailIdpBase {
  EndpointEmailIdp(_isc.EndpointCaller caller) : super(caller);

  @override
  String get name => 'emailIdp';

  /// Logs in the user and returns a new session.
  ///
  /// Throws an [EmailAccountLoginException] in case of errors, with reason:
  /// - [EmailAccountLoginExceptionReason.invalidCredentials] if the email or
  ///   password is incorrect.
  /// - [EmailAccountLoginExceptionReason.tooManyAttempts] if there have been
  ///   too many failed login attempts.
  ///
  /// Throws an [AuthUserBlockedException] if the auth user is blocked.
  @override
  _ida.Future<_iacc.AuthSuccess> login({
    required String email,
    required String password,
  }) => caller.callServerEndpoint<_iacc.AuthSuccess>(
    'emailIdp',
    'login',
    {
      'email': email,
      'password': password,
    },
  );

  /// Starts the registration for a new user account with an email-based login
  /// associated to it.
  ///
  /// Upon successful completion of this method, an email will have been
  /// sent to [email] with a verification link, which the user must open to
  /// complete the registration.
  ///
  /// Always returns a account request ID, which can be used to complete the
  /// registration. If the email is already registered, the returned ID will not
  /// be valid.
  @override
  _ida.Future<_isc.UuidValue> startRegistration({required String email}) =>
      caller.callServerEndpoint<_isc.UuidValue>(
        'emailIdp',
        'startRegistration',
        {'email': email},
      );

  /// Verifies an account request code and returns a token
  /// that can be used to complete the account creation.
  ///
  /// Throws an [EmailAccountRequestException] in case of errors, with reason:
  /// - [EmailAccountRequestExceptionReason.expired] if the account request has
  ///   already expired.
  /// - [EmailAccountRequestExceptionReason.policyViolation] if the password
  ///   does not comply with the password policy.
  /// - [EmailAccountRequestExceptionReason.invalid] if no request exists
  ///   for the given [accountRequestId] or [verificationCode] is invalid.
  @override
  _ida.Future<String> verifyRegistrationCode({
    required _isc.UuidValue accountRequestId,
    required String verificationCode,
  }) => caller.callServerEndpoint<String>(
    'emailIdp',
    'verifyRegistrationCode',
    {
      'accountRequestId': accountRequestId,
      'verificationCode': verificationCode,
    },
  );

  /// Completes a new account registration, creating a new auth user with a
  /// profile and attaching the given email account to it.
  ///
  /// Throws an [EmailAccountRequestException] in case of errors, with reason:
  /// - [EmailAccountRequestExceptionReason.expired] if the account request has
  ///   already expired.
  /// - [EmailAccountRequestExceptionReason.policyViolation] if the password
  ///   does not comply with the password policy.
  /// - [EmailAccountRequestExceptionReason.invalid] if the [registrationToken]
  ///   is invalid.
  ///
  /// Throws an [AuthUserBlockedException] if the auth user is blocked.
  ///
  /// Returns a session for the newly created user.
  @override
  _ida.Future<_iacc.AuthSuccess> finishRegistration({
    required String registrationToken,
    required String password,
  }) => caller.callServerEndpoint<_iacc.AuthSuccess>(
    'emailIdp',
    'finishRegistration',
    {
      'registrationToken': registrationToken,
      'password': password,
    },
  );

  /// Requests a password reset for [email].
  ///
  /// If the email address is registered, an email with reset instructions will
  /// be send out. If the email is unknown, this method will have no effect.
  ///
  /// Always returns a password reset request ID, which can be used to complete
  /// the reset. If the email is not registered, the returned ID will not be
  /// valid.
  ///
  /// Throws an [EmailAccountPasswordResetException] in case of errors, with reason:
  /// - [EmailAccountPasswordResetExceptionReason.tooManyAttempts] if the user has
  ///   made too many attempts trying to request a password reset.
  ///
  @override
  _ida.Future<_isc.UuidValue> startPasswordReset({required String email}) =>
      caller.callServerEndpoint<_isc.UuidValue>(
        'emailIdp',
        'startPasswordReset',
        {'email': email},
      );

  /// Verifies a password reset code and returns a finishPasswordResetToken
  /// that can be used to finish the password reset.
  ///
  /// Throws an [EmailAccountPasswordResetException] in case of errors, with reason:
  /// - [EmailAccountPasswordResetExceptionReason.expired] if the password reset
  ///   request has already expired.
  /// - [EmailAccountPasswordResetExceptionReason.tooManyAttempts] if the user has
  ///   made too many attempts trying to verify the password reset.
  /// - [EmailAccountPasswordResetExceptionReason.invalid] if no request exists
  ///   for the given [passwordResetRequestId] or [verificationCode] is invalid.
  ///
  /// If multiple steps are required to complete the password reset, this endpoint
  /// should be overridden to return credentials for the next step instead
  /// of the credentials for setting the password.
  @override
  _ida.Future<String> verifyPasswordResetCode({
    required _isc.UuidValue passwordResetRequestId,
    required String verificationCode,
  }) => caller.callServerEndpoint<String>(
    'emailIdp',
    'verifyPasswordResetCode',
    {
      'passwordResetRequestId': passwordResetRequestId,
      'verificationCode': verificationCode,
    },
  );

  /// Completes a password reset request by setting a new password.
  ///
  /// The [verificationCode] returned from [verifyPasswordResetCode] is used to
  /// validate the password reset request.
  ///
  /// Throws an [EmailAccountPasswordResetException] in case of errors, with reason:
  /// - [EmailAccountPasswordResetExceptionReason.expired] if the password reset
  ///   request has already expired.
  /// - [EmailAccountPasswordResetExceptionReason.policyViolation] if the new
  ///   password does not comply with the password policy.
  /// - [EmailAccountPasswordResetExceptionReason.invalid] if no request exists
  ///   for the given [passwordResetRequestId] or [verificationCode] is invalid.
  ///
  /// Throws an [AuthUserBlockedException] if the auth user is blocked.
  @override
  _ida.Future<void> finishPasswordReset({
    required String finishPasswordResetToken,
    required String newPassword,
  }) => caller.callServerEndpoint<void>(
    'emailIdp',
    'finishPasswordReset',
    {
      'finishPasswordResetToken': finishPasswordResetToken,
      'newPassword': newPassword,
    },
  );

  @override
  _ida.Future<bool> hasAccount() => caller.callServerEndpoint<bool>(
    'emailIdp',
    'hasAccount',
    {},
  );
}

/// By extending [RefreshJwtTokensEndpoint], the JWT token refresh endpoint
/// is made available on the server and enables automatic token refresh on the client.
/// {@category Endpoint}
class EndpointJwtRefresh extends _iacc.EndpointRefreshJwtTokens {
  EndpointJwtRefresh(_isc.EndpointCaller caller) : super(caller);

  @override
  String get name => 'jwtRefresh';

  /// Creates a new token pair for the given [refreshToken].
  ///
  /// If [refreshToken] is omitted, cookie-mode web clients fall back to the
  /// configured HttpOnly refresh cookie. When neither source is present this
  /// throws [RefreshTokenNotFoundException], the same public "no usable refresh
  /// credential" exception used for unknown refresh tokens.
  ///
  /// Can throw the following exceptions:
  /// -[RefreshTokenMalformedException]: refresh token is malformed and could
  ///   not be parsed. Not expected to happen for tokens issued by the server.
  /// -[RefreshTokenNotFoundException]: refresh token is unknown to the server.
  ///   Either the token was deleted or generated by a different server.
  /// -[RefreshTokenExpiredException]: refresh token has expired. Will happen
  ///   only if it has not been used within configured `refreshTokenLifetime`.
  /// -[RefreshTokenInvalidSecretException]: refresh token is incorrect, meaning
  ///   it does not refer to the current secret refresh token. This indicates
  ///   either a malfunctioning client or a malicious attempt by someone who has
  ///   obtained the refresh token. In this case the underlying refresh token
  ///   will be deleted, and access to it will expire fully when the last access
  ///   token is elapsed.
  ///
  /// This endpoint is unauthenticated, meaning the client won't include any
  /// authentication information with the call.
  @override
  _ida.Future<_iacc.AuthSuccess> refreshAccessToken({String? refreshToken}) =>
      caller.callServerEndpoint<_iacc.AuthSuccess>(
        'jwtRefresh',
        'refreshAccessToken',
        {'refreshToken': refreshToken},
        authenticated: false,
      );
}

/// {@category Endpoint}
class EndpointApps extends _isc.EndpointRef {
  EndpointApps(_isc.EndpointCaller caller) : super(caller);

  @override
  String get name => 'apps';

  _ida.Future<List<_i1i173ve.WorkspaceInfo>> workspaces() =>
      caller.callServerEndpoint<List<_i1i173ve.WorkspaceInfo>>(
        'apps',
        'workspaces',
        {},
      );

  _ida.Future<int> createWorkspace(String name) =>
      caller.callServerEndpoint<int>(
        'apps',
        'createWorkspace',
        {'name': name},
      );

  _ida.Future<List<_igbv6cp9.AppManifest>> list(int workspaceId) =>
      caller.callServerEndpoint<List<_igbv6cp9.AppManifest>>(
        'apps',
        'list',
        {'workspaceId': workspaceId},
      );

  _ida.Future<_igbv6cp9.AppManifest> manifest(int appId) =>
      caller.callServerEndpoint<_igbv6cp9.AppManifest>(
        'apps',
        'manifest',
        {'appId': appId},
      );

  _ida.Future<List<_ik25ew2o.TemplateInfo>> templates() =>
      caller.callServerEndpoint<List<_ik25ew2o.TemplateInfo>>(
        'apps',
        'templates',
        {},
      );

  _ida.Future<int> instantiate(
    int workspaceId,
    String templateKey,
  ) => caller.callServerEndpoint<int>(
    'apps',
    'instantiate',
    {
      'workspaceId': workspaceId,
      'templateKey': templateKey,
    },
  );

  _ida.Future<int> remix(
    int appId,
    int workspaceId,
  ) => caller.callServerEndpoint<int>(
    'apps',
    'remix',
    {
      'appId': appId,
      'workspaceId': workspaceId,
    },
  );

  _ida.Future<void> pin(
    int appId,
    bool pinned,
  ) => caller.callServerEndpoint<void>(
    'apps',
    'pin',
    {
      'appId': appId,
      'pinned': pinned,
    },
  );

  _ida.Future<void> archive(int appId) => caller.callServerEndpoint<void>(
    'apps',
    'archive',
    {'appId': appId},
  );

  _ida.Future<String> invite(
    int appId,
    String role,
    String? recipientId,
  ) => caller.callServerEndpoint<String>(
    'apps',
    'invite',
    {
      'appId': appId,
      'role': role,
      'recipientId': recipientId,
    },
  );

  _ida.Future<int> acceptInvitation(String token) =>
      caller.callServerEndpoint<int>(
        'apps',
        'acceptInvitation',
        {'token': token},
      );

  _ida.Future<void> revokeInvitation(
    int appId,
    String token,
  ) => caller.callServerEndpoint<void>(
    'apps',
    'revokeInvitation',
    {
      'appId': appId,
      'token': token,
    },
  );

  _ida.Future<List<_iqjsfrnp.MemberInfo>> members(int appId) =>
      caller.callServerEndpoint<List<_iqjsfrnp.MemberInfo>>(
        'apps',
        'members',
        {'appId': appId},
      );

  _ida.Future<void> setGrant(
    int appId,
    String target,
    String? role,
  ) => caller.callServerEndpoint<void>(
    'apps',
    'setGrant',
    {
      'appId': appId,
      'target': target,
      'role': role,
    },
  );

  _ida.Future<List<_ihdhb6mh.ActivityItem>> activity(int appId) =>
      caller.callServerEndpoint<List<_ihdhb6mh.ActivityItem>>(
        'apps',
        'activity',
        {'appId': appId},
      );
}

/// {@category Endpoint}
class EndpointBuilder extends _isc.EndpointRef {
  EndpointBuilder(_isc.EndpointCaller caller) : super(caller);

  @override
  String get name => 'builder';

  _ida.Future<_iulf0zlt.PlatformInfo> platform() =>
      caller.callServerEndpoint<_iulf0zlt.PlatformInfo>(
        'builder',
        'platform',
        {},
      );

  _ida.Future<_i3ykup7f.BuilderSnapshot> begin(
    int workspaceId,
    String templateKey,
    int? appId,
  ) => caller.callServerEndpoint<_i3ykup7f.BuilderSnapshot>(
    'builder',
    'begin',
    {
      'workspaceId': workspaceId,
      'templateKey': templateKey,
      'appId': appId,
    },
  );

  _ida.Future<_i3ykup7f.BuilderSnapshot> get(int draftId) =>
      caller.callServerEndpoint<_i3ykup7f.BuilderSnapshot>(
        'builder',
        'get',
        {'draftId': draftId},
      );

  _ida.Future<List<_ir7xtg43.GuidanceQuestion>> suggestQuestions(
    String idea,
    int? workspaceId,
    int? draftId,
  ) => caller.callServerEndpoint<List<_ir7xtg43.GuidanceQuestion>>(
    'builder',
    'suggestQuestions',
    {
      'idea': idea,
      'workspaceId': workspaceId,
      'draftId': draftId,
    },
  );

  _ida.Future<_i3ykup7f.BuilderSnapshot> patch(
    int draftId,
    int mutation,
    String patchJson,
  ) => caller.callServerEndpoint<_i3ykup7f.BuilderSnapshot>(
    'builder',
    'patch',
    {
      'draftId': draftId,
      'mutation': mutation,
      'patchJson': patchJson,
    },
  );

  _ida.Future<_i3ykup7f.BuilderSnapshot> generate(
    int draftId,
    int mutation,
    String request, {
    bool? startFromScratch,
  }) => caller.callServerEndpoint<_i3ykup7f.BuilderSnapshot>(
    'builder',
    'generate',
    {
      'draftId': draftId,
      'mutation': mutation,
      'request': request,
      'startFromScratch': startFromScratch,
    },
  );

  _ida.Future<int> publish(_iqanq366.PublishRequest request) =>
      caller.callServerEndpoint<int>(
        'builder',
        'publish',
        {'request': request},
      );

  _ida.Future<_i3ykup7f.BuilderSnapshot> abandonFailedEdit(
    int draftId,
    int mutation,
    int jobId,
  ) => caller.callServerEndpoint<_i3ykup7f.BuilderSnapshot>(
    'builder',
    'abandonFailedEdit',
    {
      'draftId': draftId,
      'mutation': mutation,
      'jobId': jobId,
    },
  );

  _ida.Future<List<_ihdhb6mh.ActivityItem>> runs(int appId) =>
      caller.callServerEndpoint<List<_ihdhb6mh.ActivityItem>>(
        'builder',
        'runs',
        {'appId': appId},
      );
}

/// {@category Endpoint}
class EndpointMedia extends _isc.EndpointRef {
  EndpointMedia(_isc.EndpointCaller caller) : super(caller);

  @override
  String get name => 'media';

  _ida.Future<_if8lxgor.MediaUploadTicket> beginUpload(
    _iwc6jxej.MediaUploadRequest request,
  ) => caller.callServerEndpoint<_if8lxgor.MediaUploadTicket>(
    'media',
    'beginUpload',
    {'request': request},
  );

  _ida.Future<_i7y3k4w3.MediaInfo> completeUpload(
    int appId,
    String assetId,
  ) => caller.callServerEndpoint<_i7y3k4w3.MediaInfo>(
    'media',
    'completeUpload',
    {
      'appId': appId,
      'assetId': assetId,
    },
  );

  _ida.Future<_idt.ByteData> readImage(
    int appId,
    String assetId,
    String variant,
  ) => caller.callServerEndpoint<_idt.ByteData>(
    'media',
    'readImage',
    {
      'appId': appId,
      'assetId': assetId,
      'variant': variant,
    },
  );
}

/// {@category Endpoint}
class EndpointRuntime extends _isc.EndpointRef {
  EndpointRuntime(_isc.EndpointCaller caller) : super(caller);

  @override
  String get name => 'runtime';

  _ida.Future<_iwu2xk3k.RecordPage> query(
    int appId,
    String collectionId,
    String queryJson,
  ) => caller.callServerEndpoint<_iwu2xk3k.RecordPage>(
    'runtime',
    'query',
    {
      'appId': appId,
      'collectionId': collectionId,
      'queryJson': queryJson,
    },
  );

  _ida.Future<_i4pq30c6.RecordSummary> summary(
    int appId,
    String collectionId,
    String queryJson,
    String groupFieldId,
  ) => caller.callServerEndpoint<_i4pq30c6.RecordSummary>(
    'runtime',
    'summary',
    {
      'appId': appId,
      'collectionId': collectionId,
      'queryJson': queryJson,
      'groupFieldId': groupFieldId,
    },
  );

  _ida.Future<String> aggregate(
    int appId,
    String collectionId,
    String queryJson,
    String aggregateJson,
  ) => caller.callServerEndpoint<String>(
    'runtime',
    'aggregate',
    {
      'appId': appId,
      'collectionId': collectionId,
      'queryJson': queryJson,
      'aggregateJson': aggregateJson,
    },
  );

  _ida.Future<List<_i1a6ysmx.ReminderState>> reminderState(
    int appId,
    int recordId,
  ) => caller.callServerEndpoint<List<_i1a6ysmx.ReminderState>>(
    'runtime',
    'reminderState',
    {
      'appId': appId,
      'recordId': recordId,
    },
  );

  _ida.Future<_itbezqp1.RuntimeRecord> get(
    int appId,
    int recordId,
  ) => caller.callServerEndpoint<_itbezqp1.RuntimeRecord>(
    'runtime',
    'get',
    {
      'appId': appId,
      'recordId': recordId,
    },
  );

  _ida.Future<_ik2rv6uc.ActionOutcome> execute(
    _ijhj5a9o.ActionRequest request,
  ) => caller.callServerEndpoint<_ik2rv6uc.ActionOutcome>(
    'runtime',
    'execute',
    {'request': request},
  );

  _ida.Future<List<_ic0zicoc.InboxItem>> inbox() =>
      caller.callServerEndpoint<List<_ic0zicoc.InboxItem>>(
        'runtime',
        'inbox',
        {},
      );

  _ida.Future<void> readNotification(int id) => caller.callServerEndpoint<void>(
    'runtime',
    'readNotification',
    {'id': id},
  );

  _ida.Stream<_ioi01lgx.AppEvent> events(int appId) =>
      caller.callStreamingServerEndpoint<
        _ida.Stream<_ioi01lgx.AppEvent>,
        _ioi01lgx.AppEvent
      >(
        'runtime',
        'events',
        {'appId': appId},
        {},
      );
}

/// This is an example endpoint that returns a greeting message through
/// its [hello] method.
/// {@category Endpoint}
class EndpointGreeting extends _isc.EndpointRef {
  EndpointGreeting(_isc.EndpointCaller caller) : super(caller);

  @override
  String get name => 'greeting';

  /// Returns a personalized greeting message: "Hello {name}".
  _ida.Future<_ip90moho.Greeting> hello(String name) =>
      caller.callServerEndpoint<_ip90moho.Greeting>(
        'greeting',
        'hello',
        {'name': name},
      );
}

class Modules {
  Modules(Client client) {
    serverpod_auth_idp = _iaic.Caller(client);
    serverpod_auth_core = _iacc.Caller(client);
  }

  late final _iaic.Caller serverpod_auth_idp;

  late final _iacc.Caller serverpod_auth_core;
}

class Client extends _isc.ServerpodClientShared {
  Client(
    String host, {
    dynamic securityContext,
    Duration? streamingConnectionTimeout,
    Duration? connectionTimeout,
    Function(
      _isc.MethodCallContext,
      Object,
      StackTrace,
    )?
    onFailedCall,
    Function(_isc.MethodCallContext)? onSucceededCall,
    bool? disconnectStreamsOnLostInternetConnection,
    _i85jenna.Client? httpClientOverride,
  }) : super(
         host,
         _il2as5qe.Protocol(),
         securityContext: securityContext,
         streamingConnectionTimeout: streamingConnectionTimeout,
         connectionTimeout: connectionTimeout,
         onFailedCall: onFailedCall,
         onSucceededCall: onSucceededCall,
         disconnectStreamsOnLostInternetConnection:
             disconnectStreamsOnLostInternetConnection,
         httpClientOverride: httpClientOverride,
       ) {
    emailIdp = EndpointEmailIdp(this);
    jwtRefresh = EndpointJwtRefresh(this);
    apps = EndpointApps(this);
    builder = EndpointBuilder(this);
    media = EndpointMedia(this);
    runtime = EndpointRuntime(this);
    greeting = EndpointGreeting(this);
    modules = Modules(this);
  }

  late final EndpointEmailIdp emailIdp;

  late final EndpointJwtRefresh jwtRefresh;

  late final EndpointApps apps;

  late final EndpointBuilder builder;

  late final EndpointMedia media;

  late final EndpointRuntime runtime;

  late final EndpointGreeting greeting;

  late final Modules modules;

  @override
  Map<String, _isc.EndpointRef> get endpointRefLookup => {
    'emailIdp': emailIdp,
    'jwtRefresh': jwtRefresh,
    'apps': apps,
    'builder': builder,
    'media': media,
    'runtime': runtime,
    'greeting': greeting,
  };

  @override
  Map<String, _isc.ModuleEndpointCaller> get moduleLookup => {
    'serverpod_auth_idp': modules.serverpod_auth_idp,
    'serverpod_auth_core': modules.serverpod_auth_core,
  };
}
