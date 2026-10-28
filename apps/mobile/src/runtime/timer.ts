import { ensure } from "./errors";
import { normalizeTimestamp } from "../spec/values";

export interface TimerState {
  version: 1;
  phase: "ready" | "running" | "paused" | "complete";
  durationSeconds: number;
  remainingMilliseconds: number;
  deadline?: string;
}
/** Host must scope a durable store by backend + account + app. Preview gets memory only. */
export interface UtilityTimerStore {
  readonly durability: "memory" | "durable";
  read(viewId: string): Promise<unknown | null>;
  write(viewId: string, state: TimerState): Promise<void>;
}
export class MemoryUtilityTimerStore implements UtilityTimerStore {
  readonly durability = "memory";
  private values = new Map<string, TimerState>();
  async read(id: string) {
    return this.values.has(id) ? { ...this.values.get(id)! } : null;
  }
  async write(id: string, state: TimerState) {
    this.values.set(id, { ...state });
  }
}
export function readyTimer(minutes = 25): TimerState {
  ensure(
    Number.isInteger(minutes) && minutes >= 1 && minutes <= 180,
    "invalid_timer",
    "Timer duration must be one to 180 minutes.",
  );
  return {
    version: 1,
    phase: "ready",
    durationSeconds: minutes * 60,
    remainingMilliseconds: minutes * 60000,
  };
}
export function decodeTimer(input: unknown): TimerState {
  ensure(
    input !== null && typeof input === "object" && !Array.isArray(input),
    "invalid_timer",
    "The saved timer is invalid.",
  );
  const state = input as TimerState;
  ensure(
    state.version === 1 &&
      ["ready", "running", "paused", "complete"].includes(state.phase) &&
      Number.isInteger(state.durationSeconds) &&
      state.durationSeconds >= 60 &&
      state.durationSeconds <= 10800 &&
      Number.isInteger(state.remainingMilliseconds) &&
      state.remainingMilliseconds >= 0 &&
      state.remainingMilliseconds <= state.durationSeconds * 1000 &&
      (state.phase === "complete" ? state.remainingMilliseconds === 0 : true) &&
      (state.phase === "running"
        ? typeof state.deadline === "string" && state.deadline.endsWith("Z")
        : state.deadline === undefined),
    "invalid_timer",
    "The saved timer is invalid. Reset it explicitly to replace it.",
  );
  if (state.deadline) normalizeTimestamp(state.deadline);
  return { ...state };
}
export const remainingAt = (state: TimerState, now: Date) =>
  Math.max(
    0,
    Math.min(
      state.durationSeconds * 1000,
      state.phase === "running"
        ? Date.parse(state.deadline!) - now.getTime()
        : state.remainingMilliseconds,
    ),
  );
export const phaseAt = (state: TimerState, now: Date) =>
  state.phase === "running" && remainingAt(state, now) === 0
    ? "complete"
    : state.phase;
export class UtilityTimerController {
  private states = new Map<string, TimerState>();
  private loads = new Map<string, Promise<TimerState>>();
  private pending = new Map<string, Promise<void>>();
  private listeners = new Set<() => void>();
  private disposed = false;
  constructor(
    readonly store: UtilityTimerStore,
    private now: () => Date = () => new Date(),
  ) {}
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  stateFor = (viewId: string) => this.states.get(viewId);
  async load(viewId: string, minutes = 25): Promise<TimerState> {
    ensure(!this.disposed, "disposed", "The timer controller is closed.");
    const prior = this.states.get(viewId);
    if (prior) return prior;
    let request = this.loads.get(viewId);
    if (!request) {
      request = this.store
        .read(viewId)
        .then((value) => {
          const state =
            value === null ? readyTimer(minutes) : decodeTimer(value);
          if (!this.disposed) {
            this.states.set(viewId, state);
            for (const listener of this.listeners) listener();
          }
          return state;
        })
        .finally(() => this.loads.delete(viewId));
      this.loads.set(viewId, request);
    }
    return request;
  }
  change(
    viewId: string,
    operation: "start" | "pause" | "resume" | "reset",
    minutes = 25,
  ): Promise<void> {
    const task = (this.pending.get(viewId) ?? Promise.resolve()).then(
      async () => {
        ensure(!this.disposed, "disposed", "The timer controller is closed.");
        let state: TimerState;
        if (operation === "reset") {
          try {
            await this.loads.get(viewId);
          } catch {
            /* Explicit replacement. */
          }
          state = readyTimer(minutes);
        } else {
          const prior = await this.load(viewId, minutes),
            now = this.now(),
            remaining = remainingAt(prior, now);
          state = prior;
          if (
            (operation === "start" && prior.phase === "ready") ||
            (operation === "resume" &&
              prior.phase === "paused" &&
              remaining > 0)
          )
            state = {
              ...prior,
              phase: "running",
              remainingMilliseconds: remaining,
              deadline: new Date(now.getTime() + remaining).toISOString(),
            };
          else if (operation === "pause" && prior.phase === "running")
            state = {
              version: 1,
              phase: remaining === 0 ? "complete" : "paused",
              durationSeconds: prior.durationSeconds,
              remainingMilliseconds: remaining,
            };
        }
        await this.store.write(viewId, state);
        if (!this.disposed) {
          this.states.set(viewId, state);
          for (const listener of this.listeners) listener();
        }
      },
    );
    this.pending.set(
      viewId,
      task.catch(() => {}),
    );
    return task;
  }
  dispose() {
    this.disposed = true;
    this.listeners.clear();
  }
}
