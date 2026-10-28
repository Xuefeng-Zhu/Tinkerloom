# Local verification

[Documentation index](README.md) · [Reproduce checks](DEVELOPMENT.md#verification) ·
[Requirements](REQUIREMENTS.md)

This is a dated evidence ledger. Counts, local IDs, provider names and screenshots
belong to the build and environment recorded in each entry. They do not prove
current runtime availability, provider quality, device behavior or production
readiness. Documentation edits alone do not rerun these checks.

## Evidence checkpoints

| Date / record | Executed scope | Important limit |
| --- | --- | --- |
| [2026-10-07 publication validation](#publication-validation--2026-10-07) | Full verification script: 725 tests, analysis, format and separate-process reminder recovery | Local source snapshot; known architecture findings and CI mismatch remain open |
| [2026-10-07 architecture review](ARCHITECTURE_REVIEW.md#verification-and-limits) | Static analysis; 81 spec, 259 server and 92 focused renderer tests; eight defect reproductions; live CI inspection | Focused review, not a full verification/build/browser/provider run. Six confirmed defects remain open |
| [2026-10-07 concurrent generation](REQUIREMENTS.md#concurrent-ai-generation-2026-10-07) | Full verification script: 551 tests, analysis, format and separate-process reminder recovery | Synthetic providers; no live-provider concurrency or load test |
| [2026-09-24 initial mobile check](MOBILE_FEATURES.md) | 539 tests, analysis, format, restart recovery, Android build and Swift type-checking | Initial iOS build was blocked; the later signed build is recorded separately below |
| [2026-09-24 iPhone investigation](IPHONE_AI_CHECK.md) | Launcher recovery tests, signed iOS release/signature verification, and connected AI/browser preview after fixes | Later frontend installation could not proceed; physical-device generation and controls remain unverified |
| [2026-09-23 customization](CUSTOMIZATION.md) | 505 tests, restart recovery, web/Android builds; separate [AI evaluation](CUSTOMIZATION_AI_CHECK.md) | Targeted creation/edit samples; no general success-rate or physical-device claim |
| [2026-09-23 appearance](APPEARANCE.md) | 346 tests, restart recovery, web build and isolated captures | No connected preview-to-published parity or appearance-specific live-AI acceptance |
| [2026-09-23 rich components](RICH_COMPONENTS_LIVE_CHECK.md) | Connected browser and authenticated client checks, including private media, forms, summaries, revocation and persistence | Synthetic development records; no native-device, rich-component live-AI or production claim |
| [2026-09-22 fresh AI creation](AI_CREATION_CHECK.md) | Live browser creation/publication, semantic label edit and synthetic authenticated CRUD; 123 automated tests after fixes | Failures occurred during iteration; two published examples do not establish broad reliability |
| 2026-09-22 planner and 2026-09-21 baseline, below | Historical local suites, browser captures and restart evidence | Preserve the recorded results separately from later source and known defects |

These checkpoints cover different source revisions and scopes. Do not add their
test counts together or replace an older result with a newer total. For the
current suite's commands and exclusions, use [DEVELOPMENT.md](DEVELOPMENT.md#verification).
The [architecture review](ARCHITECTURE_REVIEW.md) records current known gaps,
including CI's SDK-resolution failure.

## Publication validation — 2026-10-07

Executed in an isolated publication worktree on 2026-10-07 Pacific time
(2026-10-08 UTC). The tested source is recorded through
[`faf1077`](https://github.com/Xuefeng-Zhu/AppNest/commit/faf107710341025f371367e469de7987fc9f2f82),
including AI creation compilation/repair and numeric-control validation. Local
credentials, database files, unfinished screenshots and Xcode workspace artifacts
were excluded from the publication.

`bash scripts/verify.sh` completed with exit code zero:

| Check | Result |
| --- | --- |
| Workspace analysis | No issues |
| Authored formatting | 147 files checked; zero changes |
| AppSpec | 82 tests passed with `America/Los_Angeles` timezone |
| Renderer | 205 tests passed |
| Flutter host | 179 tests passed |
| Server | 259 tests passed against managed PostgreSQL, concurrency one |
| Restart recovery | Claimant and owner reminders recovered across independent processes; completed tasks stayed suppressed and duplicate wakeups did not resend |

Total: **725 tests**, plus the restart recovery checks. Test Insights was disabled
in the isolated configuration; PostgreSQL and reminder recovery ran successfully.
No release build, connected browser flow, live-provider call, physical-device
check or deployment was performed for this publication. The
[architecture findings](ARCHITECTURE_REVIEW.md#confirmed-findings) and committed
CI SDK mismatch remain open; this passing suite does not resolve those cases.

## Historical fresh AI creation — 2026-09-22

Real browser chat created and published **Plant Corner** and **Trip Kit** without selecting templates. Both have custom fields, app-owned tabs, dedicated forms/details and status summaries. Verified preview isolation, live create/edit, workflow transitions, mixed status proportions and a semantic AI label edit with exact hash evidence for preservation. Generation failures led to bounded parsing, prompt, edit-context and renderer fixes; the process was not uniformly successful on the first attempt. See [AI_CREATION_CHECK.md](AI_CREATION_CHECK.md) for prompts, job evidence, screenshots and limits.

After these fixes, `scripts/verify.sh` passed **123 tests** (29 spec, 40 renderer, 25 host, 29 server/provider), both process-restart scenarios, clean analysis and formatting. The release web build and Wasm compatibility dry run passed. The earlier planner-specific result below remains historical evidence of that implementation stage.

## Historical rich personal mini-apps — 2026-09-22

The Daily Planner release adds declarative pages/tabs, dedicated details/forms, authenticated locations, grouped summaries and personal inbox reminders. Source and behavior are documented in [MINI_APPS.md](MINI_APPS.md).

`bash scripts/verify.sh` completed successfully after the final code changes:

| Check | Executed result |
| --- | --- |
| Static analysis, fatal infos | No issues |
| Formatting | 110 source files checked, zero changes |
| AppSpec tests | 26 passed, including explicit DST timezone assertions |
| Renderer tests | 34 passed, including full planner navigation/edit flow at mobile and desktop sizes with 150% text and external history synchronization |
| Flutter host tests | 25 passed, including authenticated routing, publication review, manual page/view editing and browser-history stack regressions |
| PostgreSQL integration tests | 22 passed, including 7 planner-specific tests |
| Restart smoke | Both claimant and owner reminder scenarios passed across independent write/read processes |
| Release web build | `flutter build web --no-pub --dart-define=SERVER_URL=http://localhost:8180/ --output ../appnest_server/web/app` succeeded; Wasm compatibility dry run passed |

Total: **107 automated tests**, plus the process-restart checks. Test Insights remains disabled because the isolated test configuration has no service secret; the PostgreSQL tests and reminder recovery completed successfully. Generated transport code was produced with Serverpod CLI 4.0.0 and then formatted by Dart; no generated source was hand-edited.

The built web bundle is local output, not a deployment. The Wasm result is a compatibility dry run, not an executed Wasm application.

Automated coverage includes:

- Legacy canonical hashes, omitted optional properties, published record preservation, invalid view/page/action references, semantic page/tab edits, exact-candidate publication, and a deterministic AI-provider page-addition proposal.
- Preview query/workflow/receipt parity, summaries beyond a results page, exclusive local-day bounds, undated records, and explicit 23-/25-hour daylight-saving assertions in `America/Los_Angeles`.
- Preserved search/filter/pagination/scroll state, rapid tab changes, guarded edits/back/close, stale definitions, unavailable records, revoked access, read-only roles, manual page creation and legacy view editing without changing hidden predicates.
- Today → Tasks → details → editor/save → back → Progress at 390×844 and 1440×1000 with 150% text, including a mobile safe-area inset. Controls are hit-tested and layout exceptions checked. Save/error feedback floats above the bottom tabs so Progress remains immediately reachable.
- Real PostgreSQL owner reminders, complete/reopen, rescheduling/clearing, terminal delivered/suppressed occurrences, duplicate wakes, archive suppression, recipient authorization and inbox record targets.
- Durable explicit enrollment across presentation-only publication and initially unset reminder times, without inheriting approval into changed or re-enabled rule generations.
- Separate-process restart recovery for both existing claimant reminders and planner owner reminders. Completed tasks remain suppressed after reopening; duplicate wakeups do not resend notifications.

The integration lifecycle creates a draft, previews its validated definition, applies manual edits, publishes, creates tasks, completes/reopens tasks, delivers an owner reminder and resolves its authorized inbox record. Its AI proposal uses `FakeAiProvider`. It does not establish live provider quality or a connected browser flow.

Rendered synthetic preview captures were inspected with real fonts and icons at 390×844 and 1440×1000. [Today mobile](evidence/rich-miniapps/today-mobile.png), [Today desktop](evidence/rich-miniapps/today-desktop.png), [Tasks](evidence/rich-miniapps/tasks-mobile.png), [details](evidence/rich-miniapps/details-mobile.png), [editor](evidence/rich-miniapps/editor-mobile.png) and [Progress](evidence/rich-miniapps/progress-mobile.png) are PNG files at their named viewport dimensions. These captures show isolated synthetic data, not live backend delivery.

### Connected browser verification — 2026-09-22

After the user's explicit request to restart and verify, the existing `local.appnest.dev` job was restarted with its unchanged configuration and persistent database. Serverpod 4.0.0 / Dart 3.13.0 initialized at 13:44:29 UTC; ports 8180/8181/8182 resumed normally. No reseeding, credential change or database reset was performed.

Verified through the authenticated Flutter release build at `http://localhost:8182/`:

- Daily Planner template → isolated preview → manual app rename → exact-candidate publication with explicit `taskReminder` approval. The live app initially contained zero records, confirming preview data was not copied.
- Created **Daily Planner · Live check** (local app 42) and **Verify planner reminder** (record 42), with independent due time 09:00 and reminder time 06:47 in the device's America/Los_Angeles timezone.
- The reminder delivered to AppNest's inbox. Server logs show run 2 succeeded once at 13:47:30 UTC. Selecting the inbox item issued `readNotification` and opened `/apps/42/pages/taskDetailPage?record=42` after authorized lookup.
- Complete changed today's and all-task progress to 100% Done. Reopen restored Open; editing notes retained the delivered state without another completion for the same occurrence.
- Mobile editing/saving, immediately selecting Progress while the save message is visible, Open/Done and priority filters, title search, and preserved search/filter state after a details round-trip.
- Created an undated follow-up with no reminder; today's scheduled total stayed 1 while the all-task total became 2.
- Reloaded the authenticated record URL and verified persisted task fields, notes and delivered reminder state. Browser Back while editing prompted for discard; Keep editing restored the editor URL, and Discard preserved the saved notes.

Live testing exposed a browser-history defect: returning from an editor created another browser entry. The fix distinguishes forward/return/external navigation, traverses known parent entries and safely replaces direct-link fallbacks. New regression tests model actual push/replace/traversal behavior, rejected and rapid Back presses, and delayed record reads after a screen is replaced. After rebuilding, the actual browser verified Tasks → details → editor → browser Back → Keep editing → Cancel/Discard → details → browser Back → Tasks. Save → details → browser Back → Tasks and accepted browser Back followed by in-app Back also passed. Closing the mini-app returned to the launcher; opening the reminder again returned to the same task. The final inbox still contained exactly one reminder after completion/reopening and subsequent note edits. Cross-document navigation, browser refresh and closing the browser tab do not have an AppNest `beforeunload` prompt; the guarded flows are in-app and same-document navigation.

Live screenshots: [Today mobile](evidence/rich-miniapps/live/today-mobile.jpg), [task desktop](evidence/rich-miniapps/live/task-desktop.jpg), [task mobile](evidence/rich-miniapps/live/task-mobile.jpg), [filtered Tasks mobile](evidence/rich-miniapps/live/tasks-mobile.jpg), [Progress mobile](evidence/rich-miniapps/live/progress-mobile.jpg). These use synthetic test content stored in the real local development database. The JPEG captures are 1440×989 (desktop) and 390×844 (mobile); the requested desktop viewport was 1440×1000. Large-text flow coverage is separately established by the 150% widget tests; these browser captures use normal text scale.

The browser console had no warning/error entries during the inspected flows. Server stderr recorded one Relic/Serverpod `ConnectionClosed` diagnostic during stream teardown; subsequent authenticated requests and the task reopen succeeded. This is recorded as a framework teardown diagnostic, not silently counted as a clean server log. No reminder retry or duplicate completion was observed.

Serverpod/Dart MCP tools were unavailable. Official CLI generation, isolated tests, the existing local job and browser automation were used. MCP hot restart/log tails/Flutter driver checks remain unexecuted. No persistence model change or migration is required. No production deployment, version upgrade or authentication shortcut was introduced.

## Historical baseline — 2026-09-21

The results below describe the earlier release. They are retained as historical evidence, not proof of later features. The earlier “no provider” and “no host tests” notes no longer describe current source: [the AI creation check](AI_CREATION_CHECK.md) records a separate 2026-09-22 live generation check, and the host now has automated navigation/builder tests.

### Executed results at the 2026-09-21 baseline

| Command / check | Actual result |
| --- | --- |
| `serverpod generate` in appnest_server | Generated protocol, clients, Future Calls and test tools with CLI 4.0.0 |
| `dart analyze --fatal-infos` at root | No issues found |
| `dart format --output=none --set-exit-if-changed ...` using verify.sh paths | 90 source files checked, zero formatting changes |
| `dart test` in packages/appnest_spec | 7 passed |
| `flutter test` in packages/appnest_renderer | 8 passed, including reconnect/resume/duplicate invalidations and six family/viewport cases at 150% text |
| `dart test --concurrency=1` in appnest_server | 15 passed (12 runtime, 2 persistence/transaction spike, 1 official scaffold greeting) |
| `dart run scripts/restart_smoke.dart` | Two independent processes, committed run recovered, duplicate wakeup harmless, one durable notification |
| `flutter build web --dart-define=SERVER_URL=http://localhost:8180/ --output ../appnest_server/web/app` | Release build succeeded; Wasm compatibility dry run succeeded, not an actual Wasm deployment |
| `bash scripts/run-local.sh --seed-demo` | Existing secrets preserved, web build completed, migrations checked, real PostgreSQL/server/scheduler started, repeat seed completed |
| `dart run bin/local_demo.dart --accelerated-template-demo` in appnest_client | Real authenticated endpoints: one final-place winner, optional-field publication preserved claim, clients closed, reopened to one persisted notification and one successful run |

`bash scripts/verify.sh` sequences the analysis/format/spec/renderer/backend/restart checks. A test-only import placement issue and an invalid simulated Flutter lifecycle transition were fixed during the run; the reconnect test was rerun successfully. The final analyzer also treats informational diagnostics as failures. The separate test database warns that its Insights service secret is absent; Insights is disabled there, not PostgreSQL, RPC or application authentication. No test failure is being counted as a pass.

The live demo reported app 35 / version 36 / record 41 on its first successful run. IDs are local evidence, not API constants. Additional repeat demos intentionally create fresh synthetic apps.

### Browser evidence at the 2026-09-21 baseline

Inspected the actual Flutter release build in the Codex browser at 1280×720 and 390×844:

- Real Serverpod email/password sign-in as a development account.
- Personal workspace empty state and shared workspace launcher with database-backed counts.
- Three template entries and their common renderer. Created “Food pantry setup” with real form fields and capacity; four records remained after reload.
- Desktop builder with dominant isolated preview; mobile Chat / Preview / Changes tabs.
- Manual AddField “Arrival instructions”, visible diff and exact-candidate review; explicit publish returned to all four live records, with no synthetic records copied.
- Visible keyboard focus and Tab traversal from Back to Activity and reminder history.
- No warning/error console entries during the captured authenticated editing flows. Transient connection errors while the development server is deliberately stopped are not treated as application data loss.

Screenshots: [desktop home](evidence/home-desktop.png), [mobile home](evidence/home-mobile.png), [desktop runtime](evidence/runtime-desktop.png), [desktop builder](evidence/builder-desktop.png), [mobile builder](evidence/builder-mobile.png), [mobile runtime](evidence/runtime-mobile.png). Captures contain synthetic local data. Some were taken before final explanatory-copy refinements; the underlying flows were unchanged.

### Design comparison at the 2026-09-21 baseline

The frontend design skills guided a calm launcher rather than a permanent chatbot. Compared the generated [concept](design/launcher-concept.png) and real screenshots visually:

1. Preserved warm off-white canvas, white bordered surfaces, charcoal text and restrained teal primary actions.
2. Preserved left workspace/navigation rail on desktop; replaced it with clear bottom navigation at narrow widths.
3. Bundled Lora locally for the editorial headline, with readable system sans-serif control/body text.
4. Preserved the prominent description input, app tiles, small approved icon palette and template rows. Actual record counts/layout respond to real data rather than matching fictional concept counts.
5. Builder/runtime use the same restrained spacing and cards; the desktop preview is dominant, while mobile tabs avoid squeezing three columns into a phone. Full-width record cards and local-time date formatting were corrected during visual inspection.

### Not executed / remaining gates at the 2026-09-21 baseline

These were the unverified layers on that date. Later entries above establish
some local AI, host-test, private-image and Android-build evidence; production,
full accessibility and physical-device acceptance remain separate gates.

- Credentialed live AI generation and AI additive editing: no provider secrets configured. Template/manual mode and fake-provider failure tests are not substitutes for this gate.
- Public/cloud deployment, production email/Redis/shared events, hosted Insights, external storage, native signed builds and device installation.
- Full screen-reader/WCAG, cross-browser, load/performance, production retention/backup/recovery and independent security audit.
- The Flutter host's scaffold test file contains no host widget suite; renderer widgets have automated coverage and host flows were inspected in the browser. Do not infer a separate passing host test suite.

Docker's daemon was unavailable; Serverpod 4's documented embedded PostgreSQL ran successfully instead. Serverpod MCP tools were not available, so CLI generation/migrations/startup and browser inspection were used. Nothing was deployed or pushed.
