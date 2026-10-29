import assert from "node:assert/strict";
import { createRequire, registerHooks } from "node:module";
import test from "node:test";
import { createElement, type ReactNode } from "react";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import type { AppSpec } from "../spec/types";
import { fullTemplates } from "./catalog";
import { FullAppController } from "./FullAppController";
import {
  InspectorInputRegistry,
  InspectorTextDraft,
} from "./inspectorTextDraft";

const spec = fullTemplates.find((item) => item.id === "planner")!.spec;
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
function app(definition: AppSpec, revision = 1) {
  return {
    id: "app",
    workspaceId: "workspace",
    name: definition.name,
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: { editDefinition: true },
    controlRevision: 1,
    allowedActions: [],
    version: null,
    draft: {
      revision,
      baseVersionId: null,
      candidateHash: `hash_${revision}`,
      spec: definition,
      publishedVersionId: null,
    },
    generation: null,
  };
}
function fixture() {
  const saved = new Map<string, string>(),
    requests: Record<string, unknown>[] = [];
  let current = app(spec),
    ids = 0;
  const controller = new FullAppController({
    scope,
    host: hostStores(new HostLifetime(scope), {
      async read(key) {
        return saved.get(key) ?? null;
      },
      async change(key, update) {
        const next = update(saved.get(key) ?? null);
        if (next === null) saved.delete(key);
        else saved.set(key, next);
      },
    }),
    newId: () => `operation_${++ids}`,
    transport: async (request) => {
      requests.push(request);
      if (request.op === "spec.getApp") return { app: current };
      if (request.op === "spec.capabilities")
        return {
          apiVersion: 1,
          formatVersions: [1],
          generation: false,
          guidance: false,
          effects: [],
          privateMedia: false,
        };
      if (request.op === "spec.review")
        return {
          review: {
            candidateHash: current.draft.candidateHash,
            expectedRevision: current.draft.revision,
            baseVersionId: null,
            currentVersionId: null,
            reviewHash: "review",
            changes: ["Publish planner"],
            compatibilityErrors: [],
            enabledRuleIds: [],
            activateExistingRecordIds: [],
          },
        };
      // Any publish/save call is observable, even if a defective client then rejects this reply.
      return { app: current };
    },
  });
  return {
    controller,
    requests,
    setApp: (value: typeof current) => {
      current = value;
    },
    get ids() {
      return ids;
    },
  };
}
function input(f: ReturnType<typeof fixture>) {
  const draft = new InspectorTextDraft(
    spec.name,
    "app:name",
    f.controller.getSnapshot().editorResetEpoch,
  );
  const registry = new InspectorInputRegistry();
  const remove = registry.register(draft);
  const unregister = f.controller.registerEditorInputGuard(
    registry.canFlush,
    registry.subscribe,
  );
  const unsubscribe = f.controller.subscribe(() =>
    draft.configure(
      f.controller.getSnapshot().candidate?.name ?? "",
      "app:name",
      f.controller.getSnapshot().editorResetEpoch,
    ),
  );
  return {
    draft,
    rejectLabel() {
      draft.change("", false);
      assert.throws(() =>
        f.controller.edit({ type: "RenameLabel", targetId: "app", label: "" }),
      );
      draft.reject();
    },
    close() {
      unsubscribe();
      unregister();
      remove();
      draft.dispose();
    },
  };
}

for (const mode of ["domain_error", "raw_guard_only"] as const) {
  test(`a prepared publication cannot dispatch after ${mode} even though its reviewed candidate is still clean`, async () => {
    const f = fixture();
    await f.controller.load();
    await f.controller.review();
    const review = f.controller.getSnapshot().review;
    assert.equal(review?.reviewHash, "review");
    const c = input(f);
    if (mode === "domain_error") c.rejectLabel();
    else c.draft.change("Unaccepted private input", false);
    assert.equal(f.controller.getSnapshot().dirty, false);
    assert.equal(f.controller.getSnapshot().review, review);
    assert.equal(f.controller.getSnapshot().reviewSpec?.name, spec.name);
    assert.equal(f.controller.hasRejectedEditorInput, true);
    if (mode === "raw_guard_only")
      assert.equal(f.controller.getSnapshot().editorError, null);
    await f.controller.publish();
    assert.equal(f.requests.filter((v) => v.op === "spec.publish").length, 0);
    assert.equal(f.ids, 0);
    assert.equal(f.controller.getSnapshot().pending, null);
    assert.match(
      f.controller.getSnapshot().error!,
      /Fix or discard.*before publishing/,
    );
    c.close();
    f.controller.dispose();
  });
}

test("background replacement preserves rejected raw text after an unrelated no-op clears the general error", async () => {
  const f = fixture();
  await f.controller.load();
  const c = input(f);
  const epoch = f.controller.getSnapshot().editorResetEpoch;
  c.rejectLabel();
  f.controller.edit({ type: "SetTheme", theme: spec.theme });
  assert.equal(f.controller.getSnapshot().editorError, null);
  assert.equal(f.controller.getSnapshot().dirty, false);
  assert.equal(f.controller.hasRejectedEditorInput, true);
  const localCandidate = f.controller.getSnapshot().candidate;
  f.setApp(app({ ...spec, name: "Remote authoritative name" }, 2));
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().candidate, localCandidate);
  assert.equal(
    f.controller.getSnapshot().app?.draft?.spec.name,
    "Remote authoritative name",
  );
  assert.equal(f.controller.getSnapshot().conflict, true);
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch);
  assert.equal(c.draft.getSnapshot(), "");
  assert.equal(f.controller.hasRejectedEditorInput, true);
  assert.equal(await f.controller.flush(), false);
  assert.equal(f.requests.filter((v) => v.op === "spec.saveDraft").length, 0);
  f.controller.discardLocalEdits();
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch + 1);
  assert.equal(c.draft.getSnapshot(), "Remote authoritative name");
  assert.equal(f.controller.hasRejectedEditorInput, false);
  c.close();
  f.controller.dispose();
});

const hooks = registerHooks({
  resolve(specifier, context, next) {
    return next(
      specifier === "react-native" ? "react-native-web" : specifier,
      context,
    );
  },
});
const panel = import("./PublicationPanel");
const { renderToStaticMarkup } = createRequire(import.meta.url)(
  "react-dom/server",
) as { renderToStaticMarkup(element: ReactNode): string };
test.after(() => hooks.deregister());
test("actual publication panel disables preparing another review while mounted raw input is rejected", async () => {
  const { PublicationPanel } = await panel;
  const f = fixture();
  await f.controller.load();
  const c = input(f);
  c.draft.change("Unaccepted private label", false);
  assert.equal(f.controller.getSnapshot().editorError, null);
  const html = renderToStaticMarkup(
    createElement(PublicationPanel, {
      controller: f.controller,
      state: f.controller.getSnapshot(),
    }),
  );
  const button = html.match(
    /<[^>]+aria-label="Prepare exact publication review"[^>]*>/,
  )![0];
  assert.match(button, /(?:aria-disabled="true"| disabled="")/);
  c.draft.accept();
  const repaired = renderToStaticMarkup(
    createElement(PublicationPanel, {
      controller: f.controller,
      state: f.controller.getSnapshot(),
    }),
  );
  const enabled = repaired.match(
    /<[^>]+aria-label="Prepare exact publication review"[^>]*>/,
  )![0];
  assert.doesNotMatch(enabled, /(?:aria-disabled="true"| disabled="")/);
  c.close();
  f.controller.dispose();
});

test("a remote draft removing the selected collection preserves rejected raw input and records a conflict until Discard", async () => {
  const f = fixture();
  await f.controller.load();
  const initial = f.controller.getSnapshot().candidate!;
  const collection = initial.collections[0],
    field = collection.fields[0];
  const identity = (c: string, f: string) => `field:${c}:${f}:label`;
  const draft = new InspectorTextDraft(
    field.label,
    identity(collection.id, field.id),
    f.controller.getSnapshot().editorResetEpoch,
  );
  const registry = new InspectorInputRegistry();
  const remove = registry.register(draft);
  const unregister = f.controller.registerEditorInputGuard(
    registry.canFlush,
    registry.subscribe,
  );
  const unsubscribe = f.controller.subscribe(() => {
    const current = f.controller.getSnapshot(),
      candidate = current.candidate;
    const currentCollection =
      candidate?.collections.find((c) => c.id === collection.id) ??
      candidate?.collections[0];
    const currentField =
      currentCollection?.fields.find((item) => item.id === field.id) ??
      currentCollection?.fields[0];
    draft.configure(
      currentField?.label ?? "",
      currentCollection && currentField
        ? identity(currentCollection.id, currentField.id)
        : "unavailable",
      current.editorResetEpoch,
    );
  });
  draft.change("", false);
  assert.throws(() =>
    f.controller.edit({
      type: "RenameField",
      collectionId: collection.id,
      fieldId: field.id,
      label: "",
    }),
  );
  draft.reject();
  f.controller.edit({ type: "SetTheme", theme: initial.theme });
  assert.equal(f.controller.getSnapshot().dirty, false);
  assert.equal(f.controller.getSnapshot().editorError, null);
  assert.equal(f.controller.hasRejectedEditorInput, true);
  const epoch = f.controller.getSnapshot().editorResetEpoch;
  const localCandidate = f.controller.getSnapshot().candidate;
  const replacement = fullTemplates.find((item) => item.id === "notes")!.spec;
  assert.equal(
    replacement.collections.some((c) => c.id === collection.id),
    false,
  );
  f.setApp(app(replacement, 2));
  await f.controller.load();
  assert.equal(f.controller.getSnapshot().candidate, localCandidate);
  assert.deepEqual(f.controller.getSnapshot().candidate, initial);
  assert.equal(
    f.controller.getSnapshot().app?.draft?.spec.name,
    replacement.name,
  );
  assert.equal(f.controller.getSnapshot().conflict, true);
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch);
  assert.equal(draft.getSnapshot(), "");
  assert.equal(draft.matches(identity(collection.id, field.id), epoch), true);
  assert.equal(f.controller.hasRejectedEditorInput, true);
  assert.equal(await f.controller.flush(), false);
  assert.equal(f.requests.filter((r) => r.op === "spec.saveDraft").length, 0);
  f.controller.discardLocalEdits();
  assert.equal(f.controller.getSnapshot().candidate?.name, replacement.name);
  assert.equal(f.controller.getSnapshot().conflict, false);
  assert.equal(f.controller.getSnapshot().editorResetEpoch, epoch + 1);
  assert.equal(draft.getSnapshot(), replacement.collections[0].fields[0].label);
  assert.equal(f.controller.hasRejectedEditorInput, false);
  unsubscribe();
  unregister();
  remove();
  draft.dispose();
  f.controller.dispose();
});
