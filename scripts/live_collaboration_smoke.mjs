#!/usr/bin/env node
/**
 * Real Appwrite development probe. Creates synthetic QA accounts and rows.
 * Passwords, cookies, tokens, and raw responses stay in memory and are not logged.
 * Run only against the isolated development project authorized by its owner.
 * Usage: node scripts/live_collaboration_smoke.mjs --database-id PUBLIC_ID
 * Optional: --origin http://localhost:8426
 * Every completed run retains a sanitized output/live-collaboration/RUN/report.json,
 * including failures. QA rows/accounts remain; user sessions are signed out.
 * This is live REST evidence only. Time expiry and device/UI limits stay explicit.
 */
import { randomBytes } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { isDeepStrictEqual } from "node:util";
import {
  containsPrivateRowFields,
  isPrivateRowReadDenied,
} from "./live_smoke_denial.mjs";
import {
  exactKeys,
  validDocument,
  validInvitation,
  validMember,
  validPreview,
  validRecord,
  validRecordPage,
  validSummary,
  safeCode,
  safeObservation,
} from "./live_collaboration_contract.mjs";

const report = {
  schemaVersion: 1,
  runId:
    "qa-collab-" +
    Date.now().toString(36) +
    "-" +
    randomBytes(4).toString("hex"),
  startedAt: new Date().toISOString(),
  completedAt: null,
  status: "running",
  target: null,
  accounts: [],
  resources: {},
  checks: [],
  coverage: {
    layer: "Real REST user sessions and deployed Function operations only.",
    unverified: [
      "Natural seven-day expiry denial: this bounded run cannot advance the service clock.",
      "One-hundred-workspace/app admission limits: not filled by this bounded run.",
      "Network failure injection is not performed; exact-command receipt replays are checked.",
      "Browser, native device, and UI interactions are not exercised by this script.",
    ],
  },
  budget: {
    maxHttpRequests: 240,
    maxSyntheticAccounts: 5,
    maxInvitationsPerIssuer: 50,
    httpRequests: 0,
  },
};
const outcomes = new Map();
let activeAssertions = 0;
let httpRequests = 0;
const privateValues = new Set();

class ProbeError extends Error {
  constructor(code, observation = {}) {
    super(code);
    this.code = code;
    this.observation = observation;
  }
}

function safeProbeCode(value) {
  return typeof value === "string" && /^[a-z0-9_]{1,96}$/.test(value)
    ? value
    : "unexpected_probe_error";
}

function verify(condition, code, observation = {}) {
  activeAssertions++;
  if (!condition) throw new ProbeError(code, observation);
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
          ? safeProbeCode(error.code)
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
    if (httpRequests >= report.budget.maxHttpRequests)
      throw new ProbeError("http_request_budget_exhausted");
    httpRequests++;
    report.budget.httpRequests = httpRequests;
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
      else {
        this.cookies.set(name, value);
        privateValues.add(value);
      }
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
    executionStatus: [
      "completed",
      "failed",
      "processing",
      "waiting",
      "scheduled",
    ].includes(result.executionStatus)
      ? result.executionStatus
      : "unavailable",
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
  privateValues.add(credentials.password);
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

function documentResponse(result, appId, role, archived) {
  const data = expectFunction(result);
  verify(
    exactKeys(data, ["app"]) && validDocument(data.app),
    "strict_app_document_invalid",
  );
  verify(
    data.app.id === appId && data.app.role === role,
    "app_identity_or_role_mismatch",
  );
  if (archived !== undefined)
    verify(data.app.archived === archived, "app_archive_state_mismatch");
  return data.app;
}

function invitationCommand(appId, role, recipientId = null) {
  const token = randomBytes(32).toString("base64url");
  privateValues.add(token);
  return {
    op: "createInvitation",
    appId,
    id: randomId("inv"),
    operationId: randomId("opr"),
    role,
    recipientId,
    token,
  };
}

function saveCommand(appId, document, title) {
  return {
    op: "saveDraft",
    appId,
    operationId: randomId("sav"),
    expectedRevision: document.draftRevision,
    expectedPublishedRevision: document.publishedRevision,
    definition: {
      title,
      description: "Synthetic collaboration verification.",
      primaryFieldId: "title",
      fields: [
        { id: "title", label: "Title", kind: "text", required: true },
        { id: "body", label: "Body", kind: "longText" },
      ],
    },
  };
}

function publishCommand(appId, document) {
  return {
    op: "publishApp",
    appId,
    operationId: randomId("pub"),
    expectedRevision: document.draftRevision,
    expectedPublishedRevision: document.publishedRevision,
    candidateRevision: document.candidateRevision,
  };
}

async function parallelAcross(requests) {
  const results = await Promise.allSettled(
    requests.map(([actor, command]) => actor.client.execute(command)),
  );
  verify(
    results.every((result) => result.status === "fulfilled"),
    "parallel_request_transport_failure",
  );
  return results.map((result) => result.value);
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
  const actors = Object.fromEntries(
    ["owner", "builder", "member", "viewer", "outsider"].map((label) => [
      label,
      { client: new AppwriteClient(configuration), credentials: null },
    ]),
  );
  const { owner, builder, member, viewer, outsider } = actors;
  const anonymous = new AppwriteClient(configuration);
  const appId = randomId("app");
  const siblingId = randomId("sib");
  const unpublishedId = randomId("unp");
  const workspaceId = randomId("wor");
  const foreignWorkspace = randomId("for");
  const foreignApp = randomId("far");
  const recordId = randomId("rec");
  report.resources = {
    workspaceId,
    appId,
    siblingId,
    unpublishedId,
    foreignWorkspace,
    foreignApp,
    recordId,
  };
  let ownerDocument, builderDocument, siblingDocument;
  let ownerFirstSave, ownerFirstSaved, builderFirstSave, builderFirstSaved;
  let builderInvite,
    builderGrantRevision = 1;
  let ownerArchiveInvite, builderArchiveInvite, archivedReceipt;
  let ownerInvitationCount = 0;
  const ownerIssued = [];
  const grants = new Map();

  async function get(actor, id = appId, role) {
    return documentResponse(
      await actor.client.execute({ op: "getApp", appId: id }),
      id,
      role ?? Object.entries(actors).find(([, value]) => value === actor)?.[0],
    );
  }
  async function issue(actor, command) {
    const data = expectFunction(await actor.client.execute(command));
    verify(
      exactKeys(data, ["invitation"]) &&
        validInvitation(data.invitation, command.appId),
      "strict_invitation_dto_invalid",
    );
    verify(
      data.invitation.id === command.id &&
        data.invitation.role === command.role &&
        data.invitation.recipientId === command.recipientId &&
        data.invitation.issuerId === actor.credentials.id &&
        data.invitation.acceptedBy === null &&
        data.invitation.revoked === false,
      "invitation_receipt_terms_mismatch",
    );
    if (actor === owner) {
      ownerInvitationCount++;
      ownerIssued.push({ command, receipt: data });
    }
    return data;
  }
  async function inspect(actor, command) {
    const data = expectFunction(
      await actor.client.execute({
        op: "inspectInvitation",
        token: command.token,
      }),
    );
    verify(
      exactKeys(data, ["invitation"]) && validPreview(data.invitation),
      "strict_invitation_preview_invalid",
    );
    verify(
      data.invitation.appId === command.appId &&
        data.invitation.role === command.role,
      "preview_terms_mismatch",
    );
    return data.invitation;
  }
  async function accept(actor, command, operationId = randomId("acc")) {
    const body = { op: "acceptInvitation", token: command.token, operationId };
    const data = expectFunction(await actor.client.execute(body));
    verify(
      exactKeys(data, ["appId"]) && data.appId === command.appId,
      "acceptance_app_identity_mismatch",
    );
    return { command: body, receipt: data };
  }
  async function memberRows() {
    let cursor;
    const rows = [];
    for (let index = 0; index < 5; index++) {
      const page = expectFunction(
        await owner.client.execute({
          op: "listMembers",
          appId,
          ...(cursor ? { afterId: cursor } : {}),
        }),
      );
      verify(
        exactKeys(page, ["members", "nextCursor"]) &&
          Array.isArray(page.members) &&
          page.members.length <= 51 &&
          page.members.every((item) => validMember(item)),
        "strict_member_page_invalid",
      );
      verify(
        page.nextCursor === null ||
          (typeof page.nextCursor === "string" && page.nextCursor !== cursor),
        "member_cursor_invalid",
      );
      rows.push(...page.members);
      if (page.nextCursor === null) {
        verify(
          rows[0]?.actorId === owner.credentials.id &&
            rows[0]?.role === "owner" &&
            rows.filter((row) => row.role === "owner").length === 1 &&
            new Set(rows.map((row) => row.actorId)).size === rows.length,
          "member_page_identity_invalid",
        );
        return rows;
      }
      cursor = page.nextCursor;
    }
    throw new ProbeError("member_pagination_bound_exceeded");
  }
  async function invitationRows(id = appId, actor = owner) {
    let cursor;
    const rows = [];
    for (let index = 0; index < 5; index++) {
      const page = expectFunction(
        await actor.client.execute({
          op: "listInvitations",
          appId: id,
          ...(cursor ? { afterId: cursor } : {}),
        }),
      );
      verify(
        exactKeys(page, ["invitations", "nextCursor"]) &&
          Array.isArray(page.invitations) &&
          page.invitations.length <= 25 &&
          page.invitations.every((item) => validInvitation(item, id)),
        "strict_invitation_page_invalid",
      );
      verify(
        page.nextCursor === null ||
          (typeof page.nextCursor === "string" && page.nextCursor !== cursor),
        "invitation_cursor_invalid",
      );
      rows.push(...page.invitations);
      if (page.nextCursor === null) {
        verify(
          new Set(rows.map((row) => row.id)).size === rows.length,
          "duplicate_invitation_page_rows",
        );
        return rows;
      }
      cursor = page.nextCursor;
    }
    throw new ProbeError("invitation_pagination_bound_exceeded");
  }
  async function changeGrant(actor, target, role, expectedRevision) {
    const command = {
      op: "setGrant",
      appId,
      actorId: target.credentials.id,
      role,
      expectedRevision,
      operationId: randomId("gra"),
    };
    const data = expectFunction(await actor.client.execute(command));
    verify(
      exactKeys(data, ["member"]) &&
        validMember(data.member, true) &&
        data.member.actorId === command.actorId &&
        data.member.role === role &&
        data.member.revision === expectedRevision + 1,
      "grant_receipt_mismatch",
    );
    return data.member;
  }
  async function unavailable(actor, command) {
    const result = await actor.client.execute(command);
    expectFunction(result, 404, "invitation_unavailable");
    verify(
      exactKeys(result.data, ["error"]),
      "unavailable_invitation_leaked_metadata",
    );
  }

  for (const [label, actor] of Object.entries(actors)) {
    await check(`qa_${label}_session`, [], async () => {
      actor.credentials = await createAccount(actor.client, label);
      await signIn(actor.client, actor.credentials);
      return { source: "real_client_session" };
    });
  }
  await check("owner_workspace_and_apps", ["qa_owner_session"], async () => {
    const workspace = expectFunction(
      await owner.client.execute({
        op: "createWorkspace",
        id: workspaceId,
        name: "QA collaboration " + report.runId,
      }),
    );
    verify(
      exactKeys(workspace, ["workspace"]) &&
        exactKeys(workspace.workspace, ["id", "name", "role"]) &&
        workspace.workspace.id === workspaceId &&
        workspace.workspace.role === "owner",
      "strict_workspace_creation_invalid",
    );
    for (const [id, name] of [
      [appId, "QA shared planner"],
      [siblingId, "QA sibling"],
      [unpublishedId, "QA unpublished"],
    ]) {
      const data = expectFunction(
        await owner.client.execute({ op: "createApp", id, workspaceId, name }),
      );
      verify(
        exactKeys(data, ["app"]) &&
          validSummary(data.app) &&
          data.app.id === id &&
          data.app.workspaceId === workspaceId &&
          data.app.role === "owner",
        "strict_app_creation_invalid",
      );
    }
  });
  await check(
    "foreign_workspace_and_app",
    ["qa_outsider_session"],
    async () => {
      const workspace = expectFunction(
        await outsider.client.execute({
          op: "createWorkspace",
          id: foreignWorkspace,
          name: "QA foreign " + report.runId,
        }),
      );
      verify(
        workspace.workspace?.id === foreignWorkspace,
        "foreign_workspace_identity_mismatch",
      );
      const app = expectFunction(
        await outsider.client.execute({
          op: "createApp",
          id: foreignApp,
          workspaceId: foreignWorkspace,
          name: "QA foreign app",
        }),
      );
      verify(
        validSummary(app.app) && app.app.id === foreignApp,
        "foreign_app_identity_mismatch",
      );
    },
  );
  await check(
    "owner_initial_publication",
    ["owner_workspace_and_apps"],
    async () => {
      ownerDocument = await get(owner);
      verify(
        ownerDocument.draftRevision === 0 &&
          ownerDocument.candidateRevision === 0 &&
          ownerDocument.publishedRevision === 0,
        "new_app_revision_not_zero",
      );
      ownerFirstSave = saveCommand(
        appId,
        ownerDocument,
        "Owner initial publication",
      );
      ownerFirstSaved = expectFunction(
        await owner.client.execute(ownerFirstSave),
      );
      verify(
        exactKeys(ownerFirstSaved, ["app"]) &&
          validDocument(ownerFirstSaved.app),
        "initial_save_dto_invalid",
      );
      ownerDocument = documentResponse(
        await owner.client.execute(publishCommand(appId, ownerFirstSaved.app)),
        appId,
        "owner",
      );
      verify(
        ownerDocument.publishedRevision === 1 &&
          ownerDocument.candidateRevision === 1 &&
          ownerDocument.basePublishedRevision === 1,
        "initial_publication_revision_invalid",
      );
      siblingDocument = await get(owner, siblingId, "owner");
      siblingDocument = documentResponse(
        await owner.client.execute(
          saveCommand(siblingId, siblingDocument, "Sibling publication"),
        ),
        siblingId,
        "owner",
      );
      siblingDocument = documentResponse(
        await owner.client.execute(publishCommand(siblingId, siblingDocument)),
        siblingId,
        "owner",
      );
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
    "cross_tenant_function_denials",
    ["owner_initial_publication", "foreign_workspace_and_app"],
    async () => {
      for (const command of [
        { op: "listApps", workspaceId },
        { op: "getApp", appId },
        { op: "listRecords", appId, definitionRevision: 1 },
        { op: "listMembers", appId },
        { op: "listInvitations", appId },
        { op: "createApp", id: randomId("den"), workspaceId, name: "Denied" },
      ]) {
        const result = await outsider.client.execute(command);
        expectFunction(result, 404, "not_found");
        verify(
          exactKeys(result.data, ["error"]),
          "cross_tenant_error_leaked_metadata",
        );
      }
      expectFunction(
        await owner.client.execute({ op: "getApp", appId: foreignApp }),
        404,
        "not_found",
      );
    },
  );
  await check(
    "bound_invitation_review_has_no_membership_side_effect",
    ["owner_initial_publication", "qa_builder_session", "qa_outsider_session"],
    async () => {
      builderInvite = invitationCommand(
        appId,
        "builder",
        builder.credentials.id,
      );
      await issue(owner, builderInvite);
      await unavailable(outsider, {
        op: "inspectInvitation",
        token: builderInvite.token,
      });
      const first = await inspect(builder, builderInvite);
      const second = await inspect(builder, builderInvite);
      verify(
        first.accepted === false && isDeepStrictEqual(first, second),
        "inspection_consumed_or_changed_invitation",
      );
      expectFunction(
        await builder.client.execute({ op: "getApp", appId }),
        404,
        "not_found",
      );
      const workspaces = expectFunction(
        await builder.client.execute({ op: "listWorkspaces" }),
      ).workspaces;
      verify(
        Array.isArray(workspaces) &&
          !workspaces.some((row) => row.id === workspaceId),
        "inspection_added_workspace_membership",
      );
      verify(
        !(await memberRows()).some(
          (row) => row.actorId === builder.credentials.id,
        ),
        "inspection_added_app_grant",
      );
      const pending = (await invitationRows()).find(
        (row) => row.id === builderInvite.id,
      );
      verify(
        pending?.acceptedBy === null && pending.revoked === false,
        "inspection_consumed_token",
      );
      const accepted = await accept(builder, builderInvite);
      const retry = expectFunction(
        await builder.client.execute(accepted.command),
      );
      verify(
        exactKeys(retry, ["appId"]) &&
          isDeepStrictEqual(retry, accepted.receipt),
        "acceptance_receipt_retry_changed",
      );
      verify(
        (await inspect(builder, builderInvite)).accepted === true,
        "accepted_preview_not_confirmed",
      );
      builderDocument = await get(builder);
      verify(
        builderDocument.definition === null &&
          builderDocument.draftRevision === 0 &&
          builderDocument.candidateRevision === 0 &&
          builderDocument.publishedRevision === 1,
        "builder_received_owner_private_draft",
      );
    },
  );
  for (const [label, actor] of [
    ["member", member],
    ["viewer", viewer],
  ]) {
    await check(
      `join_${label}_with_explicit_acceptance`,
      ["owner_initial_publication", `qa_${label}_session`],
      async () => {
        const command = invitationCommand(appId, label, actor.credentials.id);
        await issue(owner, command);
        verify(
          (await inspect(actor, command)).accepted === false,
          "new_invite_already_accepted",
        );
        expectFunction(
          await actor.client.execute({ op: "getApp", appId }),
          404,
          "not_found",
        );
        await accept(actor, command);
        const document = await get(actor);
        verify(
          document.definition === null &&
            document.draftRevision === 0 &&
            document.candidateRevision === 0 &&
            document.publishedRevision === 1,
          "reader_received_private_draft",
        );
        grants.set(label, 1);
      },
    );
  }
  await check(
    "shared_workspace_hides_unpublished_and_ungranted_apps",
    ["bound_invitation_review_has_no_membership_side_effect"],
    async () => {
      const command = invitationCommand(
        unpublishedId,
        "builder",
        builder.credentials.id,
      );
      await issue(owner, command);
      await accept(builder, command);
      expectFunction(
        await builder.client.execute({ op: "getApp", appId: unpublishedId }),
        404,
        "not_found",
      );
      const data = expectFunction(
        await builder.client.execute({ op: "listApps", workspaceId }),
      );
      verify(
        exactKeys(data, ["apps"]) &&
          Array.isArray(data.apps) &&
          data.apps.every(validSummary) &&
          data.apps.some((app) => app.id === appId) &&
          !data.apps.some((app) => [unpublishedId, siblingId].includes(app.id)),
        "shared_workspace_leaked_unpublished_or_ungranted_app",
      );
    },
  );
  await check(
    "shareable_invitation_is_single_use",
    [
      "owner_initial_publication",
      "qa_outsider_session",
      "join_viewer_with_explicit_acceptance",
    ],
    async () => {
      const command = invitationCommand(appId, "viewer");
      await issue(owner, command);
      verify(
        (await inspect(outsider, command)).accepted === false,
        "shareable_invite_not_pending",
      );
      await accept(outsider, command);
      await unavailable(viewer, {
        op: "acceptInvitation",
        token: command.token,
        operationId: randomId("den"),
      });
      await unavailable(viewer, {
        op: "inspectInvitation",
        token: command.token,
      });
      const rows = await memberRows();
      verify(
        rows.find((row) => row.actorId === outsider.credentials.id)?.role ===
          "viewer",
        "single_use_recipient_grant_missing",
      );
    },
  );
  await check(
    "private_table_reads_are_denied",
    ["bound_invitation_review_has_no_membership_side_effect"],
    async () => {
      for (const [table, row] of [
        ["invitations", builderInvite.id],
        ["receipts", ownerFirstSave.operationId],
      ]) {
        const result = await owner.client.request(
          "GET",
          `/tablesdb/${encodeURIComponent(configuration.databaseId)}/tables/${table}/rows/${encodeURIComponent(row)}`,
        );
        verify(
          !containsPrivateRowFields(result.data) &&
            isPrivateRowReadDenied(result, { knownExistingRow: true }),
          "private_table_read_not_denied",
          { httpStatus: result.status, code: safeCode(result.data?.type) },
        );
      }
    },
  );
  await check(
    "member_and_viewer_capabilities_and_write_denials",
    [
      "join_member_with_explicit_acceptance",
      "join_viewer_with_explicit_acceptance",
    ],
    async () => {
      for (const actor of [member, viewer]) {
        const document = await get(actor);
        verify(
          Object.values(document.capabilities).every(
            (value) => value === false,
          ),
          "reader_capabilities_not_read_only",
        );
        const page = expectFunction(
          await actor.client.execute({
            op: "listRecords",
            appId,
            definitionRevision: 1,
          }),
        );
        verify(
          validRecordPage(page) &&
            page.definitionRevision === 1 &&
            page.nextCursor === null,
          "reader_record_page_invalid",
        );
        for (const command of [
          saveCommand(appId, document, "Denied draft"),
          publishCommand(appId, document),
          {
            op: "saveRecord",
            appId,
            id: randomId("den"),
            operationId: randomId("den"),
            expectedRevision: 0,
            definitionRevision: 1,
            values: { title: "Denied" },
          },
          invitationCommand(appId, "viewer"),
          {
            op: "revokeInvitation",
            appId,
            invitationId: builderInvite.id,
            operationId: randomId("den"),
          },
          {
            op: "setGrant",
            appId,
            actorId: builder.credentials.id,
            role: "viewer",
            expectedRevision: 1,
            operationId: randomId("den"),
          },
          { op: "archiveApp", appId, operationId: randomId("den") },
        ])
          expectFunction(await actor.client.execute(command), 403, "forbidden");
      }
      expectFunction(
        await builder.client.execute({
          op: "archiveApp",
          appId,
          operationId: randomId("den"),
        }),
        403,
        "forbidden",
      );
      expectFunction(
        await owner.client.execute({
          op: "setGrant",
          appId,
          actorId: owner.credentials.id,
          role: "viewer",
          expectedRevision: 0,
          operationId: randomId("den"),
        }),
        403,
        "forbidden",
      );
      expectFunction(
        await owner.client.execute({
          ...invitationCommand(appId, "viewer"),
          role: "owner",
        }),
        400,
        "invalid_role",
      );
      expectFunction(
        await owner.client.execute({
          ...invitationCommand(appId, "viewer"),
          expiresAt: "2000-01-01T00:00:00.000Z",
        }),
        400,
        "invalid_request",
      );
    },
  );
  await check(
    "owner_and_builder_write_records_readers_observe_live_values",
    [
      "member_and_viewer_capabilities_and_write_denials",
      "bound_invitation_review_has_no_membership_side_effect",
    ],
    async () => {
      const command = {
        op: "saveRecord",
        appId,
        id: recordId,
        operationId: randomId("rec"),
        expectedRevision: 0,
        definitionRevision: 1,
        values: { title: "Owner record", body: "Synthetic" },
      };
      const first = expectFunction(await owner.client.execute(command));
      verify(
        exactKeys(first, ["record", "definitionRevision"]) &&
          validRecord(first.record) &&
          first.record.id === recordId &&
          first.record.revision === 1 &&
          first.definitionRevision === 1,
        "owner_record_receipt_invalid",
      );
      const second = expectFunction(
        await builder.client.execute({
          ...command,
          operationId: randomId("rec"),
          expectedRevision: 1,
          values: { title: "Builder record", body: "Synthetic" },
        }),
      );
      verify(
        exactKeys(second, ["record", "definitionRevision"]) &&
          validRecord(second.record) &&
          second.record.id === recordId &&
          second.record.revision === 2 &&
          second.definitionRevision === 1,
        "builder_record_receipt_invalid",
      );
      const page = expectFunction(
        await viewer.client.execute({
          op: "listRecords",
          appId,
          definitionRevision: 1,
        }),
      );
      verify(
        validRecordPage(page) &&
          page.records.length === 1 &&
          isDeepStrictEqual(page.records[0], second.record),
        "reader_live_record_mismatch",
      );
    },
  );
  await check(
    "private_drafts_use_distinct_global_candidates_and_stale_publication_is_denied",
    [
      "bound_invitation_review_has_no_membership_side_effect",
      "join_member_with_explicit_acceptance",
      "join_viewer_with_explicit_acceptance",
    ],
    async () => {
      builderFirstSave = saveCommand(
        appId,
        builderDocument,
        "Builder private candidate",
      );
      builderFirstSaved = expectFunction(
        await builder.client.execute(builderFirstSave),
      );
      verify(
        exactKeys(builderFirstSaved, ["app"]) &&
          validDocument(builderFirstSaved.app),
        "builder_private_save_invalid",
      );
      builderDocument = builderFirstSaved.app;
      ownerDocument = documentResponse(
        await owner.client.execute(
          saveCommand(appId, ownerDocument, "Owner private candidate"),
        ),
        appId,
        "owner",
      );
      verify(
        builderDocument.draftRevision === 1 &&
          ownerDocument.draftRevision === 2 &&
          builderDocument.candidateRevision === 2 &&
          ownerDocument.candidateRevision === 3,
        "local_or_global_candidate_counter_invalid",
      );
      verify(
        (await get(owner)).definition.title === "Owner private candidate" &&
          (await get(builder)).definition.title === "Builder private candidate",
        "private_candidate_isolation_failed",
      );
      for (const actor of [member, viewer]) {
        const document = await get(actor);
        verify(
          document.definition === null &&
            document.candidateRevision === 0 &&
            document.draftRevision === 0 &&
            document.publishedDefinition.title === "Owner initial publication",
          "reader_private_candidate_leak",
        );
      }
      builderDocument = documentResponse(
        await builder.client.execute(publishCommand(appId, builderDocument)),
        appId,
        "builder",
      );
      verify(
        builderDocument.publishedRevision === 2 &&
          builderDocument.draftRevision === 1,
        "publication_used_local_instead_of_global_revision",
      );
      expectFunction(
        await owner.client.execute(publishCommand(appId, ownerDocument)),
        409,
        "definition_conflict",
      );
      ownerDocument = await get(owner);
      verify(
        ownerDocument.publishedRevision === 2 &&
          ownerDocument.basePublishedRevision === 1,
        "stale_private_base_not_preserved",
      );
      ownerDocument = documentResponse(
        await owner.client.execute(
          saveCommand(appId, ownerDocument, "Owner rebased candidate"),
        ),
        appId,
        "owner",
      );
      ownerDocument = documentResponse(
        await owner.client.execute(publishCommand(appId, ownerDocument)),
        appId,
        "owner",
      );
      verify(
        ownerDocument.publishedRevision === 4 &&
          ownerDocument.draftRevision === 3,
        "rebased_publication_revision_invalid",
      );
      const receipt = expectFunction(
        await owner.client.execute(ownerFirstSave),
      );
      verify(
        isDeepStrictEqual(receipt, ownerFirstSaved),
        "old_draft_receipt_was_rewritten",
      );
      expectFunction(
        await owner.client.execute({
          ...ownerFirstSave,
          definition: {
            ...ownerFirstSave.definition,
            title: "Changed same operation",
          },
        }),
        409,
        "operation_conflict",
      );
    },
  );
  await check(
    "parallel_publications_have_one_winner_and_reject_the_stale_loser",
    [
      "private_drafts_use_distinct_global_candidates_and_stale_publication_is_denied",
    ],
    async () => {
      ownerDocument = documentResponse(
        await owner.client.execute(
          saveCommand(appId, ownerDocument, "Owner racing publication"),
        ),
        appId,
        "owner",
      );
      builderDocument = await get(builder);
      builderDocument = documentResponse(
        await builder.client.execute(
          saveCommand(appId, builderDocument, "Builder racing publication"),
        ),
        appId,
        "builder",
      );
      const commands = [
        publishCommand(appId, ownerDocument),
        publishCommand(appId, builderDocument),
      ];
      const results = await parallelAcross([
        [owner, commands[0]],
        [builder, commands[1]],
      ]);
      let winners = 0;
      let loser;
      for (let index = 0; index < results.length; index++) {
        const result = results[index];
        if (result.status === 200) {
          documentResponse(result, appId, index === 0 ? "owner" : "builder");
          winners++;
        } else {
          expectFunction(result, 409);
          verify(
            ["transaction_conflict", "definition_conflict"].includes(
              result.data.error,
            ),
            "unexpected_publication_race_error",
          );
          loser = index;
        }
      }
      verify(
        winners === 1 && loser !== undefined,
        "parallel_publication_winner_count_invalid",
        { winnerCount: winners },
      );
      ownerDocument = await get(owner);
      const winning = commands[1 - loser];
      verify(
        ownerDocument.publishedRevision === winning.candidateRevision &&
          ownerDocument.publishedRevision > 4,
        "publication_race_did_not_persist_winner",
      );
      expectFunction(
        await [owner, builder][loser].client.execute(commands[loser]),
        409,
        "definition_conflict",
      );
      return {
        winnerCount: winners,
        publishedRevision: ownerDocument.publishedRevision,
      };
    },
  );
  await check(
    "builder_issuer_generation_and_explicit_invitation_revocation",
    [
      "bound_invitation_review_has_no_membership_side_effect",
      "qa_outsider_session",
    ],
    async () => {
      const old = invitationCommand(appId, "viewer", outsider.credentials.id);
      await issue(builder, old);
      builderGrantRevision = (
        await changeGrant(owner, builder, "viewer", builderGrantRevision)
      ).revision;
      await unavailable(outsider, {
        op: "inspectInvitation",
        token: old.token,
      });
      await unavailable(outsider, {
        op: "acceptInvitation",
        token: old.token,
        operationId: randomId("den"),
      });
      builderGrantRevision = (
        await changeGrant(owner, builder, "builder", builderGrantRevision)
      ).revision;
      await unavailable(outsider, {
        op: "inspectInvitation",
        token: old.token,
      });
      const current = invitationCommand(
        appId,
        "viewer",
        outsider.credentials.id,
      );
      await issue(builder, current);
      verify(
        (await inspect(outsider, current)).accepted === false,
        "restored_builder_new_invite_invalid",
      );
      const revoked = expectFunction(
        await owner.client.execute({
          op: "revokeInvitation",
          appId,
          invitationId: current.id,
          operationId: randomId("rev"),
        }),
      );
      verify(
        validInvitation(revoked.invitation, appId) &&
          revoked.invitation.revoked === true,
        "revocation_receipt_invalid",
      );
      await unavailable(outsider, {
        op: "inspectInvitation",
        token: current.token,
      });
      await unavailable(outsider, {
        op: "acceptInvitation",
        token: current.token,
        operationId: randomId("den"),
      });
    },
  );
  await check(
    "parallel_accept_and_revoke_preserve_single_use_authority",
    ["owner_initial_publication", "join_viewer_with_explicit_acceptance"],
    async () => {
      const invitation = invitationCommand(
        siblingId,
        "viewer",
        viewer.credentials.id,
      );
      await issue(owner, invitation);
      const acceptCommand = {
        op: "acceptInvitation",
        token: invitation.token,
        operationId: randomId("acc"),
      };
      const revokeCommand = {
        op: "revokeInvitation",
        appId: siblingId,
        invitationId: invitation.id,
        operationId: randomId("rev"),
      };
      const [accepted, revoked] = await parallelAcross([
        [viewer, acceptCommand],
        [owner, revokeCommand],
      ]);
      if (accepted.status === 200) {
        const data = expectFunction(accepted);
        verify(
          exactKeys(data, ["appId"]) && data.appId === siblingId,
          "race_acceptance_app_mismatch",
        );
      } else {
        verify(
          (accepted.status === 404 &&
            accepted.data?.error === "invitation_unavailable") ||
            (accepted.status === 409 &&
              accepted.data?.error === "transaction_conflict"),
          "unexpected_acceptance_race_error",
          functionObservation(accepted),
        );
        expectFunction(accepted, accepted.status, accepted.data.error);
      }
      if (revoked.status === 200) {
        const data = expectFunction(revoked);
        verify(
          validInvitation(data.invitation, siblingId) &&
            data.invitation.revoked,
          "race_revocation_receipt_invalid",
        );
      } else expectFunction(revoked, 409, "transaction_conflict");
      verify(
        accepted.status === 200 || revoked.status === 200,
        "race_had_no_committed_operation",
      );
      // This is a deliberately tested exact receipt retry, never a new operation.
      const finalRevoke = expectFunction(
        await owner.client.execute(revokeCommand),
      );
      verify(
        validInvitation(finalRevoke.invitation, siblingId) &&
          finalRevoke.invitation.revoked,
        "exact_race_revocation_retry_invalid",
      );
      const stored = (await invitationRows(siblingId)).find(
        (row) => row.id === invitation.id,
      );
      verify(
        stored?.revoked === true &&
          [null, viewer.credentials.id].includes(stored.acceptedBy),
        "race_final_invitation_state_invalid",
      );
      const access = await viewer.client.execute({
        op: "getApp",
        appId: siblingId,
      });
      if (stored.acceptedBy === viewer.credentials.id) {
        documentResponse(access, siblingId, "viewer");
        verify(
          accepted.status === 200,
          "accepted_grant_without_successful_acceptance",
        );
      } else expectFunction(access, 404, "not_found");
      await unavailable(viewer, acceptCommand);
    },
  );
  await check(
    "prepare_archive_receipt_probes",
    [
      "builder_issuer_generation_and_explicit_invitation_revocation",
      "owner_initial_publication",
    ],
    async () => {
      ownerArchiveInvite = invitationCommand(
        appId,
        "viewer",
        outsider.credentials.id,
      );
      builderArchiveInvite = invitationCommand(
        appId,
        "viewer",
        outsider.credentials.id,
      );
      await issue(owner, ownerArchiveInvite);
      await issue(builder, builderArchiveInvite);
    },
  );
  await check(
    "rolling_invitation_quota_is_shared_across_apps_and_exact_retries_count_once",
    [
      "prepare_archive_receipt_probes",
      "parallel_accept_and_revoke_preserve_single_use_authority",
      "shareable_invitation_is_single_use",
    ],
    async () => {
      while (ownerInvitationCount < report.budget.maxInvitationsPerIssuer) {
        await issue(
          owner,
          invitationCommand(
            ownerInvitationCount % 2 === 0 ? appId : siblingId,
            "viewer",
          ),
        );
      }
      verify(ownerInvitationCount === 50, "quota_probe_issuance_count_invalid");
      const denied = await owner.client.execute(
        invitationCommand(siblingId, "viewer"),
      );
      expectFunction(denied, 429, "quota_exceeded");
      const last = ownerIssued.at(-1);
      const receipt = expectFunction(await owner.client.execute(last.command));
      verify(
        isDeepStrictEqual(receipt, last.receipt),
        "quota_counted_exact_invitation_retry",
      );
      expectFunction(
        await owner.client.execute(invitationCommand(appId, "viewer")),
        429,
        "quota_exceeded",
      );
      const rows = [
        ...(await invitationRows()),
        ...(await invitationRows(siblingId)),
        ...(await invitationRows(unpublishedId)),
      ];
      const owned = rows.filter((row) => row.issuerId === owner.credentials.id);
      verify(
        owned.length === 50 && new Set(owned.map((row) => row.id)).size === 50,
        "quota_persisted_invitation_count_invalid",
      );
      verify(
        ownerIssued.every(({ command }) =>
          owned.some(
            (row) => row.id === command.id && row.appId === command.appId,
          ),
        ),
        "quota_issued_invitation_missing_from_inventory",
      );
      return { invitationCount: owned.length };
    },
  );
  await check(
    "archived_apps_allow_removal_and_exact_receipts_but_no_new_writes",
    [
      "prepare_archive_receipt_probes",
      "private_drafts_use_distinct_global_candidates_and_stale_publication_is_denied",
      "join_viewer_with_explicit_acceptance",
    ],
    async () => {
      const archive = { op: "archiveApp", appId, operationId: randomId("arc") };
      archivedReceipt = expectFunction(await owner.client.execute(archive));
      verify(
        validDocument(archivedReceipt.app) &&
          archivedReceipt.app.archived &&
          archivedReceipt.app.capabilities.revokeAccess,
        "archive_receipt_invalid",
      );
      for (const actor of [owner, builder]) {
        const document = await get(
          actor,
          appId,
          actor === owner ? "owner" : "builder",
        );
        verify(
          document.archived &&
            document.capabilities.revokeAccess &&
            ["share", "editDefinition", "writeRecords", "archive"].every(
              (key) => document.capabilities[key] === false,
            ),
          "archived_capabilities_invalid",
        );
      }
      expectFunction(
        await builder.client.execute(invitationCommand(appId, "viewer")),
        403,
        "app_archived",
      );
      expectFunction(
        await owner.client.execute({
          op: "setGrant",
          appId,
          actorId: viewer.credentials.id,
          role: "builder",
          expectedRevision: grants.get("viewer"),
          operationId: randomId("den"),
        }),
        403,
        "app_archived",
      );
      expectFunction(
        await owner.client.execute(
          saveCommand(appId, ownerDocument, "Denied archived edit"),
        ),
        403,
        "app_archived",
      );
      verify(
        isDeepStrictEqual(
          expectFunction(await owner.client.execute(ownerFirstSave)),
          ownerFirstSaved,
        ),
        "archive_blocked_old_owner_receipt",
      );
      verify(
        isDeepStrictEqual(
          expectFunction(await builder.client.execute(builderFirstSave)),
          builderFirstSaved,
        ),
        "archive_blocked_old_builder_receipt",
      );
      const oldInvite = ownerIssued.find(
        (item) => item.command.id === ownerArchiveInvite.id,
      );
      verify(
        isDeepStrictEqual(
          expectFunction(await owner.client.execute(ownerArchiveInvite)),
          oldInvite.receipt,
        ),
        "archive_blocked_exact_invitation_receipt",
      );
      verify(
        (await invitationRows(appId, builder)).length > 0,
        "archived_builder_cannot_list_management_metadata",
      );
      const revoked = expectFunction(
        await builder.client.execute({
          op: "revokeInvitation",
          appId,
          invitationId: ownerArchiveInvite.id,
          operationId: randomId("rev"),
        }),
      );
      verify(
        validInvitation(revoked.invitation, appId) &&
          revoked.invitation.revoked,
        "archived_invitation_removal_failed",
      );
      await changeGrant(owner, viewer, null, grants.get("viewer"));
      expectFunction(
        await viewer.client.execute({ op: "getApp", appId }),
        404,
        "not_found",
      );
      await changeGrant(owner, builder, null, builderGrantRevision);
      expectFunction(
        await builder.client.execute(builderFirstSave),
        404,
        "not_found",
      );
      expectFunction(
        await builder.client.execute(builderArchiveInvite),
        404,
        "not_found",
      );
      expectFunction(
        await builder.client.execute({ op: "listInvitations", appId }),
        404,
        "not_found",
      );
      verify(
        isDeepStrictEqual(
          expectFunction(await owner.client.execute(archive)),
          archivedReceipt,
        ),
        "archive_receipt_retry_changed",
      );
      return { source: "real_function" };
    },
  );
  await check(
    "fresh_owner_session_reads_archived_persistent_app",
    ["archived_apps_allow_removal_and_exact_receipts_but_no_new_writes"],
    async () => {
      const fresh = new AppwriteClient(configuration);
      await signIn(fresh, owner.credentials);
      const document = documentResponse(
        await fresh.execute({ op: "getApp", appId }),
        appId,
        "owner",
        true,
      );
      verify(
        document.publishedRevision === ownerDocument.publishedRevision &&
          document.publishedDefinition !== null,
        "fresh_session_lost_publication",
      );
      const result = await fresh.request("DELETE", "/account/sessions/current");
      verify(result.status === 204, "fresh_session_logout_failed", {
        httpStatus: result.status,
      });
      return {
        source: "fresh_client_session",
        publishedRevision: document.publishedRevision,
      };
    },
  );
  for (const [label, actor] of Object.entries(actors)) {
    if (!actor.client.cookies.size) continue;
    await check(`qa_${label}_signout`, [], async () => {
      const result = await actor.client.request(
        "DELETE",
        "/account/sessions/current",
      );
      verify(result.status === 204, "qa_signout_failed", {
        httpStatus: result.status,
      });
    });
  }
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
        ? safeProbeCode(error.code)
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
let serialized = JSON.stringify(report, null, 2) + "\n";
if (
  [...privateValues].some(
    (value) => value.length > 12 && serialized.includes(value),
  )
) {
  serialized =
    JSON.stringify(
      {
        schemaVersion: 1,
        runId: report.runId,
        status: "failed",
        code: "report_secret_scan_failed",
      },
      null,
      2,
    ) + "\n";
  report.status = "failed";
}
try {
  const directory = fileURLToPath(
    new URL(`../output/live-collaboration/${report.runId}/`, import.meta.url),
  );
  await mkdir(directory, { recursive: true });
  await writeFile(join(directory, "report.json"), serialized, {
    flag: "wx",
    mode: 0o600,
  });
} catch {
  report.status = "failed";
  serialized =
    JSON.stringify(
      {
        ...JSON.parse(serialized),
        status: "failed",
        persistenceError: "report_persistence_failed",
      },
      null,
      2,
    ) + "\n";
}
process.stdout.write(serialized);
process.exitCode = report.status === "passed" ? 0 : 1;
