# AppNest NVIDIA model evaluation: post-hoc offline compiler-assisted diagnostic

Snapshot: 2026-10-08T10:22:38.092014Z (blocked). Run: `e7cd449878d1973a1e973cee86dcaa68dd2030325283fb0006b8c085121bb84a`.

Input checkpoint SHA256: `9f83e60ae88fe28d3e30da0102deb4ea69dadcd973ae8bafb638ee34c9f3f771`.

Fresh-create saved responses only; primary scores and source were not changed. All scored source hashes match the checkpoint manifest. No live calls were made.

Saved fresh-create responses only. Replays production required-capability closure and creation checks, then the fixed benchmark assertions. Operation acceptance means at least one observed response passes; response rates exclude transport attempts with no saved response and are not independent trials. Post-hoc diagnosis is not a replacement run: original repair attempts were conditioned on strict-parser diagnostics. No authenticated save, Flutter rendering, reminders, publication, or device behavior is verified.

Observed response attempts: 25; transport attempts without a response excluded: 54.

Strict raw full means strict parsing plus production checks and fixed feature assertions. Compiler full adds only supported missing capability declarations, then applies the same checks.

| Model | Saved response attempts | Strict schema | Compiler schema | Compiler + production checks | Strict raw full | Compiler full |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| moonshotai/kimi-k3 | 9 | 8/9 (88.9%) | 8/9 (88.9%) | 8/9 (88.9%) | 7/9 (77.8%) | 7/9 (77.8%) |
| z-ai/glm-5.3 | 16 | 14/16 (87.5%) | 15/16 (93.8%) | 15/16 (93.8%) | 11/16 (68.8%) | 12/16 (75.0%) |
| deepseek-ai/deepseek-v4.1-flash | 0 | 0/0 (unknown%) | 0/0 (unknown%) | 0/0 (unknown%) | 0/0 (unknown%) | 0/0 (unknown%) |

Operation denominator includes all planned creations; terminal counts expose incomplete snapshots. Acceptance means any observed attempt passes.

| Model | Terminal/planned operations | Strict schema | Compiler schema | Compiler + production checks | Strict raw full | Compiler full | Primary scored |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| moonshotai/kimi-k3 | 12/12 | 8/12 (66.7%) | 8/12 (66.7%) | 8/12 (66.7%) | 7/12 (58.3%) | 7/12 (58.3%) | 7/12 (58.3%) |
| z-ai/glm-5.3 | 12/12 | 12/12 (100.0%) | 12/12 (100.0%) | 12/12 (100.0%) | 11/12 (91.7%) | 11/12 (91.7%) | 11/12 (91.7%) |
| deepseek-ai/deepseek-v4.1-flash | 12/12 | 0/12 (0.0%) | 0/12 (0.0%) | 0/12 (0.0%) | 0/12 (0.0%) | 0/12 (0.0%) | 0/12 (0.0%) |

| Model | Case | Attempt | Strict parse | Compiler | Production checks | Scenario assertions | Remaining diagnostic |
| --- | --- | ---: | --- | --- | --- | --- | --- |
| moonshotai/kimi-k3 | create-notes-fields | 3 | true | true | true | true |  |
| z-ai/glm-5.3 | create-notes-fields | 1 | true | true | true | true |  |
| moonshotai/kimi-k3 | create-notes-appearance | 1 | true | true | true | true |  |
| z-ai/glm-5.3 | create-notes-appearance | 1 | true | true | true | true |  |
| moonshotai/kimi-k3 | create-reminders-timing | 1 | true | true | true | true |  |
| z-ai/glm-5.3 | create-reminders-timing | 1 | true | true | true | true |  |
| moonshotai/kimi-k3 | create-reminders-name | 1 | true | true | true | false | Make the reminder timestamp optional and editable in add/edit forms. |
| moonshotai/kimi-k3 | create-reminders-name | 2 | false | false | false | false | output_json: The AI response was not valid JSON. Return exactly one complete JSON object without commentary or markdown. |
| z-ai/glm-5.3 | create-reminders-name | 1 | true | true | true | false | Make the reminder timestamp optional and editable in add/edit forms. |
| z-ai/glm-5.3 | create-reminders-name | 2 | true | true | true | true |  |
| moonshotai/kimi-k3 | create-calendar-category | 1 | true | true | true | true |  |
| z-ai/glm-5.3 | create-calendar-category | 1 | false | false | false | false | Choose an approved theme and icon |
| z-ai/glm-5.3 | create-calendar-category | 2 | true | true | true | true |  |
| moonshotai/kimi-k3 | create-calendar-appearance | 3 | true | true | true | true |  |
| z-ai/glm-5.3 | create-calendar-appearance | 1 | true | true | true | true |  |
| moonshotai/kimi-k3 | create-focus-duration | 1 | true | true | true | true |  |
| z-ai/glm-5.3 | create-focus-duration | 1 | false | true | true | true |  |
| z-ai/glm-5.3 | create-focus-duration | 2 | true | true | true | true |  |
| moonshotai/kimi-k3 | create-focus-clock | 1 | true | true | true | true |  |
| z-ai/glm-5.3 | create-focus-clock | 1 | true | true | true | true |  |
| z-ai/glm-5.3 | create-rich-dashboard | 1 | true | true | true | true |  |
| z-ai/glm-5.3 | create-multistep-form | 1 | true | true | true | false | Expose private image upload, timestamp, multiline caption, rating and favorite controls. |
| z-ai/glm-5.3 | create-multistep-form | 3 | true | true | true | false | Expose private image upload, timestamp, multiline caption, rating and favorite controls. |
| z-ai/glm-5.3 | create-shared-workflow | 1 | true | true | true | true |  |
| z-ai/glm-5.3 | create-capacity-signup | 1 | true | true | true | true |  |

Capability additions are recorded per attempt in the JSON artifact.
