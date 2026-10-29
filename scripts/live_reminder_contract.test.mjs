import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import {
  workerReceipt,
  receiptHash,
  verifyReminderConfiguration,
  reminderStates,
  reminderRuns,
  reminderInbox,
  safeReminderReport,
} from "./live_reminder_contract.mjs";
import {
  runReminderSmoke,
  readReminderConfiguration,
} from "./live_reminder_smoke.mjs";
import { sha } from "./live_full_contract.mjs";
const wire = JSON.parse(
  readFileSync(
    new URL("./fixtures/reminder_service_wire.json", import.meta.url),
    "utf8",
  ),
);
const base = {
  endpoint: "https://example.test/v1",
  origin: "http://localhost:8426",
  projectId: "project",
  functionId: "core",
  coreDeploymentId: "core-deploy",
  workerFunctionId: "worker",
  workerDeploymentId: "worker-deploy",
  sourceCommit: "fc71fe4",
  maxHttp: 300,
  timeoutMs: 1000,
  waitSeconds: 0,
  enableLiveReminders: true,
};
function receipt(overrides = {}) {
  return {
    schemaVersion: 1,
    capturedAt: new Date().toISOString(),
    projectId: base.projectId,
    coreFunctionId: base.functionId,
    coreDeploymentId: base.coreDeploymentId,
    workerFunctionId: base.workerFunctionId,
    workerDeploymentId: base.workerDeploymentId,
    execute: [],
    domains: [],
    intervalMinutes: 60,
    configuredWorkerIdentityMatches: true,
    remindersEnabled: { core: true, worker: true },
    executionScopesVerified: { core: true, worker: true },
    oneShot: { accepted: true, executionId: "actual-work-execution" },
    ...overrides,
  };
}
function config() {
  const bytes = Buffer.from(JSON.stringify(receipt()));
  return {
    ...base,
    workerGate: workerReceipt(bytes, receiptHash(bytes), base),
  };
}
const response = (body, status = 200, headers = {}) =>
  new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers,
  });
function fakeCloud({
  effects = ["notifyOwner", "notifyAssignee"],
  unknownWorkspace = false,
  conflictCapabilities = 0,
  auth429 = false,
  existingAccounts = [],
  timedWorker = false,
  neverDeliver = false,
} = {}) {
  const accounts = existingAccounts.map((value) => ({ ...value })),
    cookies = new Map(),
    apps = new Map(),
    records = new Map(),
    invitations = new Map(),
    calls = [];
  let sequence = 0,
    conflicts = conflictCapabilities;
  const runRows = new Map(),
    notices = new Map(),
    commandReceipts = new Map();
  const updateWorker = () => {
    for (const app of apps.values())
      for (const record of records.values()) {
        if (record.appId !== app.id) continue;
        const rule = app.version.spec.automationRequests[0],
          date = record.data[rule.trigger.fieldId];
        let run = runRows.get(record.id);
        if (!run && date) {
          const dueAt = new Date(
            Date.parse(date) - rule.trigger.offsetSeconds * 1000,
          ).toISOString();
          run = {
            id: "run-" + record.id,
            ruleId: rule.id,
            recordId: record.id,
            status: "pending",
            dueAt,
            nextAttemptAt: dueAt,
            attempts: 0,
            errorCategory: null,
            recipientCount: 0,
          };
          runRows.set(record.id, run);
        }
        if (
          !run ||
          run.status !== "pending" ||
          Date.now() < Date.parse(run.dueAt) ||
          neverDeliver
        )
          continue;
        const suppress =
          !date || (rule.condition && record.data.status !== "Open");
        run.status = suppress ? "suppressed" : "succeeded";
        run.attempts = 1;
        const recipient =
          rule.effect.type === "notifyOwner"
            ? accounts[0]?.id
            : app.memberRevoked
              ? null
              : record.assignee;
        run.recipientCount = !suppress && recipient ? 1 : 0;
        if (run.recipientCount)
          notices.set(run.id, {
            id: "note-" + record.id,
            appId: app.id,
            runId: run.id,
            recordId: record.id,
            collectionId: rule.trigger.collectionId,
            title: "Synthetic notice",
            body: "Synthetic reminder body",
            createdAt: new Date().toISOString(),
            isRead: false,
            recipient,
          });
      }
  };
  const execution = (body, status = 200) =>
    response(
      {
        status: "completed",
        deploymentId: base.coreDeploymentId,
        responseStatusCode: status,
        responseBody: JSON.stringify(body),
      },
      201,
    );
  const fetchImpl = async (url, options) => {
    const path = new URL(url).pathname.replace(/^\/v1/, "");
    const body = options.body ? JSON.parse(options.body) : null;
    calls.push({
      path,
      method: options.method,
      body,
      headers: options.headers,
    });
    assert.equal(options.headers["X-Appwrite-Key"], undefined);
    assert.equal(options.headers["X-Appwrite-JWT"], undefined);
    if (path === "/account" && options.method === "POST") {
      if (auth429)
        return response({ type: "general_rate_limit_exceeded" }, 429, {
          "retry-after": "1",
        });
      accounts.push({
        id: body.userId,
        email: body.email,
        password: body.password,
      });
      return response({ $id: body.userId }, 201);
    }
    if (path === "/account/sessions/email") {
      const actor = accounts.find(
        (actor) =>
          actor.email === body.email && actor.password === body.password,
      );
      assert(actor);
      const cookie = `private-session-${accounts.indexOf(actor)}`;
      cookies.set(cookie, actor);
      return response({ $id: "session" }, 201, {
        "set-cookie": `a_session_project=${cookie}; Path=/; HttpOnly`,
      });
    }
    const actor = cookies.get(options.headers.Cookie?.split("=")[1]);
    if (path === "/account" && options.method === "GET")
      return response({ $id: actor?.id });
    if (path === "/account/sessions/current" && options.method === "DELETE")
      return response(null, 204);
    assert.equal(path, "/functions/core/executions");
    assert.equal(body.headers["content-type"], "application/json");
    assert.deepEqual(Object.keys(body.headers), ["content-type"]);
    const request = JSON.parse(body.body);
    assert.equal(Object.hasOwn(request, "proof"), false);
    assert.equal(Object.hasOwn(request, "clock"), false);
    const app = apps.get(request.appId);
    switch (request.op) {
      case "spec.capabilities":
        if (conflicts-- > 0)
          return execution({ error: "transaction_conflict" }, 409);
        return execution({ apiVersion: 1, effects });
      case "createWorkspace":
        if (unknownWorkspace) throw new Error("PRIVATE_PASSWORD_OR_PROOF");
        return execution({ workspace: { id: request.id } });
      case "spec.instantiate": {
        const spec = structuredClone(wire.templates[request.templateKey]);
        const app = {
          id: request.id,
          workspaceId: request.workspaceId,
          name: spec.name,
          engine: "appspec.v1",
          role: "owner",
          archived: false,
          capabilities: {
            editDefinition: true,
            share: true,
            writeRecords: true,
            archive: true,
            revokeAccess: true,
          },
          allowedActions: spec.actions.map((action) => action.id),
          generation: null,
          controlRevision: 1,
          version: { id: "v-" + request.id, number: 1, hash: sha(spec), spec },
          draft: null,
        };
        apps.set(app.id, app);
        return execution({ app });
      }
      case "spec.saveDraft":
        app.draft = {
          revision: request.expectedRevision + 1,
          baseVersionId: request.expectedVersionId,
          candidateHash: sha(request.spec),
          spec: request.spec,
          publishedVersionId: null,
        };
        return execution({ app });
      case "spec.review": {
        const review = {
          candidateHash: app.draft.candidateHash,
          expectedRevision: app.draft.revision,
          baseVersionId: app.version.id,
          currentVersionId: app.version.id,
          changes: [],
          compatibilityErrors: [],
          enabledRuleIds: request.enabledRuleIds,
          activateExistingRecordIds: request.activateExistingRecordIds,
        };
        review.reviewHash = sha({
          candidateHash: review.candidateHash,
          enabledRuleIds: [...review.enabledRuleIds].sort(),
          activateExistingRecordIds: [
            ...review.activateExistingRecordIds,
          ].sort(),
        });
        return execution({ review });
      }
      case "spec.publish":
        app.version = {
          id: "p-" + app.id,
          number: 2,
          hash: app.draft.candidateHash,
          spec: app.draft.spec,
        };
        app.draft.publishedVersionId = app.version.id;
        return execution({ app });
      case "spec.execute": {
        if (commandReceipts.has(request.operationId))
          return execution(commandReceipts.get(request.operationId));
        let record;
        if (!request.targetRecordId) {
          record = {
            id: "record-" + ++sequence,
            revision: 1,
            appId: request.appId,
            data: request.input.data,
          };
          records.set(record.id, record);
        } else {
          record = records.get(request.targetRecordId);
          assert.equal(request.expectedRecordRevision, record.revision);
          record.revision++;
          if (request.actionId === "moveTask")
            record.data.status = request.input.value;
          if (request.actionId === "assignChore")
            record.assignee = request.input.value;
          if (request.input.data)
            for (const [key, value] of Object.entries(request.input.data)) {
              if (value === null) delete record.data[key];
              else record.data[key] = value;
            }
        }
        const outcome = {
          outcome: {
            recordId: record.id,
            revision: record.revision,
            message: "Saved",
          },
        };
        commandReceipts.set(request.operationId, outcome);
        return execution(outcome);
      }
      case "spec.reminderState": {
        const record = records.get(request.recordId),
          rule = app.version.spec.automationRequests[0],
          date = record.data[rule.trigger.fieldId];
        return execution({
          versionId: request.versionId,
          states: [
            {
              ruleId: rule.id,
              state: date ? "pending" : "unset",
              scheduledAt: date
                ? new Date(
                    Date.parse(date) - rule.trigger.offsetSeconds * 1000,
                  ).toISOString()
                : null,
              eligible: !!date,
              recipientCount: 0,
            },
          ],
        });
      }
      case "createInvitation":
        invitations.set(request.token, request);
        return execution({});
      case "inspectInvitation":
        return execution({
          invitation: {
            appId: invitations.get(request.token).appId,
            role: "member",
          },
        });
      case "acceptInvitation":
        return execution({});
      case "setGrant":
        app.memberRevoked = true;
        return execution({});
      case "spec.readNotification": {
        const item = [...notices.values()].find(
          (item) => item.id === request.notificationId,
        );
        if (!item || item.recipient !== actor.id)
          return execution({ error: "not_found" }, 404);
        item.isRead = true;
        return execution({ notificationId: item.id, isRead: true });
      }
      case "spec.inbox": {
        if (!timedWorker) return execution({ items: [], nextCursor: null });
        updateWorker();
        return execution({
          items: [...notices.values()]
            .filter(
              (item) =>
                item.recipient === actor.id &&
                !apps.get(item.appId).memberRevoked,
            )
            .map(({ recipient, ...item }) => item),
          nextCursor: null,
        });
      }
      case "spec.runs":
        if (actor === accounts[1])
          return execution({ error: "forbidden" }, 403);
        assert(timedWorker);
        updateWorker();
        return execution({
          runs: [...runRows.values()].filter(
            (run) => records.get(run.recordId).appId === request.appId,
          ),
          nextCursor: null,
        });
      default:
        assert.fail("Unexpected operation " + request.op);
    }
  };
  return {
    fetchImpl,
    calls,
    accounts,
    commands: () =>
      calls
        .filter((call) => call.path.includes("/functions/"))
        .map((call) => JSON.parse(call.body.body)),
  };
}

test("module import is inert and programmatic/CLI entry refuses missing explicit enable or genuine receipt gate", async () => {
  let calls = 0;
  await assert.rejects(
    runReminderSmoke(
      { ...base, enableLiveReminders: false },
      {
        fetchImpl: async () => {
          calls++;
          throw Error();
        },
      },
    ),
    (error) => error.code === "explicit_enable_required",
  );
  await assert.rejects(
    runReminderSmoke(
      {
        ...base,
        workerGate: {
          attestation:
            "operator_console_metadata_not_public_server_attestation",
          sha256: "a".repeat(64),
        },
      },
      {
        fetchImpl: async () => {
          calls++;
          throw Error();
        },
      },
    ),
    (error) => error.code === "private_worker_gate_required",
  );
  assert.throws(
    () => readReminderConfiguration([], {}, "/missing"),
    (error) => error.code === "explicit_enable_required",
  );
  assert.equal(calls, 0);
});
test("worker receipt binds project/deployments, private execute/domain, enabled core+worker, scopes and accepted one-shot", () => {
  for (const change of [
    { projectId: "other" },
    { workerDeploymentId: "stale" },
    { execute: ["any"] },
    { domains: ["public.test"] },
    { intervalMinutes: 1 },
    { configuredWorkerIdentityMatches: false },
    { remindersEnabled: { core: true, worker: false } },
    { executionScopesVerified: { core: false, worker: true } },
    { oneShot: { accepted: false, executionId: "pending" } },
    { capturedAt: "2000-01-01T00:00:00.000Z" },
    { apiKey: "SECRET" },
  ]) {
    const bytes = Buffer.from(JSON.stringify(receipt(change)));
    assert.throws(() => workerReceipt(bytes, receiptHash(bytes), base));
  }
  const bytes = Buffer.from(JSON.stringify(receipt()));
  assert.throws(() => workerReceipt(bytes, "a".repeat(64), base));
  assert.doesNotThrow(() => verifyReminderConfiguration(config()));
  const gated = config();
  for (const key of [
    "projectId",
    "functionId",
    "coreDeploymentId",
    "workerFunctionId",
    "workerDeploymentId",
  ])
    assert.throws(() =>
      verifyReminderConfiguration({ ...gated, [key]: "changed-target" }),
    );
});
test("hard HTTP/account/wait bounds reject wider runs before any request", () => {
  for (const change of [
    { maxHttp: 301 },
    { waitSeconds: 301 },
    { waitSeconds: 120 },
    { workerFunctionId: null },
  ])
    assert.throws(() =>
      verifyReminderConfiguration({ ...config(), ...change }),
    );
});
test("actual service/worker DTO fixture demonstrates states, explicit enrollment, duplicate drains and current-recipient isolation", () => {
  for (const [name, value] of Object.entries(wire.states))
    assert.equal(
      reminderStates(value, value.versionId, "taskReminder").state,
      name,
    );
  assert(
    reminderRuns(wire.ownerRuns).some((run) => run.status === "suppressed"),
  );
  assert.equal(reminderInbox(wire.ownerInbox).length, 1);
  assert.equal(reminderInbox(wire.memberInbox).length, 1);
  assert.equal(reminderInbox(wire.ownerCannotSeeMemberInbox).length, 0);
  assert.equal(reminderInbox(wire.afterRevocationInbox).length, 0);
  assert.equal(wire.crossRecipientReadDenied.error, "not_found");
  assert.equal(wire.revokedRecipientRun.recipientCount, 0);
  assert.equal(wire.readAcknowledgement.isRead, true);
});
test("DTOs reject unknown fields, rollover UTC times, wrong identity and private batch payloads", () => {
  const pending = structuredClone(wire.states.pending);
  pending.states[0].scheduledAt = "2030-02-31T10:00:00.000Z";
  assert.throws(() =>
    reminderStates(pending, pending.versionId, "taskReminder"),
  );
  assert.throws(() =>
    reminderRuns({ ...wire.ownerRuns, recipientIdsJson: "[]" }),
  );
  assert.throws(() =>
    reminderInbox({
      ...wire.memberInbox,
      headers: { Authorization: "secret" },
    }),
  );
  assert.throws(() =>
    reminderStates(wire.states.pending, "wrong", "taskReminder"),
  );
});
test("disabled operational effects create no app/effect work and sign out the sole temporary session", async () => {
  const fake = fakeCloud({ effects: [] });
  const report = await runReminderSmoke(config(), {
    fetchImpl: fake.fetchImpl,
  });
  assert.equal(report.status, "blocked");
  assert.equal(fake.accounts.length, 1);
  assert.equal(report.budget.cleanupSessions, 1);
  assert.deepEqual(
    fake.commands().map((command) => command.op),
    ["spec.capabilities"],
  );
  assert(!JSON.stringify(report).includes(fake.accounts[0].email));
});
test("a narrow read conflict retry never replays business writes, and unknown write stops after one attempt with both signouts", async () => {
  const fake = fakeCloud({ conflictCapabilities: 1, unknownWorkspace: true });
  const waits = [];
  const report = await runReminderSmoke(config(), {
    fetchImpl: fake.fetchImpl,
    sleep: async (ms) => {
      waits.push(ms);
    },
  });
  assert.equal(report.status, "observation_pending");
  assert.equal(
    fake.commands().filter((command) => command.op === "spec.capabilities")
      .length,
    2,
  );
  assert.equal(
    fake.commands().filter((command) => command.op === "createWorkspace")
      .length,
    1,
  );
  assert.equal(
    fake.commands().filter((command) => command.op === "spec.instantiate")
      .length,
    0,
  );
  assert.equal(report.budget.cleanupSessions, 2);
  assert.deepEqual(waits, [250]);
  assert(!JSON.stringify(report).includes("PRIVATE_PASSWORD_OR_PROOF"));
});
test("auth429 never repeats credentials or creates another account", async () => {
  const fake = fakeCloud({ auth429: true });
  const report = await runReminderSmoke(config(), {
    fetchImpl: fake.fetchImpl,
    sleep: async () => assert.fail("no auth retry"),
  });
  assert.equal(report.status, "blocked");
  assert.equal(fake.calls.length, 1);
  assert.equal(report.budget.syntheticAccounts, 0);
});
test("no-wait orchestration performs explicit approvals and member consent, invalidates date/condition/grant and reports pending without worker calls", async () => {
  const fake = fakeCloud();
  const report = await runReminderSmoke(config(), {
    fetchImpl: fake.fetchImpl,
    sleep: async () => assert.fail("no timed wait without opt-in"),
  });
  assert.equal(report.status, "observation_pending");
  assert.equal(fake.accounts.length, 2);
  assert.equal(report.budget.cleanupSessions, 2);
  assert(report.budget.httpRequests <= 100);
  const commands = fake.commands();
  assert.equal(
    commands.filter((command) => command.op === "spec.publish").length,
    3,
  );
  assert.equal(
    commands.filter((command) => command.op === "acceptInvitation").length,
    2,
  );
  assert(
    commands.some(
      (command) => command.op === "setGrant" && command.role === null,
    ),
  );
  assert(
    commands.some(
      (command) =>
        command.op === "spec.execute" &&
        command.input.data?.reminderAt === null,
    ),
  );
  assert(
    commands.some(
      (command) =>
        command.op === "spec.execute" && command.input.value === "Done",
    ),
  );
  assert(commands.every((command) => !String(command.op).includes("worker")));
  assert(
    report.checks.some(
      (check) =>
        check.name === "live_delivery_observation" &&
        check.status === "observation_pending",
    ),
  );
  for (const actor of fake.accounts)
    for (const secret of Object.values(actor))
      assert(!JSON.stringify(report).includes(secret));
  assert(!JSON.stringify(report).includes("Synthetic reminder"));
});
test("report reconstructs only public provenance and bounded counts and cannot emit recipient/content/proof/headers", () => {
  const input = {
    runId: "qa-reminder-test",
    startedAt: new Date().toISOString(),
    completedAt: new Date().toISOString(),
    status: "observation_pending",
    target: {
      ...base,
      endpoint: "https://user:PRIVATE@example.test/v1",
      workerReceiptSha256: "a".repeat(64),
    },
    checks: [
      {
        name: "private_recipient_value",
        status: "passed",
        code: "RAW_PRIVATE",
        assertions: 1,
        observations: {
          recipientIds: ["private"],
          body: "private",
          headers: { Authorization: "secret" },
          ownerItems: 1,
        },
      },
    ],
    budget: {
      httpRequests: 12,
      maxHttpRequests: 300,
      syntheticAccounts: 2,
      cleanupSessions: 2,
    },
  };
  const text = JSON.stringify(safeReminderReport(input));
  for (const secret of [
    "PRIVATE",
    "RAW_PRIVATE",
    "private_recipient_value",
    "recipientIds",
    "Authorization",
  ])
    assert(!text.includes(secret));
  const safe = safeReminderReport(
    { ...input, target: { ...input.target, functionId: "private-secret" } },
    new Set(["private-secret"]),
  );
  assert.equal(safe.checks[0].code, "redaction_failure");
});

test("in-memory synthetic pool skips account creation but signs in, verifies IDs and signs out its own sessions", async () => {
  const pool = [
    {
      id: "pooled-owner",
      email: "pool-owner@example.test",
      password: "SyntheticPassword123!",
    },
    {
      id: "pooled-member",
      email: "pool-member@example.test",
      password: "DifferentPassword123!",
    },
  ];
  const fake = fakeCloud({ existingAccounts: pool });
  const supplied = [];
  const report = await runReminderSmoke(config(), {
    fetchImpl: fake.fetchImpl,
    actorCredentials: async (label, { runId }) => {
      supplied.push({ label, runId });
      return pool[label === "owner" ? 0 : 1];
    },
  });
  assert.equal(report.status, "observation_pending");
  assert.equal(
    fake.calls.filter(
      (call) => call.path === "/account" && call.method === "POST",
    ).length,
    0,
  );
  assert.equal(
    fake.calls.filter(
      (call) => call.path === "/account" && call.method === "GET",
    ).length,
    2,
  );
  assert.equal(report.budget.syntheticAccounts, 0);
  assert.equal(report.budget.reusedVerifiedSyntheticAccounts, 2);
  assert.equal(report.budget.cleanupSessions, 2);
  assert(
    report.accounts.every(
      (account) => account.creationStatus === "reused_verified",
    ),
  );
  assert.deepEqual(
    supplied.map((value) => value.label),
    ["owner", "member"],
  );
  for (const credentials of pool)
    for (const value of Object.values(credentials))
      assert(!JSON.stringify(report).includes(value));
});
test("invalid/non-synthetic pooled credentials are refused rather than falling back to create or random signin", async () => {
  for (const value of [
    null,
    { id: "id", email: "human@example.com", password: "SyntheticPassword123!" },
    { id: "id", email: "pool@example.test", password: "short" },
    {
      id: "id",
      email: "pool@example.test",
      password: "SyntheticPassword123!",
      apiKey: "forbidden",
    },
  ]) {
    const fake = fakeCloud();
    const report = await runReminderSmoke(config(), {
      fetchImpl: fake.fetchImpl,
      actorCredentials: async () => value,
    });
    assert.equal(fake.calls.length, 0);
    assert.notEqual(report.status, "passed");
  }
});
test("positive timed orchestration reaches only observed in-app delivery and bounded dedup with no private-worker route", async (t) => {
  const start = Date.now();
  t.mock.timers.enable({ apis: ["Date"], now: start });
  const fake = fakeCloud({ timedWorker: true });
  const report = await runReminderSmoke(
    { ...config(), waitSeconds: 300 },
    {
      fetchImpl: fake.fetchImpl,
      sleep: async (ms) => {
        t.mock.timers.tick(ms);
      },
    },
  );
  assert.equal(report.status, "passed", JSON.stringify(report));
  assert.equal(report.budget.cleanupSessions, 2);
  assert(report.budget.httpRequests <= 300);
  assert(report.checks.some((check) => check.deliveredRuns === 2));
  assert(report.checks.some((check) => check.sameOccurrenceItems === 1));
  assert.equal(report.target.workerDeploymentObserved, false);
  assert.equal(
    report.coverage.oneShotCausality,
    "not_observable_from_public_client",
  );
  assert(fake.calls.every((call) => !call.path.includes("/functions/worker/")));
  assert(Date.now() - start <= 300000);
});

test("five-minute pending worker observation remains pending, obeys HTTP cap and never starts a retry write", async (t) => {
  const start = Date.now();
  t.mock.timers.enable({ apis: ["Date"], now: start });
  const fake = fakeCloud({ timedWorker: true, neverDeliver: true });
  const report = await runReminderSmoke(
    { ...config(), waitSeconds: 300 },
    { fetchImpl: fake.fetchImpl, sleep: async (ms) => t.mock.timers.tick(ms) },
  );
  assert.equal(report.status, "observation_pending");
  assert(
    report.checks.some(
      (check) =>
        check.name === "observe_terminal_runs_and_private_inboxes" &&
        check.code === "observation_window_expired",
    ),
  );
  assert.equal(report.budget.cleanupSessions, 2);
  assert(report.budget.httpRequests <= 300);
  assert(Date.now() - start <= 300000);
  const mutations = fake.commands().filter((command) => command.operationId);
  assert.equal(
    new Set(mutations.map((command) => command.operationId)).size,
    mutations.length,
  );
});
test("pooled owner/member must have distinct IDs and emails before the second account is authenticated", async () => {
  for (const duplicate of ["id", "email"]) {
    const pool = [
      {
        id: "different-id",
        email: "pool-owner@example.test",
        password: "SyntheticPassword123!",
      },
      {
        id: "same-id",
        email: "pool-member@example.test",
        password: "DifferentPassword123!",
      },
    ];
    pool[1][duplicate] = pool[0][duplicate];
    const fake = fakeCloud({ existingAccounts: pool });
    const report = await runReminderSmoke(config(), {
      fetchImpl: fake.fetchImpl,
      actorCredentials: async (label) => pool[label === "owner" ? 0 : 1],
    });
    assert.notEqual(report.status, "passed");
    assert.equal(
      fake.calls.filter((call) => call.path === "/account/sessions/email")
        .length,
      1,
    );
    assert.equal(report.budget.cleanupSessions, 1);
    assert.equal(report.budget.reusedVerifiedSyntheticAccounts, 1);
  }
});

test("pooled credentials require a fresh authenticated account ID match before reuse is counted", async () => {
  const actual = {
    id: "real-synthetic-id",
    email: "pool-owner@example.test",
    password: "SyntheticPassword123!",
  };
  const fake = fakeCloud({ existingAccounts: [actual] });
  const report = await runReminderSmoke(config(), {
    fetchImpl: fake.fetchImpl,
    actorCredentials: async () => ({ ...actual, id: "wrong-claimed-id" }),
  });
  assert.equal(report.status, "blocked");
  assert.equal(report.budget.reusedVerifiedSyntheticAccounts, 0);
  assert.equal(report.budget.syntheticAccounts, 0);
  assert.equal(report.budget.cleanupSessions, 1);
  assert.equal(fake.commands().length, 0);
  assert.equal(fake.calls.filter((call) => call.path === "/account").length, 1);
});
