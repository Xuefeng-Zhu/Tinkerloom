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

abstract class ActionOutcome
    implements _is.SerializableModel, _is.ProtocolSerialization {
  ActionOutcome._({
    required this.recordId,
    required this.revision,
    required this.message,
  });

  factory ActionOutcome({
    required int recordId,
    required int revision,
    required String message,
  }) = _ActionOutcomeImpl;

  factory ActionOutcome.fromJson(Map<String, dynamic> jsonSerialization) {
    return ActionOutcome(
      recordId: jsonSerialization['recordId'] as int,
      revision: jsonSerialization['revision'] as int,
      message: jsonSerialization['message'] as String,
    );
  }

  int recordId;

  int revision;

  String message;

  /// Returns a shallow copy of this [ActionOutcome]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  ActionOutcome copyWith({
    int? recordId,
    int? revision,
    String? message,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ActionOutcome',
      'recordId': recordId,
      'revision': revision,
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'ActionOutcome',
      'recordId': recordId,
      'revision': revision,
      'message': message,
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _ActionOutcomeImpl extends ActionOutcome {
  _ActionOutcomeImpl({
    required int recordId,
    required int revision,
    required String message,
  }) : super._(
         recordId: recordId,
         revision: revision,
         message: message,
       );

  /// Returns a shallow copy of this [ActionOutcome]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  ActionOutcome copyWith({
    int? recordId,
    int? revision,
    String? message,
  }) {
    return ActionOutcome(
      recordId: recordId ?? this.recordId,
      revision: revision ?? this.revision,
      message: message ?? this.message,
    );
  }
}
