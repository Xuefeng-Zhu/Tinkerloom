import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import test from "node:test";
import { decodeAppSpec } from "../spec/decode";
import type { AppSpec, JsonValue } from "../spec/types";
import type { RuntimeCommand, RuntimeRecord } from "./types";
import { PreviewRuntimeAdapter } from "./preview";
import { RuntimeController } from "./controller";
import { RuntimeError, runtimeError } from "./errors";
import { BackendError } from "../backend/errors";
import { MemoryRuntimeCommandStore } from "./commands";
import type { RuntimeCommandStore } from "./commands";
import {
  FunctionRuntimeAdapter,
  decodeRuntimeManifest,
} from "./functionAdapter";
import {
  aggregateRecords,
  buildViewQuery,
  compareTyped,
  dateBuckets,
  localDayRange,
  matchingRecords,
  monthBuckets,
} from "./query";
import {
  decodeTimer,
  MemoryUtilityTimerStore,
  phaseAt,
  remainingAt,
  UtilityTimerController,
} from "./timer";
import { runtimeJsonSnapshot } from "./json";

const root = new URL(
  "../../../../appwrite_backend/packages/appnest_spec/",
  import.meta.url,
);
const fixture = (name: string): AppSpec =>
  decodeAppSpec(
    JSON.parse(readFileSync(new URL(`fixtures/${name}.json`, root), "utf8")),
  );
const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
const failure = (code: string) => (error: unknown) =>
  error instanceof RuntimeError && error.code === code;
let operation = 0;
const command = (
  adapter: PreviewRuntimeAdapter,
  actionId: string,
  input: Record<string, JsonValue>,
  record?: RuntimeRecord,
  operationId = `operation_${++operation}`,
): RuntimeCommand => ({
  appId: adapter.appId,
  versionId: adapter.versionId,
  operationId,
  actionId,
  input,
  ...(record
    ? { targetRecordId: record.id, expectedRecordRevision: record.revision }
    : {}),
});
const durableStore = (): RuntimeCommandStore => {
  const memory = new MemoryRuntimeCommandStore();
  return {
    durability: "durable",
    read: () => memory.read(),
    save: (c) => memory.save(c),
    clear: (id) => memory.clear(id),
  };
};
function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

test("all original positive fixtures seed isolated preview collections and validate every row", async () => {
  const names = readdirSync(new URL("fixtures/", root)).filter(
    (name) => name.endsWith(".json") && name !== "unsupported.json",
  );
  assert.equal(names.length, 12);
  for (const name of names) {
    const spec = fixture(name.slice(0, -5)),
      adapter = new PreviewRuntimeAdapter(spec, {
        now: new Date("2026-10-28T12:00:00Z"),
      });
    for (const collection of spec.collections) {
      const page = await adapter.query(collection.id, { limit: 100 });
      assert.ok(page.records.length >= 3);
      assert.equal(page.total, page.records.length);
      assert.ok(
        page.records.every(
          (row) => row.collectionId === collection.id && row.revision === 1,
        ),
      );
    }
    adapter.dispose();
  }
});
test("preview instances do not share records, receipts, listeners or mutations", async () => {
  const a = new PreviewRuntimeAdapter(fixture("notes")),
    b = new PreviewRuntimeAdapter(fixture("notes"));
  await a.execute(command(a, "addRecord", { data: { title: "Only in A" } }));
  assert.equal((await a.query("notes", {})).total, 4);
  assert.equal((await b.query("notes", {})).total, 3);
  a.dispose();
  assert.equal((await b.query("notes", {})).total, 3);
  await assert.rejects(a.query("notes", {}), failure("disposed"));
  b.dispose();
});
test("create and patch receipts replay exact original results after later edits", async () => {
  const a = new PreviewRuntimeAdapter(fixture("notes")),
    create = command(a, "addRecord", { data: { title: "Created" } }),
    first = await a.execute(create),
    row = await a.get(first.recordId);
  const edit = command(a, "editRecord", { data: { title: "Edited" } }, row),
    second = await a.execute(edit);
  assert.equal(second.revision, 2);
  assert.deepEqual(await a.execute(create), first);
  assert.deepEqual(await a.execute(edit), second);
  assert.equal((await a.get(first.recordId)).data.title, "Edited");
  await assert.rejects(
    a.execute({ ...create, input: { data: { title: "Different" } } }),
    failure("operation_conflict"),
  );
  await assert.rejects(
    a.execute(command(a, "editRecord", { data: { title: "Stale" } }, row)),
    failure("revision_conflict"),
  );
});
test("workflow and assignment use dedicated actions and eligible members", async () => {
  const a = new PreviewRuntimeAdapter(fixture("chores"));
  await assert.rejects(
    a.execute(
      command(a, "addChore", { data: { title: "Invalid", status: "Done" } }),
    ),
    failure("invalid_input"),
  );
  const created = await a.execute(
    command(a, "addChore", { data: { title: "New chore", status: "Open" } }),
  );
  let row = await a.get(created.recordId);
  await assert.rejects(
    a.execute(command(a, "editChore", { data: { status: "Done" } }, row)),
    failure("invalid_input"),
  );
  await assert.rejects(
    a.execute(
      command(a, "editChore", { data: { assignee: "preview_member" } }, row),
    ),
    failure("invalid_input"),
  );
  await assert.rejects(
    a.execute(command(a, "moveChore", { value: "Done" }, row)),
    failure("invalid_transition"),
  );
  await a.execute(command(a, "moveChore", { value: "Doing" }, row));
  row = await a.get(row.id);
  assert.equal(row.data.status, "Doing");
  await assert.rejects(
    a.execute(command(a, "assignChore", { value: "not_a_member" }, row)),
    failure("invalid_input"),
  );
  await a.execute(command(a, "assignChore", { value: "preview_member" }, row));
  row = await a.get(row.id);
  assert.equal(row.data.assignee, "preview_member");
  await a.execute(command(a, "assignChore", { value: null }, row));
  assert.equal((await a.get(row.id)).data.assignee, undefined);
});
test("capacity create/configure/claim/release preserve bounds and own idempotent claims", async () => {
  const a = new PreviewRuntimeAdapter(fixture("volunteer")),
    created = await a.execute(
      command(a, "addShift", {
        data: { title: "One place", startsAt: "2030-01-05T10:00:00Z" },
        capacity: 1,
      }),
    );
  let row = await a.get(created.recordId);
  await a.execute(command(a, "join", {}, row));
  row = await a.get(row.id);
  assert.equal(row.allocated, 1);
  assert.equal(row.claimed, true);
  assert.equal(
    row.revision,
    1,
    "Capacity counters use pool semantics, not record edits",
  );
  await a.execute(command(a, "join", {}, row));
  row = await a.get(row.id);
  assert.equal(row.allocated, 1);
  await assert.rejects(
    a.execute(command(a, "configure", { capacity: 0 }, row)),
    failure("invalid_input"),
  );
  await a.execute(command(a, "leave", {}, row));
  row = await a.get(row.id);
  assert.equal(row.allocated, 0);
  await a.execute(command(a, "configure", { capacity: 0 }, row));
  row = await a.get(row.id);
  await assert.rejects(
    a.execute(command(a, "join", {}, row)),
    failure("exhausted_capacity"),
  );
});
test("three policy presets constrain member affordances and preview writes", async () => {
  const personal = new PreviewRuntimeAdapter(fixture("notes"), {
    role: "member",
  });
  assert.equal(personal.permits(personal.spec.actions[0]), false);
  await assert.rejects(
    personal.execute(
      command(personal, "addRecord", { data: { title: "Denied" } }),
    ),
    failure("forbidden"),
  );
  const workflow = new PreviewRuntimeAdapter(fixture("chores"), {
    role: "member",
  });
  assert.ok(workflow.spec.actions.every((action) => workflow.permits(action)));
  const capacity = new PreviewRuntimeAdapter(fixture("volunteer"), {
    role: "member",
  });
  assert.equal(
    capacity.permits(
      capacity.spec.actions.find((action) => action.id === "join")!,
    ),
    true,
  );
  assert.equal(
    capacity.permits(
      capacity.spec.actions.find((action) => action.id === "addShift")!,
    ),
    false,
  );
});
test("preview pages bind cursors to filters and sort, and totals precede pagination", async () => {
  const a = new PreviewRuntimeAdapter(fixture("reading"));
  const page = await a.query("books", {
    limit: 1,
    sort: [{ fieldId: "title", descending: false }],
  });
  assert.equal(page.total, 3);
  assert.equal(page.records.length, 1);
  assert.ok(page.nextCursor);
  const second = await a.query("books", {
    limit: 1,
    sort: [{ fieldId: "title", descending: false }],
    cursor: page.nextCursor!,
  });
  assert.notEqual(page.records[0].id, second.records[0].id);
  await assert.rejects(
    a.query("books", {
      limit: 1,
      sort: [{ fieldId: "title", descending: true }],
      cursor: page.nextCursor!,
    }),
    failure("invalid_cursor"),
  );
});
test("complete collection summaries/aggregates never count only the loaded page", async () => {
  const a = new PreviewRuntimeAdapter(fixture("habitTracker")),
    page = await a.query("checkins", { limit: 1 }),
    total = await a.aggregate(
      "checkins",
      { limit: 1 },
      { metric: "sum", fieldId: "minutes" },
    );
  assert.equal(page.records.length, 1);
  assert.equal(total.total, 14);
  assert.equal(total.value, 460);
  const summary = await a.summary("checkins", { limit: 1 }, "category");
  assert.equal(summary.total, 14);
  assert.equal(
    Object.values(summary.groups).reduce((x, y) => x + y, 0),
    14,
  );
});
test("typed sorting is deterministic, nulls last both ways, preserves timestamp microseconds and negative years", () => {
  const c = fixture("reading").collections[0];
  const row = (id: string, rating?: number): RuntimeRecord => ({
    id,
    collectionId: c.id,
    data: {
      title: "Same",
      status: "To read",
      ...(rating === undefined ? {} : { rating }),
    },
    revision: 1,
    writtenUnderVersionId: "v",
    capacity: null,
    allocated: null,
    claimed: false,
    allowedActions: [],
  });
  assert.deepEqual(
    matchingRecords(c, [row("b", 1), row("A", 1), row("z"), row("a", 3)], {
      sort: [{ fieldId: "rating", descending: true }],
    }).map((r) => r.id),
    ["a", "A", "b", "z"],
  );
  assert.ok(
    compareTyped(
      "timestamp",
      "2030-01-01T00:00:00.000001Z",
      "2030-01-01T00:00:00.000002Z",
    ) < 0,
  );
  assert.ok(
    compareTyped("timestamp", "-0001-01-01T00:00:00Z", "0000-01-01T00:00:00Z") <
      0,
  );
  assert.ok(compareTyped("text", "A", "a") < 0);
});
test("empty numeric averages are null and date buckets are half open", () => {
  const spec = fixture("habitTracker"),
    c = spec.collections[0],
    rows: RuntimeRecord[] = [
      {
        id: "a",
        collectionId: c.id,
        data: { title: "At boundary", loggedAt: "2030-01-02T00:00:00.000001Z" },
        revision: 1,
        writtenUnderVersionId: "v",
        capacity: null,
        allocated: null,
        claimed: false,
        allowedActions: [],
      },
    ];
  const average = aggregateRecords(
    c,
    rows,
    {},
    { metric: "average", fieldId: "minutes" },
    "v",
  );
  assert.equal(average.value, null);
  const dates = aggregateRecords(
    c,
    rows,
    {},
    {
      metric: "count",
      dateFieldId: "loggedAt",
      buckets: [
        {
          key: "before",
          start: "2030-01-01T00:00:00Z",
          end: "2030-01-02T00:00:00.000001Z",
        },
        {
          key: "after",
          start: "2030-01-02T00:00:00.000001Z",
          end: "2030-01-03T00:00:00Z",
        },
      ],
    },
    "v",
  );
  assert.deepEqual(
    dates.groups.map((g) => g.count),
    [0, 1],
  );
});
test("local day/month/chart buckets honor DST and calendar boundaries", () => {
  const original = process.env.TZ;
  process.env.TZ = "America/Los_Angeles";
  try {
    const spring = localDayRange(new Date(2026, 2, 8)),
      fall = localDayRange(new Date(2026, 10, 1));
    assert.equal(
      Date.parse(spring.end) - Date.parse(spring.start),
      23 * 3600000,
    );
    assert.equal(Date.parse(fall.end) - Date.parse(fall.start), 25 * 3600000);
    assert.equal(monthBuckets(new Date(2028, 1, 8)).length, 29);
    const weeks = dateBuckets(new Date(2026, 9, 28), "week", 2);
    assert.equal(new Date(weeks[1].start).getDay(), 1);
    assert.equal(weeks[0].end, weeks[1].start);
  } finally {
    if (original === undefined) delete process.env.TZ;
    else process.env.TZ = original;
  }
});
test("calendar query uses the selected civil day and timeline has a real unset filter", () => {
  const spec = fixture("projectHub"),
    calendar = spec.views.find((v) => v.type === "calendar")!,
    timeline = spec.views.find((v) => v.type === "timeline")!;
  const query = buildViewQuery(spec, calendar, {
    selectedDay: new Date(2026, 9, 28),
  });
  assert.deepEqual(
    query.filters?.map((f) => f.operator),
    ["gte", "lt"],
  );
  assert.equal(query.sort?.[0].fieldId, "dueAt");
  assert.equal(
    buildViewQuery(spec, timeline, { undated: true }).filters?.at(-1)?.value,
    null,
  );
});
test("controller retains exact command through unknown outcome, blocks a competing write/navigation, and retries its key", async () => {
  const adapter = new PreviewRuntimeAdapter(fixture("notes")),
    original = adapter.execute.bind(adapter);
  let sent = 0;
  const seen: RuntimeCommand[] = [];
  adapter.execute = async (request) => {
    seen.push(clone(request));
    if (++sent === 1) {
      await original(request);
      throw new Error("Lost response");
    }
    return original(request);
  };
  const controller = new RuntimeController(adapter, () => "retained_key");
  const input = { data: { title: "Saved once" } };
  assert.equal(await controller.execute("addRecord", input), null);
  input.data.title = "Changed later";
  assert.equal(controller.getSnapshot().pending?.status, "uncertain");
  assert.equal(controller.navigate({ pageId: "homePage" }), false);
  await assert.rejects(
    controller.execute("addRecord", { data: { title: "Second" } }),
    failure("pending_command"),
  );
  const outcome = await controller.retry();
  assert.ok(outcome);
  assert.deepEqual(seen[0], seen[1]);
  assert.equal((await adapter.query("notes", {})).total, 4);
  assert.equal(controller.getSnapshot().pending, null);
  assert.equal((await adapter.get(outcome!.recordId)).data.title, "Saved once");
});
test("recovery across controller remount never auto sends and keeps original version/input", async () => {
  const adapter = new PreviewRuntimeAdapter(fixture("notes")),
    store = durableStore(),
    saved = command(
      adapter,
      "addRecord",
      { data: { title: "Recovered" } },
      undefined,
      "old_operation",
    );
  await store.save(saved);
  let calls = 0;
  const original = adapter.execute.bind(adapter);
  adapter.execute = async (input) => {
    calls++;
    assert.deepEqual(input, saved);
    return original(input);
  };
  const controller = new RuntimeController(
    adapter,
    () => "new_key",
    () => new Date(),
    store,
  );
  await controller.refresh();
  assert.equal(calls, 0);
  assert.equal(
    controller.getSnapshot().pending?.command.operationId,
    "old_operation",
  );
  assert.deepEqual(controller.getSnapshot().views, {});
  await controller.retry();
  assert.equal(calls, 1);
  assert.equal(await store.read(), null);
});
test("controller persists before sending, serializes competing calls, and never sends after a store failure", async () => {
  const adapter = new PreviewRuntimeAdapter(fixture("notes")),
    save = deferred<void>(),
    memory = durableStore();
  let calls = 0;
  adapter.execute = async () => {
    calls++;
    return { recordId: "r", revision: 1, message: "Saved" };
  };
  const store: RuntimeCommandStore = {
    durability: "durable",
    read: async () => null,
    save: async (value) => {
      await save.promise;
      await memory.save(value);
    },
    clear: (id) => memory.clear(id),
  };
  const controller = new RuntimeController(
      adapter,
      () => `key_${++operation}`,
      () => new Date(),
      store,
    ),
    first = controller.execute("addRecord", { data: { title: "First" } });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(calls, 0);
  await assert.rejects(
    controller.execute("addRecord", { data: { title: "Second" } }),
    failure("pending_command"),
  );
  save.resolve();
  await first;
  assert.equal(calls, 1);
  const failed = new RuntimeController(
    adapter,
    () => "failed",
    () => new Date(),
    {
      ...store,
      save: async () => {
        throw new Error("Disk full");
      },
    },
  );
  assert.equal(
    await failed.execute("addRecord", { data: { title: "Never sent" } }),
    null,
  );
  assert.equal(calls, 1);
  assert.equal(failed.getSnapshot().pending?.status, "failed");
});
test("live controller refuses writes without an injected durable store", async () => {
  const adapter = new PreviewRuntimeAdapter(fixture("notes"));
  Object.defineProperty(adapter, "preview", { value: false });
  const controller = new RuntimeController(adapter, () => "blocked");
  await assert.rejects(
    controller.execute("addRecord", { data: { title: "No" } }),
    failure("unavailable"),
  );
  assert.equal((await adapter.query("notes", {})).total, 3);
});
test("late read cannot overwrite a dirty editor or a newer location", async () => {
  const adapter = new PreviewRuntimeAdapter(fixture("notes")),
    original = adapter.query.bind(adapter),
    pending = deferred<Awaited<ReturnType<typeof original>>>();
  adapter.query = () => pending.promise;
  const controller = new RuntimeController(adapter, () => "id"),
    request = controller.refresh();
  await new Promise((resolve) => setImmediate(resolve));
  controller.setDirty(true);
  pending.resolve(await original("notes", {}));
  await request;
  assert.deepEqual(controller.getSnapshot().views, {});
  assert.equal(controller.getSnapshot().dirty, true);
});
test("controller refresh retains the loaded prefix and query changes reset pagination", async () => {
  const spec = fixture("notes");
  spec.views[0].query = { limit: 1 };
  const adapter = new PreviewRuntimeAdapter(spec),
    controller = new RuntimeController(adapter, () => "id");
  await controller.refresh();
  assert.equal(controller.getSnapshot().views.allEntries.records.length, 1);
  await controller.loadMore("allEntries");
  assert.equal(controller.getSnapshot().views.allEntries.records.length, 2);
  await controller.refresh();
  assert.equal(controller.getSnapshot().views.allEntries.records.length, 2);
  await controller.select("allEntries", {
    sort: { fieldId: "title", descending: true },
  });
  assert.equal(controller.getSnapshot().views.allEntries.records.length, 1);
});
test("focused detail record refreshes atomically and disappears on an authorization error", async () => {
  const adapter = new PreviewRuntimeAdapter(fixture("notes")),
    row = (await adapter.query("notes", {})).records[0],
    controller = new RuntimeController(adapter, () => "id");
  controller.focusRecord(row);
  await controller.refresh();
  assert.equal(controller.getSnapshot().record?.id, row.id);
  adapter.get = async () => {
    throw new RuntimeError("forbidden", "Access removed");
  };
  await controller.refresh();
  assert.equal(controller.getSnapshot().record, null);
  assert.equal(controller.getSnapshot().error?.code, "forbidden");
});
function manifest() {
  return decodeRuntimeManifest({
    id: "app",
    workspaceId: "workspace",
    name: "Notes",
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: { writeRecords: true },
    controlRevision: 0,
    allowedActions: ["addRecord", "editRecord"],
    version: {
      id: "version",
      number: 1,
      hash: "server_hash",
      spec: fixture("notes"),
    },
    draft: null,
  });
}
test("Function adapter enforces engine/current read version and collection-bound rows", async () => {
  assert.throws(
    () => decodeRuntimeManifest({ ...manifest(), engine: "bounded.v1" }),
    failure("unsupported_engine"),
  );
  const preview = new PreviewRuntimeAdapter(fixture("notes")),
    page = await preview.query("notes", {});
  const good = new FunctionRuntimeAdapter(manifest(), async (request) => ({
    ...page,
    versionId: request.versionId,
  }));
  assert.equal((await good.query("notes", {})).records.length, 3);
  const stale = new FunctionRuntimeAdapter(manifest(), async () => ({
    ...page,
    versionId: "old",
  }));
  await assert.rejects(
    stale.query("notes", {}),
    failure("definition_conflict"),
  );
  const wrong = new FunctionRuntimeAdapter(manifest(), async () => ({
    ...page,
    versionId: "version",
    records: [{ ...page.records[0], collectionId: "not_notes" }],
  }));
  await assert.rejects(wrong.query("notes", {}));
});
test("Function adapter retains old-version receipt request and treats unreadable write results as uncertain", async () => {
  const seen: Record<string, unknown>[] = [],
    adapter = new FunctionRuntimeAdapter(manifest(), async (request) => {
      seen.push(request);
      return {
        outcome: { recordId: "created", revision: 1, message: "Saved" },
      };
    }),
    request: RuntimeCommand = {
      appId: "app",
      versionId: "older_version",
      operationId: "retained",
      actionId: "addRecord",
      input: { data: { title: "Old definition" } },
    };
  assert.equal((await adapter.execute(request)).recordId, "created");
  assert.equal(seen[0].versionId, "older_version");
  const invalid = new FunctionRuntimeAdapter(manifest(), async () => ({
    outcome: {},
  }));
  await assert.rejects(
    invalid.execute(request),
    (error) => error instanceof RuntimeError && error.uncertain,
  );
  const empty = new FunctionRuntimeAdapter(manifest(), async () => null);
  await assert.rejects(
    empty.execute(request),
    (error) => error instanceof RuntimeError && error.uncertain,
  );
});
test("member directory fully pages shared op without sending versionId and detects repeated cursor", async () => {
  let call = 0;
  const adapter = new FunctionRuntimeAdapter(manifest(), async (request) => {
    assert.equal(request.op, "listMembers");
    assert.equal(Object.hasOwn(request, "versionId"), false);
    return ++call === 1
      ? { members: [{ actorId: "owner", role: "owner" }], nextCursor: "grant" }
      : {
          members: [
            { actorId: "member", role: "member" },
            { actorId: "revoked", role: null },
          ],
          nextCursor: null,
        };
  });
  assert.deepEqual(
    (await adapter.members()).map((m) => m.id),
    ["owner", "member"],
  );
  const looping = new FunctionRuntimeAdapter(manifest(), async () => ({
    members: [],
    nextCursor: "same",
  }));
  await assert.rejects(looping.members(), failure("invalid_response"));
});
test("live unavailable media/reminder paths never manufacture a response", async () => {
  const adapter = new FunctionRuntimeAdapter(manifest(), async () => {
    throw new Error("Must not call");
  });
  assert.equal(adapter.features.has("reminders"), false);
  await assert.rejects(adapter.reminderState("record"), failure("unavailable"));
  await assert.rejects(adapter.readImage("image"), failure("unavailable"));
  await assert.rejects(adapter.pickImage(), failure("unavailable"));
});
test("timer uses saved deadline across remounts and commits storage before publishing", async () => {
  const store = new MemoryUtilityTimerStore();
  let now = new Date("2030-01-01T10:00:00Z");
  const a = new UtilityTimerController(store, () => now);
  await a.change("timer", "start", 1);
  now = new Date(now.getTime() + 20000);
  assert.equal(remainingAt(a.stateFor("timer")!, now), 40000);
  a.dispose();
  const b = new UtilityTimerController(store, () => now);
  await b.load("timer", 1);
  assert.equal(remainingAt(b.stateFor("timer")!, now), 40000);
  await b.change("timer", "pause", 1);
  now = new Date(now.getTime() + 100000);
  assert.equal(remainingAt(b.stateFor("timer")!, now), 40000);
  await b.change("timer", "resume", 1);
  now = new Date(now.getTime() + 40000);
  assert.equal(phaseAt(b.stateFor("timer")!, now), "complete");
});
test("corrupt timer is not silently replaced and a failed write leaves previous state", async () => {
  assert.throws(() =>
    decodeTimer({
      version: 1,
      phase: "running",
      durationSeconds: 60,
      remainingMilliseconds: 60000,
      deadline: "2030-02-30T10:00:00Z",
    }),
  );
  const store = new MemoryUtilityTimerStore(),
    controller = new UtilityTimerController(store, () => new Date());
  await controller.load("timer", 1);
  const original = clone(controller.stateFor("timer"));
  store.write = async () => {
    throw new Error("Disk full");
  };
  await assert.rejects(controller.change("timer", "start", 1));
  assert.deepEqual(controller.stateFor("timer"), original);
});
test("runtime commands preserve forty large text fields beyond the smaller definition bound", async () => {
  const spec: AppSpec = {
    formatVersion: 1,
    name: "Large records",
    theme: "teal",
    icon: "book",
    requires: ["collections.v1", "records.create.v1", "views.list.v1"],
    collections: [
      {
        id: "items",
        label: "Items",
        fields: Array.from({ length: 40 }, (_, index) => ({
          id: `field_${index}`,
          label: `Field ${index}`,
          type: "text",
          required: true,
        })),
        behaviors: [],
      },
    ],
    views: [
      {
        id: "list",
        label: "Items",
        type: "list",
        collectionId: "items",
        actionIds: ["create"],
      },
    ],
    actions: [
      {
        id: "create",
        label: "Create",
        collectionId: "items",
        capability: "records.create.v1",
      },
    ],
    policyPresetRequest: "personalTracker.v1",
    automationRequests: [],
  };
  const adapter = new PreviewRuntimeAdapter(spec, { records: { items: [] } }),
    data = Object.fromEntries(
      spec.collections[0].fields.map((field) => [field.id, "织".repeat(10000)]),
    ),
    request = command(adapter, "create", { data });
  assert.ok(JSON.stringify(request).length > 128 * 1024);
  const outcome = await adapter.execute(request),
    value = (await adapter.get(outcome.recordId)).data.field_39;
  assert.ok(typeof value === "string");
  assert.equal(value.length, 10000);
});
test("runtime snapshots reject hidden executable hooks before serialization and bound encoded bytes", () => {
  let invoked = 0;
  const value = { input: { data: { title: "Safe" } } };
  Object.defineProperty(value.input.data, "toJSON", {
    value() {
      invoked++;
      return {};
    },
  });
  assert.throws(() => runtimeJsonSnapshot(value));
  assert.equal(invoked, 0);
  const accessor = { input: {} };
  Object.defineProperty(accessor.input, "hidden", {
    get() {
      invoked++;
      return "unsafe";
    },
  });
  assert.throws(() => runtimeJsonSnapshot(accessor));
  assert.equal(invoked, 0);
  assert.throws(
    () => runtimeJsonSnapshot({ input: "x".repeat(6 * 1024 * 1024) }),
    failure("request_too_large"),
  );
});
test("runtime definition and retained command snapshots cannot be mutated after validation", async () => {
  const adapter = new PreviewRuntimeAdapter(fixture("notes")),
    controller = new RuntimeController(adapter, () => "frozen");
  adapter.execute = async () => {
    throw new Error("Lost result");
  };
  await controller.execute("addRecord", { data: { title: "Original" } });
  assert.equal(Object.isFrozen(adapter.spec), true);
  const saved = controller.getSnapshot().pending!.command;
  assert.equal(Object.isFrozen(saved.input), true);
  assert.equal(Object.isFrozen(saved.input.data), true);
  assert.throws(() => {
    (saved.input.data as { title: string }).title = "Changed";
  });
});
test("shared authenticated transport errors retain definite rejection and uncertain outcome semantics", () => {
  assert.equal(
    runtimeError(
      new BackendError("Not allowed", "forbidden", "service", false, 403),
      true,
    ).uncertain,
    false,
  );
  assert.equal(
    runtimeError(
      new BackendError(
        "Transaction result unknown",
        "transaction_conflict",
        "service",
        false,
        409,
      ),
      true,
    ).uncertain,
    true,
  );
  assert.equal(
    runtimeError(
      new BackendError(
        "Unreadable response",
        "invalid_response",
        "invalid_response",
        false,
      ),
      true,
    ).uncertain,
    true,
  );
});
test("access failure during paging or mutation hides every cached record/editor and requires a fresh manifest", async () => {
  const spec = fixture("notes");
  spec.views[0].query = { limit: 1 };
  const adapter = new PreviewRuntimeAdapter(spec),
    controller = new RuntimeController(adapter, () => "lost_access");
  await controller.refresh();
  assert.equal(controller.getSnapshot().views.allEntries.records.length, 1);
  adapter.query = async () => {
    throw new BackendError(
      "Access removed",
      "permission_denied",
      "service",
      false,
      403,
    );
  };
  await controller.loadMore("allEntries");
  assert.equal(controller.getSnapshot().accessDenied, true);
  assert.deepEqual(controller.getSnapshot().views, {});
  assert.equal(controller.getSnapshot().record, null);
  assert.equal(controller.writeAvailable, false);
  const second = new PreviewRuntimeAdapter(fixture("notes")),
    store = durableStore(),
    mutating = new RuntimeController(
      second,
      () => "retained_denial",
      () => new Date(),
      store,
    );
  await mutating.refresh();
  mutating.setDirty(true);
  second.execute = async () => {
    throw new BackendError(
      "Sign in again",
      "unusual_service_type",
      "unauthenticated",
      false,
      401,
    );
  };
  await mutating.execute("addRecord", { data: { title: "Private input" } });
  assert.equal(mutating.getSnapshot().accessDenied, true);
  assert.deepEqual(mutating.getSnapshot().views, {});
  assert.equal(mutating.getSnapshot().dirty, false);
  assert.ok(
    await store.read(),
    "Keep the account-scoped identity for later safe reconciliation",
  );
  await assert.rejects(
    mutating.execute("addRecord", { data: { title: "Blocked" } }),
    failure("forbidden"),
  );
});
