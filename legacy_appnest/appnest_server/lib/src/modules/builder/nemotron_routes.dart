import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider.dart';

const nvidiaEvaluationBase = 'https://integrate.api.nvidia.com/v1';
const openRouterEvaluationBase = 'https://openrouter.ai/api/v1';

class NemotronEvaluationRoute {
  final String name, base, credentialName, outputDirectory;
  final List<String> models;
  const NemotronEvaluationRoute(
    this.name,
    this.base,
    this.credentialName,
    this.outputDirectory,
    this.models,
  );
  bool get isNvidia => name == 'nvidia';
  List<String> get allowedModels => isNvidia ? nvidiaEvaluationModels : models;
}

NemotronEvaluationRoute nemotronRoute(String name) => switch (name) {
  'nvidia' => const NemotronEvaluationRoute(
    'nvidia',
    nvidiaEvaluationBase,
    'NVIDIA_API_KEY',
    'nemotron-eval-nvidia',
    nvidiaNemotronModels,
  ),
  'openrouter' => const NemotronEvaluationRoute(
    'openrouter',
    openRouterEvaluationBase,
    'OPENROUTER_API_KEY',
    'nemotron-eval',
    freeNemotronModels,
  ),
  _ => throw const FormatException(
    'Choose --provider=nvidia or --provider=openrouter.',
  ),
};

void validateNemotronModelSelection(
  List<String> selected,
  NemotronEvaluationRoute route,
) {
  if (selected.isEmpty ||
      selected.toSet().length != selected.length ||
      selected.any((model) => !route.allowedModels.contains(model))) {
    throw FormatException(
      'Select distinct exact allowlisted ${route.name} model IDs.',
    );
  }
}

/// The NVIDIA model API does not publish pricing or trial quota. Require the
/// official model page to explicitly advertise a free endpoint before dispatch.
Map<String, dynamic> validateNvidiaFreeEndpointPage(String model, String html) {
  validateNemotronModelSelection([model], nemotronRoute('nvidia'));
  final profile = nvidiaEvaluationProfile(model);
  final text = html
      .replaceAll(
        RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  final identity = RegExp(
    r'(?<![A-Za-z0-9_.-])' +
        RegExp.escape(profile.catalogPath.split('/').last) +
        r'(?![A-Za-z0-9_.-])',
  );
  if (!identity.hasMatch(text) ||
      !text.contains('Start building with a free API endpoint.') ||
      !RegExp(r'Model Availability\s+Free Endpoint\s+Available\b')
          .hasMatch(text)) {
    throw FormatException(
      'NVIDIA does not advertise an available free endpoint for $model.',
    );
  }
  return {
    'id': model,
    'freeEndpoint': true,
    'sourceUrl': profile.catalogUrl,
    'family': profile.family,
    'pricingVerified': false,
    'supportedParameters': null,
  };
}

Future<List<Map<String, dynamic>>> readNvidiaNemotronCatalog(
  http.Client client,
  List<String> models,
) async {
  validateNemotronModelSelection(models, nemotronRoute('nvidia'));
  final entries = <Map<String, dynamic>>[];
  for (final model in models) {
    final html = await (() async {
      final request = http.Request(
        'GET',
        Uri.parse(nvidiaEvaluationProfile(model).catalogUrl),
      )..followRedirects = false;
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw const FormatException(
          'Could not verify NVIDIA free endpoint availability.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) {
          throw const FormatException(
            'NVIDIA catalog page exceeded its bound.',
          );
        }
        bytes.addAll(chunk);
      }
      try {
        return utf8.decode(bytes);
      } on FormatException {
        throw const FormatException('NVIDIA catalog page was not valid UTF-8.');
      }
    })().timeout(const Duration(seconds: 20));
    entries.add(validateNvidiaFreeEndpointPage(model, html));
  }
  return entries;
}

/// An authenticated model listing checks credentials without consuming a chat
/// completion. It establishes access, never a numerical free-trial allowance.
Future<Map<String, dynamic>> readNvidiaNemotronAccess(
  http.Client client,
  String key,
  List<String> models,
) async {
  validateNemotronModelSelection(models, nemotronRoute('nvidia'));
  return (() async {
    final request =
        http.Request('GET', Uri.parse('$nvidiaEvaluationBase/models'))
          ..followRedirects = false
          ..headers['Authorization'] = 'Bearer $key';
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw AiResponseException(
        'preflight_http',
        'NVIDIA credential/model-access check failed.',
        statusCode: response.statusCode,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const FormatException('NVIDIA model listing exceeded its bound.');
      }
      bytes.addAll(chunk);
    }
    final dynamic envelope;
    try {
      envelope = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const FormatException('Invalid NVIDIA model listing.');
    }
    final data = envelope is Map ? envelope['data'] : null;
    if (data is! List) {
      throw const FormatException('Invalid NVIDIA model listing.');
    }
    final accessible = data.whereType<Map>().map((m) => m['id']).toSet();
    if (models.any((m) => !accessible.contains(m))) {
      throw const FormatException(
        'A selected NVIDIA model is not available to this credential.',
      );
    }
    return <String, dynamic>{
      'authenticatedCatalogVerified': true,
      'accountLimitsKnown': false,
      'freeRequests': null,
      'completionCallsMade': false,
    };
  })().timeout(const Duration(seconds: 20));
}
