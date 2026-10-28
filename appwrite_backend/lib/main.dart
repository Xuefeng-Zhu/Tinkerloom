import 'dart:convert';
import 'dart:io';

import 'service.dart';
import 'worker_http.dart';
import 'providers/provider.dart';

/// Appwrite Dart Function entrypoint. Appwrite injects context and credentials.
Future<dynamic> main(dynamic context) async {
  final headers = Map<String, dynamic>.from(context.req.headers as Map);
  final jwt = headers['x-appwrite-user-jwt'];
  final key = headers['x-appwrite-key'];
  if (jwt is! String || jwt.isEmpty) {
    return context.res.json({'error': 'unauthenticated'}, 401);
  }
  if (key is! String || key.isEmpty) {
    context.error('Missing Appwrite function execution key');
    return context.res.json({'error': 'backend_unavailable'}, 503);
  }
  final endpoint = Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT'];
  final project = Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'];
  final database = Platform.environment['PLATFORM_DATABASE_ID'];
  if (endpoint == null ||
      project == null ||
      database == null ||
      endpoint.isEmpty ||
      project.isEmpty ||
      database.isEmpty) {
    context.error('Missing Appwrite function configuration');
    return context.res.json({'error': 'backend_unavailable'}, 503);
  }
  if (context.req.method != 'POST') {
    return context.res.json({'error': 'method_not_allowed'}, 405);
  }
  final mediaCapText = Platform.environment['PLATFORM_MEDIA_PROJECT_BYTES'];
  final mediaCap = mediaCapText == null
      ? MediaLimits.maxProjectBytes
      : int.tryParse(mediaCapText);
  if (mediaCap == null || mediaCap < 1 || mediaCap > 2147483647) {
    context.error('Invalid media quota configuration');
    return context.res.json({'error': 'backend_unavailable'}, 503);
  }
  final backend = AppwriteRest(Uri.parse(endpoint), project, database, key);
  final bucket = Platform.environment['PLATFORM_MEDIA_BUCKET_ID'];
  final files = bucket == null || bucket.isEmpty
      ? null
      : AppwritePrivateFiles(Uri.parse(endpoint), project, bucket, key);
  final workerId = Platform.environment['PLATFORM_WORKER_FUNCTION_ID'];
  final wakeups = workerId == null || workerId.isEmpty
      ? null
      : AppwriteWorkerWakeups(Uri.parse(endpoint), project, workerId, key);
  try {
    final account = await backend.account(jwt);
    final actor = account[r'$id'];
    if (actor is! String || actor.isEmpty) {
      return context.res.json({'error': 'unauthenticated'}, 401);
    }
    final bodyText = context.req.bodyText as String;
    final bodyBytes = utf8.encode(bodyText).length;
    if (bodyBytes > 6291456) {
      return context.res.json({'error': 'request_too_large'}, 413);
    }
    final data = jsonDecode(bodyText);
    if (data is! Map<String, dynamic>) {
      return context.res.json({'error': 'invalid_request'}, 400);
    }
    if (!(data['op'] is String && (data['op'] as String).startsWith('spec.')) &&
        bodyBytes > 65536) {
      return context.res.json({'error': 'request_too_large'}, 413);
    }
    final service = PlatformService(
      backend,
      media: files,
      mediaProjectBytes: mediaCap,
      aiProvider: ChatCompletionProvider.configured(Platform.environment),
      remindersEnabled:
          Platform.environment['PLATFORM_REMINDERS_ENABLED'] == 'true',
      wakeups: wakeups,
    );
    final result = await service.execute(actor, data);
    // Commit precedes optional delivery. A scheduling outage never fabricates
    // successful work or turns a committed command into a failed command.
    try {
      await WorkerEngine(service).flushWakeups(limit: 3);
    } catch (_) {}
    return context.res.json(result, 200, {
      'Cache-Control': 'private, no-store',
    });
  } on FormatException {
    return context.res.json({'error': 'invalid_request'}, 400);
  } on ServiceException catch (error) {
    return context.res.json({'error': error.code}, error.status);
  } on RestException catch (error) {
    // No provider body or token in logs. The account endpoint identifies a bad JWT.
    if (error.authFailure) {
      return context.res.json({'error': 'unauthenticated'}, 401);
    }
    context.error(
      'Appwrite database request failed with status ${error.status}',
    );
    return context.res.json({'error': 'backend_unavailable'}, 503);
  } catch (_) {
    context.error('Function execution failed');
    return context.res.json({'error': 'backend_unavailable'}, 503);
  } finally {
    files?.close();
    backend.close();
    wakeups?.close();
  }
}
