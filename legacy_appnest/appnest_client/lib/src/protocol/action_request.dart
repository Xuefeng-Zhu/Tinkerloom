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
import 'package:appnest_client/src/protocol/protocol.dart' as _ikh0m8by;
import 'package:serverpod_client/serverpod_client.dart' as _isc;

abstract class ActionRequest
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  ActionRequest._({
    required this.appId,
    required this.actionId,
    this.targetRecordId,
    required this.expectedDefinitionVersionId,
    this.expectedRecordRevision,
    required this.input,
    required this.idempotencyKey,
  });

  factory ActionRequest({
    required int appId,
    required String actionId,
    int? targetRecordId,
    required int expectedDefinitionVersionId,
    int? expectedRecordRevision,
    required dynamic input,
    required String idempotencyKey,
  }) = _ActionRequestImpl;

  factory ActionRequest.fromJson(Map<String, dynamic> jsonSerialization) {
    return ActionRequest(
      appId: jsonSerialization['appId'] as int,
      actionId: jsonSerialization['actionId'] as String,
      targetRecordId: jsonSerialization['targetRecordId'] as int?,
      expectedDefinitionVersionId:
          jsonSerialization['expectedDefinitionVersionId'] as int,
      expectedRecordRevision:
          jsonSerialization['expectedRecordRevision'] as int?,
      input: _ikh0m8by.Protocol().deserializeDynamicFieldValue(
        jsonSerialization['input'],
      ),
      idempotencyKey: jsonSerialization['idempotencyKey'] as String,
    );
  }

  int appId;

  String actionId;

  int? targetRecordId;

  int expectedDefinitionVersionId;

  int? expectedRecordRevision;

  dynamic input;

  String idempotencyKey;

  /// Returns a shallow copy of this [ActionRequest]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  ActionRequest copyWith({
    int? appId,
    String? actionId,
    int? targetRecordId,
    int? expectedDefinitionVersionId,
    int? expectedRecordRevision,
    dynamic input,
    String? idempotencyKey,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ActionRequest',
      'appId': appId,
      'actionId': actionId,
      if (targetRecordId != null) 'targetRecordId': targetRecordId,
      'expectedDefinitionVersionId': expectedDefinitionVersionId,
      if (expectedRecordRevision != null)
        'expectedRecordRevision': expectedRecordRevision,
      'input': _ikh0m8by.Protocol().dynamicFieldToJson(input),
      'idempotencyKey': idempotencyKey,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'ActionRequest',
      'appId': appId,
      'actionId': actionId,
      if (targetRecordId != null) 'targetRecordId': targetRecordId,
      'expectedDefinitionVersionId': expectedDefinitionVersionId,
      if (expectedRecordRevision != null)
        'expectedRecordRevision': expectedRecordRevision,
      'input': _ikh0m8by.Protocol().dynamicFieldToJson(
        input,
        forProtocol: true,
      ),
      'idempotencyKey': idempotencyKey,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ActionRequestImpl extends ActionRequest {
  _ActionRequestImpl({
    required int appId,
    required String actionId,
    int? targetRecordId,
    required int expectedDefinitionVersionId,
    int? expectedRecordRevision,
    required dynamic input,
    required String idempotencyKey,
  }) : super._(
         appId: appId,
         actionId: actionId,
         targetRecordId: targetRecordId,
         expectedDefinitionVersionId: expectedDefinitionVersionId,
         expectedRecordRevision: expectedRecordRevision,
         input: input,
         idempotencyKey: idempotencyKey,
       );

  /// Returns a shallow copy of this [ActionRequest]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  ActionRequest copyWith({
    int? appId,
    String? actionId,
    Object? targetRecordId = _Undefined,
    int? expectedDefinitionVersionId,
    Object? expectedRecordRevision = _Undefined,
    Object? input = _Undefined,
    String? idempotencyKey,
  }) {
    return ActionRequest(
      appId: appId ?? this.appId,
      actionId: actionId ?? this.actionId,
      targetRecordId: targetRecordId is int?
          ? targetRecordId
          : this.targetRecordId,
      expectedDefinitionVersionId:
          expectedDefinitionVersionId ?? this.expectedDefinitionVersionId,
      expectedRecordRevision: expectedRecordRevision is int?
          ? expectedRecordRevision
          : this.expectedRecordRevision,
      input: input != _Undefined ? input : this.input,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }
}
