import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../evaluation/nemotron_parallel_scheduler.dart';

import 'nemotron_report.dart';
import 'nemotron_routes.dart';
import 'nemotron_scenarios.dart';
import 'provider.dart';

const nemotronBenchmarkVersion = 'appnest-nemotron-v2';
const nemotronEvaluationBase = 'https://openrouter.ai/api/v1';

typedef NemotronInvocation = Future<AiResult> Function(
  String model,
  NemotronScenario scenario,
  AppSpec baseline,
  List<String> diagnostics,
  String? rejectedOutput,
);

/// Snapshot only the selected public catalog entries, never provider secrets.
List<Map<String, dynamic>> selectFreeNemotronModels(
  Map<String, dynamic> catalog,
  List<String> selected,
) {
  if (selected.isEmpty ||
      selected.toSet().length != selected.length ||
      selected.any((model) => !freeNemotronModels.contains(model))) {
    throw const FormatException(
      'Select distinct allowlisted free Nemotron IDs.',
    );
  }
  final data = catalog['data'];
  if (data is! List) throw const FormatException('Invalid model catalog.');
  return selected.map((id) {
    final matches = data.whereType<Map>().where((m) => m['id'] == id);
    if (matches.length != 1) {
      throw FormatException('Free route unavailable in catalog: $id');
    }
    final entry = matches.single;
    final pricing = entry['pricing'];
    if (pricing is! Map ||
        [
          'prompt',
          'completion',
        ].any((name) => num.tryParse('${pricing[name]}') != 0) ||
        pricing.entries.any(
          (e) => e.key != 'overrides' && num.tryParse('${e.value}') != 0,
        ) ||
        pricing.containsKey('overrides')) {
      throw FormatException('Route does not have verified zero pricing: $id');
    }
    final parameters = entry['supported_parameters'];
    if (id == 'nvidia/nemotron-3-super-120b-a12b:free' &&
        (parameters is! List || !parameters.contains('response_format'))) {
      throw const FormatException('Super structured-output profile changed.');
    }
    return <String, dynamic>{
      'id': id,
      'pricing': pricing,
      'supportedParameters': parameters,
      'contextLength': entry['context_length'],
      'canonicalSlug': entry['canonical_slug'],
    };
  }).toList();
}

Future<Map<String, dynamic>> readNemotronCatalog(http.Client client) async {
  final response = await client
      .get(
        Uri.parse('$nemotronEvaluationBase/models'),
      )
      .timeout(const Duration(seconds: 20));
  if (response.statusCode != 200) {
    throw const FormatException('Could not read the public model catalog.');
  }
  final value = jsonDecode(response.body);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid public model catalog.');
  }
  return value;
}

/// Read only quota metadata; account labels, balances and credentials are omitted.
Future<Map<String, dynamic>> readNemotronQuota(
  http.Client client,
  String key,
) async {
  final response = await client
      .get(
        Uri.parse('$nemotronEvaluationBase/key'),
        headers: {'Authorization': 'Bearer $key'},
      )
      .timeout(const Duration(seconds: 20));
  if (response.statusCode != 200) {
    throw AiResponseException(
      'preflight_http',
      'OpenRouter credential/quota check failed.',
      statusCode: response.statusCode,
    );
  }
  final decoded = jsonDecode(response.body);
  final data = decoded is Map ? decoded['data'] : null;
  final quota = data is Map ? data['free_model_daily_requests'] : null;
  return {
    'checkedAt': DateTime.now().toUtc().toIso8601String(),
    'freeRequests': quota is Map
        ? {
            for (final k in ['used', 'limit', 'remaining'])
              if (quota[k] is num) k: quota[k],
          }
        : null,
  };
}

/// Guidance needs its raw usage for the benchmark. The application API stays
/// unchanged; both paths share request construction and output parsing.
Future<AiResult> invokeNemotronGuidance(
  ChatCompletionProvider provider,
  NemotronScenario scenario, {
  http.Client? client,
}) async {
  if (!provider.nemotronEvaluation) {
    throw ArgumentError(
      'Guidance evaluation requires a supported model profile.',
    );
  }
  final transport = client ?? http.Client();
  try {
    return await (() async {
      final body = provider.adaptRequestForTransport(
        buildGuidanceRequest(provider.model, scenario.prompt),
        generation: false,
      );
      final request =
          http.Request(
              'POST',
              Uri.parse(
                '${provider.base.toString().replaceFirst(RegExp(r'/$'), '')}/chat/completions',
              ),
            )
            ..followRedirects = false
            ..headers.addAll({
              'Authorization': 'Bearer ${provider.key}',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            })
            ..body = jsonEncode(body);
      final response = await transport.send(request);
      if (response.statusCode != 200) {
        if (provider.nvidiaEvaluation && response.statusCode == 202) {
          throw const AiResponseException(
            'indeterminate',
            'NVIDIA accepted asynchronous guidance work; its outcome is unknown. Do not resubmit this request.',
            statusCode: 202,
            retryable: false,
          );
        }
        final retrySeconds = int.tryParse(
          response.headers['retry-after'] ?? '',
        );
        throw AiResponseException(
          'http_error',
          'Nemotron guidance request failed.',
          statusCode: response.statusCode,
          retryAfter: retrySeconds == null
              ? null
              : Duration(seconds: retrySeconds),
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 65536) {
          throw const AiResponseException(
            'guidance_envelope_size',
            'Guidance response exceeded the bound.',
          );
        }
        bytes.addAll(chunk);
      }
      dynamic envelope;
      try {
        envelope = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        throw const AiResponseException(
          'guidance_envelope',
          'Guidance response was not a valid completion envelope.',
        );
      }
      final usage = envelope is Map && envelope['usage'] is Map<String, dynamic>
          ? envelope['usage'] as Map<String, dynamic>
          : <String, dynamic>{};
      final error = envelope is Map ? envelope['error'] : null;
      if (error is Map) {
        final parsedCode = int.tryParse('${error['code']}');
        final code =
            {
              400,
              401,
              402,
              403,
              404,
              408,
              422,
              429,
              500,
              502,
              503,
              504,
            }.contains(parsedCode)
            ? parsedCode
            : null;
        throw AiResponseException(
          'http_error',
          'Nemotron provider returned an interrupted guidance completion.',
          statusCode: code,
          usage: usage,
        );
      }
      final choices = envelope is Map ? envelope['choices'] : null;
      final choice =
          choices is List && choices.isNotEmpty && choices.first is Map
          ? choices.first as Map
          : null;
      final message = choice?['message'];
      final content = message is Map ? message['content'] : null;
      if (choice?['finish_reason'] != 'stop' || content is! String) {
        throw AiResponseException(
          'guidance_completion',
          'Guidance did not complete a JSON answer.',
          usage: usage,
          syntheticResponse: content is String ? content : null,
        );
      }
      return AiResult(content, provider.base.host, provider.model, usage);
    })().timeout(const Duration(seconds: 20));
  } on TimeoutException {
    throw const AiResponseException('timeout', 'Guidance timed out.');
  } on http.ClientException {
    throw const AiResponseException(
      'transport_error',
      'Could not reach the guidance provider.',
    );
  } finally {
    if (client == null) transport.close();
  }
}

String nemotronBenchmarkLabel(List<String> models, String provider) =>
    provider == 'nvidia' && models.any((m) => !nvidiaNemotronModels.contains(m))
    ? 'AppNest NVIDIA model evaluation'
    : 'AppNest Nemotron evaluation';

Map<String, String> nemotronModelFamilies(
  List<String> models,
  String provider,
) => {
  for (final model in models)
    model: provider == 'nvidia'
        ? nvidiaEvaluationProfile(model).family
        : 'Nemotron',
};

Map<String, dynamic> nemotronTransportProfiles(
  List<String> models,
  String provider, {
  NvidiaNemotronProfile nemotronProfile = NvidiaNemotronProfile.baseline,
}) {
  validateNvidiaNemotronProfileSelection(models, provider, nemotronProfile);
  return {
    for (final model in models)
      model: provider == 'nvidia'
          ? nvidiaEvaluationProfile(
              model,
              nemotronProfile: nemotronProfile,
            ).toJson()
          : {
              'profile': model.contains('super-')
                  ? 'openrouter-free-json-schema-v1'
                  : 'openrouter-free-instruction-schema-v1',
              'reasoning': model.contains('super-') || model.contains('ultra-')
                  ? 'medium'
                  : 'model default',
              'generationDeadlineSeconds': 90,
              'guidanceDeadlineSeconds': 20,
            },
  };
}

Map<String, dynamic> newNemotronCheckpoint({
  required List<String> models,
  required List<NemotronScenario> scenarios,
  required List<Map<String, dynamic>> catalog,
  required Map<String, dynamic> source,
  String provider = 'openrouter',
  int concurrency = 1,
  Duration requestInterval = const Duration(seconds: 4),
  NvidiaNemotronProfile nemotronProfile = NvidiaNemotronProfile.baseline,
  Map<String, dynamic>? creationPipeline,
}) {
  final execution = nemotronExecution(concurrency, requestInterval);
  final route = nemotronRoute(provider);
  validateNemotronModelSelection(models, route);
  validateNvidiaNemotronProfileSelection(models, provider, nemotronProfile);
  final manifest = {
    'benchmarkVersion': nemotronBenchmarkVersion,
    'provider': provider,
    'nemotronProfile': nemotronProfile.id,
    'creationPipeline': ?creationPipeline,
    'benchmarkLabel': creationPipeline == null
        ? nemotronBenchmarkLabel(models, provider)
        : 'AppNest ${creationPipeline['pipeline']} pipeline evaluation',
    'modelFamilies': nemotronModelFamilies(models, provider),
    'apiBase': route.base,
    'models': models,
    'scenarios': scenarios.map((s) => s.toJson()).toList(),
    'source': source,
    'maxAttempts': 3,
    'execution': execution,
    'transportProfiles': nemotronTransportProfiles(
      models,
      provider,
      nemotronProfile: nemotronProfile,
    ),
  };
  final now = DateTime.now().toUtc().toIso8601String();
  return {
    'schemaVersion': 1,
    ...manifest,
    'runFingerprint': sha256
        .convert(
          utf8.encode(
            jsonEncode({
              ...manifest,
              'source': {
                'commit': source['commit'],
                'contractSourceSha256': source['contractSourceSha256'],
              },
            }),
          ),
        )
        .toString(),
    'createdAt': now,
    'updatedAt': now,
    'status': 'pending',
    'catalog': catalog,
    'freeOnly': true,
    'queueTimingMeasured': false,
    'connectedAppVerified': false,
    'operations': [
      for (final scenario in scenarios)
        for (final model in models)
          <String, dynamic>{
            'model': model,
            'case': scenario.id,
            'operation': scenario.operation,
            if (scenario.sequenceSourceId != null)
              'sequenceSourceId': scenario.sequenceSourceId,
            'status': 'pending',
            'success': false,
            'attempts': <Map<String, dynamic>>[],
            'totalMs': 0,
          },
    ],
  };
}

void validateNemotronResume(
  Map<String, dynamic> saved,
  Map<String, dynamic> expected,
) {
  if (saved['schemaVersion'] != 1 ||
      saved['runFingerprint'] != expected['runFingerprint']) {
    throw const FormatException(
      'Checkpoint contract/source differs; use a new output path for a new run.',
    );
  }
  for (final key in [
    'benchmarkVersion',
    'provider',
    'nemotronProfile',
    'creationPipeline',
    'benchmarkLabel',
    'modelFamilies',
    'apiBase',
    'models',
    'scenarios',
    'maxAttempts',
    'execution',
    'transportProfiles',
  ]) {
    if (jsonEncode(saved[key]) != jsonEncode(expected[key])) {
      throw const FormatException('Checkpoint manifest has changed.');
    }
  }
  final savedSource = saved['source'] as Map?;
  final expectedSource = expected['source'] as Map;
  if (savedSource == null ||
      [
        'commit',
        'contractSourceSha256',
      ].any((k) => savedSource[k] != expectedSource[k])) {
    throw const FormatException('Checkpoint source identity has changed.');
  }
  final operations = saved['operations'];
  final expectedOperations = expected['operations'] as List;
  if (operations is! List || operations.length != expectedOperations.length) {
    throw const FormatException(
      'Checkpoint operations do not match the manifest.',
    );
  }
  for (var i = 0; i < operations.length; i++) {
    final actual = operations[i];
    final required = expectedOperations[i] as Map;
    if (actual is! Map ||
        ['model', 'case', 'operation'].any((k) => actual[k] != required[k]) ||
        actual['sequenceSourceId'] != required['sequenceSourceId'] ||
        !{
          'passed',
          'failed',
          'skipped',
          'pending',
          'in_flight',
          'blocked',
          'indeterminate',
        }.contains(actual['status']) ||
        actual['attempts'] is! List ||
        (actual['attempts'] as List).length > 3) {
      throw const FormatException('Checkpoint operation identity is invalid.');
    }
    final attempts = actual['attempts'] as List;
    for (var n = 0; n < attempts.length; n++) {
      if (attempts[n] is! Map || attempts[n]['number'] != n + 1) {
        throw const FormatException('Checkpoint attempt sequence is invalid.');
      }
    }
    if (actual['status'] == 'passed' &&
        (attempts.isEmpty || attempts.last['success'] != true)) {
      throw const FormatException('Checkpoint pass has no successful attempt.');
    }
  }
}

/// Score the received text, deriving the candidate instead of trusting saved
/// candidate JSON. Shared by live execution and offline replay.
AppSpec? scoreNemotronResult(
  NemotronScenario scenario,
  String text,
  AppSpec baseline,
) {
  final output = parseAiOutput(text);
  AppSpec? candidate;
  if (scenario.operation == 'create') {
    candidate = AppSpec.parse(jsonEncode(output));
    if (candidate.appearance == null) {
      candidate = candidate.patch({
        'type': 'SetAppearance',
        'appearance': {'style': 'clean'},
      }, () => 'unused');
    }
  } else if ({'edit', 'sequence'}.contains(scenario.operation)) {
    keys(output, {'patches'}, 'edit output');
    candidate = baseline;
    var sequence = 0;
    for (final patch in array(output['patches'], 'patches', 10)) {
      candidate = candidate!.patch(
        object(patch, 'patch'),
        () => 'eval_${++sequence}',
      );
    }
    final compatibility = baseline.compatibilityErrors(candidate!);
    if (compatibility.isNotEmpty) throw SpecException(compatibility.join(' '));
  }
  scenario.validate(
    output,
    candidate,
    baselineOverride: scenario.sequenceSourceId == null ? null : baseline,
  );
  return candidate;
}

/// Atomic checkpoint replacement, including an in-flight marker before network
/// dispatch. An interrupted request is never automatically issued again.
Future<void> saveNemotronCheckpoint(
  File file,
  Map<String, dynamic> checkpoint,
) async {
  checkpoint['updatedAt'] = DateTime.now().toUtc().toIso8601String();
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(checkpoint)}\n',
    flush: true,
  );
  await temporary.rename(file.path);
  final summary = summarizeNemotronEvaluation(checkpoint);
  await File(
    '${file.path}.summary.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');
  await File('${file.path}.md').writeAsString(renderNemotronReport(checkpoint));
}

Map<String, dynamic> nemotronExecution(int concurrency, Duration interval) {
  if (concurrency < 1 || concurrency > 4 || interval.isNegative) {
    throw ArgumentError(
      'Concurrency must be 1 through 4 and pacing nonnegative.',
    );
  }
  return {
    'concurrency': concurrency,
    'requestIntervalMs': interval.inMilliseconds,
    'pacing': concurrency == 1 ? 'serial-delay' : 'global-dispatch',
    'perModelSequential': true,
  };
}

class NemotronEvaluationRunner {
  final Map<String, dynamic> checkpoint;
  final List<NemotronScenario> scenarios;
  final NemotronInvocation invoke;
  final Future<void> Function(Map<String, dynamic>) save;
  final void Function(String) log;
  final Future<void> Function(Duration) delay;
  final Duration requestInterval;
  final int concurrency;

  NemotronEvaluationRunner({
    required this.checkpoint,
    required this.scenarios,
    required this.invoke,
    required this.save,
    void Function(String)? log,
    Future<void> Function(Duration)? delay,
    this.requestInterval = const Duration(seconds: 4),
    this.concurrency = 1,
  }) : log = log ?? ((_) {}),
       delay = delay ?? Future<void>.delayed {
    nemotronExecution(concurrency, requestInterval);
  }

  Future<void> run({int? maxRequests}) async {
    if (maxRequests != null && maxRequests < 1) {
      throw ArgumentError.value(maxRequests, 'maxRequests', 'Must be positive');
    }
    final frozenConcurrency =
        (checkpoint['execution'] as Map?)?['concurrency'] ?? 1;
    if (frozenConcurrency != concurrency) {
      throw const FormatException(
        'Checkpoint concurrency differs; use a new output path.',
      );
    }
    if (concurrency == 1) {
      await _runSerial(maxRequests: maxRequests);
    } else {
      await _runParallel(maxRequests: maxRequests);
    }
  }

  Future<void> _runSerial({int? maxRequests}) async {
    if (checkpoint['billingGuardTripped'] == true) {
      throw const FormatException(
        'Billing guard was tripped; this run cannot resume.',
      );
    }
    var requests = 0;
    final models = List<String>.from(checkpoint['models'] as List);
    final rows = (checkpoint['operations'] as List)
        .cast<Map<String, dynamic>>();
    for (final row in rows.where((r) => r['status'] == 'in_flight')) {
      row['status'] = 'indeterminate';
      row['diagnostic'] =
          'Interrupted request has an unknown outcome; not replayed.';
    }
    checkpoint['status'] = 'running';
    checkpoint.remove('blockedReason');
    await save(checkpoint);
    for (var caseIndex = 0; caseIndex < scenarios.length; caseIndex++) {
      final scenario = scenarios[caseIndex];
      // Rotate model order so daily quota boundaries do not always favor one.
      for (var offset = 0; offset < models.length; offset++) {
        final model = models[(caseIndex + offset) % models.length];
        final row = rows.singleWhere(
          (r) => r['model'] == model && r['case'] == scenario.id,
        );
        if (!{'pending', 'blocked'}.contains(row['status'])) continue;
        AppSpec baseline =
            scenario.operation == 'create' ||
                scenario.operation == 'unsupported' ||
                scenario.operation == 'guidance'
            ? starterTemplates()['reading']!
            : scenario.baseline;
        if (scenario.sequenceSourceId != null) {
          final source = rows.singleWhere(
            (r) =>
                r['model'] == model && r['case'] == scenario.sequenceSourceId,
          );
          if (source['status'] != 'passed') {
            row['status'] = 'skipped';
            row['diagnostic'] =
                'Source creation did not pass; no substitute baseline used.';
            await save(checkpoint);
            continue;
          }
          baseline = AppSpec.parse(jsonEncode(source['candidate']));
        }
        final attempts = row['attempts'] as List;
        while (attempts.length < 3) {
          if (maxRequests != null && requests >= maxRequests) {
            checkpoint['status'] = 'blocked';
            checkpoint['blockedReason'] =
                'Requested per-invocation request cap reached.';
            await save(checkpoint);
            return;
          }
          final last = attempts.isEmpty ? null : attempts.last as Map;
          final diagnostics = last?['diagnostic'] is String
              ? [last!['diagnostic'] as String]
              : <String>[];
          row['status'] = 'in_flight';
          row['inFlightAttempt'] = attempts.length + 1;
          await save(checkpoint);
          final dispatchedAt = DateTime.now().toUtc().toIso8601String();
          final watch = Stopwatch()..start();
          AiResult? result;
          AiResponseException? providerError;
          Map<String, dynamic>? candidateJson;
          String? diagnostic;
          String kind = 'received';
          try {
            requests++;
            result = await invoke(
              model,
              scenario,
              baseline,
              diagnostics,
              last?['syntheticResponse'] as String?,
            );
            final candidate = scoreNemotronResult(
              scenario,
              result.text,
              baseline,
            );
            candidateJson = candidate?.toJson();
          } on AiResponseException catch (e) {
            providerError = e;
            diagnostic = e.message;
            kind = result != null
                ? 'validation'
                : e.statusCode == 429
                ? 'rate_limit'
                : e.statusCode == 402
                ? 'quota_exhausted'
                : e.kind;
          } on SpecException catch (e) {
            diagnostic = e.message;
            kind = 'validation';
          } catch (e) {
            diagnostic = 'Unexpected ${e.runtimeType}';
            kind = 'internal_error';
          }
          watch.stop();
          final success = diagnostic == null;
          final usage = result?.usage ?? providerError?.usage;
          attempts.add(<String, dynamic>{
            'number': attempts.length + 1,
            'elapsedMs': watch.elapsedMilliseconds,
            'dispatchedAt': dispatchedAt,
            'completedAt': DateTime.now().toUtc().toIso8601String(),
            'success': success,
            'kind': kind,
            if (providerError != null) 'detailKind': providerError.kind,
            'diagnostic': ?diagnostic,
            if (providerError?.statusCode != null)
              'httpStatus': providerError!.statusCode,
            if (providerError?.retryAfter != null)
              'retryAfterSeconds': providerError!.retryAfter!.inSeconds,
            'usage': ?usage,
            if (result?.pipelineEvidence != null ||
                providerError?.pipelineEvidence != null)
              'pipelineEvidence':
                  result?.pipelineEvidence ?? providerError?.pipelineEvidence,
            if (result?.rawText != null) 'providerResponse': result!.rawText,
            if (result != null || providerError?.syntheticResponse != null)
              'syntheticResponse':
                  result?.text ?? providerError!.syntheticResponse,
          });
          row.remove('inFlightAttempt');
          row['totalMs'] = (row['totalMs'] as int) + watch.elapsedMilliseconds;
          row['success'] = success;
          row['status'] = success ? 'passed' : 'pending';
          if (candidateJson != null && success) {
            row['candidate'] = candidateJson;
          }
          if (diagnostic != null) row['diagnostic'] = diagnostic;
          if (usage?['cost'] is num && (usage!['cost'] as num) > 0) {
            row['status'] = 'blocked';
            checkpoint['status'] = 'blocked';
            checkpoint['billingGuardTripped'] = true;
            checkpoint['blockedReason'] = 'Provider reported nonzero cost on a free-only route; no further requests dispatched.';
            await save(checkpoint);
            return;
          }
          if (providerError?.statusCode == 202) {
            row['status'] = 'indeterminate';
            checkpoint['status'] = 'incomplete';
            checkpoint['blockedReason'] = 'Provider accepted asynchronous work (HTTP 202); request outcome is unknown and will not be replayed.';
            await save(checkpoint);
            return;
          }
          if ({402, 429, 401, 403}.contains(providerError?.statusCode)) {
            row['status'] = 'blocked';
            checkpoint['status'] = 'blocked';
            checkpoint['blockedReason'] =
                '$kind (HTTP ${providerError!.statusCode}); resume explicitly after availability changes.';
            await save(checkpoint);
            return;
          }
          await save(checkpoint);
          log(
            '${scenario.id} | $model | ${success ? 'PASS' : kind} | attempt ${attempts.length} | ${watch.elapsedMilliseconds} ms',
          );
          if (success) break;
          if (providerError?.retryable == false ||
              {400, 404, 405, 422}.contains(providerError?.statusCode) ||
              kind == 'internal_error') {
            break;
          }
          await delay(requestInterval);
        }
        if (row['status'] == 'pending' || row['status'] == 'blocked') {
          row['status'] = 'failed';
          await save(checkpoint);
        }
        await delay(requestInterval);
      }
    }
    checkpoint['status'] = rows.any((r) => r['status'] == 'indeterminate')
        ? 'incomplete'
        : 'completed';
    await save(checkpoint);
  }

  Future<void> _runParallel({int? maxRequests}) async {
    if (checkpoint['billingGuardTripped'] == true) {
      throw const FormatException(
        'Billing guard was tripped; this run cannot resume.',
      );
    }
    final stateGate = NemotronAsyncGate();
    final dispatchGate = NemotronAsyncGate();
    final clock = Stopwatch()..start();
    Duration? lastDispatch;
    var stopped = false;
    var requests = 0;
    var active = 0;
    var peakActive = 0;
    final models = List<String>.from(checkpoint['models'] as List);
    final rows = (checkpoint['operations'] as List)
        .cast<Map<String, dynamic>>();

    Future<void> persist() async {
      try {
        await save(checkpoint);
      } catch (_) {
        stopped = true;
        if (checkpoint['billingGuardTripped'] != true) {
          checkpoint['status'] = 'incomplete';
          checkpoint['blockedReason'] =
              'Checkpoint write failed; no further requests dispatched.';
        }
        rethrow;
      }
    }

    await stateGate.run(() async {
      checkpoint['executionObserved'] = {
        'requestsDispatchedThisInvocation': 0,
        'peakConcurrentRequestsThisInvocation': 0,
      };
      for (final row in rows.where((r) => r['status'] == 'in_flight')) {
        row['status'] = 'indeterminate';
        row['diagnostic'] =
            'Interrupted request has an unknown outcome; not replayed.';
      }
      checkpoint['status'] = 'running';
      checkpoint.remove('blockedReason');
      await persist();
    });

    await runNemotronModelLanes<(String, NemotronScenario)>(
      [
        for (final model in models)
          [for (final scenario in scenarios) (model, scenario)],
      ],
      concurrency: concurrency,
      shouldStop: () => stopped,
      execute: (work) async {
        final (model, scenario) = work;
        final row = rows.singleWhere(
          (r) => r['model'] == model && r['case'] == scenario.id,
        );
        AppSpec? baseline;
        final ready = await stateGate.run(() async {
          if (stopped || !{'pending', 'blocked'}.contains(row['status'])) {
            return false;
          }
          baseline =
              {'create', 'unsupported', 'guidance'}.contains(scenario.operation)
              ? starterTemplates()['reading']!
              : scenario.baseline;
          if (scenario.sequenceSourceId != null) {
            final source = rows.singleWhere(
              (r) =>
                  r['model'] == model && r['case'] == scenario.sequenceSourceId,
            );
            if (source['status'] != 'passed') {
              row['status'] = 'skipped';
              row['diagnostic'] =
                  'Source creation did not pass; no substitute baseline used.';
              await persist();
              return false;
            }
            baseline = AppSpec.parse(jsonEncode(source['candidate']));
          }
          if ((row['attempts'] as List).length >= 3) {
            row['status'] = 'failed';
            await persist();
            return false;
          }
          return true;
        });
        if (!ready) return true;
        final attempts = row['attempts'] as List;
        final last = attempts.isEmpty ? null : attempts.last as Map;
        final diagnostics = last?['diagnostic'] is String
            ? [last!['diagnostic'] as String]
            : <String>[];
        Future<AiResult>? invocation;
        late final String dispatchedAt;
        late final Stopwatch watch;
        final dispatched = await dispatchGate.run(() async {
          if (stopped) return false;
          if (lastDispatch != null) {
            final remaining = requestInterval - (clock.elapsed - lastDispatch!);
            if (remaining > Duration.zero) await delay(remaining);
          }
          return stateGate.run(() async {
            if (stopped) return false;
            if (maxRequests != null && requests >= maxRequests) {
              stopped = true;
              checkpoint['status'] = 'blocked';
              checkpoint['blockedReason'] =
                  'Requested per-invocation request cap reached.';
              await persist();
              return false;
            }
            // Reserve before any await; the network starts only after this
            // in-flight marker has been durably saved.
            requests++;
            final previousStatus = row['status'];
            row['status'] = 'in_flight';
            row['inFlightAttempt'] = attempts.length + 1;
            try {
              await persist();
            } catch (_) {
              // This request was never sent. A later draining save can persist
              // the rollback; a partially written disk marker remains safely
              // indeterminate on resume if storage stays unavailable.
              requests--;
              row['status'] = previousStatus;
              row.remove('inFlightAttempt');
              rethrow;
            }
            lastDispatch = clock.elapsed;
            dispatchedAt = DateTime.now().toUtc().toIso8601String();
            watch = Stopwatch()..start();
            active++;
            if (active > peakActive) peakActive = active;
            // Start under the same state gate as the successful marker save:
            // no observed stop can interleave between persistence and dispatch.
            invocation = Future<AiResult>.sync(
              () => invoke(
                model,
                scenario,
                baseline!,
                diagnostics,
                last?['syntheticResponse'] as String?,
              ),
            );
            // Attach an immediate handler while outer gates release. The
            // original future is still awaited below to retain the error.
            unawaited(
              invocation!.then<void>(
                (_) {},
                onError: (Object _, StackTrace _) {},
              ),
            );
            return true;
          });
        });
        if (!dispatched) return true;

        AiResult? result;
        AiResponseException? providerError;
        Map<String, dynamic>? candidateJson;
        String? diagnostic;
        var kind = 'received';
        try {
          result = await invocation!;
          final candidate = scoreNemotronResult(
            scenario,
            result.text,
            baseline!,
          );
          candidateJson = candidate?.toJson();
        } on AiResponseException catch (e) {
          providerError = e;
          diagnostic = e.message;
          kind = result != null
              ? 'validation'
              : e.statusCode == 429
              ? 'rate_limit'
              : e.statusCode == 402
              ? 'quota_exhausted'
              : e.kind;
        } on SpecException catch (e) {
          diagnostic = e.message;
          kind = 'validation';
        } catch (e) {
          diagnostic = 'Unexpected ${e.runtimeType}';
          kind = 'internal_error';
        } finally {
          watch.stop();
          active--;
        }
        final completedAt = DateTime.now().toUtc().toIso8601String();
        return stateGate.run(() async {
          final success = diagnostic == null;
          final usage = result?.usage ?? providerError?.usage;
          attempts.add(<String, dynamic>{
            'number': attempts.length + 1,
            'elapsedMs': watch.elapsedMilliseconds,
            'dispatchedAt': dispatchedAt,
            'completedAt': completedAt,
            'success': success,
            'kind': kind,
            if (providerError != null) 'detailKind': providerError.kind,
            'diagnostic': ?diagnostic,
            if (providerError?.statusCode != null)
              'httpStatus': providerError!.statusCode,
            if (providerError?.retryAfter != null)
              'retryAfterSeconds': providerError!.retryAfter!.inSeconds,
            'usage': ?usage,
            if (result?.pipelineEvidence != null ||
                providerError?.pipelineEvidence != null)
              'pipelineEvidence':
                  result?.pipelineEvidence ?? providerError?.pipelineEvidence,
            if (result?.rawText != null) 'providerResponse': result!.rawText,
            if (result != null || providerError?.syntheticResponse != null)
              'syntheticResponse':
                  result?.text ?? providerError!.syntheticResponse,
          });
          row.remove('inFlightAttempt');
          row['totalMs'] = (row['totalMs'] as int) + watch.elapsedMilliseconds;
          row['success'] = success;
          row['status'] = success ? 'passed' : 'pending';
          if (candidateJson != null && success) {
            row['candidate'] = candidateJson;
          }
          if (diagnostic != null) row['diagnostic'] = diagnostic;
          checkpoint['executionObserved'] = {
            'requestsDispatchedThisInvocation': requests,
            'peakConcurrentRequestsThisInvocation': peakActive,
          };
          if (usage?['cost'] is num && (usage!['cost'] as num) > 0) {
            row['status'] = 'blocked';
            checkpoint['status'] = 'blocked';
            checkpoint['billingGuardTripped'] = true;
            checkpoint['blockedReason'] = 'Provider reported nonzero cost on a free-only route; no further requests dispatched.';
            stopped = true;
          } else if (providerError?.statusCode == 202) {
            row['status'] = 'indeterminate';
            if (!stopped) {
              checkpoint['status'] = 'incomplete';
              checkpoint['blockedReason'] = 'Provider accepted asynchronous work (HTTP 202); request outcome is unknown and will not be replayed.';
            }
            stopped = true;
          } else if ({402, 429, 401, 403}.contains(providerError?.statusCode)) {
            row['status'] = 'blocked';
            if (!stopped) {
              checkpoint['status'] = 'blocked';
              checkpoint['blockedReason'] =
                  '$kind (HTTP ${providerError!.statusCode}); resume explicitly after availability changes.';
            }
            stopped = true;
          }
          final retry =
              !success &&
              !stopped &&
              attempts.length < 3 &&
              providerError?.retryable != false &&
              !{400, 404, 405, 422}.contains(providerError?.statusCode) &&
              kind != 'internal_error';
          if (!retry && !stopped && row['status'] == 'pending') {
            row['status'] = 'failed';
          }
          await persist();
          log(
            '${scenario.id} | $model | ${success ? 'PASS' : kind} | attempt ${attempts.length} | ${watch.elapsedMilliseconds} ms',
          );
          return !retry;
        });
      },
    );
    await stateGate.run(() async {
      if (!stopped) {
        checkpoint['status'] = rows.any((r) => r['status'] == 'indeterminate')
            ? 'incomplete'
            : 'completed';
      }
      await persist();
    });
  }
}
