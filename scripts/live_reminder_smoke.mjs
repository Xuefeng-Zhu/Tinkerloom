#!/usr/bin/env node
/** Explicitly gated user-cookie probe. Importing never starts Cloud work. */
import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve, join } from "node:path";
import { readFullConfiguration } from "./live_full_smoke.mjs";
import {
  AppwriteUserClient,
  HttpBudget,
  authRequest,
  functionObservation,
} from "./live_full_transport.mjs";
import {
  validFullApp,
  validReview,
  validOutcome,
  id,
  FullProbeError,
} from "./live_full_contract.mjs";
import {
  ReminderProbeError,
  requireProbe,
  workerReceipt,
  verifyReminderConfiguration,
  reminderStates,
  reminderRuns,
  reminderInbox,
  safeReminderReport,
} from "./live_reminder_contract.mjs";
const newId = (prefix) =>
  prefix.slice(0, 3) + "-" + randomBytes(14).toString("hex");
const readOps = new Set([
  "spec.capabilities",
  "spec.getApp",
  "spec.getRecord",
  "spec.reminderState",
  "spec.runs",
  "spec.inbox",
  "spec.review",
  "inspectInvitation",
]);
export function readReminderConfiguration(
  args = process.argv.slice(2),
  env = process.env,
  publicFile,
) {
  let enabled = false,
    receiptPath,
    receiptSha,
    waitSeconds = 0;
  const full = [];
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    if (flag === "--enable-live-reminders=true") {
      enabled = true;
      continue;
    }
    if (flag === "--worker-configuration-receipt") {
      receiptPath = args[++i];
      continue;
    }
    if (flag === "--worker-configuration-sha256") {
      receiptSha = args[++i];
      continue;
    }
    if (flag === "--wait-seconds") {
      waitSeconds = Number(args[++i]);
      continue;
    }
    requireProbe(
      !flag.startsWith("--enable-live-reminders"),
      "explicit_enable_required",
    );
    full.push(flag, args[++i]);
  }
  requireProbe(enabled, "explicit_enable_required");
  requireProbe(
    typeof receiptPath === "string" && typeof receiptSha === "string",
    "private_worker_gate_required",
  );
  if (!full.includes("--max-http")) full.push("--max-http", "300");
  const configuration = readFullConfiguration(full, env, publicFile);
  configuration.enableLiveReminders = true;
  configuration.waitSeconds = waitSeconds;
  let bytes;
  try {
    bytes = readFileSync(receiptPath);
  } catch {
    throw new ReminderProbeError("private_worker_gate_required");
  }
  configuration.workerGate = workerReceipt(bytes, receiptSha, configuration);
  verifyReminderConfiguration(configuration);
  return configuration;
}
export async function runReminderSmoke(
  configuration,
  {
    fetchImpl = globalThis.fetch,
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    onProgress = () => {},
    actorCredentials,
  } = {},
) {
  verifyReminderConfiguration(configuration);
  requireProbe(
    actorCredentials === undefined || typeof actorCredentials === "function",
    "invalid_reminder_configuration",
  );
  const privateValues = new Set(),
    budget = new HttpBudget(configuration.maxHttp, 4),
    clients = [],
    actors = {},
    checks = [];
  const startedAt = new Date().toISOString(),
    runId =
      "qa-reminder-" +
      Date.now().toString(36) +
      "-" +
      randomBytes(3).toString("hex");
  const report = {
    runId,
    startedAt,
    completedAt: null,
    status: "running",
    target: {
      ...configuration,
      workerReceiptSha256: configuration.workerGate.sha256,
    },
    checks,
    accounts: [],
    budget: {
      reusedVerifiedSyntheticAccounts: 0,
      maxHttpRequests: configuration.maxHttp,
      httpRequests: 0,
      syntheticAccounts: 0,
      cleanupSessions: 0,
    },
  };
  let assertionCount = 0,
    lastOperation;
  let observationDeadline = null;
  const actorIds = new Set();
  const actorEmails = new Set();
  const verify = (value) => {
    assertionCount++;
    requireProbe(value, "assertion_failed");
  };
  const phase = async (name, run) => {
    const before = assertionCount;
    try {
      onProgress({ phase: name });
    } catch {
      /* Logging cannot alter probe behavior. */
    }
    try {
      const result = await run();
      checks.push({
        name,
        status: result?.pending ? "observation_pending" : "passed",
        code: result?.pending ?? "none",
        assertions: assertionCount - before,
        observations: result?.observations ?? {},
      });
      return result;
    } catch (error) {
      checks.push({
        name,
        status:
          error instanceof ReminderProbeError && error.uncertain
            ? "observation_pending"
            : error instanceof ReminderProbeError &&
                [
                  "operational_effects_unavailable",
                  "auth_unavailable",
                  "read_unavailable",
                  "invalid_reminder_configuration",
                ].includes(error.code)
              ? "blocked"
              : "failed",
        code:
          error instanceof ReminderProbeError
            ? error.code
            : error instanceof FullProbeError &&
                error.code === "http_budget_exhausted"
              ? error.code
              : "unexpected_probe_error",
        assertions: assertionCount - before,
        operation: lastOperation,
        observation: error?.observation,
      });
      throw error;
    }
  };
  const execute = async (
    actor,
    request,
    { mutation = false, status = 200, code } = {},
  ) => {
    lastOperation = request.op;
    try {
      if (observationDeadline !== null) {
        const remaining = observationDeadline - Date.now();
        if (remaining <= 0)
          throw new ReminderProbeError("observation_window_expired", {
            uncertain: true,
          });
        actor.client.configuration.timeoutMs = Math.max(
          1,
          Math.min(configuration.timeoutMs, remaining),
        );
      }
      const result = await actor.client.execute(request);
      if (
        result.outer?.status >= 200 &&
        result.outer.status < 300 &&
        result.executionStatus === "completed" &&
        result.deploymentMatched === true &&
        result.status === status
      ) {
        if (code) verify(result.data?.error === code);
        return result.data;
      }
      if (
        !mutation &&
        result.status === 409 &&
        result.data?.error === "transaction_conflict"
      )
        throw new ReminderProbeError("read_unavailable");
      if (
        mutation &&
        (result.executionStatus !== "completed" ||
          result.deploymentMatched !== true ||
          (result.status === 409 &&
            result.data?.error === "transaction_conflict") ||
          result.status >= 500)
      )
        throw new ReminderProbeError("write_outcome_unknown", {
          uncertain: true,
          observation: functionObservation(result),
        });
      throw new ReminderProbeError("assertion_failed", {
        observation: functionObservation(result),
      });
    } catch (error) {
      if (error instanceof ReminderProbeError) throw error;
      throw new ReminderProbeError(
        mutation ? "write_outcome_unknown" : "read_unavailable",
        { uncertain: mutation },
      );
    }
  };
  const read = async (actor, request, options) => {
    requireProbe(readOps.has(request.op), "invalid_reminder_configuration");
    for (let attempt = 0; ; attempt++)
      try {
        return await execute(actor, request, options);
      } catch (error) {
        if (error.code !== "read_unavailable" || attempt >= 2) throw error;
        await sleep(250);
      }
  };
  const mutate = (actor, request, options) =>
    execute(actor, request, { ...options, mutation: true });
  const createActor = async (label) => {
    requireProbe(clients.length < 2, "invalid_reminder_configuration");
    const client = new AppwriteUserClient(
      { ...configuration },
      {
        budget,
        privateValues,
        fetchImpl,
      },
    );
    clients.push(client);
    const supplied = actorCredentials
      ? await actorCredentials(label, { runId })
      : null;
    const credentials = actorCredentials
      ? supplied && { ...supplied }
      : {
          id: newId("usr"),
          email: `${runId}-${label}@example.test`,
          password: randomBytes(24).toString("base64url") + "aA1!",
        };
    requireProbe(
      credentials &&
        Object.keys(credentials).length === 3 &&
        ["id", "email", "password"].every((key) =>
          Object.hasOwn(credentials, key),
        ) &&
        id(credentials.id) &&
        typeof credentials.email === "string" &&
        /^[A-Za-z0-9][A-Za-z0-9+._-]{0,160}@example\.test$/.test(
          credentials.email,
        ) &&
        typeof credentials.password === "string" &&
        /^[\x21-\x7e]{12,256}$/.test(credentials.password) &&
        !actorIds.has(credentials.id) &&
        !actorEmails.has(credentials.email.toLowerCase()),
      "invalid_reminder_configuration",
    );
    actorIds.add(credentials.id);
    actorEmails.add(credentials.email.toLowerCase());
    privateValues.add(credentials.id);
    privateValues.add(credentials.email);
    privateValues.add(credentials.password);
    if (!actorCredentials) {
      const created = await authRequest(client, "POST", "/account", {
        userId: credentials.id,
        email: credentials.email,
        password: credentials.password,
        name: "Synthetic reminder QA",
      });
      requireProbe(created.status === 201, "auth_unavailable");
      report.budget.syntheticAccounts++;
    }
    const signed = await authRequest(
      client,
      "POST",
      "/account/sessions/email",
      { email: credentials.email, password: credentials.password },
    );
    requireProbe(
      signed.status === 201 && client.cookies.size > 0,
      "auth_unavailable",
    );
    const account = await client.request("GET", "/account");
    requireProbe(
      account.status === 200 && account.data?.$id === credentials.id,
      "auth_unavailable",
    );
    if (actorCredentials) report.budget.reusedVerifiedSyntheticAccounts++;
    report.accounts.push({
      label,
      creationStatus: actorCredentials
        ? "reused_verified"
        : "created_synthetic",
    });
    return { client, credentials };
  };
  const getRuns = async (target) => {
    const response = await read(actors.owner, {
      op: "spec.runs",
      appId: target.app.id,
    });
    requireProbe(response.nextCursor === null);
    return reminderRuns(response);
  };
  const getInbox = async (actor) => {
    const items = [];
    let afterId;
    const cursors = new Set();
    for (let page = 0; page < 3; page++) {
      const response = await read(actor, {
        op: "spec.inbox",
        ...(afterId ? { afterId } : {}),
      });
      items.push(...reminderInbox(response));
      if (response.nextCursor === null) {
        const targets = new Set([
          ownerApp?.app.id,
          memberApp?.app.id,
          revokedApp?.app.id,
        ]);
        return items.filter((item) => targets.has(item.appId));
      }
      requireProbe(
        !cursors.has(response.nextCursor),
        "invalid_reminder_response",
      );
      cursors.add(response.nextCursor);
      afterId = response.nextCursor;
    }
    throw new ReminderProbeError("read_unavailable");
  };
  const command = (target, actionId, input, record) => ({
    op: "spec.execute",
    appId: target.app.id,
    versionId: target.app.version.id,
    operationId: newId("cmd"),
    actionId,
    input,
    ...(record
      ? { targetRecordId: record.id, expectedRecordRevision: record.revision }
      : {}),
  });
  const record = async (actor, target, body) => {
    const result = await mutate(actor, body);
    verify(validOutcome(result));
    return {
      id: result.outcome.recordId,
      revision: result.outcome.revision,
      body,
      receipt: result,
    };
  };
  const makeApp = async (templateKey) => {
    // Worker planning stages the workspace guard. Separate synthetic scopes
    // prevent one app's asynchronous planning from contending with another
    // app's setup. Keep every write single-attempt.
    const workspaceId = newId("wor");
    await mutate(actors.owner, {
      op: "createWorkspace",
      id: workspaceId,
      name: "Synthetic reminder QA",
    });
    const result = await mutate(actors.owner, {
      op: "spec.instantiate",
      id: newId("app"),
      workspaceId,
      templateKey,
      operationId: newId("new"),
    });
    verify(validFullApp(result.app));
    return { app: result.app };
  };
  const approve = async (target, ruleId, records = []) => {
    const old = target.app.version.id;
    const saved = await mutate(actors.owner, {
      op: "spec.saveDraft",
      appId: target.app.id,
      operationId: newId("sav"),
      expectedRevision: target.app.draft?.revision ?? 0,
      expectedVersionId: old,
      spec: target.app.version.spec,
    });
    verify(validFullApp(saved.app));
    const review = await read(actors.owner, {
      op: "spec.review",
      appId: target.app.id,
      expectedRevision: saved.app.draft.revision,
      enabledRuleIds: [ruleId],
      activateExistingRecordIds: records,
    });
    verify(validReview(review.review));
    const published = await mutate(actors.owner, {
      op: "spec.publish",
      appId: target.app.id,
      operationId: newId("pub"),
      expectedRevision: saved.app.draft.revision,
      expectedVersionId: old,
      candidateHash: review.review.candidateHash,
      reviewHash: review.review.reviewHash,
      enabledRuleIds: [ruleId],
      activateExistingRecordIds: records,
    });
    verify(validFullApp(published.app));
    target.app = published.app;
    target.ruleId = ruleId;
  };
  const join = async (target) => {
    const token = randomBytes(32).toString("base64url");
    privateValues.add(token);
    await mutate(actors.owner, {
      op: "createInvitation",
      id: newId("inv"),
      appId: target.app.id,
      operationId: newId("inv"),
      recipientId: actors.member.credentials.id,
      role: "member",
      token,
    });
    const preview = await read(actors.member, {
      op: "inspectInvitation",
      token,
    });
    verify(
      preview.invitation?.appId === target.app.id &&
        preview.invitation.role === "member",
    );
    await mutate(actors.member, {
      op: "acceptInvitation",
      token,
      operationId: newId("acc"),
    });
  };
  let ownerApp,
    memberApp,
    revokedApp,
    ownerRecord,
    clearedRecord,
    conditionRecord,
    memberRecord,
    revokedRecord,
    plannedBeforeInvalidation = false,
    due;
  try {
    await phase("authenticate_owner_and_confirm_effects", async () => {
      actors.owner = await createActor("owner");
      const caps = await read(actors.owner, { op: "spec.capabilities" });
      requireProbe(
        Array.isArray(caps.effects) &&
          ["notifyOwner", "notifyAssignee"].every((effect) =>
            caps.effects.includes(effect),
          ),
        "operational_effects_unavailable",
      );
      verify(caps.apiVersion === 1);
    });
    await phase(
      "setup_explicit_owner_approval_and_member_acceptance",
      async () => {
        actors.member = await createActor("member");
        ownerApp = await makeApp("reminders");
        memberApp = await makeApp("chores");
        revokedApp = await makeApp("chores");
        const ownerRule = ownerApp.app.version.spec.automationRequests.find(
          (rule) => rule.id === "taskReminder",
        );
        const memberRule = memberApp.app.version.spec.automationRequests.find(
          (rule) => rule.id === "dueReminder",
        );
        verify(
          ownerRule?.trigger?.type === "beforeTimestamp" &&
            ownerRule.trigger.fieldId === "reminderAt" &&
            ownerRule.trigger.offsetSeconds === 0 &&
            ownerRule.effect?.type === "notifyOwner" &&
            ownerRule.effect.channel === "inApp",
        );
        verify(
          memberRule?.trigger?.type === "beforeTimestamp" &&
            memberRule.trigger.fieldId === "dueAt" &&
            memberRule.trigger.offsetSeconds === 3600 &&
            memberRule.effect?.type === "notifyAssignee" &&
            memberRule.effect.channel === "inApp",
        );
        for (const key of ["ownerRecord", "clearedRecord", "conditionRecord"]) {
          const value = await record(
            actors.owner,
            ownerApp,
            command(ownerApp, "addTask", {
              data: { title: "Synthetic reminder", status: "Open" },
            }),
          );
          if (key === "ownerRecord") ownerRecord = value;
          else if (key === "clearedRecord") clearedRecord = value;
          else conditionRecord = value;
        }
        const unset = reminderStates(
          await read(actors.owner, {
            op: "spec.reminderState",
            appId: ownerApp.app.id,
            versionId: ownerApp.app.version.id,
            recordId: ownerRecord.id,
          }),
          ownerApp.app.version.id,
          "taskReminder",
        );
        verify(unset.state === "unset");
        await approve(ownerApp, "taskReminder", [
          ownerRecord.id,
          clearedRecord.id,
          conditionRecord.id,
        ]);
        await approve(memberApp, "dueReminder");
        await approve(revokedApp, "dueReminder");
        await join(memberApp);
        await join(revokedApp);
      },
    );
    await phase(
      "set_real_future_dates_and_member_self_assignment",
      async () => {
        due = Date.now() + 180000;
        const reminderAt = new Date(due).toISOString();
        for (const value of [ownerRecord, clearedRecord, conditionRecord]) {
          const next = await record(
            actors.owner,
            ownerApp,
            command(
              ownerApp,
              "editTask",
              {
                data: {
                  reminderAt,
                  dueAt: new Date(due + 86400000).toISOString(),
                },
              },
              value,
            ),
          );
          value.revision = next.revision;
        }
        for (const target of [memberApp, revokedApp]) {
          const value = await record(
            actors.member,
            target,
            command(target, "addChore", {
              data: {
                title: "Synthetic member reminder",
                status: "Open",
                dueAt: new Date(due + 3600000).toISOString(),
              },
            }),
          );
          const assigned = await record(
            actors.member,
            target,
            command(
              target,
              "assignChore",
              { value: actors.member.credentials.id },
              value,
            ),
          );
          value.revision = assigned.revision;
          if (target === memberApp) memberRecord = value;
          else revokedRecord = value;
        }
        const state = reminderStates(
          await read(actors.owner, {
            op: "spec.reminderState",
            appId: ownerApp.app.id,
            versionId: ownerApp.app.version.id,
            recordId: ownerRecord.id,
          }),
          ownerApp.app.version.id,
          "taskReminder",
        );
        verify(
          state.state === "pending" &&
            state.scheduledAt === reminderAt &&
            state.eligible === true,
        );
        verify(
          (await getInbox(actors.owner)).length === 0 &&
            (await getInbox(actors.member)).length === 0,
        );
        await read(
          actors.member,
          { op: "spec.runs", appId: memberApp.app.id },
          { status: 403, code: "forbidden" },
        );
      },
    );
    const stopAt = Date.now() + configuration.waitSeconds * 1000;
    if (configuration.waitSeconds > 0) observationDeadline = stopAt;
    await phase("observe_planning_then_invalidate_before_due", async () => {
      while (Date.now() < Math.min(stopAt, due - 30000)) {
        const runs = await getRuns(ownerApp);
        plannedBeforeInvalidation = [clearedRecord, conditionRecord].every(
          (record) =>
            runs.some(
              (run) => run.recordId === record.id && run.status === "pending",
            ),
        );
        if (plannedBeforeInvalidation) break;
        await sleep(15000);
      }
      requireProbe(Date.now() < due, "read_unavailable");
      const cleared = await record(
        actors.owner,
        ownerApp,
        command(
          ownerApp,
          "editTask",
          { data: { reminderAt: null } },
          clearedRecord,
        ),
      );
      clearedRecord.revision = cleared.revision;
      await record(
        actors.owner,
        ownerApp,
        command(ownerApp, "moveTask", { value: "Done" }, conditionRecord),
      );
      await mutate(actors.owner, {
        op: "setGrant",
        appId: revokedApp.app.id,
        actorId: actors.member.credentials.id,
        role: null,
        expectedRevision: 1,
        operationId: newId("rev"),
      });
      const state = reminderStates(
        await read(actors.owner, {
          op: "spec.reminderState",
          appId: ownerApp.app.id,
          versionId: ownerApp.app.version.id,
          recordId: clearedRecord.id,
        }),
        ownerApp.app.version.id,
        "taskReminder",
      );
      verify(state.state === "unset");
      return plannedBeforeInvalidation ? {} : { pending: "pending_planning" };
    });
    if (configuration.waitSeconds === 0) {
      checks.push({
        name: "live_delivery_observation",
        status: "observation_pending",
        code: "observation_window_expired",
        assertions: 0,
      });
    } else {
      let observed;
      await phase("observe_terminal_runs_and_private_inboxes", async () => {
        while (Date.now() < stopAt) {
          const ownerRuns = await getRuns(ownerApp),
            memberRuns = await getRuns(memberApp),
            revokedRuns = await getRuns(revokedApp),
            ownerItems = await getInbox(actors.owner),
            memberItems = await getInbox(actors.member);
          const main = ownerRuns.find((run) => run.recordId === ownerRecord.id),
            member = memberRuns.find((run) => run.recordId === memberRecord.id),
            revoked = revokedRuns.find(
              (run) => run.recordId === revokedRecord.id,
            );
          if (
            [...ownerRuns, ...memberRuns, ...revokedRuns].some(
              (run) => run.status === "failed",
            )
          )
            throw new ReminderProbeError("confirmed_run_failure");
          verify(
            ownerItems.filter((item) => item.recordId === ownerRecord.id)
              .length <= 1 &&
              memberItems.filter((item) => item.recordId === memberRecord.id)
                .length <= 1,
          );
          verify(
            !ownerItems.some((item) => item.recordId === memberRecord.id) &&
              !memberItems.some((item) => item.appId === revokedApp.app.id),
          );
          if (
            main?.status === "succeeded" &&
            main.recipientCount === 1 &&
            member?.status === "succeeded" &&
            member.recipientCount === 1 &&
            revoked &&
            ["succeeded", "suppressed"].includes(revoked.status) &&
            revoked.recipientCount === 0 &&
            ownerItems.some((item) => item.recordId === ownerRecord.id) &&
            memberItems.some((item) => item.recordId === memberRecord.id)
          ) {
            verify(
              Date.parse(
                ownerItems.find((item) => item.recordId === ownerRecord.id)
                  .createdAt,
              ) >= due &&
                Date.parse(
                  memberItems.find((item) => item.recordId === memberRecord.id)
                    .createdAt,
                ) >= due,
            );
            const stale = ownerRuns.filter((run) =>
              [clearedRecord.id, conditionRecord.id].includes(run.recordId),
            );
            if (plannedBeforeInvalidation)
              verify(
                stale.length >= 2 &&
                  stale.every(
                    (run) =>
                      run.status === "suppressed" && run.recipientCount === 0,
                  ),
              );
            observed = { main, member, ownerItems, memberItems };
            return {
              observations: {
                ownerItems: ownerItems.length,
                memberItems: memberItems.length,
                deliveredRuns: 2,
                suppressedRuns: stale.filter(
                  (run) => run.status === "suppressed",
                ).length,
                zeroRecipientRuns: 1,
              },
            };
          }
          try {
            onProgress({
              phase: "waiting_for_worker_observation",
              httpRequests: budget.used,
            });
          } catch {}
          await sleep(Math.min(15000, Math.max(1, stopAt - Date.now())));
        }
        return { pending: "observation_window_expired" };
      });
      if (observed)
        await phase(
          "read_receipts_cross_recipient_denial_and_bounded_dedup",
          async () => {
            const item = observed.memberItems.find(
              (item) => item.recordId === memberRecord.id,
            );
            const body = {
              op: "spec.readNotification",
              appId: memberApp.app.id,
              runId: item.runId,
              notificationId: item.id,
              operationId: newId("rea"),
            };
            const ack = await mutate(actors.member, body);
            verify(ack.notificationId === item.id && ack.isRead === true);
            verify(
              JSON.stringify(await mutate(actors.member, body)) ===
                JSON.stringify(ack),
            );
            await mutate(
              actors.owner,
              { ...body, operationId: newId("den") },
              { status: 404, code: "not_found" },
            );
            verify(
              (await getInbox(actors.member)).find(
                (value) => value.id === item.id,
              )?.isRead === true,
            );
            const replay = await mutate(actors.owner, ownerRecord.body);
            verify(
              JSON.stringify(replay) === JSON.stringify(ownerRecord.receipt),
            );
            await record(
              actors.owner,
              ownerApp,
              command(
                ownerApp,
                "editTask",
                { data: { notes: "Synthetic unrelated edit" } },
                ownerRecord,
              ),
            );
            if (Date.now() + 30000 > stopAt)
              return { pending: "observation_window_expired" };
            await sleep(30000);
            const inbox = await getInbox(actors.owner),
              runs = await getRuns(ownerApp);
            verify(
              inbox.filter((item) => item.recordId === ownerRecord.id)
                .length === 1 &&
                runs.filter((run) => run.recordId === ownerRecord.id).length ===
                  1,
            );
            return { observations: { sameOccurrenceItems: 1 } };
          },
        );
    }
  } catch (error) {
    if (!checks.length)
      checks.push({
        name: "preflight",
        status: "blocked",
        code: error.code ?? "unexpected_probe_error",
        assertions: 0,
      });
  } finally {
    for (const client of clients) {
      client.configuration.timeoutMs = configuration.timeoutMs;
      if (!client.cookies.size) continue;
      try {
        const result = await client.request(
          "DELETE",
          "/account/sessions/current",
          undefined,
          { cleanup: true },
        );
        if (result.status === 204) report.budget.cleanupSessions++;
        else
          checks.push({
            name: "session_cleanup",
            status: "blocked",
            code: "cleanup_unconfirmed",
            assertions: 0,
          });
      } catch {
        checks.push({
          name: "session_cleanup",
          status: "blocked",
          code: "cleanup_unconfirmed",
          assertions: 0,
        });
      }
    }
    report.completedAt = new Date().toISOString();
    report.budget.httpRequests = budget.used;
  }
  report.status = checks.some((check) => check.status === "failed")
    ? "failed"
    : checks.some((check) => check.status === "observation_pending")
      ? "observation_pending"
      : checks.some((check) => check.status === "blocked")
        ? "blocked"
        : "passed";
  return safeReminderReport(report, privateValues);
}
async function main() {
  let report;
  try {
    report = await runReminderSmoke(readReminderConfiguration(), {
      onProgress: (value) => process.stderr.write(JSON.stringify(value) + "\n"),
    });
  } catch (error) {
    report = {
      schemaVersion: 1,
      status: "blocked",
      checks: [
        {
          name: "explicit_enable_and_private_worker_gate",
          status: "blocked",
          code: [
            "explicit_enable_required",
            "private_worker_gate_required",
          ].includes(error.code)
            ? error.code
            : "invalid_reminder_configuration",
          assertions: 0,
        },
      ],
    };
  }
  const text = JSON.stringify(report, null, 2) + "\n";
  if (report.runId) {
    try {
      const directory = fileURLToPath(
        new URL(`../output/live-reminders/${report.runId}/`, import.meta.url),
      );
      await mkdir(directory, { recursive: true });
      await writeFile(join(directory, "report.json"), text, {
        flag: "wx",
        mode: 0o600,
      });
    } catch {
      report = {
        ...report,
        status: "failed",
        persistenceError: "report_persistence_failed",
      };
    }
  }
  process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  process.exitCode =
    report.status === "passed" ? 0 : report.status === "failed" ? 1 : 2;
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  await main();
