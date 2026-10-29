import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { writeFile } from "node:fs/promises";
import { Account, Client, Functions, ExecutionMethod } from "appwrite";
import { AppwriteBackend } from "/private/tmp/tinkerloom-guarded-read-completeness/apps/mobile/src/backend/core";
import { BackendError } from "/private/tmp/tinkerloom-guarded-read-completeness/apps/mobile/src/backend/errors";
import { GuardedReadCoordinator } from "/private/tmp/tinkerloom-guarded-read-completeness/apps/mobile/src/runtime/guardedReads";
import { accountTransport } from "/private/tmp/tinkerloom-guarded-read-completeness/apps/mobile/src/full/FullRegistry";
import {
  FunctionRuntimeAdapter,
  decodeRuntimeManifest,
} from "/private/tmp/tinkerloom-guarded-read-completeness/apps/mobile/src/runtime/functionAdapter";
import { HostLifetime } from "/private/tmp/tinkerloom-guarded-read-completeness/apps/mobile/src/host/scope";
import { hostStores } from "/private/tmp/tinkerloom-guarded-read-completeness/apps/mobile/src/host/storage";
import { PrivateMediaController } from "/private/tmp/tinkerloom-guarded-read-completeness/apps/mobile/src/media/controller";
import { MediaRecovery } from "/private/tmp/tinkerloom-guarded-read-completeness/apps/mobile/src/media/recovery";
const directory = "/private/tmp/tinkerloom-media-sdk-hmsx112y";
const stage = "/private/tmp/tinkerloom-guarded-read-completeness";
const child = spawn(
  "/private/tmp/tinkerloom-dart-3.11.0-arm64/dart-sdk/bin/dart",
  [
    "--packages=/Users/frank/mygit/Tinkerloom/appwrite_backend/.dart_tool/package_config.json",
    `${directory}/service_bridge.dart`,
  ],
  {
    stdio: ["pipe", "pipe", "pipe"],
    env: { ...process.env, DART_SUPPRESS_ANALYTICS: "true" },
  },
);
let sequence = 0,
  readyYes!: (value: any) => void,
  readyNo!: (error: Error) => void;
const initial = new Promise<any>((yes, no) => {
  readyYes = yes;
  readyNo = no;
});
const pending = new Map<
  number,
  { resolve(value: any): void; reject(error: Error): void }
>();
createInterface({ input: child.stdout }).on("line", (line) => {
  const value = JSON.parse(line);
  if (value.ready) readyYes(value);
  else {
    const waiting = pending.get(value.id);
    pending.delete(value.id);
    if (value.error) waiting?.reject(new Error(value.error));
    else waiting?.resolve(value.data);
  }
});
child.stderr.on("data", (data) => process.stderr.write(data));
child.on("error", readyNo);
child.on("exit", (code) => {
  if (code) {
    readyNo(new Error(`bridge_exit_${code}`));
    for (const waiting of pending.values())
      waiting.reject(new Error("bridge_closed"));
  }
});
const rpc = (action: string) =>
  new Promise<any>((resolve, reject) => {
    const id = ++sequence;
    pending.set(id, { resolve, reject });
    child.stdin.write(JSON.stringify({ id, action }) + "\n");
  });
const hash = (bytes: Uint8Array) =>
  createHash("sha256").update(bytes).digest("hex");
const tick = () => new Promise((resolve) => setTimeout(resolve, 20));
async function main() {
  let closed = false;
  try {
    const fixture = await initial,
      manifest = decodeRuntimeManifest(fixture.app);
    const client = new Client()
      .setEndpoint(fixture.endpoint)
      .setProject("synthetic");
    const functions = new Functions(client);
    let activeSDK = 0,
      maximumSDK = 0;
    const backend = new AppwriteBackend({
      account: new Account(client),
      newId() {
        throw new Error("Image reads cannot allocate write IDs");
      },
      execute: async (body) => {
        maximumSDK = Math.max(maximumSDK, ++activeSDK);
        try {
          return await functions.createExecution({
            functionId: "core",
            body,
            async: false,
            method: ExecutionMethod.POST,
            headers: { "content-type": "application/json" },
          });
        } finally {
          activeSDK--;
        }
      },
    });
    const [a, b] = fixture.assetIds as [string, string];
    const status = (assetId: string) => ({
      op: "spec.media.status",
      appId: "app",
      assetId,
    });
    const read = (assetId: string) => ({
      op: "spec.media.read",
      appId: "app",
      assetId,
      variant: "display",
      offset: 0,
    });
    const query = {
      op: "spec.query",
      appId: "app",
      versionId: manifest.version!.id,
      collectionId: fixture.collectionId,
      query: {},
    };
    const raw = [];
    for (const pair of [
      [status(a), status(b)],
      [read(a), read(b)],
      [read(a), query],
    ]) {
      await rpc("arm");
      const first = backend.executeSpec(pair[0]);
      const failure = assert.rejects(
        first,
        (error: unknown) =>
          error instanceof BackendError &&
          error.kind === "service" &&
          error.status === 409 &&
          error.code === "transaction_conflict" &&
          !error.uncertain,
      );
      await rpc("paused");
      await backend.executeSpec(pair[1]);
      await rpc("release");
      await failure;
      raw.push({ first: pair[0].op, second: pair[1].op, confirmedConflict: 1 });
    }
    const lane = new GuardedReadCoordinator();
    const transport = lane.transport(
      accountTransport({
        execute: (request) => backend.executeSpec(request),
        expected: { accountId: "alice", epoch: 1, active: true },
        readSession: () => ({ accountId: "alice", epoch: 1, active: true }),
        alive: () => !closed,
        onUnauthenticated() {
          throw new Error("Unexpected synthetic auth failure");
        },
      }),
    );
    const lifetime = new HostLifetime({
      endpoint: fixture.endpoint,
      projectId: "synthetic",
      accountId: "alice",
      appId: "app",
    });
    const values = new Map<string, string>();
    const host = hostStores(lifetime, {
      async read(key) {
        return values.get(key) ?? null;
      },
      async change(key, update) {
        const next = update(values.get(key) ?? null);
        if (next === null) values.delete(key);
        else values.set(key, next);
      },
    });
    const imageHashes: string[] = [];
    let resources = 0,
      created = 0;
    const base = new FunctionRuntimeAdapter(manifest, transport);
    const media = new PrivateMediaController(base, transport, lifetime, {
      privateMedia: true,
      recovery: new MediaRecovery(host.storage),
      newId() {
        throw new Error("No IDs from image reads");
      },
      requestTimeoutMs: 10_000,
      readConcurrency: 2,
      readVariant: "display",
      isCurrent: () => !closed,
      ports: {
        sha256: async (bytes) => hash(bytes),
        pick: async () => {
          throw new Error("No picker in this read-only proof");
        },
        image: async (bytes, type) => {
          assert.ok(bytes.byteLength > 8);
          assert.equal(type, "image/png");
          imageHashes.push(hash(bytes));
          resources++;
          return {
            uri: `blob:synthetic-owned-${++created}`,
            dispose() {
              resources--;
            },
          };
        },
        dispose() {},
      },
    });
    const before = await rpc("stats");
    assert.equal(before.failedTransactions, 3);
    maximumSDK = 0;
    await rpc("resetMaximum");
    await rpc("arm");
    const first = media.read(a);
    await rpc("paused");
    const second = media.read(b),
      records = base.query(fixture.collectionId, {});
    await tick();
    const held = await rpc("stats");
    assert.equal(held.calls.length, before.calls.length + 1);
    assert.equal(activeSDK, 1);
    await rpc("release");
    const [one, two, page] = await Promise.all([first, second, records]);
    const after = await rpc("stats");
    assert.equal(maximumSDK, 1);
    assert.equal(after.maximumConcurrentSDK, 1);
    assert.equal(after.failedTransactions, before.failedTransactions);
    assert.deepEqual(after.businessCounts, before.businessCounts);
    assert.equal(after.businessHash, before.businessHash);
    assert.equal(after.fileBytesHash, before.fileBytesHash);
    assert.equal(resources, 2);
    assert.notEqual(one.uri, two.uri);
    assert.equal(page.records.length, 0);
    const calls = after.calls
      .slice(before.calls.length)
      .map((call: any) => call.op);
    assert.equal(calls.length, 5);
    assert.equal(
      calls.filter((op: string) => op === "spec.media.status").length,
      2,
    );
    assert.equal(
      calls.filter((op: string) => op === "spec.media.read").length,
      2,
    );
    assert.equal(calls.filter((op: string) => op === "spec.query").length, 1);
    assert.equal(imageHashes.length, 2);
    assert.equal(imageHashes[0], fixture.displayHashes[0]);
    assert.equal(imageHashes[1], fixture.displayHashes[1]);
    await media.read(a);
    const cached = await rpc("stats");
    assert.deepEqual(cached.calls.slice(after.calls.length), [
      { op: "spec.media.status" },
    ]);
    assert.equal(resources, 2);
    assert.equal(cached.businessHash, before.businessHash);
    assert.equal(cached.fileBytesHash, before.fileBytesHash);
    media.dispose();
    lifetime.dispose();
    lane.dispose();
    closed = true;
    assert.equal(resources, 0);
    assert.equal(values.size, 0);
    const result = {
      proof:
        "actual_Appwrite_SDK_backend_accountTransport_21op_FIFO_PrivateMediaController_Functions_loopback_actual_PlatformService_AppwriteRest_optimistic_MemoryStore_fakeStorage",
      authority: "synthetic_injected_alice_not_Cloud_authenticated",
      sdkVersion: "29.1.0",
      rawOverlapPairs: raw,
      coordinatedPipeline: {
        completePrivateMediaControllerReads: 2,
        actualQuery: 1,
        assetStatusCalls: 2,
        assetChunkReadCalls: 2,
        totalSDKCalls: 5,
        sdkDispatchWhileFirstHeld: 1,
        maximumConcurrentSDK: maximumSDK,
        newFailedTransactions: 0,
        businessRowCountsUnchanged: true,
        businessRowContentsUnchanged: true,
        StorageByteContentsUnchanged: true,
        wholeTransportByteHashesVerifiedByController: 2,
        newWriteIDs: 0,
        pickerCalls: 0,
      },
      cachedRead: { reauthorizedStatusCalls: 1, additionalChunkReads: 0 },
      disposal: {
        ownedImageResources: resources,
        localRecoveryEntries: values.size,
      },
      limitations: [
        "Functions gateway envelope and actor are synthetic; no actual Cloud sign-in, Cloud timing, native/UI/provider proof",
        "Storage file port and image-resource URI port are fake; actual service PNG sanitizer and client byte/hash validation execute",
        "Optimistic store commit failure is locally modeled; actual Appwrite REST adapter communicates only with loopback test server",
      ],
      sourceStage: stage,
    };
    await writeFile(
      `${directory}/result.json`,
      JSON.stringify(result, null, 2) + "\n",
    );
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await rpc("close");
    child.stdin.end();
    child.kill("SIGTERM");
  }
}
void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
  child.kill("SIGTERM");
});
