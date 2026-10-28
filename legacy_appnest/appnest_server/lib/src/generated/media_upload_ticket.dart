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

abstract class MediaUploadTicket
    implements _is.SerializableModel, _is.ProtocolSerialization {
  MediaUploadTicket._({
    required this.assetId,
    required this.uploadDescription,
  });

  factory MediaUploadTicket({
    required String assetId,
    required String uploadDescription,
  }) = _MediaUploadTicketImpl;

  factory MediaUploadTicket.fromJson(Map<String, dynamic> jsonSerialization) {
    return MediaUploadTicket(
      assetId: jsonSerialization['assetId'] as String,
      uploadDescription: jsonSerialization['uploadDescription'] as String,
    );
  }

  String assetId;

  String uploadDescription;

  /// Returns a shallow copy of this [MediaUploadTicket]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  MediaUploadTicket copyWith({
    String? assetId,
    String? uploadDescription,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MediaUploadTicket',
      'assetId': assetId,
      'uploadDescription': uploadDescription,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'MediaUploadTicket',
      'assetId': assetId,
      'uploadDescription': uploadDescription,
    };
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _MediaUploadTicketImpl extends MediaUploadTicket {
  _MediaUploadTicketImpl({
    required String assetId,
    required String uploadDescription,
  }) : super._(
         assetId: assetId,
         uploadDescription: uploadDescription,
       );

  /// Returns a shallow copy of this [MediaUploadTicket]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  MediaUploadTicket copyWith({
    String? assetId,
    String? uploadDescription,
  }) {
    return MediaUploadTicket(
      assetId: assetId ?? this.assetId,
      uploadDescription: uploadDescription ?? this.uploadDescription,
    );
  }
}
