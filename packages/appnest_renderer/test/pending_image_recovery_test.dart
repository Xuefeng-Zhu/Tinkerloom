import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic 16x8 solid-color PNG, not user media.
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAICAIAAAB/FOjAAAAAE0lEQVR4nGO4ZGBGEmIY1UALDQDGgZwBzNOGvQAAAABJRU5ErkJggg==',
);

class PendingPreview extends PreviewRuntimeAdapter {
  PendingPreview() : super(photoJournalTemplate());
  int uploads = 0, checks = 0;
  bool deny = false, stillProcessing = false;
  Completer<String>? status;
  final commands = <Map<String, dynamic>>[];
  @override
  bool get readOnly => deny;
  @override
  Future<Uint8List?> pickImage() async => png;
  @override
  Future<Uint8List> readImage(String assetId, {bool thumbnail = true}) async =>
      png;
  PendingImageUpload get pending => PendingImageUpload(
    assetId: 'synthetic-ready-image',
    checkReady: () async {
      checks++;
      if (status != null) return status!.future;
      if (stillProcessing) throw pending;
      return 'synthetic-ready-image';
    },
  );
  @override
  Future<String> uploadImage(
    Uint8List imageBytes, {
    required String collectionId,
    required String fieldId,
    RuntimeItem? record,
  }) async {
    uploads++;
    throw pending;
  }

  @override
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  ) async {
    commands.add({'input': jsonDecode(jsonEncode(input)), 'key': key});
    await super.execute(action, record, input, key);
  }
}

class LegacyHarness {
  LegacyHarness(PendingPreview initial) : adapter = ValueNotifier(initial);
  final ValueNotifier<PendingPreview> adapter;
  Map<String, dynamic>? saved;
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => ValueListenableBuilder<PendingPreview>(
                    valueListenable: adapter,
                    builder: (_, current, _) => RecordForm(
                      key: const ValueKey('retained-form'),
                      collection: current.spec.collection('memories'),
                      members: () async => [],
                      adapter: current,
                    ),
                  ),
                );
              },
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );
    await press(tester, 'Open form');
  }
}

Future<void> press(WidgetTester tester, String label) async {
  final target = find.text(label).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> title(WidgetTester tester, String value) async {
  final field = find.widgetWithText(TextField, 'Title *');
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

FilledButton button(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

void main() {
  testWidgets(
    'legacy READY check attaches once and preserves the typed title',
    (tester) async {
      final adapter = PendingPreview(), host = LegacyHarness(PendingPreview());
      host.adapter.value.dispose();
      host.adapter.value = adapter;
      await host.mount(tester);
      await title(tester, 'Retained title');
      await press(tester, 'Choose image');
      expect(adapter.uploads, 1);
      expect(adapter.checks, 0);
      expect(button(tester, 'Save').onPressed, isNull);
      await tester.pump(const Duration(minutes: 1));
      expect(adapter.checks, 0, reason: 'Status checks are never automatic.');
      await press(tester, 'Check image status');
      expect(adapter.checks, 1);
      expect(
        find.text('Image attached. Save the form to keep it.'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsOneWidget);
      await press(tester, 'Save');
      expect((host.saved!['data'] as Map)['title'], 'Retained title');
      expect((host.saved!['data'] as Map)['photo'], 'synthetic-ready-image');
      expect(adapter.uploads, 1);
      await tester.pumpWidget(const SizedBox());
      host.adapter.dispose();
      adapter.dispose();
    },
  );

  testWidgets(
    'discarding a pending image preserves other values and enables Save',
    (tester) async {
      final adapter = PendingPreview(), host = LegacyHarness(PendingPreview());
      host.adapter.value.dispose();
      host.adapter.value = adapter;
      await host.mount(tester);
      await title(tester, 'Keep these words');
      await press(tester, 'Choose image');
      await press(tester, 'Discard pending image');
      expect(button(tester, 'Save').onPressed, isNotNull);
      await press(tester, 'Save');
      expect((host.saved!['data'] as Map)['title'], 'Keep these words');
      expect((host.saved!['data'] as Map)['photo'], isNull);
      expect(adapter.checks, 0);
      await tester.pumpWidget(const SizedBox());
      host.adapter.dispose();
      adapter.dispose();
    },
  );

  testWidgets(
    'a still-processing check retains the same upload without reupload',
    (tester) async {
      final adapter = PendingPreview()..stillProcessing = true;
      final host = LegacyHarness(adapter);
      await host.mount(tester);
      await title(tester, 'Still retained');
      await press(tester, 'Choose image');
      await press(tester, 'Check image status');
      expect(adapter.uploads, 1);
      expect(adapter.checks, 1);
      expect(button(tester, 'Save').onPressed, isNull);
      expect(find.text('Check image status'), findsOneWidget);
      adapter.stillProcessing = false;
      await press(tester, 'Check image status');
      expect(adapter.checks, 2);
      expect(button(tester, 'Save').onPressed, isNotNull);
      expect(find.text('Could not upload image.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      host.adapter.dispose();
      adapter.dispose();
    },
  );

  testWidgets(
    'a pending READY check holds the form and cannot be submitted twice',
    (tester) async {
      final adapter = PendingPreview()..status = Completer<String>();
      final host = LegacyHarness(adapter);
      await host.mount(tester);
      await title(tester, 'Busy retained');
      await press(tester, 'Choose image');
      final check = find.text('Check image status');
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pump();
      expect(button(tester, 'Save').onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Checking image…'),
            )
            .onPressed,
        isNull,
      );
      expect(adapter.checks, 1);
      adapter.status!.complete('synthetic-ready-image');
      await tester.pumpAndSettle();
      expect(button(tester, 'Save').onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
      host.adapter.dispose();
      adapter.dispose();
    },
  );

  testWidgets(
    'a late READY response cannot attach to a replacement form context',
    (tester) async {
      final old = PendingPreview()..status = Completer<String>();
      final fresh = PendingPreview(), host = LegacyHarness(old);
      await host.mount(tester);
      await title(tester, 'Keep new context');
      await press(tester, 'Choose image');
      await tester.ensureVisible(find.text('Check image status'));
      await tester.tap(find.text('Check image status'));
      await tester.pump();
      host.adapter.value = fresh;
      await tester.pumpAndSettle();
      old.status!.complete('synthetic-ready-image');
      await tester.pumpAndSettle();
      expect(
        find.text('Image attached. Save the form to keep it.'),
        findsNothing,
      );
      expect(find.byType(Image), findsNothing);
      await press(tester, 'Save');
      expect((host.saved!['data'] as Map)['title'], 'Keep new context');
      expect((host.saved!['data'] as Map)['photo'], isNull);
      expect(fresh.uploads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      host.adapter.dispose();
      old.dispose();
      fresh.dispose();
    },
  );

  testWidgets(
    'authority loss during READY check never attaches the late image',
    (tester) async {
      final adapter = PendingPreview()..status = Completer<String>();
      final host = LegacyHarness(adapter);
      await host.mount(tester);
      await title(tester, 'Keep other values');
      await press(tester, 'Choose image');
      await tester.ensureVisible(find.text('Check image status'));
      await tester.tap(find.text('Check image status'));
      await tester.pump();
      adapter.deny = true;
      adapter.status!.complete('synthetic-ready-image');
      await tester.pumpAndSettle();
      expect(
        find.text('Image attached. Save the form to keep it.'),
        findsNothing,
      );
      expect(find.byType(Image), findsNothing);
      expect(find.widgetWithText(TextField, 'Title *'), findsOneWidget);
      expect(adapter.commands, isEmpty);
      await tester.pumpWidget(const SizedBox());
      host.adapter.dispose();
      adapter.dispose();
    },
  );

  testWidgets(
    'unmounting during READY check does not update disposed form state',
    (tester) async {
      final adapter = PendingPreview()..status = Completer<String>();
      final host = LegacyHarness(adapter);
      await host.mount(tester);
      await press(tester, 'Choose image');
      await tester.ensureVisible(find.text('Check image status'));
      await tester.tap(find.text('Check image status'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      adapter.status!.complete('synthetic-ready-image');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(adapter.commands, isEmpty);
      host.adapter.dispose();
      adapter.dispose();
    },
  );

  testWidgets(
    'multi-step form blocks Next until READY then saves the image once',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = PendingPreview();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniAppRuntime(
              adapter: adapter,
              initialLocation: const MiniAppLocation('formPage'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await title(tester, 'Two-step image');
      await press(tester, 'Choose image');
      expect(button(tester, 'Next step').onPressed, isNull);
      adapter.status = Completer<String>();
      await tester.ensureVisible(find.text('Check image status'));
      await tester.tap(find.text('Check image status'));
      await tester.pump();
      expect(button(tester, 'Next step').onPressed, isNull);
      adapter.status!.complete('synthetic-ready-image');
      await tester.pumpAndSettle();
      expect(button(tester, 'Next step').onPressed, isNotNull);
      await press(tester, 'Next step');
      final caption = find.widgetWithText(TextField, 'Caption');
      await tester.ensureVisible(caption);
      await tester.enterText(caption, 'Caption retained after READY');
      await press(tester, 'Save');
      expect(adapter.uploads, 1);
      expect(adapter.checks, 1);
      expect(adapter.commands, hasLength(1));
      final data = adapter.commands.single['input']['data'] as Map;
      expect(data['title'], 'Two-step image');
      expect(data['caption'], 'Caption retained after READY');
      expect(data['photo'], 'synthetic-ready-image');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );

  testWidgets(
    'multi-step discard unblocks Next and preserves the typed title',
    (tester) async {
      final adapter = PendingPreview();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniAppRuntime(
              adapter: adapter,
              initialLocation: const MiniAppLocation('formPage'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await title(tester, 'Words survive discard');
      await press(tester, 'Choose image');
      expect(button(tester, 'Next step').onPressed, isNull);
      await press(tester, 'Discard pending image');
      expect(button(tester, 'Next step').onPressed, isNotNull);
      await press(tester, 'Next step');
      await press(tester, 'Save');
      expect(adapter.commands, hasLength(1));
      final data = adapter.commands.single['input']['data'] as Map;
      expect(data['title'], 'Words survive discard');
      expect(data['photo'], isNull);
      expect(adapter.uploads, 1);
      expect(adapter.checks, 0);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );
}
