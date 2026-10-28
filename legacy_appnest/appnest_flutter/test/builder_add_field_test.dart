import 'dart:convert';

import 'package:appnest_flutter/client.dart' as transport;
import 'package:appnest_flutter/features/builder/builder_screen.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'builder_creation_test.dart' show draft;
import 'visual_inspector_test.dart' show VisualClient;

void main() {
  testWidgets(
    'Content Add field binds the allocated field to same-collection add edit and details',
    (tester) async {
      final json =
          jsonDecode(notesTemplate().canonical) as Map<String, dynamic>;
      (json['collections'] as List).add({
        ...json['collections'][0] as Map<String, dynamic>,
        'id': 'otherNotes',
        'label': 'Other notes',
      });
      (json['views'] as List).add({
        'id': 'otherDetails',
        'type': 'details',
        'collectionId': 'otherNotes',
      });
      final before = AppSpec.parse(jsonEncode(json));
      final client = VisualClient()..current = draft(spec: before);
      transport.client = client;
      addTearDown(client.close);
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: BuilderScreen(initial: client.current)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('customize-app')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Content'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename app or field'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a field').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .first,
        'Source',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Update preview'));
      await tester.pumpAndSettle();

      expect(client.writes, hasLength(1));
      final patch = jsonDecode(
        client.writes.single['patchJson'] as String,
      ) as Map<String, dynamic>;
      expect(patch['type'], 'AddField');
      expect(patch['collectionId'], 'notes');
      expect(patch['viewIds'], ['entryDetails', 'entryEditor']);
      expect((patch['field'] as Map).containsKey('id'), isFalse);
      // VisualClient applies the captured payload through the real AppSpec.patch,
      // allocating its field identity exactly as the trusted server does.
      final after = AppSpec.parse(client.current.candidateJson);
      final field = after
          .collection('notes')
          .fields
          .singleWhere((f) => f.label == 'Source');
      expect(field.id, 'unused');
      for (final id in ['entryDetails', 'entryEditor']) {
        expect(after.view(id).fieldIds, [
          ...before.view(id).fieldIds,
          field.id,
        ]);
      }
      expect(
        after.view('allEntries').toJson(),
        before.view('allEntries').toJson(),
      );
      expect(
        after.view('otherDetails').toJson(),
        before.view('otherDetails').toJson(),
      );
      expect(
        after.collection('otherNotes').toJson(),
        before.collection('otherNotes').toJson(),
      );

      // Exercise the controls a person uses in the updated preview.
      await tester.tap(find.widgetWithText(FilledButton, 'Add entry'));
      await tester.pumpAndSettle();
      expect(find.text('Source'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Community morning'));
      await tester.pumpAndSettle();
      expect(find.text('Source'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit entry'));
      await tester.pumpAndSettle();
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('This page is unavailable'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
