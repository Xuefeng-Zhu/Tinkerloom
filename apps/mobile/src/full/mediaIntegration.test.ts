import { PreviewRuntimeAdapter } from "../runtime/preview";
import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import wire from "./fixtures/serviceWire.json";
import { HostLifetime } from "../host/scope";
import type { HostScope } from "../host/scope";
import { hostStores } from "../host/storage";
import { createDraftMediaController } from "../media/draft";
import type { MediaPorts } from "../media/types";
import { decode64, encode64 } from "../media/codec";
import { CHUNK_BYTES } from "../media/types";
import type { MediaRuntimeAdapter } from "../media/adapter";
import { RuntimeError } from "../runtime/errors";
import { manifest, platformCapabilities } from "./contracts";
import type { FullManifest } from "./contracts";
import { FullAppController } from "./FullAppController";
import { createLiveRuntime } from "./createLiveRuntime";
import { fullTemplates } from "./catalog";
const scope = {
  endpoint: "https://example.test/v1",
  projectId: "project",
  accountId: "alice",
  appId: "app",
};
const sha = (bytes: Uint8Array | string) =>
  createHash("sha256").update(bytes).digest("hex");
const picture = () => ({
  bytes: Uint8Array.from([255, 216, 255, 1, 2, 3]),
  mimeType: "image/jpeg" as const,
  name: "private",
});
class Ports implements MediaPorts {
  resources = new Set<string>();
  disposed = 0;
  async sha256(bytes: Uint8Array) {
    return sha(bytes);
  }
  async pick() {
    return picture();
  }
  async image() {
    const uri = `blob:image-${this.resources.size}`;
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
function hosts() {
  const data = new Map<string, string>();
  const opened: ReturnType<typeof hostStores>[] = [];
  return {
    data,
    opened,
    make: (input: HostScope) => {
      const host = hostStores(new HostLifetime(input), {
        async read(k) {
          return data.get(k) ?? null;
        },
        async change(k, update) {
          const next = update(data.get(k) ?? null);
          if (next === null) data.delete(k);
          else data.set(k, next);
        },
      });
      opened.push(host);
      return host;
    },
  };
}
class Broker {
  calls: Record<string, unknown>[] = [];
  bytes = new Uint8Array();
  status = "pending";
  receipts = new Map<string, unknown>();
  before?: () => Promise<void>;
  info() {
    return this.status === "ready"
      ? {
          assetId: "asset",
          status: "ready",
          contentType: "image/jpeg",
          byteLength: this.bytes.length,
          width: 100,
          height: 80,
          sha256: sha(this.bytes),
        }
      : {
          assetId: "asset",
          status: this.status,
          inputBytes: this.bytes.length,
          uploadedBytes: this.status === "pending" ? 0 : this.bytes.length,
        };
  }
  call = async (request: Record<string, unknown>): Promise<unknown> => {
    this.calls.push(request);
    await this.before?.();
    switch (request.op) {
      case "spec.media.begin":
        this.bytes = new Uint8Array(request.byteLength as number);
        return {
          asset: this.info(),
          chunkBytes: CHUNK_BYTES,
          expiresAt: "2030-01-01T00:00:00.000Z",
        };
      case "spec.media.chunk":
        this.bytes.set(decode64(request.dataBase64));
        return { assetId: "asset", uploadedBytes: this.bytes.length };
      case "spec.media.complete":
        this.status = "queued";
        return { asset: this.info() };
      case "spec.media.status":
        this.status = "ready";
        return { asset: this.info() };
      case "spec.media.read":
        return {
          assetId: "asset",
          variant: request.variant,
          offset: 0,
          nextOffset: null,
          byteLength: this.bytes.length,
          contentType: "image/jpeg",
          sha256: sha(this.bytes),
          chunkSha256: sha(this.bytes),
          dataBase64: encode64(this.bytes),
          width: 100,
          height: 80,
          cacheControl: "private, no-store",
        };
      default:
        assert.fail("unexpected media operation");
    }
  };
}
function savedApp(): FullManifest {
  const app = manifest(wire.draft.app, "app");
  return {
    ...app,
    draft: {
      ...app.draft!,
      candidateHash: sha("saved-project"),
      spec: fullTemplates.find((t) => t.id === "projectHub")!.spec,
    },
  };
}
function fixture(input = savedApp(), available = true) {
  const host = hosts(),
    broker = new Broker(),
    rootHost = host.make(scope),
    all: Record<string, unknown>[] = [];
  let current = input,
    ids = 0,
    factories = 0;
  const controller = new FullAppController({
    scope,
    host: rootHost,
    newId: () => `operation-${++ids}`,
    draftMediaFactory: (saved, transport, context) => {
      factories++;
      return createDraftMediaController(
        saved,
        transport,
        context.host.lifetime,
        {
          privateMedia: true,
          newId: () => `image-${++ids}`,
          current: context.current,
          createHostStorage: host.make,
          ports: new Ports(),
          onAccessFailure: context.onAccessFailure,
        },
      );
    },
    transport: async (request) => {
      all.push(request);
      if (request.op === "spec.getApp") return { app: current };
      if (request.op === "spec.capabilities")
        return { ...wire.capabilities, privateMedia: available };
      if (request.op === "spec.saveDraft") {
        current = {
          ...current,
          draft: {
            ...current.draft!,
            revision: (request.expectedRevision as number) + 1,
            candidateHash: sha("saved-next"),
            spec: request.spec as NonNullable<FullManifest["draft"]>["spec"],
          },
        };
        return { app: current };
      }
      if (String(request.op).startsWith("spec.media."))
        return broker.call(request);
      assert.fail("unexpected business operation");
    },
  });
  return {
    controller,
    host,
    broker,
    all,
    rootHost,
    setApp: (app: FullManifest) => {
      current = app;
    },
    getApp: () => current,
    factories: () => factories,
  };
}

test("root unpublished builder installs negotiated media-only authority independently of a runtime", async () => {
  const f = fixture();
  await f.controller.load();
  assert.equal(f.controller.runtime, null);
  assert(f.controller.draftMedia);
  assert.equal(f.controller.draftMedia.base.versionId, null);
  assert.notEqual(f.controller.draftMedia.lifetime, f.rootHost.lifetime);
  assert.equal(f.factories(), 1);
  assert.equal(f.broker.calls.length, 0);
  await f.controller.draftMedia.uploadDraft(picture());
  assert.equal(f.broker.calls[0].draftRevision, 1);
  assert.equal(Object.hasOwn(f.broker.calls[0], "versionId"), false);
  f.controller.dispose();
  assert(f.host.opened.every((host) => !host.lifetime.active));
});

test("root never installs draft image authority for unavailable, viewer, member, archived, consumed or generating apps", async () => {
  const variants: [FullManifest, boolean][] = [[savedApp(), false]];
  for (const role of ["viewer", "member"] as const)
    variants.push([{ ...savedApp(), role }, true]);
  variants.push([{ ...savedApp(), archived: true }, true]);
  const consumed = savedApp();
  consumed.draft = { ...consumed.draft!, publishedVersionId: "published" };
  variants.push([consumed, true]);
  const generating = savedApp();
  generating.generation = {
    id: "job",
    status: "generating",
    mode: "edit",
    mutation: 1,
    attempts: 1,
    requestText: "test",
    diagnostics: "",
    provider: null,
    model: null,
    nextAttemptAt: "2030-01-01T00:00:00.000Z",
    failureCategory: null,
  };
  variants.push([generating, true]);
  for (const [app, available] of variants) {
    const f = fixture(app, available);
    await f.controller.load();
    assert.equal(f.controller.draftMedia, null);
    assert.equal(f.factories(), 0);
    assert.equal(f.broker.calls.length, 0);
    f.controller.dispose();
  }
});

test("explicit banner selection changes only that existing banner locally and normal save advances saved authority", async () => {
  const f = fixture();
  await f.controller.load();
  const media = f.controller.draftMedia!;
  await media.uploadDraft(picture());
  const original = f.controller.getSnapshot().candidate!,
    before = f.all.length;
  await f.controller.applyDraftBannerImage(
    "welcome",
    "asset",
    media.savedContext,
  );
  assert.equal(f.controller.getSnapshot().dirty, true);
  assert.equal(
    f.all
      .slice(before)
      .some((request) =>
        ["spec.saveDraft", "spec.publish"].includes(String(request.op)),
      ),
    false,
  );
  const candidate = f.controller.getSnapshot().candidate!;
  assert.deepEqual(candidate.collections, original.collections);
  assert.deepEqual(candidate.actions, original.actions);
  const banner = candidate.views.find((view) => view.id === "welcome");
  assert.equal(banner?.type, "banner");
  if (banner?.type === "banner") {
    assert.equal(banner.options?.imageAssetId, "asset");
    assert(banner.options?.imageAlt);
  }
  assert.equal(
    f.controller.draftMedia,
    media,
    "dirty editor keeps saved-authority reads for isolated preload",
  );
  await f.controller.save();
  assert.equal(f.controller.getSnapshot().dirty, false);
  assert.equal(f.controller.getSnapshot().app?.draft?.revision, 2);
  assert.notEqual(f.controller.draftMedia, media);
  assert(!media.lifetime.active);
  assert.equal(
    f.all.filter((request) => request.op === "spec.publish").length,
    0,
  );
  f.controller.dispose();
});

test("dirty and invalid candidates, wrong banners and mismatched saved context cannot attach an image", async () => {
  const f = fixture();
  await f.controller.load();
  const media = f.controller.draftMedia!;
  await media.uploadDraft(picture());
  await assert.rejects(
    f.controller.applyDraftBannerImage("missing", "asset", media.savedContext),
  );
  f.controller.edit({ type: "RenameLabel", targetId: "app", label: "Unsaved" });
  const before = f.broker.calls.length;
  await assert.rejects(
    f.controller.applyDraftBannerImage("welcome", "asset", media.savedContext),
  );
  assert.equal(f.broker.calls.length, before);
  f.controller.discardLocalEdits();
  assert.throws(() => f.controller.setCandidate({ bad: true }));
  await assert.rejects(
    f.controller.applyDraftBannerImage("welcome", "asset", media.savedContext),
  );
  f.controller.discardLocalEdits();
  await assert.rejects(
    f.controller.applyDraftBannerImage("welcome", "asset", {
      ...media.savedContext,
      candidateHash: sha("wrong"),
    }),
  );
  f.controller.dispose();
});

test("a dirty edit appearing during ready-status selection cancels attachment", async () => {
  const f = fixture();
  await f.controller.load();
  const media = f.controller.draftMedia!;
  await media.uploadDraft(picture());
  f.broker.before = async () => {
    f.controller.edit({
      type: "RenameLabel",
      targetId: "app",
      label: "Changed while reading",
    });
  };
  await assert.rejects(
    f.controller.applyDraftBannerImage("welcome", "asset", media.savedContext),
  );
  const banner = f.controller
    .getSnapshot()
    .candidate?.views.find((view) => view.id === "welcome");
  if (banner?.type === "banner")
    assert.equal(banner.options?.imageAssetId, undefined);
  f.controller.dispose();
});

test("confirmed hash/revision changes and role downgrade dispose saved-authority private resources", async () => {
  const f = fixture();
  await f.controller.load();
  const old = f.controller.draftMedia!;
  await old.uploadDraft(picture());
  const image = await old.read("asset");
  assert(old.ownsUri(image.uri));
  const changed = {
    ...f.getApp(),
    draft: {
      ...f.getApp().draft!,
      revision: 2,
      candidateHash: sha("revision2"),
    },
  };
  f.setApp(changed);
  await f.controller.load();
  assert(!old.lifetime.active);
  assert(!old.ownsUri(image.uri));
  assert(f.controller.draftMedia);
  assert.notEqual(f.controller.draftMedia, old);
  const latest = f.controller.draftMedia!;
  f.setApp({ ...changed, role: "viewer" });
  await f.controller.load();
  assert(!latest.lifetime.active);
  assert.equal(f.controller.draftMedia, null);
  f.controller.dispose();
});

test("published root wrapper shares one child storage lifetime across watch, reminders and outer media", async () => {
  const local = hosts(),
    parent = local.make(scope),
    ports = new Ports();
  let active = true,
    polls = 0;
  const app = manifest(wire.published.app, "app"),
    platform = platformCapabilities({
      ...wire.capabilities,
      privateMedia: true,
    });
  const adapter = createLiveRuntime(
    app,
    async (request) => {
      if (request.op === "spec.watch") {
        polls++;
        return {
          appId: "app",
          versionId: app.version!.id,
          controlRevision: app.controlRevision,
          role: app.role,
          archived: app.archived,
        };
      }
      assert.fail("no automatic media request");
    },
    { host: parent, platform },
    {
      newId: () => "id",
      isCurrent: () => active,
      onManifestChange: () => {},
      onAccessFailure: () => {},
      createHostStorage: local.make,
      mediaPorts: ports,
      watchActivity: {
        getSnapshot: () => ({ foreground: true, online: true }),
        subscribe: () => () => {},
      },
    },
  ) as MediaRuntimeAdapter;
  assert(adapter.media);
  assert.equal(adapter.media.lifetime, local.opened[1].lifetime);
  assert.notEqual(adapter.media.lifetime, parent.lifetime);
  assert(adapter.features.has("imageRead"));
  const stop = adapter.watch(() => {});
  adapter.setActive?.(true);
  await new Promise((resolve) => setTimeout(resolve, 15));
  assert.equal(polls, 1);
  adapter.setActive?.(false);
  active = false;
  stop();
  adapter.dispose();
  assert(!local.opened[1].lifetime.active);
  assert(parent.lifetime.active);
  assert.equal(ports.disposed, 1);
  parent.lifetime.dispose();
});

test("published wrapper rejects parent-storage/new-lifetime mismatch and closes children on host close", async () => {
  const local = hosts(),
    parent = local.make(scope),
    app = manifest(wire.published.app, "app"),
    platform = platformCapabilities({
      ...wire.capabilities,
      privateMedia: true,
    });
  const wrong = local.make(scope);
  assert.throws(() =>
    createLiveRuntime(
      app,
      async () => ({}),
      { host: parent, platform },
      {
        newId: () => "id",
        isCurrent: () => true,
        onManifestChange: () => {},
        onAccessFailure: () => {},
        createHostStorage: () => ({ ...wrong, storage: parent.storage }),
        mediaPorts: new Ports(),
      },
    ),
  );
  wrong.lifetime.dispose();
  const adapter = createLiveRuntime(
    app,
    async () => ({}),
    { host: parent, platform },
    {
      newId: () => "id",
      isCurrent: () => true,
      onManifestChange: () => {},
      onAccessFailure: () => {},
      createHostStorage: local.make,
      mediaPorts: new Ports(),
    },
  );
  const child = adapter.media!.lifetime;
  parent.lifetime.dispose();
  assert(!child.active);
  assert.throws(
    () => adapter.media!.read("asset"),
    (error) => error instanceof RuntimeError && error.code === "disposed",
  );
  adapter.dispose();
});

async function settlePreview(controller: FullAppController) {
  for (let i = 0; i < 20 && controller.getSnapshot().previewImagesLoading; i++)
    await new Promise((resolve) => setImmediate(resolve));
  assert.equal(controller.getSnapshot().previewImagesLoading, false);
}
test("root preloads a broker-ready image outside isolated dirty preview, and revokes its grant before refresh", async () => {
  const f = fixture();
  await f.controller.load();
  const media = f.controller.draftMedia!;
  await media.uploadDraft(picture());
  await f.controller.applyDraftBannerImage(
    "welcome",
    "asset",
    media.savedContext,
  );
  await settlePreview(f.controller);
  const state = f.controller.getSnapshot();
  assert(state.previewStaticImageAssets);
  assert.equal(state.previewUnavailableAssetCount, 0);
  const preview = new PreviewRuntimeAdapter(state.candidate!, {
    staticImageAssets: state.previewStaticImageAssets,
  });
  const image = await preview.readImage("asset");
  assert(media.ownsUri(image.uri));
  const revision = preview.imageRevision;
  const pending = f.controller.load();
  await assert.rejects(preview.readImage("asset"));
  assert(preview.imageRevision > revision);
  await pending;
  preview.dispose();
  f.controller.dispose();
});
test("newly typed unconfirmed static IDs stay unavailable without a broker probe or loss of dirty edits", async () => {
  const f = fixture();
  await f.controller.load();
  const banner = f.controller
    .getSnapshot()
    .candidate!.views.find((view) => view.type === "banner")!;
  assert(banner.type === "banner");
  const { id, ...view } = banner;
  const before = f.broker.calls.length;
  f.controller.edit({
    type: "UpdateView",
    viewId: id,
    view: {
      ...view,
      options: {
        ...view.options,
        title: banner.options!.title,
        imageAssetId: "unconfirmed",
        imageAlt: "not yet uploaded",
      },
    },
  });
  await settlePreview(f.controller);
  assert.equal(f.broker.calls.length, before);
  assert.equal(f.controller.getSnapshot().dirty, true);
  assert(f.controller.getSnapshot().app);
  assert.equal(f.controller.getSnapshot().previewUnavailableAssetCount, 1);
  const preview = new PreviewRuntimeAdapter(
    f.controller.getSnapshot().candidate!,
    { staticImageAssets: f.controller.getSnapshot().previewStaticImageAssets },
  );
  await assert.rejects(preview.readImage("unconfirmed"));
  preview.dispose();
  f.controller.dispose();
});
