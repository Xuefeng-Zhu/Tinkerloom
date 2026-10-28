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

abstract class ActivityItem
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  ActivityItem._({
    required this.id,
    required this.action,
    required this.createdAt,
    required this.status,
  });

  factory ActivityItem({
    required int id,
    required String action,
    required DateTime createdAt,
    required String status,
  }) = _ActivityItemImpl;

  factory ActivityItem.fromJson(Map<String, dynamic> jsonSerialization) {
    return ActivityItem(
      id: jsonSerialization['id'] as int,
      action: jsonSerialization['action'] as String,
      createdAt: _isc.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      status: jsonSerialization['status'] as String,
    );
  }

  int id;

  String action;

  DateTime createdAt;

  String status;

  /// Returns a shallow copy of this [ActivityItem]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  ActivityItem copyWith({
    int? id,
    String? action,
    DateTime? createdAt,
    String? status,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'ActivityItem',
      'id': id,
      'action': action,
      'createdAt': createdAt.toJson(),
      'status': status,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'ActivityItem',
      'id': id,
      'action': action,
      'createdAt': createdAt.toJson(),
      'status': status,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _ActivityItemImpl extends ActivityItem {
  _ActivityItemImpl({
    required int id,
    required String action,
    required DateTime createdAt,
    required String status,
  }) : super._(
         id: id,
         action: action,
         createdAt: createdAt,
         status: status,
       );

  /// Returns a shallow copy of this [ActivityItem]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  ActivityItem copyWith({
    int? id,
    String? action,
    DateTime? createdAt,
    String? status,
  }) {
    return ActivityItem(
      id: id ?? this.id,
      action: action ?? this.action,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }
}
