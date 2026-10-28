import 'dart:convert';
import 'dart:typed_data';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/features/builder/appearance_editor.dart';
import 'package:appnest_flutter/features/builder/page_editor.dart';
import 'package:appnest_flutter/features/builder/visual_edit_session.dart';
import 'package:appnest_flutter/features/builder/visual_inspector.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'visual_edit_session_test.dart' show snapshot;

class _Harness {
  late BuilderSnapshot server;
  late VisualEditSession session;
  late PreviewRuntimeAdapter preview;
  bool offline = false;
  _Harness(AppSpec spec) {
    server = snapshot(spec, 0);
    preview = PreviewRuntimeAdapter(spec);
    session = VisualEditSession(
      snapshot: server,
      read: () async => server,
      write: (revision, json) async {
        if (offline) throw StateError('offline');
        if (revision != server.mutation) throw StateError('conflict');
        server = snapshot(
          AppSpec.parse(server.candidateJson).patch(
            jsonDecode(json),
            () => throw StateError('No IDs expected'),
          ),
          revision + 1,
        );
        return server;
      },
      onSaved: (next, _) =>
          preview.applyPresentationSpec(AppSpec.parse(next.candidateJson)),
    );
  }
  void dispose() {
    session.dispose();
    preview.dispose();
  }
}

void main() {
  Future<_Harness> mount(
    WidgetTester tester, {
    AppSpec? spec,
    bool mobile = false,
    MiniAppEditTarget target = const MiniAppEditTarget(
      MiniAppEditKind.app,
      'app',
    ),
  }) async {
    tester.view.physicalSize = mobile
        ? const Size(320, 840)
        : const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _Harness(spec ?? starterTemplates()['reading']!);
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(mobile ? 1.5 : 1)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: mobile ? 320 : 380,
              child: VisualInspector(
                target: target,
                session: harness.session,
                preview: harness.preview,
                mobile: mobile,
                onClose: () {},
                onReload: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets(
    'cumulative controls survive style switching and reset preserves content',
    (tester) async {
      final h = await mount(tester);
      final initial = h.session.spec;
      await tap(tester, 'appearance-accent-#AF4B71');
      await tap(tester, 'appearance-typography-serif');
      await tap(tester, 'appearance-density-spacious');
      await tap(tester, 'appearance-corners-rounded');
      expect(h.session.projected.appearance!.toJson(), {
        'style': 'clean',
        'accentColor': '#AF4B71',
        'typography': 'serif',
        'density': 'spacious',
        'corners': 'rounded',
      });
      await tap(tester, 'appearance-style-playful');
      expect(h.session.projected.appearance!.toJson(), {
        'style': 'playful',
        'accentColor': '#AF4B71',
      });
      expect(await h.session.flush(), true);
      await tap(tester, 'appearance-reset');
      expect(await h.session.flush(), true);
      expect(h.session.spec.appearance!.toJson(), {'style': 'playful'});
      expect(
        h.session.spec.collections.map((c) => c.toJson()),
        initial.collections.map((c) => c.toJson()),
      );
      expect(
        h.session.spec.views.map((v) => v.toJson()),
        initial.views.map((v) => v.toJson()),
      );
      expect(h.session.spec.navigation?.toJson(), initial.navigation?.toJson());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'invalid hex blocks save and keeps other appearance choices while corrected',
    (tester) async {
      final h = await mount(tester);
      await tap(tester, 'appearance-density-spacious');
      final hex = find.byKey(const ValueKey('appearance-accent-hex'));
      await tester.ensureVisible(hex);
      await tester.enterText(hex, '#12');
      await tester.pump();
      expect(h.session.validationError, isNotNull);
      expect(await h.session.flush(), false);
      expect(find.text('Use a color like #177D79.'), findsOneWidget);
      await tester.enterText(hex, '#123abc');
      await tester.pump();
      expect(await h.session.flush(), true);
      expect(h.session.spec.appearance!.accentColor, '#123ABC');
      expect(h.session.spec.appearance!.density, 'spacious');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed appearance save retains choices and retry succeeds', (
    tester,
  ) async {
    final h = await mount(tester);
    h.offline = true;
    await tap(tester, 'appearance-style-editorial');
    expect(await h.session.flush(), false);
    await tester.pump();
    expect(h.session.error, isNotNull);
    expect(h.session.pending, true);
    expect(h.session.projected.appearance!.style, 'editorial');
    h.offline = false;
    final retry = find.text('Retry');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(h.session.error, isNull);
    expect(h.session.spec.appearance!.style, 'editorial');
    expect(h.session.pending, false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('appearance conflict disables controls and offers draft reload', (
    tester,
  ) async {
    final h = await mount(tester);
    h.server = snapshot(
      h.session.spec.patch({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': 'Other editor',
      }, () => 'unused'),
      1,
    );
    await tap(tester, 'appearance-style-playful');
    expect(await h.session.flush(), false);
    await tester.pump();
    expect(h.session.conflict, true);
    expect(find.text('Reload latest draft'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('appearance-density-compact')),
          )
          .onSelected,
      isNull,
    );
    expect(AppSpec.parse(h.server.candidateJson).name, 'Other editor');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'thumbnail samples are isolated copies and choices fit mobile large text',
    (tester) async {
      final h = await mount(tester, mobile: true);
      expect(tester.takeException(), isNull);
      final sample = (await h.preview.query('books', {})).items.first;
      await h.preview.execute(
        h.preview.spec.actions.firstWhere(
          (a) => a.capability == 'records.patch.v1',
        ),
        sample,
        {
          'data': {'title': 'My preview book'},
        },
        'appearance-test',
      );
      // Reopen to show the current preview samples, including edits made by hand.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppearanceEditor(
                spec: h.preview.spec,
                preview: h.preview,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final thumbnails = tester
          .widgetList<MiniAppRuntime>(find.byType(MiniAppRuntime))
          .toList();
      expect(thumbnails.length, 3);
      for (final thumbnail in thumbnails) {
        expect(thumbnail.adapter, isNot(same(h.preview)));
        expect(
          (await thumbnail.adapter.get(sample.id)).data['title'],
          'My preview book',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('page inspector layout changes preserve sections and date', (
    tester,
  ) async {
    final spec = dailyPlannerTemplate();
    final page = spec.navigation!.pages.first;
    final h = await mount(
      tester,
      spec: spec,
      target: MiniAppEditTarget(MiniAppEditKind.page, page.id),
    );
    await tap(tester, 'page-layout-featuredFirst');
    expect(await h.session.flush(), true);
    expect(h.session.spec.page(page.id).layout, 'featuredFirst');
    expect(h.session.spec.page(page.id).viewIds, page.viewIds);
    expect(h.session.spec.page(page.id).showDate, page.showDate);
    expect(
      h.session.spec.navigation!.tabs.map((t) => t.toJson()),
      spec.navigation!.tabs.map((t) => t.toJson()),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'page editor preserves an existing layout when editing its title',
    (tester) async {
      final initial = dailyPlannerTemplate();
      final page = initial.navigation!.pages.first;
      final spec = initial.patch(
        editPage(initial, page.id, {'layout': 'twoColumn'}),
        () => 'unused',
      );
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => PageEditor(spec: spec),
                    ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Page title'),
        'New page heading',
      );
      await tester.tap(find.text('Update preview'));
      await tester.pumpAndSettle();
      expect((result!['page'] as Map)['layout'], 'twoColumn');
      expect((result!['page'] as Map)['title'], 'New page heading');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('page editor keeps unsaved style and invalid hex across tabs', (
    tester,
  ) async {
    final spec = dailyPlannerTemplate();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => PageEditor(spec: spec),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Appearance'));
    await tester.pumpAndSettle();
    expect(
      find.text('Original appearance. Choose a style to update it.'),
      findsOneWidget,
    );
    await tap(tester, 'appearance-style-editorial');
    final hex = find.byKey(const ValueKey('appearance-accent-hex'));
    await tester.ensureVisible(hex);
    await tester.enterText(hex, '#12');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Pages'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pages'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Appearance'));
    await tester.pump();
    expect(tester.widget<TextField>(hex).controller!.text, '#12');
    expect(find.text('Use a color like #177D79.'), findsOneWidget);
    await tester.tap(find.text('Update preview'));
    await tester.pump();
    expect(find.byType(PageEditor), findsOneWidget);
    await tester.ensureVisible(hex);
    await tester.enterText(hex, '#123456');
    await tester.pump();
    await tester.tap(find.text('Update preview'));
    await tester.pumpAndSettle();
    expect(find.byType(PageEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late image bytes refresh all three thumbnail adapters', (
    tester,
  ) async {
    final h = await mount(tester);
    final bytes = Uint8List.fromList([1, 2, 3]);
    h.preview.setImageAsset('late-authorized-image', bytes);
    await tester.pumpAndSettle();
    final thumbnails = tester.widgetList<MiniAppRuntime>(
      find.byType(MiniAppRuntime),
    );
    expect(thumbnails, hasLength(3));
    for (final thumbnail in thumbnails) {
      expect(await thumbnail.adapter.readImage('late-authorized-image'), bytes);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unchanged legacy Appearance tab submits a no-op', (
    tester,
  ) async {
    final spec = dailyPlannerTemplate();
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => PageEditor(spec: spec),
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update preview'));
    await tester.pumpAndSettle();
    expect(result, {'type': 'SetAppearance', 'appearance': null});
    expect(spec.patch(result!, () => 'unused').hash, spec.hash);
    expect(tester.takeException(), isNull);
  });
}
