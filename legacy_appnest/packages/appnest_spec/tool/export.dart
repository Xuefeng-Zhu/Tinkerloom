import 'dart:io';
import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';

void main() {
  Directory('schema').createSync(recursive: true);
  Directory('fixtures').createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  File('schema/appspec-v1.schema.json')
      .writeAsStringSync('${encoder.convert(appSpecSchema())}\n');
  for (final e in starterTemplates().entries) {
    File('fixtures/${e.key}.json')
        .writeAsStringSync('${encoder.convert(e.value.toJson())}\n');
  }
  final unsupported = starterTemplates()['reading']!.toJson();
  (unsupported['requires'] as List).add('payments.charge.v1');
  File('fixtures/unsupported.json')
      .writeAsStringSync('${encoder.convert(unsupported)}\n');
}
