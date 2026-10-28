/// Aggregates a frozen synthetic provider benchmark without runtime dependencies.
///
/// A provider/quota failure is an availability result, not a model correctness
/// failure. Missing usage stays unknown; retries contribute to all usage totals.
Map<String, dynamic> summarizeNemotronEvaluation(
  Map<String, dynamic> checkpoint,
) {
  final provider = checkpoint['provider'] as String? ?? 'openrouter';
  final nvidia = provider == 'nvidia';
  final models = (checkpoint['models'] as List? ?? const [])
      .whereType<String>()
      .toList();
  final scenarios = _maps(checkpoint['scenarios']);
  final operations = _maps(checkpoint['operations']);
  final planned = <String, int>{for (final name in _categories) name: 0};
  for (final scenario in scenarios) {
    final category = _category(scenario);
    if (planned.containsKey(category)) {
      planned[category] = planned[category]! + 1;
    }
  }
  final summaries = <String, dynamic>{};
  for (final model in models) {
    final rows = operations.where((row) => row['model'] == model).toList();
    summaries[model] = {
      ..._summarize(rows, planned.values.fold<int>(0, (a, b) => a + b)),
      'categories': {
        for (final category in _categories)
          category: _summarize(
            rows.where((row) => _category(row) == category).toList(),
            planned[category]!,
          ),
      },
    };
  }
  return {
    'schemaVersion': 1,
    'provider': provider,
    'apiBase': checkpoint['apiBase'],
    'benchmarkVersion': checkpoint['benchmarkVersion'],
    'benchmarkLabel':
        checkpoint['benchmarkLabel'] ?? 'AppNest Nemotron evaluation',
    'creationPipeline': ?checkpoint['creationPipeline'],
    'modelFamilies': checkpoint['modelFamilies'],
    'status': checkpoint['status'],
    'createdAt': checkpoint['createdAt'],
    'updatedAt': checkpoint['updatedAt'],
    'source': checkpoint['source'],
    'runFingerprint': checkpoint['runFingerprint'],
    'catalog': checkpoint['catalog'],
    'transportProfiles': checkpoint['transportProfiles'],
    'execution':
        checkpoint['execution'] ??
        const {
          'concurrency': 1,
          'requestIntervalMs': 4000,
          'pacing': 'serial-delay',
          'perModelSequential': true,
        },
    'executionObserved': checkpoint['executionObserved'],
    'models': summaries,
    'plannedPerModel': planned.values.fold<int>(0, (a, b) => a + b),
    'plannedCategories': planned,
    'recommendations': {
      'create': _recommend(summaries, 'create'),
      'edit': _recommend(summaries, 'edit'),
    },
    'expectedPriceUsd': nvidia ? null : 0,
    'expectedCostBasis': nvidia
        ? 'free_developer_endpoint'
        : 'zero_priced_openrouter_free_route',
    'pricingVerified': !nvidia,
    'accountLimitsKnown': false,
    'limitations': [
      'Exploratory single-trial measurements; no statistical reliability claim.',
      'Synthetic provider and definition checks only. No authenticated '
          'persistence, Flutter rendering, publication, device, or production '
          'acceptance is established.',
      'Transport, quota, and unavailable-model failures are availability '
          'results and excluded from observed correctness rates.',
      'Known token and cost sums include every attempt. Missing usage is '
          'unknown and is never replaced with zero.',
    ],
  };
}

/// Renders a compact report from the same checkpoint used for JSON aggregation.
String renderNemotronReport(Map<String, dynamic> checkpoint) {
  final summary = summarizeNemotronEvaluation(checkpoint);
  final models = _map(summary['models']);
  final nvidia = summary['provider'] == 'nvidia';
  final execution = _map(summary['execution']);
  final observed = _map(summary['executionObserved']);
  final buffer = StringBuffer()
    ..writeln(
      '# ${_cell(summary['benchmarkLabel'])} (${_cell(summary['provider'])})',
    )
    ..writeln()
    ..writeln(
      summary['creationPipeline'] == null
          ? ''
          : 'Creation pipeline: ${summary['creationPipeline']['pipeline']}. '
                'This measures the combined pipeline; individual serving models are recorded per attempt.',
    )
    ..writeln(
      'Status: ${_cell(summary['status'])}. '
      'Benchmark: ${_cell(summary['benchmarkVersion'])}. '
      'Planned operations per model: ${summary['plannedPerModel']}.',
    )
    ..writeln()
    ..writeln(
      'Execution: concurrency ${execution['concurrency']}; '
      '${_cell(execution['pacing'])} pacing ${execution['requestIntervalMs']} ms; '
      'operations within each model are sequential.'
      '${observed['peakConcurrentRequestsThisInvocation'] == null ? '' : ' Observed peak concurrent requests in the latest invocation: ${observed['peakConcurrentRequestsThisInvocation']}.'}',
    )
    ..writeln()
    ..writeln(
      checkpoint['blockedReason'] == null
          ? ''
          : 'Pause reason: ${_cell(checkpoint['blockedReason'])}.',
    )
    ..writeln(
      'Synthetic provider and definition benchmark; one trial per '
      'scenario. These results do not establish authenticated persistence, '
      'Flutter rendering, publication, device, or production behavior.',
    )
    ..writeln()
    ..writeln(
      'Observed correctness rates exclude operations without a model '
      'response. Planned pass rates include the full denominator. All retries '
      'contribute to latency and known token/cost sums.',
    )
    ..writeln()
    ..writeln(
      '| Model | Completed / planned | Attempts | Passed | First-pass observed | '
      'Eventual observed / planned | Skipped / pending / blocked / indeterminate | '
      'Availability failures | Median / p95 ms | Known total tokens | '
      'Missing usage attempts |',
    )
    ..writeln(
      '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
    );
  for (final entry in models.entries) {
    final row = _map(entry.value);
    final latency = _map(row['latencyMs']);
    final usage = _map(row['usage']);
    buffer.writeln(
      '| ${_cell(entry.key)} | '
      '${row['completed']} / ${row['planned']} | ${row['attemptCount']} | '
      '${row['passed']} | '
      '${_percent(row['firstAttemptPassRateObserved'])} | '
      '${_percent(row['eventualPassRateObserved'])} / '
      '${_percent(row['eventualPassRatePlanned'])} | '
      '${row['skipped']} / ${row['pending']} / ${row['blocked']} / '
      '${row['indeterminate']} | '
      '${row['availabilityFailureAttempts']} attempts | '
      '${_number(latency['median'])} / ${_number(latency['p95'])} | '
      '${_number(usage['totalTokens'])} | ${usage['missingUsageAttempts']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Category results')
    ..writeln()
    ..writeln(
      '| Model | Category | Completed / planned | Correctness scored | '
      'Passed | First-pass observed | Eventual observed / planned | '
      'Coverage |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- |');
  for (final entry in models.entries) {
    final categories = _map(_map(entry.value)['categories']);
    for (final category in _categories) {
      final row = _map(categories[category]);
      buffer.writeln(
        '| ${_cell(entry.key)} | $category | '
        '${row['completed']} / ${row['planned']} | '
        '${row['correctnessCompleted']} | ${row['passed']} | '
        '${_percent(row['firstAttemptPassRateObserved'])} | '
        '${_percent(row['eventualPassRateObserved'])} / '
        '${_percent(row['eventualPassRatePlanned'])} | '
        '${_percent(row['completionCoverage'])} |',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Recommendations')
    ..writeln();
  final recommendations = _map(summary['recommendations']);
  for (final category in const ['create', 'edit']) {
    final recommendation = _map(recommendations[category]);
    buffer.writeln('- **$category:** ${recommendation['explanation']}');
  }
  buffer
    ..writeln()
    ..writeln(
      'Recommendations are exploratory. Correctness ranks first, '
      'then first-attempt success, median latency, and known total tokens; '
      'unknown usage never wins a tie. The application model is unchanged.',
    )
    ..writeln()
    ..writeln('## Usage and availability')
    ..writeln()
    ..writeln(
      nvidia
          ? 'NVIDIA free developer endpoint, account limits unknown. The trial '
                'API is expected to be free; unit pricing and account quota are '
                'unverified. Provider-reported cost remains unknown when omitted. '
                'Partial sums are labeled below.'
          : 'Expected route price: USD 0 under OpenRouter free-route pricing '
                'constraints. Provider-reported cost remains unknown when '
                'omitted. Partial sums are labeled below.',
    )
    ..writeln();
  for (final entry in models.entries) {
    final row = _map(entry.value);
    final usage = _map(row['usage']);
    buffer.writeln(
      '- **${_cell(entry.key)}:** known prompt / completion / '
      'total / reasoning tokens: ${_number(usage['promptTokens'])} / '
      '${_number(usage['completionTokens'])} / '
      '${_number(usage['totalTokens'])} / '
      '${_number(usage['reasoningTokens'])}; usage complete: '
      '${usage['complete']}; reported cost USD: '
      '${_number(usage['costReportedUsd'])} '
      '(complete: ${usage['costComplete']}); availability-only outcomes: '
      '${row['availabilityOnlyFailures']}; availability kinds: '
      '${_cell(row['availabilityFailureKinds'])}.',
    );
  }
  final operations = _maps(checkpoint['operations']);
  final failures = operations.where(
    (row) => row['status'] == 'failed' || row['status'] == 'blocked',
  );
  if (failures.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Failure examples')
      ..writeln()
      ..writeln(
        'The checkpoint retains synthetic responses, definitions, and '
        'every attempt for offline replay. Up to three examples per model:',
      )
      ..writeln();
    for (final model in models.keys) {
      for (final row
          in failures.where((row) => row['model'] == model).take(3)) {
        final attempts = _maps(row['attempts']);
        final last = attempts.isEmpty ? <String, dynamic>{} : attempts.last;
        final diagnostic = last['diagnostic'] ?? row['diagnostic'];
        buffer.writeln(
          '- **${_cell(model)} / ${_cell(row['case'])}** '
          '(${_category(row)}, ${_cell(row['status'])}): '
          '${_cell(last['kind'] ?? 'no attempt')}'
          '${last['httpStatus'] == null ? '' : ' HTTP ${last['httpStatus']}'}'
          '${diagnostic == null ? '.' : ': ${_cell(diagnostic, max: 500)}'}',
        );
      }
    }
  }
  buffer
    ..writeln()
    ..writeln('## Provenance')
    ..writeln();
  final source = _map(checkpoint['source']);
  buffer
    ..writeln('- Commit: `${_cell(source['commit'])}`')
    ..writeln(
      '- Tracked dirty diff SHA-256: '
      '`${_cell(source['dirtyTrackedSha256'])}`',
    )
    ..writeln(
      '- Frozen run fingerprint: '
      '`${_cell(checkpoint['runFingerprint'])}`',
    )
    ..writeln('- Updated: ${_cell(checkpoint['updatedAt'])}.');
  if (checkpoint['apiBase'] != null) {
    buffer.writeln('- API base: ${_cell(checkpoint['apiBase'])}.');
  }
  final catalog = _maps(checkpoint['catalog']);
  final profiles = _map(checkpoint['transportProfiles']);
  if (catalog.isNotEmpty || profiles.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Frozen route configuration')
      ..writeln()
      ..writeln(
        'Provider routes and transport adaptations were frozen for the scored '
        'run. Profiles shape requests for each provider; local schema, '
        'semantic, unsupported-request, and repair checks remain authoritative. '
        'The report does not infer provider-side schema enforcement.',
      )
      ..writeln()
      ..writeln(
        nvidia
            ? '| Model | Endpoint availability / pricing | Supported parameters | '
                  'Transport profile | Source |'
            : '| Model | Pricing | Supported parameters | Transport profile |',
      )
      ..writeln(
        nvidia
            ? '| --- | --- | --- | --- | --- |'
            : '| --- | --- | --- | --- |',
      );
    for (final model in models.keys) {
      final matches = catalog.where((row) => row['id'] == model);
      final route = matches.isEmpty ? <String, dynamic>{} : matches.first;
      final pricing = nvidia
          ? 'freeEndpoint: ${_cell(route['freeEndpoint'])}; '
                'pricingVerified: ${_cell(route['pricingVerified'])}; '
                'account limits unknown'
          : _cell(route['pricing']);
      buffer.writeln(
        '| ${_cell(model)} | $pricing | '
        '${_cell(route['supported_parameters'] ?? route['supportedParameters'], max: 500)} | '
        '${_cell(profiles[model], max: 1000)} |'
        '${nvidia ? ' ${_cell(route['sourceUrl'], max: 1000)} |' : ''}',
      );
    }
  }
  return buffer.toString();
}

const _categories = ['create', 'edit', 'guidance', 'unsupported', 'sequence'];
const _availabilityKinds = {
  'http_error',
  'timeout',
  'transport_error',
  'quota',
  'quota_exhausted',
  'rate_limit',
  'unavailable',
  'interrupted',
  'provider_error',
  'auth_error',
  'configuration_error',
};

Map<String, dynamic> _summarize(List<Map<String, dynamic>> rows, int planned) {
  final completed = rows.where(_completed).toList();
  final scored = completed.where(_scored).toList();
  final attempted = rows.where((row) => _maps(row['attempts']).isNotEmpty);
  final attempts = rows.expand((row) => _maps(row['attempts'])).toList();
  final passed = completed.where((row) => row['status'] == 'passed').length;
  final firstPass = scored.where((row) {
    final attempts = _maps(row['attempts']);
    return attempts.isNotEmpty && attempts.first['success'] == true;
  }).length;
  final availability = attempts.where(_availabilityFailure).toList();
  final kinds = <String, int>{};
  for (final attempt in availability) {
    final kind = '${attempt['kind']}';
    kinds[kind] = (kinds[kind] ?? 0) + 1;
  }
  final latencies =
      completed.map((row) => _numeric(row['totalMs'])).whereType<num>().toList()
        ..sort((a, b) => a.compareTo(b));
  final skipped = rows.where((row) => row['status'] == 'skipped').length;
  final blocked = rows.where((row) => row['status'] == 'blocked').length;
  final inFlight = rows.where((row) => row['status'] == 'in_flight').length;
  final indeterminate = rows
      .where((row) => row['status'] == 'indeterminate')
      .length;
  final missing = planned > rows.length ? planned - rows.length : 0;
  final pending =
      rows.where((row) => row['status'] == 'pending').length + missing;
  return {
    'planned': planned,
    'attempted': attempted.length,
    'completed': completed.length,
    'passed': passed,
    'failed': completed.length - passed,
    'correctnessCompleted': scored.length,
    'correctnessFailed': scored.length - passed,
    'firstAttemptPassed': firstPass,
    'skipped': skipped,
    'pending': pending,
    'inFlight': inFlight,
    'indeterminate': indeterminate,
    'blocked': blocked,
    'availabilityFailureAttempts': availability.length,
    'availabilityFailureKinds': kinds,
    'availabilityOnlyFailures': completed.where((row) => !_scored(row)).length,
    'attemptCount': attempts.length,
    'completionCoverage': _rate(completed.length, planned),
    'resolvedCoverage': _rate(completed.length + skipped, planned),
    'correctnessCoverage': _rate(scored.length, planned),
    'firstAttemptPassRateObserved': _rate(firstPass, scored.length),
    'firstAttemptPassRatePlanned': _rate(firstPass, planned),
    'eventualPassRateObserved': _rate(passed, scored.length),
    'eventualPassRatePlanned': _rate(passed, planned),
    'latencyMs': {
      'sampleCount': latencies.length,
      'median': _median(latencies),
      'p95': _nearestRank(latencies, .95),
      'quantileMethod': 'median midpoint; p95 nearest rank',
    },
    'usage': _usage(attempts),
  };
}

Map<String, dynamic> _usage(List<Map<String, dynamic>> attempts) {
  final sums = <String, num>{};
  final known = <String, int>{};
  var missing = 0;
  for (final attempt in attempts) {
    final usage = _map(attempt['usage']);
    final details = _map(
      usage['completion_tokens_details'] ?? usage['completionTokensDetails'],
    );
    final values = <String, dynamic>{
      'promptTokens': usage['prompt_tokens'] ?? usage['promptTokens'],
      'completionTokens':
          usage['completion_tokens'] ?? usage['completionTokens'],
      'totalTokens': usage['total_tokens'] ?? usage['totalTokens'],
      'reasoningTokens':
          usage['reasoning_tokens'] ??
          usage['reasoningTokens'] ??
          details['reasoning_tokens'] ??
          details['reasoningTokens'],
      'costReportedUsd': usage['cost'],
    };
    if (values.entries
        .where((entry) => entry.key != 'costReportedUsd')
        .every((entry) => _numeric(entry.value) == null)) {
      missing++;
    }
    for (final entry in values.entries) {
      final value = _numeric(entry.value);
      if (value == null) continue;
      sums[entry.key] = (sums[entry.key] ?? 0) + value;
      known[entry.key] = (known[entry.key] ?? 0) + 1;
    }
  }
  final hasAttempts = attempts.isNotEmpty;
  return {
    for (final metric in const [
      'promptTokens',
      'completionTokens',
      'totalTokens',
      'reasoningTokens',
      'costReportedUsd',
    ])
      metric: sums[metric],
    'knownAttempts': known,
    'attemptCount': attempts.length,
    'missingUsageAttempts': missing,
    'complete':
        hasAttempts &&
        const ['promptTokens', 'completionTokens', 'totalTokens'].every(
          (metric) => known[metric] == attempts.length,
        ),
    'reasoningComplete':
        hasAttempts && known['reasoningTokens'] == attempts.length,
    'costComplete': hasAttempts && known['costReportedUsd'] == attempts.length,
  };
}

Map<String, dynamic> _recommend(Map<String, dynamic> models, String category) {
  final rows = <MapEntry<String, Map<String, dynamic>>>[
    for (final entry in models.entries)
      MapEntry(
        entry.key,
        _map(_map(_map(entry.value)['categories'])[category]),
      ),
  ];
  final planned = rows.isEmpty ? 0 : rows.first.value['planned'];
  if (rows.length < 2 ||
      planned == 0 ||
      rows.any(
        (row) =>
            row.value['planned'] != planned ||
            row.value['correctnessCompleted'] != planned ||
            row.value['pending'] != 0 ||
            row.value['blocked'] != 0 ||
            row.value['inFlight'] != 0,
      )) {
    return {
      'status': 'incomplete_evidence',
      'model': null,
      'explanation':
          'No winner: complete comparable $category correctness '
          'coverage is required for every selected model.',
    };
  }
  // Use a shared tie-breaker set for the whole comparison. Pairwise omission of
  // unknown values would make the sort non-transitive and could invent a winner.
  final useLatency = rows.every(
    (row) =>
        _numeric(_map(row.value['latencyMs'])['median']) != null &&
        _map(row.value['latencyMs'])['sampleCount'] == planned,
  );
  final useTokens = rows.every(
    (row) => _map(row.value['usage'])['complete'] == true,
  );
  int compare(
    MapEntry<String, Map<String, dynamic>> a,
    MapEntry<String, Map<String, dynamic>> b,
  ) => _compare(a, b, useLatency: useLatency, useTokens: useTokens);
  rows.sort(compare);
  if (rows.first.value['passed'] == 0) {
    return {
      'status': 'no_passing_candidate',
      'model': null,
      'explanation': 'No recommendation: no model passed a $category scenario.',
    };
  }
  final best = rows.first;
  final ties = rows.where((row) => compare(best, row) == 0).toList();
  if (ties.length > 1) {
    return {
      'status': 'tie',
      'model': null,
      'models': ties.map((row) => row.key).toList(),
      'explanation':
          'No unique winner: ${ties.map((row) => row.key).join(', ')} '
          'tie on correctness, first-attempt success, and available tie-breakers.',
    };
  }
  return {
    'status': 'exploratory_recommendation',
    'model': best.key,
    'ranking': rows.map((row) => row.key).toList(),
    'explanation':
        '${best.key} leads the complete $category comparison '
        '(${best.value['passed']}/$planned eventual, '
        '${best.value['firstAttemptPassed']}/$planned first attempt).',
  };
}

int _compare(
  MapEntry<String, Map<String, dynamic>> a,
  MapEntry<String, Map<String, dynamic>> b, {
  required bool useLatency,
  required bool useTokens,
}) {
  for (final metric in const ['passed', 'firstAttemptPassed']) {
    final comparison = (b.value[metric] as int).compareTo(
      a.value[metric] as int,
    );
    if (comparison != 0) return comparison;
  }
  final latencyA = _numeric(_map(a.value['latencyMs'])['median']);
  final latencyB = _numeric(_map(b.value['latencyMs'])['median']);
  if (useLatency) {
    final comparison = latencyA!.compareTo(latencyB!);
    if (comparison != 0) return comparison;
  }
  final usageA = _map(a.value['usage']);
  final usageB = _map(b.value['usage']);
  if (useTokens) {
    return (usageA['totalTokens'] as num).compareTo(
      usageB['totalTokens'] as num,
    );
  }
  return 0;
}

String _category(Map<String, dynamic> row) =>
    row['sequenceSourceId'] != null ? 'sequence' : '${row['operation']}';

bool _completed(Map<String, dynamic> row) =>
    row['status'] == 'passed' || row['status'] == 'failed';

bool _scored(Map<String, dynamic> row) =>
    row['status'] == 'passed' ||
    _maps(row['attempts']).any(
      (attempt) =>
          !_availabilityFailure(attempt) &&
          (attempt['kind'] == 'received' ||
              attempt['kind'] == 'validation' ||
              {
                'truncated',
                'completion_stopped',
                'content_missing',
                'output_json',
                'output_shape',
                'output_size',
                'guidance_completion',
                'pipeline_validation',
              }.contains(attempt['kind']) ||
              attempt['success'] == true),
    );

bool _availabilityFailure(Map<String, dynamic> attempt) =>
    _availabilityKinds.contains(attempt['kind']);

num? _numeric(dynamic value) =>
    value is num && value.isFinite && value >= 0 ? value : null;

double? _rate(int numerator, int denominator) =>
    denominator == 0 ? null : numerator / denominator;

num? _median(List<num> values) {
  if (values.isEmpty) return null;
  final middle = values.length ~/ 2;
  return values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
}

num? _nearestRank(List<num> values, double quantile) =>
    values.isEmpty ? null : values[(values.length * quantile).ceil() - 1];

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : const [];

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

String _percent(dynamic value) =>
    value is num ? '${(value * 100).toStringAsFixed(1)}%' : 'unknown';

String _number(dynamic value) => value is num ? '$value' : 'unknown';

String _cell(dynamic value, {int max = 200}) {
  if (value == null) return 'unknown';
  final text = '$value'
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .replaceAll('|', '\\|')
      .replaceAll('`', "'");
  return text.length > max ? '${text.substring(0, max)}…' : text;
}
