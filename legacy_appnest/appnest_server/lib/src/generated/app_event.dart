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

abstract class AppEvent
    implements _is.SerializableModel, _is.ProtocolSerialization {
  AppEvent._({
    required this.appId,
    required this.revision,
    required this.kind,
  });

  factory AppEvent({
    required int appId,
    required int revision,
    required String kind,
  }) = _AppEventImpl;

  factory AppEvent.fromJson(Map<String, dynamic> jsonSerialization) {
    return AppEvent(
      appId: jsonSerialization['appId'] as int,
      revision: jsonSerialization['revision'] as int,
      kind: jsonSerialization['kind'] as String,
    );
  }

  int appId;

  int revision;

  String kind;

  /// Returns a shallow copy of this [AppEvent]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AppEvent copyWith({
    int? appId,
    int? revision,
    String? kind,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'AppEvent',
      'appId': appId,
      'revision': revision,
      'kind': kind,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'AppEvent',
      'appId': appId,
      'revision': revision,
      'kind': kind,
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _AppEventImpl extends AppEvent {
  _AppEventImpl({
    required int appId,
    required int revision,
    required String kind,
  }) : super._(
         appId: appId,
         revision: revision,
         kind: kind,
       );

  /// Returns a shallow copy of this [AppEvent]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AppEvent copyWith({
    int? appId,
    int? revision,
    String? kind,
  }) {
    return AppEvent(
      appId: appId ?? this.appId,
      revision: revision ?? this.revision,
      kind: kind ?? this.kind,
    );
  }
}
