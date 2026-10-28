import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final moment = DateTime(2026, 9, 22, 12);
AppSpec styled(AppSpec spec, String style, {String? accent}) => spec.patch({
  'type': 'SetAppearance',
  'appearance': {'style': style, if (accent != null) 'accentColor': accent},
}, () => throw StateError('No IDs needed'));
AppSpec layout(AppSpec spec, String value) => spec.patch({
  'type': 'UpdatePage',
  'pageId': 'todayPage',
  'page': (spec.page('todayPage').toJson()..remove('id'))..['layout'] = value,
}, () => throw StateError('No IDs needed'));

Future<void> mount(
  WidgetTester tester,
  PreviewRuntimeAdapter adapter, {
  MiniAppController? controller,
  MiniAppLocation? location,
  Size size = const Size(1440, 1000),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: MiniAppRuntime(
            adapter: adapter,
            controller: controller,
            initialLocation: location,
            clock: () => moment,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> close(
  WidgetTester tester,
  PreviewRuntimeAdapter adapter, [
  MiniAppController? controller,
]) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  adapter.dispose();
  controller?.dispose();
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void main() {
  test('styles resolve typography, spacing, corners and accessible colors', () {
    final base = ThemeData(useMaterial3: true);
    final original = dailyPlannerTemplate();
    expect(resolveMiniAppAppearanceTheme(base, original), same(base));
    final clean = resolveMiniAppAppearanceTheme(
      base,
      styled(original, 'clean'),
    );
    final editorial = resolveMiniAppAppearanceTheme(
      base,
      styled(original, 'editorial'),
    );
    final playful = resolveMiniAppAppearanceTheme(
      base,
      styled(original, 'playful'),
    );
    expect(clean.extension<MiniAppAppearanceTokens>()!.spacingScale, .8);
    expect(editorial.extension<MiniAppAppearanceTokens>()!.spacingScale, 1.25);
    expect(playful.extension<MiniAppAppearanceTokens>()!.radius, 28);
    expect(editorial.textTheme.headlineMedium!.fontFamily, 'Lora');
    expect(clean.textTheme.headlineMedium!.fontFamily, isNot('Lora'));
    expect(
      playful.textTheme.headlineMedium!.fontSize,
      greaterThan(clean.textTheme.headlineMedium!.fontSize!),
    );
    expect(editorial.cardTheme.color, isNot(clean.cardTheme.color));
    for (final style in appearanceStyles) {
      for (final accent in [
        '#FFFFFF',
        '#000000',
        '#FFFF00',
        '#FF00FF',
        '#00FF00',
      ]) {
        final theme = resolveMiniAppAppearanceTheme(
          base,
          styled(original, style, accent: accent),
        );
        final c = theme.colorScheme;
        for (final pair in [
          (c.primary, c.onPrimary),
          (c.primaryContainer, c.onPrimaryContainer),
          (c.secondaryContainer, c.onSecondaryContainer),
          (c.tertiaryContainer, c.onTertiaryContainer),
          (c.surface, c.onSurface),
          (c.surfaceContainerLow, c.onSurfaceVariant),
        ]) {
          expect(
            contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(4.5),
            reason: '$style $accent',
          );
        }
      }
    }
    final overrides = original.patch({
      'type': 'SetAppearance',
      'appearance': {
        'style': 'editorial',
        'typography': 'sans',
        'density': 'compact',
        'corners': 'rounded',
      },
    }, () => 'unused');
    final overridden = resolveMiniAppAppearanceTheme(base, overrides);
    expect(overridden.textTheme.headlineMedium!.fontFamily, isNot('Lora'));
    expect(overridden.extension<MiniAppAppearanceTokens>()!.radius, 28);
    expect(overridden.extension<MiniAppAppearanceTokens>()!.spacingScale, .8);
  });

  test('presentation spec and forks retain records, claims, receipts and independent images', () async {
    final adapter = PreviewRuntimeAdapter(
      starterTemplates()['volunteer']!,
      now: moment,
      imageAssets: {
        'existing': Uint8List.fromList([1, 2, 3]),
      },
    );
    final before = (await adapter.query('shifts', {})).items.first;
    await adapter.execute(adapter.spec.action('join'), before, {}, 'once');
    adapter.applyPresentationSpec(styled(adapter.spec, 'editorial'));
    final fork = adapter.forkPresentation(styled(adapter.spec, 'playful'));
    expect((await fork.get(before.id)).claimed, true);
    expect((await fork.get(before.id)).revision, before.revision + 1);
    await fork.execute(fork.spec.action('join'), before, {}, 'once');
    expect((await fork.get(before.id)).allocated, 1);
    (await fork.readImage('existing'))[0] = 9;
    expect((await adapter.readImage('existing')).first, 1);
    final forkItem = await fork.get(before.id);
    forkItem.data['title'] = 'Changed only in thumbnail';
    expect((await adapter.get(before.id)).data['title'], before.data['title']);
    final unsafe = adapter.spec.toJson()
      ..['policyPresetRequest'] = 'personalTracker.v1';
    expect(
      () => adapter.applyPresentationSpec(AppSpec.parse(jsonEncode(unsafe))),
      throwsArgumentError,
    );
    expect(
      () => adapter.forkPresentation(AppSpec.parse(jsonEncode(unsafe))),
      throwsArgumentError,
    );
    expect(adapter.spec.appearance!.style, 'editorial');
    fork.dispose();
    expect((await adapter.readImage('existing')).first, 1);
    adapter.dispose();
  });

  testWidgets(
    'first appearance and repeated switches retain page, search, filter and unsaved form',
    (tester) async {
      final adapter = PreviewRuntimeAdapter(
        dailyPlannerTemplate(),
        now: moment,
      );
      final controller = MiniAppController();
      await adapter.execute(adapter.spec.action('addTask'), null, {
        'data': {'title': 'My custom walk', 'status': 'Open'},
      }, 'custom-task');
      await mount(
        tester,
        adapter,
        controller: controller,
        location: const MiniAppLocation('tasksPage'),
      );
      final search = find.widgetWithText(TextField, 'Search');
      await tester.enterText(search, 'walk');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      final status = find.byKey(const ValueKey('filter-allTasks-status'));
      await tester.tap(status);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open').last);
      await tester.pumpAndSettle();
      for (final style in appearanceStyles) {
        adapter.applyPresentationSpec(styled(adapter.spec, style));
        await tester.pumpAndSettle();
        expect(controller.location!.pageId, 'tasksPage');
        expect(tester.widget<DropdownButton<String>>(status).value, 'Open');
        expect(tester.widget<TextField>(search).controller!.text, 'walk');
        expect(find.text('Make time for a walk'), findsOneWidget);
        expect(find.text('My custom walk'), findsOneWidget);
        expect(find.text('Review the day'), findsNothing);
      }
      adapter.applyPresentationSpec(
        adapter.spec.patch({
          'type': 'UpdatePage',
          'pageId': 'tasksPage',
          'page': (adapter.spec.page('tasksPage').toJson()..remove('id'))
            ..['layout'] = 'twoColumn',
        }, () => 'unused'),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, 'walk');
      expect(controller.location!.pageId, 'tasksPage');
      expect(find.text('My custom walk'), findsOneWidget);
      await controller.navigate(
        const MiniAppLocation('taskEditorPage', editing: true),
      );
      await tester.pumpAndSettle();
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'My unfinished idea');
      adapter.applyPresentationSpec(styled(adapter.spec, 'clean'));
      await tester.pumpAndSettle();
      expect(controller.location!.pageId, 'taskEditorPage');
      expect(
        tester.widget<TextField>(field).controller!.text,
        'My unfinished idea',
      );
      expect(
        Theme.of(tester.element(field))
            .extension<MiniAppAppearanceTokens>()!
            .style,
        'clean',
      );
      // The style is scoped to the app, not its hosting Scaffold.
      expect(
        Theme.of(tester.element(find.byType(Scaffold)))
            .extension<MiniAppAppearanceTokens>(),
        isNull,
      );
      await close(tester, adapter, controller);
    },
  );

  for (final style in appearanceStyles) {
    testWidgets(
      '$style legacy runtime updates records and dialog styling in place',
      (tester) async {
        final adapter = PreviewRuntimeAdapter(
          starterTemplates()['reading']!,
          now: moment,
        );
        await mount(tester, adapter, size: const Size(390, 844));
        await tester.enterText(
          find.widgetWithText(TextField, 'Filter records…'),
          'Sample',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        adapter.applyPresentationSpec(styled(adapter.spec, style));
        await tester.pumpAndSettle();
        expect(
          tester
                  .widget<TextField>(
                    find.widgetWithText(TextField, 'Filter records…'),
                  )
                  .controller
                  ?.text ??
              tester
                  .widget<EditableText>(find.byType(EditableText))
                  .controller
                  .text,
          'Sample',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add book'));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(AlertDialog)))
              .extension<MiniAppAppearanceTokens>()!
              .style,
          style,
        );
        await close(tester, adapter);
      },
    );
    for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
      testWidgets('$style all planner pages at $size with 150% text', (
        tester,
      ) async {
        final adapter = PreviewRuntimeAdapter(
          styled(layout(dailyPlannerTemplate(), 'featuredFirst'), style),
          now: moment,
        );
        final controller = MiniAppController();
        await mount(
          tester,
          adapter,
          controller: controller,
          size: size,
          scale: 1.5,
        );
        for (final page in adapter.spec.navigation!.pages) {
          await controller.navigate(
            MiniAppLocation(
              page.id,
              recordId: page.id == 'taskDetailPage' ? 1 : null,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byWidgetPredicate(
              (w) => w is Row && '${w.key}'.contains('section-pair-'),
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull, reason: page.id);
        }
        await close(tester, adapter, controller);
      });
    }
  }

  for (final value in ['stacked', 'twoColumn', 'featuredFirst']) {
    for (final width in [1000.0, 1440.0]) {
      testWidgets('$value layout uses available content width at $width', (
        tester,
      ) async {
        final adapter = PreviewRuntimeAdapter(
          styled(layout(dailyPlannerTemplate(), value), 'clean'),
          now: moment,
        );
        await mount(tester, adapter, size: Size(width, 1000));
        final first = tester.getTopLeft(
          find.byKey(const ValueKey('section-todaySummary')),
        );
        final second = tester.getTopLeft(
          find.byKey(const ValueKey('section-todayTasks')),
        );
        final third = tester.getTopLeft(
          find.byKey(const ValueKey('section-overdueTasks')),
        );
        if (width == 1440 && value == 'twoColumn') {
          expect(first.dy, second.dy);
          expect(second.dx, greaterThan(first.dx));
          expect(third.dy, greaterThan(first.dy));
        } else if (width == 1440 && value == 'featuredFirst') {
          expect(first.dy, lessThan(second.dy));
          expect(second.dy, third.dy);
          expect(third.dx, greaterThan(second.dx));
        } else {
          expect(first.dx, second.dx);
          expect(first.dy, lessThan(second.dy));
          expect(second.dy, lessThan(third.dy));
        }
        await close(tester, adapter);
      });
    }
  }

  testWidgets('wide table interrupts pairing without reordering sections', (
    tester,
  ) async {
    final json = layout(dailyPlannerTemplate(), 'twoColumn').toJson();
    (json['requires'] as List).add('views.table.v1');
    final views = json['views'] as List;
    views[1] = <String, dynamic>{...views[1], 'type': 'table'};
    final adapter = PreviewRuntimeAdapter(
      AppSpec.parse(jsonEncode(json)),
      now: moment,
    );
    await mount(tester, adapter);
    final first = tester.getRect(
      find.byKey(const ValueKey('section-todaySummary')),
    );
    final table = tester.getRect(
      find.byKey(const ValueKey('section-todayTasks')),
    );
    final third = tester.getRect(
      find.byKey(const ValueKey('section-overdueTasks')),
    );
    expect(table.width, first.width);
    expect(table.top, greaterThan(first.top));
    expect(third.top, greaterThan(table.top));
    await close(tester, adapter);
  });

  for (final (size, scale, beside) in [
    (const Size(1440, 1000), 1.0, true),
    (const Size(390, 844), 1.0, false),
    (const Size(1440, 1000), 1.5, false),
  ]) {
    testWidgets('banner beside responds to $size at text scale $scale', (
      tester,
    ) async {
      final spec = styled(projectHubTemplate(), 'editorial');
      final banner = spec.view('welcome');
      final next = spec.patch({
        'type': 'UpdateView',
        'viewId': banner.id,
        'view': (banner.toJson()..remove('id'))
          ..['options'] = {
            ...banner.options,
            'imagePlacement': 'beside',
            'imageAssetId': 'preview_image_banner',
            'imageAlt': 'Sample banner',
          },
      }, () => 'unused');
      final adapter = PreviewRuntimeAdapter(
        next,
        now: moment,
        imageAssets: {
          'preview_image_banner': base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
          ),
        },
      );
      await mount(tester, adapter, size: size, scale: scale);
      expect(
        find.byKey(const ValueKey('banner-beside-welcome')),
        beside ? findsOneWidget : findsNothing,
      );
      expect(find.bySemanticsLabel('Sample banner'), findsOneWidget);
      await close(tester, adapter);
    });
  }

  testWidgets('compact design retains 48px button, icon and checkbox targets', (
    tester,
  ) async {
    final theme = resolveMiniAppAppearanceTheme(
      ThemeData(),
      styled(dailyPlannerTemplate(), 'clean'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Action')),
              IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
              Checkbox(value: false, onChanged: (_) {}),
              FilterChip(label: const Text('Filter'), onSelected: (_) {}),
            ],
          ),
        ),
      ),
    );
    for (final type in [FilledButton, IconButton, Checkbox, FilterChip]) {
      expect(
        tester.getSize(find.byType(type)).height,
        greaterThanOrEqualTo(48),
        reason: '$type',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long page titles wrap and keyboard traversal reaches styled controls',
    (tester) async {
      final json = styled(dailyPlannerTemplate(), 'editorial').toJson();
      json['navigation']['pages'][0]['title'] = 'A carefully planned day with enough time for everything that matters';
      final adapter = PreviewRuntimeAdapter(
        AppSpec.parse(jsonEncode(json)),
        now: moment,
      );
      await mount(tester, adapter, size: const Size(390, 844), scale: 1.5);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await close(tester, adapter);
    },
  );
}
