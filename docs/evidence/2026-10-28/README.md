# Appwrite development verification — October 28, 2026

These are preserved sanitized reports from real REST client sessions against the isolated Appwrite development project. Synthetic QA accounts and data were left in place. The reports contain public target/resource identifiers and statuses, not passwords, cookies, JWTs, or API keys.

| Receipt                                                              | Result                                                                                                              |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| [Initial live smoke](appwrite-smoke-first.json)                      | 25 passed, 1 failed, 180 assertions; completed 16:42:33 UTC                                                         |
| [Corrected live smoke](appwrite-smoke-corrected.json)                | 26 passed, 0 failed, 181 assertions; completed 16:48:08 UTC                                                         |
| [Manual browser QA, by origin](browser-qa.md)                        | Initial sign-up/builder/records on 127.0.0.1; version 2, full reload, and sign-out/sign-in persistence on localhost |
| [Rich-records live smoke](appwrite-smoke-rich-records.json)          | 33 passed, 0 failed, 305 assertions; completed 18:01:21 UTC; origin `http://localhost:8426`                         |
| [Unicode normalization live smoke](appwrite-smoke-rich-unicode.json) | 34 passed, 0 failed, 314 assertions; completed 18:08:59 UTC; origin `http://localhost:8426`                         |

The initial failure is retained exactly as produced. `direct_table_read_denial` expected 401/403, but Appwrite returned `404 row_not_found` for the known existing private workspace. [Appwrite documents this concealment behavior](https://appwrite.io/blog/post/build-a-permission-aware-ai-copilot#turn-permission-errors-into-answers). The corrected probe accepts only that exact 404 type after trusted creation/listing proves the row exists and also checks for no `$id`, `ownerId`, `name`, or `rows` keys at any depth. It retains 401/403 and rejects unrelated 404 types. All other live assertions are unchanged.

## Initial builder/records deployment identity

| Setting                                 | Recorded value                                                     |
| --------------------------------------- | ------------------------------------------------------------------ |
| Endpoint/region                         | `https://sfo.cloud.appwrite.io/v1` — SFO                           |
| Project                                 | `6ae1928a003a65851e95`                                             |
| Database                                | `tinkerloom`                                                       |
| Function                                | `tinkerloom-core`                                                  |
| Deployment for initial/corrected probes | `6ae2259d95aa17a2f1a2`                                             |
| Uploaded archive SHA-256                | `3b55fac16f249e8a3409373702d2ba556f9d9eb9276542452fd11b1b7e6a1946` |

The deployment identity and archive hash record the backend uploaded for these probes. The JSON reports identify their target but do not independently contain the deployment ID/hash. Later client/documentation changes do not change that archive receipt.

Both historical reports used origin `http://127.0.0.1:8426`. The current default and web platform setup use `http://localhost:8426` to keep one web registration alongside Android and Apple within the Free platform limit. The preserved JSON is unchanged and does not establish browser behavior at the new origin.

## Rich-records deployment identity

The [rich-records report](appwrite-smoke-rich-records.json) preserves the expanded suite exactly as produced: 33 checks passed, none failed or blocked, and 305 assertions passed. Its seven additional rich checks cover the legacy baseline, compatible optional number/date fields and table publication, typed record persistence and exact replay, invalid values preserving the record, agenda publication and receipt replay after view changes, invalid views preserving the draft, and cross-account denial. The later [Unicode normalization report](appwrite-smoke-rich-unicode.json) retained those checks and added `unicode_record_normalization_and_exact_replay`: it passed 34 checks and 314 assertions, with none failed or blocked. That extra real REST check verifies U+0085 text/choice normalization and exact record replay. Earlier reports remain unchanged.

| Setting                              | Recorded value                                                     |
| ------------------------------------ | ------------------------------------------------------------------ |
| Endpoint/region                      | `https://sfo.cloud.appwrite.io/v1` — SFO                           |
| Project/database/function            | `6ae1928a003a65851e95` / `tinkerloom` / `tinkerloom-core`          |
| Origin                               | `http://localhost:8426`                                            |
| Backend commit                       | `2f5a9dd`                                                          |
| Active deployment at rich checkpoint | `6ae23803828d45b4fdf7`                                             |
| Uploaded archive SHA-256             | `098c5ed6908a3e45f5b388e6c3131041dfaf8501fba5dbe1dbf65cc166b07420` |
| Exact rich report SHA-256            | `526ef6eaf76071e3c6e58ac4a0c44b48032614e80657e993e6aad7f7485b2f06` |
| Exact Unicode report SHA-256         | `0f5a92c9d640237c57774a6a307578325a9ebb5b86890ca7ac2c5f986ce624ea` |

Both rich JSON reports identify their target and observations, but do not independently contain the deployment ID, backend commit, or archive hash; those values are the separate deployment/upload receipt for this checkpoint. The rich source also passed 22 backend check groups, 52 shared definition/value fixture cases, and 54 client tests plus TypeScript, lint, and formatting after the Unicode acknowledgment fix. JavaScript bundle exports passed at the preceding rich-feature checkpoint. Those local checks are distinct from the real REST/session evidence.

Rich-feature browser QA was still ongoing when this checkpoint was recorded. The existing manual browser receipt remains evidence of the earlier builder/record flow, not proof of the new number/date/table/agenda controls. See [rich records](../../RICH_RECORDS.md) for scope and validation boundaries.

The passing suite demonstrates the listed REST/session/Function invariants, including live concurrency and fresh-session persistence. The separately recorded browser flow identifies which saved builder/record paths were exercised at each hostname. Native builds/device behavior, forced network-response loss, full AppNest parity, and production acceptance remain separate checks.

The [rich-feature browser flow](rich-browser-qa.md) separately verifies the rendered number/date/table/agenda client and one ten-to-eleven-record page boundary, including fresh-session persistence and the Unicode save correction.

## Native custom-module compilation checkpoint

The [fixed-snapshot report](native-module/README.md),
[iOS receipt](native-module/ios-receipt.json),
[Android receipt](native-module/android-receipt.json), and
[toolchain/baseline-preservation receipt](native-module/toolchain-and-preservation.json)
record successful local compilation and actual custom native class presence.
The 169-file input and CNG-transformed source hashes bind this evidence; later
full-host/final-source integration and device behavior are not established.
Earlier native and service/browser evidence remains preserved.
