import assert from "node:assert/strict";
import test from "node:test";
import type { Definition, Values } from "../preview/model";
import { prepareRecordValues } from "./recordInputs";

const definition: Definition = {
  title: "Plan",
  description: "Dates and quantities",
  primaryFieldId: "title",
  fields: [
    { id: "title", label: "Title", kind: "text", required: true },
    { id: "amount", label: "Amount", kind: "number" },
    { id: "day", label: "Day", kind: "date" },
  ],
};

test("save converts numeric text only at submission and preserves blanks", () => {
  const inputs: Values = {
    title: "Book a table",
    amount: "0",
    day: "2026-11-03",
  };
  assert.deepEqual(prepareRecordValues(definition, inputs), {
    title: "Book a table",
    amount: 0,
    day: "2026-11-03",
  });
  assert.equal(inputs.amount, "0");
  assert.equal(
    prepareRecordValues(definition, { title: "Later", amount: "", day: "" })
      .amount,
    "",
  );
  assert.equal(
    prepareRecordValues(definition, {
      title: "Refund",
      amount: "-12.5",
      day: "",
    }).amount,
    -12.5,
  );
});

test("unfinished, nonfinite, or oversized number inputs do not submit", () => {
  for (const amount of [
    "-",
    "1.",
    "1e2",
    "Infinity",
    "1000000000000001",
    true,
    Number.NaN,
  ]) {
    assert.throws(() =>
      prepareRecordValues(definition, { title: "Test", amount, day: "" }),
    );
  }
});

test("date input is validated as exact civil text, without trimming or rollover", () => {
  for (const day of [
    "2026-2-01",
    "2026-02-29",
    "2026-11-03 ",
    " 2026-11-03",
    "0000-01-01",
  ]) {
    assert.throws(() =>
      prepareRecordValues(definition, { title: "Test", amount: "", day }),
    );
  }
  assert.equal(
    prepareRecordValues(definition, {
      title: "Leap day",
      amount: "",
      day: "2000-02-29",
    }).day,
    "2000-02-29",
  );
});
