import { BackendError } from "../backend/errors";
import {
  ensure,
  isRuntimeAccessFailure,
  runtimeError,
} from "../runtime/errors";
import type { RuntimeTransport } from "../runtime/types";
import {
  id,
  runsPage,
  type AutomationRun,
  type SessionLifetime,
} from "./contracts";
export interface RunsOptions {
  appId: string;
  transport: RuntimeTransport;
  lifetime: SessionLifetime;
  onUnauthenticated?: () => void;
}
export interface RunsState {
  runs: AutomationRun[];
  cursor: string | null;
  loading: boolean;
  error: string | null;
  denied: boolean;
}
export class AutomationRunsController {
  private closed = false;
  private sequence = 0;
  private stopLifetime = () => {};
  private listeners = new Set<() => void>();
  private state: RunsState = {
    runs: [],
    cursor: null,
    loading: false,
    error: null,
    denied: false,
  };
  constructor(readonly options: RunsOptions) {
    id(options.appId);
    this.stopLifetime =
      options.lifetime.onDispose?.(() => this.dispose()) ?? (() => {});
  }
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  getSnapshot = () => this.state;
  private active() {
    this.options.lifetime.assertActive();
    ensure(!this.closed, "disposed", "This account's run history is closed.");
  }
  private emit(change: Partial<RunsState>) {
    if (this.closed) return;
    this.state = { ...this.state, ...change };
    for (const listener of this.listeners) listener();
  }
  async load(more = false) {
    if (this.closed || !this.options.lifetime.active) return;
    this.active();
    const cursor = more ? this.state.cursor : null;
    if (more && (!cursor || this.state.loading)) return;
    const sequence = ++this.sequence;
    this.emit({ loading: true, error: null });
    try {
      const response = await this.options.transport({
        op: "spec.runs",
        appId: this.options.appId,
        ...(cursor ? { afterId: cursor } : {}),
      });
      this.active();
      if (sequence !== this.sequence) return;
      const page = runsPage(response);
      if (more)
        ensure(
          page.runs.every(
            (item) =>
              !this.state.runs.some((existing) => existing.id === item.id),
          ) && page.nextCursor !== cursor,
          "invalid_response",
          "The run page overlaps earlier results. Refresh run history.",
        );
      this.emit({
        runs: more ? [...this.state.runs, ...page.runs] : page.runs,
        cursor: page.nextCursor,
        loading: false,
        denied: false,
      });
    } catch (error) {
      if (this.closed || sequence !== this.sequence) return;
      const failure = runtimeError(error);
      const unauthorized =
        (error instanceof BackendError &&
          (error.kind === "unauthenticated" || error.status === 401)) ||
        failure.code === "unauthenticated";
      const denied =
        unauthorized ||
        isRuntimeAccessFailure(failure) ||
        (error instanceof BackendError &&
          [403, 404].includes(error.status ?? 0));
      this.emit({
        loading: false,
        error: failure.message,
        ...(denied ? { runs: [], cursor: null, denied: true } : {}),
      });
      if (unauthorized) {
        try {
          this.options.onUnauthenticated?.();
        } finally {
          this.dispose();
        }
      }
    }
  }
  dispose() {
    if (this.closed) return;
    this.closed = true;
    this.sequence++;
    this.stopLifetime();
    this.state = {
      ...this.state,
      runs: [],
      cursor: null,
      loading: false,
      error: null,
    };
    this.listeners.clear();
  }
}
