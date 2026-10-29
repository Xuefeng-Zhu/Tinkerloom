# React Native private media integration

The authenticated full host composes polling, reminders and private media around
one encrypted child scope. Sign-out, authority changes and runtime replacement
close that scope, revoke ephemeral image resources and fence late responses.

Record forms carry the exact version, action, field, target record and revision
into uploads. The client persists encrypted upload intent before sending chunks;
unknown results require explicit recovery. Only server-confirmed ready assets
can be attached. Choosing an image does not save a record.

Unpublished author drafts use their saved revision and candidate hash locally.
An explicit existing banner selection creates an unsaved semantic edit after a
ready-status check. The normal Save action commits it. Dirty or invalid candidates
cannot attach a late upload, and no unsupported candidate hash enters the RPC.

Preview image reads happen in the authenticated host. At most 16 known saved or
broker-confirmed references are preloaded with three concurrent reads. The
isolated preview receives revocable opaque image grants and has no authenticated
transport, encrypted store, native picker or device bridge. Newly typed arbitrary
asset IDs cannot trigger private reads. Presentation changes preserve preview
records and navigation; behavior changes recreate the sandbox.

Native selection uses the Expo image-only picker and bounded reads. Android broad
storage and audio permissions are blocked; the existing camera permission remains
for explicit flashlight control. Web selection checks size before copying bytes.
Neither picker claims to sanitize originals: the private backend owns sanitization.

## Verification boundary

The 2026-10-28 integrated source passed 361 tests with no skips, TypeScript, Expo
lint with zero warnings, formatting and Web/iOS/Android exports. This includes ten
actual host integration groups and retained upload/recovery/draft/static-preview
coverage. All 28 frozen integration and static-preview file hashes were checked
before committing.

These are local source, transport and lifecycle checks. They do not establish
Cloud media delivery, native compilation of these changes, permission prompts or
device UI behavior. The subsequent bounded memory-only implementation is documented in
[src/runtime/PREVIEW_IMAGE_UPLOAD.md](../apps/mobile/src/runtime/PREVIEW_IMAGE_UPLOAD.md).
It preserves exact accepted original bytes without claiming sanitization or full
JPEG/WebP entropy decoding. The integrated suite now passes 482 tests, including
121 new image groups, plus typecheck, lint, formatting and all platform exports.


## Record-read failure and recovery presentation correction

Mounted browser testing found a record-read failure was incorrectly converted
into a private-image upload error, showing retained progress of 0/0 without an
upload. The media wrapper now preserves base runtime errors and only explicit
auth/lifecycle failures clear private cache authority. Recovery progress requires
a real positive-byte saved upload; local storage initialization failures have
their own read-only retry notice. Empty recovery wrappers and device-consent
panels for specifications requesting no device features are omitted. App-mode
radios also expose explicit web and native checked state.

Known read operations may repeat only a definite completed service409
transaction_conflict, at most three total attempts with the same immutable
request. Account and disposed guards apply to every attempt. Unknown transport
results, other errors and mutations are never automatically repeated.

All490 integrated client tests, TypeScript, lint, formatting and all platform
exports passed. Browser revalidation and the final native source delta remain
separate acceptance steps. The5f006b9 native checkpoint predates this correction.
