import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import { HostLifetime } from "../host/scope";
import { accountTransport, type AccountSession } from "../full/FullRegistry";
import { fullTemplates } from "../full/catalog";
import { RuntimeController } from "./controller";
import { RuntimeError } from "./errors";
import type { RuntimeAdapter, RuntimeCommand, RuntimeRecord } from "./types";
import type { RuntimeCommandStore } from "./commands";
import { withInvalidation } from "./invalidation";
import {
  decodeInvalidation,
  type InvalidationStamp,
  type WatchActivity,
  type WatchClock,
} from "./invalidationTypes";
import { nativeWatchActivity, webWatchActivity } from "./invalidationActivity";
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const lifetime = () => new HostLifetime(scope);
const stamp = (change: Partial<InvalidationStamp> = {}): InvalidationStamp => ({
  appId: "app",
  versionId: "version",
  controlRevision: 1,
  role: "owner",
  archived: false,
  ...change,
});
const capability = { mode: "poll.v1" as const, minimumIntervalMs: 15000 };
const flush = () => new Promise<void>((resolve) => setImmediate(resolve));
function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (error: unknown) => void;
  const promise = new Promise<T>((a, b) => {
    resolve = a;
    reject = b;
  });
  return { promise, resolve, reject };
}
class Clock implements WatchClock {
  now = 0;
  next = 0;
  tasks = new Map<number, { at: number; callback: () => void }>();
  delays: number[] = [];
  setTimeout = (callback: () => void, delay: number) => {
    const key = ++this.next;
    this.delays.push(delay);
    this.tasks.set(key, { at: this.now + delay, callback });
    return key;
  };
  clearTimeout = (handle: unknown) => {
    this.tasks.delete(handle as number);
  };
  async advance(milliseconds: number) {
    const end = this.now + milliseconds;
    let count = 0;
    while (true) {
      const ready = [...this.tasks]
        .filter(([, v]) => v.at <= end)
        .sort((a, b) => a[1].at - b[1].at)[0];
      if (!ready) break;
      assert.ok(++count < 1000, "timer loop");
      this.now = ready[1].at;
      this.tasks.delete(ready[0]);
      ready[1].callback();
      await flush();
    }
    this.now = end;
    await flush();
  }
}
class Activity implements WatchActivity {
  state = { foreground: true, online: true };
  listeners = new Set<() => void>();
  getSnapshot = () => this.state;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  change(value: Partial<typeof this.state>) {
    this.state = { ...this.state, ...value };
    for (const listener of [...this.listeners]) listener();
  }
}
const spec = fullTemplates.find((t) => t.id === "notes")!.spec;
const row: RuntimeRecord = {
  id: "record",
  collectionId: spec.collections[0].id,
  data: { title: "Private record" },
  revision: 1,
  writtenUnderVersionId: "version",
  capacity: null,
  allocated: null,
  claimed: false,
  allowedActions: spec.actions.map((a) => a.id),
};
function base(change: Partial<RuntimeAdapter> = {}): RuntimeAdapter {
  return {
    appId: "app",
    versionId: "version",
    spec,
    preview: false,
    role: "owner",
    archived: false,
    approvedRuleIds: [],
    features: new Set(["members"]),
    query: async () => ({
      records: [row],
      total: 1,
      nextCursor: null,
      versionId: "version",
    }),
    get: async () => row,
    summary: async () => ({ total: 1, groups: {}, versionId: "version" }),
    aggregate: async () => ({
      total: 1,
      value: 1,
      groups: [],
      versionId: "version",
    }),
    execute: async () => ({
      recordId: "record",
      revision: 2,
      message: "Saved",
    }),
    permits: () => true,
    members: async () => [],
    reminderState: async () => ({ kind: "none", label: "Disabled" }),
    readImage: async () => ({ uri: "private://asset" }),
    pickImage: async () => null,
    uploadImage: async () => "asset",
    watch: () => () => {},
    dispose: () => {},
    ...change,
  };
}
function watched(change: Partial<RuntimeAdapter> = {}) {
  const events = new Set<() => void>();
  return {
    adapter: base({
      ...change,
      features: new Set(["watch"]),
      watch: (listener) => {
        events.add(listener);
        return () => {
          events.delete(listener);
        };
      },
    }),
    fire() {
      for (const listener of [...events]) listener();
    },
  };
}
function commands(initial: RuntimeCommand | null = null): RuntimeCommandStore {
  let saved = initial;
  return {
    durability: "durable",
    read: async () => saved,
    save: async (command) => {
      saved = command;
    },
    clear: async (operationId) => {
      assert.equal(saved?.operationId, operationId);
      saved = null;
    },
  };
}
const retained: RuntimeCommand = {
  appId: "app",
  versionId: "original_version",
  operationId: "original_operation",
  actionId: spec.actions.find((a) => a.capability === "records.create.v1")!.id,
  input: { data: { title: "Retained private input" } },
};
test("watch uses confirmed capability and scoped live host only, with no traffic before activation", async () => {
  const clock = new Clock(),
    activity = new Activity(),
    life = lifetime();
  let calls = 0;
  const wrapper = withInvalidation(
    base(),
    async () => {
      calls++;
      return stamp();
    },
    life,
    {
      capability: null,
      clock,
      activity,
      onManifestChange: () => {},
      onAccessFailure: () => {},
    },
  );
  wrapper.watch(() => {});
  wrapper.setActive?.(true);
  await clock.advance(300000);
  assert.equal(calls, 0);
  assert.equal(wrapper.features.has("watch"), false);
  assert.equal(activity.listeners.size, 0);
  wrapper.dispose();
  assert.throws(() =>
    withInvalidation(base({ preview: true }), async () => stamp(), lifetime(), {
      capability,
      onManifestChange: () => {},
      onAccessFailure: () => {},
    }),
  );
  assert.throws(() =>
    withInvalidation(
      base({ appId: "foreign" }),
      async () => stamp(),
      lifetime(),
      { capability, onManifestChange: () => {}, onAccessFailure: () => {} },
    ),
  );
  assert.throws(() =>
    withInvalidation(base(), async () => stamp(), lifetime(), {
      capability,
      minimumIntervalMs: 1000,
      onManifestChange: () => {},
      onAccessFailure: () => {},
    }),
  );
});
test("initial baseline, domain changes and reconnect notify, stable tokens do not poll random guards or duplicate refreshes", async () => {
  const clock = new Clock(),
    activity = new Activity(),
    life = lifetime();
  let current = stamp(),
    calls = 0,
    invalidations = 0;
  const manifests: InvalidationStamp[] = [];
  const wrapper = withInvalidation(
    base(),
    async (request) => {
      assert.deepEqual(request, { op: "spec.watch", appId: "app" });
      calls++;
      return current;
    },
    life,
    {
      capability,
      clock,
      activity,
      onManifestChange: (value) => {
        manifests.push(value);
      },
      onAccessFailure: () => assert.fail("unexpected denial"),
    },
  );
  wrapper.watch(() => invalidations++);
  await clock.advance(0);
  assert.equal(calls, 0);
  wrapper.setActive?.(true);
  await clock.advance(0);
  assert.equal(invalidations, 1);
  await clock.advance(15000);
  assert.equal(invalidations, 1);
  current = stamp({ controlRevision: 2 });
  await clock.advance(15000);
  assert.equal(invalidations, 2);
  activity.change({ online: false });
  await clock.advance(90000);
  assert.equal(calls, 3);
  activity.change({ online: true });
  await clock.advance(0);
  assert.equal(invalidations, 3);
  assert.equal(manifests.length, 3);
  assert.equal(manifests[2].controlRevision, 2);
  wrapper.dispose();
  assert.equal(activity.listeners.size, 0);
  assert.equal(clock.tasks.size, 0);
  life.dispose();
});
test("foreground pause and resume fence late polls without overlapping in-flight requests", async () => {
  const clock = new Clock(),
    activity = new Activity(),
    life = lifetime(),
    response = deferred<unknown>();
  let calls = 0,
    currentRequests = 0,
    maxRequests = 0,
    notified = 0;
  const wrapper = withInvalidation(
    base(),
    async () => {
      calls++;
      currentRequests++;
      maxRequests = Math.max(maxRequests, currentRequests);
      try {
        return calls === 1 ? await response.promise : stamp();
      } finally {
        currentRequests--;
      }
    },
    life,
    {
      capability,
      clock,
      activity,
      onManifestChange: () => {
        notified++;
      },
      onAccessFailure: () => assert.fail("unexpected denial"),
    },
  );
  wrapper.watch(() => {});
  wrapper.setActive?.(true);
  await clock.advance(0);
  activity.change({ foreground: false });
  activity.change({ foreground: true });
  await clock.advance(120000);
  assert.equal(calls, 1);
  response.resolve(stamp({ controlRevision: 999 }));
  await flush();
  await clock.advance(0);
  assert.equal(calls, 2);
  assert.equal(maxRequests, 1);
  assert.equal(notified, 1);
  wrapper.setActive?.(false);
  await clock.advance(120000);
  assert.equal(calls, 2);
  wrapper.dispose();
  assert.equal(clock.tasks.size, 0);
});
test("connection errors back off to120s and first successful reconnect invalidates even the same token", async () => {
  const clock = new Clock(),
    activity = new Activity(),
    life = lifetime();
  let fail = false,
    calls = 0,
    notified = 0;
  const wrapper = withInvalidation(
    base(),
    async () => {
      calls++;
      if (fail) throw new Error("offline");
      return stamp();
    },
    life,
    {
      capability,
      clock,
      activity,
      onManifestChange: () => {
        notified++;
      },
      onAccessFailure: () => assert.fail("unexpected denial"),
    },
  );
  wrapper.watch(() => {});
  wrapper.setActive?.(true);
  await clock.advance(0);
  fail = true;
  await clock.advance(15000);
  await clock.advance(30000);
  await clock.advance(60000);
  await clock.advance(120000);
  assert.deepEqual(
    clock.delays.slice(0, 6),
    [0, 15000, 30000, 60000, 120000, 120000],
  );
  fail = false;
  await clock.advance(120000);
  assert.equal(notified, 2);
  assert.equal(calls, 6);
  assert.equal(clock.delays.at(-1), 15000);
  wrapper.dispose();
});
test("wrong app, invalid role, malformed counters and guard-only responses fail closed once", async () => {
  for (const response of [
    stamp({ appId: "foreign" }),
    { ...stamp(), role: "admin" },
    { ...stamp(), controlRevision: "2" },
    { ...stamp(), guard: "random" },
    { appId: "app", guard: "changed-on-read" },
  ]) {
    const clock = new Clock(),
      activity = new Activity(),
      life = lifetime();
    let denied = 0,
      notified = 0;
    const wrapper = withInvalidation(base(), async () => response, life, {
      capability,
      clock,
      activity,
      onManifestChange: () => {
        notified++;
      },
      onAccessFailure: (error) => {
        assert.equal(error.code, "forbidden");
        denied++;
      },
    });
    wrapper.watch(() => {});
    wrapper.setActive?.(true);
    await clock.advance(0);
    await clock.advance(120000);
    assert.equal(denied, 1);
    assert.equal(notified, 0);
    assert.equal(wrapper.features.has("watch"), false);
    wrapper.dispose();
  }
  assert.throws(() =>
    decodeInvalidation({ ...stamp(), controlRevision: -1 }, "app"),
  );
  assert.equal(
    decodeInvalidation(stamp({ versionId: null }), "app").versionId,
    null,
  );
});
test("current401/403/404 denials reach host while form is dirty; retained encrypted operation is not cleared", async () => {
  for (const status of [401, 403, 404]) {
    const clock = new Clock(),
      activity = new Activity(),
      life = lifetime(),
      store = commands(retained);
    let controller!: RuntimeController,
      denied = 0,
      writes = 0;
    const wrapper = withInvalidation(
      base({
        execute: async () => {
          writes++;
          return { recordId: "record", revision: 2, message: "Saved" };
        },
      }),
      async () => {
        throw new BackendError(
          "Denied",
          status === 401 ? "expired" : "not_found",
          status === 401 ? "unauthenticated" : "service",
          false,
          status,
        );
      },
      life,
      {
        capability,
        clock,
        activity,
        onManifestChange: () => {},
        onAccessFailure: (error) => {
          denied++;
          controller.invalidateAccess(error);
        },
      },
    );
    controller = new RuntimeController(
      wrapper,
      () => "must_not_generate",
      undefined,
      store,
    );
    await controller.recover();
    assert.ok(controller.getSnapshot().pending);
    wrapper.setActive?.(true);
    await clock.advance(0);
    assert.equal(denied, 1);
    assert.equal(controller.getSnapshot().accessDenied, true);
    assert.equal(controller.getSnapshot().pending, null);
    assert.equal(controller.getSnapshot().dirty, false);
    assert.deepEqual(controller.getSnapshot().views, {});
    assert.deepEqual(await store.read(), retained);
    assert.equal(writes, 0);
    controller.dispose();
  }
});
test("account epoch change cannot publish a late stamp or sign out the replacement session", async () => {
  const clock = new Clock(),
    activity = new Activity(),
    life = lifetime(),
    response = deferred<unknown>();
  let session: AccountSession = { accountId: "alice", epoch: 1, active: true },
    dispatched = 0,
    unauthorized = 0,
    denied = 0,
    notified = 0;
  const transport = accountTransport({
    expected: { ...session },
    readSession: () => session,
    alive: () => life.active,
    onUnauthenticated: () => {
      unauthorized++;
    },
    execute: async () => {
      dispatched++;
      return response.promise;
    },
  });
  const wrapper = withInvalidation(base(), transport, life, {
    capability,
    clock,
    activity,
    onManifestChange: () => {
      notified++;
    },
    onAccessFailure: () => {
      denied++;
    },
  });
  wrapper.watch(() => {});
  wrapper.setActive?.(true);
  await clock.advance(0);
  session = { accountId: "bob", epoch: 2, active: true };
  response.resolve(stamp());
  await flush();
  await clock.advance(120000);
  assert.equal(dispatched, 1);
  assert.equal(notified, 0);
  assert.equal(unauthorized, 0);
  assert.equal(denied, 0);
  assert.equal(clock.tasks.size, 0);
  wrapper.dispose();
});
test("disposed scope fences late polling and delegates image upload context/lifecycle unchanged", async () => {
  const clock = new Clock(),
    activity = new Activity(),
    life = lifetime(),
    response = deferred<unknown>();
  let disposed = 0,
    notified = 0,
    received: unknown;
  const activations: boolean[] = [];
  const wrapper = withInvalidation(
    base({
      features: new Set(["imageUpload"]),
      uploadImage: async (_image, context) => {
        received = context;
        return "asset";
      },
      setActive: (value) => {
        activations.push(value);
      },
      dispose: () => {
        disposed++;
      },
    }),
    () => response.promise,
    life,
    {
      capability,
      clock,
      activity,
      onManifestChange: () => {
        notified++;
      },
      onAccessFailure: () => assert.fail("late denial"),
    },
  );
  wrapper.watch(() => {});
  wrapper.setActive?.(true);
  const context = {
    versionId: "version",
    actionId: "create",
    fieldId: "photo",
  };
  await wrapper.uploadImage(
    { bytes: new Uint8Array([1]), mimeType: "image/png", name: "image.png" },
    context,
  );
  assert.equal(received, context);
  assert.equal(wrapper.features.has("imageUpload"), true);
  await clock.advance(0);
  life.dispose();
  response.resolve(stamp());
  await flush();
  assert.equal(notified, 0);
  assert.equal(disposed, 1);
  assert.equal(activity.listeners.size, 0);
  assert.equal(clock.tasks.size, 0);
  assert.deepEqual(activations, [true, false]);
  wrapper.dispose();
  assert.equal(disposed, 1);
});
test("web and native activity are scoped, pause on hidden/offline/blur and release every subscription", () => {
  function events() {
    const callbacks = new Map<string, Set<() => void>>();
    return {
      callbacks,
      addEventListener(event: string, listener: () => void) {
        const values = callbacks.get(event) ?? new Set();
        values.add(listener);
        callbacks.set(event, values);
      },
      removeEventListener(event: string, listener: () => void) {
        callbacks.get(event)?.delete(listener);
      },
      fire(event: string) {
        for (const next of callbacks.get(event) ?? []) next();
      },
      count() {
        return [...callbacks.values()].reduce(
          (sum, values) => sum + values.size,
          0,
        );
      },
    };
  }
  const document = { ...events(), visibilityState: "visible" },
    window = events(),
    navigator = { onLine: true };
  const web = webWatchActivity({ document, window, navigator });
  let changes = 0;
  const stop = web.subscribe(() => changes++);
  assert.equal(document.count() + window.count(), 3);
  document.visibilityState = "hidden";
  document.fire("visibilitychange");
  assert.equal(web.getSnapshot().foreground, false);
  navigator.onLine = false;
  window.fire("offline");
  assert.equal(web.getSnapshot().online, false);
  stop();
  assert.equal(document.count() + window.count(), 0);
  assert.equal(changes, 2);
  let state: string | null = null;
  const callbacks = new Map<string, (state?: string) => void>();
  const native = nativeWatchActivity({
    currentState: () => state,
    subscribe(event, listener) {
      callbacks.set(event, listener);
      return () => {
        callbacks.delete(event);
      };
    },
  });
  const stopNative = native.subscribe(() => {});
  assert.equal(native.getSnapshot().foreground, false);
  state = "active";
  callbacks.get("change")?.(state);
  assert.equal(native.getSnapshot().foreground, true);
  callbacks.get("blur")?.();
  assert.equal(native.getSnapshot().foreground, false);
  callbacks.get("focus")?.();
  assert.equal(native.getSnapshot().foreground, true);
  stopNative();
  assert.equal(callbacks.size, 0);
  native.dispose?.();
  assert.equal(native.getSnapshot().foreground, false);
});
test("runtime coalesces repeated invalidations during loading and defers dirty updates until editing ends", async () => {
  const pending = deferred<Awaited<ReturnType<RuntimeAdapter["query"]>>>();
  let reads = 0,
    concurrent = 0,
    max = 0;
  const source = watched({
    query: async () => {
      reads++;
      concurrent++;
      max = Math.max(max, concurrent);
      try {
        return reads === 1
          ? await pending.promise
          : {
              records: [row],
              total: 1,
              nextCursor: null,
              versionId: "version",
            };
      } finally {
        concurrent--;
      }
    },
  });
  const controller = new RuntimeController(
    source.adapter,
    () => "operation",
    undefined,
    commands(),
  );
  const loading = controller.refresh();
  await flush();
  for (let i = 0; i < 8; i++) source.fire();
  assert.equal(reads, 1);
  pending.resolve({
    records: [row],
    total: 1,
    nextCursor: null,
    versionId: "version",
  });
  await loading;
  await flush();
  assert.equal(reads, 2);
  assert.equal(max, 1);
  controller.setDirty(true);
  for (let i = 0; i < 8; i++) source.fire();
  await flush();
  assert.equal(reads, 2);
  controller.setDirty(false);
  controller.setDirty(false);
  await flush();
  assert.equal(reads, 3);
  controller.dispose();
});
test("runtime retains a pending command through invalidations and performs one refresh only after explicit retry", async () => {
  let reads = 0,
    writes = 0;
  const store = commands(retained),
    source = watched({
      query: async () => {
        reads++;
        return {
          records: [row],
          total: 1,
          nextCursor: null,
          versionId: "version",
        };
      },
      execute: async (command) => {
        writes++;
        assert.deepEqual(command, retained);
        return { recordId: "record", revision: 2, message: "Saved" };
      },
    });
  const controller = new RuntimeController(
    source.adapter,
    () => "must_not_allocate",
    undefined,
    store,
  );
  await controller.recover();
  source.fire();
  source.fire();
  controller.setDirty(false);
  await flush();
  assert.equal(reads, 0);
  assert.equal(writes, 0);
  await controller.retry();
  assert.equal(writes, 1);
  assert.equal(reads, 1);
  assert.equal(await store.read(), null);
  controller.dispose();
});
test("definitive failure acknowledgement drains invalidation once, still respecting a dirty form", async () => {
  for (const dirty of [false, true]) {
    let reads = 0,
      writes = 0;
    const source = watched({
      query: async () => {
        reads++;
        return {
          records: [row],
          total: 1,
          nextCursor: null,
          versionId: "version",
        };
      },
      execute: async () => {
        writes++;
        throw new BackendError(
          "Rejected",
          "invalid_request",
          "service",
          false,
          400,
        );
      },
    });
    const controller = new RuntimeController(
      source.adapter,
      () => "failed_operation",
      undefined,
      commands(),
    );
    await controller.refresh();
    if (dirty) controller.setDirty(true);
    await controller.execute(retained.actionId, retained.input);
    source.fire();
    source.fire();
    await controller.acknowledgeFailure();
    assert.equal(reads, dirty ? 1 : 2);
    if (dirty) {
      controller.setDirty(false);
      await flush();
      assert.equal(reads, 2);
    }
    assert.equal(writes, 1);
    controller.dispose();
  }
});
test("current access denial in an in-flight record fetch clears private state despite becoming dirty", async () => {
  const response = deferred<Awaited<ReturnType<RuntimeAdapter["query"]>>>();
  let denied = 0;
  const source = watched({ query: () => response.promise });
  const controller = new RuntimeController(
    source.adapter,
    () => "operation",
    undefined,
    commands(),
    {
      onAccessFailure: () => {
        denied++;
      },
    },
  );
  const loading = controller.refresh();
  await flush();
  controller.setDirty(true);
  response.reject(
    new BackendError("Revoked", "forbidden", "service", false, 403),
  );
  await loading;
  assert.equal(denied, 1);
  assert.equal(controller.getSnapshot().accessDenied, true);
  assert.equal(controller.getSnapshot().dirty, false);
  assert.deepEqual(controller.getSnapshot().views, {});
  controller.dispose();
});
test("the first successful watch baseline covers a query that began before the subscription response", async () => {
  const clock = new Clock(),
    activity = new Activity(),
    life = lifetime(),
    response = deferred<Awaited<ReturnType<RuntimeAdapter["query"]>>>();
  let reads = 0;
  const wrapped = withInvalidation(
    base({
      query: async () => {
        reads++;
        return reads === 1
          ? response.promise
          : {
              records: [row],
              total: 1,
              nextCursor: null,
              versionId: "version",
            };
      },
    }),
    async () => stamp(),
    life,
    {
      capability,
      clock,
      activity,
      onManifestChange: () => {},
      onAccessFailure: () => assert.fail("unexpected denial"),
    },
  );
  const controller = new RuntimeController(
    wrapped,
    () => "operation",
    undefined,
    commands(),
  );
  const loading = controller.refresh();
  await flush();
  wrapped.setActive?.(true);
  await clock.advance(0);
  assert.equal(reads, 1);
  response.resolve({
    records: [],
    total: 0,
    nextCursor: null,
    versionId: "version",
  });
  await loading;
  assert.equal(reads, 2);
  assert.equal(
    controller.getSnapshot().views[spec.views[0].id].records[0].id,
    "record",
  );
  controller.dispose();
});
test("repeated identical activity events do not reset the minimum polling interval", async () => {
  const clock = new Clock(),
    activity = new Activity(),
    life = lifetime();
  let calls = 0;
  const wrapped = withInvalidation(
    base(),
    async () => {
      calls++;
      return stamp();
    },
    life,
    {
      capability,
      clock,
      activity,
      onManifestChange: () => {},
      onAccessFailure: () => {},
    },
  );
  wrapped.watch(() => {});
  wrapped.setActive?.(true);
  await clock.advance(0);
  for (let i = 0; i < 8; i++)
    activity.change({ foreground: true, online: true });
  await clock.advance(0);
  assert.equal(calls, 1);
  await clock.advance(15000);
  assert.equal(calls, 2);
  wrapped.dispose();
});
test("paging defers watched refresh until completion and retains the loaded record prefix", async () => {
  const second = { ...row, id: "second" },
    page = deferred<Awaited<ReturnType<RuntimeAdapter["query"]>>>();
  let calls = 0,
    waiting = true;
  const source = watched({
    query: async (_collection, query) => {
      calls++;
      if (query.cursor) {
        if (waiting) {
          waiting = false;
          return page.promise;
        }
        return {
          records: [second],
          total: 2,
          nextCursor: null,
          versionId: "version",
        };
      }
      return {
        records: [row],
        total: 2,
        nextCursor: "cursor",
        versionId: "version",
      };
    },
  });
  const controller = new RuntimeController(
    source.adapter,
    () => "operation",
    undefined,
    commands(),
  );
  await controller.refresh();
  const more = controller.loadMore(spec.views[0].id);
  await flush();
  source.fire();
  source.fire();
  await flush();
  assert.equal(calls, 2);
  page.resolve({
    records: [second],
    total: 2,
    nextCursor: null,
    versionId: "version",
  });
  await more;
  await flush();
  assert.equal(calls, 4);
  assert.deepEqual(
    controller
      .getSnapshot()
      .views[spec.views[0].id].records.map((item) => item.id),
    ["record", "second"],
  );
  controller.dispose();
});
test("duplicate current access failures do not notify twice and disposed runtime snapshots retain no private data", async () => {
  const source = watched();
  let denials = 0;
  const controller = new RuntimeController(
    source.adapter,
    () => "operation",
    undefined,
    commands(),
    {
      onAccessFailure: () => {
        denials++;
      },
    },
  );
  await controller.refresh();
  controller.focusRecord(row);
  controller.setDirty(true);
  controller.invalidateAccess(new RuntimeError("forbidden", "Revoked"));
  controller.invalidateAccess(new RuntimeError("forbidden", "Still revoked"));
  assert.equal(denials, 1);
  assert.equal(controller.getSnapshot().record, null);
  assert.deepEqual(controller.getSnapshot().views, {});
  controller.dispose();
  assert.equal(controller.getSnapshot().pending, null);
  assert.equal(controller.getSnapshot().dirty, false);
});
