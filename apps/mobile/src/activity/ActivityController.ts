import { BackendError } from "../backend/errors";
import {
  ensure,
  isRuntimeAccessFailure,
  runtimeError,
} from "../runtime/errors";
import type { RuntimeTransport } from "../runtime/types";
import { activityId, activityPage, type ActivityEntry } from "./contracts";

export interface ActivitySession {
  accountId: string | null;
  epoch: number;
  active: boolean;
}
export interface ActivityOptions {
  appId: string;
  accountId: string;
  epoch: number;
  transport: RuntimeTransport;
  readSession: () => ActivitySession;
  subscribeSession: (listener: () => void) => () => void;
  onUnauthenticated?: () => void;
}
export interface ActivityState {
  items: readonly ActivityEntry[];
  cursor: string | null;
  loading: boolean;
  denied: boolean;
  error: string | null;
}

/** Read-only, scoped to one account epoch and app. It never reads a private draft. */
export class ActivityController {
  private closed = false;
  private sequence = 0;
  private listeners = new Set<() => void>();
  private unsubscribe = () => {};
  private observing = false;
  private holders = 0;
  readonly options: Readonly<ActivityOptions>;
  private state: ActivityState = {
    items: [],
    cursor: null,
    loading: false,
    denied: false,
    error: null,
  };
  constructor(options: ActivityOptions) {
    this.options = Object.freeze({ ...options });
    activityId(options.appId);
    activityId(options.accountId);
    ensure(
      Number.isSafeInteger(options.epoch) && options.epoch >= 0,
      "invalid_scope",
      "An authenticated session is required for activity.",
    );
    ensure(this.current(), "session_changed", "Sign in to inspect activity.");
  }
  private observeSession() {
    if (this.observing || this.closed) return;
    this.observing = true;
    this.unsubscribe = this.options.subscribeSession(() => {
      if (!this.current()) this.dispose();
    });
  }
  /** React's repeated effect setup may retain again before deferred disposal. */
  retain() {
    if (!this.current()) {
      this.dispose();
      return () => {};
    }
    this.observeSession();
    this.holders++;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.holders--;
      queueMicrotask(() => {
        if (this.holders === 0) this.dispose();
      });
    };
  }
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  getSnapshot = () => this.state;
  private current() {
    const session = this.options.readSession();
    return (
      !this.closed &&
      session.active &&
      session.accountId === this.options.accountId &&
      session.epoch === this.options.epoch
    );
  }
  private emit(change: Partial<ActivityState>) {
    if (this.closed) return;
    this.state = { ...this.state, ...change };
    for (const listener of this.listeners) listener();
  }
  async load(more = false) {
    this.observeSession();
    if (!this.current()) {
      this.dispose();
      return;
    }
    const cursor = more ? this.state.cursor : null;
    if (more && (!cursor || this.state.loading)) return;
    const sequence = ++this.sequence;
    this.emit({ loading: true, error: null });
    try {
      const response = await this.options.transport({
        op: "spec.listActivity",
        appId: this.options.appId,
        limit: 50,
        ...(cursor ? { cursor } : {}),
      });
      if (!this.current()) {
        this.dispose();
        return;
      }
      if (sequence !== this.sequence) return;
      const page = activityPage(response, this.options.appId);
      ensure(
        !more ||
          (page.nextCursor !== cursor &&
            (!page.items.length ||
              !this.state.items.length ||
              page.items[0].id >
                this.state.items[this.state.items.length - 1].id)),
        "invalid_response",
        "Activity changed. Refresh before loading another page.",
      );
      this.emit({
        items: more ? [...this.state.items, ...page.items] : page.items,
        cursor: page.nextCursor,
        loading: false,
        denied: false,
      });
    } catch (error) {
      if (!this.current()) {
        this.dispose();
        return;
      }
      if (sequence !== this.sequence) return;
      const failure = runtimeError(error);
      const unauthorized =
        failure.code === "unauthenticated" ||
        (error instanceof BackendError && error.status === 401);
      const denied =
        unauthorized ||
        isRuntimeAccessFailure(failure) ||
        failure.code === "not_found" ||
        (error instanceof BackendError &&
          [403, 404].includes(error.status ?? 0));
      const stale = failure.code === "revision_conflict";
      this.emit({
        loading: false,
        error: denied
          ? "Access is unavailable. Activity has been cleared."
          : stale
            ? "Activity changed. Refresh to load a current page."
            : "Activity could not be loaded. Refresh to try again.",
        ...(denied || stale ? { items: [], cursor: null } : {}),
        denied,
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
  cancelRead() {
    ++this.sequence;
    this.emit({ loading: false });
  }
  dispose() {
    if (this.closed) return;
    this.closed = true;
    ++this.sequence;
    this.unsubscribe();
    this.state = {
      items: [],
      cursor: null,
      loading: false,
      denied: true,
      error: "This account session has closed.",
    };
    for (const listener of this.listeners) listener();
    this.listeners.clear();
  }
}
