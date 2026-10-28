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

abstract class InboxItem
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  InboxItem._({
    required this.id,
    required this.appId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.recordId,
    this.collectionId,
  });

  factory InboxItem({
    required int id,
    required int appId,
    required String title,
    required String body,
    required DateTime createdAt,
    required bool isRead,
    int? recordId,
    String? collectionId,
  }) = _InboxItemImpl;

  factory InboxItem.fromJson(Map<String, dynamic> jsonSerialization) {
    return InboxItem(
      id: jsonSerialization['id'] as int,
      appId: jsonSerialization['appId'] as int,
      title: jsonSerialization['title'] as String,
      body: jsonSerialization['body'] as String,
      createdAt: _isc.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      isRead: _isc.BoolJsonExtension.fromJson(jsonSerialization['isRead']),
      recordId: jsonSerialization['recordId'] as int?,
      collectionId: jsonSerialization['collectionId'] as String?,
    );
  }

  int id;

  int appId;

  String title;

  String body;

  DateTime createdAt;

  bool isRead;

  int? recordId;

  String? collectionId;

  /// Returns a shallow copy of this [InboxItem]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  InboxItem copyWith({
    int? id,
    int? appId,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? isRead,
    int? recordId,
    String? collectionId,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'InboxItem',
      'id': id,
      'appId': appId,
      'title': title,
      'body': body,
      'createdAt': createdAt.toJson(),
      'isRead': isRead,
      if (recordId != null) 'recordId': recordId,
      if (collectionId != null) 'collectionId': collectionId,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'InboxItem',
      'id': id,
      'appId': appId,
      'title': title,
      'body': body,
      'createdAt': createdAt.toJson(),
      'isRead': isRead,
      if (recordId != null) 'recordId': recordId,
      if (collectionId != null) 'collectionId': collectionId,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _InboxItemImpl extends InboxItem {
  _InboxItemImpl({
    required int id,
    required int appId,
    required String title,
    required String body,
    required DateTime createdAt,
    required bool isRead,
    int? recordId,
    String? collectionId,
  }) : super._(
         id: id,
         appId: appId,
         title: title,
         body: body,
         createdAt: createdAt,
         isRead: isRead,
         recordId: recordId,
         collectionId: collectionId,
       );

  /// Returns a shallow copy of this [InboxItem]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  InboxItem copyWith({
    int? id,
    int? appId,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? isRead,
    Object? recordId = _Undefined,
    Object? collectionId = _Undefined,
  }) {
    return InboxItem(
      id: id ?? this.id,
      appId: appId ?? this.appId,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      recordId: recordId is int? ? recordId : this.recordId,
      collectionId: collectionId is String? ? collectionId : this.collectionId,
    );
  }
}
