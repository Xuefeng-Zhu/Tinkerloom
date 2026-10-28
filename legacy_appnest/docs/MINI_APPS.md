# Rich personal mini-apps

[Documentation index](README.md) · [Architecture](../ARCHITECTURE.md) · [Component contract](RICH_COMPONENTS.md) · [Development workflow](DEVELOPMENT.md)

Daily Planner is an ordinary declarative AppSpec rendered by the shared Flutter engine. It uses the existing private app, authentication, grants, actions, publication and durable notification systems. It does not generate code or introduce a separate interactive engine.

App-owned pages and tabs take inspiration from [Tencent's global and page configuration model](https://www.tencentcloud.com/document/product/1219/61741); AppNest retains its own bounded semantic schema and trusted Flutter/Serverpod runtime.

## Daily Planner

| Page | Behavior |
| --- | --- |
| Today | Device-local date, today's Open/Done summary, scheduled tasks, separate overdue Open tasks, Add task |
| Tasks | Title search, status and priority filters, ascending due-time order, pagination, undated tasks after dated tasks |
| Progress | Database-wide Open/Done totals and completion proportions for today's scheduled tasks and all tasks |
| Task details | Notes, priority, optional due/reminder times, typed reminder state, Edit, Complete/Reopen |
| Task editor | Dedicated create/edit form with optional timestamps, clear controls and confirmation before discarding changes |

Workflow is `Open → Done → Open`. Progress describes current status; it does not claim completion dates, historical productivity, streaks or recurrence. `dueAt` and `reminderAt` are independent UTC timestamps. No reminder time is selected by default. Day filters construct local midnight and the next local midnight independently, then convert each boundary to UTC. This handles 23- and 25-hour local days. Undated tasks remain available in Tasks and all-task totals.

Mini-apps have a compact identity header with back/menu/close controls. Management actions are in the menu. App-owned bottom tabs become a navigation rail on desktop. Returning from details preserves the source tab, search, filters, loaded pages and scroll position. Navigation-enabled apps guard unsaved editor changes across tab switches, back and close, and clear private content on access errors. Unavailable records and stale definitions receive safe recoverable errors.

Legacy definitions without navigation still use a separate renderer. The
[architecture review](ARCHITECTURE_REVIEW.md#3-p2--legacy-authorization-failure-leaves-or-restores-private-ui-state)
records a confirmed limitation: its editor can remain visible, and an in-flight
read can restore content, after an access error. The backend still enforces
authorization. The review also records an
[ambiguous Save limitation](ARCHITECTURE_REVIEW.md#2-p2--save-retry-can-duplicate-a-committed-create):
retrying a create whose successful response was lost can create a duplicate.
Server receipts deduplicate a reused command key; the current UI allocates a
different key on each attempt. These findings remain open.

Authenticated locations are `/apps/<appId>/pages/<pageId>?record=<recordId>&edit=true`; `record` and `edit` are optional. Flutter web currently uses hash URLs, for example `/#/apps/42/pages/taskDetailPage?record=77`. Routes convey identity, never authority. Serverpod checks app and record access. Existing invitation links retain their token acceptance flow. Selecting a reminder resolves its record through authorized lookup before showing details.

## Authoring and compatibility

Optional `navigation` defines an entry tab, 1–5 tabs, up to 16 pages and 1–8 semantic view sections per page. A page has a title, optional local-date header and optional trusted primary action. Views configure field presentation, choice filters, bounded default queries, relative-day bindings and detail/form destinations. All IDs and collection/action references are validated. There is no arbitrary widget tree, script or expression evaluation.

Details and form views require dedicated, single-section pages outside the tabs.
List views can point to those pages with `detailPageId` and `formPageId` in the
same collection. A page's primary action must be a declared create action
reachable through a form on the page or a view's form destination.

New capability gates are `navigation.v1`, `views.configured.v1`, `notifications.owner.v1` and `automations.conditions.v1`. Query filters now include `lt`. Combined default, relative-day, search and interactive filters remain bounded by the shared eight-filter limit.

The builder's **Pages & navigation** editor offers page/section creation and ordering, titles, dates and primary actions; view fields, filters, sorting and destinations; entry page, tab labels/icons/order; and approved theme colors. The isolated preview uses the same renderer. Semantic edits include `AddPage`, `UpdatePage`, `ReorderPages`, `SetNavigation`, `UpdateView` and `SetTheme`. `AddPage` can atomically include `newViews` and a tab so trusted code allocates valid IDs in one patch. AI prompts receive these operations, the schema and capability contract. Fresh creation omits starter templates and the placeholder definition; edits receive the current definition. Generated proposals still require validation and exact-candidate publication.

Absent new properties stay absent from canonical JSON. Existing fixture hashes, immutable published definitions and record data are preserved. Navigation and presentation changes become live only through explicit publication. Preview mutations use synthetic data, isolated receipts and synthetic reminder states; they neither create live records nor schedule notifications.

## Summaries and reminders

`runtime.summary(appId, collectionId, queryJson, groupFieldId)` returns typed totals and choice counts from one authenticated transaction under the app lock. It shares query predicate compilation with record queries and aggregates every matching row, regardless of cursor or page size. Optional unset choice values contribute to the total but not a named choice count.

`runtime.reminderState(appId, recordId)` returns typed per-rule state: **unset**, **disabled**, **unenrolled**, **pending**, **delivered**, **suppressed** or **failed**, with intended time and current eligibility. `AppManifest.approvedRuleIds` exposes approved rules; older manifests can omit it. Inbox responses optionally identify the source collection/record from the existing automation run after access checks.

The planner requests a `notifyOwner` effect with the bounded condition `status == Open`. Publication must explicitly approve the rule. Enabling or changing a rule does not automatically enroll existing records: publication review separately selects an existing-record scope. The worker rechecks approval, rule generation, timestamp, condition, archive/deletion state, execution grant and recipient access under the app lock at delivery.

Explicit enrollment is durably stamped with the approved automation ID and generation in the existing outbox. It survives processing, unrelated presentation publications and initially unset reminder timestamps. It never enrolls a later changed or re-enabled rule generation.

Occurrence identity remains tied to rule generation and reminder timestamp. Notes, completion and reopening do not mint a new occurrence. Reopening before a pending occurrence executes can permit delivery. Delivered or suppressed occurrences remain terminal. Rescheduling creates a different occurrence; clearing the timestamp invalidates pending delivery. Notifications commit atomically with successful run state and deduplicate repeated wakeups. Delivery stays inside AppNest's inbox.

The original mini-app navigation release required no persistence model changes
or migrations. Its summary/reminder/inbox fields are transport definitions
generated by Serverpod. Later features, such as private media, have their own
model and migration requirements. Recurrence, external delivery, public
discovery, payments and production deployment remain outside scope.

## Evidence

The connected local browser flow was verified on 2026-09-22 after an explicitly
authorized restart: create/preview/publish, task changes, owner inbox delivery,
reminder-to-record navigation, mobile editing/filters and record URL reload.
[Live verification and its limits](VERIFICATION.md#connected-browser-verification--2026-09-22)
distinguish the real local database checks from the isolated captures below.
That run created **Daily Planner · Live check**; its current availability and
the current running build are not established by the historical check.

See [verification](VERIFICATION.md) for dated automated, build and live-runtime results. The following captures are rendered **isolated synthetic previews**, not evidence of a connected live reminder flow:

- [Today, desktop](evidence/rich-miniapps/today-desktop.png)
- [Today, mobile](evidence/rich-miniapps/today-mobile.png)
- [Tasks, mobile](evidence/rich-miniapps/tasks-mobile.png)
- [Task details, mobile](evidence/rich-miniapps/details-mobile.png)
- [Task editor, mobile](evidence/rich-miniapps/editor-mobile.png)
- [Progress, mobile](evidence/rich-miniapps/progress-mobile.png)
