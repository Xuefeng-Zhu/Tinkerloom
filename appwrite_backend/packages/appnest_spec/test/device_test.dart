import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

void main() {
  test('Phone Toolkit uses bounded collection-free device capabilities', () {
    final spec = phoneToolkitTemplate();
    expect(spec.collections, isEmpty);
    expect(spec.actions, isEmpty);
    expect(spec.views.every((view) => view.contentOnly), isTrue);
    expect(
      requestedDeviceCapabilities(spec),
      deviceCapabilityLabels.keys.toSet(),
    );
    expect(AppSpec.parse(spec.canonical).hash, spec.hash);
  });
  test(
    'device fields reject identifiers, duplicates, empty and arbitrary options',
    () {
      for (final options in <Map<String, dynamic>>[
        {'fields': []},
        {
          'fields': ['batteryLevel', 'batteryLevel'],
        },
        {
          'fields': ['serialNumber'],
        },
        {
          'fields': ['wifiSSID'],
        },
        {
          'fields': ['model'],
          'upload': true,
        },
        {
          'fields': ['location'],
        },
      ]) {
        expect(
          () => DeviceInfoOptions.fromJson(options),
          throwsA(isA<SpecException>()),
        );
      }
      for (final options in <Map<String, dynamic>>[
        {'control': 'wifi'},
        {'control': 'bluetooth'},
        {'control': 'brightness', 'value': 2},
        {'control': 'eval'},
        {'control': 'flashlight', 'onLoad': true},
      ]) {
        expect(
          () => DeviceControlOptions.fromJson(options),
          throwsA(isA<SpecException>()),
        );
      }
    },
  );
  test('device views require capabilities and reject data/action bindings', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (json) => (json['requires'] as List).remove('views.deviceInfo.v1'),
      (json) => json.remove('navigation'),
      (json) => json['views'][0]['collectionId'] = 'records',
      (json) => json['views'][0]['query'] = {'limit': 1},
      (json) => json['views'][0]['options'] = {
        'fields': ['deviceId'],
      },
    ]) {
      final json = phoneToolkitTemplate().toJson();
      mutate(json);
      expect(
        () => AppSpec.parse(jsonEncode(json)),
        throwsA(isA<SpecException>()),
      );
    }
  });
  test('semantic device edits preserve identity and existing app records', () {
    final original = notesTemplate();
    final next = original.patch({
      'type': 'AddPage',
      'page': {'title': 'Phone', 'viewIds': []},
      'newViews': [
        {
          'type': 'deviceInfo',
          'label': 'Battery',
          'options': {
            'fields': ['batteryLevel'],
          },
        },
      ],
      'tab': {'label': 'Phone', 'icon': 'today'},
    }, () => 'mobile${sequence++}');
    expect(next.compatibilityErrors(original), isEmpty);
    expect(
      next.collections.map((c) => c.toJson()),
      original.collections.map((c) => c.toJson()),
    );
    expect(next.requires, contains('views.deviceInfo.v1'));
    expect(requestedDeviceCapabilities(next), {'battery'});
  });
}

int sequence = 0;
