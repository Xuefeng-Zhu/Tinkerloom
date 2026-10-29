import { BackendError } from "../backend/errors";
import type { HostLifetime } from "../host/scope";
import { ensure, RuntimeError, runtimeError } from "./errors";
import type { RuntimeAdapter, RuntimeTransport } from "./types";
import { createWatchActivity } from "./watchActivity";
import {
  decodeInvalidation,
  invalidationIdentity,
  type InvalidationCapability,
  type InvalidationStamp,
  type WatchActivity,
  type WatchClock,
} from "./invalidationTypes";
export interface InvalidationOptions {
  capability: InvalidationCapability | null;
  minimumIntervalMs?: number;
  onManifestChange: (stamp: InvalidationStamp) => void | Promise<void>;
  onAccessFailure: (error: RuntimeError) => void;
  onPollError?: (error: RuntimeError) => void;
  clock?: WatchClock;
  activity?: WatchActivity;
}
const clock: WatchClock = {
  setTimeout: (callback, milliseconds) => setTimeout(callback, milliseconds),
  clearTimeout: (handle) =>
    clearTimeout(handle as ReturnType<typeof setTimeout>),
};
/** No subscription, timer or HTTP transport enters isolated previews. */
export function withInvalidation(
  base: RuntimeAdapter,
  transport: RuntimeTransport,
  lifetime: HostLifetime,
  options: InvalidationOptions,
): RuntimeAdapter {
  ensure(
    !base.preview,
    "preview_isolated",
    "An isolated preview cannot receive an authenticated invalidation transport.",
  );
  lifetime.assertActive();
  ensure(
    base.appId === lifetime.scope.appId,
    "invalid_scope",
    "Invalidation scope belongs to a different app.",
  );
  const capability = options.capability;
  if (capability)
    ensure(
      capability.mode === "poll.v1" &&
        Number.isSafeInteger(capability.minimumIntervalMs) &&
        capability.minimumIntervalMs >= 15000 &&
        capability.minimumIntervalMs <= 120000,
      "unsupported_capability",
      "Invalidation polling requires a supported confirmed server capability.",
    );
  const interval =
    options.minimumIntervalMs ?? capability?.minimumIntervalMs ?? 15000;
  ensure(
    Number.isSafeInteger(interval) &&
      interval >= 15000 &&
      interval <= 120000 &&
      (!capability || interval >= capability.minimumIntervalMs),
    "invalid_interval",
    "Invalidation polling must respect the server minimum within 15–120 seconds.",
  );
  const scheduler = options.clock ?? clock,
    activity = options.activity ?? createWatchActivity(),
    ownedActivity = !options.activity;
  const appId = base.appId,
    listeners = new Set<() => void>();
  let enabled = false,
    closed = false,
    terminal = false,
    timer: unknown = null,
    inflight = false,
    epoch = 0,
    failures = 0,
    baseline = true,
    queued = false,
    last: string | null = null;
  let stopActivity = () => {},
    stopLifetime = () => {},
    stopBase = () => {};
  const current = () => !closed && !terminal && lifetime.active;
  const foreground = () => {
    const state = activity.getSnapshot();
    return state.foreground && state.online;
  };
  const permitted = () =>
    current() && enabled && !!capability && listeners.size > 0 && foreground();
  const clearTimer = () => {
    if (timer !== null) {
      scheduler.clearTimeout(timer);
      timer = null;
    }
  };
  const report = (
    callback: ((error: RuntimeError) => void) | undefined,
    error: RuntimeError,
  ) => {
    try {
      callback?.(error);
    } catch {
      /* A host callback cannot create a retry loop. */
    }
  };
  const deny = (error: RuntimeError) => {
    terminal = true;
    clearTimer();
    epoch++;
    queued = false;
    report(options.onAccessFailure, error);
  };
  const schedule = (delay: number) => {
    clearTimer();
    if (!permitted()) return;
    timer = scheduler.setTimeout(() => {
      timer = null;
      void poll();
    }, delay);
  };
  const restart = () => {
    epoch++;
    baseline = true;
    queued = true;
    clearTimer();
    if (permitted() && !inflight) schedule(0);
  };
  const suspend = () => {
    epoch++;
    baseline = true;
    queued = false;
    clearTimer();
  };
  const poll = async () => {
    if (!permitted() || inflight) return;
    const started = epoch;
    inflight = true;
    queued = false;
    let delay = interval;
    try {
      const response = await transport(
        { op: "spec.watch", appId },
        { isCurrent: () => current() && started === epoch && permitted() },
      );
      if (!current() || started !== epoch || !permitted()) return;
      let stamp: InvalidationStamp;
      try {
        stamp = decodeInvalidation(response, appId);
      } catch {
        deny(
          new RuntimeError(
            "forbidden",
            "Current app identity and access could not be confirmed from its invalidation response.",
          ),
        );
        return;
      }
      const identity = invalidationIdentity(stamp),
        changed = baseline || last !== identity;
      last = identity;
      baseline = false;
      failures = 0;
      if (changed) {
        // Authority metadata reaches the host even while a business form is dirty.
        try {
          const followup = options.onManifestChange(stamp);
          if (followup)
            void followup.catch((error) => {
              if (current()) report(options.onPollError, runtimeError(error));
            });
        } catch (error) {
          report(options.onPollError, runtimeError(error));
        }
        if (!current() || started !== epoch) return;
        for (const listener of [...listeners]) {
          if (!current() || started !== epoch) break;
          try {
            listener();
          } catch (error) {
            report(options.onPollError, runtimeError(error));
          }
        }
      }
    } catch (error) {
      if (!current() || started !== epoch || !permitted()) return;
      const failure = runtimeError(error);
      if (failure.code === "session_changed") {
        dispose();
        return;
      }
      if (
        failure.code === "unauthenticated" ||
        (error instanceof BackendError &&
          [401, 403, 404].includes(error.status ?? 0)) ||
        ["forbidden", "not_found", "authorization_failure"].includes(
          failure.code,
        )
      ) {
        deny(
          new RuntimeError(
            failure.code === "unauthenticated"
              ? "unauthenticated"
              : "forbidden",
            failure.code === "unauthenticated"
              ? "Please sign in again."
              : "Current app access is no longer available.",
          ),
        );
        return;
      }
      failures++;
      baseline = true;
      delay = Math.min(120000, interval * 2 ** Math.min(failures, 4));
      report(options.onPollError, failure);
    } finally {
      inflight = false;
      if (permitted()) schedule(queued || started !== epoch ? 0 : delay);
    }
  };
  const dispose = () => {
    if (closed) return;
    closed = true;
    epoch++;
    clearTimer();
    queued = false;
    stopActivity();
    stopLifetime();
    stopBase();
    listeners.clear();
    if (ownedActivity) activity.dispose?.();
    base.setActive?.(false);
    base.dispose();
  };
  let observedActivity = activity.getSnapshot();
  if (capability)
    stopActivity = activity.subscribe(() => {
      const next = activity.getSnapshot();
      if (
        next.foreground === observedActivity.foreground &&
        next.online === observedActivity.online
      )
        return;
      observedActivity = next;
      if (permitted()) restart();
      else suspend();
    });
  stopLifetime = lifetime.onDispose(dispose);
  const guarded = async <T>(run: () => Promise<T>) => {
    lifetime.assertActive();
    ensure(
      current(),
      "disposed",
      "This account's invalidation runtime is closed.",
    );
    const result = await run();
    lifetime.assertActive();
    ensure(
      current(),
      "disposed",
      "This account's invalidation runtime is closed.",
    );
    return result;
  };
  return {
    get appId() {
      return base.appId;
    },
    get versionId() {
      return base.versionId;
    },
    get spec() {
      return base.spec;
    },
    get preview() {
      return base.preview;
    },
    get role() {
      return base.role;
    },
    get archived() {
      return base.archived;
    },
    get approvedRuleIds() {
      return base.approvedRuleIds;
    },
    get features() {
      const features = new Set(base.features);
      features.delete("watch");
      if (capability && current()) features.add("watch");
      return features;
    },
    query: (...args) => guarded(() => base.query(...args)),
    get: (...args) => guarded(() => base.get(...args)),
    summary: (...args) => guarded(() => base.summary(...args)),
    aggregate: (...args) => guarded(() => base.aggregate(...args)),
    execute: (...args) => guarded(() => base.execute(...args)),
    permits: (...args) => current() && base.permits(...args),
    members: (...args) => guarded(() => base.members(...args)),
    reminderState: (...args) => guarded(() => base.reminderState(...args)),
    readImage: (...args) => guarded(() => base.readImage(...args)),
    pickImage: () => guarded(() => base.pickImage()),
    uploadImage: (...args) => guarded(() => base.uploadImage(...args)),
    setActive(active) {
      if (active) {
        lifetime.assertActive();
        ensure(current(), "disposed", "This invalidation runtime is closed.");
      }
      base.setActive?.(active);
      if (enabled === active) return;
      enabled = active;
      if (active) restart();
      else suspend();
    },
    watch(listener) {
      if (!capability || !current()) return () => {};
      const first = listeners.size === 0;
      listeners.add(listener);
      if (first) {
        if (base.features.has("watch"))
          stopBase = base.watch(() => {
            if (permitted()) for (const next of [...listeners]) next();
          });
        restart();
      }
      let removed = false;
      return () => {
        if (removed) return;
        removed = true;
        listeners.delete(listener);
        if (!listeners.size) {
          suspend();
          stopBase();
          stopBase = () => {};
        }
      };
    },
    dispose,
  };
}
