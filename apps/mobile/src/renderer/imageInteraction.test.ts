import assert from "node:assert/strict";
import test from "node:test";
import { fullTemplates } from "../full/catalog";
import { RuntimeController } from "../runtime/controller";
import { PreviewRuntimeAdapter } from "../runtime/preview";
import { MemoryRuntimeCommandStore } from "../runtime/commands";
import { RuntimeError } from "../runtime/errors";
import type {
  PickedImage,
  RuntimeCommand,
  RuntimeRecord,
} from "../runtime/types";
import {
  createFieldImageLifetime,
  disposeFieldImageLifetime,
  selectFieldImage,
} from "./imageInteraction";
import { editorRecordSnapshot } from "./editorSnapshot";
function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (reason: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
const image = (): PickedImage => ({
  bytes: Uint8Array.from(
    Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==",
      "base64",
    ),
  ),
  mimeType: "image/png",
  name: "synthetic.png",
});
async function fixture() {
  const spec = fullTemplates.find((item) => item.id === "photoJournal")!.spec;
  const adapter = new PreviewRuntimeAdapter(spec),
    controller = new RuntimeController(adapter, () =>
      assert.fail("image interaction cannot allocate record commands"),
    );
  await controller.recover();
  const row = (await adapter.query(spec.collections[0].id, {})).records[0];
  controller.focusRecord(row, true);
  await controller.refresh();
  return { adapter, controller, row: controller.getSnapshot().record! };
}

test("picker/upload lease freezes a pristine snapshot and blocks navigation/read/write until the selected image becomes local input", async () => {
  const { adapter, controller, row } = await fixture(),
    life = createFieldImageLifetime(),
    picked = deferred<PickedImage | null>(),
    uploaded = deferred<string>(),
    uploadStarted = deferred<void>();
  const source = image();
  let reads = 0,
    commits = 0;
  const newer = { ...row, revision: row.revision + 1 };
  adapter.get = async () => {
    ++reads;
    return newer;
  };
  const selection = selectFieldImage(life, {
    beginInteraction: () => controller.beginFormInteraction(),
    pick: () => picked.promise,
    upload: async (value) => {
      assert.equal(value, source);
      uploadStarted.resolve();
      return uploaded.promise;
    },
    commit: () => {
      assert.equal(controller.getSnapshot().formBusy, true);
      ++commits;
      controller.setDirty(true);
    },
    busy: () => {},
    error: () => {},
  });
  assert.equal(controller.getSnapshot().formBusy, true);
  assert.equal(controller.canLeave, false);
  assert.equal(
    controller.navigate(
      { pageId: controller.getSnapshot().location.pageId },
      true,
    ),
    false,
  );
  assert.equal(controller.back(true), false);
  assert.equal(await controller.applyLocation({ recordId: row.id }), "blocked");
  await assert.rejects(
    controller.execute(adapter.spec.actions[0].id, { data: {} }),
    (error) => error instanceof RuntimeError && error.code === "form_busy",
  );
  await controller.refresh();
  assert.equal(reads, 0);
  assert.equal(controller.getSnapshot().record, row);
  picked.resolve(source);
  await uploadStarted.promise;
  await controller.refresh();
  assert.equal(reads, 0);
  uploaded.resolve("opaque_ready_asset");
  await selection;
  assert.equal(commits, 1);
  assert.equal(controller.getSnapshot().formBusy, false);
  assert.equal(controller.getSnapshot().dirty, true);
  assert.equal(controller.getSnapshot().record, row);
  assert.equal(
    editorRecordSnapshot(row, controller.getSnapshot().record, true, false),
    row,
  );
  assert.ok(source.bytes.every((byte) => byte === 0));
  controller.setDirty(false);
  await controller.refresh();
  assert.equal(controller.getSnapshot().record?.revision, newer.revision);
  disposeFieldImageLifetime(life);
  controller.dispose();
});

test("cancelling the picker releases the busy lease and permits deferred authorized refresh without marking dirty", async () => {
  const { adapter, controller, row } = await fixture(),
    life = createFieldImageLifetime(),
    picked = deferred<PickedImage | null>();
  const busy: boolean[] = [];
  const newer = { ...row, revision: row.revision + 1 };
  adapter.get = async () => newer;
  const selecting = selectFieldImage(life, {
    beginInteraction: () => controller.beginFormInteraction(),
    pick: () => picked.promise,
    upload: async () => assert.fail("cancel has no upload"),
    commit: () => assert.fail("cancel has no value"),
    busy: (value) => busy.push(value),
    error: () => {},
  });
  await controller.refresh();
  assert.equal(controller.getSnapshot().record, row);
  picked.resolve(null);
  await selecting;
  await controller.refresh();
  assert.deepEqual(busy, [true, false]);
  assert.equal(controller.getSnapshot().formBusy, false);
  assert.equal(controller.getSnapshot().dirty, false);
  assert.equal(controller.getSnapshot().record?.revision, newer.revision);
  disposeFieldImageLifetime(life);
  controller.dispose();
});

test("unmount during picker releases immediately, zeroes late selected bytes and never uploads or commits to another form", async () => {
  const { controller } = await fixture(),
    life = createFieldImageLifetime(),
    picked = deferred<PickedImage | null>(),
    source = image();
  let uploads = 0,
    commits = 0;
  const busy: boolean[] = [];
  const selecting = selectFieldImage(life, {
    beginInteraction: () => controller.beginFormInteraction(),
    pick: () => picked.promise,
    upload: async () => {
      ++uploads;
      return "asset";
    },
    commit: () => ++commits,
    busy: (value) => busy.push(value),
    error: () => {},
  });
  disposeFieldImageLifetime(life);
  assert.equal(controller.getSnapshot().formBusy, false);
  picked.resolve(source);
  await selecting;
  assert.equal(uploads, 0);
  assert.equal(commits, 0);
  assert.deepEqual(busy, [true]);
  assert.ok(source.bytes.every((byte) => byte === 0));
  controller.dispose();
});

test("unmount during upload cannot leave a phantom lock or let its late finally release a new form's lease", async () => {
  const { controller } = await fixture(),
    life = createFieldImageLifetime(),
    uploaded = deferred<string>(),
    started = deferred<void>(),
    source = image();
  let commits = 0;
  const selecting = selectFieldImage(life, {
    beginInteraction: () => controller.beginFormInteraction(),
    pick: async () => source,
    upload: async () => {
      started.resolve();
      return uploaded.promise;
    },
    commit: () => ++commits,
    busy: () => {},
    error: () => {},
  });
  await started.promise;
  disposeFieldImageLifetime(life);
  assert.equal(controller.getSnapshot().formBusy, false);
  const next = controller.beginFormInteraction();
  assert.ok(next);
  assert.equal(controller.getSnapshot().formBusy, true);
  uploaded.resolve("late_asset");
  await selecting;
  assert.equal(commits, 0);
  assert.equal(controller.getSnapshot().formBusy, true);
  assert.ok(source.bytes.every((byte) => byte === 0));
  next();
  next();
  assert.equal(controller.getSnapshot().formBusy, false);
  controller.dispose();
});

test("duplicate image selection is coalesced before invoking another picker or acquiring another lease", async () => {
  const life = createFieldImageLifetime(),
    picked = deferred<PickedImage | null>(),
    source = image();
  let begins = 0,
    picks = 0,
    releases = 0,
    commits = 0;
  const options = {
    beginInteraction: () => {
      ++begins;
      return () => ++releases;
    },
    pick: () => {
      ++picks;
      return picked.promise;
    },
    upload: async () => "asset",
    commit: () => ++commits,
    busy: () => {},
    error: () => {},
  };
  const selecting = selectFieldImage(life, options);
  await selectFieldImage(life, options);
  assert.equal(begins, 1);
  assert.equal(picks, 1);
  picked.resolve(source);
  await selecting;
  assert.equal(commits, 1);
  assert.equal(releases, 1);
  disposeFieldImageLifetime(life);
  assert.equal(releases, 1);
});

test("unrecovered or retained commands reject image interaction before picker/upload, without altering the exact journal", async () => {
  const spec = fullTemplates.find((item) => item.id === "photoJournal")!.spec,
    adapter = new PreviewRuntimeAdapter(spec),
    store = new MemoryRuntimeCommandStore();
  const command: RuntimeCommand = {
    appId: adapter.appId,
    versionId: adapter.versionId,
    operationId: "unchanged_original",
    actionId: spec.actions[0].id,
    input: { data: {} },
  };
  await store.save(command);
  const controller = new RuntimeController(
    adapter,
    () => assert.fail("no new record command"),
    undefined,
    store,
  );
  assert.equal(controller.beginFormInteraction(), null);
  await controller.recover();
  assert.equal(controller.getSnapshot().pending?.status, "uncertain");
  const errors: (string | null)[] = [];
  await selectFieldImage(createFieldImageLifetime(), {
    beginInteraction: () => controller.beginFormInteraction(),
    pick: async () => assert.fail("no picker while unknown"),
    upload: async () => assert.fail("no upload"),
    commit: () => assert.fail("no commit"),
    busy: () => assert.fail("no busy lease"),
    error: (message) => errors.push(message),
  });
  assert.equal(errors.length, 1);
  assert.deepEqual(await store.read(), command);
  assert.equal(controller.getSnapshot().formBusy, false);
  controller.dispose();
});

test("current denial and controller disposal clear image locks; dead lifetime callbacks cannot commit", async () => {
  const { controller, row } = await fixture(),
    life = createFieldImageLifetime(),
    uploaded = deferred<string>(),
    started = deferred<void>(),
    source = image();
  let commits = 0;
  const selecting = selectFieldImage(life, {
    beginInteraction: () => controller.beginFormInteraction(),
    pick: async () => source,
    upload: async () => {
      started.resolve();
      return uploaded.promise;
    },
    commit: () => ++commits,
    busy: () => {},
    error: () => {},
  });
  await started.promise;
  controller.invalidateAccess(new RuntimeError("forbidden", "Revoked"));
  disposeFieldImageLifetime(life);
  assert.equal(controller.getSnapshot().record, null);
  assert.equal(controller.getSnapshot().formBusy, false);
  assert.equal(controller.beginFormInteraction(), null);
  uploaded.resolve("late_asset");
  await selecting;
  assert.equal(commits, 0);
  assert.ok(source.bytes.every((byte) => byte === 0));
  controller.dispose();
  assert.equal(controller.getSnapshot().formBusy, false);
  assert.equal(controller.beginFormInteraction(), null);
  assert.equal(row.revision, 1);
});

test("upload failure and even a faulty busy callback cannot retain source bytes or the navigation lease", async () => {
  const life = createFieldImageLifetime(),
    source = image();
  let released = 0;
  const errors: (string | null)[] = [];
  const task = selectFieldImage(life, {
    beginInteraction: () => () => ++released,
    pick: async () => source,
    upload: async () => {
      throw new Error("Private diagnostic never surfaced");
    },
    commit: () => assert.fail("failed upload cannot commit"),
    busy: (value) => {
      if (!value) throw new Error("UI callback failure");
    },
    error: (message) => errors.push(message),
  });
  await assert.rejects(task, /UI callback failure/);
  assert.equal(released, 1);
  assert.ok(source.bytes.every((byte) => byte === 0));
  assert.equal(life.finishInteraction, null);
  assert.deepEqual(errors, [
    null,
    "The image could not be uploaded. Your other values are retained.",
  ]);
  disposeFieldImageLifetime(life);
  assert.equal(released, 1);
});

test("cleanup still releases a lease if a trusted adapter transferred and detached its input buffer", async () => {
  const life = createFieldImageLifetime(),
    source = image();
  let released = 0;
  const selecting = selectFieldImage(life, {
    beginInteraction: () => () => ++released,
    pick: async () => source,
    upload: async (picked) => {
      structuredClone(picked.bytes.buffer, { transfer: [picked.bytes.buffer] });
      return "asset";
    },
    commit: () => {},
    busy: () => {},
    error: () => {},
  });
  await assert.rejects(selecting, TypeError);
  assert.equal(released, 1);
  assert.equal(life.finishInteraction, null);
  assert.equal(life.imageBusy, false);
  disposeFieldImageLifetime(life);
  assert.equal(released, 1);
});

test("an already in-flight read cannot replace the pristine form snapshot after the picker starts", async () => {
  const { adapter, controller, row } = await fixture(),
    life = createFieldImageLifetime();
  const reading = deferred<RuntimeRecord>(),
    started = deferred<void>(),
    picked = deferred<PickedImage | null>(),
    source = image();
  adapter.get = async () => {
    started.resolve();
    return reading.promise;
  };
  const refresh = controller.refresh();
  await started.promise;
  const selecting = selectFieldImage(life, {
    beginInteraction: () => controller.beginFormInteraction(),
    pick: () => picked.promise,
    upload: async () => "ready_asset",
    commit: () => controller.setDirty(true),
    busy: () => {},
    error: () => {},
  });
  reading.resolve({ ...row, revision: row.revision + 1 });
  await refresh;
  assert.equal(controller.getSnapshot().record, row);
  assert.equal(controller.getSnapshot().formBusy, true);
  picked.resolve(source);
  await selecting;
  assert.equal(controller.getSnapshot().record, row);
  assert.equal(controller.getSnapshot().dirty, true);
  assert.equal(controller.getSnapshot().formBusy, false);
  assert.ok(source.bytes.every((byte) => byte === 0));
  disposeFieldImageLifetime(life);
  controller.dispose();
});

test("a current in-flight read denial still hides private state while the picker is busy", async () => {
  const { adapter, controller } = await fixture(),
    life = createFieldImageLifetime();
  const reading = deferred<RuntimeRecord>(),
    started = deferred<void>(),
    picked = deferred<PickedImage | null>(),
    source = image();
  adapter.get = async () => {
    started.resolve();
    return reading.promise;
  };
  const refresh = controller.refresh();
  await started.promise;
  const selecting = selectFieldImage(life, {
    beginInteraction: () => controller.beginFormInteraction(),
    pick: () => picked.promise,
    upload: async () => assert.fail("denied picker cannot upload"),
    commit: () => assert.fail("denied picker cannot commit"),
    busy: () => {},
    error: () => {},
  });
  assert.equal(controller.getSnapshot().formBusy, true);
  reading.reject(new RuntimeError("forbidden", "Access revoked"));
  await refresh;
  assert.equal(controller.getSnapshot().accessDenied, true);
  assert.equal(controller.getSnapshot().record, null);
  assert.equal(controller.getSnapshot().formBusy, false);
  disposeFieldImageLifetime(life);
  picked.resolve(source);
  await selecting;
  assert.ok(source.bytes.every((byte) => byte === 0));
  controller.dispose();
});
