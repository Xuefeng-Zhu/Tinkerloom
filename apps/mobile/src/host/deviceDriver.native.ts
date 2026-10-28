import { AppState, Linking } from "react-native";
import * as Battery from "expo-battery";
import * as Device from "expo-device";
import * as Network from "expo-network";
import * as Localization from "expo-localization";
import * as Haptics from "expo-haptics";
import { Camera } from "expo-camera";
import NativeControls from "../../modules/tinkerloom-device";
import type { DeviceCapability, DeviceInfoField } from "../spec/types";
import type { DeviceState } from "../runtime/types";
import { ensure } from "../runtime/errors";
import type { DeviceDriver } from "./device";
import { requireTorchPermission } from "./torchPermission";

/** Reads a fixed, coarse allowlist. No name, serial, OS ID, IP, SSID or location. */
export function nativeDeviceDriver(): DeviceDriver {
  return {
    foreground: AppState.currentState === "active",
    observeForeground(listener) {
      const subscription = AppState.addEventListener("change", (state) =>
        listener(state === "active"),
      );
      return () => subscription.remove();
    },
    async supported() {
      const result: DeviceCapability[] = ["device", "connection", "locale"];
      if (await Battery.isAvailableAsync()) result.push("battery");
      if (NativeControls) {
        const controls = await NativeControls.availability();
        for (const control of [
          "flashlight",
          "brightness",
          "keepAwake",
          "haptics",
        ] as const)
          if (controls[control] === true) result.push(control);
      }
      return result;
    },
    async read(fields: readonly DeviceInfoField[], current: () => boolean) {
      const check = () =>
        ensure(
          current(),
          "inactive",
          "Device access changed before this request completed.",
        );
      check();
      const result: DeviceState = {};
      if (fields.includes("batteryLevel")) {
        const level = await Battery.getBatteryLevelAsync();
        check();
        result.batteryLevel = level < 0 ? null : level;
      }
      if (fields.includes("charging")) {
        check();
        const state = await Battery.getBatteryStateAsync();
        check();
        result.charging =
          state === Battery.BatteryState.CHARGING
            ? "Charging"
            : state === Battery.BatteryState.FULL
              ? "Full"
              : state === Battery.BatteryState.UNPLUGGED
                ? "Not charging"
                : null;
      }
      if (fields.includes("model")) result.model = Device.modelName ?? null;
      if (fields.includes("osVersion"))
        result.osVersion =
          [Device.osName, Device.osVersion].filter(Boolean).join(" ") || null;
      if (fields.includes("connection")) {
        check();
        const state = await Network.getNetworkStateAsync();
        check();
        result.connection =
          state.isConnected === false ? "None" : (state.type ?? "Unknown");
      }
      if (
        fields.some((field) =>
          ["language", "region", "timeZone"].includes(field),
        )
      ) {
        const locale = Localization.getLocales()[0];
        if (fields.includes("language"))
          result.language = locale?.languageTag ?? null;
        if (fields.includes("region"))
          result.region = locale?.regionCode ?? null;
        if (fields.includes("timeZone"))
          result.timeZone = Localization.getCalendars()[0]?.timeZone ?? null;
      }
      return result;
    },
    async apply(control, value, lease, current) {
      const check = () =>
        ensure(
          current(),
          "inactive",
          "Return to the app and try the control again.",
        );
      check();
      ensure(
        NativeControls,
        "unavailable",
        "Native device controls are unavailable in this build.",
      );
      if (control === "flashlight") {
        if (value === true) {
          await requireTorchPermission(
            {
              get: Camera.getCameraPermissionsAsync,
              request: Camera.requestCameraPermissionsAsync,
            },
            check,
          );
        }
        check();
        await NativeControls.setTorch(value === true, lease);
      } else if (control === "brightness")
        await NativeControls.setBrightness(
          typeof value === "number" ? value : null,
          lease,
        );
      else if (control === "keepAwake")
        await NativeControls.setKeepAwake(value === true, lease);
      else await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    },
    async release(control, lease) {
      if (NativeControls) await NativeControls.release(control, lease);
    },
    async openSettings() {
      await Linking.openSettings();
    },
  };
}
