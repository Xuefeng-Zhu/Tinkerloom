import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { RuntimeError } from "../runtime/errors";
import { fullTemplates } from "./catalog";
import { editableFieldsForView } from "../spec/bindings";
import { FullCommandJournal } from "./commandJournal";
import { FullAppController } from "./FullAppController";
import { FullWorkspaceController } from "./FullWorkspaceController";
import {
  applySemanticEdit,
  presentationFingerprint,
  semanticId,
} from "./semanticEdits";
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const data = new Map<string, string>();
function host() {
  return hostStores(new HostLifetime(scope), {
    async read(key) {
      return data.get(key) ?? null;
    },
    async change(key, update) {
      const next = update(data.get(key) ?? null);
      if (next === null) data.delete(key);
      else data.set(key, next);
    },
  });
}
const spec = fullTemplates.find((t) => t.id === "planner")!.spec;
const caps = {
  apiVersion: 1,
  formatVersions: [1],
  generation: true,
  guidance: true,
  effects: [],
  privateMedia: false,
};
function app(revision = 1, candidate = spec) {
  return {
    id: "app",
    workspaceId: "workspace",
    name: "Planner",
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: { build: true },
    controlRevision: 1,
    allowedActions: [],
    version: null,
    draft: {
      revision,
      baseVersionId: null,
      candidateHash: `hash_${revision}`,
      spec: candidate,
      publishedVersionId: null,
    },
    generation: null,
  };
}
function factory(
  transport: (request: Record<string, unknown>) => Promise<unknown>,
) {
  let id = 0;
  return new FullAppController({
    scope,
    host: host(),
    transport,
    newId: () => `op_${++id}`,
  });
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => (resolve = r));
  return { promise, resolve };
}
test("journal persists immutable request before transport, reopens read-only and exact retry survives unrelated newer version", async () => {
  data.clear();
  const first = new FullCommandJournal(host().storage);
  const request = {
    op: "spec.publish",
    appId: "app",
    operationId: "op",
    expectedRevision: 2,
    expectedVersionId: "v1",
    reviewHash: "review",
    enabledRuleIds: [],
    activateExistingRecordIds: [],
  };
  await first.prepare(request, { spec });
  request.expectedRevision = 99;
  let calls = 0;
  await assert.rejects(
    first.send(
      async (input) => {
        calls++;
        assert.equal(input.expectedRevision, 2);
        throw new Error("lost");
      },
      () => null,
    ),
  );
  assert.equal(first.status, "uncertain");
  await assert.rejects(first.acknowledgeRejection());
  first.dispose();
  const reopened = new FullCommandJournal(host().storage);
  await reopened.recover();
  assert.equal(calls, 1);
  assert.equal(reopened.pending?.request.expectedVersionId, "v1");
  await reopened.send(
    async (input) => {
      calls++;
      assert.equal(input.expectedRevision, 2);
      return { ok: true };
    },
    () => true,
  );
  assert.equal(calls, 2);
  assert.equal(await host().storage.read("full-command"), null);
});
test("durable persistence failure sends no mutation and another retained operation cannot be overwritten", async () => {
  const journal = new FullCommandJournal({
    async read() {
      return null;
    },
    async compareAndSwap() {
      throw new Error("disk");
    },
  });
  let calls = 0;
  await assert.rejects(
    journal.prepare({ op: "spec.generate", operationId: "op" }),
  );
  await assert.rejects(
    journal.send(
      async () => {
        calls++;
        return {};
      },
      () => true,
    ),
  );
  assert.equal(calls, 0);
  data.clear();
  const a = new FullCommandJournal(host().storage),
    b = new FullCommandJournal(host().storage);
  await Promise.all([a.recover(), b.recover()]);
  await a.prepare({ op: "spec.generate", operationId: "a" });
  await assert.rejects(b.prepare({ op: "spec.generate", operationId: "b" }));
});
test("lost save response retains original revision/spec after refresh, close/reopen, and explicit retry", async () => {
  data.clear();
  let current = app(),
    lost = true;
  const mutations: Record<string, unknown>[] = [];
  const transport = async (request: Record<string, unknown>) => {
    if (request.op === "spec.capabilities") return caps;
    if (request.op === "spec.getApp") return { app: current };
    mutations.push(request);
    if (lost) throw new Error("lost");
    return { app: app(2, request.spec as typeof spec) };
  };
  let controller = factory(transport);
  await controller.load();
  controller.edit({ type: "RenameLabel", targetId: "app", label: "New name" });
  await controller.save();
  assert.equal(controller.getSnapshot().pendingStatus, "uncertain");
  current = app(5);
  await controller.load();
  assert.equal(controller.getSnapshot().conflict, true);
  controller.dispose();
  lost = false;
  controller = factory(transport);
  await controller.load();
  assert.equal(mutations.length, 1);
  await controller.retry();
  assert.deepEqual(mutations[1], mutations[0]);
  assert.equal((mutations[1].spec as typeof spec).name, "New name");
  assert.equal(controller.getSnapshot().app?.draft?.revision, 5);
  assert.equal(controller.getSnapshot().pending, null);
  controller.dispose();
});
test("confirmed role loss clears private candidate/review/retained payload in memory before capabilities read; stored unknown operation survives", async () => {
  data.clear();
  let current = app();
  const gate = deferred<unknown>();
  let capabilityCalls = 0;
  const controller = factory(async (request) => {
    if (request.op === "spec.getApp") return { app: current };
    if (request.op === "spec.capabilities")
      return ++capabilityCalls === 1 ? caps : gate.promise;
    throw new Error("lost");
  });
  await controller.load();
  controller.edit({ type: "RenameLabel", targetId: "app", label: "Secret" });
  await controller.save();
  current = { ...app(), role: "viewer", capabilities: { build: false } };
  const loading = controller.load();
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(controller.getSnapshot().candidate, null);
  assert.equal(controller.getSnapshot().pending, null);
  assert.notEqual(await host().storage.read("full-command"), null);
  gate.resolve(caps);
  await loading;
  controller.dispose();
});
test("publication binds exact reviewed candidate and scope", async () => {
  data.clear();
  const writes: Record<string, unknown>[] = [];
  let current = app();
  const controller = factory(async (request) => {
    if (request.op === "spec.getApp") return { app: current };
    if (request.op === "spec.capabilities") return caps;
    if (request.op === "spec.review")
      return {
        review: {
          candidateHash: "hash_1",
          expectedRevision: 1,
          baseVersionId: null,
          currentVersionId: null,
          reviewHash: "review",
          changes: ["Create app"],
          compatibilityErrors: [],
          enabledRuleIds: [],
          activateExistingRecordIds: [],
        },
      };
    writes.push(request);
    if (request.op === "spec.publish") {
      current = {
        ...current,
        version: { id: "v1", number: 1, hash: "hash_1", spec } as never,
        draft: { ...current.draft, publishedVersionId: "v1" as never },
      };
      return { app: current };
    }
    throw new Error("unexpected");
  });
  await controller.load();
  await controller.review();
  assert.equal(writes.length, 0);
  await controller.publish();
  assert.equal(writes.length, 1);
  assert.equal(writes[0].reviewHash, "review");
  assert.deepEqual(writes[0].enabledRuleIds, []);
  controller.dispose();
});
test("disposed account fences late private manifest and guidance responses", async () => {
  data.clear();
  const response = deferred<unknown>();
  const controller = factory(async () => response.promise);
  const loading = controller.load();
  controller.dispose();
  response.resolve({ app: app() });
  await loading;
  assert.equal(controller.getSnapshot().app, null);
});
test("definitive rejection can be acknowledged; unknown request cannot be discarded", async () => {
  data.clear();
  const controller = factory(async (request) =>
    request.op === "spec.getApp"
      ? { app: app() }
      : request.op === "spec.capabilities"
        ? caps
        : Promise.reject(new RuntimeError("revision_conflict", "Conflict")),
  );
  await controller.load();
  controller.edit({ type: "RenameLabel", targetId: "app", label: "Edit" });
  await controller.save();
  assert.equal(controller.getSnapshot().pendingStatus, "rejected");
  assert.throws(() => controller.discardLocalEdits());
  await controller.acknowledgeRejection();
  assert.equal(controller.getSnapshot().pending, null);
  controller.dispose();
});
test("workspace pin retry captures original preference revision despite newer launcher read", async () => {
  data.clear();
  let revision = 1,
    lost = true;
  const writes: Record<string, unknown>[] = [];
  const controller = new FullWorkspaceController({
    scope,
    workspaceId: "workspace",
    host: host(),
    newId: () => "operation",
    transport: async (request) => {
      if (request.op === "spec.launcher")
        return {
          apps: [
            {
              id: "app",
              workspaceId: "workspace",
              name: "App",
              engine: "appspec.v1",
              role: "viewer",
              archived: false,
              pinned: false,
              pinRevision: revision,
              recordCount: 0,
              availablePlaces: null,
              version: null,
            },
          ],
          nextCursor: null,
        };
      if (request.op === "spec.listDrafts")
        return { drafts: [], nextCursor: null };
      writes.push(request);
      if (lost) throw new Error("lost");
      return { shortcut: { appId: "app", pinned: true, revision: 2 } };
    },
  });
  await controller.load();
  await controller.setPinned(controller.getSnapshot().apps[0], true);
  revision = 7;
  await controller.load();
  lost = false;
  await controller.retry();
  assert.equal(writes[1].expectedRevision, 1);
  assert.deepEqual(writes[1], writes[0]);
  controller.dispose();
});
test("atomic field addition preserves implicit views and repairs final stepped form binding; invalid binding leaves source untouched", () => {
  const source = structuredClone(spec);
  const collection = source.collections[0];
  const form = source.views.find(
    (v) => v.type === "form" && v.collectionId === collection.id,
  );
  assert.ok(form && form.type === "form");
  delete form.fieldIds;
  form.options = {
    steps: [
      {
        id: "first_step",
        title: "Details",
        fieldIds: editableFieldsForView(source, form).map((f) => f.id),
      },
    ],
  };
  source.requires.push("views.interactive.v1");
  if (!source.requires.includes("views.configured.v1"))
    source.requires.push("views.configured.v1");
  const next = applySemanticEdit(
    source,
    {
      type: "AddField",
      collectionId: collection.id,
      field: { label: "Extra", type: "text", required: false },
      viewIds: [],
    },
    () => "abc-def",
  );
  const id = next.collections[0].fields.at(-1)!.id;
  assert.equal(id, "field_abcdef");
  const newForm = next.views.find((v) => v.id === form.id);
  assert.ok(newForm?.type === "form");
  assert.equal(newForm.fieldIds, undefined);
  assert.equal(newForm.options!.steps![0].fieldIds.at(-1), id);
  assert.equal(
    source.collections[0].fields.length + 1,
    next.collections[0].fields.length,
  );
  assert.throws(() =>
    applySemanticEdit(
      source,
      {
        type: "AddField",
        collectionId: collection.id,
        field: { label: "Bad", type: "text", required: false },
        viewIds: ["missing"],
      },
      () => "new",
    ),
  );
  assert.equal(source.collections[0].fields.length, collection.fields.length);
});
test("presentation guard preserves only display changes, rejects binding changes; stable IDs use safe prefix and global collision checks", () => {
  const styled = applySemanticEdit(
    spec,
    { type: "SetAppearance", appearance: { style: "editorial" } },
    () => "new",
  );
  assert.equal(presentationFingerprint(spec), presentationFingerprint(styled));
  const altered = structuredClone(spec);
  altered.collections[0].fields[0].required =
    !altered.collections[0].fields[0].required;
  assert.notEqual(
    presentationFingerprint(spec),
    presentationFingerprint(altered),
  );
  assert.equal(
    semanticId(() => "123-abc", new Set(), "field"),
    "field_123abc",
  );
  assert.throws(() =>
    semanticId(() => "same", new Set(["field_same"]), "field"),
  );
});

test("archived exact receipt resolves journal without restoring historical permissions when fresh access read fails", async () => {
  data.clear();
  let reads = 0,
    phase = "initial";
  const original = app();
  const archived = {
    ...original,
    archived: true,
    capabilities: { build: false },
    draft: null,
  };
  const controller = factory(async (request) => {
    if (request.op === "spec.capabilities") return caps;
    if (request.op === "spec.getApp") {
      reads++;
      if (phase === "receipt") throw new Error("read failed");
      return { app: phase === "archived" ? archived : original };
    }
    if (phase === "initial") throw new Error("lost response");
    phase = "receipt";
    return { app: app(2, request.spec as typeof spec) };
  });
  await controller.load();
  controller.edit({
    type: "RenameLabel",
    targetId: "app",
    label: "Committed private name",
  });
  await controller.save();
  phase = "archived";
  await controller.load();
  assert.equal(controller.getSnapshot().app?.archived, true);
  assert.ok(controller.getSnapshot().pending);
  assert.equal(controller.canBuild, false);
  await controller.retry();
  assert.equal(reads, 3);
  assert.equal(controller.getSnapshot().app?.archived, true);
  assert.equal(controller.canBuild, false);
  assert.equal(controller.getSnapshot().refreshRequired, true);
  assert.equal(controller.getSnapshot().pending, null);
  assert.equal(await host().storage.read("full-command"), null);
  controller.dispose();
});
test("generation request recovery and polling preserve exact job envelope and never enqueue a duplicate", async () => {
  data.clear();
  let job: Record<string, unknown> | null = null,
    lost = true;
  const writes: Record<string, unknown>[] = [];
  const controller = factory(async (request) => {
    if (request.op === "spec.capabilities") return caps;
    if (request.op === "spec.getApp" || request.op === "spec.getGeneration")
      return {
        app: { ...app(job ? 2 : 1), generation: job },
        ...(request.op === "spec.getGeneration" ? { generation: job } : {}),
      };
    writes.push(request);
    job = {
      id: "job",
      status: "queued",
      mode: "edit",
      mutation: 2,
      attempts: 0,
      requestText: request.request,
      diagnostics: "",
      provider: null,
      model: null,
      nextAttemptAt: "2030-01-01T00:00:00Z",
      failureCategory: null,
    };
    if (lost) throw new Error("lost");
    return { app: { ...app(2), generation: job }, generation: job };
  });
  await controller.load();
  await controller.generate("  Preserve my exact request  ");
  assert.equal(controller.getSnapshot().pendingStatus, "uncertain");
  await controller.pollGeneration();
  assert.equal(writes.length, 1);
  lost = false;
  await controller.retry();
  assert.deepEqual(writes[1], writes[0]);
  await controller.pollGeneration();
  await controller.pollGeneration();
  assert.equal(writes.length, 2);
  assert.equal(writes[0].request, "  Preserve my exact request  ");
  controller.dispose();
});
test("foreign-app retained envelopes fail before any mutation and remain saved", async () => {
  data.clear();
  await host().storage.write("full-command", {
    version: 1,
    request: {
      op: "spec.generate",
      appId: "other_app",
      operationId: "original",
    },
    context: {},
  });
  let writes = 0;
  const controller = factory(async (request) => {
    if (request.op === "spec.getApp") return { app: app() };
    if (request.op === "spec.capabilities") return caps;
    writes++;
    return {};
  });
  await controller.load();
  assert.match(controller.getSnapshot().error!, /does not belong/);
  await controller.retry();
  assert.equal(writes, 0);
  assert.notEqual(await host().storage.read("full-command"), null);
  controller.dispose();
});

test("confirmed missing app clears its private view and retains unresolved journal", async () => {
  data.clear();
  let removed = false;
  const controller = factory(async (request) => {
    if (request.op === "spec.capabilities") return caps;
    if (request.op === "spec.getApp") {
      if (removed)
        throw new BackendError(
          "Missing app",
          "not_found",
          "service",
          false,
          404,
        );
      return { app: app() };
    }
    throw new Error("lost");
  });
  await controller.load();
  controller.edit({ type: "RenameLabel", targetId: "app", label: "Private" });
  await controller.save();
  removed = true;
  await controller.load();
  assert.equal(controller.getSnapshot().app, null);
  assert.equal(controller.getSnapshot().candidate, null);
  assert.equal(controller.getSnapshot().pending, null);
  assert.notEqual(await host().storage.read("full-command"), null);
  controller.dispose();
});
test("late guidance cannot attach to a changed candidate and never creates a generation command", async () => {
  data.clear();
  const response = deferred<unknown>();
  let writes = 0;
  const controller = factory(async (request) => {
    if (request.op === "spec.getApp") return { app: app() };
    if (request.op === "spec.capabilities") return caps;
    if (request.op === "spec.guidance") return response.promise;
    writes++;
    return {};
  });
  await controller.load();
  const guidance = controller.requestGuidance("Plan useful tasks");
  controller.edit({
    type: "RenameLabel",
    targetId: "app",
    label: "New candidate",
  });
  response.resolve({
    questions: [{ question: "Who uses it?", options: ["Me", "A team"] }],
  });
  await guidance;
  assert.equal(controller.getSnapshot().guidance, null);
  assert.equal(writes, 0);
  controller.dispose();
});

test("invalid projected text stops an earlier debounce and blocks save until explicitly fixed or discarded", async () => {
  data.clear();
  let writes = 0;
  const controller = factory(async (request) => {
    if (request.op === "spec.getApp") return { app: app() };
    if (request.op === "spec.capabilities") return caps;
    writes++;
    throw new Error("must not send invalid projection");
  });
  await controller.load();
  controller.edit(
    { type: "RenameLabel", targetId: "app", label: "A valid projected edit" },
    true,
  );
  assert.throws(() =>
    controller.edit({ type: "RenameLabel", targetId: "app", label: "" }, true),
  );
  await new Promise((resolve) => setTimeout(resolve, 700));
  assert.equal(writes, 0);
  assert.ok(controller.getSnapshot().editorError);
  assert.equal(await controller.flush(), false);
  assert.equal(writes, 0);
  controller.discardLocalEdits();
  assert.equal(controller.getSnapshot().editorError, null);
  assert.equal(controller.getSnapshot().dirty, false);
  controller.dispose();
});
test("a competing flush cannot unlock a save while its durable write is still pending", async () => {
  data.clear();
  const gate = deferred<void>();
  const values = new Map<string, string>();
  let current = app(),
    writes = 0;
  const local = hostStores(new HostLifetime(scope), {
    async read(key) {
      return values.get(key) ?? null;
    },
    async change(key, update) {
      await gate.promise;
      const next = update(values.get(key) ?? null);
      if (next === null) values.delete(key);
      else values.set(key, next);
    },
  });
  const controller = new FullAppController({
    scope,
    host: local,
    newId: () => "original",
    transport: async (request) => {
      if (request.op === "spec.getApp") return { app: current };
      if (request.op === "spec.capabilities") return caps;
      writes++;
      current = app(2, request.spec as typeof spec);
      return { app: current };
    },
  });
  await controller.load();
  controller.edit({
    type: "RenameLabel",
    targetId: "app",
    label: "Atomic save",
  });
  const saving = controller.save();
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(controller.getSnapshot().busy, true);
  assert.equal(await controller.flush(), false);
  await controller.save();
  assert.equal(controller.getSnapshot().busy, true);
  assert.equal(writes, 0);
  gate.resolve();
  await saving;
  assert.equal(writes, 1);
  assert.equal(controller.getSnapshot().busy, false);
  controller.dispose();
});
