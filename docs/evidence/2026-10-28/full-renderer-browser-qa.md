# Full semantic renderer browser checkpoint — October 28, 2026

Tested the exported React Native web bundle at `http://localhost:8426`, using
the mounted `/miniapps` routes and the isolated preview adapter. This is
**browser + synthetic in-memory runtime evidence**, not live Appwrite actions,
private media, delivered reminders, native/device controls or full acceptance.

The gallery decoded and displayed all12 canonical original positive templates.
The same renderer has explicit branches for all21 view types,8 field types,
7 action types and3 policies. Mounted interaction here covered only the
following scenarios; source/helper coverage is a separate layer.

- Daily Planner: created a task with High priority and timestamp
  `2026-10-28T19:30:00.123456Z`. Today summary changed from2 to3, Open1 to2,
  and the task appeared at the expected local time. Its workflow transition
  changed Open2/Done1 to Open1/Done2. Reopening the editor preserved the exact
  microsecond timestamp and record revision2.
- Dirty navigation: edited a task, attempted Close app, confirmed the discard
  dialog; Keep editing retained the input. Explicit Discard changes returned
  to the gallery.
- Volunteer Shifts: Join shift changed both collection views from0/4 to1/4,
  showed own-claim state, disabled a second claim and enabled release. Setting
  capacity0 was definitively rejected without changing allocation. Review
  values allowed correction to1; release changed both views to0/1. Reload
  reset isolated sample state to0/4.
- Record details: browser testing found that configured details could omit
  their record title. The renderer now shows its bound title; a fresh bundle
  reload displayed Community morning as the details heading.
- Project Hub: mounted declared page tabs, banner and board;6 loaded records
  and complete preview column counts Open3/Done3 appeared. Drag gestures
  were not exercised; equivalent transition buttons remain available.

[Mounted Project Hub screenshot](full-renderer-preview.jpg). The screenshot
is a bounded visual receipt, not proof of cloud persistence or concurrency.

Root checks passed: TypeScript, Expo lint,174 client tests, Prettier and
web/iOS/Android bundle exports. After the last save-recovery wording cleanup,
TypeScript/lint were rerun and formatting/all three exports refreshed. These
exports are not Xcode/Gradle builds. Native final-source builds and actual
installation remain pending, as do mounted checks for the remaining views,
small/large-text/keyboard/screen-reader layouts, external browser Back,
authenticated live adapters and durable host recovery.
