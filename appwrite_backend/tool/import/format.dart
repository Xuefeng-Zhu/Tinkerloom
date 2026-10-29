// Offline-only format primitives. No I/O, network, database or service imports.
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:appnest_spec/appnest_spec.dart' as spec;

typedef Json = Map<String, dynamic>;

class ImportProblem implements Exception {
  final String code, path;
  const ImportProblem(this.code, this.path);
  @override
  String toString() => '$code at $path';
}

Never bad(String code, String path) => throw ImportProblem(code, path);
String digest(List<int> bytes) => sha256.convert(bytes).toString();
String hash(Object? value) => spec.hashJson(value);
String identity(String kind, List<String> parts) =>
    '$kind${digest(utf8.encode(jsonEncode(parts))).substring(0, 32)}';
Json obj(Object? value, String path) {
  if (value is! Json) bad('object_required', path);
  return value;
}

void shape(
  Json value,
  Set<String> required,
  Set<String> optional,
  String path,
) {
  if (!value.keys.toSet().containsAll(required)) bad('missing_field', path);
  if (value.keys.any((k) => !required.contains(k) && !optional.contains(k))) {
    bad('unknown_field', path);
  }
}

String text(Object? value, String path, {int max = 128}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > max ||
      value.contains(RegExp(r'[\x00-\x1f]')))
    bad('invalid_text', path);
  return value;
}

String oldId(Object? value, String path) {
  final id = text(value, path, max: 19);
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(id) ||
      BigInt.parse(id) > BigInt.parse('9223372036854775807')) {
    bad('invalid_source_id', path);
  }
  return id;
}

String targetId(Object? value, String path) {
  final id = text(value, path, max: 36);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$').hasMatch(id)) {
    bad('invalid_target_id', path);
  }
  return id;
}

String sha(Object? value, String path) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    bad('invalid_sha256', path);
  }
  return value;
}

int integer(Object? value, String path, {int min = 0, int max = 2147483646}) {
  if (value is! int || value < min || value > max) bad('invalid_integer', path);
  return value;
}

bool boolean(Object? value, String path) {
  if (value is! bool) bad('invalid_boolean', path);
  return value;
}

String timestamp(Object? value, String path) {
  // Provider-owned metadata is restricted to losslessly representable UTC
  // milliseconds. AppSpec record timestamps use the richer canonical codec.
  final s = text(value, path, max: 64);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$').hasMatch(s)) {
    bad('metadata_timestamp_requires_utc_milliseconds', path);
  }
  final d = DateTime.tryParse(s);
  if (d == null || d.year < 1 || d.toIso8601String() != s) {
    bad('invalid_timestamp', path);
  }
  return s;
}

List<Json> objects(Object? value, String path, {int max = 100000}) {
  if (value is! List || value.length > max) bad('invalid_array', path);
  return [for (var i = 0; i < value.length; i++) obj(value[i], '$path[$i]')];
}

/// JSON parser rejects duplicate keys before jsonDecode could overwrite them.
/// File byte bounds are enforced before decoding; recursion is capped here.
class StrictJson {
  final String source;
  int at = 0;
  StrictJson(this.source);
  Object? parse() {
    final result = _value(0);
    _space();
    if (at != source.length) bad('invalid_json', r'$');
    return result;
  }

  void _space() {
    while (at < source.length && ' \r\n\t'.contains(source[at])) {
      at++;
    }
  }

  String _string() {
    final start = at++;
    var escaped = false;
    while (at < source.length) {
      final c = source[at++];
      if (!escaped && c == '"') {
        try {
          return jsonDecode(source.substring(start, at)) as String;
        } catch (_) {
          bad('invalid_json', r'$');
        }
      }
      if (!escaped && c == '\\') {
        escaped = true;
      } else {
        escaped = false;
      }
    }
    bad('invalid_json', r'$');
  }

  Object? _value(int depth) {
    if (depth > 64) bad('json_depth_exceeded', r'$');
    _space();
    if (at >= source.length) bad('invalid_json', r'$');
    final c = source[at];
    if (c == '"') return _string();
    if (c == '{') {
      at++;
      _space();
      final result = <String, dynamic>{};
      if (at < source.length && source[at] == '}') {
        at++;
        return result;
      }
      while (true) {
        _space();
        if (at >= source.length || source[at] != '"') bad('invalid_json', r'$');
        final key = _string();
        if (result.containsKey(key)) bad('duplicate_json_key', r'$');
        _space();
        if (at >= source.length || source[at++] != ':')
          bad('invalid_json', r'$');
        result[key] = _value(depth + 1);
        _space();
        if (at >= source.length) bad('invalid_json', r'$');
        final end = source[at++];
        if (end == '}') return result;
        if (end != ',') bad('invalid_json', r'$');
      }
    }
    if (c == '[') {
      at++;
      _space();
      final result = <dynamic>[];
      if (at < source.length && source[at] == ']') {
        at++;
        return result;
      }
      while (true) {
        result.add(_value(depth + 1));
        _space();
        if (at >= source.length) bad('invalid_json', r'$');
        final end = source[at++];
        if (end == ']') return result;
        if (end != ',') bad('invalid_json', r'$');
      }
    }
    final start = at;
    while (at < source.length && !' \r\n\t,]}'.contains(source[at])) {
      at++;
    }
    if (start == at) bad('invalid_json', r'$');
    try {
      final result = jsonDecode(source.substring(start, at));
      if (result is num && !result.isFinite) bad('nonfinite_number', r'$');
      return result;
    } on FormatException {
      bad('invalid_json', r'$');
    }
  }
}

Json decodeDocument(List<int> bytes, String kind, {int maxBytes = 33554432}) {
  if (bytes.isEmpty || bytes.length > maxBytes) bad('file_size_limit', kind);
  try {
    return obj(StrictJson(utf8.decode(bytes)).parse(), kind);
  } on FormatException {
    bad('invalid_utf8', kind);
  }
}
