import 'dart:async';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/features/mini_app/live_adapter.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter_test/flutter_test.dart';

class EventClient extends Client {
  int starts = 0, cancellations = 0;
  final controllers = <StreamController<AppEvent>>[];
  EventClient() : super('http://localhost:1/');

  @override
  dynamic callStreamingServerEndpoint<T, G>(
    String endpoint,
    String method,
    Map<String, dynamic> args,
    Map<String, Stream> streams, {
    bool authenticated = true,
  }) {
    expect(endpoint, 'runtime');
    expect(method, 'events');
    expect(authenticated, isTrue);
    starts++;
    final controller = StreamController<AppEvent>(
      onCancel: () => cancellations++,
    );
    controllers.add(controller);
    return controller.stream;
  }
}

void main() {
  test(
    'page and gallery share one RPC, cancel it, and reconnect on demand',
    () async {
      final client = EventClient();
      addTearDown(client.close);
      final spec = photoJournalTemplate();
      final adapter = LiveRuntimeAdapter(
        client,
        AppManifest(
          appId: 1,
          workspaceId: 1,
          name: spec.name,
          versionId: 1,
          specJson: spec.canonical,
          role: 'owner',
          archived: false,
          pinned: true,
          recordCount: 0,
          availablePlaces: 0,
        ),
      );
      var received = 0;
      final subscriptions = List.generate(
        51,
        (_) => adapter.watch().listen((_) => received++),
      );
      expect(client.starts, 1);
      client.controllers.single.add(
        AppEvent(appId: 1, revision: 1, kind: 'refresh'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, 51);
      for (final subscription in subscriptions.take(50)) {
        await subscription.cancel();
      }
      expect(client.cancellations, 0);
      await subscriptions.last.cancel();
      expect(client.cancellations, 1);
      final resumed = adapter.watch().listen((_) => received++);
      expect(client.starts, 2);
      client.controllers.last.add(
        AppEvent(appId: 1, revision: 2, kind: 'refresh'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, 52);
      await resumed.cancel();
      expect(client.cancellations, 2);
      for (final controller in client.controllers) {
        await controller.close();
      }
    },
  );
}
