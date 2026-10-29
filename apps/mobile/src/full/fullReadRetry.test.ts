import assert from "node:assert/strict";
import test from "node:test";
import {
  AppwriteBackend,
  type ExecutionResult,
  type SdkAdapter,
} from "../backend/core";
import { BackendError } from "../backend/errors";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { accountTransport } from "./FullRegistry";
import { FullAppController } from "./FullAppController";
import { fullTemplates } from "./catalog";

const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const spec = fullTemplates.find((template) => template.id === "planner")!.spec;
const caps = {
  apiVersion: 1,
  formatVersions: [1],
  generation: true,
  guidance: true,
  effects: ["notifyOwner"],
  privateMedia: false,
};
function app(name = "Private planner") {
  return {
    id: "app",
    workspaceId: "workspace",
    name,
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: { editDefinition: true },
    controlRevision: 1,
    allowedActions: [],
    version: null,
    draft: {
      revision: 1,
      baseVersionId: null,
      candidateHash: "candidate_hash",
      spec,
      publishedVersionId: null,
    },
    generation: null as unknown,
  };
}
function completed(value: unknown, status: unknown = 200): ExecutionResult {
  return {
    status: "completed",
    responseStatusCode: status,
    responseBody: JSON.stringify(value),
  };
}
const conflict = () => completed({ error: "transaction_conflict" }, 409);
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((yes) => {
    resolve = yes;
  });
  return { promise, resolve };
}
function fixture() {
  let ids = 0;
  let session = { accountId: "alice" as string | null, epoch: 1, active: true };
  const saved = new Map<string, string>(),
    requests: Record<string, unknown>[] = [],
    wires: string[] = [];
  const counts = new Map<string, number>();
  let current = app();
  let respond:
    | ((
        request: Record<string, unknown>,
        count: number,
      ) => Promise<ExecutionResult> | ExecutionResult)
    | null = null;
  let intercept:
    ((request: Record<string, unknown>) => Promise<unknown>) | null = null;
  const host = hostStores(new HostLifetime(scope), {
    async read(key) {
      return saved.get(key) ?? null;
    },
    async change(key, update) {
      const next = update(saved.get(key) ?? null);
      if (next === null) saved.delete(key);
      else saved.set(key, next);
    },
  });
  const sdk: SdkAdapter = {
    newId: () => `operation_${++ids}`,
    account: {
      get: async () => null,
      create: async () => null,
      createEmailPasswordSession: async () => null,
      deleteSession: async () => null,
    },
    async execute(wire) {
      wires.push(wire);
      const request = JSON.parse(wire),
        op = String(request.op),
        count = (counts.get(op) ?? 0) + 1;
      counts.set(op, count);
      if (respond) return respond(request, count);
      if (op === "spec.getApp" || op === "spec.getGeneration")
        return completed({ app: current });
      if (op === "spec.capabilities") return completed(caps);
      if (op === "spec.review")
        return completed({
          review: {
            candidateHash: "candidate_hash",
            expectedRevision: 1,
            baseVersionId: null,
            currentVersionId: null,
            reviewHash: "review_hash",
            changes: [],
            compatibilityErrors: [],
            enabledRuleIds: request.enabledRuleIds,
            activateExistingRecordIds: request.activateExistingRecordIds,
          },
        });
      assert.fail(`Unexpected request ${op}`);
    },
  };
  const backend = new AppwriteBackend(sdk);
  const transport = accountTransport({
    execute: (request) => backend.executeSpec(request),
    readSession: () => session,
    expected: { ...session },
    alive: () => host.lifetime.active,
    onUnauthenticated() {
      host.lifetime.dispose();
    },
  });
  const controller = new FullAppController({
    scope,
    host,
    newId: () => backend.newId(),
    transport: async (request) => {
      requests.push(request);
      if (intercept) return intercept(request);
      return transport(request);
    },
  });
  return {
    controller,
    host,
    saved,
    requests,
    wires,
    counts,
    get ids() {
      return ids;
    },
    get current() {
      return current;
    },
    set current(value: ReturnType<typeof app>) {
      current = value;
    },
    set respond(value: typeof respond) {
      respond = value;
    },
    set intercept(value: typeof intercept) {
      intercept = value;
    },
    closeAccount() {
      session = { accountId: null, epoch: 2, active: false };
      host.lifetime.dispose();
    },
    switchAccountBeforeRegistryCleanup() {
      session = { accountId: "bob", epoch: 2, active: true };
    },
  };
}

test("full manifest and capability reads repeat only completed definite SDK409 and retain frozen identical requests", async () => {
  const f = fixture();
  f.respond = (request, count) => {
    if (count <= 2) return conflict();
    return completed(request.op === "spec.getApp" ? { app: f.current } : caps);
  };
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().app?.id, "app");
  assert.equal(f.controller.getSnapshot().error, null);
  for (const op of ["spec.getApp", "spec.capabilities"]) {
    const requests = f.requests.filter((request) => request.op === op),
      wires = f.wires.filter((wire) => JSON.parse(wire).op === op);
    assert.equal(requests.length, 3);
    assert.equal(new Set(requests).size, 1);
    assert.ok(requests.every(Object.isFrozen));
    assert.equal(new Set(wires).size, 1);
  }
  assert.equal(f.ids, 0);
  assert.equal(f.saved.size, 0);
  f.controller.dispose();
});
test("exhausted manifest or capability409 makes exactly three attempts and preserves an honest failure", async () => {
  for (const op of ["spec.getApp", "spec.capabilities"]) {
    const f = fixture();
    f.respond = (request) =>
      request.op === op ? conflict() : completed({ app: f.current });
    await f.controller.load();
    assert.equal(f.counts.get(op), 3);
    assert.match(f.controller.getSnapshot().error!, /same time/);
    if (op === "spec.getApp")
      assert.equal(f.controller.getSnapshot().app, null);
    else assert.equal(f.controller.getSnapshot().platform, null);
    assert.equal(f.ids, 0);
    f.controller.dispose();
  }
});
test("unknown/raw errors, uncertain errors, different codes/statuses and malformed SDK status/body never retry", async () => {
  const cases: { sdk?: ExecutionResult; error?: unknown; direct?: boolean }[] =
    [
      { error: new Error("Unknown transport") },
      {
        error: {
          code: "transaction_conflict",
          kind: "service",
          status: 409,
          uncertain: false,
        },
        direct: true,
      },
      {
        error: new BackendError(
          "Unknown",
          "transaction_conflict",
          "service",
          true,
          409,
        ),
      },
      {
        error: new BackendError(
          "Wrong kind",
          "transaction_conflict",
          "transport",
          false,
          409,
        ),
      },
      {
        error: Object.assign(
          new BackendError(
            "Missing certainty",
            "transaction_conflict",
            "service",
            false,
            409,
          ),
          { uncertain: undefined },
        ),
      },
      {
        error: Object.assign(
          new BackendError(
            "Malformed certainty",
            "transaction_conflict",
            "service",
            false,
            409,
          ),
          { uncertain: 0 },
        ),
      },
      {
        error: new BackendError(
          "String status",
          "transaction_conflict",
          "service",
          false,
          "409" as unknown as number,
        ),
      },
      { sdk: completed({ error: "revision_conflict" }, 409) },
      { sdk: completed({ error: "transaction_conflict" }, 403) },
      { sdk: completed({ error: "transaction_conflict" }, 404) },
      { sdk: completed({ error: "transaction_conflict" }, 500) },
      { sdk: completed({ error: "transaction_conflict" }, "409") },
      {
        sdk: {
          status: "completed",
          responseStatusCode: 409,
          responseBody: "{",
        },
      },
      {
        sdk: {
          status: "processing",
          responseStatusCode: 409,
          responseBody: '{"error":"transaction_conflict"}',
        },
      },
      { sdk: completed({ error: { code: "transaction_conflict" } }, 409) },
      { sdk: completed({ error: "transaction_conflict" }) },
    ];
  for (const scenario of cases) {
    const f = fixture();
    if (scenario.direct)
      f.intercept = async () => {
        throw scenario.error;
      };
    else
      f.respond = () => {
        if (scenario.error) throw scenario.error;
        return scenario.sdk!;
      };
    await f.controller.load();
    assert.equal(f.requests.length, 1);
    assert.equal(f.controller.getSnapshot().app, null);
    assert.ok(f.controller.getSnapshot().error);
    f.controller.dispose();
  }
});
test("disposal, lifetime closure or changed account during conflict backoff prevents every extra SDK HTTP request", async () => {
  for (const close of ["dispose", "lifetime", "session"]) {
    const f = fixture(),
      entered = deferred<void>();
    f.respond = () => {
      entered.resolve();
      return conflict();
    };
    const loading = f.controller.load();
    await entered.promise;
    // Let the real execution decoder reject before closing the retry's captured session.
    await new Promise((resolve) => setTimeout(resolve, 10));
    if (close === "dispose") f.controller.dispose();
    else if (close === "lifetime") f.closeAccount();
    else f.switchAccountBeforeRegistryCleanup();
    await loading;
    assert.equal(f.wires.length, 1);
    assert.equal(f.controller.getSnapshot().app, null);
    f.controller.dispose();
  }
});
test("a superseding load cancels conflict backoff and a late successful older manifest cannot replace it", async () => {
  for (const late of [false, true]) {
    const f = fixture(),
      entered = deferred<void>(),
      response = deferred<ExecutionResult>();
    f.respond = (request, count) => {
      if (request.op === "spec.capabilities") return completed(caps);
      if (count === 1) {
        entered.resolve();
        return late ? response.promise : conflict();
      }
      return completed({ app: app("Newer authorized manifest") });
    };
    const older = f.controller.load();
    await entered.promise;
    if (!late) await new Promise((resolve) => setTimeout(resolve, 10));
    await f.controller.load();
    response.resolve(completed({ app: app("Obsolete private manifest") }));
    await older;
    assert.equal(f.counts.get("spec.getApp"), 2);
    assert.equal(
      f.controller.getSnapshot().app?.name,
      "Newer authorized manifest",
    );
    assert.equal(f.controller.getSnapshot().error, null);
    f.controller.dispose();
  }
});
test("a current403 after a definite conflict clears previously loaded private authority instead of retrying denial", async () => {
  const f = fixture();
  await f.controller.load();
  assert.ok(f.controller.getSnapshot().candidate);
  const start = f.counts.get("spec.getApp")!;
  f.respond = (_request, count) =>
    count === start + 1 ? conflict() : completed({ error: "forbidden" }, 403);
  await f.controller.load();
  assert.equal(f.counts.get("spec.getApp"), start + 2);
  assert.equal(f.controller.getSnapshot().app, null);
  assert.equal(f.controller.getSnapshot().candidate, null);
  assert.equal(f.controller.previewSpec, null);
  assert.equal(f.controller.runtime, null);
  f.controller.dispose();
});
test("a superseding load cancels capability retries and fences a late obsolete access denial", async () => {
  for (const late of [false, true]) {
    const f = fixture(),
      entered = deferred<void>(),
      response = deferred<ExecutionResult>();
    f.respond = (request, count) => {
      if (request.op === "spec.getApp")
        return completed({
          app: app(count === 1 ? "Original" : "Fresh authority"),
        });
      if (count === 1) {
        entered.resolve();
        return late ? response.promise : conflict();
      }
      return completed(caps);
    };
    const older = f.controller.load();
    await entered.promise;
    if (!late) await new Promise((resolve) => setTimeout(resolve, 10));
    await f.controller.load();
    response.resolve(completed({ error: "forbidden" }, 403));
    await older;
    assert.equal(f.counts.get("spec.capabilities"), 2);
    assert.equal(f.controller.getSnapshot().app?.name, "Fresh authority");
    assert.equal(f.controller.getSnapshot().error, null);
    assert.equal(f.controller.getSnapshot().platform?.generation, true);
    f.controller.dispose();
  }
});
test("review retries preserve revision and deeply frozen approved arrays after caller mutation", async () => {
  const f = fixture();
  await f.controller.load();
  const rules = ["taskReminder"],
    records = ["record_1"],
    entered = deferred<void>();
  f.respond = (request, count) => {
    assert.equal(request.op, "spec.review");
    if (count === 1) {
      entered.resolve();
      return conflict();
    }
    return completed({
      review: {
        candidateHash: "candidate_hash",
        expectedRevision: 1,
        baseVersionId: null,
        currentVersionId: null,
        reviewHash: "review_hash",
        changes: [],
        compatibilityErrors: [],
        enabledRuleIds: request.enabledRuleIds,
        activateExistingRecordIds: request.activateExistingRecordIds,
      },
    });
  };
  const reviewing = f.controller.review(rules, records);
  await entered.promise;
  rules.push("unapproved");
  records[0] = "different_record";
  await reviewing;
  const attempts = f.requests.filter((request) => request.op === "spec.review");
  assert.equal(attempts.length, 2);
  assert.equal(attempts[0], attempts[1]);
  assert.ok(Object.isFrozen(attempts[0]));
  assert.ok(Object.isFrozen(attempts[0].enabledRuleIds));
  assert.ok(Object.isFrozen(attempts[0].activateExistingRecordIds));
  assert.deepEqual(attempts[0], {
    op: "spec.review",
    appId: "app",
    expectedRevision: 1,
    enabledRuleIds: ["taskReminder"],
    activateExistingRecordIds: ["record_1"],
  });
  assert.deepEqual(
    f.controller.getSnapshot().review?.activateExistingRecordIds,
    ["record_1"],
  );
  assert.equal(f.ids, 0);
  f.controller.dispose();
});
test("generation polling retries the same captured job and cannot install values after a superseding load", async () => {
  for (const supersede of [false, true]) {
    const f = fixture();
    f.current.generation = {
      id: "job_1",
      mode: "edit",
      status: "queued",
      mutation: 1,
      attempts: 0,
      requestText: "Retained request",
      diagnostics: "",
      provider: null,
      model: null,
      failureCategory: null,
      nextAttemptAt: "2030-01-01T00:00:00Z",
    };
    await f.controller.load();
    const entered = deferred<void>();
    f.respond = (request, count) => {
      if (request.op === "spec.getGeneration" && count === 1) {
        entered.resolve();
        return conflict();
      }
      if (request.op === "spec.capabilities") return completed(caps);
      return completed({ app: f.current });
    };
    const polling = f.controller.pollGeneration();
    await entered.promise;
    if (supersede) {
      f.current = app("Current separate load");
      await f.controller.load();
    }
    await polling;
    const attempts = f.requests.filter(
      (request) => request.op === "spec.getGeneration",
    );
    assert.equal(attempts.length, supersede ? 1 : 2);
    assert.deepEqual(attempts[0], {
      op: "spec.getGeneration",
      appId: "app",
      jobId: "job_1",
    });
    if (!supersede) assert.equal(attempts[0], attempts[1]);
    else
      assert.equal(
        f.controller.getSnapshot().app?.name,
        "Current separate load",
      );
    assert.equal(f.ids, 0);
    f.controller.dispose();
  }
});
test("mutations and optional provider guidance never use the known-read retry path or allocate another command", async () => {
  const f = fixture();
  await f.controller.load();
  f.respond = () => conflict();
  await f.controller.requestGuidance("Add a simple notes workflow");
  assert.equal(f.counts.get("spec.guidance"), 1);
  f.controller.setCandidate({ ...spec, name: "Explicit unsent edit" });
  await f.controller.save();
  assert.equal(f.counts.get("spec.saveDraft"), 1);
  assert.equal(f.ids, 1);
  assert.equal(f.controller.getSnapshot().pendingStatus, "uncertain");
  assert.equal(
    f.controller.getSnapshot().pending?.request.operationId,
    "operation_1",
  );
  assert.ok(f.saved.size > 0);
  f.controller.dispose();
});
