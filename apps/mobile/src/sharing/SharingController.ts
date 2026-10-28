import { BackendError } from "../backend/errors";
import type {
  AppBackend,
  MiniApp,
  AppMember,
  CreateInvitation,
  Invitation,
  RevokeInvitation,
  SetGrant,
  ArchiveApp,
} from "../backend/types";
import { InvitationController } from "./InvitationController";

type Pending =
  | { kind: "invite"; command: CreateInvitation }
  | { kind: "revoke"; command: RevokeInvitation }
  | { kind: "grant"; command: SetGrant }
  | { kind: "archive"; command: ArchiveApp };

export interface SharingState {
  app: MiniApp | null;
  members: AppMember[];
  invitations: Invitation[];
  memberCursor: string | null;
  invitationCursor: string | null;
  createdInvite: { invitation: Invitation; token: string } | null;
  pending: Pending | null;
  busy: boolean;
  loading: boolean;
  error: string | null;
  notice: string | null;
}

const initial = (): SharingState => ({
  app: null,
  members: [],
  invitations: [],
  memberCursor: null,
  invitationCursor: null,
  createdInvite: null,
  pending: null,
  busy: false,
  loading: false,
  error: null,
  notice: null,
});

function errorMessage(error: unknown): string {
  return error instanceof BackendError
    ? error.message
    : "This change could not be confirmed. Retry the same request.";
}

function canRecover(app: MiniApp, pending: Pending): boolean {
  if (pending.kind === "archive")
    return (
      app.capabilities?.archive === true ||
      (app.archived === true &&
        app.role === "owner" &&
        app.capabilities?.revokeAccess === true)
    );
  // Archived owners/builders can recover receipts for old writes. The server
  // still rejects new work, and a revoked sharing role cannot recover secrets.
  return app.capabilities?.revokeAccess === true;
}

/** Keep private candidate payloads out of the sharing state, including the
 * bounded fallback used by older injected backends. */
function metadata(app: MiniApp): MiniApp {
  return {
    id: app.id,
    workspaceId: app.workspaceId,
    name: app.name,
    ...(app.engine === undefined ? {} : { engine: app.engine }),
    ...(app.role === undefined ? {} : { role: app.role }),
    ...(app.archived === undefined ? {} : { archived: app.archived }),
    ...(app.capabilities === undefined
      ? {}
      : { capabilities: { ...app.capabilities } }),
  };
}

function archiveAcknowledged(app: MiniApp | null): MiniApp | null {
  if (!app) return null;
  // A stored receipt confirms archival, not current roles, labels or drafts.
  // Apply only the downward write restriction until a fresh authorized read.
  return {
    ...app,
    archived: true,
    ...(app.capabilities === undefined
      ? {}
      : {
          capabilities: {
            ...app.capabilities,
            editDefinition: false,
            share: false,
            writeRecords: false,
            archive: false,
          },
        }),
  };
}

/** Account-scoped commands retain the original token, role, target and revision. */
export class SharingController {
  private state = initial();
  private listeners = new Set<() => void>();
  private generation = 0;
  private disposed = false;

  constructor(
    private readonly backend: AppBackend,
    readonly appId: string,
    private readonly newToken: () => Promise<string>,
    private readonly onAuthFailure: () => void,
  ) {}

  getSnapshot = () => this.state;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private set(patch: Partial<SharingState>) {
    if (this.disposed) return;
    this.state = { ...this.state, ...patch };
    for (const listener of this.listeners) listener();
  }

  private fail(error: unknown) {
    if (error instanceof BackendError && error.kind === "unauthenticated") {
      this.set(initial());
      this.onAuthFailure();
      return;
    }
    if (
      error instanceof BackendError &&
      (error.status === 403 || error.status === 404)
    ) {
      this.set({ ...initial(), error: errorMessage(error) });
      return;
    }
    this.set({ loading: false, busy: false, error: errorMessage(error) });
  }

  async load(): Promise<void> {
    if (this.disposed || this.state.busy) return;
    const generation = ++this.generation;
    this.set({ loading: true, error: null });
    try {
      const app = metadata(
        await (this.backend.getAppAccess?.(this.appId) ??
          this.backend.getApp(this.appId)),
      );
      if (this.disposed || generation !== this.generation) return;
      const canManage = app.capabilities?.revokeAccess === true;
      // Apply confirmed access before another read can fail. In particular, a
      // former builder must immediately lose private invitations and tokens.
      this.set({
        app,
        ...(!canManage
          ? {
              invitations: [],
              invitationCursor: null,
              createdInvite: null,
            }
          : {}),
        pending:
          this.state.pending && canRecover(app, this.state.pending)
            ? this.state.pending
            : null,
      });
      const [members, invitations] = await Promise.all([
        this.backend.listMembers(this.appId),
        canManage
          ? this.backend.listInvitations(this.appId)
          : Promise.resolve({ invitations: [], nextCursor: null }),
      ]);
      if (this.disposed || generation !== this.generation) return;
      this.set({
        app,
        members: members.members,
        invitations: invitations.invitations,
        memberCursor: members.nextCursor,
        invitationCursor: invitations.nextCursor,
        loading: false,
      });
    } catch (error) {
      if (!this.disposed && generation === this.generation) this.fail(error);
    }
  }

  async loadMore(kind: "members" | "invitations"): Promise<void> {
    const cursor =
      kind === "members"
        ? this.state.memberCursor
        : this.state.invitationCursor;
    if (!cursor || this.state.busy || this.state.loading || this.disposed)
      return;
    if (kind === "invitations" && !this.state.app?.capabilities?.revokeAccess)
      return;
    const generation = ++this.generation;
    this.set({ loading: true, error: null });
    try {
      if (kind === "members") {
        const page = await this.backend.listMembers(this.appId, cursor);
        if (this.disposed || generation !== this.generation) return;
        const members = new Map(
          this.state.members.map((item) => [item.actorId, item]),
        );
        for (const member of page.members) members.set(member.actorId, member);
        this.set({
          members: [...members.values()],
          memberCursor: page.nextCursor,
        });
      } else {
        const page = await this.backend.listInvitations(this.appId, cursor);
        if (this.disposed || generation !== this.generation) return;
        const invitations = new Map(
          this.state.invitations.map((item) => [item.id, item]),
        );
        for (const invitation of page.invitations)
          invitations.set(invitation.id, invitation);
        this.set({
          invitations: [...invitations.values()],
          invitationCursor: page.nextCursor,
        });
      }
      this.set({ loading: false });
    } catch (error) {
      if (!this.disposed && generation === this.generation) this.fail(error);
    }
  }

  async invite(
    role: Invitation["role"],
    recipientId: string | null,
  ): Promise<void> {
    if (
      !this.state.app?.capabilities?.share ||
      this.state.busy ||
      this.state.loading ||
      this.state.pending ||
      this.disposed
    )
      return;
    const generation = ++this.generation;
    this.set({ busy: true, error: null, notice: null });
    try {
      const token = await this.newToken();
      if (this.disposed || generation !== this.generation) return;
      await this.run({
        kind: "invite",
        command: {
          appId: this.appId,
          id: this.backend.newId(),
          operationId: this.backend.newId(),
          role,
          recipientId,
          token,
        },
      });
    } catch (error) {
      if (!this.disposed && generation === this.generation) this.fail(error);
    }
  }

  async revoke(invitationId: string): Promise<void> {
    if (
      !this.state.app?.capabilities?.revokeAccess ||
      this.state.busy ||
      this.state.loading ||
      this.state.pending ||
      this.disposed
    )
      return;
    await this.run({
      kind: "revoke",
      command: {
        appId: this.appId,
        invitationId,
        operationId: this.backend.newId(),
      },
    });
  }

  async changeRole(member: AppMember, role: SetGrant["role"]): Promise<void> {
    if (
      !(role === null
        ? this.state.app?.capabilities?.revokeAccess
        : this.state.app?.capabilities?.share) ||
      member.role === "owner" ||
      this.state.busy ||
      this.state.loading ||
      this.state.pending ||
      this.disposed
    )
      return;
    await this.run({
      kind: "grant",
      command: {
        appId: this.appId,
        actorId: member.actorId,
        role,
        expectedRevision: member.revision,
        operationId: this.backend.newId(),
      },
    });
  }

  async archive(): Promise<void> {
    if (
      !this.state.app?.capabilities?.archive ||
      this.state.busy ||
      this.state.loading ||
      this.state.pending ||
      this.disposed
    )
      return;
    await this.run({
      kind: "archive",
      command: {
        appId: this.appId,
        operationId: this.backend.newId(),
      },
    });
  }

  async retry(): Promise<void> {
    if (
      this.state.pending &&
      this.state.app &&
      canRecover(this.state.app, this.state.pending) &&
      !this.state.busy &&
      !this.state.loading &&
      !this.disposed
    )
      await this.run(this.state.pending);
  }

  private async run(pending: Pending): Promise<void> {
    const generation = ++this.generation;
    this.set({
      busy: true,
      loading: false,
      pending,
      error: null,
      notice: null,
    });
    try {
      let app = this.state.app;
      let createdInvite = this.state.createdInvite;
      if (pending.kind === "invite") {
        const invitation = await this.backend.createInvitation(pending.command);
        createdInvite = { invitation, token: pending.command.token };
      } else if (pending.kind === "revoke") {
        await this.backend.revokeInvitation(pending.command);
        if (createdInvite?.invitation.id === pending.command.invitationId)
          createdInvite = null;
      } else if (pending.kind === "grant") {
        await this.backend.setGrant(pending.command);
      } else {
        const acknowledgement = await (this.backend.archiveAppAccess?.(
          pending.command,
        ) ?? this.backend.archiveApp(pending.command));
        if (
          acknowledgement.id !== this.appId ||
          acknowledgement.archived !== true
        ) {
          throw new BackendError(
            "The archive response could not be confirmed. Retry this same request.",
            "invalid_response",
            "invalid_response",
            true,
          );
        }
        app = archiveAcknowledged(app);
        createdInvite = null;
      }
      if (this.disposed || generation !== this.generation) return;
      this.set({
        app,
        busy: false,
        pending: null,
        createdInvite,
        notice: "Change saved.",
      });
      await this.load();
    } catch (error) {
      if (this.disposed || generation !== this.generation) return;
      const uncertain =
        !(error instanceof BackendError) ||
        error.uncertain ||
        error.code === "transaction_conflict";
      this.set({ busy: false, pending: uncertain ? pending : null });
      this.fail(error);
    }
  }

  dispose() {
    this.disposed = true;
    this.generation++;
    this.state = initial();
    this.listeners.clear();
  }
}

export class SharingRegistry {
  private entries = new Map<string, SharingController>();
  private acceptances = new Map<string, InvitationController>();
  constructor(
    private readonly backend: AppBackend,
    private readonly newToken: () => Promise<string>,
    private readonly onAuthFailure: () => void,
  ) {}
  get(userId: string, appId: string) {
    const key = `${userId}/${appId}`;
    let controller = this.entries.get(key);
    if (!controller) {
      controller = new SharingController(
        this.backend,
        appId,
        this.newToken,
        this.onAuthFailure,
      );
      this.entries.set(key, controller);
    }
    return controller;
  }
  invitation(userId: string, token: string) {
    const key = `${userId}/${token}`;
    let controller = this.acceptances.get(key);
    if (!controller) {
      controller = new InvitationController(
        this.backend,
        token,
        this.onAuthFailure,
      );
      this.acceptances.set(key, controller);
    }
    return controller;
  }
  keepUser(userId: string | null) {
    for (const [key, controller] of this.entries) {
      if (!userId || !key.startsWith(`${userId}/`)) {
        controller.dispose();
        this.entries.delete(key);
      }
    }
    for (const [key, controller] of this.acceptances) {
      if (!userId || !key.startsWith(`${userId}/`)) {
        controller.dispose();
        this.acceptances.delete(key);
      }
    }
  }
  dispose() {
    for (const controller of this.entries.values()) controller.dispose();
    this.entries.clear();
    for (const controller of this.acceptances.values()) controller.dispose();
    this.acceptances.clear();
  }
}
