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
import 'package:serverpod_client/serverpod_client.dart' as _isc;

abstract class MemberInfo
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  MemberInfo._({
    required this.actorId,
    required this.role,
  });

  factory MemberInfo({
    required String actorId,
    required String role,
  }) = _MemberInfoImpl;

  factory MemberInfo.fromJson(Map<String, dynamic> jsonSerialization) {
    return MemberInfo(
      actorId: jsonSerialization['actorId'] as String,
      role: jsonSerialization['role'] as String,
    );
  }

  String actorId;

  String role;

  /// Returns a shallow copy of this [MemberInfo]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  MemberInfo copyWith({
    String? actorId,
    String? role,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MemberInfo',
      'actorId': actorId,
      'role': role,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'MemberInfo',
      'actorId': actorId,
      'role': role,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _MemberInfoImpl extends MemberInfo {
  _MemberInfoImpl({
    required String actorId,
    required String role,
  }) : super._(
         actorId: actorId,
         role: role,
       );

  /// Returns a shallow copy of this [MemberInfo]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  MemberInfo copyWith({
    String? actorId,
    String? role,
  }) {
    return MemberInfo(
      actorId: actorId ?? this.actorId,
      role: role ?? this.role,
    );
  }
}
