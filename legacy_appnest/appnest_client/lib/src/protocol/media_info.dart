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

abstract class MediaInfo
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  MediaInfo._({
    required this.assetId,
    required this.contentType,
    required this.width,
    required this.height,
    required this.byteLength,
  });

  factory MediaInfo({
    required String assetId,
    required String contentType,
    required int width,
    required int height,
    required int byteLength,
  }) = _MediaInfoImpl;

  factory MediaInfo.fromJson(Map<String, dynamic> jsonSerialization) {
    return MediaInfo(
      assetId: jsonSerialization['assetId'] as String,
      contentType: jsonSerialization['contentType'] as String,
      width: jsonSerialization['width'] as int,
      height: jsonSerialization['height'] as int,
      byteLength: jsonSerialization['byteLength'] as int,
    );
  }

  String assetId;

  String contentType;

  int width;

  int height;

  int byteLength;

  /// Returns a shallow copy of this [MediaInfo]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  MediaInfo copyWith({
    String? assetId,
    String? contentType,
    int? width,
    int? height,
    int? byteLength,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'MediaInfo',
      'assetId': assetId,
      'contentType': contentType,
      'width': width,
      'height': height,
      'byteLength': byteLength,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'MediaInfo',
      'assetId': assetId,
      'contentType': contentType,
      'width': width,
      'height': height,
      'byteLength': byteLength,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _MediaInfoImpl extends MediaInfo {
  _MediaInfoImpl({
    required String assetId,
    required String contentType,
    required int width,
    required int height,
    required int byteLength,
  }) : super._(
         assetId: assetId,
         contentType: contentType,
         width: width,
         height: height,
         byteLength: byteLength,
       );

  /// Returns a shallow copy of this [MediaInfo]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  MediaInfo copyWith({
    String? assetId,
    String? contentType,
    int? width,
    int? height,
    int? byteLength,
  }) {
    return MediaInfo(
      assetId: assetId ?? this.assetId,
      contentType: contentType ?? this.contentType,
      width: width ?? this.width,
      height: height ?? this.height,
      byteLength: byteLength ?? this.byteLength,
    );
  }
}
