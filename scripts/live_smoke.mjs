#!/usr/bin/env node
/**
 * Real Appwrite development probe. Creates synthetic QA accounts and rows.
 * Passwords, cookies, tokens, and raw responses stay in memory and are not logged.
 * Run only against the isolated development project authorized by its owner.
 */
import { randomBytes } from "node:crypto";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";
import {
  containsPrivateRowFields,
  isPrivateRowReadDenied,
} from "./live_smoke_denial.mjs";

const report = {
  schemaVersion: 1,
  runId: "qa-" + Date.now().toString(36) + "-" + randomBytes(4).toString("hex"),
  startedAt: new Date().toISOString(),
  completedAt: null,
  status: "running",
  target: null,
  accounts: [],
  resources: {},
  checks: [],
  coverage:
    "Real REST client sessions and Function operations; not browser, native-device, or full-feature acceptance.",
};
const outcomes = new Map();
let activeAssertions = 0;

class ProbeError extends Error {
  constructor(code, observation = {}) {
    super(code);
    this.code = code;
    this.observation = observation;
  }
}

function safeCode(value, fallback = "unknown_error") {
  return typeof value === "string" && /^[a-zA-Z0-9_.-]{1,96}$/.test(value)
    ? value
    : fallback;
}

function verify(condition, code, observation = {}) {
  activeAssertions++;
  if (!condition) throw new ProbeError(code, observation);
}

function safeObservation(value = {}) {
  const allowed = new Set([
    "httpStatus",
    "functionStatus",
    "executionStatus",
    "code",
    "revision",
    "draftRevision",
    "publishedRevision",
    "workspaceId",
    "appId",
    "recordId",
    "operationId",
    "source",
    "winnerCount",
    "expectedFunctionStatus",
  ]);
  const result = {};
  for (const [key, item] of Object.entries(value)) {
    if (!allowed.has(key)) continue;
    const outputKey = key === "code" ? "observedCode" : key;
    if (typeof item === "number" && Number.isFinite(item))
      result[outputKey] = item;
    else if (
      typeof item === "string" &&
      /^[a-zA-Z0-9_.:/ -]{1,150}$/.test(item)
    )
      result[outputKey] = item;
  }
  return result;
}

async function check(name, prerequisites, run) {
  if (prerequisites.some((item) => outcomes.get(item) !== "passed")) {
    report.checks.push({
      name,
      status: "blocked",
      code: "prerequisite_failed",
      assertions: 0,
    });
    outcomes.set(name, "blocked");
    return;
  }
  activeAssertions = 0;
  const started = Date.now();
  try {
    const observation = await run();
    if (activeAssertions === 0) throw new ProbeError("no_assertions_executed");
    report.checks.push({
      name,
      status: "passed",
      assertions: activeAssertions,
      durationMs: Date.now() - started,
      ...safeObservation(observation),
    });
    outcomes.set(name, "passed");
  } catch (error) {
    report.checks.push({
      name,
      status: "failed",
      assertions: activeAssertions,
      durationMs: Date.now() - started,
      code:
        error instanceof ProbeError
          ? safeCode(error.code)
          : "unexpected_probe_error",
      ...(error instanceof ProbeError
        ? safeObservation(error.observation)
        : {}),
    });
    outcomes.set(name, "failed");
  }
}

function randomId(prefix) {
  return prefix.slice(0, 3) + "-" + randomBytes(14).toString("hex");
}

function readConfiguration() {
  const local = fileURLToPath(
    new URL("../apps/mobile/.env.local", import.meta.url),
  );
  if (existsSync(local)) {
    try {
      process.loadEnvFile(local);
    } catch {
      throw new ProbeError("public_environment_file_invalid");
    }
  }
  let databaseId = process.env.TINKERLOOM_DATABASE_ID;
  let origin = process.env.TINKERLOOM_ORIGIN || "http://localhost:8426";
  const args = process.argv.slice(2);
  for (let index = 0; index < args.length; index++) {
    if (args[index] === "--database-id" && args[index + 1])
      databaseId = args[++index];
    else if (args[index] === "--origin" && args[index + 1])
      origin = args[++index];
    else throw new ProbeError("unsupported_or_incomplete_argument");
  }
  const endpoint = (process.env.EXPO_PUBLIC_APPWRITE_ENDPOINT || "")
    .trim()
    .replace(/\/$/, "");
  const projectId = process.env.EXPO_PUBLIC_APPWRITE_PROJECT_ID || "";
  const functionId = process.env.EXPO_PUBLIC_APPWRITE_FUNCTION_ID || "";
  if (endpoint.length > 512 || origin.length > 512) {
    throw new ProbeError("endpoint_or_origin_too_long");
  }
  const id = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,35}$/;
  if (
    ![projectId, functionId, databaseId].every(
      (value) => typeof value === "string" && id.test(value),
    )
  ) {
    throw new ProbeError("public_project_function_and_database_ids_required");
  }
  let endpointUrl, originUrl;
  try {
    endpointUrl = new URL(endpoint);
    originUrl = new URL(origin);
  } catch {
    throw new ProbeError("endpoint_or_origin_invalid");
  }
  const localEndpoint = ["localhost", "127.0.0.1", "[::1]"].includes(
    endpointUrl.hostname,
  );
  if (
    (endpointUrl.protocol !== "https:" &&
      !(localEndpoint && endpointUrl.protocol === "http:")) ||
    endpointUrl.username ||
    endpointUrl.password ||
    endpointUrl.search ||
    endpointUrl.hash ||
    endpointUrl.pathname !== "/v1"
  )
    throw new ProbeError("unsafe_or_invalid_endpoint");
  if (
    !["http:", "https:"].includes(originUrl.protocol) ||
    originUrl.origin !== origin ||
    originUrl.username ||
    originUrl.password
  )
    throw new ProbeError("origin_must_be_an_http_origin");
  return { endpoint, projectId, functionId, databaseId, origin };
}

class AppwriteClient {
  constructor(configuration) {
    this.configuration = configuration;
    this.cookies = new Map();
  }

  async request(method, path, body) {
    const headers = {
      "X-Appwrite-Project": this.configuration.projectId,
      Origin: this.configuration.origin,
    };
    if (body !== undefined) headers["Content-Type"] = "application/json";
    if (this.cookies.size)
      headers.Cookie = [...this.cookies.entries()]
        .map(([key, value]) => key + "=" + value)
        .join("; ");
    let response;
    try {
      response = await fetch(this.configuration.endpoint + path, {
        method,
        headers,
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        redirect: "error",
        signal: AbortSignal.timeout(30_000),
      });
    } catch {
      throw new ProbeError("request_transport_failure");
    }
    if (typeof response.headers.getSetCookie !== "function")
      throw new ProbeError("node_cookie_api_unavailable");
    for (const header of response.headers.getSetCookie()) {
      const pair = header.split(";", 1)[0];
      const separator = pair.indexOf("=");
      if (separator < 1) continue;
      const name = pair.slice(0, separator);
      const value = pair.slice(separator + 1);
      if (!/^[a-zA-Z0-9_.-]+$/.test(name) || /[\r\n]/.test(value))
        throw new ProbeError("invalid_session_cookie");
      if (!value) this.cookies.delete(name);
      else this.cookies.set(name, value);
    }
    let text;
    try {
      text = await response.text();
    } catch {
      throw new ProbeError("response_transport_failure", {
        httpStatus: response.status,
      });
    }
    if (text.length > 2_097_152)
      throw new ProbeError("response_too_large", {
        httpStatus: response.status,
      });
    let data = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        throw new ProbeError("response_not_json", {
          httpStatus: response.status,
        });
      }
    }
    return { status: response.status, data };
  }

  async execute(payload) {
    const outer = await this.request(
      "POST",
      "/functions/" +
        encodeURIComponent(this.configuration.functionId) +
        "/executions",
      {
        body: JSON.stringify(payload),
        async: false,
        path: "/",
        method: "POST",
        headers: { "content-type": "application/json" },
      },
    );
    if (outer.status < 200 || outer.status >= 300) return { outer };
    const execution = outer.data;
    if (!execution || typeof execution !== "object" || Array.isArray(execution))
      throw new ProbeError("execution_response_invalid");
    let data;
    try {
      data = JSON.parse(execution.responseBody);
    } catch {
      throw new ProbeError("function_response_not_json", {
        httpStatus: outer.status,
      });
    }
    if (!data || typeof data !== "object" || Array.isArray(data))
      throw new ProbeError("function_response_invalid");
    return {
      outer,
      executionStatus: execution.status,
      status: execution.responseStatusCode,
      data,
    };
  }
}

function functionObservation(result) {
  return {
    httpStatus: result.outer.status,
    functionStatus: result.status,
    executionStatus: safeCode(result.executionStatus, "unavailable"),
    code: safeCode(result.data?.error ?? result.outer.data?.type, "none"),
  };
}

function expectFunction(result, status = 200, code) {
  const observation = {
    ...functionObservation(result),
    expectedFunctionStatus: status,
  };
  verify(
    result.outer.status >= 200 && result.outer.status < 300,
    "function_execution_api_rejected",
    observation,
  );
  verify(
    result.executionStatus === "completed",
    "function_execution_incomplete",
    observation,
  );
  verify(result.status === status, "unexpected_function_status", observation);
  if (code)
    verify(
      result.data?.error === code,
      "unexpected_function_error_code",
      observation,
    );
  return result.data;
}

async function parallelExecutions(client, commands) {
  const settled = await Promise.allSettled(
    commands.map((command) => client.execute(command)),
  );
  verify(
    settled.every((result) => result.status === "fulfilled"),
    "parallel_request_transport_failure",
  );
  return settled.map((result) => result.value);
}

async function createAccount(client, label) {
  const credentials = {
    id: randomId("qa"),
    email:
      "tinkerloom-" +
      report.runId +
      "-" +
      label.toLowerCase() +
      "@example.test",
    password: "T!" + randomBytes(24).toString("hex") + "a9",
  };
  const result = await client.request("POST", "/account", {
    userId: credentials.id,
    email: credentials.email,
    password: credentials.password,
    name: "Tinkerloom QA " + label + " " + report.runId,
  });
  report.accounts.push({
    label: "QA " + label,
    id: credentials.id,
    creationStatus:
      result.status === 201 && result.data?.$id === credentials.id
        ? "created"
        : "unconfirmed",
  });
  verify(result.status === 201, "qa_account_creation_failed", {
    httpStatus: result.status,
    code: safeCode(result.data?.type),
  });
  verify(result.data?.$id === credentials.id, "qa_account_identity_mismatch");
  return credentials;
}

async function signIn(client, credentials) {
  const result = await client.request("POST", "/account/sessions/email", {
    email: credentials.email,
    password: credentials.password,
  });
  verify(result.status === 201, "qa_session_creation_failed", {
    httpStatus: result.status,
    code: safeCode(result.data?.type),
  });
  verify(client.cookies.size > 0, "qa_session_cookie_missing");
  const account = await client.request("GET", "/account");
  verify(
    account.status === 200 && account.data?.$id === credentials.id,
    "qa_session_identity_mismatch",
    { httpStatus: account.status },
  );
}

async function main() {
  const configuration = readConfiguration();
  report.target = {
    endpoint: configuration.endpoint,
    origin: configuration.origin,
    projectId: configuration.projectId,
    functionId: configuration.functionId,
    databaseId: configuration.databaseId,
  };
  const a = new AppwriteClient(configuration);
  const b = new AppwriteClient(configuration);
  const anonymous = new AppwriteClient(configuration);
  let credentialsA, credentialsB, workspaceA, workspaceB, appA, appB;
  let draftResponse, publishedResponse, createdRecordResponse, currentRecord;
  const recordId = randomId("rec");
  const definition = {
    title: "QA notes " + report.runId,
    description: "Synthetic development verification.",
    primaryFieldId: "title",
    fields: [
      { id: "title", label: "Title", kind: "text", required: true },
      { id: "body", label: "Note", kind: "longText" },
      { id: "done", label: "Done", kind: "boolean" },
      {
        id: "category",
        label: "Category",
        kind: "choice",
        options: ["QA", "Later"],
      },
    ],
  };
  let draftCommand, publishCommand, createRecordCommand, editRecordCommand;

  await check("qa_account_a_and_session", [], async () => {
    credentialsA = await createAccount(a, "A");
    await signIn(a, credentialsA);
    return { source: "real_client_session" };
  });
  await check("qa_account_b_and_session", [], async () => {
    credentialsB = await createAccount(b, "B");
    await signIn(b, credentialsB);
    return { source: "real_client_session" };
  });
  await check(
    "owner_a_workspace_and_app_creation",
    ["qa_account_a_and_session"],
    async () => {
      workspaceA = randomId("wsa");
      appA = randomId("apa");
      const created = expectFunction(
        await a.execute({
          op: "createWorkspace",
          id: workspaceA,
          name: "QA A " + report.runId,
        }),
      );
      verify(
        created.workspace?.id === workspaceA,
        "workspace_creation_identity_mismatch",
      );
      const app = expectFunction(
        await a.execute({
          op: "createApp",
          id: appA,
          workspaceId: workspaceA,
          name: "QA notes " + report.runId,
        }),
      );
      verify(
        app.app?.id === appA && app.app?.workspaceId === workspaceA,
        "app_creation_identity_mismatch",
      );
      report.resources = { ...report.resources, workspaceA, appA, recordId };
      return { workspaceId: workspaceA, appId: appA };
    },
  );
  await check(
    "owner_b_workspace_and_app_creation",
    ["qa_account_b_and_session"],
    async () => {
      workspaceB = randomId("wsb");
      appB = randomId("apb");
      const workspace = expectFunction(
        await b.execute({
          op: "createWorkspace",
          id: workspaceB,
          name: "QA B " + report.runId,
        }),
      );
      verify(
        workspace.workspace?.id === workspaceB,
        "workspace_b_identity_mismatch",
      );
      const app = expectFunction(
        await b.execute({
          op: "createApp",
          id: appB,
          workspaceId: workspaceB,
          name: "QA B " + report.runId,
        }),
      );
      verify(app.app?.id === appB, "app_b_identity_mismatch");
      report.resources = { ...report.resources, workspaceB, appB };
      return { workspaceId: workspaceB, appId: appB };
    },
  );
  await check(
    "owned_lists_are_isolated",
    [
      "owner_a_workspace_and_app_creation",
      "owner_b_workspace_and_app_creation",
    ],
    async () => {
      const rowsA = expectFunction(
        await a.execute({ op: "listWorkspaces" }),
      ).workspaces;
      const rowsB = expectFunction(
        await b.execute({ op: "listWorkspaces" }),
      ).workspaces;
      verify(
        Array.isArray(rowsA) &&
          rowsA.some((row) => row.id === workspaceA) &&
          !rowsA.some((row) => row.id === workspaceB),
        "workspace_a_list_isolation_failed",
      );
      verify(
        Array.isArray(rowsB) &&
          rowsB.some((row) => row.id === workspaceB) &&
          !rowsB.some((row) => row.id === workspaceA),
        "workspace_b_list_isolation_failed",
      );
      const apps = expectFunction(
        await a.execute({ op: "listApps", workspaceId: workspaceA }),
      ).apps;
      verify(
        Array.isArray(apps) &&
          apps.some((row) => row.id === appA && row.workspaceId === workspaceA),
        "owned_app_missing",
      );
    },
  );
  await check(
    "cross_account_workspace_denial",
    ["owner_a_workspace_and_app_creation", "qa_account_b_and_session"],
    async () => {
      const result = await b.execute({
        op: "listApps",
        workspaceId: workspaceA,
      });
      expectFunction(result, 404, "not_found");
      return functionObservation(result);
    },
  );
  await check("anonymous_function_denial", [], async () => {
    const result = await anonymous.execute({ op: "listWorkspaces" });
    if ([401, 403].includes(result.outer.status))
      verify(true, "anonymous_denied_by_platform");
    else expectFunction(result, 401, "unauthenticated");
    return functionObservation(result);
  });
  await check(
    "direct_table_read_denial",
    ["owner_a_workspace_and_app_creation", "owned_lists_are_isolated"],
    async () => {
      const result = await a.request(
        "GET",
        "/tablesdb/" +
          encodeURIComponent(configuration.databaseId) +
          "/tables/workspaces/rows/" +
          encodeURIComponent(workspaceA),
      );
      verify(
        !containsPrivateRowFields(result.data),
        "direct_table_read_leaked_row_fields",
        { httpStatus: result.status, code: safeCode(result.data?.type) },
      );
      verify(
        isPrivateRowReadDenied(result, {
          knownExistingRow:
            outcomes.get("owner_a_workspace_and_app_creation") === "passed" &&
            outcomes.get("owned_lists_are_isolated") === "passed",
        }),
        "direct_table_read_not_denied",
        { httpStatus: result.status, code: safeCode(result.data?.type) },
      );
      return { httpStatus: result.status, code: safeCode(result.data?.type) };
    },
  );
  await check(
    "direct_table_create_denial",
    ["qa_account_a_and_session"],
    async () => {
      const result = await a.request(
        "POST",
        "/tablesdb/" +
          encodeURIComponent(configuration.databaseId) +
          "/tables/workspaces/rows",
        {
          rowId: randomId("dir"),
          data: {
            ownerId: credentialsA.id,
            name: "QA direct-denial probe " + report.runId,
          },
          permissions: [],
        },
      );
      verify(
        [401, 403].includes(result.status),
        "direct_table_create_not_denied",
        { httpStatus: result.status, code: safeCode(result.data?.type) },
      );
      return { httpStatus: result.status, code: safeCode(result.data?.type) };
    },
  );
  await check(
    "fresh_app_has_no_published_definition",
    ["owner_a_workspace_and_app_creation"],
    async () => {
      const app = expectFunction(
        await a.execute({ op: "getApp", appId: appA }),
      ).app;
      verify(
        app?.draftRevision === 0 &&
          app.publishedRevision === 0 &&
          app.definition === null,
        "fresh_app_state_invalid",
      );
      expectFunction(
        await a.execute({
          op: "listRecords",
          appId: appA,
          definitionRevision: 0,
        }),
        409,
        "not_published",
      );
    },
  );
  await check(
    "parallel_initial_draft_writes",
    ["owner_a_workspace_and_app_creation"],
    async () => {
      const raceApp = randomId("rac");
      const created = expectFunction(
        await a.execute({
          op: "createApp",
          id: raceApp,
          workspaceId: workspaceA,
          name: "QA draft race " + report.runId,
        }),
      );
      verify(created.app?.id === raceApp, "draft_race_app_creation_mismatch");
      report.resources.raceApp = raceApp;
      const commands = ["A", "B"].map((suffix) => ({
        op: "saveDraft",
        appId: raceApp,
        expectedRevision: 0,
        operationId: randomId("rac"),
        definition: { ...definition, title: "QA draft race writer " + suffix },
      }));
      const results = await parallelExecutions(a, commands);
      const winners = results
        .map((result, index) => ({ result, index }))
        .filter(
          ({ result }) =>
            result.outer.status >= 200 &&
            result.outer.status < 300 &&
            result.executionStatus === "completed" &&
            result.status === 200,
        );
      verify(winners.length === 1, "draft_race_winner_count_invalid", {
        winnerCount: winners.length,
      });
      const winner = winners[0];
      const loser = results[1 - winner.index];
      expectFunction(loser, 409);
      verify(
        ["revision_conflict", "transaction_conflict"].includes(
          loser.data?.error,
        ),
        "draft_race_loser_code_invalid",
        functionObservation(loser),
      );
      const saved = expectFunction(
        await a.execute({ op: "getApp", appId: raceApp }),
      ).app;
      verify(
        saved?.draftRevision === 1 &&
          saved.publishedRevision === 0 &&
          isDeepStrictEqual(
            saved.definition,
            commands[winner.index].definition,
          ),
        "draft_race_stored_state_invalid",
      );
      return { appId: raceApp, draftRevision: 1, winnerCount: 1 };
    },
  );
  await check(
    "save_draft",
    ["fresh_app_has_no_published_definition"],
    async () => {
      draftCommand = {
        op: "saveDraft",
        appId: appA,
        expectedRevision: 0,
        operationId: randomId("op"),
        definition,
      };
      draftResponse = expectFunction(await a.execute(draftCommand));
      verify(
        draftResponse.app?.draftRevision === 1 &&
          draftResponse.app.publishedRevision === 0,
        "draft_revision_invalid",
      );
      verify(
        isDeepStrictEqual(draftResponse.app.definition, definition),
        "saved_definition_mismatch",
      );
      const fetched = expectFunction(
        await a.execute({ op: "getApp", appId: appA }),
      ).app;
      verify(
        isDeepStrictEqual(fetched.definition, definition) &&
          fetched.draftRevision === 1,
        "draft_readback_failed",
      );
      return { draftRevision: 1, operationId: draftCommand.operationId };
    },
  );
  await check("invalid_draft_preserves_previous", ["save_draft"], async () => {
    expectFunction(
      await a.execute({
        ...draftCommand,
        operationId: randomId("bad"),
        expectedRevision: 1,
        definition: { ...definition, title: "" },
      }),
      400,
      "invalid_definition",
    );
    const fetched = expectFunction(
      await a.execute({ op: "getApp", appId: appA }),
    ).app;
    verify(
      fetched.draftRevision === 1 &&
        isDeepStrictEqual(fetched.definition, definition),
      "invalid_draft_changed_state",
    );
  });
  await check("stale_draft_revision_denial", ["save_draft"], async () => {
    expectFunction(
      await a.execute({
        ...draftCommand,
        operationId: randomId("stl"),
        definition: { ...definition, title: "Stale QA change" },
      }),
      409,
      "revision_conflict",
    );
  });
  await check("publish_reviewed_revision", ["save_draft"], async () => {
    publishCommand = {
      op: "publishApp",
      appId: appA,
      expectedRevision: 1,
      operationId: randomId("pub"),
    };
    publishedResponse = expectFunction(await a.execute(publishCommand));
    verify(
      publishedResponse.app?.publishedRevision === 1 &&
        isDeepStrictEqual(
          publishedResponse.app.publishedDefinition,
          definition,
        ),
      "published_candidate_mismatch",
    );
    const replay = expectFunction(await a.execute(publishCommand));
    verify(
      isDeepStrictEqual(replay, publishedResponse),
      "publication_replay_changed_outcome",
    );
    return { publishedRevision: 1, operationId: publishCommand.operationId };
  });
  await check(
    "draft_receipt_replay_after_publication",
    ["publish_reviewed_revision"],
    async () => {
      const replay = expectFunction(await a.execute(draftCommand));
      verify(
        isDeepStrictEqual(replay, draftResponse),
        "draft_receipt_not_original_outcome",
      );
    },
  );
  await check(
    "draft_receipt_changed_payload_denial",
    ["save_draft"],
    async () => {
      expectFunction(
        await a.execute({
          ...draftCommand,
          definition: { ...definition, title: "Changed QA payload" },
        }),
        409,
        "operation_conflict",
      );
    },
  );
  await check(
    "live_record_create_and_query",
    ["publish_reviewed_revision"],
    async () => {
      createRecordCommand = {
        op: "saveRecord",
        appId: appA,
        id: recordId,
        expectedRevision: 0,
        definitionRevision: 1,
        operationId: randomId("rec"),
        values: {
          title: "QA created record",
          body: "Synthetic probe.",
          done: false,
          category: "QA",
        },
      };
      createdRecordResponse = expectFunction(
        await a.execute(createRecordCommand),
      );
      currentRecord = createdRecordResponse.record;
      verify(
        currentRecord?.id === recordId &&
          currentRecord.revision === 1 &&
          isDeepStrictEqual(currentRecord.values, createRecordCommand.values),
        "created_record_mismatch",
      );
      const page = expectFunction(
        await a.execute({
          op: "listRecords",
          appId: appA,
          definitionRevision: 1,
        }),
      );
      verify(
        page.definitionRevision === 1 &&
          Array.isArray(page.records) &&
          page.records.length === 1 &&
          isDeepStrictEqual(page.records[0], currentRecord),
        "created_record_query_mismatch",
      );
      return {
        recordId,
        revision: 1,
        operationId: createRecordCommand.operationId,
      };
    },
  );
  await check(
    "live_record_edit",
    ["live_record_create_and_query"],
    async () => {
      editRecordCommand = {
        ...createRecordCommand,
        expectedRevision: 1,
        operationId: randomId("edt"),
        values: {
          ...createRecordCommand.values,
          title: "QA edited record",
          done: true,
        },
      };
      const result = expectFunction(await a.execute(editRecordCommand));
      currentRecord = result.record;
      verify(
        currentRecord?.revision === 2 &&
          isDeepStrictEqual(currentRecord.values, editRecordCommand.values),
        "edited_record_mismatch",
      );
      const replay = expectFunction(await a.execute(editRecordCommand));
      verify(
        isDeepStrictEqual(replay, result),
        "record_edit_replay_changed_outcome",
      );
      return { recordId, revision: 2 };
    },
  );
  await check(
    "stale_record_revision_denial",
    ["live_record_edit"],
    async () => {
      expectFunction(
        await a.execute({
          ...editRecordCommand,
          operationId: randomId("stl"),
          values: {
            ...editRecordCommand.values,
            title: "Stale QA record edit",
          },
        }),
        409,
        "revision_conflict",
      );
    },
  );
  await check(
    "record_receipt_changed_payload_denial",
    ["live_record_create_and_query"],
    async () => {
      expectFunction(
        await a.execute({
          ...createRecordCommand,
          values: {
            ...createRecordCommand.values,
            title: "Changed QA record payload",
          },
        }),
        409,
        "operation_conflict",
      );
    },
  );
  await check(
    "record_create_receipt_replay_after_edit",
    ["live_record_edit"],
    async () => {
      const replay = expectFunction(await a.execute(createRecordCommand));
      verify(
        isDeepStrictEqual(replay, createdRecordResponse),
        "record_create_receipt_not_original_outcome",
      );
      const page = expectFunction(
        await a.execute({
          op: "listRecords",
          appId: appA,
          definitionRevision: 1,
        }),
      );
      verify(
        Array.isArray(page.records) &&
          page.records.length === 1 &&
          isDeepStrictEqual(page.records[0], currentRecord),
        "receipt_replay_changed_current_record",
      );
    },
  );
  await check(
    "cross_account_app_and_record_denial",
    ["publish_reviewed_revision", "qa_account_b_and_session"],
    async () => {
      expectFunction(
        await b.execute({ op: "getApp", appId: appA }),
        404,
        "not_found",
      );
      expectFunction(
        await b.execute({
          ...draftCommand,
          operationId: randomId("bad"),
          expectedRevision: 1,
        }),
        404,
        "not_found",
      );
      expectFunction(
        await b.execute({
          op: "listRecords",
          appId: appA,
          definitionRevision: 1,
        }),
        404,
        "not_found",
      );
      expectFunction(
        await b.execute({
          op: "saveRecord",
          appId: appA,
          id: randomId("bad"),
          expectedRevision: 0,
          definitionRevision: 1,
          operationId: randomId("bad"),
          values: {
            title: "Unauthorized QA attempt",
            body: "",
            done: false,
            category: "QA",
          },
        }),
        404,
        "not_found",
      );
    },
  );
  await check(
    "parallel_same_revision_writes",
    ["live_record_edit"],
    async () => {
      const commands = ["A", "B"].map((suffix) => ({
        ...editRecordCommand,
        expectedRevision: 2,
        operationId: randomId("par"),
        values: {
          ...editRecordCommand.values,
          title: "QA parallel writer " + suffix,
        },
      }));
      const results = await parallelExecutions(a, commands);
      const winners = results
        .map((result, index) => ({ result, index }))
        .filter(
          ({ result }) =>
            result.outer.status >= 200 &&
            result.outer.status < 300 &&
            result.executionStatus === "completed" &&
            result.status === 200,
        );
      verify(winners.length === 1, "parallel_write_winner_count_invalid", {
        winnerCount: winners.length,
      });
      const winner = winners[0];
      const loser = results[1 - winner.index];
      expectFunction(loser, 409);
      verify(
        ["revision_conflict", "transaction_conflict"].includes(
          loser.data?.error,
        ),
        "parallel_write_loser_code_invalid",
        functionObservation(loser),
      );
      currentRecord = expectFunction(winner.result).record;
      verify(
        currentRecord?.revision === 3 &&
          isDeepStrictEqual(
            currentRecord.values,
            commands[winner.index].values,
          ),
        "parallel_write_winner_state_invalid",
      );
      const page = expectFunction(
        await a.execute({
          op: "listRecords",
          appId: appA,
          definitionRevision: 1,
        }),
      );
      verify(
        Array.isArray(page.records) &&
          page.records.length === 1 &&
          isDeepStrictEqual(page.records[0], currentRecord),
        "parallel_write_stored_state_invalid",
      );
      return { recordId, revision: 3, winnerCount: 1 };
    },
  );
  await check("fresh_session_persistence", ["live_record_edit"], async () => {
    const signedOut = await a.request("DELETE", "/account/sessions/current");
    verify(
      signedOut.status === 204,
      "signout_before_persistence_check_failed",
      { httpStatus: signedOut.status },
    );
    const fresh = new AppwriteClient(configuration);
    await signIn(fresh, credentialsA);
    const app = expectFunction(
      await fresh.execute({ op: "getApp", appId: appA }),
    ).app;
    verify(
      app?.draftRevision === 1 &&
        app.publishedRevision === 1 &&
        isDeepStrictEqual(app.publishedDefinition, definition),
      "app_not_persistent_across_session",
    );
    const page = expectFunction(
      await fresh.execute({
        op: "listRecords",
        appId: appA,
        definitionRevision: 1,
      }),
    );
    verify(
      Array.isArray(page.records) &&
        page.records.length === 1 &&
        isDeepStrictEqual(page.records[0], currentRecord),
      "record_not_persistent_across_session",
    );
    const logout = await fresh.request("DELETE", "/account/sessions/current");
    verify(logout.status === 204, "fresh_session_logout_failed", {
      httpStatus: logout.status,
    });
    return {
      recordId,
      revision: currentRecord.revision,
      source: "fresh_client_session",
    };
  });
  await check(
    "qa_account_b_signout",
    ["qa_account_b_and_session"],
    async () => {
      const result = await b.request("DELETE", "/account/sessions/current");
      verify(result.status === 204, "qa_b_signout_failed", {
        httpStatus: result.status,
      });
    },
  );
}

try {
  await main();
} catch (error) {
  report.checks.push({
    name: "probe_setup",
    status: "failed",
    assertions: 0,
    code:
      error instanceof ProbeError
        ? safeCode(error.code)
        : "unexpected_probe_setup_error",
  });
}
report.completedAt = new Date().toISOString();
report.status =
  report.checks.length > 0 &&
  report.checks.every((item) => item.status === "passed")
    ? "passed"
    : "failed";
report.summary = {
  passed: report.checks.filter((item) => item.status === "passed").length,
  failed: report.checks.filter((item) => item.status === "failed").length,
  blocked: report.checks.filter((item) => item.status === "blocked").length,
  assertions: report.checks.reduce((total, item) => total + item.assertions, 0),
};
process.stdout.write(JSON.stringify(report, null, 2) + "\n");
process.exitCode = report.status === "passed" ? 0 : 1;
