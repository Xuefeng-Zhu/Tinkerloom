import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { readMediaConfiguration, runMediaSmoke } from "./live_media_smoke.mjs";
import {
  validAsset,
  validBegin,
  validChunkAck,
  validUsage,
  decodeReadChunk,
  cacheHeader,
  storageDenied,
  sanitizedReport,
  safeObservation,
} from "./live_media_contract.mjs";
import {
  maximumSyntheticPng,
  decodeSyntheticPng,
  byteSha,
  crc32,
  CHUNK_BYTES,
  MAX_BYTES,
  PNG_METADATA_MARKER,
} from "./live_media_fixture.mjs";
import { AppwriteUserClient, HttpBudget } from "./live_full_transport.mjs";
const wire = JSON.parse(
  readFileSync(
    new URL("./fixtures/live_media/serviceWire.json", import.meta.url),
    "utf8",
  ),
);
const clone = (v) => structuredClone(v);
const configArgs = [
  "--endpoint",
  "https://appwrite.invalid/v1",
  "--project-id",
  "synthetic-project",
  "--function-id",
  "synthetic-core",
  "--database-id",
  "tinkerloom",
  "--bucket-id",
  "synthetic-media",
  "--worker-function-id",
  "synthetic-worker",
  "--source-commit",
  "fc71abc",
  "--source-sha256",
  "a".repeat(64),
  "--worker-source-commit",
  "b542d9f",
  "--worker-source-sha256",
  "b".repeat(64),
  "--core-deployment-id",
  "synthetic-core-deploy",
  "--worker-deployment-id",
  "synthetic-worker-deploy",
];
const configured = () => readMediaConfiguration(configArgs, {});
test("actual Dart-generated response fixture accepts strict media DTOs", () => {
  assert.match(wire.proof, /simulated store; no Cloud evidence/);
  assert.equal(validBegin(wire.begin, MAX_BYTES), true);
  assert.equal(
    validChunkAck(wire.firstChunk, wire.begin.asset.assetId, CHUNK_BYTES),
    true,
  );
  assert.equal(
    validChunkAck(wire.lastChunk, wire.begin.asset.assetId, MAX_BYTES),
    true,
  );
  assert.equal(validAsset(wire.complete.asset, wire.begin.asset.assetId), true);
  assert.equal(validAsset(wire.ready.asset, wire.begin.asset.assetId), true);
  assert.equal(validUsage(wire.usage), true);
});
test("pending ready failed variants reject unknown keys/states/leaked private internals", () => {
  for (const key of [
    "requestJson",
    "uploaderId",
    "inputHash",
    "url",
    "providerFileId",
    "leaseToken",
  ]) {
    assert.equal(validAsset({ ...wire.ready.asset, [key]: "private" }), false);
  }
  for (const status of [
    "uploading",
    "deleting",
    "deleted",
    "expired",
    "issuing",
  ])
    assert.equal(validAsset({ ...wire.begin.asset, status }), false);
  assert.equal(
    validAsset({
      ...wire.begin.asset,
      status: "failed",
      error: "arbitrary private marker",
    }),
    false,
  );
  assert.equal(
    validAsset({
      ...wire.begin.asset,
      status: "failed",
      error: "invalid_media",
    }),
    true,
  );
  assert.equal(
    validAsset({ ...wire.begin.asset, uploadedBytes: MAX_BYTES + 1 }),
    false,
  );
  assert.equal(validAsset({ ...wire.ready.asset, width: 2049 }), false);
});
test("begin/chunk/usage contracts bind exact counts and current cumulative retry acknowledgement", () => {
  assert.equal(
    validBegin({ ...wire.begin, chunkBytes: CHUNK_BYTES - 1 }, MAX_BYTES),
    false,
  );
  assert.equal(validBegin({ ...wire.begin, extra: "token" }, MAX_BYTES), false);
  assert.equal(validBegin(wire.begin, MAX_BYTES - 1), false);
  assert.equal(
    validChunkAck(wire.lastChunk, wire.begin.asset.assetId, MAX_BYTES),
    true,
  );
  assert.equal(
    validChunkAck(wire.lastChunk, wire.begin.asset.assetId, CHUNK_BYTES),
    false,
  );
  assert.equal(validChunkAck(wire.firstChunk, "other", CHUNK_BYTES), false);
  assert.equal(
    validUsage({
      ...wire.usage,
      pendingReleaseBytes: wire.usage.reservedBytes + 1,
    }),
    false,
  );
});
test("exact 5 MiB source is a fully valid still PNG with actual pixels and twenty full chunks", () => {
  const f = maximumSyntheticPng(),
    decoded = decodeSyntheticPng(f.bytes);
  assert.equal(f.bytes.length, 5242880);
  assert.equal(f.sha256, wire.png.sha256);
  assert.equal(f.bytes.length / CHUNK_BYTES, 20);
  assert.equal(decoded.width, 16);
  assert.equal(decoded.height, 8);
  assert.equal(decoded.pixels.equals(f.pixels), true);
  assert.ok(decoded.types.includes("npAd"));
  assert.ok(decoded.types.includes("tEXt"));
  const second = maximumSyntheticPng();
  assert.equal(byteSha(second.bytes), f.sha256);
  assert.equal(crc32(Buffer.from("123456789")), 0xcbf43926);
});
test("actual sanitized PNG variants preserve pixels and strip original padding/text metadata", () => {
  const source = maximumSyntheticPng();
  for (const [variant, value] of [
    ["display", wire.display],
    ["thumbnail", wire.thumbnail],
  ]) {
    const bytes = decodeReadChunk(value, {
      assetId: wire.ready.asset.assetId,
      variant,
      offset: 0,
    });
    const decoded = decodeSyntheticPng(bytes);
    assert.equal(decoded.pixels.equals(source.pixels), true);
    assert.deepEqual(decoded.types, ["IHDR", "IDAT", "IEND"]);
    assert.equal(bytes.includes(Buffer.from(PNG_METADATA_MARKER)), false);
    assert.equal(byteSha(bytes), value.sha256);
    assert.equal(bytes.length, value.byteLength);
  }
});
test("chunk identity variant offset digest length MIME headers and canonical base64 are strict", () => {
  const base = wire.display,
    opts = { assetId: base.assetId, variant: "display", offset: 0 };
  for (const [key, value] of [
    ["assetId", "other"],
    ["variant", "thumbnail"],
    ["offset", 1],
    ["nextOffset", 262144],
    ["sha256", "invalid"],
    ["chunkSha256", "0".repeat(64)],
    ["byteLength", base.byteLength + 1],
    ["contentType", "text/plain"],
    ["cacheControl", "public"],
    ["dataBase64", base.dataBase64 + "\n"],
    ["width", 0],
    ["extra", "private"],
  ])
    assert.throws(() => decodeReadChunk({ ...base, [key]: value }, opts));
  const prior = { ...base, sha256: "0".repeat(64) };
  assert.throws(() => decodeReadChunk(base, { ...opts, previous: prior }));
});
test("PNG integrity parser detects corruption appended garbage animation and expansion mismatch", () => {
  const f = maximumSyntheticPng();
  const corrupt = Buffer.from(f.bytes);
  corrupt[100] ^= 1;
  assert.throws(() => decodeSyntheticPng(corrupt));
  assert.throws(() =>
    decodeSyntheticPng(Buffer.concat([f.bytes, Buffer.from([0])])),
  );
  assert.throws(() => decodeSyntheticPng(f.bytes, { maximum: MAX_BYTES - 1 }));
});
test("EXIF-6 fixture includes original metadata and actual sanitizer outcome hashes", () => {
  const v = wire.orientation,
    bytes = Buffer.from(v.inputBase64, "base64");
  assert.equal(bytes.length, v.inputByteLength);
  assert.equal(byteSha(bytes), v.inputSha256);
  assert.ok(bytes.includes(Buffer.from("Exif\0\0")));
  assert.equal(v.orientation, 6);
  assert.deepEqual(
    [v.originalWidth, v.originalHeight, v.width, v.height],
    [12, 6, 6, 12],
  );
  assert.notEqual(v.inputSha256, v.displaySha256);
  assert.equal(v.contentType, "image/jpeg");
});
test("function response cache header comes from actual execution responseHeaders", () => {
  assert.equal(
    cacheHeader({
      outer: {
        data: { responseHeaders: { "Cache-Control": "private, no-store" } },
      },
    }),
    "private, no-store",
  );
  assert.equal(
    cacheHeader({
      outer: {
        data: {
          responseHeaders: {
            "Cache-Control": "private, no-store",
            "cache-control": "public",
          },
        },
      },
    }),
    null,
  );
  assert.equal(cacheHeader({}), null);
});
test("direct private storage denial permits only known-resource concealment and no payload leakage", () => {
  for (const status of [401, 403])
    assert.equal(
      storageDenied(
        { status, data: { type: "general_access_forbidden" } },
        { kind: "file" },
      ),
      true,
    );
  const denied = {
    status: 404,
    data: { type: "storage_file_not_found", message: "hidden" },
  };
  assert.equal(
    storageDenied(denied, { kind: "file", knownExisting: true }),
    true,
  );
  assert.equal(
    storageDenied(denied, { kind: "file", knownExisting: false }),
    false,
  );
  assert.equal(
    storageDenied(
      { status: 404, data: { type: "storage_bucket_not_found" } },
      { kind: "file", knownExisting: true },
    ),
    false,
  );
  for (const key of [
    "$id",
    "files",
    "$permissions",
    "responseBody",
    "dataBase64",
    "rows",
  ])
    assert.equal(
      storageDenied(
        { ...denied, data: { ...denied.data, [key]: "leak" } },
        { kind: "file", knownExisting: true },
      ),
      false,
    );
});
test("configuration requires exact core/worker/source provenance no paid/provider flags or API keys", () => {
  const c = configured();
  assert.equal(c.maxHttp, 300);
  assert.equal(c.readyPolls, 24);
  assert.equal(c.observeRelease, false);
  for (const flag of [
    "--api-key",
    "--admin-key",
    "--jwt",
    "--password",
    "--delete",
    "--allow-provider",
  ])
    assert.throws(() =>
      readMediaConfiguration([...configArgs, flag, "private"], {}),
    );
  for (const [flag, value] of [
    ["--max-http", "301"],
    ["--expected-provider", "openai"],
    ["--expected-reminders", "true"],
    ["--ready-polls", "25"],
    ["--poll-ms", "0"],
  ])
    assert.throws(() =>
      readMediaConfiguration([...configArgs, flag, value], {}),
    );
  assert.throws(() =>
    readMediaConfiguration(
      configArgs.filter((_, i) => i !== 16 && i !== 17),
      {},
    ),
  );
  assert.throws(() =>
    readMediaConfiguration([...configArgs, "--project-id", "another"], {}),
  );
});
test("report allowlist drops private values arbitrary fields status text and raw bytes", () => {
  const secret = "private_marker_for_secret_scan",
    base = {
      runId: "qa-media-abc-12345678",
      startedAt: new Date().toISOString(),
      completedAt: new Date().toISOString(),
      status: "passed",
      target: configured(),
      accounts: [{ label: "owner", id: "owner" }],
      resources: { appId: "app", assetBase64: secret },
      checks: [
        {
          name: "private_worker_ready",
          status: "passed",
          assertions: 1,
          code: "arbitrary_private_status",
          message: secret,
          dataBase64: secret,
          sha256: "a".repeat(64),
        },
      ],
      unknown: secret,
    };
  const r = sanitizedReport(base, new Set([secret]));
  assert.equal(JSON.stringify(r).includes(secret), false);
  assert.equal(r.status, "passed");
  assert.equal(r.checks[0].sha256, "a".repeat(64));
  const bad = sanitizedReport(
    { ...base, target: { ...configured(), projectId: secret } },
    new Set([secret]),
  );
  assert.equal(bad.status, "failed");
  assert.equal(JSON.stringify(bad).includes(secret), false);
  assert.equal(bad.summary.failed, 1);
  assert.equal(
    safeObservation({ code: secret }).backendCode,
    "unrecognized_error",
  );
});
test("HTTP budget hard cap reserves session cleanup and cannot be exceeded", () => {
  const b = new HttpBudget(300, 6);
  for (let i = 0; i < 294; i++) {
    b.start();
    b.finish();
  }
  assert.throws(() => b.start());
  for (let i = 0; i < 6; i++) {
    b.start(true);
    b.finish();
  }
  assert.equal(b.used, 300);
  assert.throws(() => b.start(true));
});
test("existing user transport sends only project/origin/cookie headers no admin credentials", async () => {
  const calls = [],
    c = new AppwriteUserClient(configured(), {
      fetchImpl: async (url, options) => {
        calls.push({ url, options });
        return new Response("{}", {
          status: 200,
          headers: {
            "Set-Cookie":
              "a_session=session-synthetic-secret; Path=/; HttpOnly",
          },
        });
      },
    });
  await c.request("GET", "/account");
  await c.request("GET", "/account");
  assert.equal(c.cookies.size, 1);
  assert.ok(calls[1].options.headers.Cookie);
  assert.equal(
    Object.keys(calls[1].options.headers).some((k) =>
      /key|jwt|authorization/i.test(k),
    ),
    false,
  );
});
test("transport uncertainty is not retried and remaining dependent media checks remain blocked", async () => {
  let calls = 0;
  const report = await runMediaSmoke(configured(), {
    fetchImpl: async () => {
      calls++;
      throw new Error("private transport detail");
    },
    sleep: async () => {
      throw new Error("unexpected sleep");
    },
  });
  assert.equal(calls, 2);
  assert.equal(report.status, "failed");
  assert.equal(report.budget.httpRequests, 2);
  assert.ok(report.summary.failed >= 2);
  assert.ok(report.summary.blocked > 0);
  assert.equal(
    JSON.stringify(report).includes("private transport detail"),
    false,
  );
  assert.equal(report.accounts.length, 2);
  assert.equal(report.coverage.providerCallsIntended, 0);
});
test("private denial error envelope rejects nested resource data even under an error key", () => {
  assert.equal(
    storageDenied(
      { status: 403, data: { error: { rows: [{ $id: "leaked" }] } } },
      { kind: "file", knownExisting: true },
    ),
    false,
  );
  assert.equal(
    storageDenied(
      { status: 403, data: { message: ["private"] } },
      { kind: "bucket", knownExisting: true },
    ),
    false,
  );
});
