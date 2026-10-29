# Authorized static images in isolated previews

The host may lend the preview already-authorized banner image resources. The preview never receives a RuntimeAdapter, transport, SDK, media controller, HostLifetime, resource factory, storage adapter, device bridge or read callback. It receives only an opaque, readonly image grant containing frozen `ImageAsset` copies. Ordinary objects, deserialized JSON and raw URI maps are rejected at runtime.

`StaticPreviewImagePreloader` is the host-side entry point:

```ts
const preloader = new StaticPreviewImagePreloader({
  lifetime: childHostLifetime,
  readImage: (id) => draftMedia.read(id),
  ownsUri: (uri) => draftMedia.ownsUri(uri),
  isCurrent: (id) => id === currentPreviewSnapshotIdentity(),
});
const result = await preloader.load(validatedCandidate, snapshotIdentity);
if (!result.closed && snapshotIdentity === currentPreviewSnapshotIdentity()) {
  // React props for either DesignCanvas or IsolatedPreview:
  // { spec: validatedCandidate, staticImageAssets: result.staticImageAssets }
}
// On app/account/role/archive/generation/saved-context change or host unmount:
preloader.dispose();
```

The host owns `snapshotIdentity` and its current-snapshot comparison. Bind it to the account/app scope, the particular media controller, saved author draft revision/hash and current displayed candidate identity. Do not derive authority from a declaration or historical receipt. `readImage` must be an already account/app/author fenced, readonly broker call, and `ownsUri` must verify that the active broker currently owns that exact resource. Do not pass a URL or file path supplied by AppSpec, a user or a server DTO as a broker-owned resource.

Each load immediately revokes its previous image grant and fences earlier in-flight loads. It strictly decodes/freezes the candidate before reading and enumerates only unique static banner `options.imageAssetId` values. It never reads image-valued record fields or seeds live records. At most 16 assets and three independent reads are allowed. Each URI is bounded to 4096 characters, must use a host-created `blob:` or local `file:///` resource, must pass ownership verification, and cannot contain query/fragment/whitespace/control text. Arbitrary HTTP, bearer URLs, data URLs, library `content://` paths and unowned local files are refused. Metadata dimensions are at most 2048 each. Broker byte validation/cache bounds remain the broker's responsibility; the preview does not decode image bytes.

Failed assets are reported by ID in `unavailableAssetIds`, without backend error messages, headers or data. Other authorized images remain usable. A disposed scope, replaced snapshot or out-of-order load returns a revoked empty grant with `closed: true`; it cannot later inject old images. Constructor options are copied/frozen so caller mutation cannot replace the captured lifetime or callbacks. The preloader revokes grants but does not delete files or revoke browser URLs: the media broker owns those resources and must close them on scope loss/cache eviction. There is no preview-side network fallback, host IO, authorization callback or automatic preload retry.

`PreviewOptions.staticImageAssets`, `new PreviewSession(spec, kind, staticImageAssets)`, `session.update(spec, staticImageAssets)`, `createDesignPreview(spec, {staticImageAssets})`, and the `DesignCanvas`/`IsolatedPreview` prop accept the opaque grant. Image reads use a frozen filtered copy of only the declaration's static asset IDs, plus the existing synthetic `preview_image_N` namespace. Removing a map through `PreviewSession.update` clears it. Direct `applyPresentationSpec(spec)` preserves the current map; its optional second argument accepts a replacement grant or explicit `null` to clear it.

Presentation/map changes preserve the same controller, sample record IDs/data, exact command receipts, cursor and navigation. Semantic changes start a newly validated, isolated sandbox; invalid replacement input leaves the prior session intact. A disposed session cannot be reopened by a late image result. `PreviewRuntimeAdapter.imageRevision` changes on replacement/revocation and emits its local watch event. The image renderer must subscribe to this preview-only revision independently of deferred record refresh and include the revision in both its effect dependencies and saved-response identity. This hides an old URI immediately even while a record form is dirty. The parent integration owns that renderer hook and broker/controller lifetime wiring.

The explicit **Use example image** form action continues to select an in-memory synthetic sample. `uploadImage(PickedImage)` also supports bounded memory-only original bytes under separate `preview_memory_` IDs; see [the memory upload contract](../runtime/PREVIEW_IMAGE_UPLOAD.md). It returns the exact accepted bytes as a data URI and advertises `imageUpload` only because that path is implemented. It does not pick, transmit, transcode or sanitize a file. Host-preloaded static images are real authorized resources; record samples and example image actions remain synthetic. No authenticated picker, native picker, decoder or live upload controller enters preview construction.

Verification: ten new offline groups cover invalid/foreign maps and unsafe URI forms, getter rejection, static-only bounded preload, partial failures, frozen copies, three-read concurrency, scope closure, late/out-of-order results, immutable captured scope, presentation preservation, semantic restart and closed-session fencing, plus zero global backend/host callback calls inside try/design previews and malformed-byte rejection. The follow-up memory upload suite adds exact accepted-byte roundtrips and resource/format/lifecycle checks. The three retained presentation tests and the existing fixture/prototype/view tests remain unchanged. These checks establish source/lifecycle behavior only, not live Appwrite media authorization, browser pixels, native file/image behavior or device proof.
