# Post-hoc offline compiler-assisted diagnostic

Snapshot: 2026-10-08T08:25:25.001971Z (completed). Run: `2bdf5764a25f152759f936a945d50cfbbc6c7d23e51000b56aae7fc64a32bbb1`.

Fresh-create saved responses only; primary scores and source were not changed. All scored source hashes match the checkpoint manifest. No live calls were made.

Saved fresh-create responses only. Replays production required-capability closure and creation checks, then the fixed benchmark assertions. Operation acceptance means at least one observed response passes; response rates exclude transport attempts with no saved response and are not independent trials. Post-hoc diagnosis is not a replacement run: original repair attempts were conditioned on strict-parser diagnostics. No authenticated save, Flutter rendering, reminders, publication, or device behavior is verified.

Observed response attempts: 88; transport attempts without a response excluded: 41.

Strict raw full means strict parsing plus production checks and fixed feature assertions. Compiler full adds only supported missing capability declarations, then applies the same checks.

| Model | Saved response attempts | Strict schema | Compiler schema | Strict raw full | Compiler full |
| --- | ---: | ---: | ---: | ---: | ---: |
| nvidia/nemotron-3.5-lightning-30b-a3b | 33 | 2/33 (6.1%) | 6/33 (18.2%) | 1/33 (3.0%) | 1/33 (3.0%) |
| nvidia/nemotron-3-super-120b-a12b | 28 | 13/28 (46.4%) | 16/28 (57.1%) | 6/28 (21.4%) | 7/28 (25.0%) |
| nvidia/nemotron-3-ultra-550b-a55b | 18 | 8/18 (44.4%) | 12/18 (66.7%) | 7/18 (38.9%) | 10/18 (55.6%) |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | 9 | 0/9 (0.0%) | 0/9 (0.0%) | 0/9 (0.0%) | 0/9 (0.0%) |

Operation denominator includes all planned creations; terminal counts expose incomplete snapshots. Acceptance means any observed attempt passes.

| Model | Terminal/planned operations | Strict schema | Compiler schema | Strict raw full | Compiler full | Primary scored |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| nvidia/nemotron-3.5-lightning-30b-a3b | 12/12 | 2/12 (16.7%) | 4/12 (33.3%) | 1/12 (8.3%) | 1/12 (8.3%) | 1/12 (8.3%) |
| nvidia/nemotron-3-super-120b-a12b | 12/12 | 9/12 (75.0%) | 10/12 (83.3%) | 6/12 (50.0%) | 6/12 (50.0%) | 6/12 (50.0%) |
| nvidia/nemotron-3-ultra-550b-a55b | 12/12 | 7/12 (58.3%) | 8/12 (66.7%) | 7/12 (58.3%) | 8/12 (66.7%) | 7/12 (58.3%) |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | 12/12 | 0/12 (0.0%) | 0/12 (0.0%) | 0/12 (0.0%) | 0/12 (0.0%) | 0/12 (0.0%) |

| Model | Case | Attempt | Strict parse | Compiler | Production checks | Scenario assertions | Remaining diagnostic |
| --- | --- | ---: | --- | --- | --- | --- | --- |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-notes-fields | 1 | false | true | true | false | On a reachable record view such as noteList, set titleFieldId:"title" and filterFieldIds:["category"]. The search control requires BOTH view.titleFieldId referencing the existing text title and view.filterFieldIds:[EXISTING_CATEGORY_FIELD_ID]. Include views.configured.v1 in requires; do not create another title or category field. |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-notes-fields | 2 | false | false | false | false | list options: unknown properties controls |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-notes-fields | 3 | false | false | false | false | list options: unknown properties controls |
| nvidia/nemotron-3-super-120b-a12b | create-notes-fields | 1 | false | false | false | false | Unsupported required capabilities: "interactive.v1". Use only capability names listed in the AppSpec schema requires enum. |
| nvidia/nemotron-3-super-120b-a12b | create-notes-fields | 2 | false | false | false | false | list options: unknown properties presentation |
| nvidia/nemotron-3-super-120b-a12b | create-notes-fields | 3 | false | true | true | false | On a reachable record view such as notesList, set titleFieldId:"title" and filterFieldIds:["category"]. The search control requires BOTH view.titleFieldId referencing the existing text title and view.filterFieldIds:[EXISTING_CATEGORY_FIELD_ID]. Include views.configured.v1 in requires; do not create another title or category field. |
| nvidia/nemotron-3-ultra-550b-a55b | create-notes-fields | 2 | true | true | true | true |  |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-notes-appearance | 1 | false | true | true | false | Include the category field in the reachable add and edit forms. |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-notes-appearance | 2 | false | false | false | false | Form noteForm must remove the control for workflow-managed field category; change its state through the workflow action. |
| nvidia/nemotron-3-super-120b-a12b | create-notes-appearance | 1 | false | false | false | false | list options: unknown properties presentation |
| nvidia/nemotron-3-super-120b-a12b | create-notes-appearance | 2 | true | true | true | true |  |
| nvidia/nemotron-3-ultra-550b-a55b | create-notes-appearance | 2 | true | true | true | true |  |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create-notes-appearance | 1 | false | false | false | false | Unsupported field type |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create-notes-appearance | 2 | false | false | false | false | Unsupported field type |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create-notes-appearance | 3 | false | false | false | false | Unsupported field type |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-reminders-timing | 1 | false | true | true | false | Include one owner inbox reminder rule for open tasks. |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-reminders-timing | 2 | false | true | true | false | Include one owner inbox reminder rule for open tasks. |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-reminders-timing | 3 | true | true | true | false | Include one owner inbox reminder rule for open tasks. |
| nvidia/nemotron-3-super-120b-a12b | create-reminders-timing | 1 | false | true | true | false | Include one owner inbox reminder rule for open tasks. |
| nvidia/nemotron-3-super-120b-a12b | create-reminders-timing | 2 | true | true | true | true |  |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create-reminders-timing | 3 | false | false | false | false | AppSpec: unknown properties unsupported |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-reminders-name | 1 | false | false | false | false | AppSpec: unknown properties notifications, explicitRequirements |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-reminders-name | 2 | false | false | false | false | AppSpec: unknown properties notifications |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-reminders-name | 3 | false | false | false | false | AppSpec: unknown properties notifications |
| nvidia/nemotron-3-super-120b-a12b | create-reminders-name | 1 | true | true | true | true |  |
| nvidia/nemotron-3-ultra-550b-a55b | create-reminders-name | 3 | false | true | true | true |  |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-calendar-category | 1 | false | false | false | false | Field required must be boolean |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-calendar-category | 2 | false | false | false | false | Field required must be boolean |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-calendar-category | 3 | false | false | false | false | Field required must be boolean |
| nvidia/nemotron-3-super-120b-a12b | create-calendar-category | 1 | false | false | false | false | Choose an approved theme and icon |
| nvidia/nemotron-3-super-120b-a12b | create-calendar-category | 2 | false | false | false | false | Choose an approved theme and icon |
| nvidia/nemotron-3-super-120b-a12b | create-calendar-category | 3 | false | false | false | false | Choose an approved theme and icon |
| nvidia/nemotron-3-ultra-550b-a55b | create-calendar-category | 1 | true | true | true | true |  |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create-calendar-category | 3 | false | false | false | false | AppSpec: unknown properties unsupported |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-calendar-appearance | 1 | false | false | false | false | Field required must be boolean |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-calendar-appearance | 2 | false | false | false | false | Field required must be boolean |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-calendar-appearance | 3 | false | false | false | false | Field required must be boolean |
| nvidia/nemotron-3-super-120b-a12b | create-calendar-appearance | 1 | false | false | false | false | Choose an approved theme and icon |
| nvidia/nemotron-3-super-120b-a12b | create-calendar-appearance | 2 | false | false | false | false | Choose an approved theme and icon |
| nvidia/nemotron-3-super-120b-a12b | create-calendar-appearance | 3 | false | false | false | false | Choose an approved theme and icon |
| nvidia/nemotron-3-ultra-550b-a55b | create-calendar-appearance | 2 | false | true | true | true |  |
| nvidia/nemotron-3-ultra-550b-a55b | create-calendar-appearance | 3 | true | true | true | true |  |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create-calendar-appearance | 2 | false | false | false | false | AppSpec: unknown properties unsupported |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create-calendar-appearance | 3 | false | false | false | false | AppSpec: unknown properties unsupported |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-focus-duration | 1 | false | false | false | false | Choose an approved tab icon |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-focus-duration | 2 | false | false | false | false | Choose an approved tab icon |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-focus-duration | 3 | false | false | false | false | Choose an approved theme and icon |
| nvidia/nemotron-3-super-120b-a12b | create-focus-duration | 1 | false | true | true | true |  |
| nvidia/nemotron-3-super-120b-a12b | create-focus-duration | 2 | true | true | true | true |  |
| nvidia/nemotron-3-ultra-550b-a55b | create-focus-duration | 1 | false | true | true | true |  |
| nvidia/nemotron-3-ultra-550b-a55b | create-focus-duration | 2 | true | true | true | true |  |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create-focus-duration | 3 | false | false | false | false | output_json: The AI response was not valid JSON. Return exactly one complete JSON object without commentary or markdown. |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-focus-clock | 1 | false | false | false | false | Choose an approved tab icon |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-focus-clock | 3 | true | true | true | true |  |
| nvidia/nemotron-3-super-120b-a12b | create-focus-clock | 1 | true | true | true | true |  |
| nvidia/nemotron-3-ultra-550b-a55b | create-focus-clock | 1 | true | true | true | true |  |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-rich-dashboard | 1 | false | false | false | false | Form activityForm field minutes has type integer, but control text requires text. |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-rich-dashboard | 2 | false | false | false | false | Form activityForm field minutes has type integer, but control text requires text. |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-rich-dashboard | 3 | false | false | false | false | Form activityForm field minutes has type integer, but control text requires text. |
| nvidia/nemotron-3-super-120b-a12b | create-rich-dashboard | 1 | true | true | true | false | Show the requested total-minutes target, daily 14-period line chart and checklist. |
| nvidia/nemotron-3-super-120b-a12b | create-rich-dashboard | 2 | false | false | false | false | list options: unknown properties presentation |
| nvidia/nemotron-3-super-120b-a12b | create-rich-dashboard | 3 | true | true | true | false | Show the requested total-minutes target, daily 14-period line chart and checklist. |
| nvidia/nemotron-3-ultra-550b-a55b | create-rich-dashboard | 1 | false | false | false | false | Choose an approved theme and icon |
| nvidia/nemotron-3-ultra-550b-a55b | create-rich-dashboard | 2 | false | false | false | false | Choose an approved theme and icon |
| nvidia/nemotron-3-ultra-550b-a55b | create-rich-dashboard | 3 | false | false | false | false | Choose an approved theme and icon |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-multistep-form | 1 | false | false | false | false | Field required must be boolean |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-multistep-form | 2 | false | false | false | false | Field required must be boolean |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-multistep-form | 3 | false | false | false | false | Field required must be boolean |
| nvidia/nemotron-3-super-120b-a12b | create-multistep-form | 1 | true | true | true | false | Expose private image upload, timestamp, multiline caption, rating and favorite controls. |
| nvidia/nemotron-3-super-120b-a12b | create-multistep-form | 2 | true | true | true | false | Expose private image upload, timestamp, multiline caption, rating and favorite controls. |
| nvidia/nemotron-3-super-120b-a12b | create-multistep-form | 3 | true | true | true | false | Expose private image upload, timestamp, multiline caption, rating and favorite controls. |
| nvidia/nemotron-3-ultra-550b-a55b | create-multistep-form | 1 | false | true | true | false | Expose private image upload, timestamp, multiline caption, rating and favorite controls. |
| nvidia/nemotron-3-ultra-550b-a55b | create-multistep-form | 2 | true | true | true | false | Expose private image upload, timestamp, multiline caption, rating and favorite controls. |
| nvidia/nemotron-3-ultra-550b-a55b | create-multistep-form | 3 | true | true | true | true |  |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | create-multistep-form | 3 | false | false | false | false | list options: unknown properties presentation |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-shared-workflow | 1 | false | false | false | false | list options: unknown properties groupByFieldId |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-shared-workflow | 2 | false | false | false | false | list options: unknown properties groupByFieldId |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-shared-workflow | 3 | false | false | false | false | list options: unknown properties groupByFieldId |
| nvidia/nemotron-3-super-120b-a12b | create-shared-workflow | 1 | false | false | false | false | Form taskForm field effort has type integer, but control text requires text. |
| nvidia/nemotron-3-super-120b-a12b | create-shared-workflow | 2 | true | true | true | true |  |
| nvidia/nemotron-3-ultra-550b-a55b | create-shared-workflow | 2 | false | false | false | false | Form taskForm field effort has type integer, but control text requires text. |
| nvidia/nemotron-3-ultra-550b-a55b | create-shared-workflow | 3 | false | false | false | false | Form taskForm field effort has type integer, but control text requires text. |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-capacity-signup | 1 | false | false | false | false | list options: unknown properties query |
| nvidia/nemotron-3.5-lightning-30b-a3b | create-capacity-signup | 3 | false | false | false | false | Unknown field status |
| nvidia/nemotron-3-super-120b-a12b | create-capacity-signup | 1 | false | false | false | false | Unknown field assignee |
| nvidia/nemotron-3-super-120b-a12b | create-capacity-signup | 2 | true | true | true | false | Expose shift list, capacity summary, configure, join and release controls. |
| nvidia/nemotron-3-super-120b-a12b | create-capacity-signup | 3 | true | true | true | false | Expose shift list, capacity summary, configure, join and release controls. |
| nvidia/nemotron-3-ultra-550b-a55b | create-capacity-signup | 1 | false | false | false | false | Grouped summaries need a choice field |

Capability additions are recorded per attempt in the JSON artifact.
