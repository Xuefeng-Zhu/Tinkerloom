import 'dart:convert';

import 'errors.dart';

const definitionBytes = 16384;
const valuesBytes = 16384;
final _fieldId = RegExp(r'^[a-z][a-zA-Z0-9_]{0,31}$');

Map<String, dynamic> jsonObject(Object? value, String error) {
  if (value is! Map<String, dynamic>) throw ServiceException(error, 400);
  return value;
}

String boundedText(Object? value, int maximum, String error,
    {bool empty = false}) {
  if (value is! String) throw ServiceException(error, 400);
  final normalized = value.trim();
  if ((!empty && normalized.isEmpty) || normalized.length > maximum) {
    throw ServiceException(error, 400);
  }
  return normalized;
}

void _keys(Map<String, dynamic> value, Set<String> allowed, String error) {
  if (value.keys.any((key) => !allowed.contains(key)))
    throw ServiceException(error, 400);
}

Map<String, dynamic> validateDefinition(Object? value) {
  const error = 'invalid_definition';
  final source = jsonObject(value, error);
  _keys(source, {'title', 'description', 'primaryFieldId', 'fields'}, error);
  final title = boundedText(source['title'], 80, error);
  final description = source['description'];
  if (description is! String || description.length > 240)
    throw const ServiceException(error, 400);
  final sourceFields = source['fields'];
  if (sourceFields is! List || sourceFields.isEmpty || sourceFields.length > 10)
    throw const ServiceException(error, 400);
  final ids = <String>{};
  final fields = <Map<String, dynamic>>[];
  for (final raw in sourceFields) {
    final field = jsonObject(raw, error);
    _keys(field, {'id', 'label', 'kind', 'required', 'options'}, error);
    final id = field['id'];
    final kind = field['kind'];
    if (id is! String ||
        !_fieldId.hasMatch(id) ||
        !ids.add(id) ||
        !{'text', 'longText', 'boolean', 'choice'}.contains(kind))
      throw const ServiceException(error, 400);
    if (field.containsKey('required') && field['required'] is! bool)
      throw const ServiceException(error, 400);
    final normalized = <String, dynamic>{
      'id': id,
      'label': boundedText(field['label'], 64, error),
      'kind': kind
    };
    if (field['required'] == true) normalized['required'] = true;
    if (kind == 'choice') {
      final options = field['options'];
      if (options is! List || options.isEmpty || options.length > 12)
        throw const ServiceException(error, 400);
      final choices =
          options.map((option) => boundedText(option, 64, error)).toList();
      if (choices.toSet().length != choices.length)
        throw const ServiceException(error, 400);
      normalized['options'] = choices;
    } else if (field.containsKey('options')) {
      throw const ServiceException(error, 400);
    }
    fields.add(normalized);
  }
  final primary = source['primaryFieldId'];
  if (!fields.any((field) =>
      field['id'] == primary &&
      field['kind'] == 'text' &&
      field['required'] == true)) throw const ServiceException(error, 400);
  final result = <String, dynamic>{
    'title': title,
    'description': description,
    'primaryFieldId': primary,
    'fields': fields
  };
  if (utf8.encode(jsonEncode(result)).length > definitionBytes)
    throw const ServiceException(error, 400);
  return result;
}

Map<String, dynamic> validateValues(
    Map<String, dynamic> definition, Object? input) {
  const error = 'invalid_values';
  final values = jsonObject(input, error);
  final fields = (definition['fields'] as List).cast<Map<String, dynamic>>();
  _keys(values, fields.map((field) => field['id'] as String).toSet(), error);
  final result = <String, dynamic>{};
  for (final field in fields) {
    final id = field['id'] as String;
    final value = values[id];
    final kind = field['kind'];
    if (kind == 'boolean') {
      if (values.containsKey(id) && value is! bool)
        throw const ServiceException(error, 400);
      result[id] = value ?? false;
    } else if (!values.containsKey(id) || value == '') {
      if (field['required'] == true) throw const ServiceException(error, 400);
      result[id] = '';
    } else {
      final text = boundedText(value, kind == 'longText' ? 4000 : 200, error,
          empty: field['required'] != true);
      if (kind == 'choice' &&
          text.isNotEmpty &&
          !(field['options'] as List).contains(text))
        throw const ServiceException(error, 400);
      result[id] = text;
    }
  }
  if (utf8.encode(jsonEncode(result)).length > valuesBytes)
    throw const ServiceException(error, 400);
  return result;
}

void requireCompatible(
    Map<String, dynamic> previous, Map<String, dynamic> next) {
  if (previous['primaryFieldId'] != next['primaryFieldId'])
    throw const ServiceException('incompatible_definition', 409);
  final oldFields = (previous['fields'] as List).cast<Map<String, dynamic>>();
  final newFields = {
    for (final field in (next['fields'] as List).cast<Map<String, dynamic>>())
      field['id']: field
  };
  for (final old in oldFields) {
    final current = newFields[old['id']];
    if (current == null ||
        current['kind'] != old['kind'] ||
        (current['required'] == true) != (old['required'] == true))
      throw const ServiceException('incompatible_definition', 409);
    if (old['kind'] == 'choice' &&
        (old['options'] as List)
            .any((option) => !(current['options'] as List).contains(option)))
      throw const ServiceException('incompatible_definition', 409);
  }
  final oldIds = oldFields.map((field) => field['id']).toSet();
  if (newFields.values.any(
      (field) => !oldIds.contains(field['id']) && field['required'] == true))
    throw const ServiceException('incompatible_definition', 409);
}

String canonicalJson(Object? value) {
  Object? canonical(Object? item) {
    if (item is Map<String, dynamic>) {
      final keys = item.keys.toList()..sort();
      return {for (final key in keys) key: canonical(item[key])};
    }
    if (item is List) return item.map(canonical).toList();
    return item;
  }

  return jsonEncode(canonical(value));
}
