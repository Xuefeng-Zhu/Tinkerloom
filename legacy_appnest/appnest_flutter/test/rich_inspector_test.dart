import 'dart:convert';

import 'package:appnest_flutter/features/builder/visual_edit_session.dart';
import 'package:appnest_flutter/features/builder/visual_inspector.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'visual_edit_session_test.dart' show snapshot;

void main() {
  Future<VisualEditSession> mount(
    WidgetTester tester,
    AppSpec spec,
    String viewId,
  ) async {
    var server = snapshot(spec, 0);
    final session = VisualEditSession(
      snapshot: server,
      read: () async => server,
      write: (revision, json) async {
        expect(revision, server.mutation);
        server = snapshot(
          AppSpec.parse(server.candidateJson).patch(
            jsonDecode(json),
            () => throw StateError('Unexpected new ID'),
          ),
          revision + 1,
        );
        return server;
      },
      onSaved: (_, _) {},
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisualInspector(
            target: MiniAppEditTarget(MiniAppEditKind.section, viewId),
            session: session,
            onClose: () {},
            onReload: () {},
          ),
        ),
      ),
    );
    return session;
  }

  testWidgets('chart style and group finish as one valid inspector edit', (
    tester,
  ) async {
    final session = await mount(tester, habitTrackerTemplate(), 'dailyMinutes');
    await tester.tap(find.byKey(const ValueKey('component-style-line')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Donut').last);
    await tester.pumpAndSettle();
    expect(session.validationError, isNotNull);
    expect(session.snapshot.mutation, 0);
    final grouping = find.byKey(const ValueKey('inspector-group-null'));
    await tester.ensureVisible(grouping);
    await tester.tap(grouping);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Category').last);
    await tester.pumpAndSettle();
    expect(session.validationError, isNull);
    expect(await session.flush(), true);
    final chart = session.spec.view('dailyMinutes');
    expect(chart.options, {'style': 'donut', 'metric': 'count'});
    expect(chart.groupByFieldId, 'category');
    expect(session.snapshot.mutation, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rapid edits to separate banner options both survive autosave', (
    tester,
  ) async {
    final spec = projectHubTemplate();
    final banner = spec.views.firstWhere((v) => v.type == 'banner');
    final session = await mount(tester, spec, banner.id);
    final title = find.byKey(const ValueKey('component-text-title'));
    await tester.ensureVisible(title);
    await tester.enterText(title, 'A new heading');
    await tester.pump();
    final body = find.byKey(const ValueKey('component-text-body'));
    await tester.ensureVisible(body);
    await tester.enterText(body, 'A new description');
    await tester.pump();
    expect(await session.flush(), true);
    final options = session.spec.view(banner.id).options;
    expect(options['title'], 'A new heading');
    expect(options['body'], 'A new description');
    expect(session.snapshot.mutation, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('choosing a board move action also binds the action', (
    tester,
  ) async {
    final original = projectHubTemplate();
    final board = original.view('taskBoard');
    final spec = original.patch({
      'type': 'UpdateView',
      'viewId': board.id,
      'view': (board.toJson()..remove('id'))
        ..remove('options')
        ..['actionIds'] = ['addRecord', 'editRecord'],
    }, () => throw StateError('Unexpected new ID'));
    final session = await mount(tester, spec, board.id);
    await tester.tap(find.text('Drag cards between columns'));
    await tester.pump();
    expect(session.validationError, isNotNull);
    await tester.tap(find.byKey(const ValueKey('component-moveActionId-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change status').last);
    await tester.pumpAndSettle();
    expect(session.validationError, isNull);
    expect(await session.flush(), true);
    expect(session.spec.view(board.id).actionIds, [
      'addRecord',
      'editRecord',
      'moveRecord',
    ]);
    expect(session.spec.view(board.id).options, {
      'draggable': true,
      'moveActionId': 'moveRecord',
    });
    await tester.pumpWidget(const SizedBox());
  });
}
