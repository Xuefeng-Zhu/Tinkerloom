// Opt-in, synthetic-only model benchmark. Does not start an app server or
// change application model selection. Run --describe before --live.
import 'dart:convert';
import 'dart:io';

import 'package:appnest_server/src/evaluation/nemotron_case_selection.dart';
import 'package:appnest_server/src/generated/serverpod.dart';
import 'package:appnest_server/src/modules/builder/nemotron_evaluation.dart';
import 'package:appnest_server/src/modules/builder/nemotron_report.dart';
import 'package:appnest_server/src/modules/builder/nemotron_routes.dart';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/creation_pipeline_evaluation.dart';
import 'package:appnest_server/src/modules/builder/creation_pipeline_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  String? option(String name) => args
      .where((a) => a.startsWith('$name='))
      .map((a) => a.substring(name.length + 1))
      .firstOrNull;
  final allowed = {'--describe', '--catalog', '--live', '--resume', '--replay'};
  if (args.any(
    (a) =>
        !allowed.contains(a) &&
        ![
          '--provider=',
          '--models=',
          '--cases=',
          '--nemotron-profile=',
          '--creation-pipeline=',
          '--output=',
          '--max-requests=',
          '--concurrency=',
        ].any(a.startsWith),
  )) {
    stderr.writeln(
      'Unknown option. Use --describe, --catalog, --live [--resume], or --replay; --provider=nvidia|openrouter --models=ID,ID --cases=ID,ID --nemotron-profile=PROFILE --creation-pipeline=baseline|scoped|plan|repair|cascade --output=FILE --max-requests=N --concurrency=1..4.',
    );
    exitCode = 2;
    return;
  }
  final mode = args.where(
    (a) => {'--describe', '--catalog', '--live', '--replay'}.contains(a),
  );
  if (mode.length != 1 ||
      args.contains('--resume') && !args.contains('--live')) {
    stdout.writeln(
      'Choose --describe (offline), --catalog (public GET), --live [--resume], or --replay (offline).',
    );
    exitCode = args.isEmpty ? 0 : 2;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent;
  late final NemotronEvaluationRoute route;
  late final List<String> models;
  late final List<NemotronScenario> scenarios;
  late final NvidiaNemotronProfile nemotronProfile;
  late final CreationPipeline pipeline;
  try {
    route = nemotronRoute(option('--provider') ?? 'nvidia');
    models = option('--models')?.split(',') ?? route.models.toList();
    validateNemotronModelSelection(models, route);
    nemotronProfile = parseNvidiaNemotronProfile(
      option('--nemotron-profile') ?? 'baseline',
    );
    validateNvidiaNemotronProfileSelection(models, route.name, nemotronProfile);
    pipeline = parseCreationPipeline(
      option('--creation-pipeline') ?? 'baseline',
    );
    if (pipeline != CreationPipeline.baseline &&
        (route.name != 'nvidia' ||
            models.length != 1 ||
            models.single != pipelineTargetModel ||
            nemotronProfile != NvidiaNemotronProfile.efficientCreation)) {
      throw const FormatException(
        'Creation pipelines require NVIDIA Super only and --nemotron-profile=efficient-creation.',
      );
    }
    scenarios = selectNemotronCases([
      ...nemotronScenarios(),
      ...nemotronSequences(),
      if (option('--cases') != null) ...creationPipelineTransferScenarios(),
    ], cases: option('--cases'));
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
    return;
  }
  final output = File(
    option('--output') ??
        '${root.path}/output/${route.outputDirectory}/checkpoint.json',
  );
  final maxRequests = option('--max-requests') == null
      ? null
      : int.tryParse(option('--max-requests')!);
  if (option('--max-requests') != null &&
      (maxRequests == null || maxRequests <= 0)) {
    stderr.writeln('--max-requests must be a positive integer.');
    exitCode = 2;
    return;
  }
  final concurrency = int.tryParse(option('--concurrency') ?? '1');
  if (concurrency == null || concurrency < 1 || concurrency > 4) {
    stderr.writeln('--concurrency must be an integer from 1 through 4.');
    exitCode = 2;
    return;
  }
  if (pipeline == CreationPipeline.cascade && concurrency != 1) {
    stderr.writeln(
      'Cascade requires --concurrency=1 to preserve actual-model pacing.',
    );
    exitCode = 2;
    return;
  }
  const requestInterval = Duration(seconds: 4);
  if (args.contains('--describe')) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'benchmarkVersion': nemotronBenchmarkVersion,
        'provider': route.name,
        'nemotronProfile': nemotronProfile.id,
        if (pipeline != CreationPipeline.baseline)
          'creationPipeline': creationPipelineMetadata(pipeline),
        'destination': '${route.base}/chat/completions',
        'credentialName': route.credentialName,
        'output': output.path,
        'models': models,
        'allowedModels': route.allowedModels,
        'benchmarkLabel': nemotronBenchmarkLabel(models, route.name),
        'modelFamilies': nemotronModelFamilies(models, route.name),
        'transportProfiles': nemotronTransportProfiles(
          models,
          route.name,
          nemotronProfile: nemotronProfile,
        ),
        'scenarios': scenarios.map((s) => s.toJson()).toList(),
        'maxAttempts': 3,
        'execution': nemotronExecution(concurrency, requestInterval),
        'privateRecordsIncluded': false,
        'networkCallsMade': false,
        'freeEndpointRequired': true,
        'accountLimitsKnown': false,
        'baselinePolicy': 'identical fixtures for edits; fixed reading example for creation; model output only for sequences',
      }),
    );
    return;
  }
  Serverpod? pod;
  RandomAccessFile? checkpointLock;
  final client = http.Client();
  try {
    if (args.contains('--replay')) {
      final checkpoint =
          jsonDecode(await output.readAsString()) as Map<String, dynamic>;
      final byId = {for (final s in scenarios) s.id: s};
      var checked = 0;
      for (final row in checkpoint['operations'] as List) {
        if (row['status'] != 'passed') continue;
        final scenario = byId[row['case']];
        if (scenario == null)
          throw const FormatException('Unknown saved scenario.');
        final attempt = (row['attempts'] as List).last as Map;
        AppSpec? baselineOverride;
        if (scenario.sequenceSourceId != null) {
          final source = (checkpoint['operations'] as List).singleWhere(
            (r) =>
                r['model'] == row['model'] &&
                r['case'] == scenario.sequenceSourceId,
          );
          baselineOverride = AppSpec.parse(jsonEncode(source['candidate']));
        }
        final baseline =
            baselineOverride ??
            (scenario.operation == 'create'
                ? starterTemplates()['reading']!
                : scenario.baseline);
        final derived = scoreNemotronResult(
          scenario,
          attempt['pipelineEvidence'] is Map
              ? deriveCreationPipelineResponse(
                  (attempt['providerResponse'] ?? attempt['syntheticResponse'])
                      as String,
                  Map<String, dynamic>.from(attempt['pipelineEvidence'] as Map),
                )
              : attempt['syntheticResponse'] as String,
          baseline,
        );
        if (jsonEncode(derived?.toJson()) != jsonEncode(row['candidate'])) {
          throw const FormatException(
            'Saved candidate differs from replayed response.',
          );
        }
        checked++;
      }
      stdout.writeln(
        'Offline replay passed for $checked accepted synthetic results.',
      );
      stdout.writeln(renderNemotronReport(checkpoint));
      return;
    }
    final accessModels = [
      ...models,
      if (pipeline == CreationPipeline.cascade) pipelineFallbackModel,
    ];
    final catalog = route.isNvidia
        ? await readNvidiaNemotronCatalog(client, accessModels)
        : selectFreeNemotronModels(await readNemotronCatalog(client), models);
    if (args.contains('--catalog')) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(catalog));
      return;
    }
    await output.parent.create(recursive: true);
    checkpointLock = await File('${output.path}.lock')
        .open(mode: FileMode.append);
    try {
      await checkpointLock.lock(FileLock.exclusive);
    } on FileSystemException {
      throw const FormatException(
        'Another evaluator owns this output checkpoint.',
      );
    }
    // Config construction only; never call start().
    pod = Serverpod([
      '--mode=development',
    ], serverDirectory: Directory('${root.path}/appnest_server'));
    final source = await _sourceSnapshot(root);
    final expected = newNemotronCheckpoint(
      models: models,
      scenarios: scenarios,
      catalog: catalog,
      source: source,
      provider: route.name,
      concurrency: concurrency,
      requestInterval: requestInterval,
      nemotronProfile: nemotronProfile,
      creationPipeline: pipeline == CreationPipeline.baseline
          ? null
          : creationPipelineMetadata(pipeline),
    );
    Map<String, dynamic> checkpoint;
    if (args.contains('--resume')) {
      checkpoint =
          jsonDecode(await output.readAsString()) as Map<String, dynamic>;
      validateNemotronResume(checkpoint, expected);
      checkpoint['latestCatalog'] = catalog;
    } else {
      if (await output.exists()) {
        throw const FormatException(
          'Output exists. Use --resume or a new output path.',
        );
      }
      checkpoint = expected;
    }
    // NVIDIA must never fall back to a key belonging to another provider.
    // Legacy AI_API_KEY remains usable for OpenRouter only when its configured
    // base identifies OpenRouter; an explicit provider key takes precedence.
    final key = route.isNvidia
        ? pod.getPassword('NVIDIA_API_KEY')
        : pod.getPassword('OPENROUTER_API_KEY') ??
              (pod
                          .getPassword('AI_BASE_URL')
                          ?.replaceFirst(RegExp(r'/$'), '') ==
                      openRouterEvaluationBase
                  ? pod.getPassword('AI_API_KEY')
                  : null);
    if (key == null || key.trim().isEmpty) {
      checkpoint['status'] = 'blocked';
      checkpoint['blockedReason'] =
          'Configure server-only ${route.credentialName} for ${route.name}. No completion calls made.';
      await saveNemotronCheckpoint(output, checkpoint);
      stdout.writeln(checkpoint['blockedReason']);
      stdout.writeln('Checkpoint: ${output.path}');
      exitCode = 3;
      return;
    }
    await saveNemotronCheckpoint(output, checkpoint);
    late final Map<String, dynamic> quota;
    try {
      quota = route.isNvidia
          ? await readNvidiaNemotronAccess(client, key, accessModels)
          : await readNemotronQuota(client, key);
    } catch (e) {
      checkpoint['status'] = 'blocked';
      checkpoint['blockedReason'] =
          'Credential/model-access preflight failed (${e.runtimeType}); no completion calls made.';
      await saveNemotronCheckpoint(output, checkpoint);
      rethrow;
    }
    quota['checkedAt'] = DateTime.now().toUtc().toIso8601String();
    checkpoint['quota'] = quota;
    if ((quota['freeRequests'] as Map?)?['remaining'] == 0) {
      checkpoint['status'] = 'blocked';
      checkpoint['blockedReason'] =
          'Free daily request quota is exhausted; no completion calls made.';
      await saveNemotronCheckpoint(output, checkpoint);
      stdout.writeln(checkpoint['blockedReason']);
      exitCode = 3;
      return;
    }
    final providers = {
      for (final model in models)
        model:
            {
              CreationPipeline.scoped,
              CreationPipeline.plan,
              CreationPipeline.repair,
            }.contains(pipeline)
            ? ExperimentalCreationProvider(
                Uri.parse(route.base),
                model,
                key,
                pipeline: pipeline,
              )
            : ChatCompletionProvider(
                Uri.parse(route.base),
                model,
                key,
                freeNemotronEvaluation: !route.isNvidia,
                nvidiaModelEvaluation: route.isNvidia,
                nemotronProfile: nemotronProfile,
              ),
    };
    final cascade = pipeline == CreationPipeline.cascade
        ? CreationCascade(
            providers[models.single]!,
            ChatCompletionProvider(
              Uri.parse(route.base),
              pipelineFallbackModel,
              key,
              nvidiaModelEvaluation: true,
            ),
          )
        : null;
    final runner = NemotronEvaluationRunner(
      checkpoint: checkpoint,
      scenarios: scenarios,
      concurrency: concurrency,
      requestInterval: requestInterval,
      save: (state) => saveNemotronCheckpoint(output, state),
      log: stdout.writeln,
      invoke: (model, scenario, baseline, diagnostics, rejected) async {
        final provider = providers[model]!;
        if (scenario.operation == 'guidance') {
          return invokeNemotronGuidance(provider, scenario);
        }
        if (cascade != null &&
            !{'edit', 'sequence'}.contains(scenario.operation)) {
          final row = (checkpoint['operations'] as List).singleWhere(
            (row) => row['model'] == model && row['case'] == scenario.id,
          );
          final fallbackPreviouslyUsed = (row['attempts'] as List).any(
            (attempt) =>
                attempt['pipelineEvidence']?['servedByModel'] ==
                pipelineFallbackModel,
          );
          return cascade.generate(
            scenario.prompt,
            baseline,
            editing: false,
            diagnostics: diagnostics,
            rejectedOutput: rejected,
            fallbackPreviouslyUsed: fallbackPreviouslyUsed,
          );
        }
        return provider.generate(
          scenario.prompt,
          baseline,
          editing: {'edit', 'sequence'}.contains(scenario.operation),
          diagnostics: diagnostics,
          rejectedOutput: rejected,
        );
      },
    );
    await runner.run(maxRequests: maxRequests);
    stdout.writeln('Checkpoint: ${output.path}');
    stdout.writeln('Report: ${output.path}.md');
    if (checkpoint['status'] != 'completed') {
      stdout.writeln(
        checkpoint['blockedReason'] ??
            'Some request outcomes are indeterminate.',
      );
      exitCode = 3;
    } else if ((checkpoint['operations'] as List).any(
      (r) => r['status'] == 'failed',
    )) {
      exitCode = 1;
    }
  } on AiResponseException catch (e) {
    stderr.writeln(
      '${e.kind}: ${e.message} (HTTP ${e.statusCode ?? 'unknown'})',
    );
    exitCode = 2;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
  } catch (e) {
    stderr.writeln(
      'Evaluation stopped: ${e.runtimeType}. Checkpoint, if present, is preserved.',
    );
    exitCode = 2;
  } finally {
    client.close();
    if (checkpointLock != null) await checkpointLock.close();
    if (pod != null) await pod.shutdown(exitProcess: false);
  }
}

Future<Map<String, dynamic>> _sourceSnapshot(Directory root) async {
  Future<String> git(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: root.path,
    );
    if (result.exitCode != 0)
      throw const FormatException('Could not identify evaluation source.');
    return result.stdout as String;
  }

  final sourcePaths = [
    'appnest_server/lib/src/modules/builder',
    'appnest_server/lib/src/evaluation',
    'packages/appnest_spec/lib',
    'scripts/nemotron_eval.dart',
    'pubspec.yaml',
    'pubspec.lock',
    'appnest_server/pubspec.yaml',
    'packages/appnest_spec/pubspec.yaml',
  ];
  final files = <File>[];
  for (final path in sourcePaths) {
    final type = await FileSystemEntity.type('${root.path}/$path');
    if (type == FileSystemEntityType.file) {
      files.add(File('${root.path}/$path'));
    } else {
      await for (final item in Directory(
        '${root.path}/$path',
      ).list(recursive: true)) {
        if (item is File && item.path.endsWith('.dart')) files.add(item);
      }
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  final hashes = <String, String>{};
  for (final file in files) {
    hashes[file.path.substring(root.path.length + 1)] = sha256
        .convert(await file.readAsBytes())
        .toString();
  }
  return {
    'commit': (await git(['rev-parse', 'HEAD'])).trim(),
    'dirtyTrackedSha256': sha256
        .convert(utf8.encode(await git(['diff', 'HEAD', '--binary'])))
        .toString(),
    'contractSourceSha256': sha256
        .convert(
          utf8.encode(
            jsonEncode({'files': hashes, 'dartVersion': Platform.version}),
          ),
        )
        .toString(),
    'dartVersion': Platform.version,
    'files': hashes,
  };
}
