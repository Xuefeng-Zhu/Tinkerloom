import assert from "node:assert/strict";
import test from "node:test";
import { fullTemplates } from "../full/catalog";
import { RuntimeController } from "./controller";
import { RuntimeError } from "./errors";
import { PreviewRuntimeAdapter } from "./preview";
import type { RuntimeRecord, RecordPage } from "./types";

test("duplicate record focus is coalesced so Back can leave the overlay once", async () => {
  const spec = fullTemplates.find(
    (template) => template.id === "planner",
  )!.spec;
  const adapter = new PreviewRuntimeAdapter(spec);
  const row = (await adapter.query("tasks", {})).records[0];
  const controller = new RuntimeController(adapter, () => "unused");
  const first = controller.focusRecord(row);
  const duplicate = controller.focusRecord(row);
  assert.deepEqual(controller.getSnapshot().history, [{ pageId: "todayPage" }]);
  assert.equal(controller.back(), true);
  assert.deepEqual(controller.getSnapshot().location, { pageId: "todayPage" });
  assert.equal(controller.canGoBack, false);
  assert.equal(first, true);
  assert.equal(duplicate, false);
  controller.dispose();
});

test("duplicate edit focus updates a pristine authorized revision without adding a new browser visit", async () => {
  const spec = fullTemplates.find(
    (template) => template.id === "planner",
  )!.spec;
  const adapter = new PreviewRuntimeAdapter(spec);
  const row = (await adapter.query("tasks", {})).records[0];
  const controller = new RuntimeController(adapter, () => "unused");
  controller.focusRecord(row, true);
  const newer = {
    ...row,
    revision: row.revision + 1,
    data: { ...row.data, title: "Authorized current row" },
  };
  const duplicate = controller.focusRecord(newer, true);
  assert.equal(controller.getSnapshot().record, newer);
  assert.equal(controller.getSnapshot().history.length, 1);
  assert.equal(duplicate, false);
  controller.dispose();
});

test("old focused-row callbacks cannot reintroduce private records after access denial or scope disposal", async () => {
  const spec = fullTemplates.find(
    (template) => template.id === "planner",
  )!.spec;
  const adapter = new PreviewRuntimeAdapter(spec);
  const row = (await adapter.query("tasks", {})).records[0];
  const controller = new RuntimeController(adapter, () => "unused");
  controller.focusRecord(row);
  controller.invalidateAccess(new RuntimeError("forbidden", "Access revoked"));
  assert.throws(
    () => controller.focusRecord(row),
    (error) => error instanceof RuntimeError && error.code === "forbidden",
  );
  assert.equal(controller.getSnapshot().record, null);
  controller.dispose();
  assert.throws(
    () => controller.focusRecord(row),
    (error) => error instanceof RuntimeError && error.code === "disposed",
  );
  assert.equal(controller.getSnapshot().record, null);
});

function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (reason: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

test("an obsolete refresh denial cannot erase a newer authorized external record location", async () => {
  const spec = fullTemplates.find(
    (template) => template.id === "planner",
  )!.spec;
  const adapter = new PreviewRuntimeAdapter(spec),
    rows = (await adapter.query("tasks", {})).records;
  const controller = new RuntimeController(adapter, () => "unused"),
    wait = deferred<RuntimeRecord>(),
    started = deferred<void>();
  controller.focusRecord(rows[0]);
  adapter.get = async (id) => {
    if (id === rows[0].id) {
      started.resolve();
      return wait.promise;
    }
    assert.equal(id, rows[1].id);
    return rows[1];
  };
  const refresh = controller.refresh();
  await started.promise;
  assert.equal(
    await controller.applyLocation({ recordId: rows[1].id }),
    "applied",
  );
  wait.reject(new RuntimeError("forbidden", "Earlier revoked grant"));
  await refresh;
  assert.equal(controller.getSnapshot().accessDenied, false);
  assert.equal(controller.getSnapshot().location.recordId, rows[1].id);
  await controller.refresh();
  assert.equal(controller.getSnapshot().record?.id, rows[1].id);
  controller.dispose();
});

test("a current external record denial still hides private input when only local typing cancels the response", async () => {
  const spec = fullTemplates.find(
    (template) => template.id === "planner",
  )!.spec;
  const adapter = new PreviewRuntimeAdapter(spec),
    rows = (await adapter.query("tasks", {})).records;
  const controller = new RuntimeController(adapter, () => "unused"),
    wait = deferred<RuntimeRecord>(),
    started = deferred<void>();
  controller.focusRecord(rows[0], true);
  adapter.get = async () => {
    started.resolve();
    return wait.promise;
  };
  const opening = controller.applyLocation({ recordId: rows[1].id });
  await started.promise;
  controller.setDirty(true);
  wait.reject(new RuntimeError("forbidden", "Current grant revoked"));
  await assert.rejects(
    opening,
    (error) => error instanceof RuntimeError && error.code === "forbidden",
  );
  assert.equal(controller.getSnapshot().accessDenied, true);
  assert.equal(controller.getSnapshot().record, null);
  controller.dispose();
});

test("old load-more denial is fenced by actual navigation, while current denial still hides a newly dirty form", async () => {
  for (const next of ["navigate", "dirty"] as const) {
    const spec = structuredClone(
      fullTemplates.find((template) => template.id === "planner")!.spec,
    );
    spec.views.find((view) => view.id === "allTasks")!.query = { limit: 1 };
    const adapter = new PreviewRuntimeAdapter(spec),
      rows = (await adapter.query("tasks", { limit: 100 })).records;
    const controller = new RuntimeController(adapter, () => "unused"),
      wait = deferred<RecordPage>(),
      started = deferred<void>();
    controller.navigate({ pageId: "tasksPage" });
    await controller.refresh();
    assert.ok(controller.getSnapshot().views.allTasks.nextCursor);
    const query = adapter.query.bind(adapter);
    adapter.query = async (id, request) =>
      request.cursor ? (started.resolve(), wait.promise) : query(id, request);
    const paging = controller.loadMore("allTasks");
    await started.promise;
    if (next === "navigate")
      assert.equal(
        await controller.applyLocation({ recordId: rows[1].id }),
        "applied",
      );
    else controller.setDirty(true);
    wait.reject(
      new RuntimeError("forbidden", "Grant revoked during older page"),
    );
    await paging;
    assert.equal(controller.getSnapshot().accessDenied, next === "dirty", next);
    if (next === "navigate") {
      await controller.refresh();
      assert.equal(controller.getSnapshot().record?.id, rows[1].id);
    } else assert.deepEqual(controller.getSnapshot().views, {});
    controller.dispose();
  }
});

test("an accepted same-location reload supersedes an older page success before it can append stale rows", async () => {
  const spec = structuredClone(
    fullTemplates.find((template) => template.id === "planner")!.spec,
  );
  spec.views.find((view) => view.id === "allTasks")!.query = { limit: 1 };
  const adapter = new PreviewRuntimeAdapter(spec),
    controller = new RuntimeController(adapter, () => "unused");
  controller.navigate({ pageId: "tasksPage" });
  await controller.refresh();
  const wait = deferred<RecordPage>(),
    started = deferred<void>(),
    query = adapter.query.bind(adapter);
  let oldPage!: RecordPage;
  adapter.query = async (id, request) => {
    if (request.cursor) {
      oldPage = await query(id, request);
      started.resolve();
      return wait.promise;
    }
    return query(id, request);
  };
  const seen: string[] = [];
  const stop = controller.subscribe(() => {
    for (const row of controller.getSnapshot().views.allTasks?.records ?? [])
      seen.push(String(row.data.title));
  });
  const paging = controller.loadMore("allTasks");
  await started.promise;
  assert.equal(
    await controller.applyLocation({ pageId: "tasksPage" }),
    "applied",
  );
  wait.resolve({
    ...oldPage,
    records: oldPage.records.map((row) => ({
      ...row,
      data: { ...row.data, title: "Obsolete page value" },
    })),
  });
  await paging;
  await controller.refresh();
  assert.equal(seen.includes("Obsolete page value"), false);
  stop();
  controller.dispose();
});

test("a newer external read request supersedes an older denial without letting local edits suppress its own denial", async () => {
  const spec = fullTemplates.find(
    (template) => template.id === "planner",
  )!.spec;
  const adapter = new PreviewRuntimeAdapter(spec),
    rows = (await adapter.query("tasks", {})).records;
  const controller = new RuntimeController(adapter, () => "unused"),
    older = deferred<RuntimeRecord>(),
    newer = deferred<RuntimeRecord>(),
    startedOld = deferred<void>(),
    startedNew = deferred<void>();
  adapter.get = async (id) => {
    if (id === rows[0].id) {
      startedOld.resolve();
      return older.promise;
    }
    startedNew.resolve();
    return newer.promise;
  };
  const first = controller.applyLocation({ recordId: rows[0].id });
  await startedOld.promise;
  const second = controller.applyLocation({ recordId: rows[1].id });
  await startedNew.promise;
  older.reject(new RuntimeError("forbidden", "Earlier authority response"));
  assert.equal(await first, "stale");
  assert.equal(controller.getSnapshot().accessDenied, false);
  newer.resolve(rows[1]);
  assert.equal(await second, "applied");
  assert.equal(controller.getSnapshot().location.recordId, rows[1].id);
  controller.dispose();
});
