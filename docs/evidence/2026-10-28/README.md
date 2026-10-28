# Appwrite development verification — October 28, 2026

These are preserved sanitized reports from real REST client sessions against the isolated Appwrite development project. Synthetic QA accounts and data were left in place. The reports contain public target/resource identifiers and statuses, not passwords, cookies, JWTs, or API keys.

| Receipt                                               | Result                                                                                                              |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| [Initial live smoke](appwrite-smoke-first.json)       | 25 passed, 1 failed, 180 assertions; completed 16:42:33 UTC                                                         |
| [Corrected live smoke](appwrite-smoke-corrected.json) | 26 passed, 0 failed, 181 assertions; completed 16:48:08 UTC                                                         |
| [Manual browser QA, by origin](browser-qa.md)         | Initial sign-up/builder/records on 127.0.0.1; version 2, full reload, and sign-out/sign-in persistence on localhost |

The initial failure is retained exactly as produced. `direct_table_read_denial` expected 401/403, but Appwrite returned `404 row_not_found` for the known existing private workspace. [Appwrite documents this concealment behavior](https://appwrite.io/blog/post/build-a-permission-aware-ai-copilot#turn-permission-errors-into-answers). The corrected probe accepts only that exact 404 type after trusted creation/listing proves the row exists and also checks for no `$id`, `ownerId`, `name`, or `rows` keys at any depth. It retains 401/403 and rejects unrelated 404 types. All other live assertions are unchanged.

## Deployment identity

| Setting                  | Recorded value                                                     |
| ------------------------ | ------------------------------------------------------------------ |
| Endpoint/region          | `https://sfo.cloud.appwrite.io/v1` — SFO                           |
| Project                  | `6ae1928a003a65851e95`                                             |
| Database                 | `tinkerloom`                                                       |
| Function                 | `tinkerloom-core`                                                  |
| Active deployment        | `6ae2259d95aa17a2f1a2`                                             |
| Uploaded archive SHA-256 | `3b55fac16f249e8a3409373702d2ba556f9d9eb9276542452fd11b1b7e6a1946` |

The deployment identity and archive hash record the backend uploaded for these probes. The JSON reports identify their target but do not independently contain the deployment ID/hash. Later client/documentation changes do not change that archive receipt.

Both historical reports used origin `http://127.0.0.1:8426`. The current default and web platform setup use `http://localhost:8426` to keep one web registration alongside Android and Apple within the Free platform limit. The preserved JSON is unchanged and does not establish browser behavior at the new origin.

The passing suite demonstrates the listed REST/session/Function invariants, including live concurrency and fresh-session persistence. The separately recorded browser flow identifies which saved builder/record paths were exercised at each hostname. Native builds/device behavior, forced network-response loss, full AppNest parity, and production acceptance remain separate checks.
