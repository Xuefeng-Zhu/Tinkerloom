# Rich records browser verification

Date: October 28, 2026. Client: exported React Native web bundle at `http://localhost:8426`, using Appwrite development deployment `6ae23803828d45b4fdf7`. The final client includes Unicode acknowledgement fix `c564983`.

This is a manual browser observation receipt. The REST smoke reports and unit tests are separate evidence. All accounts and values used here are synthetic QA data; passwords stayed in memory.

1. Opened the isolated Planner preview, verified civil-date agenda groups, numeric zero, and the Undated group. Changed its layout to a table locally; its sample rows remained isolated.
2. Signed up a fresh project user through the client and created a workspace and app `6ae239170025b9919abd`.
3. Selected the Planner structure, saved draft 1, reviewed its agenda layout and Planned date binding, then published version 1. The live app was empty; the three preview sample rows were not copied.
4. Entered a record with zero minutes and invalid `2027-02-29`. The editor rejected the date while retaining the inputs. Replacing it with valid `2028-02-29` saved successfully, showing zero in the agenda.
5. Created another record with blank optional date/minutes. It appeared under Undated with empty cells, separately from zero.
6. Saved, reviewed, and published table version 2. Both records and their values remained visible.
7. After rebuilding with the Unicode fix, entered a title surrounded by U+0085, `2000-02-29`, and `-12.5` minutes. The save was confirmed, the title displayed as `Unicode title QA`, and the negative fraction remained visible. The separate REST suite sent raw U+0085 values and verified exact receipt replay.
8. Fully reloaded the app, then signed out and signed in again. Published version 2 and all three records, including zero, blank values, and the Unicode/negative record, remained visible.
9. At a temporary 390 × 844 browser viewport, the table stayed within the page: `innerWidth`, root scroll width, and body scroll width were all 390. Horizontal scrolling remained inside the table. The viewport override was then reset.
10. Created eight additional labelled QA records. The table's first page showed ten loaded rows and Load more records; loading the next page showed eleven unique Edit controls, including Pagination QA 8, and no further Load more control.
11. Saved, reviewed, and published agenda version 3. The initial page again showed ten loaded records. Load more fetched the eleventh record, correctly grouping `2029-01-08` and keeping Undated last. The DOM showed eleven unique Edit controls and no further page control. Agenda sorting did not change the server cursor.

The final visible state identified published version 3 and eleven loaded records. The [final screenshot](rich-records-browser.jpg) captures the header and first date group; it does not show every row simultaneously. The QA session was signed out before handoff.

This verifies the exercised browser forms, publication, table/agenda rendering, persistence, and one ten-record page boundary. It does not establish native compilation/device behavior, full accessibility, exhaustive timezone/locale behavior, collection-wide sorting/calendar totals, forced lost-response recovery, or full AppNest parity.
