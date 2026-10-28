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

abstract class WorkspaceInfo
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  WorkspaceInfo._({
    required this.id,
    required this.name,
    required this.role,
  });

  factory WorkspaceInfo({
    required int id,
    required String name,
    required String role,
  }) = _WorkspaceInfoImpl;

  factory WorkspaceInfo.fromJson(Map<String, dynamic> jsonSerialization) {
    return WorkspaceInfo(
      id: jsonSerialization['id'] as int,
      name: jsonSerialization['name'] as String,
      role: jsonSerialization['role'] as String,
    );
  }

  int id;

  String name;

  String role;

  /// Returns a shallow copy of this [WorkspaceInfo]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  WorkspaceInfo copyWith({
    int? id,
    String? name,
    String? role,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'WorkspaceInfo',
      'id': id,
      'name': name,
      'role': role,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'WorkspaceInfo',
      'id': id,
      'name': name,
      'role': role,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _WorkspaceInfoImpl extends WorkspaceInfo {
  _WorkspaceInfoImpl({
    required int id,
    required String name,
    required String role,
  }) : super._(
         id: id,
         name: name,
         role: role,
       );

  /// Returns a shallow copy of this [WorkspaceInfo]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  WorkspaceInfo copyWith({
    int? id,
    String? name,
    String? role,
  }) {
    return WorkspaceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
    );
  }
}
