import assert from "node:assert/strict";
import test from "node:test";
import { BackendError } from "../backend/errors";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { PreviewRuntimeAdapter } from "../runtime/preview";
import { resolveLocation } from "../runtime/location";
import { fullTemplates } from "./catalog";
import { FullAppController } from "./FullAppController";
import {
  fullRouteParams,
  isCurrentFullRoute,
  parseFullRoute,
} from "./navigation";

const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const spec = fullTemplates.find(
  (template) => template.id === "photoJournal",
)!.spec;
function fixture() {
  let current: Record<string, unknown> = {
    id: "app",
    workspaceId: "workspace",
    name: spec.name,
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: { editDefinition: true },
    allowedActions: spec.actions.map((action) => action.id),
    controlRevision: 1,
    version: { id: "published_1", number: 1, hash: "version_hash", spec },
    draft: null,
    generation: null,
  };
  let denyRead = false,
    ids = 0;
  const saved = new Map<string, string>(),
    calls: Record<string, unknown>[] = [];
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
      calls.push(request);
      if (request.op === "spec.getApp") {
        if (denyRead)
          throw new BackendError(
            "Access removed",
            "forbidden",
            "service",
            false,
            403,
          );
        return { app: current };
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
        current = {
          ...current,
          draft: {
            revision: Number(request.expectedRevision) + 1,
            baseVersionId: request.expectedVersionId,
            candidateHash: "candidate_hash",
            spec: request.spec,
            publishedVersionId: null,
          },
        };
        return { app: current };
      }
      if (request.op === "spec.getRecord")
        return {
          versionId: "published_1",
          record: {
            id: request.recordId,
            collectionId: "memories",
            data: { title: "An authorized memory" },
            revision: 1,
            writtenUnderVersionId: "published_1",
            capacity: null,
            allocated: null,
            claimed: false,
            allowedActions: [],
          },
        };
      if (request.op === "spec.query")
        return {
          versionId: "published_1",
          records: [],
          total: 0,
          nextCursor: null,
        };
      assert.fail(`Unexpected request ${String(request.op)}`);
    },
  });
  return {
    controller,
    calls,
    saved,
    get ids() {
      return ids;
    },
    set denyRead(value: boolean) {
      denyRead = value;
    },
  };
}

test("a confirmed published copy installs a locked replacement runtime whose omitted entry-page URL is already its visible location", async () => {
  const f = fixture(),
    request = parseFullRoute({ mode: "build" });
  await f.controller.load();
  const initialRuntime = f.controller.runtime!;
  const windows: {
    pending: unknown;
    canLeave: boolean;
    sameTextKey: boolean;
    sameVisibleLocation: boolean;
    madeRequest: boolean;
  }[] = [];
  const stop = f.controller.subscribe(() => {
    const runtime = f.controller.runtime,
      state = f.controller.getSnapshot();
    if (!runtime || runtime === initialRuntime || !state.busy) return;
    const location = runtime.getSnapshot().location,
      canonical = parseFullRoute(
        fullRouteParams(scope.appId, location, "build"),
      ),
      before = f.calls.length;
    const sameVisibleLocation = isCurrentFullRoute(
      request,
      location,
      "build",
      spec.navigation!.entryPageId,
    );
    windows.push({
      pending: state.pending,
      canLeave: f.controller.canLeave,
      sameTextKey: request.key === canonical.key,
      sameVisibleLocation,
      madeRequest: f.calls.length !== before,
    });
  });
  await f.controller.editPublishedVersion();
  stop();
  assert.ok(
    windows.length > 0,
    "Actual ACK→replacement-runtime→busy window must occur",
  );
  for (const window of windows) {
    assert.equal(
      window.pending,
      null,
      "The receipt and local clear are confirmed",
    );
    assert.equal(window.canLeave, false, "Post-save refresh is still busy");
    assert.equal(
      window.sameTextKey,
      false,
      "Original textual guard treats an omitted page as different",
    );
    assert.equal(
      window.sameVisibleLocation,
      true,
      "The already-visible entry alias must not enter the blocked-link warning branch",
    );
    assert.equal(
      window.madeRequest,
      false,
      "Identity comparison sends no request or navigation",
    );
  }
  assert.notEqual(f.controller.runtime, initialRuntime);
  assert.equal(f.controller.getSnapshot().pending, null);
  assert.equal(f.controller.getSnapshot().busy, false);
  assert.equal(f.controller.getSnapshot().error, null);
  assert.deepEqual(f.controller.getSnapshot().candidate, spec);
  assert.equal(
    f.calls.filter((call) => call.op === "spec.saveDraft").length,
    1,
  );
  assert.equal(f.ids, 1);
  assert.equal(f.saved.size, 0);
  f.controller.dispose();
});
test("default-page equivalence never substitutes the current nonentry page, selected record, edit state, mode or invalid identity", () => {
  const request = parseFullRoute({ mode: "build" }),
    entry = spec.navigation!.entryPageId;
  assert.equal(
    isCurrentFullRoute(request, { pageId: entry }, "build", entry),
    true,
  );
  for (const location of [
    { pageId: "galleryPage" },
    { pageId: entry, recordId: "record_1" },
    { pageId: entry, recordId: "record_1", editing: true },
  ])
    assert.equal(isCurrentFullRoute(request, location, "build", entry), false);
  for (const params of [
    { mode: "preview" },
    { mode: "build", page: "galleryPage" },
    { mode: "build", recordId: "record_1" },
    { mode: "build", recordId: "record_1", edit: "true" },
    { mode: "build", page: "../private" },
    { mode: "build", edit: "true" },
  ])
    assert.equal(
      isCurrentFullRoute(
        parseFullRoute(params),
        { pageId: entry },
        "build",
        entry,
      ),
      false,
    );
  assert.equal(
    isCurrentFullRoute(
      parseFullRoute({ mode: "build" }),
      { pageId: "__legacy__" },
      "build",
      "__legacy__",
    ),
    true,
  );
});
test("a different record link remains a fresh manifest plus authorized record lookup and does not allocate or replay a command", async () => {
  const f = fixture(),
    request = parseFullRoute({ mode: "build", recordId: "record_1" });
  await f.controller.load();
  assert.equal(
    isCurrentFullRoute(
      request,
      f.controller.runtime!.getSnapshot().location,
      "build",
      spec.navigation!.entryPageId,
    ),
    false,
  );
  const start = f.calls.length;
  // The existing external-link path retains this order: refresh, then apply authorized identities.
  await f.controller.load();
  assert.equal(
    await f.controller.runtime!.applyLocation(request.location),
    "applied",
  );
  const ops = f.calls.slice(start).map((call) => call.op);
  assert.equal(ops[0], "spec.getApp");
  assert.ok(ops.indexOf("spec.getRecord") > ops.indexOf("spec.getApp"));
  assert.equal(
    f.controller.runtime!.getSnapshot().location.recordId,
    "record_1",
  );
  assert.equal(f.ids, 0);
  assert.equal(f.saved.size, 0);
  f.controller.dispose();
});
test("a fresh link cannot use alias comparison to retain private state after authority is revoked", async () => {
  const f = fixture(),
    request = parseFullRoute({ mode: "build", recordId: "record_1" });
  await f.controller.load();
  assert.equal(
    isCurrentFullRoute(
      request,
      f.controller.runtime!.getSnapshot().location,
      "build",
      spec.navigation!.entryPageId,
    ),
    false,
  );
  const start = f.calls.length;
  f.denyRead = true;
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().app, null);
  assert.equal(f.controller.runtime, null);
  assert.equal(
    f.calls.slice(start).filter((call) => call.op === "spec.getRecord").length,
    0,
  );
  assert.equal(f.ids, 0);
  f.controller.dispose();
});

test("an omitted record page must still resolve its authorized details or form target even when the same record is selected on the entry page", async () => {
  const adapter = new PreviewRuntimeAdapter(spec),
    record = (await adapter.query("memories", { limit: 1 })).records[0];
  try {
    assert.ok(record);
    for (const editing of [false, true]) {
      const request = parseFullRoute({
        mode: "build",
        recordId: record.id,
        ...(editing ? { edit: "true" } : {}),
      });
      const current = {
        pageId: spec.navigation!.entryPageId,
        recordId: record.id,
        ...(editing ? { editing: true } : {}),
      };
      const target = await resolveLocation(adapter, request.location);
      assert.equal(target.pageId, editing ? "formPage" : "detailPage");
      assert.equal(target.recordId, record.id);
      assert.notDeepEqual(target, current);
      assert.equal(
        isCurrentFullRoute(
          request,
          current,
          "build",
          spec.navigation!.entryPageId,
        ),
        false,
        "An omitted record page is not an entry-page alias",
      );
      assert.equal(
        isCurrentFullRoute(
          parseFullRoute(fullRouteParams(scope.appId, target, "build")),
          target,
          "build",
          spec.navigation!.entryPageId,
        ),
        true,
        "Exact canonical page/record/edit identities keep the existing no-op policy",
      );
    }
  } finally {
    adapter.dispose();
  }
});
test("the preexisting canonical legacy-record match is preserved when its page is intentionally omitted", async () => {
  const legacy = fullTemplates.find(
      (template) => template.id === "reading",
    )!.spec,
    adapter = new PreviewRuntimeAdapter(legacy);
  try {
    assert.equal(legacy.navigation, undefined);
    const record = (await adapter.query(legacy.collections[0].id, { limit: 1 }))
        .records[0],
      current = { pageId: "__legacy__", recordId: record.id },
      request = parseFullRoute(fullRouteParams(scope.appId, current, "build"));
    assert.equal(request.location.pageId, undefined);
    assert.deepEqual(await resolveLocation(adapter, request.location), current);
    assert.equal(
      isCurrentFullRoute(request, current, "build", "__legacy__"),
      true,
    );
  } finally {
    adapter.dispose();
  }
});
