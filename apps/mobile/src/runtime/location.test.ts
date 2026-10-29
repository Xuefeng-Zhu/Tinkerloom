import assert from "node:assert/strict";
import test from "node:test";
import { fullTemplates } from "../full/catalog";
import { editorRecordSnapshot } from "../renderer/editorSnapshot";
import { RuntimeController } from "./controller";
import { MemoryRuntimeCommandStore } from "./commands";
import { RuntimeError } from "./errors";
import { locationHistory, resolveLocation, sameLocation } from "./location";
import { PreviewRuntimeAdapter } from "./preview";
import type { RuntimeCommand, RuntimeRecord } from "./types";

const planner = fullTemplates.find((item) => item.id === "planner")!.spec;
const adapter = () => new PreviewRuntimeAdapter(planner);
const first = async (a: PreviewRuntimeAdapter) =>
  (await a.query("tasks", {})).records[0];
const failure = (code: string) => (error: unknown) =>
  error instanceof RuntimeError && error.code === code;
function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (reason: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

test("record-only and edit links resolve from an authorized current record and the current manifest", async () => {
  const a = adapter(),
    row = await first(a),
    reads: string[] = [],
    get = a.get.bind(a);
  a.get = async (id) => {
    reads.push(id);
    return get(id);
  };
  a.execute = async () => assert.fail("URL resolution cannot execute actions");
  assert.deepEqual(await resolveLocation(a, { recordId: row.id }), {
    pageId: "taskDetailPage",
    recordId: row.id,
  });
  assert.deepEqual(
    await resolveLocation(a, { recordId: row.id, editing: true }),
    { pageId: "taskEditorPage", recordId: row.id, editing: true },
  );
  assert.deepEqual(reads, [row.id, row.id]);
  assert.deepEqual(await resolveLocation(a, {}), { pageId: "todayPage" });
  a.dispose();
});
test("unknown pages, mismatched record identities, inaccessible rows and unauthorized edits fail without navigating or trusting URL authority", async () => {
  const a = adapter(),
    row = await first(a);
  await assert.rejects(
    resolveLocation(a, { pageId: "unknown" }),
    failure("invalid_location"),
  );
  await assert.rejects(
    resolveLocation(a, { pageId: "taskEditorPage", editing: true }),
    failure("invalid_location"),
  );
  await assert.rejects(
    resolveLocation(a, { recordId: "missing" }),
    failure("not_found"),
  );
  a.get = async () => ({ ...row, id: "substituted" });
  await assert.rejects(
    resolveLocation(a, { recordId: row.id }),
    failure("invalid_response"),
  );
  a.get = async () => ({ ...row, allowedActions: [] });
  await assert.rejects(
    resolveLocation(a, { recordId: row.id, editing: true }),
    failure("invalid_location"),
  );
  assert.deepEqual(await resolveLocation(a, { recordId: row.id }), {
    pageId: "taskDetailPage",
    recordId: row.id,
  });
  a.get = async () => ({ ...row, collectionId: "other_collection" });
  await assert.rejects(
    resolveLocation(a, { pageId: "tasksPage", recordId: row.id }),
    failure("invalid_location"),
  );
  a.dispose();
});
test("external Back/Forward trims known history, clears foreign paths, and tab pushes never accumulate stale return entries", async () => {
  const a = adapter(),
    c = new RuntimeController(a, () => "unused"),
    row = await first(a);
  c.navigate({ pageId: "taskDetailPage", recordId: row.id });
  c.navigate({ pageId: "taskEditorPage", recordId: row.id, editing: true });
  assert.equal(c.getSnapshot().history.length, 2);
  assert.equal(
    await c.applyLocation({ pageId: "taskDetailPage", recordId: row.id }),
    "applied",
  );
  assert.deepEqual(c.getSnapshot().history, [{ pageId: "todayPage" }]);
  assert.equal(await c.applyLocation({ pageId: "progressPage" }), "applied");
  assert.deepEqual(c.getSnapshot().history, []);
  c.navigate({ pageId: "taskDetailPage", recordId: row.id });
  c.navigate({ pageId: "tasksPage" });
  assert.deepEqual(c.getSnapshot().history, []);
  c.dispose();
});
test("direct-link Back falls back to the manifest entry with no browser/native owned parent", async () => {
  const a = adapter(),
    c = new RuntimeController(a, () => "unused"),
    row = await first(a);
  assert.equal(
    await c.applyLocation({ recordId: row.id, editing: true }),
    "applied",
  );
  assert.equal(c.canGoBack, true);
  assert.deepEqual(c.getSnapshot().history, []);
  assert.equal(c.back(), true);
  assert.deepEqual(c.getSnapshot().location, { pageId: "todayPage" });
  assert.equal(c.canGoBack, false);
  assert.equal(c.back(), false);
  c.dispose();
});
test("dirty external query changes retain the same location, values and history without issuing even a record read", async () => {
  const a = adapter(),
    c = new RuntimeController(a, () => "unused"),
    row = await first(a);
  c.focusRecord(row, true);
  c.setDirty(true);
  const before = c.getSnapshot();
  let reads = 0;
  a.get = async () => {
    ++reads;
    return row;
  };
  assert.equal(await c.applyLocation({ pageId: "tasksPage" }), "blocked");
  assert.equal(
    await c.applyLocation({ recordId: "different", editing: true }),
    "blocked",
  );
  assert.equal(c.back(), false);
  assert.equal(c.getSnapshot(), before);
  assert.equal(reads, 0);
  c.dispose();
});
test("unknown durable record commands stay byte-for-byte retained and cannot be cleared by a deep link or Back", async () => {
  const a = adapter(),
    store = new MemoryRuntimeCommandStore();
  const command: RuntimeCommand = {
    appId: a.appId,
    versionId: a.versionId,
    operationId: "retained_original",
    actionId: "addTask",
    input: { data: { title: "Unconfirmed", status: "Open" } },
  };
  await store.save(command);
  const c = new RuntimeController(
    a,
    () => assert.fail("no new operation ID"),
    undefined,
    store,
  );
  a.get = async () =>
    assert.fail("pending journal must be recovered before identity reads");
  a.execute = async () => assert.fail("deep links cannot retry a saved write");
  assert.equal(await c.applyLocation({ recordId: "other_record" }), "blocked");
  assert.equal(c.getSnapshot().pending?.status, "uncertain");
  assert.equal(c.navigate({ pageId: "tasksPage" }, true), false);
  assert.equal(c.back(true), false);
  assert.deepEqual(await store.read(), command);
  c.dispose();
  assert.deepEqual(await store.read(), command);
});
test("authorized record reads finishing after a dirty edit, newer navigation or disposed account scope cannot change location", async () => {
  for (const interrupt of ["dirty", "navigate", "dispose"] as const) {
    const a = adapter(),
      c = new RuntimeController(a, () => "unused"),
      row = await first(a),
      wait = deferred<RuntimeRecord>(),
      started = deferred<void>();
    a.get = async () => {
      started.resolve();
      return wait.promise;
    };
    const task = c.applyLocation({ recordId: row.id, editing: true });
    await started.promise;
    if (interrupt === "dirty") c.setDirty(true);
    if (interrupt === "navigate") c.navigate({ pageId: "tasksPage" });
    if (interrupt === "dispose") c.dispose();
    const expected = c.getSnapshot().location;
    wait.resolve(row);
    assert.equal(await task, "stale", interrupt);
    assert.deepEqual(c.getSnapshot().location, expected, interrupt);
    if (interrupt !== "dispose") c.dispose();
  }
});
test("a later external URL wins an out-of-order authorized read without clearing the newer history", async () => {
  const a = adapter(),
    c = new RuntimeController(a, () => "unused"),
    row = await first(a),
    wait = deferred<RuntimeRecord>(),
    started = deferred<void>();
  a.get = async () => {
    started.resolve();
    return wait.promise;
  };
  const earlier = c.applyLocation({ recordId: row.id });
  await started.promise;
  assert.equal(await c.applyLocation({ pageId: "tasksPage" }), "applied");
  const newer = c.getSnapshot().location;
  wait.resolve(row);
  assert.equal(await earlier, "stale");
  assert.deepEqual(c.getSnapshot().location, newer);
  c.dispose();
});
test("current authentication denial during external lookup hides old records; a denied edit affordance alone keeps read access", async () => {
  const a = adapter(),
    c = new RuntimeController(a, () => "unused"),
    row = await first(a);
  c.focusRecord(row);
  a.get = async () => {
    throw new RuntimeError("forbidden", "Revoked");
  };
  await assert.rejects(
    c.applyLocation({ recordId: row.id }),
    failure("forbidden"),
  );
  assert.equal(c.getSnapshot().accessDenied, true);
  assert.equal(c.getSnapshot().record, null);
  assert.equal(c.navigate({ pageId: "tasksPage" }), false);
  c.dispose();
  const viewer = adapter(),
    readOnly = new RuntimeController(viewer, () => "unused");
  viewer.get = async () => ({ ...row, allowedActions: [] });
  await assert.rejects(
    readOnly.applyLocation({ recordId: row.id, editing: true }),
    failure("invalid_location"),
  );
  assert.equal(readOnly.getSnapshot().accessDenied, false);
  assert.equal(await readOnly.applyLocation({ recordId: row.id }), "applied");
  readOnly.dispose();
});
test("pristine modal editor follows authorized new revisions while dirty/pending snapshots stay captured and missing reads show no form", async () => {
  const a = adapter(),
    c = new RuntimeController(a, () => "unused"),
    original = await first(a);
  c.focusRecord(original, true);
  await c.refresh();
  const updated: RuntimeRecord = {
    ...original,
    revision: original.revision + 1,
    data: { ...original.data, title: "Changed remotely" },
  };
  a.get = async () => updated;
  await c.refresh();
  const current = c.getSnapshot().record;
  assert.equal(editorRecordSnapshot(original, current, false, false), updated);
  assert.equal(editorRecordSnapshot(original, current, true, false), original);
  assert.equal(editorRecordSnapshot(original, current, false, true), original);
  assert.equal(editorRecordSnapshot(original, null, false, false), null);
  assert.equal(
    editorRecordSnapshot(original, { ...updated, id: "other" }, false, false),
    null,
  );
  assert.equal(
    editorRecordSnapshot(
      original,
      { ...updated, collectionId: "other" },
      false,
      false,
    ),
    null,
  );
  assert.equal(
    editorRecordSnapshot(undefined, updated, false, false),
    undefined,
  );
  c.dispose();
});
test("a refresh that completes after typing never swaps the captured modal record or its expected revision", async () => {
  const a = adapter(),
    c = new RuntimeController(a, () => "unused"),
    original = await first(a),
    wait = deferred<RuntimeRecord>(),
    started = deferred<void>();
  c.focusRecord(original, true);
  a.get = async () => {
    started.resolve();
    return wait.promise;
  };
  const refresh = c.refresh();
  await started.promise;
  c.setDirty(true);
  wait.resolve({
    ...original,
    revision: 2,
    data: { ...original.data, title: "Remote" },
  });
  await refresh;
  assert.equal(c.getSnapshot().record, original);
  assert.equal(
    editorRecordSnapshot(
      original,
      c.getSnapshot().record,
      c.getSnapshot().dirty,
      false,
    ),
    original,
  );
  c.dispose();
});
test("navigation identity includes edit state and never duplicates unchanged locations", () => {
  const current = { pageId: "tasksPage", recordId: "r1" };
  assert.equal(sameLocation(current, { ...current, editing: false }), true);
  assert.equal(sameLocation(current, { ...current, editing: true }), false);
  assert.deepEqual(locationHistory([], current, current, "push", []), []);
  assert.deepEqual(
    locationHistory(
      [{ pageId: "todayPage" }],
      current,
      { pageId: "taskEditorPage", recordId: "r1", editing: true },
      "push",
      [],
    ),
    [{ pageId: "todayPage" }, current],
  );
});

test("an explicit command starting and finishing during a URL lookup cancels that older navigation without changing its saved command", async () => {
  const a = adapter(),
    store = new MemoryRuntimeCommandStore(),
    c = new RuntimeController(
      a,
      () => "exact_navigation_race",
      undefined,
      store,
    ),
    row = await first(a),
    wait = deferred<RuntimeRecord>(),
    started = deferred<void>();
  a.get = async () => {
    started.resolve();
    return wait.promise;
  };
  const navigation = c.applyLocation({ recordId: row.id });
  await started.promise;
  const result = await c.execute("addTask", {
    data: { title: "User explicitly saved", status: "Open" },
  });
  assert.ok(result);
  assert.equal(c.getSnapshot().pending, null);
  wait.resolve(row);
  assert.equal(await navigation, "stale");
  assert.deepEqual(c.getSnapshot().location, { pageId: "todayPage" });
  assert.equal(await store.read(), null);
  const created = await a.query("tasks", {});
  assert.equal(
    created.records.filter(
      (record) => record.data.title === "User explicitly saved",
    ).length,
    1,
  );
  c.dispose();
});

test("a stale denied external read cannot invalidate a newer authorized location or account scope", async () => {
  const a = adapter(),
    c = new RuntimeController(a, () => "unused"),
    row = await first(a),
    wait = deferred<RuntimeRecord>(),
    started = deferred<void>();
  a.get = async () => {
    started.resolve();
    return wait.promise;
  };
  const earlier = c.applyLocation({ recordId: row.id });
  await started.promise;
  assert.equal(await c.applyLocation({ pageId: "tasksPage" }), "applied");
  wait.reject(new RuntimeError("forbidden", "Earlier grant was revoked"));
  assert.equal(await earlier, "stale");
  assert.equal(c.getSnapshot().accessDenied, false);
  assert.deepEqual(c.getSnapshot().location, { pageId: "tasksPage" });
  c.dispose();
});
