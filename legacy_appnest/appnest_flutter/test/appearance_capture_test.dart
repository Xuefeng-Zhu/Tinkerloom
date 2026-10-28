import 'dart:io';
import 'dart:ui' as ui;

import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/builder/builder_screen.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'builder_creation_test.dart' show draft;
import 'visual_inspector_test.dart' show VisualClient;

/// Opt-in screenshots use synthetic authenticated transport and preview records.
/// They do not verify a running server, model provider, or live publication.
void main() {
  const output = String.fromEnvironment('APPNEST_CAPTURE_DIR');
  final client = VisualClient();
  setUpAll(() => transport.client = client);
  tearDownAll(client.close);
  setUpAll(() async {
    if (output.isEmpty) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Lora')..addFont(
          File('assets/fonts/Lora.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        ))
        .load();
    var directory = File(Platform.resolvedExecutable).parent;
    for (var level = 0; level < 10; level++) {
      final base = '${directory.path}/bin/cache/artifacts/material_fonts';
      final icon = File('$base/MaterialIcons-Regular.otf');
      if (await icon.exists()) {
        await (FontLoader(
          'MaterialIcons',
        )..addFont(icon.readAsBytes().then(ByteData.sublistView))).load();
        await (FontLoader('AppNestCapture')..addFont(
              File('$base/Roboto-Regular.ttf')
                  .readAsBytes()
                  .then(ByteData.sublistView),
            ))
            .load();
        break;
      }
      directory = directory.parent;
    }
  });

  for (final mobile in [false, true]) {
    testWidgets('appearance builder ${mobile ? 'mobile' : 'desktop'}', (
      tester,
    ) async {
      client.current = draft(
        spec: dailyPlannerTemplate().patch({
          'type': 'SetAppearance',
          'appearance': {'style': 'editorial'},
        }, () => throw StateError('No IDs expected')),
      );
      tester.view.physicalSize = mobile
          ? const Size(390, 844)
          : const Size(1440, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: output.isEmpty ? null : 'AppNestCapture',
            ),
            home: BuilderScreen(initial: client.current),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (mobile) {
        await tester.tap(find.text('Try'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('open-appearance')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('appearance-style-editorial')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (output.isNotEmpty) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/appearance-builder-${mobile ? 'mobile' : 'desktop'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
