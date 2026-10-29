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
    void Function(Map<String, dynamic>) changed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ComponentOptionsEditor(
              spec: photoJournalTemplate(),
              type: 'banner',
              collectionId: '',
              options: const {
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
}
