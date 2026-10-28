// Separate post-hoc diagnostic; no live calls or scored artifact changes.
import 'dart:convert';
import 'dart:io';

import 'package:appnest_server/src/modules/builder/creation_compiler.dart';
import 'package:appnest_server/src/modules/builder/generation_quality.dart';
import 'package:appnest_server/src/modules/builder/generation_requirements.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:crypto/crypto.dart';

String explain(Object e) => switch (e) {
  SpecException() => e.message,
  AiResponseException() => '${e.kind}: ${e.message}',
  _ => '$e',
};

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
    (o) =>
        o['model'] == 'moonshotai/kimi-k3' &&
        o['case'] == 'create-reminders-name',
  ) as Map;
  final scenario = nemotronScenarios().singleWhere(
    (s) => s.id == 'create-reminders-name',
  );
  final requirements = GenerationRequirements.fromRequest(scenario.prompt);
  final rows = <Map<String, dynamic>>[];
  for (final attempt in operation['attempts'] as List) {
    final raw = attempt['syntheticResponse'];
    final row = <String, dynamic>{
      'attempt': attempt['number'],
      'primaryKind': attempt['kind'],
      'primaryDiagnostic': attempt['diagnostic'],
      'hasSavedResponse': raw is String,
      'strictParserPass': false,
      'compilerPass': false,
      'productionChecksPass': false,
      'fixedAssertionsPass': false,
      'fixedAssertionsPassAfterDiagnosticOnlyOptionalReminder': false,
    };
    rows.add(row);
    if (raw is! String) continue;
    row['responseSha256'] = sha256.convert(utf8.encode(raw)).toString();
    Map<String, dynamic> output;
    try {
      output = parseAiOutput(raw);
    } catch (e) {
      row['parseDiagnostic'] = explain(e);
      continue;
    }
    AppSpec.parse(jsonEncode(output));
    row['strictParserPass'] = true;
    final compiled = compileGeneratedCreation(
      jsonEncode(output),
      rawOutput: raw,
    );
    row['compilerPass'] = true;
    row['compilerAddedCapabilities'] = compiled.toJson()['addedCapabilities'];
    validateGeneratedExperience(compiled.spec);
    requirements.validate(compiled.spec);
    row['productionChecksPass'] = true;
    try {
      scenario.validate(output, compiled.spec);
      row['fixedAssertionsPass'] = true;
    } catch (e) {
      row['fixedAssertionDiagnostic'] = explain(e);
    }
    final rule = compiled.spec.automationRequests.single;
    final field = compiled.spec
        .collection(rule.collectionId)
        .field(rule.fieldId);
    row['reminderTimestampRequired'] = field.required;
    final hypothetical = jsonDecode(jsonEncode(output)) as Map<String, dynamic>;
    final collection = (hypothetical['collections'] as List).singleWhere(
      (c) => c['id'] == rule.collectionId,
    );
    final changedField = (collection['fields'] as List).singleWhere(
      (f) => f['id'] == rule.fieldId,
    );
    changedField['required'] = false;
    try {
      scenario.validate(hypothetical, AppSpec.parse(jsonEncode(hypothetical)));
      row['fixedAssertionsPassAfterDiagnosticOnlyOptionalReminder'] = true;
    } catch (e) {
      row['remainingDiagnosticAfterOptionalReminder'] = explain(e);
    }
  }
  final result = {
    'label': 'POSTHOC OFFLINE KIMI REMINDER ASSERTION DIAGNOSTIC',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'inputCheckpointSha256': sha256.convert(bytes).toString(),
    'inputCheckpointUpdatedAt': checkpoint['updatedAt'],
    'inputCheckpointStatus': checkpoint['status'],
    'runFingerprint': checkpoint['runFingerprint'],
    'sourceMatchesScoredManifest': true,
    'primaryScoresChanged': false,
    'liveCallsMade': false,
    'operationStatus': operation['status'],
    'scenarioPrompt': scenario.prompt,
    'extractedProductionOwnerInboxRequirement': requirements.ownerInboxReminder
        ?.toJson(),
    'attempts': rows,
    'caveat':
        'Making the reminder optional is a diagnostic-only functional '
        'change, not production compilation or a score correction. The fixed '
        'scorer requires optional reminder timestamps; the request expressly '
        'says optional due dates and independent reminder times. The production '
        'literal requirement extractor does not require an optional reminder '
        'for that wording. No renderer, delivery, save or device execution is '
        'verified.',
  };
  File('$directory/posthoc-offline-kimi-reminder-assertion.json')
      .writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
  final markdown = StringBuffer(
    '# Posthoc offline Kimi reminder assertion diagnostic\n\n'
    'Generated: ${result['generatedAt']}. Input checkpoint updated: '
    '${checkpoint['updatedAt']} (${checkpoint['status']}). '
    'SHA256 `${result['inputCheckpointSha256']}`. '
    'Run `${checkpoint['runFingerprint']}`.\n\n'
    'Every scored source hash matched the checkpoint manifest. No provider calls, '
    'checkpoint writes, scored source edits or primary score changes were made.\n\n'
    '`moonshotai/kimi-k3` / `create-reminders-name` remains '
    '**${operation['status']}** in the frozen primary benchmark. Production '
    'checks include strict AppSpec parsing, required-capability compilation, '
    'generated-experience validation and request-derived GenerationRequirements.\n\n'
    '| Attempt | Saved response | Strict parse | Production checks | Fixed assertions | Fixed assertions after diagnostic-only optional reminder |\n'
    '| --- | --- | --- | --- | --- | --- |\n',
  );
  for (final row in rows) {
    markdown.writeln(
      '| ${row['attempt']} | ${row['hasSavedResponse']} | '
      '${row['strictParserPass']} | ${row['productionChecksPass']} | '
      '${row['fixedAssertionsPass']} | '
      '${row['fixedAssertionsPassAfterDiagnosticOnlyOptionalReminder']} |',
    );
  }
  markdown.writeln(
    '\nAttempt 1 declares an optional due date and a separate, editable '
    'reminder timestamp with `required: true`. Its sole fixed assertion failure '
    'is that the reminder timestamp must also be optional. The isolated '
    'in-memory diagnostic changes only that boolean to false. The compiler '
    'does not make this functional change or add capabilities. Attempt 2 is '
    'malformed JSON; attempt 3 timed out without a saved response.\n\n'
    'The frozen prompt says “optional due dates and independent reminder '
    'times.” Optionality expressly modifies due dates; the scorer also '
    'enforces optional reminder times. The production literal requirement '
    'extractor sets `optionalTimestamp: false` for this wording. This is a '
    'scoring-contract interpretation caveat, rather than a capability-closure '
    'repair. The scorer\'s interpretation was fixed before the run and applies '
    'to all models.\n\n'
    'A required reminder timestamp has a real behavioral consequence: an '
    'unscheduled task cannot be saved and the optional timestamp\'s Clear '
    'action is not shown. That differs from GLM\'s multistep case, where the '
    'renderer supplies an upload control by image field type even when its '
    'explicit configuration is omitted.\n\n'
    '${result['caveat']} Primary scoring remains unchanged. The JSON records '
    'all three attempts and the isolated optionality check; '
    '`offline_kimi_reminder_diagnostic.dart` reproduces it from the local saved '
    'checkpoint.\n',
  );
  File('$directory/posthoc-offline-kimi-reminder-assertion.md')
      .writeAsStringSync(markdown.toString());
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
}
