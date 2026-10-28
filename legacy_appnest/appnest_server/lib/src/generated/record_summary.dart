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

abstract class RecordSummary
    implements _is.SerializableModel, _is.ProtocolSerialization {
  RecordSummary._({
    required this.total,
    required this.groups,
  });

  factory RecordSummary({
    required int total,
    required Map<String, int> groups,
  }) = _RecordSummaryImpl;

  factory RecordSummary.fromJson(Map<String, dynamic> jsonSerialization) {
    return RecordSummary(
      total: jsonSerialization['total'] as int,
      groups: _i270vp9r.Protocol().deserialize<Map<String, int>>(
        jsonSerialization['groups'],
      ),
    );
  }

  int total;

  Map<String, int> groups;

  /// Returns a shallow copy of this [RecordSummary]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  RecordSummary copyWith({
    int? total,
    Map<String, int>? groups,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'RecordSummary',
      'total': total,
      'groups': groups.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'RecordSummary',
      'total': total,
      'groups': groups.toJson(),
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _RecordSummaryImpl extends RecordSummary {
  _RecordSummaryImpl({
    required int total,
    required Map<String, int> groups,
  }) : super._(
         total: total,
         groups: groups,
       );

  /// Returns a shallow copy of this [RecordSummary]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  RecordSummary copyWith({
    int? total,
    Map<String, int>? groups,
  }) {
    return RecordSummary(
      total: total ?? this.total,
      groups:
          groups ??
          this.groups.map(
            (
              key0,
              value0,
            ) => MapEntry(
              key0,
              value0,
            ),
          ),
    );
  }
}
