import 'dart:convert';
import 'dart:io';
import 'service.dart';
import 'worker_http.dart';
import 'providers/provider.dart';

/// Deploy this file as the ONE private worker Function, execute:[], no domain.
/// The hourly platform interval runs reconciliation only; provider work is a
/// separate execution mode of this same Function, never awaited by that pass.
Future<dynamic> main(dynamic context) async {
  final env = Platform.environment,
      headers = Map<String, dynamic>.from(context.req.headers as Map);
  if (!privateWorkerRequest(env, headers, context.req.method as String))
    return context.res.json({'error': 'unauthenticated'}, 401);
  final endpoint = env['APPWRITE_FUNCTION_API_ENDPOINT'],
      project = env['APPWRITE_FUNCTION_PROJECT_ID'],
      database = env['PLATFORM_DATABASE_ID'];
  if (endpoint == null ||
      project == null ||
      database == null ||
      endpoint.isEmpty ||
      project.isEmpty ||
      database.isEmpty)
    return context.res.json({'error': 'backend_unavailable'}, 503);
  final key = headers['x-appwrite-key'] as String;
  final backend = AppwriteRest(Uri.parse(endpoint), project, database, key);
  final wakeups = AppwriteWorkerWakeups(
    Uri.parse(endpoint),
    project,
    env['PLATFORM_WORKER_FUNCTION_ID']!,
    key,
  );
  try {
    final runner = WorkerEngine(
      PlatformService(
        backend,
        aiProvider: ChatCompletionProvider.configured(env),
        remindersEnabled: env['PLATFORM_REMINDERS_ENABLED'] == 'true',
        wakeups: wakeups,
      ),
    );
    final text = context.req.bodyText as String;
    if (utf8.encode(text).length > 4096)
      return context.res.json({'error': 'request_too_large'}, 413);
    if (headers['x-appwrite-trigger'] == 'schedule') {
      if (text.trim().isNotEmpty && text.trim() != '{}')
        return context.res.json({'error': 'invalid_request'}, 400);
      return context.res.json(await runner.reconcile(), 200);
    }
    final input = jsonDecode(text);
    if (input is! Map<String, dynamic> ||
        input.keys.toSet().difference({'dispatchId', 'proof'}).isNotEmpty ||
        input['dispatchId'] is! String ||
        input['proof'] is! String)
      return context.res.json({'error': 'invalid_request'}, 400);
    return context.res.json(
      await runner.dispatch(
        input['dispatchId'] as String,
        input['proof'] as String,
      ),
      200,
    );
  } on ServiceException catch (error) {
    return context.res.json({'error': error.code}, error.status);
  } on FormatException {
    return context.res.json({'error': 'invalid_request'}, 400);
  } catch (_) {
    context.error('Private work execution failed');
    return context.res.json({'error': 'backend_unavailable'}, 503);
  } finally {
    backend.close();
    wakeups.close();
  }
}
