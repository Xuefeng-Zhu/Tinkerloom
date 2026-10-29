/** Actual Dart business/worker orchestration; only HTTP authentication is stubbed. */
import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { randomBytes } from "node:crypto";
import { runReminderSmoke } from "./live_reminder_smoke.mjs";
import { workerReceipt, receiptHash } from "./live_reminder_contract.mjs";

const start = Date.UTC(2030, 0, 2);
const accounts = {
  owner: {
    id: "synthetic-owner",
    email: "tinkerloom-reminder-owner@example.test",
    password: "SyntheticOwnerPassword123!",
  },
  member: {
    id: "synthetic-member",
    email: "tinkerloom-reminder-member@example.test",
    password: "SyntheticMemberPassword123!",
  },
};
function configuration(waitSeconds = 0) {
  const target = {
    endpoint: "https://appwrite.invalid/v1",
    origin: "http://localhost:8426",
    projectId: "project",
    functionId: "core",
    coreDeploymentId: "core-deploy",
    workerFunctionId: "worker",
    workerDeploymentId: "worker-deploy",
    sourceCommit: "0677ee1",
    maxHttp: 300,
    timeoutMs: 1000,
    enableLiveReminders: true,
    waitSeconds,
  };
  const bytes = Buffer.from(
    JSON.stringify({
      schemaVersion: 1,
      capturedAt: new Date().toISOString(),
      projectId: target.projectId,
      coreFunctionId: target.functionId,
      coreDeploymentId: target.coreDeploymentId,
      workerFunctionId: target.workerFunctionId,
      workerDeploymentId: target.workerDeploymentId,
      execute: [],
      domains: [],
      intervalMinutes: 60,
      configuredWorkerIdentityMatches: true,
      remindersEnabled: { core: true, worker: true },
      executionScopesVerified: { core: true, worker: true },
      oneShot: { accepted: true, executionId: "synthetic-local-provenance" },
    }),
  );
  return {
    ...target,
    workerGate: workerReceipt(bytes, receiptHash(bytes), target),
  };
}
async function harness(
  t,
  {
    drain = true,
    loseThirdInstantiate = false,
    raceThirdInstantiate = false,
  } = {},
) {
  const child = spawn(
    process.env.TINKERLOOM_TEST_DART ?? "dart",
    ["--suppress-analytics", "run", "test/reminder_orchestration_bridge.dart"],
    {
      cwd: fileURLToPath(new URL("../appwrite_backend/", import.meta.url)),
      stdio: ["pipe", "pipe", "pipe"],
    },
  );
  t.after(() => {
    child.stdin.end();
    child.kill("SIGTERM");
  });
  let readyYes,
    readyNo,
    seen = false,
    instantiations = 0,
    localWorkerDrains = 0;
  const ready = new Promise((yes, no) => {
    readyYes = yes;
    readyNo = no;
  });
  const pending = [],
    calls = [],
    sessions = new Map();
  createInterface({ input: child.stdout }).on("line", (line) => {
    const value = JSON.parse(line);
    if (!seen) {
      seen = true;
      readyYes(value);
      return;
    }
    pending.shift()?.resolve(value);
  });
  child.stderr.on("data", () => {});
  child.on("error", () => readyNo(new Error("local_bridge_unavailable")));
  child.on("exit", () => {
    if (!seen) readyNo(new Error("local_bridge_unavailable"));
    for (const item of pending.splice(0))
      item.reject(new Error("local_bridge_closed"));
  });
  await ready;
  const rpc = (value) =>
    new Promise((resolve, reject) => {
      pending.push({ resolve, reject });
      child.stdin.write(JSON.stringify({ ...value, now: Date.now() }) + "\n");
    });
  const response = (status, value, headers = {}) =>
    new Response(status === 204 ? null : JSON.stringify(value), {
      status,
      headers,
    });
  const fetchImpl = async (url, options) => {
    const path = new URL(url).pathname.slice(3),
      body = options.body ? JSON.parse(options.body) : undefined;
    calls.push({ path, method: options.method, body });
    assert.equal(options.headers["X-Appwrite-Key"], undefined);
    assert.equal(options.headers["X-Appwrite-JWT"], undefined);
    assert.notEqual(options.method === "POST" ? path : null, "/account");
    if (path === "/account/sessions/email") {
      const actor = Object.values(accounts).find(
        (item) => item.email === body.email && item.password === body.password,
      );
      assert(actor);
      const cookie = "local-private-" + randomBytes(16).toString("hex");
      sessions.set(cookie, actor.id);
      return response(
        201,
        {},
        { "Set-Cookie": `a_session=${cookie}; Path=/; HttpOnly` },
      );
    }
    const cookie = options.headers.Cookie?.split("=", 2)[1],
      actor = sessions.get(cookie);
    if (path === "/account" && options.method === "GET")
      return response(200, { $id: actor });
    if (path === "/account/sessions/current" && options.method === "DELETE") {
      assert(actor);
      sessions.delete(cookie);
      return response(204, undefined, {
        "Set-Cookie": "a_session=; Max-Age=0; Path=/",
      });
    }
    assert.equal(path, "/functions/core/executions");
    assert(actor);
    const input = JSON.parse(body.body);
    assert.deepEqual(body.headers, { "content-type": "application/json" });
    assert(!Object.hasOwn(input, "proof"));
    assert(!Object.hasOwn(input, "clock"));
    assert(!Object.hasOwn(input, "now"));
    if (
      drain &&
      ["spec.runs", "spec.inbox", "spec.reminderState"].includes(input.op)
    ) {
      const result = await rpc({ kind: "localWorkerDrain", drains: 2 });
      assert.equal(result.status, 200);
      localWorkerDrains += 2;
    }
    const isThirdInstantiate =
      input.op === "spec.instantiate" && ++instantiations === 3;
    const result = await rpc({
      kind: "publicCore",
      actor,
      input,
      ...(isThirdInstantiate && raceThirdInstantiate
        ? { raceWorkerPlanning: true }
        : {}),
    });
    if (isThirdInstantiate && loseThirdInstantiate)
      throw new Error("PRIVATE_COMMITTED_RESPONSE_LOST");
    return response(201, {
      status: "completed",
      deploymentId: "core-deploy",
      responseStatusCode: result.status,
      responseBody: JSON.stringify(result.data),
    });
  };
  return {
    fetchImpl,
    calls,
    rpc,
    get localWorkerDrains() {
      return localWorkerDrains;
    },
    commands() {
      return calls
        .filter((item) => item.path.includes("/functions/"))
        .map((item) => JSON.parse(item.body.body));
    },
  };
}
const provider = async (label) => accounts[label];

test(
  "real PlatformService accepts the complete reminder setup, rule approval, old-record enrollment and member self-assignment",
  { timeout: 120000 },
  async (t) => {
    t.mock.timers.enable({ apis: ["Date"], now: start });
    const local = await harness(t);
    const report = await runReminderSmoke(configuration(), {
      actorCredentials: provider,
      fetchImpl: local.fetchImpl,
    });
    assert.equal(report.status, "observation_pending", JSON.stringify(report));
    assert(
      !report.checks.some((check) =>
        ["failed", "blocked"].includes(check.status),
      ),
      JSON.stringify(report),
    );
    assert(
      report.checks.find(
        (check) =>
          check.name === "set_real_future_dates_and_member_self_assignment",
      )?.status === "passed",
    );
    assert.equal(report.budget.cleanupSessions, 2);
    assert.equal(report.budget.syntheticAccounts, 0);
    assert.equal(
      local.commands().filter((command) => command.op === "spec.instantiate")
        .length,
      3,
    );
    t.diagnostic(
      JSON.stringify({
        localOnly: true,
        clock: "virtual",
        checks: report.checks,
        budget: report.budget,
      }),
    );
  },
);

test(
  "actual trusted local WorkerEngine reaches owner/member inbox delivery, suppresses changed/revoked recipients, and preserves receipt dedup",
  { timeout: 120000 },
  async (t) => {
    t.mock.timers.enable({ apis: ["Date"], now: start });
    const local = await harness(t);
    const report = await runReminderSmoke(configuration(300), {
      actorCredentials: provider,
      fetchImpl: local.fetchImpl,
      sleep: async (ms) => t.mock.timers.tick(ms),
    });
    assert.equal(report.status, "passed", JSON.stringify(report));
    assert(report.checks.some((check) => check.deliveredRuns === 2));
    assert(report.checks.some((check) => check.sameOccurrenceItems === 1));
    assert.equal(report.target.workerDeploymentObserved, false);
    assert.equal(report.budget.cleanupSessions, 2);
    assert(report.budget.httpRequests <= 300);
    assert(local.localWorkerDrains > 0);
    assert(Date.now() - start <= 300000);
    for (const value of Object.values(accounts).flatMap(Object.values))
      assert(!JSON.stringify(report).includes(value));
    assert(
      !local.calls.some((call) => call.path.includes("/functions/worker/")),
    );
    t.diagnostic(
      JSON.stringify({
        localOnly: true,
        clock: "virtual",
        checks: report.checks,
        budget: report.budget,
        localWorkerDrains: local.localWorkerDrains,
      }),
    );
  },
);

test(
  "real committed third instantiate with a deliberately lost response remains unknown and is never automatically replayed",
  { timeout: 120000 },
  async (t) => {
    t.mock.timers.enable({ apis: ["Date"], now: start });
    const local = await harness(t, { loseThirdInstantiate: true });
    const report = await runReminderSmoke(configuration(300), {
      actorCredentials: provider,
      fetchImpl: local.fetchImpl,
      sleep: async () => assert.fail("no retry"),
    });
    assert.equal(report.status, "observation_pending");
    assert.equal(report.budget.cleanupSessions, 2);
    assert.equal(
      local.commands().filter((command) => command.op === "spec.instantiate")
        .length,
      3,
    );
    assert.equal(
      local.commands().filter((command) => command.op === "spec.saveDraft")
        .length,
      0,
    );
    assert(!JSON.stringify(report).includes("PRIVATE_COMMITTED_RESPONSE_LOST"));
  },
);

test(
  "actual worker planning can conflict with a same-workspace instantiate without committing a partial app",
  { timeout: 120000 },
  async (t) => {
    t.mock.timers.enable({ apis: ["Date"], now: start });
    const local = await harness(t);
    const core = (input, options = {}) =>
      local.rpc({
        kind: "publicCore",
        actor: accounts.owner.id,
        input,
        ...options,
      });
    assert.equal(
      (
        await core({
          op: "createWorkspace",
          id: "shared-workspace",
          name: "Synthetic shared setup",
        })
      ).status,
      200,
    );
    for (let n = 1; n <= 2; n++)
      assert.equal(
        (
          await core({
            op: "spec.instantiate",
            id: `shared-app-${n}`,
            workspaceId: "shared-workspace",
            operationId: `shared-create-${n}`,
            templateKey: "chores",
          })
        ).status,
        200,
      );
    const conflict = await core(
      {
        op: "spec.instantiate",
        id: "shared-app-3",
        workspaceId: "shared-workspace",
        operationId: "shared-create-3",
        templateKey: "chores",
      },
      { raceWorkerPlanning: true },
    );
    assert.equal(conflict.status, 409);
    assert.equal(conflict.data.error, "transaction_conflict");
    const missing = await core({ op: "spec.getApp", appId: "shared-app-3" });
    assert.equal(missing.status, 404);
    assert.equal(missing.data.error, "not_found");
    t.diagnostic(
      JSON.stringify({
        localOnly: true,
        race: "worker_planning_versus_workspace_guard",
        functionStatus: conflict.status,
        backendCode: conflict.data.error,
      }),
    );
  },
);

test(
  "isolated probe workspaces permit setup while the actual worker plans earlier apps, with no write retry",
  { timeout: 120000 },
  async (t) => {
    t.mock.timers.enable({ apis: ["Date"], now: start });
    const local = await harness(t, { raceThirdInstantiate: true });
    const report = await runReminderSmoke(configuration(), {
      actorCredentials: provider,
      fetchImpl: local.fetchImpl,
      sleep: async () => assert.fail("no retry"),
    });
    assert.equal(report.status, "observation_pending", JSON.stringify(report));
    assert(
      !report.checks.some((check) =>
        ["failed", "blocked"].includes(check.status),
      ),
      JSON.stringify(report),
    );
    const creates = local
      .commands()
      .filter((command) => command.op === "spec.instantiate");
    assert.equal(creates.length, 3);
    assert.equal(
      new Set(creates.map((command) => command.workspaceId)).size,
      3,
    );
    assert.equal(report.budget.cleanupSessions, 2);
  },
);

test(
  "actual service with no local worker drain remains pending through the bounded virtual observation window",
  { timeout: 120000 },
  async (t) => {
    t.mock.timers.enable({ apis: ["Date"], now: start });
    const local = await harness(t, { drain: false });
    const report = await runReminderSmoke(configuration(300), {
      actorCredentials: provider,
      fetchImpl: local.fetchImpl,
      sleep: async (ms) => t.mock.timers.tick(ms),
    });
    assert.equal(report.status, "observation_pending", JSON.stringify(report));
    assert(
      !report.checks.some((check) =>
        ["failed", "blocked"].includes(check.status),
      ),
      JSON.stringify(report),
    );
    assert(
      report.checks.some(
        (check) => check.code === "observation_window_expired",
      ),
    );
    assert.equal(local.localWorkerDrains, 0);
    assert.equal(report.budget.cleanupSessions, 2);
    assert(report.budget.httpRequests <= 300);
    assert(Date.now() - start <= 300000);
    const mutations = local.commands().filter((command) => command.operationId);
    assert.equal(
      new Set(mutations.map((command) => command.operationId)).size,
      mutations.length,
    );
  },
);
