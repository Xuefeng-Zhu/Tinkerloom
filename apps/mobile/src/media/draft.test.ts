import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { HostLifetime } from "../host/scope";
import type { HostScope } from "../host/scope";
import { ScopedHostStorage } from "../host/storage";
import { decodeAppSpec } from "../spec/decode";
import { RuntimeError } from "../runtime/errors";
import { BackendError } from "../backend/errors";
import {
  createDraftMediaController,
  selectReadyDraftMedia,
  draftMediaAuthority,
} from "./draft";
import type { SavedDraftMediaSnapshot } from "./draft";
import { decodeUpload, MediaRecovery } from "./recovery";
import type { MediaPorts } from "./types";
import { CHUNK_BYTES } from "./types";
import { encode64, decode64 } from "./codec";
const hash = (bytes: Uint8Array | string) =>
  createHash("sha256").update(bytes).digest("hex");
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const failure = (code: string) => (error: unknown) =>
  error instanceof RuntimeError && error.code === code;
function image() {
  return {
    bytes: Uint8Array.from([255, 216, 255, 1, 2, 3, 4, 5]),
    mimeType: "image/jpeg" as const,
    name: "private.jpg",
  };
}
function saved(): SavedDraftMediaSnapshot {
  return {
    appId: "app",
    role: "owner",
    archived: false,
    pendingGeneration: false,
    draft: {
      revision: 1,
      candidateHash: hash("saved"),
      publishedVersionId: null,
      spec: decodeAppSpec(
        JSON.parse(
          readFileSync(
            new URL(
              "../../../../appwrite_backend/packages/appnest_spec/fixtures/photoJournal.json",
              import.meta.url,
            ),
            "utf8",
          ),
        ),
      ),
    },
  };
}
class Store {
  values = new Map<string, string>();
  async read(key: string) {
    return this.values.get(key) ?? null;
  }
  async change(key: string, update: (value: string | null) => string | null) {
    const next = update(this.values.get(key) ?? null);
    if (next === null) this.values.delete(key);
    else this.values.set(key, next);
  }
}
class Ports implements MediaPorts {
  resources = new Set<string>();
  disposed = 0;
  async sha256(bytes: Uint8Array) {
    return hash(bytes);
  }
  async pick() {
    return image();
  }
  async image() {
    const uri = `blob:private-${this.resources.size}`;
    this.resources.add(uri);
    return {
      uri,
      dispose: () => {
        this.resources.delete(uri);
      },
    };
  }
  dispose() {
    this.disposed++;
    this.resources.clear();
  }
}
class Broker {
  calls: Record<string, unknown>[] = [];
  replies = new Map<string, unknown>();
  chunks = new Map<number, string>();
  bytes = new Uint8Array();
  status = "pending";
  ready = true;
  assets = 0;
  after?: (
    request: Record<string, unknown>,
    reply: unknown,
  ) => Promise<unknown>;
  before?: (request: Record<string, unknown>) => Promise<void>;
  info() {
    return this.status === "ready"
      ? {
          assetId: "asset",
          status: "ready",
          contentType: "image/jpeg",
          byteLength: this.bytes.length,
          width: 100,
          height: 80,
          sha256: hash(this.bytes),
        }
      : {
          assetId: "asset",
          status: this.status,
          inputBytes: this.bytes.length,
          uploadedBytes: [...this.chunks.keys()].length ? this.bytes.length : 0,
        };
  }
  call = async (request: Record<string, unknown>): Promise<unknown> => {
    this.calls.push(JSON.parse(JSON.stringify(request)));
    await this.before?.(request);
    let reply: unknown;
    switch (request.op) {
      case "spec.media.begin": {
        const key = request.operationId as string;
        if (!this.replies.has(key)) {
          this.assets++;
          this.bytes = new Uint8Array(request.byteLength as number);
          this.replies.set(key, {
            asset: this.info(),
            chunkBytes: CHUNK_BYTES,
            expiresAt: "2030-01-01T00:00:00.000Z",
          });
        }
        reply = this.replies.get(key);
        break;
      }
      case "spec.media.chunk": {
        const bytes = decode64(request.dataBase64);
        assert.equal(hash(bytes), request.sha256);
        const offset = request.offset as number;
        if (this.chunks.has(offset))
          assert.equal(this.chunks.get(offset), request.sha256);
        else {
          this.bytes.set(bytes, offset);
          this.chunks.set(offset, request.sha256 as string);
        }
        reply = { assetId: "asset", uploadedBytes: this.bytes.length };
        break;
      }
      case "spec.media.complete": {
        const key = request.operationId as string;
        if (!this.replies.has(key)) {
          this.status = "queued";
          this.replies.set(key, { asset: this.info() });
        }
        reply = this.replies.get(key);
        break;
      }
      case "spec.media.status": {
        if (this.ready && ["queued", "ready"].includes(this.status))
          this.status = "ready";
        reply = { asset: this.info() };
        break;
      }
      case "spec.media.read": {
        assert.equal(this.status, "ready");
        reply = {
          assetId: "asset",
          variant: request.variant,
          offset: 0,
          nextOffset: null,
          byteLength: this.bytes.length,
          contentType: "image/jpeg",
          sha256: hash(this.bytes),
          chunkSha256: hash(this.bytes),
          dataBase64: encode64(this.bytes),
          width: 100,
          height: 80,
          cacheControl: "private, no-store",
        };
        break;
      }
      default:
        assert.fail(
          "draft media has no record/query/generation/definition API",
        );
    }
    return this.after ? this.after(request, reply) : reply;
  };
}
function fixture(
  options: {
    store?: Store;
    broker?: Broker;
    saved?: SavedDraftMediaSnapshot;
  } = {},
) {
  const state = options.saved ?? saved(),
    store = options.store ?? new Store(),
    broker = options.broker ?? new Broker(),
    ports = new Ports(),
    parent = new HostLifetime(scope);
  let current: SavedDraftMediaSnapshot | null = state,
    ids = 0,
    hostCalls = 0;
  const makeHost = (input: HostScope) => {
    hostCalls++;
    const lifetime = new HostLifetime(input);
    return { lifetime, storage: new ScopedHostStorage(lifetime, store) };
  };
  const controller = createDraftMediaController(state, broker.call, parent, {
    privateMedia: true,
    newId: () => `id-${++ids}`,
    current: () => current,
    createHostStorage: makeHost,
    ports,
  });
  return {
    controller,
    broker,
    store,
    ports,
    parent,
    state,
    makeHost,
    setCurrent: (value: SavedDraftMediaSnapshot | null) => {
      current = value;
    },
    hostCalls: () => hostCalls,
  };
}

test("unpublished saved drafts have honest null version authority and only a media surface", async () => {
  const f = fixture();
  await f.controller.recover();
  assert.equal(f.controller.base.versionId, null);
  assert.notEqual(f.controller.lifetime, f.parent);
  assert.equal(f.controller.lifetime.key, f.parent.key);
  assert.equal("query" in f.controller, false);
  assert.equal("execute" in f.controller, false);
  assert.equal("permits" in f.controller.base, false);
  assert.equal(f.broker.calls.length, 0);
  assert.equal(await f.controller.uploadDraft(image()), "asset");
  const begin = f.broker.calls[0];
  assert.equal(begin.draftRevision, 1);
  for (const key of ["versionId", "candidateHash", "actionId", "fieldId"])
    assert.equal(Object.hasOwn(begin, key), false);
  const stored = await new MediaRecovery(
    new ScopedHostStorage(f.controller.lifetime, f.store),
    "private-draft-media-v1",
  ).read();
  assert.equal(stored?.versionId, null);
  assert.equal(stored?.candidateHash, f.state.draft!.candidateHash);
  assert.equal(
    (await f.controller.read("asset")).uri.startsWith("blob:"),
    true,
  );
  assert.equal(f.ports.resources.size, 1);
  f.controller.dispose();
  assert(f.parent.active);
  assert(!f.controller.lifetime.active);
  assert.equal(f.ports.resources.size, 0);
  f.parent.dispose();
});

test("draft authority is a frozen copy of saved data and rejects nonsaved/consumed/forbidden states", () => {
  const input = saved(),
    authority = draftMediaAuthority(input);
  input.draft!.revision = 2;
  input.draft!.spec.name = "dirty editor";
  assert.equal(authority.draft.revision, 1);
  assert.notEqual(authority.spec.name, "dirty editor");
  assert(Object.isFrozen(authority.spec));
  for (const change of [
    { role: "viewer" },
    { role: "member" },
    { archived: true },
    { pendingGeneration: true },
    { draft: null },
  ]) {
    const invalid = { ...saved(), ...change } as SavedDraftMediaSnapshot;
    assert.throws(() => draftMediaAuthority(invalid));
  }
  const consumed = saved();
  consumed.draft!.publishedVersionId = "version";
  assert.throws(
    () => draftMediaAuthority(consumed),
    failure("media_draft_consumed"),
  );
});

for (const op of [
  "spec.media.begin",
  "spec.media.chunk",
  "spec.media.complete",
]) {
  test(`unpublished ${op} unknown outcome reopens locally and only explicit retry sends the exact request`, async () => {
    const store = new Store(),
      broker = new Broker();
    let lost = false;
    broker.after = async (request, reply) => {
      if (!lost && request.op === op) {
        lost = true;
        throw new BackendError(
          "PRIVATE_TOKEN",
          "connection_failed",
          "transport",
          true,
        );
      }
      return reply;
    };
    const one = fixture({ store, broker });
    await assert.rejects(
      one.controller.uploadDraft(image()),
      (error) => error instanceof RuntimeError && error.uncertain,
    );
    const request = broker.calls.find((call) => call.op === op)!;
    one.parent.dispose();
    const count = broker.calls.length;
    const two = fixture({ store, broker });
    await two.controller.recover();
    assert.equal(broker.calls.length, count);
    assert.equal(await two.controller.retry(), "asset");
    assert.deepEqual(broker.calls.filter((call) => call.op === op)[1], request);
    assert.equal(broker.assets, 1);
    two.parent.dispose();
  });
}

test("a changed saved draft can acknowledge its old exact begin receipt but cannot start another chunk", async () => {
  const store = new Store(),
    broker = new Broker();
  let lost = false;
  broker.after = async (request, reply) => {
    if (!lost) {
      lost = true;
      throw new Error("lost");
    }
    return reply;
  };
  const one = fixture({ store, broker });
  await assert.rejects(one.controller.uploadDraft(image()));
  one.parent.dispose();
  const next = saved();
  next.draft!.revision = 2;
  next.draft!.candidateHash = hash("new saved");
  const two = fixture({ store, broker, saved: next });
  await two.controller.recover();
  await assert.rejects(
    two.controller.retry(),
    failure("media_context_changed"),
  );
  assert.deepEqual(
    broker.calls.map((call) => call.op),
    ["spec.media.begin", "spec.media.begin"],
  );
  two.parent.dispose();
});

for (const change of [
  "hash",
  "revision",
  "role",
  "archive",
  "generation",
  "missing",
]) {
  test(`saved draft ${change} change fences late completion and closes only its child`, async () => {
    const f = fixture();
    await f.controller.recover();
    const changed = saved();
    if (change === "hash") changed.draft!.candidateHash = hash("other");
    if (change === "revision") changed.draft!.revision = 2;
    if (change === "role") changed.role = "viewer";
    if (change === "archive") changed.archived = true;
    if (change === "generation") changed.pendingGeneration = true;
    f.broker.after = async (_request, reply) => {
      f.setCurrent(change === "missing" ? null : changed);
      return reply;
    };
    await assert.rejects(f.controller.uploadDraft(image()));
    assert.equal(f.broker.calls.length, 1);
    assert(!f.controller.lifetime.active);
    assert(f.parent.active);
    f.parent.dispose();
  });
}

test("same-revision changed candidate hash cannot select old ready media after reopening", async () => {
  const store = new Store(),
    broker = new Broker(),
    one = fixture({ store, broker });
  await one.controller.uploadDraft(image());
  one.parent.dispose();
  const next = saved();
  next.draft!.candidateHash = hash("changed without revision");
  const two = fixture({ store, broker, saved: next });
  await two.controller.recover();
  let selected = 0;
  await assert.rejects(
    selectReadyDraftMedia(
      two.controller,
      two.controller.savedContext,
      () => true,
      () => selected++,
    ),
    failure("media_context_changed"),
  );
  assert.equal(selected, 0);
  two.parent.dispose();
});

test("ready selection is explicit, read-only and cancels if the destination changes during await", async () => {
  const f = fixture();
  await f.controller.uploadDraft(image());
  let selected: string[] = [];
  assert.deepEqual(selected, []);
  const mutations = f.broker.calls.filter(
    (call) => call.op !== "spec.media.status",
  ).length;
  assert(
    await selectReadyDraftMedia(
      f.controller,
      f.controller.savedContext,
      () => true,
      (id) => selected.push(id),
    ),
  );
  assert.deepEqual(selected, ["asset"]);
  assert.equal(
    f.broker.calls.filter((call) => call.op !== "spec.media.status").length,
    mutations,
  );
  let current = true;
  f.broker.before = async () => {
    current = false;
  };
  selected = [];
  await assert.rejects(
    selectReadyDraftMedia(
      f.controller,
      f.controller.savedContext,
      () => current,
      (id) => selected.push(id),
    ),
    failure("media_context_changed"),
  );
  assert.deepEqual(selected, []);
  f.parent.dispose();
});

test("unavailable capability and wrong/shared host scopes fail before broker calls", () => {
  const input = saved(),
    parent = new HostLifetime(scope),
    store = new Store();
  let hosts = 0;
  const common = {
    newId: () => "id",
    current: () => input,
    createHostStorage: () => {
      hosts++;
      return {
        lifetime: parent,
        storage: new ScopedHostStorage(parent, store),
      };
    },
    ports: new Ports(),
  };
  assert.throws(
    () =>
      createDraftMediaController(input, async () => assert.fail(), parent, {
        ...common,
        privateMedia: false,
      }),
    failure("media_unavailable"),
  );
  assert.equal(hosts, 0);
  assert.throws(
    () =>
      createDraftMediaController(input, async () => assert.fail(), parent, {
        ...common,
        privateMedia: true,
      }),
    failure("media_local_unavailable"),
  );
  assert(parent.active);
  parent.dispose();
});

test("parent disposal clears unpublished image cache and null versions are rejected for record manifests", async () => {
  const f = fixture();
  await f.controller.uploadDraft(image());
  await f.controller.read("asset");
  assert.equal(f.ports.resources.size, 1);
  const recovery = new MediaRecovery(
    new ScopedHostStorage(f.controller.lifetime, f.store),
    "private-draft-media-v1",
  );
  const record = await recovery.read();
  assert(record);
  const withoutHash = { ...record };
  delete withoutHash.candidateHash;
  assert.throws(
    () => decodeUpload(withoutHash),
    failure("media_saved_invalid"),
  );
  assert.throws(() =>
    decodeUpload({
      ...record,
      context: { versionId: "version", actionId: "create", fieldId: "photo" },
    }),
  );
  f.parent.dispose();
  assert.equal(f.ports.resources.size, 0);
  assert(!f.controller.lifetime.active);
});

test("draft recovery uses a separate encrypted-host namespace and does not hydrate record recovery", async () => {
  const store = new Store();
  const prior = new HostLifetime(scope),
    storage = new ScopedHostStorage(prior, store);
  await storage.write("private-media-v1", {
    retainedRecordCommand: "unchanged",
  });
  const f = fixture({ store });
  await f.controller.recover();
  assert.equal(f.controller.getSnapshot().stage, null);
  await f.controller.uploadDraft(image());
  assert.deepEqual(await storage.read("private-media-v1"), {
    retainedRecordCommand: "unchanged",
  });
  assert(store.values.has("private-draft-media-v1"));
  f.parent.dispose();
  prior.dispose();
});

test("queued unpublished media only becomes selectable after explicit ready status and discard never deletes remotely", async () => {
  const broker = new Broker();
  broker.ready = false;
  const f = fixture({ broker });
  let selected = 0;
  await assert.rejects(
    f.controller.uploadDraft(image()),
    failure("media_processing"),
  );
  const before = broker.calls.length;
  assert.equal(
    await selectReadyDraftMedia(
      f.controller,
      f.controller.savedContext,
      () => true,
      () => selected++,
    ),
    false,
  );
  assert.equal(selected, 0);
  assert.deepEqual(
    broker.calls.slice(before).map((call) => call.op),
    ["spec.media.status"],
  );
  broker.ready = true;
  assert(
    await selectReadyDraftMedia(
      f.controller,
      f.controller.savedContext,
      () => true,
      () => selected++,
    ),
  );
  assert.equal(selected, 1);
  const count = broker.calls.length;
  await f.controller.discard();
  assert.equal(broker.calls.length, count);
  assert.equal(f.controller.getSnapshot().stage, null);
  f.parent.dispose();
});

test("builder draft media is permitted without a published runtime and unavailable current authority closes its child", async () => {
  const input = saved();
  input.role = "builder";
  const f = fixture({ saved: input });
  await f.controller.recover();
  assert.equal(f.controller.base.versionId, null);
  await f.controller.uploadDraft(image());
  await f.controller.read("asset");
  assert.equal(f.ports.resources.size, 1);
  f.setCurrent(null);
  assert.throws(() => f.controller.read("asset"));
  assert.equal(f.ports.resources.size, 0);
  assert(!f.controller.lifetime.active);
  assert(f.parent.active);
  f.parent.dispose();
});
