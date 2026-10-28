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

abstract class ReminderState
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  ReminderState._({
    required this.ruleId,
    required this.state,
    this.scheduledAt,
    required this.eligible,
  });

  factory ReminderState({
    required String ruleId,
    required String state,
    DateTime? scheduledAt,
    required bool eligible,
  }) = _ReminderStateImpl;

  factory ReminderState.fromJson(Map<String, dynamic> jsonSerialization) {
    return ReminderState(
      ruleId: jsonSerialization['ruleId'] as String,
      state: jsonSerialization['state'] as String,
      scheduledAt: jsonSerialization['scheduledAt'] == null
          ? null
          : _isc.DateTimeJsonExtension.fromJson(
              jsonSerialization['scheduledAt'],
            ),
      eligible: _isc.BoolJsonExtension.fromJson(jsonSerialization['eligible']),
    );
  }

  String ruleId;

  String state;

  DateTime? scheduledAt;

  bool eligible;

  /// Returns a shallow copy of this [ReminderState]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  ReminderState copyWith({
    String? ruleId,
    String? state,
    DateTime? scheduledAt,
    bool? eligible,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ReminderState',
      'ruleId': ruleId,
      'state': state,
      if (scheduledAt != null) 'scheduledAt': scheduledAt?.toJson(),
      'eligible': eligible,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'ReminderState',
      'ruleId': ruleId,
      'state': state,
      if (scheduledAt != null) 'scheduledAt': scheduledAt?.toJson(),
      'eligible': eligible,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _ReminderStateImpl extends ReminderState {
  _ReminderStateImpl({
    required String ruleId,
    required String state,
    DateTime? scheduledAt,
    required bool eligible,
  }) : super._(
         ruleId: ruleId,
         state: state,
         scheduledAt: scheduledAt,
         eligible: eligible,
       );

  /// Returns a shallow copy of this [ReminderState]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  ReminderState copyWith({
    String? ruleId,
    String? state,
    Object? scheduledAt = _Undefined,
    bool? eligible,
  }) {
    return ReminderState(
      ruleId: ruleId ?? this.ruleId,
      state: state ?? this.state,
      scheduledAt: scheduledAt is DateTime? ? scheduledAt : this.scheduledAt,
      eligible: eligible ?? this.eligible,
    );
  }
}
