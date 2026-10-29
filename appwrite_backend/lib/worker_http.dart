import 'dart:convert';
import 'dart:io';

import 'service.dart';

/// Transport-only wakeups. The execution key is injected for this execution;
/// applications must not configure a permanent project API key here.
class AppwriteWorkerWakeups implements WorkerWakeups {
  AppwriteWorkerWakeups(
    this.endpoint,
    this.project,
    this.functionId,
    this.key, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final Uri endpoint;
  final String project, functionId, key;
  final DateTime Function() clock;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  Map<String, dynamic> body(String id, String proof, DateTime at) {
    final now = clock().toUtc();
    // Delayed execution supports minute precision and must be >=60 seconds in
    // the future. Rounding up keeps an actual reminder from firing early.
    final delayed = at.toUtc().isAfter(now);
    final minimum = now.add(const Duration(minutes: 1));
    final requested = at.toUtc().isAfter(minimum) ? at.toUtc() : minimum;
    final minute = DateTime.fromMillisecondsSinceEpoch(
      ((requested.millisecondsSinceEpoch + 59999) ~/ 60000) * 60000,
      isUtc: true,
    );
    return {
      'body': jsonEncode({'dispatchId': id, 'proof': proof}),
      'async': true,
      'method': 'POST',
      'headers': <String, String>{},
      if (delayed) 'scheduledAt': minute.toIso8601String(),
    };
  }

  @override
  Future<String> schedule({
    required String dispatchId,
    required String proof,
    required DateTime at,
  }) async {
    final base = endpoint.toString().replaceFirst(RegExp(r'/$'), '');
    final request = await _client
        .postUrl(
          Uri.parse(
            '$base/functions/${Uri.encodeComponent(functionId)}/executions',
          ),
        )
        .timeout(const Duration(seconds: 8));
    request.headers.set('X-Appwrite-Project', project);
    request.headers.set('X-Appwrite-Key', key);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body(dispatchId, proof, at)));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > 65536) throw const RestException(502);
      bytes.addAll(chunk);
    }
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw RestException(response.statusCode);
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map ||
        json[r'$id'] is! String ||
        (json[r'$id'] as String).isEmpty)
      throw const RestException(502);
    return json[r'$id'] as String;
  }

  void close() => _client.close(force: true);
}

/// Defense in depth in addition to execute:[] and no public Function domain.
/// Appwrite strips these reserved headers before server-injecting them. A user
/// execution (even an administrator's JWT) must never be a privileged worker.
bool privateWorkerRequest(
  Map<String, dynamic> environment,
  Map<String, dynamic> headers,
  String method,
) =>
    method == 'POST' &&
    environment['APPWRITE_FUNCTION_ID'] is String &&
    (environment['APPWRITE_FUNCTION_ID'] as String).isNotEmpty &&
    environment['APPWRITE_FUNCTION_ID'] ==
        environment['PLATFORM_WORKER_FUNCTION_ID'] &&
    headers['x-appwrite-key'] is String &&
    (headers['x-appwrite-key'] as String).isNotEmpty &&
    (headers['x-appwrite-user-jwt'] == null ||
        headers['x-appwrite-user-jwt'] == '') &&
    (headers['x-appwrite-user-id'] == null ||
        headers['x-appwrite-user-id'] == '') &&
    {'http', 'schedule'}.contains(headers['x-appwrite-trigger']);

/// Appwrite uses the schedule trigger for both intervals and scheduledAt
/// one-shot executions. Interval bodies are empty; one-shots retain the opaque
/// dispatch proof, which the durable dispatcher must verify before doing work.
Map<String, dynamic>? decodePrivateWorkerBody(String trigger, String text) {
  if (utf8.encode(text).length > 4096) {
    throw const ServiceException('request_too_large', 413);
  }
  if (!{'http', 'schedule'}.contains(trigger)) {
    throw const ServiceException('invalid_request', 400);
  }
  if (trigger == 'schedule' && (text.trim().isEmpty || text.trim() == '{}')) {
    return null;
  }
  final input = jsonDecode(text);
  if (input is! Map<String, dynamic> ||
      input.keys.toSet().difference({'dispatchId', 'proof'}).isNotEmpty ||
      input['dispatchId'] is! String ||
      input['proof'] is! String) {
    throw const ServiceException('invalid_request', 400);
  }
  return input;
}
