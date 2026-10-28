/** Offline DTO/report checks. These helpers do not call or simulate Appwrite. */
import { isDeepStrictEqual } from "node:util";

const roles = new Set(["owner", "builder", "member", "viewer"]);
const grants = new Set(["builder", "member", "viewer"]);
const idPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/;
const knownCodes = new Set([
  "none",
  "unavailable",
  "unauthenticated",
  "not_found",
  "forbidden",
  "app_archived",
  "invitation_unavailable",
  "invalid_request",
  "invalid_role",
  "invalid_id",
  "invalid_name",
  "invalid_definition",
  "invalid_values",
  "revision_conflict",
  "definition_conflict",
  "operation_conflict",
  "id_conflict",
  "transaction_conflict",
  "quota_exceeded",
  "not_published",
  "row_not_found",
  "user_already_exists",
  "user_session_already_exists",
  "user_invalid_credentials",
  "general_rate_limit_exceeded",
  "project_not_found",
  "function_not_found",
  "general_unauthorized_scope",
  "general_access_forbidden",
  "table_not_found",
  "database_not_found",
  "unrecognized_error",
  "backend_unavailable",
  "method_not_allowed",
  "request_too_large",
]);
const object = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const id = (value) => typeof value === "string" && idPattern.test(value);
const revision = (value) =>
  Number.isInteger(value) && value >= 0 && value < 2_147_483_647;
const title = (value) =>
  typeof value === "string" &&
  value.trim() === value &&
  value.length > 0 &&
  value.length <= 128;

export function exactKeys(value, keys) {
  return (
    object(value) &&
    Object.keys(value).length === keys.length &&
    keys.every((key) => Object.hasOwn(value, key))
  );
}

export function validAccess(value) {
  if (
    !object(value) ||
    !roles.has(value.role) ||
    typeof value.archived !== "boolean"
  )
    return false;
  const builder = value.role === "owner" || value.role === "builder";
  return isDeepStrictEqual(value.capabilities, {
    editDefinition: builder && !value.archived,
    share: builder && !value.archived,
    writeRecords: builder && !value.archived,
    archive: value.role === "owner" && !value.archived,
    revokeAccess: builder,
  });
}

export function validSummary(value) {
  return (
    exactKeys(value, [
      "id",
      "workspaceId",
      "name",
      "role",
      "archived",
      "capabilities",
    ]) &&
    id(value.id) &&
    id(value.workspaceId) &&
    title(value.name) &&
    validAccess(value)
  );
}

export function validDocument(value) {
  if (
    !exactKeys(value, [
      "id",
      "workspaceId",
      "name",
      "role",
      "archived",
      "capabilities",
      "draftRevision",
      "candidateRevision",
      "basePublishedRevision",
      "publishedRevision",
      "definition",
      "publishedDefinition",
    ]) ||
    !id(value.id) ||
    !id(value.workspaceId) ||
    !title(value.name) ||
    !validAccess(value) ||
    ![
      value.draftRevision,
      value.candidateRevision,
      value.basePublishedRevision,
      value.publishedRevision,
    ].every(revision)
  )
    return false;
  return (
    (value.draftRevision === 0) === (value.definition === null) &&
    (value.draftRevision === 0) === (value.candidateRevision === 0) &&
    (value.publishedRevision === 0) === (value.publishedDefinition === null) &&
    (value.definition === null || object(value.definition)) &&
    (value.publishedDefinition === null || object(value.publishedDefinition)) &&
    value.basePublishedRevision <= value.publishedRevision &&
    (value.draftRevision !== 0 ||
      value.basePublishedRevision === value.publishedRevision) &&
    (!["member", "viewer"].includes(value.role) || value.draftRevision === 0)
  );
}

function instant(value) {
  if (typeof value !== "string") return NaN;
  const parts =
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3}|\d{6})(?:Z|\+00:00)$/.exec(
      value,
    );
  if (!parts) return NaN;
  const [year, month, day, hour, minute, second] = parts
    .slice(1, 7)
    .map(Number);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (
    year < 1 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > days[month - 1] ||
    hour > 23 ||
    minute > 59 ||
    second > 59
  )
    return NaN;
  return Date.parse(value);
}

export function validInvitation(value, appId) {
  return (
    exactKeys(value, [
      "id",
      "appId",
      "issuerId",
      "role",
      "recipientId",
      "createdAt",
      "expiresAt",
      "revoked",
      "acceptedBy",
    ]) &&
    [value.id, value.appId, value.issuerId].every(id) &&
    value.appId === appId &&
    grants.has(value.role) &&
    (value.recipientId === null || id(value.recipientId)) &&
    (value.acceptedBy === null || id(value.acceptedBy)) &&
    typeof value.revoked === "boolean" &&
    (value.recipientId === null ||
      value.acceptedBy === null ||
      value.recipientId === value.acceptedBy) &&
    Number.isFinite(instant(value.createdAt)) &&
    instant(value.expiresAt) - instant(value.createdAt) ===
      7 * 24 * 60 * 60 * 1000
  );
}

export function validPreview(value) {
  return (
    exactKeys(value, ["appId", "appName", "role", "expiresAt", "accepted"]) &&
    id(value.appId) &&
    title(value.appName) &&
    grants.has(value.role) &&
    typeof value.accepted === "boolean" &&
    Number.isFinite(instant(value.expiresAt))
  );
}

export function validMember(value, allowRevoked = false) {
  return (
    exactKeys(value, ["actorId", "role", "revision"]) &&
    id(value.actorId) &&
    (roles.has(value.role) || (allowRevoked && value.role === null)) &&
    revision(value.revision) &&
    (value.role === "owner" ? value.revision === 0 : value.revision > 0)
  );
}

export function validRecord(value) {
  return (
    exactKeys(value, ["id", "revision", "values"]) &&
    id(value.id) &&
    revision(value.revision) &&
    value.revision > 0 &&
    object(value.values) &&
    Object.keys(value.values).length <= 10 &&
    Object.entries(value.values).every(
      ([key, item]) =>
        /^[a-z][a-zA-Z0-9_]{0,31}$/.test(key) &&
        ((typeof item === "string" && item.length <= 4000) ||
          typeof item === "boolean" ||
          (typeof item === "number" &&
            Number.isFinite(item) &&
            Math.abs(item) <= 1e15)),
    )
  );
}

export function validRecordPage(value) {
  return (
    exactKeys(value, ["records", "definitionRevision", "nextCursor"]) &&
    Array.isArray(value.records) &&
    value.records.length <= 10 &&
    value.records.every(validRecord) &&
    new Set(value.records.map((row) => row.id)).size === value.records.length &&
    revision(value.definitionRevision) &&
    value.definitionRevision > 0 &&
    (value.nextCursor === null || id(value.nextCursor))
  );
}

export function safeCode(value) {
  return knownCodes.has(value) ? value : "unrecognized_error";
}

/** No arbitrary server strings, identifiers, links, error messages or tokens. */
export function safeObservation(value = {}) {
  const result = {};
  for (const key of [
    "httpStatus",
    "functionStatus",
    "expectedFunctionStatus",
    "revision",
    "draftRevision",
    "publishedRevision",
    "candidateRevision",
    "winnerCount",
    "invitationCount",
    "requestCount",
  ]) {
    if (Number.isSafeInteger(value[key]) && value[key] >= 0)
      result[key] = value[key];
  }
  if (Object.hasOwn(value, "code")) result.observedCode = safeCode(value.code);
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
    result.executionStatus = value.executionStatus;
  if (
    ["real_client_session", "real_function", "fresh_client_session"].includes(
      value.source,
    )
  )
    result.source = value.source;
  if (roles.has(value.role)) result.role = value.role;
  return result;
}
