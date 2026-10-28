# Rich components: connected development verification

[Documentation index](README.md) · [Component contract](RICH_COMPONENTS.md) · [Verification record](VERIFICATION.md)

Executed on 2026-09-23 UTC against the local development server at
`http://localhost:8180/` and the release web app at `http://localhost:8182/`.
All newly created data and images in this check are synthetic. Existing apps,
credentials, databases, and uncommitted builder work were retained.

This is a historical execution record. App IDs, records, process names, and
runtime responses identify the 2026-09-23 run; they do not establish their current
availability. Current setup and runtime-control rules are in
[development](DEVELOPMENT.md).

## Activation

- Fetched origin; local `main` and `origin/main` had no commits ahead or behind.
- The development database already contained the guidance, rich-media, and
  media-cleanup-recovery migrations. Restarted only the existing
  `local.appnest.dev` job with `dart run bin/main.dart --apply-migrations`.
- Startup at 05:34:14 UTC reported `Latest database migration already applied.`
  The web server listened on port 8182 and returned HTTP 200.
- Rebuilt the served release bundle with `flutter build web --no-pub
  --no-wasm-dry-run --dart-define=SERVER_URL=http://localhost:8180/
  --output ../appnest_server/web/app` from `appnest_flutter`.
- Serverpod/Dart MCP tools were unavailable. The user's local activation request
  authorized the documented CLI fallback. No production service was changed.

## Authenticated client checks

The run used the opt-in, loopback-only script from `appnest_client`:

```sh
dart run bin/rich_components_smoke.dart --run-rich-smoke
```

It signs in with the documented synthetic development accounts, creates fresh
timestamp-labelled apps, and uses public authenticated endpoints throughout.
This run's identifier was `2026-09-23T053536349127Z`.

Rerunning requires the explicitly seeded local environment and creates new
apps, records, and images. The script does not start the server. See
[development](DEVELOPMENT.md) before repeating connected checks.

| App | Executed result |
| --- | --- |
| 57, Photos | Uploaded a 720,523-byte synthetic PNG, completed sanitization, read display/thumbnail variants, published a private-image banner, saved an image record, granted viewer access and revoked it. |
| 58, Workflow | Member performed a legal workflow transition; identical receipt retry returned its outcome; stale revision and protected-field patch were rejected; a later note edit persisted. |
| 59, Metrics | Created 106 records; queried 100 + 6 cursor pages; checked count 106, sum 54, average 54/105, empty average, and three date buckets. |
| All three | Fresh authenticated clients reread definitions, records, private bytes/references and aggregate values; revoked access stayed denied. |

The script passed. It does not restart the server itself or exercise Flutter UI.

## Connected Chrome checks

Used an isolated headless Chrome context with actual email/password sign-in,
Flutter accessibility semantics, and the served release build. Desktop viewport
was 1440×1000; mobile viewport was 390×844.

| Flow | Executed result |
| --- | --- |
| Create and publish | Instantiated Photo Journal, renamed it through visual editing to **Rich UI Photo Journal 22:35:56**, reviewed and explicitly published app 60. The live app initially contained zero records. |
| Browser image upload | Selected a synthetic 320×200 PNG through the real browser file chooser. The authenticated upload completed and the image appeared in the form. |
| Multi-step save | Entered a title, advanced to caption/rating/favorite, then saved. Observed zero `runtime/execute` requests before or on Next and exactly one on Save. |
| Reload persistence | Record 156 retained its title, caption, rating 4, favorite=true and rendered private image after a full page reload. |
| Leave guard | Closing a changed form showed Keep editing / Discard. Discard left no extra record. |
| Private views | App 57 rendered the private image in cards, gallery and a static image banner. |
| Workflow keyboard | Opened app 58's Move menu with Enter and selected Move to Open with the keyboard. The card changed columns after saving. |
| Checklist and table | Sorted the Tasks table by Task; checked the workflow checklist item and observed it checked, including after a full page reload. |
| Calendar and timeline | September 22 showed exactly one record. Selecting September 23 showed zero and “No records this day.” Timeline and Undated controls were reachable. |
| Metrics and charts | App 59 displayed sum 54 of target 150, 106 matching records, line values, average-energy bars with No data for empty periods, and choice-count donut values 53/0/53. |

### Corrections found through the browser

The first image-picker attempt failed because an old Flutter release-build cache
omitted the newly added web file-selector plugin. Official `flutter clean`,
`flutter pub get`, and a fresh release build regenerated plugin registration.
The repeated browser chooser/upload then succeeded. Generated files were not
edited by hand; README documents the clean-build requirement after plugin changes.

Moving from Title to Caption exposed reused text-control state in the
accessibility DOM. Each form field subtree now has a stable field-ID key. The
regression checks distinct text-editing state and independent retained drafts.
The targeted renderer suite passed 22 tests, and the served release was rebuilt
with the fix before repeating browser verification. The complete renderer suite
then passed 85 tests. In Chrome, Caption started empty on the first advance;
after entering distinct values, Previous/Next retained both Title and Caption,
with zero business commands. Focused accessibility inputs and visible text
agreed. Flutter populates the active accessibility textarea on focus, so the
DOM assertions focus each field before inspecting its restored value. This
extra verification draft was discarded without saving.

Static analysis and formatting of the new connected smoke script passed.
Server logs from the 05:34:14 UTC restart through 05:49:36 UTC contained only
the eight intentional denial/conflict errors from the smoke tests, with no
unexpected errors. The connected browser reported no uncaught page errors.

## Captures

These screenshots show the connected development app, using synthetic images
and records rather than preview placeholders:

- [Uploaded record after reload](evidence/rich-components/live/browser-upload-reloaded-desktop.png)
- [Private gallery](evidence/rich-components/live/gallery-desktop.png)
- [Private banner on mobile](evidence/rich-components/live/banner-mobile.png)
- [Workflow table and checklist](evidence/rich-components/live/table-and-checklist-desktop.png)
- [Workflow checklist after reload](evidence/rich-components/live/workflow-reloaded-desktop.png)
- [Calendar and timeline](evidence/rich-components/live/calendar-and-timeline-desktop.png)
- [Calendar on mobile](evidence/rich-components/live/calendar-mobile.png)
- [Metric and line chart](evidence/rich-components/live/metrics-and-line-desktop.png)
- [Bar and donut charts](evidence/rich-components/live/bar-and-donut-desktop.png)
- [Charts on mobile](evidence/rich-components/live/charts-mobile.png)
- [Independent multi-step field state](evidence/rich-components/live/multistep-field-state-fixed.png)

## Scope limits

The full repository verification and initial release build are recorded in
[RICH_COMPONENTS.md](RICH_COMPONENTS.md). This connected run adds browser and
authenticated development-server evidence. It does not establish credentialed
AI generation of the new components, native device installation, a comprehensive
accessibility audit, production deployment, multi-instance operation, or
large-scale performance. Browser screenshots use normal device text scaling;
150% text coverage comes from the automated renderer tests.

The later [architecture review](ARCHITECTURE_REVIEW.md) reproduced ambiguous
create retries and legacy-renderer UI invalidation failures. Those cases were
not exercised by this dated happy-path save/reload run, and the successful
receipt retry in the client table reused the same key. The historical results
above remain evidence for their stated scenarios.
