import { ensure } from "../runtime/errors";

export interface HostScope {
  endpoint: string;
  projectId: string;
  accountId: string;
  appId: string;
}

export class HostLifetime {
  readonly scope: Readonly<HostScope>;
  readonly key: string;
  private closed = false;
  private cleanups = new Set<() => void>();
  constructor(scope: HostScope) {
    let endpoint: URL;
    try {
      endpoint = new URL(scope.endpoint);
    } catch {
      throw new Error("A valid backend endpoint is required.");
    }
    ensure(
      !endpoint.username &&
        !endpoint.password &&
        !endpoint.search &&
        !endpoint.hash &&
        (endpoint.protocol === "https:" ||
          (endpoint.protocol === "http:" &&
            ["localhost", "127.0.0.1", "[::1]"].includes(endpoint.hostname))) &&
        [scope.projectId, scope.accountId, scope.appId].every(
          (value) =>
            typeof value === "string" &&
            /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value),
        ),
      "invalid_scope",
      "Local recovery requires a signed-in backend, project, account and app.",
    );
    this.scope = Object.freeze({
      projectId: scope.projectId,
      accountId: scope.accountId,
      appId: scope.appId,
      endpoint: endpoint.toString().replace(/\/+$/, ""),
    });
    this.key = JSON.stringify([
      1,
      this.scope.endpoint,
      scope.projectId,
      scope.accountId,
      scope.appId,
    ]);
  }
  get active() {
    return !this.closed;
  }
  assertActive() {
    ensure(
      !this.closed,
      "disposed",
      "This account's local app scope is closed.",
    );
  }
  onDispose(cleanup: () => void) {
    this.assertActive();
    this.cleanups.add(cleanup);
    return () => {
      this.cleanups.delete(cleanup);
    };
  }
  dispose() {
    if (this.closed) return;
    this.closed = true;
    for (const cleanup of this.cleanups) {
      try {
        cleanup();
      } catch {
        /* The scope remains closed. */
      }
    }
    this.cleanups.clear();
  }
}
