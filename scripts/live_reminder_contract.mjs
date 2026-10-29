/** Reminder probe contracts only. Importing performs no I/O or network. */
import { createHash } from "node:crypto";
import { exactKeys, id, safeFullObservation } from "./live_full_contract.mjs";
const verifiedWorkerGates = new WeakMap();
const boundTargetKeys = [
  "projectId",
  "functionId",
  "coreDeploymentId",
  "workerFunctionId",
  "workerDeploymentId",
];
export const receiptHash = (bytes) =>
  createHash("sha256").update(bytes).digest("hex");
const instant = (value) => {
  if (typeof value !== "string") return false;
  const match =
    /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)\.(\d{3})(?:\d{3})?Z$/.exec(
      value,
    );
  if (!match) return false;
  const date = new Date(value);
  return (
    Number.isFinite(date.getTime()) &&
    [
      date.getUTCFullYear(),
      date.getUTCMonth() + 1,
      date.getUTCDate(),
      date.getUTCHours(),
      date.getUTCMinutes(),
      date.getUTCSeconds(),
      date.getUTCMilliseconds(),
    ].every((part, index) => part === Number(match[index + 1]))
  );
};
const count = (value) => Number.isSafeInteger(value) && value >= 0;
export class ReminderProbeError extends Error {
  constructor(code, { uncertain = false, observation = {} } = {}) {
    super(code);
    this.code = code;
    this.uncertain = uncertain;
    this.observation = safeFullObservation(observation);
  }
}
export function requireProbe(condition, code = "invalid_reminder_response") {
  if (!condition) throw new ReminderProbeError(code);
}
/** Operator provenance is deliberately labelled, never promoted to server attestation. */
export function workerReceipt(bytes, expectedSha, configuration) {
  requireProbe(
    typeof expectedSha === "string" &&
      /^[a-f0-9]{64}$/.test(expectedSha) &&
      bytes.byteLength <= 65536 &&
      receiptHash(bytes) === expectedSha,
    "private_worker_gate_required",
  );
  let value;
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch {
    throw new ReminderProbeError("private_worker_gate_required");
  }
  requireProbe(
    exactKeys(value, [
      "schemaVersion",
      "capturedAt",
      "projectId",
      "coreFunctionId",
      "coreDeploymentId",
      "workerFunctionId",
      "workerDeploymentId",
      "execute",
      "domains",
      "intervalMinutes",
      "configuredWorkerIdentityMatches",
      "remindersEnabled",
      "executionScopesVerified",
      "oneShot",
    ]),
    "private_worker_gate_required",
  );
  requireProbe(
    value.schemaVersion === 1 &&
      instant(value.capturedAt) &&
      value.projectId === configuration.projectId &&
      value.coreFunctionId === configuration.functionId &&
      value.coreDeploymentId === configuration.coreDeploymentId &&
      value.workerFunctionId === configuration.workerFunctionId &&
      value.workerDeploymentId === configuration.workerDeploymentId &&
      value.configuredWorkerIdentityMatches === true &&
      Array.isArray(value.execute) &&
      value.execute.length === 0 &&
      Array.isArray(value.domains) &&
      value.domains.length === 0 &&
      Number.isInteger(value.intervalMinutes) &&
      value.intervalMinutes >= 60 &&
      value.intervalMinutes <= 1440 &&
      exactKeys(value.remindersEnabled, ["core", "worker"]) &&
      value.remindersEnabled.core === true &&
      value.remindersEnabled.worker === true &&
      exactKeys(value.executionScopesVerified, ["core", "worker"]) &&
      value.executionScopesVerified.core === true &&
      value.executionScopesVerified.worker === true &&
      exactKeys(value.oneShot, ["accepted", "executionId"]) &&
      value.oneShot.accepted === true &&
      id(value.oneShot.executionId),
    "private_worker_gate_required",
  );
  requireProbe(
    Date.parse(value.capturedAt) <= Date.now() + 60000 &&
      Date.parse(value.capturedAt) >= Date.now() - 86400000,
    "private_worker_gate_required",
  );
  const gate = Object.freeze({
    sha256: expectedSha,
    capturedAt: value.capturedAt,
    intervalMinutes: value.intervalMinutes,
    attestation: "operator_console_metadata_not_public_server_attestation",
  });
  verifiedWorkerGates.set(
    gate,
    Object.freeze(
      Object.fromEntries(
        boundTargetKeys.map((key) => [key, configuration[key]]),
      ),
    ),
  );
  return gate;
}
export function verifyReminderConfiguration(configuration) {
  requireProbe(
    configuration.enableLiveReminders === true,
    "explicit_enable_required",
  );
  requireProbe(
    verifiedWorkerGates.has(configuration.workerGate) &&
      boundTargetKeys.every(
        (key) =>
          verifiedWorkerGates.get(configuration.workerGate)[key] ===
          configuration[key],
      ) &&
      configuration.workerGate?.attestation ===
        "operator_console_metadata_not_public_server_attestation" &&
      /^[a-f0-9]{64}$/.test(configuration.workerGate.sha256) &&
      id(configuration.workerFunctionId) &&
      Date.parse(configuration.workerGate.capturedAt) <= Date.now() + 60000 &&
      Date.parse(configuration.workerGate.capturedAt) >= Date.now() - 86400000,
    "private_worker_gate_required",
  );
  requireProbe(
    Number.isInteger(configuration.maxHttp) &&
      configuration.maxHttp >= 100 &&
      configuration.maxHttp <= 300 &&
      (configuration.waitSeconds === 0 ||
        (Number.isInteger(configuration.waitSeconds) &&
          configuration.waitSeconds >= 180 &&
          configuration.waitSeconds <= 300)),
    "invalid_reminder_configuration",
  );
}
export function reminderStates(input, versionId, ruleId) {
  requireProbe(
    exactKeys(input, ["states", "versionId"]) &&
      input.versionId === versionId &&
      Array.isArray(input.states) &&
      input.states.length === 1,
  );
  const value = input.states[0];
  requireProbe(
    exactKeys(value, [
      "ruleId",
      "state",
      "scheduledAt",
      "eligible",
      "recipientCount",
    ]) &&
      value.ruleId === ruleId &&
      [
        "unset",
        "disabled",
        "unenrolled",
        "pending",
        "delivered",
        "suppressed",
        "failed",
      ].includes(value.state) &&
      (value.scheduledAt === null || instant(value.scheduledAt)) &&
      typeof value.eligible === "boolean" &&
      count(value.recipientCount) &&
      value.recipientCount <= 500,
  );
  return value;
}
export function reminderRuns(input) {
  requireProbe(
    exactKeys(input, ["runs", "nextCursor"]) &&
      Array.isArray(input.runs) &&
      input.runs.length <= 50 &&
      (input.nextCursor === null || id(input.nextCursor)),
  );
  const ids = new Set();
  for (const run of input.runs) {
    requireProbe(
      exactKeys(run, [
        "id",
        "ruleId",
        "recordId",
        "status",
        "dueAt",
        "nextAttemptAt",
        "attempts",
        "errorCategory",
        "recipientCount",
      ]) &&
        id(run.id) &&
        typeof run.ruleId === "string" &&
        id(run.recordId) &&
        ["pending", "running", "succeeded", "suppressed", "failed"].includes(
          run.status,
        ) &&
        instant(run.dueAt) &&
        instant(run.nextAttemptAt) &&
        count(run.attempts) &&
        run.attempts <= 5 &&
        (run.errorCategory === null ||
          /^[a-z_]{1,64}$/.test(run.errorCategory)) &&
        count(run.recipientCount) &&
        run.recipientCount <= 500 &&
        !ids.has(run.id),
    );
    ids.add(run.id);
  }
  return input.runs;
}
export function reminderInbox(input) {
  requireProbe(
    exactKeys(input, ["items", "nextCursor"]) &&
      Array.isArray(input.items) &&
      input.items.length <= 100 &&
      (input.nextCursor === null || id(input.nextCursor)),
  );
  const ids = new Set();
  for (const value of input.items) {
    requireProbe(
      exactKeys(value, [
        "id",
        "appId",
        "runId",
        "recordId",
        "collectionId",
        "title",
        "body",
        "createdAt",
        "isRead",
      ]) &&
        id(value.id) &&
        id(value.appId) &&
        id(value.runId) &&
        (value.recordId === null) === (value.collectionId === null) &&
        (value.recordId === null || id(value.recordId)) &&
        (value.collectionId === null ||
          typeof value.collectionId === "string") &&
        typeof value.title === "string" &&
        value.title.length <= 4096 &&
        typeof value.body === "string" &&
        value.body.length <= 16384 &&
        instant(value.createdAt) &&
        typeof value.isRead === "boolean" &&
        !ids.has(value.id),
    );
    ids.add(value.id);
  }
  return input.items;
}
const safeEndpoint = (value) => {
  try {
    const url = new URL(value);
    return !url.username &&
      !url.password &&
      !url.search &&
      !url.hash &&
      (url.protocol === "https:" ||
        (url.protocol === "http:" &&
          ["localhost", "127.0.0.1"].includes(url.hostname)))
      ? url.toString().replace(/\/$/, "")
      : null;
  } catch {
    return null;
  }
};
const safeId = (value) => (id(value) ? value : null);
const phaseNames = new Set([
  "authenticate_owner_and_confirm_effects",
  "setup_explicit_owner_approval_and_member_acceptance",
  "set_real_future_dates_and_member_self_assignment",
  "live_delivery_observation",
  "observe_planning_then_invalidate_before_due",
  "observe_terminal_runs_and_private_inboxes",
  "read_receipts_cross_recipient_denial_and_bounded_dedup",
  "session_cleanup",
  "preflight",
  "redaction",
  "explicit_enable_and_private_worker_gate",
]);
const statuses = new Set([
  "passed",
  "failed",
  "blocked",
  "observation_pending",
]);
const codes = new Set([
  "none",
  "explicit_enable_required",
  "private_worker_gate_required",
  "invalid_reminder_configuration",
  "configuration_invalid",
  "operational_effects_unavailable",
  "auth_unavailable",
  "prerequisite_unavailable",
  "invalid_reminder_response",
  "assertion_failed",
  "write_outcome_unknown",
  "read_unavailable",
  "pending_planning",
  "observation_window_expired",
  "confirmed_run_failure",
  "http_budget_exhausted",
  "unexpected_probe_error",
  "cleanup_unconfirmed",
  "redaction_failure",
]);
const counts = new Set([
  "ownerItems",
  "memberItems",
  "plannedRuns",
  "deliveredRuns",
  "suppressedRuns",
  "zeroRecipientRuns",
  "httpRequests",
  "elapsedMs",
  "syntheticAccounts",
  "sameOccurrenceItems",
  "cleanupSessions",
]);
/** Fixed fields and numeric observations only; no recipient IDs, text, bodies, cookies or proofs. */
export function safeReminderReport(input, privateValues = new Set()) {
  const report = {
    schemaVersion: 1,
    runId:
      typeof input.runId === "string" &&
      /^qa-reminder-[a-z0-9-]{1,64}$/.test(input.runId)
        ? input.runId
        : null,
    startedAt: instant(input.startedAt) ? input.startedAt : null,
    completedAt: instant(input.completedAt) ? input.completedAt : null,
    status: statuses.has(input.status) ? input.status : "failed",
    target: {
      endpoint: safeEndpoint(input.target?.endpoint),
      projectId: safeId(input.target?.projectId),
      functionId: safeId(input.target?.functionId),
      coreDeploymentId: safeId(input.target?.coreDeploymentId),
      workerFunctionId: safeId(input.target?.workerFunctionId),
      workerDeploymentId: safeId(input.target?.workerDeploymentId),
      sourceCommit: /^[a-f0-9]{7,40}$/.test(input.target?.sourceCommit ?? "")
        ? input.target.sourceCommit
        : null,
      sourceSha256: /^[a-f0-9]{64}$/.test(input.target?.sourceSha256 ?? "")
        ? input.target.sourceSha256
        : null,
      workerReceiptSha256: /^[a-f0-9]{64}$/.test(
        input.target?.workerReceiptSha256 ?? "",
      )
        ? input.target.workerReceiptSha256
        : null,
      sourceAttestation: "operator_supplied_not_server_attested",
      workerDeploymentObserved: false,
    },
    checks: input.checks.map((check) => ({
      name: phaseNames.has(check.name) ? check.name : "redacted_check",
      status: statuses.has(check.status) ? check.status : "failed",
      code: codes.has(check.code) ? check.code : "unexpected_probe_error",
      assertions: count(check.assertions) ? check.assertions : 0,
      ...Object.fromEntries(
        Object.entries(check.observations ?? {}).filter(
          ([key, value]) => counts.has(key) && count(value),
        ),
      ),
    })),
    accounts: (input.accounts ?? [])
      .filter(
        (account) =>
          ["owner", "member"].includes(account.label) &&
          ["created_synthetic", "reused_verified"].includes(
            account.creationStatus,
          ),
      )
      .slice(0, 2)
      .map((account) => ({
        label: account.label,
        creationStatus: account.creationStatus,
      })),
    budget: {
      reusedVerifiedSyntheticAccounts: count(
        input.budget?.reusedVerifiedSyntheticAccounts,
      )
        ? input.budget.reusedVerifiedSyntheticAccounts
        : 0,
      maxHttpRequests: input.budget?.maxHttpRequests ?? 300,
      httpRequests: input.budget?.httpRequests ?? 0,
      maxSyntheticAccounts: 2,
      syntheticAccounts: input.budget?.syntheticAccounts ?? 0,
      cleanupSessions: input.budget?.cleanupSessions ?? 0,
    },
    coverage: {
      layer: "authenticated_user_client_when_explicitly_executed",
      oneShotCausality: "not_observable_from_public_client",
      hourlyRecovery: "not_proven_by_five_minute_window",
      unverified: [
        "worker_process_interruption",
        "retry_backoff_exhaustion",
        "provider_starvation",
        "active_claimant_fanout",
        "email_push_provider_device_UI",
      ],
    },
  };
  const serialized = JSON.stringify(report);
  if (
    [...privateValues].some(
      (value) =>
        typeof value === "string" &&
        value.length >= 8 &&
        serialized.includes(value),
    )
  )
    return {
      schemaVersion: 1,
      status: "failed",
      checks: [
        {
          name: "redaction",
          status: "failed",
          code: "redaction_failure",
          assertions: 0,
        },
      ],
    };
  return report;
}
