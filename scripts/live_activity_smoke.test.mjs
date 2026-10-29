/** Real business service; test auth and HTTP boundaries are explicit stubs. */
import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { randomBytes } from "node:crypto";
import {
  runActivitySmoke,
  activityPage,
  verifyActivityConfiguration,
} from "./live_activity_smoke.mjs";
const labels = ["owner", "builder", "member", "viewer", "outsider"];
const config = () => ({
  enableLiveActivity: true,
  endpoint: "https://appwrite.invalid/v1",
  origin: "http://localhost:8426",
  projectId: "project",
  functionId: "core",
  databaseId: "db",
  coreDeploymentId: "activity-core",
  preflightAppId: "preflight-app",
  sourceCommit: "a05b362",
  sourceSha256: "a".repeat(64),
  maxHttp: 180,
  timeoutMs: 1000,
});
const credentials = Object.fromEntries(
  labels.map((label) => [
    label,
    {
      id: `usr-${label}`,
      email: `tinkerloom-offline-${label}@example.test`,
      password: "SyntheticPrivatePassword123!" + label,
    },
  ]),
);
const provider = async (label) => credentials[label];
function fixturePage() {
  return {
    appId: "app",
    items: [
      {
        id: "a-one",
        action: "records.create.v1",
        createdAt: "2030-01-02T00:00:00.000Z",
        status: "committed",
      },
    ],
    nextCursor: null,
  };
}

test("activity probe requires explicit enable, exact source/deployment, bounded budget and memory pool before dispatch", async () => {
  let calls = 0;
  for (const [change, actorCredentials] of [
    [{ enableLiveActivity: false }, provider],
    [{ coreDeploymentId: null }, provider],
    [{ sourceSha256: null }, provider],
    [{ preflightAppId: "bad/id" }, provider],
    [{ maxHttp: 181 }, provider],
    [{ timeoutMs: 60001 }, provider],
    [{}, undefined],
  ])
    await assert.rejects(
      runActivitySmoke(
        { ...config(), ...change },
        {
          actorCredentials,
          fetchImpl: async () => {
            calls++;
            assert.fail();
          },
        },
      ),
    );
  assert.equal(calls, 0);
  assert.doesNotThrow(() => verifyActivityConfiguration(config(), provider));
});
test("activity metadata parser accepts only exact committed fields and refuses private values and malformed pages", () => {
  assert.deepEqual(activityPage(fixturePage(), "app"), fixturePage());
  for (const page of [
    { ...fixturePage(), appId: "foreign" },
    { ...fixturePage(), payload: "private" },
    {
      ...fixturePage(),
      items: [{ ...fixturePage().items[0], actorId: "private" }],
    },
    {
      ...fixturePage(),
      items: [{ ...fixturePage().items[0], requestId: "private" }],
    },
    {
      ...fixturePage(),
      items: [{ ...fixturePage().items[0], recordId: "private" }],
    },
    {
      ...fixturePage(),
      items: [{ ...fixturePage().items[0], data: { title: "private" } }],
    },
    {
      ...fixturePage(),
      items: [{ ...fixturePage().items[0], status: "pending" }],
    },
    {
      ...fixturePage(),
      items: [
        { ...fixturePage().items[0], createdAt: "2030-02-31T00:00:00.000Z" },
      ],
    },
    {
      ...fixturePage(),
      items: [fixturePage().items[0], fixturePage().items[0]],
    },
    { ...fixturePage(), nextCursor: "cursor", items: [] },
  ])
    assert.throws(() => activityPage(page, "app"));
  const marker = "PRIVATE_MARKER";
  assert.throws(() =>
    activityPage(
      {
        ...fixturePage(),
        items: [{ ...fixturePage().items[0], action: marker }],
      },
      "app",
      2,
      new Set([marker]),
    ),
  );
});

async function bridge(t, fault) {
  const child = spawn(
    process.env.TINKERLOOM_TEST_DART ?? "dart",
    ["--suppress-analytics", "run", "test/activity_probe_bridge.dart"],
    {
      cwd: fileURLToPath(new URL("../appwrite_backend/", import.meta.url)),
      stdio: ["pipe", "pipe", "pipe"],
    },
  );
  t.after(() => {
    child.stdin.end();
    child.kill("SIGTERM");
  });
  const pending = [],
    calls = [],
    sessions = new Map();
  let readyResolve, readyReject;
  const ready = new Promise((yes, no) => {
    readyResolve = yes;
    readyReject = no;
  });
  let readySeen = false,
    conflictUsed = false;
  createInterface({ input: child.stdout }).on("line", (line) => {
    const data = JSON.parse(line);
    if (!readySeen) {
      readySeen = true;
      readyResolve(data);
      return;
    }
    const next = pending.shift();
    if (next) next.resolve(data);
  });
  child.stderr.on("data", () => {});
  child.on("error", () => readyReject(new Error("offline_bridge_unavailable")));
  child.on("exit", () => {
    if (!readySeen) readyReject(new Error("offline_bridge_unavailable"));
    for (const item of pending.splice(0))
      item.reject(new Error("offline_bridge_closed"));
  });
  await ready;
  const rpc = (actor, input) =>
    new Promise((resolve, reject) => {
      pending.push({ resolve, reject });
      child.stdin.write(JSON.stringify({ actor, input }) + "\n");
    });
  const response = (status, data, headers = {}) =>
    new Response(data === undefined ? null : JSON.stringify(data), {
      status,
      headers,
    });
  const fetchImpl = async (url, options) => {
    const path = new URL(url).pathname.slice(3),
      body = options.body ? JSON.parse(options.body) : null;
    calls.push({ path, method: options.method, body });
    assert.equal(options.headers["X-Appwrite-Key"], undefined);
    assert.equal(options.headers["X-Appwrite-JWT"], undefined);
    assert.notEqual(
      path,
      "/account",
      "Probe cannot create or broadly inspect accounts",
    );
    if (path === "/account/sessions/email") {
      const actor = Object.values(credentials).find(
        (actor) =>
          actor.email === body.email && actor.password === body.password,
      );
      assert(actor);
      const token = "private-session-" + randomBytes(8).toString("hex");
      sessions.set(token, actor.id);
      return response(
        201,
        {},
        { "Set-Cookie": `a_session=${token}; Path=/; HttpOnly` },
      );
    }
    const cookie = options.headers.Cookie?.split("=", 2)[1],
      actor = sessions.get(cookie);
    if (path === "/account/sessions/current") {
      sessions.delete(cookie);
      return response(204, undefined, {
        "Set-Cookie": "a_session=; Max-Age=0; Path=/",
      });
    }
    if (path.startsWith("/tablesdb/"))
      return response(403, { type: "general_access_forbidden", code: 403 });
    assert.equal(path, "/functions/core/executions");
    if (!actor) return response(401, { type: "user_unauthorized", code: 401 });
    const input = JSON.parse(body.body);
    assert.deepEqual(body.headers, { "content-type": "application/json" });
    assert(!Object.hasOwn(input, "proof"));
    assert(!Object.hasOwn(input, "clock"));
    let result;
    if (
      input.op === "spec.listActivity" &&
      input.appId === "preflight-app" &&
      fault === "unavailable"
    )
      result = { status: 400, data: { error: "unknown_operation" } };
    else if (
      input.op === "spec.listActivity" &&
      !conflictUsed &&
      fault === "readConflict"
    ) {
      conflictUsed = true;
      result = { status: 409, data: { error: "transaction_conflict" } };
    } else result = await rpc(actor, input);
    if (fault === "lostWrite" && input.op === "spec.instantiate")
      throw new Error("PRIVATE_UNCONFIRMED_RESPONSE");
    if (
      fault === "metadataLeak" &&
      input.op === "spec.listActivity" &&
      result.status === 200
    )
      result.data.items[0].actorId = "PRIVATE_RAW_AUDIT";
    return response(201, {
      status: "completed",
      deploymentId: fault === "wrongDeployment" ? "old-core" : "activity-core",
      responseStatusCode: result.status,
      responseBody: JSON.stringify(result.data),
    });
  };
  // Account identity remains a normal separate request, with no fake user override in RPCs.
  const withAccount = async (url, options) => {
    if (new URL(url).pathname === "/v1/account" && options.method === "GET") {
      calls.push({ path: "/account", method: "GET" });
      return response(200, {
        $id: sessions.get(options.headers.Cookie?.split("=", 2)[1]),
      });
    }
    return fetchImpl(url, options);
  };
  return { calls, fetchImpl: withAccount };
}

test(
  "positive narrow orchestration uses the real Dart service for roles, scopes, cursor privacy and archive without new accounts",
  { timeout: 120000 },
  async (t) => {
    const f = await bridge(t);
    const report = await runActivitySmoke(config(), {
      actorCredentials: provider,
      fetchImpl: f.fetchImpl,
      sleep: async () => {},
    });
    assert.equal(report.status, "passed", JSON.stringify(report.checks));
    assert.equal(report.budget.syntheticAccountsCreated, 0);
    assert.equal(report.budget.reusedVerifiedSyntheticAccounts, 5);
    assert.equal(report.budget.cleanupSessions, 5);
    assert(report.budget.httpRequests <= 180);
    t.diagnostic(
      JSON.stringify({ budget: report.budget, summary: report.summary }),
    );
    assert.equal(
      report.checks.find(
        (check) => check.name === "all_four_roles_metadata_paging",
      ).authorizedRoles,
      4,
    );
    assert.equal(
      report.checks.find(
        (check) =>
          check.name === "cross_scope_cursor_and_private_table_denials",
      ).directAuditRowDenials,
      5,
    );
    for (const value of Object.values(credentials).flatMap((actor) =>
      Object.values(actor),
    ))
      assert(!JSON.stringify(report).includes(value));
    assert(!JSON.stringify(report).includes("PRIVATE_ACTIVITY_"));
    assert(
      !f.calls.some(
        (call) => call.path === "/account" && call.method === "POST",
      ),
    );
  },
);
test(
  "unknown activity/new-core metadata failure blocks all setup mutations while still signing out five verified sessions",
  { timeout: 120000 },
  async (t) => {
    for (const fault of ["unavailable", "wrongDeployment", "metadataLeak"]) {
      const f = await bridge(t, fault);
      const report = await runActivitySmoke(config(), {
        actorCredentials: provider,
        fetchImpl: f.fetchImpl,
      });
      assert.notEqual(report.status, "passed");
      assert.equal(report.budget.cleanupSessions, 5);
      assert(
        !f.calls
          .filter((call) => call.path.includes("/functions/"))
          .some((call) => JSON.parse(call.body.body).op === "createWorkspace"),
      );
      assert(!JSON.stringify(report).includes("PRIVATE_RAW_AUDIT"));
    }
  },
);
test(
  "one narrow read conflict retries safely but an already-committed lost write stops with no replacement operation",
  { timeout: 120000 },
  async (t) => {
    const healthy = await bridge(t, "readConflict");
    const report = await runActivitySmoke(config(), {
      actorCredentials: provider,
      fetchImpl: healthy.fetchImpl,
      sleep: async () => {},
    });
    assert.equal(report.status, "passed");
    assert.equal(report.budget.readConflicts, 1);
    const lost = await bridge(t, "lostWrite");
    const pending = await runActivitySmoke(config(), {
      actorCredentials: provider,
      fetchImpl: lost.fetchImpl,
    });
    assert.equal(pending.status, "observation_pending");
    assert.equal(pending.budget.cleanupSessions, 5);
    const writes = lost.calls
      .filter((call) => call.path.includes("/functions/"))
      .map((call) => JSON.parse(call.body.body))
      .filter((input) => input.op === "spec.instantiate");
    assert.equal(writes.length, 1);
    assert(!JSON.stringify(pending).includes("PRIVATE_UNCONFIRMED_RESPONSE"));
  },
);
test("duplicate pool identities cannot authenticate or fall back to creating an account", async () => {
  let requests = 0;
  const report = await runActivitySmoke(config(), {
    actorCredentials: async () => credentials.owner,
    fetchImpl: async () => {
      requests++;
      assert.fail();
    },
  });
  assert.equal(requests, 0);
  assert.equal(report.budget.syntheticAccountsCreated, 0);
  assert.notEqual(report.status, "passed");
});

test(
  "exhausting the bounded HTTP budget preserves all five session cleanup requests",
  { timeout: 120000 },
  async (t) => {
    const f = await bridge(t);
    const report = await runActivitySmoke(
      { ...config(), maxHttp: 80 },
      {
        actorCredentials: provider,
        fetchImpl: f.fetchImpl,
      },
    );
    assert.equal(report.status, "blocked");
    assert.equal(report.summary.observation_pending, 0);
    assert.equal(report.budget.cleanupSessions, 5);
    assert(report.budget.httpRequests <= 80);
    assert(
      report.checks.some((check) => check.code === "http_budget_exhausted"),
    );
  },
);
