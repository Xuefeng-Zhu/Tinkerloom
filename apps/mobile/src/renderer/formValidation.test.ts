import assert from "node:assert/strict";
import test from "node:test";
import { fullTemplates } from "../full/catalog";
import { AppSpecError } from "../spec/errors";
import { normalizeFieldValue } from "../spec/values";
import type { FieldSpec } from "../spec/types";
import { RuntimeError } from "../runtime/errors";
import type { RuntimeRecord } from "../runtime/types";
import {
  editorFields,
  initialEditorValues,
  editorValidation,
  normalizedEditorData,
  FieldValidationError,
  editorIssueTarget,
  firstEditorIssueTarget,
} from "./model";

test("Photo Journal empty first-step title yields a structured inline issue and exact first-step focus target", () => {
  const spec = fullTemplates.find(
    (template) => template.id === "photoJournal",
  )!.spec;
  const view = spec.views.find((view) => view.type === "form")!;
  const fields = editorFields(spec, view),
    values = initialEditorValues(fields);
  const before = structuredClone(values),
    visible = fields.filter((field) =>
      view.options!.steps![0].fieldIds.includes(field.id),
    );
  const result = editorValidation(visible, values, view.options?.controls);
  assert.equal(result.issues.length, 1);
  const issue = result.issues[0];
  assert.ok(issue instanceof FieldValidationError);
  assert.ok(issue instanceof AppSpecError);
  assert.equal(issue.fieldId, "title");
  assert.equal(issue.fieldLabel, "Title");
  assert.equal(issue.detail, "This field is required.");
  assert.deepEqual(
    firstEditorIssueTarget(result.issues, view.options!.steps!),
    {
      fieldId: "title",
      label: "Title",
      detail: "This field is required.",
      step: 0,
    },
  );
  assert.deepEqual(values, before);
});

test("final-save focus follows earliest invalid step while visible control order breaks ties", () => {
  const fields: FieldSpec[] = [
    { id: "late", label: "Later number", type: "number", required: true },
    { id: "first", label: "First title", type: "text", required: true },
    { id: "second", label: "Second title", type: "text", required: true },
  ];
  const result = editorValidation(fields, {
    late: "bad",
    first: "",
    second: "",
  });
  assert.deepEqual(
    result.issues.map((issue) => issue.fieldId),
    ["late", "first", "second"],
  );
  const steps = [{ fieldIds: ["first", "second"] }, { fieldIds: ["late"] }];
  assert.equal(firstEditorIssueTarget(result.issues, steps)?.fieldId, "first");
  assert.equal(firstEditorIssueTarget(result.issues, steps)?.step, 0);
  assert.equal(
    firstEditorIssueTarget(
      result.issues.filter((issue) => issue.fieldId !== "first"),
      steps,
    )?.fieldId,
    "second",
  );
});

test("only local structured field errors request focus; generic/late server text is never parsed for identifiers", () => {
  const steps = [{ fieldIds: ["title"] }];
  assert.equal(
    editorIssueTarget(Error("This field is required (title)"), steps),
    null,
  );
  assert.equal(
    editorIssueTarget(
      new RuntimeError("invalid_values", "Title is required (title)"),
      steps,
    ),
    null,
  );
  assert.equal(
    editorIssueTarget(
      { fieldId: "title", detail: "server-shaped error" },
      steps,
    ),
    null,
  );
  assert.equal(editorIssueTarget(undefined, steps), null);
  assert.equal(firstEditorIssueTarget([], steps), null);
  assert.equal(
    editorIssueTarget(
      new FieldValidationError("__capacity", "Capacity", "Use a whole number."),
      steps,
      2,
    )?.step,
    2,
  );
});

test("the normalizing API keeps domain error code/path/message compatibility while adding field metadata", () => {
  const field: FieldSpec = {
    id: "title",
    label: "Title",
    type: "text",
    required: true,
  };
  let original: unknown;
  try {
    normalizeFieldValue(field, null);
  } catch (error) {
    original = error;
  }
  assert.ok(original instanceof AppSpecError);
  let wrapped: unknown;
  try {
    normalizedEditorData([field], { title: null });
  } catch (error) {
    wrapped = error;
  }
  assert.ok(wrapped instanceof FieldValidationError);
  assert.ok(wrapped instanceof AppSpecError);
  assert.equal(wrapped.code, original.code);
  assert.equal(wrapped.path, original.path);
  assert.equal(wrapped.message, original.message);
  assert.equal(wrapped.fieldId, "title");
});

test("validation collects all field issues without mutating controlled text or discarding valid false/zero/unset values", () => {
  const fields: FieldSpec[] = [
    { id: "amount", label: "Amount", type: "number", required: false },
    { id: "done", label: "Done", type: "boolean", required: false },
    { id: "note", label: "Note", type: "text", required: false },
    { id: "whole", label: "Whole", type: "integer", required: true },
    { id: "at", label: "Time", type: "timestamp", required: false },
  ];
  const values = Object.freeze({
    amount: "0",
    done: false,
    note: null,
    whole: "1.5",
    at: "2030-02-30T10:00:00Z",
  });
  const result = editorValidation(fields, values);
  assert.deepEqual(result.data, { amount: 0, done: false, note: null });
  assert.deepEqual(
    result.issues.map((issue) => issue.fieldId),
    ["whole", "at"],
  );
  assert.equal(values.whole, "1.5");
  assert.equal(values.at, "2030-02-30T10:00:00Z");
  assert.match(result.issues[0].detail, /whole number/);
  assert.match(result.issues[1].detail, /valid date and time/);
});

test("unchanged stored configured ranges remain accepted and changed values produce a field-specific range issue", () => {
  const fields: FieldSpec[] = [
      { id: "rating", label: "Rating", type: "integer", required: false },
      { id: "title", label: "Title", type: "text", required: true },
    ],
    controls = [{ fieldId: "rating", control: "rating" as const }];
  const record: RuntimeRecord = {
    id: "record",
    collectionId: "entries",
    revision: 1,
    writtenUnderVersionId: "version",
    capacity: null,
    allocated: null,
    claimed: false,
    allowedActions: [],
    data: { rating: 8, title: "Original" },
  };
  const original = editorValidation(
    fields,
    { rating: "8", title: "Changed" },
    controls,
    record,
  );
  assert.equal(original.issues.length, 0);
  assert.equal(original.data.rating, 8);
  const changed = editorValidation(
    fields,
    { rating: "7", title: "Changed" },
    controls,
    record,
  );
  assert.equal(changed.issues[0].fieldId, "rating");
  assert.equal(changed.issues[0].detail, "Use a value between 1 and 5.");
});

test("valid prototype-named fields retain their own errors and values without inherited methods or false matches", () => {
  const fields: FieldSpec[] = [
    {
      id: "constructor",
      label: "Constructor note",
      type: "text",
      required: true,
    },
    { id: "toString", label: "Amount", type: "number", required: false },
    { id: "hasOwnProperty", label: "Flag", type: "boolean", required: false },
  ];
  const values = Object.assign(Object.create(null), {
    toString: "0",
    hasOwnProperty: false,
  });
  const result = editorValidation(fields, values);
  assert.equal(result.issues.length, 1);
  assert.equal(result.issues[0].fieldId, "constructor");
  assert.equal(Object.hasOwn(result.data, "constructor"), false);
  assert.equal(result.data.toString, 0);
  assert.equal(result.data.hasOwnProperty, false);
  const issues = new Map(
    result.issues.map((issue) => [issue.fieldId, issue.detail]),
  );
  assert.equal(issues.get("constructor"), "This field is required.");
});

test("repairing one controlled value changes validation results without synthesizing a request from async messages", () => {
  const fields: FieldSpec[] = [
    { id: "title", label: "Title", type: "text", required: true },
    { id: "count", label: "Count", type: "integer", required: true },
  ];
  const original = { title: "", count: "bad" },
    first = editorValidation(fields, original);
  const repaired = { ...original, title: "My retained title" },
    second = editorValidation(fields, repaired);
  assert.equal(first.issues.length, 2);
  assert.deepEqual(
    second.issues.map((issue) => issue.fieldId),
    ["count"],
  );
  assert.equal(second.data.title, "My retained title");
  assert.equal(original.title, "");
  assert.equal(editorIssueTarget(Error("count"), []), null);
});
