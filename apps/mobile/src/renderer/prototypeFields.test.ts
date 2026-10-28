import assert from "node:assert/strict";
import test from "node:test";
import { decodeAppSpec } from "../spec/decode";
import { normalizeRecordValues } from "../spec/values";
import { ownValue } from "../spec/ownValue";
import { matchingRecords, aggregateRecords } from "../runtime/query";
import { PreviewRuntimeAdapter } from "../runtime/preview";
import type { RuntimeRecord } from "../runtime/types";
import {
  displayField,
  initialEditorValues,
  normalizedEditorData,
  recordTitle,
} from "./model";
const spec = decodeAppSpec({
  formatVersion: 1,
  name: "Valid data names",
  theme: "teal",
  icon: "book",
  requires: [
    "collections.v1",
    "views.list.v1",
    "views.details.v1",
    "views.form.v1",
    "records.create.v1",
    "records.patch.v1",
  ],
  collections: [
    {
      id: "items",
      label: "Items",
      fields: [
        {
          id: "constructor",
          label: "Constructor",
          type: "text",
          required: false,
        },
        { id: "toString", label: "To string", type: "text", required: false },
        {
          id: "hasOwnProperty",
          label: "Own value",
          type: "number",
          required: false,
        },
      ],
      behaviors: [],
    },
  ],
  views: [
    {
      id: "list",
      type: "list",
      label: "Items",
      collectionId: "items",
      titleFieldId: "constructor",
      actionIds: [],
    },
    {
      id: "details",
      type: "details",
      label: "Details",
      collectionId: "items",
      actionIds: [],
    },
    {
      id: "form",
      type: "form",
      label: "Editor",
      collectionId: "items",
      actionIds: ["create", "patch"],
    },
  ],
  actions: [
    {
      id: "create",
      label: "Create",
      collectionId: "items",
      capability: "records.create.v1",
    },
    {
      id: "patch",
      label: "Patch",
      collectionId: "items",
      capability: "records.patch.v1",
    },
  ],
  policyPresetRequest: "personalTracker.v1",
  automationRequests: [],
});
const collection = spec.collections[0];
function record(id: string, data: RuntimeRecord["data"]): RuntimeRecord {
  return {
    id,
    collectionId: collection.id,
    data,
    revision: 1,
    writtenUnderVersionId: "version",
    capacity: null,
    allocated: null,
    claimed: false,
    allowedActions: [],
  };
}
test("optional prototype-named fields stay absent in details/title/form and query boundaries, supplied values remain usable", () => {
  const absent = record(
      "absent",
      JSON.parse(JSON.stringify(normalizeRecordValues(collection, {}))),
    ),
    present = record(
      "present",
      normalizeRecordValues(collection, {
        constructor: "A useful title",
        toString: "Actual text",
        hasOwnProperty: 0,
      }),
    );
  assert.equal(recordTitle(spec, spec.views[0], absent), "Untitled");
  assert.equal(recordTitle(spec, spec.views[0], present), "A useful title");
  for (const field of collection.fields) {
    assert.equal(ownValue(absent.data, field.id), undefined);
    assert.equal(
      displayField(field, ownValue(absent.data, field.id)),
      "Not set",
    );
  }
  assert.equal(
    displayField(
      collection.fields[2],
      ownValue(present.data, "hasOwnProperty"),
    ),
    "0",
  );
  assert.deepEqual(initialEditorValues(collection.fields, absent), {
    constructor: null,
    toString: null,
    hasOwnProperty: null,
  });
  assert.deepEqual(initialEditorValues(collection.fields, present), {
    constructor: "A useful title",
    toString: "Actual text",
    hasOwnProperty: "0",
  });
  assert.deepEqual(normalizedEditorData(collection.fields, {}), {
    constructor: null,
    toString: null,
    hasOwnProperty: null,
  });
  const rows = [absent, present];
  assert.deepEqual(
    matchingRecords(collection, rows, {
      filters: [{ fieldId: "constructor", operator: "eq", value: null }],
    }).map((r) => r.id),
    ["absent"],
  );
  assert.deepEqual(
    matchingRecords(collection, rows, {
      filters: [{ fieldId: "toString", operator: "contains", value: "Actual" }],
    }).map((r) => r.id),
    ["present"],
  );
  assert.deepEqual(
    matchingRecords(collection, rows, {
      sort: [{ fieldId: "hasOwnProperty", descending: true }],
    }).map((r) => r.id),
    ["present", "absent"],
  );
  assert.equal(
    aggregateRecords(
      collection,
      rows,
      {},
      { metric: "sum", fieldId: "hasOwnProperty" },
      "version",
    ).value,
    0,
  );
});
test("preview round trips preserve valid prototype-named values without inherited field data or invoking accessors", async () => {
  const adapter = new PreviewRuntimeAdapter(spec, { records: { items: [{}] } });
  const initial = await adapter.query("items", {});
  assert.equal(
    recordTitle(spec, spec.views[0], initial.records[0]),
    "Untitled",
  );
  const outcome = await adapter.execute({
    appId: adapter.appId,
    versionId: adapter.versionId,
    operationId: "create_valid_names",
    actionId: "create",
    input: {
      data: { constructor: "Real", toString: "A note", hasOwnProperty: 0 },
    },
  });
  const saved = await adapter.get(outcome.recordId!);
  assert.equal(ownValue(saved.data, "toString"), "A note");
  assert.equal(ownValue(saved.data, "hasOwnProperty"), 0);
  assert.equal(
    (
      await adapter.query("items", {
        filters: [{ fieldId: "constructor", operator: "eq", value: null }],
      })
    ).total,
    1,
  );
  let invoked = 0;
  const accessor = Object.defineProperty({}, "constructor", {
    get() {
      invoked++;
      throw new Error("must not run");
    },
  });
  assert.equal(ownValue(accessor, "constructor"), undefined);
  assert.equal(invoked, 0);
  adapter.dispose();
});
