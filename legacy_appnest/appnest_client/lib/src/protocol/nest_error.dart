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

abstract class NestError
    implements
        _isc.SerializableException,
        _isc.SerializableModel,
        _isc.ProtocolSerialization {
  NestError._({
    required this.category,
    required this.message,
  });

  factory NestError({
    required String category,
    required String message,
  }) = _NestErrorImpl;

  factory NestError.fromJson(Map<String, dynamic> jsonSerialization) {
    return NestError(
      category: jsonSerialization['category'] as String,
      message: jsonSerialization['message'] as String,
    );
  }

  String category;

  String message;

  /// Returns a shallow copy of this [NestError]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  NestError copyWith({
    String? category,
    String? message,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'NestError',
      'category': category,
      'message': message,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'NestError',
      'category': category,
      'message': message,
    };
  }

  @override
  String toString() {
    return 'NestError(category: $category, message: $message)';
  }
}

class _NestErrorImpl extends NestError {
  _NestErrorImpl({
    required String category,
    required String message,
  }) : super._(
         category: category,
         message: message,
       );

  /// Returns a shallow copy of this [NestError]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  NestError copyWith({
    String? category,
    String? message,
  }) {
    return NestError(
      category: category ?? this.category,
      message: message ?? this.message,
    );
  }
}
