import 'package:appnest_flutter/features/builder/reminder_editor.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'component_binding_options_test.dart' show mountOptions, selectOption;
import 'page_editor_compatibility_test.dart' show editView;

void main() {
  testWidgets(
    'device controls and information fields customize without records',
    (tester) async {
      final spec = phoneToolkitTemplate();
      final options = await mountOptions(tester, spec, 'flashlight');
      await selectOption(tester, 'control', 'flashlight', 'Keep screen awake');
      expect(DeviceControlOptions.fromJson(options()).control, 'keepAwake');
      final info = await mountOptions(tester, spec, 'phoneInfo');
      await tester.tap(find.text('Battery level'));
      await tester.pump();
      expect(
        DeviceInfoOptions.fromJson(info()).fields,
        isNot(contains('batteryLevel')),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('collection-free clock can be renamed from Layout', (
    tester,
  ) async {
    final spec = focusTemplate();
    expect(spec.collections, isEmpty);
    final updated = await editView(tester, spec);
    expect(updated.views.first.label, 'Renamed view');
    expect(updated.collections, isEmpty);
    expect(updated.views.first.options, spec.views.first.options);
  });

  testWidgets('clock settings work without a collection and validate', (
    tester,
  ) async {
    final spec = focusTemplate();
    final clock = spec.views.firstWhere((view) => view.type == 'clock');
    final options = await mountOptions(tester, spec, clock.id);
    await selectOption(tester, 'style', 'digital', 'Analog');
    await selectOption(tester, 'hourFormat', 'system', '24-hour');
    await tester.tap(find.text('Show seconds'));
    await tester.pump();
    final changed = spec.patch({
      'type': 'UpdateView',
      'viewId': clock.id,
      'view': (clock.toJson()..remove('id'))..['options'] = options(),
    }, () => throw StateError('Must retain identity'));
    expect(changed.view(clock.id).options, containsPair('style', 'analog'));
    expect(changed.view(clock.id).options, containsPair('showSeconds', true));
    expect(changed.collections, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus duration accepts bounded whole minutes', (tester) async {
    final spec = focusTemplate();
    final timer = spec.views.firstWhere((view) => view.type == 'timer');
    final options = await mountOptions(tester, spec, timer.id);
    await tester.enterText(find.byKey(const ValueKey('timer-duration')), '45');
    await tester.pump();
    expect(options()['durationMinutes'], 45);
    await tester.enterText(find.byKey(const ValueKey('timer-duration')), '181');
    await tester.pump();
    expect(find.text('Enter a whole number from 1 to 180.'), findsOneWidget);
    expect(
      () => spec.patch({
        'type': 'UpdateView',
        'viewId': timer.id,
        'view': (timer.toJson()..remove('id'))..['options'] = options(),
      }, () => throw StateError('Must retain identity')),
      throwsA(isA<SpecException>()),
    );
  });

  testWidgets(
    'reminder editor changes timing and retains recipient and completion condition',
    (tester) async {
      final spec = dailyPlannerTemplate();
      final original = spec.automationRequests.single;
      Map<String, dynamic>? patch;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  patch = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => ReminderEditor(spec: spec, rule: original),
                  );
                },
                child: const Text('Edit reminder'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit reminder'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('reminder-minutes')),
        '15',
      );
      await tester.tap(find.text('Update preview'));
      await tester.pumpAndSettle();
      expect(patch!['ruleId'], original.id);
      expect((patch!['rule'] as Map).containsKey('id'), isFalse);
      final changed = spec.patch(
        patch!,
        () => throw StateError('Must retain rule identity'),
      );
      final rule = changed.automationRequests.single;
      expect(rule.id, original.id);
      expect(rule.offsetSeconds, 900);
      expect(rule.effect, original.effect);
      expect(rule.condition!.toJson(), original.condition!.toJson());
    },
  );
}
