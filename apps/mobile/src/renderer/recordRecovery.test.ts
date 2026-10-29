import assert from "node:assert/strict";
import { createRequire, registerHooks } from "node:module";
import test from "node:test";
import { createElement, type ReactNode } from "react";
import { BackendError } from "../backend/errors";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { FullAppController } from "../full/FullAppController";
import {
  NavigationEpoch,
  guardHostNavigation,
  parseFullRoute,
} from "../full/navigation";
import { decodeAppSpec } from "../spec/decode";
import { RuntimeError } from "../runtime/errors";
import type { RuntimeCommand } from "../runtime/types";
import {
  performRecordRecovery,
  recordRecoveryOutsideLive,
  recordRecoveryPresentation,
  RecordRecoveryGate,
} from "./recordRecovery";

const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const spec = decodeAppSpec({
  formatVersion: 1,
  name: "Retained notes",
  theme: "teal",
  icon: "book",
  requires: ["collections.v1", "views.list.v1", "records.patch.v1"],
  collections: [
    {
      id: "items",
      label: "Items",
      fields: [{ id: "title", label: "Title", type: "text", required: true }],
      behaviors: [],
    },
  ],
  views: [
    {
      id: "itemsList",
      type: "list",
      label: "Items",
      collectionId: "items",
      titleFieldId: "title",
      actionIds: ["editItem"],
    },
  ],
  actions: [
    {
      id: "editItem",
      label: "Edit item",
      collectionId: "items",
      capability: "records.patch.v1",
    },
  ],
  policyPresetRequest: "personalTracker.v1",
  automationRequests: [],
});
const original: RuntimeCommand = {
  appId: "app",
  versionId: "version_1",
  operationId: "original_operation",
  actionId: "editItem",
  targetRecordId: "original_record",
  expectedRecordRevision: 7,
  input: { data: { title: "Private retained input" } },
};
function app() {
  return {
    id: "app",
    workspaceId: "workspace",
    name: spec.name,
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: { editDefinition: true },
    allowedActions: ["editItem"],
    controlRevision: 2,
    version: { id: "version_2", number: 2, hash: "current_hash", spec },
    draft: null,
    generation: null,
  };
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((yes) => {
    resolve = yes;
  });
  return { promise, resolve };
}
function fixture(saved = new Map<string, string>()) {
  const requests: Record<string, unknown>[] = [];
  let ids = 0,
    clearFails = false;
  let execute: (
    request: Record<string, unknown>,
  ) => Promise<unknown> = async () => ({
    outcome: {
      recordId: "original_record",
      revision: 8,
      message: "Saved original change",
    },
  });
  const host = hostStores(new HostLifetime(scope), {
    async read(key) {
      return saved.get(key) ?? null;
    },
    async change(key, update) {
      const next = update(saved.get(key) ?? null);
      if (clearFails && key === "command" && next === null)
        throw new Error("Local storage unavailable");
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
      if (request.op === "spec.getApp") return { app: app() };
      if (request.op === "spec.capabilities")
        return {
          apiVersion: 1,
          formatVersions: [1],
          generation: false,
          guidance: false,
          effects: [],
          privateMedia: false,
        };
      if (request.op === "spec.execute") return execute(request);
      if (request.op === "spec.query")
        return {
          versionId: request.versionId,
          records: [],
          total: 0,
          nextCursor: null,
        };
      assert.fail(`Unexpected request ${String(request.op)}`);
    },
  });
  return {
    controller,
    host,
    saved,
    requests,
    set execute(value: typeof execute) {
      execute = value;
    },
    set clearFails(value: boolean) {
      clearFails = value;
    },
    get ids() {
      return ids;
    },
    executions: () => requests.filter((r) => r.op === "spec.execute"),
  };
}
async function reopened() {
  const first = fixture();
  await first.host.commands.save(original);
  first.controller.dispose();
  const next = fixture(first.saved);
  await next.controller.load();
  await next.controller.runtime!.recover();
  return next;
}
async function navigate(f: ReturnType<typeof fixture>) {
  let actions = 0,
    blocked = 0,
    prompts = 0;
  await guardHostNavigation({
    source: f.controller,
    epoch: new NavigationEpoch(),
    focused: () => true,
    action: () => {
      actions++;
    },
    blocked: () => {
      blocked++;
    },
    prompt: () => {
      prompts++;
    },
  });
  return { actions, blocked, prompts };
}

// Server rendering exercises the actual FullAppScreen branch. Router focus/back hooks and
// native safe-area plumbing are inert test boundaries; this is not browser navigation proof.
const routerUrl = "tinkerloom-test:record-router",
  safeAreaUrl = "tinkerloom-test:record-safe-area";
const hooks = registerHooks({
  resolve(specifier, context, next) {
    if (specifier === "expo-router")
      return { url: routerUrl, shortCircuit: true };
    if (specifier === "react-native-safe-area-context")
      return { url: safeAreaUrl, shortCircuit: true };
    return next(
      specifier === "react-native" ? "react-native-web" : specifier,
      context.parentURL?.startsWith("tinkerloom-test:")
        ? { ...context, parentURL: import.meta.url }
        : context,
    );
  },
  load(url, context, next) {
    if (url === routerUrl)
      return {
        format: "module",
        shortCircuit: true,
        source:
          "export function useFocusEffect(){} export function useIsFocused(){return true;} export function usePreventRemove(){return ()=>{};}",
      };
    if (url === safeAreaUrl)
      return {
        format: "module",
        shortCircuit: true,
        source: 'export {View as SafeAreaView} from "react-native-web";',
      };
    return next(url, context);
  },
});
const components = Promise.all([
  import("./RecordRecoveryPanel"),
  import("../full/FullAppScreen"),
]);
const { renderToStaticMarkup } = createRequire(import.meta.url)(
  "react-dom/server",
) as { renderToStaticMarkup(element: ReactNode): string };
test.after(() => hooks.deregister());
async function renderHost(
  f: ReturnType<typeof fixture>,
  mode: "live" | "build" | "preview",
  owned = true,
) {
  const [, { FullAppScreen }] = await components;
  return renderToStaticMarkup(
    createElement(FullAppScreen, {
      controller: f.controller,
      onBack() {},
      initialMode: mode,
      route: parseFullRoute({ mode }),
      protectedLocationOwned: owned,
    }),
  );
}
async function renderPanel(f: ReturnType<typeof fixture>) {
  const [{ RecordRecoveryPanel }] = await components;
  return f.controller.runtime
    ? renderToStaticMarkup(
        createElement(RecordRecoveryPanel, {
          controller: f.controller.runtime,
        }),
      )
    : "";
}

test("a reopened Build or Preview route exposes exactly one original record retry while restoration makes no write", async () => {
  const f = await reopened();
  assert.equal(f.executions().length, 0);
  assert.equal(f.ids, 0);
  assert.deepEqual(
    f.controller.runtime!.getSnapshot().pending?.command,
    original,
  );
  assert.deepEqual(await navigate(f), { actions: 0, blocked: 1, prompts: 0 });
  for (const mode of ["build", "preview", "live"] as const) {
    const html = await renderHost(f, mode);
    assert.equal(
      (html.match(/aria-label="Retry original record request"/g) ?? []).length,
      1,
    );
    assert.match(html, /may apply the original change/);
    assert.doesNotMatch(html, /Private retained input/);
  }
  assert.equal(
    (
      (await renderHost(f, "build", false)).match(
        /aria-label="Retry original record request"/g,
      ) ?? []
    ).length,
    1,
  );
  assert.equal(f.executions().length, 0);
  assert.equal(f.ids, 0);
  f.controller.dispose();
});
test("explicit retry uses the exact retained version, record revision, operation and values even under a newer publication", async () => {
  const f = await reopened(),
    runtime = f.controller.runtime!;
  await performRecordRecovery(runtime, original.operationId, "retry");
  assert.deepEqual(f.executions(), [{ op: "spec.execute", ...original }]);
  assert.equal(f.ids, 0);
  assert.equal(await f.host.commands.read(), null);
  assert.equal(runtime.getSnapshot().pending, null);
  assert.equal(await renderPanel(f), "");
  assert.deepEqual(await navigate(f), { actions: 1, blocked: 0, prompts: 0 });
  f.controller.dispose();
});
test("a lost retry response remains uncertain, cannot be acknowledged and never allocates or auto-replays another operation", async () => {
  const f = await reopened(),
    runtime = f.controller.runtime!;
  f.execute = async () => {
    throw new BackendError("Response lost", "network_error", "transport", true);
  };
  await performRecordRecovery(runtime, original.operationId, "retry");
  assert.equal(runtime.getSnapshot().pending?.status, "uncertain");
  assert.deepEqual(await f.host.commands.read(), original);
  assert.equal(
    await performRecordRecovery(runtime, original.operationId, "acknowledge"),
    false,
  );
  const html = await renderPanel(f);
  assert.match(html, /Retry original record request/);
  assert.doesNotMatch(html, /Acknowledge record failure/);
  assert.equal(f.executions().length, 1);
  assert.equal(f.ids, 0);
  await Promise.resolve();
  assert.equal(f.executions().length, 1);
  f.controller.dispose();
});
test("a definite rejection offers acknowledgment only and clearing its entry preserves the existing unsaved-form navigation prompt", async () => {
  const f = await reopened(),
    runtime = f.controller.runtime!;
  f.execute = async () => {
    throw new BackendError(
      "The original record revision changed",
      "revision_conflict",
      "service",
      false,
      409,
    );
  };
  await performRecordRecovery(runtime, original.operationId, "retry");
  assert.equal(runtime.getSnapshot().pending?.status, "failed");
  assert.deepEqual(await f.host.commands.read(), original);
  assert.equal(
    await performRecordRecovery(runtime, original.operationId, "retry"),
    false,
  );
  const html = await renderHost(f, "build");
  assert.equal(
    (html.match(/aria-label="Acknowledge record failure"/g) ?? []).length,
    1,
  );
  assert.doesNotMatch(html, /aria-label="Retry original record request"/);
  f.clearFails = true;
  await performRecordRecovery(runtime, original.operationId, "acknowledge");
  assert.equal(runtime.getSnapshot().pending?.status, "failed");
  assert.deepEqual(await f.host.commands.read(), original);
  assert.match(await renderPanel(f), /recovery entry could not be cleared/);
  f.clearFails = false;
  await performRecordRecovery(runtime, original.operationId, "acknowledge");
  assert.equal(await f.host.commands.read(), null);
  assert.equal(runtime.getSnapshot().pending, null);
  assert.equal(f.executions().length, 1);
  assert.deepEqual(await navigate(f), { actions: 0, blocked: 0, prompts: 1 });
  runtime.setDirty(false);
  assert.deepEqual(await navigate(f), { actions: 1, blocked: 0, prompts: 0 });
  f.controller.dispose();
});
test("a receipt whose local clear fails remains an exact uncertain command with an honest retry panel", async () => {
  const f = await reopened(),
    runtime = f.controller.runtime!;
  f.clearFails = true;
  await performRecordRecovery(runtime, original.operationId, "retry");
  assert.equal(runtime.getSnapshot().pending?.status, "uncertain");
  assert.deepEqual(await f.host.commands.read(), original);
  assert.match(await renderPanel(f), /recovery entry could not be cleared/);
  f.clearFails = false;
  await performRecordRecovery(runtime, original.operationId, "retry");
  assert.deepEqual(f.executions(), [
    { op: "spec.execute", ...original },
    { op: "spec.execute", ...original },
  ]);
  assert.equal(runtime.getSnapshot().pending, null);
  f.controller.dispose();
});
test("current access denial clears the panel and private host state while retaining account-scoped recovery", async () => {
  const f = await reopened(),
    runtime = f.controller.runtime!;
  f.execute = async () => {
    throw new BackendError(
      "Access removed",
      "forbidden",
      "service",
      false,
      403,
    );
  };
  await performRecordRecovery(runtime, original.operationId, "retry");
  assert.equal(f.controller.getSnapshot().app, null);
  assert.equal(f.controller.runtime, null);
  assert.equal(recordRecoveryPresentation(runtime.getSnapshot()), null);
  assert.equal(await renderPanel(f), "");
  assert.deepEqual(await f.host.commands.read(), original);
  assert.equal(
    await performRecordRecovery(runtime, original.operationId, "retry"),
    false,
  );
  assert.equal(f.executions().length, 1);
  f.controller.dispose();
});
test("account disposal fences a late receipt and leaves the original command for its own account scope", async () => {
  const f = await reopened(),
    runtime = f.controller.runtime!,
    gate = deferred<unknown>();
  f.execute = () => gate.promise;
  const retry = performRecordRecovery(runtime, original.operationId, "retry");
  assert.equal(runtime.getSnapshot().pending?.status, "sending");
  const html = await renderPanel(f);
  assert.match(html, /Record request in progress/);
  assert.doesNotMatch(html, /aria-label="Retry original record request"/);
  f.controller.dispose();
  gate.resolve({
    outcome: { recordId: "original_record", revision: 8, message: "Saved" },
  });
  await retry;
  assert.equal(recordRecoveryPresentation(runtime.getSnapshot()), null);
  const fresh = fixture(f.saved);
  assert.deepEqual(await fresh.host.commands.read(), original);
  assert.equal(f.ids, 0);
  fresh.controller.dispose();
});
test("stale UI callbacks cannot retry a replacement command or acknowledge an uncertain outcome", async () => {
  const f = await reopened(),
    runtime = f.controller.runtime!;
  await performRecordRecovery(runtime, original.operationId, "retry");
  f.execute = async () => {
    throw new Error("Lost new response");
  };
  await runtime.execute(
    "editItem",
    { data: { title: "A separate explicit user edit" } },
    {
      id: "new_record",
      collectionId: "items",
      data: { title: "Old title" },
      revision: 2,
      writtenUnderVersionId: "version_2",
      capacity: null,
      allocated: null,
      claimed: false,
      allowedActions: ["editItem"],
    },
  );
  const replacement = runtime.getSnapshot().pending!.command;
  assert.notEqual(replacement.operationId, original.operationId);
  const requests = f.executions().length;
  assert.equal(
    await performRecordRecovery(runtime, original.operationId, "retry"),
    false,
  );
  assert.equal(
    await performRecordRecovery(
      runtime,
      replacement.operationId,
      "acknowledge",
    ),
    false,
  );
  assert.equal(f.executions().length, requests);
  assert.deepEqual(await f.host.commands.read(), replacement);
  f.controller.dispose();
});
test("the host owns recovery outside Live and the runtime owns it when its original app surface is visible", () => {
  for (const mode of ["live", "build", "preview"] as const) {
    assert.equal(recordRecoveryOutsideLive(mode, true, true), mode !== "live");
    assert.equal(recordRecoveryOutsideLive(mode, false, true), false);
    assert.equal(recordRecoveryOutsideLive(mode, true, false), true);
  }
  assert.equal(
    recordRecoveryPresentation({
      pending: null,
      accessDenied: false,
      error: null,
    }),
    null,
  );
  assert.equal(
    recordRecoveryPresentation({
      pending: { command: original, status: "uncertain" },
      accessDenied: true,
      error: new RuntimeError("forbidden", "Denied"),
    }),
    null,
  );
});

test("recovery attachment A→B→A becomes available after the original uncertain retry settles without auto replay", async () => {
  const a = await reopened(),
    b = await reopened(),
    runtime = a.controller.runtime!,
    other = b.controller.runtime!,
    gate = new RecordRecoveryGate(),
    response = deferred<void>();
  a.execute = async () => {
    await response.promise;
    throw new BackendError("Response lost", "network_error", "transport", true);
  };
  const detachA = gate.attach(runtime),
    originalToken = gate.getSnapshot().token!;
  const oldRun = gate.run(originalToken, () =>
    performRecordRecovery(runtime, original.operationId, "retry"),
  );
  assert.equal(gate.getSnapshot().busy, true);
  assert.equal(a.executions().length, 1);
  assert.equal(
    await gate.run(originalToken, async () => assert.fail("Duplicate click")),
    false,
  );
  detachA();
  const detachB = gate.attach(other);
  assert.equal(gate.getSnapshot().owner, other);
  assert.equal(gate.getSnapshot().busy, false);
  detachB();
  const detachReturnedA = gate.attach(runtime),
    returnedToken = gate.getSnapshot().token!;
  assert.notEqual(returnedToken, originalToken);
  assert.equal(gate.getSnapshot().busy, false);
  assert.equal(
    await gate.run(originalToken, async () => assert.fail("Stale button")),
    false,
  );
  assert.equal(a.executions().length, 1);
  assert.equal(b.executions().length, 0);
  response.resolve();
  await oldRun;
  assert.equal(runtime.getSnapshot().pending?.status, "uncertain");
  assert.equal(gate.getSnapshot().owner, runtime);
  assert.equal(gate.getSnapshot().busy, false);
  assert.equal(a.executions().length, 1);
  a.execute = async () => ({
    outcome: { recordId: "original_record", revision: 8, message: "Saved" },
  });
  assert.equal(
    await gate.run(returnedToken, () =>
      performRecordRecovery(runtime, original.operationId, "retry"),
    ),
    true,
  );
  assert.deepEqual(a.executions(), [
    { op: "spec.execute", ...original },
    { op: "spec.execute", ...original },
  ]);
  assert.equal(a.ids, 0);
  assert.equal(await a.host.commands.read(), null);
  detachReturnedA();
  a.controller.dispose();
  b.controller.dispose();
});
test("an old recovery completion cannot unlock a new action on reattached A; cleanup releases its owner and subscriptions", async () => {
  const a = await reopened(),
    b = await reopened(),
    runtime = a.controller.runtime!,
    gate = new RecordRecoveryGate(),
    oldFinished = deferred<void>(),
    oldCompletion = deferred<void>(),
    newResponse = deferred<unknown>();
  let notifications = 0;
  const unsubscribe = gate.subscribe(() => {
    notifications++;
  });
  a.execute = async () => {
    throw new Error("Response lost");
  };
  const detachOldA = gate.attach(runtime),
    oldToken = gate.getSnapshot().token!;
  const oldRun = gate.run(oldToken, async () => {
    await performRecordRecovery(runtime, original.operationId, "retry");
    oldFinished.resolve();
    await oldCompletion.promise;
  });
  await oldFinished.promise;
  assert.equal(runtime.getSnapshot().pending?.status, "uncertain");
  detachOldA();
  const detachB = gate.attach(b.controller.runtime!);
  detachB();
  const detachNewA = gate.attach(runtime),
    newToken = gate.getSnapshot().token!;
  a.execute = () => newResponse.promise;
  const newRun = gate.run(newToken, () =>
    performRecordRecovery(runtime, original.operationId, "retry"),
  );
  assert.equal(gate.getSnapshot().busy, true);
  detachOldA();
  detachB();
  assert.equal(gate.getSnapshot().token, newToken);
  oldCompletion.resolve();
  await oldRun;
  assert.equal(gate.getSnapshot().busy, true);
  assert.equal(
    await gate.run(newToken, async () =>
      assert.fail("New run is still pending"),
    ),
    false,
  );
  assert.equal(a.executions().length, 2);
  detachNewA();
  assert.deepEqual(gate.getSnapshot(), {
    owner: null,
    token: null,
    busy: false,
  });
  unsubscribe();
  const beforeLateCompletion = notifications;
  a.controller.dispose();
  newResponse.resolve({
    outcome: { recordId: "original_record", revision: 8, message: "Saved" },
  });
  await newRun;
  assert.equal(notifications, beforeLateCompletion);
  assert.deepEqual(gate.getSnapshot(), {
    owner: null,
    token: null,
    busy: false,
  });
  const nextAccountVisit = fixture(a.saved);
  assert.deepEqual(await nextAccountVisit.host.commands.read(), original);
  nextAccountVisit.controller.dispose();
  b.controller.dispose();
});
