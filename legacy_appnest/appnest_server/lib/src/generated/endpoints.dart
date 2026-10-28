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
import 'package:appnest_server/src/generated/action_request.dart' as _ilhdpzxy;
import 'package:appnest_server/src/generated/future_calls.dart' as _itt87tub;
import 'package:appnest_server/src/generated/media_upload_request.dart'
    as _ihi072ai;
import 'package:appnest_server/src/generated/publish_request.dart' as _ivuulprf;
import 'package:serverpod/serverpod.dart' as _is;
import 'package:serverpod_auth_core_server/serverpod_auth_core_server.dart'
    as _iacs;
import 'package:serverpod_auth_idp_server/serverpod_auth_idp_server.dart'
    as _iais;
import '../auth/email_idp_endpoint.dart' as _iuc1hd5t;
import '../auth/jwt_refresh_endpoint.dart' as _inwq3ztq;
import '../endpoints/apps_endpoint.dart' as _iuo089a1;
import '../endpoints/builder_endpoint.dart' as _ittyaucl;
import '../endpoints/media_endpoint.dart' as _iaymoujt;
import '../endpoints/runtime_endpoint.dart' as _i7rxtwkb;
import '../greetings/greeting_endpoint.dart' as _il624ik7;
export 'future_calls.dart' show ServerpodFutureCallsGetter;

class Endpoints extends _is.EndpointDispatch {
  @override
  void initializeEndpoints(_is.Server server) {
    var endpoints = <String, _is.Endpoint>{
      'emailIdp': _iuc1hd5t.EmailIdpEndpoint()
        ..initialize(
          server,
          'emailIdp',
          null,
        ),
      'jwtRefresh': _inwq3ztq.JwtRefreshEndpoint()
        ..initialize(
          server,
          'jwtRefresh',
          null,
        ),
      'apps': _iuo089a1.AppsEndpoint()
        ..initialize(
          server,
          'apps',
          null,
        ),
      'builder': _ittyaucl.BuilderEndpoint()
        ..initialize(
          server,
          'builder',
          null,
        ),
      'media': _iaymoujt.MediaEndpoint()
        ..initialize(
          server,
          'media',
          null,
        ),
      'runtime': _i7rxtwkb.RuntimeEndpoint()
        ..initialize(
          server,
          'runtime',
          null,
        ),
      'greeting': _il624ik7.GreetingEndpoint()
        ..initialize(
          server,
          'greeting',
          null,
        ),
    };
    connectors['emailIdp'] = _is.EndpointConnector(
      name: 'emailIdp',
      endpoint: endpoints['emailIdp']!,
      methodConnectors: {
        'login': _is.MethodConnector(
          name: 'login',
          params: {
            'email': _is.ParameterDescription(
              name: 'email',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'password': _is.ParameterDescription(
              name: 'password',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['emailIdp'] as _iuc1hd5t.EmailIdpEndpoint).login(
                    session,
                    email: params['email'],
                    password: params['password'],
                  ),
        ),
        'startRegistration': _is.MethodConnector(
          name: 'startRegistration',
          params: {
            'email': _is.ParameterDescription(
              name: 'email',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['emailIdp'] as _iuc1hd5t.EmailIdpEndpoint)
                  .startRegistration(
                    session,
                    email: params['email'],
                  ),
        ),
        'verifyRegistrationCode': _is.MethodConnector(
          name: 'verifyRegistrationCode',
          params: {
            'accountRequestId': _is.ParameterDescription(
              name: 'accountRequestId',
              type: _is.getType<_is.UuidValue>(),
              nullable: false,
            ),
            'verificationCode': _is.ParameterDescription(
              name: 'verificationCode',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['emailIdp'] as _iuc1hd5t.EmailIdpEndpoint)
                  .verifyRegistrationCode(
                    session,
                    accountRequestId: params['accountRequestId'],
                    verificationCode: params['verificationCode'],
                  ),
        ),
        'finishRegistration': _is.MethodConnector(
          name: 'finishRegistration',
          params: {
            'registrationToken': _is.ParameterDescription(
              name: 'registrationToken',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'password': _is.ParameterDescription(
              name: 'password',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['emailIdp'] as _iuc1hd5t.EmailIdpEndpoint)
                  .finishRegistration(
                    session,
                    registrationToken: params['registrationToken'],
                    password: params['password'],
                  ),
        ),
        'startPasswordReset': _is.MethodConnector(
          name: 'startPasswordReset',
          params: {
            'email': _is.ParameterDescription(
              name: 'email',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['emailIdp'] as _iuc1hd5t.EmailIdpEndpoint)
                  .startPasswordReset(
                    session,
                    email: params['email'],
                  ),
        ),
        'verifyPasswordResetCode': _is.MethodConnector(
          name: 'verifyPasswordResetCode',
          params: {
            'passwordResetRequestId': _is.ParameterDescription(
              name: 'passwordResetRequestId',
              type: _is.getType<_is.UuidValue>(),
              nullable: false,
            ),
            'verificationCode': _is.ParameterDescription(
              name: 'verificationCode',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['emailIdp'] as _iuc1hd5t.EmailIdpEndpoint)
                  .verifyPasswordResetCode(
                    session,
                    passwordResetRequestId: params['passwordResetRequestId'],
                    verificationCode: params['verificationCode'],
                  ),
        ),
        'finishPasswordReset': _is.MethodConnector(
          name: 'finishPasswordReset',
          params: {
            'finishPasswordResetToken': _is.ParameterDescription(
              name: 'finishPasswordResetToken',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'newPassword': _is.ParameterDescription(
              name: 'newPassword',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['emailIdp'] as _iuc1hd5t.EmailIdpEndpoint)
                  .finishPasswordReset(
                    session,
                    finishPasswordResetToken:
                        params['finishPasswordResetToken'],
                    newPassword: params['newPassword'],
                  ),
        ),
        'hasAccount': _is.MethodConnector(
          name: 'hasAccount',
          params: {},
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['emailIdp'] as _iuc1hd5t.EmailIdpEndpoint)
                  .hasAccount(session),
        ),
      },
    );
    connectors['jwtRefresh'] = _is.EndpointConnector(
      name: 'jwtRefresh',
      endpoint: endpoints['jwtRefresh']!,
      methodConnectors: {
        'refreshAccessToken': _is.MethodConnector(
          name: 'refreshAccessToken',
          params: {
            'refreshToken': _is.ParameterDescription(
              name: 'refreshToken',
              type: _is.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['jwtRefresh'] as _inwq3ztq.JwtRefreshEndpoint)
                      .refreshAccessToken(
                        session,
                        refreshToken: params['refreshToken'],
                      ),
        ),
      },
    );
    connectors['apps'] = _is.EndpointConnector(
      name: 'apps',
      endpoint: endpoints['apps']!,
      methodConnectors: {
        'workspaces': _is.MethodConnector(
          name: 'workspaces',
          params: {},
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint)
                  .workspaces(session),
        ),
        'createWorkspace': _is.MethodConnector(
          name: 'createWorkspace',
          params: {
            'name': _is.ParameterDescription(
              name: 'name',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['apps'] as _iuo089a1.AppsEndpoint).createWorkspace(
                    session,
                    params['name'],
                  ),
        ),
        'list': _is.MethodConnector(
          name: 'list',
          params: {
            'workspaceId': _is.ParameterDescription(
              name: 'workspaceId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint).list(
                session,
                params['workspaceId'],
              ),
        ),
        'manifest': _is.MethodConnector(
          name: 'manifest',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint).manifest(
                session,
                params['appId'],
              ),
        ),
        'templates': _is.MethodConnector(
          name: 'templates',
          params: {},
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint)
                  .templates(session),
        ),
        'instantiate': _is.MethodConnector(
          name: 'instantiate',
          params: {
            'workspaceId': _is.ParameterDescription(
              name: 'workspaceId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'templateKey': _is.ParameterDescription(
              name: 'templateKey',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['apps'] as _iuo089a1.AppsEndpoint).instantiate(
                    session,
                    params['workspaceId'],
                    params['templateKey'],
                  ),
        ),
        'remix': _is.MethodConnector(
          name: 'remix',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'workspaceId': _is.ParameterDescription(
              name: 'workspaceId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint).remix(
                session,
                params['appId'],
                params['workspaceId'],
              ),
        ),
        'pin': _is.MethodConnector(
          name: 'pin',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'pinned': _is.ParameterDescription(
              name: 'pinned',
              type: _is.getType<bool>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint).pin(
                session,
                params['appId'],
                params['pinned'],
              ),
        ),
        'archive': _is.MethodConnector(
          name: 'archive',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint).archive(
                session,
                params['appId'],
              ),
        ),
        'invite': _is.MethodConnector(
          name: 'invite',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'role': _is.ParameterDescription(
              name: 'role',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'recipientId': _is.ParameterDescription(
              name: 'recipientId',
              type: _is.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint).invite(
                session,
                params['appId'],
                params['role'],
                params['recipientId'],
              ),
        ),
        'acceptInvitation': _is.MethodConnector(
          name: 'acceptInvitation',
          params: {
            'token': _is.ParameterDescription(
              name: 'token',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint)
                  .acceptInvitation(
                    session,
                    params['token'],
                  ),
        ),
        'revokeInvitation': _is.MethodConnector(
          name: 'revokeInvitation',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'token': _is.ParameterDescription(
              name: 'token',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint)
                  .revokeInvitation(
                    session,
                    params['appId'],
                    params['token'],
                  ),
        ),
        'members': _is.MethodConnector(
          name: 'members',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint).members(
                session,
                params['appId'],
              ),
        ),
        'setGrant': _is.MethodConnector(
          name: 'setGrant',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'target': _is.ParameterDescription(
              name: 'target',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'role': _is.ParameterDescription(
              name: 'role',
              type: _is.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint).setGrant(
                session,
                params['appId'],
                params['target'],
                params['role'],
              ),
        ),
        'activity': _is.MethodConnector(
          name: 'activity',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['apps'] as _iuo089a1.AppsEndpoint).activity(
                session,
                params['appId'],
              ),
        ),
      },
    );
    connectors['builder'] = _is.EndpointConnector(
      name: 'builder',
      endpoint: endpoints['builder']!,
      methodConnectors: {
        'platform': _is.MethodConnector(
          name: 'platform',
          params: {},
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['builder'] as _ittyaucl.BuilderEndpoint)
                  .platform(session),
        ),
        'begin': _is.MethodConnector(
          name: 'begin',
          params: {
            'workspaceId': _is.ParameterDescription(
              name: 'workspaceId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'templateKey': _is.ParameterDescription(
              name: 'templateKey',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int?>(),
              nullable: true,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['builder'] as _ittyaucl.BuilderEndpoint).begin(
                    session,
                    params['workspaceId'],
                    params['templateKey'],
                    params['appId'],
                  ),
        ),
        'get': _is.MethodConnector(
          name: 'get',
          params: {
            'draftId': _is.ParameterDescription(
              name: 'draftId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['builder'] as _ittyaucl.BuilderEndpoint).get(
                    session,
                    params['draftId'],
                  ),
        ),
        'suggestQuestions': _is.MethodConnector(
          name: 'suggestQuestions',
          params: {
            'idea': _is.ParameterDescription(
              name: 'idea',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'workspaceId': _is.ParameterDescription(
              name: 'workspaceId',
              type: _is.getType<int?>(),
              nullable: true,
            ),
            'draftId': _is.ParameterDescription(
              name: 'draftId',
              type: _is.getType<int?>(),
              nullable: true,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['builder'] as _ittyaucl.BuilderEndpoint)
                  .suggestQuestions(
                    session,
                    params['idea'],
                    params['workspaceId'],
                    params['draftId'],
                  ),
        ),
        'patch': _is.MethodConnector(
          name: 'patch',
          params: {
            'draftId': _is.ParameterDescription(
              name: 'draftId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'mutation': _is.ParameterDescription(
              name: 'mutation',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'patchJson': _is.ParameterDescription(
              name: 'patchJson',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['builder'] as _ittyaucl.BuilderEndpoint).patch(
                    session,
                    params['draftId'],
                    params['mutation'],
                    params['patchJson'],
                  ),
        ),
        'generate': _is.MethodConnector(
          name: 'generate',
          params: {
            'draftId': _is.ParameterDescription(
              name: 'draftId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'mutation': _is.ParameterDescription(
              name: 'mutation',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'request': _is.ParameterDescription(
              name: 'request',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'startFromScratch': _is.ParameterDescription(
              name: 'startFromScratch',
              type: _is.getType<bool?>(),
              nullable: true,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['builder'] as _ittyaucl.BuilderEndpoint).generate(
                    session,
                    params['draftId'],
                    params['mutation'],
                    params['request'],
                    startFromScratch: params['startFromScratch'],
                  ),
        ),
        'publish': _is.MethodConnector(
          name: 'publish',
          params: {
            'request': _is.ParameterDescription(
              name: 'request',
              type: _is.getType<_ivuulprf.PublishRequest>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['builder'] as _ittyaucl.BuilderEndpoint).publish(
                    session,
                    params['request'],
                  ),
        ),
        'abandonFailedEdit': _is.MethodConnector(
          name: 'abandonFailedEdit',
          params: {
            'draftId': _is.ParameterDescription(
              name: 'draftId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'mutation': _is.ParameterDescription(
              name: 'mutation',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'jobId': _is.ParameterDescription(
              name: 'jobId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['builder'] as _ittyaucl.BuilderEndpoint)
                  .abandonFailedEdit(
                    session,
                    params['draftId'],
                    params['mutation'],
                    params['jobId'],
                  ),
        ),
        'runs': _is.MethodConnector(
          name: 'runs',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['builder'] as _ittyaucl.BuilderEndpoint).runs(
                    session,
                    params['appId'],
                  ),
        ),
      },
    );
    connectors['media'] = _is.EndpointConnector(
      name: 'media',
      endpoint: endpoints['media']!,
      methodConnectors: {
        'beginUpload': _is.MethodConnector(
          name: 'beginUpload',
          params: {
            'request': _is.ParameterDescription(
              name: 'request',
              type: _is.getType<_ihi072ai.MediaUploadRequest>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['media'] as _iaymoujt.MediaEndpoint).beginUpload(
                    session,
                    params['request'],
                  ),
        ),
        'completeUpload': _is.MethodConnector(
          name: 'completeUpload',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'assetId': _is.ParameterDescription(
              name: 'assetId',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['media'] as _iaymoujt.MediaEndpoint)
                  .completeUpload(
                    session,
                    params['appId'],
                    params['assetId'],
                  ),
        ),
        'readImage': _is.MethodConnector(
          name: 'readImage',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'assetId': _is.ParameterDescription(
              name: 'assetId',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'variant': _is.ParameterDescription(
              name: 'variant',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['media'] as _iaymoujt.MediaEndpoint).readImage(
                    session,
                    params['appId'],
                    params['assetId'],
                    params['variant'],
                  ),
        ),
      },
    );
    connectors['runtime'] = _is.EndpointConnector(
      name: 'runtime',
      endpoint: endpoints['runtime']!,
      methodConnectors: {
        'query': _is.MethodConnector(
          name: 'query',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'collectionId': _is.ParameterDescription(
              name: 'collectionId',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'queryJson': _is.ParameterDescription(
              name: 'queryJson',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['runtime'] as _i7rxtwkb.RuntimeEndpoint).query(
                    session,
                    params['appId'],
                    params['collectionId'],
                    params['queryJson'],
                  ),
        ),
        'summary': _is.MethodConnector(
          name: 'summary',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'collectionId': _is.ParameterDescription(
              name: 'collectionId',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'queryJson': _is.ParameterDescription(
              name: 'queryJson',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'groupFieldId': _is.ParameterDescription(
              name: 'groupFieldId',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['runtime'] as _i7rxtwkb.RuntimeEndpoint).summary(
                    session,
                    params['appId'],
                    params['collectionId'],
                    params['queryJson'],
                    params['groupFieldId'],
                  ),
        ),
        'aggregate': _is.MethodConnector(
          name: 'aggregate',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'collectionId': _is.ParameterDescription(
              name: 'collectionId',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'queryJson': _is.ParameterDescription(
              name: 'queryJson',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'aggregateJson': _is.ParameterDescription(
              name: 'aggregateJson',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['runtime'] as _i7rxtwkb.RuntimeEndpoint).aggregate(
                    session,
                    params['appId'],
                    params['collectionId'],
                    params['queryJson'],
                    params['aggregateJson'],
                  ),
        ),
        'reminderState': _is.MethodConnector(
          name: 'reminderState',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'recordId': _is.ParameterDescription(
              name: 'recordId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['runtime'] as _i7rxtwkb.RuntimeEndpoint)
                  .reminderState(
                    session,
                    params['appId'],
                    params['recordId'],
                  ),
        ),
        'get': _is.MethodConnector(
          name: 'get',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
            'recordId': _is.ParameterDescription(
              name: 'recordId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['runtime'] as _i7rxtwkb.RuntimeEndpoint).get(
                    session,
                    params['appId'],
                    params['recordId'],
                  ),
        ),
        'execute': _is.MethodConnector(
          name: 'execute',
          params: {
            'request': _is.ParameterDescription(
              name: 'request',
              type: _is.getType<_ilhdpzxy.ActionRequest>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['runtime'] as _i7rxtwkb.RuntimeEndpoint).execute(
                    session,
                    params['request'],
                  ),
        ),
        'inbox': _is.MethodConnector(
          name: 'inbox',
          params: {},
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['runtime'] as _i7rxtwkb.RuntimeEndpoint)
                  .inbox(session),
        ),
        'readNotification': _is.MethodConnector(
          name: 'readNotification',
          params: {
            'id': _is.ParameterDescription(
              name: 'id',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['runtime'] as _i7rxtwkb.RuntimeEndpoint)
                  .readNotification(
                    session,
                    params['id'],
                  ),
        ),
        'events': _is.MethodStreamConnector(
          name: 'events',
          params: {
            'appId': _is.ParameterDescription(
              name: 'appId',
              type: _is.getType<int>(),
              nullable: false,
            ),
          },
          streamParams: {},
          returnType: _is.MethodStreamReturnType.streamType,
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
                Map<String, Stream> streamParams,
              ) => (endpoints['runtime'] as _i7rxtwkb.RuntimeEndpoint).events(
                session,
                params['appId'],
              ),
        ),
      },
    );
    connectors['greeting'] = _is.EndpointConnector(
      name: 'greeting',
      endpoint: endpoints['greeting']!,
      methodConnectors: {
        'hello': _is.MethodConnector(
          name: 'hello',
          params: {
            'name': _is.ParameterDescription(
              name: 'name',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['greeting'] as _il624ik7.GreetingEndpoint).hello(
                    session,
                    params['name'],
                  ),
        ),
      },
    );
    modules['serverpod_auth_idp'] = _iais.Endpoints()
      ..initializeEndpoints(server);
    modules['serverpod_auth_core'] = _iacs.Endpoints()
      ..initializeEndpoints(server);
  }

  @override
  _is.FutureCallDispatch? get futureCalls {
    return _itt87tub.FutureCalls();
  }
}
