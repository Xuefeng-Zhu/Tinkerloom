import assert from "node:assert/strict";
import { createRequire, registerHooks } from "node:module";
import test from "node:test";
import { createElement, type ReactNode } from "react";
import { BackendError } from "../backend/errors";
import type { AppBackend } from "../backend/types";
import { HostLifetime, type HostScope } from "../host/scope";
import { hostStores } from "../host/storage";
import { RuntimeError } from "../runtime/errors";
import { fullTemplates } from "./catalog";
import {
  applyClarificationSelections,
  assessClarification,
  builtInClarification,
  canAssessClarification,
  cleanClarificationQuestions,
  originalClarificationRequest,
  selectClarificationAnswer,
} from "./clarification";
import { FullAppController } from "./FullAppController";
import { FullRegistry, type AccountSession } from "./FullRegistry";
import { FullWorkspaceController } from "./FullWorkspaceController";

const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const spec = fullTemplates.find((t) => t.id === "planner")!.spec;
const capabilities = {
  apiVersion: 1,
  formatVersions: [1],
  generation: false,
  guidance: true,
  effects: [],
  privateMedia: false,
};
const questions = [
  {
    question: "Who will use this app?",
    options: ["Just me", "A small team", "My community"],
  },
  { question: "What should it track?", options: ["Tasks", "Events", "Notes"] },
];
function manifest(id = "app", draft = true) {
  return {
    id,
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
    generation: null,
  };
}
function host(saved = new Map<string, string>(), appId = "app") {
  return hostStores(new HostLifetime({ ...scope, appId }), {
    async read(key) {
      return saved.get(key) ?? null;
    },
    async change(key, update) {
      const next = update(saved.get(key) ?? null);
      if (next === null) saved.delete(key);
      else saved.set(key, next);
    },
  });
}
function deferred<T = unknown>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
function assessor(
  overrides: Partial<Parameters<typeof assessClarification>[0]> = {},
) {
  return assessClarification({
    request: "  Plan a useful tool\n",
    mode: "create",
    providerEnabled: true,
    askProvider: async () => ({ questions }),
    isCurrent: () => true,
    isAlive: () => true,
    ...overrides,
  });
}
function appController(
  overrides: {
    guidance?: boolean;
    handler?: (request: Record<string, unknown>) => Promise<unknown>;
  } = {},
) {
  const calls: Record<string, unknown>[] = [];
  let current: Record<string, unknown> = manifest();
  let ids = 0;
  const controller = new FullAppController({
    scope,
    host: host(),
    newId: () => `operation_${++ids}`,
    transport: async (request) => {
      calls.push(request);
      if (request.op === "spec.getApp") return { app: current };
      if (request.op === "spec.capabilities")
        return { ...capabilities, guidance: overrides.guidance ?? true };
      return overrides.handler ? overrides.handler(request) : { questions };
    },
  });
  return {
    controller,
    calls,
    setApp: (value: typeof current) => {
      current = value;
    },
    get ids() {
      return ids;
    },
  };
}

test("guidance byte and character bounds are independent of the generation limit", () => {
  assert.equal(canAssessClarification("a".repeat(2000)), true);
  assert.equal(canAssessClarification("a".repeat(2001)), false);
  assert.equal(canAssessClarification("é".repeat(2000)), true);
  assert.equal(canAssessClarification("界".repeat(1500)), false);
  assert.equal(canAssessClarification("😀".repeat(1000)), true);
});

test("provider questions preserve explicit ready and strictly clean usable choices", () => {
  assert.deepEqual(cleanClarificationQuestions({ questions: [] }), []);
  assert.deepEqual(
    cleanClarificationQuestions({
      questions: questions.map((q) => ({
        question: ` ${q.question} `,
        options: q.options.map((o) => ` ${o} `),
      })),
    }),
    questions,
  );
  for (const value of [
    null,
    {},
    { questions: "wrong" },
    { questions: questions.slice(0, 1) },
    { questions: [...questions, ...questions] },
    { questions: [{ ...questions[0], options: ["A", "B"] }, questions[1]] },
    {
      questions: [
        { ...questions[0], options: ["One", "one", "Three"] },
        questions[1],
      ],
    },
    { questions: [questions[0], questions[0]] },
    {
      questions: [
        { ...questions[0], question: "No question mark" },
        questions[1],
      ],
    },
  ]) {
    assert.equal(cleanClarificationQuestions(value), null);
  }
});

test("long, disabled and unconfirmed provider checks use local labeled questions without network", async () => {
  let calls = 0;
  for (const providerEnabled of [false, null]) {
    const result = await assessor({
      providerEnabled,
      askProvider: async () => {
        calls++;
        return {};
      },
    });
    assert.equal(result?.source, "built-in");
    assert.equal(result?.requestText, "  Plan a useful tool\n");
  }
  const result = await assessor({
    request: "界".repeat(1500),
    mode: "edit",
    providerEnabled: async () => {
      calls++;
      return true;
    },
    askProvider: async () => {
      calls++;
      return {};
    },
  });
  assert.equal(calls, 0);
  assert.equal(result?.questions[0].question, "What should change first?");
  assert.match(result!.notice, /2,000 characters or 4,000 bytes/);
  assert.ok(Object.isFrozen(result?.questions[0].options));
});

test("unusable and temporarily unavailable provider answers fall back but access/session failures never do", async () => {
  const unusable = await assessor({
    askProvider: async () => ({
      questions: [{ question: "Bad?", options: [] }],
    }),
  });
  assert.equal(unusable?.source, "built-in");
  assert.match(unusable!.notice, /could not be used/);
  for (const failure of [
    new Error("network"),
    new RuntimeError("provider_unavailable", "Unavailable"),
    new RuntimeError("quota_exceeded", "Daily limit"),
    new BackendError("Conflict", "transaction_conflict", "service", false, 409),
  ]) {
    assert.equal(
      (
        await assessor({
          askProvider: async () => {
            throw failure;
          },
        })
      )?.source,
      "built-in",
    );
  }
  for (const failure of [
    new RuntimeError("forbidden", "Revoked"),
    new RuntimeError("not_found", "Gone"),
    new BackendError("Session closed", "session_changed", "transport", false),
  ]) {
    await assert.rejects(
      assessor({
        askProvider: async () => {
          throw failure;
        },
      }),
      (error) => error === failure,
    );
  }
});

test("zero provider questions gives a ready result and optional questions are purely local", async () => {
  const ready = await assessor({
    askProvider: async () => ({ questions: [] }),
  });
  assert.equal(ready?.ready, true);
  assert.match(ready!.notice, /actionable/);
  assert.equal(ready?.questions.length, 0);
  const optional = builtInClarification(
    ready!.requestText,
    ready!.mode,
    "optional",
  );
  assert.equal(optional.source, "built-in");
  assert.equal(optional.questions.length, 3);
  assert.equal(
    originalClarificationRequest(optional, ready!.requestText),
    ready!.requestText,
  );
});

test("one local answer per question replaces the choice and only explicit application changes the exact original text", async () => {
  const assessment = (await assessor())!;
  const original = assessment.requestText;
  const first = selectClarificationAnswer(assessment, {}, 0, 0);
  const changed = selectClarificationAnswer(assessment, first, 0, 2);
  const both = selectClarificationAnswer(assessment, changed, 1, 1);
  assert.deepEqual(first, { 0: 0 });
  assert.deepEqual(changed, { 0: 2 });
  assert.equal(assessment.requestText, original);
  assert.equal(
    originalClarificationRequest(assessment, original),
    "  Plan a useful tool\n",
  );
  assert.equal(
    applyClarificationSelections(assessment, original, both),
    `${original}\n\nMore details:\n- Who will use this app? My community\n- What should it track? Events`,
  );
  assert.equal(
    applyClarificationSelections(assessment, original, changed).includes(
      "Events",
    ),
    false,
  );
  assert.throws(
    () => applyClarificationSelections(assessment, original, {}),
    /Choose at least one/,
  );
  assert.throws(
    () => applyClarificationSelections(assessment, original.trim(), both),
    /request changed/,
  );
  assert.throws(
    () => selectClarificationAnswer(assessment, first, 0, 99),
    /available/,
  );
  assert.throws(
    () =>
      applyClarificationSelections(
        builtInClarification("a".repeat(16384), "create", "too_long"),
        "a".repeat(16384),
        { 0: 0 },
      ),
    /16 KiB/,
  );
});

test("editing while capability check is in flight prevents even a later provider request", async () => {
  const gate = deferred<boolean>();
  let current = true,
    calls = 0;
  const pending = assessor({
    providerEnabled: () => gate.promise,
    askProvider: async () => {
      calls++;
      return { questions };
    },
    isCurrent: () => current,
  });
  current = false;
  gate.resolve(true);
  assert.equal(await pending, null);
  assert.equal(calls, 0);
});

test("late ordinary errors are ignored; current-scope authority denial remains authoritative; disposed scopes expose nothing", async () => {
  for (const outcome of ["ordinary", "access", "disposed"] as const) {
    const gate = deferred();
    let current = true,
      alive = true;
    const pending = assessor({
      askProvider: () => gate.promise,
      isCurrent: () => current,
      isAlive: () => alive,
    });
    current = false;
    if (outcome === "disposed") alive = false;
    gate.reject(
      new RuntimeError(
        outcome === "ordinary" ? "provider_unavailable" : "forbidden",
        "Rejected",
      ),
    );
    if (outcome === "access") await assert.rejects(pending, /Rejected/);
    else assert.equal(await pending, null);
  }
});

test("builder help remains usable with provider off and keeps unsent request exact across navigation refresh", async () => {
  const f = appController({ guidance: false });
  await f.controller.load();
  const request = "  Please improve my planner\n";
  f.controller.setGenerationRequest(request);
  await f.controller.requestGuidance(request);
  assert.equal(f.controller.getSnapshot().guidance?.source, "built-in");
  assert.equal(f.controller.getSnapshot().guidance?.mode, "edit");
  assert.equal(f.controller.getSnapshot().generationRequest, request);
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().generationRequest, request);
  assert.equal(
    f.calls.filter(
      (v) => !["spec.getApp", "spec.capabilities"].includes(String(v.op)),
    ).length,
    0,
  );
  assert.equal(f.ids, 0);
  f.controller.dispose();
  assert.equal(f.controller.getSnapshot().generationRequest, "");
});

test("builder long and scratch requests use correct local mode; selections never create a generation command", async () => {
  const f = appController();
  await f.controller.load();
  const request = "界".repeat(1500);
  f.controller.setGenerationRequest(request);
  await f.controller.requestGuidance(request, true);
  const assessment = f.controller.getSnapshot().guidance!;
  assert.equal(assessment.mode, "create");
  f.controller.setGenerationRequest(
    applyClarificationSelections(assessment, request, { 0: 1 }),
  );
  assert.equal(f.controller.getSnapshot().guidance, null);
  assert.ok(f.controller.getSnapshot().generationRequest.startsWith(request));
  assert.equal(
    f.calls.some((v) =>
      ["spec.guidance", "spec.generate", "spec.createApp"].includes(
        String(v.op),
      ),
    ),
    false,
  );
  f.controller.dispose();
});

test("ready builder guidance offers local optional questions and unusable response has explicit fallback", async () => {
  let response: unknown = { questions: [] };
  const f = appController({ handler: async () => response });
  await f.controller.load();
  f.controller.setGenerationRequest("Plan a useful tool");
  await f.controller.requestGuidance("Plan a useful tool");
  assert.equal(f.controller.getSnapshot().guidance?.ready, true);
  const calls = f.calls.length;
  f.controller.useBuiltInGuidance();
  assert.equal(f.calls.length, calls);
  assert.equal(f.controller.getSnapshot().guidance?.source, "built-in");
  response = { questions: [{ question: "Bad?", options: [] }] };
  await f.controller.requestGuidance("Plan a useful tool");
  assert.match(
    f.controller.getSnapshot().guidance!.notice,
    /could not be used/,
  );
  assert.equal(f.controller.getSnapshot().error, null);
  f.controller.dispose();
});

test("late guidance success and failure cannot replace a newly edited composer or candidate", async () => {
  for (const reject of [false, true]) {
    const gate = deferred();
    const f = appController({ handler: async () => gate.promise });
    await f.controller.load();
    f.controller.setGenerationRequest("Original idea");
    const pending = f.controller.requestGuidance("Original idea");
    f.controller.setGenerationRequest("Changed idea");
    if (reject) gate.reject(new Error("late network error"));
    else gate.resolve({ questions });
    await pending;
    assert.equal(f.controller.getSnapshot().guidance, null);
    assert.equal(f.controller.getSnapshot().generationRequest, "Changed idea");
    assert.equal(f.controller.getSnapshot().error, null);
    assert.equal(f.controller.getSnapshot().guidanceLoading, false);
    f.controller.dispose();
  }
});

for (const status of [401, 403, 404]) {
  test(`builder ${status} clears planned text and private state even after the composer changed`, async () => {
    const gate = deferred();
    const f = appController({ handler: async () => gate.promise });
    f.controller.prepareIdea("Secret plan");
    assert.equal(f.controller.getSnapshot().preparedRequest, null);
    await f.controller.load();
    assert.equal(f.controller.getSnapshot().generationRequest, "Secret plan");
    const pending = f.controller.requestGuidance("Secret plan");
    f.controller.setGenerationRequest("A different unsent plan");
    gate.reject(
      new BackendError(
        "Denied",
        status === 404 ? "not_found" : "denied",
        status === 401 ? "unauthenticated" : "service",
        false,
        status,
      ),
    );
    await pending;
    assert.equal(f.controller.getSnapshot().app, null);
    assert.equal(f.controller.getSnapshot().candidate, null);
    assert.equal(f.controller.getSnapshot().preparedRequest, null);
    assert.equal(f.controller.getSnapshot().generationRequest, "");
    f.controller.dispose();
  });
}

test("prepared builder idea never displays before authority or after role loss, and cannot replace an edited unsent request", async () => {
  const f = appController();
  f.controller.prepareIdea("Original prepared idea");
  assert.equal(f.controller.getSnapshot().generationRequest, "");
  await f.controller.load();
  assert.equal(
    f.controller.getSnapshot().generationRequest,
    "Original prepared idea",
  );
  f.controller.setGenerationRequest("Keep my unsent request");
  f.controller.prepareIdea("Another prepared idea");
  assert.equal(
    f.controller.getSnapshot().generationRequest,
    "Keep my unsent request",
  );
  assert.equal(
    f.controller.getSnapshot().preparedRequest,
    "Another prepared idea",
  );
  f.setApp({
    ...manifest(),
    role: "viewer",
    capabilities: { editDefinition: false },
  });
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().preparedRequest, null);
  assert.equal(f.controller.getSnapshot().generationRequest, "");
  assert.equal(
    f.controller.prepareIdea("Cannot enter a revoked builder"),
    false,
  );
  assert.equal(f.controller.getSnapshot().generationRequest, "");
  f.controller.dispose();
});

test("archiving a shell without a candidate fences pending clarification and clears all planned text", async () => {
  const gate = deferred();
  const f = appController({ handler: async () => gate.promise });
  f.setApp(manifest("app", false));
  await f.controller.load();
  f.controller.setGenerationRequest("Private shell idea");
  const pending = f.controller.requestGuidance("Private shell idea");
  f.setApp({
    ...manifest("app", false),
    archived: true,
    capabilities: { editDefinition: false },
  });
  await f.controller.load();
  gate.resolve({ questions });
  await pending;
  assert.equal(f.controller.getSnapshot().app?.archived, true);
  assert.equal(f.controller.getSnapshot().generationRequest, "");
  assert.equal(f.controller.getSnapshot().guidance, null);
  assert.equal(f.controller.getSnapshot().guidanceLoading, false);
  f.controller.dispose();
});

test("session-epoch transport rejection clears only the closed controllers' planned text", async () => {
  const f = appController({
    handler: async () => {
      throw new BackendError("Session changed", "session_changed", "transport");
    },
  });
  await f.controller.load();
  f.controller.setGenerationRequest("Old session plan");
  await f.controller.requestGuidance("Old session plan");
  assert.equal(f.controller.getSnapshot().app, null);
  assert.equal(f.controller.getSnapshot().generationRequest, "");
  f.controller.dispose();
  const workspace = new FullWorkspaceController({
    scope,
    host: host(),
    workspaceId: "workspace",
    newId: () => "unused",
    transport: async () => {
      throw new BackendError("Session changed", "session_changed", "transport");
    },
  });
  workspace.setPlannedIdea("Old workspace plan");
  await workspace.requestGuidance("Old workspace plan");
  assert.equal(workspace.getSnapshot().plannedIdea, "");
  assert.equal(workspace.getSnapshot().guidance, null);
  workspace.dispose();
});

test("prepared request requires an explicit generation command and the retained payload keeps its exact text", async () => {
  const requestText = "  Build a useful planner\n";
  const writes: Record<string, unknown>[] = [];
  let id = 0;
  let current: Record<string, unknown> = manifest("app", false);
  const controller = new FullAppController({
    scope,
    host: host(),
    newId: () => `operation_${++id}`,
    transport: async (request) => {
      if (request.op === "spec.getApp") return { app: current };
      if (request.op === "spec.capabilities")
        return { ...capabilities, generation: true, guidance: false };
      writes.push(request);
      current = {
        ...current,
        generation: {
          id: "job",
          status: "queued",
          mode: "create",
          mutation: 1,
          attempts: 0,
          requestText: request.request,
          diagnostics: "",
          provider: null,
          model: null,
          nextAttemptAt: "2030-01-01T00:00:00Z",
          failureCategory: null,
        },
      };
      return { app: current, generation: current.generation };
    },
  });
  assert.equal(controller.prepareIdea(requestText), true);
  await controller.load();
  await controller.requestGuidance(requestText);
  assert.equal(writes.length, 0);
  assert.equal(controller.getSnapshot().generationRequest, requestText);
  await controller.generate(controller.getSnapshot().generationRequest);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].op, "spec.generate");
  assert.equal(writes[0].request, requestText);
  assert.equal(id, 1);
  assert.equal(writes[0].startFromScratch, true);
  assert.equal(controller.getSnapshot().generationRequest, "");
  assert.equal(
    controller.getSnapshot().conversation.entries[0].requestText,
    requestText,
  );
  assert.equal(
    controller.getSnapshot().conversation.entries[0].origin,
    "accepted",
  );
  controller.dispose();
});

test("refreshing an older job never overwrites a different unsent composer", async () => {
  const f = appController();
  await f.controller.load();
  f.controller.setGenerationRequest("  Keep this unsent idea exactly\n");
  f.setApp({
    ...manifest(),
    generation: {
      id: "job",
      status: "queued",
      mode: "edit",
      mutation: 1,
      attempts: 0,
      requestText: "Previously accepted idea",
      diagnostics: "",
      provider: null,
      model: null,
      nextAttemptAt: "2030-01-01T00:00:00Z",
      failureCategory: null,
    },
  });
  await f.controller.load();
  assert.equal(
    f.controller.getSnapshot().generationRequest,
    "  Keep this unsent idea exactly\n",
  );
  assert.equal(
    f.controller.getSnapshot().app?.generation?.requestText,
    "Previously accepted idea",
  );
  f.controller.dispose();
});

test("workspace help calls the real workspace-only envelope and never allocates an app or operation ID", async () => {
  const calls: Record<string, unknown>[] = [];
  let ids = 0;
  const controller = new FullWorkspaceController({
    scope,
    workspaceId: "workspace",
    host: host(),
    newId: () => `id_${++ids}`,
    transport: async (request) => {
      calls.push(request);
      return request.op === "spec.capabilities" ? capabilities : { questions };
    },
  });
  const original = "  A useful community tool\n";
  controller.setPlannedIdea(original);
  await controller.requestGuidance(original);
  assert.deepEqual(calls, [
    { op: "spec.capabilities" },
    { op: "spec.guidance", workspaceId: "workspace", request: original },
  ]);
  assert.equal(controller.getSnapshot().plannedIdea, original);
  assert.equal(controller.getSnapshot().guidance?.source, "provider");
  assert.equal(controller.getSnapshot().pending, null);
  assert.equal(ids, 0);
  controller.dispose();
});

test("workspace long/off requests have built-in fallback and typing during capability lookup cancels the provider call", async () => {
  const gate = deferred();
  const calls: Record<string, unknown>[] = [];
  let phase = "off";
  const controller = new FullWorkspaceController({
    scope,
    workspaceId: "workspace",
    host: host(),
    newId: () => "unused",
    transport: async (request) => {
      calls.push(request);
      return phase === "off"
        ? { ...capabilities, guidance: false }
        : gate.promise;
    },
  });
  await controller.requestGuidance("Useful idea");
  assert.equal(controller.getSnapshot().guidance?.source, "built-in");
  await controller.requestGuidance("a".repeat(2001));
  assert.equal(calls.length, 1);
  phase = "pending";
  const pending = controller.requestGuidance("Original idea");
  controller.setPlannedIdea("Changed idea");
  gate.resolve(capabilities);
  await pending;
  assert.equal(calls.length, 2);
  assert.equal(controller.getSnapshot().guidance, null);
  assert.equal(controller.getSnapshot().plannedIdea, "Changed idea");
  controller.dispose();
});

test("workspace authority loss clears private planning text synchronously and account disposal fences late answers", async () => {
  for (const disposed of [false, true]) {
    const gate = deferred();
    const controller = new FullWorkspaceController({
      scope,
      workspaceId: "workspace",
      host: host(),
      newId: () => "unused",
      transport: async (request) =>
        request.op === "spec.capabilities" ? capabilities : gate.promise,
    });
    controller.setPlannedIdea("Private workspace plan");
    const pending = controller.requestGuidance("Private workspace plan");
    await new Promise((resolve) => setTimeout(resolve, 0));
    if (disposed) controller.dispose();
    gate.reject(new BackendError("Denied", "forbidden", "service", false, 403));
    await pending;
    assert.equal(controller.getSnapshot().plannedIdea, "");
    assert.equal(controller.getSnapshot().guidance, null);
    assert.equal(controller.getSnapshot().guidanceLoading, false);
  }
});

test("unknown shell creation retains original memory idea without adding it to the durable command or RPC", async () => {
  const saved = new Map<string, string>();
  const calls: Record<string, unknown>[] = [],
    handoffs: [string, string][] = [];
  let lost = true,
    ids = 0;
  const controller = new FullWorkspaceController({
    scope,
    workspaceId: "workspace",
    host: host(saved),
    newId: () => `id_${++ids}`,
    onPreparedIdea: (id, request) => {
      handoffs.push([id, request]);
      return true;
    },
    transport: async (request) => {
      calls.push(request);
      if (request.op === "spec.launcher") return { apps: [], nextCursor: null };
      if (request.op === "spec.listDrafts")
        return { drafts: [], nextCursor: null };
      if (lost) throw new Error("lost response");
      return { app: manifest(String(request.id), false) };
    },
  });
  const original = "  My exact original private plan\n";
  controller.setPlannedIdea(original);
  await controller.create("Shell", original);
  assert.equal(controller.getSnapshot().pendingStatus, "uncertain");
  const encoded = [...saved.values()].join("");
  assert.equal(encoded.includes("original private plan"), false);
  controller.setPlannedIdea("A replacement idea");
  await controller.load();
  assert.deepEqual(handoffs, []);
  lost = false;
  await controller.retry();
  const writes = calls.filter((v) => v.op === "spec.createApp");
  assert.equal(ids, 2);
  assert.deepEqual(writes[1], writes[0]);
  assert.deepEqual(Object.keys(writes[0]).sort(), [
    "id",
    "name",
    "op",
    "operationId",
    "workspaceId",
  ]);
  assert.deepEqual(handoffs, [["id_1", original]]);
  assert.equal(controller.getSnapshot().createdIdeaStatus, "prepared");
  assert.equal(controller.getSnapshot().plannedIdea, "A replacement idea");
  controller.dispose();
});

test("reopened unknown creation restores no memory idea and cannot substitute newly entered planning text", async () => {
  const saved = new Map<string, string>();
  const handoffs: string[] = [];
  let lost = true;
  const options = {
    scope,
    workspaceId: "workspace",
    newId: () => "original_id",
    onPreparedIdea: (_: string, request: string) => {
      handoffs.push(request);
      return true;
    },
    transport: async (request: Record<string, unknown>) => {
      if (request.op === "spec.launcher") return { apps: [], nextCursor: null };
      if (request.op === "spec.listDrafts")
        return { drafts: [], nextCursor: null };
      if (lost) throw new Error("lost");
      return { app: manifest(String(request.id), false) };
    },
  };
  let controller = new FullWorkspaceController({
    ...options,
    host: host(saved),
  });
  await controller.create("Shell", "Private plan before restart");
  controller.dispose();
  controller = new FullWorkspaceController({ ...options, host: host(saved) });
  await controller.load();
  controller.setPlannedIdea("Different plan after restart");
  lost = false;
  await controller.retry();
  assert.deepEqual(handoffs, []);
  assert.equal(controller.getSnapshot().createdIdeaStatus, "not-restored");
  assert.equal(
    controller.getSnapshot().plannedIdea,
    "Different plan after restart",
  );
  controller.dispose();
});

function registryHost(scope: HostScope) {
  const saved = new Map<string, string>();
  return hostStores(new HostLifetime(scope), {
    async read(key) {
      return saved.get(key) ?? null;
    },
    async change(key, update) {
      const next = update(saved.get(key) ?? null);
      if (next === null) saved.delete(key);
      else saved.set(key, next);
    },
  });
}
test("actual account registry hands the original idea to only the created scoped app and clears it across account epochs", async () => {
  let session: AccountSession = { accountId: "alice", epoch: 1, active: true },
    ids = 0;
  const calls: Record<string, unknown>[] = [];
  const backend = {
    newId: () => `id_${++ids}`,
    executeSpec: async (request: Record<string, unknown>) => {
      calls.push(request);
      if (request.op === "spec.capabilities") return capabilities;
      if (request.op === "spec.getApp")
        return { app: manifest(String(request.appId), false) };
      if (request.op === "spec.createApp")
        return { app: manifest(String(request.id), false) };
      return request.op === "spec.launcher"
        ? { apps: [], nextCursor: null }
        : { drafts: [], nextCursor: null };
    },
  } as unknown as AppBackend;
  const registry = new FullRegistry({
    backend,
    scope,
    readSession: () => session,
    onUnauthenticated() {},
    hostFactory: registryHost,
  });
  const workspace = registry.workspace("alice", "workspace");
  await workspace.create("Shell", "  Scoped prepared idea\n");
  const app = registry.app("alice", "id_1");
  assert.equal(app.getSnapshot().preparedRequest, null);
  await app.load();
  assert.equal(app.getSnapshot().generationRequest, "  Scoped prepared idea\n");
  assert.equal(app.getSnapshot().preparedRequest, "  Scoped prepared idea\n");
  assert.equal(
    calls.some((v) => v.op === "spec.generate"),
    false,
  );
  session = { accountId: "alice", epoch: 2, active: true };
  registry.syncSession();
  assert.equal(app.getSnapshot().generationRequest, "");
  assert.equal(workspace.getSnapshot().plannedIdea, "");
  const replacement = registry.app("alice", "id_1");
  await replacement.load();
  assert.equal(replacement.getSnapshot().preparedRequest, null);
  assert.equal(replacement.getSnapshot().generationRequest, "");
  registry.dispose();
});

test("late shell receipt after account replacement cannot hand its private idea to the new account", async () => {
  let session: AccountSession = { accountId: "alice", epoch: 1, active: true };
  const gate = deferred();
  const backend = {
    newId: () => "new_app",
    executeSpec: async () => gate.promise,
  } as unknown as AppBackend;
  const registry = new FullRegistry({
    backend,
    scope,
    readSession: () => session,
    onUnauthenticated() {},
    hostFactory: registryHost,
  });
  const workspace = registry.workspace("alice", "workspace");
  const pending = workspace.create("Shell", "Private old-account idea");
  await new Promise((resolve) => setTimeout(resolve, 0));
  session = { accountId: "bob", epoch: 2, active: true };
  registry.syncSession();
  gate.resolve({ app: manifest("new_app", false) });
  await pending;
  const app = registry.app("bob", "new_app");
  assert.equal(app.getSnapshot().preparedRequest, null);
  assert.equal(app.getSnapshot().generationRequest, "");
  assert.equal(workspace.getSnapshot().plannedIdea, "");
  registry.dispose();
});

const webHooks = registerHooks({
  resolve(specifier, context, next) {
    return next(
      specifier === "react-native" ? "react-native-web" : specifier,
      context,
    );
  },
});
const panels = Promise.all([
  import("./GenerationPanel"),
  import("./ClarificationPanel"),
]);
const { renderToStaticMarkup } = createRequire(import.meta.url)(
  "react-dom/server",
) as { renderToStaticMarkup(element: ReactNode): string };
test.after(() => webHooks.deregister());
test("actual web panel offers help when generation/provider guidance is off, and ready result has a visible continuation", async () => {
  const [{ GenerationPanel }, { ClarificationPanel }] = await panels;
  const f = appController({ guidance: false });
  await f.controller.load();
  f.controller.setGenerationRequest("A useful local idea");
  const html = renderToStaticMarkup(
    createElement(GenerationPanel, {
      controller: f.controller,
      state: f.controller.getSnapshot(),
    }),
  );
  assert.match(html, /Help me clarify/);
  assert.match(html, /A useful local idea/);
  assert.match(html, /not configured/);
  const helpTag = html.match(/<[^>]+aria-label="Help me clarify"[^>]*>/)![0];
  assert.doesNotMatch(helpTag, /aria-disabled="true"/);
  const ready = (await assessor({
    askProvider: async () => ({ questions: [] }),
  }))!;
  const readyHtml = renderToStaticMarkup(
    createElement(ClarificationPanel, {
      assessment: ready,
      loading: false,
      currentRequest: ready.requestText,
      disabled: false,
      onUse() {},
      onContinue() {},
      onBuiltIn() {},
    }),
  );
  assert.match(readyHtml, /Ready to continue/);
  assert.match(readyHtml, /Continue with original request/);
  assert.match(readyHtml, /Show optional built-in questions/);
  assert.doesNotMatch(readyHtml, /Use selections/);
  f.controller.dispose();
});
