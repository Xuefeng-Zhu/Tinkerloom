// Opt-in provider/schema evaluation. Does not start Serverpod, access records,
// publish apps, or print credentials. Run from the repository root with --live.
import 'dart:convert';
import 'dart:io';

import 'package:appnest_server/src/generated/serverpod.dart';
import 'package:appnest_server/src/modules/builder/customization_evaluation.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';

const cases = <(String, String, String)>[
  (
    'notes-fields',
    'Make a personal notes app with titles, multiline notes, categories, search, add/edit forms, and a details page for each note.',
    'Add an optional text field named Source to my notes. Include it in the add/edit form and details. Preserve every existing field and page.',
  ),
  (
    'notes-appearance',
    'Build a simple notebook to capture my ideas with titles, long notes, and categories. I need to add and edit notes.',
    'Give this app an editorial appearance with accent color #3B6B5A. Keep all content and behavior unchanged.',
  ),
  (
    'reminders-timing',
    'Create a personal reminder list with title, notes, Open/Done status, and an optional Remind me timestamp. Remind the owner in the AppNest inbox at that time only while Open. Include add/edit screens.',
    'Update the existing reminder rule to fire 10 minutes before its existing timestamp. Preserve its rule ID, condition, and recipient.',
  ),
  (
    'reminders-name',
    'I want a simple personal task reminder app with optional due dates and independent reminder times, Open and Done states, and owner inbox reminders only for open tasks. Let me add and edit tasks.',
    'Rename this app to Gentle Reminders and change nothing else.',
  ),
  (
    'calendar-category',
    'Create a personal calendar for my events with title, start time, notes, and a Category choice of Personal or Work. Include monthly calendar with daily agenda and add/edit screens.',
    'Add Travel as another choice in the existing Category field. Preserve all existing choices, fields, and views.',
  ),
  (
    'calendar-appearance',
    'Make an events calendar with a monthly calendar and selected-day agenda, event titles, date and time, notes, and add/edit screens.',
    'Change this app to the playful appearance style. Keep its content and behavior unchanged.',
  ),
  (
    'focus-duration',
    'Make a minimal clock and focus timer app. Show a local digital clock and a 25-minute focus countdown with start, pause, resume, and reset. No record collections are needed.',
    'Change the existing focus timer default duration to 40 minutes. Keep the clock and all other settings unchanged.',
  ),
  (
    'focus-clock',
    'Build my focus app with a digital local clock showing seconds and a 25-minute countdown timer. It needs no notes, tasks, or record collections.',
    'Change the existing clock to analog and hide its seconds hand. Preserve the timer and all other settings.',
  ),
];

Future<void> main(List<String> args) async {
  if (!args.contains('--live') && !args.contains('--describe')) {
    stdout.writeln(
      'Use --live to run 8 synthetic creations and 8 edits through the configured AI provider. No app server is started.',
    );
    return;
  }
  final selectedArg = args.where((a) => a.startsWith('--cases=')).firstOrNull;
  final selectedIds = selectedArg?.substring(8).split(',').toSet();
  if (selectedIds != null &&
      (selectedIds.isEmpty ||
          selectedIds.difference(cases.map((c) => c.$1).toSet()).isNotEmpty)) {
    stderr.writeln('Unknown case ID. Choose IDs from --describe.');
    exitCode = 2;
    return;
  }
  final selected = cases
      .where((c) => selectedIds == null || selectedIds.contains(c.$1))
      .toList();
  final editSourceArg = args
      .where((a) => a.startsWith('--edits-from='))
      .firstOrNull;
  final templateEdits = args.contains('--template-edits');
  if (templateEdits && editSourceArg != null) {
    stderr.writeln('Choose either template edits or saved synthetic edits.');
    exitCode = 2;
    return;
  }
  final savedCreates = <String, AppSpec>{};
  if (templateEdits) {
    final templates = starterTemplates();
    for (final c in selected) {
      var baseline = templates[c.$1.split('-').first]!;
      if (c.$1 == 'focus-clock') {
        final clock = baseline.views.singleWhere((v) => v.type == 'clock');
        baseline = baseline.patch({
          'type': 'UpdateView',
          'viewId': clock.id,
          'view': {
            ...clock.toJson()..remove('id'),
            'options': {...clock.options, 'showSeconds': true},
          },
        }, () => throw StateError('No IDs needed'));
      }
      validateCustomizationScenario(c.$1, baseline);
      savedCreates[c.$1] = baseline;
    }
  }
  if (editSourceArg != null) {
    final source = jsonDecode(
      await File(editSourceArg.substring(13)).readAsString(),
    ) as Map;
    for (final row in source['operations'] as List) {
      if (row['operation'] == 'create' &&
          row['success'] == true &&
          row['candidate'] != null) {
        savedCreates[row['case'] as String] = AppSpec.parse(
          jsonEncode(row['candidate']),
        );
      }
    }
    if (selected.any((c) => !savedCreates.containsKey(c.$1))) {
      stderr.writeln(
        'Every selected edit needs a saved successful synthetic creation.',
      );
      exitCode = 2;
      return;
    }
  }
  final plannedOperations =
      selected.length * (editSourceArg == null && !templateEdits ? 2 : 1);
  final root = File.fromUri(Platform.script).parent.parent;
  final outputArg = args.where((a) => a.startsWith('--output=')).firstOrNull;
  final output = File(
    outputArg?.substring(9) ??
        '${root.path}/docs/evidence/customization/provider-eval.json',
  );
  // Construction loads configuration only; never call start().
  final pod = Serverpod([
    '--mode=development',
  ], serverDirectory: Directory('${root.path}/appnest_server'));
  final base = pod.getPassword('AI_BASE_URL'),
      model = pod.getPassword('AI_MODEL'),
      key = pod.getPassword('AI_API_KEY');
  if ([base, model, key].any((v) => v == null || v.trim().isEmpty)) {
    stderr.writeln('AI provider is not configured; no live calls made.');
    await pod.shutdown(exitProcess: false);
    exitCode = 2;
    return;
  }
  final provider = ChatCompletionProvider(Uri.parse(base!), model!, key!);
  if (args.contains('--describe')) {
    final request = buildAiRequest(
      model,
      cases.first.$2,
      starterTemplates()['reading']!,
      editing: false,
    );
    final description = const JsonEncoder.withIndent('  ').convert({
      'destination': '${provider.base}/chat/completions',
      'model': model,
      'operations': selected
          .map((c) => {'id': c.$1, 'create': c.$2, 'edit': c.$3})
          .toList(),
      'payloadContents': [
        'synthetic prompts above',
        'AppNest declarative schema and fixed capability guidance',
        'fixed synthetic reading example',
        'previous generated synthetic definition for edits',
        'bounded synthetic validation diagnostics for retries',
      ],
      'privateRecordsIncluded': false,
      'firstRequestBytes': utf8.encode(jsonEncode(request)).length,
      'networkCallsMade': false,
    });
    stdout.writeln(description);
    if (outputArg != null) {
      await output.parent.create(recursive: true);
      await output.writeAsString('$description\n');
    }
    await pod.shutdown(exitProcess: false);
    return;
  }
  final rows = <Map<String, dynamic>>[];
  var sequence = 0;
  Future<AppSpec?> run(
    String id,
    String prompt,
    AppSpec current,
    bool editing,
  ) async {
    final watch = Stopwatch()..start();
    final attempts = <Map<String, dynamic>>[];
    final diagnostics = <String>[];
    String? rejected;
    AppSpec? accepted;
    for (var attempt = 1; attempt <= Limits.generationAttempts; attempt++) {
      final requestWatch = Stopwatch()..start();
      AiResult? result;
      String? failure;
      try {
        result = await provider.generate(
          prompt,
          current,
          editing: editing,
          diagnostics: diagnostics,
          rejectedOutput: rejected,
        );
        final json = parseAiOutput(result.text);
        if (json['unsupported'] != null)
          throw const SpecException(
            'Supported showcase was reported as unsupported.',
          );
        var candidate = current;
        if (editing) {
          keys(json, {'patches'}, 'edit output');
          for (final patch in array(json['patches'], 'patches', 10)) {
            candidate = candidate.patch(
              object(patch, 'patch'),
              () => 'eval_${++sequence}',
            );
          }
          final errors = current.compatibilityErrors(candidate);
          if (errors.isNotEmpty) throw SpecException(errors.join(' '));
        } else {
          candidate = AppSpec.parse(jsonEncode(json));
          if (candidate.appearance == null) {
            candidate = candidate.patch({
              'type': 'SetAppearance',
              'appearance': {'style': 'clean'},
            }, () => 'unused');
          }
        }
        validateCustomizationScenario(
          id,
          candidate,
          baseline: editing ? current : null,
        );
        accepted = candidate;
      } on AiResponseException catch (e) {
        failure = '${e.kind}: ${e.message}';
      } on SpecException catch (e) {
        failure = e.message;
      } catch (e) {
        failure = 'Unexpected ${e.runtimeType}';
      }
      attempts.add({
        'attempt': attempt,
        'elapsedMs': requestWatch.elapsedMilliseconds,
        'success': accepted != null,
        if (failure != null) 'diagnostic': failure,
        if (result != null) ...{
          'usage': result.usage,
          // This opt-in runner creates synthetic definitions only. Persist the
          // exact response for offline review and stronger future assertions.
          'syntheticResponse': result.text,
        },
      });
      if (accepted != null) break;
      diagnostics
        ..clear()
        ..add(failure ?? 'Return a valid complete definition.');
      rejected = result?.text;
    }
    rows.add({
      'case': id,
      'operation': editing ? 'edit' : 'create',
      'success': accepted != null,
      'totalMs': watch.elapsedMilliseconds,
      'attempts': attempts,
      if (accepted != null) ...{
        'candidateHash': accepted.hash,
        'candidate': accepted.toJson(),
      },
      if (editing) 'baseline': current.toJson(),
    });
    stdout.writeln(
      '$id ${editing ? 'edit' : 'create'}: ${accepted == null ? 'FAIL' : 'PASS'}, ${attempts.length} attempt(s), ${watch.elapsedMilliseconds} ms',
    );
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
        'layer': 'live provider + schema + exact synthetic scenario assertions',
        'assertionVersion': 3,
        'requestContract': 'appnest-v1-typed-customization-2',
        'plannedOperations': plannedOperations,
        'baselineSource': templateEdits
            ? 'explicit synthetic template fixtures'
            : editSourceArg != null
            ? 'saved synthetic model creation'
            : 'live synthetic model creation',
        if (editSourceArg != null)
          'savedSyntheticSource': editSourceArg.substring(13),
        'model': model,
        'queueTimingMeasured': false,
        'connectedAppVerified': false,
        'operations': rows,
      }),
    );
    return accepted;
  }

  try {
    for (final (id, create, edit) in selected) {
      final candidate = editSourceArg != null || templateEdits
          ? savedCreates[id]
          : await run(id, create, starterTemplates()['reading']!, false);
      if (candidate != null) await run(id, edit, candidate, true);
    }
    if (rows.length != plannedOperations ||
        rows.any((r) => r['success'] != true))
      exitCode = 1;
  } finally {
    await pod.shutdown(exitProcess: false);
  }
}
