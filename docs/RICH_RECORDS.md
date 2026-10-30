# Rich records: numbers, civil dates, and views

Tinkerloom's bounded declarative model now supports numeric and civil-date records and optional list, table, or agenda presentation. The same field definitions are used in the local preview, builder, client validation, trusted Appwrite Function, and published records. This document describes the bounded engine rather than the full AppSpec runtime.

## Define and use a small planner

The template shelf includes **A little plan**, with a planned date, numeric minutes, completion state, and notes. The builder can add optional number/date fields to existing apps and select a presentation view. Template samples remain in the local preview; choosing a template saves its structure, and publication starts with the app's own live records.

```json
{
  "title": "A little plan",
  "description": "Give each next step a date, or leave space for later.",
  "primaryFieldId": "title",
  "fields": [
    { "id": "title", "label": "Plan", "kind": "text", "required": true },
    { "id": "day", "label": "Planned date", "kind": "date" },
    { "id": "minutes", "label": "Minutes", "kind": "number" },
    { "id": "done", "label": "Completed", "kind": "boolean" }
  ],
  "view": { "kind": "agenda", "dateFieldId": "day" }
}
```

Save a draft, review its exact revision, and publish it before creating live records. Appwrite retains the original request/operation ID for safe retries. Changing a presentation view still goes through draft saving and explicit publication; it does not change the existing record values or field identities.

## Typed value contract

| Field                | Accepted                                                                                                  | Rejected                                                                                                     |
| -------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `number`             | A finite JSON number in the inclusive range −1e15 to +1e15; zero and negative/fractional values are valid | Numeric strings such as `"12"`, booleans, non-finite values, and numbers outside the bound                   |
| `date`               | Exactly `YYYY-MM-DD`, using ASCII digits, Gregorian month lengths/leap years, and years 0001–9999         | Year 0000, a February 29 in a non-leap year, whitespace, timestamps, timezone offsets, and parser rollover |
| Optional number/date | Missing or `""`, normalized to `""`                                                                       | `null`; a blank required value                                                                               |

A civil date represents a calendar day, not an instant. The service does not attach a timezone or convert it to a UTC timestamp. February 29 is valid in years divisible by 400, or divisible by 4 but not by 100. Input parsing never repairs an impossible day by rolling it into the next month.

Numbers are bounded general numeric values; this does not add an exact decimal-money type or currency arithmetic. The existing 16 KiB encoded JSON limits for definitions and record values remain in force in addition to per-field bounds.

## Presentation contract

The `view` property is optional:

- `{ "kind": "list" }` uses the list presentation.
- `{ "kind": "table" }` uses the table presentation.
- `{ "kind": "agenda", "dateFieldId": "day" }` groups records by the referenced civil-date field, including an undated group when that optional field is empty.

Agenda requires `dateFieldId` to reference an existing field whose kind is `date`. The date field itself may be optional. List and table must omit `dateFieldId`. Unknown properties, unsupported kinds, missing agenda references, and references to non-date fields are rejected.

The table and agenda render only the records already loaded by the client, including any additional pages explicitly loaded. They are not whole-database aggregates, a complete calendar query, or a full calendar scheduling system. Pagination remains ten records per backend page. A visible group count must not be interpreted as the total number of matching records in the database.

An absent `view` stays absent in the normalized/canonical definition rather than gaining an implicit default. This preserves legacy definition bytes and command-receipt identity. Presentation view changes are compatible; destructive field changes remain blocked. Existing field IDs, types, requiredness, choices, and the required text primary field retain their earlier compatibility rules. Newly added fields must be optional to publish over existing records.

## Verification checkpoint

The backend passed 22 check groups, including 52 shared fixture cases in [rich_contract.json](../appwrite_backend/test/fixtures/rich_contract.json): 18 definition cases and 34 value cases. Dart and TypeScript consume that same fixture, including U+0085 trimming for titles, labels, choice options, and text/long-text/choice values while preserving descriptions. This keeps normalized request acknowledgments and exact receipt retries consistent across languages; date values still reject surrounding whitespace. Direct language-level checks also cover `NaN`/infinity, numeric boundaries, Gregorian century rules, encoded byte limits, legacy receipt replay, and compatible publication with old records. After the Unicode acknowledgment fix, the client passed 54 tests, TypeScript, lint, and formatting. The full client verification, including web/iOS/Android JavaScript exports, passed again after the Unicode fix. These are bundle checks, not native builds or device acceptance.

The preserved rich-records REST smoke passed **33 checks and 305 assertions** against the isolated free Appwrite development project. The later Unicode normalization REST smoke retains those checks and passed **34 checks and 314 assertions**, including real U+0085 record normalization and exact replay. These reports verify real account/session and Function operations, private-table denial, tenant isolation, stale/concurrent write behavior, receipts, compatible rich publication, numeric/date persistence, invalid input preservation, and fresh-session persistence. These reports do not establish browser interactions, native builds/device behavior, forced transport-response loss, or full AppNest feature acceptance. The separate rich browser receipt records live Planner publication, strict date input, zero/negative/blank values, Unicode confirmation, reload/fresh-session persistence, table/agenda publication, and a ten-to-eleven-record pagination boundary. It also records a contained table at 390-pixel browser width; this is responsive web evidence, not a native-device test.

| Deployment receipt              | Value                                                              |
| ------------------------------- | ------------------------------------------------------------------ |
| Project                         | `6ae1928a003a65851e95`                                             |
| Endpoint                        | `https://sfo.cloud.appwrite.io/v1`                                 |
| Database/function               | `tinkerloom` / `tinkerloom-core`                                   |
| Backend commit                  | `2f5a9dd`                                                          |
| Active deployment at checkpoint | `6ae23803828d45b4fdf7`                                             |
| Uploaded archive SHA-256        | `098c5ed6908a3e45f5b388e6c3131041dfaf8501fba5dbe1dbf65cc166b07420` |

The report records the public target and test observations; the deployment ID and archive hash are the separate upload/deployment receipt associated with that checkpoint. See the evidence index for preserved earlier successes and the original failed report.


Verification records are preserved in the [evidence directory](evidence/).
