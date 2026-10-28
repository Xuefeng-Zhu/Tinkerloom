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

abstract class NestWorkerFutureCallGenerateModel
    implements _is.SerializableModel, _is.ProtocolSerialization {
  NestWorkerFutureCallGenerateModel._({required this.jobId});

  factory NestWorkerFutureCallGenerateModel({required int jobId}) =
      _NestWorkerFutureCallGenerateModelImpl;

  factory NestWorkerFutureCallGenerateModel.fromJson(
    Map<String, dynamic> jsonSerialization,
  ) {
    return NestWorkerFutureCallGenerateModel(
      jobId: jsonSerialization['jobId'] as int,
    );
  }

  int jobId;

  /// Returns a shallow copy of this [NestWorkerFutureCallGenerateModel]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  NestWorkerFutureCallGenerateModel copyWith({int? jobId});
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'NestWorkerFutureCallGenerateModel',
      'jobId': jobId,
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

class _NestWorkerFutureCallGenerateModelImpl
    extends NestWorkerFutureCallGenerateModel {
  _NestWorkerFutureCallGenerateModelImpl({required int jobId})
    : super._(jobId: jobId);

  /// Returns a shallow copy of this [NestWorkerFutureCallGenerateModel]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  NestWorkerFutureCallGenerateModel copyWith({int? jobId}) {
    return NestWorkerFutureCallGenerateModel(jobId: jobId ?? this.jobId);
  }
}
