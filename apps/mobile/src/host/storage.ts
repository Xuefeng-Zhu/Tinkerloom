import { decodeRetainedCommand } from "../runtime/commands";
import type { RuntimeCommandStore } from "../runtime/commands";
import { decodeTimer } from "../runtime/timer";
import type { TimerState, UtilityTimerStore } from "../runtime/timer";
import type { RuntimeCommand } from "../runtime/types";
import { ensure } from "../runtime/errors";
import { runtimeJsonSnapshot, RUNTIME_REQUEST_BYTES } from "../runtime/json";
import type { HostLifetime } from "./scope";

/** Updates are atomic per entry. The callback is pure and may run again on CAS conflict. */
export interface AtomicHostStorage {
  read(key: string): Promise<string | null>;
  change(
    key: string,
    update: (previous: string | null) => string | null,
  ): Promise<void>;
}
export const HOST_ENTRY_BYTES = RUNTIME_REQUEST_BYTES + 8192;
export const byteLength = (text: string) =>
  new TextEncoder().encode(text).byteLength;
export function checkEntry(text: string) {
  ensure(
    byteLength(text) <= HOST_ENTRY_BYTES,
    "storage_too_large",
    "Local recovery exceeds the supported storage bound.",
  );
}
const stable = (value: unknown): string =>
  JSON.stringify(value, (_, item) =>
    item && typeof item === "object" && !Array.isArray(item)
      ? Object.fromEntries(
          Object.keys(item)
            .sort()
            .map((key) => [key, item[key]]),
        )
      : item,
  );

/** No network, command execution or timer replay occurs when these stores open. */
export class ScopedHostStorage {
  constructor(
    readonly lifetime: HostLifetime,
    private readonly port: AtomicHostStorage,
  ) {}
  private decode(text: string | null, kind: string): unknown | null {
    if (text === null) return null;
    checkEntry(text);
    let value: unknown;
    try {
      value = JSON.parse(text);
    } catch {
      throw new Error(
        "Saved local app state is unreadable. It has not been replaced.",
      );
    }
    const row = value as {
      version?: unknown;
      scope?: unknown;
      kind?: unknown;
      payload?: unknown;
    };
    ensure(
      row &&
        typeof row === "object" &&
        !Array.isArray(row) &&
        Object.keys(row).length === 4 &&
        row.version === 1 &&
        row.scope === this.lifetime.key &&
        row.kind === kind &&
        Object.hasOwn(row, "payload"),
      "invalid_saved_scope",
      "Saved local state belongs to a different app scope or is invalid.",
    );
    return runtimeJsonSnapshot(row.payload);
  }
  async read(kind: string): Promise<unknown | null> {
    this.lifetime.assertActive();
    const text = await this.port.read(kind);
    this.lifetime.assertActive();
    return this.decode(text, kind);
  }
  async change(
    kind: string,
    update: (previous: unknown | null) => unknown | null,
  ) {
    this.lifetime.assertActive();
    await this.port.change(kind, (text) => {
      this.lifetime.assertActive();
      const payload = update(this.decode(text, kind));
      if (payload === null) return null;
      const encoded = JSON.stringify({
        version: 1,
        scope: this.lifetime.key,
        kind,
        payload: runtimeJsonSnapshot(payload),
      });
      checkEntry(encoded);
      return encoded;
    });
    this.lifetime.assertActive();
  }
  /** Generic JSON entry for retained builder/publication/generation commands. */
  write(kind: string, value: unknown) {
    const snapshot = runtimeJsonSnapshot(value);
    return this.change(kind, () => snapshot);
  }
  async compareAndSwap(
    kind: string,
    expected: unknown | null,
    next: unknown | null,
  ): Promise<boolean> {
    const before = runtimeJsonSnapshot(expected),
      after = runtimeJsonSnapshot(next);
    let changed = false;
    await this.change(kind, (current) => {
      changed = stable(current) === stable(before);
      return changed ? after : current;
    });
    return changed;
  }
}

export class DurableRuntimeCommandStore implements RuntimeCommandStore {
  readonly durability = "durable" as const;
  constructor(private readonly storage: ScopedHostStorage) {}
  async read() {
    const value = await this.storage.read("command");
    return value === null
      ? null
      : decodeRetainedCommand(value, this.storage.lifetime.scope.appId);
  }
  async save(input: RuntimeCommand) {
    const command = decodeRetainedCommand(
      input,
      this.storage.lifetime.scope.appId,
    );
    await this.storage.change("command", (value) => {
      if (value !== null) {
        const previous = decodeRetainedCommand(
          value,
          this.storage.lifetime.scope.appId,
        );
        ensure(
          previous.operationId === command.operationId,
          "pending_command",
          "Resolve the previous saved operation first.",
        );
        ensure(
          stable(previous) === stable(command),
          "operation_conflict",
          "A saved operation cannot change its original input.",
        );
      }
      return command;
    });
  }
  async clear(operationId: string) {
    await this.storage.change("command", (value) => {
      ensure(
        value === null ||
          decodeRetainedCommand(value, this.storage.lifetime.scope.appId)
            .operationId === operationId,
        "operation_conflict",
        "The saved operation changed. It has not been removed.",
      );
      return null;
    });
  }
}

function timerKey(viewId: string) {
  ensure(
    /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/.test(viewId),
    "invalid_timer",
    "A valid timer view is required.",
  );
  return `timer:${viewId}`;
}
function timer(value: unknown) {
  const snapshot = runtimeJsonSnapshot(value);
  ensure(
    snapshot &&
      typeof snapshot === "object" &&
      Object.keys(snapshot).every((key) =>
        [
          "version",
          "phase",
          "durationSeconds",
          "remainingMilliseconds",
          "deadline",
        ].includes(key),
      ),
    "invalid_timer",
    "Saved timer data is invalid.",
  );
  return decodeTimer(snapshot);
}
export class DurableUtilityTimerStore implements UtilityTimerStore {
  readonly durability = "durable" as const;
  constructor(private readonly storage: ScopedHostStorage) {}
  async read(viewId: string) {
    const value = await this.storage.read(timerKey(viewId));
    return value === null ? null : timer(value);
  }
  async write(viewId: string, state: TimerState) {
    const checked = timer(state);
    await this.storage.change(timerKey(viewId), () => checked);
  }
}

export function hostStores(lifetime: HostLifetime, port: AtomicHostStorage) {
  const storage = new ScopedHostStorage(lifetime, port);
  return {
    lifetime,
    storage,
    commands: new DurableRuntimeCommandStore(storage),
    timers: new DurableUtilityTimerStore(storage),
  };
}
