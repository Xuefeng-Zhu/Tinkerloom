# Click-to-edit controls

[Documentation index](README.md) · [Customization](CUSTOMIZATION.md) · [Appearance](APPEARANCE.md) · [Component settings](RICH_COMPONENTS.md)

Use **Edit** in the builder preview toolbar, then click a page heading, section,
or displayed field. The app name in the builder header opens app settings.
Desktop uses an inspector beside the preview; small screens use a scrollable
sheet with **Back to preview**. **Done editing** returns to normal preview use.

- App: name, coordinated appearance, custom accent, heading/spacing/corner
  overrides, and an approved icon. See [appearance](APPEARANCE.md) for resets and
  palette behavior.
- Page: heading, date visibility, and responsive layout. Tab labels are independent.
- Section: label, compact/cards for rich record lists, and up/down within its
  page, plus the selected component's validated options. See
  [rich components](RICH_COMPONENTS.md) and [mobile capabilities](MOBILE_FEATURES.md)
  for bindings and allowed options. Legacy definitions retain their global view
  order and are not migrated.
- Field: label everywhere that collection field appears. Values, types and IDs
  remain unchanged.

Text saves after 600 ms of inactivity or on blur. Discrete controls save
immediately. Saves use the authenticated builder patch endpoint with the latest
acknowledged mutation. Multiple pending edits to the same control coalesce;
page/view payloads are reconstructed from the acknowledged definition.

The inspector shows Saving, Saved, validation errors, or a recoverable failure.
Selection changes, leaving Edit mode, AI requests, publication and route exit
flush pending changes. Failed saves block those transitions until retry or
explicit discard. A lost response is checked against the current draft before
retrying. A different revision or unexpected definition stops the queue and
requires reloading the latest draft; local edits never silently overwrite it.

This queue saves definition edits. Record-action Saves use a different path:
after an ambiguous create response, a manual Save retry can allocate a new
command key and create a duplicate. Legacy runtime editors also have an open
access-error invalidation gap. See the [architecture review](ARCHITECTURE_REVIEW.md).
The definition queue's reconciliation behavior does not cover those operations.

Edit instrumentation is optional on `MiniAppRuntime` and ignored for live
adapters. It emits typed definition targets with collection and parent page/view
identity. Nested fields receive selection before their surrounding section;
record actions cannot execute in Edit mode. Page navigation and scrolling remain
available. Forms show selectable field representations while editing design.

Supported presentation-only patches update the existing isolated preview
adapter. They retain sample records, receipts, page location and filters. The adapter rejects patches
that change data bindings, actions or behavior. AI/schema changes still recreate
the preview. Reset sample data is unavailable during visual editing.

## Semantic patch addition

```json
{"type":"RenameField","collectionId":"books","fieldId":"title","label":"Book title"}
```

All four properties are required; extra properties, unknown collections/fields,
empty labels and labels over 160 characters are rejected. `RenameLabel` remains
backwards compatible and continues to reject ambiguous IDs. No database model,
migration, generated endpoint or authentication change is needed.

## Historical verification

Regression tests cover collection-scoped renames, schema compatibility, revision
serialization, debounce/coalescing, input validation, uncertain responses and
conflicts, retained preview records and receipts, nested selection, keyboard
activation, ignored live edit configuration, and mobile inspection at 150% text.
An authenticated PostgreSQL integration test covers persistence, revision checks,
and rejection of another user's mutation. Live-service verification is separate
from these tests and requires the running server to load the updated spec code.

On 2026-09-22, the complete spec (30), renderer (44 before the additional guarded
form test), Flutter app (52 before the additional discard-input test), and server
(30) suites passed. The added regressions were run separately after the final
edge-case fixes. Static analysis, formatting and the release web build passed.

The rebuilt local browser UI was inspected at desktop and 390×844. A synthetic
template draft named **Visual Edit Test** autosaved an app name, sage palette,
page title and date visibility; its Today tab label remained independent. The
mobile inspector was visibly verified. The old **Pocket Library Test** tab was
preserved. Neither draft was published. The backend running during that check
rejected the new field rename, so the edit was explicitly discarded; the
operation passed against the updated server in PostgreSQL integration tests.
The local server was restarted with the updated code on 2026-09-23, but a live
field-rename check was not repeated in that recorded follow-up. These dated
results do not establish which build is running now; see
[verification](VERIFICATION.md) for later evidence and
[development](DEVELOPMENT.md) before repeating a connected check.
