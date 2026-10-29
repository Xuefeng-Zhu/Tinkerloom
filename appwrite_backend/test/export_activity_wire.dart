import 'dart:convert';
import 'dart:io';
import 'activity_test.dart' show activityWire;

Future<void> main(List<String> args) async {
  if (args.length != 1)
    throw ArgumentError('One fixture output path is required');
  final wire = await activityWire();
  File(
    args.single,
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(wire)}\n');
  stdout.writeln(
    jsonEncode({'status': 'passed', 'fixturePages': 2, 'cloudRequests': 0}),
  );
}
