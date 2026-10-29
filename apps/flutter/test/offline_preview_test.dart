import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_flutter/preview.dart';

void main() {
  testWidgets('original template renderer opens without a backend', (
    tester,
  ) async {
    await tester.pumpWidget(const TinkerloomPreviewApp());
    expect(find.text('Try a template'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Project Hub'), 400);
    await tester.tap(find.text('Project Hub'));
    await tester.pumpAndSettle();
    expect(find.text('Offline preview · sample data'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Project Hub'), findsOneWidget);
    expect(find.text('Offline preview · sample data'), findsNothing);
  });
}
