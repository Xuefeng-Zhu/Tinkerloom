import assert from "node:assert/strict";
import test from "node:test";
import type { AppBackend, MiniApp } from "../backend/types";
import { AppwriteBackend, type SdkAdapter } from "../backend/core";
import { BackendError } from "../backend/errors";
import { AppController } from "./controller";
const user = { id: "alice", email: "alice@example.test", name: "Alice" };
const apps = (workspaceId: string): MiniApp[] => [
  { id: `${workspaceId}_app`, workspaceId, name: "App" },
];
const conflict = () =>
  new BackendError(
    "This app changed. Refresh it before saving again.",
    "definition_conflict",
    "service",
    false,
    409,
  );
const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));
async function until(fn: () => boolean) {
  for (let i = 0; i < 200; i++) {
    if (fn()) return;
    await tick();
  }
  assert.fail("Expected catalogue read did not start");
}
function fixture() {
  const calls: string[] = [];
  let ids = 0,
    writes = 0;
  let read: (workspaceId: string) => Promise<MiniApp[]> = async (workspaceId) =>
    apps(workspaceId);
  const backend = {
    currentUser: async () => user,
    signIn: async () => user,
    signOut: async () => {},
    listWorkspaces: async () => [
      { id: "alpha", name: "Alpha" },
      { id: "beta", name: "Beta" },
    ],
    listApps: (workspaceId: string) => {
      calls.push(workspaceId);
      return read(workspaceId);
    },
    newId: () => {
      ids++;
      return "write_id";
    },
    createApp: async () => {
      writes++;
      throw conflict();
    },
  } as unknown as AppBackend;
  return {
    controller: new AppController(backend),
    calls,
    setRead(fn: typeof read) {
      read = fn;
    },
    get ids() {
      return ids;
    },
    get writes() {
      return writes;
    },
  };
}

test("home refresh and workspace selection recover only definite catalogue snapshot conflicts with the captured workspace", async () => {
  const f = fixture();
  await f.controller.bootstrap();
  for (const action of ["refresh", "selection"] as const) {
    let attempts = 0;
    f.calls.length = 0;
    f.setRead(async (id) => {
      if (attempts++ < 2) throw conflict();
      return apps(id);
    });
    if (action === "refresh") await f.controller.refresh();
    else await f.controller.selectWorkspace("beta");
    const workspace = action === "refresh" ? "alpha" : "beta";
    assert.deepEqual(f.calls, [workspace, workspace, workspace]);
    assert.deepEqual(f.controller.getSnapshot().apps, apps(workspace));
    assert.equal(f.controller.getSnapshot().error, null);
    assert.equal(f.controller.getSnapshot().loading, false);
  }
  assert.equal(f.ids, 0);
  assert.equal(f.writes, 0);
  f.controller.dispose();
});

test("catalogue conflict exhaustion stays visible after three attempts", async () => {
  const f = fixture();
  await f.controller.bootstrap();
  f.calls.length = 0;
  f.setRead(async () => {
    throw conflict();
  });
  await f.controller.refresh();
  assert.deepEqual(f.calls, ["alpha", "alpha", "alpha"]);
  assert.equal(f.controller.getSnapshot().error, conflict().message);
  assert.deepEqual(f.controller.getSnapshot().apps, []);
  assert.equal(f.controller.getSnapshot().loading, false);
  f.controller.dispose();
});

test("uncertain, generic, revision, transport and authorization errors never enter the catalogue retry path", async () => {
  for (const error of [
    new BackendError("Unknown", "definition_conflict", "service", true, 409),
    new BackendError(
      "Wrong status",
      "definition_conflict",
      "service",
      false,
      400,
    ),
    new BackendError(
      "Wrong kind",
      "definition_conflict",
      "transport",
      false,
      409,
    ),
    new BackendError("Revision", "revision_conflict", "service", false, 409),
    new BackendError(
      "Transaction",
      "transaction_conflict",
      "service",
      false,
      409,
    ),
    new BackendError("Denied", "forbidden", "service", false, 403),
    new BackendError("Missing", "not_found", "service", false, 404),
    new BackendError(
      "Expired",
      "unauthenticated",
      "unauthenticated",
      false,
      401,
    ),
    new Error("definition_conflict"),
  ]) {
    const f = fixture();
    await f.controller.bootstrap();
    f.calls.length = 0;
    f.setRead(async () => {
      throw error;
    });
    await f.controller.refresh();
    assert.deepEqual(f.calls, ["alpha"]);
    assert.equal(
      f.controller.getSnapshot().phase,
      error instanceof BackendError && error.kind === "unauthenticated"
        ? "signedOut"
        : "signedIn",
    );
    assert.ok(f.controller.getSnapshot().error);
    f.controller.dispose();
  }
});

test("catalogue backoff rechecks selection, refresh, sign-out, same-account reauthentication and disposal before another SDK call", async () => {
  for (const action of [
    "selection",
    "refresh",
    "signOut",
    "reauthenticate",
    "expire",
    "dispose",
  ] as const) {
    const f = fixture();
    await f.controller.bootstrap();
    f.calls.length = 0;
    let rejectOnce = true;
    f.setRead(async (id) => {
      if (rejectOnce) {
        rejectOnce = false;
        throw conflict();
      }
      return apps(id);
    });
    const old = f.controller.refresh();
    await until(() => f.calls.length === 1);
    let latest = Promise.resolve();
    if (action === "selection") latest = f.controller.selectWorkspace("beta");
    if (action === "refresh") latest = f.controller.refresh();
    if (action === "signOut") latest = f.controller.signOut();
    if (action === "reauthenticate")
      latest = f.controller.authenticate(
        "signIn",
        "alice@example.test",
        "synthetic-password",
      );
    if (action === "expire") f.controller.expireSession();
    if (action === "dispose") f.controller.dispose();
    await Promise.all([old, latest]);
    assert.deepEqual(
      f.calls,
      action === "selection"
        ? ["alpha", "beta"]
        : action === "refresh" || action === "reauthenticate"
          ? ["alpha", "alpha"]
          : ["alpha"],
    );
    if (action === "selection")
      assert.deepEqual(f.controller.getSnapshot().apps, apps("beta"));
    if (action === "signOut" || action === "expire")
      assert.deepEqual(f.controller.getSnapshot().apps, []);
    f.controller.dispose();
  }
});

test("a definite creation conflict stays a single write and does not use catalogue read retry", async () => {
  const f = fixture();
  await f.controller.bootstrap();
  f.controller.openCreation("app");
  await f.controller.submitCreation("Synthetic shell");
  assert.equal(f.writes, 1);
  assert.equal(f.ids, 1);
  assert.equal(f.controller.getSnapshot().creation?.error, conflict().message);
  f.controller.dispose();
});

test("actual AppwriteBackend classifies listApps definition conflict as a definite read for bounded home recovery", async () => {
  const wires: string[] = [];
  let attempts = 0;
  const sdk: SdkAdapter = {
    account: {
      get: async () => ({ $id: user.id, email: user.email, name: user.name }),
      create: async () => null,
      createEmailPasswordSession: async () => null,
      deleteSession: async () => null,
    },
    newId: () => {
      throw new Error("Read recovery cannot allocate IDs");
    },
    execute: async (body) => {
      wires.push(body);
      const input = JSON.parse(body);
      let value: unknown;
      let status = 200;
      if (input.op === "listWorkspaces")
        value = { workspaces: [{ id: "alpha", name: "Alpha", role: "owner" }] };
      else if (attempts++ < 2) {
        value = { error: "definition_conflict" };
        status = 409;
      } else
        value = {
          apps: [
            {
              ...apps("alpha")[0],
              engine: "appspec.v1",
              role: "owner",
              archived: false,
              capabilities: {
                editDefinition: true,
                share: true,
                writeRecords: true,
                archive: true,
                revokeAccess: true,
              },
            },
          ],
        };
      return {
        status: "completed",
        responseStatusCode: status,
        responseBody: JSON.stringify(value),
      };
    },
  };
  const controller = new AppController(new AppwriteBackend(sdk));
  await controller.bootstrap();
  assert.equal(controller.getSnapshot().error, null);
  assert.equal(controller.getSnapshot().apps[0]?.id, "alpha_app");
  assert.deepEqual(
    wires.slice(1),
    Array(3).fill(JSON.stringify({ op: "listApps", workspaceId: "alpha" })),
  );
  controller.dispose();
});
