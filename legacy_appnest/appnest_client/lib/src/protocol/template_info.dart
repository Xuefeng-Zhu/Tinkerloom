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

abstract class TemplateInfo
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  TemplateInfo._({
    required this.key,
    required this.name,
    required this.specJson,
    required this.description,
  });

  factory TemplateInfo({
    required String key,
    required String name,
    required String specJson,
    required String description,
  }) = _TemplateInfoImpl;

  factory TemplateInfo.fromJson(Map<String, dynamic> jsonSerialization) {
    return TemplateInfo(
      key: jsonSerialization['key'] as String,
      name: jsonSerialization['name'] as String,
      specJson: jsonSerialization['specJson'] as String,
      description: jsonSerialization['description'] as String,
    );
  }

  String key;

  String name;

  String specJson;

  String description;

  /// Returns a shallow copy of this [TemplateInfo]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  TemplateInfo copyWith({
    String? key,
    String? name,
    String? specJson,
    String? description,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'TemplateInfo',
      'key': key,
      'name': name,
      'specJson': specJson,
      'description': description,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'TemplateInfo',
      'key': key,
      'name': name,
      'specJson': specJson,
      'description': description,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _TemplateInfoImpl extends TemplateInfo {
  _TemplateInfoImpl({
    required String key,
    required String name,
    required String specJson,
    required String description,
  }) : super._(
         key: key,
         name: name,
         specJson: specJson,
         description: description,
       );

  /// Returns a shallow copy of this [TemplateInfo]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  TemplateInfo copyWith({
    String? key,
    String? name,
    String? specJson,
    String? description,
  }) {
    return TemplateInfo(
      key: key ?? this.key,
      name: name ?? this.name,
      specJson: specJson ?? this.specJson,
      description: description ?? this.description,
    );
  }
}
