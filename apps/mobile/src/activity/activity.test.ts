import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { BackendError } from "../backend/errors";
import { AppwriteBackend, type SdkAdapter } from "../backend/core";
import { RuntimeError } from "../runtime/errors";
import type { RuntimeTransport } from "../runtime/types";
import {
  ActivityController,
  type ActivityOptions,
  type ActivitySession,
} from "./ActivityController";
import { activityLabel, activityPage } from "./contracts";

const wire = JSON.parse(
  readFileSync(new URL("./fixtures/serviceWire.json", import.meta.url), "utf8"),
);
const item = (n: number) => ({
  id: `a${String(n).padStart(3, "0")}`,
  action: "records.create.v1",
  createdAt: "2030-01-02T00:00:00.000Z",
  status: "committed",
});
const first = () => ({
  appId: "app",
  items: Array.from({ length: 50 }, (_, n) => item(n)),
  nextCursor: "opaque-first",
});
const last = () => ({ appId: "app", items: [item(50)], nextCursor: null });
test("activity labels describe known committed work and safely handle future names", () => {
  assert.equal(activityLabel("records.create.v1"), "Record created");
  assert.equal(activityLabel("archiveApp"), "App archived");
  assert.equal(activityLabel("__proto__"), "App change");
  assert.equal(activityLabel("future.handler.v2"), "App change");
});
test("actual SDK transport classifies unavailable activity execution as a read, never an uncertain mutation", async () => {
  const sdk: SdkAdapter = {
    newId: () => "unused",
    account: {
      get: async () => null,
      create: async () => null,
      createEmailPasswordSession: async () => null,
      deleteSession: async () => null,
    },
    execute: async () => ({
      status: "completed",
      responseStatusCode: 503,
      responseBody: JSON.stringify({ error: "backend_unavailable" }),
    }),
  };
  const backend = new AppwriteBackend(sdk);
  await assert.rejects(
    backend.executeSpec({ op: "spec.listActivity", appId: "app" }),
    (error) =>
      error instanceof BackendError &&
      !error.uncertain &&
      error.code === "backend_unavailable",
  );
  sdk.execute = async () => ({
    status: "processing",
    responseStatusCode: 0,
    responseBody: "",
  });
  await assert.rejects(
    backend.executeSpec({ op: "spec.listActivity", appId: "app" }),
    (error) =>
      error instanceof BackendError &&
      !error.uncertain &&
      error.code === "execution_incomplete",
  );
});
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
function fixture(transport: RuntimeTransport) {
  let session: ActivitySession = { accountId: "alice", epoch: 1, active: true };
  const listeners = new Set<() => void>(),
    calls: Record<string, unknown>[] = [];
  let expired = 0;
  const options: ActivityOptions = {
    appId: "app",
    accountId: "alice",
    epoch: 1,
    transport: async (request) => {
      calls.push(request);
      return transport(request);
    },
    readSession: () => session,
    subscribeSession: (callback) => {
      listeners.add(callback);
      return () => {
        listeners.delete(callback);
      };
    },
    onUnauthenticated: () => {
      expired++;
    },
  };
  return {
    controller: new ActivityController(options),
    options,
    calls,
    listeners,
    expired: () => expired,
    change: (next: Partial<ActivitySession>) => {
      session = { ...session, ...next };
      for (const listener of listeners) listener();
    },
  };
}

test("real Dart service fixture decodes exact metadata and no private columns", () => {
  const first = activityPage(wire.first, "app", 2),
    second = activityPage(wire.second, "app", 2);
  assert.equal(first.items.length, 2);
  assert(second.items[0].id > first.items.at(-1)!.id);
  assert(Object.isFrozen(first));
  assert(Object.isFrozen(first.items[0]));
  for (const row of first.items)
    assert.deepEqual(Object.keys(row), ["id", "action", "createdAt", "status"]);
});

test("strict wire rejects foreign app, privacy columns, duplicate/order violations, rollover and bad cursor bounds", () => {
  for (const changed of [
    { ...wire.first, appId: "other" },
    { ...wire.first, actorId: "private" },
    {
      ...wire.first,
      items: [{ ...wire.first.items[0], requestId: "private" }],
    },
    { ...wire.first, items: [wire.first.items[0], wire.first.items[0]] },
    { ...wire.first, items: [...wire.first.items].reverse() },
    {
      ...wire.first,
      items: [
        { ...wire.first.items[0], createdAt: "2030-02-31T00:00:00.000Z" },
      ],
    },
    { ...wire.first, items: [{ ...wire.first.items[0], status: "pending" }] },
    { ...wire.first, nextCursor: "x".repeat(1025) },
    { ...wire.first, nextCursor: "!" },
    { ...wire.first, items: [], nextCursor: "cursor" },
    { ...wire.first, items: Array.from({ length: 51 }, (_, n) => item(n)) },
  ])
    assert.throws(() => activityPage(changed, "app", 2));
});

test("only bounded activity reads are sent and full pages append without duplicates", async () => {
  const f = fixture(async (request) => (request.cursor ? last() : first()));
  await f.controller.load();
  await f.controller.load(true);
  await f.controller.load(true);
  assert.equal(f.controller.getSnapshot().items.length, 51);
  assert.equal(f.calls.length, 2);
  assert.deepEqual(f.calls, [
    { op: "spec.listActivity", appId: "app", limit: 50 },
    {
      op: "spec.listActivity",
      appId: "app",
      limit: 50,
      cursor: "opaque-first",
    },
  ]);
});

test("refresh wins over an older in-flight page", async () => {
  const pending = deferred<unknown>();
  const f = fixture(async (request) =>
    request.cursor ? pending.promise : first(),
  );
  await f.controller.load();
  const more = f.controller.load(true);
  await f.controller.load();
  pending.resolve(last());
  await more;
  assert.equal(f.controller.getSnapshot().items.length, 50);
  assert.equal(f.controller.getSnapshot().cursor, "opaque-first");
});

test("duplicate/repeated cursor and cross-page overlap never append", async () => {
  for (const result of [
    { ...first(), items: Array.from({ length: 50 }, (_, n) => item(50 + n)) },
    { ...last(), items: [item(49)] },
  ]) {
    const f = fixture(async (request) => (request.cursor ? result : first()));
    await f.controller.load();
    await f.controller.load(true);
    assert.equal(f.controller.getSnapshot().items.length, 50);
    assert(f.controller.getSnapshot().error);
  }
});

test("account change clears cached history synchronously and rejects a late response", async () => {
  const pending = deferred<unknown>();
  const f = fixture(async (request) =>
    request.cursor ? pending.promise : first(),
  );
  await f.controller.load();
  const more = f.controller.load(true);
  f.change({ accountId: "bob" });
  assert.equal(f.controller.getSnapshot().items.length, 0);
  assert.equal(f.listeners.size, 0);
  pending.resolve(last());
  await more;
  assert.equal(f.controller.getSnapshot().items.length, 0);
  await f.controller.load();
  assert.equal(f.calls.length, 2);
});

test("same account reauthentication and inactive auth transitions invalidate the old epoch", async () => {
  for (const change of [{ epoch: 2 }, { active: false }]) {
    const f = fixture(async () => first());
    await f.controller.load();
    f.change(change);
    assert.equal(f.controller.getSnapshot().items.length, 0);
    assert.equal(f.controller.getSnapshot().denied, true);
    await f.controller.load();
    assert.equal(f.calls.length, 1);
  }
});

test("current grant concealment/forbidden clears all pages without signing the account out", async () => {
  for (const status of [403, 404]) {
    let denied = false;
    const f = fixture(async () => {
      if (denied)
        throw new BackendError(
          "PRIVATE_BODY",
          status === 404 ? "not_found" : "forbidden",
          "service",
          false,
          status,
        );
      return first();
    });
    await f.controller.load();
    denied = true;
    await f.controller.load(true);
    assert.equal(f.controller.getSnapshot().items.length, 0);
    assert.equal(f.controller.getSnapshot().cursor, null);
    assert.equal(f.controller.getSnapshot().denied, true);
    assert.equal(f.expired(), 0);
    assert(!f.controller.getSnapshot().error?.includes("PRIVATE_BODY"));
  }
});

test("401 clears pages and closes the account session once", async () => {
  const f = fixture(async () => {
    throw new BackendError(
      "private",
      "unauthenticated",
      "unauthenticated",
      false,
      401,
    );
  });
  await f.controller.load();
  await f.controller.load();
  assert.equal(f.expired(), 1);
  assert.equal(f.calls.length, 1);
  assert.equal(f.controller.getSnapshot().items.length, 0);
});

test("stale activity snapshot clears paging and requires a fresh first-page read", async () => {
  const f = fixture(async (request) => {
    if (request.cursor) throw new RuntimeError("revision_conflict", "private");
    return first();
  });
  await f.controller.load();
  await f.controller.load(true);
  assert.equal(f.controller.getSnapshot().items.length, 0);
  assert.equal(f.controller.getSnapshot().cursor, null);
  assert.match(f.controller.getSnapshot().error!, /Activity changed/);
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().items.length, 50);
});

test("transient read failure is visible, never retries or invents committed entries", async () => {
  const f = fixture(async () => {
    throw Error("PRIVATE_COOKIE");
  });
  await f.controller.load();
  assert.equal(f.calls.length, 1);
  assert.equal(f.controller.getSnapshot().items.length, 0);
  assert(!f.controller.getSnapshot().error?.includes("PRIVATE_COOKIE"));
});

test("route blur cancels a late result and disposal unsubscribes and clears history", async () => {
  const pending = deferred<unknown>(),
    f = fixture(async () => pending.promise);
  const read = f.controller.load();
  f.controller.cancelRead();
  pending.resolve(first());
  await read;
  assert.equal(f.controller.getSnapshot().items.length, 0);
  f.controller.dispose();
  assert.equal(f.listeners.size, 0);
  assert.equal(f.controller.getSnapshot().items.length, 0);
});

test("an abandoned React render has no subscription and repeated effect setup retains one live controller", async () => {
  const f = fixture(async () => first());
  assert.equal(f.listeners.size, 0);
  const release = f.controller.retain();
  release();
  const releaseAgain = f.controller.retain();
  await Promise.resolve();
  assert.equal(f.listeners.size, 1);
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().items.length, 50);
  releaseAgain();
  await Promise.resolve();
  assert.equal(f.listeners.size, 0);
  assert.equal(f.controller.getSnapshot().items.length, 0);
});

test("caller options cannot retarget an existing controller", async () => {
  const f = fixture(async () => first());
  f.options.appId = "foreign";
  f.options.accountId = "bob";
  await f.controller.load();
  assert.equal(f.calls[0].appId, "app");
  assert.equal(f.controller.getSnapshot().items.length, 50);
});
