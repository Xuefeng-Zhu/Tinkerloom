import assert from "node:assert/strict";
import { createRequire, registerHooks } from "node:module";
import test from "node:test";
import { createElement, type ReactNode } from "react";
import { BackendError } from "../backend/errors";
import { HostLifetime } from "../host/scope";
import { hostStores } from "../host/storage";
import { decodeAppSpec } from "../spec/decode";
import { RuntimeError } from "../runtime/errors";
import { FunctionRuntimeAdapter } from "../runtime/functionAdapter";
import type { MediaRuntimeAdapter } from "../media/adapter";
import type { PrivateMediaController } from "../media/controller";
import { fullTemplates } from "./catalog";
import { FullAppController } from "./FullAppController";
import { PreviewSession } from "./PreviewSession";

const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const raw = JSON.parse(
  JSON.stringify(fullTemplates.find((t) => t.id === "photoJournal")!.spec),
);
raw.name = "Our family journal";
raw.collections[0].fields.push({
  id: "ourCustomMood",
  label: "Our custom mood",
  type: "text",
  required: false,
});
raw.views
  .filter((view: { type: string }) => view.type === "form")
  .forEach((view: { options: { steps: { fieldIds: string[] }[] } }) =>
    view.options.steps.at(-1)!.fieldIds.push("ourCustomMood"),
  );
raw.requires.push("views.banner.v1");
raw.views.push({
  id: "ourFamilyBanner",
  type: "banner",
  label: "Our family",
  actionIds: [],
  options: {
    title: "Our family memories",
    tone: "accent",
    imageAssetId: "family_photo",
    imageAlt: "Our approved family photo",
  },
});
raw.navigation.pages[0].viewIds.unshift("ourFamilyBanner");
const custom = decodeAppSpec(raw);
function app(spec = custom, versionId = "published_1") {
  return {
    id: "app",
    workspaceId: "workspace",
    name: spec.name,
    engine: "appspec.v1",
    role: "owner",
    archived: false,
    capabilities: { editDefinition: true },
    controlRevision: 1,
    allowedActions: [],
    version: { id: versionId, number: 1, hash: `hash_${versionId}`, spec },
    draft: null,
    generation: null,
  };
}
function savedDraft(
  request: Record<string, unknown>,
  current: Record<string, unknown>,
) {
  return {
    ...current,
    draft: {
      revision: Number(request.expectedRevision) + 1,
      baseVersionId: request.expectedVersionId,
      candidateHash: "saved_hash",
      spec: request.spec,
      publishedVersionId: null,
    },
  };
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
function fixture(
  options: {
    saved?: Map<string, string>;
    privateMedia?: boolean;
    onAssetRead?: () => void;
  } = {},
) {
  const saved = options.saved ?? new Map<string, string>(),
    calls: Record<string, unknown>[] = [];
  let current: Record<string, unknown> = app(),
    ids = 0;
  let read: (() => Promise<unknown>) | null = null;
  let beforePersist: (() => Promise<void>) | null = null;
  let mutation: (request: Record<string, unknown>) => Promise<unknown> = async (
    request,
  ) => {
    current = savedDraft(request, current);
    return { app: current };
  };
  const host = hostStores(new HostLifetime(scope), {
    async read(key) {
      return saved.get(key) ?? null;
    },
    async change(key, update) {
      if (beforePersist && key === "full-command") await beforePersist();
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
      if (request.op === "spec.getApp") return read ? read() : { app: current };
      if (request.op === "spec.capabilities")
        return {
          apiVersion: 1,
          formatVersions: [1],
          generation: false,
          guidance: false,
          effects: [],
          privateMedia: options.privateMedia ?? false,
        };
      assert.equal(
        request.op,
        "spec.saveDraft",
        "Customization must not generate or publish",
      );
      assert.ok(saved.size > 0, "Persist before sending the save");
      return mutation(request);
    },
    ...(options.privateMedia
      ? {
          adapterFactory: (manifest, transport) => {
            const adapter = new FunctionRuntimeAdapter(
              manifest,
              transport,
            ) as MediaRuntimeAdapter;
            const lifetime = new HostLifetime(scope);
            const stopLifetime = host.lifetime.onDispose(() =>
              lifetime.dispose(),
            );
            const media = {
              lifetime,
              getSnapshot: () => ({ asset: null }),
              async read(assetId: string) {
                assert.equal(assetId, "family_photo");
                options.onAssetRead?.();
                return {
                  uri: "blob:approved-family-photo",
                  width: 120,
                  height: 80,
                  alt: "Family photo",
                };
              },
              ownsUri: (uri: string) =>
                lifetime.active && uri === "blob:approved-family-photo",
            } as unknown as PrivateMediaController;
            Object.defineProperty(adapter, "media", { value: media });
            const dispose = adapter.dispose.bind(adapter);
            adapter.dispose = () => {
              stopLifetime();
              lifetime.dispose();
              dispose();
            };
            return adapter;
          },
        }
      : {}),
  });
  return {
    controller,
    host,
    calls,
    saved,
    get current() {
      return current;
    },
    set current(value: Record<string, unknown>) {
      current = value;
    },
    set read(value: typeof read) {
      read = value;
    },
    set mutation(value: typeof mutation) {
      mutation = value;
    },
    set beforePersist(value: typeof beforePersist) {
      beforePersist = value;
    },
    get ids() {
      return ids;
    },
    writes: () => calls.filter((r) => r.op === "spec.saveDraft"),
  };
}

test("published custom definition is available for isolated read-only preview with no draft, ID allocation or mutation", async () => {
  const f = fixture();
  await f.controller.load();
  assert.deepEqual(f.controller.previewSpec, custom);
  assert.equal(f.controller.getSnapshot().candidate, null);
  assert.equal(f.controller.canEditPublishedVersion, true);
  assert.equal(f.writes().length, 0);
  assert.equal(f.ids, 0);
  assert.equal(f.saved.size, 0);
  const preview = new PreviewSession(f.controller.previewSpec!);
  assert.deepEqual(
    preview.getSnapshot().session.controller.adapter.spec,
    custom,
  );
  assert.equal(f.writes().length, 0);
  preview.dispose();
  f.controller.dispose();
});
test("explicit edit seeds and durably saves the exact current non-catalog published spec including custom fields and image IDs", async () => {
  for (const role of ["owner", "builder"]) {
    const f = fixture();
    f.current = { ...app(), role };
    await f.controller.load();
    await f.controller.editPublishedVersion();
    assert.equal(f.writes().length, 1);
    const request = f.writes()[0];
    assert.deepEqual(request.spec, custom);
    assert.equal(request.expectedRevision, 0);
    assert.equal(request.expectedVersionId, "published_1");
    assert.equal(f.ids, 1);
    assert.deepEqual(f.controller.getSnapshot().candidate, custom);
    assert.equal(
      f.controller.getSnapshot().app?.draft?.baseVersionId,
      "published_1",
    );
    assert.equal(f.controller.getSnapshot().dirty, false);
    assert.equal(f.saved.size, 0);
    assert.ok(f.calls.filter((r) => r.op === "spec.getApp").length >= 3);
    assert.equal(
      f.calls.some((r) =>
        ["spec.generate", "spec.publish", "spec.createApp"].includes(
          String(r.op),
        ),
      ),
      false,
    );
    assert.deepEqual(f.controller.getSnapshot().app?.version?.spec, custom);
    f.controller.dispose();
  }
});
test("a changed published version or new own draft found during the fresh read prevents copying the stale displayed definition", async () => {
  for (const kind of ["version", "draft"]) {
    const f = fixture();
    await f.controller.load();
    if (kind === "version")
      f.current = app(
        decodeAppSpec({ ...raw, name: "A newer publication" }),
        "published_2",
      );
    else
      f.current = savedDraft(
        {
          expectedRevision: 0,
          expectedVersionId: "published_1",
          spec: decodeAppSpec({ ...raw, name: "Other device author draft" }),
        },
        f.current,
      );
    await f.controller.editPublishedVersion();
    assert.equal(f.writes().length, 0);
    assert.equal(f.ids, 0);
    assert.match(
      f.controller.getSnapshot().error!,
      kind === "version" ? /published version changed/ : /existing draft/,
    );
    f.controller.dispose();
  }
});
test("a failed fresh access read never authorizes the save from cached published metadata", async () => {
  const f = fixture();
  await f.controller.load();
  f.read = async () => {
    throw new Error("No response");
  };
  await f.controller.editPublishedVersion();
  assert.equal(f.writes().length, 0);
  assert.equal(f.ids, 0);
  assert.equal(f.controller.getSnapshot().candidate, null);
  assert.match(f.controller.getSnapshot().error!, /could not be confirmed/);
  f.controller.dispose();
});
test("current authority and account loss fence late seed reads and clear published preview access", async () => {
  for (const kind of ["viewer", "archive", "forbidden", "dispose"]) {
    const f = fixture();
    await f.controller.load();
    if (kind === "viewer")
      f.current = {
        ...app(),
        role: "viewer",
        capabilities: { editDefinition: false },
      };
    if (kind === "archive") f.current = { ...app(), archived: true };
    if (kind === "forbidden")
      f.read = async () => {
        throw new BackendError("Revoked", "forbidden", "service", false, 403);
      };
    if (kind === "dispose") {
      const gate = deferred<unknown>(),
        entered = deferred<void>();
      f.read = async () => {
        entered.resolve();
        return gate.promise;
      };
      const editing = f.controller.editPublishedVersion();
      await entered.promise;
      f.controller.dispose();
      gate.resolve({ app: app() });
      await editing;
    } else await f.controller.editPublishedVersion();
    assert.equal(f.writes().length, 0);
    assert.equal(f.ids, 0);
    assert.equal(f.controller.previewSpec, null);
    assert.equal(f.controller.getSnapshot().candidate, null);
    f.controller.dispose();
  }
});
test("blank shells stay empty, while own drafts and unsaved record or image work cannot be overwritten", async () => {
  const blank = fixture();
  blank.current = { ...app(), version: null };
  await blank.controller.load();
  assert.equal(blank.controller.previewSpec, null);
  await blank.controller.editPublishedVersion();
  assert.equal(blank.writes().length, 0);
  blank.controller.dispose();
  const own = fixture();
  const ownDefinition = decodeAppSpec({
    ...raw,
    name: "Existing author draft",
  });
  own.current = savedDraft(
    {
      expectedRevision: 0,
      expectedVersionId: "published_1",
      spec: ownDefinition,
    },
    own.current,
  );
  await own.controller.load();
  assert.deepEqual(own.controller.previewSpec, ownDefinition);
  await own.controller.editPublishedVersion();
  assert.equal(own.writes().length, 0);
  own.controller.dispose();
  const pending = fixture();
  const retainedRecord = {
    appId: "app",
    versionId: "published_1",
    actionId: "addRecord",
    operationId: "record_operation",
    input: { title: "Unconfirmed memory" },
  };
  await pending.host.commands.save(retainedRecord);
  await pending.controller.load();
  await pending.controller.editPublishedVersion();
  assert.equal(pending.writes().length, 0);
  assert.deepEqual(await pending.host.commands.read(), retainedRecord);
  pending.controller.dispose();
  const generating = fixture();
  generating.current = {
    ...app(),
    generation: {
      id: "job",
      status: "queued",
      mode: "edit",
      mutation: 1,
      attempts: 0,
      requestText: "Accepted active request",
      diagnostics: "",
      provider: null,
      model: null,
      nextAttemptAt: "2030-01-01T00:00:00Z",
      failureCategory: null,
    },
  };
  await generating.controller.load();
  await generating.controller.editPublishedVersion();
  assert.equal(generating.writes().length, 0);
  generating.controller.dispose();
  const record = fixture();
  await record.controller.load();
  await record.controller.runtime!.recover();
  record.controller.runtime!.setDirty(true);
  await record.controller.editPublishedVersion();
  assert.equal(record.writes().length, 0);
  record.controller.runtime!.setDirty(false);
  const release = record.controller.runtime!.beginFormInteraction();
  assert.ok(release);
  await record.controller.editPublishedVersion();
  assert.equal(record.writes().length, 0);
  release();
  record.controller.dispose();
});
test("lost seed save is retained exactly across reopen and newer publication; no new edit can replace it", async () => {
  const f = fixture();
  let committed: Record<string, unknown> | null = null;
  f.mutation = async (request) => {
    committed = savedDraft(request, f.current);
    f.current = committed;
    throw new Error("Lost response");
  };
  await f.controller.load();
  await f.controller.editPublishedVersion();
  assert.equal(f.controller.getSnapshot().pendingStatus, "uncertain");
  const original = f.writes()[0];
  assert.deepEqual(original.spec, custom);
  await f.controller.editPublishedVersion();
  assert.equal(f.writes().length, 1);
  assert.equal(f.ids, 1);
  f.controller.dispose();
  const reopened = fixture({ saved: f.saved });
  reopened.current = {
    ...committed!,
    version: { ...app().version, id: "published_2", number: 2 },
  };
  await reopened.controller.load();
  assert.equal(reopened.writes().length, 0);
  reopened.mutation = async (request) => {
    assert.deepEqual(request, original);
    return { app: committed };
  };
  await reopened.controller.retry();
  assert.equal(reopened.writes().length, 1);
  assert.equal(reopened.controller.getSnapshot().pending, null);
  assert.equal(
    reopened.controller.getSnapshot().app?.version?.id,
    "published_2",
  );
  assert.equal(reopened.saved.size, 0);
  reopened.controller.dispose();
});
test("a publication racing durable save preparation cannot change the captured base version", async () => {
  const f = fixture(),
    gate = deferred<void>(),
    entered = deferred<void>();
  let pause = true;
  f.beforePersist = async () => {
    if (pause) {
      entered.resolve();
      await gate.promise;
    }
  };
  f.mutation = async (request) => {
    assert.equal(request.expectedVersionId, "published_1");
    throw new RuntimeError("definition_conflict", "Published version changed");
  };
  await f.controller.load();
  const editing = f.controller.editPublishedVersion();
  await entered.promise;
  f.current = app(
    decodeAppSpec({ ...raw, name: "Newer publication" }),
    "published_2",
  );
  await f.controller.load();
  pause = false;
  gate.resolve();
  await editing;
  assert.equal(f.writes().length, 1);
  assert.equal(f.controller.getSnapshot().pendingStatus, "rejected");
  assert.equal(
    f.controller.getSnapshot().pending?.request.expectedVersionId,
    "published_1",
  );
  assert.deepEqual(f.controller.getSnapshot().pending?.request.spec, custom);
  f.controller.dispose();
});
test("published fallback static images are preloaded by the authorized host and read in preview without another host call", async () => {
  let reads = 0;
  const f = fixture({ privateMedia: true, onAssetRead: () => reads++ });
  await f.controller.load();
  for (
    let i = 0;
    i < 20 && !f.controller.getSnapshot().previewStaticImageAssets;
    i++
  )
    await new Promise((resolve) => setTimeout(resolve, 1));
  assert.equal(reads, 1);
  const preview = new PreviewSession(
    f.controller.previewSpec!,
    "try",
    f.controller.getSnapshot().previewStaticImageAssets,
  );
  const asset = await preview
    .getSnapshot()
    .session.controller.adapter.readImage("family_photo");
  assert.equal(asset.uri, "blob:approved-family-photo");
  assert.equal(reads, 1);
  f.current = {
    ...app(),
    role: "viewer",
    capabilities: { editDefinition: false },
  };
  await f.controller.load();
  assert.equal(f.controller.previewSpec, null);
  await assert.rejects(
    preview.getSnapshot().session.controller.adapter.readImage("family_photo"),
  );
  preview.dispose();
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
const components = Promise.all([
  import("./PublishedBasePanel"),
  import("./GenerationPanel"),
]);
const { renderToStaticMarkup } = createRequire(import.meta.url)(
  "react-dom/server",
) as { renderToStaticMarkup(element: ReactNode): string };
test.after(() => hooks.deregister());
test("the actual published-base panel exposes the explicit manual action with provider off and hides it for drafts or lost access", async () => {
  const [{ PublishedBasePanel }, { GenerationPanel }] = await components,
    f = fixture();
  await f.controller.load();
  const html = renderToStaticMarkup(
    createElement(PublishedBasePanel, {
      controller: f.controller,
      state: f.controller.getSnapshot(),
    }),
  );
  assert.match(html, /Edit published version/);
  assert.match(html, /published version 1/);
  assert.doesNotMatch(
    html.match(/<[^>]+aria-label="Edit published version"[^>]*>/)![0],
    /aria-disabled="true"/,
  );
  const composer = renderToStaticMarkup(
    createElement(GenerationPanel, {
      controller: f.controller,
      state: f.controller.getSnapshot(),
    }),
  );
  assert.match(composer, /Choose Edit published version/);
  assert.match(composer, /Refine with AI/);
  assert.equal(f.writes().length, 0);
  await f.controller.editPublishedVersion();
  assert.equal(
    renderToStaticMarkup(
      createElement(PublishedBasePanel, {
        controller: f.controller,
        state: f.controller.getSnapshot(),
      }),
    ),
    "",
  );
  f.current = {
    ...app(),
    role: "viewer",
    capabilities: { editDefinition: false },
  };
  await f.controller.load();
  assert.equal(
    renderToStaticMarkup(
      createElement(PublishedBasePanel, {
        controller: f.controller,
        state: f.controller.getSnapshot(),
      }),
    ),
    "",
  );
  f.controller.dispose();
});

test("repeated explicit edit actions join one fresh authority read and one original save", async () => {
  const f = fixture();
  await f.controller.load();
  const gate = deferred<unknown>(),
    entered = deferred<void>();
  let reads = 0;
  f.read = async () => {
    reads++;
    entered.resolve();
    return gate.promise;
  };
  const first = f.controller.editPublishedVersion();
  await entered.promise;
  const second = f.controller.editPublishedVersion();
  assert.equal(first, second);
  f.read = null;
  gate.resolve({ app: f.current });
  await Promise.all([first, second]);
  assert.equal(reads, 1);
  assert.equal(f.writes().length, 1);
  assert.equal(f.ids, 1);
  f.controller.dispose();
});
