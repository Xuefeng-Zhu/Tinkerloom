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
import 'package:appnest_server/src/generated/protocol.dart' as _i270vp9r;
import 'package:serverpod/serverpod.dart' as _is;

abstract class BuilderSnapshot
    implements _is.SerializableModel, _is.ProtocolSerialization {
  BuilderSnapshot._({
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
    bool? candidateReady,
    this.latestRequest,
    int? jobAttempts,
    this.jobCreatedAt,
    this.jobUpdatedAt,
    this.failureCategory,
  }) : candidateReady = candidateReady ?? false,
       jobAttempts = jobAttempts ?? 0;

  factory BuilderSnapshot({
    required int appId,
    required int draftId,
    int? jobId,
    int? baseVersionId,
    required int mutation,
    required String stage,
    required String candidateJson,
    required String candidateHash,
    required List<String> diagnostics,
    required List<String> changes,
    required List<String> enabledRuleIds,
    int? publishedVersionId,
    bool? candidateReady,
    String? latestRequest,
    int? jobAttempts,
    DateTime? jobCreatedAt,
    DateTime? jobUpdatedAt,
    String? failureCategory,
  }) = _BuilderSnapshotImpl;

  factory BuilderSnapshot.fromJson(Map<String, dynamic> jsonSerialization) {
    return BuilderSnapshot(
      appId: jsonSerialization['appId'] as int,
      draftId: jsonSerialization['draftId'] as int,
      jobId: jsonSerialization['jobId'] as int?,
      baseVersionId: jsonSerialization['baseVersionId'] as int?,
      mutation: jsonSerialization['mutation'] as int,
      stage: jsonSerialization['stage'] as String,
      candidateJson: jsonSerialization['candidateJson'] as String,
      candidateHash: jsonSerialization['candidateHash'] as String,
      diagnostics: _i270vp9r.Protocol().deserialize<List<String>>(
        jsonSerialization['diagnostics'],
      ),
      changes: _i270vp9r.Protocol().deserialize<List<String>>(
        jsonSerialization['changes'],
      ),
      enabledRuleIds: _i270vp9r.Protocol().deserialize<List<String>>(
        jsonSerialization['enabledRuleIds'],
      ),
      publishedVersionId: jsonSerialization['publishedVersionId'] as int?,
      candidateReady: jsonSerialization['candidateReady'] == null
          ? null
          : _is.BoolJsonExtension.fromJson(jsonSerialization['candidateReady']),
      latestRequest: jsonSerialization['latestRequest'] as String?,
      jobAttempts: jsonSerialization['jobAttempts'] as int?,
      jobCreatedAt: jsonSerialization['jobCreatedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(
              jsonSerialization['jobCreatedAt'],
            ),
      jobUpdatedAt: jsonSerialization['jobUpdatedAt'] == null
          ? null
          : _is.DateTimeJsonExtension.fromJson(
              jsonSerialization['jobUpdatedAt'],
            ),
      failureCategory: jsonSerialization['failureCategory'] as String?,
    );
  }

  int appId;

  int draftId;

  int? jobId;

  int? baseVersionId;

  int mutation;

  String stage;

  String candidateJson;

  String candidateHash;

  List<String> diagnostics;

  List<String> changes;

  List<String> enabledRuleIds;

  int? publishedVersionId;

  bool candidateReady;

  String? latestRequest;

  int jobAttempts;

  DateTime? jobCreatedAt;

  DateTime? jobUpdatedAt;

  String? failureCategory;

  /// Returns a shallow copy of this [BuilderSnapshot]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  BuilderSnapshot copyWith({
    int? appId,
    int? draftId,
    int? jobId,
    int? baseVersionId,
    int? mutation,
    String? stage,
    String? candidateJson,
    String? candidateHash,
    List<String>? diagnostics,
    List<String>? changes,
    List<String>? enabledRuleIds,
    int? publishedVersionId,
    bool? candidateReady,
    String? latestRequest,
    int? jobAttempts,
    DateTime? jobCreatedAt,
    DateTime? jobUpdatedAt,
    String? failureCategory,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'BuilderSnapshot',
      'appId': appId,
      'draftId': draftId,
      if (jobId != null) 'jobId': jobId,
      if (baseVersionId != null) 'baseVersionId': baseVersionId,
      'mutation': mutation,
      'stage': stage,
      'candidateJson': candidateJson,
      'candidateHash': candidateHash,
      'diagnostics': diagnostics.toJson(),
      'changes': changes.toJson(),
      'enabledRuleIds': enabledRuleIds.toJson(),
      if (publishedVersionId != null) 'publishedVersionId': publishedVersionId,
      'candidateReady': candidateReady,
      if (latestRequest != null) 'latestRequest': latestRequest,
      'jobAttempts': jobAttempts,
      if (jobCreatedAt != null) 'jobCreatedAt': jobCreatedAt?.toJson(),
      if (jobUpdatedAt != null) 'jobUpdatedAt': jobUpdatedAt?.toJson(),
      if (failureCategory != null) 'failureCategory': failureCategory,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'BuilderSnapshot',
      'appId': appId,
      'draftId': draftId,
      if (jobId != null) 'jobId': jobId,
      if (baseVersionId != null) 'baseVersionId': baseVersionId,
      'mutation': mutation,
      'stage': stage,
      'candidateJson': candidateJson,
      'candidateHash': candidateHash,
      'diagnostics': diagnostics.toJson(),
      'changes': changes.toJson(),
      'enabledRuleIds': enabledRuleIds.toJson(),
      if (publishedVersionId != null) 'publishedVersionId': publishedVersionId,
      'candidateReady': candidateReady,
      if (latestRequest != null) 'latestRequest': latestRequest,
      'jobAttempts': jobAttempts,
      if (jobCreatedAt != null) 'jobCreatedAt': jobCreatedAt?.toJson(),
      if (jobUpdatedAt != null) 'jobUpdatedAt': jobUpdatedAt?.toJson(),
      if (failureCategory != null) 'failureCategory': failureCategory,
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _BuilderSnapshotImpl extends BuilderSnapshot {
  _BuilderSnapshotImpl({
    required int appId,
    required int draftId,
    int? jobId,
    int? baseVersionId,
    required int mutation,
    required String stage,
    required String candidateJson,
    required String candidateHash,
    required List<String> diagnostics,
    required List<String> changes,
    required List<String> enabledRuleIds,
    int? publishedVersionId,
    bool? candidateReady,
    String? latestRequest,
    int? jobAttempts,
    DateTime? jobCreatedAt,
    DateTime? jobUpdatedAt,
    String? failureCategory,
  }) : super._(
         appId: appId,
         draftId: draftId,
         jobId: jobId,
         baseVersionId: baseVersionId,
         mutation: mutation,
         stage: stage,
         candidateJson: candidateJson,
         candidateHash: candidateHash,
         diagnostics: diagnostics,
         changes: changes,
         enabledRuleIds: enabledRuleIds,
         publishedVersionId: publishedVersionId,
         candidateReady: candidateReady,
         latestRequest: latestRequest,
         jobAttempts: jobAttempts,
         jobCreatedAt: jobCreatedAt,
         jobUpdatedAt: jobUpdatedAt,
         failureCategory: failureCategory,
       );

  /// Returns a shallow copy of this [BuilderSnapshot]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  BuilderSnapshot copyWith({
    int? appId,
    int? draftId,
    Object? jobId = _Undefined,
    Object? baseVersionId = _Undefined,
    int? mutation,
    String? stage,
    String? candidateJson,
    String? candidateHash,
    List<String>? diagnostics,
    List<String>? changes,
    List<String>? enabledRuleIds,
    Object? publishedVersionId = _Undefined,
    bool? candidateReady,
    Object? latestRequest = _Undefined,
    int? jobAttempts,
    Object? jobCreatedAt = _Undefined,
    Object? jobUpdatedAt = _Undefined,
    Object? failureCategory = _Undefined,
  }) {
    return BuilderSnapshot(
      appId: appId ?? this.appId,
      draftId: draftId ?? this.draftId,
      jobId: jobId is int? ? jobId : this.jobId,
      baseVersionId: baseVersionId is int? ? baseVersionId : this.baseVersionId,
      mutation: mutation ?? this.mutation,
      stage: stage ?? this.stage,
      candidateJson: candidateJson ?? this.candidateJson,
      candidateHash: candidateHash ?? this.candidateHash,
      diagnostics: diagnostics ?? this.diagnostics.map((e0) => e0).toList(),
      changes: changes ?? this.changes.map((e0) => e0).toList(),
      enabledRuleIds:
          enabledRuleIds ?? this.enabledRuleIds.map((e0) => e0).toList(),
      publishedVersionId: publishedVersionId is int?
          ? publishedVersionId
          : this.publishedVersionId,
      candidateReady: candidateReady ?? this.candidateReady,
      latestRequest: latestRequest is String?
          ? latestRequest
          : this.latestRequest,
      jobAttempts: jobAttempts ?? this.jobAttempts,
      jobCreatedAt: jobCreatedAt is DateTime?
          ? jobCreatedAt
          : this.jobCreatedAt,
      jobUpdatedAt: jobUpdatedAt is DateTime?
          ? jobUpdatedAt
          : this.jobUpdatedAt,
      failureCategory: failureCategory is String?
          ? failureCategory
          : this.failureCategory,
    );
  }
}
