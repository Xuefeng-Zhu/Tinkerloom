# Rich component library

[Documentation index](README.md) · [Mini-app navigation](MINI_APPS.md) · [Visual editing](VISUAL_EDITING.md) · [Development workflow](DEVELOPMENT.md)

AppNest's shared renderer supports tables, calendars, timelines, charts, metrics,
private images, formatted content, richer forms, checklists, and draggable
workflow boards. These are declarative platform components. They use the same
authenticated records, approved actions, draft review, and publication flow as
existing mini-apps.

## Authoring

Open **Pages & navigation → Views → Choose component** to browse the component
catalog. Select the collection, fields, actions, and component settings, then
attach the view to a page. The visual inspector also edits component options;
changes are saved through its existing revision-aware queue. Invalid settings
remain editable and block publication until corrected.

The AI builder receives the same schema and capability contract. It can propose
components and bind image fields, but it cannot upload images or invent private
asset identities. Upload a banner image from its editor or a record image from
the record form. Existing apps change only after explicit publication.

Three additional templates demonstrate the library:

| Template | Components |
| --- | --- |
| Project Hub | Banner, table, calendar, timeline, checklist, draggable board |
| Photo Journal | Formatted text, image cards, gallery, multi-step image form |
| Habit Tracker | Numeric metrics, target progress, date and category charts, richer controls |

New components require `navigation.v1`. Every view retains its stable identity
and declares `views.<type>.v1`; form controls/steps and draggable boards also
require `views.interactive.v1`. Image fields require `fields.image.v1`.
`formatVersion` stays 1 and absent options remain absent from canonical JSON.
Legacy definitions retain their existing renderer and hashes.

## Component behavior

| Component | Configuration and behavior |
| --- | --- |
| `table` | `fieldIds` select columns; column sorting queries the complete collection; pagination and detail navigation are retained. |
| `calendar` | `options.dateFieldId` binds a timestamp. Month badges count all matching records; selecting a day opens its paginated agenda. |
| `timeline` | `options.dateFieldId` groups records into local calendar days. Optional dates offer an Undated view. |
| `chart` | `options.style` is `bar`, `donut`, or `line`; metric is `count`, `sum`, or `average`. Numeric metrics bind `valueFieldId`. Choice groups use `groupByFieldId`; date groups use `dateFieldId`, `bucket`, and optional `periods`. |
| `metric` | Count, sum, or average with optional positive `target`. The label retains the actual value even when progress exceeds its target. |
| `imageCards`, `gallery` | Bind an image field using `options.imageFieldId`, with optional text `captionFieldId`. Each gallery item is a record. |
| `banner` | Collection-free title, body, approved tone, optional private image with description, and optional tab destination. |
| `richText` | Collection-free restricted Markdown: headings, paragraphs, emphasis, lists, quotes, and inline code. No executable HTML or external embeds. |
| `form` | Optional typed `controls` and ordered `steps`. Fields are validated before advancing; the final Save sends one create/patch command per attempt. |
| `checklist` | Boolean field plus a patch action, or a two-state workflow with explicit checked/unchecked values and reversible transitions. |
| `board` | Optional `draggable: true` plus `moveActionId`; only approved legal workflow transitions accept a move. The Move menu provides an alternative to dragging. |

Form controls include text/multiline, checkbox/switch, select/segmented choices,
slider/stepper/rating, date-time, and image upload. Sliders and steppers require
finite `min`, `max`, and positive `step`; integer fields require integral bounds
and steps. Ratings use integers from 1 to 5 and accept no custom bounds.

The form rejects newly entered or changed values outside the control's range,
including before advancing a step. An unchanged, previously stored out-of-range
value remains visible and survives an unrelated edit; using a control can
correct it without silently clamping it on display. These form ranges do not
add collection-level constraints to other authorized writes. Optional fields
preserve their unset state and provide a clear action.

Multi-step forms retain all local input and the existing unsaved-change guard.
Intermediate steps never create records. Board/checklist commands retain record
revisions, idempotency receipts, authorization, and transactional audit/outbox
writes. Reconnection does not replay a failed business command.

An ambiguous response is a separate case: if a create committed but its reply
was lost, pressing Save again currently allocates another command key and can
create a duplicate. See the open
[command retry finding](ARCHITECTURE_REVIEW.md#2-p2--save-retry-can-duplicate-a-committed-create).
Legacy definitions also have an open
[UI invalidation finding](ARCHITECTURE_REVIEW.md#3-p2--legacy-authorization-failure-leaves-or-restores-private-ui-state)
after access errors. The server's receipt and authorization checks do not by
themselves resolve these client lifecycle issues.

## Aggregation contract

`runtime.aggregate(appId, collectionId, queryJson, aggregateJson)` returns JSON:
`{total, value, groups:[{key, count, value}]}`. The renderer and isolated preview
implement the corresponding `RuntimeAdapter.aggregate` method.

The aggregate request contains `metric`, optional numeric `fieldId`, and either
choice `groupFieldId` or timestamp `dateFieldId` with explicit
`buckets:[{key,start,end}]`. At most 366 nonoverlapping UTC ranges are accepted.
The renderer constructs each local day/week/month boundary independently, so
daylight-saving changes do not turn calendar days into fixed 24-hour durations.
Date charts default to the last 30 daily periods.

All matching records contribute regardless of page size or cursor. Filters use
the existing authenticated typed query compiler. Overall totals cover the base
query; date groups cover their individual ranges. Missing numbers are excluded
from averages, empty averages are null, and empty counts/sums are zero. An empty
choice-group key denotes unset values. Numeric results use the existing double
projection. Charts display readable values alongside graphics. Donuts show
choice counts; signed numeric metrics are supported by bars and lines.

Time-series values are current records grouped by their chosen timestamp.
They do not imply stored historical snapshots or inferred completion dates.

## Private images

The `image` field stores only an opaque asset ID. The authenticated media API is:

- `beginUpload(MediaUploadRequest)` returns an asset ID and scoped upload ticket.
- `completeUpload(appId, assetId)` validates and sanitizes the stored upload.
- `readImage(appId, assetId, variant)` returns authenticated image bytes for the
  `display` or `thumbnail` variant.

Uploads accept still JPEG, PNG, or WebP images up to 5 MiB, 16 megapixels, and
8192 pixels on either side. The server inspects dimensions before decoding,
normalizes orientation, strips metadata, and produces display images up to
2048 pixels and thumbnails up to 384 pixels. The request-body transport limit
is 6 MiB; separate definition, query, and upload limits remain enforced.

Private storage is app-scoped: 500 assets and 250 MiB per app, including pending
reservations. Upload tickets expire after ten minutes. Every read checks current
app access. Builders can access draft media; ordinary app readers can access
images in the active definition or nondeleted records. Cross-app references are
rejected. Archived apps remain readable but cannot accept uploads or edits.

Media references change in the same transaction as records, drafts, and
publication. All retained immutable versions and drafts protect their images.
The reconciler removes expired pending uploads and media unreferenced for 24
hours, rechecking references under the app lock before deletion. Processing
leases and deletion states allow interrupted work to retry; original upload
bytes are removed after sanitization with recoverable accounting.

Remix copies structure and clears static image references. AI requests never
contain image bytes, filenames, storage paths, or download URLs. Previews keep
sample uploads in memory only; the builder host can inject already-authorized
banner bytes without granting the preview adapter network or storage access.

## Historical verification and runtime activation

Executed against the working tree on 2026-09-23 (UTC). The counts and activation
details below describe that run, not a check of today's runtime or GitHub CI.
Use [verification](VERIFICATION.md) for the wider evidence record and
[development](DEVELOPMENT.md) for the current workflow.

| Check | Result |
| --- | --- |
| `bash scripts/verify.sh` | Passed; analysis and authored-source formatting clean. |
| Spec tests | 52 passed, including legacy hashes, capability gates, bindings and compatibility. |
| Shared renderer tests | 84 passed in the full verification run; 85 passed after adding the browser-discovered form-field identity regression. Includes mobile/desktop at 150% text, final-only form submission, failed saves, image revocation and legacy image forms. |
| Flutter app tests | 106 passed, including authoring, cumulative inspector edits, form-step reconciliation and shared media event streams. |
| Server tests | 48 passed against embedded PostgreSQL, including aggregates over 100 records, actual binary HTTP upload, concurrent image reads, retention, quotas, revocation and cleanup recovery. |
| Independent-process restart smoke | Passed; committed runs and owner/claimant reminders recovered without duplicate delivery. |
| Release web build | Passed; `flutter build web --no-pub --dart-define=SERVER_URL=http://localhost:8180/ --output build/rich-components-web` from `appnest_flutter`. Wasm dry-run also succeeded. |

The initial optimized bundle was written to
`appnest_flutter/build/rich-components-web`. After the user requested local
activation, a fresh release build replaced `appnest_server/web/app`, and the
existing `local.appnest.dev` job was restarted with `--apply-migrations`. At
05:34 UTC the server reported the latest migration already applied and served
the updated app on port 8182. The media migrations are
`20260923044835954-rich-media` and
`20260923045124015-media-cleanup-recovery`; the earlier guidance migration and
existing uncommitted builder work are retained. Serverpod/Dart MCP tools were
unavailable, so the authorized local activation used the official CLI and the
existing macOS job.

Connected verification then passed: authenticated template creation and explicit
publication, browser image selection/upload, one final multi-step form command,
private image rendering after a full page reload, keyboard workflow movement,
checklist updates, calendar agendas, and charts. A separate authenticated client
smoke covered 106 persisted records, aggregate results, stale/forbidden commands,
private-image revocation, and fresh-login persistence. See the
[dated connected verification record](RICH_COMPONENTS_LIVE_CHECK.md) for the
exact scope, test app IDs, corrections found during browser testing, and captures.

Not executed for the new components: credentialed live AI generation, native
device installation, a full accessibility audit, or production deployment.
Run `bash scripts/verify.sh` for the reproducible automated suite; connected
development-app evidence is recorded separately from embedded-database tests.

The checked-in captures are PNGs at 390×844 and 1440×1000 with synthetic records:
[mobile calendar](evidence/rich-components/rich-calendar-390.png),
[desktop charts](evidence/rich-components/rich-charts-1440.png),
[desktop gallery](evidence/rich-components/rich-gallery-1440.png), and
[mobile form](evidence/rich-components/rich-form-390.png). They verify rendered
layout, including explicit sample-image placeholders, rather than live uploads.
