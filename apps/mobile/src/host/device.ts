import { deviceFieldCapability } from "../spec/bindings";
import type {
  DeviceCapability,
  DeviceControl,
  DeviceInfoField,
} from "../spec/types";
import type { DeviceBridge, DeviceState } from "../runtime/types";
import { ensure, RuntimeError } from "../runtime/errors";
import type { ScopedHostStorage } from "./storage";

export const deviceCapabilities: readonly DeviceCapability[] = [
  "battery",
  "device",
  "connection",
  "locale",
  "flashlight",
  "brightness",
  "keepAwake",
  "haptics",
];
const controls: readonly DeviceControl[] = [
  "flashlight",
  "brightness",
  "keepAwake",
  "haptics",
];
const information: readonly DeviceInfoField[] = [
  "batteryLevel",
  "charging",
  "model",
  "osVersion",
  "connection",
  "language",
  "region",
  "timeZone",
];
export interface DeviceDriver {
  supported(): Promise<readonly DeviceCapability[]>;
  read(
    fields: readonly DeviceInfoField[],
    current: () => boolean,
  ): Promise<DeviceState>;
  apply(
    control: DeviceControl,
    value: boolean | number | undefined,
    lease: string,
    current: () => boolean,
  ): Promise<void>;
  release(control: DeviceControl, lease: string): Promise<void>;
  openSettings(): Promise<void>;
  foreground?: boolean;
  observeForeground?(listener: (active: boolean) => void): () => void;
}
export interface DeviceAccessState {
  requested: readonly DeviceCapability[];
  supported: readonly DeviceCapability[];
  granted: readonly DeviceCapability[];
  initialized: boolean;
  active: boolean;
  busy: boolean;
  error: string | null;
}

/** Consent belongs to this account/app; no device values are persisted or sent. */
export class ScopedDeviceBridge implements DeviceBridge {
  private state: DeviceAccessState;
  private listeners = new Set<() => void>();
  private disposed = false;
  private foreground: boolean;
  private epoch = 0;
  private consentEpoch = 0;
  private tail: Promise<unknown> = Promise.resolve();
  private stopForeground: () => void;
  private stopScope: () => void;
  constructor(
    private readonly storage: ScopedHostStorage,
    private readonly driver: DeviceDriver,
    requested: readonly DeviceCapability[],
    private readonly lease: string,
  ) {
    ensure(
      requested.every((value) => deviceCapabilities.includes(value)),
      "invalid_device_capability",
      "Unsupported device capability.",
    );
    this.state = {
      requested: [...new Set(requested)],
      supported: [],
      granted: [],
      initialized: false,
      active: false,
      busy: false,
      error: null,
    };
    this.foreground = driver.foreground ?? true;
    this.stopForeground =
      driver.observeForeground?.((active) => this.setForeground(active)) ??
      (() => {});
    this.stopScope = storage.lifetime.onDispose(() => this.dispose());
  }
  getSnapshot = () => this.state;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  private set(patch: Partial<DeviceAccessState>) {
    if (this.disposed || !this.storage.lifetime.active) return;
    this.state = { ...this.state, ...patch };
    for (const listener of this.listeners) listener();
  }
  get available(): readonly DeviceCapability[] {
    return this.usable
      ? this.state.granted.filter((capability) =>
          this.state.supported.includes(capability),
        )
      : [];
  }
  private get usable() {
    return (
      !this.disposed &&
      this.storage.lifetime.active &&
      this.state.initialized &&
      this.state.active &&
      this.foreground
    );
  }
  private enqueue<T>(task: () => Promise<T>): Promise<T> {
    const next = this.tail.catch(() => {}).then(task);
    this.tail = next;
    return next;
  }
  async initialize() {
    this.storage.lifetime.assertActive();
    ensure(!this.disposed, "disposed", "Device access is closed.");
    const epoch = ++this.consentEpoch;
    this.set({ busy: true, error: null });
    try {
      const [stored, supported] = await Promise.all([
        this.storage.read("device-consent"),
        this.driver.supported(),
      ]);
      this.storage.lifetime.assertActive();
      if (this.disposed || epoch !== this.consentEpoch) return;
      this.set({
        supported: supported.filter((capability) =>
          deviceCapabilities.includes(capability),
        ),
      });
      ensure(
        stored === null ||
          (Array.isArray(stored) &&
            stored.length <= deviceCapabilities.length &&
            stored.every((capability) =>
              deviceCapabilities.includes(capability),
            )),
        "invalid_device_consent",
        "Saved device access is unreadable. Reset it explicitly to replace it.",
      );
      this.set({
        initialized: true,
        supported: supported.filter((capability) =>
          deviceCapabilities.includes(capability),
        ),
        granted: ((stored ?? []) as DeviceCapability[]).filter((capability) =>
          this.state.requested.includes(capability),
        ),
        busy: false,
      });
    } catch (error) {
      this.set({
        busy: false,
        error: "Device access could not be loaded. No access has been enabled.",
      });
      throw error;
    }
  }
  async setGrant(capability: DeviceCapability, enabled: boolean) {
    this.storage.lifetime.assertActive();
    ensure(
      !this.disposed &&
        !this.state.busy &&
        this.state.initialized &&
        this.state.requested.includes(capability) &&
        (!enabled || this.state.supported.includes(capability)),
      "unavailable",
      "This device capability is unavailable or another access change is pending.",
    );
    ++this.epoch;
    const epoch = ++this.consentEpoch;
    const next = new Set(this.state.granted);
    if (enabled) next.add(capability);
    else next.delete(capability);
    if (!enabled) this.set({ granted: [...next] });
    this.set({ busy: true, error: null });
    try {
      if (!enabled && controls.includes(capability as DeviceControl))
        await this.release(capability as DeviceControl);
      await this.storage.change("device-consent", () => [...next].sort());
      this.storage.lifetime.assertActive();
      if (this.disposed || epoch !== this.consentEpoch) return;
      this.set({ granted: [...next], busy: false });
    } catch (error) {
      this.set({
        busy: false,
        error:
          "Device access could not be saved. Removed access stays off in this session.",
      });
      throw error;
    }
  }
  async resetGrants() {
    this.storage.lifetime.assertActive();
    ensure(
      !this.disposed && !this.state.busy,
      "unavailable",
      "Another device access change is pending.",
    );
    ++this.epoch;
    ++this.consentEpoch;
    this.set({ granted: [], busy: true, error: null });
    try {
      await this.releaseAll();
      await this.storage.change("device-consent", () => []);
      this.set({ initialized: true, busy: false });
    } catch (error) {
      this.set({
        busy: false,
        error: "Device access is off. Its saved preference could not be reset.",
      });
      throw error;
    }
  }
  setActive(active: boolean) {
    if (this.disposed) return;
    ++this.epoch;
    this.set({ active });
    if (!active)
      void this.releaseAll().catch(() =>
        this.set({ error: "Some device controls could not be released." }),
      );
  }
  setForeground(active: boolean) {
    if (this.disposed) return;
    this.foreground = active;
    ++this.epoch;
    this.set({});
    if (!active)
      void this.releaseAll().catch(() =>
        this.set({ error: "Some device controls could not be released." }),
      );
  }
  async read(fields: readonly DeviceInfoField[]): Promise<DeviceState> {
    ensure(
      this.usable &&
        fields.length > 0 &&
        fields.length <= information.length &&
        new Set(fields).size === fields.length &&
        fields.every((field) => information.includes(field)) &&
        fields.every((field) =>
          this.available.includes(deviceFieldCapability(field)),
        ),
      "device_access_off",
      "Enable this app's device access before reading device information.",
    );
    const epoch = this.epoch,
      value = await this.driver.read(
        fields,
        () => this.usable && epoch === this.epoch,
      );
    this.storage.lifetime.assertActive();
    ensure(
      this.usable && epoch === this.epoch,
      "inactive",
      "Device access changed before this read completed.",
    );
    const result: DeviceState = {};
    for (const field of fields) {
      const item = value[field];
      ensure(
        item === null ||
          item === undefined ||
          typeof item === "boolean" ||
          (typeof item === "string" && item.length <= 160) ||
          (typeof item === "number" &&
            Number.isFinite(item) &&
            (field !== "batteryLevel" || (item >= 0 && item <= 1))),
        "invalid_device_response",
        "This device response could not be confirmed.",
      );
      result[field] = item ?? null;
    }
    return result;
  }
  async control(control: DeviceControl, value?: boolean | number) {
    ensure(
      controls.includes(control) &&
        !this.state.busy &&
        this.usable &&
        this.available.includes(control),
      "device_access_off",
      "Enable this app's access before using this control.",
    );
    ensure(
      control === "haptics"
        ? value === undefined
        : control === "brightness"
          ? value === undefined ||
            (typeof value === "number" &&
              Number.isFinite(value) &&
              value >= 0 &&
              value <= 1)
          : typeof value === "boolean",
      "invalid_device_control",
      "This device control value is invalid.",
    );
    const epoch = this.epoch;
    await this.enqueue(async () => {
      ensure(
        this.usable && epoch === this.epoch && this.available.includes(control),
        "inactive",
        "Return to the app and try the control again.",
      );
      try {
        await this.driver.apply(
          control,
          value,
          this.lease,
          () =>
            this.usable &&
            epoch === this.epoch &&
            this.available.includes(control),
        );
      } finally {
        if (!this.usable || epoch !== this.epoch)
          await this.driver.release(control, this.lease);
      }
      ensure(
        this.usable && epoch === this.epoch,
        "inactive",
        "The device request was interrupted. Try it again explicitly.",
      );
    });
  }
  release(control: DeviceControl): Promise<void> {
    ensure(
      controls.includes(control),
      "invalid_device_control",
      "Unsupported device control.",
    );
    // A view exit must also cancel work awaiting an OS permission/read, before
    // its queued cleanup runs. It must never resume that effect off-screen.
    ++this.epoch;
    return this.enqueue(() => this.driver.release(control, this.lease));
  }
  private releaseAll() {
    return this.enqueue(async () => {
      const results = await Promise.allSettled(
        controls.map((control) => this.driver.release(control, this.lease)),
      );
      if (results.some((result) => result.status === "rejected"))
        throw new RuntimeError(
          "release_failed",
          "Device controls could not all be released.",
        );
    });
  }
  async openSettings() {
    this.storage.lifetime.assertActive();
    ensure(!this.disposed, "disposed", "Device access is closed.");
    await this.driver.openSettings();
  }
  dispose() {
    if (this.disposed) return;
    ++this.epoch;
    this.stopForeground();
    this.stopScope();
    this.state = { ...this.state, granted: [], active: false, busy: false };
    this.disposed = true;
    this.listeners.clear();
    void this.releaseAll().catch(() => {});
  }
}
