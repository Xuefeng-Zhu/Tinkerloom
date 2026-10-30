import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';
import 'package:tinkerloom_flutter/features/mini_app/live_adapter.dart';

class SyntheticEventClient extends Client {
  SyntheticEventClient(this.manifest) : super('https://offline.invalid');
  final AppManifest manifest;
  final events = StreamController<AppEvent>.broadcast();
  int manifestReads = 0;
  bool deny = false;
  int imageReads = 0;
  Completer<AppManifest>? manifestGate;
  @override
  dynamic callStreamingServerEndpoint<T, R>(
    String endpoint,
    String method,
    Map<String, dynamic> args,
    Map<String, Stream> streams, {
    bool authenticated = true,
  }) => events.stream;
  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    if (endpoint == 'apps' && method == 'manifest') {
      manifestReads++;
      if (manifestGate != null) return await manifestGate!.future as T;
      if (deny) throw BackendForbidden('Access revoked');
      return manifest as T;
    }
    if (endpoint == 'runtime' && method == 'query') {
      final preview = PreviewRuntimeAdapter(AppSpec.parse(manifest.specJson!));
      final page = await preview.query(
        args['collectionId'] as String,
        jsonDecode(args['queryJson'] as String) as Map<String, dynamic>,
      );
      preview.dispose();
      return RecordPage(
        records: page.items
            .map(
              (r) => RuntimeRecord(
                id: r.id,
                collectionId: r.collectionId,
                data: r.data,
                revision: r.revision,
                claimed: r.claimed,
                allowedActions: r.allowedActions,
              ),
            )
            .toList(),
        total: page.total,
      ) as T;
    }
    if (endpoint == 'media' && method == 'readImage') {
      imageReads++;
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
      );
      return ByteData.sublistView(png) as T;
    }
    throw StateError('Unexpected offline endpoint $endpoint.$method');
  }
}

void main() {
  testWidgets('real live adapter fences device checks before event transform', (
    tester,
  ) async {
    final spec = phoneToolkitTemplate();
    final manifest = AppManifest(
      appId: 'app',
      workspaceId: 'ws',
      name: spec.name,
      versionId: 'v1',
      specJson: spec.canonical,
      role: 'owner',
      archived: false,
      pinned: false,
      recordCount: 0,
      availablePlaces: 0,
    );
    final client = SyntheticEventClient(manifest);
    final adapter = LiveRuntimeAdapter(client, manifest);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.manifestReads, 0);
    client.events.add(AppEvent(appId: 'app', revision: 1, kind: 'changed'));
    await tester.pumpAndSettle();
    expect(client.manifestReads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    client.events.add(AppEvent(appId: 'app', revision: 2, kind: 'changed'));
    await tester.pump();
    expect(client.manifestReads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(client.manifestReads, 1);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covered')),
      ),
    );
    await tester.pumpAndSettle();
    client.events.add(AppEvent(appId: 'app', revision: 3, kind: 'changed'));
    await tester.pump();
    expect(client.manifestReads, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    client.deny = true;
    client.events.add(AppEvent(appId: 'app', revision: 4, kind: 'changed'));
    await tester.pumpAndSettle();
    expect(client.manifestReads, 2);
    expect(find.text('This page is unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await client.events.close();
    await client.close();
    adapter.deviceCapabilities.dispose();
    adapter.timerController.dispose();
  });

  test(
    'live adapter drops a delayed validation error once its guard closes',
    () async {
      final spec = phoneToolkitTemplate();
      final manifest = AppManifest(
        appId: 'app',
        workspaceId: 'ws',
        name: spec.name,
        versionId: 'v1',
        specJson: spec.canonical,
        role: 'owner',
        archived: false,
        pinned: false,
        recordCount: 0,
        availablePlaces: 0,
      );
      final client = SyntheticEventClient(manifest);
      final adapter = LiveRuntimeAdapter(client, manifest);
      var allowed = true;
      var received = 0;
      var errors = 0;
      adapter.setAutomaticReadGuard(() => allowed);
      final subscription = adapter.watch().listen(
        (_) => received++,
        onError: (_) => errors++,
      );
      client.manifestGate = Completer<AppManifest>();
      client.events.add(AppEvent(appId: 'app', revision: 1, kind: 'changed'));
      await Future<void>.delayed(Duration.zero);
      expect(client.manifestReads, 1);
      allowed = false;
      client.manifestGate!.completeError(
        BackendNetworkException('Temporary failure'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, 0);
      expect(errors, 0);
      allowed = true;
      client.manifestGate = Completer<AppManifest>();
      client.events.add(AppEvent(appId: 'app', revision: 2, kind: 'changed'));
      await Future<void>.delayed(Duration.zero);
      allowed = false;
      client.manifestGate!.completeError(BackendForbidden('Access revoked'));
      await Future<void>.delayed(Duration.zero);
      expect(errors, 1, reason: 'definite access loss must propagate');
      client.events.addError(BackendUnauthorized('Session expired'));
      await Future<void>.delayed(Duration.zero);
      expect(
        errors,
        2,
        reason: 'authentication stream errors must still propagate',
      );
      await subscription.cancel();
      await client.events.close();
      await client.close();
      adapter.deviceCapabilities.dispose();
      adapter.timerController.dispose();
    },
  );

  testWidgets(
    'real live media reads stay quiet while backgrounded and reload on tap',
    (tester) async {
      final spec = photoJournalTemplate();
      final manifest = AppManifest(
        appId: 'app',
        workspaceId: 'ws',
        name: spec.name,
        versionId: 'v1',
        specJson: spec.canonical,
        role: 'owner',
        archived: false,
        pinned: false,
        recordCount: 0,
        availablePlaces: 0,
      );
      final client = SyntheticEventClient(manifest);
      final adapter = LiveRuntimeAdapter(client, manifest);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
        ),
      );
      await tester.pumpAndSettle();
      expect(client.imageReads, greaterThan(0));
      final reads = client.manifestReads;
      final images = client.imageReads;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      client.events.add(AppEvent(appId: 'app', revision: 1, kind: 'changed'));
      await tester.pumpAndSettle();
      expect(client.manifestReads, reads);
      expect(client.imageReads, images);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.manifestReads, reads);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      );
      await tester.pumpAndSettle();
      client.events.add(AppEvent(appId: 'app', revision: 2, kind: 'changed'));
      await tester.pump();
      expect(client.manifestReads, reads);
      expect(client.imageReads, images);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh page'));
      await tester.pumpAndSettle();
      expect(client.imageReads, greaterThan(images));
      await tester.pumpWidget(const SizedBox());
      await client.events.close();
      await client.close();
      adapter.deviceCapabilities.dispose();
      adapter.timerController.dispose();
    },
  );
  test(
    'queued device events do not begin validation after guard closes',
    () async {
      final spec = phoneToolkitTemplate();
      final manifest = AppManifest(
        appId: 'app',
        workspaceId: 'ws',
        name: spec.name,
        versionId: 'v1',
        specJson: spec.canonical,
        role: 'owner',
        archived: false,
        pinned: false,
        recordCount: 0,
        availablePlaces: 0,
      );
      final client = SyntheticEventClient(manifest);
      final adapter = LiveRuntimeAdapter(client, manifest);
      var allowed = true;
      var received = 0;
      adapter.setAutomaticReadGuard(() => allowed);
      final subscription = adapter.watch().listen((_) => received++);
      client.manifestGate = Completer<AppManifest>();
      client.events.add(AppEvent(appId: 'app', revision: 1, kind: 'changed'));
      client.events.add(AppEvent(appId: 'app', revision: 2, kind: 'changed'));
      await Future<void>.delayed(Duration.zero);
      expect(client.manifestReads, 1);
      allowed = false;
      client.manifestGate!.complete(manifest);
      await Future<void>.delayed(Duration.zero);
      expect(client.manifestReads, 1);
      expect(received, 0);
      await subscription.cancel();
      await client.events.close();
      await client.close();
      adapter.deviceCapabilities.dispose();
      adapter.timerController.dispose();
    },
  );
}
