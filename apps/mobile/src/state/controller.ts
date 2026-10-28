import type { AppBackend, MiniApp, User, Workspace } from "../backend/types";
import { BackendError } from "../backend/errors";

type CreationKind = "workspace" | "app";
export interface Creation {
  kind: CreationKind;
  open: boolean;
  busy: boolean;
  error: string | null;
  command: { id: string; name: string; workspaceId?: string } | null;
}

export interface AppState {
  phase: "loading" | "signedOut" | "signedIn";
  user: User | null;
  authBusy: boolean;
  workspaces: Workspace[];
  workspaceId: string | null;
  apps: MiniApp[];
  loading: boolean;
  error: string | null;
  notice: string | null;
  creation: Creation | null;
}

const initial = (): AppState => ({
  phase: "loading",
  user: null,
  authBusy: false,
  workspaces: [],
  workspaceId: null,
  apps: [],
  loading: false,
  error: null,
  notice: null,
  creation: null,
});

function safeMessage(error: unknown): string {
  return error instanceof BackendError
    ? error.message
    : "We could not confirm the request. Check your connection and try again.";
}

/** Session and selection generations keep late responses out of another view. */
export class AppController {
  private state: AppState = initial();
  private listeners = new Set<() => void>();
  private session = 0;
  private request = 0;

  constructor(private readonly backend: AppBackend) {}

  getSnapshot = (): AppState => this.state;
  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private set(patch: Partial<AppState>): void {
    this.state = { ...this.state, ...patch };
    for (const listener of this.listeners) listener();
  }

  private signedOut(message: string | null = null): void {
    this.session++;
    this.request++;
    this.state = { ...initial(), phase: "signedOut", error: message };
    this.set({});
  }
  expireSession(): void {
    this.signedOut("Your session has expired. Sign in again to continue.");
  }

  private failure(error: unknown): boolean {
    if (error instanceof BackendError && error.kind === "unauthenticated") {
      this.signedOut("Your session has expired. Sign in again to continue.");
      return true;
    }
    return false;
  }

  async bootstrap(): Promise<void> {
    const session = ++this.session;
    this.set({ phase: "loading", error: null, authBusy: false });
    try {
      const user = await this.backend.currentUser();
      if (session !== this.session) return;
      if (!user) {
        this.signedOut();
        return;
      }
      this.set({ phase: "signedIn", user, error: null });
      await this.refresh();
    } catch (error) {
      if (session === this.session) this.signedOut(safeMessage(error));
    }
  }

  async authenticate(
    mode: "signIn" | "signUp",
    email: string,
    password: string,
    name = "",
  ): Promise<void> {
    if (this.state.authBusy) return;
    const session = ++this.session;
    this.set({ authBusy: true, error: null });
    try {
      const user =
        mode === "signIn"
          ? await this.backend.signIn(email.trim(), password)
          : await this.backend.signUp(email.trim(), password, name.trim());
      if (session !== this.session) return;
      this.set({ phase: "signedIn", user, authBusy: false, error: null });
      await this.refresh();
    } catch (error) {
      if (session === this.session)
        this.set({
          phase: "signedOut",
          authBusy: false,
          error: safeMessage(error),
        });
    }
  }

  async signOut(): Promise<void> {
    if (this.state.authBusy || this.state.creation?.busy) return;
    const session = ++this.session;
    this.request++;
    this.set({ authBusy: true, loading: false, error: null });
    try {
      await this.backend.signOut();
      if (session === this.session) this.signedOut();
    } catch (error) {
      if (session !== this.session || this.failure(error)) return;
      this.set({ authBusy: false, error: safeMessage(error) });
    }
  }

  async refresh(): Promise<void> {
    if (!this.state.user || this.state.authBusy) return;
    const session = this.session;
    const request = ++this.request;
    this.set({ loading: true, error: null });
    try {
      const workspaces = await this.backend.listWorkspaces();
      if (session !== this.session || request !== this.request) return;
      const workspaceId = workspaces.some(
        (w) => w.id === this.state.workspaceId,
      )
        ? this.state.workspaceId
        : (workspaces[0]?.id ?? null);
      this.set({ workspaces, workspaceId, apps: [] });
      const apps = workspaceId ? await this.backend.listApps(workspaceId) : [];
      if (session !== this.session || request !== this.request) return;
      this.set({ apps, loading: false });
    } catch (error) {
      if (
        session !== this.session ||
        request !== this.request ||
        this.failure(error)
      )
        return;
      this.set({ loading: false, error: safeMessage(error) });
    }
  }

  async selectWorkspace(workspaceId: string): Promise<void> {
    if (
      !this.state.user ||
      this.state.authBusy ||
      !this.state.workspaces.some((w) => w.id === workspaceId)
    )
      return;
    const session = this.session;
    const request = ++this.request;
    this.set({
      workspaceId,
      apps: [],
      loading: true,
      error: null,
      notice: null,
    });
    try {
      const apps = await this.backend.listApps(workspaceId);
      if (session === this.session && request === this.request)
        this.set({ apps, loading: false });
    } catch (error) {
      if (
        session !== this.session ||
        request !== this.request ||
        this.failure(error)
      )
        return;
      this.set({ loading: false, error: safeMessage(error) });
    }
  }

  openCreation(kind: CreationKind): void {
    if (!this.state.user || this.state.authBusy) return;
    if (this.state.creation?.command) {
      this.set({ creation: { ...this.state.creation, open: true } });
      return;
    }
    if (kind === "app" && !this.state.workspaceId) return;
    this.set({
      creation: { kind, open: true, busy: false, error: null, command: null },
      notice: null,
    });
  }

  closeCreation(): void {
    const creation = this.state.creation;
    if (!creation || creation.busy) return;
    this.set({
      creation: creation.command ? { ...creation, open: false } : null,
    });
  }

  async submitCreation(name: string): Promise<void> {
    const creation = this.state.creation;
    if (!creation || creation.busy || !this.state.user || this.state.authBusy)
      return;
    const command = creation.command ?? {
      id: this.backend.newId(),
      name: name.trim(),
      ...(creation.kind === "app"
        ? { workspaceId: this.state.workspaceId! }
        : {}),
    };
    if (!command.name || command.name.length > 128) {
      this.set({
        creation: { ...creation, error: "Enter a name of 1–128 characters." },
      });
      return;
    }
    const session = this.session;
    this.set({ creation: { ...creation, command, busy: true, error: null } });
    try {
      if (creation.kind === "workspace")
        await this.backend.createWorkspace(command);
      else
        await this.backend.createApp({
          ...command,
          workspaceId: command.workspaceId!,
        });
      if (session !== this.session) return;
      this.set({
        creation: null,
        notice: `${creation.kind === "workspace" ? "Workspace" : "App shell"} created.`,
      });
      await this.refresh();
    } catch (error) {
      if (session !== this.session || this.failure(error)) return;
      const uncertain = !(error instanceof BackendError) || error.uncertain;
      this.set({
        creation: {
          ...creation,
          open: true,
          busy: false,
          command: uncertain ? command : null,
          error: safeMessage(error),
        },
      });
    }
  }

  /** Unmount only fences callbacks; it never logs out another mounted client. */
  dispose(): void {
    this.session++;
    this.request++;
    this.listeners.clear();
  }
}
