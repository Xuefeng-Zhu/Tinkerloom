import assert from "node:assert/strict";
import test from "node:test";
import type { AppBackend } from "../backend/types";
import { HostLifetime } from "../host/scope";
import type { HostScope } from "../host/scope";
import { hostStores } from "../host/storage";
import type { MediaPorts } from "../media/types";
import { GuardedReadCoordinator } from "../runtime/guardedReads";
import { RuntimeError } from "../runtime/errors";
import type { RuntimeTransport } from "../runtime/types";
import { NotificationsController } from "../notifications/NotificationsController";
import type { InboxItem } from "../notifications/contracts";
import { createLiveRuntime } from "./createLiveRuntime";
import { FullRegistry } from "./FullRegistry";
import { fullTemplates } from "./catalog";
import { platformCapabilities } from "./contracts";
import wire from "./fixtures/serviceWire.json";
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const spec = fullTemplates.find((t) => t.id === "projectHub")!.spec;
const manifest = {
  id: "app",
  workspaceId: "ws",
  name: spec.name,
  engine: "appspec.v1" as const,
  role: "owner" as const,
  archived: false,
  capabilities: { editDefinition: true },
  controlRevision: 1,
  allowedActions: spec.actions.map((a) => a.id),
  draft: null,
  generation: null,
  version: { id: "version_1", number: 1, hash: "hash", spec },
};
function host(input: HostScope) {
  const values = new Map<string, string>();
  return hostStores(new HostLifetime(input), {
    async read(k) {
      return values.get(k) ?? null;
    },
    async change(k, fn) {
      const v = fn(values.get(k) ?? null);
      if (v === null) values.delete(k);
      else values.set(k, v);
    },
  });
}
function deferred<T = unknown>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((yes) => {
    resolve = yes;
  });
  return { promise, resolve };
}
const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));
async function until(condition: () => boolean) {
  for (let i = 0; i < 200; i++) {
    if (condition()) return;
    await tick();
  }
  assert.fail("Expected startup read did not dispatch");
}
function response(r: Record<string, unknown>) {
  switch (r.op) {
    case "spec.getApp":
      return { app: { ...manifest, id: r.appId } };
    case "spec.capabilities":
      return wire.capabilities;
    case "spec.watch":
      return {
        appId: r.appId,
        versionId: "version_1",
        controlRevision: 1,
        role: "owner",
        archived: false,
      };
    case "spec.query":
      return {
        records: [],
        total: 0,
        nextCursor: null,
        versionId: "version_1",
      };
    case "spec.summary":
      return { total: 0, groups: { Open: 0, Done: 0 }, versionId: "version_1" };
    default:
      return {};
  }
}

test("FullRegistry startup baseline watch, manifest reload and runtime views share one account lane across apps", async () => {
  const original = new Map<string, PropertyDescriptor | undefined>();
  const events = { addEventListener() {}, removeEventListener() {} };
  for (const [key, value] of Object.entries({
    indexedDB: {},
    document: { ...events, visibilityState: "visible" },
    window: events,
    navigator: { onLine: true },
  })) {
    original.set(key, Object.getOwnPropertyDescriptor(globalThis, key));
    Object.defineProperty(globalThis, key, { value, configurable: true });
  }
  let active = 0,
    maximum = 0,
    ids = 0;
  const calls: Record<string, unknown>[] = [];
  const backend = {
    newId: () => {
      ids++;
      throw new Error("Read startup cannot allocate an operation ID");
    },
    executeSpec: async (r: Record<string, unknown>) => {
      calls.push(r);
      if (r.op === "spec.capabilities") return response(r);
      maximum = Math.max(maximum, ++active);
      try {
        await tick();
        return response(r);
      } finally {
        active--;
      }
    },
  } as unknown as AppBackend;
  const registry = new FullRegistry({
    backend,
    scope,
    readSession: () => ({ accountId: "alice", epoch: 1, active: true }),
    onUnauthenticated() {},
    hostFactory: host,
  });
  try {
    const app = registry.app("alice", "app"),
      other = registry.app("alice", "other");
    await Promise.all([app.load(), other.load()]);
    assert.ok(app.runtime && other.runtime);
    const release = app.acquireLiveLease(true);
    const reads = Promise.all([app.runtime.refresh(), other.runtime.refresh()]);
    await until(
      () =>
        calls.filter((r) => r.op === "spec.getApp" && r.appId === "app")
          .length >= 2 &&
        calls.filter((r) => r.op === "spec.query" && r.appId === "app")
          .length >= 2,
    );
    await reads;
    await app.runtime.refresh();
    release();
    assert.equal(maximum, 1);
    assert.equal(ids, 0);
    assert.ok(calls.some((r) => r.op === "spec.watch"));
    assert.equal(app.getSnapshot().error, null);
    assert.equal(app.runtime.getSnapshot().accessDenied, false);
    assert.ok(
      Object.values(app.runtime.getSnapshot().views).every((v) => !v.error),
    );
    assert.ok(calls.every((r) => !("isCurrent" in r) && !("context" in r)));
  } finally {
    registry.dispose();
    for (const [key, descriptor] of original) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else Reflect.deleteProperty(globalThis, key);
    }
  }
});

test("real live wrapper composition forwards all read fences and cancels a queued stopped watch", async () => {
  const lane = new GuardedReadCoordinator(),
    gate = deferred(),
    calls: string[] = [],
    queued: string[] = [];
  const execute = lane.transport(async (r) => {
    calls.push(String(r.op));
    if (r.op === "spec.getApp") return gate.promise;
    return response(r);
  });
  const transport: RuntimeTransport = (r, context) => {
    queued.push(String(r.op));
    return execute(r, context);
  };
  const root = host(scope);
  const ports: MediaPorts = {
    async sha256() {
      return "a".repeat(64);
    },
    async pick() {
      return null;
    },
    async image() {
      throw new Error("No image reads requested");
    },
    dispose() {},
  };
  const adapter = createLiveRuntime(
    manifest,
    transport,
    {
      host: root,
      platform: platformCapabilities({
        ...wire.capabilities,
        privateMedia: true,
      }),
    },
    {
      newId: () => {
        throw new Error("Reads cannot allocate IDs");
      },
      isCurrent: () => true,
      onManifestChange() {},
      onAccessFailure() {
        assert.fail("Superseded reads cannot revoke access");
      },
      createHostStorage: host,
      mediaPorts: ports,
      watchActivity: {
        getSnapshot: () => ({ foreground: true, online: true }),
        subscribe: () => () => {},
      },
    },
  );
  const stopped = adapter.watch(() => {});
  try {
    const block = transport({ op: "spec.getApp" });
    let current = true;
    const context = { isCurrent: () => current };
    const reads = [
      adapter.query("projects", {}, context),
      adapter.get("private_record", context),
      adapter.summary("projects", {}, "status", context),
      adapter.aggregate("projects", {}, { metric: "count" }, context),
    ];
    const assertions = reads.map((p) =>
      assert.rejects(
        p,
        (e: unknown) =>
          e instanceof RuntimeError && e.code === "superseded_read",
      ),
    );
    adapter.setActive?.(true);
    await until(() => queued.includes("spec.watch"));
    adapter.setActive?.(false);
    current = false;
    gate.resolve({});
    await Promise.all([block, ...assertions]);
    await tick();
    assert.deepEqual(calls, ["spec.getApp"]);
  } finally {
    stopped();
    adapter.dispose();
    root.lifetime.dispose();
    lane.dispose();
  }
});

test("inbox target replacement and disposal cancel queued record reads while the app remains retained", async () => {
  for (const operation of ["replace", "dispose"] as const) {
    const lane = new GuardedReadCoordinator(),
      gate = deferred(),
      calls: Record<string, unknown>[] = [];
    const transport = lane.transport(async (r) => {
      calls.push(r);
      if (r.op === "spec.getApp") return gate.promise;
      if (r.op === "spec.getRecord")
        return {
          versionId: "version_1",
          record: {
            id: r.recordId,
            collectionId: "projects",
            data: { title: "Current", status: "Open" },
            revision: 1,
            writtenUnderVersionId: "version_1",
            capacity: null,
            allocated: null,
            claimed: false,
            allowedActions: [],
          },
        };
      return {};
    });
    const adapter = createLiveRuntime(
      manifest,
      transport,
      { host: host(scope), platform: null },
      {
        newId: () => "unused",
        isCurrent: () => true,
        onManifestChange() {},
        onAccessFailure() {},
        createHostStorage: host,
      },
    );
    const items: InboxItem[] = ["one", "two"].map((id) => ({
      id,
      appId: "app",
      runId: `run_${id}`,
      recordId: `record_${id}`,
      collectionId: "projects",
      title: "Task",
      body: "Open",
      createdAt: "2030-01-01T00:00:00Z",
      isRead: false,
    }));
    const inbox = new NotificationsController({
      scope,
      host: host({ ...scope, appId: "inbox" }),
      newId: () => "unused",
      transport: async () => ({ items, nextCursor: null }),
    });
    await inbox.load();
    const blocked = transport({ op: "spec.getApp" });
    const old = inbox.verifyTarget(items[0], async () => adapter);
    await tick();
    const latest =
      operation === "replace"
        ? inbox.verifyTarget(items[1], async () => adapter)
        : Promise.resolve(null);
    if (operation === "dispose") inbox.dispose();
    await tick();
    gate.resolve({});
    const [obsolete, result] = await Promise.all([old, latest]);
    await blocked;
    assert.equal(obsolete, null);
    assert.equal(
      result?.recordId ?? null,
      operation === "replace" ? "record_two" : null,
    );
    assert.deepEqual(
      calls.filter((r) => r.op === "spec.getRecord").map((r) => r.recordId),
      operation === "replace" ? ["record_two"] : [],
    );
    inbox.dispose();
    adapter.dispose();
    lane.dispose();
  }
});

test("registry host sequences and lifetime disposal drop queued manifests before SDK dispatch", async () => {
  for (const action of ["supersede", "dispose"] as const) {
    const gate = deferred(),
      calls: Record<string, unknown>[] = [];
    const backend = {
      newId: () => "unused",
      executeSpec: async (r: Record<string, unknown>) => {
        calls.push(r);
        if (r.op === "spec.getApp" && r.appId === "blocking")
          await gate.promise;
        return r.op === "spec.getApp"
          ? { app: { ...manifest, id: r.appId, version: null } }
          : wire.capabilities;
      },
    } as unknown as AppBackend;
    const registry = new FullRegistry({
      backend,
      scope,
      readSession: () => ({ accountId: "alice", epoch: 1, active: true }),
      onUnauthenticated() {},
      hostFactory: host,
    });
    const blocking = registry.app("alice", "blocking"),
      app = registry.app("alice", "app");
    const held = blocking.load();
    await until(() => calls.length === 1);
    const old = app.load();
    await tick();
    const latest = action === "supersede" ? app.load() : Promise.resolve();
    if (action === "dispose") app.dispose();
    gate.resolve({});
    await Promise.all([held, old, latest]);
    assert.equal(
      calls.filter((r) => r.op === "spec.getApp" && r.appId === "app").length,
      action === "supersede" ? 1 : 0,
    );
    if (action === "supersede") assert.equal(app.getSnapshot().app?.id, "app");
    registry.dispose();
  }
});
