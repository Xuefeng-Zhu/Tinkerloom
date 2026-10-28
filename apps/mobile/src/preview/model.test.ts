import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { previewTemplates } from "./catalog";
import {
  addPreviewRecord,
  createPreviewSession,
  customizePreview,
  resetPreviewSession,
  updatePreviewRecord,
  validateDefinition,
  validateValues,
  isCivilDate,
  NUMBER_LIMIT,
  parseNumericInput,
} from "./model";
import type { Definition, Values } from "./model";
import { canonicalText } from "./canonicalText";

interface RichContract {
  baseDefinition: Definition;
  validDefinitions: { name: string; input: Definition; expected: Definition }[];
  invalidDefinitions: { name: string; input: Definition }[];
  validValues: {
    name: string;
    definition?: Definition;
    input: Values;
    expected: Values;
  }[];
  invalidValues: { name: string; input: Values }[];
}
const richContract = JSON.parse(
  readFileSync(
    new URL(
      "../../../../appwrite_backend/test/fixtures/rich_contract.json",
      import.meta.url,
    ),
    "utf8",
  ),
) as RichContract;

function template(id: string) {
  const found = previewTemplates.find((item) => item.id === id);
  assert.ok(found, `Missing template ${id}`);
  return found;
}

test("preview rejects invalid choices, unknown fields, and missing required titles", () => {
  const definition = template("reading").definition;
  assert.throws(
    () =>
      validateValues(definition, { title: "A book", status: "Not a choice" }),
    /available/,
  );
  assert.throws(
    () => validateValues(definition, { title: "A book", privileged: true }),
    /unknown field/,
  );
  assert.throws(() => validateValues(definition, { title: "   " }), /required/);
  assert.throws(
    () => validateValues(definition, { title: "A book", author: true }),
    /must be text/,
  );
});

test("separate preview sessions never share record or definition mutation", () => {
  const first = createPreviewSession(template("tasks"));
  const second = createPreviewSession(template("tasks"));
  const changed = updatePreviewRecord(first, first.records[0].id, {
    ...first.records[0].values,
    done: true,
  });
  const renamed = customizePreview(changed, "Our weekend", {
    title: "Next step",
  });
  assert.equal(renamed.records[0].values.done, true);
  assert.equal(first.records[0].values.done, false);
  assert.equal(second.records[0].values.done, false);
  assert.equal(renamed.definition.fields[0].id, first.definition.fields[0].id);
  assert.equal(second.definition.title, "A little progress");
  assert.equal(template("tasks").definition.fields[0].label, "Task");
});

test("reset removes new local records and customizations and restores samples", () => {
  const initial = createPreviewSession(template("notes"));
  const edited = customizePreview(
    addPreviewRecord(initial, { title: "My new note" }),
    "My notes",
    { title: "Heading" },
  );
  const reset = resetPreviewSession(edited);
  assert.equal(reset.definition.title, initial.definition.title);
  assert.equal(reset.definition.fields[0].label, "Title");
  assert.deepEqual(reset.records, initial.records);
  assert.equal(reset.nextId, 1);
});

test("record update cannot invent identities and boolean inputs are checked", () => {
  const session = createPreviewSession(template("tasks"));
  assert.throws(
    () => updatePreviewRecord(session, "missing", { title: "Task" }),
    /no longer/,
  );
  assert.throws(
    () => addPreviewRecord(session, { title: "Task", done: "true" }),
    /on or off/,
  );
  const next = addPreviewRecord(session, { title: "  Take a break  " });
  assert.equal(next.records.at(-1)?.values.title, "Take a break");
  assert.equal(next.records.at(-1)?.values.done, false);
});

test("definition validation rejects unstable identities and unsupported fields", () => {
  const definition = template("notes").definition;
  assert.throws(
    () =>
      validateDefinition({
        ...definition,
        fields: [definition.fields[0], definition.fields[0]],
      }),
    /unique/,
  );
  assert.throws(
    () => validateDefinition({ ...definition, primaryFieldId: "body" }),
    /primary field/,
  );
});

test("shared Dart/TypeScript rich-definition fixtures agree on views and field kinds", () => {
  for (const scenario of richContract.validDefinitions) {
    assert.doesNotThrow(
      () => validateDefinition(scenario.input),
      scenario.name,
    );
    assert.doesNotThrow(
      () => validateDefinition(scenario.expected),
      scenario.name,
    );
    const session = createPreviewSession({
      id: scenario.name,
      caption: "Fixture",
      definition: scenario.input,
      samples: [],
    });
    assert.deepEqual(
      session.definition.view,
      scenario.expected.view,
      scenario.name,
    );
    assert.equal(
      Object.prototype.hasOwnProperty.call(session.definition, "view"),
      Object.prototype.hasOwnProperty.call(scenario.expected, "view"),
      scenario.name,
    );
    if (scenario.input.view) {
      assert.notEqual(session.definition.view, scenario.input.view);
      assert.notEqual(session.definition.view, session.source.definition.view);
    }
  }
  for (const scenario of richContract.invalidDefinitions) {
    assert.throws(
      () => validateDefinition(scenario.input),
      { name: "PreviewValidationError" },
      scenario.name,
    );
  }
});

test("shared Dart/TypeScript values preserve zero and dates while rejecting coercions", () => {
  for (const scenario of richContract.validValues) {
    assert.deepEqual(
      validateValues(
        scenario.definition ?? richContract.baseDefinition,
        scenario.input,
      ),
      scenario.expected,
      scenario.name,
    );
  }
  for (const scenario of richContract.invalidValues) {
    assert.throws(
      () => validateValues(richContract.baseDefinition, scenario.input),
      { name: "PreviewValidationError" },
      scenario.name,
    );
  }
});

test("numbers reject nonfinite values and exact bounds apply to required fields", () => {
  for (const value of [
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.NEGATIVE_INFINITY,
    NUMBER_LIMIT + 1,
    -NUMBER_LIMIT - 1,
  ]) {
    assert.throws(
      () =>
        validateValues(richContract.baseDefinition, {
          title: "Item",
          amount: value,
        }),
      /finite number/,
    );
  }
  const required: Definition = {
    ...richContract.baseDefinition,
    fields: richContract.baseDefinition.fields.map((field) =>
      field.id === "amount" ? { ...field, required: true } : field,
    ),
  };
  assert.equal(
    validateValues(required, { title: "Item", amount: 0 }).amount,
    0,
  );
  assert.equal(
    validateValues(required, { title: "Item", amount: NUMBER_LIMIT }).amount,
    NUMBER_LIMIT,
  );
  assert.equal(
    validateValues(required, { title: "Item", amount: -NUMBER_LIMIT }).amount,
    -NUMBER_LIMIT,
  );
  assert.throws(
    () => validateValues(required, { title: "Item", amount: "" }),
    /required/,
  );
  assert.throws(() => validateValues(required, { title: "Item" }), /required/);
});

test("civil dates reject rollover, whitespace, timestamps and non-Gregorian leap days", () => {
  for (const value of [
    "0001-01-01",
    "0004-02-29",
    "2000-02-29",
    "2400-02-29",
    "9999-12-31",
  ])
    assert.equal(isCivilDate(value), true, value);
  for (const value of [
    "0000-01-01",
    "1900-02-29",
    "2100-02-29",
    "2024-04-31",
    "2024-01-01\n",
    "2024-01-01Z",
    " 2024-01-01",
    20240101,
    null,
  ])
    assert.equal(isCivilDate(value), false, String(value));
});

test("numeric form conversion is decimal-only and never turns blank into zero", () => {
  for (const value of ["", " ", "\n\t"])
    assert.equal(parseNumericInput(value), "");
  assert.equal(parseNumericInput("0"), 0);
  assert.equal(parseNumericInput("-0"), 0);
  assert.equal(parseNumericInput(" 12.75 "), 12.75);
  assert.equal(parseNumericInput("-.5"), -0.5);
  assert.equal(parseNumericInput(String(NUMBER_LIMIT)), NUMBER_LIMIT);
  for (const value of [
    "NaN",
    "Infinity",
    "1e3",
    "0x10",
    "1,000",
    "1_000",
    "+1",
    "1.",
    String(NUMBER_LIMIT + 1),
  ])
    assert.throws(
      () => parseNumericInput(value),
      { name: "PreviewValidationError" },
      value,
    );
});

test("canonical text matches Dart Unicode whitespace and BOM without altering interior text", () => {
  const codes = [
    0x09,
    0x0a,
    0x0b,
    0x0c,
    0x0d,
    0x20,
    0x85,
    0xa0,
    0x1680,
    ...Array.from({ length: 11 }, (_, index) => 0x2000 + index),
    0x2028,
    0x2029,
    0x202f,
    0x205f,
    0x3000,
    0xfeff,
  ];
  for (const code of codes) {
    const whitespace = String.fromCodePoint(code);
    assert.equal(
      canonicalText(`${whitespace}Title${whitespace}`),
      "Title",
      `U+${code.toString(16)}`,
    );
  }
  assert.equal(
    canonicalText("\u0085First\u0085Second\u0085"),
    "First\u0085Second",
  );
  assert.equal(canonicalText("\u200bTitle\u200b"), "\u200bTitle\u200b");
  assert.equal(canonicalText("\u180eTitle\u180e"), "\u180eTitle\u180e");
});

test("record text and choices trim NEL while civil dates remain strict", () => {
  const definition: Definition = {
    title: "Notes",
    description: "",
    primaryFieldId: "title",
    fields: [
      { id: "title", label: "Title", kind: "text", required: true },
      { id: "body", label: "Body", kind: "longText" },
      {
        id: "category",
        label: "Category",
        kind: "choice",
        options: ["\u0085Blue\u0085", "Gold"],
      },
      { id: "when", label: "Date", kind: "date" },
    ],
  };
  assert.deepEqual(
    validateValues(definition, {
      title: "\u0085Title\u0085",
      body: "\u0085Line\u0085inside\u0085",
      category: "\u0085Blue\u0085",
      when: "2024-02-29",
    }),
    {
      title: "Title",
      body: "Line\u0085inside",
      category: "Blue",
      when: "2024-02-29",
    },
  );
  assert.throws(
    () => validateValues(definition, { title: "\u0085" }),
    /required/,
  );
  assert.throws(
    () =>
      validateValues(definition, {
        title: "Title",
        when: "\u00852024-02-29\u0085",
      }),
    /valid date/,
  );
  assert.throws(
    () => validateDefinition({ ...definition, title: "\u0085" }),
    /required/,
  );
});
