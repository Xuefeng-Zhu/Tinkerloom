#!/usr/bin/env node
/** Import-safe. Remote operations begin only in explicitly invoked main/runMediaSmoke. */
import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual as equal } from "node:util";
import {
  AppwriteUserClient,
  HttpBudget,
  functionObservation,
} from "./live_full_transport.mjs";
import {
  exactKeys,
  object,
  id,
  identity,
  validFullApp,
  validReview,
  validOutcome,
  validRuntimeRecord,
  isFullPrivateRowDenied,
} from "./live_full_contract.mjs";
import {
  validInvitation,
  validPreview,
} from "./live_collaboration_contract.mjs";
import {
  MediaProbeError,
  validAsset,
  validBegin,
  validChunkAck,
  validUsage,
  decodeReadChunk,
  cacheHeader,
  safeObservation,
  sanitizedReport,
  storageDenied,
  safeErrorEnvelope,
  digest,
} from "./live_media_contract.mjs";
import {
  maximumSyntheticPng,
  decodeSyntheticPng,
  byteSha,
  CHUNK_BYTES,
  MAX_BYTES,
  PNG_METADATA_MARKER,
} from "./live_media_fixture.mjs";
const randomId = (p) => p.slice(0, 3) + "-" + randomBytes(14).toString("hex");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const fixturePath = fileURLToPath(
  new URL("./fixtures/live_media/serviceWire.json", import.meta.url),
);
export function readMediaConfiguration(
  args = process.argv.slice(2),
  env = process.env,
) {
  const value = {
    endpoint: env.EXPO_PUBLIC_APPWRITE_ENDPOINT,
    projectId: env.EXPO_PUBLIC_APPWRITE_PROJECT_ID,
    functionId: env.EXPO_PUBLIC_APPWRITE_FUNCTION_ID,
    databaseId: "tinkerloom",
    origin: "http://localhost:8426",
    maxHttp: 300,
    timeoutMs: 45000,
    readyPolls: 24,
    pollMs: 5000,
    observeRelease: false,
    releasePolls: 20,
    expectedProvider: "none",
    expectedReminders: "false",
  };
  const flags = {
    "--endpoint": "endpoint",
    "--project-id": "projectId",
    "--function-id": "functionId",
    "--database-id": "databaseId",
    "--bucket-id": "bucketId",
    "--origin": "origin",
    "--source-commit": "sourceCommit",
    "--source-sha256": "sourceSha256",
    "--worker-source-commit": "workerSourceCommit",
    "--worker-source-sha256": "workerSourceSha256",
    "--core-deployment-id": "coreDeploymentId",
    "--worker-deployment-id": "workerDeploymentId",
    "--worker-function-id": "workerFunctionId",
    "--max-http": "maxHttp",
    "--timeout-ms": "timeoutMs",
    "--ready-polls": "readyPolls",
    "--poll-ms": "pollMs",
    "--expected-provider": "expectedProvider",
    "--expected-reminders": "expectedReminders",
  };
  const seen = new Set();
  for (let i = 0; i < args.length; i++) {
    if (seen.has(args[i])) throw new MediaProbeError("unsupported_argument");
    seen.add(args[i]);
    if (args[i] === "--observe-staging-release") {
      value.observeRelease = true;
      continue;
    }
    const key = flags[args[i]];
    if (!key || !args[i + 1] || args[i + 1].startsWith("--"))
      throw new MediaProbeError("unsupported_argument");
    value[key] = args[++i];
  }
  for (const key of ["maxHttp", "timeoutMs", "readyPolls", "pollMs"])
    value[key] = Number(value[key]);
  if (
    ![
      value.projectId,
      value.functionId,
      value.databaseId,
      value.bucketId,
      value.coreDeploymentId,
      value.workerDeploymentId,
      value.workerFunctionId,
    ].every(id) ||
    value.functionId === value.workerFunctionId ||
    ![value.sourceCommit, value.workerSourceCommit].every(
      (s) => typeof s === "string" && /^[a-f0-9]{7,40}$/.test(s),
    ) ||
    ![value.sourceSha256, value.workerSourceSha256].every(digest)
  )
    throw new MediaProbeError("provenance_required");
  let endpoint, origin;
  try {
    endpoint = new URL(value.endpoint);
    origin = new URL(value.origin);
  } catch {
    throw new MediaProbeError("configuration_invalid");
  }
  if (
    endpoint.protocol !== "https:" ||
    endpoint.pathname !== "/v1" ||
    endpoint.username ||
    endpoint.password ||
    endpoint.search ||
    endpoint.hash ||
    origin.origin !== value.origin ||
    !["http:", "https:"].includes(origin.protocol) ||
    origin.username ||
    origin.password ||
    !Number.isInteger(value.maxHttp) ||
    value.maxHttp < 120 ||
    value.maxHttp > 300 ||
    !Number.isInteger(value.timeoutMs) ||
    value.timeoutMs < 1000 ||
    value.timeoutMs > 60000 ||
    !Number.isInteger(value.readyPolls) ||
    value.readyPolls < 1 ||
    value.readyPolls > 24 ||
    !Number.isInteger(value.pollMs) ||
    value.pollMs < 1000 ||
    value.pollMs > 10000 ||
    value.expectedProvider !== "none" ||
    value.expectedReminders !== "false"
  )
    throw new MediaProbeError("configuration_invalid");
  return value;
}
export async function runMediaSmoke(
  configuration,
  { fetchImpl = globalThis.fetch, sleep = pause, now = Date.now } = {},
) {
  const started = now(),
    runId = `qa-media-${started.toString(36)}-${randomBytes(4).toString("hex")}`;
  const budget = new HttpBudget(configuration.maxHttp, 6),
    privateValues = new Set(),
    clients = [],
    actors = {},
    outcomes = new Map();
  const report = {
    runId,
    startedAt: new Date(started).toISOString(),
    status: "running",
    target: { ...configuration },
    accounts: [],
    resources: {},
    checks: [],
    budget: {
      maxHttpRequests: configuration.maxHttp,
      reservedCleanupRequests: 6,
      maxSyntheticAccounts: 2,
      readyPollLimit: configuration.readyPolls,
    },
  };
  let assertions = 0,
    definition,
    draft,
    version,
    maximumAsset,
    orientationAsset,
    maximumReady,
    orientationReady,
    initialUsage,
    readyObservedAt,
    latestReadyAt,
    revokedAsset,
    revokedBegin,
    revokedComplete,
    revokedReady,
    completeCommand,
    completeReceipt;
  const png = maximumSyntheticPng(),
    wire = JSON.parse(readFileSync(fixturePath, "utf8")),
    oriented = Buffer.from(wire.orientation.inputBase64, "base64");
  for (const v of [
    PNG_METADATA_MARKER,
    png.bytes.toString("base64"),
    wire.orientation.inputBase64,
  ])
    privateValues.add(v);
  const verify = (yes, observation = {}) => {
    assertions++;
    if (!yes)
      throw new MediaProbeError("assertion_failed", {
        ...observation,
        assertionIndex: assertions,
      });
  };
  const check = async (name, prerequisites, action) => {
    if (prerequisites.some((p) => outcomes.get(p) !== "passed")) {
      outcomes.set(name, "blocked");
      report.checks.push({
        name,
        status: "blocked",
        assertions: 0,
        code: "prerequisite_failed",
      });
      return;
    }
    assertions = 0;
    try {
      const observation = await action();
      if (!assertions) throw new MediaProbeError("no_assertions_executed");
      outcomes.set(name, "passed");
      report.checks.push({
        name,
        status: "passed",
        assertions,
        ...safeObservation(observation),
      });
    } catch (error) {
      outcomes.set(name, "failed");
      report.checks.push({
        name,
        status: "failed",
        assertions,
        code: error?.code ?? "unexpected_probe_error",
        ...safeObservation(error?.observation),
      });
    }
  };
  const client = () => {
    const c = new AppwriteUserClient(configuration, {
      budget,
      privateValues,
      fetchImpl,
    });
    clients.push(c);
    return c;
  };
  const execute = async (actor, payload) => {
    const result = await actor.client.execute(payload);
    verify(
      result.outer.status >= 200 &&
        result.outer.status < 300 &&
        result.deploymentMatched &&
        result.executionStatus === "completed" &&
        result.status === 200 &&
        !Object.hasOwn(result.data, "error"),
      functionObservation(result),
    );
    return result;
  };
  const data = async (actor, payload) => (await execute(actor, payload)).data;
  const error = async (actor, payload, code, status) => {
    const r = await actor.client.execute(payload);
    verify(
      r.outer.status >= 200 &&
        r.outer.status < 300 &&
        r.deploymentMatched &&
        r.executionStatus === "completed" &&
        r.status === status &&
        exactKeys(r.data, ["error"]) &&
        r.data.error === code,
      { ...functionObservation(r), code: r.data?.error },
    );
    return r;
  };
  async function createActor(label) {
    verify(report.accounts.length < 2);
    const account = {
      id: randomId("usr"),
      email: `tinkerloom-${runId}-${label}@example.test`,
      password: "T!" + randomBytes(24).toString("hex") + "a9",
    };
    privateValues.add(account.email);
    privateValues.add(account.password);
    const actor = { account, client: client() };
    actors[label] = actor;
    const observed = { label, id: account.id, creationStatus: "unconfirmed" };
    report.accounts.push(observed);
    const made = await actor.client.request("POST", "/account", {
      userId: account.id,
      email: account.email,
      password: account.password,
      name: "Tinkerloom media QA " + label,
    });
    verify(made.status === 201 && made.data?.$id === account.id, {
      httpStatus: made.status,
      code: made.data?.type,
    });
    observed.creationStatus = "created";
    const session = await actor.client.request(
      "POST",
      "/account/sessions/email",
      { email: account.email, password: account.password },
    );
    verify(session.status === 201 && actor.client.cookies.size > 0, {
      httpStatus: session.status,
      code: session.data?.type,
    });
    const actual = await actor.client.request("GET", "/account");
    verify(actual.status === 200 && actual.data?.$id === account.id, {
      httpStatus: actual.status,
    });
  }
  async function readVariant(assetId, variant, expected) {
    let offset = 0,
      previous,
      calls = 0;
    const chunks = [];
    while (true) {
      verify(++calls <= (variant === "display" ? 20 : 2));
      const result = await execute(actors.owner, {
        op: "spec.media.read",
        appId: report.resources.appId,
        assetId,
        variant,
        offset,
      });
      verify(cacheHeader(result) === "private, no-store");
      const chunk = decodeReadChunk(result.data, {
        assetId,
        variant,
        offset,
        previous,
      });
      assertions++;
      chunks.push(chunk);
      previous = result.data;
      if (previous.nextOffset === null) break;
      offset = previous.nextOffset;
    }
    const bytes = Buffer.concat(chunks);
    verify(
      bytes.length === previous.byteLength &&
        byteSha(bytes) === previous.sha256,
    );
    if (expected)
      verify(
        previous.sha256 === expected.sha256 &&
          previous.byteLength === expected.byteLength &&
          previous.width === expected.width &&
          previous.height === expected.height &&
          previous.contentType === expected.contentType,
      );
    return { bytes, descriptor: previous, calls };
  }
  async function ready(assetId, actor = actors.owner) {
    for (let poll = 0; poll < configuration.readyPolls; poll++) {
      const response = await data(actor, {
        op: "spec.media.status",
        appId: report.resources.appId,
        assetId,
      });
      verify(
        exactKeys(response, ["asset"]) && validAsset(response.asset, assetId),
      );
      if (response.asset.status === "ready")
        return { asset: response.asset, polls: poll + 1 };
      verify(
        ["pending", "queued", "processing"].includes(response.asset.status),
      );
      if (poll + 1 < configuration.readyPolls)
        await sleep(configuration.pollMs);
    }
    throw new MediaProbeError("media_ready_timeout", {
      polls: configuration.readyPolls,
    });
  }
  async function beginAndChunks(input, begin, actor = actors.owner) {
    const created = await data(actor, begin);
    verify(validBegin(created, input.length));
    const assetId = created.asset.assetId;
    for (let offset = 0; offset < input.length; offset += CHUNK_BYTES) {
      const chunk = input.subarray(
        offset,
        Math.min(offset + CHUNK_BYTES, input.length),
      );
      const ack = await data(actor, {
        op: "spec.media.chunk",
        appId: report.resources.appId,
        assetId,
        offset,
        sha256: byteSha(chunk),
        dataBase64: chunk.toString("base64"),
      });
      verify(validChunkAck(ack, assetId, offset + chunk.length));
    }
    return assetId;
  }
  try {
    await check("fixture_maximum_png", [], async () => {
      const decoded = decodeSyntheticPng(png.bytes);
      verify(
        png.bytes.length === MAX_BYTES &&
          png.sha256 === wire.png.sha256 &&
          decoded.pixels.equals(png.pixels) &&
          decoded.width === 16 &&
          decoded.height === 8,
      );
      verify(
        oriented.length === wire.orientation.inputByteLength &&
          byteSha(oriented) === wire.orientation.inputSha256 &&
          oriented.includes(Buffer.from("Exif\0\0")),
      );
      return {
        byteLength: png.bytes.length,
        sha256: png.sha256,
        width: 16,
        height: 8,
        chunks: 20,
      };
    });
    for (const label of ["owner", "outsider"])
      await check("authenticate_" + label, [], () => createActor(label));
    await check(
      "zero_provider_reminder_capabilities",
      ["authenticate_owner"],
      async () => {
        const caps = await data(actors.owner, { op: "spec.capabilities" });
        verify(
          exactKeys(caps, Object.keys(wire.capabilities)) &&
            caps.apiVersion === 1 &&
            caps.generation === false &&
            caps.guidance === false &&
            caps.privateMedia === true &&
            equal(caps.effects, []),
        );
        verify(
          equal(caps.invalidations, {
            mode: "poll.v1",
            minimumIntervalMs: 15000,
          }),
        );
        const catalog = await data(actors.owner, { op: "spec.templates" });
        verify(
          exactKeys(catalog, ["templates"]) && Array.isArray(catalog.templates),
        );
        const selected = catalog.templates.filter(
          (t) => t.key === "photoJournal",
        );
        verify(selected.length === 1 && object(selected[0].spec));
        definition = structuredClone(selected[0].spec);
        return {};
      },
    );
    await check(
      "create_private_draft_and_foreign_app",
      [
        "authenticate_owner",
        "authenticate_outsider",
        "zero_provider_reminder_capabilities",
      ],
      async () => {
        const workspaceId = randomId("wor"),
          appId = randomId("app"),
          foreignAppId = randomId("for");
        report.resources = { workspaceId, appId, foreignAppId };
        const made = await data(actors.owner, {
          op: "createWorkspace",
          id: workspaceId,
          name: "Media QA workspace",
        });
        verify(made.workspace?.id === workspaceId);
        for (const id of [appId, foreignAppId]) {
          const shell = await data(actors.owner, {
            op: "spec.createApp",
            id,
            workspaceId,
            name: "Media QA isolated app",
            operationId: randomId("new"),
          });
          verify(
            validFullApp(shell.app) &&
              shell.app.id === id &&
              shell.app.version === null,
          );
        }
        const saved = await data(actors.owner, {
          op: "spec.saveDraft",
          appId,
          operationId: randomId("sav"),
          expectedRevision: 0,
          expectedVersionId: null,
          spec: definition,
        });
        verify(
          validFullApp(saved.app) &&
            saved.app.draft?.revision === 1 &&
            saved.app.version === null,
        );
        draft = saved.app.draft;
        initialUsage = await data(actors.owner, {
          op: "spec.media.usage",
          appId,
        });
        verify(
          validUsage(initialUsage) &&
            initialUsage.reservedBytes === 0 &&
            initialUsage.assetCount === 0,
        );
        return {};
      },
    );
    const begin = () => ({
      op: "spec.media.begin",
      appId: report.resources.appId,
      operationId: runId + "-max",
      draftRevision: draft.revision,
      byteLength: MAX_BYTES,
      contentType: "image/png",
      sha256: png.sha256,
    });
    await check(
      "maximum_begin_exact_receipt_and_conflict",
      ["fixture_maximum_png", "create_private_draft_and_foreign_app"],
      async () => {
        const command = begin(),
          response = await data(actors.owner, command);
        verify(validBegin(response, MAX_BYTES));
        maximumAsset = response.asset.assetId;
        report.resources.maximumAssetId = maximumAsset;
        verify(
          maximumAsset ===
            identity("i", [
              report.resources.appId,
              actors.owner.account.id,
              command.operationId,
            ]),
        );
        verify(equal(await data(actors.owner, command), response));
        await error(
          actors.owner,
          { ...command, byteLength: MAX_BYTES - 1 },
          "operation_conflict",
          409,
        );
        const usage = await data(actors.owner, {
          op: "spec.media.usage",
          appId: report.resources.appId,
        });
        verify(
          validUsage(usage) &&
            usage.assetCount === 1 &&
            usage.reservedBytes === MAX_BYTES * 2 + 512 * 1024,
        );
        return {
          assetCount: usage.assetCount,
          reservedBytes: usage.reservedBytes,
        };
      },
    );
    await check(
      "pending_asset_privacy",
      ["maximum_begin_exact_receipt_and_conflict", "authenticate_outsider"],
      async () => {
        await error(
          actors.outsider,
          {
            op: "spec.media.status",
            appId: report.resources.appId,
            assetId: maximumAsset,
          },
          "not_found",
          404,
        );
        await error(
          actors.owner,
          {
            op: "spec.media.status",
            appId: report.resources.foreignAppId,
            assetId: maximumAsset,
          },
          "not_found",
          404,
        );
        await error(
          actors.owner,
          {
            op: "spec.media.read",
            appId: report.resources.appId,
            assetId: maximumAsset,
            variant: "display",
            offset: 0,
          },
          "not_found",
          404,
        );
        return {};
      },
    );
    await check(
      "twenty_chunks_exact_retry_conflict_and_complete",
      ["maximum_begin_exact_receipt_and_conflict"],
      async () => {
        const chunkCommand = (offset) => {
          const bytes = png.bytes.subarray(offset, offset + CHUNK_BYTES);
          return {
            op: "spec.media.chunk",
            appId: report.resources.appId,
            assetId: maximumAsset,
            offset,
            sha256: byteSha(bytes),
            dataBase64: bytes.toString("base64"),
          };
        };
        await error(
          actors.owner,
          chunkCommand(CHUNK_BYTES),
          "revision_conflict",
          409,
        );
        completeCommand = {
          op: "spec.media.complete",
          appId: report.resources.appId,
          assetId: maximumAsset,
          operationId: randomId("cmp"),
        };
        await error(actors.owner, completeCommand, "media_incomplete", 409);
        for (let offset = 0; offset < MAX_BYTES; offset += CHUNK_BYTES) {
          const command = chunkCommand(offset),
            ack = await data(actors.owner, command);
          verify(validChunkAck(ack, maximumAsset, offset + CHUNK_BYTES));
          if (!offset) {
            verify(equal(await data(actors.owner, command), ack));
            const altered = Buffer.from(png.bytes.subarray(0, CHUNK_BYTES));
            altered[100] ^= 1;
            await error(
              actors.owner,
              {
                ...command,
                sha256: byteSha(altered),
                dataBase64: altered.toString("base64"),
              },
              "operation_conflict",
              409,
            );
          }
        }
        const replay = await data(actors.owner, chunkCommand(0));
        verify(validChunkAck(replay, maximumAsset, MAX_BYTES));
        completeReceipt = await data(actors.owner, completeCommand);
        verify(
          exactKeys(completeReceipt, ["asset"]) &&
            validAsset(completeReceipt.asset, maximumAsset) &&
            completeReceipt.asset.status === "queued",
        );
        verify(
          equal(await data(actors.owner, completeCommand), completeReceipt),
        );
        return { chunks: 20, uploadedBytes: MAX_BYTES };
      },
    );
    await check(
      "private_worker_ready",
      ["twenty_chunks_exact_retry_conflict_and_complete"],
      async () => {
        const observed = await ready(maximumAsset);
        maximumReady = observed.asset;
        readyObservedAt = now();
        latestReadyAt = readyObservedAt;
        verify(
          maximumReady.contentType === "image/png" &&
            maximumReady.width === 16 &&
            maximumReady.height === 8,
        );
        return {
          polls: observed.polls,
          byteLength: maximumReady.byteLength,
          sha256: maximumReady.sha256,
        };
      },
    );
    await check(
      "maximum_variants_full_bytes_headers_pixels",
      ["private_worker_ready"],
      async () => {
        const values = [];
        for (const variant of ["display", "thumbnail"]) {
          const value = await readVariant(
            maximumAsset,
            variant,
            variant === "display" ? maximumReady : undefined,
          );
          const decoded = decodeSyntheticPng(value.bytes);
          verify(
            decoded.pixels.equals(png.pixels) &&
              equal(decoded.types, ["IHDR", "IDAT", "IEND"]),
          );
          verify(
            !value.bytes.includes(Buffer.from(PNG_METADATA_MARKER)) &&
              !value.bytes.includes(Buffer.from("npAd")),
          );
          values.push(value);
        }
        verify(values[0].descriptor.sha256 !== png.sha256);
        return {
          displaySha256: values[0].descriptor.sha256,
          thumbnailSha256: values[1].descriptor.sha256,
          width: 16,
          height: 8,
        };
      },
    );
    await check(
      "draft_reference_review_publication_and_record",
      ["maximum_variants_full_bytes_headers_pixels"],
      async () => {
        definition.requires.push("views.banner.v1");
        definition.views.push({
          id: "qaCover",
          type: "banner",
          label: "QA cover",
          options: {
            title: "Synthetic cover",
            imageAssetId: maximumAsset,
            imageAlt: "Synthetic QA pixels",
          },
        });
        definition.navigation.pages[0].viewIds.push("qaCover");
        const saved = await data(actors.owner, {
          op: "spec.saveDraft",
          appId: report.resources.appId,
          operationId: randomId("sav"),
          expectedRevision: 1,
          expectedVersionId: null,
          spec: definition,
        });
        verify(validFullApp(saved.app) && saved.app.draft.revision === 2);
        draft = saved.app.draft;
        const review = await data(actors.owner, {
          op: "spec.review",
          appId: report.resources.appId,
          expectedRevision: 2,
          enabledRuleIds: [],
          activateExistingRecordIds: [],
        });
        verify(
          exactKeys(review, ["review"]) &&
            validReview(review.review) &&
            review.review.compatibilityErrors.length === 0 &&
            equal(review.review.enabledRuleIds, []) &&
            equal(review.review.activateExistingRecordIds, []),
        );
        const published = await data(actors.owner, {
          op: "spec.publish",
          appId: report.resources.appId,
          operationId: randomId("pub"),
          expectedRevision: 2,
          expectedVersionId: null,
          candidateHash: review.review.candidateHash,
          reviewHash: review.review.reviewHash,
          enabledRuleIds: [],
          activateExistingRecordIds: [],
        });
        verify(
          validFullApp(published.app) &&
            published.app.version.hash === draft.candidateHash,
        );
        version = published.app.version;
        report.resources.versionId = version.id;
        const record = await data(actors.owner, {
          op: "spec.execute",
          appId: report.resources.appId,
          versionId: version.id,
          actionId: "addRecord",
          operationId: randomId("rec"),
          input: { data: { title: "Synthetic media QA", photo: maximumAsset } },
        });
        verify(validOutcome(record));
        report.resources.recordId = record.outcome.recordId;
        const fetched = await data(actors.owner, {
          op: "spec.getRecord",
          appId: report.resources.appId,
          versionId: version.id,
          recordId: report.resources.recordId,
        });
        verify(
          validRuntimeRecord(fetched.record, "memories") &&
            fetched.record.data.photo === maximumAsset,
        );
        return {};
      },
    );
    await check(
      "published_action_upload_orientation",
      ["draft_reference_review_publication_and_record"],
      async () => {
        const command = {
          op: "spec.media.begin",
          appId: report.resources.appId,
          operationId: randomId("ori"),
          versionId: version.id,
          actionId: "editRecord",
          fieldId: "photo",
          targetRecordId: report.resources.recordId,
          expectedRecordRevision: 1,
          byteLength: oriented.length,
          contentType: "image/jpeg",
          sha256: byteSha(oriented),
        };
        orientationAsset = await beginAndChunks(oriented, command);
        report.resources.orientationAssetId = orientationAsset;
        await error(
          actors.owner,
          { ...completeCommand, assetId: orientationAsset },
          "operation_conflict",
          409,
        );
        const complete = await data(actors.owner, {
          op: "spec.media.complete",
          appId: report.resources.appId,
          assetId: orientationAsset,
          operationId: randomId("cmp"),
        });
        verify(
          exactKeys(complete, ["asset"]) &&
            validAsset(complete.asset, orientationAsset) &&
            complete.asset.status === "queued",
        );
        return { byteLength: oriented.length, sha256: byteSha(oriented) };
      },
    );
    await check(
      "orientation_private_worker_ready_and_full_variants",
      ["published_action_upload_orientation"],
      async () => {
        const observed = await ready(orientationAsset);
        orientationReady = observed.asset;
        latestReadyAt = now();
        verify(
          orientationReady.width === wire.orientation.width &&
            orientationReady.height === wire.orientation.height &&
            orientationReady.contentType === "image/jpeg" &&
            orientationReady.sha256 === wire.orientation.displaySha256,
        );
        for (const variant of ["display", "thumbnail"]) {
          const value = await readVariant(orientationAsset, variant, {
            width: 6,
            height: 12,
            contentType: "image/jpeg",
            byteLength:
              wire.orientation[
                variant === "display" ? "displayBytes" : "thumbnailBytes"
              ],
            sha256:
              wire.orientation[
                variant === "display" ? "displaySha256" : "thumbnailSha256"
              ],
          });
          verify(
            value.bytes[0] === 255 &&
              value.bytes[1] === 216 &&
              !value.bytes.includes(Buffer.from("Exif\0\0")),
          );
        }
        const edited = await data(actors.owner, {
          op: "spec.execute",
          appId: report.resources.appId,
          versionId: version.id,
          actionId: "editRecord",
          targetRecordId: report.resources.recordId,
          expectedRecordRevision: 1,
          operationId: randomId("edt"),
          input: {
            data: { title: "Synthetic media QA", photo: orientationAsset },
          },
        });
        verify(validOutcome(edited) && edited.outcome.revision === 2);
        return {
          polls: observed.polls,
          width: 6,
          height: 12,
          displaySha256: orientationReady.sha256,
          thumbnailSha256: wire.orientation.thumbnailSha256,
        };
      },
    );
    await check(
      "unshared_cross_actor_and_cross_app_denials",
      [
        "orientation_private_worker_ready_and_full_variants",
        "authenticate_outsider",
      ],
      async () => {
        for (const assetId of [maximumAsset, orientationAsset]) {
          await error(
            actors.outsider,
            {
              op: "spec.media.read",
              appId: report.resources.appId,
              assetId,
              variant: "display",
              offset: 0,
            },
            "not_found",
            404,
          );
          await error(
            actors.owner,
            {
              op: "spec.media.read",
              appId: report.resources.foreignAppId,
              assetId,
              variant: "display",
              offset: 0,
            },
            "not_found",
            404,
          );
        }
        return {};
      },
    );
    await check(
      "grant_viewer_read_and_upload_denial",
      ["unshared_cross_actor_and_cross_app_denials"],
      async () => {
        const token = randomBytes(32).toString("base64url");
        privateValues.add(token);
        const invite = await data(actors.owner, {
          op: "createInvitation",
          id: randomId("inv"),
          appId: report.resources.appId,
          operationId: randomId("ivo"),
          token,
          role: "viewer",
          recipientId: actors.outsider.account.id,
        });
        verify(validInvitation(invite.invitation, report.resources.appId));
        const inspected = await data(actors.outsider, {
          op: "inspectInvitation",
          token,
        });
        verify(validPreview(inspected.invitation));
        const accepted = await data(actors.outsider, {
          op: "acceptInvitation",
          token,
          operationId: randomId("acc"),
        });
        verify(
          exactKeys(accepted, ["appId"]) &&
            accepted.appId === report.resources.appId,
        );
        const visible = await data(actors.outsider, {
          op: "spec.media.status",
          appId: report.resources.appId,
          assetId: maximumAsset,
        });
        verify(
          exactKeys(visible, ["asset"]) &&
            validAsset(visible.asset, maximumAsset) &&
            visible.asset.status === "ready",
        );
        const read = await execute(actors.outsider, {
          op: "spec.media.read",
          appId: report.resources.appId,
          assetId: orientationAsset,
          variant: "display",
          offset: 0,
        });
        verify(cacheHeader(read) === "private, no-store");
        const chunk = decodeReadChunk(read.data, {
          assetId: orientationAsset,
          variant: "display",
          offset: 0,
        });
        assertions++;
        verify(byteSha(chunk) === orientationReady.sha256);
        await error(
          actors.outsider,
          {
            op: "spec.media.begin",
            appId: report.resources.appId,
            operationId: randomId("bad"),
            versionId: version.id,
            actionId: "addRecord",
            fieldId: "photo",
            byteLength: oriented.length,
            contentType: "image/jpeg",
            sha256: byteSha(oriented),
          },
          "forbidden",
          403,
        );
        return {};
      },
    );
    await check(
      "builder_own_upload_receipt_current_authority",
      ["grant_viewer_read_and_upload_denial"],
      async () => {
        const changed = await data(actors.owner, {
          op: "setGrant",
          appId: report.resources.appId,
          actorId: actors.outsider.account.id,
          role: "builder",
          expectedRevision: 1,
          operationId: randomId("upg"),
        });
        verify(
          changed.member?.role === "builder" && changed.member.revision === 2,
        );
        revokedBegin = {
          op: "spec.media.begin",
          appId: report.resources.appId,
          operationId: randomId("rvb"),
          versionId: version.id,
          actionId: "editRecord",
          fieldId: "photo",
          targetRecordId: report.resources.recordId,
          expectedRecordRevision: 2,
          byteLength: oriented.length,
          contentType: "image/jpeg",
          sha256: byteSha(oriented),
        };
        revokedAsset = await beginAndChunks(
          oriented,
          revokedBegin,
          actors.outsider,
        );
        report.resources.revokedAssetId = revokedAsset;
        const repeated = await data(actors.outsider, revokedBegin);
        verify(
          validBegin(repeated, oriented.length) &&
            repeated.asset.assetId === revokedAsset,
        );
        revokedComplete = {
          op: "spec.media.complete",
          appId: report.resources.appId,
          assetId: revokedAsset,
          operationId: randomId("rvc"),
        };
        const queued = await data(actors.outsider, revokedComplete);
        verify(
          validAsset(queued.asset, revokedAsset) &&
            queued.asset.status === "queued",
        );
        verify(equal(await data(actors.outsider, revokedComplete), queued));
        const observed = await ready(revokedAsset, actors.outsider);
        revokedReady = observed.asset;
        latestReadyAt = now();
        verify(revokedReady.sha256 === wire.orientation.displaySha256);
        await error(actors.owner, revokedComplete, "not_found", 404);
        return { polls: observed.polls, sha256: revokedReady.sha256 };
      },
    );
    await check(
      "direct_private_storage_table_read_write_denials",
      ["grant_viewer_read_and_upload_denial"],
      async () => {
        const table = `/tablesdb/${encodeURIComponent(configuration.databaseId)}/tables/media_assets/rows/${maximumAsset}`;
        const bucket = `/storage/buckets/${encodeURIComponent(configuration.bucketId)}`;
        const file = `${bucket}/files/${identity("i", [maximumAsset, "display"])}`;
        let rowDenials = 0;
        for (const actor of [actors.owner, actors.outsider]) {
          for (const [method, body] of [
            ["GET", undefined],
            ["PATCH", { data: { inputBytes: MAX_BYTES } }],
          ]) {
            const result = await actor.client.request(method, table, body);
            verify(
              safeErrorEnvelope(result.data) &&
                isFullPrivateRowDenied(result, { knownExistingRow: true }),
              {
                httpStatus: result.status,
                code: result.data?.type,
              },
            );
            rowDenials++;
          }
          for (const [method, path, body, kind] of [
            ["GET", bucket, undefined, "bucket"],
            ["GET", `${bucket}/files`, undefined, "bucket"],
            ["GET", file, undefined, "file"],
            ["GET", `${file}/view`, undefined, "file"],
            ["PUT", file, { name: "private.bin" }, "file"],
            ["PUT", bucket, { name: configuration.bucketId }, "bucket"],
          ]) {
            const result = await actor.client.request(method, path, body);
            verify(storageDenied(result, { kind, knownExisting: true }), {
              httpStatus: result.status,
              code: result.data?.type,
            });
          }
        }
        // A private resource's existence is established by ready broker reads,
        // not by accepting an arbitrary missing ID as a permission denial.
        const response = await data(actors.owner, {
          op: "spec.media.status",
          appId: report.resources.appId,
          assetId: maximumAsset,
        });
        verify(
          validAsset(response.asset, maximumAsset) &&
            response.asset.status === "ready",
        );
        return { rowDenials };
      },
    );
    await check(
      "revoke_current_access_and_receipt_denial",
      ["builder_own_upload_receipt_current_authority"],
      async () => {
        const revoked = await data(actors.owner, {
          op: "setGrant",
          appId: report.resources.appId,
          actorId: actors.outsider.account.id,
          expectedRevision: 2,
          role: null,
          operationId: randomId("rev"),
        });
        verify(
          exactKeys(revoked, ["member"]) &&
            revoked.member.actorId === actors.outsider.account.id &&
            revoked.member.role === null &&
            revoked.member.revision === 3,
        );
        for (const op of ["spec.media.status", "spec.media.read"])
          await error(
            actors.outsider,
            {
              op,
              appId: report.resources.appId,
              assetId: maximumAsset,
              ...(op.endsWith("read") ? { variant: "display", offset: 0 } : {}),
            },
            "not_found",
            404,
          );
        // Exact own begin/complete receipts cannot outlive current app authority.
        await error(actors.outsider, revokedBegin, "not_found", 404);
        await error(actors.outsider, revokedComplete, "not_found", 404);
        await error(
          actors.outsider,
          {
            op: "spec.media.status",
            appId: report.resources.appId,
            assetId: revokedAsset,
          },
          "not_found",
          404,
        );
        await error(
          actors.outsider,
          {
            op: "spec.media.chunk",
            appId: report.resources.appId,
            assetId: maximumAsset,
            offset: 0,
            sha256: byteSha(png.bytes.subarray(0, CHUNK_BYTES)),
            dataBase64: png.bytes.subarray(0, CHUNK_BYTES).toString("base64"),
          },
          "not_found",
          404,
        );
        return {};
      },
    );
    await check(
      "private_worker_public_execution_and_forged_proof_denial",
      ["authenticate_owner"],
      async () => {
        const anonymous = client(),
          path = `/functions/${encodeURIComponent(configuration.workerFunctionId)}/executions`;
        for (const [current, forged] of [
          [anonymous, false],
          [actors.owner.client, false],
          [actors.owner.client, true],
        ]) {
          const proof = randomBytes(32).toString("base64url");
          privateValues.add(proof);
          const response = await current.request("POST", path, {
            async: false,
            body: JSON.stringify({ dispatchId: randomId("dis"), proof }),
            method: "POST",
            path: "/",
            headers: forged
              ? {
                  "x-appwrite-key": "synthetic-forged-not-a-key",
                  "x-appwrite-trigger": "schedule",
                }
              : {},
          });
          if ([401, 403].includes(response.status))
            verify(storageDenied(response, { kind: "function" }), {
              httpStatus: response.status,
              code: response.data?.type,
            });
          else {
            const execution = response.data;
            let body;
            try {
              body = JSON.parse(execution?.responseBody);
            } catch {}
            verify(
              // Inner authentication is defense in depth; execute:[] itself
              // must prevent publicly creating the worker execution.
              false,
              {
                httpStatus: response.status,
                functionStatus: execution?.responseStatusCode,
                code: body?.error,
              },
            );
          }
        }
        return {};
      },
    );
    await check(
      "usage_staging_reservation_retained",
      ["builder_own_upload_receipt_current_authority"],
      async () => {
        const usage = await data(actors.owner, {
          op: "spec.media.usage",
          appId: report.resources.appId,
        });
        verify(validUsage(usage) && usage.assetCount === 3);
        const variants =
          maximumReady.byteLength * 2 +
          2 * (wire.orientation.displayBytes + wire.orientation.thumbnailBytes);
        const originals = MAX_BYTES + oriented.length * 2;
        const elapsed = now() - readyObservedAt;
        // No claim that bytes are freed before a legitimate quiet period. If
        // processing took longer, keep the remaining cleanup gate unverified.
        if (elapsed < 16 * 60000)
          verify(
            usage.reservedBytes >= variants + MAX_BYTES &&
              usage.pendingReleaseBytes >= MAX_BYTES,
          );
        verify(
          usage.reservedBytes >= variants &&
            usage.pendingReleaseBytes <= originals,
        );
        return {
          reservedBytes: usage.reservedBytes,
          pendingReleaseBytes: usage.pendingReleaseBytes,
          assetCount: usage.assetCount,
          elapsedMs: elapsed,
        };
      },
    );
    if (!configuration.observeRelease) {
      report.checks.push({
        name: "optional_quiet_period_release",
        status: "pending",
        assertions: 0,
        code: "quiet_period_not_elapsed",
      });
    } else
      await check(
        "optional_quiet_period_release",
        ["usage_staging_reservation_retained"],
        async () => {
          const earliest = latestReadyAt + 16 * 60000;
          for (
            let attempt = 0;
            attempt < configuration.releasePolls;
            attempt++
          ) {
            await sleep(60000);
            const usage = await data(actors.owner, {
              op: "spec.media.usage",
              appId: report.resources.appId,
            });
            verify(validUsage(usage));
            const elapsed = now() - readyObservedAt;
            if (usage.pendingReleaseBytes === 0) {
              verify(now() >= earliest && usage.assetCount === 3);
              const expected =
                maximumReady.byteLength * 2 +
                2 *
                  (wire.orientation.displayBytes +
                    wire.orientation.thumbnailBytes);
              verify(usage.reservedBytes === expected);
              return {
                polls: attempt + 1,
                reservedBytes: usage.reservedBytes,
                pendingReleaseBytes: 0,
                elapsedMs: elapsed,
              };
            }
            if (now() < earliest)
              verify(usage.pendingReleaseBytes >= MAX_BYTES);
          }
          throw new MediaProbeError("quiet_period_not_elapsed", {
            polls: configuration.releasePolls,
          });
        },
      );
  } catch (error) {
    report.checks.push({
      name: "probe_setup",
      status: "failed",
      assertions: 0,
      code: error?.code ?? "unexpected_probe_error",
    });
  } finally {
    for (const label of ["owner", "outsider"]) {
      const actor = actors[label];
      if (!actor?.client.cookies.size) continue;
      await check("temporary_session_signout_" + label, [], async () => {
        const signed = await actor.client.request(
          "DELETE",
          "/account/sessions/current",
          undefined,
          { cleanup: true },
        );
        verify(signed.status === 204, {
          httpStatus: signed.status,
          code: signed.data?.type,
        });
        actor.client.cookies.clear();
        return {};
      });
    }
  }
  report.completedAt = new Date(now()).toISOString();
  report.budget.httpRequests = budget.used;
  report.budget.peakConcurrentHttp = budget.peak;
  report.budget.syntheticAccountsAttempted = report.accounts.length;
  report.target.coreDeploymentMatchedExecutions = clients.reduce(
    (n, c) => n + c.deploymentMatches,
    0,
  );
  report.status =
    report.checks.length &&
    report.checks.every((c) => ["passed", "pending"].includes(c.status))
      ? "passed"
      : "failed";
  return sanitizedReport(report, privateValues);
}
export async function main() {
  let report;
  try {
    report = await runMediaSmoke(readMediaConfiguration());
  } catch (error) {
    report = sanitizedReport({
      runId: `qa-media-${Date.now().toString(36)}-${randomBytes(4).toString("hex")}`,
      startedAt: new Date().toISOString(),
      status: "failed",
      checks: [
        {
          name: "probe_configuration",
          status: "failed",
          assertions: 0,
          code: error?.code ?? "unexpected_probe_error",
        },
      ],
    });
  }
  try {
    const directory = fileURLToPath(
      new URL(`../output/live-media/${report.runId}/`, import.meta.url),
    );
    await mkdir(directory, { recursive: true, mode: 0o700 });
    await writeFile(
      join(directory, "report.json"),
      JSON.stringify(report, null, 2) + "\n",
      { flag: "wx", mode: 0o600 },
    );
  } catch {
    report.status = "failed";
    report.checks.push({
      name: "probe_setup",
      status: "failed",
      assertions: 0,
      code: "report_persistence_failed",
    });
    report = sanitizedReport(report);
  }
  process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  process.exitCode = report.status === "passed" ? 0 : 1;
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  await main();
