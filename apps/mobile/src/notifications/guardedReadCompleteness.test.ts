import assert from "node:assert/strict";
import test from "node:test";
import type { AppBackend } from "../backend/types";
import { BackendError } from "../backend/errors";
import { ActivityController } from "../activity/ActivityController";
import { FullRegistry } from "../full/FullRegistry";
import { createLiveRuntime } from "../full/createLiveRuntime";
import { fullTemplates } from "../full/catalog";
import { platformCapabilities } from "../full/contracts";
import wire from "../full/fixtures/serviceWire.json";
import { HostLifetime } from "../host/scope";
import type { HostScope } from "../host/scope";
import { hostStores } from "../host/storage";
import type { MediaPorts } from "../media/types";
import { RuntimeError } from "../runtime/errors";
import { GuardedReadCoordinator } from "../runtime/guardedReads";
import type { RuntimeTransport } from "../runtime/types";
import { NotificationsController } from "./NotificationsController";
import { AutomationRunsController } from "./AutomationRunsController";
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const spec = fullTemplates.find((t) => t.id === "chores")!.spec;
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
const stale = (e: unknown) =>
  e instanceof RuntimeError && e.code === "superseded_read";
function response(r: Record<string, unknown>) {
  switch (r.op) {
    case "spec.reminderState":
      return {
        versionId: "version_1",
        states: [
          {
            ruleId: "dueReminder",
            state: "unset",
            scheduledAt: null,
            eligible: false,
            recipientCount: 0,
          },
        ],
      };
    case "spec.query":
      return {
        versionId: "version_1",
        records: [],
        total: 0,
        nextCursor: null,
      };
    case "spec.getApp":
      return { app: { ...manifest, version: null } };
    case "spec.capabilities":
      return wire.capabilities;
    case "spec.runs":
      return { runs: [], nextCursor: null };
    case "spec.inbox":
      return { items: [], nextCursor: null };
    case "listMembers":
      return {
        members: [{ actorId: "alice", role: "owner", revision: 1 }],
        nextCursor: null,
      };
    case "spec.listActivity":
      return { appId: "app", items: [], nextCursor: null };
    default:
      return {};
  }
}
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
function runtime(transport: RuntimeTransport) {
  const root = host(scope);
  const adapter = createLiveRuntime(
    manifest,
    transport,
    {
      host: root,
      platform: platformCapabilities({
        ...wire.capabilities,
        effects: ["notifyAssignee"],
        privateMedia: true,
      }),
    },
    {
      newId: () => {
        throw new Error("Read status cannot allocate IDs");
      },
      isCurrent: () => true,
      onManifestChange() {},
      onAccessFailure() {},
      createHostStorage: host,
      mediaPorts: ports,
    },
  );
  return {
    adapter,
    root,
    dispose() {
      adapter.dispose();
      root.lifetime.dispose();
    },
  };
}

test("all twenty-one guard-staging and observing reads share the lane while unrelated operations bypass", async () => {
  const ops = [
    "spec.getApp",
    "spec.getRecord",
    "spec.review",
    "spec.query",
    "spec.summary",
    "spec.aggregate",
    "spec.listVersions",
    "spec.getVersion",
    "spec.watch",
    "spec.getGeneration",
    "spec.reminderState",
    "spec.runs",
    "spec.listActivity",
    "spec.appAccess",
    "spec.launcher",
    "spec.listDrafts",
    "spec.inbox",
    "listMembers",
    "spec.media.status",
    "spec.media.read",
    "spec.media.usage",
  ];
  const lane = new GuardedReadCoordinator(),
    gate = deferred(),
    calls: string[] = [];
  const transport = lane.transport(async (r) => {
    calls.push(String(r.op));
    if (r.op === "spec.getApp") return gate.promise;
    return {};
  });
  const queued = ops.map((op) => transport({ op, appId: "app" }));
  for (const op of [
    "spec.execute",
    "spec.readNotification",
    "spec.publish",
    "spec.guidance",
    "spec.unknown",
  ])
    await transport({ op });
  assert.deepEqual(calls.slice(1), [
    "spec.execute",
    "spec.readNotification",
    "spec.publish",
    "spec.guidance",
    "spec.unknown",
  ]);
  gate.resolve({});
  await Promise.all(queued);
  assert.deepEqual(calls.slice(6), ops.slice(1));
  lane.dispose();
});

test("real watch/reminder/media wrapper composition serializes peer card statuses with runtime queries", async () => {
  const lane = new GuardedReadCoordinator(),
    calls: Record<string, unknown>[] = [];
  let active = 0,
    maximum = 0;
  const transport = lane.transport(async (r) => {
    calls.push(r);
    maximum = Math.max(maximum, ++active);
    try {
      await tick();
      return response(r);
    } finally {
      active--;
    }
  });
  const f = runtime(transport);
  try {
    const statuses = Array.from({ length: 50 }, (_, i) =>
      f.adapter.reminderState(`record_${i}`),
    );
    const query = f.adapter.query("chores", {});
    const results = await Promise.all(statuses);
    await query;
    assert.equal(maximum, 1);
    assert.equal(results.length, 50);
    assert.ok(
      results.every((r) => r.label === "dueReminder: No reminder timestamp"),
    );
    assert.equal(calls.filter((r) => r.op === "spec.reminderState").length, 50);
    assert.equal(calls.filter((r) => r.op === "spec.query").length, 1);
    assert.ok(calls.every((r) => !("isCurrent" in r) && !("context" in r)));
  } finally {
    f.dispose();
    lane.dispose();
  }
});

test("removed card scope, runtime disposal and parent lifetime cancel queued reminder statuses with zero SDK calls", async () => {
  for (const action of ["removed", "disposed", "lifetime"] as const) {
    const lane = new GuardedReadCoordinator(),
      gate = deferred(),
      calls: string[] = [];
    const transport = lane.transport(async (r) => {
      calls.push(String(r.op));
      if (r.op === "spec.getApp") return gate.promise;
      return response(r);
    });
    const f = runtime(transport);
    const block = transport({ op: "spec.getApp" });
    let active = true;
    const status = f.adapter.reminderState("private_record", {
      isCurrent: () => active,
    });
    const rejected = assert.rejects(status, stale);
    if (action === "removed") active = false;
    if (action === "disposed") f.adapter.dispose();
    if (action === "lifetime") f.root.lifetime.dispose();
    gate.resolve({});
    await Promise.all([block, rejected]);
    assert.deepEqual(calls, ["spec.getApp"]);
    f.dispose();
    lane.dispose();
  }
});

test("reminder status failures remain definite single reads and do not replay side effects", async () => {
  for (const [code, status] of [
    ["transaction_conflict", 409],
    ["forbidden", 403],
    ["not_found", 404],
  ] as const) {
    const lane = new GuardedReadCoordinator();
    let calls = 0;
    const transport = lane.transport(async () => {
      calls++;
      throw new BackendError("Unavailable", code, "service", false, status);
    });
    const f = runtime(transport);
    await assert.rejects(
      f.adapter.reminderState("record"),
      (e: unknown) =>
        e instanceof BackendError && e.code === code && !e.uncertain,
    );
    assert.equal(calls, 1);
    f.dispose();
    lane.dispose();
  }
});

test("run history supersession and disposal fence newly queued reads", async () => {
  for (const action of ["supersede", "dispose"] as const) {
    const lane = new GuardedReadCoordinator(),
      gate = deferred(),
      calls: Record<string, unknown>[] = [],
      lifetime = new HostLifetime(scope);
    const transport = lane.transport(async (r) => {
      calls.push(r);
      if (r.op === "spec.getApp") return gate.promise;
      return response(r);
    });
    const controller = new AutomationRunsController({
      appId: "app",
      lifetime,
      transport,
    });
    const block = transport({ op: "spec.getApp" });
    const old = controller.load();
    const latest =
      action === "supersede" ? controller.load() : Promise.resolve();
    if (action === "dispose") lifetime.dispose();
    gate.resolve({});
    await Promise.all([block, old, latest]);
    assert.equal(
      calls.filter((r) => r.op === "spec.runs").length,
      action === "supersede" ? 1 : 0,
    );
    controller.dispose();
    lifetime.dispose();
    lane.dispose();
  }
});

test("registry activity and run history share manifest lane with session, cancel and disposal fences", async () => {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "indexedDB");
  Object.defineProperty(globalThis, "indexedDB", {
    value: {},
    configurable: true,
  });
  try {
    for (const action of ["current", "cancel", "dispose", "session"] as const) {
      const gate = deferred(),
        calls: Record<string, unknown>[] = [];
      let session = { accountId: "alice", epoch: 1, active: true };
      const backend = {
        newId: () => {
          throw new Error("No write identity");
        },
        executeSpec: async (r: Record<string, unknown>) => {
          calls.push(r);
          if (r.op === "spec.getApp") await gate.promise;
          return response(r);
        },
      } as unknown as AppBackend;
      const registry = new FullRegistry({
        backend,
        scope,
        readSession: () => session,
        onUnauthenticated() {},
        hostFactory: host,
      });
      const transport = registry.activityTransport("alice");
      assert.throws(
        () => transport({ op: "spec.publish" }),
        (e: unknown) =>
          e instanceof RuntimeError && e.code === "invalid_request",
      );
      const activity = new ActivityController({
        appId: "app",
        accountId: "alice",
        epoch: 1,
        transport,
        readSession: () => session,
        subscribeSession: () => () => {},
      });
      const app = registry.app("alice", "app");
      const held = app.load();
      await tick();
      const read = activity.load();
      const runs = registry.notifications("alice").runs("app");
      const history = runs.load();
      await tick();
      assert.deepEqual(
        calls.map((r) => r.op),
        ["spec.getApp"],
      );
      if (action === "cancel") activity.cancelRead();
      if (action === "dispose") {
        activity.dispose();
        runs.dispose();
      }
      if (action === "session") {
        session = { accountId: "alice", epoch: 2, active: true };
        registry.syncSession();
      }
      gate.resolve({});
      await Promise.all([held, read, history]);
      assert.equal(
        calls.filter((r) => r.op === "spec.listActivity").length,
        action === "current" ? 1 : 0,
      );
      assert.equal(
        calls.filter((r) => r.op === "spec.runs").length,
        action === "current" || action === "cancel" ? 1 : 0,
      );
      if (action === "current") {
        assert.equal(activity.getSnapshot().error, null);
        assert.equal(runs.getSnapshot().error, null);
      }
      activity.dispose();
      registry.dispose();
    }
  } finally {
    if (descriptor) Object.defineProperty(globalThis, "indexedDB", descriptor);
    else Reflect.deleteProperty(globalThis, "indexedDB");
  }
});

test("member field cleanup cancels queued directory reads through all wrappers before SDK dispatch", async () => {
  const lane = new GuardedReadCoordinator(),
    gate = deferred(),
    calls: Record<string, unknown>[] = [];
  const transport = lane.transport(async (r) => {
    calls.push(r);
    if (r.op === "spec.getApp") return gate.promise;
    return response(r);
  });
  const f = runtime(transport);
  const block = transport({ op: "spec.getApp" });
  let current = true;
  const obsolete = assert.rejects(
    f.adapter.members({ isCurrent: () => current }),
    stale,
  );
  const latest = f.adapter.members({ isCurrent: () => true });
  current = false;
  gate.resolve({});
  const [, , members] = await Promise.all([block, obsolete, latest]);
  assert.deepEqual(members, [{ id: "alice", label: "alice (owner)" }]);
  assert.equal(calls.filter((r) => r.op === "listMembers").length, 1);
  f.dispose();
  lane.dispose();
});

test("inbox observer shares the registry lane and cancels superseded or disposed queued pages", async () => {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "indexedDB");
  Object.defineProperty(globalThis, "indexedDB", {
    value: {},
    configurable: true,
  });
  try {
    for (const action of ["supersede", "dispose"] as const) {
      const gate = deferred(),
        calls: Record<string, unknown>[] = [];
      const backend = {
        newId: () => "unused",
        executeSpec: async (r: Record<string, unknown>) => {
          calls.push(r);
          if (r.op === "spec.getApp") await gate.promise;
          return response(r);
        },
      } as unknown as AppBackend;
      const registry = new FullRegistry({
        backend,
        scope,
        readSession: () => ({ accountId: "alice", epoch: 1, active: true }),
        onUnauthenticated() {},
        hostFactory: host,
      });
      const transport = registry.notifications("alice").inbox.options.transport;
      const inbox = new NotificationsController({
        scope,
        transport,
        host: host({ ...scope, appId: "inbox" }),
        newId: () => "unused",
      });
      const block = registry.app("alice", "app").load();
      await tick();
      const old = inbox.load();
      const latest = action === "supersede" ? inbox.load() : Promise.resolve();
      if (action === "dispose") inbox.dispose();
      assert.deepEqual(
        calls.map((r) => r.op),
        ["spec.getApp"],
      );
      gate.resolve({});
      await Promise.all([block, old, latest]);
      assert.equal(
        calls.filter((r) => r.op === "spec.inbox").length,
        action === "supersede" ? 1 : 0,
      );
      if (action === "supersede") assert.equal(inbox.getSnapshot().error, null);
      inbox.dispose();
      registry.dispose();
    }
  } finally {
    if (descriptor) Object.defineProperty(globalThis, "indexedDB", descriptor);
    else Reflect.deleteProperty(globalThis, "indexedDB");
  }
});
