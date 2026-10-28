import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import type {
  AcceptInvitation,
  AppBackend,
  AppDocument,
  AppMember,
  ArchiveApp,
  CreateInvitation,
  Invitation,
  InvitationPage,
  InvitationPreview,
  MemberPage,
  MiniApp,
  RevokeInvitation,
  SetGrant,
} from "../backend/types";
import { InvitationController } from "./InvitationController";
import { SharingController, SharingRegistry } from "./SharingController";

const token = "a".repeat(42) + "A";
const otherToken = "b".repeat(42) + "A";
const owner: AppMember = { actorId: "owner", role: "owner", revision: 0 };
const member: AppMember = { actorId: "reader", role: "viewer", revision: 3 };
const invitation: Invitation = {
  id: "invitation",
  appId: "app",
  issuerId: "owner",
  role: "builder",
  recipientId: "recipient",
  createdAt: "2026-10-28T10:00:00.000Z",
  expiresAt: "2026-11-04T10:00:00.000Z",
  revoked: false,
  acceptedBy: null,
};
const preview: InvitationPreview = {
  appId: "app",
  appName: "Private planner",
  role: "builder",
  expiresAt: invitation.expiresAt,
  accepted: false,
};
function app(
  role: AppDocument["role"] = "owner",
  archived = false,
): AppDocument {
  const builder = role === "owner" || role === "builder";
  return {
    id: "app",
    workspaceId: "workspace",
    name: "Private planner",
    role,
    archived,
    capabilities: {
      editDefinition: builder && !archived,
      share: builder && !archived,
      writeRecords: builder && !archived,
      archive: role === "owner" && !archived,
      revokeAccess: builder,
    },
    draftRevision: 0,
    publishedRevision: 0,
    definition: null,
    publishedDefinition: null,
  };
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((accept, fail) => {
    resolve = accept;
    reject = fail;
  });
  return { promise, resolve, reject };
}
const unknownResult = () =>
  new BackendError("Result unknown.", "connection_failed", "transport", true);
const denied = (status = 403) =>
  new BackendError(
    "Access was removed.",
    "forbidden",
    "service",
    false,
    status,
  );
const expired = () =>
  new BackendError(
    "Sign in again.",
    "user_unauthorized",
    "unauthenticated",
    false,
    401,
  );

class Backend implements AppBackend {
  generatedIds = 0;
  invitationsRead = 0;
  inspectedTokens: string[] = [];
  creates: CreateInvitation[] = [];
  grants: SetGrant[] = [];
  revocations: RevokeInvitation[] = [];
  archives: ArchiveApp[] = [];
  acceptances: AcceptInvitation[] = [];
  getApp = async (): Promise<AppDocument> => app();
  getAppAccess?: AppBackend["getAppAccess"];
  archiveAppAccess?: AppBackend["archiveAppAccess"];
  listMembers = async (): Promise<MemberPage> => ({
    members: [owner, member],
    nextCursor: "member-page-2",
  });
  listInvitations = async (): Promise<InvitationPage> => {
    this.invitationsRead++;
    return { invitations: [invitation], nextCursor: "invite-page-2" };
  };
  createImpl = async (command: CreateInvitation): Promise<Invitation> => ({
    ...invitation,
    id: command.id,
    role: command.role,
    recipientId: command.recipientId,
  });
  grantImpl = async (command: SetGrant): Promise<AppMember> => ({
    actorId: command.actorId,
    role: command.role,
    revision: command.expectedRevision + 1,
  });
  inspectImpl = async (): Promise<InvitationPreview> => preview;
  acceptImpl = async (): Promise<{ appId: string }> => ({ appId: "app" });
  newId() {
    return `operation-${++this.generatedIds}`;
  }
  createInvitation(command: CreateInvitation) {
    this.creates.push({ ...command });
    return this.createImpl(command);
  }
  setGrant(command: SetGrant) {
    this.grants.push({ ...command });
    return this.grantImpl(command);
  }
  async revokeInvitation(command: RevokeInvitation) {
    this.revocations.push({ ...command });
    return { ...invitation, id: command.invitationId, revoked: true };
  }
  async archiveApp(command: ArchiveApp) {
    this.archives.push({ ...command });
    return app("owner", true);
  }
  inspectInvitation(value: string) {
    this.inspectedTokens.push(value);
    return this.inspectImpl();
  }
  acceptInvitation(command: AcceptInvitation) {
    this.acceptances.push({ ...command });
    return this.acceptImpl();
  }
  async currentUser() {
    return null;
  }
  async signIn(): Promise<never> {
    throw new Error("Unused auth");
  }
  async signUp(): Promise<never> {
    throw new Error("Unused auth");
  }
  async signOut() {}
  async listWorkspaces() {
    return [];
  }
  async createWorkspace() {}
  async listApps() {
    return [];
  }
  async createApp() {}
  async saveDraft(): Promise<never> {
    throw new Error("Unused definition");
  }
  async publishApp(): Promise<never> {
    throw new Error("Unused definition");
  }
  async listRecords(): Promise<never> {
    throw new Error("Unused records");
  }
  async saveRecord(): Promise<never> {
    throw new Error("Unused records");
  }
}

test("an unknown invitation retains its token, role, recipient and IDs through route return, refresh and retry", async () => {
  const backend = new Backend();
  let rngCalls = 0;
  backend.createImpl = async (command) => {
    if (backend.creates.length === 1) throw unknownResult();
    return { ...invitation, id: command.id };
  };
  const registry = new SharingRegistry(
    backend,
    async () => {
      rngCalls++;
      return token;
    },
    () => {},
  );
  const controller = registry.get("owner", "app");
  await controller.load();
  await controller.invite("builder", "recipient");
  const original = {
    appId: "app",
    id: "operation-1",
    operationId: "operation-2",
    role: "builder",
    recipientId: "recipient",
    token,
  };
  assert.deepEqual(controller.getSnapshot().pending, {
    kind: "invite",
    command: original,
  });
  assert.equal(registry.get("owner", "app"), controller);
  await registry.get("owner", "app").load();
  await controller.invite("viewer", null);
  assert.equal(
    backend.creates.length,
    1,
    "a pending command blocks a replacement invite",
  );
  await controller.retry();
  assert.deepEqual(backend.creates, [original, original]);
  assert.equal(rngCalls, 1);
  assert.equal(backend.generatedIds, 2);
  assert.equal(controller.getSnapshot().pending, null);
  assert.equal(controller.getSnapshot().createdInvite?.token, token);
});

test("a grant retry keeps the reviewed member revision even after a newer member page", async () => {
  const backend = new Backend();
  backend.grantImpl = async (command) => {
    if (backend.grants.length === 1) throw unknownResult();
    return { actorId: command.actorId, role: command.role, revision: 4 };
  };
  const controller = new SharingController(
    backend,
    "app",
    async () => token,
    () => {},
  );
  await controller.load();
  await controller.changeRole(member, "builder");
  backend.listMembers = async () => ({
    members: [owner, { ...member, revision: 9 }],
    nextCursor: null,
  });
  await controller.load();
  await controller.retry();
  assert.equal(controller.getSnapshot().members[1].revision, 9);
  assert.deepEqual(backend.grants, [
    {
      appId: "app",
      actorId: "reader",
      role: "builder",
      expectedRevision: 3,
      operationId: "operation-1",
    },
    {
      appId: "app",
      actorId: "reader",
      role: "builder",
      expectedRevision: 3,
      operationId: "operation-1",
    },
  ]);
});

test("a confirmed read-only role clears private invitations and a pending token before a later member read fails", async () => {
  const backend = new Backend();
  const controller = new SharingController(
    backend,
    "app",
    async () => token,
    () => {},
  );
  await controller.load();
  await controller.invite("builder", "recipient");
  backend.createImpl = async () => {
    throw unknownResult();
  };
  await controller.invite("viewer", null);
  assert.ok(controller.getSnapshot().createdInvite);
  assert.ok(controller.getSnapshot().pending);
  const members = deferred<MemberPage>();
  backend.getApp = async () => app("viewer");
  backend.listMembers = () => members.promise;
  const loading = controller.load();
  await Promise.resolve();
  const state = controller.getSnapshot();
  assert.equal(state.app?.role, "viewer");
  assert.equal(state.createdInvite, null);
  assert.equal(state.pending, null);
  assert.deepEqual(state.invitations, []);
  assert.equal(state.invitationCursor, null);
  assert.equal(state.loading, true);
  members.reject(new Error("Connection lost after the downgrade"));
  await loading;
  await controller.retry();
  assert.equal(backend.creates.length, 2);
  assert.equal(
    backend.invitationsRead,
    2,
    "read-only refresh never requests private invitations",
  );
  assert.equal(controller.getSnapshot().createdInvite, null);
});

test("an archived owner can revoke invitations and remove readers, but cannot create grants or invitations", async () => {
  const backend = new Backend();
  backend.getApp = async () => app("owner", true);
  let rngCalls = 0;
  const controller = new SharingController(
    backend,
    "app",
    async () => {
      rngCalls++;
      return token;
    },
    () => {},
  );
  await controller.load();
  await controller.invite("viewer", null);
  await controller.changeRole(member, "builder");
  await controller.archive();
  assert.equal(rngCalls, 0);
  assert.deepEqual(backend.creates, []);
  assert.equal(backend.grants.length, 0);
  assert.deepEqual(backend.archives, []);
  await controller.revoke(invitation.id);
  await controller.changeRole(member, null);
  assert.equal(backend.revocations.length, 1);
  assert.equal(backend.grants[0].role, null);
  assert.equal(backend.invitationsRead, 3);
});

test("archiving preserves the original invitation receipt retry for an authorized builder", async () => {
  const backend = new Backend();
  backend.createImpl = async (command) => {
    if (backend.creates.length === 1) throw unknownResult();
    return { ...invitation, id: command.id };
  };
  const controller = new SharingController(
    backend,
    "app",
    async () => token,
    () => {},
  );
  await controller.load();
  await controller.invite("builder", "recipient");
  backend.getApp = async () => app("builder", true);
  await controller.load();
  assert.ok(controller.getSnapshot().pending);
  await controller.retry();
  assert.deepEqual(backend.creates[1], backend.creates[0]);
  assert.equal(controller.getSnapshot().pending, null);
});

test("a confirmed archive disables new work even when the following refresh cannot connect", async () => {
  const backend = new Backend();
  let rngCalls = 0;
  const controller = new SharingController(
    backend,
    "app",
    async () => {
      rngCalls++;
      return token;
    },
    () => {},
  );
  await controller.load();
  backend.getApp = async () => {
    throw new Error("Offline after archive receipt");
  };
  await controller.archive();
  assert.equal(controller.getSnapshot().app?.archived, true);
  assert.equal(controller.getSnapshot().app?.capabilities?.revokeAccess, true);
  await controller.invite("viewer", null);
  await controller.changeRole(member, "builder");
  assert.equal(rngCalls, 0);
  assert.equal(backend.grants.length, 0);
  await controller.changeRole(member, null);
  await controller.revoke(invitation.id);
  assert.equal(backend.grants.length, 1);
  assert.equal(backend.revocations.length, 1);
});

test("403 and authentication expiry clear private sharing state and retained commands", async () => {
  for (const failure of [denied(), expired()]) {
    const backend = new Backend();
    let authFailures = 0;
    const controller = new SharingController(
      backend,
      "app",
      async () => token,
      () => {
        authFailures++;
      },
    );
    await controller.load();
    await controller.invite("builder", "recipient");
    backend.grantImpl = async () => {
      throw unknownResult();
    };
    await controller.changeRole(member, "builder");
    backend.getApp = async () => {
      throw failure;
    };
    await controller.load();
    const state = controller.getSnapshot();
    assert.equal(state.app, null);
    assert.deepEqual(state.members, []);
    assert.deepEqual(state.invitations, []);
    assert.equal(state.createdInvite, null);
    assert.equal(state.pending, null);
    assert.equal(state.loading, false);
    assert.equal(state.busy, false);
    assert.equal(authFailures, failure.kind === "unauthenticated" ? 1 : 0);
  }
});

test("a stale sharing response cannot overwrite a newer confirmed access downgrade", async () => {
  const backend = new Backend();
  const slowInvitations = deferred<InvitationPage>();
  backend.listInvitations = () => slowInvitations.promise;
  const controller = new SharingController(
    backend,
    "app",
    async () => token,
    () => {},
  );
  const oldLoad = controller.load();
  await Promise.resolve();
  backend.getApp = async () => app("viewer");
  await controller.load();
  slowInvitations.resolve({
    invitations: [invitation],
    nextCursor: "private-page",
  });
  await oldLoad;
  assert.equal(controller.getSnapshot().app?.role, "viewer");
  assert.deepEqual(controller.getSnapshot().invitations, []);
  assert.equal(controller.getSnapshot().invitationCursor, null);
});

test("switching accounts fences late private sharing pages and invitation creation responses", async () => {
  const backend = new Backend();
  const registry = new SharingRegistry(
    backend,
    async () => token,
    () => {},
  );
  const pageController = registry.get("account-a", "app");
  const privatePage = deferred<InvitationPage>();
  backend.listInvitations = () => privatePage.promise;
  const loading = pageController.load();
  await Promise.resolve();
  registry.keepUser("account-b");
  privatePage.resolve({ invitations: [invitation], nextCursor: null });
  await loading;
  assert.equal(pageController.getSnapshot().app, null);
  assert.deepEqual(pageController.getSnapshot().invitations, []);
  assert.notEqual(registry.get("account-b", "app"), pageController);

  backend.listInvitations = async () => ({ invitations: [], nextCursor: null });
  const creator = registry.get("account-b", "other-app");
  await creator.load();
  const created = deferred<Invitation>();
  backend.createImpl = () => created.promise;
  const creating = creator.invite("builder", "recipient");
  await Promise.resolve();
  registry.keepUser(null);
  created.resolve(invitation);
  await creating;
  assert.equal(creator.getSnapshot().createdInvite, null);
  assert.equal(creator.getSnapshot().pending, null);
  assert.equal(creator.getSnapshot().app, null);
});

test("disposing the registry while token generation is pending prevents any write", async () => {
  const backend = new Backend();
  const entropy = deferred<string>();
  const registry = new SharingRegistry(
    backend,
    () => entropy.promise,
    () => {},
  );
  const controller = registry.get("owner", "app");
  await controller.load();
  const creating = controller.invite("viewer", null);
  registry.dispose();
  entropy.resolve(token);
  await creating;
  assert.deepEqual(backend.creates, []);
  assert.equal(backend.generatedIds, 0);
  assert.equal(controller.getSnapshot().pending, null);
});

test("a late private app response cannot restore a disposed account's sharing screen", async () => {
  const backend = new Backend();
  const privateApp = deferred<AppDocument>();
  backend.getApp = () => privateApp.promise;
  const registry = new SharingRegistry(
    backend,
    async () => token,
    () => {},
  );
  const controller = registry.get("account-a", "app");
  const loading = controller.load();
  registry.keepUser("account-b");
  privateApp.resolve(app());
  await loading;
  assert.equal(controller.getSnapshot().app, null);
  assert.equal(controller.getSnapshot().loading, false);
  assert.equal(
    backend.invitationsRead,
    0,
    "a disposed account cannot begin further private reads",
  );
});

test("inspection is read-only and acceptance requires the explicit reviewed action", async () => {
  const backend = new Backend();
  const controller = new InvitationController(backend, token, () => {});
  await controller.accept();
  await controller.load();
  await controller.load();
  assert.deepEqual(backend.inspectedTokens, [token, token]);
  assert.deepEqual(backend.acceptances, []);
  assert.equal(backend.generatedIds, 0);
  assert.equal(controller.getSnapshot().preview?.appName, "Private planner");
  await controller.accept();
  await controller.accept();
  assert.deepEqual(backend.acceptances, [
    { token, operationId: "operation-1" },
  ]);
  assert.equal(controller.getSnapshot().appId, "app");
});

test("an unknown acceptance keeps the identical token and operation through route return and inspection", async () => {
  const backend = new Backend();
  backend.acceptImpl = async () => {
    if (backend.acceptances.length === 1) throw unknownResult();
    return { appId: "app" };
  };
  const registry = new SharingRegistry(
    backend,
    async () => otherToken,
    () => {},
  );
  const controller = registry.invitation("recipient", token);
  await controller.load();
  await controller.accept();
  assert.equal(registry.invitation("recipient", token), controller);
  await controller.load();
  await controller.accept();
  assert.equal(backend.acceptances.length, 1);
  await controller.retry();
  assert.deepEqual(backend.acceptances, [
    { token, operationId: "operation-1" },
    { token, operationId: "operation-1" },
  ]);
  assert.equal(backend.generatedIds, 1);
  assert.equal(controller.getSnapshot().appId, "app");
  assert.equal(controller.getSnapshot().pending, null);
});

test("an acceptance acknowledgement must match the originally inspected app", async () => {
  const backend = new Backend();
  backend.acceptImpl = async () => ({ appId: "wrong-app" });
  const controller = new InvitationController(backend, token, () => {});
  await controller.load();
  await controller.accept();
  assert.equal(controller.getSnapshot().appId, null);
  assert.ok(controller.getSnapshot().pending);
  assert.match(controller.getSnapshot().error ?? "", /could not be confirmed/);
  backend.inspectImpl = async () => ({ ...preview, appId: "wrong-app" });
  await controller.load();
  assert.equal(
    controller.getSnapshot().preview?.appId,
    "app",
    "a changed inspection cannot retarget an unconfirmed acceptance",
  );
  backend.acceptImpl = async () => ({ appId: "app" });
  await controller.retry();
  assert.equal(controller.getSnapshot().appId, "app");
  assert.deepEqual(backend.acceptances[1], backend.acceptances[0]);
});

test("revocation during inspection clears an invitation preview and an unknown acceptance", async () => {
  for (const status of [403, 404]) {
    const backend = new Backend();
    const controller = new InvitationController(backend, token, () => {});
    await controller.load();
    backend.acceptImpl = async () => {
      throw unknownResult();
    };
    await controller.accept();
    backend.inspectImpl = async () => {
      throw denied(status);
    };
    await controller.load();
    assert.equal(controller.getSnapshot().preview, null);
    assert.equal(controller.getSnapshot().pending, null);
    assert.equal(controller.getSnapshot().appId, null);
    await controller.retry();
    await controller.accept();
    assert.equal(backend.acceptances.length, 1);
  }
});

test("a stale invitation inspection failure cannot erase a newer accepted preview", async () => {
  const backend = new Backend();
  const oldPreview = deferred<InvitationPreview>();
  backend.inspectImpl = () => oldPreview.promise;
  const controller = new InvitationController(backend, token, () => {});
  const oldLoad = controller.load();
  backend.inspectImpl = async () => ({ ...preview, accepted: true });
  await controller.load();
  oldPreview.reject(denied());
  await oldLoad;
  assert.equal(controller.getSnapshot().appId, "app");
  assert.equal(controller.getSnapshot().preview?.accepted, true);
  assert.equal(controller.getSnapshot().error, null);
  assert.equal(backend.acceptances.length, 0);
});

test("a definitive acceptance refusal clears the reviewed invitation rather than offering a retry", async () => {
  const backend = new Backend();
  const controller = new InvitationController(backend, token, () => {});
  await controller.load();
  backend.acceptImpl = async () => {
    throw denied();
  };
  await controller.accept();
  assert.equal(controller.getSnapshot().preview, null);
  assert.equal(controller.getSnapshot().pending, null);
  assert.equal(controller.getSnapshot().busy, false);
  assert.equal(controller.getSnapshot().appId, null);
});

test("session expiry clears invitation account state and notifies the session owner", async () => {
  const backend = new Backend();
  let authFailures = 0;
  const controller = new InvitationController(backend, token, () => {
    authFailures++;
  });
  await controller.load();
  backend.acceptImpl = async () => {
    throw expired();
  };
  await controller.accept();
  assert.equal(authFailures, 1);
  assert.deepEqual(controller.getSnapshot(), {
    preview: null,
    pending: null,
    appId: null,
    busy: false,
    loading: false,
    error: null,
  });
});

test("account replacement fences late invitation previews, acceptances and auth failures", async () => {
  for (const response of ["preview", "acceptance", "auth-failure"] as const) {
    const backend = new Backend();
    let authFailures = 0;
    const registry = new SharingRegistry(
      backend,
      async () => token,
      () => {
        authFailures++;
      },
    );
    const controller = registry.invitation("account-a", token);
    const result = deferred<InvitationPreview | { appId: string }>();
    let pending: Promise<void>;
    if (response === "preview") {
      backend.inspectImpl = () => result.promise as Promise<InvitationPreview>;
      pending = controller.load();
    } else {
      await controller.load();
      backend.acceptImpl = () => result.promise as Promise<{ appId: string }>;
      pending = controller.accept();
    }
    registry.keepUser("account-b");
    if (response === "auth-failure") result.reject(expired());
    else result.resolve(response === "preview" ? preview : { appId: "app" });
    await pending;
    assert.equal(controller.getSnapshot().preview, null);
    assert.equal(controller.getSnapshot().appId, null);
    assert.equal(controller.getSnapshot().pending, null);
    assert.equal(
      authFailures,
      0,
      "an old account cannot expire a replacement session",
    );
    assert.notEqual(registry.invitation("account-b", token), controller);
  }
});

function appMetadata(
  role: MiniApp["role"] = "owner",
  archived = false,
): MiniApp {
  const value = app(role, archived);
  return {
    id: value.id,
    workspaceId: value.workspaceId,
    name: value.name,
    role: value.role,
    archived: value.archived,
    engine: "appspec.v1",
    capabilities: value.capabilities,
  };
}

test("sharing uses engine-neutral metadata for every full AppSpec role without fetching a bounded document", async () => {
  for (const role of ["owner", "builder", "member", "viewer"] as const) {
    const backend = new Backend();
    backend.getApp = async () => {
      throw new Error("Bounded parser must not run");
    };
    backend.getAppAccess = async () => appMetadata(role);
    const controller = new SharingController(
      backend,
      "app",
      async () => token,
      () => {},
    );
    await controller.load();
    assert.equal(controller.getSnapshot().app?.engine, "appspec.v1");
    assert.equal(controller.getSnapshot().app?.role, role);
    assert.equal(controller.getSnapshot().error, null);
    assert.equal(
      backend.invitationsRead,
      role === "owner" || role === "builder" ? 1 : 0,
    );
    assert.equal("definition" in controller.getSnapshot().app!, false);
    assert.equal("draft" in controller.getSnapshot().app!, false);
  }
});

test("the bounded sharing fallback keeps only metadata and never retains an author definition", async () => {
  const backend = new Backend();
  const controller = new SharingController(
    backend,
    "app",
    async () => token,
    () => {},
  );
  await controller.load();
  assert.equal(controller.getSnapshot().app?.name, "Private planner");
  assert.equal("definition" in controller.getSnapshot().app!, false);
  assert.equal("draftRevision" in controller.getSnapshot().app!, false);
});

test("archive receipt metadata is only an acknowledgement until a fresh authorized metadata read", async () => {
  const backend = new Backend(),
    fresh = deferred<MiniApp>(),
    started = deferred<void>();
  let reads = 0;
  backend.getApp = async () => {
    throw new Error("Bounded document must not be requested");
  };
  backend.getAppAccess = async () => {
    if (++reads === 1) return appMetadata();
    started.resolve();
    return fresh.promise;
  };
  backend.archiveAppAccess = async (command) => {
    backend.archives.push({ ...command });
    return {
      ...appMetadata("owner", true),
      name: "Historical title",
      workspaceId: "historical-workspace",
    };
  };
  const controller = new SharingController(
    backend,
    "app",
    async () => token,
    () => {},
  );
  await controller.load();
  const saving = controller.archive();
  await started.promise;
  assert.equal(controller.getSnapshot().app?.name, "Private planner");
  assert.equal(controller.getSnapshot().app?.workspaceId, "workspace");
  assert.equal(controller.getSnapshot().app?.archived, true);
  assert.equal(controller.getSnapshot().app?.capabilities?.share, false);
  assert.equal(controller.getSnapshot().pending, null);
  fresh.resolve({ ...appMetadata("owner", true), name: "Current title" });
  await saving;
  assert.equal(controller.getSnapshot().app?.name, "Current title");
  assert.equal(backend.archives.length, 1);
});

test("an uncertain full-app archive retains its exact envelope across metadata reload and explicit retry", async () => {
  const backend = new Backend();
  let archived = false;
  const commands: ArchiveApp[] = [];
  backend.getAppAccess = async () => appMetadata("owner", archived);
  backend.archiveAppAccess = async (command) => {
    commands.push({ ...command });
    archived = true;
    if (commands.length === 1) throw unknownResult();
    return appMetadata("owner", true);
  };
  const controller = new SharingController(
    backend,
    "app",
    async () => token,
    () => {},
  );
  await controller.load();
  await controller.archive();
  assert.equal(controller.getSnapshot().pending?.kind, "archive");
  await controller.load();
  assert.equal(commands.length, 1);
  assert.equal(controller.getSnapshot().app?.archived, true);
  await controller.retry();
  assert.deepEqual(commands[1], commands[0]);
  assert.equal(controller.getSnapshot().pending, null);
});

test("account disposal fences late metadata and prevents post-archive refresh from the old sharing controller", async () => {
  const backend = new Backend(),
    read = deferred<MiniApp>();
  let reads = 0;
  backend.getAppAccess = () => {
    reads++;
    return read.promise;
  };
  const registry = new SharingRegistry(
    backend,
    async () => token,
    () => {},
  );
  const controller = registry.get("a", "app"),
    loading = controller.load();
  registry.keepUser("b");
  read.resolve(appMetadata());
  await loading;
  assert.equal(controller.getSnapshot().app, null);
  assert.equal(backend.invitationsRead, 0);
  const current = registry.get("b", "app");
  backend.getAppAccess = async () => {
    reads++;
    return appMetadata();
  };
  await current.load();
  const ack = deferred<MiniApp>();
  backend.archiveAppAccess = () => ack.promise;
  const archiving = current.archive();
  registry.keepUser("c");
  const before = reads;
  ack.resolve(appMetadata("owner", true));
  await archiving;
  assert.equal(reads, before);
  assert.equal(current.getSnapshot().app, null);
});
