/** Offline-safe, identifier-free observer. Importing performs no network I/O. */
export const diagnosticCategories = Object.freeze([
  "stagingConflict",
  "commitBodyAccepted",
  "commitBodyRejected",
  "commitResponseOther",
  "terminalLookupDenied",
  "terminalLookupUnavailable",
  "terminalIdentityMismatch",
  "terminalNotConfirmed",
  "abortConfirmed",
  "retryStarted",
  "retryExhausted",
  "retryNotEnabled",
  "cleanupUnconfirmed",
]);
export const operationNames = Object.freeze([
  "createWorkspace",
  "listWorkspaces",
  "createApp",
  "listApps",
  "getAppAccess",
  "getApp",
  "saveDraft",
  "publishApp",
  "listRecords",
  "saveRecord",
  "createInvitation",
  "acceptInvitation",
  "inspectInvitation",
  "listInvitations",
  "revokeInvitation",
  "listMembers",
  "setGrant",
  "archiveApp",
  "spec.capabilities",
  "spec.templates",
  "spec.createApp",
  "spec.instantiate",
  "spec.remix",
  "spec.launcher",
  "spec.appAccess",
  "spec.listDrafts",
  "spec.listVersions",
  "spec.getVersion",
  "spec.setPinned",
  "spec.saveDraft",
  "spec.review",
  "spec.publish",
  "spec.watch",
  "spec.getApp",
  "spec.execute",
  "spec.query",
  "spec.summary",
  "spec.aggregate",
  "spec.getRecord",
  "spec.generate",
  "spec.getGeneration",
  "spec.keepPrevious",
  "spec.guidance",
  "spec.reminderState",
  "spec.inbox",
  "spec.readNotification",
  "spec.runs",
  "spec.listActivity",
  "spec.media.begin",
  "spec.media.chunk",
  "spec.media.complete",
  "spec.media.status",
  "spec.media.read",
  "spec.media.usage",
]);
export const errorCodes = Object.freeze([
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
export const observerLimits = Object.freeze({
  requestBytes: 256 * 1024,
  responseBytes: 1024 * 1024,
  functionBodyBytes: 64 * 1024,
  logBytes: 16 * 1024,
  diagnosticEventsPerExecution: 12,
  conflictEvents: 80,
  pendingInspections: 8,
  inspectionMilliseconds: 2500,
  counter: 1_000_000,
});

const operations = new Set(operationNames),
  categories = new Set(diagnosticCategories),
  codes = new Set(errorCodes);
const statuses = new Set([
  200, 201, 202, 204, 400, 401, 403, 404, 405, 408, 409, 413, 422, 429, 500,
  502, 503, 504,
]);
const executionStatuses = new Set([
  "waiting",
  "processing",
  "completed",
  "failed",
  "scheduled",
]);
const encoder = new TextEncoder();
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const zeroes = (names) => Object.fromEntries(names.map((name) => [name, 0]));
const status = (v) => (statuses.has(v) ? String(v) : "other");
const increment = (map, key, amount = 1) => {
  map[key] = Math.min(observerLimits.counter, map[key] + amount);
};

function textBytes(value, limit) {
  if (typeof value === "string") {
    // UTF-8 bytes are at least the UTF-16 length for valid JSON ASCII delimiters;
    // this cheap first bound also avoids encoding a huge string.
    if (value.length > limit || encoder.encode(value).byteLength > limit)
      return null;
    return value;
  }
  let bytes;
  if (value instanceof ArrayBuffer) bytes = new Uint8Array(value);
  else if (ArrayBuffer.isView(value))
    bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  else return null;
  if (bytes.byteLength > limit) return null;
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

/** Cancels only the clone reader; never await tee cancellation (the caller owns the other branch). */
async function boundedStream(stream, limit) {
  if (!stream) return "";
  let reader, timer;
  try {
    reader = stream.getReader();
    const timeout = new Promise((resolve) => {
      timer = setTimeout(
        () => resolve(null),
        observerLimits.inspectionMilliseconds,
      );
    });
    const chunks = [];
    let length = 0;
    while (true) {
      const part = await Promise.race([reader.read(), timeout]);
      if (part === null) return null;
      if (part.done) break;
      if (!(part.value instanceof Uint8Array)) return null;
      length += part.value.byteLength;
      if (length > limit) return null;
      chunks.push(new Uint8Array(part.value));
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
    if (reader) {
      try {
        void reader.cancel().catch(() => {});
      } catch {}
      try {
        reader.releaseLock();
      } catch {}
    }
  }
}

function targetRequest(input, init) {
  try {
    const isRequest =
      typeof Request !== "undefined" && input instanceof Request;
    const url =
      typeof input === "string"
        ? input
        : input instanceof URL
          ? input.href
          : isRequest
            ? input.url
            : null;
    if (url === null) return false;
    const method = init?.method ?? (isRequest ? input.method : "GET");
    return (
      typeof method === "string" &&
      method.toUpperCase() === "POST" &&
      /^\/(?:v1\/)?functions\/tinkerloom-core\/executions$/.test(
        new URL(url).pathname,
      )
    );
  } catch {
    return false;
  }
}

async function requestOperation(input, init) {
  try {
    let text;
    if (init?.body !== undefined)
      text = textBytes(init.body, observerLimits.requestBytes);
    else if (typeof Request !== "undefined" && input instanceof Request) {
      text = await boundedStream(
        input.clone().body,
        observerLimits.requestBytes,
      );
    }
    if (text === null || text === undefined) return "unavailable";
    const envelope = JSON.parse(text);
    if (!object(envelope)) return "unavailable";
    let data = envelope.data;
    if (typeof envelope.body === "string") {
      const body = textBytes(envelope.body, observerLimits.requestBytes);
      data = body === null ? null : JSON.parse(body);
    }
    return object(data) && operations.has(data.op) ? data.op : "unavailable";
  } catch {
    return "unavailable";
  }
}

function responseFields(envelope) {
  const fields = {
    executionStatus: executionStatuses.has(envelope.status)
      ? envelope.status
      : "unavailable",
    functionStatus: status(envelope.responseStatusCode),
    deployment:
      envelope.deploymentId === undefined ||
      envelope.deploymentId === null ||
      envelope.deploymentId === ""
        ? "absent"
        : typeof envelope.deploymentId === "string" &&
            /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(envelope.deploymentId)
          ? "present"
          : "invalid",
    errorCode: "none",
    diagnostics: zeroes(diagnosticCategories),
  };
  if (typeof envelope.responseBody === "string") {
    const body = textBytes(
      envelope.responseBody,
      observerLimits.functionBodyBytes,
    );
    if (body === null) fields.errorCode = "unavailable";
    else {
      try {
        const data = JSON.parse(body);
        if (!object(data)) fields.errorCode = "unavailable";
        else if (data.error !== undefined)
          fields.errorCode = codes.has(data.error)
            ? data.error
            : "unrecognized_error";
      } catch {
        fields.errorCode = "unavailable";
      }
    }
  } else if (envelope.type !== undefined) {
    fields.errorCode = codes.has(envelope.type)
      ? envelope.type
      : "unrecognized_error";
  }
  let accepted = 0;
  for (const log of [envelope.errors, envelope.logs]) {
    const text = textBytes(log, observerLimits.logBytes);
    if (text === null) continue;
    for (const line of text.split(/\r?\n/)) {
      if (accepted === observerLimits.diagnosticEventsPerExecution) break;
      const match = /^transaction_diagnostic:([A-Za-z]+)$/.exec(line.trim());
      if (match && categories.has(match[1])) {
        fields.diagnostics[match[1]]++;
        accepted++;
      }
    }
  }
  return fields;
}

/**
 * Returns {fetch, snapshot, settled}. fetch forwards the exact original arguments
 * and returns the original Response. Call await settled() after a probe, before
 * snapshot(), to wait for current background clone inspections (bounded 2.5s).
 */
export function makeTransactionObserver(fetchImpl) {
  if (typeof fetchImpl !== "function")
    throw new TypeError("fetchImpl must be a function");
  const pending = new Set();
  let slots = 0;
  const state = {
    version: 1,
    counts: {
      matchedRequests: 0,
      fetchFailures: 0,
      inspectedResponses: 0,
      unreadableResponses: 0,
      inspectionsSkipped: 0,
      conflictEventsDropped: 0,
    },
    operations: zeroes([...operationNames, "unavailable"]),
    httpStatuses: zeroes([...statuses].map(String).concat("other")),
    executionStatuses: zeroes([...executionStatuses, "unavailable"]),
    functionStatuses: zeroes([...statuses].map(String).concat("other")),
    deployments: zeroes(["present", "absent", "invalid"]),
    errorCodes: zeroes(errorCodes),
    diagnostics: zeroes(diagnosticCategories),
    conflictEvents: [],
  };
  function startInspection(response, operationPromise) {
    let clone;
    try {
      clone = response.clone();
    } catch {
      slots--;
      increment(state.counts, "unreadableResponses");
      return;
    }
    const work = (async () => {
      const [text, operation] = await Promise.all([
        boundedStream(clone.body, observerLimits.responseBytes),
        operationPromise,
      ]);
      increment(state.operations, operation);
      if (text === null) {
        increment(state.counts, "unreadableResponses");
        return;
      }
      let envelope;
      try {
        envelope = JSON.parse(text);
      } catch {
        increment(state.counts, "unreadableResponses");
        return;
      }
      if (!object(envelope)) {
        increment(state.counts, "unreadableResponses");
        return;
      }
      const fields = responseFields(envelope);
      increment(state.counts, "inspectedResponses");
      increment(state.executionStatuses, fields.executionStatus);
      increment(state.functionStatuses, fields.functionStatus);
      increment(state.deployments, fields.deployment);
      increment(state.errorCodes, fields.errorCode);
      let diagnosticTotal = 0;
      for (const category of diagnosticCategories) {
        increment(state.diagnostics, category, fields.diagnostics[category]);
        diagnosticTotal += fields.diagnostics[category];
      }
      const httpStatus = status(response.status);
      if (
        diagnosticTotal ||
        httpStatus === "409" ||
        fields.functionStatus === "409" ||
        fields.errorCode === "transaction_conflict"
      ) {
        if (state.conflictEvents.length < observerLimits.conflictEvents)
          state.conflictEvents.push({ operation, httpStatus, ...fields });
        else increment(state.counts, "conflictEventsDropped");
      }
    })().catch(() => {
      increment(state.counts, "unreadableResponses");
    });
    pending.add(work);
    void work.finally(() => {
      pending.delete(work);
      slots--;
    });
  }
  return Object.freeze({
    async fetch(...args) {
      const matched = targetRequest(args[0], args[1]);
      const observe = matched && slots < observerLimits.pendingInspections;
      if (observe) slots++;
      if (matched) increment(state.counts, "matchedRequests");
      // Clone a Request before the underlying fetch can consume it. Never read
      // init.body streams: doing so would change the actual outgoing request.
      const operation = observe ? requestOperation(args[0], args[1]) : null;
      let response;
      try {
        response = await Reflect.apply(fetchImpl, this, args);
      } catch (error) {
        if (observe) slots--;
        if (matched) increment(state.counts, "fetchFailures");
        throw error;
      }
      if (matched) {
        try {
          increment(state.httpStatuses, status(response.status));
          if (observe) startInspection(response, operation);
          else increment(state.counts, "inspectionsSkipped");
        } catch {
          increment(state.counts, "unreadableResponses");
        }
      }
      return response;
    },
    snapshot() {
      return JSON.parse(JSON.stringify(state));
    },
    async settled() {
      await Promise.allSettled([...pending]);
    },
  });
}
