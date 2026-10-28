import 'dart:async';
import 'dart:convert';
import 'dart:ui' show CheckedState;

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ResponseLostPreview extends PreviewRuntimeAdapter {
  ResponseLostPreview(super.spec);
  bool loseResponse = true;
  bool rejectNext = false;
  bool restrictWrites = false;

  @override
  bool get readOnly => restrictWrites;
  final attempts = <Map<String, dynamic>>[];
  Completer<void>? pendingRetry;
  final connection = StreamController<void>.broadcast();

  @override
  Stream<void> watch() => connection.stream;

  @override
  void dispose() {
    connection.close();
    super.dispose();
  }

  @override
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  ) async {
    attempts.add({
      'action': action.id,
      'record': record?.id,
      'revision': record?.revision,
      'input': jsonDecode(jsonEncode(input)),
      'key': key,
    });
    if (rejectNext) {
      rejectNext = false;
      throw const SpecException('Your changes were rejected. Check the title.');
    }
    if (pendingRetry != null) await pendingRetry!.future;
    await super.execute(action, record, input, key);
    if (loseResponse) {
      loseResponse = false;
      throw StateError(
        'The response was lost after the transaction committed.',
      );
    }
  }

  Future<void> externalEdit(int id, String title) async {
    await super.execute(spec.action('editRecord'), await get(id), {
      'data': {'title': title},
    }, 'external-edit');
  }
}

Future<MiniAppController> mount(
  WidgetTester tester,
  PreviewRuntimeAdapter adapter, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = MiniAppController();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MiniAppRuntime(adapter: adapter, controller: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    adapter.dispose();
  });
  return controller;
}

Future<void> press(WidgetTester tester, String label) async {
  final button = find.text(label).last;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  testWidgets(
    'pristine editor refresh updates values and their revision together',
    (tester) async {
      final adapter = ResponseLostPreview(projectHubTemplate())
        ..loseResponse = false;
      final controller = await mount(tester, adapter);
      await controller.navigate(
        const MiniAppLocation('formPage', recordId: 1, editing: true),
      );
      await tester.pumpAndSettle();
      await adapter.externalEdit(1, 'Other member latest title');
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Task *')).controller!.text,
        'Other member latest title',
      );
      await tester.enterText(field('Notes'), 'My unrelated note edit');
      await press(tester, 'Save');
      final saved = await adapter.get(1);
      expect(saved.data['title'], 'Other member latest title');
      expect(saved.data['notes'], 'My unrelated note edit');
      expect(adapter.attempts.single['revision'], 2);
    },
  );

  testWidgets(
    'dirty editor keeps its original revision after another member edits',
    (tester) async {
      final adapter = ResponseLostPreview(projectHubTemplate())
        ..loseResponse = false;
      final controller = await mount(tester, adapter);
      await controller.navigate(
        const MiniAppLocation('formPage', recordId: 1, editing: true),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Notes'), 'Unsaved local notes');
      await adapter.externalEdit(1, 'Another member changed this');
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      await press(tester, 'Save');
      expect(adapter.attempts.single['revision'], 1);
      expect(
        (await adapter.get(1)).data['title'],
        'Another member changed this',
      );
      expect(
        tester.widget<TextField>(field('Notes')).controller!.text,
        'Unsaved local notes',
      );
      expect(find.textContaining('Could not save.'), findsOneWidget);
    },
  );

  testWidgets(
    'lost create response retries the frozen command without a duplicate',
    (tester) async {
      final adapter = ResponseLostPreview(projectHubTemplate());
      final controller = await mount(tester, adapter);
      await controller.navigate(
        const MiniAppLocation('formPage', editing: true),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Task *'), 'Receipt-backed task');
      await press(tester, 'Save');
      expect(find.textContaining('Save outcome unconfirmed.'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(find.text('Simulated in preview'), findsNothing);
      final title = tester.widget<TextField>(field('Task *'));
      expect(title.readOnly, isTrue);
      // Even a programmatic controller change cannot replace receipt-bound input.
      title.controller!.text = 'Changed after the unconfirmed request';
      adapter.pendingRetry = Completer<void>();
      await tester.ensureVisible(find.text('Retry save'));
      await tester.tap(find.text('Retry save'));
      await tester.pump();
      expect(find.text('Checking save…'), findsOneWidget);
      adapter.pendingRetry!.complete();
      await tester.pumpAndSettle();
      expect(adapter.attempts, hasLength(2));
      expect(adapter.attempts[1], adapter.attempts[0]);
      final page = await adapter.query('projects', {
        'filters': [
          {
            'fieldId': 'title',
            'operator': 'eq',
            'value': 'Receipt-backed task',
          },
        ],
      });
      expect(page.total, 1);
      expect(find.text('Retry save'), findsNothing);
      expect(find.text('Simulated in preview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lost edit response preserves the original revision across refresh',
    (tester) async {
      final adapter = ResponseLostPreview(projectHubTemplate());
      final controller = await mount(tester, adapter);
      final original = await adapter.get(1);
      await controller.navigate(
        const MiniAppLocation('formPage', recordId: 1, editing: true),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Task *'), 'My acknowledged edit');
      await press(tester, 'Save');
      expect((await adapter.get(1)).revision, original.revision + 1);
      await adapter.externalEdit(1, 'A later edit from another member');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      await press(tester, 'Retry save');
      expect(adapter.attempts, hasLength(2));
      expect(adapter.attempts[1], adapter.attempts[0]);
      expect(adapter.attempts.last['revision'], original.revision);
      final record = await adapter.get(1);
      expect(record.revision, original.revision + 2);
      expect(record.data['title'], 'A later edit from another member');
      expect(find.textContaining('Save outcome unconfirmed.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unconfirmed save stays frozen when receipt recovery is rejected',
    (tester) async {
      final adapter = ResponseLostPreview(projectHubTemplate());
      final controller = await mount(tester, adapter);
      await controller.navigate(
        const MiniAppLocation('formPage', editing: true),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Task *'), 'Still checking this task');
      await press(tester, 'Save');
      adapter.rejectNext = true;
      await press(tester, 'Retry save');
      expect(tester.widget<TextField>(field('Task *')).readOnly, isTrue);
      expect(find.text('Retry save'), findsOneWidget);
      expect(find.textContaining('Save outcome unconfirmed.'), findsOneWidget);
      await press(tester, 'Retry save');
      expect(adapter.attempts, hasLength(3));
      expect(adapter.attempts[1], adapter.attempts.first);
      expect(adapter.attempts[2], adapter.attempts.first);
      expect(
        (await adapter.query('projects', {
          'filters': [
            {
              'fieldId': 'title',
              'operator': 'eq',
              'value': 'Still checking this task',
            },
          ],
        })).total,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reconnection preserves an unconfirmed command without replaying it',
    (tester) async {
      final adapter = ResponseLostPreview(projectHubTemplate());
      final controller = await mount(tester, adapter);
      await controller.navigate(
        const MiniAppLocation('formPage', editing: true),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Task *'), 'Reconnect recovery');
      await press(tester, 'Save');
      adapter.connection.addError(StateError('Connection interrupted'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(adapter.attempts, hasLength(1));
      expect(find.text('Retry save'), findsOneWidget);
      await press(tester, 'Retry save');
      expect(adapter.attempts, hasLength(2));
      expect(adapter.attempts.last, adapter.attempts.first);
      expect(
        (await adapter.query('projects', {
          'filters': [
            {
              'fieldId': 'title',
              'operator': 'eq',
              'value': 'Reconnect recovery',
            },
          ],
        })).total,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('multi-step recovery returns to the final step after reconnect', (
    tester,
  ) async {
    final adapter = ResponseLostPreview(photoJournalTemplate());
    final controller = await mount(tester, adapter);
    await controller.navigate(const MiniAppLocation('formPage', editing: true));
    await tester.pumpAndSettle();
    await tester.enterText(field('Title *'), 'A recoverable memory');
    await press(tester, 'Next step');
    await press(tester, 'Save');
    adapter.connection.addError(StateError('Connection interrupted'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(adapter.attempts, hasLength(1));
    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(find.text('Retry save'), findsOneWidget);
    expect(find.textContaining('Save outcome unconfirmed.'), findsOneWidget);
    await press(tester, 'Retry save');
    expect(adapter.attempts, hasLength(2));
    expect(adapter.attempts.last, adapter.attempts.first);
    expect(
      (await adapter.query('memories', {
        'filters': [
          {
            'fieldId': 'title',
            'operator': 'eq',
            'value': 'A recoverable memory',
          },
        ],
      })).total,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an unconfirmed checklist write blocks another command until recovery',
    (tester) async {
      final adapter = ResponseLostPreview(habitTrackerTemplate());
      final controller = await mount(tester, adapter);
      await controller.navigate(const MiniAppLocation('checkinsPage'));
      await tester.pumpAndSettle();
      final check = find.byType(Checkbox).first;
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(adapter.attempts, hasLength(1));
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(adapter.attempts, hasLength(1));
      await press(tester, 'Retry save');
      expect(adapter.attempts, hasLength(2));
      expect(adapter.attempts.last, adapter.attempts.first);
      expect(find.text('Retry save'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a stale workflow callback cannot replace an unconfirmed command',
    (tester) async {
      final adapter = ResponseLostPreview(projectHubTemplate());
      await mount(tester, adapter, size: const Size(1440, 1000));
      final original = await adapter.get(1);
      final target = original.data['status'] == 'Open' ? 'Done' : 'Open';
      final move = find
          .byWidgetPredicate(
            (widget) =>
                widget is PopupMenuButton<String> &&
                widget.tooltip == 'Move record',
          )
          .first;
      final staleCallback = tester
          .widget<PopupMenuButton<String>>(move)
          .onSelected!;
      await tester.ensureVisible(move);
      await tester.tap(move);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to $target'));
      await tester.pumpAndSettle();
      expect(adapter.attempts, hasLength(1));
      expect(tester.widget<PopupMenuButton<String>>(move).enabled, isFalse);
      staleCallback(target);
      await tester.pumpAndSettle();
      expect(adapter.attempts, hasLength(1));
      await press(tester, 'Retry save');
      expect(adapter.attempts, hasLength(2));
      expect(adapter.attempts.last, adapter.attempts.first);
      expect((await adapter.get(1)).revision, original.revision + 1);
      expect((await adapter.get(1)).data['status'], target);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'receipt recovery remains visible when edit permission is removed',
    (tester) async {
      final adapter = ResponseLostPreview(projectHubTemplate());
      final controller = await mount(tester, adapter);
      await controller.navigate(
        const MiniAppLocation('formPage', editing: true),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Task *'), 'Permission-change recovery');
      await press(tester, 'Save');
      adapter.restrictWrites = true;
      adapter.connection.add(null);
      await tester.pumpAndSettle();
      expect(
        find.text('You have read-only access to this record.'),
        findsOneWidget,
      );
      expect(find.text('Retry save'), findsOneWidget);
      await press(tester, 'Retry save');
      expect(adapter.attempts, hasLength(2));
      expect(adapter.attempts.last, adapter.attempts.first);
      expect(find.text('Retry save'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'leaving an unconfirmed save requires an explicit truthful choice',
    (tester) async {
      final adapter = ResponseLostPreview(projectHubTemplate());
      final controller = await mount(tester, adapter);
      await controller.navigate(
        const MiniAppLocation('formPage', editing: true),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('Task *'), 'A request I cannot confirm');
      await press(tester, 'Save');
      adapter.rejectNext = true;
      await press(tester, 'Retry save');
      expect(adapter.attempts, hasLength(2));
      final keepEditing = controller.navigate(
        const MiniAppLocation('boardPage'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Your changes may already be saved.'),
        findsWidgets,
      );
      expect(
        find.textContaining(
          'Reopening will not retry this request automatically.',
        ),
        findsOneWidget,
      );
      await press(tester, 'Return to save');
      expect(await keepEditing, isFalse);
      expect(find.text('Retry save'), findsOneWidget);
      expect(adapter.attempts, hasLength(2));
      final leaving = controller.navigate(const MiniAppLocation('boardPage'));
      await tester.pumpAndSettle();
      await press(tester, 'Leave without retrying');
      expect(await leaving, isTrue);
      expect(controller.location, const MiniAppLocation('boardPage'));
      expect(adapter.attempts, hasLength(2));
      expect(find.text('Retry save'), findsNothing);
      await controller.navigate(
        const MiniAppLocation('formPage', editing: true),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Task *')).readOnly, isFalse);
      expect(adapter.attempts, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('definite rejection allows correction with a fresh command key', (
    tester,
  ) async {
    final adapter = ResponseLostPreview(projectHubTemplate())
      ..loseResponse = false
      ..rejectNext = true;
    final controller = await mount(tester, adapter);
    await controller.navigate(const MiniAppLocation('formPage', editing: true));
    await tester.pumpAndSettle();
    await tester.enterText(field('Task *'), 'Rejected title');
    await press(tester, 'Save');
    expect(find.textContaining('Your changes were rejected.'), findsOneWidget);
    expect(tester.widget<TextField>(field('Task *')).readOnly, isFalse);
    expect(find.text('Retry save'), findsNothing);
    await tester.ensureVisible(field('Task *'));
    await tester.enterText(field('Task *'), 'Corrected title');
    await press(tester, 'Save');
    expect(adapter.attempts, hasLength(2));
    expect(adapter.attempts.last['key'], isNot(adapter.attempts.first['key']));
    expect(
      (adapter.attempts.last['input'] as Map)['data']['title'],
      'Corrected title',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('field errors identify every invalid value and focus the first', (
    tester,
  ) async {
    final adapter = ResponseLostPreview(projectHubTemplate())
      ..loseResponse = false;
    final controller = await mount(tester, adapter);
    await controller.navigate(const MiniAppLocation('formPage', editing: true));
    await tester.pumpAndSettle();
    await tester.ensureVisible(field('Effort'));
    await tester.enterText(field('Effort'), 'many');
    await press(tester, 'Save');
    final title = tester.widget<TextField>(field('Task *'));
    final effort = tester.widget<TextField>(field('Effort'));
    expect(title.decoration!.errorText, 'Task is required');
    expect(effort.decoration!.errorText, 'Effort must be a whole number.');
    expect(title.focusNode!.hasFocus, isTrue);
    expect(tester.getRect(field('Task *')).top, greaterThanOrEqualTo(0));
    expect(adapter.attempts, isEmpty);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ),
      findsWidgets,
    );
    await tester.ensureVisible(field('Task *'));
    await tester.enterText(field('Task *'), 'Valid task');
    await tester.ensureVisible(field('Effort'));
    await tester.enterText(field('Effort'), '3');
    await press(tester, 'Save');
    expect(adapter.attempts, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop editor is bounded and choices expose radio semantics', (
    tester,
  ) async {
    final adapter = PreviewRuntimeAdapter(projectHubTemplate());
    final controller = await mount(
      tester,
      adapter,
      size: const Size(1440, 1000),
    );
    final semantics = tester.ensureSemantics();
    await controller.navigate(const MiniAppLocation('formPage', editing: true));
    await tester.pumpAndSettle();
    expect(tester.getSize(field('Task *')).width, lessThanOrEqualTo(720));
    final normal = find.bySemanticsLabel('Priority: Normal');
    expect(normal, findsOneWidget);
    final node = tester.getSemantics(normal);
    expect(node.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(node.flagsCollection.isChecked, isNot(CheckedState.none));
    expect(
      tester.getSize(find.widgetWithText(ChoiceChip, 'Normal')).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Normal'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(normal).flagsCollection.isChecked,
      CheckedState.isTrue,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy save recovers the original create after a lost response',
    (tester) async {
      final adapter = ResponseLostPreview(starterTemplates()['reading']!);
      await mount(tester, adapter);
      await press(tester, 'Add book');
      await tester.enterText(field('Title *'), 'Legacy receipt recovery');
      await press(tester, 'Save');
      expect(find.textContaining('Save outcome unconfirmed.'), findsOneWidget);
      await press(tester, 'Retry save');
      expect(adapter.attempts, hasLength(2));
      expect(adapter.attempts.last, adapter.attempts.first);
      expect(
        (await adapter.query('books', {
          'filters': [
            {
              'fieldId': 'title',
              'operator': 'eq',
              'value': 'Legacy receipt recovery',
            },
          ],
        })).total,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
