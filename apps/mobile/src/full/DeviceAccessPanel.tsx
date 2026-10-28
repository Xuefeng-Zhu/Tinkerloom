import { useState, useSyncExternalStore } from "react";
import { Text, View } from "react-native";
import type { ScopedDeviceBridge } from "../host/device";
import { Button } from "../components/Button";
import { Notice } from "../components/Notice";
import { Card, Toggle, styles } from "./ui";
export function DeviceAccessPanel({ device }: { device: ScopedDeviceBridge }) {
  const [actionError, setActionError] = useState<string | null>(null);
  const state = useSyncExternalStore(
    device.subscribe,
    device.getSnapshot,
    device.getSnapshot,
  );
  return (
    <Card title="Device access">
      <Text style={styles.body}>
        Device features stay off until you allow them for this account and app.
        Reading device information stays on this device. Publishing does not
        grant consent.
      </Text>
      {(state.error || actionError) && (
        <Notice text={state.error ?? actionError!} error />
      )}
      {!state.initialized && (
        <Text style={styles.muted}>Checking available features…</Text>
      )}
      {state.requested.length === 0 ? (
        <Text style={styles.muted}>
          This app does not request device features.
        </Text>
      ) : (
        state.requested.map((capability) => (
          <View key={capability} style={{ gap: 4 }}>
            <Toggle
              label={`Allow ${capability}`}
              value={state.granted.includes(capability)}
              disabled={
                state.busy ||
                !state.initialized ||
                !state.supported.includes(capability)
              }
              onChange={(enabled) => {
                void device.setGrant(capability, enabled).catch(() => {});
              }}
            />
            {!state.supported.includes(capability) && (
              <Text style={styles.muted}>Unavailable on this host.</Text>
            )}
          </View>
        ))
      )}
      <Text style={styles.muted}>
        Allowing flashlight access may request the operating system’s camera
        permission when you tap the flashlight control. No camera capture is
        provided. Controls release when you leave or the app enters the
        background.
      </Text>
      <View style={styles.row}>
        <Button
          label="Reset device permissions"
          variant="secondary"
          disabled={state.busy}
          onPress={() => {
            void device.resetGrants().catch(() => {});
          }}
        />
        <Button
          label="Open system settings"
          disabled={state.supported.length === 0}
          variant="quiet"
          onPress={() => {
            setActionError(null);
            void device
              .openSettings()
              .catch(() =>
                setActionError(
                  "System settings could not be opened on this host.",
                ),
              );
          }}
        />
      </View>
    </Card>
  );
}
