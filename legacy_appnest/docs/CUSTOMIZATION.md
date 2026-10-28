# Everyday mini-app customization

[Documentation index](README.md) · [Visual editing](VISUAL_EDITING.md) · [Appearance](APPEARANCE.md) · [Mobile capabilities](MOBILE_FEATURES.md) · [Development workflow](DEVELOPMENT.md)

AppNest's core loop is describe → try → customize → use. The four showcase
definitions are Notes, Reminders, Calendar, and Clock & Focus. These are examples
of the shared declarative engine; choosing an example prompt still asks the AI
to create a fresh definition. Explicitly choosing a template starts from that
template instead.

## Authoring

Creation and follow-up edits go directly to durable generation. **Help shape my
idea** optionally asks questions. A failed edit keeps the previous preview;
**Keep previous version** dismisses the failed edit through a revision-checked
server operation. Reopening a draft restores safe job progress and the latest
request. After a lost enqueue response, the client reads the draft before
attempting another submission.

**Customize** groups appearance, content, layout, and supported behavior. On a
phone it uses a bottom sheet; on a wide builder it appears beside the preview.
Published apps also expose a Customize button. Semantic operation names remain
internal. Notes, events, and reminder items retain their stable field, record,
and page identities during customization.

`AddField` may include `viewIds` naming existing lists, tables, forms or details
in the same collection. The server allocates the new field ID and binds it to those views
atomically; a stepped form receives it in the final step. Implicit all-field
views remain implicit, including unselected stepped forms whose steps must
cover the automatically visible field. Explicit field lists retain their order
and append the new field. AI edits can therefore add a field to the list,
details and editor in one request without guessing IDs or requiring another
generation turn. Views in another collection and components without a field
display contract remain invalid targets.

**Use app** or **Apply changes** opens one review of the exact candidate. Reminder
enablement and enrollment of existing records remain explicit. The new
`UpdateReminder` semantic patch replaces the selected rule's supported
definition while preserving its ID. It does not bypass publication or enroll
old records automatically. Reminder delivery is still one-time and in-app only;
calendars display AppNest records, not the phone's calendar.

Draft enqueue and visual-edit saves reconcile uncertain responses against the
saved draft. Record-action Saves use a different path: the current renderer
allocates a new command key when a person retries after an ambiguous failure.
A committed create with a lost reply can therefore be duplicated. Legacy
definitions without navigation also have an access-error UI invalidation gap.
Both are open findings in the [architecture review](ARCHITECTURE_REVIEW.md);
the draft-recovery behavior above does not resolve them.

## Clock and timer contract

`views.clock.v1` and `views.timer.v1` are collection-free views. Utility-only
apps can have empty collections and actions; no dummy data collection is
needed. They require navigation and retain the same validation, preview, and
publication flow as record apps. Existing definitions and canonical hashes do
not change simply because these capabilities are available.

| Component | Options | Defaults |
| --- | --- | --- |
| Clock | `style`: analog/digital; `hourFormat`: system/12/24; `showSeconds`; `showDate` | Digital, system format, no seconds, date visible |
| Timer | `durationMinutes`: integer from 1 to 180 | 25 minutes |

The clock follows local device time. A running countdown stores its UTC deadline;
pause stores the remaining duration, resume establishes a new deadline, and
reset uses the current configured duration. Changing the default duration does
not restart an active countdown. Remaining time is clamped to the original
duration and zero; manual changes to system time can change the computed
remaining time. This is an in-app focus timer, not an OS alarm.

`UtilityTimerController` owns state independently of widget mounts and serializes
writes. `UtilityTimerStore` isolates persistence from rendering. The live host
injects `DeviceTimerStore`, backed by `SharedPreferencesAsync` and scoped to the
backend, signed-in account, app, and component ID. State is saved on explicit
actions rather than depending on an app termination callback. Preview uses an
independent memory store and never receives the live device store. Storage
errors are visible. Preferences support normal reopening; they are not a
critical-data durability guarantee or cross-device synchronization service.

Same-app authorized manifest refreshes retain the controller, including during
appearance changes, to avoid racing pending writes. The host disposes it when
the app closes, its scope changes, or a manifest reload fails. Saved local state
remains scoped to that account for later reopening; a renderer read error does
not erase preferences. No timer data is sent to Serverpod or the AI.

## Generation scheduling and interfaces

After committing a generation job, the server schedules a named Future Call
immediately. A ten-second reconciler recovers interrupted dispatch, due retries,
and expired leases. It schedules generation instead of waiting for a model
response. Named calls are wakeups, not deduplication keys: the job's lease,
next-attempt time, mutation, and version checks remain authoritative.

Independent apps can generate concurrently. Each app's row lock and each job's
lease fence duplicate wakeups without a global generation lock. Reconciliation
schedules up to 100 due jobs per pass, including expired leases, so recovery
does not wait for one build to finish before dispatching another. Each enqueue
and retry schedules its own wakeup.

All environments configure eight Future Call slots per server process, shared
by generation, reminders and reconciliation. Further work queues when all slots
are occupied. Model requests never run inside a database transaction. One active
job per user and 30 generation jobs per user per rolling 24 hours remain in place.
Provider request/token quotas are separate from the shared worker pool.

`BuilderSnapshot` adds `candidateReady`, `latestRequest`, `jobAttempts`,
`jobCreatedAt`, `jobUpdatedAt`, and `failureCategory`. The authenticated
`abandonFailedEdit(draftId, mutation, jobId)` endpoint accepts only the current
failed edit, preserves the candidate, and advances the draft mutation. A failed
first creation cannot promote its placeholder through this endpoint. DTOs and
Future Call transport are regenerated from authored sources; no database table
change or migration is required.

Generated candidates receive an additional reachable-interaction check.
Editable collections need usable add/edit controls; collection-free utilities
must expose a clock, timer, device-information or device-control component from
their entry page or tabs. Legacy saved definitions are not retroactively rejected
by this generation-only check.
Edits compare against the current candidate and reject newly introduced
usability failures, allowing older append-only apps to retain their behavior.
Aggregate views cannot satisfy record-edit reachability.

## Historical verification

Executed on 2026-09-23. These counts and environment limitations belong to that
run. Later mobile/iPhone evidence is recorded separately in
[mobile capabilities](MOBILE_FEATURES.md) and the
[iPhone investigation](IPHONE_AI_CHECK.md); current runtime availability is not
inferred from any earlier build or screenshot.

| Check | Result |
| --- | --- |
| `scripts/verify.sh` | Passed: workspace analysis, authored-source formatting, 505 tests and isolated two-process restart recovery |
| Specification | 76 tests passed, including unchanged legacy hashes, atomic field bindings and utility definitions |
| Renderer | 152 tests passed, including countdown persistence boundaries, corruption recovery and large-text layouts |
| Flutter app | 159 tests passed, including describe-first creation, publication review, failure recovery, rapid-tap guards and manual field visibility |
| Server | 118 tests passed, including PostgreSQL utility publication, record preservation, scheduling, cross-user generation capacity and synthetic scenario assertions |
| Web release | Passed after `flutter clean` and `flutter pub get` |
| Android release APK | Passed; compiled for the local emulator API URL, not installed on a device |
| Unsigned iOS release | Blocked before compilation: Xcode reports its required iOS 26.5 platform component is not installed |
| Synthetic captures | Mobile/desktop customization, Notes, Reminders, Calendar and clock/timer views captured |

The run recorded its workspace suite log at
`/tmp/appnest-customization-push-verify.log`; temporary logs are not repository
artifacts and may no longer be available. Local
automated tests and isolated screenshots do not establish physical-device,
connected development-server, or live-model acceptance. No updated development
runtime was activated: Serverpod/Dart MCP tools were unavailable, and no app
server was started or restarted. No reachable iPhone, Android device, or installed
simulator runtime was available for native interaction checks.

Captures: [mobile customization](evidence/customization/customization-builder-mobile.png),
[desktop customization](evidence/customization/customization-builder-desktop.png),
[mobile analog clock](evidence/customization/utility-focus-analog-390.png), and
[desktop digital clock](evidence/customization/utility-focus-digital-1440.png).

The Notes, Reminders, and Calendar starters also have synthetic renderer captures
at 390×844 and 1440×1000:

| Starter | Mobile | Desktop |
| --- | --- | --- |
| Notes | [Capture](evidence/customization/utility-notes-390.png) | [Capture](evidence/customization/utility-notes-1440.png) |
| Reminders | [Capture](evidence/customization/utility-reminders-390.png) | [Capture](evidence/customization/utility-reminders-1440.png) |
| Calendar | [Capture](evidence/customization/utility-calendar-390.png) | [Capture](evidence/customization/utility-calendar-1440.png) |

The opt-in `scripts/customization_eval.dart --live` evaluates eight synthetic
creations and eight follow-up edits through the configured provider. It starts
no app server, publishes nothing, and reads no user records. It reports provider
time, retries, schema/compatibility checks, and requested-feature fulfillment.
It does not measure server queue time or prove connected UI use. `--describe`
prints only the destination and synthetic payload manifest without making
network calls. The credentials are never printed or included in model messages.
The saved [evaluation manifest](evidence/customization/provider-eval-manifest.json)
records the destination and synthetic requests. The user approved these Nebius
requests on 2026-09-23. The [initial run](evidence/customization/provider-eval-initial.json)
accepted 5 of 8 creations and 0 of 5 attempted edits; 3 edits could not run because
their creations failed. It used weaker feature-marker assertions and retained
hashes, not candidate definitions. Those results exposed edit-envelope errors,
missing capabilities and unusable field/view linkage. Follow-up verification
uses exact scenario assertions and retains synthetic responses and definitions
for offline inspection; no user records are included.
At the close of that evaluation, outcomes were **5/8 creations and 8/8 edits**,
with three edits tested on explicit templates after creation failed. See the
[live evaluation and remaining failures](CUSTOMIZATION_AI_CHECK.md). Creation
reliability remains a product limitation.

Edit requests provide the same typed patch schema in both the system prompt
and `response_format`. The full-app output schema remains confined to creation
requests. This follows the provider's guidance to make the prompt and requested
[structured output](https://docs.tokenfactory.nebius.com/ai-models-inference/json)
agree; local validation still rejects malformed or incompatible responses.
`--cases=...` selects scenarios, and `--edits-from=<saved-report>` reuses successful
synthetic candidates for an edit-only recheck without regenerating them.

The recorded Nebius results do not establish reliability or response-format
support for another configured provider. See [AI setup](AI_SETUP.md) for the
current provider-specific contract.

Native verification requires a connected device and an API URL reachable from
that device via `--dart-define=SERVER_URL=...`. Android emulator localhost is
different from the Mac's localhost; pass `http://10.0.2.2:8180/` for a locally
configured emulator. Physical devices require a reachable LAN or HTTPS API URL.
No deployment is part of this change.

Bounded phone controls and device-information cards are now implemented in the
[mobile capabilities extension](MOBILE_FEATURES.md), with separate local access
grants. Native calendar integration, background timer alerts, and cross-device
timer synchronization remain outside this phase.
