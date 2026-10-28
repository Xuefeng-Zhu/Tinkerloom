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
import 'runtime_record.dart' as _ilpx295a;

abstract class RecordPage
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  RecordPage._({
    required this.records,
    required this.total,
    this.nextCursor,
  });

  factory RecordPage({
    required List<_ilpx295a.RuntimeRecord> records,
    required int total,
    String? nextCursor,
  }) = _RecordPageImpl;

  factory RecordPage.fromJson(Map<String, dynamic> jsonSerialization) {
    return RecordPage(
      records: _ikh0m8by.Protocol().deserialize<List<_ilpx295a.RuntimeRecord>>(
        jsonSerialization['records'],
      ),
      total: jsonSerialization['total'] as int,
      nextCursor: jsonSerialization['nextCursor'] as String?,
    );
  }

  List<_ilpx295a.RuntimeRecord> records;

  int total;

  String? nextCursor;

  /// Returns a shallow copy of this [RecordPage]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  RecordPage copyWith({
    List<_ilpx295a.RuntimeRecord>? records,
    int? total,
    String? nextCursor,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'RecordPage',
      'records': records.toJson(valueToJson: (v) => v.toJson()),
      'total': total,
      if (nextCursor != null) 'nextCursor': nextCursor,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'RecordPage',
      'records': records.toJson(valueToJson: (v) => v.toJsonForProtocol()),
      'total': total,
      if (nextCursor != null) 'nextCursor': nextCursor,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _RecordPageImpl extends RecordPage {
  _RecordPageImpl({
    required List<_ilpx295a.RuntimeRecord> records,
    required int total,
    String? nextCursor,
  }) : super._(
         records: records,
         total: total,
         nextCursor: nextCursor,
       );

  /// Returns a shallow copy of this [RecordPage]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  RecordPage copyWith({
    List<_ilpx295a.RuntimeRecord>? records,
    int? total,
    Object? nextCursor = _Undefined,
  }) {
    return RecordPage(
      records: records ?? this.records.map((e0) => e0.copyWith()).toList(),
      total: total ?? this.total,
      nextCursor: nextCursor is String? ? nextCursor : this.nextCursor,
    );
  }
}
