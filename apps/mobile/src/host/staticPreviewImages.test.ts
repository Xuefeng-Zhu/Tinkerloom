import assert from "node:assert/strict";
import test from "node:test";
import { HostLifetime } from "./scope";
import { StaticPreviewImagePreloader } from "./staticPreviewImages";
import {
  createOwnedPreviewImageAssets,
  snapshotPreviewImages,
} from "../runtime/previewImageAssets";
import type { PreviewStaticImageAssets } from "../runtime/previewImageAssets";
import type { ImageAsset } from "../runtime/types";
import { PreviewRuntimeAdapter } from "../runtime/preview";
import { fullTemplates } from "../full/catalog";
import { decodeAppSpec } from "../spec/decode";
import type { AppSpec } from "../spec/types";

const lifetime = (accountId = "owner") =>
  new HostLifetime({
    endpoint: "https://example.test/v1",
    projectId: "project",
    accountId,
    appId: "app",
  });
function withImages(...ids: string[]): AppSpec {
  const spec = structuredClone(
    fullTemplates.find((t) => t.id === "projectHub")!.spec,
  );
  const banner = spec.views.find((v) => v.type === "banner")!;
  const copies = ids.map((id, i) => ({
    ...structuredClone(banner),
    id: `staticBanner${i}`,
    options: {
      ...banner.options!,
      imageAssetId: id,
      imageAlt: "Authorized banner",
    },
  }));
  spec.views = [...spec.views.filter((v) => v.type !== "banner"), ...copies];
  const page = spec.navigation!.pages[0];
  page.viewIds = page.viewIds
    .filter((id) => id !== banner.id)
    .concat(copies.map((v) => v.id));
  return decodeAppSpec(spec);
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}
const unavailable = (error: unknown) =>
  typeof error === "object" &&
  error !== null &&
  "code" in error &&
  error.code === "not_found";

test("preview refuses raw asset maps, unowned files, network/bearer URLs, getters and oversized resources", () => {
  const spec = withImages("authorized");
  for (const raw of [
    { authorized: { uri: "file:///etc/passwd" } },
    new Map(),
    {
      readImage() {
        throw Error("must never call");
      },
    },
  ]) {
    assert.throws(
      () =>
        new PreviewRuntimeAdapter(spec, {
          staticImageAssets: raw as unknown as PreviewStaticImageAssets,
        }),
    );
  }
  for (const uri of [
    "https://example.test/private?token=secret",
    "http://localhost/private",
    "data:image/png;base64,abc",
    "content://library/photo",
    "file://remote/photo",
    "file:///etc/passwd",
    "blob:test#secret",
  ]) {
    assert.throws(() =>
      createOwnedPreviewImageAssets(
        [["authorized", { uri }]],
        (value) => value !== "file:///etc/passwd",
      ),
    );
  }
  let getterCalls = 0;
  const malicious = Object.defineProperty({}, "uri", {
    get() {
      getterCalls++;
      return "blob:test";
    },
    enumerable: true,
  });
  assert.throws(() =>
    createOwnedPreviewImageAssets(
      [["authorized", malicious as ImageAsset]],
      () => true,
    ),
  );
  assert.equal(getterCalls, 0);
  assert.throws(() =>
    createOwnedPreviewImageAssets(
      [["authorized", { uri: "blob:test", width: 100000, height: 100000 }]],
      () => true,
    ),
  );
  assert.throws(() =>
    createOwnedPreviewImageAssets(
      Array.from(
        { length: 17 },
        (_, i) => [`asset${i}`, { uri: `blob:${i}` }] as const,
      ),
      () => true,
    ),
  );
  assert.throws(() =>
    createOwnedPreviewImageAssets(
      [["preview_image_0", { uri: "blob:test" }]],
      () => true,
    ),
  );
});

test("host preload reads only unique static declarations and reports partial failures without exposing error contents", async () => {
  const host = lifetime(),
    calls: string[] = [];
  const spec = withImages("authorized", "unavailable", "authorized");
  const loader = new StaticPreviewImagePreloader({
    lifetime: host,
    isCurrent: (id) => id === "saved:7:hash",
    ownsUri: (uri) => uri === "blob:host-created",
    readImage: async (id) => {
      calls.push(id);
      if (id === "unavailable") throw Error("private backend message");
      return { uri: "blob:host-created", width: 100, height: 80 };
    },
  });
  const result = await loader.load(spec, "saved:7:hash");
  assert.deepEqual(calls.sort(), ["authorized", "unavailable"]);
  assert.deepEqual(result.unavailableAssetIds, ["unavailable"]);
  assert.equal(result.closed, false);
  assert.equal(JSON.stringify(result).includes("private backend"), false);
  const preview = new PreviewRuntimeAdapter(spec, {
    staticImageAssets: result.staticImageAssets,
  });
  assert.equal(
    (await preview.readImage("authorized")).uri,
    "blob:host-created",
  );
  await assert.rejects(preview.readImage("unavailable"), unavailable);
  assert.match(
    (await preview.readImage("preview_image_0")).uri,
    /^data:image\/png;base64,/,
  );
  await assert.rejects(
    preview.readImage("arbitrary_record_image"),
    unavailable,
  );
  preview.dispose();
  loader.dispose();
  host.dispose();
});

test("image grant snapshots are frozen copies, scoped to current static refs, and revoke without host IO", async () => {
  const original = {
      uri: "file:///owned/cache/banner.png",
      width: 8,
      height: 4,
    },
    spec = withImages("authorized");
  const grant = createOwnedPreviewImageAssets(
    [
      ["authorized", original],
      ["other", { uri: "blob:other" }],
    ],
    () => true,
  );
  original.uri = "https://example.test/forbidden";
  const preview = new PreviewRuntimeAdapter(spec, {
    staticImageAssets: grant.staticImageAssets,
  });
  const first = await preview.readImage("authorized");
  assert.equal(first.uri, "file:///owned/cache/banner.png");
  first.uri = "https://mutated.test";
  assert.equal(
    (await preview.readImage("authorized")).uri,
    "file:///owned/cache/banner.png",
  );
  await assert.rejects(preview.readImage("other"), unavailable);
  let notifications = 0;
  preview.watch(() => notifications++);
  const before = preview.imageRevision;
  grant.revoke();
  assert.ok(preview.imageRevision > before);
  assert.equal(notifications, 1);
  await assert.rejects(preview.readImage("authorized"), unavailable);
  preview.dispose();
  grant.revoke();
});

test("preloader limits independent reads to three and does not retain mutable callback objects", async () => {
  const host = lifetime(),
    waiting = Array.from({ length: 6 }, () => deferred<ImageAsset>());
  const ids = Array.from({ length: 6 }, (_, i) => `asset${i}`),
    calls: string[] = [];
  let active = 0,
    peak = 0;
  const objects = ids.map((_, i) => ({ uri: `blob:owned${i}` }));
  const loader = new StaticPreviewImagePreloader({
    lifetime: host,
    isCurrent: () => true,
    ownsUri: (uri) => /^blob:owned\d$/.test(uri),
    readImage: async (id) => {
      const index = ids.indexOf(id);
      calls.push(id);
      active++;
      peak = Math.max(peak, active);
      const image = await waiting[index].promise;
      active--;
      return image;
    },
  });
  const loading = loader.load(withImages(...ids), "saved");
  assert.equal(calls.length, 3);
  waiting[0].resolve(objects[0]);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(calls.length, 4);
  objects[0].uri = "https://mutation.test";
  for (let i = 1; i < 6; i++) waiting[i].resolve(objects[i]);
  const result = await loading;
  assert.equal(peak, 3);
  assert.equal(result.unavailableAssetIds.length, 0);
  const preview = new PreviewRuntimeAdapter(withImages(...ids), {
    staticImageAssets: result.staticImageAssets,
  });
  assert.equal((await preview.readImage("asset0")).uri, "blob:owned0");
  preview.dispose();
  loader.dispose();
  host.dispose();
});

test("scope closure fences late reads, revokes prior grants and cannot inject old tenant images into a new preview", async () => {
  const host = lifetime("oldOwner"),
    pending = deferred<ImageAsset>();
  let delayed = false;
  const loader = new StaticPreviewImagePreloader({
    lifetime: host,
    isCurrent: () => true,
    ownsUri: () => host.active,
    readImage: async () =>
      delayed ? pending.promise : { uri: "blob:old-owner" },
  });
  const spec = withImages("authorized"),
    loaded = await loader.load(spec, "saved1");
  const old = new PreviewRuntimeAdapter(spec, {
    staticImageAssets: loaded.staticImageAssets,
  });
  assert.equal((await old.readImage("authorized")).uri, "blob:old-owner");
  delayed = true;
  const loading = loader.load(spec, "saved2");
  await assert.rejects(old.readImage("authorized"), unavailable);
  host.dispose();
  pending.resolve({ uri: "blob:late-private-image" });
  const late = await loading;
  assert.equal(late.closed, true);
  const next = new PreviewRuntimeAdapter(spec, {
    staticImageAssets: late.staticImageAssets,
  });
  await assert.rejects(next.readImage("authorized"), unavailable);
  assert.equal(
    snapshotPreviewImages(loaded.staticImageAssets, ["authorized"]).size,
    0,
  );
  old.dispose();
  next.dispose();
});

test("superseding snapshots fence out-of-order preloads and invalid specs perform no reads", async () => {
  const host = lifetime(),
    pending = deferred<ImageAsset>();
  let current = "old",
    calls = 0;
  const loader = new StaticPreviewImagePreloader({
    lifetime: host,
    isCurrent: (id) => id === current,
    ownsUri: () => true,
    readImage: async () =>
      ++calls === 1 ? pending.promise : { uri: "blob:new" },
  });
  const spec = withImages("authorized"),
    old = loader.load(spec, "old");
  current = "new";
  const newest = await loader.load(spec, "new");
  pending.resolve({ uri: "blob:old" });
  const stale = await old;
  assert.equal(stale.closed, true);
  const preview = new PreviewRuntimeAdapter(spec, {
    staticImageAssets: newest.staticImageAssets,
  });
  assert.equal((await preview.readImage("authorized")).uri, "blob:new");
  const invalid = structuredClone(spec);
  invalid.views[0].type = "untrusted" as never;
  await assert.rejects(loader.load(invalid, "new"));
  assert.equal(calls, 2);
  preview.dispose();
  loader.dispose();
  host.dispose();
});

test("caller mutation cannot replace the preloader's captured account lifetime or read callback", async () => {
  const original = lifetime("first"),
    replacement = lifetime("second");
  let firstReads = 0,
    secondReads = 0;
  const options = {
    lifetime: original,
    isCurrent: () => true,
    ownsUri: () => true,
    readImage: async () => {
      firstReads++;
      return { uri: "blob:first" };
    },
  };
  const loader = new StaticPreviewImagePreloader(options);
  options.lifetime = replacement;
  options.readImage = async () => {
    secondReads++;
    return { uri: "blob:second" };
  };
  const spec = withImages("authorized"),
    result = await loader.load(spec, "saved");
  assert.equal(firstReads, 1);
  assert.equal(secondReads, 0);
  const preview = new PreviewRuntimeAdapter(spec, {
    staticImageAssets: result.staticImageAssets,
  });
  assert.equal((await preview.readImage("authorized")).uri, "blob:first");
  original.dispose();
  await assert.rejects(preview.readImage("authorized"), unavailable);
  preview.dispose();
  replacement.dispose();
});
