import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { HostLifetime } from "../host/scope";
import { ScopedHostStorage } from "../host/storage";
import type { AtomicHostStorage } from "../host/storage";
import { PreviewRuntimeAdapter } from "../runtime/preview";
import type { PickedImage, RuntimeAdapter } from "../runtime/types";
import { decodeAppSpec } from "../spec/decode";
import { RuntimeError } from "../runtime/errors";
import { BackendError } from "../backend/errors";
import { withPrivateMedia } from "./adapter";
import { PrivateMediaController } from "./controller";
import { MediaRecovery, decodeUpload } from "./recovery";
import { asset, context, decode64, encode64, readChunk } from "./codec";
import { CHUNK_BYTES, ORIGINAL_BYTES } from "./types";
import { attachReadyMedia } from "./attachment";
import type { MediaPorts, ImageResource, MediaUploadContext } from "./types";
const sha = (bytes: Uint8Array | string) =>
  createHash("sha256").update(bytes).digest("hex");
const failure = (code: string) => (error: unknown) =>
  error instanceof RuntimeError && error.code === code;
function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (reason: unknown) => void;
  const promise = new Promise<T>((ok, fail) => {
    resolve = ok;
    reject = fail;
  });
  return { promise, resolve, reject };
}
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
function image(length = 32): PickedImage {
  const bytes = new Uint8Array(length).fill(37);
  bytes.set([255, 216, 255]);
  return { bytes, mimeType: "image/jpeg", name: "private-original-name.jpg" };
}
function base(role = "owner", archived = false): RuntimeAdapter {
  const spec = decodeAppSpec(
    JSON.parse(
      readFileSync(
        new URL(
          "../../../../appwrite_backend/packages/appnest_spec/fixtures/photoJournal.json",
          import.meta.url,
        ),
        "utf8",
      ),
    ),
  );
  const adapter = new PreviewRuntimeAdapter(spec, { role: role as "owner" });
  Object.defineProperties(adapter, {
    appId: { value: "app" },
    versionId: { value: "version" },
    preview: { value: false },
    role: { value: role },
    archived: { value: archived },
  });
  return adapter;
}
function uploadContext(adapter: RuntimeAdapter): MediaUploadContext {
  const action = adapter.spec.actions.find(
      (a) => a.capability === "records.create.v1",
    )!,
    collection = adapter.spec.collections.find(
      (c) => c.id === action.collectionId,
    )!;
  return {
    versionId: adapter.versionId,
    actionId: action.id,
    fieldId: collection.fields.find((f) => f.type === "image")!.id,
  };
}
class Store implements AtomicHostStorage {
  entries = new Map<string, string>();
  writes = 0;
  failBefore = false;
  afterCommit: ((value: unknown) => boolean) | null = null;
  async read(key: string) {
    return this.entries.get(key) ?? null;
  }
  async change(key: string, update: (value: string | null) => string | null) {
    this.writes++;
    if (this.failBefore) {
      this.failBefore = false;
      throw new Error("PRIVATE_STORAGE_VALUE");
    }
    const next = update(this.entries.get(key) ?? null);
    if (next === null) this.entries.delete(key);
    else this.entries.set(key, next);
    if (this.afterCommit?.(next === null ? null : JSON.parse(next))) {
      this.afterCommit = null;
      throw new Error("PRIVATE_STORAGE_VALUE");
    }
  }
}
class Ports implements MediaPorts {
  images = new Map<string, Uint8Array>();
  created = 0;
  removed = 0;
  picks = 0;
  disposed = 0;
  selected: PickedImage | null = image();
  materialize: ReturnType<typeof deferred<void>> | null = null;
  uri = "blob:test-";
  async sha256(bytes: Uint8Array) {
    return sha(bytes);
  }
  async pick() {
    this.picks++;
    return this.selected;
  }
  async image(
    bytes: Uint8Array,
    _type: "image/jpeg" | "image/png",
  ): Promise<ImageResource> {
    const copy = Uint8Array.from(bytes);
    if (this.materialize) await this.materialize.promise;
    const uri = this.uri + ++this.created;
    this.images.set(uri, copy);
    let removed = false;
    return {
      uri,
      dispose: () => {
        if (removed) return;
        removed = true;
        this.removed++;
        copy.fill(0);
        this.images.delete(uri);
      },
    };
  }
  dispose() {
    this.disposed++;
    for (const bytes of this.images.values()) bytes.fill(0);
    this.images.clear();
  }
}
class Broker {
  requests: Record<string, unknown>[] = [];
  reservations = 0;
  ready = true;
  bytes = image().bytes;
  uploaded = 0;
  status = "pending";
  beginReplies = new Map<string, unknown>();
  completeReplies = new Map<string, unknown>();
  chunks = new Map<number, string>();
  before: ((payload: Record<string, unknown>) => Promise<void>) | null = null;
  after:
    | ((payload: Record<string, unknown>, reply: unknown) => Promise<unknown>)
    | null = null;
  readChange: ((reply: Record<string, unknown>) => void) | null = null;
  info(ready = this.status === "ready") {
    return ready
      ? {
          assetId: "asset",
          status: "ready",
          contentType: "image/jpeg",
          byteLength: this.bytes.length,
          width: 400,
          height: 300,
          sha256: sha(this.bytes),
        }
      : {
          assetId: "asset",
          status: this.status,
          uploadedBytes: this.uploaded,
          inputBytes: this.bytes.length,
          ...(this.status === "failed" ? { error: "invalid_image" } : {}),
        };
  }
  call = async (payload: Record<string, unknown>): Promise<unknown> => {
    this.requests.push(JSON.parse(JSON.stringify(payload)));
    if (this.before) await this.before(payload);
    let reply: unknown;
    switch (payload.op) {
      case "spec.media.begin": {
        const key = payload.operationId as string;
        if (!this.beginReplies.has(key)) {
          this.reservations++;
          this.status = "pending";
          this.bytes = new Uint8Array(payload.byteLength as number);
          this.uploaded = 0;
          this.beginReplies.set(key, {
            asset: this.info(false),
            chunkBytes: CHUNK_BYTES,
            expiresAt: "2030-01-01T11:00:00.000Z",
          });
        }
        reply = this.beginReplies.get(key);
        break;
      }
      case "spec.media.chunk": {
        const offset = payload.offset as number,
          chunk = decode64(payload.dataBase64);
        assert.equal(sha(chunk), payload.sha256);
        if (this.chunks.has(offset))
          assert.equal(this.chunks.get(offset), payload.sha256);
        else {
          assert.equal(offset, this.uploaded);
          this.bytes.set(chunk, offset);
          this.uploaded += chunk.length;
          this.chunks.set(offset, payload.sha256 as string);
        }
        reply = { assetId: "asset", uploadedBytes: this.uploaded };
        break;
      }
      case "spec.media.complete": {
        const key = payload.operationId as string;
        if (!this.completeReplies.has(key)) {
          assert.equal(this.uploaded, this.bytes.length);
          this.status = "queued";
          this.completeReplies.set(key, { asset: this.info(false) });
        }
        reply = this.completeReplies.get(key);
        break;
      }
      case "spec.media.status":
        if (
          this.ready &&
          ["queued", "processing", "ready"].includes(this.status)
        )
          this.status = "ready";
        reply = { asset: this.info() };
        break;
      case "spec.media.read": {
        const variant = payload.variant as string,
          bytes =
            variant === "thumbnail"
              ? this.bytes.subarray(
                  0,
                  Math.min(this.bytes.length, CHUNK_BYTES + 11),
                )
              : this.bytes;
        const offset = payload.offset as number,
          end = Math.min(offset + CHUNK_BYTES, bytes.length),
          chunk = bytes.subarray(offset, end);
        const row = {
          assetId: "asset",
          variant,
          offset,
          nextOffset: end === bytes.length ? null : end,
          byteLength: bytes.length,
          contentType: "image/jpeg",
          sha256: sha(bytes),
          chunkSha256: sha(chunk),
          dataBase64: encode64(chunk),
          width: 400,
          height: 300,
          cacheControl: "private, no-store",
        };
        this.readChange?.(row);
        reply = row;
        break;
      }
      default:
        throw new Error("Unexpected broker operation");
    }
    return this.after ? this.after(payload, reply) : reply;
  };
}
function fixture(
  options: {
    role?: string;
    versionId?: string;
    archived?: boolean;
    store?: Store;
    broker?: Broker;
    ports?: Ports;
    pollAttempts?: number;
    requestTimeoutMs?: number;
    isCurrent?: () => boolean;
  } = {},
) {
  const lifetime = new HostLifetime(scope),
    storage = new ScopedHostStorage(lifetime, options.store ?? new Store()),
    ports = options.ports ?? new Ports(),
    broker = options.broker ?? new Broker(),
    adapter = base(options.role, options.archived);
  if (options.versionId)
    Object.defineProperty(adapter, "versionId", { value: options.versionId });
  let sequence = 0,
    accessFailures = 0;
  const controller = new PrivateMediaController(
    adapter,
    broker.call,
    lifetime,
    {
      privateMedia: true,
      newId: () => `operation-${++sequence}`,
      recovery: new MediaRecovery(storage),
      ports,
      pollAttempts: options.pollAttempts,
      requestTimeoutMs: options.requestTimeoutMs,
      isCurrent: options.isCurrent,
      onAccessFailure: () => {
        accessFailures++;
      },
    },
  );
  return {
    lifetime,
    storage,
    ports,
    broker,
    adapter,
    controller,
    context: uploadContext(adapter),
    newIds: () => sequence,
    accessFailures: () => accessFailures,
  };
}
const unknown = () =>
  new BackendError(
    "Do not echo BASE64_OR_SECRET",
    "connection_failed",
    "transport",
    true,
  );

test("5 MiB uploads persist twenty bounded host entries before the first RPC and never save a record", async () => {
  const store = new Store(),
    f = fixture({ store });
  let checked = false;
  f.broker.before = async (payload) => {
    if (!checked) {
      checked = true;
      assert.equal(payload.op, "spec.media.begin");
      assert.equal(
        [...store.entries.keys()].filter((k) =>
          k.startsWith("private-media-v1-"),
        ).length,
        20,
      );
      assert.ok(
        Math.max(...[...store.entries.values()].map((v) => v.length)) < 400_000,
      );
    }
  };
  assert.equal(
    await f.controller.upload(f.context, image(ORIGINAL_BYTES)),
    "asset",
  );
  const chunks = f.broker.requests.filter((r) => r.op === "spec.media.chunk");
  assert.equal(chunks.length, 20);
  assert.deepEqual(
    chunks.map((r) => r.offset),
    Array.from({ length: 20 }, (_, i) => i * CHUNK_BYTES),
  );
  assert.equal(
    f.broker.requests.some((r) => r.op === "spec.execute"),
    false,
  );
  assert.equal(f.controller.getSnapshot().stage, "ready");
  assert.equal(
    JSON.stringify(f.controller.getSnapshot()).includes("dataBase64"),
    false,
  );
  assert.equal(
    JSON.stringify(f.controller.getSnapshot()).includes(
      "private-original-name",
    ),
    false,
  );
  f.lifetime.dispose();
});
test("oversized, unsupported and forged contexts fail before any mutation", async () => {
  const f = fixture();
  for (const value of [
    image(ORIGINAL_BYTES + 1),
    { ...image(), mimeType: "image/png" as const },
    { ...image(), bytes: new Uint8Array([1, 2, 3]) },
  ])
    await assert.rejects(f.controller.upload(f.context, value));
  for (const value of [
    { draftRevision: 1, ...f.context },
    { ...f.context, versionId: "other" },
    { ...f.context, fieldId: "notAnImage" },
    { ...f.context, targetRecordId: "record" },
  ])
    await assert.rejects(
      f.controller.upload(value as MediaUploadContext, image()),
    );
  assert.equal(f.broker.requests.length, 0);
  f.lifetime.dispose();
});
test("viewer and archived scopes cannot start uploads or choose images", async () => {
  for (const options of [{ role: "viewer" }, { archived: true }]) {
    const f = fixture(options);
    await f.controller.recover();
    await assert.rejects(
      f.controller.upload(f.context, image()),
      failure("forbidden"),
    );
    await assert.rejects(f.controller.pickImage());
    assert.equal(f.ports.picks, 0);
    assert.equal(f.broker.requests.length, 0);
    f.lifetime.dispose();
  }
});
test("picker cancellation has no storage reservation or broker effects", async () => {
  const store = new Store(),
    f = fixture({ store });
  f.ports.selected = null;
  await f.controller.recover();
  assert.equal(await f.controller.pickImage(), null);
  assert.equal(store.writes, 0);
  assert.equal(f.broker.requests.length, 0);
  f.lifetime.dispose();
});
for (const operation of [
  "spec.media.begin",
  "spec.media.chunk",
  "spec.media.complete",
]) {
  test(`unknown ${operation} survives reopening with the exact retained request and no automatic replay`, async () => {
    const store = new Store(),
      broker = new Broker();
    let lost = false,
      original = "";
    broker.after = async (payload, reply) => {
      if (payload.op === operation && !lost) {
        lost = true;
        original = sha(JSON.stringify(payload));
        throw unknown();
      }
      return reply;
    };
    const first = fixture({ store, broker });
    await assert.rejects(
      first.controller.upload(first.context, image(CHUNK_BYTES + 9)),
      (e: unknown) => e instanceof RuntimeError && e.uncertain,
    );
    assert.equal(first.controller.getSnapshot().uncertain, true);
    first.lifetime.dispose();
    const count = broker.requests.length,
      next = fixture({ store, broker });
    await next.controller.recover();
    assert.equal(broker.requests.length, count);
    assert.equal(next.newIds(), 0);
    assert.equal(await next.controller.retry(), "asset");
    assert.equal(sha(JSON.stringify(broker.requests[count])), original);
    assert.equal(broker.reservations, 1);
    assert.equal(next.newIds(), 0);
    next.lifetime.dispose();
  });
}
test("a corrupted local chunk never reaches the network during recovery retry", async () => {
  const store = new Store(),
    f = fixture({ store });
  let lost = false;
  f.broker.after = async (p, r) => {
    if (!lost) {
      lost = true;
      throw unknown();
    }
    return r;
  };
  await assert.rejects(f.controller.upload(f.context, image()));
  const key = [...store.entries.keys()].find((k) => k.endsWith("-0"))!;
  const saved = JSON.parse(store.entries.get(key)!);
  saved.payload.data = encode64(new Uint8Array(32));
  store.entries.set(key, JSON.stringify(saved));
  const count = f.broker.requests.length;
  await assert.rejects(f.controller.retry(), failure("media_saved_invalid"));
  assert.equal(f.broker.requests.length, count);
  f.lifetime.dispose();
});
test("interrupted local preparation can only resume with identical bytes and sends nothing before persistence", async () => {
  const store = new Store(),
    f = fixture({ store });
  let once = false;
  const original = store.change.bind(store);
  store.change = async (key, update) => {
    if (key.endsWith("-1") && !once) {
      once = true;
      throw new Error("Private write failed");
    }
    return original(key, update);
  };
  const picked = image(CHUNK_BYTES + 3);
  await assert.rejects(f.controller.upload(f.context, picked));
  assert.equal(f.broker.requests.length, 0);
  await assert.rejects(
    f.controller.retry(),
    failure("media_reselect_required"),
  );
  assert.equal(f.broker.requests.length, 0);
  await assert.rejects(
    f.controller.upload(f.context, image()),
    failure("media_pending"),
  );
  assert.equal(await f.controller.upload(f.context, picked), "asset");
  assert.equal(f.broker.reservations, 1);
  f.lifetime.dispose();
});
test("unknown local acknowledgement persistence reloads the committed manifest without recreating an asset", async () => {
  const store = new Store();
  store.afterCommit = (value) =>
    Boolean(
      value &&
      (value as { payload?: { phase?: string; assetId?: string } }).payload
        ?.phase === "chunks" &&
      (value as { payload: { assetId?: string } }).payload.assetId,
    );
  const f = fixture({ store });
  await assert.rejects(f.controller.upload(f.context, image()));
  assert.equal(f.controller.getSnapshot().initialized, false);
  assert.equal(await f.controller.retry(), "asset");
  assert.equal(f.broker.reservations, 1);
  f.lifetime.dispose();
});
test("a higher duplicate uploadedBytes acknowledgement does not skip retained chunk validation", async () => {
  const f = fixture();
  let first = true;
  f.broker.after = async (payload, reply) => {
    if (payload.op === "spec.media.chunk" && first) {
      first = false;
      throw unknown();
    }
    if (payload.op === "spec.media.chunk")
      return { assetId: "asset", uploadedBytes: CHUNK_BYTES * 2 + 7 };
    return reply;
  };
  await assert.rejects(
    f.controller.upload(f.context, image(CHUNK_BYTES * 2 + 7)),
  );
  assert.equal(await f.controller.retry(), "asset");
  assert.deepEqual(
    f.broker.requests
      .filter((r) => r.op === "spec.media.chunk")
      .map((r) => r.offset),
    [0, 0, CHUNK_BYTES, CHUNK_BYTES * 2],
  );
  f.lifetime.dispose();
});
test("queued processing is persisted and status polling never auto-replays upload mutations", async () => {
  const broker = new Broker();
  broker.ready = false;
  const f = fixture({ broker });
  await assert.rejects(
    f.controller.upload(f.context, image()),
    failure("media_processing"),
  );
  assert.equal(f.controller.getSnapshot().stage, "processing");
  const mutations = broker.requests.filter(
    (r) => r.op !== "spec.media.status",
  ).length;
  assert.equal(await f.controller.poll(), null);
  assert.equal(
    broker.requests.filter((r) => r.op !== "spec.media.status").length,
    mutations,
  );
  broker.ready = true;
  assert.equal(await f.controller.poll(), "asset");
  f.lifetime.dispose();
});
test("failed processing is not ready and a new upload requires explicit local discard", async () => {
  const broker = new Broker();
  broker.ready = false;
  const f = fixture({ broker });
  await assert.rejects(
    f.controller.upload(f.context, image()),
    failure("media_processing"),
  );
  broker.status = "failed";
  await assert.rejects(f.controller.poll(), failure("media_failed"));
  assert.equal(f.controller.getSnapshot().stage, "failed");
  const count = broker.requests.length;
  await assert.rejects(f.controller.retry(), failure("media_pending"));
  assert.equal(broker.requests.length, count);
  await f.controller.discard();
  assert.equal(f.controller.getSnapshot().stage, null);
  f.lifetime.dispose();
});
test("caller byte mutation cannot change the original retained upload", async () => {
  const f = fixture(),
    picked = image(CHUNK_BYTES + 17),
    original = sha(picked.bytes);
  const upload = f.controller.upload(f.context, picked);
  picked.bytes.fill(0);
  assert.equal(await upload, "asset");
  assert.equal(sha(f.broker.bytes), original);
  f.lifetime.dispose();
});
test("concurrent controllers reserve one local upload and cannot overwrite each other's envelopes", async () => {
  const store = new Store(),
    one = fixture({ store }),
    two = fixture({ store });
  const gate = deferred<void>();
  one.broker.before = async () => gate.promise;
  const first = one.controller.upload(one.context, image());
  await new Promise((r) => setTimeout(r, 10));
  await assert.rejects(
    two.controller.upload(two.context, image(33)),
    failure("media_pending"),
  );
  assert.equal(two.broker.requests.length, 0);
  gate.resolve();
  await first;
  one.lifetime.dispose();
  two.lifetime.dispose();
});
test("timeout preserves the exact pending mutation and no automatic retry occurs", async () => {
  const f = fixture({ requestTimeoutMs: 5 }),
    gate = deferred<void>();
  f.broker.before = async () => gate.promise;
  await assert.rejects(
    f.controller.upload(f.context, image()),
    (e: unknown) => e instanceof RuntimeError && e.uncertain,
  );
  assert.equal(f.broker.requests.length, 1);
  assert.equal(f.controller.getSnapshot().uncertain, true);
  gate.resolve();
  await new Promise((r) => setImmediate(r));
  assert.equal(f.broker.requests.length, 1);
  f.lifetime.dispose();
});
test("a published-version change can recover an exact begin receipt but cannot start new chunk work", async () => {
  const store = new Store(),
    broker = new Broker();
  let lost = false;
  broker.after = async (p, r) => {
    if (!lost) {
      lost = true;
      throw unknown();
    }
    return r;
  };
  const old = fixture({ store, broker });
  await assert.rejects(old.controller.upload(old.context, image()));
  old.lifetime.dispose();
  const next = fixture({ store, broker, versionId: "new-version" });
  await next.controller.recover();
  await assert.rejects(
    next.controller.retry(),
    failure("media_context_changed"),
  );
  assert.deepEqual(
    broker.requests.map((r) => r.op),
    ["spec.media.begin", "spec.media.begin"],
  );
  next.lifetime.dispose();
});
test("chunked reads verify hashes, dimensions, offsets and whole bytes before creating a private URI", async () => {
  const f = fixture();
  await f.controller.upload(f.context, image(CHUNK_BYTES + 19));
  const asset = await f.controller.read("asset", "display");
  assert.ok(asset.uri.startsWith("blob:"));
  assert.equal(f.ports.created, 1);
  assert.equal(
    f.broker.requests.filter((r) => r.op === "spec.media.read").length,
    2,
  );
  const count = f.broker.requests.filter(
    (r) => r.op === "spec.media.read",
  ).length;
  const again = await f.controller.read("asset", "display");
  assert.equal(again.uri, asset.uri);
  assert.equal(
    f.broker.requests.filter((r) => r.op === "spec.media.read").length,
    count,
  );
  assert.ok(
    f.broker.requests.filter((r) => r.op === "spec.media.status").length >= 3,
  );
  f.lifetime.dispose();
  assert.equal(f.ports.images.size, 0);
});
for (const change of [
  "digest",
  "whole",
  "offset",
  "length",
  "mime",
  "dimensions",
  "variant",
  "asset",
  "cache",
]) {
  test(`corrupt ${change} read metadata cannot create an image resource`, async () => {
    const f = fixture();
    await f.controller.upload(f.context, image(CHUNK_BYTES + 7));
    f.broker.readChange = (row) => {
      if (change === "digest") row.chunkSha256 = "0".repeat(64);
      if (change === "whole") row.sha256 = "0".repeat(64);
      if (change === "offset") row.offset = 1;
      if (change === "length") row.byteLength = ORIGINAL_BYTES + 1;
      if (change === "mime") row.contentType = "image/svg+xml";
      if (change === "dimensions") row.width = 1e9;
      if (change === "variant") row.variant = "display";
      if (change === "asset") row.assetId = "other";
      if (change === "cache") row.cacheControl = "public";
    };
    await assert.rejects(f.controller.read("asset", "thumbnail"));
    assert.equal(f.ports.created, 0);
    f.lifetime.dispose();
  });
}
test("a subsequent authorization failure revokes every cached URL and returns no cached pixels", async () => {
  const f = fixture();
  await f.controller.upload(f.context, image());
  await f.controller.read("asset");
  assert.equal(f.ports.images.size, 1);
  f.broker.before = async (p) => {
    if (p.op === "spec.media.status")
      throw new BackendError(
        "Private server detail",
        "forbidden",
        "service",
        false,
        403,
      );
  };
  await assert.rejects(f.controller.read("asset"));
  assert.equal(f.ports.images.size, 0);
  assert.equal(f.controller.getSnapshot().accessDenied, true);
  assert.equal(f.accessFailures(), 1);
  f.lifetime.dispose();
});
test("closing an account scope rejects late downloads and late auth failures without notifying a new account", async () => {
  const f = fixture();
  await f.controller.upload(f.context, image());
  const gate = deferred<void>();
  f.broker.before = async (p) => {
    if (p.op === "spec.media.read") await gate.promise;
  };
  const reading = f.controller.read("asset");
  await new Promise((r) => setImmediate(r));
  f.lifetime.dispose();
  await assert.rejects(reading);
  gate.reject(
    new BackendError(
      "Private error",
      "user_unauthorized",
      "unauthenticated",
      false,
      401,
    ),
  );
  await new Promise((r) => setImmediate(r));
  assert.equal(f.ports.created, 0);
  assert.equal(f.accessFailures(), 0);
  assert.equal(f.controller.getSnapshot().asset, null);
});
test("a resource created after scope closure is immediately revoked", async () => {
  const ports = new Ports(),
    f = fixture({ ports });
  await f.controller.upload(f.context, image());
  ports.materialize = deferred<void>();
  const reading = f.controller.read("asset");
  await new Promise((r) => setImmediate(r));
  f.lifetime.dispose();
  ports.materialize.resolve();
  await assert.rejects(reading);
  assert.equal(ports.images.size, 0);
  assert.equal(ports.removed, 1);
});
test("a URI port cannot smuggle a public bearer URL or data URI into the renderer", async () => {
  for (const uri of [
    "https://example.test/private?token=SECRET-",
    "data:image/jpeg;base64,",
  ]) {
    const ports = new Ports(),
      f = fixture({ ports });
    ports.uri = uri;
    await f.controller.upload(f.context, image());
    await assert.rejects(f.controller.read("asset"));
    assert.equal(ports.removed, 1);
    assert.equal(f.controller.getSnapshot().error?.includes("SECRET"), false);
    f.lifetime.dispose();
  }
});
test("preview and unavailable capabilities preserve the original isolated adapter without touching live ports", async () => {
  const f = fixture(),
    preview = new PreviewRuntimeAdapter(f.adapter.spec);
  const wrapped = withPrivateMedia(
    preview,
    async () => {
      throw new Error("Live transport must not run");
    },
    f.lifetime,
    {
      privateMedia: true,
      newId: () => "id",
      storage: f.storage,
      ports: f.ports,
    },
  );
  assert.equal(wrapped, preview);
  assert.equal(f.ports.picks, 0);
  assert.equal(
    withPrivateMedia(f.adapter, f.broker.call, f.lifetime, {
      privateMedia: false,
      newId: () => "id",
      storage: f.storage,
      ports: f.ports,
    }),
    f.adapter,
  );
  f.lifetime.dispose();
});
test("the wrapper delegates the complete runtime and lifecycle while guarding closed scopes", async () => {
  const f = fixture();
  let active: boolean | null = null,
    disposed = 0;
  const realDispose = f.adapter.dispose.bind(f.adapter);
  f.adapter.dispose = () => {
    disposed++;
    realDispose();
  };
  f.adapter.setActive = (value) => {
    active = value;
  };
  const wrapped = withPrivateMedia(f.adapter, f.broker.call, f.lifetime, {
    privateMedia: true,
    newId: () => "unused",
    storage: f.storage,
    ports: f.ports,
  });
  await wrapped.media!.recover();
  assert.equal(wrapped.appId, "app");
  assert.equal(wrapped.spec, f.adapter.spec);
  assert.equal(wrapped.features.has("imageRead"), true);
  wrapped.setActive?.(false);
  assert.equal(active, false);
  await assert.rejects(
    wrapped.uploadImage(image()),
    failure("media_context_required"),
  );
  assert.equal(f.broker.requests.length, 0);
  f.lifetime.dispose();
  await assert.rejects(wrapped.members());
  wrapped.dispose();
  wrapped.dispose();
  assert.equal(disposed, 1);
  assert.equal(wrapped.features.has("imageRead"), false);
});
test("strict DTOs reject mixed contexts, internal statuses, noncanonical base64 and mismatched read pages", () => {
  for (const value of ["A===", "AA=A", "AB==", "AAAA\n", "===="]) {
    assert.throws(() => decode64(value));
  }
  assert.throws(() => context({ draftRevision: 1, versionId: "version" }));
  assert.throws(() =>
    context({
      versionId: "version",
      actionId: "action",
      fieldId: "field",
      expectedRecordRevision: 1,
    }),
  );
  for (const status of ["uploading", "expired", "deleting", "deleted"]) {
    assert.throws(() =>
      asset({ assetId: "asset", status, uploadedBytes: 0, inputBytes: 1 }),
    );
  }
  const data = {
    assetId: "asset",
    variant: "thumbnail",
    offset: 0,
    nextOffset: null,
    byteLength: 3,
    contentType: "image/jpeg",
    width: 1,
    height: 1,
    sha256: sha(image(3).bytes),
    chunkSha256: sha(image(3).bytes),
    dataBase64: encode64(image(3).bytes),
    cacheControl: "private, no-store",
  };
  assert.equal(readChunk(data, "asset", "thumbnail", 0).bytes.length, 3);
  assert.throws(() =>
    readChunk({ ...data, nextOffset: 3 }, "asset", "thumbnail", 0),
  );
  assert.throws(() => decodeUpload({ format: 1 }));
});

for (const operation of [
  "spec.media.begin",
  "spec.media.chunk",
  "spec.media.complete",
]) {
  test(`a malformed ${operation} acknowledgement retains the exact committed request for explicit recovery`, async () => {
    const f = fixture();
    let corrupt = true;
    f.broker.after = async (payload, reply) => {
      if (payload.op === operation && corrupt) {
        corrupt = false;
        return { wrong: "PRIVATE_BASE64" };
      }
      return reply;
    };
    await assert.rejects(
      f.controller.upload(f.context, image()),
      (error) =>
        error instanceof RuntimeError &&
        error.uncertain &&
        !error.message.includes("PRIVATE_BASE64"),
    );
    const retained = f.broker.requests.find(
      (request) => request.op === operation,
    )!;
    assert(f.controller.getSnapshot().uncertain);
    assert.equal(await f.controller.retry(), "asset");
    const calls = f.broker.requests.filter(
      (request) => request.op === operation,
    );
    assert.deepEqual(calls[1], retained);
    assert.equal(f.broker.reservations, 1);
    f.lifetime.dispose();
  });
}
test("an unconfirmed local reservation is recovered in the same controller and requires identical reselected bytes", async () => {
  const store = new Store();
  store.afterCommit = (value) =>
    Boolean(
      value &&
      (value as { payload?: { phase?: string } }).payload?.phase ===
        "preparing",
    );
  const f = fixture({ store });
  await assert.rejects(f.controller.upload(f.context, image()));
  assert.equal(f.broker.requests.length, 0);
  assert.equal(f.controller.getSnapshot().initialized, false);
  await assert.rejects(
    f.controller.retry(),
    failure("media_reselect_required"),
  );
  await assert.rejects(
    f.controller.upload(f.context, image(33)),
    failure("media_pending"),
  );
  assert.equal(await f.controller.upload(f.context, image()), "asset");
  assert.equal(f.broker.reservations, 1);
  f.lifetime.dispose();
});
test("ready media attachment reauthorizes read-only status and edits only the matching current form", async () => {
  const f = fixture();
  await f.controller.upload(f.context, image());
  const mutations = f.broker.requests.filter(
    (request) => request.op !== "spec.media.status",
  ).length;
  const attached: string[] = [];
  assert(
    await attachReadyMedia(
      f.controller,
      f.context,
      () => true,
      (id) => attached.push(id),
    ),
  );
  assert.deepEqual(attached, ["asset"]);
  assert.equal(
    f.broker.requests.filter((request) => request.op !== "spec.media.status")
      .length,
    mutations,
  );
  await assert.rejects(
    attachReadyMedia(
      f.controller,
      { draftRevision: 1 },
      () => true,
      () => assert.fail("different field attached"),
    ),
    failure("media_context_changed"),
  );
  let current = true;
  f.broker.before = async (request) => {
    if (request.op === "spec.media.status") current = false;
  };
  await assert.rejects(
    attachReadyMedia(
      f.controller,
      f.context,
      () => current,
      () => assert.fail("late attachment"),
    ),
    failure("media_context_changed"),
  );
  f.lifetime.dispose();
});
test("picker operations serialize and late picker bytes are cleared when the app scope closes", async () => {
  const f = fixture();
  await f.controller.recover();
  const gate = deferred<PickedImage | null>();
  f.ports.pick = () => gate.promise;
  const one = f.controller.pickImage();
  await assert.rejects(
    f.controller.pickImage(),
    failure("media_recovery_required"),
  );
  f.lifetime.dispose();
  const late = image();
  gate.resolve(late);
  await assert.rejects(one, failure("disposed"));
  assert(late.bytes.every((value) => value === 0));
});
test("read concurrency stays bounded across queue handoff and closed queued reads send nothing", async () => {
  const f = fixture();
  await f.controller.upload(f.context, image());
  const initial = f.broker.requests.length;
  const gate = deferred<void>();
  let active = 0,
    maximum = 0;
  const transport = async (request: Record<string, unknown>) => {
    if (request.op === "spec.media.status") {
      active++;
      maximum = Math.max(maximum, active);
      await gate.promise;
      active--;
      return { asset: { ...f.broker.info(true), assetId: request.assetId } };
    }
    assert.fail("closed scope must not download");
  };
  const c = new PrivateMediaController(f.adapter, transport, f.lifetime, {
    privateMedia: true,
    newId: () => "operation",
    recovery: new MediaRecovery(f.storage),
    ports: f.ports,
    readConcurrency: 2,
  });
  const reads = Array.from({ length: 12 }, (_, index) =>
    c.read(`asset${index}`),
  );
  await new Promise((resolve) => setTimeout(resolve, 5));
  assert.equal(maximum, 2);
  f.lifetime.dispose();
  gate.resolve();
  const outcomes = await Promise.allSettled(reads);
  assert(outcomes.every((result) => result.status === "rejected"));
  assert.equal(maximum, 2);
  assert.equal(f.broker.requests.length, initial);
});
test("role downgrades and version scope changes fence new uploads without echoing raw transport data", async () => {
  let current = true;
  const f = fixture({ isCurrent: () => current });
  await f.controller.upload(f.context, image());
  current = false;
  assert.throws(
    () => f.controller.read("asset"),
    failure("media_scope_changed"),
  );
  assert.equal(f.ports.images.size, 0);
  f.lifetime.dispose();
  const other = fixture();
  other.broker.before = async () => {
    throw new BackendError(
      "SECRET_BASE64_AND_TOKEN",
      "permission_denied",
      "service",
      false,
      403,
    );
  };
  await assert.rejects(
    other.controller.upload(other.context, image()),
    (error) =>
      error instanceof RuntimeError &&
      !error.message.includes("SECRET_BASE64_AND_TOKEN"),
  );
  assert(other.controller.getSnapshot().accessDenied);
  assert.equal(other.accessFailures(), 1);
  other.lifetime.dispose();
});

test("an adapter authority change invalidates cached pixels even without an optional host callback", async () => {
  const owner = base();
  let role = owner.role;
  const scoped = Object.create(owner) as RuntimeAdapter;
  Object.defineProperty(scoped, "role", { get: () => role });
  const f = fixture();
  const c = new PrivateMediaController(scoped, f.broker.call, f.lifetime, {
    privateMedia: true,
    newId: () => "new-operation",
    recovery: new MediaRecovery(f.storage),
    ports: f.ports,
  });
  await c.upload(uploadContext(scoped), image());
  await c.read("asset");
  assert.equal(f.ports.images.size, 1);
  role = "viewer";
  assert.throws(() => c.read("asset"), failure("media_scope_changed"));
  assert.equal(f.ports.images.size, 0);
  f.lifetime.dispose();
});

test("failed wrapper initialization cleans platform resources without exposing filesystem details", () => {
  const f = fixture();
  const wrongLifetime = new HostLifetime({ ...scope, appId: "different" });
  assert.throws(
    () =>
      withPrivateMedia(f.adapter, f.broker.call, wrongLifetime, {
        privateMedia: true,
        newId: () => "operation",
        storage: f.storage,
        ports: f.ports,
      }),
    failure("media_local_unavailable"),
  );
  assert.equal(f.ports.disposed, 1);
  f.lifetime.dispose();
  wrongLifetime.dispose();
});
