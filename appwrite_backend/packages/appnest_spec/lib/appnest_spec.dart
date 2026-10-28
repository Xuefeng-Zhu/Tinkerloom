library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

part 'src/spec.dart';
part 'src/appearance.dart';
part 'src/templates.dart';
part 'src/schema.dart';
part 'src/rich_spec.dart';
part 'src/rich_templates.dart';
part 'src/utility_spec.dart';
part 'src/device_spec.dart';
part 'src/utility_templates.dart';

class SpecException implements Exception {
  final String message;
  const SpecException(this.message);
  @override
  String toString() => message;
}

/// Views that can display a newly allocated field through AddField.viewIds.
const fieldBindingViewTypes = {'list', 'table', 'form', 'details'};

class Limits {
  static const definitionBytes = 131072,
      depth = 12,
      collections = 8,
      fields = 40,
      views = 16,
      actions = 32,
      rules = 10,
      pageSize = 100,
      promptBytes = 16384,
      filters = 8,
      generationAttempts = 3,
      automationBatch = 100,
      activationScope = 500,
      notificationFanout = 500,
      invitationsPerDay = 50,
      generationJobsPerDay = 30,
      appsPerWorkspace = 100;
}

String canonicalJson(Object? value) {
  Object? sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sort(v[k])};
    }
    if (v is List) return v.map(sort).toList();
    return v;
  }

  return jsonEncode(sort(value));
}

String hashJson(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

Map<String, dynamic> object(Object? value, String where) {
  if (value is! Map<String, dynamic>)
    throw SpecException('$where must be an object');
  return value;
}

void keys(Map<String, dynamic> value, Set<String> allowed, String where) {
  final extra = value.keys.toSet().difference(allowed);
  if (extra.isNotEmpty)
    throw SpecException('$where: unknown properties ${extra.join(", ")}');
}

String str(Object? value, String where, {int max = 160}) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    throw SpecException(
      '$where must be nonempty text (maximum $max characters)',
    );
  }
  return value;
}

String stableId(Object? value) {
  final result = str(value, 'id', max: 64);
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(result)) {
    throw const SpecException('IDs must be simple stable identifiers');
  }
  return result;
}

List<dynamic> array(Object? value, String where, int max) {
  if (value is! List || value.length > max)
    throw SpecException('$where must be a bounded array');
  return value;
}

void unique(Iterable<String> values, String where) {
  final list = values.toList();
  if (list.toSet().length != list.length)
    throw SpecException('Duplicate IDs in $where');
}
