import assert from "node:assert/strict";
import test from "node:test";
import { createOwnedPreviewImageAssets } from "./previewImageAssets";
import { PreviewRuntimeAdapter } from "./preview";
import { PreviewSession } from "../full/PreviewSession";
import { createDesignPreview } from "../full/createDesignPreview";
import { fullTemplates } from "../full/catalog";
import { decodeAppSpec } from "../spec/decode";
import type { AppSpec, RecordValues } from "../spec/types";
function specWithBanner(): AppSpec {
  const spec = structuredClone(
    fullTemplates.find((t) => t.id === "projectHub")!.spec,
  );
  const banner = spec.views.find((v) => v.type === "banner")!;
  banner.options = {
    ...banner.options!,
    imageAssetId: "bannerAsset",
    imageAlt: "Authorized banner",
  };
  return decodeAppSpec(spec);
}
function images(uri: string) {
  return createOwnedPreviewImageAssets(
    [["bannerAsset", { uri, width: 4, height: 4 }]],
    () => true,
  );
}

test("static image replacement preserves sample records, exact receipts, cursor and navigation across presentation changes", async () => {
  const spec = specWithBanner(),
    firstImages = images("blob:first"),
    session = new PreviewSession(spec, "try", firstImages.staticImageAssets);
  const initial = session.getSnapshot().session,
    adapter = initial.controller.adapter as PreviewRuntimeAdapter;
  const collection = spec.collections[0],
    page = await adapter.query(collection.id, { limit: 1 });
  assert.ok(page.nextCursor);
  const values: RecordValues = Object.fromEntries(
    collection.fields
      .filter((field) => field.required)
      .map((field) => [
        field.id,
        field.type === "choice" ? field.choices![0] : "Private sample action",
      ]),
  );
  const command = {
    appId: "preview",
    versionId: "preview_v1",
    operationId: "sample_receipt",
    actionId: spec.actions.find(
      (action) => action.capability === "records.create.v1",
    )!.id,
    input: { data: values },
  };
  const receipt = await adapter.execute(command),
    record = await adapter.get(receipt.recordId);
  const location = { pageId: spec.navigation!.pages.at(-1)!.id };
  initial.controller.navigate(location, true);
  const secondImages = images("file:///owned/cache/second.png"),
    next = structuredClone(spec);
  next.name = "Presentation update";
  next.views.find((view) => view.type === "banner")!.options!.title =
    "A different welcome";
  const beforeRevision = adapter.imageRevision;
  let changes = 0;
  session.subscribe(() => changes++);
  session.update(next, secondImages.staticImageAssets);
  assert.equal(session.getSnapshot().session, initial);
  assert.equal(initial.controller.adapter, adapter);
  assert.equal(changes, 1);
  assert.ok(adapter.imageRevision > beforeRevision);
  assert.equal(
    (await adapter.readImage("bannerAsset")).uri,
    "file:///owned/cache/second.png",
  );
  assert.deepEqual(await adapter.get(record.id), record);
  assert.deepEqual(await adapter.execute(command), receipt);
  assert.deepEqual(initial.controller.getSnapshot().location, location);
  assert.ok(
    (await adapter.query(collection.id, { limit: 1, cursor: page.nextCursor! }))
      .records.length,
  );
  firstImages.revoke();
  assert.equal(
    (await adapter.readImage("bannerAsset")).uri,
    "file:///owned/cache/second.png",
  );
  session.dispose();
  secondImages.revoke();
});

test("semantic restart remains isolated with authorized static images and a closed session cannot accept late injection", async () => {
  const spec = specWithBanner(),
    grant = images("blob:authorized"),
    session = new PreviewSession(spec, "try", grant.staticImageAssets);
  const before = session.getSnapshot().session;
  const semantic = structuredClone(spec);
  semantic.collections[0].fields.push({
    id: "privateSampleNote",
    label: "Sample note",
    type: "text",
    required: false,
  });
  session.update(decodeAppSpec(semantic), grant.staticImageAssets);
  assert.notEqual(session.getSnapshot().session, before);
  assert.equal(session.getSnapshot().restarted, true);
  assert.equal(session.getSnapshot().session.controller.adapter.preview, true);
  assert.equal(
    (
      await session
        .getSnapshot()
        .session.controller.adapter.readImage("bannerAsset")
    ).uri,
    "blob:authorized",
  );
  session.dispose();
  const closed = session.getSnapshot().session;
  session.update(spec, images("blob:late").staticImageAssets);
  assert.equal(session.getSnapshot().session, closed);
  await assert.rejects(
    closed.controller.adapter.readImage("bannerAsset"),
    (error) => (error as { code?: string }).code === "disposed",
  );
  grant.revoke();
});

test("try/design previews with static assets make zero backend or host callbacks and byte upload never invents synthetic success", async () => {
  const originalFetch = globalThis.fetch;
  let requests = 0,
    ownsCalls = 0;
  globalThis.fetch = async () => {
    requests++;
    throw new Error("Preview attempted network access");
  };
  const grant = createOwnedPreviewImageAssets(
    [["bannerAsset", { uri: "blob:authorized" }]],
    () => {
      ownsCalls++;
      return true;
    },
  );
  const ownedAtMint = ownsCalls;
  const spec = specWithBanner(),
    preview = new PreviewRuntimeAdapter(spec, {
      staticImageAssets: grant.staticImageAssets,
    });
  const design = createDesignPreview(spec, {
    staticImageAssets: grant.staticImageAssets,
  });
  try {
    await preview.query(spec.collections[0].id, {});
    await preview.members();
    assert.equal(
      (await preview.readImage("bannerAsset")).uri,
      "blob:authorized",
    );
    assert.equal(
      (await design.controller.adapter.readImage("bannerAsset")).uri,
      "blob:authorized",
    );
    assert.equal(
      (preview.features as ReadonlySet<string>).has("imageUpload"),
      false,
    );
    await assert.rejects(
      preview.uploadImage({
        bytes: new Uint8Array([1, 2, 3]),
        mimeType: "image/jpeg",
        name: "sample.jpg",
      }),
      /Use an example image/,
    );
    assert.match(
      (await preview.readImage("preview_image_0")).uri,
      /^data:image\/png;base64,/,
    );
    assert.equal(design.controller.adapter.permits(spec.actions[0]), false);
    assert.equal(ownsCalls, ownedAtMint);
    assert.equal(requests, 0);
  } finally {
    globalThis.fetch = originalFetch;
    preview.dispose();
    design.dispose();
    grant.revoke();
  }
});
