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

abstract class NestWorkerFutureCallExecuteModel
    implements _is.SerializableModel, _is.ProtocolSerialization {
  NestWorkerFutureCallExecuteModel._({required this.runId});

  factory NestWorkerFutureCallExecuteModel({required int runId}) =
      _NestWorkerFutureCallExecuteModelImpl;

  factory NestWorkerFutureCallExecuteModel.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return NestWorkerFutureCallExecuteModel(
      runId: jsonSerialization['runId'] as int,
    );
  }

  int runId;

  /// Returns a shallow copy of this [NestWorkerFutureCallExecuteModel]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  NestWorkerFutureCallExecuteModel copyWith({int? runId});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'NestWorkerFutureCallExecuteModel',
      'runId': runId,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {};
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _NestWorkerFutureCallExecuteModelImpl
    extends NestWorkerFutureCallExecuteModel {
  _NestWorkerFutureCallExecuteModelImpl({required int runId})
    : super._(runId: runId);

  /// Returns a shallow copy of this [NestWorkerFutureCallExecuteModel]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  NestWorkerFutureCallExecuteModel copyWith({int? runId}) {
    return NestWorkerFutureCallExecuteModel(runId: runId ?? this.runId);
  }
}
