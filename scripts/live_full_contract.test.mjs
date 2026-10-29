import assert from "node:assert/strict";
import test from "node:test";
import {
  FullProbeError,
  safeFullObservation,
  safeFinalReport,
  isFullPrivateRowDenied,
  validFullApp,
  validReview,
  validRuntimePage,
  validRuntimeRecord,
  sha,
} from "./live_full_contract.mjs";
import {
  AppwriteUserClient,
  HttpBudget,
  authRequest,
  authCooldown,
  functionObservation,
} from "./live_full_transport.mjs";
import { readFullConfiguration, runFullSmoke } from "./live_full_smoke.mjs";
const configuration = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  functionId: "core",
  databaseId: "database",
  coreDeploymentId: "deployment",
  workerDeploymentId: "worker_deployment",
  sourceCommit: "b542d9f",
  origin: "http://localhost:8426",
  timeoutMs: 1000,
  maxHttp: 600,
  twentyDistinct: false,
};
const spec = {
  formatVersion: 1,
  name: "Offline declaration",
  theme: "teal",
  icon: "book",
  requires: [],
  collections: [],
  views: [],
  actions: [],
  policyPresetRequest: "personalTracker.v1",
  automationRequests: [],
};
const app = {
  id: "app",
  workspaceId: "workspace",
  name: "QA",
  engine: "appspec.v1",
  role: "viewer",
  archived: false,
  capabilities: {
    editDefinition: false,
    share: false,
    writeRecords: false,
    archive: false,
    revokeAccess: false,
  },
  allowedActions: [],
  generation: null,
  controlRevision: 1,
  version: { id: "version", number: 1, hash: "a".repeat(64), spec },
  draft: null,
};
const response = (data, status = 200, headers = {}) =>
  new Response(JSON.stringify(data), { status, headers });
test("module import is inert and configuration requires explicit public deployment/source provenance", () => {
  const args = [
    "--endpoint",
    configuration.endpoint,
    "--project-id",
    "project",
    "--function-id",
    "core",
    "--database-id",
    "database",
    "--source-commit",
    "b542d9f",
    "--core-deployment-id",
    "deployment",
    "--worker-deployment-id",
    "worker_deployment",
  ];
  const parsed = readFullConfiguration(
    args,
    {},
    "/definitely-missing-public-file",
  );
  assert.equal(parsed.twentyDistinct, false);
  assert.equal(parsed.maxHttp, 600);
  assert.equal(
    readFullConfiguration(
      [...args, "--twenty-distinct-capacity-actors"],
      {},
      "/missing",
    ).twentyDistinct,
    true,
  );
  assert.throws(() => readFullConfiguration(args.slice(0, -2), {}, "/missing"));
  assert.throws(() =>
    readFullConfiguration([...args, "--max-http", "601"], {}, "/missing"),
  );
  assert.throws(() =>
    readFullConfiguration(
      [...args, "--endpoint", "https://user:password@example.test/v1"],
      {},
      "/missing",
    ),
  );
  assert.throws(() =>
    readFullConfiguration(
      [...args, "--origin", "https://example.test/path"],
      {},
      "/missing",
    ),
  );
});
test("cookie-only injected HTTP transport sends no admin header and retains secrets only in memory", async () => {
  const requests = [],
    secrets = new Set(),
    budget = new HttpBudget(10, 0);
  const client = new AppwriteUserClient(configuration, {
    budget,
    privateValues: secrets,
    fetchImpl: async (url, request) => {
      requests.push({ url, ...request });
      return response({ ok: true }, 200, {
        "set-cookie":
          "a_session_project=private-cookie-value-123456789; Path=/; HttpOnly",
      });
    },
  });
  await client.request("POST", "/account/sessions/email", {
    email: "qa@example.test",
    password: "private-password",
  });
  await client.request("GET", "/account");
  assert.equal(requests.length, 2);
  assert.equal(
    requests[1].headers.Cookie,
    "a_session_project=private-cookie-value-123456789",
  );
  assert.equal(requests[1].headers["X-Appwrite-Key"], undefined);
  assert.equal(requests[1].headers["X-Appwrite-JWT"], undefined);
  assert.equal(requests[1].redirect, "error");
  assert.equal(secrets.has("private-cookie-value-123456789"), true);
  assert.equal(budget.used, 2);
  assert.equal(budget.inFlight, 0);
});
test("HTTP budget preserves cleanup allowance and can never exceed600 calls", async () => {
  assert.throws(() => new HttpBudget(601));
  const budget = new HttpBudget(3, 1),
    client = new AppwriteUserClient(configuration, {
      budget,
      fetchImpl: async () => response({}),
    });
  await client.request("GET", "/one");
  await client.request("GET", "/two");
  await assert.rejects(
    client.request("GET", "/blocked"),
    (error) => error.code === "http_budget_exhausted",
  );
  await client.request("DELETE", "/account/sessions/current", undefined, {
    cleanup: true,
  });
  await assert.rejects(
    client.request("DELETE", "/account/sessions/current", undefined, {
      cleanup: true,
    }),
  );
  assert.equal(budget.used, 3);
  assert.equal(budget.inFlight, 0);
});
test("Function transport exposes only bounded execution data and records exact deployment metadata", async () => {
  let request;
  const client = new AppwriteUserClient(configuration, {
    budget: new HttpBudget(10, 0),
    fetchImpl: async (_url, options) => {
      request = JSON.parse(options.body);
      return response(
        {
          status: "completed",
          deploymentId: "deployment",
          responseStatusCode: 403,
          responseBody: JSON.stringify({ error: "forbidden" }),
          logs: "private-provider-secret",
        },
        201,
      );
    },
  });
  const result = await client.execute({ op: "spec.getApp", appId: "app" });
  assert.deepEqual(JSON.parse(request.body), {
    op: "spec.getApp",
    appId: "app",
  });
  assert.equal(result.status, 403);
  assert.equal(result.deploymentMatched, true);
  assert.equal(result.logs, undefined);
  assert.equal(client.deploymentMatches, 1);
  assert.deepEqual(functionObservation(result), {
    httpStatus: 201,
    functionStatus: 403,
    executionStatus: "completed",
    code: "forbidden",
  });
});
test("transport failures and incomplete executions cannot become successful business denials", async () => {
  const broken = new AppwriteUserClient(configuration, {
    budget: new HttpBudget(10, 0),
    fetchImpl: async () => {
      throw new Error("raw-private-network-error");
    },
  });
  await assert.rejects(
    broken.execute({ op: "spec.getApp" }),
    (error) =>
      error instanceof FullProbeError &&
      error.code === "request_transport_failure" &&
      !error.message.includes("private"),
  );
  const outer = new AppwriteUserClient(configuration, {
    budget: new HttpBudget(10, 0),
    fetchImpl: async () => response({ type: "function_not_found" }, 404),
  });
  const result = await outer.execute({ op: "spec.getApp" });
  assert.equal(result.status, undefined);
  assert.equal(result.outer.status, 404);
  assert.equal(functionObservation(result).code, "function_not_found");
  const wrong = new AppwriteUserClient(configuration, {
    budget: new HttpBudget(10, 0),
    fetchImpl: async () =>
      response(
        {
          status: "processing",
          deploymentId: "other",
          responseStatusCode: 200,
          responseBody: "{}",
        },
        201,
      ),
  });
  const incomplete = await wrong.execute({ op: "spec.getApp" });
  assert.equal(incomplete.executionStatus, "processing");
  assert.equal(incomplete.deploymentMatched, false);
});
test("6MiB semantic requests and8MiB Function bodies are bounded before unsafe logging", async () => {
  let calls = 0;
  const client = new AppwriteUserClient(configuration, {
    budget: new HttpBudget(10, 0),
    fetchImpl: async () => {
      calls++;
      return response(
        {
          status: "completed",
          deploymentId: "deployment",
          responseStatusCode: 200,
          responseBody: "x".repeat(8 * 1024 * 1024 + 1),
        },
        201,
      );
    },
  });
  await assert.rejects(
    client.execute({
      op: "spec.saveDraft",
      input: "x".repeat(6 * 1024 * 1024),
    }),
    (error) => error.code === "request_too_large",
  );
  assert.equal(calls, 0);
  await assert.rejects(
    client.execute({ op: "spec.getApp" }),
    (error) => error.code === "execution_response_invalid",
  );
  assert.equal(calls, 1);
});
test("auth429 never retries by default and explicit actor-pool mode honors known cooldown without changing credentials", async () => {
  let calls = 0;
  const bodies = [],
    delays = [];
  const client = {
    request: async (_method, _path, body) => {
      calls++;
      bodies.push(body);
      return calls === 1 ? { status: 429, retryAfter: "1" } : { status: 201 };
    },
  };
  const body = { email: "qa@example.test", password: "secret" };
  const first = await authRequest(client, "POST", "/account", body);
  assert.equal(first.status, 429);
  assert.equal(calls, 1);
  calls = 0;
  const second = await authRequest(client, "POST", "/account", body, {
    allowCooldown: true,
    sleep: async (ms) => delays.push(ms),
  });
  assert.equal(second.status, 201);
  assert.equal(calls, 2);
  assert.deepEqual(delays, [1250]);
  assert.equal(bodies[1], body);
  assert.equal(bodies[2], body);
  assert.throws(() => authCooldown({ status: 429 }));
  await assert.rejects(
    authRequest(
      { request: async () => ({ status: 429, retryAfter: "999" }) },
      "POST",
      "/account",
      body,
      {
        allowCooldown: true,
        sleep: async () => assert.fail("must not retry before cooldown"),
      },
    ),
    (error) => error.code === "auth_rate_limit_wait_budget_exceeded",
  );
});
test("known existing private row404 concealment is accepted but missing configuration and leaked row fields fail", () => {
  assert.equal(
    isFullPrivateRowDenied(
      {
        status: 404,
        data: { type: "row_not_found", message: "Missing", code: 404 },
      },
      { knownExistingRow: true },
    ),
    true,
  );
  assert.equal(
    isFullPrivateRowDenied(
      { status: 404, data: { type: "row_not_found" } },
      { knownExistingRow: false },
    ),
    false,
  );
  for (const type of [
    "database_not_found",
    "table_not_found",
    "project_not_found",
    "function_not_found",
  ])
    for (const status of [401, 403, 404])
      assert.equal(
        isFullPrivateRowDenied(
          { status, data: { type } },
          { knownExistingRow: true },
        ),
        false,
      );
  for (const fields of [
    { specJson: "private" },
    { recipientIdsJson: "other-actor" },
    { actorId: "actor" },
    { rows: [] },
    { data: { private: "row" } },
  ])
    assert.equal(
      isFullPrivateRowDenied(
        { status: 403, data: { type: "general_access_forbidden", ...fields } },
        { knownExistingRow: true },
      ),
      false,
    );
  assert.equal(
    isFullPrivateRowDenied({ status: 200, data: { rows: [] } }, {}),
    false,
  );
});
test("full DTO checks reject build aliases, leaked drafts/jobs and mismatched receipt/scope fields", () => {
  assert.equal(validFullApp(app), true);
  assert.equal(
    validFullApp({
      ...app,
      capabilities: { ...app.capabilities, build: false },
    }),
    false,
  );
  assert.equal(
    validFullApp({
      ...app,
      draft: {
        revision: 1,
        baseVersionId: "version",
        candidateHash: "b".repeat(64),
        publishedVersionId: null,
        spec,
      },
    }),
    false,
  );
  assert.equal(
    validFullApp({ ...app, generation: { requestText: "private prompt" } }),
    false,
  );
  const record = {
    id: "record",
    collectionId: "items",
    data: { title: "QA", zero: 0 },
    revision: 1,
    writtenUnderVersionId: "version",
    capacity: null,
    allocated: null,
    claimed: false,
    allowedActions: [],
  };
  assert.equal(validRuntimeRecord(record, "items"), true);
  assert.equal(validRuntimeRecord({ ...record, allocated: 0 }, "items"), false);
  assert.equal(
    validRuntimeRecord({ ...record, claimed: true }, "items"),
    false,
  );
  assert.equal(
    validRuntimeRecord({ ...record, capacity: 1, allocated: 2 }, "items"),
    false,
  );
  assert.equal(
    validRuntimeRecord({ ...record, ownerId: "private" }, "items"),
    false,
  );
  assert.equal(
    validRuntimePage(
      { records: [record], total: 1, nextCursor: null, versionId: "version" },
      "different",
      "items",
    ),
    false,
  );
  const candidateHash = "a".repeat(64),
    review = {
      candidateHash,
      expectedRevision: 1,
      baseVersionId: null,
      currentVersionId: null,
      reviewHash: sha({
        candidateHash,
        enabledRuleIds: [],
        activateExistingRecordIds: [],
      }),
      changes: ["Create"],
      compatibilityErrors: [],
      enabledRuleIds: [],
      activateExistingRecordIds: [],
    };
  assert.equal(validReview(review), true);
  assert.equal(
    validReview({ ...review, enabledRuleIds: ["unreviewed"] }),
    false,
  );
});
test("report allowlists reject raw bodies/headers/private codes and secret scan preserves failures and blocked checks", () => {
  const secret = "private-secret-value-123456789";
  const report = {
    schemaVersion: 1,
    runId: "qa-full-test-12345678",
    startedAt: new Date().toISOString(),
    completedAt: new Date().toISOString(),
    status: "failed",
    target: { ...configuration, sourceCommit: "b542d9f" },
    accounts: [],
    resources: { workspaceId: "workspace" },
    budget: { maxHttpRequests: 600 },
    capacityTrial: {
      distinctAuthenticatedActors: 3,
      submittedAttempts: 20,
      uniqueOperationIds: 20,
    },
    rawBody: secret,
    headers: { Cookie: secret },
    checks: [
      {
        name: "authenticate_owner",
        status: "failed",
        assertions: 2,
        code: "assertion_failed",
        backendCode: secret,
        httpStatus: 403,
        rawResponse: secret,
      },
      {
        name: "seed_115_typed_records_and_exact_create_receipt",
        status: "blocked",
        assertions: 0,
        code: "prerequisite_failed",
      },
    ],
  };
  const sanitized = safeFinalReport(report, new Set([secret]));
  const text = JSON.stringify(sanitized);
  assert.equal(text.includes(secret), false);
  assert.equal(sanitized.checks.length, 2);
  assert.equal(sanitized.checks[0].backendCode, "unrecognized_error");
  assert.equal(sanitized.summary.failed, 1);
  assert.equal(sanitized.summary.blocked, 1);
  assert.equal(
    safeFullObservation({ code: secret, request: { password: secret } })
      .backendCode,
    "unrecognized_error",
  );
  const cookie = "a".repeat(40);
  const scanned = safeFinalReport(
    { ...report, target: { ...report.target, sourceCommit: cookie } },
    new Set([cookie]),
  );
  assert.equal(JSON.stringify(scanned).includes(cookie), false);
  assert.equal(scanned.securityFailure, "report_secret_scan_failed");
  assert.equal(
    scanned.checks.some((v) => v.status === "blocked"),
    true,
  );
  assert.equal(scanned.status, "failed");
});

test("whole probe retains all failed auth checks and blocked dependencies without retrying or exposing injected private messages", async () => {
  let calls = 0;
  const leaked = "private-error-that-must-not-be-in-report";
  const report = await runFullSmoke(configuration, {
    fetchImpl: async (url, request) => {
      calls++;
      assert.equal(new URL(url).pathname, "/v1/account");
      assert.equal(request.method, "POST");
      return response(
        { type: "general_rate_limit_exceeded", message: leaked },
        429,
      );
    },
    sleep: async () =>
      assert.fail("default probe never retries auth throttles"),
  });
  assert.equal(calls, 5);
  assert.equal(report.accounts.length, 5);
  assert.equal(report.budget.httpRequests, 5);
  assert.equal(report.status, "failed");
  assert.equal(report.summary.failed, 5);
  assert.ok(report.summary.blocked > 30);
  assert.equal(report.capacityTrial.submittedAttempts, 0);
  assert.equal(
    report.checks.filter(
      (check) =>
        check.name.startsWith("authenticate_") && check.status === "failed",
    ).length,
    5,
  );
  assert.equal(JSON.stringify(report).includes(leaked), false);
  assert.equal(
    report.checks.find(
      (check) =>
        check.name === "twenty_concurrent_unique_final_capacity_attempts",
    ).status,
    "blocked",
  );
});
