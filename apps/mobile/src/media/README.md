# Private image adapter

This module adds the installed private image broker to a live AppSpec runtime. It uses the existing authenticated Function transport and account/app-scoped encrypted host storage. Definitions supply neither network destinations nor local file paths. Preview keeps its original isolated adapter.

## Root integration

Compose `watch → reminders → private media`, with private media outermost:

```ts
const runtime = withPrivateMedia(baseWithReminders, transport, childLifetime, {
  privateMedia: capabilities.privateMedia,
  newId, // host CSPRNG IDs, retained with the original command
  storage: childHost.storage,
  isCurrent: () => currentRuntimeScopeIsActive,
  onAccessFailure: clearCurrentAppPermission,
});
```

Negotiate `spec.capabilities` before enabling this wrapper. `storage.lifetime` must be the same child lifetime supplied to the wrapper. The child must close on sign-out, app/version/role change and runtime disposal. The wrapper delegates every base method, including `setActive`. `dispose` closes media ports and the base adapter. It advertises image upload only for an active non-viewer, unarchived live scope; server policies still authorize every operation independently.

`uploadImage(image, context)` accepts the shared `RuntimeImageUploadContext`: `{versionId, actionId, fieldId, targetRecordId?, expectedRecordRevision?}`. Create actions forbid a record target; patch actions require both target and captured record revision. The action must be declared and its field must be an image field in that action's collection. Author draft callers use the separate `createDraftMediaController` factory described in [DRAFT_MEDIA.md](./DRAFT_MEDIA.md). A published RuntimeAdapter is not draft authority; `captureUploadContext` cannot create it. Never infer a draft revision or field from current UI position.

The returned adapter has an optional `.media` controller. The pure index exports `withPrivateMedia`, `PrivateMediaController`, `MediaRecovery`, DTO types and `attachReadyMedia`. Import the optional React Native UI directly from `./RecoveryPanel` so Node/pure clients do not load UI libraries.

```tsx
<PrivateMediaRecoveryPanel
  controller={runtime.media}
  destination={uploadContext}
  onAttach={(assetId) => onChange(assetId)}
/>
```

The panel props are `{controller, destination?: MediaUploadContext, onAttach?: (assetId: string) => void}`. A destination-bound panel renders only for the exact saved upload context. Mount one additional panel without a destination at app level if recovery from an older version must remain discoverable. That panel can recover or discard, but cannot attach to a field.

`attachReadyMedia(controller, destination, isCurrent, attach): Promise<boolean>` makes an authenticated read-only status request and compares the exact frozen destination before and after awaiting it. The caller's `isCurrent` must fence component/field/record changes. Only ready, currently authorized media calls `attach(assetId)`. Attachment changes a form value; uploading and attachment do not execute a record save.

## Retained commands

Originals must be JPEG, PNG or WebP and at most 5 MiB. All original bytes and hashes are persisted in at most twenty 256 KiB chunk entries before the first server mutation. Every stored entry fits the existing host entry bound; metadata stores at most one exact pending chunk request. The real host supplies encrypted storage; unit tests use an explicitly in-memory port and do not prove encryption on a device.

`spec.media.begin`, `spec.media.chunk` and `spec.media.complete` have separate frozen envelopes. Unknown transport results, timeouts, transaction conflicts, malformed acknowledgements and unconfirmed local acknowledgement persistence retain the exact request. Opening `.recover()` loads only local data and never calls the broker. `.retry()` is an explicit user action: it validates retained original bytes, replays the pending envelope, then proceeds with new work only under the current context. A receipt from an older version can be acknowledged before new-context validation; the old envelope is never rewritten into the newer version.

Duplicate chunk ACKs may report later committed bytes. The controller still resends every retained subsequent chunk in order so the server checks each hash; a count is not a trusted manifest. A status result does not acknowledge an unknown mutation. `.poll()` performs only status reads. Queued/processing images remain retained and raise `media_processing`; the bounded default poll is one read, with no timer that repeats writes. `.discard()` removes local recovery, with no server deletion, record save or receipt inference. A preparing upload whose local persistence was interrupted requires reselecting the identical original or explicit discard.

Server status values are exactly `pending | queued | processing | ready | failed`. `media_expired` is a command error, not a client-invented status. Free Cloud processing/recovery timing remains governed by the installed worker; this client does not establish one-shot wakeup availability or minute-level delivery.

## Picking and private reads

Web uses an opaque image-only HTML file input. It checks `File.size` before any slice read and never creates an original image URL or decodes original pixels. Native uses the official image-only Expo image picker with `base64:false` and `exif:false`, then lazily opens a read-only FileHandle. Both read in bounded pieces and stop at 5 MiB + one byte to detect unknown/lying lengths. Native removes only the returned app-owned `ImagePicker` cache copy, including late picker completion after scope closure; it never deletes `content://` or library originals. No startup permission request or camera capture is performed.

Broker reads validate asset identity, variant, offsets, exact page lengths, JPEG/PNG type, dimensions, `private, no-store`, each chunk SHA-256 and the complete SHA-256 before creating a renderable URI. Display is bounded to 5 MiB, thumbnail to 512 KiB. Thumbnail responses carry the display dimensions per the server contract. Only host-created blob/file URIs reach the renderer; public bearer URLs and data URIs are rejected. The default is thumbnail with two concurrent downloads, a queue bound of 128 and a 32 MiB byte cache (bounded configuration up to 64 MiB). Each cache use first rechecks current server status/authority. LRU eviction, permission failure, version/app/account closure and late URI creation revoke resources. Already-decoded pixels in a mounted component require the root permission callback to unmount the app immediately.

Native files use a random per-scope folder under the app cache. A new process clears prior ephemeral media folders; disposal deletes the current scope's files. Files are temporary private app-cache material, not durable recovery. Durable original bytes stay in the encrypted host entries. No raw filenames, originals, base64, URLs or broker error messages are logged by this module.

## Dependency and verification boundaries

`expo-image-picker ~58.0.10` was installed with the official `expo install` command. The plugin declares photo selection text, preserves the existing flashlight camera permission message and disables microphone permission. It does not invoke an OS dialog during development. References: [Expo ImagePicker](https://docs.expo.dev/versions/latest/sdk/imagepicker/) and [Expo FileSystem](https://docs.expo.dev/versions/latest/sdk/filesystem/). The Web picker intentionally avoids the SDK's Web implementation because that implementation decodes selected images before returning their File.

The focused 50 groups exercise bounded byte IO, strict DTOs, all three unknown/malformed mutation ACKs, reopening, local commit uncertainty, concurrent upload reservations, changed versions/forms, read integrity, scope races, preview isolation and wrapper delegation. The full isolated snapshot passes 278 client tests, TypeScript, Expo lint and owned-file formatting. Host Web/iOS/Android exports pass; a separate temporary entry explicitly importing this new wrapper and UI also bundles for all three platforms. These are source, fake transport/DOM and JavaScript bundle proofs. They do not claim live Appwrite media, OS picker permission, device cache/encryption, image worker or native compilation proof. The prior custom-module native compile predates this dependency; final source needs a fresh CNG/native build after root integration.
