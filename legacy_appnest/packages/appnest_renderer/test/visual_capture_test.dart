import 'dart:io';
import 'dart:ui' as ui;

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in artifacts are synthetic renderer evidence, never live server proof.
/// flutter test test/visual_capture_test.dart \
///   --dart-define=APPNEST_CAPTURE_DIR=/tmp/appnest-miniapp-captures
class _DeviceCaptureState extends PreviewDeviceCapabilitiesAdapter {
  @override
  final bool supported;
  @override
  bool get preview => false;
  @override
  Set<String> get granted => {};
  _DeviceCaptureState(super.spec, this.supported);
}

class _DeviceCaptureRuntime extends PreviewRuntimeAdapter {
  @override
  late final PreviewDeviceCapabilitiesAdapter deviceCapabilities =
      _DeviceCaptureState(spec, available);
  final bool available;
  _DeviceCaptureRuntime(super.spec, {required this.available, super.now});
}

void main() {
  const output = String.fromEnvironment('APPNEST_CAPTURE_DIR');
  setUpAll(() async {
    if (output.isEmpty) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    // The host already bundles this font; captures must exercise the real
    // editorial face rather than Flutter test's placeholder glyphs.
    final lora = File('../../appnest_flutter/assets/fonts/Lora.ttf');
    await (FontLoader(
      'Lora',
    )..addFont(lora.readAsBytes().then(ByteData.sublistView))).load();
    // Locate the bundled SDK icon font without checking in machine-specific paths.
    var directory = File(Platform.resolvedExecutable).parent;
    for (var level = 0; level < 10; level++) {
      final font = File(
        '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (await font.exists()) {
        final textFont = File(
          '${directory.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        );
        await (FontLoader(
          'AppNestCapture',
        )..addFont(textFont.readAsBytes().then(ByteData.sublistView))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
        break;
      }
      directory = directory.parent;
    }
  });
  final moment = DateTime(2026, 9, 22, 12);
  final cases = <(String, Size, MiniAppLocation)>[
    (
      'today-desktop',
      const Size(1440, 1000),
      const MiniAppLocation('todayPage'),
    ),
    ('today-mobile', const Size(390, 844), const MiniAppLocation('todayPage')),
    ('tasks-mobile', const Size(390, 844), const MiniAppLocation('tasksPage')),
    (
      'details-mobile',
      const Size(390, 844),
      const MiniAppLocation('taskDetailPage', recordId: 2),
    ),
    (
      'editor-mobile',
      const Size(390, 844),
      const MiniAppLocation('taskEditorPage', recordId: 2, editing: true),
    ),
    (
      'progress-mobile',
      const Size(390, 844),
      const MiniAppLocation('progressPage'),
    ),
  ];
  final richCases = <(String, Size, MiniAppLocation, AppSpec)>[
    for (final size in [const Size(390, 844), const Size(1440, 1000)]) ...[
      (
        'rich-board-${size.width.toInt()}',
        size,
        const MiniAppLocation('boardPage'),
        projectHubTemplate(),
      ),
      (
        'rich-table-${size.width.toInt()}',
        size,
        const MiniAppLocation('tablePage'),
        projectHubTemplate(),
      ),
      (
        'rich-calendar-${size.width.toInt()}',
        size,
        const MiniAppLocation('calendarPage'),
        projectHubTemplate(),
      ),
      (
        'rich-charts-${size.width.toInt()}',
        size,
        const MiniAppLocation('patternsPage'),
        habitTrackerTemplate(),
      ),
      (
        'rich-gallery-${size.width.toInt()}',
        size,
        const MiniAppLocation('galleryPage'),
        photoJournalTemplate(),
      ),
      (
        'rich-form-${size.width.toInt()}',
        size,
        const MiniAppLocation('formPage'),
        photoJournalTemplate(),
      ),
    ],
  ];
  for (final (name, size, location, template) in [
    for (final (name, size, location) in cases)
      (name, size, location, dailyPlannerTemplate()),
    ...richCases,
    for (final size in [const Size(390, 1000), const Size(1440, 1000)])
      for (final status in ['accessOff', 'unavailable'])
        (
          'device-$status-${size.width.toInt()}',
          size,
          const MiniAppLocation('controlsPage'),
          phoneToolkitTemplate(),
        ),
    for (final size in [const Size(390, 1000), const Size(1440, 1000)])
      for (final page in ['phonePage', 'controlsPage'])
        (
          'device-$page-${size.width.toInt()}',
          size,
          MiniAppLocation(page),
          phoneToolkitTemplate(),
        ),
    for (final (utility, template) in [
      ('notes', notesTemplate()),
      ('reminders', remindersTemplate()),
      ('calendar', calendarTemplate()),
    ])
      for (final size in [const Size(390, 844), const Size(1440, 1000)])
        (
          'utility-$utility-${size.width.toInt()}',
          size,
          MiniAppLocation(template.navigation!.entryPageId),
          template,
        ),
    for (final style in ['digital', 'analog'])
      for (final size in [const Size(390, 844), const Size(1440, 1000)])
        (
          'utility-focus-$style-${size.width.toInt()}',
          size,
          const MiniAppLocation('focusPage'),
          focusTemplate().patch({
            'type': 'UpdateView',
            'viewId': 'localClock',
            'view': {
              ...focusTemplate().view('localClock').toJson()..remove('id'),
              'options': {'style': style, 'hourFormat': '24', 'showDate': true},
            },
          }, () => 'unused'),
        ),
    for (final style in appearanceStyles)
      for (final size in [const Size(390, 844), const Size(1440, 1000)])
        (
          'appearance-$style-${size.width.toInt()}',
          size,
          const MiniAppLocation('todayPage'),
          dailyPlannerTemplate()
              .patch({
                'type': 'SetAppearance',
                'appearance': {'style': style},
              }, () => 'unused')
              .patch({
                'type': 'UpdatePage',
                'pageId': 'todayPage',
                'page': {
                  ...dailyPlannerTemplate().page('todayPage').toJson()
                    ..remove('id'),
                  'layout': 'featuredFirst',
                },
              }, () => 'unused'),
        ),
  ]) {
    testWidgets('isolated preview visual layout $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter =
          name.startsWith('device-accessOff') ||
              name.startsWith('device-unavailable')
          ? _DeviceCaptureRuntime(
              template,
              now: moment,
              available: name.startsWith('device-accessOff'),
            )
          : PreviewRuntimeAdapter(template, now: moment);
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
            home: Scaffold(
              body: MiniAppRuntime(
                adapter: adapter,
                initialLocation: location,
                clock: () => moment,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic records'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (output.isNotEmpty) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    });
  }
}
