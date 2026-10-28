# iPhone AI prompt investigation — 2026-09-24

[Documentation index](README.md) · [Mobile contract](MOBILE_FEATURES.md) · [AI setup](AI_SETUP.md) · [Verification record](VERIFICATION.md)

This is a historical investigation, not a current runtime or device report.
The job IDs, provider responses, build results, and availability observations
below belong to 2026-09-24. Consult [AI setup](AI_SETUP.md) for current source
configuration and [development](DEVELOPMENT.md) for runtime-control rules.

The signed iPhone build included the mobile component contract, but the running
development backend still served an older contract. Its authenticated template
catalog listed only Project Hub, Photo Journal, Habit Tracker, Daily Planner,
Reading, Chores and Volunteer; it omitted Notes, Reminders, Calendar, Clock & Focus
and Phone Toolkit from the current source.

The Phone Toolkit example reached the configured AI provider successfully. All
three responses returned HTTP 200, but the running backend rejected each during
AppSpec validation. The terminal diagnostic was `Unsupported AppSpec format
version`. Subsequent creation attempts while this job was running received the
then-existing one-generation-at-a-time quota error. Current source permits
independent users' generations to overlap; the one-active-job-per-user quota
remains. This was not a phone text-input failure or a missing provider credential.

Using the source's provider adapter at the time, the same public Phone
Toolkit example passed on its first attempt. The returned definition passed
`AppSpec.parse` and `validateGeneratedExperience`, with a device-information
view, flashlight, brightness, keep-awake and haptic controls, two pages, and no
record collections or record actions. No private records or device readings were
sent. The direct provider check alone did not establish connected browser or
iPhone acceptance; the subsequent browser checks below found another failure.

The backend was initially left running because repository instructions reserve
startup to the user. After the user explicitly requested the restart, only the
identified `local.appnest.dev` job was restarted with its existing configuration
and database. Existing failed jobs were not automatically replayed.

The launcher also retains accepted AI creation handles for the current session
and exposes **Resume build**, scoped to the selected workspace. Resuming refreshes
the existing draft through the authenticated builder endpoint without creating
another app or submitting another AI request. This makes running and failed
requests reachable after leaving the builder; it is not cross-session draft
discovery.

Validation: all 29 launcher recovery tests passed, including six new regression
cases for resuming a failed build at phone width, preserving the handle after a
network failure, stale and denied draft handling, and publication cleanup.
Workspace static analysis passed. The signed iOS release build and deep/strict
code-signature verification passed. Installation could not proceed because the
paired iPhone was unavailable. The later backend fix was active without requiring
that frontend update. Physical iPhone generation and control behavior remain
unverified.

## Connected browser check

The local release web app was rebuilt and loaded at `http://localhost:8182/`.
The Phone Toolkit starter populated the complete prompt and **Create app**
submitted one request. Leaving with Back showed **Resume build**; resuming
reopened the same running request without another begin/generate call.

Before the restart, the backend still returned the old seven-template catalog. Browser job
24 failed on three attempts: AppSpec validation, invalid JSON, then output
truncation. The browser showed **Let's try that again** and **Build details**
identified the 8,000-token limit. No app was published.

After the authorized restart, the backend catalog included the five new utility
starters. Browser retry job 25 still failed after three attempts, ending with
`Unknown behavior flashlight`. Thus the outdated backend was not the only issue:
the model sometimes confused native device controls with record behaviors.

The correction made the provider contract explicitly separate those concepts,
require empty collections/actions/automations for device-only apps, and include
a compact public device-view fragment rather than a starter fallback. Record guidance is
scoped to apps that store records. Invalid behavior bindings still fail strict
validation, but diagnostics now identify the action, expected behavior type and
collection, and explain that phone controls belong in device views. All 81
AppSpec tests and 24 provider tests passed; workspace analysis and diff checks
passed. No validation rules were relaxed.

After restarting with this correction, the same browser request (job 26)
reached `preview ready` on attempt 1 with no validation error. The visible
Phone Toolkit preview contained information and controls tabs. In the simulated
preview, flashlight and keep-awake switches changed to on; brightness changed
from 50% to 60% and **Restore brightness** returned it to 50%. The haptic preview
button was available and clickable; browser testing does not prove physical
haptics. Device-information cards were explicitly labeled simulated. The draft
was left unpublished for review. Its current availability was not rechecked.
This establishes the tested browser creation and preview flow, not universal
generation reliability or native-device acceptance.
