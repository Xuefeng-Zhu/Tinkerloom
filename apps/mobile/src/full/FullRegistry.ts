import { BackendError } from "../backend/errors";
import type { AppBackend } from "../backend/types";
import type { HostScope } from "../host/scope";
import type { RuntimeTransport } from "../runtime/types";
import { ensure } from "../runtime/errors";
import { FullAppController } from "./FullAppController";
import { FullWorkspaceController } from "./FullWorkspaceController";

export interface AccountSession {
  accountId: string | null;
  epoch: number;
  active: boolean;
}
const sessionKey = (session: AccountSession) =>
  session.active && session.accountId
    ? JSON.stringify([session.accountId, session.epoch])
    : null;

/** Check before dispatch and after settlement, including same-account reauthentication. */
export function accountTransport(options: {
  execute: RuntimeTransport;
  readSession: () => AccountSession;
  expected: AccountSession;
  alive: () => boolean;
  onUnauthenticated: () => void;
}): RuntimeTransport {
  const expectedKey = sessionKey(options.expected);
  const current = () =>
    options.alive() &&
    expectedKey !== null &&
    sessionKey(options.readSession()) === expectedKey;
  const changed = (dispatched: boolean) =>
    new BackendError(
      "This account session has closed. Reopen the app after signing in.",
      "session_changed",
      "transport",
      dispatched,
    );
  return async (request) => {
    if (!current()) throw changed(false);
    try {
      const response = await options.execute(request);
      if (!current()) throw changed(true);
      return response;
    } catch (error) {
      if (!current()) throw changed(true);
      if (
        error instanceof BackendError &&
        (error.kind === "unauthenticated" || error.status === 401)
      ) {
        options.onUnauthenticated();
      }
      throw error;
    }
  };
}

/** Retains controllers across routes, while encrypted recovery survives disposal. */
export class FullRegistry {
  private apps = new Map<string, FullAppController>();
  private workspaces = new Map<string, FullWorkspaceController>();
  private key: string | null = null;
  private closed = false;
  constructor(
    private readonly options: {
      backend: AppBackend;
      scope: Pick<HostScope, "endpoint" | "projectId">;
      readSession: () => AccountSession;
      onUnauthenticated: () => void;
    },
  ) {}

  syncSession() {
    const next = sessionKey(this.options.readSession());
    if (next !== this.key) {
      this.clear();
      this.key = next;
    }
  }
  private clear() {
    for (const app of this.apps.values()) app.dispose();
    for (const workspace of this.workspaces.values()) workspace.dispose();
    this.apps.clear();
    this.workspaces.clear();
  }
  private session(accountId: string) {
    this.syncSession();
    const expected = this.options.readSession();
    ensure(
      !this.closed && expected.active && expected.accountId === accountId,
      "session_changed",
      "Sign in to open your apps.",
    );
    return expected;
  }
  private transport(expected: AccountSession): RuntimeTransport {
    const execute = this.options.backend.executeSpec;
    ensure(execute, "unavailable", "The full app service is unavailable.");
    return accountTransport({
      execute: (request) => execute.call(this.options.backend, request),
      expected,
      readSession: this.options.readSession,
      alive: () => !this.closed,
      onUnauthenticated: this.options.onUnauthenticated,
    });
  }
  app(accountId: string, appId: string) {
    const expected = this.session(accountId);
    ensure(
      /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(appId),
      "invalid_app",
      "This app is unavailable.",
    );
    let app = this.apps.get(appId);
    if (!app) {
      app = new FullAppController({
        scope: { ...this.options.scope, accountId, appId },
        transport: this.transport(expected),
        newId: () => this.options.backend.newId(),
      });
      this.apps.set(appId, app);
    }
    return app;
  }
  workspace(accountId: string, workspaceId: string) {
    const expected = this.session(accountId);
    ensure(
      /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(workspaceId),
      "invalid_workspace",
      "This workspace is unavailable.",
    );
    let workspace = this.workspaces.get(workspaceId);
    if (!workspace) {
      workspace = new FullWorkspaceController({
        scope: { ...this.options.scope, accountId },
        workspaceId,
        transport: this.transport(expected),
        newId: () => this.options.backend.newId(),
      });
      this.workspaces.set(workspaceId, workspace);
    }
    return workspace;
  }
  refreshApp(appId: string) {
    this.syncSession();
    const app = this.apps.get(appId);
    if (app) void app.load();
  }
  dispose() {
    this.closed = true;
    this.clear();
    this.key = null;
  }
}
