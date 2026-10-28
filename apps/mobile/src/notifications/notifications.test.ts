import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import type { RuntimeAdapter, RuntimeRecord } from "../runtime/types";
import { fullTemplates } from "../full/catalog";
import { inboxPage, runsPage, reminderPage, type InboxItem } from "./contracts";
import { NotificationsController } from "./NotificationsController";
import { NotificationJournal } from "./NotificationJournal";
import { AutomationRunsController } from "./AutomationRunsController";
import { collapsedReminder, withReminders } from "./withReminders";
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
};
function storage(rows = new Map<string, string>()) {
  return hostStores(new HostLifetime({ ...scope, appId: "inbox" }), {
    async read(key) {
      return rows.get(key) ?? null;
    },
    async change(key, update) {
      const next = update(rows.get(key) ?? null);
      if (next === null) rows.delete(key);
      else rows.set(key, next);
    },
  });
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => (resolve = r));
  return { promise, resolve };
}
const item = (suffix = "one"): InboxItem => ({
  id: `notification_${suffix}`,
  appId: "app",
  runId: `run_${suffix}`,
  recordId: `record_${suffix}`,
  collectionId: "tasks",
  title: "A reminder",
  body: "Open this item",
  createdAt: "2030-01-01T00:00:00.000001Z",
  isRead: false,
});
const page = (items: InboxItem[], nextCursor: string | null = null) => ({
  items,
  nextCursor,
});
const run = (suffix = "one") => ({
  id: `run_${suffix}`,
  ruleId: "rule",
  recordId: `record_${suffix}`,
  status: "pending",
  dueAt: "2030-01-01T00:00:00Z",
  nextAttemptAt: "2030-01-01T00:00:00Z",
  attempts: 0,
  errorCategory: null,
  recipientCount: 0,
});
const row = (
  recordId = "record_one",
  collectionId = "tasks",
): RuntimeRecord => ({
  id: recordId,
  collectionId,
  data: { title: "Current record" },
  revision: 1,
  writtenUnderVersionId: "older_version",
  capacity: null,
  allocated: null,
  claimed: false,
  allowedActions: [],
});
function adapter(change: Partial<RuntimeAdapter> = {}): RuntimeAdapter {
  return {
    appId: "app",
    versionId: "version",
    spec: fullTemplates.find((t) => t.id === "planner")!.spec,
    preview: false,
    role: "viewer",
    archived: false,
    approvedRuleIds: [],
    features: new Set(["members", "imageRead"]),
    query: async () => ({
      records: [],
      total: 0,
      nextCursor: null,
      versionId: "version",
    }),
    get: async (id) => row(id),
    summary: async () => ({ total: 0, groups: {}, versionId: "version" }),
    aggregate: async () => ({
      total: 0,
      value: null,
      groups: [],
      versionId: "version",
    }),
    execute: async () => ({
      recordId: "record",
      revision: 1,
      message: "Saved",
    }),
    permits: () => false,
    members: async () => [],
    reminderState: async () => ({ kind: "none", label: "Base" }),
    readImage: async () => ({ uri: "private://memory" }),
    pickImage: async () => null,
    uploadImage: async () => "asset",
    watch: () => () => {},
    dispose: () => {},
    ...change,
  };
}
test("strict backend DTOs preserve nullable removed targets and reject recipient disclosure, cursor forgery and invalid run/reminder scopes", () => {
  const removed = { ...item(), recordId: null, collectionId: null };
  assert.equal(inboxPage(page([removed])).items[0].recordId, null);
  assert.throws(() =>
    inboxPage(page([{ ...item(), recipientIds: ["foreign"] } as never])),
  );
  assert.throws(() => inboxPage(page([{ ...item(), collectionId: null }])));
  assert.throws(() => inboxPage(page([item()], "other_cursor")));
  assert.throws(() =>
    runsPage({
      runs: [{ ...run(), recipientIds: ["foreign"] }],
      nextCursor: null,
    }),
  );
  assert.equal(
    runsPage({ runs: [{ ...run(), ruleId: null }], nextCursor: null }).runs[0]
      .ruleId,
    null,
  );
  assert.throws(() =>
    reminderPage({ versionId: "other", states: [] }, "version", []),
  );
  assert.throws(() =>
    reminderPage(
      {
        versionId: "version",
        states: [
          {
            ruleId: "foreign",
            state: "pending",
            scheduledAt: null,
            eligible: true,
            recipientCount: 0,
          },
        ],
      },
      "version",
      ["rule"],
    ),
  );
});
test("read receipt is persisted before transport; lost response survives close/reopen with exact original identity and no automatic replay", async () => {
  const rows = new Map<string, string>();
  let lost = true,
    ids = 0;
  const writes: Record<string, unknown>[] = [];
  const transport = async (request: Record<string, unknown>) => {
    if (request.op === "spec.inbox") return page([item()]);
    assert.ok(rows.has("notification-read"));
    writes.push(request);
    if (lost) throw new Error("lost response");
    return { notificationId: request.notificationId, isRead: true };
  };
  let controller = new NotificationsController({
    scope,
    host: storage(rows),
    transport,
    newId: () => `op_${++ids}`,
  });
  await controller.load();
  await controller.markRead(controller.getSnapshot().items[0]);
  assert.equal(controller.getSnapshot().phase, "uncertain");
  assert.equal(controller.getSnapshot().items[0].isRead, false);
  await controller.acknowledgeRejection();
  assert.equal(controller.getSnapshot().pending?.operationId, "op_1");
  controller.dispose();
  controller = new NotificationsController({
    scope,
    host: storage(rows),
    transport,
    newId: () => `op_${++ids}`,
  });
  await controller.load();
  assert.equal(writes.length, 1);
  assert.equal(ids, 1);
  lost = false;
  await controller.retry();
  assert.deepEqual(writes[1], writes[0]);
  assert.equal(controller.getSnapshot().items[0].isRead, true);
  assert.equal(rows.has("notification-read"), false);
  controller.dispose();
});
test("persistence failure sends nothing, failed durable clear retains uncertainty, and mismatched acknowledgement never marks another notification", async () => {
  const host = storage();
  const failing = new NotificationJournal(
    {
      read: async () => null,
      compareAndSwap: async () => {
        throw new Error("disk");
      },
    },
    host.lifetime,
  );
  await assert.rejects(
    failing.prepare({
      op: "spec.readNotification",
      appId: "app",
      runId: "run",
      notificationId: "notification",
      operationId: "op",
    }),
  );
  let sent = 0;
  await assert.rejects(
    failing.send(async () => {
      sent++;
      return {};
    }),
  );
  assert.equal(sent, 0);
  const command = {
    op: "spec.readNotification" as const,
    appId: "app",
    runId: "run",
    notificationId: "notification",
    operationId: "op",
  };
  const journal = new NotificationJournal(host.storage, host.lifetime);
  await journal.prepare(command);
  await assert.rejects(
    journal.send(async () => ({ notificationId: "other", isRead: true })),
  );
  assert.equal(journal.phase, "uncertain");
  assert.ok(await host.storage.read("notification-read"));
  const blocked = new NotificationJournal(
    {
      read: (key) => host.storage.read(key),
      compareAndSwap: async () => false,
    },
    host.lifetime,
  );
  await blocked.recover();
  await assert.rejects(
    blocked.send(async () => ({
      notificationId: "notification",
      isRead: true,
    })),
  );
  assert.equal(blocked.phase, "uncertain");
  assert.ok(await host.storage.read("notification-read"));
  host.lifetime.dispose();
});
test("refresh wins over an out-of-order inbox page; repeated/stale page never duplicates loaded items", async () => {
  const delayed = deferred<unknown>();
  let requests = 0;
  const controller = new NotificationsController({
    scope,
    host: storage(),
    newId: () => "op",
    transport: async (request) => {
      requests++;
      if (requests === 1) return page([item()], item().id);
      if (request.afterId) return delayed.promise;
      return page([item("fresh")]);
    },
  });
  await controller.load();
  const older = controller.load(true);
  await controller.load();
  delayed.resolve(page([item("older")]));
  await older;
  assert.deepEqual(
    controller.getSnapshot().items.map((v) => v.id),
    ["notification_fresh"],
  );
  controller.dispose();
});
test("account disposal fences late private inbox and receipt responses and keeps unresolved encrypted command", async () => {
  const response = deferred<unknown>(),
    rows = new Map<string, string>();
  const controller = new NotificationsController({
    scope,
    host: storage(rows),
    newId: () => "op",
    transport: async (request) =>
      request.op === "spec.inbox" ? page([item()]) : response.promise,
  });
  await controller.load();
  const writing = controller.markRead(item());
  await new Promise((resolve) => setTimeout(resolve, 0));
  controller.dispose();
  response.resolve({ notificationId: item().id, isRead: true });
  await writing;
  assert.deepEqual(controller.getSnapshot().items, []);
  assert.ok(rows.has("notification-read"));
  const late = deferred<unknown>(),
    reader = new NotificationsController({
      scope,
      host: storage(),
      newId: () => "op",
      transport: async () => late.promise,
    });
  const loading = reader.load();
  reader.dispose();
  late.resolve(page([item()]));
  await loading;
  assert.deepEqual(reader.getSnapshot().items, []);
});
test("app-only forbidden read receipt hides that app, retains exact rejection and does not expire account; 401 does expire it", async () => {
  let expired = 0,
    denied = false;
  const controller = new NotificationsController({
    scope,
    host: storage(),
    newId: () => "op",
    onUnauthenticated: () => expired++,
    transport: async (request) =>
      request.op === "spec.inbox"
        ? page([item(), { ...item("two"), appId: "other" }])
        : Promise.reject(
            new BackendError("Forbidden", "forbidden", "service", false, 403),
          ),
  });
  await controller.load();
  await controller.markRead(item());
  assert.equal(expired, 0);
  assert.deepEqual(
    controller.getSnapshot().items.map((v) => v.appId),
    ["other"],
  );
  assert.equal(controller.getSnapshot().phase, "rejected");
  await controller.acknowledgeRejection();
  assert.equal(controller.getSnapshot().pending, null);
  controller.dispose();
  const unauthorized = new NotificationsController({
    scope,
    host: storage(),
    newId: () => "op",
    onUnauthenticated: () => expired++,
    transport: async () => {
      denied = true;
      throw new BackendError(
        "Sign in",
        "expired",
        "unauthenticated",
        false,
        401,
      );
    },
  });
  await unauthorized.load();
  assert.equal(denied, true);
  assert.equal(expired, 1);
  assert.deepEqual(unauthorized.getSnapshot().items, []);
});
test("notification targets require current matching live adapter and runtime record collection; removed or foreign records never navigate", async () => {
  const controller = new NotificationsController({
    scope,
    host: storage(),
    newId: () => "op",
    transport: async () => page([item()]),
  });
  await controller.load();
  let gets = 0;
  assert.equal(
    await controller.verifyTarget(item(), async () =>
      adapter({
        appId: "foreign",
        get: async () => {
          gets++;
          return row();
        },
      }),
    ),
    null,
  );
  assert.equal(gets, 0);
  assert.equal(
    await controller.verifyTarget(item(), async () =>
      adapter({ get: async () => row("record_one", "foreign_collection") }),
    ),
    null,
  );
  const target = await controller.verifyTarget(item(), async () => adapter());
  assert.equal(target?.appId, "app");
  assert.equal(target?.versionId, "version");
  assert.equal(target?.record.id, "record_one");
  const delayed = deferred<RuntimeRecord>();
  const opening = controller.verifyTarget(item(), async () =>
    adapter({ get: () => delayed.promise }),
  );
  await new Promise((resolve) => setTimeout(resolve, 0));
  controller.dispose();
  delayed.resolve(row());
  assert.equal(await opening, null);
});
test("run history requires each backend read, clears on role loss without global expiry, and fences stale pages/disposal", async () => {
  const lifetime = new HostLifetime({ ...scope, appId: "app" }),
    delayed = deferred<unknown>();
  let calls = 0,
    expired = 0;
  const controller = new AutomationRunsController({
    appId: "app",
    lifetime,
    onUnauthenticated: () => expired++,
    transport: async (request) => {
      calls++;
      if (calls === 1) return { runs: [run()], nextCursor: "run_one" };
      if (request.afterId) return delayed.promise;
      throw new BackendError("Forbidden", "forbidden", "service", false, 403);
    },
  });
  await controller.load();
  const more = controller.load(true);
  await controller.load();
  assert.equal(controller.getSnapshot().denied, true);
  assert.equal(expired, 0);
  delayed.resolve({ runs: [run("old")], nextCursor: null });
  await more;
  assert.deepEqual(controller.getSnapshot().runs, []);
  controller.dispose();
  lifetime.dispose();
});
test("reminder wrapper delegates all media/features and leaves approvals unchanged; authoritative rule state controls label", async () => {
  const lifetime = new HostLifetime({ ...scope, appId: "app" });
  const base = adapter();
  const rule = base.spec.automationRequests[0].id;
  const calls: Record<string, unknown>[] = [];
  const wrapped = withReminders(
    base,
    async (request) => {
      calls.push(request);
      return {
        versionId: "version",
        states: [
          {
            ruleId: rule,
            state: "disabled",
            scheduledAt: "2030-01-01T00:00:00Z",
            eligible: false,
            recipientCount: 0,
          },
        ],
      };
    },
    lifetime,
    { effects: ["notifyOwner"] },
  );
  assert.equal(wrapped.features.has("reminders"), true);
  assert.equal(wrapped.features.has("imageRead"), true);
  assert.deepEqual(wrapped.approvedRuleIds, []);
  assert.equal((await wrapped.readImage("asset")).uri, "private://memory");
  const state = await wrapped.reminderState("record_one");
  assert.equal(state.kind, "none");
  assert.match(state.label, /Disabled/);
  assert.doesNotMatch(state.label, /cheduled/);
  assert.deepEqual(calls[0], {
    op: "spec.reminderState",
    appId: "app",
    versionId: "version",
    recordId: "record_one",
  });
  wrapped.dispose();
  lifetime.dispose();
});
test("reminders are unavailable without operational capabilities; disposal fences late data and preserves delegate lifecycle", async () => {
  const lifetime = new HostLifetime({ ...scope, appId: "app" });
  let calls = 0,
    disposed = 0;
  const response = deferred<unknown>();
  const base = adapter({ dispose: () => disposed++ });
  const off = withReminders(
    base,
    async () => {
      calls++;
      return {};
    },
    lifetime,
    { effects: [] },
  );
  assert.equal(off.features.has("reminders"), false);
  await assert.rejects(off.reminderState("record_one"));
  assert.equal(calls, 0);
  off.dispose();
  assert.equal(disposed, 1);
  const active = new HostLifetime({ ...scope, appId: "app" });
  const wrapped = withReminders(
    adapter({ dispose: () => disposed++ }),
    () => response.promise,
    active,
    { effects: ["notifyOwner"] },
  );
  const reading = wrapped.reminderState("record_one");
  active.dispose();
  response.resolve({ versionId: "version", states: [] });
  await assert.rejects(reading);
  wrapped.dispose();
  assert.equal(disposed, 2);
  assert.throws(() =>
    withReminders(
      adapter({ preview: true }),
      async () => ({}),
      new HostLifetime({ ...scope, appId: "preview" }),
      { effects: ["notifyOwner"] },
    ),
  );
});
test("collapsed statuses never call disabled, failed, suppressed, unenrolled or unset reminders scheduled", () => {
  for (const state of [
    "disabled",
    "failed",
    "suppressed",
    "unenrolled",
    "unset",
  ] as const) {
    const result = collapsedReminder([
      {
        ruleId: "rule",
        state,
        scheduledAt: "2030-01-01T00:00:00Z",
        eligible: false,
        recipientCount: 0,
      },
    ]);
    assert.notEqual(result.kind, "scheduled");
    assert.doesNotMatch(result.label, /cheduled/);
  }
  const pending = collapsedReminder([
    {
      ruleId: "rule",
      state: "pending",
      scheduledAt: null,
      eligible: false,
      recipientCount: 0,
    },
  ]);
  assert.equal(pending.kind, "pending");
  assert.match(pending.label, /Pending.*ineligible/);
  const delivered = collapsedReminder([
    {
      ruleId: "rule",
      state: "delivered",
      scheduledAt: null,
      eligible: true,
      recipientCount: 2,
    },
  ]);
  assert.equal(delivered.kind, "delivered");
  assert.match(delivered.label, /2 recipients/);
});
test("a later permission denial cannot turn an older uncertain receipt into a discardable rejection", async () => {
  const rows = new Map<string, string>();
  let lost = true,
    writes = 0;
  const controller = new NotificationsController({
    scope,
    host: storage(rows),
    newId: () => "original",
    transport: async (request) => {
      if (request.op === "spec.inbox")
        return page([item(), { ...item("two"), appId: "other" }]);
      writes++;
      if (lost) throw new Error("lost response");
      throw new BackendError("Forbidden", "forbidden", "service", false, 403);
    },
  });
  await controller.load();
  await controller.markRead(item());
  lost = false;
  await controller.retry();
  assert.equal(controller.getSnapshot().phase, "uncertain");
  await controller.acknowledgeRejection();
  assert.equal(controller.getSnapshot().pending?.operationId, "original");
  assert.ok(rows.has("notification-read"));
  await controller.markRead({ ...item("two"), appId: "other" });
  assert.equal(writes, 2);
  controller.dispose();
});
test("wrong account storage is rejected, duplicate pages cannot accumulate, and run results after account close stay hidden", async () => {
  assert.throws(
    () =>
      new NotificationsController({
        scope: { ...scope, accountId: "bob" },
        host: storage(),
        newId: () => "op",
        transport: async () => page([]),
      }),
  );
  let pageNumber = 0;
  const controller = new NotificationsController({
    scope,
    host: storage(),
    newId: () => "op",
    transport: async () => {
      pageNumber++;
      return page([item()], item().id);
    },
  });
  await controller.load();
  await controller.load(true);
  assert.equal(pageNumber, 2);
  assert.equal(controller.getSnapshot().items.length, 1);
  assert.match(controller.getSnapshot().error!, /overlaps/);
  controller.dispose();
  const lifetime = new HostLifetime({ ...scope, appId: "app" }),
    response = deferred<unknown>();
  const runs = new AutomationRunsController({
    appId: "app",
    lifetime,
    transport: async () => response.promise,
  });
  const loading = runs.load();
  lifetime.dispose();
  response.resolve({ runs: [run()], nextCursor: null });
  await loading;
  assert.deepEqual(runs.getSnapshot().runs, []);
});
test("reminder composition forwards image authorization context and optional lifecycle activation", async () => {
  const lifetime = new HostLifetime({ ...scope, appId: "app" }),
    activations: boolean[] = [];
  let received: unknown;
  const base = adapter({
    setActive: (active) => activations.push(active),
    uploadImage: async (_image, context) => {
      received = context;
      return "asset";
    },
  });
  const wrapped = withReminders(base, async () => ({}), lifetime, {
    effects: ["notifyOwner"],
  });
  wrapped.setActive?.(true);
  wrapped.setActive?.(false);
  const context = {
    versionId: "version",
    actionId: "create",
    fieldId: "photo",
  };
  await wrapped.uploadImage(
    { bytes: new Uint8Array([1]), mimeType: "image/png", name: "selected.png" },
    context,
  );
  assert.equal(received, context);
  assert.deepEqual(activations, [true, false]);
  wrapped.dispose();
  assert.throws(() => wrapped.setActive?.(true));
  lifetime.dispose();
});
test("a lost local persistence response sends nothing and explicit refresh recovers that original operation", async () => {
  const rows = new Map<string, string>(),
    local = storage(rows),
    swap = local.storage.compareAndSwap.bind(local.storage);
  let first = true,
    ids = 0;
  const writes: Record<string, unknown>[] = [];
  local.storage.compareAndSwap = async (kind, before, next) => {
    const result = await swap(kind, before, next);
    if (next !== null && first) {
      first = false;
      throw new Error("local acknowledgement lost");
    }
    return result;
  };
  const controller = new NotificationsController({
    scope,
    host: local,
    newId: () => `op_${++ids}`,
    transport: async (request) => {
      if (request.op === "spec.inbox") return page([item()]);
      writes.push(request);
      return { notificationId: request.notificationId, isRead: true };
    },
  });
  await controller.load();
  await controller.markRead(item());
  assert.equal(writes.length, 0);
  assert.ok(rows.has("notification-read"));
  await controller.load();
  assert.equal(controller.getSnapshot().pending?.operationId, "op_1");
  assert.equal(ids, 1);
  await controller.retry();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].operationId, "op_1");
  controller.dispose();
});
test("concurrent recovery calls share one read and cannot replace a newly prepared command", async () => {
  const response = deferred<unknown | null>();
  let reads = 0,
    current: unknown | null = null;
  const lifetime = new HostLifetime({ ...scope, appId: "inbox" });
  const journal = new NotificationJournal(
    {
      read: async () => {
        reads++;
        return response.promise;
      },
      compareAndSwap: async (_kind, before, next) => {
        if (JSON.stringify(current) !== JSON.stringify(before)) return false;
        current = next;
        return true;
      },
    },
    lifetime,
  );
  const recovering = journal.recover(),
    preparing = journal.prepare({
      op: "spec.readNotification",
      appId: "app",
      runId: "run",
      notificationId: "notification",
      operationId: "original",
    });
  assert.equal(reads, 1);
  response.resolve(null);
  await Promise.all([recovering, preparing]);
  assert.equal(journal.pending?.operationId, "original");
  assert.equal(reads, 1);
  journal.dispose();
  lifetime.dispose();
});
