import { randomUUID } from "expo-crypto";
import type { DeviceCapability } from "../spec/types";
import { ScopedDeviceBridge } from "./device";
import { nativeDeviceDriver } from "./deviceDriver.native";
import type { ScopedHostStorage } from "./storage";

export function createDeviceBridge(
  storage: ScopedHostStorage,
  requested: readonly DeviceCapability[],
) {
  return new ScopedDeviceBridge(
    storage,
    nativeDeviceDriver(),
    requested,
    randomUUID(),
  );
}
