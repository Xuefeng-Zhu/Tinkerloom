import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import type {
  AppBackend,
  CreateApp,
  CreateWorkspace,
  MiniApp,
  User,
  Workspace,
} from "../backend/types";
import { AppController } from "./controller";

const user: User = { id: "owner", email: "owner@example.test", name: "Owner" };
const workspaces: Workspace[] = [
  { id: "alpha", name: "Everyday" },
  { id: "beta", name: "Projects" },
];
const app = (id: string, workspaceId: string): MiniApp => ({
  id,
  workspaceId,
  name: id,
});

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((accept, fail) => {
    resolve = accept;
    reject = fail;
  });
  return { promise, resolve, reject };
}

class FakeBackend implements AppBackend {
  generatedIds = 0;
  appCommands: CreateApp[] = [];
  workspaceCommands: CreateWorkspace[] = [];
  listWorkspacesImpl = async (): Promise<Workspace[]> => workspaces;
  listAppsImpl = async (workspaceId: string): Promise<MiniApp[]> => [
    app(`${workspaceId}-app`, workspaceId),
  ];
  createAppImpl = async (_command: CreateApp): Promise<void> => {};
  createWorkspaceImpl = async (_command: CreateWorkspace): Promise<void> => {};

  newId() {
    this.generatedIds++;
    return `request-${this.generatedIds}`;
  }
  async currentUser() {
    return user;
  }
  async signIn(_email: string, _password: string) {
    return user;
  }
  async signUp(_email: string, _password: string, _name: string) {
    return user;
  }
  async signOut() {}
  listWorkspaces() {
    return this.listWorkspacesImpl();
  }
  listApps(workspaceId: string) {
    return this.listAppsImpl(workspaceId);
  }
  createWorkspace(command: CreateWorkspace) {
    this.workspaceCommands.push({ ...command });
    return this.createWorkspaceImpl(command);
  }
  createApp(command: CreateApp) {
    this.appCommands.push({ ...command });
    return this.createAppImpl(command);
  }
}

test("a lost creation response keeps its ID, name, and original workspace after close and reopen", async () => {
  const backend = new FakeBackend();
  backend.createAppImpl = async () => {
    if (backend.appCommands.length === 1) {
      throw new BackendError(
        "The result is unknown.",
        "connection_failed",
        "transport",
        true,
      );
    }
  };
  const controller = new AppController(backend);
  await controller.bootstrap();
  controller.openCreation("app");
  await controller.submitCreation("  Garden notes  ");
  const original = {
    id: "request-1",
    name: "Garden notes",
    workspaceId: "alpha",
  };
  assert.deepEqual(controller.getSnapshot().creation?.command, original);
  assert.equal(controller.getSnapshot().creation?.busy, false);

  controller.closeCreation();
  assert.equal(controller.getSnapshot().creation?.open, false);
  await controller.selectWorkspace("beta");
  controller.openCreation("app");
  assert.equal(controller.getSnapshot().workspaceId, "beta");
  assert.deepEqual(controller.getSnapshot().creation?.command, original);
  assert.equal(controller.getSnapshot().creation?.open, true);

  await controller.submitCreation("Replacement name");
  assert.deepEqual(backend.appCommands, [original, original]);
  assert.equal(backend.generatedIds, 1);
  assert.equal(controller.getSnapshot().creation, null);
  assert.equal(controller.getSnapshot().workspaceId, "beta");
  assert.deepEqual(controller.getSnapshot().apps, [app("beta-app", "beta")]);
});

test("a workspace creation retry also retains the original request after closing", async () => {
  const backend = new FakeBackend();
  backend.createWorkspaceImpl = async () => {
    if (backend.workspaceCommands.length === 1)
      throw new Error("Connection dropped after commit");
  };
  const controller = new AppController(backend);
  await controller.bootstrap();
  controller.openCreation("workspace");
  await controller.submitCreation("Our home");
  controller.closeCreation();
  controller.openCreation("app");
  assert.equal(controller.getSnapshot().creation?.kind, "workspace");
  await controller.submitCreation("A different workspace");
  assert.deepEqual(backend.workspaceCommands, [
    { id: "request-1", name: "Our home" },
    { id: "request-1", name: "Our home" },
  ]);
  assert.equal(backend.appCommands.length, 0);
});

test("a slower prior workspace response cannot replace the current workspace apps", async () => {
  const backend = new FakeBackend();
  const controller = new AppController(backend);
  await controller.bootstrap();
  const earlier = deferred<MiniApp[]>();
  const current = deferred<MiniApp[]>();
  backend.listAppsImpl = (workspaceId) =>
    workspaceId === "alpha" ? earlier.promise : current.promise;

  const alphaRequest = controller.selectWorkspace("alpha");
  const betaRequest = controller.selectWorkspace("beta");
  current.resolve([app("current-result", "beta")]);
  await betaRequest;
  earlier.resolve([app("stale-result", "alpha")]);
  await alphaRequest;

  assert.equal(controller.getSnapshot().workspaceId, "beta");
  assert.deepEqual(controller.getSnapshot().apps, [
    app("current-result", "beta"),
  ]);
  assert.equal(controller.getSnapshot().loading, false);
  assert.equal(controller.getSnapshot().error, null);
});

test("a stale workspace failure cannot clear or add an error to the current selection", async () => {
  const backend = new FakeBackend();
  const controller = new AppController(backend);
  await controller.bootstrap();
  const earlier = deferred<MiniApp[]>();
  backend.listAppsImpl = async (workspaceId) =>
    workspaceId === "alpha" ? earlier.promise : [app("new-result", "beta")];
  const alphaRequest = controller.selectWorkspace("alpha");
  await controller.selectWorkspace("beta");
  earlier.reject(
    new BackendError("Old request failed.", "connection_failed", "transport"),
  );
  await alphaRequest;

  assert.equal(controller.getSnapshot().workspaceId, "beta");
  assert.deepEqual(controller.getSnapshot().apps, [app("new-result", "beta")]);
  assert.equal(controller.getSnapshot().error, null);
});

test("an app response arriving after signout cannot repopulate account state", async () => {
  const backend = new FakeBackend();
  const controller = new AppController(backend);
  await controller.bootstrap();
  const pending = deferred<MiniApp[]>();
  backend.listAppsImpl = () => pending.promise;
  const request = controller.selectWorkspace("beta");
  await controller.signOut();
  pending.resolve([app("late-private-app", "beta")]);
  await request;

  const state = controller.getSnapshot();
  assert.equal(state.phase, "signedOut");
  assert.equal(state.user, null);
  assert.deepEqual(state.workspaces, []);
  assert.equal(state.workspaceId, null);
  assert.deepEqual(state.apps, []);
  assert.equal(state.loading, false);
});

test("definitive authentication expiry clears all account and retained-command state", async () => {
  const backend = new FakeBackend();
  const controller = new AppController(backend);
  await controller.bootstrap();
  backend.createAppImpl = async () => {
    throw new BackendError(
      "Unknown result.",
      "connection_failed",
      "transport",
      true,
    );
  };
  controller.openCreation("app");
  await controller.submitCreation("Private notes");
  assert.ok(controller.getSnapshot().creation?.command);
  backend.listWorkspacesImpl = async () => {
    throw new BackendError(
      "Please sign in again.",
      "user_unauthorized",
      "unauthenticated",
      false,
      401,
    );
  };
  await controller.refresh();

  const state = controller.getSnapshot();
  assert.equal(state.phase, "signedOut");
  assert.equal(state.user, null);
  assert.deepEqual(state.workspaces, []);
  assert.deepEqual(state.apps, []);
  assert.equal(state.workspaceId, null);
  assert.equal(state.creation, null);
  assert.equal(state.loading, false);
  assert.equal(state.authBusy, false);
  assert.match(state.error ?? "", /session has expired/i);
});

test("an explicit session check can recover a transient startup failure without creating a new session", async () => {
  const backend = new FakeBackend();
  let signIns = 0;
  backend.signIn = async () => {
    signIns++;
    return user;
  };
  backend.currentUser = async () => {
    throw new BackendError(
      "Connection unavailable.",
      "connection_failed",
      "transport",
    );
  };
  const controller = new AppController(backend);
  await controller.bootstrap();
  assert.equal(controller.getSnapshot().phase, "signedOut");
  assert.ok(controller.getSnapshot().error);
  backend.currentUser = async () => user;
  await controller.bootstrap();
  assert.equal(controller.getSnapshot().phase, "signedIn");
  assert.deepEqual(controller.getSnapshot().user, user);
  assert.equal(controller.getSnapshot().error, null);
  assert.equal(signIns, 0);
});
