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

abstract class RuntimeRecord
    implements _is.SerializableModel, _is.ProtocolSerialization {
  RuntimeRecord._({
    required this.id,
    required this.collectionId,
    required this.data,
    required this.revision,
    this.capacity,
    this.allocated,
    required this.claimed,
    required this.allowedActions,
  });

  factory RuntimeRecord({
    required int id,
    required String collectionId,
    required dynamic data,
    required int revision,
    int? capacity,
    int? allocated,
    required bool claimed,
    required List<String> allowedActions,
  }) = _RuntimeRecordImpl;

  factory RuntimeRecord.fromJson(Map<String, dynamic> jsonSerialization) {
    return RuntimeRecord(
      id: jsonSerialization['id'] as int,
      collectionId: jsonSerialization['collectionId'] as String,
      data: _i270vp9r.Protocol().deserializeDynamicFieldValue(
        jsonSerialization['data'],
      ),
      revision: jsonSerialization['revision'] as int,
      capacity: jsonSerialization['capacity'] as int?,
      allocated: jsonSerialization['allocated'] as int?,
      claimed: _is.BoolJsonExtension.fromJson(jsonSerialization['claimed']),
      allowedActions: _i270vp9r.Protocol().deserialize<List<String>>(
        jsonSerialization['allowedActions'],
      ),
    );
  }

  int id;

  String collectionId;

  dynamic data;

  int revision;

  int? capacity;

  int? allocated;

  bool claimed;

  List<String> allowedActions;

  /// Returns a shallow copy of this [RuntimeRecord]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  RuntimeRecord copyWith({
    int? id,
    String? collectionId,
    dynamic data,
    int? revision,
    int? capacity,
    int? allocated,
    bool? claimed,
    List<String>? allowedActions,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'RuntimeRecord',
      'id': id,
      'collectionId': collectionId,
      'data': _i270vp9r.Protocol().dynamicFieldToJson(data),
      'revision': revision,
      if (capacity != null) 'capacity': capacity,
      if (allocated != null) 'allocated': allocated,
      'claimed': claimed,
      'allowedActions': allowedActions.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'RuntimeRecord',
      'id': id,
      'collectionId': collectionId,
      'data': _i270vp9r.Protocol().dynamicFieldToJson(
        data,
        forProtocol: true,
      ),
      'revision': revision,
      if (capacity != null) 'capacity': capacity,
      if (allocated != null) 'allocated': allocated,
      'claimed': claimed,
      'allowedActions': allowedActions.toJson(),
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _RuntimeRecordImpl extends RuntimeRecord {
  _RuntimeRecordImpl({
    required int id,
    required String collectionId,
    required dynamic data,
    required int revision,
    int? capacity,
    int? allocated,
    required bool claimed,
    required List<String> allowedActions,
  }) : super._(
         id: id,
         collectionId: collectionId,
         data: data,
         revision: revision,
         capacity: capacity,
         allocated: allocated,
         claimed: claimed,
         allowedActions: allowedActions,
       );

  /// Returns a shallow copy of this [RuntimeRecord]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  RuntimeRecord copyWith({
    int? id,
    String? collectionId,
    Object? data = _Undefined,
    int? revision,
    Object? capacity = _Undefined,
    Object? allocated = _Undefined,
    bool? claimed,
    List<String>? allowedActions,
  }) {
    return RuntimeRecord(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      data: data != _Undefined ? data : this.data,
      revision: revision ?? this.revision,
      capacity: capacity is int? ? capacity : this.capacity,
      allocated: allocated is int? ? allocated : this.allocated,
      claimed: claimed ?? this.claimed,
      allowedActions:
          allowedActions ?? this.allowedActions.map((e0) => e0).toList(),
    );
  }
}
