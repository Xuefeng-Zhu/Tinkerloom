import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class AccessState extends DeviceCapabilitiesAdapter {
  @override
  final bool supported;
  @override
  Set<String> get requested => {'battery', 'flashlight'};
  AccessState(this.supported);
}

void main() {
  testWidgets(
    'synthetic preview queries and controls do not need native channels',
    (tester) async {
      final adapter = PreviewRuntimeAdapter(phoneToolkitTemplate());
      final controller = MiniAppController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniAppRuntime(adapter: adapter, controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Battery level: 78%'), findsOneWidget);
      expect(find.text('Simulated phone · preview only'), findsOneWidget);
      await tester.tap(find.text('Controls'));
      await tester.pumpAndSettle();
      final flashlight = find.widgetWithText(SwitchListTile, 'Flashlight');
      await tester.ensureVisible(flashlight);
      await tester.tap(flashlight);
      await tester.pumpAndSettle();
      expect(adapter.deviceCapabilities.values['flashlight'], isTrue);
      final other = PreviewRuntimeAdapter(phoneToolkitTemplate());
      expect(other.deviceCapabilities.values['flashlight'], isFalse);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      other.dispose();
      controller.dispose();
    },
  );
  for (final supported in [true, false]) {
    testWidgets(
      'device access is off by default; mobile available = $supported',
      (tester) async {
        final device = AccessState(supported);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: DeviceAccessPanel(adapter: device)),
          ),
        );
        expect(
          tester
              .widgetList<SwitchListTile>(find.byType(SwitchListTile))
              .every((s) => !s.value),
          isTrue,
        );
        if (!supported) {
          expect(
            find.text('Available in the Android or iOS app'),
            findsOneWidget,
          );
          expect(
            tester
                .widgetList<SwitchListTile>(find.byType(SwitchListTile))
                .every((s) => s.onChanged == null),
            isTrue,
          );
        }
        await tester.pumpWidget(const SizedBox());
        device.dispose();
      },
    );
  }
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    for (final page in ['phonePage', 'controlsPage']) {
      testWidgets('device layout $page $size at large text', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final adapter = PreviewRuntimeAdapter(phoneToolkitTemplate());
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(1.5),
              ),
              child: Scaffold(
                body: MiniAppRuntime(
                  adapter: adapter,
                  initialLocation: MiniAppLocation(page),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        adapter.dispose();
      });
    }
  }
}
