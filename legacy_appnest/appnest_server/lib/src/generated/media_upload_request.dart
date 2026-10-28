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
import 'package:serverpod/serverpod.dart' as _is;

abstract class MediaUploadRequest
    implements _is.SerializableModel, _is.ProtocolSerialization {
  MediaUploadRequest._({
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

  factory MediaUploadRequest({
    required int appId,
    int? draftId,
    String? actionId,
    int? targetRecordId,
    String? fieldId,
    int? expectedDefinitionVersionId,
    required int byteLength,
    required String contentType,
    required String idempotencyKey,
  }) = _MediaUploadRequestImpl;

  factory MediaUploadRequest.fromJson(Map<String, dynamic> jsonSerialization) {
    return MediaUploadRequest(
      appId: jsonSerialization['appId'] as int,
      draftId: jsonSerialization['draftId'] as int?,
      actionId: jsonSerialization['actionId'] as String?,
      targetRecordId: jsonSerialization['targetRecordId'] as int?,
      fieldId: jsonSerialization['fieldId'] as String?,
      expectedDefinitionVersionId:
          jsonSerialization['expectedDefinitionVersionId'] as int?,
      byteLength: jsonSerialization['byteLength'] as int,
      contentType: jsonSerialization['contentType'] as String,
      idempotencyKey: jsonSerialization['idempotencyKey'] as String,
    );
  }

  int appId;

  int? draftId;

  String? actionId;

  int? targetRecordId;

  String? fieldId;

  int? expectedDefinitionVersionId;

  int byteLength;

  String contentType;

  String idempotencyKey;

  /// Returns a shallow copy of this [MediaUploadRequest]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  MediaUploadRequest copyWith({
    int? appId,
    int? draftId,
    String? actionId,
    int? targetRecordId,
    String? fieldId,
    int? expectedDefinitionVersionId,
    int? byteLength,
    String? contentType,
    String? idempotencyKey,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MediaUploadRequest',
      'appId': appId,
      if (draftId != null) 'draftId': draftId,
      if (actionId != null) 'actionId': actionId,
      if (targetRecordId != null) 'targetRecordId': targetRecordId,
      if (fieldId != null) 'fieldId': fieldId,
      if (expectedDefinitionVersionId != null)
        'expectedDefinitionVersionId': expectedDefinitionVersionId,
      'byteLength': byteLength,
      'contentType': contentType,
      'idempotencyKey': idempotencyKey,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'MediaUploadRequest',
      'appId': appId,
      if (draftId != null) 'draftId': draftId,
      if (actionId != null) 'actionId': actionId,
      if (targetRecordId != null) 'targetRecordId': targetRecordId,
      if (fieldId != null) 'fieldId': fieldId,
      if (expectedDefinitionVersionId != null)
        'expectedDefinitionVersionId': expectedDefinitionVersionId,
      'byteLength': byteLength,
      'contentType': contentType,
      'idempotencyKey': idempotencyKey,
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _MediaUploadRequestImpl extends MediaUploadRequest {
  _MediaUploadRequestImpl({
    required int appId,
    int? draftId,
    String? actionId,
    int? targetRecordId,
    String? fieldId,
    int? expectedDefinitionVersionId,
    required int byteLength,
    required String contentType,
    required String idempotencyKey,
  }) : super._(
         appId: appId,
         draftId: draftId,
         actionId: actionId,
         targetRecordId: targetRecordId,
         fieldId: fieldId,
         expectedDefinitionVersionId: expectedDefinitionVersionId,
         byteLength: byteLength,
         contentType: contentType,
         idempotencyKey: idempotencyKey,
       );

  /// Returns a shallow copy of this [MediaUploadRequest]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  MediaUploadRequest copyWith({
    int? appId,
    Object? draftId = _Undefined,
    Object? actionId = _Undefined,
    Object? targetRecordId = _Undefined,
    Object? fieldId = _Undefined,
    Object? expectedDefinitionVersionId = _Undefined,
    int? byteLength,
    String? contentType,
    String? idempotencyKey,
  }) {
    return MediaUploadRequest(
      appId: appId ?? this.appId,
      draftId: draftId is int? ? draftId : this.draftId,
      actionId: actionId is String? ? actionId : this.actionId,
      targetRecordId: targetRecordId is int?
          ? targetRecordId
          : this.targetRecordId,
      fieldId: fieldId is String? ? fieldId : this.fieldId,
      expectedDefinitionVersionId: expectedDefinitionVersionId is int?
          ? expectedDefinitionVersionId
          : this.expectedDefinitionVersionId,
      byteLength: byteLength ?? this.byteLength,
      contentType: contentType ?? this.contentType,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }
}
