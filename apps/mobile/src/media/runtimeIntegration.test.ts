import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { AppwriteBackend } from "../backend/core";
import type { ExecutionResult, SdkAdapter } from "../backend/core";
import { BackendError } from "../backend/errors";
import { FunctionRuntimeAdapter } from "../runtime/functionAdapter";
import type { RuntimeManifest } from "../runtime/functionAdapter";
import { RuntimeError } from "../runtime/errors";
import { fullTemplates } from "../full/catalog";
import { accountTransport } from "../full/FullRegistry";
import type { AccountSession } from "../full/FullRegistry";
import { requestedDeviceCapabilities } from "../spec/bindings";
import { HostLifetime } from "../host/scope";
import { ScopedHostStorage } from "../host/storage";
import type { AtomicHostStorage } from "../host/storage";
import { withPrivateMedia } from "./adapter";
import { mediaRecoveryPresentation } from "./controller";
import type { MediaPorts } from "./types";
const spec = fullTemplates.find(
  (template) => template.id === "photoJournal",
)!.spec;
const wire = JSON.parse(
  readFileSync(
    new URL(
      "../../../../scripts/fixtures/live_media/serviceWire.json",
      import.meta.url,
    ),
    "utf8",
  ),
);
function manifest(): RuntimeManifest {
  return {
    id: "app",
    workspaceId: "workspace",
    name: "Photo Journal",
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: {
      editDefinition: true,
      writeRecords: true,
      share: true,
      archive: true,
      revokeAccess: true,
    },
    allowedActions: spec.actions.map((action) => action.id),
    controlRevision: 1,
    version: { id: "version", number: 1, hash: "a".repeat(64), spec },
    draft: null,
  };
}
const complete = (
  responseStatusCode: number,
  data: unknown,
): ExecutionResult => ({
  status: "completed",
  responseStatusCode,
  responseBody: JSON.stringify(data),
});
const emptyPage = {
  records: [],
  total: 0,
  nextCursor: null,
  versionId: "version",
};
const failure = (code: string) => (error: unknown) =>
  error instanceof RuntimeError && error.code === code;
function backend(execute: SdkAdapter["execute"]) {
  return new AppwriteBackend({
    newId: () => "unused",
    execute,
    account: {
      get: async () => ({}),
      create: async () => ({}),
      createEmailPasswordSession: async () => ({}),
      deleteSession: async () => ({}),
    },
  });
}
class MemoryStore implements AtomicHostStorage {
  entries = new Map<string, string>();
  fail = false;
  async read(key: string) {
    if (this.fail) throw Error("PRIVATE_STORAGE_DIAGNOSTIC");
    return this.entries.get(key) ?? null;
  }
  async change(key: string, update: (value: string | null) => string | null) {
    const value = update(this.entries.get(key) ?? null);
    if (value === null) this.entries.delete(key);
    else this.entries.set(key, value);
  }
}
function host(
  base = new FunctionRuntimeAdapter(manifest(), async () => emptyPage),
  failStorage = false,
) {
  const lifetime = new HostLifetime({
      endpoint: "https://example.test/v1",
      projectId: "project",
      accountId: "owner",
      appId: "app",
    }),
    store = new MemoryStore();
  store.fail = failStorage;
  const storage = new ScopedHostStorage(lifetime, store);
  let removed = 0,
    accessFailures = 0,
    brokerCalls = 0;
  const ports: MediaPorts = {
    sha256: async (bytes) => createHash("sha256").update(bytes).digest("hex"),
    pick: async () => null,
    image: async () => {
      let disposed = false;
      return {
        uri: "blob:host-owned-image",
        dispose() {
          if (!disposed) {
            removed++;
            disposed = true;
          }
        },
      };
    },
    dispose() {},
  };
  const wrapped = withPrivateMedia(
    base,
    async (request) => {
      brokerCalls++;
      if (request.op === "spec.media.status")
        return structuredClone(wire.ready);
      if (request.op === "spec.media.read")
        return structuredClone(wire.thumbnail);
      throw Error("Unexpected media request");
    },
    lifetime,
    {
      privateMedia: true,
      storage,
      ports,
      newId: () => "unused",
      onAccessFailure: () => accessFailures++,
    },
  );
  return {
    wrapped,
    base,
    lifetime,
    store,
    get removed() {
      return removed;
    },
    get accessFailures() {
      return accessFailures;
    },
    get brokerCalls() {
      return brokerCalls;
    },
  };
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

test("real completed core wire conflicts repeat one immutable query, then clean media state stays hidden", async () => {
  const requests: unknown[] = [];
  const sdk = backend(async (body) => {
    requests.push(JSON.parse(body));
    return requests.length < 3
      ? complete(409, { error: "transaction_conflict" })
      : complete(200, emptyPage);
  });
  const base = new FunctionRuntimeAdapter(manifest(), (request) =>
      sdk.executeSpec(request),
    ),
    f = host(base);
  await f.wrapped.media!.recover();
  const input = {
    filters: [
      { fieldId: "title", operator: "contains" as const, value: "original" },
    ],
    limit: 2,
  };
  const pending = f.wrapped.query("memories", input);
  input.filters[0].value = "changed after dispatch";
  assert.deepEqual(await pending, emptyPage);
  assert.equal(requests.length, 3);
  assert.deepEqual(requests[1], requests[0]);
  assert.deepEqual(requests[2], requests[0]);
  const state = f.wrapped.media!.getSnapshot();
  assert.equal(state.error, null);
  assert.equal(state.stage, null);
  assert.equal(mediaRecoveryPresentation(state), "hidden");
  assert.equal(f.brokerCalls, 0);
  f.wrapped.dispose();
  f.lifetime.dispose();
});

test("bounded read retry exhausts at three and original nonmedia RuntimeErrors never become upload recovery", async () => {
  let calls = 0;
  const sdk = backend(async () => {
      calls++;
      return complete(409, { error: "transaction_conflict" });
    }),
    f = host(
      new FunctionRuntimeAdapter(manifest(), (request) =>
        sdk.executeSpec(request),
      ),
    );
  await f.wrapped.media!.recover();
  await assert.rejects(
    f.wrapped.query("memories", {}),
    failure("transaction_conflict"),
  );
  assert.equal(calls, 3);
  const original = new RuntimeError("revision_conflict", "The record changed.");
  f.base.get = async () => {
    throw original;
  };
  await assert.rejects(f.wrapped.get("record"), (error) => error === original);
  const state = f.wrapped.media!.getSnapshot();
  assert.equal(state.error, null);
  assert.equal(state.stage, null);
  assert.equal(state.accessDenied, false);
  assert.equal(mediaRecoveryPresentation(state), "hidden");
  f.wrapped.dispose();
  f.lifetime.dispose();
});

test("base query/get/summary/aggregate/member errors preserve identity and cached media until actual auth/lifecycle loss", async () => {
  const f = host();
  await f.wrapped.media!.recover();
  await f.wrapped.readImage(wire.ready.asset.assetId);
  assert.equal(f.wrapped.media!.ownsUri("blob:host-owned-image"), true);
  const original = new RuntimeError(
    "read_failed",
    "Records are temporarily unavailable.",
  );
  f.base.query = async () => {
    throw original;
  };
  f.base.get = async () => {
    throw original;
  };
  f.base.summary = async () => {
    throw original;
  };
  f.base.aggregate = async () => {
    throw original;
  };
  f.base.members = async () => {
    throw original;
  };
  for (const read of [
    () => f.wrapped.query("memories", {}),
    () => f.wrapped.get("record"),
    () => f.wrapped.summary("memories", {}, "favorite"),
    () => f.wrapped.aggregate("memories", {}, { metric: "count" }),
    () => f.wrapped.members(),
  ])
    await assert.rejects(read(), (error) => error === original);
  assert.equal(f.removed, 0);
  assert.equal(f.wrapped.media!.getSnapshot().error, null);
  assert.equal(
    mediaRecoveryPresentation(f.wrapped.media!.getSnapshot()),
    "hidden",
  );
  const denied = new RuntimeError("forbidden", "App access was revoked.");
  f.base.query = async () => {
    throw denied;
  };
  await assert.rejects(
    f.wrapped.query("memories", {}),
    (error) => error === denied,
  );
  assert.equal(f.removed, 1);
  assert.equal(f.accessFailures, 1);
  assert.equal(f.wrapped.media!.getSnapshot().accessDenied, true);
  assert.equal(f.wrapped.media!.getSnapshot().error, null);
  assert.equal(f.wrapped.features.has("imageRead"), false);
  f.wrapped.dispose();
  f.lifetime.dispose();
});

test("storage-open failure is an honest local-unavailable state with no retained stage/progress/discard model", async () => {
  const f = host(undefined, true);
  await assert.rejects(f.wrapped.media!.recover());
  const state = f.wrapped.media!.getSnapshot();
  assert.equal(state.initialized, false);
  assert.equal(state.stage, null);
  assert.equal(state.inputBytes, 0);
  assert.equal(mediaRecoveryPresentation(state), "local_unavailable");
  assert.equal(state.error?.includes("PRIVATE_STORAGE"), false);
  assert.equal(f.brokerCalls, 0);
  f.store.fail = false;
  await f.wrapped.media!.recover();
  assert.equal(
    mediaRecoveryPresentation(f.wrapped.media!.getSnapshot()),
    "hidden",
  );
  const fresh = f.wrapped.media!.getSnapshot();
  assert.equal(
    mediaRecoveryPresentation({
      ...fresh,
      error: "An unrelated image read failed",
    }),
    "hidden",
  );
  assert.equal(
    mediaRecoveryPresentation({
      ...fresh,
      stage: "chunks",
      inputBytes: 100,
      uploadedBytes: 0,
    }),
    "retained",
  );
  assert.equal(
    mediaRecoveryPresentation({
      ...fresh,
      stage: "chunks",
      inputBytes: 0,
      uploadedBytes: 0,
    }),
    "hidden",
  );
  assert.equal(
    mediaRecoveryPresentation({
      ...fresh,
      stage: "chunks",
      inputBytes: 100,
      accessDenied: true,
    }),
    "hidden",
  );
  f.wrapped.dispose();
  f.lifetime.dispose();
});

test("only definite known read service409 conflicts retry; malformed responses, unknown transport and mutations never do", async () => {
  const results: ((body: string) => Promise<ExecutionResult>)[] = [
    async () => complete(409, { error: "revision_conflict" }),
    async () => complete(409, { error: { code: "transaction_conflict" } }),
    async () => ({
      status: "processing",
      responseStatusCode: 409,
      responseBody: '{"error":"transaction_conflict"}',
    }),
    async () => ({
      status: "completed",
      responseStatusCode: 200,
      responseBody: "{",
    }),
    async () => complete(200, { error: { code: "transaction_conflict" } }),
    async () => {
      throw Error("Private network detail");
    },
  ];
  for (const execute of results) {
    let calls = 0;
    const sdk = backend(async (body) => {
        calls++;
        return execute(body);
      }),
      adapter = new FunctionRuntimeAdapter(manifest(), (request) =>
        sdk.executeSpec(request),
      );
    await assert.rejects(adapter.query("memories", {}));
    assert.equal(calls, 1);
    adapter.dispose();
  }
  let uncertainCalls = 0;
  const uncertain = new FunctionRuntimeAdapter(manifest(), async () => {
    uncertainCalls++;
    throw new BackendError(
      "Unknown read outcome",
      "transaction_conflict",
      "service",
      true,
      409,
    );
  });
  await assert.rejects(uncertain.query("memories", {}));
  assert.equal(uncertainCalls, 1);
  uncertain.dispose();
  let mutationCalls = 0;
  const sdk = backend(async () => {
      mutationCalls++;
      return complete(409, { error: "transaction_conflict" });
    }),
    adapter = new FunctionRuntimeAdapter(manifest(), (request) =>
      sdk.executeSpec(request),
    );
  await assert.rejects(
    adapter.execute({
      appId: "app",
      versionId: "version",
      operationId: "retained-operation",
      actionId: "addRecord",
      input: { data: { title: "Keep original identity" } },
    }),
    (error) =>
      failure("transaction_conflict")(error) &&
      (error as RuntimeError).uncertain,
  );
  assert.equal(mutationCalls, 1);
  adapter.dispose();
});

test("all known read methods use bounded completed-conflict recovery without changing their actual wire DTO", async () => {
  const reading = fullTemplates.find(
    (template) => template.id === "reading",
  )!.spec;
  for (const op of [
    "spec.getRecord",
    "spec.summary",
    "spec.aggregate",
    "listMembers",
  ]) {
    let calls = 0;
    const sdk = backend(async (body) => {
      assert.equal(JSON.parse(body).op, op);
      if (++calls === 1)
        return complete(409, { error: "transaction_conflict" });
      return complete(
        200,
        op === "spec.getRecord"
          ? {
              versionId: "version",
              record: {
                id: "record",
                collectionId: "books",
                data: { title: "Example", status: "Reading" },
                revision: 1,
                writtenUnderVersionId: "version",
                capacity: null,
                allocated: null,
                claimed: false,
                allowedActions: [],
              },
            }
          : op === "spec.summary"
            ? { versionId: "version", total: 0, groups: { Reading: 0 } }
            : op === "spec.aggregate"
              ? { versionId: "version", total: 0, value: 0, groups: [] }
              : {
                  members: [{ actorId: "owner", role: "owner" }],
                  nextCursor: null,
                },
      );
    });
    const m = manifest();
    m.version = { ...m.version!, spec: reading };
    m.allowedActions = reading.actions.map((action) => action.id);
    const adapter = new FunctionRuntimeAdapter(m, (request) =>
      sdk.executeSpec(request),
    );
    if (op === "spec.getRecord") await adapter.get("record");
    else if (op === "spec.summary")
      await adapter.summary("books", {}, "status");
    else if (op === "spec.aggregate")
      await adapter.aggregate("books", {}, { metric: "count" });
    else await adapter.members();
    assert.equal(calls, 2);
    adapter.dispose();
  }
});

test("dispose and account epoch loss fence retries and late successful reads", async () => {
  const waiting = deferred<ExecutionResult>(),
    started = deferred<void>();
  let calls = 0;
  const sdk = backend(async () => {
    if (++calls === 1) return complete(409, { error: "transaction_conflict" });
    started.resolve();
    return waiting.promise;
  });
  const adapter = new FunctionRuntimeAdapter(manifest(), (request) =>
      sdk.executeSpec(request),
    ),
    pending = adapter.query("memories", {});
  await started.promise;
  adapter.dispose();
  waiting.resolve(complete(200, emptyPage));
  await assert.rejects(pending, failure("disposed"));
  assert.equal(calls, 2);
  let session: AccountSession = { accountId: "owner", epoch: 1, active: true },
    accountCalls = 0;
  const captured = { ...session },
    next = deferred<unknown>();
  const transport = accountTransport({
    expected: captured,
    readSession: () => session,
    alive: () => true,
    onUnauthenticated: () => {},
    execute: async () => {
      accountCalls++;
      return next.promise;
    },
  });
  const fenced = new FunctionRuntimeAdapter(manifest(), transport),
    loading = fenced.query("memories", {});
  session = { accountId: "replacement", epoch: 2, active: true };
  next.resolve(emptyPage);
  await assert.rejects(loading, failure("session_changed"));
  assert.equal(accountCalls, 1);
  fenced.dispose();
  const base = new FunctionRuntimeAdapter(manifest(), async () => emptyPage),
    f = host(base),
    late = deferred<typeof emptyPage>();
  base.query = async () => late.promise;
  const query = f.wrapped.query("memories", {});
  f.wrapped.dispose();
  late.resolve(emptyPage);
  await assert.rejects(query, failure("disposed"));
  f.lifetime.dispose();
});

test("Photo Journal does not request consent while the real device template retains its declared groups", () => {
  assert.deepEqual(requestedDeviceCapabilities(spec), []);
  const deviceSpec = fullTemplates.find(
      (template) => template.id === "phoneToolkit",
    )!.spec,
    groups = requestedDeviceCapabilities(deviceSpec);
  assert.ok(groups.includes("flashlight"));
  assert.ok(groups.includes("device"));
  assert.ok(groups.includes("battery"));
});
