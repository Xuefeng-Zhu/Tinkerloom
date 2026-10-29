import assert from "node:assert/strict";
import test from "node:test";
import { fullTemplates } from "./catalog";
import {
  canvasFieldTargets,
  InspectorFlushQueue,
  validInspectorTarget,
} from "./inspectorSelection";
import type { InspectorTarget } from "./inspectorSelection";
const initial = fullTemplates.find((item) => item.id === "planner")!.spec;
const clone = () => structuredClone(initial);
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
function fixture(flush: () => Promise<boolean>) {
  let spec = clone(),
    available = true;
  const selected: InspectorTarget[] = [];
  const queue = new InspectorFlushQueue({
    flush,
    spec: () => spec,
    available: () => available,
    select: (target) => selected.push(target),
  });
  return {
    queue,
    selected,
    setSpec: (next: typeof spec) => {
      spec = next;
    },
    setAvailable: (next: boolean) => {
      available = next;
    },
  };
}
test("canvas app/page/view/field identities resolve only in the current declaration", () => {
  const spec = clone(),
    collection = spec.collections[0],
    field = collection.fields[0];
  assert.equal(validInspectorTarget(spec, { kind: "app" }), true);
  assert.equal(
    validInspectorTarget(spec, {
      kind: "page",
      pageId: spec.navigation!.pages[0].id,
    }),
    true,
  );
  assert.equal(
    validInspectorTarget(spec, { kind: "view", viewId: spec.views[0].id }),
    true,
  );
  assert.equal(
    validInspectorTarget(spec, {
      kind: "field",
      collectionId: collection.id,
      fieldId: field.id,
    }),
    true,
  );
  assert.equal(
    validInspectorTarget(spec, {
      kind: "field",
      collectionId: "missing",
      fieldId: field.id,
    }),
    false,
  );
  assert.equal(
    validInspectorTarget(spec, { kind: "view", viewId: "removed" }),
    false,
  );
  assert.equal(
    validInspectorTarget(spec, { kind: "page", pageId: "removed" }),
    false,
  );
  delete spec.navigation;
  assert.equal(
    validInspectorTarget(spec, { kind: "page", pageId: "__legacy__" }),
    true,
  );
});
test("field inspection follows explicit view field order and contains metadata only", () => {
  const spec = clone(),
    view = spec.views.find((item) => item.collectionId)!;
  const collection = spec.collections.find(
    (item) => item.id === view.collectionId,
  )!;
  view.fieldIds = [collection.fields[1].id, collection.fields[0].id];
  assert.deepEqual(
    canvasFieldTargets(spec, view.id),
    [collection.fields[1], collection.fields[0]].map((field) => ({
      collectionId: collection.id,
      fieldId: field.id,
      label: field.label,
    })),
  );
  assert.deepEqual(canvasFieldTargets(spec, "missing"), []);
});
test("blur and the latest inspector selection join one in-flight save", async () => {
  const done = deferred<boolean>();
  let calls = 0;
  const f = fixture(() => {
    calls++;
    return done.promise;
  });
  assert.equal(f.queue.flushing, false);
  const blur = f.queue.flush();
  const first = f.queue.inspect({ kind: "app" });
  const last = f.queue.inspect({ kind: "view", viewId: initial.views[0].id });
  await Promise.resolve();
  assert.equal(calls, 1);
  assert.equal(f.queue.flushing, true);
  assert.deepEqual(f.selected, []);
  f.setAvailable(false);
  done.resolve(true);
  assert.equal(await blur, true);
  assert.equal(await first, false);
  assert.equal(await last, true);
  assert.deepEqual(f.selected, [{ kind: "view", viewId: initial.views[0].id }]);
  assert.equal(f.queue.flushing, false);
});
test("rejected or failed saves never switch inspectors or repeat a write", async () => {
  for (const result of [false, "throw"] as const) {
    let calls = 0;
    const f = fixture(async () => {
      calls++;
      if (result === "throw") throw Error("synthetic");
      return false;
    });
    assert.equal(await f.queue.inspect({ kind: "app" }), false);
    assert.equal(calls, 1);
    assert.deepEqual(f.selected, []);
  }
});
test("a target removed during the save cannot select a replacement identity", async () => {
  const done = deferred<boolean>(),
    f = fixture(() => done.promise);
  const id = initial.views[0].id;
  const selected = f.queue.inspect({ kind: "view", viewId: id });
  await Promise.resolve();
  const next = clone();
  next.views = next.views.filter((view) => view.id !== id);
  f.setSpec(next);
  done.resolve(true);
  assert.equal(await selected, false);
  assert.deepEqual(f.selected, []);
});
test("closing before the queued flush starts sends no save", async () => {
  let calls = 0;
  const f = fixture(async () => {
    calls++;
    return true;
  });
  const selected = f.queue.inspect({ kind: "app" });
  f.queue.dispose();
  assert.equal(await selected, false);
  assert.equal(calls, 0);
  assert.deepEqual(f.selected, []);
});
test("closing after a save starts fences late selection without pretending to undo it", async () => {
  const done = deferred<boolean>();
  let calls = 0;
  const f = fixture(() => {
    calls++;
    return done.promise;
  });
  const selected = f.queue.inspect({ kind: "app" });
  await Promise.resolve();
  f.queue.dispose();
  done.resolve(true);
  assert.equal(await selected, false);
  assert.equal(calls, 1);
  assert.deepEqual(f.selected, []);
  assert.equal(await f.queue.flush(), false);
});
test("section transitions serialize with blur, while an initially locked editor cannot start a save", async () => {
  let calls = 0,
    changes = 0;
  const done = deferred<boolean>(),
    f = fixture(() => {
      calls++;
      return done.promise;
    });
  const blur = f.queue.flush(),
    transition = f.queue.transition(() => changes++);
  await Promise.resolve();
  assert.equal(changes, 0);
  done.resolve(true);
  assert.equal(await blur, true);
  assert.equal(await transition, true);
  assert.equal(calls, 1);
  assert.equal(changes, 1);
  f.setAvailable(false);
  assert.equal(await f.queue.transition(() => changes++), false);
  assert.equal(changes, 1);
  assert.equal(calls, 1);
});
test("effect replay never reuses an old save or late target selection", async () => {
  const old = deferred<boolean>(),
    fresh = deferred<boolean>();
  let calls = 0;
  const f = fixture(() => (++calls === 1 ? old.promise : fresh.promise));
  const before = f.queue.inspect({ kind: "app" });
  await Promise.resolve();
  f.queue.dispose();
  f.queue.activate();
  const after = f.queue.inspect({ kind: "view", viewId: initial.views[0].id });
  await Promise.resolve();
  assert.equal(calls, 2);
  old.resolve(true);
  assert.equal(await before, false);
  assert.deepEqual(f.selected, []);
  fresh.resolve(true);
  assert.equal(await after, true);
  assert.deepEqual(f.selected, [{ kind: "view", viewId: initial.views[0].id }]);
});
