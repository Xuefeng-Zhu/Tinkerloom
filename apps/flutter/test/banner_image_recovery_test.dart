import 'dart:async';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_flutter/features/builder/component_options_editor.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Future<String?> Function() upload,
    void Function(Map<String, dynamic>) changed, {
    Map<String, dynamic>? initialOptions,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ComponentOptionsEditor(
              spec: photoJournalTemplate(),
              type: 'banner',
              collectionId: '',
              options:
                  initialOptions ??
                  const {
                    'title': 'Retained title',
                    'body': 'Retained body',
                  },
              uploadImage: upload,
              onChanged: changed,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'processing banner attaches READY after one explicit status read without re-upload',
    (tester) async {
      var uploads = 0, checks = 0;
      Map<String, dynamic>? changed;
      await mount(tester, () async {
        uploads++;
        throw PendingImageUpload(
          assetId: 'asset-A',
          checkReady: () async {
            checks++;
            return 'asset-A';
          },
        );
      }, (value) => changed = value);
      await tester.tap(find.text('Upload banner image'));
      await tester.pumpAndSettle();
      expect(find.text('Check image status'), findsOneWidget);
      expect(changed, isNull);
      await tester.tap(find.text('Check image status'));
      await tester.pumpAndSettle();
      expect(uploads, 1);
      expect(checks, 1);
      expect(changed?['imageAssetId'], 'asset-A');
      expect(changed?['title'], 'Retained title');
      expect(changed?['body'], 'Retained body');
      expect(find.text('Check image status'), findsNothing);
      expect(find.textContaining('Couldn’t upload'), findsNothing);
    },
  );

  testWidgets('leaving banner editor fences a late READY result', (
    tester,
  ) async {
    final ready = Completer<String>();
    var changes = 0;
    await mount(
      tester,
      () async => throw PendingImageUpload(
        assetId: 'asset-A',
        checkReady: () => ready.future,
      ),
      (_) => changes++,
    );
    await tester.tap(find.text('Upload banner image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check image status'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    ready.complete('asset-A');
    await tester.pump();
    expect(changes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'discarding pending banner changes no definition and permits a new selection',
    (tester) async {
      var uploads = 0, checks = 0, changes = 0;
      await mount(tester, () async {
        uploads++;
        throw PendingImageUpload(
          assetId: 'asset-A',
          checkReady: () async {
            checks++;
            return 'asset-A';
          },
        );
      }, (_) => changes++);
      await tester.tap(find.text('Upload banner image'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard pending image'));
      await tester.pumpAndSettle();
      expect(changes, 0);
      expect(checks, 0);
      expect(find.text('Check image status'), findsNothing);
      await tester.tap(find.text('Upload banner image'));
      await tester.pumpAndSettle();
      expect(uploads, 2);
    },
  );

  testWidgets(
    'pending replacement prevents Remove racing a late READY response',
    (tester) async {
      final ready = Completer<String>();
      var checks = 0;
      final changes = <Map<String, dynamic>>[];
      await mount(
        tester,
        () async => throw PendingImageUpload(
          assetId: 'replacement-image',
          checkReady: () {
            checks++;
            return ready.future;
          },
        ),
        changes.add,
        initialOptions: {
          'title': 'Retained title',
          'body': 'Retained body',
          'imageAssetId': 'original-image',
        },
      );
      await tester.ensureVisible(find.text('Replace banner image'));
      await tester.tap(find.text('Replace banner image'));
      await tester.pumpAndSettle();
      final remove = find.widgetWithText(TextButton, 'Remove image');
      expect(tester.widget<TextButton>(remove).onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Discard pending image'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('Check image status'));
      await tester.tap(find.text('Check image status'));
      await tester.pump();
      expect(tester.widget<TextButton>(remove).onPressed, isNull);
      expect(changes, isEmpty);
      ready.complete('replacement-image');
      await tester.pumpAndSettle();
      expect(changes, hasLength(1));
      expect(changes.single['imageAssetId'], 'replacement-image');
      expect(tester.widget<TextButton>(remove).onPressed, isNotNull);
      await tester.ensureVisible(find.text('Remove image'));
      await tester.tap(find.text('Remove image'));
      await tester.pumpAndSettle();
      expect(changes, hasLength(2));
      expect(changes.last['imageAssetId'], isNull);
      expect(changes.last['title'], 'Retained title');
      await tester.pump(const Duration(minutes: 1));
      expect(changes, hasLength(2));
      expect(checks, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
