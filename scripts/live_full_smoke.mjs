#!/usr/bin/env node
/** Real REST probe: import-safe. No Cloud operation occurs until CLI main runs. */
import { randomBytes } from "node:crypto";
import { readSyntheticCredentials } from "./live_ephemeral_accounts.mjs";
import { existsSync, readFileSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join, resolve } from "node:path";
import { isDeepStrictEqual as equal } from "node:util";
import {
  AppwriteUserClient,
  HttpBudget,
  authRequest,
  functionObservation,
} from "./live_full_transport.mjs";
import {
  FullProbeError,
  safeFullObservation,
  safeFinalReport,
  exactKeys,
  object,
  id,
  identity,
  validSpec,
  validFullApp,
  validReview,
  validOutcome,
  validRuntimeRecord,
  validRuntimePage,
  validAggregate,
  fullNumericCases,
  validVersion,
  isFullPrivateRowDenied,
} from "./live_full_contract.mjs";
import {
  validInvitation,
  validPreview,
} from "./live_collaboration_contract.mjs";
import { containsPrivateRowFields } from "./live_smoke_denial.mjs";
const templateKeys = [
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
const randomId = (prefix) =>
  prefix.slice(0, 3) + "-" + randomBytes(14).toString("hex");
function publicEnvironment(path) {
  const values = {};
  if (existsSync(path))
    for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
      const match =
        /^(EXPO_PUBLIC_APPWRITE_(?:ENDPOINT|PROJECT_ID|FUNCTION_ID))=(.*)$/.exec(
          line.trim(),
        );
      if (match) {
        const raw = match[2].trim();
        values[match[1]] =
          (raw.startsWith('"') && raw.endsWith('"')) ||
          (raw.startsWith("'") && raw.endsWith("'"))
            ? raw.slice(1, -1)
            : raw;
      }
    }
  return values;
}
export function readFullConfiguration(
  args = process.argv.slice(2),
  env = process.env,
  publicFile = fileURLToPath(
    new URL("../apps/mobile/.env.local", import.meta.url),
  ),
) {
  const local = publicEnvironment(publicFile),
    value = {
      endpoint:
        env.EXPO_PUBLIC_APPWRITE_ENDPOINT ??
        local.EXPO_PUBLIC_APPWRITE_ENDPOINT,
      projectId:
        env.EXPO_PUBLIC_APPWRITE_PROJECT_ID ??
        local.EXPO_PUBLIC_APPWRITE_PROJECT_ID,
      functionId:
        env.EXPO_PUBLIC_APPWRITE_FUNCTION_ID ??
        local.EXPO_PUBLIC_APPWRITE_FUNCTION_ID,
      databaseId: env.TINKERLOOM_DATABASE_ID,
      origin: "http://localhost:8426",
      maxHttp: 600,
      timeoutMs: 45000,
      twentyDistinct: false,
    };
  const flags = {
    "--endpoint": "endpoint",
    "--project-id": "projectId",
    "--function-id": "functionId",
    "--database-id": "databaseId",
    "--origin": "origin",
    "--source-commit": "sourceCommit",
    "--source-sha256": "sourceSha256",
    "--core-deployment-id": "coreDeploymentId",
    "--worker-deployment-id": "workerDeploymentId",
    "--worker-function-id": "workerFunctionId",
    "--max-http": "maxHttp",
    "--timeout-ms": "timeoutMs",
  };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--twenty-distinct-capacity-actors") {
      value.twentyDistinct = true;
      continue;
    }
    const key = flags[args[i]];
    if (!key || !args[i + 1]) throw new FullProbeError("unsupported_argument");
    value[key] = args[++i];
  }
  value.maxHttp = Number(value.maxHttp);
  value.timeoutMs = Number(value.timeoutMs);
  if (
    ![
      value.projectId,
      value.functionId,
      value.databaseId,
      value.coreDeploymentId,
      value.workerDeploymentId,
    ].every(id) ||
    (value.workerFunctionId !== undefined && !id(value.workerFunctionId)) ||
    typeof value.sourceCommit !== "string" ||
    !/^[0-9a-f]{7,40}$/.test(value.sourceCommit) ||
    (value.sourceSha256 !== undefined &&
      !/^[0-9a-f]{64}$/.test(value.sourceSha256))
  )
    throw new FullProbeError("provenance_required");
  let endpoint, origin;
  try {
    endpoint = new URL(value.endpoint);
    origin = new URL(value.origin);
  } catch {
    throw new FullProbeError("configuration_invalid");
  }
  if (
    endpoint.username ||
    endpoint.password ||
    endpoint.search ||
    endpoint.hash ||
    endpoint.pathname !== "/v1" ||
    (endpoint.protocol !== "https:" &&
      !(
        endpoint.protocol === "http:" &&
        ["localhost", "127.0.0.1", "[::1]"].includes(endpoint.hostname)
      )) ||
    origin.origin !== value.origin ||
    !["http:", "https:"].includes(origin.protocol) ||
    !Number.isInteger(value.maxHttp) ||
    value.maxHttp < 100 ||
    value.maxHttp > 600 ||
    !Number.isInteger(value.timeoutMs) ||
    value.timeoutMs < 1000 ||
    value.timeoutMs > 120000
  )
    throw new FullProbeError("configuration_invalid");
  value.endpoint = endpoint.toString().replace(/\/$/, "");
  return value;
}
export async function runFullSmoke(
  configuration,
  { fetchImpl = globalThis.fetch, sleep, actorCredentials } = {},
) {
  if (actorCredentials !== undefined && typeof actorCredentials !== "function")
    throw new FullProbeError("configuration_invalid");
  if (actorCredentials && configuration.twentyDistinct)
    throw new FullProbeError("configuration_invalid");

  const runId =
      "qa-full-" +
      Date.now().toString(36) +
      "-" +
      randomBytes(4).toString("hex"),
    privateValues = new Set(),
    maxAccounts = configuration.twentyDistinct ? 22 : 5,
    budget = new HttpBudget(configuration.maxHttp, maxAccounts + 4),
    outcomes = new Map(),
    actors = {},
    createdClients = [];
  const report = {
    schemaVersion: 1,
    runId,
    startedAt: new Date().toISOString(),
    completedAt: null,
    status: "running",
    target: {
      endpoint: configuration.endpoint,
      origin: configuration.origin,
      projectId: configuration.projectId,
      functionId: configuration.functionId,
      databaseId: configuration.databaseId,
      sourceCommit: configuration.sourceCommit,
      sourceSha256: configuration.sourceSha256 ?? null,
      coreDeploymentId: configuration.coreDeploymentId,
      workerDeploymentId: configuration.workerDeploymentId,
      workerFunctionId: configuration.workerFunctionId ?? null,
      sourceAttestation: "operator_supplied_not_server_attested",
      workerDeploymentObserved: false,
    },
    accounts: [],
    resources: {},
    checks: [],
    budget: {
      maxHttpRequests: configuration.maxHttp,
      maxSyntheticAccounts: maxAccounts,
      maxInvitationsPerIssuer: 50,
      httpRequests: 0,
    },
    capacityTrial: {
      submittedAttempts: 0,
      uniqueOperationIds: 0,
      distinctAuthenticatedActors: 0,
      peakConcurrentHttp: 0,
      serverExecutionBarrier: false,
    },
    coverage: {
      layer:
        "Real authenticated REST operations only when executed against Cloud.",
      unverified: [
        "Provider generation/spend, reminder delivery and media execution are not invoked.",
        "spec.watch is outside this deployed checkpoint and is not called.",
        "UI, browser/native device, server execution barriers, transactional internals, gateway maximum body sizes and production performance are not proved.",
        "Exact-command receipts are replayed; network-loss injection is not performed.",
        "No accounts, apps or records are deleted; only temporary user sessions are signed out.",
      ],
    },
  };
  let assertions = 0,
    invitationCount = 0;
  const verify = (condition, observation = {}) => {
    assertions++;
    if (!condition)
      throw new FullProbeError("assertion_failed", {
        ...observation,
        assertionIndex: assertions,
      });
  };
  const check = async (name, prerequisites, run) => {
    if (prerequisites.some((key) => outcomes.get(key) !== "passed")) {
      report.checks.push({
        name,
        status: "blocked",
        assertions: 0,
        code: "prerequisite_failed",
      });
      outcomes.set(name, "blocked");
      return;
    }
    assertions = 0;
    const started = Date.now();
    try {
      const observation = await run();
      if (assertions === 0) throw new FullProbeError("no_assertions_executed");
      report.checks.push({
        name,
        status: "passed",
        assertions,
        durationMs: Date.now() - started,
        ...safeFullObservation(observation),
      });
      outcomes.set(name, "passed");
    } catch (error) {
      report.checks.push({
        name,
        status: "failed",
        assertions,
        durationMs: Date.now() - started,
        code:
          error instanceof FullProbeError
            ? error.code
            : "unexpected_probe_error",
        ...(error instanceof FullProbeError
          ? safeFullObservation(error.observation)
          : {}),
      });
      outcomes.set(name, "failed");
    }
  };
  const client = () => {
    const value = new AppwriteUserClient(configuration, {
      budget,
      privateValues,
      fetchImpl,
    });
    createdClients.push(value);
    return value;
  };
  const expect = (result, status = 200, code) => {
    const observation = {
      ...functionObservation(result),
      expectedFunctionStatus: status,
    };
    verify(
      result.outer.status >= 200 && result.outer.status < 300,
      observation,
    );
    verify(result.executionStatus === "completed", observation);
    verify(result.deploymentMatched === true, observation);
    verify(result.status === status, observation);
    if (code)
      verify(
        exactKeys(result.data, ["error"]) && result.data.error === code,
        observation,
      );
    return result.data;
  };
  const execute = async (actor, payload, status = 200, code) =>
    expect(await actor.client.execute(payload), status, code);
  const app = async (actor, appId) => {
    const data = await execute(actor, { op: "spec.getApp", appId });
    verify(
      exactKeys(data, ["app"]) &&
        validFullApp(data.app) &&
        data.app.id === appId,
    );
    return data.app;
  };
  const command = (appId, versionId, actionId, input, recordId, revision) => ({
    op: "spec.execute",
    appId,
    versionId,
    operationId: randomId("cmd"),
    actionId,
    input,
    ...(recordId ? { targetRecordId: recordId } : {}),
    ...(revision === undefined ? {} : { expectedRecordRevision: revision }),
  });
  const action = async (actor, payload) => {
    const data = await execute(actor, payload);
    verify(validOutcome(data));
    return data.outcome;
  };
  const getRecord = async (actor, appId, versionId, recordId, collectionId) => {
    const data = await execute(actor, {
      op: "spec.getRecord",
      appId,
      versionId,
      recordId,
    });
    verify(
      exactKeys(data, ["record", "versionId"]) &&
        data.versionId === versionId &&
        validRuntimeRecord(data.record, collectionId) &&
        data.record.id === recordId,
    );
    return data.record;
  };
  const query = async (actor, appId, versionId, collectionId, query) => {
    const page = await execute(actor, {
      op: "spec.query",
      appId,
      versionId,
      collectionId,
      query,
    });
    verify(validRuntimePage(page, versionId, collectionId));
    return page;
  };
  async function signIn(actor, freshClient = actor.client) {
    const result = await authRequest(
      freshClient,
      "POST",
      "/account/sessions/email",
      { email: actor.credentials.email, password: actor.credentials.password },
      {
        allowCooldown: configuration.twentyDistinct,
        ...(sleep ? { sleep } : {}),
      },
    );
    verify(result.status === 201, {
      httpStatus: result.status,
      code: result.data?.type,
    });
    verify(freshClient.cookies.size > 0);
    const account = await freshClient.request("GET", "/account");
    verify(
      account.status === 200 && account.data?.$id === actor.credentials.id,
      { httpStatus: account.status },
    );
  }
  async function createActor(label) {
    verify(report.accounts.length < maxAccounts);
    const actor = {
      client: client(),
      credentials: actorCredentials
        ? await readSyntheticCredentials(
            actorCredentials,
            label,
            runId,
            privateValues,
          )
        : {
            id: randomId("usr"),
            email: `tinkerloom-${runId}-${label}@example.test`,
            password: "T!" + randomBytes(24).toString("hex") + "a9",
          },
    };
    privateValues.add(actor.credentials.email);
    privateValues.add(actor.credentials.password);
    verify(!report.accounts.some((value) => value.id === actor.credentials.id));
    actors[label] = actor;
    const accountReport = {
      label,
      id: actor.credentials.id,
      creationStatus: "unconfirmed",
    };
    report.accounts.push(accountReport);
    if (!actorCredentials) {
      const result = await authRequest(
        actor.client,
        "POST",
        "/account",
        {
          userId: actor.credentials.id,
          email: actor.credentials.email,
          password: actor.credentials.password,
          name: "Tinkerloom full QA " + label,
        },
        {
          allowCooldown: configuration.twentyDistinct,
          ...(sleep ? { sleep } : {}),
        },
      );
      accountReport.creationStatus =
        result.status === 201 && result.data?.$id === actor.credentials.id
          ? "created"
          : "unconfirmed";
      verify(
        result.status === 201 && result.data?.$id === actor.credentials.id,
        {
          httpStatus: result.status,
          code: result.data?.type,
        },
      );
    }
    await signIn(actor);
    if (actorCredentials) accountReport.creationStatus = "reused_verified";
    return actor;
  }
  async function invite(actor, appId, role, { inspect = true } = {}) {
    verify(++invitationCount <= 50);
    const token = randomBytes(32).toString("base64url");
    privateValues.add(token);
    const body = {
      op: "createInvitation",
      appId,
      id: randomId("inv"),
      operationId: randomId("ivo"),
      role,
      recipientId: actor.credentials.id,
      token,
    };
    const made = await execute(actors.owner, body);
    verify(
      exactKeys(made, ["invitation"]) &&
        validInvitation(made.invitation, appId),
    );
    verify(
      made.invitation.recipientId === actor.credentials.id &&
        made.invitation.role === role,
    );
    if (inspect) {
      const preview = await execute(actor, { op: "inspectInvitation", token });
      verify(
        exactKeys(preview, ["invitation"]) &&
          validPreview(preview.invitation) &&
          preview.invitation.appId === appId &&
          preview.invitation.role === role,
      );
    }
    const accepted = await execute(actor, {
      op: "acceptInvitation",
      token,
      operationId: randomId("acc"),
    });
    verify(exactKeys(accepted, ["appId"]) && accepted.appId === appId);
  }
  async function grant(actor, appId, role) {
    // setGrant changes an existing grant; invitations establish the first one.
    await invite(actor, appId, role, { inspect: false });
    const current = await app(actor, appId);
    verify(current.role === role);
  }
  async function save(actor, appId, spec, revision, versionId) {
    const body = {
      op: "spec.saveDraft",
      appId,
      operationId: randomId("sav"),
      expectedRevision: revision,
      expectedVersionId: versionId,
      spec,
    };
    const data = await execute(actor, body);
    verify(
      exactKeys(data, ["app"]) &&
        validFullApp(data.app) &&
        data.app.draft?.revision === revision + 1 &&
        data.app.draft.baseVersionId === versionId,
    );
    return { body, receipt: data, app: data.app };
  }
  async function review(actor, appId, draft) {
    const data = await execute(actor, {
      op: "spec.review",
      appId,
      expectedRevision: draft.revision,
      enabledRuleIds: [],
      activateExistingRecordIds: [],
    });
    verify(exactKeys(data, ["review"]) && validReview(data.review));
    verify(
      data.review.candidateHash === draft.candidateHash &&
        data.review.expectedRevision === draft.revision &&
        data.review.baseVersionId === draft.baseVersionId &&
        data.review.compatibilityErrors.length === 0,
    );
    verify(
      equal(data.review.enabledRuleIds, []) &&
        equal(data.review.activateExistingRecordIds, []),
    );
    return data.review;
  }
  async function publish(actor, appId, draft, versionId) {
    const checked = await review(actor, appId, draft);
    const body = {
      op: "spec.publish",
      appId,
      operationId: randomId("pub"),
      expectedRevision: draft.revision,
      expectedVersionId: versionId,
      candidateHash: checked.candidateHash,
      reviewHash: checked.reviewHash,
      enabledRuleIds: [],
      activateExistingRecordIds: [],
    };
    const data = await execute(actor, body);
    verify(
      exactKeys(data, ["app"]) &&
        validFullApp(data.app) &&
        data.app.version?.hash === checked.candidateHash &&
        data.app.draft?.publishedVersionId === data.app.version.id,
    );
    return { body, receipt: data, app: data.app };
  }
  const workspaceId = randomId("wor"),
    foreignWorkspace = randomId("for"),
    readingId = randomId("rea"),
    instances = new Map();
  report.resources = { workspaceId, foreignWorkspace, readingId };
  let catalog,
    firstSave,
    firstPublish,
    currentReading,
    ownerPending,
    builderPublished,
    ownerReview,
    firstRecordCommand,
    firstRecordReceipt,
    firstRecord,
    capacityRecord,
    capacityActors = [],
    trialWinner,
    trialWinningCommand,
    trialWinningReceipt,
    foreignApp;
  try {
    for (const label of ["owner", "builder", "member", "viewer", "outsider"])
      await check("authenticate_" + label, [], async () => {
        await createActor(label);
        return {};
      });
    await check(
      "create_owner_and_foreign_workspaces",
      ["authenticate_owner", "authenticate_outsider"],
      async () => {
        for (const [actor, workspace, name] of [
          [actors.owner, workspaceId, "Full QA workspace"],
          [actors.outsider, foreignWorkspace, "Separate QA workspace"],
        ]) {
          const data = await execute(actor, {
            op: "createWorkspace",
            id: workspace,
            name,
          });
          verify(data.workspace?.id === workspace);
        }
        return {};
      },
    );
    await check(
      "catalog_and_operational_capabilities",
      ["authenticate_owner"],
      async () => {
        const caps = await execute(actors.owner, { op: "spec.capabilities" });
        verify(
          caps.apiVersion === 1 &&
            Array.isArray(caps.formatVersions) &&
            caps.formatVersions.includes(1),
        );
        verify(
          typeof caps.generation === "boolean" &&
            typeof caps.guidance === "boolean" &&
            Array.isArray(caps.effects) &&
            typeof caps.privateMedia === "boolean",
        );
        const result = await execute(actors.owner, { op: "spec.templates" });
        verify(
          exactKeys(result, ["templates"]) &&
            Array.isArray(result.templates) &&
            result.templates.length === 12,
        );
        verify(
          equal(
            [...result.templates.map((item) => item.key)].sort(),
            [...templateKeys].sort(),
          ),
        );
        verify(
          result.templates.every(
            (item) =>
              exactKeys(item, ["key", "name", "spec"]) && validSpec(item.spec),
          ),
        );
        catalog = new Map(
          result.templates.map((item) => [item.key, item.spec]),
        );
        return { templates: 12 };
      },
    );
    await check(
      "manual_empty_shell_and_exact_review_publication",
      [
        "create_owner_and_foreign_workspaces",
        "catalog_and_operational_capabilities",
      ],
      async () => {
        const create = {
          op: "spec.createApp",
          id: readingId,
          workspaceId,
          name: "Full manual QA",
          operationId: randomId("new"),
        };
        const made = await execute(actors.owner, create);
        verify(
          validFullApp(made.app) &&
            made.app.version === null &&
            made.app.draft === null,
        );
        firstSave = await save(
          actors.owner,
          readingId,
          catalog.get("reading"),
          0,
          null,
        );
        firstPublish = await publish(
          actors.owner,
          readingId,
          firstSave.app.draft,
          null,
        );
        currentReading = firstPublish.app;
        verify(currentReading.version.number === 1);
        verify(equal(await execute(actors.owner, create), made));
        return { versions: 1 };
      },
    );
    for (const role of ["builder", "member", "viewer"])
      await check(
        "join_reading_as_" + role,
        [
          "manual_empty_shell_and_exact_review_publication",
          "authenticate_" + role,
        ],
        async () => {
          await invite(actors[role], readingId, role);
          const value = await app(actors[role], readingId);
          verify(
            value.role === role &&
              value.draft === null &&
              value.generation === null,
          );
          return {};
        },
      );
    for (const key of templateKeys)
      await check(
        "instantiate_" + key,
        [
          "create_owner_and_foreign_workspaces",
          "catalog_and_operational_capabilities",
        ],
        async () => {
          const id = randomId("tpl"),
            body = {
              op: "spec.instantiate",
              id,
              workspaceId,
              templateKey: key,
              operationId: randomId("ins"),
            };
          const result = await execute(actors.owner, body);
          verify(
            exactKeys(result, ["app"]) &&
              validFullApp(result.app) &&
              result.app.id === id &&
              result.app.version.number === 1 &&
              result.app.draft === null,
          );
          verify(result.app.version.spec.name === catalog.get(key).name);
          instances.set(key, { app: result.app, body, receipt: result });
          report.resources.templateApps ??= {};
          report.resources.templateApps[key] = id;
          verify(equal(await execute(actors.owner, body), result));
          await execute(
            actors.owner,
            { ...body, templateKey: key === "notes" ? "reading" : "notes" },
            409,
            "operation_conflict",
          );
          return {};
        },
      );
    await check(
      "template_instances_have_no_copied_records",
      [
        "instantiate_planner",
        "instantiate_projectHub",
        "instantiate_volunteer",
        "instantiate_reading",
        "instantiate_habitTracker",
        "instantiate_calendar",
        "instantiate_notes",
        "instantiate_chores",
        "instantiate_photoJournal",
        "instantiate_reminders",
        "instantiate_focus",
        "instantiate_phoneToolkit",
      ],
      async () => {
        const result = await execute(actors.owner, {
          op: "spec.launcher",
          workspaceId,
          limit: 50,
        });
        verify(Array.isArray(result.apps) && result.nextCursor === null);
        for (const value of instances.values()) {
          const entry = result.apps.find((item) => item.id === value.app.id);
          verify(
            entry?.engine === "appspec.v1" &&
              entry.recordCount === 0 &&
              entry.version.id === value.app.version.id,
          );
        }
        return { templates: 12 };
      },
    );
    await check(
      "private_author_drafts_and_global_stale_publication",
      ["join_reading_as_builder"],
      async () => {
        const base = currentReading.version.id,
          ownSpec = {
            ...catalog.get("reading"),
            name: "Private owner candidate",
          },
          builderSpec = {
            ...catalog.get("reading"),
            name: "Private builder candidate",
          };
        ownerPending = await save(actors.owner, readingId, ownSpec, 1, base);
        const other = await save(
          actors.builder,
          readingId,
          builderSpec,
          0,
          base,
        );
        ownerReview = await review(
          actors.owner,
          readingId,
          ownerPending.app.draft,
        );
        verify(
          (await app(actors.owner, readingId)).draft.spec.name === ownSpec.name,
        );
        verify(
          (await app(actors.builder, readingId)).draft.spec.name ===
            builderSpec.name,
        );
        builderPublished = await publish(
          actors.builder,
          readingId,
          other.app.draft,
          base,
        );
        verify(builderPublished.app.version.number === 2);
        const stale = {
          op: "spec.publish",
          appId: readingId,
          operationId: randomId("old"),
          expectedRevision: ownerPending.app.draft.revision,
          expectedVersionId: base,
          candidateHash: ownerReview.candidateHash,
          reviewHash: ownerReview.reviewHash,
          enabledRuleIds: [],
          activateExistingRecordIds: [],
        };
        await execute(actors.owner, stale, 409, "definition_conflict");
        const list = await execute(actors.owner, {
          op: "spec.listDrafts",
          workspaceId,
          limit: 50,
        });
        verify(
          Array.isArray(list.drafts) &&
            list.drafts.some(
              (value) =>
                value.appId === readingId &&
                value.engine === "appspec.v1" &&
                value.stale === true,
            ),
        );
        const rebased = await save(
          actors.owner,
          readingId,
          ownSpec,
          2,
          builderPublished.app.version.id,
        );
        const published = await publish(
          actors.owner,
          readingId,
          rebased.app.draft,
          builderPublished.app.version.id,
        );
        currentReading = published.app;
        verify(currentReading.version.number === 3);
        return { versions: 3 };
      },
    );
    await check(
      "exact_definition_receipts_survive_newer_publication_and_changed_input_conflicts",
      ["private_author_drafts_and_global_stale_publication"],
      async () => {
        verify(
          equal(await execute(actors.owner, firstSave.body), firstSave.receipt),
        );
        verify(
          equal(
            await execute(actors.owner, firstPublish.body),
            firstPublish.receipt,
          ),
        );
        await execute(
          actors.owner,
          {
            ...firstSave.body,
            spec: { ...firstSave.body.spec, name: "Changed same operation" },
          },
          409,
          "operation_conflict",
        );
        await execute(
          actors.owner,
          { ...firstPublish.body, reviewHash: "0".repeat(64) },
          409,
          "operation_conflict",
        );
        await execute(
          actors.owner,
          { ...firstPublish.body, operationId: randomId("rep") },
          409,
          "revision_conflict",
        );
        return {};
      },
    );
    await check(
      "private_drafts_do_not_leak_to_member_or_viewer",
      [
        "private_author_drafts_and_global_stale_publication",
        "join_reading_as_member",
        "join_reading_as_viewer",
      ],
      async () => {
        for (const role of ["member", "viewer"]) {
          const value = await app(actors[role], readingId);
          verify(
            value.draft === null &&
              value.generation === null &&
              value.allowedActions.length === 0 &&
              value.capabilities.writeRecords === false,
          );
          await execute(
            actors[role],
            {
              op: "spec.saveDraft",
              appId: readingId,
              operationId: randomId("no"),
              expectedRevision: 0,
              expectedVersionId: currentReading.version.id,
              spec: catalog.get("reading"),
            },
            403,
            "forbidden",
          );
        }
        return {};
      },
    );
    await check(
      "seed_115_typed_records_and_exact_create_receipt",
      ["private_author_drafts_and_global_stale_publication"],
      async () => {
        for (let i = 0; i < 115; i++) {
          const data = {
            title: "Book " + String(i).padStart(3, "0"),
            status: i % 2 === 0 ? "Reading" : "Finished",
            notes: i % 3 === 0 ? "ALPHA note" : "Beta",
            ...(i < 100 ? { rating: i } : {}),
          };
          const body = command(
            readingId,
            currentReading.version.id,
            "addBook",
            { data },
          );
          const result = await execute(actors.owner, body);
          verify(validOutcome(result));
          if (i === 0) {
            firstRecordCommand = body;
            firstRecordReceipt = result;
            firstRecord = result.outcome.recordId;
            report.resources.firstRecordId = firstRecord;
            verify(equal(await execute(actors.owner, body), result));
            await execute(
              actors.owner,
              {
                ...body,
                input: { data: { ...data, title: "Changed same operation" } },
              },
              409,
              "operation_conflict",
            );
          }
        }
        return { records: 115 };
      },
    );
    await check(
      "owner_builder_member_viewer_and_outsider_personal_policy",
      [
        "seed_115_typed_records_and_exact_create_receipt",
        "join_reading_as_builder",
        "join_reading_as_member",
        "join_reading_as_viewer",
        "authenticate_outsider",
      ],
      async () => {
        for (const role of ["owner", "builder", "member", "viewer"]) {
          const value = await app(actors[role], readingId);
          verify(value.role === role);
          const record = await getRecord(
            actors[role],
            readingId,
            currentReading.version.id,
            firstRecord,
            "books",
          );
          verify(record.data.rating === 0 && record.data.status === "Reading");
          if (["member", "viewer"].includes(role)) {
            verify(record.allowedActions.length === 0);
            await execute(
              actors[role],
              command(readingId, currentReading.version.id, "addBook", {
                data: { title: "Denied", status: "Reading" },
              }),
              403,
              "forbidden",
            );
          }
        }
        await action(
          actors.builder,
          command(
            readingId,
            currentReading.version.id,
            "editBook",
            { data: { author: "QA builder" } },
            firstRecord,
            1,
          ),
        );
        await execute(
          actors.outsider,
          { op: "spec.getApp", appId: readingId },
          404,
          "not_found",
        );
        await execute(
          actors.outsider,
          {
            op: "spec.query",
            appId: readingId,
            versionId: currentReading.version.id,
            collectionId: "books",
            query: {},
          },
          404,
          "not_found",
        );
        return {};
      },
    );
    await check(
      "ranked_pages_and_global_numeric_aggregates",
      ["seed_115_typed_records_and_exact_create_receipt"],
      async () => {
        const version = currentReading.version.id,
          q = {
            filters: [
              { fieldId: "notes", operator: "contains", value: "alpha" },
            ],
            sort: [
              { fieldId: "rating", descending: true },
              { fieldId: "title", descending: false },
            ],
            limit: 7,
          },
          ids = new Set();
        let cursor = null,
          total = 0,
          pages = 0,
          prior = Infinity,
          sawUnset = false;
        do {
          const result = await query(
            actors.owner,
            readingId,
            version,
            "books",
            { ...q, ...(cursor ? { cursor } : {}) },
          );
          pages++;
          verify(pages <= 10);
          total = result.total;
          for (const record of result.records) {
            verify(!ids.has(record.id));
            ids.add(record.id);
            if (!Object.hasOwn(record.data, "rating")) sawUnset = true;
            else {
              verify(!sawUnset && record.data.rating <= prior);
              prior = record.data.rating;
            }
          }
          cursor = result.nextCursor;
        } while (cursor);
        verify(total === 39 && ids.size === 39 && sawUnset);
        const base = {
            appId: readingId,
            versionId: version,
            collectionId: "books",
            query: { limit: 1 },
          },
          summary = await execute(actors.owner, {
            op: "spec.summary",
            ...base,
            groupFieldId: "status",
          });
        verify(
          exactKeys(summary, ["total", "groups", "versionId"]) &&
            summary.total === 115 &&
            summary.versionId === version &&
            summary.groups.Reading === 58 &&
            summary.groups.Finished === 57,
        );
        for (const [metric, expected] of [
          ["sum", 4950],
          ["average", 49.5],
        ]) {
          const result = await execute(actors.owner, {
            op: "spec.aggregate",
            ...base,
            aggregate: { metric, fieldId: "rating" },
          });
          verify(
            validAggregate(result, version) &&
              result.total === 115 &&
              result.value === expected,
          );
        }
        const unset = await query(actors.owner, readingId, version, "books", {
          filters: [{ fieldId: "rating", operator: "eq", value: null }],
          limit: 100,
        });
        verify(unset.total === 15 && unset.records.length === 15);
        const first = await query(actors.owner, readingId, version, "books", {
          limit: 1,
        });
        verify(typeof first.nextCursor === "string");
        await execute(
          actors.owner,
          {
            op: "spec.query",
            appId: readingId,
            versionId: version,
            collectionId: "books",
            query: {
              limit: 1,
              cursor: first.nextCursor,
              filters: [
                { fieldId: "title", operator: "eq", value: "Book 000" },
              ],
            },
          },
          400,
          "invalid_request",
        );
        // A cursor whose anchor no longer matches must fail rather than restart.
        const anchorQuery = {
          filters: [{ fieldId: "notes", operator: "contains", value: "alpha" }],
          sort: [{ fieldId: "title", descending: false }],
          limit: 1,
        };
        const anchored = await query(
          actors.owner,
          readingId,
          version,
          "books",
          anchorQuery,
        );
        verify(
          typeof anchored.nextCursor === "string" &&
            anchored.records.length === 1,
        );
        const anchor = anchored.records[0];
        await action(
          actors.owner,
          command(
            readingId,
            version,
            "editBook",
            {
              data: { notes: "Retired cursor anchor" },
            },
            anchor.id,
            anchor.revision,
          ),
        );
        await execute(
          actors.owner,
          {
            op: "spec.query",
            appId: readingId,
            versionId: version,
            collectionId: "books",
            query: { ...anchorQuery, cursor: anchored.nextCursor },
          },
          409,
          "revision_conflict",
        );
        return { records: 115, pages };
      },
    );
    for (const key of ["chores", "volunteer"])
      await check(
        "grant_roles_" + key,
        [
          "instantiate_" + key,
          "join_reading_as_builder",
          "join_reading_as_member",
          "join_reading_as_viewer",
        ],
        async () => {
          for (const role of ["builder", "member", "viewer"])
            await grant(actors[role], instances.get(key).app.id, role);
          return {};
        },
      );
    await check(
      "workflow_assignment_and_protected_fields",
      ["grant_roles_chores", "authenticate_outsider"],
      async () => {
        const target = instances.get("chores").app,
          version = target.version.id;
        const made = await action(
          actors.member,
          command(target.id, version, "addChore", {
            data: {
              title: "Synthetic chore",
              status: "Open",
              assignee: actors.builder.credentials.id,
            },
          }),
        );
        const record = made.recordId;
        await execute(
          actors.member,
          command(
            target.id,
            version,
            "editChore",
            { data: { status: "Done" } },
            record,
            1,
          ),
          403,
          "forbidden",
        );
        await execute(
          actors.member,
          command(
            target.id,
            version,
            "editChore",
            { data: { assignee: actors.owner.credentials.id } },
            record,
            1,
          ),
          403,
          "forbidden",
        );
        await execute(
          actors.member,
          command(
            target.id,
            version,
            "moveChore",
            { value: "Done" },
            record,
            1,
          ),
          400,
          "invalid_values",
        );
        await action(
          actors.member,
          command(
            target.id,
            version,
            "moveChore",
            { value: "Doing" },
            record,
            1,
          ),
        );
        await action(
          actors.member,
          command(
            target.id,
            version,
            "assignChore",
            { value: actors.member.credentials.id },
            record,
            2,
          ),
        );
        await action(
          actors.member,
          command(
            target.id,
            version,
            "editChore",
            { data: { notes: "Ordinary member patch" } },
            record,
            3,
          ),
        );
        await execute(
          actors.member,
          command(
            target.id,
            version,
            "editChore",
            { data: { notes: "Stale" } },
            record,
            1,
          ),
          409,
          "revision_conflict",
        );
        await execute(
          actors.member,
          command(
            target.id,
            version,
            "assignChore",
            { value: actors.outsider.credentials.id },
            record,
            4,
          ),
          400,
          "invalid_values",
        );
        await execute(
          actors.viewer,
          command(
            target.id,
            version,
            "moveChore",
            { value: "Done" },
            record,
            4,
          ),
          403,
          "forbidden",
        );
        const current = await getRecord(
          actors.member,
          target.id,
          version,
          record,
          "chores",
        );
        verify(
          current.data.status === "Doing" &&
            current.data.assignee === actors.member.credentials.id &&
            current.revision === 4,
        );
        return {};
      },
    );
    await check(
      "capacity_create_policy_timestamp_and_date_bucket_boundaries",
      ["grant_roles_volunteer"],
      async () => {
        const target = instances.get("volunteer").app,
          version = target.version.id;
        await execute(
          actors.member,
          command(target.id, version, "addShift", {
            data: {
              title: "Denied member create",
              startsAt: "2030-01-01T00:00:00Z",
            },
            capacity: 1,
          }),
          403,
          "forbidden",
        );
        await execute(
          actors.owner,
          command(target.id, version, "addShift", {
            data: {
              title: "Civil date is not a timestamp",
              startsAt: "2030-01-01",
            },
            capacity: 1,
          }),
          400,
          "invalid_values",
        );
        const created = await action(
          actors.owner,
          command(target.id, version, "addShift", {
            data: {
              title: "Final place",
              startsAt: "2030-01-01T00:00:00.123456Z",
            },
            capacity: 1,
          }),
        );
        capacityRecord = created.recordId;
        report.resources.capacityRecord = capacityRecord;
        const value = await getRecord(
          actors.owner,
          target.id,
          version,
          capacityRecord,
          "shifts",
        );
        verify(
          value.capacity === 1 &&
            value.allocated === 0 &&
            value.data.startsAt === "2030-01-01T00:00:00.123456Z",
        );
        const aggregate = await execute(actors.owner, {
          op: "spec.aggregate",
          appId: target.id,
          versionId: version,
          collectionId: "shifts",
          query: { limit: 1 },
          aggregate: {
            metric: "count",
            dateFieldId: "startsAt",
            buckets: [
              {
                key: "before",
                start: "2030-01-01T00:00:00.000000Z",
                end: "2030-01-01T00:00:00.123456Z",
              },
              {
                key: "at",
                start: "2030-01-01T00:00:00.123456Z",
                end: "2030-01-01T00:00:01.000000Z",
              },
            ],
          },
        });
        verify(
          validAggregate(aggregate, version) &&
            aggregate.total === 1 &&
            aggregate.groups.find((g) => g.key === "before")?.count === 0 &&
            aggregate.groups.find((g) => g.key === "at")?.count === 1,
        );
        await execute(
          actors.viewer,
          command(target.id, version, "join", {}, capacityRecord),
          403,
          "forbidden",
        );
        capacityActors = [actors.owner, actors.builder, actors.member];
        return {};
      },
    );
    if (configuration.twentyDistinct)
      await check(
        "explicit_twenty_actor_auth_pool",
        ["capacity_create_policy_timestamp_and_date_bucket_boundaries"],
        async () => {
          for (let i = 1; i <= 17; i++) {
            const actor = await createActor(
              "capacity_" + String(i).padStart(2, "0"),
            );
            await invite(actor, instances.get("volunteer").app.id, "member", {
              inspect: false,
            });
            const current = await app(actor, instances.get("volunteer").app.id);
            verify(
              current.role === "member" &&
                current.allowedActions.includes("join"),
            );
            capacityActors.push(actor);
          }
          verify(
            new Set(capacityActors.map((actor) => actor.credentials.id))
              .size === 20,
          );
          return { distinctActors: 20 };
        },
      );
    await check(
      "twenty_concurrent_unique_final_capacity_attempts",
      [
        "capacity_create_policy_timestamp_and_date_bucket_boundaries",
        ...(configuration.twentyDistinct
          ? ["explicit_twenty_actor_auth_pool"]
          : []),
      ],
      async () => {
        const target = instances.get("volunteer").app,
          version = target.version.id;
        for (const actor of capacityActors) {
          const current = await app(actor, target.id);
          verify(current.allowedActions.includes("join"));
        }
        const attempts = Array.from({ length: 20 }, (_, index) => ({
          actor: capacityActors[index % capacityActors.length],
          body: command(target.id, version, "join", {}, capacityRecord),
        }));
        report.capacityTrial.submittedAttempts = attempts.length;
        report.capacityTrial.uniqueOperationIds = new Set(
          attempts.map((v) => v.body.operationId),
        ).size;
        report.capacityTrial.distinctAuthenticatedActors = new Set(
          attempts.map((v) => v.actor.credentials.id),
        ).size;
        verify(report.capacityTrial.uniqueOperationIds === 20);
        verify(
          report.capacityTrial.distinctAuthenticatedActors ===
            (configuration.twentyDistinct ? 20 : 3),
        );
        budget.beginTrial();
        const results = await Promise.allSettled(
          attempts.map(async (attempt) =>
            attempt.actor.client.execute(attempt.body),
          ),
        );
        report.capacityTrial.peakConcurrentHttp = budget.endTrial();
        verify(
          results.every((result) => result.status === "fulfilled"),
          {
            attempts: 20,
            distinctActors: report.capacityTrial.distinctAuthenticatedActors,
          },
        );
        const returned = results.map((result) => result.value);
        let success = 0;
        for (const result of returned) {
          if (
            result.outer.status >= 200 &&
            result.outer.status < 300 &&
            result.status === 200
          ) {
            expect(result);
            verify(validOutcome(result.data));
            success++;
          } else {
            verify(
              result.outer.status >= 200 &&
                result.outer.status < 300 &&
                result.executionStatus === "completed" &&
                result.deploymentMatched &&
                result.status === 409 &&
                ["transaction_conflict", "exhausted_capacity"].includes(
                  result.data?.error,
                ),
              functionObservation(result),
            );
          }
        }
        verify(success > 0);
        verify(report.capacityTrial.peakConcurrentHttp === 20);
        const claimed = [];
        for (const actor of capacityActors) {
          const current = await getRecord(
            actor,
            target.id,
            version,
            capacityRecord,
            "shifts",
          );
          verify(current.capacity === 1 && current.allocated === 1);
          if (current.claimed) claimed.push(actor);
        }
        verify(claimed.length === 1, {
          claimedActors: claimed.length,
          allocated: 1,
          capacity: 1,
        });
        trialWinner = claimed[0];
        const winningIndex = attempts.findIndex(
          (attempt, index) =>
            attempt.actor === trialWinner && returned[index].status === 200,
        );
        verify(winningIndex >= 0);
        trialWinningCommand = attempts[winningIndex].body;
        trialWinningReceipt = returned[winningIndex].data;
        report.capacityTrial.successResponses = success;
        report.capacityTrial.distinctClaimedActors = claimed.length;
        report.capacityTrial.committedAllocationObserved = 1;
        return {
          attempts: 20,
          uniqueOperations: 20,
          distinctActors: report.capacityTrial.distinctAuthenticatedActors,
          successResponses: success,
          claimedActors: 1,
          allocated: 1,
          capacity: 1,
          peakConcurrentHttp: report.capacityTrial.peakConcurrentHttp,
        };
      },
    );
    await check(
      "capacity_receipt_counter_release_reactivation_and_configuration",
      ["twenty_concurrent_unique_final_capacity_attempts"],
      async () => {
        const target = instances.get("volunteer").app,
          version = target.version.id;
        verify(
          equal(
            await execute(trialWinner, trialWinningCommand),
            trialWinningReceipt,
          ),
        );
        await execute(
          actors.member,
          command(
            target.id,
            version,
            "configure",
            { capacity: 2 },
            capacityRecord,
          ),
          403,
          "forbidden",
        );
        await execute(
          actors.owner,
          command(
            target.id,
            version,
            "configure",
            { capacity: 0 },
            capacityRecord,
          ),
          400,
          "invalid_values",
        );
        await action(
          trialWinner,
          command(target.id, version, "leave", {}, capacityRecord),
        );
        await action(
          trialWinner,
          command(target.id, version, "leave", {}, capacityRecord),
        );
        verify(
          (
            await getRecord(
              actors.owner,
              target.id,
              version,
              capacityRecord,
              "shifts",
            )
          ).allocated === 0,
        );
        verify(
          equal(
            await execute(trialWinner, trialWinningCommand),
            trialWinningReceipt,
          ),
        );
        verify(
          (
            await getRecord(
              actors.owner,
              target.id,
              version,
              capacityRecord,
              "shifts",
            )
          ).allocated === 0,
        );
        await action(
          actors.owner,
          command(
            target.id,
            version,
            "configure",
            { capacity: 2 },
            capacityRecord,
          ),
        );
        let state = await getRecord(
          actors.owner,
          target.id,
          version,
          capacityRecord,
          "shifts",
        );
        verify(state.capacity === 2 && state.allocated === 0);
        await action(
          actors.owner,
          command(
            target.id,
            version,
            "configure",
            { capacity: 1 },
            capacityRecord,
          ),
        );
        await action(
          trialWinner,
          command(target.id, version, "join", {}, capacityRecord),
        );
        state = await getRecord(
          trialWinner,
          target.id,
          version,
          capacityRecord,
          "shifts",
        );
        verify(state.allocated === 1 && state.claimed);
        const loser = capacityActors.find((actor) => actor !== trialWinner);
        await execute(
          loser,
          command(target.id, version, "join", {}, capacityRecord),
          409,
          "exhausted_capacity",
        );
        return { allocated: 1, capacity: 1 };
      },
    );
    await check(
      "numeric_rejections_leave_record_population_unchanged",
      [
        "ranked_pages_and_global_numeric_aggregates",
        "instantiate_habitTracker",
      ],
      async () => {
        const version = currentReading.version.id;
        const ratingField = currentReading.version.spec.collections
          .find((value) => value.id === "books")
          ?.fields.find((value) => value.id === "rating");
        verify(ratingField?.type === "integer");
        for (const rating of fullNumericCases(ratingField.type).invalid)
          await execute(
            actors.owner,
            command(readingId, version, "addBook", {
              data: { title: "Rejected numeric", status: "Reading", rating },
            }),
            400,
            "invalid_values",
          );
        verify(
          (await query(actors.owner, readingId, version, "books", { limit: 1 }))
            .total === 115,
        );
        // Keep NUMBER's distinct ±1e15 requirement on a real number field.
        const habit = instances.get("habitTracker").app;
        const minutesField = habit.version.spec.collections
          .find((value) => value.id === "checkins")
          ?.fields.find((value) => value.id === "minutes");
        verify(minutesField?.type === "number");
        const numberCases = fullNumericCases(minutesField.type);
        const numberBase = {
          title: "Numeric boundary",
          loggedAt: "2026-01-01T00:00:00.000Z",
        };
        const beforeNumbers = await query(
          actors.owner,
          habit.id,
          habit.version.id,
          "checkins",
          { limit: 1 },
        );
        for (const minutes of numberCases.valid) {
          const written = await action(
            actors.owner,
            command(habit.id, habit.version.id, "addRecord", {
              data: { ...numberBase, minutes },
            }),
          );
          const persisted = await getRecord(
            actors.owner,
            habit.id,
            habit.version.id,
            written.recordId,
            "checkins",
          );
          verify(persisted.data.minutes === minutes);
        }
        for (const minutes of numberCases.invalid)
          await execute(
            actors.owner,
            command(habit.id, habit.version.id, "addRecord", {
              data: { ...numberBase, minutes },
            }),
            400,
            "invalid_values",
          );
        const afterNumbers = await query(
          actors.owner,
          habit.id,
          habit.version.id,
          "checkins",
          { limit: 1 },
        );
        verify(
          afterNumbers.total === beforeNumbers.total + numberCases.valid.length,
        );
        return { records: 115 };
      },
    );
    await check(
      "immutable_history_remix_and_actor_private_pins",
      [
        "private_author_drafts_and_global_stale_publication",
        "ranked_pages_and_global_numeric_aggregates",
        "join_reading_as_viewer",
      ],
      async () => {
        const seen = [],
          ids = new Set();
        let before;
        do {
          const result = await execute(actors.viewer, {
            op: "spec.listVersions",
            appId: readingId,
            limit: 1,
            ...(before === undefined ? {} : { beforeNumber: before }),
          });
          verify(
            exactKeys(result, [
              "versions",
              "currentVersionId",
              "nextBeforeNumber",
            ]) &&
              result.currentVersionId === currentReading.version.id &&
              Array.isArray(result.versions) &&
              result.versions.length === 1 &&
              result.versions.every((value) => validVersion(value)),
          );
          for (const value of result.versions) {
            verify(!ids.has(value.id));
            ids.add(value.id);
            seen.push(value.number);
          }
          before = result.nextBeforeNumber;
          verify(before === null || Number.isInteger(before));
        } while (before !== null);
        verify(equal(seen, [3, 2, 1]));
        const historical = await execute(actors.viewer, {
          op: "spec.getVersion",
          appId: readingId,
          versionId: firstPublish.app.version.id,
        });
        verify(
          exactKeys(historical, ["version", "currentVersionId"]) &&
            validVersion(historical.version, true) &&
            historical.version.hash === firstPublish.app.version.hash &&
            historical.version.spec.name === catalog.get("reading").name,
        );
        const copyId = randomId("mix"),
          body = {
            op: "spec.remix",
            id: copyId,
            workspaceId,
            sourceAppId: readingId,
            sourceVersionId: currentReading.version.id,
            operationId: randomId("mix"),
          };
        const copied = await execute(actors.owner, body);
        verify(
          validFullApp(copied.app) &&
            copied.app.id === copyId &&
            copied.app.version.number === 1 &&
            copied.app.version.id !== currentReading.version.id &&
            copied.app.version.hash === currentReading.version.hash,
        );
        verify(equal(await execute(actors.owner, body), copied));
        verify(
          (
            await query(actors.owner, copyId, copied.app.version.id, "books", {
              limit: 1,
            })
          ).total === 0,
        );
        await execute(
          actors.member,
          { op: "spec.getApp", appId: copyId },
          404,
          "not_found",
        );
        // Manual spec.createApp intentionally does not auto-pin its creator.
        const ownerPinned = await execute(actors.owner, {
          op: "spec.setPinned",
          appId: readingId,
          pinned: true,
          expectedRevision: 0,
          operationId: randomId("own"),
        });
        verify(
          equal(ownerPinned, {
            shortcut: { appId: readingId, pinned: true, revision: 1 },
          }),
        );
        const pin = {
            op: "spec.setPinned",
            appId: readingId,
            pinned: true,
            expectedRevision: 0,
            operationId: randomId("pin"),
          },
          pinned = await execute(actors.viewer, pin);
        verify(
          equal(pinned, {
            shortcut: { appId: readingId, pinned: true, revision: 1 },
          }),
        );
        verify(equal(await execute(actors.viewer, pin), pinned));
        await execute(
          actors.viewer,
          { ...pin, pinned: false },
          409,
          "operation_conflict",
        );
        const unpinned = await execute(actors.viewer, {
          ...pin,
          pinned: false,
          expectedRevision: 1,
          operationId: randomId("unp"),
        });
        verify(
          equal(unpinned, {
            shortcut: { appId: readingId, pinned: false, revision: 2 },
          }),
        );
        const ownerLauncher = await execute(actors.owner, {
          op: "spec.launcher",
          workspaceId,
          limit: 50,
          pinnedOnly: true,
        });
        verify(
          Array.isArray(ownerLauncher.apps) &&
            ownerLauncher.apps.some(
              (value) => value.id === readingId && value.pinned === true,
            ),
        );
        const viewerLauncher = await execute(actors.viewer, {
          op: "spec.launcher",
          workspaceId,
          limit: 50,
          pinnedOnly: true,
        });
        verify(
          Array.isArray(viewerLauncher.apps) &&
            !viewerLauncher.apps.some((value) => value.id === readingId),
        );
        return { versions: 3 };
      },
    );
    await check(
      "cross_workspace_and_parent_substitution_denials",
      [
        "seed_115_typed_records_and_exact_create_receipt",
        "instantiate_volunteer",
        "create_owner_and_foreign_workspaces",
      ],
      async () => {
        const made = await execute(actors.outsider, {
          op: "spec.instantiate",
          id: randomId("far"),
          workspaceId: foreignWorkspace,
          templateKey: "reading",
          operationId: randomId("far"),
        });
        verify(validFullApp(made.app));
        foreignApp = made.app;
        report.resources.foreignAppId = foreignApp.id;
        await execute(
          actors.owner,
          { op: "spec.getApp", appId: foreignApp.id },
          404,
          "not_found",
        );
        await execute(
          actors.outsider,
          {
            op: "spec.getRecord",
            appId: readingId,
            versionId: currentReading.version.id,
            recordId: firstRecord,
          },
          404,
          "not_found",
        );
        const deniedId = randomId("no");
        await execute(
          actors.owner,
          {
            op: "spec.createApp",
            id: deniedId,
            workspaceId: foreignWorkspace,
            name: "Must not cross tenants",
            operationId: randomId("no"),
          },
          404,
          "not_found",
        );
        await execute(
          actors.outsider,
          { op: "spec.getApp", appId: deniedId },
          404,
          "not_found",
        );
        const capacity = instances.get("volunteer").app;
        await execute(
          actors.owner,
          {
            op: "spec.getRecord",
            appId: capacity.id,
            versionId: capacity.version.id,
            recordId: firstRecord,
          },
          404,
          "not_found",
        );
        await execute(
          actors.owner,
          {
            op: "spec.getRecord",
            appId: readingId,
            versionId: capacity.version.id,
            recordId: firstRecord,
          },
          409,
          "definition_conflict",
        );
        return {};
      },
    );
    await check(
      "known_existing_private_rows_and_direct_write_are_denied",
      [
        "seed_115_typed_records_and_exact_create_receipt",
        "capacity_receipt_counter_release_reactivation_and_configuration",
      ],
      async () => {
        const capacity = instances.get("volunteer").app,
          pool = identity("p", [capacityRecord, "places"]),
          rows = [
            ["apps", readingId],
            ["spec_versions", firstPublish.app.version.id],
            ["spec_records", firstRecord],
            ["receipts", firstRecordCommand.operationId],
            [
              "spec_drafts",
              identity("s", [readingId, actors.owner.credentials.id]),
            ],
            ["spec_pools", pool],
            ["spec_claims", identity("c", [pool, trialWinner.credentials.id])],
            [
              "audit",
              identity("a", [readingId, firstRecordCommand.operationId]),
            ],
            [
              "outbox",
              identity("o", [readingId, firstRecordCommand.operationId]),
            ],
          ];
        let denials = 0;
        for (const [table, rowId] of rows) {
          const result = await actors.owner.client.request(
            "GET",
            `/tablesdb/${encodeURIComponent(configuration.databaseId)}/tables/${table}/rows/${encodeURIComponent(rowId)}`,
          );
          verify(isFullPrivateRowDenied(result, { knownExistingRow: true }), {
            httpStatus: result.status,
            code: result.data?.type,
          });
          verify(!containsPrivateRowFields(result.data));
          denials++;
        }
        const write = await actors.owner.client.request(
          "POST",
          `/tablesdb/${encodeURIComponent(configuration.databaseId)}/tables/apps/rows`,
          {
            rowId: randomId("raw"),
            data: {
              ownerId: actors.owner.credentials.id,
              workspaceId,
              name: "Unauthorized direct row",
            },
            permissions: [],
          },
        );
        verify(
          isFullPrivateRowDenied(write) && [401, 403].includes(write.status),
          {
            httpStatus: write.status,
            code: write.data?.type,
          },
        );
        return { rowDenials: denials };
      },
    );
    await check(
      "fresh_cookie_session_reloads_persisted_versions_and_records",
      ["ranked_pages_and_global_numeric_aggregates"],
      async () => {
        const fresh = client();
        await signIn(actors.owner, fresh);
        const value = await execute(
          { client: fresh },
          { op: "spec.getApp", appId: readingId },
        );
        verify(
          validFullApp(value.app) &&
            value.app.version.id === currentReading.version.id,
        );
        const record = await getRecord(
          { client: fresh },
          readingId,
          currentReading.version.id,
          firstRecord,
          "books",
        );
        verify(record.data.title === "Book 000");
        const all = await query(
          { client: fresh },
          readingId,
          currentReading.version.id,
          "books",
          { limit: 1 },
        );
        verify(all.total === 115);
        return { records: 115 };
      },
    );
    await check(
      "archive_keeps_exact_receipts_but_blocks_new_writes",
      [
        "exact_definition_receipts_survive_newer_publication_and_changed_input_conflicts",
        "owner_builder_member_viewer_and_outsider_personal_policy",
      ],
      async () => {
        const archive = {
            op: "archiveApp",
            appId: readingId,
            operationId: randomId("arc"),
          },
          receipt = await execute(actors.owner, archive);
        verify(receipt.app?.id === readingId && receipt.app.archived === true);
        verify(equal(await execute(actors.owner, archive), receipt));
        const archived = await app(actors.owner, readingId);
        verify(
          archived.archived &&
            archived.version.id === currentReading.version.id &&
            archived.allowedActions.length === 0 &&
            archived.capabilities.writeRecords === false,
        );
        verify(
          equal(
            await execute(actors.owner, firstRecordCommand),
            firstRecordReceipt,
          ),
        );
        verify(
          equal(await execute(actors.owner, firstSave.body), firstSave.receipt),
        );
        verify(
          equal(
            await execute(actors.owner, firstPublish.body),
            firstPublish.receipt,
          ),
        );
        await execute(
          actors.owner,
          command(readingId, currentReading.version.id, "addBook", {
            data: { title: "No archived write", status: "Reading" },
          }),
          403,
          "app_archived",
        );
        await execute(
          actors.builder,
          {
            op: "spec.saveDraft",
            appId: readingId,
            expectedRevision: 1,
            expectedVersionId: currentReading.version.id,
            operationId: randomId("no"),
            spec: catalog.get("reading"),
          },
          403,
          "app_archived",
        );
        const read = await getRecord(
          actors.viewer,
          readingId,
          currentReading.version.id,
          firstRecord,
          "books",
        );
        verify(read.allowedActions.length === 0);
        const changed = await execute(actors.owner, {
          op: "setGrant",
          appId: readingId,
          actorId: actors.builder.credentials.id,
          role: null,
          expectedRevision: 1,
          operationId: randomId("rev"),
        });
        verify(object(changed));
        await execute(actors.builder, builderPublished.body, 404, "not_found");
        await execute(
          actors.builder,
          { op: "spec.getApp", appId: readingId },
          404,
          "not_found",
        );
        return {};
      },
    );
  } catch (error) {
    report.checks.push({
      name: "probe_setup",
      status: "failed",
      assertions: 0,
      code:
        error instanceof FullProbeError ? error.code : "unexpected_probe_error",
    });
  } finally {
    for (let index = 0; index < createdClients.length; index++) {
      const current = createdClients[index];
      if (!current.cookies.size) continue;
      await check("temporary_session_signout_" + index, [], async () => {
        const result = await current.request(
          "DELETE",
          "/account/sessions/current",
          undefined,
          { cleanup: true },
        );
        verify(result.status === 204, {
          httpStatus: result.status,
          code: result.data?.type,
        });
        current.cookies.clear();
        return {};
      });
    }
  }
  report.completedAt = new Date().toISOString();
  report.budget.httpRequests = budget.used;
  report.budget.peakConcurrentHttp = budget.peak;
  report.budget.syntheticAccountsAttempted = report.accounts.length;
  report.budget.syntheticAccountsCreated = report.accounts.filter(
    (value) => value.creationStatus === "created",
  ).length;
  report.budget.reusedVerifiedSyntheticAccounts = report.accounts.filter(
    (value) => value.creationStatus === "reused_verified",
  ).length;
  report.budget.invitationsIssued = invitationCount;
  report.target.coreDeploymentMatchedExecutions = createdClients.reduce(
    (sum, value) => sum + value.deploymentMatches,
    0,
  );
  report.status =
    report.checks.length > 0 &&
    report.checks.every((value) => value.status === "passed")
      ? "passed"
      : "failed";
  report.summary = {
    passed: report.checks.filter((v) => v.status === "passed").length,
    failed: report.checks.filter((v) => v.status === "failed").length,
    blocked: report.checks.filter((v) => v.status === "blocked").length,
    assertions: report.checks.reduce((sum, value) => sum + value.assertions, 0),
  };
  return safeFinalReport(report, privateValues);
}
export async function main() {
  let report;
  try {
    report = await runFullSmoke(readFullConfiguration());
  } catch (error) {
    report = {
      schemaVersion: 1,
      runId:
        "qa-full-" +
        Date.now().toString(36) +
        "-" +
        randomBytes(4).toString("hex"),
      status: "failed",
      checks: [
        {
          name: "probe_configuration",
          status: "failed",
          assertions: 0,
          code:
            error instanceof FullProbeError
              ? error.code
              : "unexpected_probe_error",
        },
      ],
    };
  }
  const serialized = JSON.stringify(report, null, 2) + "\n";
  try {
    const directory = fileURLToPath(
      new URL(`../output/live-full/${report.runId}/`, import.meta.url),
    );
    await mkdir(directory, { recursive: true });
    await writeFile(join(directory, "report.json"), serialized, {
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
  process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  process.exitCode = report.status === "passed" ? 0 : 1;
}
if (
  typeof process !== "undefined" &&
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  await main();
