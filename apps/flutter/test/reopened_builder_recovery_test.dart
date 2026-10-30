import 'dart:async';
import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';
import 'package:tinkerloom_flutter/client.dart' as transport;
import 'package:tinkerloom_flutter/features/builder/builder_screen.dart';
import 'package:tinkerloom_flutter/features/home/home_screen.dart';

import '../../../packages/tinkerloom_client/test/client_test.dart'
    show Fixture, OfflineRejectedProvider, executeFixture;

void main() {
  Future<void> mountHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'launcher displays published summaries without fetching each spec',
    (tester) async {
      final f = Fixture();
      addTearDown(f.client.close);
      await f.published();
      transport.client = f.client;
      final before = f.calls.where((c) => c['op'] == 'spec.getApp').length;
      await mountHome(tester);
      expect(find.text('Reading Journal'), findsWidgets);
      expect(find.text('0 records'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(f.calls.where((c) => c['op'] == 'spec.getApp'), hasLength(before));
    },
  );

  testWidgets('reopened home checks a retained request without resending', (
    tester,
  ) async {
    final f = Fixture(provider: OfflineRejectedProvider());
    addTearDown(f.client.close);
    transport.client = f.client;
    final (_, initial) = await f.draft();
    f.loseNextOp = 'spec.generate';
    await expectLater(
      f.client.builder.generate(
        initial.draftId,
        initial.mutation,
        'My idea',
        startFromScratch: false,
      ),
      throwsA(isA<BackendNetworkException>()),
    );
    final before = f.calls.where((c) => c['op'] == 'spec.generate').length;
    await mountHome(tester);
    expect(
      find.byKey(const ValueKey('check-retained-builder-request')),
      findsOneWidget,
    );
    expect(f.calls.where((c) => c['op'] == 'spec.commandReceipt'), isEmpty);
    await tester.tap(
      find.byKey(const ValueKey('check-retained-builder-request')),
    );
    await tester.pumpAndSettle();
    expect(f.calls.where((c) => c['op'] == 'spec.generate'), hasLength(before));
    expect(
      f.calls.where((c) => c['op'] == 'spec.commandReceipt'),
      hasLength(1),
    );
    expect(
      f.calls.lastWhere((c) => c['op'] == 'spec.getApp')['suppressWakeups'],
      true,
    );
    expect(find.text('Open draft'), findsOneWidget);
    expect(f.client.pendingBuilderRecovery, isNull);
  });

  testWidgets('unresolved retained request stays visible and never resends', (
    tester,
  ) async {
    final f = Fixture(provider: OfflineRejectedProvider());
    addTearDown(f.client.close);
    transport.client = f.client;
    final (_, initial) = await f.draft();
    f.loseBeforeOp = 'spec.generate';
    await expectLater(
      f.client.builder.generate(
        initial.draftId,
        initial.mutation,
        'My idea',
        startFromScratch: false,
      ),
      throwsA(isA<BackendNetworkException>()),
    );
    await mountHome(tester);
    final before = f.calls.where((c) => c['op'] == 'spec.generate').length;
    await tester.tap(
      find.byKey(const ValueKey('check-retained-builder-request')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('still unconfirmed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('check-retained-builder-request')),
      findsOneWidget,
    );
    expect(f.calls.where((c) => c['op'] == 'spec.generate'), hasLength(before));
    expect(f.client.pendingBuilderRecovery, isNotNull);
  });

  testWidgets('reopened builder recovers a saved visual edit without replay', (
    tester,
  ) async {
    final f = Fixture();
    addTearDown(f.client.close);
    transport.client = f.client;
    final (_, initial) = await f.draft();
    f.loseNextOp = 'spec.saveDraft';
    await expectLater(
      f.client.builder.patch(
        initial.draftId,
        initial.mutation,
        jsonEncode({
          'type': 'RenameLabel',
          'targetId': 'title',
          'label': 'Recovered title',
        }),
      ),
      throwsA(isA<BackendNetworkException>()),
    );
    final before = f.calls.where((c) => c['op'] == 'spec.saveDraft').length;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: BuilderScreen(initial: initial)));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('check-retained-builder-request')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('check-retained-builder-request')),
    );
    await tester.pumpAndSettle();
    expect(
      f.calls.where((c) => c['op'] == 'spec.saveDraft'),
      hasLength(before),
    );
    final state = tester.state<BuilderScreenState>(find.byType(BuilderScreen));
    expect(state.draft.mutation, initial.mutation + 1);
    expect(
      find.text('The earlier request was saved. Review the current draft.'),
      findsOneWidget,
    );
    expect(f.client.pendingBuilderRecovery, isNull);
  });

  testWidgets('Open draft rechecks access after receipt recovery', (
    tester,
  ) async {
    final f = Fixture(provider: OfflineRejectedProvider());
    addTearDown(f.client.close);
    transport.client = f.client;
    final (_, initial) = await f.draft();
    f.loseNextOp = 'spec.generate';
    await expectLater(
      f.client.builder.generate(
        initial.draftId,
        initial.mutation,
        'My idea',
        startFromScratch: false,
      ),
      throwsA(isA<BackendNetworkException>()),
    );
    await mountHome(tester);
    await tester.tap(
      find.byKey(const ValueKey('check-retained-builder-request')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open draft'), findsOneWidget);
    await f.store.update('apps', initial.appId, {'ownerId': 'different-owner'});
    final before = f.calls.where((c) => c['op'] == 'spec.getApp').length;
    await tester.tap(find.text('Open draft'));
    await tester.pumpAndSettle();
    expect(
      f.calls.where((c) => c['op'] == 'spec.getApp'),
      hasLength(before + 1),
    );
    expect(find.byType(BuilderScreen), findsNothing);
  });

  testWidgets('Open draft ignores a late read after the session changes', (
    tester,
  ) async {
    final f = Fixture(provider: OfflineRejectedProvider());
    addTearDown(f.client.close);
    final (_, initial) = await f.draft();
    final gate = Completer<void>();
    final entered = Completer<void>();
    final auth = ClientAuth()..setSession({'id': 'alice'});
    var quietReads = 0;
    final client = Client(
      'https://offline.invalid/v1',
      auth: auth,
      transport: (input) async {
        if (input['op'] == 'spec.getApp' && input['suppressWakeups'] == true) {
          quietReads++;
          if (quietReads == 2) {
            entered.complete();
            await gate.future;
          }
        }
        final result = await executeFixture(f, 'alice', input);
        if (input['op'] == 'spec.generate') {
          throw BackendNetworkException(
            'Synthetic lost reply',
            uncertain: true,
          );
        }
        return result;
      },
    );
    addTearDown(client.close);
    transport.client = client;
    await expectLater(
      client.builder.generate(
        initial.draftId,
        initial.mutation,
        'My idea',
        startFromScratch: false,
      ),
      throwsA(isA<BackendNetworkException>()),
    );
    await mountHome(tester);
    await tester.tap(
      find.byKey(const ValueKey('check-retained-builder-request')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open draft'));
    await tester.pump();
    expect(entered.isCompleted, isTrue);
    auth.setSession({'id': 'bob'});
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BuilderScreen), findsNothing);
  });

  testWidgets(
    'Home rechecks build capability before opening a recovered draft',
    (tester) async {
      final f = Fixture();
      addTearDown(f.client.close);
      final (app, _) = await f.published();
      final workspace = (await f.client.apps.manifest(app)).workspaceId;
      final bob = f.forActor('bob');
      addTearDown(bob.close);
      final token = await f.client.apps.invite(app, 'builder', 'bob');
      await bob.apps.acceptInvitation(token);
      final initial = await bob.builder.begin(workspace, 'reading', app);
      f.loseNextOp = 'spec.saveDraft';
      await expectLater(
        bob.builder.patch(
          initial.draftId,
          initial.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'title',
            'label': 'Private edit',
          }),
        ),
        throwsA(isA<BackendNetworkException>()),
      );
      transport.client = bob;
      await mountHome(tester);
      await tester.tap(
        find.byKey(const ValueKey('check-retained-builder-request')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open draft'), findsOneWidget);
      await f.client.apps.members(app);
      await f.client.apps.setGrant(app, 'bob', 'viewer');
      await tester.tap(find.text('Open draft'));
      await tester.pumpAndSettle();
      expect(find.byType(BuilderScreen), findsNothing);
      expect(find.textContaining('no longer have permission'), findsOneWidget);
    },
  );

  testWidgets(
    'a downgraded builder hides its previously visible private preview',
    (tester) async {
      final f = Fixture();
      addTearDown(f.client.close);
      final (app, _) = await f.published();
      final workspace = (await f.client.apps.manifest(app)).workspaceId;
      final bob = f.forActor('bob');
      addTearDown(bob.close);
      final token = await f.client.apps.invite(app, 'builder', 'bob');
      await bob.apps.acceptInvitation(token);
      final initial = await bob.builder.begin(workspace, 'reading', app);
      final patch = {
        'type': 'RenameLabel',
        'targetId': 'title',
        'label': 'Private edit',
      };
      final expected = AppSpec.parse(initial.candidateJson)
          .patch(patch, () => 'unused');
      f.loseNextOp = 'spec.saveDraft';
      await expectLater(
        bob.builder.patch(initial.draftId, initial.mutation, jsonEncode(patch)),
        throwsA(isA<BackendNetworkException>()),
      );
      expect(
        await bob.confirmRetainedBuilderCommand(
          appId: app,
          operation: 'spec.saveDraft',
          expectedRevision: initial.mutation,
          candidateHash: expected.hash,
        ),
        RetainedCommandStatus.confirmed,
      );
      await f.client.apps.members(app);
      await f.client.apps.setGrant(app, 'bob', 'viewer');
      transport.client = bob;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: BuilderScreen(initial: initial)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MiniAppRuntime), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('check-retained-builder-request')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MiniAppRuntime), findsNothing);
      expect(
        find.text('You no longer have access to edit this draft.'),
        findsOneWidget,
      );
      expect(bob.pendingBuilderRecovery?.receiptConfirmed, isTrue);
    },
  );

  testWidgets(
    'denial for another pending app does not hide the current draft',
    (tester) async {
      final f = Fixture();
      addTearDown(f.client.close);
      final (otherApp, _) = await f.published();
      final workspace = (await f.client.apps.manifest(otherApp)).workspaceId;
      final bob = f.forActor('bob');
      addTearDown(bob.close);
      final token = await f.client.apps.invite(otherApp, 'builder', 'bob');
      await bob.apps.acceptInvitation(token);
      final other = await bob.builder.begin(workspace, 'reading', otherApp);
      final ownWorkspace = await bob.apps.createWorkspace('Bob workspace');
      final own = await bob.builder.begin(ownWorkspace, 'reading', null);
      final patch = {
        'type': 'RenameLabel',
        'targetId': 'title',
        'label': 'Private edit',
      };
      final expected = AppSpec.parse(other.candidateJson)
          .patch(patch, () => 'unused');
      f.loseNextOp = 'spec.saveDraft';
      await expectLater(
        bob.builder.patch(other.draftId, other.mutation, jsonEncode(patch)),
        throwsA(isA<BackendNetworkException>()),
      );
      expect(
        await bob.confirmRetainedBuilderCommand(
          appId: otherApp,
          operation: 'spec.saveDraft',
          expectedRevision: other.mutation,
          candidateHash: expected.hash,
        ),
        RetainedCommandStatus.confirmed,
      );
      await f.client.apps.members(otherApp);
      await f.client.apps.setGrant(otherApp, 'bob', 'viewer');
      transport.client = bob;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: BuilderScreen(initial: own)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('check-retained-builder-request')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MiniAppRuntime), findsWidgets);
      expect(
        find.text('You no longer have access to edit this draft.'),
        findsNothing,
      );
      expect(bob.pendingBuilderRecovery?.receiptConfirmed, isTrue);
    },
  );

  testWidgets('Home can set aside a confirmed creation after losing access', (
    tester,
  ) async {
    final f = Fixture(provider: OfflineRejectedProvider());
    addTearDown(f.client.close);
    await f.client.apps.createWorkspace('Workspace');
    final calls = <String>[];
    final client = Client(
      'https://offline.invalid/v1',
      auth: ClientAuth()..setSession({'id': 'alice'}),
      transport: (input) async {
        final op = input['op'] as String;
        calls.add(op);
        final result = await executeFixture(f, 'alice', input);
        if (op == 'spec.generate') {
          throw BackendNetworkException('lost response', uncertain: true);
        }
        if (op == 'spec.commandReceipt' && result['confirmed'] == true) {
          final command = input['command'] as Map<String, dynamic>;
          await f.store.update('apps', command['appId'] as String, {
            'ownerId': 'other',
          });
        }
        return result;
      },
    );
    addTearDown(client.close);
    transport.client = client;
    await mountHome(tester);
    await tester.enterText(
      find.byKey(const ValueKey('app-idea')),
      'A reading list',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-app')));
    await tester.pumpAndSettle();
    expect(calls, contains('spec.generate'), reason: 'Calls: $calls');
    expect(client.pendingBuilderRecovery, isNotNull, reason: 'Calls: $calls');
    expect(find.text('Check request'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('create-app')));
    await tester.pumpAndSettle();
    expect(client.pendingBuilderRecovery?.receiptConfirmed, isTrue);
    expect(find.byKey(const ValueKey('set-aside-recovery')), findsOneWidget);
    final before = calls.length;
    await tester.tap(find.byKey(const ValueKey('set-aside-recovery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-set-aside-recovery')));
    await tester.pumpAndSettle();
    expect(calls.length, before);
    expect(client.pendingBuilderRecovery, isNull);
    expect(find.text('Create app'), findsOneWidget);
  });

  testWidgets('Builder can set aside a confirmed request after losing access', (
    tester,
  ) async {
    final f = Fixture(provider: OfflineRejectedProvider());
    addTearDown(f.client.close);
    final (_, initial) = await f.draft();
    final calls = <String>[];
    final client = Client(
      'https://offline.invalid/v1',
      auth: ClientAuth()..setSession({'id': 'alice'}),
      transport: (input) async {
        final op = input['op'] as String;
        calls.add(op);
        final result = await executeFixture(f, 'alice', input);
        if (op == 'spec.generate') {
          throw BackendNetworkException('lost response', uncertain: true);
        }
        if (op == 'spec.commandReceipt' && result['confirmed'] == true) {
          final command = input['command'] as Map<String, dynamic>;
          await f.store.update('apps', command['appId'] as String, {
            'ownerId': 'other',
          });
        }
        return result;
      },
    );
    addTearDown(client.close);
    transport.client = client;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: BuilderScreen(initial: initial)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('builder-prompt')),
      'Improve my list',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh connection'));
    await tester.pumpAndSettle();
    expect(
      find.text('You no longer have access to edit this draft.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('set-aside-recovery')), findsOneWidget);
    final before = calls.length;
    await tester.tap(find.byKey(const ValueKey('set-aside-recovery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-set-aside-recovery')));
    await tester.pumpAndSettle();
    expect(calls.length, before);
    expect(client.pendingBuilderRecovery, isNull);
    expect(find.byType(MiniAppRuntime), findsNothing);
  });

  testWidgets(
    'visual edit can set aside a confirmed save after losing access',
    (tester) async {
      final f = Fixture();
      addTearDown(f.client.close);
      final (_, initial) = await f.draft();
      final calls = <String>[];
      final client = Client(
        'https://offline.invalid/v1',
        auth: ClientAuth()..setSession({'id': 'alice'}),
        transport: (input) async {
          final op = input['op'] as String;
          calls.add(op);
          final result = await executeFixture(f, 'alice', input);
          if (op == 'spec.saveDraft') {
            throw BackendNetworkException('lost response', uncertain: true);
          }
          if (op == 'spec.commandReceipt' && result['confirmed'] == true) {
            final command = input['command'] as Map<String, dynamic>;
            await f.store.update('apps', command['appId'] as String, {
              'ownerId': 'other',
            });
          }
          return result;
        },
      );
      addTearDown(client.close);
      transport.client = client;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: BuilderScreen(initial: initial)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('visual-label')),
        'Private edit',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check save status'));
      await tester.pumpAndSettle();
      expect(
        find.text('You no longer have access to edit this draft.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('set-aside-recovery')), findsOneWidget);
      final before = calls.length;
      await tester.tap(find.byKey(const ValueKey('set-aside-recovery')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-set-aside-recovery')),
      );
      await tester.pumpAndSettle();
      expect(calls.length, before);
      expect(client.pendingBuilderRecovery, isNull);
      expect(find.byType(MiniAppRuntime), findsNothing);
    },
  );

  testWidgets(
    'an in-flight request outliving its builder becomes recoverable',
    (
      tester,
    ) async {
      final f = Fixture(provider: OfflineRejectedProvider());
      addTearDown(f.client.close);
      final (_, initial) = await f.draft();
      final gate = Completer<void>();
      final calls = <String>[];
      final client = Client(
        'https://offline.invalid/v1',
        auth: ClientAuth()..setSession({'id': 'alice'}),
        transport: (input) async {
          final op = input['op'] as String;
          calls.add(op);
          if (op == 'spec.generate') {
            await gate.future;
            await f.service.execute('alice', input);
            throw BackendNetworkException(
              'Synthetic lost reply',
              uncertain: true,
            );
          }
          return f.service.execute('alice', input);
        },
      );
      addTearDown(client.close);
      transport.client = client;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: BuilderScreen(initial: initial)),
      );
      await tester.pumpAndSettle();
      final flight = client.builder.generate(
        initial.draftId,
        initial.mutation,
        'In-flight idea',
        startFromScratch: false,
      );
      final failed = expectLater(
        flight,
        throwsA(isA<BackendNetworkException>()),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await tester.pump();
      await failed;
      await mountHome(tester);
      expect(
        find.byKey(const ValueKey('check-retained-builder-request')),
        findsOneWidget,
      );
      expect(calls.where((op) => op == 'spec.generate'), hasLength(1));
      await tester.tap(
        find.byKey(const ValueKey('check-retained-builder-request')),
      );
      await tester.pumpAndSettle();
      expect(calls.where((op) => op == 'spec.generate'), hasLength(1));
      expect(calls.where((op) => op == 'spec.commandReceipt'), hasLength(1));
      expect(client.pendingBuilderRecovery, isNull);
    },
  );
}
