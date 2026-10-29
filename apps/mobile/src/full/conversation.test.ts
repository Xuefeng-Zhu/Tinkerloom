import assert from "node:assert/strict";
import test from "node:test";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { RuntimeError } from "../runtime/errors";
import { FullAppController } from "./FullAppController";
import { fullTemplates } from "./catalog";
import type { Generation } from "./contracts";
import {
  AcceptedConversation,
  CONVERSATION_ENTRY_LIMIT,
  conversationOutcome,
} from "./conversation";
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const spec = fullTemplates.find((t) => t.id === "planner")!.spec;
function job(
  requestText = "  Build a useful planner\n",
  patch: Partial<Generation> = {},
): Generation {
  return {
    id: "job",
    status: "queued",
    mode: "create",
    mutation: 1,
    attempts: 0,
    requestText,
    diagnostics: "Private provider diagnostics",
    provider: "private-provider",
    model: "private-model",
    nextAttemptAt: "2030-01-01T00:00:00Z",
    failureCategory: null,
    ...patch,
  };
}
function app(generation: Generation | null = null, draft = false) {
  return {
    id: "app",
    workspaceId: "workspace",
    name: "Planner",
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: { editDefinition: true },
    controlRevision: 1,
    allowedActions: [],
    version: null,
    draft: draft
      ? {
          revision: 1,
          baseVersionId: null,
          candidateHash: "hash_1",
          spec,
          publishedVersionId: null,
        }
      : null,
    generation,
  };
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
function fixture(saved = new Map<string, string>()) {
  let current: Record<string, unknown> = app(),
    ids = 0;
  const calls: Record<string, unknown>[] = [];
  let mutation: (request: Record<string, unknown>) => Promise<unknown> = async (
    request,
  ) => {
    const generation = job(String(request.request));
    current = app(generation);
    return { app: current, generation };
  };
  let failRead = false,
    failClear = false;
  let poll: (() => Promise<unknown>) | null = null;
  const host = hostStores(new HostLifetime(scope), {
    async read(key) {
      return saved.get(key) ?? null;
    },
    async change(key, update) {
      const next = update(saved.get(key) ?? null);
      if (next === null && failClear) throw new Error("Storage unavailable");
      if (next === null) saved.delete(key);
      else saved.set(key, next);
    },
  });
  const controller = new FullAppController({
    scope,
    host,
    newId: () => `operation_${++ids}`,
    transport: async (request) => {
      calls.push(request);
      if (request.op === "spec.getApp") {
        if (failRead) throw new Error("Read unavailable");
        return { app: current };
      }
      if (request.op === "spec.capabilities")
        return {
          apiVersion: 1,
          formatVersions: [1],
          generation: true,
          guidance: false,
          effects: [],
          privateMedia: false,
        };
      if (request.op === "spec.getGeneration")
        return poll ? poll() : { app: current, generation: current.generation };
      assert.ok(
        saved.size > 0,
        "The exact request must be durable before transport",
      );
      return mutation(request);
    },
  });
  return {
    controller,
    calls,
    saved,
    set current(value: Record<string, unknown>) {
      current = value;
    },
    get current() {
      return current;
    },
    set mutation(value: typeof mutation) {
      mutation = value;
    },
    set failRead(value: boolean) {
      failRead = value;
    },
    set failClear(value: boolean) {
      failClear = value;
    },
    set poll(value: (() => Promise<unknown>) | null) {
      poll = value;
    },
    writes: () => calls.filter((c) => c.op === "spec.generate"),
  };
}

test("accepted conversation stores exact requests and factual status, deduplicates jobs, bounds memory and excludes provider bodies", () => {
  const history = new AcceptedConversation();
  const request = "  Preserve spaces\n";
  history.accept(job(request), "accepted");
  history.observe(job(request));
  assert.equal(history.getSnapshot().entries[0].requestText, request);
  assert.equal(history.getSnapshot().entries[0].current, true);
  assert.doesNotMatch(
    JSON.stringify(history.getSnapshot()),
    /Private provider|private-provider|private-model/,
  );
  history.accept(job(request), "restored");
  assert.equal(history.getSnapshot().entries.length, 1);
  assert.throws(
    () => history.accept(job("Changed identity"), "accepted"),
    /identity changed/,
  );
  history.observe(job(request, { status: "preview ready", attempts: 2 }));
  assert.match(
    conversationOutcome(history.getSnapshot().entries[0]),
    /validated private preview/,
  );
  for (let i = 0; i < 55; i++)
    history.accept(job("x".repeat(16384), { id: `job_${i}` }), "accepted");
  assert.ok(history.getSnapshot().entries.length < CONVERSATION_ENTRY_LIMIT);
  assert.ok(history.getSnapshot().omitted > 0);
  assert.equal(history.getSnapshot().entries.at(-1)?.requestText.length, 16384);
  assert.ok(Object.isFrozen(history.getSnapshot().entries[0]));
  history.clear();
  assert.deepEqual(history.getSnapshot(), { entries: [], omitted: 0 });
});

test("a blank shell sends create mode and adds one accepted request only after exact response and fresh authorization", async () => {
  const f = fixture(),
    gate = deferred<unknown>(),
    entered = deferred<void>();
  f.mutation = async (request) => {
    entered.resolve();
    return gate.promise;
  };
  await f.controller.load();
  const request = "  Exact accepted idea\n";
  f.controller.setGenerationRequest(request);
  const sending = f.controller.generate(request);
  await entered.promise;
  assert.equal(f.writes()[0].startFromScratch, true);
  assert.equal(f.controller.getSnapshot().conversation.entries.length, 0);
  assert.equal(f.writes()[0].request, request);
  const generation = job(request);
  f.current = app(generation);
  gate.resolve({ app: f.current, generation });
  await sending;
  const state = f.controller.getSnapshot();
  assert.equal(state.generationRequest, "");
  assert.equal(state.conversation.entries.length, 1);
  assert.equal(state.conversation.entries[0].origin, "accepted");
  assert.equal(state.conversation.entries[0].requestText, request);
  assert.equal(f.saved.size, 0);
  assert.equal(f.writes().length, 1);
  f.controller.dispose();
  assert.equal(f.controller.getSnapshot().conversation.entries.length, 0);
});

test("an accepted older request never clears a different unsent composer and a template remains edit mode", async () => {
  const f = fixture(),
    gate = deferred<unknown>(),
    entered = deferred<void>();
  f.current = app(null, true);
  f.mutation = async () => {
    entered.resolve();
    return gate.promise;
  };
  await f.controller.load();
  const sending = f.controller.generate("Original");
  await entered.promise;
  assert.equal(f.writes()[0].startFromScratch, false);
  f.controller.setGenerationRequest("  Newer unsent idea\n");
  const generation = job("Original", { mode: "edit", mutation: 2 });
  f.current = app(generation, true);
  gate.resolve({ app: f.current, generation });
  await sending;
  assert.equal(
    f.controller.getSnapshot().generationRequest,
    "  Newer unsent idea\n",
  );
  assert.equal(
    f.controller.getSnapshot().conversation.entries[0].requestText,
    "Original",
  );
  f.controller.dispose();
});

test("lost generation response reopens without auto acceptance or replay, then explicit exact retry appends once", async () => {
  const f = fixture();
  const request = "  Original unknown idea\n";
  f.mutation = async () => {
    f.current = app(job(request));
    throw new Error("Lost response");
  };
  await f.controller.load();
  await f.controller.generate(request);
  assert.equal(f.controller.getSnapshot().pendingStatus, "uncertain");
  assert.equal(f.controller.getSnapshot().conversation.entries.length, 0);
  const retained = f.writes()[0],
    server = f.current;
  f.controller.dispose();
  const reopened = fixture(f.saved);
  reopened.current = server;
  await reopened.controller.load();
  assert.equal(reopened.writes().length, 0);
  assert.equal(
    reopened.controller.getSnapshot().conversation.entries.length,
    0,
  );
  assert.equal(reopened.controller.getSnapshot().generationRequest, request);
  reopened.mutation = async (input) => {
    assert.deepEqual(input, retained);
    return { app: server, generation: server.generation };
  };
  await reopened.controller.retry();
  assert.equal(reopened.writes().length, 1);
  assert.equal(
    reopened.controller.getSnapshot().conversation.entries.length,
    1,
  );
  assert.equal(
    reopened.controller.getSnapshot().conversation.entries[0].origin,
    "accepted",
  );
  assert.equal(reopened.controller.getSnapshot().generationRequest, "");
  reopened.controller.dispose();
});

test("a malformed or mismatched generation acknowledgement cannot clear recovery or enter conversation", async () => {
  for (const change of [
    { requestText: "Substituted" },
    { mutation: 99 },
    { id: "foreign" },
  ]) {
    const f = fixture();
    f.mutation = async (request) => {
      const correct = job(String(request.request)),
        generation = { ...correct, ...change };
      return { app: app(correct), generation };
    };
    await f.controller.load();
    await f.controller.generate("Original");
    assert.equal(f.controller.getSnapshot().conversation.entries.length, 0);
    assert.equal(f.controller.getSnapshot().pendingStatus, "uncertain");
    assert.ok(f.saved.size > 0);
    f.controller.dispose();
  }
});

test("a received acknowledgement with failed durable clear stays uncertain and never claims acceptance", async () => {
  const f = fixture();
  f.failClear = true;
  await f.controller.load();
  await f.controller.generate("Original");
  assert.equal(f.controller.getSnapshot().pendingStatus, "uncertain");
  assert.equal(f.controller.getSnapshot().conversation.entries.length, 0);
  f.failClear = false;
  await f.controller.retry();
  assert.equal(f.controller.getSnapshot().conversation.entries.length, 1);
  f.controller.dispose();
});

test("a confirmed receipt waits for a fresh successful manifest before showing history and preserves its acceptance across read failure", async () => {
  const f = fixture();
  f.mutation = async (request) => {
    const generation = job(String(request.request));
    f.current = app(generation);
    f.failRead = true;
    return { app: f.current, generation };
  };
  await f.controller.load();
  await f.controller.generate("Original");
  assert.equal(f.saved.size, 0);
  assert.equal(f.controller.getSnapshot().conversation.entries.length, 0);
  assert.equal(f.controller.getSnapshot().refreshRequired, true);
  f.failRead = false;
  await f.controller.load();
  assert.equal(
    f.controller.getSnapshot().conversation.entries[0].origin,
    "accepted",
  );
  assert.equal(f.writes().length, 1);
  f.controller.dispose();
});

test("fresh reopening restores only latest authorized request and status changes never invent older outcomes", async () => {
  const f = fixture();
  f.current = app(
    job("Earlier", { id: "earlier", status: "generating", attempts: 1 }),
  );
  await f.controller.load();
  assert.equal(
    f.controller.getSnapshot().conversation.entries[0].origin,
    "restored",
  );
  assert.equal(f.controller.getSnapshot().generationRequest, "");
  f.current = app(
    job("Earlier", { id: "earlier", status: "preview ready", attempts: 2 }),
  );
  await f.controller.pollGeneration();
  assert.equal(
    f.controller.getSnapshot().conversation.entries[0].status,
    "preview ready",
  );
  f.current = app(job("Newer", { id: "newer", status: "stale" }));
  await f.controller.load();
  const entries = f.controller.getSnapshot().conversation.entries;
  assert.equal(entries.length, 2);
  assert.equal(entries[0].current, false);
  assert.equal(entries[1].current, false);
  assert.equal(entries[0].status, "preview ready");
  assert.match(conversationOutcome(entries[1]), /superseded/);
  f.current = {
    ...app(),
    role: "viewer",
    capabilities: { editDefinition: false },
  };
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().conversation.entries.length, 0);
  f.controller.dispose();
});

test("access loss or late responses after account disposal clear private conversation without deleting an unknown journal", async () => {
  const f = fixture();
  await f.controller.load();
  await f.controller.generate("Private accepted idea");
  assert.equal(f.controller.getSnapshot().conversation.entries.length, 1);
  f.mutation = async () => {
    throw new RuntimeError("forbidden", "Access removed");
  };
  await f.controller.generate("Another private request");
  assert.equal(f.controller.getSnapshot().conversation.entries.length, 0);
  assert.equal(f.controller.getSnapshot().generationRequest, "");
  assert.ok(f.saved.size > 0);
  const late = fixture(),
    gate = deferred<unknown>(),
    entered = deferred<void>();
  late.mutation = async () => {
    entered.resolve();
    return gate.promise;
  };
  await late.controller.load();
  const sending = late.controller.generate("Private late idea");
  await entered.promise;
  late.controller.dispose();
  const generation = job("Private late idea");
  gate.resolve({ app: app(generation), generation });
  await sending;
  assert.equal(late.controller.getSnapshot().conversation.entries.length, 0);
  assert.ok(late.saved.size > 0);
});

test("an in-flight generation poll cannot replace the selected declaration beneath rejected raw input", async () => {
  const f = fixture(),
    generation = job("Original", { mode: "edit" }),
    gate = deferred<unknown>();
  f.current = app(generation, true);
  await f.controller.load();
  const original = f.controller.getSnapshot().candidate,
    epoch = f.controller.getSnapshot().editorResetEpoch;
  let rawAccepted = true;
  const unregister = f.controller.registerEditorInputGuard(() => rawAccepted);
  f.poll = () => gate.promise;
  const polling = f.controller.pollGeneration();
  rawAccepted = false;
  const different = fullTemplates.find((t) => t.id === "notes")?.spec ?? {
    ...spec,
    name: "Remote change",
  };
  const remote = {
    ...app({ ...generation, status: "preview ready" }, true),
    draft: {
      ...app(null, true).draft!,
      revision: 2,
      spec: different,
      candidateHash: "remote_hash",
    },
  };
  gate.resolve({ app: remote, generation: remote.generation });
  await polling;
  assert.equal(f.controller.getSnapshot().candidate, original);
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch);
  assert.equal(f.controller.hasRejectedEditorInput, true);
  assert.equal(f.controller.getSnapshot().conflict, true);
  assert.equal(
    f.controller.getSnapshot().conversation.entries[0].status,
    "preview ready",
  );
  const reads = f.calls.filter((c) => c.op === "spec.getGeneration").length;
  await f.controller.pollGeneration();
  assert.equal(
    f.calls.filter((c) => c.op === "spec.getGeneration").length,
    reads,
  );
  unregister();
  f.controller.discardLocalEdits();
  assert.equal(f.controller.getSnapshot().candidate?.name, different.name);
  f.controller.dispose();
});
