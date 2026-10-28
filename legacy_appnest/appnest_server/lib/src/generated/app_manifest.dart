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

abstract class AppManifest
    implements _is.SerializableModel, _is.ProtocolSerialization {
  AppManifest._({
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
  });

  factory AppManifest({
    required int appId,
    required int workspaceId,
    required String name,
    int? versionId,
    String? specJson,
    required String role,
    required bool archived,
    required bool pinned,
    required int recordCount,
    required int availablePlaces,
    List<String>? approvedRuleIds,
  }) = _AppManifestImpl;

  factory AppManifest.fromJson(Map<String, dynamic> jsonSerialization) {
    return AppManifest(
      appId: jsonSerialization['appId'] as int,
      workspaceId: jsonSerialization['workspaceId'] as int,
      name: jsonSerialization['name'] as String,
      versionId: jsonSerialization['versionId'] as int?,
      specJson: jsonSerialization['specJson'] as String?,
      role: jsonSerialization['role'] as String,
      archived: _is.BoolJsonExtension.fromJson(jsonSerialization['archived']),
      pinned: _is.BoolJsonExtension.fromJson(jsonSerialization['pinned']),
      recordCount: jsonSerialization['recordCount'] as int,
      availablePlaces: jsonSerialization['availablePlaces'] as int,
      approvedRuleIds: jsonSerialization['approvedRuleIds'] == null
          ? null
          : _i270vp9r.Protocol().deserialize<List<String>>(
              jsonSerialization['approvedRuleIds'],
            ),
    );
  }

  int appId;

  int workspaceId;

  String name;

  int? versionId;

  String? specJson;

  String role;

  bool archived;

  bool pinned;

  int recordCount;

  int availablePlaces;

  List<String>? approvedRuleIds;

  /// Returns a shallow copy of this [AppManifest]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AppManifest copyWith({
    int? appId,
    int? workspaceId,
    String? name,
    int? versionId,
    String? specJson,
    String? role,
    bool? archived,
    bool? pinned,
    int? recordCount,
    int? availablePlaces,
    List<String>? approvedRuleIds,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AppManifest',
      'appId': appId,
      'workspaceId': workspaceId,
      'name': name,
      if (versionId != null) 'versionId': versionId,
      if (specJson != null) 'specJson': specJson,
      'role': role,
      'archived': archived,
      'pinned': pinned,
      'recordCount': recordCount,
      'availablePlaces': availablePlaces,
      if (approvedRuleIds != null) 'approvedRuleIds': approvedRuleIds?.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AppManifest',
      'appId': appId,
      'workspaceId': workspaceId,
      'name': name,
      if (versionId != null) 'versionId': versionId,
      if (specJson != null) 'specJson': specJson,
      'role': role,
      'archived': archived,
      'pinned': pinned,
      'recordCount': recordCount,
      'availablePlaces': availablePlaces,
      if (approvedRuleIds != null) 'approvedRuleIds': approvedRuleIds?.toJson(),
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AppManifestImpl extends AppManifest {
  _AppManifestImpl({
    required int appId,
    required int workspaceId,
    required String name,
    int? versionId,
    String? specJson,
    required String role,
    required bool archived,
    required bool pinned,
    required int recordCount,
    required int availablePlaces,
    List<String>? approvedRuleIds,
  }) : super._(
         appId: appId,
         workspaceId: workspaceId,
         name: name,
         versionId: versionId,
         specJson: specJson,
         role: role,
         archived: archived,
         pinned: pinned,
         recordCount: recordCount,
         availablePlaces: availablePlaces,
         approvedRuleIds: approvedRuleIds,
       );

  /// Returns a shallow copy of this [AppManifest]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AppManifest copyWith({
    int? appId,
    int? workspaceId,
    String? name,
    Object? versionId = _Undefined,
    Object? specJson = _Undefined,
    String? role,
    bool? archived,
    bool? pinned,
    int? recordCount,
    int? availablePlaces,
    Object? approvedRuleIds = _Undefined,
  }) {
    return AppManifest(
      appId: appId ?? this.appId,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      versionId: versionId is int? ? versionId : this.versionId,
      specJson: specJson is String? ? specJson : this.specJson,
      role: role ?? this.role,
      archived: archived ?? this.archived,
      pinned: pinned ?? this.pinned,
      recordCount: recordCount ?? this.recordCount,
      availablePlaces: availablePlaces ?? this.availablePlaces,
      approvedRuleIds: approvedRuleIds is List<String>?
          ? approvedRuleIds
          : this.approvedRuleIds?.map((e0) => e0).toList(),
    );
  }
}
