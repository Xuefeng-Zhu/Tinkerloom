// Separate post-hoc diagnostic. No live calls or scored artifact changes.
import 'dart:convert';
import 'dart:io';

import 'package:appnest_server/src/modules/builder/creation_compiler.dart';
import 'package:appnest_server/src/modules/builder/generation_quality.dart';
import 'package:appnest_server/src/modules/builder/generation_requirements.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:crypto/crypto.dart';

String explain(Object e) => e is SpecException ? e.message : '$e';

void main() {
  const directory = 'output/nvidia-free-model-eval';
  final bytes = File('$directory/checkpoint.json').readAsBytesSync();
  final checkpoint = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  for (final entry in (checkpoint['source']['files'] as Map).entries) {
    if (sha256
            .convert(File(entry.key as String).readAsBytesSync())
            .toString() !=
        entry.value) {
      throw StateError('Frozen source mismatch: ${entry.key}');
    }
  }
  final operation = (checkpoint['operations'] as List).singleWhere(
    (o) => o['model'] == 'z-ai/glm-5.3' && o['case'] == 'create-multistep-form',
  ) as Map;
  final scenario = nemotronScenarios().singleWhere(
    (s) => s.id == 'create-multistep-form',
  );
  final rows = <Map<String, dynamic>>[];
  for (final attempt in operation['attempts'] as List) {
    final raw = attempt['syntheticResponse'];
    if (raw is! String) continue;
    final output = parseAiOutput(raw);
    final original = compileGeneratedCreation(
      jsonEncode(output),
      rawOutput: raw,
    );
    final row = <String, dynamic>{
      'attempt': attempt['number'],
      'responseSha256': sha256.convert(utf8.encode(raw)).toString(),
      'strictParserPass': false,
      'productionChecksPass': false,
      'fixedAssertionsPass': false,
      'compilerAddedCapabilities': original.toJson()['addedCapabilities'],
      'fixedAssertionsPassAfterDiagnosticOnlyExplicitImageControl': false,
    };
    rows.add(row);
    AppSpec.parse(jsonEncode(output));
    row['strictParserPass'] = true;
    validateGeneratedExperience(original.spec);
    GenerationRequirements.fromRequest(scenario.prompt).validate(original.spec);
    row['productionChecksPass'] = true;
    try {
      scenario.validate(output, original.spec);
      row['fixedAssertionsPass'] = true;
    } catch (e) {
      row['fixedAssertionDiagnostic'] = explain(e);
    }
    final changed = jsonDecode(jsonEncode(output)) as Map<String, dynamic>;
    final image =
        (changed['collections'] as List)
                .expand((c) => c['fields'] as List)
                .singleWhere((f) => f['type'] == 'image')
            as Map;
    var count = 0;
    for (final view in changed['views'] as List) {
      if (view['type'] != 'form') continue;
      final options =
          view.putIfAbsent('options', () => <String, dynamic>{}) as Map;
      final controls =
          options.putIfAbsent('controls', () => <dynamic>[]) as List;
      controls.add({'fieldId': image['id'], 'control': 'imageUpload'});
      count++;
    }
    row['diagnosticOnlyExplicitImageControlInsertions'] = count;
    try {
      final hypothetical = AppSpec.parse(jsonEncode(changed));
      scenario.validate(changed, hypothetical);
      row['fixedAssertionsPassAfterDiagnosticOnlyExplicitImageControl'] = true;
    } catch (e) {
      row['remainingDiagnosticAfterExplicitImageControl'] = explain(e);
    }
  }
  final result = {
    'label': 'POSTHOC OFFLINE GLM MULTISTEP ASSERTION DIAGNOSTIC',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'inputCheckpointSha256': sha256.convert(bytes).toString(),
    'inputCheckpointUpdatedAt': checkpoint['updatedAt'],
    'inputCheckpointStatus': checkpoint['status'],
    'runFingerprint': checkpoint['runFingerprint'],
    'sourceMatchesScoredManifest': true,
    'primaryScoresChanged': false,
    'liveCallsMade': false,
    'operationStatus': operation['status'],
    'attempts': rows,
    'rendererSource': {
      'typeDispatch': 'packages/appnest_renderer/lib/src/editor.dart:417',
      'imageControl': 'packages/appnest_renderer/lib/src/editor.dart:799',
      'adapterUpload': 'packages/appnest_renderer/lib/src/editor.dart:850',
    },
    'caveat':
        'The one-entry in-memory insertion only isolates the failing fixed '
        'assertion; it is not production compilation, a new model response, a '
        'score correction, or renderer/device/upload execution evidence.',
  };
  File('$directory/posthoc-offline-glm-multistep-assertion.json')
      .writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
  final markdown = StringBuffer(
    '# Posthoc offline GLM multistep assertion diagnostic\n\n'
    'Generated: ${result['generatedAt']}. Input checkpoint updated: '
    '${checkpoint['updatedAt']} (${checkpoint['status']}). '
    'SHA256 `${result['inputCheckpointSha256']}`. '
    'Run `${checkpoint['runFingerprint']}`.\n\n'
    'Every scored source hash matched the checkpoint manifest. No provider calls, '
    'checkpoint writes, scored source edits or primary score changes were made.\n\n'
    '`z-ai/glm-5.3` / `create-multistep-form` remains **${operation['status']}** '
    'in the frozen primary benchmark. Only saved responses are replayed below; '
    'attempt 2 timed out. Production checks include strict AppSpec parsing, '
    'required-capability compilation, generated-experience validation and '
    'request-derived GenerationRequirements.\n\n'
    '| Attempt | Strict parse | Production checks | Added capabilities | Fixed assertions | Fixed assertions after diagnostic-only explicit image control |\n'
    '| --- | --- | --- | --- | --- | --- |\n',
  );
  for (final row in rows) {
    markdown.writeln(
      '| ${row['attempt']} | ${row['strictParserPass']} | '
      '${row['productionChecksPass']} | ${jsonEncode(row['compilerAddedCapabilities'])} | '
      '${row['fixedAssertionsPass']} | '
      '${row['fixedAssertionsPassAfterDiagnosticOnlyExplicitImageControl']} |',
    );
  }
  markdown.writeln(
    '\nThe fixed scenario requires an explicit `imageUpload` control entry on '
    'the image field. The isolated in-memory diagnostic adds only that entry. '
    'Its results do not amend the responses or primary scores.\n\n'
    'Renderer source dispatches every image field to `_imageControl` before '
    'consulting its explicit control kind '
    '(`packages/appnest_renderer/lib/src/editor.dart:417`). That widget presents '
    'Choose/Replace image (`:799`) and calls the adapter\'s `uploadImage` method '
    '(`:850`). The missing explicit configuration is therefore not source-level '
    'evidence that the typed image upload UI would be absent. The scenario '
    'assertion is stricter than the renderer\'s default image behavior.\n\n'
    '${result['caveat']} No rendered screen, authenticated asset upload, '
    'persistence or device behavior was verified. The JSON records response '
    'hashes and per-attempt results; `offline_glm_multistep_diagnostic.dart` '
    'reproduces this check from the local saved checkpoint.\n',
  );
  File('$directory/posthoc-offline-glm-multistep-assertion.md')
      .writeAsStringSync(markdown.toString());
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
}
