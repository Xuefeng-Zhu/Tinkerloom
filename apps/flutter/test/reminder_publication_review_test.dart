import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';
import 'package:tinkerloom_flutter/client.dart' as transport;
import 'package:tinkerloom_flutter/features/builder/builder_screen.dart';

import 'builder_creation_test.dart' show CreationClient, draft;

class _PublishedReviewClient extends CreationClient {
  final publications = <PublishRequest>[];
  @override
  Future<T> callServerEndpoint<T>(
    String endpoint,
    String method,
    Map<String, dynamic> args, {
    bool authenticated = true,
  }) async {
    if ('$endpoint.$method' == 'runtime.query') {
      return RecordPage(records: [], total: 0) as T;
    }
    if ('$endpoint.$method' == 'builder.publish') {
      publications.add(args['request'] as PublishRequest);
      return 'app-A' as T;
    }
    return super.callServerEndpoint<T>(
      endpoint,
      method,
      args,
      authenticated: authenticated,
    );
  }
}

void main() {
  testWidgets(
    'unknown current reminder approvals require explicit review before publication',
    (tester) async {
      final client = _PublishedReviewClient();
      addTearDown(client.close);
      transport.client = client;
      final initial = draft(spec: dailyPlannerTemplate())
          .copyWith(baseVersionId: 'version-A');
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? published;
      await tester.pumpWidget(
        MaterialApp(
          home: BuilderScreen(
            initial: initial,
            onPublished: (id) async => published = id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply changes'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Current reminder approvals are not available here',
        ),
        findsOneWidget,
      );
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Apply changes'),
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(client.publications, isEmpty);
      await tester.tap(
        find.text('I reviewed the reminder choices for this publication'),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(client.publications, hasLength(1));
      expect(client.publications.single.enabledRuleIds, isEmpty);
      expect(published, '1');
    },
  );
}
