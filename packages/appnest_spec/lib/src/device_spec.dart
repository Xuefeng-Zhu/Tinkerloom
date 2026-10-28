part of '../appnest_spec.dart';

const deviceInfoFields = {
  'batteryLevel': 'Battery level',
  'charging': 'Charging state',
  'model': 'Device model / family',
  'osVersion': 'Operating system',
  'connection': 'Connection type',
  'language': 'Language',
  'region': 'Region',
  'timeZone': 'Time zone',
};
const deviceControlLabels = {
  'flashlight': 'Flashlight',
  'brightness': 'Brightness',
  'keepAwake': 'Keep screen awake',
  'haptics': 'Haptic feedback',
};
const deviceCapabilityLabels = {
  'battery': 'Battery and charging',
  'device': 'Device and operating system',
  'connection': 'Connection type',
  'locale': 'Language, region and time zone',
  ...deviceControlLabels,
};
String deviceFieldCapability(String field) => switch (field) {
  'batteryLevel' || 'charging' => 'battery',
  'model' || 'osVersion' => 'device',
  'connection' => 'connection',
  'language' || 'region' || 'timeZone' => 'locale',
  _ => throw const SpecException('Unsupported device information'),
};

class DeviceInfoOptions {
  final List<String> fields;
  DeviceInfoOptions.fromJson(Map<String, dynamic> json)
    : fields = List.unmodifiable(
        array(
          json['fields'],
          'device information fields',
          deviceInfoFields.length,
        ).map((value) => str(value, 'device information field')),
      ) {
    keys(json, {'fields'}, 'device information options');
    if (fields.isEmpty ||
        fields.any((field) => !deviceInfoFields.containsKey(field))) {
      throw const SpecException('Choose supported device information fields');
    }
    unique(fields, 'device information fields');
  }
}

class DeviceControlOptions {
  final String control;
  DeviceControlOptions.fromJson(Map<String, dynamic> json)
    : control = str(json['control'], 'device control') {
    keys(json, {'control'}, 'device control options');
    if (!deviceControlLabels.containsKey(control))
      throw const SpecException('Choose a supported device control');
  }
}

Set<String> requestedDeviceCapabilities(AppSpec spec) => {
  for (final view in spec.views)
    if (view.type == 'deviceInfo')
      ...DeviceInfoOptions.fromJson(view.options).fields
          .map(deviceFieldCapability)
    else if (view.type == 'deviceControl')
      DeviceControlOptions.fromJson(view.options).control,
};
AppSpec phoneToolkitTemplate() => AppSpec.parse(
  jsonEncode({
    'formatVersion': 1,
    'name': 'Phone Toolkit',
    'theme': 'teal',
    'icon': 'spark',
    'requires': [
      'navigation.v1',
      'views.configured.v1',
      'views.deviceInfo.v1',
      'views.deviceControl.v1',
    ],
    'policyPresetRequest': 'personalTracker.v1',
    'collections': [],
    'actions': [],
    'automationRequests': [],
    'views': [
      {
        'id': 'phoneInfo',
        'type': 'deviceInfo',
        'label': 'My phone',
        'options': {'fields': deviceInfoFields.keys.toList()},
      },
      for (final entry in deviceControlLabels.entries)
        {
          'id': entry.key,
          'type': 'deviceControl',
          'label': entry.value,
          'options': {'control': entry.key},
        },
    ],
    'navigation': {
      'entryPageId': 'phonePage',
      'pages': [
        _richPage('phonePage', 'My phone', ['phoneInfo']),
        _richPage(
          'controlsPage',
          'Phone controls',
          deviceControlLabels.keys.toList(),
        ),
      ],
      'tabs': [
        _richTab('phonePage', 'My phone', 'today'),
        _richTab('controlsPage', 'Controls', 'list'),
      ],
    },
  }),
);
