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

abstract class PlatformInfo
    implements _is.SerializableModel, _is.ProtocolSerialization {
  PlatformInfo._({
    required this.aiAvailable,
    required this.aiMode,
    required this.development,
    required this.actorId,
  });

  factory PlatformInfo({
    required bool aiAvailable,
    required String aiMode,
    required bool development,
    required String actorId,
  }) = _PlatformInfoImpl;

  factory PlatformInfo.fromJson(Map<String, dynamic> jsonSerialization) {
    return PlatformInfo(
      aiAvailable: _is.BoolJsonExtension.fromJson(
        jsonSerialization['aiAvailable'],
      ),
      aiMode: jsonSerialization['aiMode'] as String,
      development: _is.BoolJsonExtension.fromJson(
        jsonSerialization['development'],
      ),
      actorId: jsonSerialization['actorId'] as String,
    );
  }

  bool aiAvailable;

  String aiMode;

  bool development;

  String actorId;

  /// Returns a shallow copy of this [PlatformInfo]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  PlatformInfo copyWith({
    bool? aiAvailable,
    String? aiMode,
    bool? development,
    String? actorId,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'PlatformInfo',
      'aiAvailable': aiAvailable,
      'aiMode': aiMode,
      'development': development,
      'actorId': actorId,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'PlatformInfo',
      'aiAvailable': aiAvailable,
      'aiMode': aiMode,
      'development': development,
      'actorId': actorId,
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _PlatformInfoImpl extends PlatformInfo {
  _PlatformInfoImpl({
    required bool aiAvailable,
    required String aiMode,
    required bool development,
    required String actorId,
  }) : super._(
         aiAvailable: aiAvailable,
         aiMode: aiMode,
         development: development,
         actorId: actorId,
       );

  /// Returns a shallow copy of this [PlatformInfo]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  PlatformInfo copyWith({
    bool? aiAvailable,
    String? aiMode,
    bool? development,
    String? actorId,
  }) {
    return PlatformInfo(
      aiAvailable: aiAvailable ?? this.aiAvailable,
      aiMode: aiMode ?? this.aiMode,
      development: development ?? this.development,
      actorId: actorId ?? this.actorId,
    );
  }
}
