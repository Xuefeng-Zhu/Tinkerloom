import assert from "node:assert/strict";
import test from "node:test";
import { agendaGroups, displayFieldValue } from "./recordPresentation";
import type { DisplayRecord } from "./recordPresentation";

test("record cells preserve numeric zero, negative values, false, and civil dates", () => {
  assert.equal(
    displayFieldValue({ id: "n", label: "Amount", kind: "number" }, 0),
    "0",
  );
  assert.equal(
    displayFieldValue({ id: "n", label: "Amount", kind: "number" }, -2.5),
    "-2.5",
  );
  assert.equal(
    displayFieldValue({ id: "b", label: "Done", kind: "boolean" }, false),
    "No",
  );
  assert.equal(
    displayFieldValue({ id: "b", label: "Done", kind: "boolean" }, true),
    "Yes",
  );
  assert.equal(
    displayFieldValue({ id: "d", label: "Day", kind: "date" }, "0001-01-01"),
    "0001-01-01",
  );
  assert.equal(
    displayFieldValue({ id: "n", label: "Amount", kind: "number" }, ""),
    "—",
  );
});

test("agenda groups only the supplied records by exact civil date and keeps undated last", () => {
  const records: DisplayRecord[] = [
    { id: "later", values: { day: "2026-11-03" } },
    { id: "undated", values: { day: "" } },
    { id: "earlier-a", values: { day: "2026-11-02" } },
    { id: "earlier-b", values: { day: "2026-11-02" } },
    { id: "oldest", values: { day: "0001-01-01" } },
    { id: "missing", values: {} },
  ];
  const groups = agendaGroups(records, "day");
  assert.deepEqual(
    groups.map((group) => [
      group.date,
      group.records.map((record) => record.id),
    ]),
    [
      ["0001-01-01", ["oldest"]],
      ["2026-11-02", ["earlier-a", "earlier-b"]],
      ["2026-11-03", ["later"]],
      [null, ["undated", "missing"]],
    ],
  );
  assert.deepEqual(
    records.map((record) => record.id),
    ["later", "undated", "earlier-a", "earlier-b", "oldest", "missing"],
  );
  assert.equal(
    agendaGroups(records.slice(0, 1), "day").flatMap((group) => group.records)
      .length,
    1,
  );
});
