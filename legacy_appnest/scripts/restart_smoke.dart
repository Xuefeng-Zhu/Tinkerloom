import 'dart:io';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.path;
  final tag = DateTime.now().microsecondsSinceEpoch.toString();
  for (final scenario in ['claimant', 'planner']) {
    for (final phase in ['write', 'read']) {
      final process = await Process.start(
        'dart',
        ['--suppress-analytics', 'run', 'bin/restart_probe.dart'],
        workingDirectory: '$root/appnest_server',
        environment: {
          'APPNEST_RESTART_TAG': tag,
          'APPNEST_RESTART_PHASE': phase,
          'APPNEST_RESTART_SCENARIO': scenario,
        },
        mode: ProcessStartMode.inheritStdio,
      );
      final code = await process.exitCode;
      if (code != 0) {
        exitCode = code;
        return;
      }
    }
  }
  stdout.writeln(
    'PASS: claimant and owner reminders recovered across independent processes; completed tasks stayed suppressed without duplicate notifications.',
  );
}
