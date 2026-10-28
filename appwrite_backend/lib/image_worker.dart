import 'dart:async';
import 'dart:isolate';

import 'package:appnest_spec/appnest_spec.dart';

void _work<T>((SendPort, T Function()) request) {
  try {
    Isolate.exit(request.$1, (true, request.$2()));
  } catch (error) {
    Isolate.exit(request.$1, (
      false,
      error is SpecException
          ? error.message
          : 'The image could not be decoded. Choose another image.',
    ));
  }
}

/// Header/expansion checks bound memory. This separately bounds worker lifetime
/// even if a malformed entropy stream makes a third-party decoder stall.
Future<T> runImageTask<T>(
  T Function() operation, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final port = ReceivePort();
  final result = Completer<T>();
  final subscription = port.listen((message) {
    if (result.isCompleted) return;
    if (message case (true, final T value)) {
      result.complete(value);
    } else if (message case (false, final String reason)) {
      result.completeError(SpecException(reason));
    } else {
      result.completeError(
        const SpecException('The image worker stopped. Retry the upload.'),
      );
    }
  });
  Isolate? worker;
  try {
    worker = await Isolate.spawn(
      _work<T>,
      (port.sendPort, operation),
      onExit: port.sendPort,
      onError: port.sendPort,
      errorsAreFatal: true,
    );
    return await result.future.timeout(
      timeout,
      onTimeout: () => throw const SpecException(
        'The image took too long to process. Choose another image.',
      ),
    );
  } finally {
    worker?.kill(priority: Isolate.immediate);
    await subscription.cancel();
    port.close();
  }
}
