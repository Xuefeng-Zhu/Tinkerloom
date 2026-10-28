import type { WatchActivity, WatchActivitySnapshot } from "./invalidationTypes";
export function observableActivity(
  read: () => WatchActivitySnapshot,
  listen: (notify: () => void) => () => void,
): WatchActivity {
  let snapshot = read(),
    stop: (() => void) | null = null,
    closed = false;
  const listeners = new Set<() => void>();
  const update = () => {
    const next = read();
    if (
      next.foreground !== snapshot.foreground ||
      next.online !== snapshot.online
    ) {
      snapshot = next;
      for (const listener of listeners) listener();
    }
  };
  return {
    getSnapshot() {
      if (!stop && !closed) update();
      return snapshot;
    },
    subscribe(listener) {
      if (closed) return () => {};
      listeners.add(listener);
      if (!stop) {
        snapshot = read();
        stop = listen(update);
      }
      let removed = false;
      return () => {
        if (removed) return;
        removed = true;
        listeners.delete(listener);
        if (!listeners.size) {
          stop?.();
          stop = null;
        }
      };
    },
    dispose() {
      if (closed) return;
      closed = true;
      stop?.();
      stop = null;
      listeners.clear();
      snapshot = { foreground: false, online: false };
    },
  };
}
export interface NativeWatchActivityPort {
  currentState(): string | null | undefined;
  subscribe(
    event: "change" | "focus" | "blur",
    notify: (state?: string) => void,
  ): () => void;
}
export function nativeWatchActivity(port: NativeWatchActivityPort) {
  let focused = true;
  return observableActivity(
    () => ({
      foreground: focused && port.currentState() === "active",
      online: true,
    }),
    (notify) => {
      const stops = [
        port.subscribe("change", notify),
        port.subscribe("focus", () => {
          focused = true;
          notify();
        }),
        port.subscribe("blur", () => {
          focused = false;
          notify();
        }),
      ];
      return () => {
        for (const stop of stops) stop();
      };
    },
  );
}
export interface WatchEventsPort {
  addEventListener(event: string, listener: () => void): void;
  removeEventListener(event: string, listener: () => void): void;
}
export interface WebWatchEnvironment {
  document: WatchEventsPort & { visibilityState: string };
  window: WatchEventsPort;
  navigator: { onLine: boolean };
}
export function webWatchActivity(environment: WebWatchEnvironment | null) {
  return observableActivity(
    () => ({
      foreground:
        !!environment && environment.document.visibilityState === "visible",
      online: !!environment && environment.navigator.onLine !== false,
    }),
    (notify) => {
      if (!environment) return () => {};
      environment.document.addEventListener("visibilitychange", notify);
      environment.window.addEventListener("online", notify);
      environment.window.addEventListener("offline", notify);
      return () => {
        environment.document.removeEventListener("visibilitychange", notify);
        environment.window.removeEventListener("online", notify);
        environment.window.removeEventListener("offline", notify);
      };
    },
  );
}
