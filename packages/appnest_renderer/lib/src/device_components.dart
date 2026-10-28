part of '../appnest_renderer.dart';

/// The renderer sees a bounded local interface, never a platform channel.
class DeviceCapabilitiesAdapter extends ChangeNotifier {
  bool get supported => false;
  bool get preview => false;
  bool get busy => false;
  String? get error => null;
  Set<String> get requested => const {};
  Set<String> get granted => const {};
  Map<String, dynamic> get values => const {};
  Map<String, String> get availability => const {};
  void attach() {}
  void detach() {}
  Future<void> refresh() async {}
  Future<void> setGrant(String capability, bool enabled) async {}
  Future<void> command(String control, Object? value) async {}
  Future<void> openSettings() async {}
  Future<void> resetGrants() async {}
}

class PreviewDeviceCapabilitiesAdapter extends DeviceCapabilitiesAdapter {
  @override
  Set<String> requested;
  PreviewDeviceCapabilitiesAdapter(AppSpec spec)
    : requested = requestedDeviceCapabilities(spec);
  void updateSpec(AppSpec spec) {
    requested = requestedDeviceCapabilities(spec);
    notifyListeners();
  }

  @override
  bool get supported => true;
  @override
  bool get preview => true;
  @override
  Set<String> get granted => requested;
  final _values = <String, dynamic>{
    'batteryLevel': 78,
    'charging': 'Charging',
    'model': 'Example phone',
    'osVersion': 'Example OS',
    'connection': 'Wi-Fi',
    'language': 'English',
    'region': 'United States',
    'timeZone': 'America/Los_Angeles',
    'flashlight': false,
    'brightness': 0.5,
    'keepAwake': false,
  };
  @override
  Map<String, dynamic> get values => Map.unmodifiable(_values);
  @override
  Future<void> command(String control, Object? value) async {
    if (!requested.contains(control)) return;
    if (control == 'brightness') _values[control] = value ?? 0.5;
    if (control == 'flashlight' || control == 'keepAwake')
      _values[control] = value;
    notifyListeners();
  }
}

class DeviceAccessPanel extends StatelessWidget {
  final DeviceCapabilitiesAdapter adapter;
  const DeviceAccessPanel({super.key, required this.adapter});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: adapter,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Access applies only to this mini-app, account and phone. Device information stays on this phone.',
        ),
        if (!adapter.supported)
          const Text('Available in the Android or iOS app'),
        for (final capability in adapter.requested)
          SwitchListTile(
            title: Text(deviceCapabilityLabels[capability]!),
            subtitle: adapter.availability[capability] == 'unavailable'
                ? const Text('Unavailable on this device')
                : null,
            value: adapter.granted.contains(capability),
            onChanged: adapter.supported && !adapter.busy && !adapter.preview
                ? (value) => adapter.setGrant(capability, value)
                : null,
          ),
        if (adapter.supported && !adapter.preview)
          TextButton(
            onPressed: adapter.busy ? null : adapter.resetGrants,
            child: const Text('Reset device access'),
          ),
        if (adapter.error != null) Text(adapter.error!),
        if (adapter.supported && !adapter.preview)
          TextButton(
            onPressed: adapter.busy ? null : adapter.openSettings,
            child: const Text('Open AppNest system settings'),
          ),
      ],
    ),
  );
}

class _DeviceComponent extends StatefulWidget {
  final ViewSpec view;
  final DeviceCapabilitiesAdapter adapter;
  const _DeviceComponent({
    super.key,
    required this.view,
    required this.adapter,
  });
  @override
  State<_DeviceComponent> createState() => _DeviceComponentState();
}

class _DeviceComponentState extends State<_DeviceComponent> {
  DeviceCapabilitiesAdapter get adapter => widget.adapter;
  double? _dragValue;
  @override
  void initState() {
    super.initState();
    adapter.attach();
  }

  @override
  void didUpdateWidget(_DeviceComponent old) {
    super.didUpdateWidget(old);
    if (old.adapter != adapter) {
      old.adapter.detach();
      adapter.attach();
    }
  }

  @override
  void dispose() {
    adapter.detach();
    super.dispose();
  }

  Future<void> _access() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Device access'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: DeviceAccessPanel(adapter: adapter),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: adapter,
    builder: (context, _) {
      final view = widget.view;
      final info = view.type == 'deviceInfo';
      final fields = info
          ? DeviceInfoOptions.fromJson(view.options).fields
          : <String>[];
      final control = info
          ? null
          : DeviceControlOptions.fromJson(view.options).control;
      final allowed = control != null && adapter.granted.contains(control);
      final enabled =
          allowed &&
          !adapter.busy &&
          adapter.availability[control] != 'unavailable';
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(view.label, style: Theme.of(context).textTheme.titleLarge),
              if (adapter.preview) const Text('Simulated phone · preview only'),
              if (!adapter.supported)
                const Text('Available in the Android or iOS app')
              else ...[
                if (info) ...[
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '${deviceInfoFields[field]}: ${!adapter.granted.contains(deviceFieldCapability(field))
                            ? 'Access off'
                            : adapter.values[field] == null
                            ? 'Unavailable'
                            : field == 'batteryLevel'
                            ? '${adapter.values[field]}%'
                            : adapter.values[field]}',
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: adapter.busy ? null : adapter.refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ),
                ] else ...[
                  if (!allowed)
                    const Text('Enable access to use this control.'),
                  if (adapter.availability[control] == 'unavailable')
                    const Text('Unavailable on this device'),
                  if (control == 'flashlight' || control == 'keepAwake')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(deviceControlLabels[control]!),
                      value: adapter.values[control] == true,
                      onChanged: enabled
                          ? (value) => adapter.command(control, value)
                          : null,
                    ),
                  if (control == 'brightness') ...[
                    Slider(
                      value:
                          _dragValue ??
                          (adapter.values['brightness'] as num? ?? .5)
                              .toDouble()
                              .clamp(0, 1),
                      label:
                          '${((_dragValue ?? (adapter.values['brightness'] as num? ?? .5)) * 100).round()}%',
                      onChanged: enabled
                          ? (value) => setState(() => _dragValue = value)
                          : null,
                      onChangeEnd: enabled
                          ? (value) async {
                              await adapter.command('brightness', value);
                              if (mounted) setState(() => _dragValue = null);
                            }
                          : null,
                    ),
                    TextButton(
                      onPressed: enabled
                          ? () => adapter.command('brightness', null)
                          : null,
                      child: const Text('Restore brightness'),
                    ),
                  ],
                  if (control == 'haptics')
                    FilledButton(
                      onPressed: enabled
                          ? () => adapter.command('haptics', null)
                          : null,
                      child: const Text('Feel haptic feedback'),
                    ),
                ],
                if (!adapter.preview)
                  TextButton(
                    onPressed: _access,
                    child: const Text('Device access'),
                  ),
                if (adapter.error != null) Text(adapter.error!),
              ],
            ],
          ),
        ),
      );
    },
  );
}
