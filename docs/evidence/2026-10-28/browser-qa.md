# Manual browser verification by origin

Date: October 28, 2026. Target: exported React Native web client, initially at `http://127.0.0.1:8426` and then at `http://localhost:8426`, connected to the Appwrite development deployment identified in the [evidence index](README.md).

The task operator completed this flow in a real browser and inspected the resulting rendered screen. This is a manual observation receipt, separate from the automated REST smoke suite.

## Phase 1 — registered IP hostname

At `http://127.0.0.1:8426`, while that web hostname was registered:

1. Registered a synthetic QA account through the Appwrite-backed client, then created a workspace and app.
2. Chose a template, customized its title and field labels, saved draft 1, reviewed it, and published version 1.
3. Created a live record and edited it through the client.

## Phase 2 — final localhost registration

After removing the redundant IP-host web registration, the flow continued at `http://localhost:8426`:

1. Added optional boolean field “Keep for later”, saved draft 2, reviewed and published version 2, and confirmed the existing record remained.
2. Edited that record to set the new boolean to true.
3. Fully reloaded `http://localhost:8426/apps/6ae22797002eeef2b3c5`. The client restored its session and rendered published version 2 with the persisted edited record.
4. Signed out, signed in again as the same synthetic user, and reopened the app. Published version 2 and the same edited values remained visible.

The final screen showed these synthetic values:

| Field          | Observed value                                 |
| -------------- | ---------------------------------------------- |
| Record title   | A woven idea, revised                          |
| Note           | Edited and persisted through the live function |
| Topic          | Ideas                                          |
| Keep for later | Yes                                            |

The web platform registration uses `localhost`; Android and Apple registrations use `com.tinkerloom.app`. The redundant IP-host web registration was removed to keep these three registrations within the Free development limit.

The QA password stayed in memory, and no credentials are included in this receipt. This flow verifies the exercised browser UI, session, compatible schema evolution, and persistence paths. It does not verify Xcode/Gradle compilation, native installation/device sessions, full accessibility, full AppNest parity, or production behavior.
