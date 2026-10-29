# Author-private draft images

Unpublished apps have no published RuntimeAdapter. `createDraftMediaController` creates media-only saved-draft authority with `versionId: null`; it exposes no query, record action, sharing or generation API. Only the operational `privateMedia` capability enables the factory. Schema vocabulary, isolated preview and a dirty editor candidate never authorize an upload.

## Root integration

Import the factory and pure types from `src/media`. Import `DraftMediaUploadPanel` directly from `src/media/DraftMediaUploadPanel`.

```ts
const snapshot = {
  appId: app.id,
  role: app.role,
  archived: app.archived,
  pendingGeneration: generationOrRetainedBuilderOperationIsPending,
  draft: app.draft, // authoritative saved DTO, not editor.candidate
};
const draftMedia = createDraftMediaController(
  snapshot,
  authenticatedTransport,
  parentHost.lifetime,
  {
    privateMedia: negotiatedCapabilities.privateMedia,
    newId,
    current: () => currentAuthoritativeSavedDraftSnapshotOrNull,
    createHostStorage: platform.host, // optional; platform implementation is the default
    onAccessFailure: clearCurrentBuilderPermission,
  },
);
```

The `SavedDraftMediaSnapshot` shape is `{appId, role, archived, pendingGeneration, draft}`. `draft` is null or `{revision, candidateHash, spec, publishedVersionId}`; additional fields already present in the saved draft DTO are harmless. Construction requires owner/builder, unarchived, `pendingGeneration:false`, a positive saved revision, the server's SHA-256 candidateHash and `publishedVersionId:null`. A consumed draft must be saved as a new candidate before it can receive uploads. Its AppSpec is decoded/copied/frozen. Backend hashes remain authoritative; this module does not hash unsaved editor content and call it a saved draft.

The mandatory `current()` callback returns current saved metadata, including current role/archive/pending-generation state, or null. It must read the controller's authoritative `app.draft`. The factory compares app, role, revision, candidate hash, archive, consumed state and pending generation on every asynchronous guard. A mismatch closes only the media child and clears private resources. Parent account/app closure also closes the child. Disposing media leaves its parent active. The factory owns a distinct child host and rejects sharing the parent's lifetime; its encrypted storage has the same endpoint/project/account/app scope. Supplying `createHostStorage` allows the root's existing platform host factory or isolated test ports, without sharing the published renderer's authority.

```tsx
<DraftMediaUploadPanel
  controller={draftMedia}
  context={draftMedia.savedContext}
  onReadyOpaqueAssetId={(assetId) => selectOpaqueBannerAssetForReview(assetId)}
/>
```

Panel props are `{controller: DraftMediaController, context: SavedDraftMediaContext, onReadyOpaqueAssetId: (assetId:string)=>void}`. The exact UI context is `{draftRevision, candidateHash}`. Do not substitute a new revision/hash into an existing controller; close it and construct a new saved-draft scope. Keep the selection callback stable for its intended banner/editor destination (or key the panel by that destination). A callback/destination change cancels a late selection. The panel lets the user choose an image, upload, view a ready broker thumbnail, explicitly retry/check/discard and explicitly select a ready opaque asset ID. It never saves/publishes a definition, executes a record action or inserts a static reference. The root must make banner/static-image editing a separate explicit user selection and normal reviewed draft save. No fake ID is generated for preview or AI.

`uploadDraft(image)` internally sends the broker's real `{draftRevision}` context. The hash is retained locally for the saved-candidate fence and is not added as an unsupported RPC property. `selectReadyDraftMedia(controller, destination, isCurrent, select)` rechecks authenticated ready status and exact revision/hash before and after awaiting it. `isCurrent` also fences the destination component/selection. The callback receives the broker's opaque ready ID only after these checks.

## Recovery and compatibility

The draft namespace is `private-draft-media-v1`, separate from the original `private-media-v1` record-upload namespace. Both use the existing encrypted host storage. The draft manifest persists `versionId:null` and `candidateHash`. The decoder permits null only with a draft context and candidate hash; record manifests/envelopes retain their original shape and non-null exact version. Existing private draft entries from the older published-only wrapper are not migrated or silently adopted as new saved authority.

Opening a controller loads local recovery without network calls. All original-byte persistence, twenty-chunk bound, hash checks and exact unknown mutation envelopes from the record uploader remain in force. Explicit retry may acknowledge an older exact media receipt before current-context validation; it cannot start a new chunk or select an image for a changed saved revision/hash. Unknown requests are never rewritten. Reopening with the same saved revision/hash can recover an unpublished upload. Queued processing remains pending until an explicit status read establishes ready; local discard sends no deletion or business mutation.

The focused suite retains all 50 prior media checks and adds 19 draft groups. These cover honest null-version authority, unpublished upload/read, owner/builder policy, consumed/forbidden states, separate namespaces, three unknown-write/reopen paths, changed revision/hash/role/archive/generation, old receipt acknowledgement, ready selection fencing, queue/discard and child/parent cleanup. These are source/transport/host-port tests, not live Appwrite or OS picker proof. Root integration and final native compilation remain separate checkpoints.
