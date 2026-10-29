/** Pure offline contracts/report allowlists. No SDK, credentials or network. */
import { createHash } from "node:crypto";
import { isDeepStrictEqual } from "node:util";
import { exactKeys } from "./live_collaboration_contract.mjs";
export { exactKeys };
export const object = (v) =>
  v !== null && typeof v === "object" && !Array.isArray(v);
export const id = (v) =>
  typeof v === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(v);
const stableId = (v) =>
  typeof v === "string" && /^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(v);
const revision = (v) => Number.isSafeInteger(v) && v >= 0 && v < 2147483647;
const hash = (v) => typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
const nullableId = (v) => v === null || id(v);
export const canonical = (value) =>
  JSON.stringify(value, (_, v) =>
    object(v)
      ? Object.fromEntries(
          Object.keys(v)
            .sort()
            .map((k) => [k, v[k]]),
        )
      : v,
  );
export const sha = (value) =>
  createHash("sha256").update(canonical(value)).digest("hex");
export const identity = (prefix, parts) => prefix + sha(parts).slice(0, 32);
export const fullCodes = new Set([
  "none",
  "unrecognized_error",
  "unavailable",
  "unauthenticated",
  "forbidden",
  "not_found",
  "app_archived",
  "invalid_request",
  "invalid_id",
  "invalid_name",
  "invalid_values",
  "invalid_spec",
  "invalid_definition",
  "invalid_role",
  "revision_conflict",
  "definition_conflict",
  "operation_conflict",
  "id_conflict",
  "transaction_conflict",
  "exhausted_capacity",
  "quota_exceeded",
  "not_published",
  "capability_unavailable",
  "provider_unavailable",
  "generation_pending",
  "invitation_unavailable",
  "row_not_found",
  "table_not_found",
  "database_not_found",
  "function_not_found",
  "project_not_found",
  "general_rate_limit_exceeded",
  "general_unauthorized_scope",
  "general_access_forbidden",
  "user_already_exists",
  "user_session_already_exists",
  "user_invalid_credentials",
  "request_too_large",
  "response_too_large",
  "backend_unavailable",
  "method_not_allowed",
]);
export const safeFullCode = (code, fallback = "unrecognized_error") =>
  fullCodes.has(code) ? code : fallback;
export const probeCodes = new Set([
  "assertion_failed",
  "http_budget_exhausted",
  "request_transport_failure",
  "response_transport_failure",
  "response_too_large",
  "response_not_json",
  "response_not_utf8",
  "request_too_large",
  "node_cookie_api_unavailable",
  "invalid_session_cookie",
  "execution_response_invalid",
  "function_response_not_json",
  "configuration_invalid",
  "unsupported_argument",
  "provenance_required",
  "auth_rate_limit_cooldown_unknown",
  "auth_rate_limit_wait_budget_exceeded",
  "auth_rate_limit_attempts_exhausted",
  "unexpected_probe_error",
  "prerequisite_failed",
  "report_secret_scan_failed",
  "report_persistence_failed",
  "no_assertions_executed",
]);
export class FullProbeError extends Error {
  constructor(code, observation = {}) {
    super(probeCodes.has(code) ? code : "unexpected_probe_error");
    this.code = probeCodes.has(code) ? code : "unexpected_probe_error";
    this.observation = observation;
  }
}
export function safeFullObservation(value = {}) {
  const output = {};
  for (const key of ["httpStatus", "functionStatus", "expectedFunctionStatus"])
    if (Number.isInteger(value[key]) && value[key] >= 100 && value[key] <= 599)
      output[key] = value[key];
  for (const key of [
    "assertionIndex",
    "attempts",
    "distinctActors",
    "uniqueOperations",
    "successResponses",
    "claimedActors",
    "allocated",
    "capacity",
    "records",
    "pages",
    "versions",
    "templates",
    "peakConcurrentHttp",
    "httpRequests",
    "cooldownMs",
    "rowDenials",
  ])
    if (
      Number.isSafeInteger(value[key]) &&
      value[key] >= 0 &&
      value[key] <= 1000000
    )
      output[key] = value[key];
  if (value.code !== undefined) output.backendCode = safeFullCode(value.code);
  if (value.backendCode !== undefined)
    output.backendCode = safeFullCode(value.backendCode);
  if (
    [
      "completed",
      "failed",
      "processing",
      "waiting",
      "scheduled",
      "unavailable",
    ].includes(value.executionStatus)
  )
    output.executionStatus = value.executionStatus;
  return output;
}
export function validSpec(value) {
  return (
    object(value) &&
    value.formatVersion === 1 &&
    typeof value.name === "string" &&
    value.name.length > 0 &&
    value.name.length <= 128 &&
    ["teal", "amber", "blue", "rose", "sage"].includes(value.theme) &&
    ["book", "board", "people", "spark", "check"].includes(value.icon) &&
    Array.isArray(value.requires) &&
    value.requires.every((v) => typeof v === "string") &&
    Array.isArray(value.collections) &&
    value.collections.length <= 8 &&
    Array.isArray(value.views) &&
    value.views.length <= 16 &&
    Array.isArray(value.actions) &&
    value.actions.length <= 32 &&
    Array.isArray(value.automationRequests) &&
    value.automationRequests.length <= 10 &&
    [
      "personalTracker.v1",
      "groupWorkflow.v1",
      "groupCapacitySignup.v1",
    ].includes(value.policyPresetRequest) &&
    Object.keys(value).every((k) =>
      [
        "formatVersion",
        "name",
        "theme",
        "icon",
        "requires",
        "collections",
        "views",
        "actions",
        "automationRequests",
        "policyPresetRequest",
        "navigation",
        "appearance",
      ].includes(k),
    )
  );
}
export function validAccess(app) {
  if (
    !object(app) ||
    !["owner", "builder", "member", "viewer"].includes(app.role) ||
    typeof app.archived !== "boolean" ||
    !Array.isArray(app.allowedActions) ||
    !app.allowedActions.every(stableId)
  )
    return false;
  const builder = ["owner", "builder"].includes(app.role);
  return isDeepStrictEqual(app.capabilities, {
    editDefinition: builder && !app.archived,
    share: builder && !app.archived,
    writeRecords: app.allowedActions.length > 0,
    archive: app.role === "owner" && !app.archived,
    revokeAccess: builder,
  });
}
export function validFullApp(app) {
  if (
    !exactKeys(app, [
      "id",
      "workspaceId",
      "name",
      "engine",
      "role",
      "archived",
      "capabilities",
      "allowedActions",
      "generation",
      "controlRevision",
      "version",
      "draft",
    ]) ||
    !id(app.id) ||
    !id(app.workspaceId) ||
    app.engine !== "appspec.v1" ||
    typeof app.name !== "string" ||
    !revision(app.controlRevision) ||
    !validAccess(app) ||
    app.generation !== null
  )
    return false;
  const version = app.version,
    draft = app.draft;
  if (
    version !== null &&
    (!exactKeys(version, ["id", "number", "hash", "spec"]) ||
      !id(version.id) ||
      !revision(version.number) ||
      version.number < 1 ||
      !hash(version.hash) ||
      !validSpec(version.spec))
  )
    return false;
  if (
    draft !== null &&
    (!exactKeys(draft, [
      "revision",
      "baseVersionId",
      "candidateHash",
      "publishedVersionId",
      "spec",
    ]) ||
      !revision(draft.revision) ||
      draft.revision < 1 ||
      !nullableId(draft.baseVersionId) ||
      !nullableId(draft.publishedVersionId) ||
      !hash(draft.candidateHash) ||
      !validSpec(draft.spec))
  )
    return false;
  return !["member", "viewer"].includes(app.role) || draft === null;
}
export function validReview(review) {
  return (
    exactKeys(review, [
      "candidateHash",
      "expectedRevision",
      "baseVersionId",
      "currentVersionId",
      "reviewHash",
      "changes",
      "compatibilityErrors",
      "enabledRuleIds",
      "activateExistingRecordIds",
    ]) &&
    hash(review.candidateHash) &&
    hash(review.reviewHash) &&
    revision(review.expectedRevision) &&
    nullableId(review.baseVersionId) &&
    nullableId(review.currentVersionId) &&
    Array.isArray(review.changes) &&
    review.changes.every((v) => typeof v === "string") &&
    Array.isArray(review.compatibilityErrors) &&
    review.compatibilityErrors.every((v) => typeof v === "string") &&
    Array.isArray(review.enabledRuleIds) &&
    review.enabledRuleIds.every(stableId) &&
    Array.isArray(review.activateExistingRecordIds) &&
    review.activateExistingRecordIds.every(id) &&
    review.reviewHash ===
      sha({
        candidateHash: review.candidateHash,
        enabledRuleIds: [...review.enabledRuleIds].sort(),
        activateExistingRecordIds: [...review.activateExistingRecordIds].sort(),
      })
  );
}
export function validRuntimeRecord(record, collectionId) {
  return (
    exactKeys(record, [
      "id",
      "collectionId",
      "data",
      "revision",
      "writtenUnderVersionId",
      "capacity",
      "allocated",
      "claimed",
      "allowedActions",
    ]) &&
    id(record.id) &&
    stableId(record.collectionId) &&
    (!collectionId || record.collectionId === collectionId) &&
    object(record.data) &&
    Object.values(record.data).every(
      (v) =>
        typeof v === "string" ||
        typeof v === "boolean" ||
        (typeof v === "number" && Number.isFinite(v) && Math.abs(v) <= 1e15),
    ) &&
    revision(record.revision) &&
    record.revision > 0 &&
    id(record.writtenUnderVersionId) &&
    (record.capacity === null
      ? record.allocated === null && record.claimed === false
      : revision(record.capacity) &&
        record.capacity <= 10000 &&
        revision(record.allocated) &&
        record.allocated <= record.capacity) &&
    typeof record.claimed === "boolean" &&
    Array.isArray(record.allowedActions) &&
    record.allowedActions.every(stableId)
  );
}
export function validRuntimePage(page, version, collection) {
  return (
    exactKeys(page, ["records", "total", "nextCursor", "versionId"]) &&
    page.versionId === version &&
    revision(page.total) &&
    Array.isArray(page.records) &&
    page.records.length <= 100 &&
    page.records.every((r) => validRuntimeRecord(r, collection)) &&
    new Set(page.records.map((r) => r.id)).size === page.records.length &&
    (page.nextCursor === null ||
      (typeof page.nextCursor === "string" &&
        page.nextCursor.length > 0 &&
        page.nextCursor.length <= 65536))
  );
}
export function validOutcome(data) {
  return (
    exactKeys(data, ["outcome"]) &&
    exactKeys(data.outcome, ["recordId", "revision", "message"]) &&
    id(data.outcome.recordId) &&
    revision(data.outcome.revision) &&
    data.outcome.revision > 0 &&
    data.outcome.message === "Saved"
  );
}
export function validVersion(value, withSpec = false) {
  return (
    exactKeys(value, [
      "id",
      "number",
      "hash",
      "name",
      "theme",
      "icon",
      "publisherId",
      "createdAt",
      ...(withSpec ? ["spec"] : []),
    ]) &&
    id(value.id) &&
    revision(value.number) &&
    value.number > 0 &&
    hash(value.hash) &&
    typeof value.name === "string" &&
    typeof value.theme === "string" &&
    typeof value.icon === "string" &&
    id(value.publisherId) &&
    (value.createdAt === null ||
      (typeof value.createdAt === "string" &&
        Number.isFinite(Date.parse(value.createdAt)))) &&
    (!withSpec || validSpec(value.spec))
  );
}
export function validAggregate(data, version) {
  return (
    exactKeys(data, ["total", "value", "groups", "versionId"]) &&
    data.versionId === version &&
    revision(data.total) &&
    (data.value === null ||
      (typeof data.value === "number" && Number.isFinite(data.value))) &&
    Array.isArray(data.groups) &&
    data.groups.every(
      (g) =>
        exactKeys(g, ["key", "count", "value"]) &&
        typeof g.key === "string" &&
        revision(g.count) &&
        (g.value === null ||
          (typeof g.value === "number" && Number.isFinite(g.value))),
    )
  );
}
const knownChecks = new Set([
  "create_owner_and_foreign_workspaces",
  "catalog_and_operational_capabilities",
  "manual_empty_shell_and_exact_review_publication",
  "private_author_drafts_and_global_stale_publication",
  "exact_definition_receipts_survive_newer_publication_and_changed_input_conflicts",
  "private_drafts_do_not_leak_to_member_or_viewer",
  "seed_115_typed_records_and_exact_create_receipt",
  "owner_builder_member_viewer_and_outsider_personal_policy",
  "ranked_pages_and_global_numeric_aggregates",
  "workflow_assignment_and_protected_fields",
  "capacity_create_policy_timestamp_and_date_bucket_boundaries",
  "explicit_twenty_actor_auth_pool",
  "twenty_concurrent_unique_final_capacity_attempts",
  "capacity_receipt_counter_release_reactivation_and_configuration",
  "numeric_rejections_leave_record_population_unchanged",
  "immutable_history_remix_and_actor_private_pins",
  "template_instances_have_no_copied_records",
  "cross_workspace_and_parent_substitution_denials",
  "known_existing_private_rows_and_direct_write_are_denied",
  "fresh_cookie_session_reloads_persisted_versions_and_records",
  "archive_keeps_exact_receipts_but_blocks_new_writes",
  "probe_setup",
  "probe_configuration",
  "report_secret_scan",
]);
const templates = [
  "planner",
  "projectHub",
  "volunteer",
  "reading",
  "habitTracker",
  "calendar",
  "notes",
  "chores",
  "photoJournal",
  "reminders",
  "focus",
  "phoneToolkit",
];
function checkName(name) {
  return knownChecks.has(name) ||
    /^authenticate_(owner|builder|member|viewer|outsider)$/.test(name) ||
    /^join_reading_as_(builder|member|viewer)$/.test(name) ||
    templates.some((key) => name === "instantiate_" + key) ||
    /^grant_roles_(chores|volunteer)$/.test(name) ||
    /^temporary_session_signout_\d{1,2}$/.test(name)
    ? name
    : "unrecognized_check";
}
const safeCount = (value) =>
  Number.isSafeInteger(value) && value >= 0 && value <= 1000000 ? value : 0;
function safeTarget(value) {
  if (!object(value)) return null;
  const output = {};
  for (const key of ["endpoint", "origin"])
    try {
      const url = new URL(value[key]);
      if (
        !url.username &&
        !url.password &&
        !url.search &&
        !url.hash &&
        ["https:", "http:"].includes(url.protocol)
      )
        output[key] = value[key];
    } catch {}
  for (const key of [
    "projectId",
    "functionId",
    "databaseId",
    "coreDeploymentId",
    "workerDeploymentId",
    "workerFunctionId",
  ])
    output[key] = id(value[key]) ? value[key] : null;
  output.sourceCommit =
    typeof value.sourceCommit === "string" &&
    /^[0-9a-f]{7,40}$/.test(value.sourceCommit)
      ? value.sourceCommit
      : null;
  output.sourceSha256 = hash(value.sourceSha256) ? value.sourceSha256 : null;
  output.sourceAttestation = "operator_supplied_not_server_attested";
  output.databaseBinding = "operator_supplied_not_server_attested";
  output.workerDeploymentObserved = false;
  output.coreDeploymentMatchedExecutions = safeCount(
    value.coreDeploymentMatchedExecutions,
  );
  return output;
}
export function isFullPrivateRowDenied(
  result,
  { knownExistingRow = false } = {},
) {
  const allowed = ["message", "code", "type", "version", "error"];
  return (
    object(result.data) &&
    ![
      "database_not_found",
      "table_not_found",
      "project_not_found",
      "function_not_found",
    ].includes(result.data.type) &&
    Object.keys(result.data).every((key) => allowed.includes(key)) &&
    ([401, 403].includes(result.status) ||
      (knownExistingRow &&
        result.status === 404 &&
        result.data.type === "row_not_found"))
  );
}
export function safeFinalReport(report, privateValues) {
  const checks = (report.checks ?? []).map((check) => ({
    name: checkName(check.name),
    status: ["passed", "failed", "blocked"].includes(check.status)
      ? check.status
      : "failed",
    assertions: safeCount(check.assertions),
    ...(check.durationMs === undefined
      ? {}
      : { durationMs: safeCount(check.durationMs) }),
    ...(check.code === undefined
      ? {}
      : {
          code: probeCodes.has(check.code)
            ? check.code
            : "unexpected_probe_error",
        }),
    ...safeFullObservation({ ...check, code: undefined }),
  }));
  const resources = {};
  for (const key of [
    "workspaceId",
    "foreignWorkspace",
    "readingId",
    "capacityRecord",
    "foreignAppId",
    "firstRecordId",
  ])
    if (id(report.resources?.[key])) resources[key] = report.resources[key];
  if (object(report.resources?.templateApps))
    resources.templateApps = Object.fromEntries(
      templates
        .filter((key) => id(report.resources.templateApps[key]))
        .map((key) => [key, report.resources.templateApps[key]]),
    );
  const clean = {
    schemaVersion: 1,
    runId: /^qa-full-[a-z0-9]+-[0-9a-f]{8}$/.test(report.runId)
      ? report.runId
      : "qa-full-unknown-00000000",
    startedAt:
      typeof report.startedAt === "string" &&
      Number.isFinite(Date.parse(report.startedAt))
        ? report.startedAt
        : null,
    completedAt:
      typeof report.completedAt === "string" &&
      Number.isFinite(Date.parse(report.completedAt))
        ? report.completedAt
        : null,
    status: report.status === "passed" ? "passed" : "failed",
    target: safeTarget(report.target),
    accounts: (report.accounts ?? [])
      .filter(
        (value) =>
          ["owner", "builder", "member", "viewer", "outsider"].includes(
            value.label,
          ) || /^capacity_\d{2}$/.test(value.label),
      )
      .map((value) => ({
        label: value.label,
        id: id(value.id) ? value.id : null,
        creationStatus:
          value.creationStatus === "created" ? "created" : "unconfirmed",
      })),
    resources,
    checks,
    budget: Object.fromEntries(
      [
        "maxHttpRequests",
        "maxSyntheticAccounts",
        "maxInvitationsPerIssuer",
        "httpRequests",
        "peakConcurrentHttp",
        "syntheticAccountsAttempted",
        "invitationsIssued",
      ].map((key) => [key, safeCount(report.budget?.[key])]),
    ),
    capacityTrial: {
      ...Object.fromEntries(
        [
          "submittedAttempts",
          "uniqueOperationIds",
          "distinctAuthenticatedActors",
          "peakConcurrentHttp",
          "successResponses",
          "distinctClaimedActors",
          "committedAllocationObserved",
        ].map((key) => [key, safeCount(report.capacityTrial?.[key])]),
      ),
      serverExecutionBarrier: false,
    },
    coverage: {
      layer:
        "Real authenticated REST only when this script is explicitly run against Cloud.",
      unverified: [
        "Provider spend/generation, reminders, media, spec.watch, UI/native behavior, maximum Cloud bodies, server execution barriers and production scale are not covered.",
        "Declared source/worker deployment provenance and private database binding are not server-attested.",
        "No resource/account/record deletion; temporary probe sessions are signed out.",
      ],
    },
  };
  if (
    [...privateValues].some(
      (value) =>
        typeof value === "string" &&
        value.length > 12 &&
        JSON.stringify(clean).includes(value),
    )
  ) {
    clean.target = null;
    clean.accounts = [];
    clean.resources = {};
    clean.status = "failed";
    clean.securityFailure = "report_secret_scan_failed";
    clean.checks = clean.checks.map((check) => ({
      name: check.name,
      status: check.status,
      assertions: check.assertions,
      code: "report_secret_scan_failed",
    }));
    clean.checks.push({
      name: "report_secret_scan",
      status: "failed",
      assertions: 1,
      code: "report_secret_scan_failed",
    });
  }
  clean.summary = {
    passed: clean.checks.filter((v) => v.status === "passed").length,
    failed: clean.checks.filter((v) => v.status === "failed").length,
    blocked: clean.checks.filter((v) => v.status === "blocked").length,
    assertions: clean.checks.reduce((sum, v) => sum + v.assertions, 0),
  };
  return clean;
}
