// One explicitly enabled provider guidance probe. No Appwrite or database I/O.
// The fixed receipt prevents rerunning in the same output directory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../lib/providers/provider.dart';

const probeEndpoint = 'https://api.tokenfactory.nebius.com/v1';
const probeModel = 'nvidia/nemotron-3-super-120b-a12b';
const _syntheticIdea =
    'A personal reading list to track book titles and reading progress.';
const _receiptName = 'receipt.json';

/// A single dispatch through an injected client. This wrapper enforces the
/// request target, disables redirects, and only accepts a matching model ID in
/// the provider's response. Mock clients allow fully offline regression tests.
class OneRequestClient extends http.BaseClient {
  OneRequestClient(this._inner);
  final http.Client _inner;
  int sends = 0;
  int? statusCode;
  String modelStatus = 'not_observed';
  String usageStatus = 'unknown';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (sends != 0 ||
        request.method != 'POST' ||
        request.url.toString() != '$probeEndpoint/chat/completions') {
      throw StateError('probe_request_blocked');
    }
    if (request is! http.Request) throw StateError('probe_request_blocked');
    try {
      final body = jsonDecode(request.body);
      if (body is! Map ||
          body['model'] != probeModel ||
          body['max_tokens'] is! int ||
          (body['max_tokens'] as int) < 1 ||
          (body['max_tokens'] as int) > 2048) {
        throw StateError('probe_request_blocked');
      }
    } on FormatException {
      throw StateError('probe_request_blocked');
    }
    request.followRedirects = false;
    request.maxRedirects = 0;
    sends++;
    final response = await _inner.send(request);
    statusCode = response.statusCode;
    if (response.statusCode != 200) return response;
    final bytes = <int>[];
    await for (final part in response.stream) {
      if (bytes.length + part.length > 8192) {
        modelStatus = 'invalid_envelope';
        throw StateError('probe_response_too_large');
      }
      bytes.addAll(part);
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map || decoded['model'] is! String) {
        modelStatus = 'missing_model';
        throw const FormatException();
      }
      if (decoded['model'] != probeModel) {
        modelStatus = 'model_mismatch';
        throw const FormatException();
      }
      modelStatus = 'matched';
      final usage = decoded['usage'];
      if (usage is Map &&
          (usage['total_tokens'] is int ||
              usage['completion_tokens'] is int ||
              usage['prompt_tokens'] is int)) {
        usageStatus = 'reported';
      }
    } on FormatException {
      if (modelStatus == 'not_observed') modelStatus = 'invalid_envelope';
      throw StateError('probe_response_model_unverified');
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      headers: response.headers,
      request: response.request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

Future<void> _chmod(String path, String mode) async {
  final result = await Process.run('/bin/chmod', [mode, path]);
  if (result.exitCode != 0) throw StateError('receipt_permissions_failed');
}

/// Returns only fixed categories, counts and validated model identity; never
/// returns provider content, credentials, raw errors, or request headers.
Future<Map<String, Object?>> runGuidanceProbe({
  required Map<String, String> environment,
  required Directory receiptDirectory,
  required http.Client Function() clientFactory,
}) async {
  if (environment['TINKERLOOM_NEBIUS_PROBE'] != '1' ||
      environment['TINKERLOOM_NEBIUS_PROBE_ENDPOINT'] != probeEndpoint ||
      environment['TINKERLOOM_NEBIUS_PROBE_MODEL'] != probeModel ||
      (environment['NEBIUS_API_KEY'] ?? '').trim().isEmpty) {
    throw StateError('probe_configuration_rejected');
  }
  if (await FileSystemEntity.isLink(receiptDirectory.path)) {
    throw StateError('receipt_directory_is_symlink');
  }
  await receiptDirectory.create(recursive: true);
  await _chmod(receiptDirectory.path, '700');
  final receipt = File('${receiptDirectory.path}/$_receiptName');
  await receipt.create(exclusive: true);
  await _chmod(receipt.path, '600');
  final state = <String, Object?>{
    'scope':
        'One synthetic guidance request through the local Tinkerloom Dart provider; no Appwrite calls',
    'status': 'prepared',
    'endpoint': probeEndpoint,
    'requestedModel': probeModel,
    'maximumRequests': 1,
    'maximumCompletionTokens': 2048,
    'requestCount': 0,
    'automaticRetries': 0,
    'redirectsAllowed': false,
    'servedModelStatus': 'not_observed',
    'providerUsageStatus': 'unknown',
    'costQualification':
        'Provider-reported usage does not establish actual cost; an HTTP response does not prove that no charges occurred.',
    'proofBoundary':
        'A response model is provider-reported, not independent attestation. This local request does not prove a deployed or rendered Tinkerloom application flow.',
  };
  await receipt.writeAsString('${jsonEncode(state)}\n', flush: true);

  Future<void> save() async {
    final temporary = File('${receipt.path}.tmp');
    await temporary.create(exclusive: true);
    await _chmod(temporary.path, '600');
    try {
      await temporary.writeAsString('${jsonEncode(state)}\n', flush: true);
      await temporary.rename(receipt.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  OneRequestClient? client;
  try {
    final configured = ChatCompletionProvider.configured({
      'AI_BASE_URL': probeEndpoint,
      'AI_MODEL': probeModel,
      'AI_API_KEY': environment['NEBIUS_API_KEY']!,
    });
    if (configured == null) throw StateError('provider_configuration_failed');
    client = OneRequestClient(clientFactory());
    final provider = ChatCompletionProvider(
      configured.base,
      configured.model,
      configured.key,
      clientFactory: () => client!,
    );
    state['status'] = 'dispatching';
    state['requestCount'] = null;
    state['attemptMayHaveBeenSent'] = true;
    await save();
    final questions = await provider.suggestQuestions(_syntheticIdea);
    if (client.sends != 1 || client.modelStatus != 'matched') {
      throw StateError('probe_invariant_failed');
    }
    state['status'] = 'passed';
    state['guidanceQuestionCount'] = questions.length;
    state['providerReportedModel'] = probeModel;
  } catch (_) {
    final status = client?.statusCode;
    state['status'] = client == null || client.sends == 0
        ? 'not_sent'
        : status == null ||
              status == 202 ||
              status >= 500 ||
              (status == 200 && client.modelStatus == 'not_observed')
        ? 'uncertain'
        : status == 200
        ? 'invalid_response'
        : 'rejected';
  } finally {
    state['requestCount'] = client?.sends ?? 0;
    state['httpStatus'] = client?.statusCode;
    state['servedModelStatus'] = client?.modelStatus ?? 'not_observed';
    state['providerUsageStatus'] = client?.usageStatus ?? 'unknown';
    state['attemptMayHaveBeenSent'] = (client?.sends ?? 0) != 0;
    await save();
  }
  return Map.unmodifiable(state);
}

Future<void> main() async {
  // Run only from appwrite_backend; never accept an arbitrary receipt path.
  final current = Directory.current;
  if (!File('${current.path}/lib/providers/provider.dart').existsSync() ||
      !File('${current.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('Run from the appwrite_backend directory.');
    exitCode = 2;
    return;
  }
  final output = Directory('${current.parent.path}/output');
  if (await FileSystemEntity.isLink(output.path)) {
    stderr.writeln('Probe output directory is not allowed to be a symlink.');
    exitCode = 2;
    return;
  }
  try {
    final result = await runGuidanceProbe(
      environment: Platform.environment,
      receiptDirectory: Directory('${output.path}/nebius-guidance-probe'),
      clientFactory: http.Client.new,
    );
    stdout.writeln(jsonEncode(result));
    if (result['status'] != 'passed') exitCode = 1;
  } catch (_) {
    stderr.writeln(
      'Probe could not complete. Inspect the existing receipt before further action; a request may have been sent.',
    );
    exitCode = 2;
  }
}
