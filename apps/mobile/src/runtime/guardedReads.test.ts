import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import { accountTransport } from "../full/FullRegistry";
import { fullTemplates } from "../full/catalog";
import { decodeAppSpec } from "../spec/decode";
import { RuntimeController } from "./controller";
import { FunctionRuntimeAdapter } from "./functionAdapter";
import { GuardedReadCoordinator } from "./guardedReads";
import { RuntimeError } from "./errors";
import type { RuntimeTransport } from "./types";

function deferred<T = unknown>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((yes) => {
    resolve = yes;
  });
  return { promise, resolve };
}
const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));
const stale = (error: unknown) =>
  error instanceof RuntimeError && error.code === "superseded_read";
const template = fullTemplates.find((t) => t.id === "projectHub")!.spec;
const spec = decodeAppSpec({
  ...template,
  views: template.views.map((v) =>
    v.id === "taskBoard" ? { ...v, filterFieldIds: ["status"] } : v,
  ),
});
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
  version: { id: "version_1", number: 1, hash: "hash", spec },
};
function empty(input: Record<string, unknown>) {
  if (input.op === "spec.query")
    return { records: [], total: 0, nextCursor: null, versionId: "version_1" };
  if (input.op === "spec.summary")
    return { total: 0, groups: { Open: 0, Done: 0 }, versionId: "version_1" };
  return {};
}

test("shared FIFO prevents same-workspace cross-app read overlap and captures immutable JSON before waiting", async () => {
  const lane = new GuardedReadCoordinator(),
    first = deferred(),
    calls: Record<string, unknown>[] = [];
  let active = 0,
    maximum = 0;
  const transport = lane.transport(async (request) => {
    calls.push(request);
    maximum = Math.max(maximum, ++active);
    try {
      if (calls.length === 1) await first.promise;
      return request;
    } finally {
      active--;
    }
  });
  const one = transport({ op: "spec.watch", appId: "one" });
  const input = {
    op: "spec.query",
    appId: "two",
    query: { filters: [{ fieldId: "status", op: "eq", value: "Open" }] },
  };
  const two = transport(input),
    three = transport({ op: "spec.launcher", workspaceId: "ws" });
  input.query.filters[0].value = "Done";
  assert.equal(calls.length, 1);
  first.resolve(null);
  await Promise.all([one, two, three]);
  assert.deepEqual(
    calls.map((c) => c.op),
    ["spec.watch", "spec.query", "spec.launcher"],
  );
  assert.equal(maximum, 1);
  assert.equal((calls[1].query as typeof input.query).filters[0].value, "Open");
  assert.ok(Object.isFrozen(calls[1]) && Object.isFrozen(calls[1].query));
  assert.deepEqual(Object.keys(calls[1]), ["op", "appId", "query"]);
  lane.dispose();
});

test("queued account flips and same-account reauthentication send no SDK request and discard late values", async () => {
  for (const accountId of ["bob", "alice"]) {
    const lane = new GuardedReadCoordinator(),
      gate = deferred();
    let session = { accountId: "alice", epoch: 1, active: true },
      calls = 0;
    const transport = lane.transport(
      accountTransport({
        execute: async () => {
          calls++;
          return gate.promise;
        },
        expected: { ...session },
        readSession: () => session,
        alive: () => true,
        onUnauthenticated() {},
      }),
    );
    const first = transport({ op: "spec.getApp", appId: "one" }),
      queued = transport({ op: "spec.query", appId: "two" });
    const assertions = [first, queued].map((p) =>
      assert.rejects(
        p,
        (error: unknown) =>
          error instanceof BackendError && error.code === "session_changed",
      ),
    );
    session = { accountId, epoch: 2, active: true };
    gate.resolve({ private: "alice" });
    await Promise.all(assertions);
    assert.equal(calls, 1);
    lane.dispose();
  }
});

test("superseded, disposed and throwing queued scopes cannot dispatch or poison the next read", async () => {
  const lane = new GuardedReadCoordinator(),
    gate = deferred(),
    calls: string[] = [];
  const transport = lane.transport(async (r) => {
    calls.push(String(r.appId));
    if (r.appId === "first") await gate.promise;
    return {};
  });
  const first = transport({ op: "spec.getApp", appId: "first" });
  let current = true;
  const obsolete = transport(
    { op: "spec.query", appId: "obsolete" },
    { isCurrent: () => current },
  );
  let throwing = false;
  const broken = transport(
    { op: "spec.getApp", appId: "broken" },
    {
      isCurrent: () => {
        if (throwing) throw new Error("scope callback failed");
        return true;
      },
    },
  );
  const last = transport({ op: "spec.getApp", appId: "last" });
  const rejected = [
    assert.rejects(obsolete, stale),
    assert.rejects(broken, /scope callback failed/),
  ];
  current = false;
  throwing = true;
  gate.resolve(null);
  await Promise.all([first, last, ...rejected]);
  assert.deepEqual(calls, ["first", "last"]);
  const late = deferred();
  const other = lane.transport(async () => late.promise);
  const running = other({ op: "spec.getApp" }),
    waiting = transport({ op: "spec.getApp", appId: "closed" });
  const stopped = [
    assert.rejects(running, stale),
    assert.rejects(waiting, stale),
  ];
  lane.dispose();
  late.resolve({ private: true });
  await Promise.all(stopped);
  assert.equal(calls.includes("closed"), false);
});

test("bounded read backlog rejects overflow while writes, providers, files, unknown operations and capabilities bypass once", async () => {
  const lane = new GuardedReadCoordinator(),
    gate = deferred(),
    calls: string[] = [];
  const transport = lane.transport(async (r) => {
    calls.push(String(r.op));
    if (r.op === "spec.getApp") return gate.promise;
    throw new BackendError(
      "Conflict",
      "transaction_conflict",
      "service",
      false,
      409,
    );
  });
  const first = transport({ op: "spec.getApp" });
  const waiting = Array.from({ length: 128 }, () =>
    transport({ op: "spec.query" }),
  );
  const observed = waiting.map((p) => assert.rejects(p, stale));
  await assert.rejects(
    transport({ op: "spec.query" }),
    (e: unknown) => e instanceof RuntimeError && e.code === "read_queue_full",
  );
  for (const op of [
    "spec.execute",
    "spec.publish",
    "spec.saveDraft",
    "spec.generate",
    "spec.guidance",
    "spec.media.read",
    "spec.media.begin",
    "spec.unknown",
    "spec.capabilities",
  ])
    await assert.rejects(
      transport({ op }),
      (e: unknown) =>
        e instanceof BackendError && e.code === "transaction_conflict",
    );
  assert.equal(calls.length, 10);
  const stopped = assert.rejects(first, stale);
  lane.dispose();
  gate.resolve(null);
  await Promise.all([stopped, ...observed]);
});

test("bounded adapter retries release the lane for other reads and preserve real exhaustion without replaying writes", async () => {
  const lane = new GuardedReadCoordinator(),
    calls: string[] = [];
  const transport = lane.transport(async (r) => {
    calls.push(String(r.op));
    if (r.op === "spec.query")
      throw new BackendError(
        "Conflict",
        "transaction_conflict",
        "service",
        false,
        409,
      );
    return {};
  });
  const adapter = new FunctionRuntimeAdapter(manifest, transport);
  const failing = assert.rejects(
    adapter.query("projects", {}),
    (e: unknown) =>
      e instanceof RuntimeError && e.code === "transaction_conflict",
  );
  await transport({ op: "spec.getApp", appId: "other" });
  await failing;
  assert.deepEqual(calls, [
    "spec.query",
    "spec.getApp",
    "spec.query",
    "spec.query",
  ]);
  adapter.dispose();
  lane.dispose();
});

test("runtime filter changes and disposal cancel queued reads before SDK dispatch", async () => {
  for (const change of ["filter", "dirty", "dispose"] as const) {
    const lane = new GuardedReadCoordinator(),
      gate = deferred(),
      calls: Record<string, unknown>[] = [];
    const transport = lane.transport(async (r) => {
      calls.push(r);
      if (r.op === "spec.getApp") return gate.promise;
      return empty(r);
    });
    const controller = new RuntimeController(
      new FunctionRuntimeAdapter(manifest, transport),
      () => "no_write_id",
    );
    await controller.recover();
    const blocked = transport({ op: "spec.getApp" });
    const old = controller.refresh();
    await tick();
    let latest: Promise<unknown> = Promise.resolve();
    if (change === "filter")
      latest = controller.select("taskBoard", { choices: { status: "Done" } });
    if (change === "dirty") controller.setDirty(true);
    if (change === "dispose") controller.dispose();
    gate.resolve({});
    await Promise.all([blocked, old, latest]);
    const reads = calls.filter((r) => r.op === "spec.query");
    assert.equal(reads.length, change === "filter" ? 1 : 0);
    if (change === "filter")
      assert.deepEqual((reads[0].query as { filters: unknown }).filters, [
        { fieldId: "status", operator: "eq", value: "Done" },
      ]);
    if (change === "dirty") assert.equal(controller.getSnapshot().dirty, true);
    assert.equal(controller.getSnapshot().accessDenied, false);
    controller.dispose();
    lane.dispose();
  }
});

test("queued selected record and cursor reads are dropped when navigation changes", async () => {
  const lane = new GuardedReadCoordinator(),
    gate = deferred(),
    calls: Record<string, unknown>[] = [];
  const transport: RuntimeTransport = lane.transport(async (r) => {
    calls.push(r);
    if (r.op === "spec.getApp") return gate.promise;
    if (r.op === "spec.query")
      return {
        ...empty(r),
        records: [
          {
            id: "task",
            collectionId: "projects",
            data: { title: "Task", status: "Open" },
            revision: 1,
            writtenUnderVersionId: "version_1",
            capacity: null,
            allocated: null,
            claimed: false,
            allowedActions: [],
          },
        ],
        total: 2,
        nextCursor: "opaque_cursor",
      };
    return empty(r);
  });
  const controller = new RuntimeController(
    new FunctionRuntimeAdapter(manifest, transport),
    () => "no_write_id",
  );
  await controller.refresh();
  const blocked = transport({ op: "spec.getApp" });
  const page = controller.loadMore("taskBoard");
  await tick();
  assert.ok(controller.navigate({ pageId: "tablePage" }));
  gate.resolve({});
  await Promise.all([blocked, page]);
  assert.equal(
    calls.filter(
      (r) => r.op === "spec.query" && (r.query as { cursor?: string }).cursor,
    ).length,
    0,
  );
  const gate2 = deferred();
  const transport2 = lane.transport(async (r) => {
    calls.push(r);
    if (r.op === "spec.getApp") return gate2.promise;
    return empty(r);
  });
  const recordController = new RuntimeController(
    new FunctionRuntimeAdapter(manifest, transport2),
    () => "no_write_id",
  );
  await recordController.recover();
  recordController.navigate({
    pageId: "boardPage",
    recordId: "private_record",
  });
  const blocked2 = transport2({ op: "spec.getApp" });
  const read = recordController.refresh();
  await tick();
  recordController.navigate({ pageId: "tablePage" });
  gate2.resolve({});
  await Promise.all([blocked2, read]);
  assert.equal(calls.filter((r) => r.op === "spec.getRecord").length, 0);
  controller.dispose();
  recordController.dispose();
  lane.dispose();
});

test("canceling an already dispatched read keeps the lane occupied until its SDK settles", async () => {
  const lane = new GuardedReadCoordinator(),
    gate = deferred(),
    calls: string[] = [];
  const transport = lane.transport(async (r) => {
    calls.push(String(r.appId));
    if (r.appId === "old") return gate.promise;
    return {};
  });
  let current = true;
  const old = transport(
    { op: "spec.getApp", appId: "old" },
    { isCurrent: () => current },
  );
  const rejected = assert.rejects(old, stale);
  const next = transport({ op: "spec.getApp", appId: "new" });
  current = false;
  await tick();
  assert.deepEqual(calls, ["old"]);
  gate.resolve({ private: "late" });
  await Promise.all([rejected, next]);
  assert.deepEqual(calls, ["old", "new"]);
  lane.dispose();
});

test("external record route supersession cancels its queued authorized get before SDK dispatch", async () => {
  const lane = new GuardedReadCoordinator(),
    gate = deferred(),
    calls: Record<string, unknown>[] = [];
  const transport = lane.transport(async (r) => {
    calls.push(r);
    if (r.op === "spec.getApp") return gate.promise;
    return empty(r);
  });
  const controller = new RuntimeController(
    new FunctionRuntimeAdapter(manifest, transport),
    () => "unused",
  );
  await controller.recover();
  const blocked = transport({ op: "spec.getApp" });
  const old = controller.applyLocation({ recordId: "private_record" });
  await tick();
  const next = controller.applyLocation({ pageId: "tablePage" });
  await tick();
  gate.resolve({});
  const [obsolete] = await Promise.all([old, next, blocked]);
  assert.equal(obsolete, "stale");
  assert.equal(
    calls.some((r) => r.op === "spec.getRecord"),
    false,
  );
  assert.equal(controller.getSnapshot().location.pageId, "tablePage");
  controller.dispose();
  lane.dispose();
});
