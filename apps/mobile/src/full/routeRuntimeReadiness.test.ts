import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { resolveLocation } from "../runtime/location";
import type { RuntimeManifest } from "../runtime/functionAdapter";
import { FullAppController } from "./FullAppController";
import { fullTemplates } from "./catalog";
import { parseFullRoute } from "./navigation";
import { waitForRouteRuntime } from "./routeRuntimeReadiness";

const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const spec = fullTemplates.find((template) => template.id === "planner")!.spec;
function app() {
  return {
    id: "app",
    workspaceId: "workspace",
    name: spec.name,
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: { editDefinition: true },
    controlRevision: 1,
    allowedActions: spec.actions.map((action) => action.id),
    version: {
      id: "version_1",
      number: 1,
      hash: "version_hash",
      spec,
    } as RuntimeManifest["version"],
    draft: null as unknown,
    generation: null,
  };
}
function fixture() {
  let wire = app(),
    denied = false,
    ids = 0;
  const saved = new Map<string, string>(),
    requests: Record<string, unknown>[] = [];
  const host = hostStores(new HostLifetime(scope), {
    async read(key) {
      return saved.get(key) ?? null;
    },
    async change(key, update) {
      const next = update(saved.get(key) ?? null);
      if (next === null) saved.delete(key);
      else saved.set(key, next);
    },
  });
  const controller = new FullAppController({
    scope,
    host,
    newId: () => `operation_${++ids}`,
    transport: async (request) => {
      requests.push(request);
      if (request.op === "spec.getApp") {
        if (denied)
          throw new BackendError(
            "Current access removed",
            "forbidden",
            "service",
            false,
            403,
          );
        return { app: wire };
      }
      if (request.op === "spec.capabilities")
        return {
          apiVersion: 1,
          formatVersions: [1],
          generation: false,
          guidance: false,
          effects: [],
          privateMedia: false,
        };
      if (request.op === "spec.saveDraft") {
        wire = {
          ...wire,
          draft: {
            revision: Number(request.expectedRevision) + 1,
            baseVersionId: request.expectedVersionId,
            candidateHash: "candidate_hash",
            spec: request.spec,
            publishedVersionId: null,
          },
        };
        return { app: wire };
      }
      if (request.op === "spec.getRecord")
        return {
          versionId: "version_1",
          record: {
            id: request.recordId,
            collectionId: spec.collections[0].id,
            data: { title: "Authorized item", status: "Open" },
            revision: 1,
            writtenUnderVersionId: "version_1",
            capacity: null,
            allocated: null,
            claimed: false,
            allowedActions: [],
          },
        };
      assert.fail(`Unexpected request ${String(request.op)}`);
    },
  });
  return {
    controller,
    requests,
    saved,
    get ids() {
      return ids;
    },
    get wire() {
      return wire;
    },
    set wire(value: ReturnType<typeof app>) {
      wire = value;
    },
    set denied(value: boolean) {
      denied = value;
    },
  };
}

test("confirmed save ACK leaves published metadata during its runtime-null preparation window, so a canonical page request must wait without rejection", async () => {
  const f = fixture();
  await f.controller.load();
  const first = f.controller.runtime!;
  const request = parseFullRoute({
    mode: "build",
    page: spec.navigation!.entryPageId,
  });
  const observations: {
    hasPublishedVersion: boolean;
    wait: boolean;
    pending: unknown;
    requestKey: string;
  }[] = [];
  const stop = f.controller.subscribe(() => {
    const state = f.controller.getSnapshot();
    if (f.controller.runtime || !state.app || !state.busy) return;
    observations.push({
      hasPublishedVersion: !!state.app.version,
      wait: waitForRouteRuntime(state.app),
      pending: state.pending,
      requestKey: request.key,
    });
  });
  await f.controller.editPublishedVersion();
  stop();
  assert.ok(
    observations.length > 0,
    "Actual ACK→runtime-null/published metadata window must occur",
  );
  for (const observed of observations) {
    assert.equal(observed.hasPublishedVersion, true);
    assert.equal(
      observed.pending,
      null,
      "The save and local journal clear are confirmed",
    );
    assert.equal(
      observed.wait,
      true,
      "Runtime absence must not synthesize an unpublished-page warning",
    );
    assert.equal(
      observed.requestKey,
      request.key,
      "The original request remains unchanged while waiting",
    );
  }
  assert.notEqual(f.controller.runtime, first);
  assert.ok(f.controller.runtime);
  assert.deepEqual(f.controller.getSnapshot().candidate, spec);
  assert.equal(f.controller.getSnapshot().error, null);
  assert.equal(f.controller.getSnapshot().pending, null);
  assert.equal(f.saved.size, 0);
  assert.equal(
    f.requests.filter((row) => row.op === "spec.saveDraft").length,
    1,
  );
  assert.equal(f.ids, 1);
  f.controller.dispose();
});
test("a true unpublished app still takes the existing unpublished-link path while absent or access-denied metadata only waits", async () => {
  const f = fixture();
  assert.equal(waitForRouteRuntime(f.controller.getSnapshot().app), true);
  f.wire = {
    ...app(),
    version: null,
  };
  await f.controller.load();
  assert.equal(f.controller.runtime, null);
  assert.equal(f.controller.getSnapshot().app?.version, null);
  assert.equal(waitForRouteRuntime(f.controller.getSnapshot().app), false);
  assert.equal(f.ids, 0);
  assert.equal(f.saved.size, 0);
  f.controller.dispose();
  const denied = fixture();
  await denied.controller.load();
  denied.denied = true;
  await denied.controller.load();
  assert.equal(denied.controller.runtime, null);
  assert.equal(denied.controller.getSnapshot().app, null);
  assert.ok(denied.controller.getSnapshot().error);
  assert.equal(waitForRouteRuntime(denied.controller.getSnapshot().app), true);
  assert.equal(
    denied.requests.filter((row) => row.op === "spec.getRecord").length,
    0,
  );
  denied.controller.dispose();
});
test("published viewer metadata also waits during replacement without gaining builder authority or allocating any command", async () => {
  const f = fixture();
  await f.controller.load();
  f.wire = {
    ...app(),
    role: "viewer",
    capabilities: { editDefinition: false },
  };
  const observations: boolean[] = [];
  const stop = f.controller.subscribe(() => {
    const state = f.controller.getSnapshot();
    if (!f.controller.runtime && state.app?.role === "viewer")
      observations.push(waitForRouteRuntime(state.app));
  });
  await f.controller.load();
  stop();
  assert.ok(observations.length > 0);
  assert.ok(observations.every(Boolean));
  assert.equal(f.controller.canBuild, false);
  assert.equal(f.controller.previewSpec, null);
  assert.equal(f.controller.runtime?.adapter.role, "viewer");
  assert.equal(f.ids, 0);
  f.controller.dispose();
});
test("runtime readiness does not authorize a different page or record: fresh manifest and authorized resolver remain required", async () => {
  const f = fixture();
  await f.controller.load();
  const request = parseFullRoute({ mode: "build", recordId: "record_1" }),
    start = f.requests.length;
  await f.controller.load();
  const runtime = f.controller.runtime!;
  const target = await resolveLocation(runtime.adapter, request.location);
  assert.equal(target.recordId, "record_1");
  assert.notEqual(target.pageId, undefined);
  const calls = f.requests.slice(start).map((row) => row.op);
  assert.equal(calls[0], "spec.getApp");
  assert.ok(calls.indexOf("spec.getRecord") > calls.indexOf("spec.getApp"));
  await assert.rejects(
    resolveLocation(runtime.adapter, { pageId: "not_a_page" }),
    /unavailable/,
  );
  assert.equal(f.ids, 0);
  assert.equal(f.saved.size, 0);
  f.controller.dispose();
});
