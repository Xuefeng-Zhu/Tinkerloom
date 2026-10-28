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

abstract class PublishRequest
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  PublishRequest._({
    required this.draftId,
    required this.candidateHash,
    this.expectedCurrentVersionId,
    required this.enabledRuleIds,
    required this.activateExistingRecordIds,
    required this.reviewHash,
    required this.idempotencyKey,
  });

  factory PublishRequest({
    required int draftId,
    required String candidateHash,
    int? expectedCurrentVersionId,
    required List<String> enabledRuleIds,
    required List<int> activateExistingRecordIds,
    required String reviewHash,
    required String idempotencyKey,
  }) = _PublishRequestImpl;

  factory PublishRequest.fromJson(Map<String, dynamic> jsonSerialization) {
    return PublishRequest(
      draftId: jsonSerialization['draftId'] as int,
      candidateHash: jsonSerialization['candidateHash'] as String,
      expectedCurrentVersionId:
          jsonSerialization['expectedCurrentVersionId'] as int?,
      enabledRuleIds: _ikh0m8by.Protocol().deserialize<List<String>>(
        jsonSerialization['enabledRuleIds'],
      ),
      activateExistingRecordIds: _ikh0m8by.Protocol().deserialize<List<int>>(
        jsonSerialization['activateExistingRecordIds'],
      ),
      reviewHash: jsonSerialization['reviewHash'] as String,
      idempotencyKey: jsonSerialization['idempotencyKey'] as String,
    );
  }

  int draftId;

  String candidateHash;

  int? expectedCurrentVersionId;

  List<String> enabledRuleIds;

  List<int> activateExistingRecordIds;

  String reviewHash;

  String idempotencyKey;

  /// Returns a shallow copy of this [PublishRequest]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  PublishRequest copyWith({
    int? draftId,
    String? candidateHash,
    int? expectedCurrentVersionId,
    List<String>? enabledRuleIds,
    List<int>? activateExistingRecordIds,
    String? reviewHash,
    String? idempotencyKey,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PublishRequest',
      'draftId': draftId,
      'candidateHash': candidateHash,
      if (expectedCurrentVersionId != null)
        'expectedCurrentVersionId': expectedCurrentVersionId,
      'enabledRuleIds': enabledRuleIds.toJson(),
      'activateExistingRecordIds': activateExistingRecordIds.toJson(),
      'reviewHash': reviewHash,
      'idempotencyKey': idempotencyKey,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'PublishRequest',
      'draftId': draftId,
      'candidateHash': candidateHash,
      if (expectedCurrentVersionId != null)
        'expectedCurrentVersionId': expectedCurrentVersionId,
      'enabledRuleIds': enabledRuleIds.toJson(),
      'activateExistingRecordIds': activateExistingRecordIds.toJson(),
      'reviewHash': reviewHash,
      'idempotencyKey': idempotencyKey,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _PublishRequestImpl extends PublishRequest {
  _PublishRequestImpl({
    required int draftId,
    required String candidateHash,
    int? expectedCurrentVersionId,
    required List<String> enabledRuleIds,
    required List<int> activateExistingRecordIds,
    required String reviewHash,
    required String idempotencyKey,
  }) : super._(
         draftId: draftId,
         candidateHash: candidateHash,
         expectedCurrentVersionId: expectedCurrentVersionId,
         enabledRuleIds: enabledRuleIds,
         activateExistingRecordIds: activateExistingRecordIds,
         reviewHash: reviewHash,
         idempotencyKey: idempotencyKey,
       );

  /// Returns a shallow copy of this [PublishRequest]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  PublishRequest copyWith({
    int? draftId,
    String? candidateHash,
    Object? expectedCurrentVersionId = _Undefined,
    List<String>? enabledRuleIds,
    List<int>? activateExistingRecordIds,
    String? reviewHash,
    String? idempotencyKey,
  }) {
    return PublishRequest(
      draftId: draftId ?? this.draftId,
      candidateHash: candidateHash ?? this.candidateHash,
      expectedCurrentVersionId: expectedCurrentVersionId is int?
          ? expectedCurrentVersionId
          : this.expectedCurrentVersionId,
      enabledRuleIds:
          enabledRuleIds ?? this.enabledRuleIds.map((e0) => e0).toList(),
      activateExistingRecordIds:
          activateExistingRecordIds ??
          this.activateExistingRecordIds.map((e0) => e0).toList(),
      reviewHash: reviewHash ?? this.reviewHash,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }
}
