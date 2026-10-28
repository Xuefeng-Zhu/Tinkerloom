import type { DeviceCapability } from "../spec/types";
import { unavailable } from "../runtime/errors";
import { ScopedDeviceBridge } from "./device";
import type { ScopedHostStorage } from "./storage";

/** Web reports unsupported native controls; it never substitutes simulated success. */
export function createDeviceBridge(
  storage: ScopedHostStorage,
  requested: readonly DeviceCapability[],
) {
  return new ScopedDeviceBridge(
    storage,
    {
      supported: async () => [],
      read: async () => unavailable("Native device information"),
      apply: async () => unavailable("Native device controls"),
      release: async () => {},
      openSettings: async () => unavailable("Native system settings"),
    },
    requested,
    "unsupported-web-host",
  );
}
