import assert from "node:assert/strict";
import test from "node:test";
import { previewTemplates } from "./catalog";
import {
  addPreviewRecord,
  createPreviewSession,
  customizePreview,
  resetPreviewSession,
  updatePreviewRecord,
  validateDefinition,
  validateValues,
} from "./model";

test("preview rejects invalid choices, unknown fields, and missing required titles", () => {
  const definition = previewTemplates[2].definition;
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
  const first = createPreviewSession(previewTemplates[1]);
  const second = createPreviewSession(previewTemplates[1]);
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
  assert.equal(previewTemplates[1].definition.fields[0].label, "Task");
});

test("reset removes new local records and customizations and restores samples", () => {
  const initial = createPreviewSession(previewTemplates[0]);
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
  const session = createPreviewSession(previewTemplates[1]);
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
  const definition = previewTemplates[0].definition;
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
