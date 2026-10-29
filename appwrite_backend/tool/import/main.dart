// Local files only. Do not add an operational network/DB writer to this CLI.
import 'dart:convert';
import 'dart:io' show File, FileSystemException, stdout, stderr, exitCode;
import 'engine.dart';
import 'format.dart';
import 'replay.dart';

const usage =
    'dart run tool/import/main.dart --source FILE --mapping FILE '
    '[--report NEW_FILE] [--simulate N --ledger-out NEW_FILE [--resume FILE]]';

List<int> readBounded(String path, int limit) {
  final file = File(path);
  if (file.lengthSync() > limit) bad('file_size_limit', 'input');
  final bytes = file.readAsBytesSync();
  if (bytes.length > limit) bad('file_size_limit', 'input');
  return bytes;
}

void writeNew(String path, Object? value) {
  // Never overwrite input, a previous failure report, or a ledger. Operators
  // choose a new private output path; this is not a secure-file-vault claim.
  final file = File(path)..createSync(exclusive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    flush: true,
  );
}

void main(List<String> args) {
  try {
    final options = <String, String>{};
    const allowed = {
      '--source',
      '--mapping',
      '--report',
      '--simulate',
      '--resume',
      '--ledger-out',
      '--worksheet',
    };
    for (var i = 0; i < args.length; i += 2) {
      if (!allowed.contains(args[i]) ||
          i + 1 >= args.length ||
          args[i + 1].startsWith('--') ||
          options.containsKey(args[i])) {
        bad('usage', 'arguments');
      }
      options[args[i]] = args[i + 1];
    }
    if (options.containsKey('--worksheet')) {
      if (options.length != 2 || !options.containsKey('--source'))
        bad('usage', 'arguments');
      final worksheet = identityWorksheet(
        readBounded(options['--source']!, 33554432),
      );
      writeNew(options['--worksheet']!, worksheet);
      stdout.writeln(
        jsonEncode({
          'mode': 'offline_identity_worksheet',
          'liveWrites': 0,
          'unresolvedAccounts': (worksheet['accounts'] as List).length,
          'unresolvedWorkspaces': (worksheet['workspaces'] as List).length,
          'sourceSha256': worksheet['sourceSha256'],
        }),
      );
      return;
    }
    if (!options.containsKey('--source') ||
        !options.containsKey('--mapping') ||
        options.containsKey('--simulate') !=
            options.containsKey('--ledger-out') ||
        options.containsKey('--resume') && !options.containsKey('--simulate'))
      bad('usage', 'arguments');
    final source = readBounded(options['--source']!, 33554432);
    final mapping = readBounded(options['--mapping']!, 4194304);
    final plan = planImport(source, mapping);
    final report = plan.report();
    if (options['--simulate'] != null) {
      final count = int.tryParse(options['--simulate']!);
      if (count == null || count < 1 || count > 10000)
        bad('usage', 'arguments');
      final simulation = Simulation(
        plan,
        resume: options['--resume'] == null
            ? null
            : decodeDocument(
                readBounded(options['--resume']!, 33554432),
                'ledger',
              ),
      );
      final advanced = simulation.advance(maxOperations: count);
      writeNew(options['--ledger-out']!, simulation.ledger);
      report['simulation'] = {
        'advanced': advanced,
        'confirmed': simulation.confirmed,
        'complete': simulation.complete,
        'rowCount': simulation.destination.count,
        'rowSha256': simulation.destination.checksum,
        'liveWrites': 0,
      };
    }
    if (options['--report'] != null) writeNew(options['--report']!, report);
    // Bound stdout and never print private data, names, tokens or source paths.
    stdout.writeln(
      jsonEncode({
        'mode': 'offline_dry_run',
        'cutoverReady': false,
        'liveWrites': 0,
        'validForSimulation': plan.validForSimulation,
        'sourceSha256': plan.sourceSha256,
        'mappingSha256': plan.mappingSha256,
        'targetSha256': plan.targetSha256,
        'planSha256': plan.planSha256,
        'sourceCounts': plan.sourceCounts,
        'plannedOperations': plan.rows.length,
        'quarantinedRows': plan.quarantine.length,
        'requiredIssues': plan.issues.where((i) => i.required).length,
        'issueCodes': (plan.issues.map((i) => i.code).toSet().toList()..sort()),
        if (report['simulation'] != null) 'simulation': report['simulation'],
      }),
    );
    if (!plan.validForSimulation) exitCode = 2;
  } on ImportProblem catch (e) {
    stderr.writeln(
      jsonEncode({
        'mode': 'offline_dry_run',
        'cutoverReady': false,
        'liveWrites': 0,
        'error': e.code,
        'path': e.path,
      }),
    );
    if (e.code == 'usage') stderr.writeln(usage);
    exitCode = e.code == 'usage' ? 64 : 65;
  } on FileSystemException {
    stderr.writeln(
      '{"mode":"offline_dry_run","liveWrites":0,"error":"local_file_error"}',
    );
    exitCode = 74;
  }
}
