import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { fullTemplates } from "../full/catalog";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { FunctionRuntimeAdapter } from "../runtime/functionAdapter";
import { GuardedReadCoordinator } from "../runtime/guardedReads";
import { RuntimeError } from "../runtime/errors";
import type { RuntimeTransport } from "../runtime/types";
import { PrivateMediaController } from "./controller";
import { MediaRecovery } from "./recovery";
import { encode64 } from "./codec";
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const bytes = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10]);
const sha = (value: Uint8Array) =>
  createHash("sha256").update(value).digest("hex");
const spec = fullTemplates.find((t) => t.id === "photoJournal")!.spec;
const manifest = {
  id: "app",
  workspaceId: "ws",
  name: spec.name,
  engine: "appspec.v1" as const,
  role: "owner" as const,
  archived: false,
  capabilities: { editDefinition: true },
  controlRevision: 1,
  allowedActions: spec.actions.map((a) => a.id),
  draft: null,
  version: { id: "version_1", number: 1, hash: "hash", spec },
};
function deferred<T = unknown>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((yes) => {
    resolve = yes;
  });
  return { promise, resolve };
}
const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));
function response(r: Record<string, unknown>) {
  if (r.op === "spec.media.status")
    return {
      asset: {
        assetId: r.assetId,
        status: "ready",
        contentType: "image/png",
        byteLength: bytes.length,
        width: 1,
        height: 1,
        sha256: sha(bytes),
      },
    };
  if (r.op === "spec.media.read")
    return {
      assetId: r.assetId,
      variant: r.variant,
      offset: 0,
      nextOffset: null,
      byteLength: bytes.length,
      contentType: "image/png",
      sha256: sha(bytes),
      chunkSha256: sha(bytes),
      dataBase64: encode64(bytes),
      width: 1,
      height: 1,
      cacheControl: "private, no-store",
    };
  return {};
}
function fixture(transport: RuntimeTransport, requestTimeoutMs = 1000) {
  const lifetime = new HostLifetime(scope),
    values = new Map<string, string>();
  let resources = 0,
    serial = 0,
    current = true;
  const host = hostStores(lifetime, {
    async read(k) {
      return values.get(k) ?? null;
    },
    async change(k, fn) {
      const v = fn(values.get(k) ?? null);
      if (v === null) values.delete(k);
      else values.set(k, v);
    },
  });
  const media = new PrivateMediaController(
    new FunctionRuntimeAdapter(manifest, transport),
    transport,
    lifetime,
    {
      privateMedia: true,
      recovery: new MediaRecovery(host.storage),
      newId: () => {
        throw new Error("Image reads cannot allocate write IDs");
      },
      requestTimeoutMs,
      readConcurrency: 2,
      isCurrent: () => current,
      ports: {
        sha256: async (b) => sha(b),
        pick: async () => null,
        image: async () => {
          resources++;
          return {
            uri: `blob:image_${++serial}`,
            dispose() {
              resources--;
            },
          };
        },
        dispose() {},
      },
    },
  );
  return {
    media,
    lifetime,
    get resources() {
      return resources;
    },
    closeScope() {
      current = false;
    },
    dispose() {
      media.dispose();
      lifetime.dispose();
    },
  };
}

test("two independent image status/chunk pipelines and a query share FIFO without changing cache authorization", async () => {
  const lane = new GuardedReadCoordinator(),
    calls: Record<string, unknown>[] = [];
  let active = 0,
    maximum = 0;
  const transport = lane.transport(async (r) => {
    calls.push(r);
    maximum = Math.max(maximum, ++active);
    try {
      await tick();
      return response(r);
    } finally {
      active--;
    }
  });
  const f = fixture(transport);
  const [one, two] = await Promise.all([
    f.media.read("one"),
    f.media.read("two"),
    transport({ op: "spec.query", appId: "app" }),
  ]);
  assert.equal(maximum, 1);
  assert.equal(f.resources, 2);
  assert.notEqual(one.uri, two.uri);
  assert.equal(calls.filter((r) => r.op === "spec.media.status").length, 2);
  assert.equal(calls.filter((r) => r.op === "spec.media.read").length, 2);
  await f.media.read("one");
  assert.equal(calls.filter((r) => r.op === "spec.media.status").length, 3);
  assert.equal(calls.filter((r) => r.op === "spec.media.read").length, 2);
  f.dispose();
  assert.equal(f.resources, 0);
  lane.dispose();
});

test("timed-out, disposed and replaced media scopes cancel queued status requests before SDK dispatch", async () => {
  for (const action of ["timeout", "dispose", "scope"] as const) {
    const lane = new GuardedReadCoordinator(),
      gate = deferred(),
      calls: string[] = [];
    const transport = lane.transport(async (r) => {
      calls.push(String(r.op));
      if (r.op === "spec.getApp") return gate.promise;
      return response(r);
    });
    const f = fixture(transport, action === "timeout" ? 10 : 1000);
    const block = transport({ op: "spec.getApp" });
    const read = f.media.read("private_asset");
    const rejected = assert.rejects(
      read,
      (e: unknown) =>
        e instanceof RuntimeError &&
        [
          "media_request_timeout",
          "disposed",
          "media_scope_changed",
          "superseded_read",
        ].includes(e.code),
    );
    await tick();
    if (action === "dispose") f.media.dispose();
    if (action === "scope") f.closeScope();
    if (action === "timeout") await rejected;
    gate.resolve({});
    await Promise.all([block, rejected]);
    await tick();
    assert.deepEqual(calls, ["spec.getApp"]);
    assert.equal(f.resources, 0);
    f.dispose();
    lane.dispose();
  }
});

test("upper image timeout never frees the shared lane while its unabortable SDK request remains inflight", async () => {
  const lane = new GuardedReadCoordinator(),
    gate = deferred(),
    calls: string[] = [];
  const transport = lane.transport(async (r) => {
    calls.push(String(r.op));
    if (r.op === "spec.media.status") {
      await gate.promise;
      return response(r);
    }
    return {};
  });
  const f = fixture(transport, 10);
  const read = assert.rejects(
    f.media.read("private_asset"),
    (e: unknown) =>
      e instanceof RuntimeError && e.code === "media_request_timeout",
  );
  await tick();
  const query = transport({ op: "spec.query", appId: "app" });
  await read;
  assert.deepEqual(calls, ["spec.media.status"]);
  gate.resolve({});
  await query;
  await tick();
  assert.deepEqual(calls, ["spec.media.status", "spec.query"]);
  assert.equal(f.resources, 0);
  f.dispose();
  lane.dispose();
});

test("every media mutation and provider operation bypasses a blocked read exactly once", async () => {
  const lane = new GuardedReadCoordinator(),
    gate = deferred(),
    calls: string[] = [];
  const transport = lane.transport(async (r) => {
    calls.push(String(r.op));
    if (r.op === "spec.media.read") return gate.promise;
    return {};
  });
  const read = transport({
    op: "spec.media.read",
    appId: "app",
    assetId: "one",
    variant: "thumbnail",
    offset: 0,
  });
  const ops = [
    "spec.media.begin",
    "spec.media.chunk",
    "spec.media.complete",
    "spec.media.delete",
    "spec.execute",
    "spec.saveDraft",
    "spec.guidance",
    "spec.generate",
    "spec.unknown",
  ];
  for (const op of ops) await transport({ op });
  assert.deepEqual(calls, ["spec.media.read", ...ops]);
  gate.resolve({});
  await read;
  lane.dispose();
});
