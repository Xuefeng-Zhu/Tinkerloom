// Transport-independent models for the original Flutter presentation layer.
const _unchanged = Object();

class ActionOutcome {
  ActionOutcome({
    required this.recordId,
    required this.revision,
    required this.message,
  });
  String recordId;
  int revision;
  String message;
  ActionOutcome copyWith({String? recordId, int? revision, String? message}) =>
      ActionOutcome(
        recordId: recordId ?? this.recordId,
        revision: revision ?? this.revision,
        message: message ?? this.message,
      );
  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'revision': revision,
    'message': message,
  };
}

class ActionRequest {
  ActionRequest({
    required this.appId,
    required this.actionId,
    this.targetRecordId,
    required this.expectedDefinitionVersionId,
    this.expectedRecordRevision,
    required this.input,
    required this.idempotencyKey,
  });
  String appId;
  String actionId;
  String? targetRecordId;
  String expectedDefinitionVersionId;
  int? expectedRecordRevision;
  dynamic input;
  String idempotencyKey;
  ActionRequest copyWith({
    String? appId,
    String? actionId,
    Object? targetRecordId = _unchanged,
    String? expectedDefinitionVersionId,
    Object? expectedRecordRevision = _unchanged,
    dynamic input,
    String? idempotencyKey,
  }) => ActionRequest(
    appId: appId ?? this.appId,
    actionId: actionId ?? this.actionId,
    targetRecordId: identical(targetRecordId, _unchanged)
        ? this.targetRecordId
        : targetRecordId as String?,
    expectedDefinitionVersionId:
        expectedDefinitionVersionId ?? this.expectedDefinitionVersionId,
    expectedRecordRevision: identical(expectedRecordRevision, _unchanged)
        ? this.expectedRecordRevision
        : expectedRecordRevision as int?,
    input: input ?? this.input,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
  );
  Map<String, dynamic> toJson() => {
    'appId': appId,
    'actionId': actionId,
    'targetRecordId': targetRecordId,
    'expectedDefinitionVersionId': expectedDefinitionVersionId,
    'expectedRecordRevision': expectedRecordRevision,
    'input': input,
    'idempotencyKey': idempotencyKey,
  };
}

class ActivityItem {
  ActivityItem({
    required this.id,
    required this.action,
    required this.createdAt,
    required this.status,
  });
  String id;
  String action;
  DateTime createdAt;
  String status;
  ActivityItem copyWith({
    String? id,
    String? action,
    DateTime? createdAt,
    String? status,
  }) => ActivityItem(
    id: id ?? this.id,
    action: action ?? this.action,
    createdAt: createdAt ?? this.createdAt,
    status: status ?? this.status,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'action': action,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status,
  };
}

class AppEvent {
  AppEvent({required this.appId, required this.revision, required this.kind});
  String appId;
  int revision;
  String kind;
  AppEvent copyWith({String? appId, int? revision, String? kind}) => AppEvent(
    appId: appId ?? this.appId,
    revision: revision ?? this.revision,
    kind: kind ?? this.kind,
  );
  Map<String, dynamic> toJson() => {
    'appId': appId,
    'revision': revision,
    'kind': kind,
  };
}

class AppManifest {
  AppManifest({
    required this.appId,
    required this.workspaceId,
    required this.name,
    this.versionId,
    this.specJson,
    required this.role,
    required this.archived,
    required this.pinned,
    required this.recordCount,
    required this.availablePlaces,
    this.approvedRuleIds,
    this.approvalsKnown = false,
  });
  String appId;
  String workspaceId;
  String name;
  String? versionId;
  String? specJson;
  String role;
  bool archived;
  bool pinned;
  int recordCount;
  int availablePlaces;
  List<String>? approvedRuleIds;
  bool approvalsKnown;
  AppManifest copyWith({
    bool? approvalsKnown,
    String? appId,
    String? workspaceId,
    String? name,
    Object? versionId = _unchanged,
    Object? specJson = _unchanged,
    String? role,
    bool? archived,
    bool? pinned,
    int? recordCount,
    int? availablePlaces,
    Object? approvedRuleIds = _unchanged,
  }) => AppManifest(
    approvalsKnown: approvalsKnown ?? this.approvalsKnown,
    appId: appId ?? this.appId,
    workspaceId: workspaceId ?? this.workspaceId,
    name: name ?? this.name,
    versionId: identical(versionId, _unchanged)
        ? this.versionId
        : versionId as String?,
    specJson: identical(specJson, _unchanged)
        ? this.specJson
        : specJson as String?,
    role: role ?? this.role,
    archived: archived ?? this.archived,
    pinned: pinned ?? this.pinned,
    recordCount: recordCount ?? this.recordCount,
    availablePlaces: availablePlaces ?? this.availablePlaces,
    approvedRuleIds: identical(approvedRuleIds, _unchanged)
        ? this.approvedRuleIds
        : approvedRuleIds as List<String>?,
  );
  Map<String, dynamic> toJson() => {
    'approvalsKnown': approvalsKnown,
    'appId': appId,
    'workspaceId': workspaceId,
    'name': name,
    'versionId': versionId,
    'specJson': specJson,
    'role': role,
    'archived': archived,
    'pinned': pinned,
    'recordCount': recordCount,
    'availablePlaces': availablePlaces,
    'approvedRuleIds': approvedRuleIds,
  };
}

class BuilderSnapshot {
  BuilderSnapshot({
    required this.appId,
    required this.draftId,
    this.jobId,
    this.baseVersionId,
    required this.mutation,
    required this.stage,
    required this.candidateJson,
    required this.candidateHash,
    required this.diagnostics,
    required this.changes,
    required this.enabledRuleIds,
    this.publishedVersionId,
    this.candidateReady = false,
    this.latestRequest,
    this.jobAttempts = 0,
    this.jobCreatedAt,
    this.jobUpdatedAt,
    this.failureCategory,
    this.approvalsKnown = false,
  });
  String appId;
  String draftId;
  String? jobId;
  String? baseVersionId;
  int mutation;
  String stage;
  String candidateJson;
  String candidateHash;
  List<String> diagnostics;
  List<String> changes;
  List<String> enabledRuleIds;
  String? publishedVersionId;
  bool candidateReady;
  String? latestRequest;
  int jobAttempts;
  DateTime? jobCreatedAt;
  DateTime? jobUpdatedAt;
  String? failureCategory;
  bool approvalsKnown;
  BuilderSnapshot copyWith({
    bool? approvalsKnown,
    String? appId,
    String? draftId,
    Object? jobId = _unchanged,
    Object? baseVersionId = _unchanged,
    int? mutation,
    String? stage,
    String? candidateJson,
    String? candidateHash,
    List<String>? diagnostics,
    List<String>? changes,
    List<String>? enabledRuleIds,
    Object? publishedVersionId = _unchanged,
    bool? candidateReady,
    Object? latestRequest = _unchanged,
    int? jobAttempts,
    Object? jobCreatedAt = _unchanged,
    Object? jobUpdatedAt = _unchanged,
    Object? failureCategory = _unchanged,
  }) => BuilderSnapshot(
    approvalsKnown: approvalsKnown ?? this.approvalsKnown,
    appId: appId ?? this.appId,
    draftId: draftId ?? this.draftId,
    jobId: identical(jobId, _unchanged) ? this.jobId : jobId as String?,
    baseVersionId: identical(baseVersionId, _unchanged)
        ? this.baseVersionId
        : baseVersionId as String?,
    mutation: mutation ?? this.mutation,
    stage: stage ?? this.stage,
    candidateJson: candidateJson ?? this.candidateJson,
    candidateHash: candidateHash ?? this.candidateHash,
    diagnostics: diagnostics ?? this.diagnostics,
    changes: changes ?? this.changes,
    enabledRuleIds: enabledRuleIds ?? this.enabledRuleIds,
    publishedVersionId: identical(publishedVersionId, _unchanged)
        ? this.publishedVersionId
        : publishedVersionId as String?,
    candidateReady: candidateReady ?? this.candidateReady,
    latestRequest: identical(latestRequest, _unchanged)
        ? this.latestRequest
        : latestRequest as String?,
    jobAttempts: jobAttempts ?? this.jobAttempts,
    jobCreatedAt: identical(jobCreatedAt, _unchanged)
        ? this.jobCreatedAt
        : jobCreatedAt as DateTime?,
    jobUpdatedAt: identical(jobUpdatedAt, _unchanged)
        ? this.jobUpdatedAt
        : jobUpdatedAt as DateTime?,
    failureCategory: identical(failureCategory, _unchanged)
        ? this.failureCategory
        : failureCategory as String?,
  );
  Map<String, dynamic> toJson() => {
    'approvalsKnown': approvalsKnown,
    'appId': appId,
    'draftId': draftId,
    'jobId': jobId,
    'baseVersionId': baseVersionId,
    'mutation': mutation,
    'stage': stage,
    'candidateJson': candidateJson,
    'candidateHash': candidateHash,
    'diagnostics': diagnostics,
    'changes': changes,
    'enabledRuleIds': enabledRuleIds,
    'publishedVersionId': publishedVersionId,
    'candidateReady': candidateReady,
    'latestRequest': latestRequest,
    'jobAttempts': jobAttempts,
    'jobCreatedAt': jobCreatedAt?.toUtc().toIso8601String(),
    'jobUpdatedAt': jobUpdatedAt?.toUtc().toIso8601String(),
    'failureCategory': failureCategory,
  };
}

class GuidanceQuestion {
  GuidanceQuestion({required this.question, required this.options});
  String question;
  List<String> options;
  GuidanceQuestion copyWith({String? question, List<String>? options}) =>
      GuidanceQuestion(
        question: question ?? this.question,
        options: options ?? this.options,
      );
  Map<String, dynamic> toJson() => {'question': question, 'options': options};
}

class InboxItem {
  InboxItem({
    required this.id,
    required this.appId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.recordId,
    this.collectionId,
  });
  String id;
  String appId;
  String title;
  String body;
  DateTime createdAt;
  bool isRead;
  String? recordId;
  String? collectionId;
  InboxItem copyWith({
    String? id,
    String? appId,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? isRead,
    Object? recordId = _unchanged,
    Object? collectionId = _unchanged,
  }) => InboxItem(
    id: id ?? this.id,
    appId: appId ?? this.appId,
    title: title ?? this.title,
    body: body ?? this.body,
    createdAt: createdAt ?? this.createdAt,
    isRead: isRead ?? this.isRead,
    recordId: identical(recordId, _unchanged)
        ? this.recordId
        : recordId as String?,
    collectionId: identical(collectionId, _unchanged)
        ? this.collectionId
        : collectionId as String?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'appId': appId,
    'title': title,
    'body': body,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'isRead': isRead,
    'recordId': recordId,
    'collectionId': collectionId,
  };
}

class MediaInfo {
  MediaInfo({
    required this.assetId,
    required this.contentType,
    required this.width,
    required this.height,
    required this.byteLength,
  });
  String assetId;
  String contentType;
  int width;
  int height;
  int byteLength;
  MediaInfo copyWith({
    String? assetId,
    String? contentType,
    int? width,
    int? height,
    int? byteLength,
  }) => MediaInfo(
    assetId: assetId ?? this.assetId,
    contentType: contentType ?? this.contentType,
    width: width ?? this.width,
    height: height ?? this.height,
    byteLength: byteLength ?? this.byteLength,
  );
  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'contentType': contentType,
    'width': width,
    'height': height,
    'byteLength': byteLength,
  };
}

class MediaUploadRequest {
  MediaUploadRequest({
    required this.appId,
    this.draftId,
    this.actionId,
    this.targetRecordId,
    this.fieldId,
    this.expectedDefinitionVersionId,
    required this.byteLength,
    required this.contentType,
    required this.idempotencyKey,
  });
  String appId;
  String? draftId;
  String? actionId;
  String? targetRecordId;
  String? fieldId;
  String? expectedDefinitionVersionId;
  int byteLength;
  String contentType;
  String idempotencyKey;
  MediaUploadRequest copyWith({
    String? appId,
    Object? draftId = _unchanged,
    Object? actionId = _unchanged,
    Object? targetRecordId = _unchanged,
    Object? fieldId = _unchanged,
    Object? expectedDefinitionVersionId = _unchanged,
    int? byteLength,
    String? contentType,
    String? idempotencyKey,
  }) => MediaUploadRequest(
    appId: appId ?? this.appId,
    draftId: identical(draftId, _unchanged) ? this.draftId : draftId as String?,
    actionId: identical(actionId, _unchanged)
        ? this.actionId
        : actionId as String?,
    targetRecordId: identical(targetRecordId, _unchanged)
        ? this.targetRecordId
        : targetRecordId as String?,
    fieldId: identical(fieldId, _unchanged) ? this.fieldId : fieldId as String?,
    expectedDefinitionVersionId:
        identical(expectedDefinitionVersionId, _unchanged)
        ? this.expectedDefinitionVersionId
        : expectedDefinitionVersionId as String?,
    byteLength: byteLength ?? this.byteLength,
    contentType: contentType ?? this.contentType,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
  );
  Map<String, dynamic> toJson() => {
    'appId': appId,
    'draftId': draftId,
    'actionId': actionId,
    'targetRecordId': targetRecordId,
    'fieldId': fieldId,
    'expectedDefinitionVersionId': expectedDefinitionVersionId,
    'byteLength': byteLength,
    'contentType': contentType,
    'idempotencyKey': idempotencyKey,
  };
}

class MediaUploadTicket {
  MediaUploadTicket({required this.assetId, required this.uploadDescription});
  String assetId;
  String uploadDescription;
  MediaUploadTicket copyWith({String? assetId, String? uploadDescription}) =>
      MediaUploadTicket(
        assetId: assetId ?? this.assetId,
        uploadDescription: uploadDescription ?? this.uploadDescription,
      );
  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'uploadDescription': uploadDescription,
  };
}

class MemberInfo {
  MemberInfo({required this.actorId, required this.role});
  String actorId;
  String role;
  MemberInfo copyWith({String? actorId, String? role}) =>
      MemberInfo(actorId: actorId ?? this.actorId, role: role ?? this.role);
  Map<String, dynamic> toJson() => {'actorId': actorId, 'role': role};
}

class PlatformInfo {
  PlatformInfo({
    required this.aiAvailable,
    required this.aiMode,
    required this.development,
    required this.actorId,
  });
  bool aiAvailable;
  String aiMode;
  bool development;
  String actorId;
  PlatformInfo copyWith({
    bool? aiAvailable,
    String? aiMode,
    bool? development,
    String? actorId,
  }) => PlatformInfo(
    aiAvailable: aiAvailable ?? this.aiAvailable,
    aiMode: aiMode ?? this.aiMode,
    development: development ?? this.development,
    actorId: actorId ?? this.actorId,
  );
  Map<String, dynamic> toJson() => {
    'aiAvailable': aiAvailable,
    'aiMode': aiMode,
    'development': development,
    'actorId': actorId,
  };
}

class PublishRequest {
  PublishRequest({
    required this.draftId,
    required this.candidateHash,
    this.expectedCurrentVersionId,
    required this.enabledRuleIds,
    required this.activateExistingRecordIds,
    required this.reviewHash,
    required this.idempotencyKey,
  });
  String draftId;
  String candidateHash;
  String? expectedCurrentVersionId;
  List<String> enabledRuleIds;
  List<String> activateExistingRecordIds;
  String reviewHash;
  String idempotencyKey;
  PublishRequest copyWith({
    String? draftId,
    String? candidateHash,
    Object? expectedCurrentVersionId = _unchanged,
    List<String>? enabledRuleIds,
    List<String>? activateExistingRecordIds,
    String? reviewHash,
    String? idempotencyKey,
  }) => PublishRequest(
    draftId: draftId ?? this.draftId,
    candidateHash: candidateHash ?? this.candidateHash,
    expectedCurrentVersionId: identical(expectedCurrentVersionId, _unchanged)
        ? this.expectedCurrentVersionId
        : expectedCurrentVersionId as String?,
    enabledRuleIds: enabledRuleIds ?? this.enabledRuleIds,
    activateExistingRecordIds:
        activateExistingRecordIds ?? this.activateExistingRecordIds,
    reviewHash: reviewHash ?? this.reviewHash,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
  );
  Map<String, dynamic> toJson() => {
    'draftId': draftId,
    'candidateHash': candidateHash,
    'expectedCurrentVersionId': expectedCurrentVersionId,
    'enabledRuleIds': enabledRuleIds,
    'activateExistingRecordIds': activateExistingRecordIds,
    'reviewHash': reviewHash,
    'idempotencyKey': idempotencyKey,
  };
}

class RecordPage {
  RecordPage({required this.records, required this.total, this.nextCursor});
  List<RuntimeRecord> records;
  int total;
  String? nextCursor;
  RecordPage copyWith({
    List<RuntimeRecord>? records,
    int? total,
    Object? nextCursor = _unchanged,
  }) => RecordPage(
    records: records ?? this.records,
    total: total ?? this.total,
    nextCursor: identical(nextCursor, _unchanged)
        ? this.nextCursor
        : nextCursor as String?,
  );
  Map<String, dynamic> toJson() => {
    'records': records.map((v) => v.toJson()).toList(),
    'total': total,
    'nextCursor': nextCursor,
  };
}

class RecordSummary {
  RecordSummary({required this.total, required this.groups});
  int total;
  Map<String, int> groups;
  RecordSummary copyWith({int? total, Map<String, int>? groups}) =>
      RecordSummary(total: total ?? this.total, groups: groups ?? this.groups);
  Map<String, dynamic> toJson() => {'total': total, 'groups': groups};
}

class ReminderState {
  ReminderState({
    required this.ruleId,
    required this.state,
    this.scheduledAt,
    required this.eligible,
  });
  String ruleId;
  String state;
  DateTime? scheduledAt;
  bool eligible;
  ReminderState copyWith({
    String? ruleId,
    String? state,
    Object? scheduledAt = _unchanged,
    bool? eligible,
  }) => ReminderState(
    ruleId: ruleId ?? this.ruleId,
    state: state ?? this.state,
    scheduledAt: identical(scheduledAt, _unchanged)
        ? this.scheduledAt
        : scheduledAt as DateTime?,
    eligible: eligible ?? this.eligible,
  );
  Map<String, dynamic> toJson() => {
    'ruleId': ruleId,
    'state': state,
    'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
    'eligible': eligible,
  };
}

class RuntimeRecord {
  RuntimeRecord({
    required this.id,
    required this.collectionId,
    required this.data,
    required this.revision,
    this.capacity,
    this.allocated,
    required this.claimed,
    required this.allowedActions,
  });
  String id;
  String collectionId;
  dynamic data;
  int revision;
  int? capacity;
  int? allocated;
  bool claimed;
  List<String> allowedActions;
  RuntimeRecord copyWith({
    String? id,
    String? collectionId,
    dynamic data,
    int? revision,
    Object? capacity = _unchanged,
    Object? allocated = _unchanged,
    bool? claimed,
    List<String>? allowedActions,
  }) => RuntimeRecord(
    id: id ?? this.id,
    collectionId: collectionId ?? this.collectionId,
    data: data ?? this.data,
    revision: revision ?? this.revision,
    capacity: identical(capacity, _unchanged)
        ? this.capacity
        : capacity as int?,
    allocated: identical(allocated, _unchanged)
        ? this.allocated
        : allocated as int?,
    claimed: claimed ?? this.claimed,
    allowedActions: allowedActions ?? this.allowedActions,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionId': collectionId,
    'data': data,
    'revision': revision,
    'capacity': capacity,
    'allocated': allocated,
    'claimed': claimed,
    'allowedActions': allowedActions,
  };
}

class TemplateInfo {
  TemplateInfo({
    required this.key,
    required this.name,
    required this.specJson,
    required this.description,
  });
  String key;
  String name;
  String specJson;
  String description;
  TemplateInfo copyWith({
    String? key,
    String? name,
    String? specJson,
    String? description,
  }) => TemplateInfo(
    key: key ?? this.key,
    name: name ?? this.name,
    specJson: specJson ?? this.specJson,
    description: description ?? this.description,
  );
  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'specJson': specJson,
    'description': description,
  };
}

class WorkspaceInfo {
  WorkspaceInfo({required this.id, required this.name, required this.role});
  String id;
  String name;
  String role;
  WorkspaceInfo copyWith({String? id, String? name, String? role}) =>
      WorkspaceInfo(
        id: id ?? this.id,
        name: name ?? this.name,
        role: role ?? this.role,
      );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role};
}

class NestError implements Exception {
  NestError({
    required this.category,
    required this.message,
    this.uncertain = false,
    this.status,
  });
  final String category;
  final String message;
  final bool uncertain;
  final int? status;
  @override
  String toString() => message;
}
