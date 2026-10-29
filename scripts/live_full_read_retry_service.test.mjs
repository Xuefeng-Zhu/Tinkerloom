/** Actual Dart service/worker with optimistic local REST simulation. Public HTTP/auth are injected stubs; never Cloud proof. */
import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { AppwriteUserClient, HttpBudget } from "./live_full_transport.mjs";
import { executeFullProbeOperation } from "./live_full_smoke.mjs";
import { exactKeys, validFullApp, validReview } from "./live_full_contract.mjs";
const config = {
  endpoint: "https://appwrite.invalid/v1",
  projectId: "synthetic",
  functionId: "core",
  coreDeploymentId: "deployment",
  origin: "http://localhost:8426",
  timeoutMs: 1000,
};
async function harness(t, { race = false, revoke = false } = {}) {
  const child = spawn(
    process.env.TINKERLOOM_TEST_DART ?? "dart",
    ["--suppress-analytics", "run", "test/full_read_retry_bridge.dart"],
    {
      cwd: fileURLToPath(new URL("../appwrite_backend/", import.meta.url)),
      stdio: ["pipe", "pipe", "pipe"],
    },
  );
  t.after(() => {
    child.stdin.end();
    child.kill("SIGTERM");
  });
  const pending = [];
  let readyYes,
    readyNo,
    readySeen = false;
  const ready = new Promise((yes, no) => {
    readyYes = yes;
    readyNo = no;
  });
  createInterface({ input: child.stdout }).on("line", (line) => {
    let value;
    try {
      value = JSON.parse(line);
    } catch {
      readyNo(new Error("offline_bridge_protocol"));
      return;
    }
    if (!readySeen) {
      readySeen = true;
      readyYes(value);
    } else pending.shift()?.resolve(value);
  });
  child.stderr.on("data", () => {});
  child.on("error", () => readyNo(new Error("offline_bridge_unavailable")));
  child.on("exit", () => {
    if (!readySeen) readyNo(new Error("offline_bridge_unavailable"));
    for (const p of pending.splice(0))
      p.reject(new Error("offline_bridge_closed"));
  });
  const initial = await ready,
    calls = [],
    evidence = [];
  let raceUsed = false;
  const rpc = (value) =>
    new Promise((resolve, reject) => {
      pending.push({ resolve, reject });
      child.stdin.write(JSON.stringify(value) + "\n");
    });
  const budget = new HttpBudget(100, 0);
  const client = (actor) =>
    new AppwriteUserClient(config, {
      budget,
      fetchImpl: async (url, options) => {
        assert.equal(new URL(url).pathname, "/v1/functions/core/executions");
        const envelope = JSON.parse(options.body),
          input = JSON.parse(envelope.body);
        calls.push({ actor, input, body: options.body });
        const arm = race && !raceUsed && input.op === "spec.getApp";
        if (arm) raceUsed = true;
        const result = await rpc({
          actor,
          input,
          ...(arm ? { raceRead: true, revokeAfterRace: revoke } : {}),
        });
        evidence.push({ op: input.op, ...result.localEvidence });
        return new Response(
          JSON.stringify({
            deploymentId: "deployment",
            status: "completed",
            responseStatusCode: result.status,
            responseBody: JSON.stringify(result.data),
          }),
          { status: 201 },
        );
      },
    });
  return {
    initial,
    calls,
    evidence,
    budget,
    owner: client("alice"),
    builder: client("bob"),
  };
}
async function phase(t, { race, recover }) {
  const f = await harness(t, { race });
  let assertions = 0,
    conflicts = 0,
    retries = 0;
  const check = (value) => {
    assertions++;
    if (!value) {
      const e = new Error("logical_assertion_failed");
      e.logicalAssertion = assertions;
      throw e;
    }
  };
  const execute = async (client, payload) => {
    const r = recover
      ? await executeFullProbeOperation(client, payload, {
          coreDeploymentId: "deployment",
          sleep: async () => {},
          onReadConflict: () => conflicts++,
          onReadRetry: () => retries++,
        })
      : await client.execute(payload);
    check(r.outer.status >= 200 && r.outer.status < 300);
    check(r.executionStatus === "completed");
    check(r.deploymentMatched === true);
    check(r.status === 200);
    return r.data;
  };
  const save = async (client, label, revision) => {
    const spec = { ...f.initial.app.version.spec, name: label };
    const r = await execute(client, {
      op: "spec.saveDraft",
      appId: "app-one",
      operationId:
        label === "Private owner candidate" ? "owner-save" : "builder-save",
      expectedRevision: revision,
      expectedVersionId: f.initial.app.version.id,
      spec,
    });
    check(
      exactKeys(r, ["app"]) &&
        validFullApp(r.app) &&
        r.app.draft.revision === revision + 1 &&
        r.app.draft.baseVersionId === f.initial.app.version.id,
    );
    return r.app;
  };
  const owner = await save(f.owner, "Private owner candidate", 1);
  await save(f.builder, "Private builder candidate", 0);
  const review = await execute(f.owner, {
    op: "spec.review",
    appId: "app-one",
    expectedRevision: owner.draft.revision,
    enabledRuleIds: [],
    activateExistingRecordIds: [],
  });
  check(exactKeys(review, ["review"]) && validReview(review.review));
  check(
    review.review.candidateHash === owner.draft.candidateHash &&
      review.review.expectedRevision === owner.draft.revision &&
      review.review.baseVersionId === owner.draft.baseVersionId &&
      review.review.compatibilityErrors.length === 0,
  );
  check(
    review.review.enabledRuleIds.length === 0 &&
      review.review.activateExistingRecordIds.length === 0,
  );
  let failure = null;
  try {
    for (const [client, name] of [
      [f.owner, "Private owner candidate"],
      [f.builder, "Private builder candidate"],
    ]) {
      const result = await execute(client, {
        op: "spec.getApp",
        appId: "app-one",
      });
      check(
        exactKeys(result, ["app"]) &&
          validFullApp(result.app) &&
          result.app.id === "app-one",
      );
      check(result.app.draft.spec.name === name);
    }
  } catch (e) {
    failure = e;
  }
  return { f, assertions, conflicts, retries, failure };
}
test(
  "actual worker versus private-author read recreates failure at logical assertion21 without client read recovery",
  { timeout: 60000 },
  async (t) => {
    const observed = await phase(t, { race: true, recover: false });
    assert.equal(observed.failure?.logicalAssertion, 21);
    assert.equal(observed.assertions, 21);
    assert.equal(observed.f.budget.used, 4);
    const read = observed.f.evidence.at(-1);
    assert.equal(read.op, "spec.getApp");
    assert.equal(read.newFailedTransactions, 1);
    assert.deepEqual(read.businessAfter, read.businessBefore);
  },
);
test(
  "same actual worker race recovers one identical read with healthy logical assertions/privacy and no new business receipt/audit/outbox",
  { timeout: 90000 },
  async (t) => {
    const healthy = await phase(t, { race: false, recover: true });
    const recovered = await phase(t, { race: true, recover: true });
    assert.equal(healthy.failure, null);
    assert.equal(recovered.failure, null);
    assert.equal(healthy.assertions, 29);
    assert.equal(recovered.assertions, 29);
    assert.equal(recovered.conflicts, 1);
    assert.equal(recovered.retries, 1);
    assert.equal(recovered.f.budget.used, healthy.f.budget.used + 1);
    const reads = recovered.f.calls.filter(
      (c) => c.actor === "alice" && c.input.op === "spec.getApp",
    );
    assert.equal(reads.length, 2);
    assert.equal(reads[0].body, reads[1].body);
    for (const read of recovered.f.evidence.filter(
      (e) => e.op === "spec.getApp",
    ))
      assert.deepEqual(read.businessAfter, read.businessBefore);
  },
);
test(
  "fresh actual authority is rechecked after read conflict and revoked builder gets404 without another retry",
  { timeout: 60000 },
  async (t) => {
    const f = await harness(t, { race: true, revoke: true });
    let conflicts = 0,
      retries = 0;
    const result = await executeFullProbeOperation(
      f.builder,
      { op: "spec.getApp", appId: "app-one" },
      {
        coreDeploymentId: "deployment",
        sleep: async () => {},
        onReadConflict: () => conflicts++,
        onReadRetry: () => retries++,
      },
    );
    assert.equal(result.status, 404);
    assert.deepEqual(result.data, { error: "not_found" });
    assert.equal(conflicts, 1);
    assert.equal(retries, 1);
    assert.equal(f.budget.used, 2);
    assert.equal(f.calls.length, 2);
  },
);
