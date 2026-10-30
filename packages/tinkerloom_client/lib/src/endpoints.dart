part of '../tinkerloom_client.dart';

class _Endpoint {
  _Endpoint(this.caller);
  final Client caller;
}

class EndpointApps extends _Endpoint {
  EndpointApps(Client caller) : super(caller);

  String get name => 'apps';

  Future<List<WorkspaceInfo>> workspaces() =>
      caller.callServerEndpoint<List<WorkspaceInfo>>('apps', 'workspaces', {});

  Future<String> createWorkspace(String name) => caller
      .callServerEndpoint<String>('apps', 'createWorkspace', {'name': name});

  Future<List<AppManifest>> list(String workspaceId) =>
      caller.callServerEndpoint<List<AppManifest>>('apps', 'list', {
        'workspaceId': workspaceId,
      });

  Future<AppManifest> manifest(String appId) => caller
      .callServerEndpoint<AppManifest>('apps', 'manifest', {'appId': appId});

  Future<List<TemplateInfo>> templates() =>
      caller.callServerEndpoint<List<TemplateInfo>>('apps', 'templates', {});

  Future<String> instantiate(String workspaceId, String templateKey) =>
      caller.callServerEndpoint<String>('apps', 'instantiate', {
        'workspaceId': workspaceId,
        'templateKey': templateKey,
      });

  Future<String> remix(String appId, String workspaceId) =>
      caller.callServerEndpoint<String>('apps', 'remix', {
        'appId': appId,
        'workspaceId': workspaceId,
      });

  Future<void> pin(String appId, bool pinned) =>
      caller.callServerEndpoint<void>('apps', 'pin', {
        'appId': appId,
        'pinned': pinned,
      });

  Future<void> archive(String appId) =>
      caller.callServerEndpoint<void>('apps', 'archive', {'appId': appId});

  Future<String> invite(String appId, String role, String? recipientId) =>
      caller.callServerEndpoint<String>('apps', 'invite', {
        'appId': appId,
        'role': role,
        'recipientId': recipientId,
      });

  Future<String> acceptInvitation(String token) => caller
      .callServerEndpoint<String>('apps', 'acceptInvitation', {'token': token});

  Future<void> revokeInvitation(String appId, String token) =>
      caller.callServerEndpoint<void>('apps', 'revokeInvitation', {
        'appId': appId,
        'token': token,
      });

  Future<List<MemberInfo>> members(String appId) =>
      caller.callServerEndpoint<List<MemberInfo>>('apps', 'members', {
        'appId': appId,
      });

  Future<void> setGrant(String appId, String target, String? role) =>
      caller.callServerEndpoint<void>('apps', 'setGrant', {
        'appId': appId,
        'target': target,
        'role': role,
      });

  Future<List<ActivityItem>> activity(String appId) =>
      caller.callServerEndpoint<List<ActivityItem>>('apps', 'activity', {
        'appId': appId,
      });
}

/// {@category Endpoint}
class EndpointBuilder extends _Endpoint {
  EndpointBuilder(Client caller) : super(caller);

  String get name => 'builder';

  Future<PlatformInfo> platform() =>
      caller.callServerEndpoint<PlatformInfo>('builder', 'platform', {});

  Future<BuilderSnapshot> begin(
    String workspaceId,
    String templateKey,
    String? appId,
  ) => caller.callServerEndpoint<BuilderSnapshot>('builder', 'begin', {
    'workspaceId': workspaceId,
    'templateKey': templateKey,
    'appId': appId,
  });

  Future<BuilderSnapshot> get(String draftId) =>
      caller.callServerEndpoint<BuilderSnapshot>('builder', 'get', {
        'draftId': draftId,
      });

  /// Fetch the current authorized snapshot without scheduling worker wakeups.
  Future<BuilderSnapshot> getForRecovery(String draftId) =>
      caller.callServerEndpoint<BuilderSnapshot>('builder', 'getForRecovery', {
        'draftId': draftId,
      });

  Future<List<GuidanceQuestion>> suggestQuestions(
    String idea,
    String? workspaceId,
    String? draftId,
  ) => caller.callServerEndpoint<List<GuidanceQuestion>>(
    'builder',
    'suggestQuestions',
    {'idea': idea, 'workspaceId': workspaceId, 'draftId': draftId},
  );

  Future<BuilderSnapshot> patch(
    String draftId,
    int mutation,
    String patchJson,
  ) => caller.callServerEndpoint<BuilderSnapshot>('builder', 'patch', {
    'draftId': draftId,
    'mutation': mutation,
    'patchJson': patchJson,
  });

  Future<BuilderSnapshot> generate(
    String draftId,
    int mutation,
    String request, {
    bool? startFromScratch,
  }) => caller.callServerEndpoint<BuilderSnapshot>('builder', 'generate', {
    'draftId': draftId,
    'mutation': mutation,
    'request': request,
    'startFromScratch': startFromScratch,
  });

  Future<String> publish(PublishRequest request) => caller
      .callServerEndpoint<String>('builder', 'publish', {'request': request});

  Future<BuilderSnapshot> abandonFailedEdit(
    String draftId,
    int mutation,
    String jobId,
  ) => caller.callServerEndpoint<BuilderSnapshot>(
    'builder',
    'abandonFailedEdit',
    {'draftId': draftId, 'mutation': mutation, 'jobId': jobId},
  );

  Future<List<ActivityItem>> runs(String appId) =>
      caller.callServerEndpoint<List<ActivityItem>>('builder', 'runs', {
        'appId': appId,
      });
}

/// {@category Endpoint}
class EndpointMedia extends _Endpoint {
  Future<MediaInfo> checkUpload(String appId, String assetId) =>
      caller.checkMediaUpload(appId, assetId);
  Future<void> uploadBytes(MediaUploadTicket ticket, Uint8List bytes) =>
      caller.uploadMediaBytes(ticket, bytes);
  EndpointMedia(Client caller) : super(caller);

  String get name => 'media';

  Future<MediaUploadTicket> beginUpload(MediaUploadRequest request) =>
      caller.callServerEndpoint<MediaUploadTicket>('media', 'beginUpload', {
        'request': request,
      });

  Future<MediaInfo> completeUpload(String appId, String assetId) =>
      caller.callServerEndpoint<MediaInfo>('media', 'completeUpload', {
        'appId': appId,
        'assetId': assetId,
      });

  Future<ByteData> readImage(String appId, String assetId, String variant) =>
      caller.callServerEndpoint<ByteData>('media', 'readImage', {
        'appId': appId,
        'assetId': assetId,
        'variant': variant,
      });
}

/// {@category Endpoint}
class EndpointRuntime extends _Endpoint {
  EndpointRuntime(Client caller) : super(caller);

  String get name => 'runtime';

  Future<RecordPage> query(
    String appId,
    String collectionId,
    String queryJson,
  ) => caller.callServerEndpoint<RecordPage>('runtime', 'query', {
    'appId': appId,
    'collectionId': collectionId,
    'queryJson': queryJson,
  });

  Future<RecordSummary> summary(
    String appId,
    String collectionId,
    String queryJson,
    String groupFieldId,
  ) => caller.callServerEndpoint<RecordSummary>('runtime', 'summary', {
    'appId': appId,
    'collectionId': collectionId,
    'queryJson': queryJson,
    'groupFieldId': groupFieldId,
  });

  Future<String> aggregate(
    String appId,
    String collectionId,
    String queryJson,
    String aggregateJson,
  ) => caller.callServerEndpoint<String>('runtime', 'aggregate', {
    'appId': appId,
    'collectionId': collectionId,
    'queryJson': queryJson,
    'aggregateJson': aggregateJson,
  });

  Future<List<ReminderState>> reminderState(String appId, String recordId) =>
      caller.callServerEndpoint<List<ReminderState>>(
        'runtime',
        'reminderState',
        {'appId': appId, 'recordId': recordId},
      );

  Future<RuntimeRecord> get(String appId, String recordId) =>
      caller.callServerEndpoint<RuntimeRecord>('runtime', 'get', {
        'appId': appId,
        'recordId': recordId,
      });

  Future<ActionOutcome> execute(ActionRequest request) =>
      caller.callServerEndpoint<ActionOutcome>('runtime', 'execute', {
        'request': request,
      });

  Future<List<InboxItem>> inbox() =>
      caller.callServerEndpoint<List<InboxItem>>('runtime', 'inbox', {});

  Future<void> readNotification(String id) => caller.callServerEndpoint<void>(
    'runtime',
    'readNotification',
    {'id': id},
  );

  Stream<AppEvent> events(String appId) =>
      caller.callStreamingServerEndpoint<Stream<AppEvent>, AppEvent>(
        'runtime',
        'events',
        {'appId': appId},
        {},
      );
}
