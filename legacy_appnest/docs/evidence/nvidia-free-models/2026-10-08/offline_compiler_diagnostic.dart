// Post-hoc, offline compiler-assisted diagnostics. No provider calls, credentials,
// scored-source changes, or checkpoint writes. Run from repository root:
// dart --packages=.dart_tool/package_config.json output/nvidia-free-model-eval/offline_compiler_diagnostic.dart [CHECKPOINT [OUTPUT_PREFIX]]
import 'dart:convert';
import 'dart:io';

import 'package:appnest_server/src/modules/builder/creation_compiler.dart';
import 'package:appnest_server/src/modules/builder/generation_quality.dart';
import 'package:appnest_server/src/modules/builder/generation_requirements.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:crypto/crypto.dart';

String explain(Object error) => switch (error) {
  SpecException() => error.message,
  AiResponseException() => '${error.kind}: ${error.message}',
  _ => 'Unexpected ${error.runtimeType}',
};

Future<void> main(List<String> args) async {
  final input = args.isEmpty
      ? 'output/nvidia-free-model-eval/checkpoint.json'
      : args.first;
  final prefix = args.length < 2
      ? '${File(input).parent.path}/posthoc-offline-compiler-diagnostic'
      : args[1];
  if (File(input).absolute.path == File('$prefix.json').absolute.path) {
    throw ArgumentError('Diagnostic output must not replace the checkpoint.');
  }
  final bytes = await File(input).readAsBytes();
  final checkpoint = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final source = checkpoint['source'] as Map;
  final files = source['files'] as Map;
  final mismatched = <String>[];
  for (final item in files.entries) {
    final file = File(item.key as String);
    if (!await file.exists() ||
        sha256.convert(await file.readAsBytes()).toString() != item.value) {
      mismatched.add(item.key as String);
    }
  }
  if (mismatched.isNotEmpty) {
    throw StateError('Scored source changed: ${mismatched.join(', ')}');
  }
  final descriptors = {for (final item in nemotronScenarios()) item.id: item};
  final savedScenarios = {
    for (final item in checkpoint['scenarios'] as List)
      item['id'] as String: item as Map,
  };
  final rows = <Map<String, dynamic>>[];
  final creationOperations = (checkpoint['operations'] as List)
      .where((operation) => operation['operation'] == 'create')
      .cast<Map<String, dynamic>>()
      .toList();
  var noResponse = 0;
  for (final operation in checkpoint['operations'] as List) {
    if (operation['operation'] != 'create') continue;
    final id = operation['case'] as String;
    final scenario = descriptors[id]!;
    if (canonicalJson(scenario.toJson()) != canonicalJson(savedScenarios[id])) {
      throw StateError('Saved scenario differs from local source: $id');
    }
    for (final attempt in operation['attempts'] as List) {
      final raw = attempt['syntheticResponse'];
      if (raw is! String) {
        noResponse++;
        continue;
      }
      final row = <String, dynamic>{
        'model': operation['model'],
        'case': id,
        'attempt': attempt['number'],
        'rawResponseSha256': sha256.convert(utf8.encode(raw)).toString(),
        'primarySuccess': attempt['success'],
        'primaryKind': attempt['kind'],
        'primaryDiagnostic': attempt['diagnostic'],
        'strictParserPass': false,
        'compilerPass': false,
        'productionChecksPass': false,
        'scenarioAssertionsPass': false,
      };
      rows.add(row);
      Map<String, dynamic> output;
      try {
        output = parseAiOutput(raw);
      } catch (error) {
        row['compilerDiagnostic'] = explain(error);
        continue;
      }
      try {
        AppSpec.parse(jsonEncode(output));
        row['strictParserPass'] = true;
      } catch (error) {
        row['strictParserDiagnostic'] = explain(error);
      }
      AppSpec candidate;
      try {
        final compilation = compileGeneratedCreation(
          jsonEncode(output),
          rawOutput: raw,
        );
        row['compilerPass'] = true;
        row['compilation'] = compilation.toJson();
        candidate = compilation.spec;
        if (candidate.appearance == null) {
          candidate = candidate.patch({
            'type': 'SetAppearance',
            'appearance': {'style': 'clean'},
          }, () => throw StateError('No ID allocation'));
        }
        row['normalizedCandidateHash'] = candidate.hash;
      } catch (error) {
        row['compilerDiagnostic'] = explain(error);
        continue;
      }
      final productionErrors = <String>[];
      try {
        validateGeneratedExperience(candidate);
      } catch (error) {
        productionErrors.add(explain(error));
      }
      try {
        GenerationRequirements.fromRequest(scenario.prompt).validate(candidate);
      } catch (error) {
        productionErrors.add(explain(error));
      }
      row['productionChecksPass'] = productionErrors.isEmpty;
      if (productionErrors.isNotEmpty) {
        row['productionDiagnostics'] = productionErrors;
      }
      try {
        scenario.validate(output, candidate);
        row['scenarioAssertionsPass'] = true;
      } catch (error) {
        row['scenarioDiagnostic'] = explain(error);
      }
    }
  }
  for (final row in rows) {
    row['compilerFullPass'] =
        row['compilerPass'] == true &&
        row['productionChecksPass'] == true &&
        row['scenarioAssertionsPass'] == true;
    row['strictRawFullPass'] =
        row['strictParserPass'] == true && row['compilerFullPass'] == true;
    row['compilationOnlyRepair'] =
        row['strictParserPass'] != true && row['compilerPass'] == true;
    row['fullPassRescuedByCompiler'] =
        row['strictParserPass'] != true && row['compilerFullPass'] == true;
  }
  final operationRows = <Map<String, dynamic>>[
    for (final operation in creationOperations)
      {
        'model': operation['model'],
        'case': operation['case'],
        'status': operation['status'],
        'primarySuccess': operation['success'] == true,
        'attempts': (operation['attempts'] as List).length,
        for (final key in [
          'strictParserPass',
          'compilerPass',
          'productionChecksPass',
          'scenarioAssertionsPass',
          'strictRawFullPass',
          'compilerFullPass',
          'fullPassRescuedByCompiler',
        ])
          key: rows.any(
            (row) =>
                row['model'] == operation['model'] &&
                row['case'] == operation['case'] &&
                row[key] == true,
          ),
      },
  ];
  final byModel = <Map<String, dynamic>>[
    for (final model in checkpoint['models'] as List)
      {
        'model': model,
        'responseAttempts': rows.where((row) => row['model'] == model).length,
        'plannedOperations': operationRows
            .where((row) => row['model'] == model)
            .length,
        'terminalOperations': operationRows
            .where(
              (row) =>
                  row['model'] == model &&
                  {'passed', 'failed', 'skipped'}.contains(row['status']),
            )
            .length,
        'responsePassCounts': {
          for (final key in [
            'primarySuccess',
            'strictParserPass',
            'compilerPass',
            'productionChecksPass',
            'scenarioAssertionsPass',
            'strictRawFullPass',
            'compilerFullPass',
            'compilationOnlyRepair',
            'fullPassRescuedByCompiler',
          ])
            key: rows
                .where((row) => row['model'] == model && row[key] == true)
                .length,
        },
        'operationPassCounts': {
          for (final key in [
            'primarySuccess',
            'strictParserPass',
            'compilerPass',
            'productionChecksPass',
            'scenarioAssertionsPass',
            'strictRawFullPass',
            'compilerFullPass',
            'fullPassRescuedByCompiler',
          ])
            key: operationRows
                .where((row) => row['model'] == model && row[key] == true)
                .length,
        },
      },
  ];
  final result = <String, dynamic>{
    'diagnosticVersion': 'posthoc-offline-compiler-assisted.v2',
    'benchmarkLabel':
        checkpoint['benchmarkLabel'] ?? 'AppNest model evaluation',
    'provider': checkpoint['provider'],
    'modelFamilies': checkpoint['modelFamilies'],
    'execution': checkpoint['execution'],
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'inputCheckpoint': input,
    'inputCheckpointSha256': sha256.convert(bytes).toString(),
    'inputCheckpointUpdatedAt': checkpoint['updatedAt'],
    'inputCheckpointStatus': checkpoint['status'],
    'runFingerprint': checkpoint['runFingerprint'],
    'sourceMatchesScoredManifest': true,
    'source': source,
    'primaryScoresChanged': false,
    'liveCallsMade': false,
    'scope': 'Saved fresh-create responses only. Replays production required-capability closure and creation checks, then the fixed benchmark assertions. Operation acceptance means at least one observed response passes; response rates exclude transport attempts with no saved response and are not independent trials. Post-hoc diagnosis is not a replacement run: original repair attempts were conditioned on strict-parser diagnostics. No authenticated save, Flutter rendering, reminders, publication, or device behavior is verified.',
    'summary': {
      'responseAttempts': rows.length,
      'noResponseAttemptsExcluded': noResponse,
      'plannedCreationOperations': creationOperations.length,
      'terminalCreationOperations': creationOperations
          .where(
            (row) => {'passed', 'failed', 'skipped'}.contains(row['status']),
          )
          .length,
      for (final key in [
        'strictParserPass',
        'compilerPass',
        'productionChecksPass',
        'scenarioAssertionsPass',
        'strictRawFullPass',
        'compilerFullPass',
        'compilationOnlyRepair',
        'fullPassRescuedByCompiler',
      ])
        key: rows.where((row) => row[key] == true).length,
    },
    'byModel': byModel,
    'operations': operationRows,
    'attempts': rows,
  };
  await File('$prefix.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
  final markdown = StringBuffer(
    '# ${checkpoint['benchmarkLabel'] ?? 'AppNest model evaluation'}: post-hoc offline compiler-assisted diagnostic\n\n'
    'Snapshot: ${checkpoint['updatedAt']} (${checkpoint['status']}). '
    'Run: `${checkpoint['runFingerprint']}`.\n\n'
    'Input checkpoint SHA256: `${result['inputCheckpointSha256']}`.\n\n'
    'Fresh-create saved responses only; primary scores and source were not changed. '
    'All scored source hashes match the checkpoint manifest. No live calls were made.\n\n'
    '${result['scope']}\n\n'
    'Observed response attempts: ${rows.length}; '
    'transport attempts without a response excluded: $noResponse.\n\n',
  );
  String cell(Object? value) =>
      '${value ?? ''}'.replaceAll('|', '\\|').replaceAll('\n', ' ');
  String rate(int count, int total) =>
      '$count/$total (${total == 0 ? 'unknown' : (100 * count / total).toStringAsFixed(1)}%)';
  markdown.writeln(
    'Strict raw full means strict parsing plus production checks and fixed feature assertions. '
    'Compiler full adds only supported missing capability declarations, then applies the same checks.\n\n'
    '| Model | Saved response attempts | Strict schema | Compiler schema | Compiler + production checks | Strict raw full | Compiler full |\n'
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: |',
  );
  for (final model in byModel) {
    final count = model['responsePassCounts'] as Map;
    final total = model['responseAttempts'] as int;
    markdown.writeln(
      '| ${cell(model['model'])} | $total | '
      '${rate(count['strictParserPass'] as int, total)} | '
      '${rate(count['compilerPass'] as int, total)} | '
      '${rate(count['productionChecksPass'] as int, total)} | '
      '${rate(count['strictRawFullPass'] as int, total)} | '
      '${rate(count['compilerFullPass'] as int, total)} |',
    );
  }
  markdown.writeln(
    '\nOperation denominator includes all planned creations; '
    'terminal counts expose incomplete snapshots. Acceptance means any observed attempt passes.\n\n'
    '| Model | Terminal/planned operations | Strict schema | Compiler schema | Compiler + production checks | Strict raw full | Compiler full | Primary scored |\n'
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
  );
  for (final model in byModel) {
    final count = model['operationPassCounts'] as Map;
    final total = model['plannedOperations'] as int;
    markdown.writeln(
      '| ${cell(model['model'])} | ${model['terminalOperations']}/$total | '
      '${rate(count['strictParserPass'] as int, total)} | '
      '${rate(count['compilerPass'] as int, total)} | '
      '${rate(count['productionChecksPass'] as int, total)} | '
      '${rate(count['strictRawFullPass'] as int, total)} | '
      '${rate(count['compilerFullPass'] as int, total)} | '
      '${rate(count['primarySuccess'] as int, total)} |',
    );
  }
  markdown.writeln(
    '\n| Model | Case | Attempt | Strict parse | Compiler | Production checks | Scenario assertions | Remaining diagnostic |\n'
    '| --- | --- | ---: | --- | --- | --- | --- | --- |',
  );
  for (final row in rows) {
    final diagnostic =
        row['compilerDiagnostic'] ??
        row['scenarioDiagnostic'] ??
        row['productionDiagnostics'] ??
        '';
    markdown.writeln(
      '| ${cell(row['model'])} | ${cell(row['case'])} | ${row['attempt']} | '
      '${row['strictParserPass']} | ${row['compilerPass']} | '
      '${row['productionChecksPass']} | ${row['scenarioAssertionsPass']} | '
      '${cell(diagnostic)} |',
    );
  }
  markdown.writeln(
    '\nCapability additions are recorded per attempt in the JSON artifact.',
  );
  await File('$prefix.md').writeAsString(markdown.toString());
  stdout.writeln(jsonEncode(result['summary']));
  for (final model in byModel) stdout.writeln(jsonEncode(model));
}
