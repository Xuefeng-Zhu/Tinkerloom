import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppSpec withNavigation(AppSpec spec) {
  final json = spec.toJson();
  (json['requires'] as List).add('navigation.v1');
  json['navigation'] = {
    'entryPageId': 'home',
    'pages': [
      {
        'id': 'home',
        'title': 'Home',
        'viewIds': [spec.views.first.id],
      },
    ],
    'tabs': [
      {'pageId': 'home', 'label': 'Home', 'icon': 'people'},
    ],
  };
  return AppSpec.parse(jsonEncode(json));
}

Future<void> mount(WidgetTester tester, RuntimeAdapter adapter) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: MiniAppRuntime(adapter: adapter)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final rich in [false, true]) {
    for (final archived in [false, true]) {
      testWidgets(
        '${rich ? 'rich' : 'legacy'} shell distinguishes restricted member from archive=$archived',
        (tester) async {
          var spec = starterTemplates()['reading']!;
          if (rich) spec = withNavigation(spec);
          final adapter = RestrictedPreview(spec, isArchived: archived);
          await mount(tester, adapter);
          expect(
            find.text(
              archived
                  ? 'Archived · This app is read-only'
                  : 'Read-only · Only the owner and builders can make changes',
            ),
            findsOneWidget,
          );
          if (!archived) expect(find.textContaining('Archived'), findsNothing);
          expect(find.text('Add book'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          adapter.dispose();
        },
      );
    }

    testWidgets(
      '${rich ? 'rich' : 'legacy'} capacity rejection shows a useful message without confirming a claim',
      (tester) async {
        var spec = starterTemplates()['volunteer']!;
        if (rich) spec = withNavigation(spec);
        final adapter = RejectedClaimPreview(spec);
        await mount(tester, adapter);
        final join = find.text('Join shift').first;
        await tester.ensureVisible(join);
        await tester.tap(join);
        await tester.pumpAndSettle();
        expect(
          find.text('This shift is full. Choose another shift.'),
          findsOneWidget,
        );
        expect(find.textContaining('SpecException'), findsNothing);
        expect(find.textContaining('Your place is confirmed'), findsNothing);
        expect(
          (await adapter.query(
            'shifts',
            {},
          )).items.every((item) => !item.claimed),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        adapter.dispose();
      },
    );
  }

  testWidgets(
    'unexpected transport failures use a calm fallback without diagnostics',
    (tester) async {
      final adapter = RejectedClaimPreview(
        starterTemplates()['volunteer']!,
        unexpected: true,
      );
      await mount(tester, adapter);
      final join = find.text('Join shift').first;
      await tester.ensureVisible(join);
      await tester.tap(join);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not complete the request. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('internal transport detail'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );

  testWidgets(
    'legacy timestamps explain the format without a fixed historical date',
    (tester) async {
      final adapter = PreviewRuntimeAdapter(starterTemplates()['volunteer']!);
      await mount(tester, adapter);
      await tester.tap(find.text('Create shift'));
      await tester.pumpAndSettle();
      expect(
        find.text('Local date and time: YYYY-MM-DD HH:MM'),
        findsOneWidget,
      );
      expect(find.textContaining('2026-09-22 10:00'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );
}

class RestrictedPreview extends PreviewRuntimeAdapter {
  final bool isArchived;
  RestrictedPreview(super.spec, {required this.isArchived});
  @override
  bool get archived => isArchived;
  @override
  bool get readOnly => true;
  @override
  String get role => isArchived ? 'owner' : 'member';
  @override
  bool permits(ActionSpec action) => false;
}

class RejectedClaimPreview extends PreviewRuntimeAdapter {
  final bool unexpected;
  RejectedClaimPreview(super.spec, {this.unexpected = false});
  @override
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  ) async {
    if (unexpected) throw StateError('internal transport detail');
    throw const SpecException('This shift is full. Choose another shift.');
  }
}
