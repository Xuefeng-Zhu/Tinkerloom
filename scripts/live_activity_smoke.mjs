/** Import-safe activity acceptance. Existing synthetic credentials stay in memory. */
import { randomBytes } from "node:crypto";
import { isDeepStrictEqual } from "node:util";
import {
  AppwriteUserClient,
  HttpBudget,
  authRequest,
} from "./live_full_transport.mjs";
import { readSyntheticCredentials } from "./live_ephemeral_accounts.mjs";
import {
  FullProbeError,
  exactKeys,
  object,
  id,
  validFullApp,
  validOutcome,
  isFullPrivateRowDenied,
} from "./live_full_contract.mjs";
import {
  validInvitation,
  validPreview,
} from "./live_collaboration_contract.mjs";

const labels = ["owner", "builder", "member", "viewer", "outsider"];
const phaseNames = [
  "authenticate_existing_pool",
  "preflight_exact_activity_deployment",
  "setup_scoped_apps_roles_and_private_values",
  "all_four_roles_metadata_paging",
  "cross_scope_cursor_and_private_table_denials",
  "stale_snapshot_and_current_grant_revocation",
  "archived_reads_and_expired_session",
  "temporary_session_cleanup",
];
const newId = (prefix) =>
  prefix.slice(0, 3) + "-" + randomBytes(14).toString("hex");
const ownError = (data, code) =>
  exactKeys(data, ["error"]) && data.error === code;
const encodeCursor = (value) =>
  Buffer.from(JSON.stringify(value))
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
class ActivityProbeError extends Error {
  constructor(code, uncertain = false) {
    super(code);
    this.code = code;
    this.uncertain = uncertain;
  }
}
const demand = (condition, code = "assertion_failed") => {
  if (!condition) throw new ActivityProbeError(code);
};
function instant(value) {
  if (typeof value !== "string") return false;
  const match =
    /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)\.(\d{3})(\d{3})?Z$/.exec(
      value,
    );
  if (!match || match[8] === "000") return false;
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
}
export function activityPage(
  input,
  appId,
  limit = 2,
  privateValues = new Set(),
) {
  demand(
    exactKeys(input, ["appId", "items", "nextCursor"]) &&
      input.appId === appId &&
      Array.isArray(input.items) &&
      input.items.length <= limit,
    "invalid_activity_metadata",
  );
  demand(
    input.nextCursor === null ||
      (typeof input.nextCursor === "string" &&
        /^[A-Za-z0-9_-]+={0,2}$/.test(input.nextCursor) &&
        input.nextCursor.length <= 1024 &&
        input.items.length === limit),
    "invalid_activity_metadata",
  );
  let previous;
  for (const row of input.items) {
    demand(
      exactKeys(row, ["id", "action", "createdAt", "status"]) &&
        id(row.id) &&
        typeof row.action === "string" &&
        /^[A-Za-z][A-Za-z0-9._-]{0,127}$/.test(row.action) &&
        instant(row.createdAt) &&
        row.status === "committed" &&
        (!previous || row.id > previous),
      "invalid_activity_metadata",
    );
    previous = row.id;
  }
  let decodedCursor = null;
  if (input.nextCursor !== null) {
    try {
      decodedCursor = JSON.parse(
        Buffer.from(input.nextCursor, "base64url").toString("utf8"),
      );
    } catch {
      throw new ActivityProbeError("invalid_activity_metadata");
    }
    demand(
      exactKeys(decodedCursor, ["scope", "revision", "id"]) &&
        /^[a-f0-9]{64}$/.test(decodedCursor.scope) &&
        Number.isInteger(decodedCursor.revision) &&
        decodedCursor.revision >= 0 &&
        decodedCursor.revision < 2147483647 &&
        decodedCursor.id === input.items.at(-1).id,
      "invalid_activity_metadata",
    );
    demand(
      encodeCursor(decodedCursor) === input.nextCursor,
      "invalid_activity_metadata",
    );
  }
  const encoded = JSON.stringify([input, decodedCursor]);
  demand(
    ![...privateValues].some(
      (value) => value.length > 8 && encoded.includes(value),
    ),
    "private_activity_value_exposed",
  );
  return input;
}
export function verifyActivityConfiguration(configuration, actorCredentials) {
  demand(configuration.enableLiveActivity === true, "explicit_enable_required");
  demand(
    typeof actorCredentials === "function",
    "memory_actor_provider_required",
  );
  demand(
    [
      configuration.projectId,
      configuration.functionId,
      configuration.databaseId,
      configuration.coreDeploymentId,
      configuration.preflightAppId,
    ].every(id) &&
      /^[a-f0-9]{7,40}$/.test(configuration.sourceCommit ?? "") &&
      /^[a-f0-9]{64}$/.test(configuration.sourceSha256 ?? ""),
    "provenance_required",
  );
  let endpoint, origin;
  try {
    endpoint = new URL(configuration.endpoint);
    origin = new URL(configuration.origin);
  } catch {
    throw new ActivityProbeError("configuration_invalid");
  }
  demand(
    endpoint.protocol === "https:" &&
      !endpoint.username &&
      !endpoint.password &&
      !endpoint.search &&
      !endpoint.hash &&
      endpoint.pathname === "/v1" &&
      ["http:", "https:"].includes(origin.protocol) &&
      origin.origin === configuration.origin &&
      Number.isInteger(configuration.maxHttp) &&
      configuration.maxHttp >= 80 &&
      configuration.maxHttp <= 180 &&
      Number.isInteger(configuration.timeoutMs) &&
      configuration.timeoutMs >= 1000 &&
      configuration.timeoutMs <= 60000,
    "configuration_invalid",
  );
}
const safeError = (value) =>
  object(value) &&
  Object.keys(value).every((key) =>
    ["message", "type", "code", "version", "error"].includes(key),
  ) &&
  Object.entries(value).every(([key, item]) =>
    key === "code"
      ? Number.isInteger(item) && item >= 100 && item <= 599
      : typeof item === "string" && item.length <= 10000,
  );
export async function runActivitySmoke(
  configuration,
  {
    actorCredentials,
    fetchImpl = globalThis.fetch,
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    onProgress = () => {},
  } = {},
) {
  verifyActivityConfiguration(configuration, actorCredentials);
  const config = Object.freeze({ ...configuration }),
    privateValues = new Set(),
    budget = new HttpBudget(config.maxHttp, 6),
    actors = {},
    checks = [],
    resources = {};
  const runId = `qa-activity-${Date.now().toString(36)}-${randomBytes(4).toString("hex")}`;
  let assertions = 0,
    reused = 0,
    cleaned = 0,
    conflicts = 0;
  const verify = (condition) => {
    assertions++;
    demand(condition);
  };
  const operationId = () => {
    const value = newId("op");
    privateValues.add(value);
    return value;
  };
  const phase = async (name, action) => {
    const before = assertions;
    try {
      onProgress({ phase: name, httpRequests: budget.used });
    } catch {}
    try {
      const observations = await action();
      checks.push({
        name,
        status: "passed",
        assertions: assertions - before,
        ...observations,
      });
    } catch (error) {
      const code =
        error instanceof ActivityProbeError ? error.code : "probe_unavailable";
      checks.push({
        name,
        status: error?.uncertain
          ? "observation_pending"
          : [
                "auth_unavailable",
                "activity_unavailable",
                "deployment_mismatch",
                "read_unavailable",
                "probe_unavailable",
                "http_budget_exhausted",
              ].includes(code)
            ? "blocked"
            : "failed",
        assertions: assertions - before,
        code,
      });
      throw error;
    }
  };
  const execute = async (
    actor,
    input,
    { mutation = false, status = 200, code } = {},
  ) => {
    for (let attempt = 0; ; attempt++) {
      let result;
      try {
        result = await actor.client.execute(input);
      } catch (error) {
        // The shared transport checks this before dispatch; no write was sent.
        if (
          error instanceof FullProbeError &&
          error.code === "http_budget_exhausted"
        )
          throw new ActivityProbeError("http_budget_exhausted");
        throw new ActivityProbeError(
          mutation ? "write_outcome_unknown" : "read_unavailable",
          mutation,
        );
      }
      const completed =
        result.outer?.status >= 200 &&
        result.outer.status < 300 &&
        result.executionStatus === "completed" &&
        result.deploymentMatched === true;
      if (completed && result.status === status) {
        if (code) verify(ownError(result.data, code));
        return result.data;
      }
      if (
        !mutation &&
        completed &&
        result.status === 409 &&
        ownError(result.data, "transaction_conflict")
      ) {
        conflicts++;
        if (attempt >= 2) throw new ActivityProbeError("read_unavailable");
        await sleep(250);
        continue;
      }
      if (
        completed &&
        result.status === 400 &&
        ownError(result.data, "unknown_operation")
      )
        throw new ActivityProbeError("activity_unavailable");
      if (result.deploymentMatched === false)
        throw new ActivityProbeError(
          mutation ? "write_outcome_unknown" : "deployment_mismatch",
          mutation,
        );
      if (
        mutation &&
        (!completed ||
          result.status >= 500 ||
          (result.status === 409 &&
            ownError(result.data, "transaction_conflict")))
      )
        throw new ActivityProbeError("write_outcome_unknown", true);
      throw new ActivityProbeError("assertion_failed");
    }
  };
  const mutate = (actor, input) => execute(actor, input, { mutation: true });
  const page = async (actor, appId, cursor, limit = 2) =>
    activityPage(
      await execute(actor, {
        op: "spec.listActivity",
        appId,
        limit,
        ...(cursor ? { cursor } : {}),
      }),
      appId,
      limit,
      privateValues,
    );
  const all = async (actor, appId) => {
    const items = [],
      cursors = new Set();
    let cursor;
    for (let n = 0; n < 12; n++) {
      const response = await page(actor, appId, cursor);
      verify(
        !items.length ||
          !response.items.length ||
          response.items[0].id > items.at(-1).id,
      );
      items.push(...response.items);
      if (response.nextCursor === null) return items;
      verify(!cursors.has(response.nextCursor));
      cursors.add(response.nextCursor);
      cursor = response.nextCursor;
    }
    throw new ActivityProbeError("paging_bound_exceeded");
  };
  const authDenial = async (client) => {
    const result = await client.execute({
      op: "spec.listActivity",
      appId: resources.appId,
      limit: 2,
    });
    if (
      [401, 403].includes(result.outer?.status) &&
      safeError(result.outer.data)
    )
      return "gateway";
    verify(
      result.deploymentMatched === true &&
        result.executionStatus === "completed" &&
        result.status === 401 &&
        ownError(result.data, "unauthenticated"),
    );
    return "core";
  };
  const signout = async (actor) => {
    if (actor.cleanupAttempted || !actor.client.cookies.size) return;
    actor.cleanupAttempted = true;
    const response = await actor.client.request(
      "DELETE",
      "/account/sessions/current",
      undefined,
      { cleanup: true },
    );
    demand(response.status === 204, "cleanup_unconfirmed");
    cleaned++;
  };
  let primary, other, foreign, oldCursor, baselineItems;
  const privateMarker = "PRIVATE_ACTIVITY_" + randomBytes(16).toString("hex");
  privateValues.add(privateMarker);
  try {
    await phase(phaseNames[0], async () => {
      const ids = new Set(),
        emails = new Set();
      for (const label of labels) {
        const credentials = await readSyntheticCredentials(
          actorCredentials,
          label,
          runId,
          privateValues,
        );
        demand(
          !ids.has(credentials.id) &&
            !emails.has(credentials.email.toLowerCase()),
          "duplicate_synthetic_actor",
        );
        ids.add(credentials.id);
        emails.add(credentials.email.toLowerCase());
        privateValues.add(credentials.id);
        actors[label] = {
          credentials,
          client: new AppwriteUserClient(
            { ...config },
            { budget, privateValues, fetchImpl },
          ),
          cleanupAttempted: false,
        };
      }
      for (const actor of Object.values(actors)) {
        const signed = await authRequest(
          actor.client,
          "POST",
          "/account/sessions/email",
          {
            email: actor.credentials.email,
            password: actor.credentials.password,
          },
        );
        demand(
          signed.status === 201 && actor.client.cookies.size > 0,
          "auth_unavailable",
        );
        const account = await actor.client.request("GET", "/account");
        demand(
          account.status === 200 && account.data?.$id === actor.credentials.id,
          "auth_unavailable",
        );
        reused++;
      }
      return { reusedVerifiedSyntheticAccounts: reused };
    });
    await phase(phaseNames[1], async () => {
      const preflight = await page(
        actors.owner,
        config.preflightAppId,
        undefined,
        1,
      );
      verify(preflight.items.length === 1);
      return { coreDeploymentMatched: 1 };
    });
    await phase(phaseNames[2], async () => {
      resources.workspaceId = newId("ws");
      resources.foreignWorkspaceId = newId("ws");
      await mutate(actors.owner, {
        op: "createWorkspace",
        id: resources.workspaceId,
        name: "Synthetic activity QA",
      });
      await mutate(actors.outsider, {
        op: "createWorkspace",
        id: resources.foreignWorkspaceId,
        name: "Synthetic foreign activity QA",
      });
      const instantiate = async (actor, workspaceId, name) => {
        const appId = newId("app");
        resources[name] = appId;
        const response = await mutate(actor, {
          op: "spec.instantiate",
          id: appId,
          workspaceId,
          templateKey: "chores",
          operationId: operationId(),
        });
        verify(
          validFullApp(response.app) &&
            response.app.id === appId &&
            response.app.role === "owner",
        );
        return response.app;
      };
      primary = await instantiate(actors.owner, resources.workspaceId, "appId");
      other = await instantiate(
        actors.owner,
        resources.workspaceId,
        "sameWorkspaceAppId",
      );
      foreign = await instantiate(
        actors.outsider,
        resources.foreignWorkspaceId,
        "foreignAppId",
      );
      for (const role of ["builder", "member", "viewer"]) {
        const token = randomBytes(32).toString("base64url");
        privateValues.add(token);
        const invited = await mutate(actors.owner, {
          op: "createInvitation",
          appId: primary.id,
          id: newId("inv"),
          operationId: operationId(),
          token,
          role,
          recipientId: actors[role].credentials.id,
        });
        verify(validInvitation(invited.invitation, primary.id));
        const inspected = await execute(actors[role], {
          op: "inspectInvitation",
          token,
        });
        verify(
          validPreview(inspected.invitation) &&
            inspected.invitation.appId === primary.id &&
            inspected.invitation.role === role,
        );
        const accepted = await mutate(actors[role], {
          op: "acceptInvitation",
          token,
          operationId: operationId(),
        });
        verify(exactKeys(accepted, ["appId"]) && accepted.appId === primary.id);
        const access = await execute(actors[role], {
          op: "getAppAccess",
          appId: primary.id,
        });
        verify(access.app?.id === primary.id && access.app.role === role);
      }
      const definition = structuredClone(primary.version.spec);
      definition.collections[0].fields[0].label = privateMarker;
      const saved = await mutate(actors.owner, {
        op: "spec.saveDraft",
        appId: primary.id,
        expectedRevision: primary.draft?.revision ?? 0,
        expectedVersionId: primary.version.id,
        operationId: operationId(),
        spec: definition,
      });
      verify(validFullApp(saved.app));
      for (let n = 0; n < 3; n++) {
        const created = await mutate(actors.owner, {
          op: "spec.execute",
          appId: primary.id,
          versionId: primary.version.id,
          actionId: "addChore",
          operationId: operationId(),
          input: { data: { title: privateMarker, status: "Open" } },
        });
        verify(validOutcome(created));
      }
      return { syntheticApps: 3, assignedRoles: 3, privateSeedRecords: 3 };
    });
    await phase(phaseNames[3], async () => {
      for (const role of ["owner", "builder", "member", "viewer"]) {
        const rows = await all(actors[role], primary.id);
        verify(rows.length >= 10);
        if (!baselineItems) baselineItems = rows;
        else verify(isDeepStrictEqual(rows, baselineItems));
      }
      oldCursor = (await page(actors.owner, primary.id)).nextCursor;
      verify(typeof oldCursor === "string");
      return {
        authorizedRoles: 4,
        metadataEntries: baselineItems.length,
        metadataFieldsPerEntry: 4,
      };
    });
    await phase(phaseNames[4], async () => {
      for (const role of ["builder", "member", "viewer"])
        await execute(
          actors[role],
          { op: "spec.listActivity", appId: other.id },
          { status: 404, code: "not_found" },
        );
      await execute(
        actors.outsider,
        { op: "spec.listActivity", appId: primary.id },
        { status: 404, code: "not_found" },
      );
      await execute(
        actors.owner,
        { op: "spec.listActivity", appId: foreign.id },
        { status: 404, code: "not_found" },
      );
      const otherRows = await all(actors.owner, other.id),
        foreignRows = await all(actors.outsider, foreign.id);
      verify(
        otherRows.every(
          (row) => !baselineItems.some((item) => item.id === row.id),
        ) &&
          foreignRows.every(
            (row) => !baselineItems.some((item) => item.id === row.id),
          ),
      );
      for (const [actor, appId, limit] of [
        [actors.builder, primary.id, 2],
        [actors.owner, other.id, 2],
        [actors.owner, primary.id, 3],
      ])
        await execute(
          actor,
          { op: "spec.listActivity", appId, cursor: oldCursor, limit },
          { status: 400, code: "invalid_request" },
        );
      const modified = JSON.parse(
        Buffer.from(oldCursor, "base64url").toString("utf8"),
      );
      modified.id = otherRows[0].id;
      await execute(
        actors.owner,
        {
          op: "spec.listActivity",
          appId: primary.id,
          limit: 2,
          cursor: encodeCursor(modified),
        },
        { status: 409, code: "revision_conflict" },
      );
      for (const actor of Object.values(actors)) {
        const denied = await actor.client.request(
          "GET",
          `/tablesdb/${encodeURIComponent(config.databaseId)}/tables/audit/rows/${baselineItems[0].id}`,
        );
        verify(
          safeError(denied.data) &&
            isFullPrivateRowDenied(denied, { knownExistingRow: true }),
        );
      }
      const anonymous = new AppwriteUserClient(
        { ...config },
        { budget, privateValues, fetchImpl },
      );
      await authDenial(anonymous);
      return {
        scopedReadDenials: 5,
        cursorScopeDenials: 4,
        directAuditRowDenials: 5,
        anonymousDenials: 1,
      };
    });
    await phase(phaseNames[5], async () => {
      const created = await mutate(actors.owner, {
        op: "spec.execute",
        appId: primary.id,
        versionId: primary.version.id,
        actionId: "addChore",
        operationId: operationId(),
        input: { data: { title: privateMarker, status: "Open" } },
      });
      verify(validOutcome(created));
      await execute(
        actors.owner,
        {
          op: "spec.listActivity",
          appId: primary.id,
          limit: 2,
          cursor: oldCursor,
        },
        { status: 409, code: "revision_conflict" },
      );
      const current = await all(actors.owner, primary.id);
      verify(
        current.length === baselineItems.length + 1 &&
          baselineItems.every((row) =>
            current.some((item) => isDeepStrictEqual(item, row)),
          ),
      );
      const memberCursor = (await page(actors.member, primary.id)).nextCursor;
      const removed = await mutate(actors.owner, {
        op: "setGrant",
        appId: primary.id,
        actorId: actors.member.credentials.id,
        role: null,
        expectedRevision: 1,
        operationId: operationId(),
      });
      verify(removed.member?.role === null);
      await execute(
        actors.member,
        {
          op: "spec.listActivity",
          appId: primary.id,
          limit: 2,
          cursor: memberCursor,
        },
        { status: 404, code: "not_found" },
      );
      await page(actors.builder, primary.id);
      return {
        staleCursorDenials: 1,
        revokedCurrentReadDenials: 1,
        oneAuditPerConfirmedRecordWrite: 1,
      };
    });
    await phase(phaseNames[6], async () => {
      await mutate(actors.owner, {
        op: "archiveApp",
        appId: primary.id,
        operationId: operationId(),
      });
      const ownerRows = await all(actors.owner, primary.id),
        viewerRows = await all(actors.viewer, primary.id);
      verify(
        isDeepStrictEqual(ownerRows, viewerRows) &&
          ownerRows.some((item) => item.action === "archiveApp"),
      );
      const oldCookies = [...actors.viewer.client.cookies];
      await signout(actors.viewer);
      // A retained old cookie is still the same expired session, never a new identity.
      actors.viewer.client.cookies = new Map(oldCookies);
      await authDenial(actors.viewer.client);
      actors.viewer.client.cookies.clear();
      return { archivedReadableRoles: 2, expiredSessionDenials: 1 };
    });
  } catch {
    // The failing phase already records only its fixed classification. Never replay a write.
  } finally {
    const before = assertions;
    let failed = false;
    for (const actor of Object.values(actors)) {
      try {
        await signout(actor);
      } catch {
        failed = true;
      }
      actor.client.cookies.clear();
    }
    checks.push({
      name: phaseNames[7],
      status: failed ? "blocked" : "passed",
      assertions: assertions - before,
      cleanupSessions: cleaned,
      ...(failed ? { code: "cleanup_unconfirmed" } : {}),
    });
  }
  const present = new Set(checks.map((check) => check.name));
  for (const name of phaseNames)
    if (!present.has(name))
      checks.push({
        name,
        status: "blocked",
        assertions: 0,
        code: "prerequisite_not_run",
      });
  const summary = Object.fromEntries(
    ["passed", "failed", "blocked", "observation_pending"].map((status) => [
      status,
      checks.filter((check) => check.status === status).length,
    ]),
  );
  const status = summary.failed
    ? "failed"
    : summary.observation_pending
      ? "observation_pending"
      : summary.blocked
        ? "blocked"
        : "passed";
  const report = {
    schemaVersion: 1,
    runId,
    status,
    target: {
      endpoint: config.endpoint,
      projectId: config.projectId,
      functionId: config.functionId,
      databaseId: config.databaseId,
      coreDeploymentId: config.coreDeploymentId,
      sourceCommit: config.sourceCommit,
      sourceSha256: config.sourceSha256,
      sourceAttestation: "operator_supplied_archive_mapping",
      matchedCoreExecutions: Object.values(actors).reduce(
        (sum, actor) => sum + actor.client.deploymentMatches,
        0,
      ),
    },
    resources,
    checks,
    summary: { ...summary, assertions },
    budget: {
      maxHttpRequests: config.maxHttp,
      httpRequests: budget.used,
      reservedCleanupRequests: 6,
      syntheticAccountsCreated: 0,
      reusedVerifiedSyntheticAccounts: reused,
      cleanupSessions: cleaned,
      readConflicts: conflicts,
    },
    coverage: {
      layer: "authenticated_client_only_when_explicitly_executed",
      currentAccessOnEveryPageIntended: true,
      noRawAuditPayloadIntended: true,
      noProviderOrReminderApprovalIntended: true,
      nativeBrowserUI: "not_proven",
      productionOrImport: "not_proven",
    },
  };
  if (
    [...privateValues].some(
      (value) => value.length > 8 && JSON.stringify(report).includes(value),
    )
  )
    return {
      schemaVersion: 1,
      runId,
      status: "failed",
      checks: [
        {
          name: "report_redaction",
          status: "failed",
          code: "redaction_failed",
          assertions: 1,
        },
      ],
    };
  return report;
}
