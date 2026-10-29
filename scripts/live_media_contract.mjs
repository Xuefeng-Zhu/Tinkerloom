/** Pure media-probe contracts. Never performs I/O or remote requests. */
import {
  exactKeys,
  object,
  id,
  fullCodes,
  safeFullObservation,
} from "./live_full_contract.mjs";
import { byteSha, CHUNK_BYTES, MAX_BYTES } from "./live_media_fixture.mjs";
export const mediaCodes = new Set([
  ...fullCodes,
  "invalid_media",
  "media_incomplete",
  "media_busy",
  "media_expired",
  "media_state_conflict",
  "media_integrity",
  "access_changed",
  "storage_file_not_found",
  "storage_bucket_not_found",
  "general_argument_invalid",
  "general_route_not_found",
]);
export const mediaProbeCodes = new Set([
  "assertion_failed",
  "prerequisite_failed",
  "configuration_invalid",
  "provenance_required",
  "unsupported_argument",
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
  "http_budget_exhausted",
  "no_assertions_executed",
  "unexpected_probe_error",
  "report_secret_scan_failed",
  "report_persistence_failed",
  "media_ready_timeout",
  "fixture_invalid",
  "quiet_period_not_elapsed",
]);
export class MediaProbeError extends Error {
  constructor(code, observation = {}) {
    super(mediaProbeCodes.has(code) ? code : "unexpected_probe_error");
    this.code = this.message;
    this.observation = observation;
  }
}
const integer = (n, max = 2147483646) =>
  Number.isSafeInteger(n) && n >= 0 && n <= max;
export const digest = (s) => typeof s === "string" && /^[a-f0-9]{64}$/.test(s);
const dimensions = (v) =>
  integer(v.width, 2048) &&
  v.width > 0 &&
  integer(v.height, 2048) &&
  v.height > 0 &&
  v.width * v.height <= 16000000;
export function validAsset(value, expectedId) {
  if (
    !object(value) ||
    !id(value.assetId) ||
    (expectedId && value.assetId !== expectedId)
  )
    return false;
  if (value.status === "ready")
    return (
      exactKeys(value, [
        "assetId",
        "status",
        "contentType",
        "byteLength",
        "width",
        "height",
        "sha256",
      ]) &&
      ["image/png", "image/jpeg"].includes(value.contentType) &&
      integer(value.byteLength, MAX_BYTES) &&
      value.byteLength > 0 &&
      dimensions(value) &&
      digest(value.sha256)
    );
  if (!["pending", "queued", "processing", "failed"].includes(value.status))
    return false;
  return (
    exactKeys(value, [
      "assetId",
      "status",
      "uploadedBytes",
      "inputBytes",
      ...(value.status === "failed" ? ["error"] : []),
    ]) &&
    integer(value.inputBytes, MAX_BYTES) &&
    value.inputBytes > 0 &&
    integer(value.uploadedBytes, value.inputBytes) &&
    (value.uploadedBytes === value.inputBytes ||
      value.uploadedBytes % CHUNK_BYTES === 0) &&
    (value.status !== "failed" ||
      ["invalid_media", "access_changed"].includes(value.error))
  );
}
export function validBegin(value, inputLength) {
  return (
    exactKeys(value, ["asset", "chunkBytes", "expiresAt"]) &&
    validAsset(value.asset) &&
    value.asset.status === "pending" &&
    value.asset.uploadedBytes === 0 &&
    value.asset.inputBytes === inputLength &&
    value.chunkBytes === CHUNK_BYTES &&
    typeof value.expiresAt === "string" &&
    /Z$/.test(value.expiresAt) &&
    Number.isFinite(Date.parse(value.expiresAt))
  );
}
export function validChunkAck(value, assetId, expectedBytes) {
  return (
    exactKeys(value, ["assetId", "uploadedBytes"]) &&
    value.assetId === assetId &&
    value.uploadedBytes === expectedBytes
  );
}
export function validUsage(value) {
  return (
    exactKeys(value, [
      "reservedBytes",
      "assetCount",
      "pendingReleaseBytes",
      "maximumBytes",
      "maximumAssets",
    ]) &&
    integer(value.reservedBytes, 250 * 1024 * 1024) &&
    integer(value.assetCount, 500) &&
    integer(value.pendingReleaseBytes, value.reservedBytes) &&
    value.maximumBytes === 250 * 1024 * 1024 &&
    value.maximumAssets === 500
  );
}
export function decodeReadChunk(
  value,
  { assetId, variant, offset, previous } = {},
) {
  if (
    !exactKeys(value, [
      "assetId",
      "variant",
      "offset",
      "nextOffset",
      "byteLength",
      "contentType",
      "sha256",
      "chunkSha256",
      "dataBase64",
      "width",
      "height",
      "cacheControl",
    ]) ||
    value.assetId !== assetId ||
    value.variant !== variant ||
    value.offset !== offset ||
    !integer(offset, MAX_BYTES) ||
    offset % CHUNK_BYTES ||
    !integer(
      value.byteLength,
      variant === "thumbnail" ? 512 * 1024 : MAX_BYTES,
    ) ||
    value.byteLength < 1 ||
    offset >= value.byteLength ||
    !["image/png", "image/jpeg"].includes(value.contentType) ||
    !dimensions(value) ||
    !digest(value.sha256) ||
    !digest(value.chunkSha256) ||
    value.cacheControl !== "private, no-store" ||
    typeof value.dataBase64 !== "string" ||
    value.dataBase64.length > Math.ceil(CHUNK_BYTES / 3) * 4
  )
    throw new MediaProbeError("assertion_failed");
  const bytes = Buffer.from(value.dataBase64, "base64"),
    end = Math.min(offset + CHUNK_BYTES, value.byteLength);
  if (
    bytes.toString("base64") !== value.dataBase64 ||
    bytes.length !== end - offset ||
    byteSha(bytes) !== value.chunkSha256 ||
    value.nextOffset !== (end === value.byteLength ? null : end)
  )
    throw new MediaProbeError("assertion_failed");
  if (
    previous &&
    [
      "assetId",
      "variant",
      "byteLength",
      "contentType",
      "sha256",
      "width",
      "height",
    ].some((k) => previous[k] !== value[k])
  )
    throw new MediaProbeError("assertion_failed");
  return bytes;
}
export function cacheHeader(result) {
  const headers = result?.outer?.data?.responseHeaders;
  if (!object(headers)) return null;
  const values = Object.entries(headers).filter(
    ([k]) => k.toLowerCase() === "cache-control",
  );
  return values.length === 1 ? values[0][1] : null;
}
export function safeObservation(value = {}) {
  const output = safeFullObservation({
    ...value,
    code: undefined,
    backendCode: undefined,
  });
  for (const key of [
    "byteLength",
    "uploadedBytes",
    "chunks",
    "polls",
    "width",
    "height",
    "reservedBytes",
    "pendingReleaseBytes",
    "assetCount",
    "elapsedMs",
    "httpRequests",
    "readConflicts",
    "publicWorkerDenials",
    "forgedWorkerHeaderRejections",
    "forgedWorkerPermissionDenials",
  ])
    if (integer(value[key], 1e9)) output[key] = value[key];
  // A check's code is a probe failure category, not a backend response code.
  // Prefer already-sanitized backendCode so repeated sanitization is lossless.
  const code =
    value.backendCode ??
    (mediaProbeCodes.has(value.code) ? undefined : value.code);
  if (code !== undefined)
    output.backendCode = mediaCodes.has(code) ? code : "unrecognized_error";
  for (const key of ["sha256", "displaySha256", "thumbnailSha256"])
    if (digest(value[key])) output[key] = value[key];
  return output;
}
/** Media errors have their own allowlist; the full-engine observer must not erase them. */
export function mediaFunctionObservation(result) {
  const code = result?.data?.error ?? result?.outer?.data?.type ?? "none";
  return {
    ...safeFullObservation({
      httpStatus: result?.outer?.status,
      functionStatus: result?.status,
      executionStatus: result?.executionStatus,
    }),
    code: mediaCodes.has(code) ? code : "unrecognized_error",
  };
}
export function isStatusReadConflict(result) {
  return (
    Number.isInteger(result?.outer?.status) &&
    result.outer.status >= 200 &&
    result?.outer?.status < 300 &&
    result?.deploymentMatched === true &&
    result?.executionStatus === "completed" &&
    result?.status === 409 &&
    exactKeys(result?.data, ["error"]) &&
    result.data.error === "transaction_conflict"
  );
}
/** A 400 is header-validation evidence only for an explicitly forged-header request. */
export function workerExecutionRejection(
  result,
  { forgedReservedHeaders = false } = {},
) {
  if (
    storageDenied(result, { kind: "function" }) &&
    [401, 403].includes(result.status)
  )
    return "execution_permission_denied";
  if (
    forgedReservedHeaders &&
    result.status === 400 &&
    safeErrorEnvelope(result.data) &&
    result.data.code === 400 &&
    result.data.type === "general_argument_invalid" &&
    typeof result.data.message === "string" &&
    /headers/i.test(result.data.message) &&
    /start with ["']x-appwrite(?:-["']|["'])/i.test(result.data.message)
  )
    return "reserved_headers_rejected_before_execution";
  return null;
}
export function safeErrorEnvelope(value) {
  return (
    object(value) &&
    Object.keys(value).every((k) =>
      ["message", "code", "type", "version", "error"].includes(k),
    ) &&
    Object.entries(value).every(([k, v]) =>
      k === "code"
        ? Number.isInteger(v) && v >= 100 && v <= 599
        : typeof v === "string" && v.length <= 10000,
    )
  );
}
export function storageDenied(result, { kind, knownExisting = false } = {}) {
  if (!safeErrorEnvelope(result.data)) return false;
  if (
    [
      "project_not_found",
      "database_not_found",
      "table_not_found",
      "function_not_found",
    ].includes(result.data.type)
  )
    return false;
  return (
    [401, 403].includes(result.status) ||
    (knownExisting &&
      result.status === 404 &&
      result.data.type ===
        (kind === "file"
          ? "storage_file_not_found"
          : "storage_bucket_not_found"))
  );
}
export const checkNames = new Set([
  "fixture_maximum_png",
  "authenticate_owner",
  "authenticate_outsider",
  "zero_provider_reminder_capabilities",
  "create_private_draft_and_foreign_app",
  "maximum_begin_exact_receipt_and_conflict",
  "pending_asset_privacy",
  "twenty_chunks_exact_retry_conflict_and_complete",
  "private_worker_ready",
  "maximum_variants_full_bytes_headers_pixels",
  "draft_reference_review_publication_and_record",
  "published_action_upload_orientation",
  "orientation_private_worker_ready_and_full_variants",
  "unshared_cross_actor_and_cross_app_denials",
  "grant_viewer_read_and_upload_denial",
  "builder_own_upload_receipt_current_authority",
  "direct_private_storage_table_read_write_denials",
  "revoke_current_access_and_receipt_denial",
  "private_worker_public_execution_and_forged_proof_denial",
  "usage_staging_reservation_retained",
  "optional_quiet_period_release",
  "report_secret_scan",
  "probe_setup",
  "probe_configuration",
  "temporary_session_signout_owner",
  "temporary_session_signout_outsider",
]);
export function sanitizedReport(report, privateValues = new Set()) {
  const clean = {
    schemaVersion: 1,
    mode: "live_media_worker_probe",
    runId: /^qa-media-[a-z0-9]+-[a-f0-9]{8}$/.test(report.runId)
      ? report.runId
      : "qa-media-unknown-00000000",
    startedAt: Number.isFinite(Date.parse(report.startedAt))
      ? report.startedAt
      : null,
    completedAt: Number.isFinite(Date.parse(report.completedAt))
      ? report.completedAt
      : null,
    status: report.status === "passed" ? "passed" : "failed",
    target: {},
    accounts: [],
    resources: {},
    checks: [],
    budget: {},
    coverage: {
      layer: "Authenticated REST only when explicitly executed against Cloud.",
      workerDeploymentObserved: false,
      sourceAttestation: "operator_supplied_not_server_attested",
      workerReadiness: "ready_state_indirect_evidence_only",
      providerCallsIntended: 0,
      remindersEnabledIntended: false,
      resourceDeletionIntended: false,
      unverified: [
        "Exact private-worker deployment/source/configuration is operator-attested; readiness alone does not attest its deployment ID.",
        "No provider calls, reminder scheduling/delivery, native/browser UI, server clocks or resource deletion are exercised.",
        "5 MiB valid padded PNG proves byte transport; it is a small image and does not prove worst-case 16MP memory/decode acceptance.",
        "Storage hydration reads the whole variant per response chunk; this is not a Cloud bandwidth/performance pass.",
        "16-minute quiet-period release is pending unless the explicit bounded optional phase observes it; unreferenced ready assets remain through normal retention.",
      ],
    },
  };
  const t = report.target ?? {};
  for (const key of ["endpoint", "origin"]) {
    try {
      const u = new URL(t[key]);
      if (
        !u.username &&
        !u.password &&
        !u.search &&
        !u.hash &&
        ["https:", "http:"].includes(u.protocol)
      )
        clean.target[key] = u.href.replace(/\/$/, "");
    } catch {}
  }
  for (const key of [
    "projectId",
    "functionId",
    "databaseId",
    "bucketId",
    "workerFunctionId",
    "coreDeploymentId",
    "workerDeploymentId",
  ])
    clean.target[key] = id(t[key]) ? t[key] : null;
  for (const key of ["sourceCommit", "workerSourceCommit"])
    clean.target[key] =
      typeof t[key] === "string" && /^[a-f0-9]{7,40}$/.test(t[key])
        ? t[key]
        : null;
  for (const key of ["sourceSha256", "workerSourceSha256"])
    clean.target[key] = digest(t[key]) ? t[key] : null;
  clean.target.coreDeploymentMatchedExecutions = integer(
    t.coreDeploymentMatchedExecutions,
  )
    ? t.coreDeploymentMatchedExecutions
    : 0;
  clean.accounts = (report.accounts ?? [])
    .filter((a) => ["owner", "outsider"].includes(a.label))
    .map((a) => ({
      label: a.label,
      id: id(a.id) ? a.id : null,
      creationStatus:
        a.creationStatus === "created" ? "created" : "unconfirmed",
    }));
  for (const key of [
    "workspaceId",
    "appId",
    "foreignAppId",
    "maximumAssetId",
    "orientationAssetId",
    "revokedAssetId",
    "recordId",
    "versionId",
  ])
    if (id(report.resources?.[key]))
      clean.resources[key] = report.resources[key];
  clean.checks = (report.checks ?? []).map((c) => ({
    name: checkNames.has(c.name) ? c.name : "probe_setup",
    status: ["passed", "failed", "blocked", "pending"].includes(c.status)
      ? c.status
      : "failed",
    assertions: integer(c.assertions) ? c.assertions : 0,
    ...(mediaProbeCodes.has(c.code) ? { code: c.code } : {}),
    ...safeObservation(c),
  }));
  for (const key of [
    "maxHttpRequests",
    "reservedCleanupRequests",
    "httpRequests",
    "peakConcurrentHttp",
    "syntheticAccountsAttempted",
    "maxSyntheticAccounts",
    "readyPollLimit",
    "readConflicts",
  ])
    clean.budget[key] = integer(report.budget?.[key]) ? report.budget[key] : 0;
  const serialized = JSON.stringify(clean);
  if (
    [...privateValues].some(
      (v) => typeof v === "string" && v.length > 12 && serialized.includes(v),
    )
  ) {
    clean.target = {};
    clean.accounts = [];
    clean.resources = {};
    clean.status = "failed";
    clean.checks = clean.checks.map((c) => ({
      name: c.name,
      status: c.status,
      assertions: c.assertions,
    }));
    clean.checks.push({
      name: "report_secret_scan",
      status: "failed",
      assertions: 1,
      code: "report_secret_scan_failed",
    });
  }
  clean.summary = Object.fromEntries(
    ["passed", "failed", "blocked", "pending"].map((s) => [
      s,
      clean.checks.filter((c) => c.status === s).length,
    ]),
  );
  clean.summary.assertions = clean.checks.reduce((n, c) => n + c.assertions, 0);
  return clean;
}
