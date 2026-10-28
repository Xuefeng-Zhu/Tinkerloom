import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import test from "node:test";
import {
  ACTION_CAPABILITIES,
  APP_SPEC_SCHEMA,
  AppSpecError,
  CAPABILITIES,
  FIELD_TYPES,
  POLICY_PRESETS,
  VIEW_TYPES,
  actionsForView,
  canonicalAppSpec,
  canonicalJson,
  clockOptions,
  collectionForView,
  compatibilityErrors,
  decodeAppSpec,
  decodeBoundedDefinition,
  decodeDefinitionDocument,
  editableFieldsForView,
  fieldsForView,
  getAction,
  getCollection,
  getField,
  getPage,
  getView,
  normalizeFieldValue,
  normalizeRecordValues,
  normalizeTimestamp,
  requestedDeviceCapabilities,
  timerOptions,
  tryDecodeAppSpec,
  validateRecordQuery,
  validateAggregateQuery,
  viewsForPage,
} from "./index";
import type { AppSpec, FieldSpec, ViewSpecOf } from "./types";

const canonicalRoot = new URL(
  "../../../../appwrite_backend/packages/appnest_spec/",
  import.meta.url,
);
const read = (path: string) =>
  JSON.parse(readFileSync(new URL(path, canonicalRoot), "utf8"));
const fixture = (name: string): AppSpec =>
  read(`fixtures/${name}.json`) as AppSpec;
const copy = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
const names = readdirSync(new URL("fixtures/", canonicalRoot))
  .filter((name) => name.endsWith(".json") && name !== "unsupported.json")
  .map((name) => name.slice(0, -5));

test("runtime schema and all language registries match the canonical Function export", () => {
  assert.deepEqual(APP_SPEC_SCHEMA, read("schema/appspec-v1.schema.json"));
  const p = APP_SPEC_SCHEMA.properties;
  assert.deepEqual(
    new Set(FIELD_TYPES),
    new Set(p.collections.items.properties.fields.items.properties.type.enum),
  );
  assert.deepEqual(
    new Set(VIEW_TYPES),
    new Set(p.views.items.properties.type.enum),
  );
  assert.deepEqual(
    new Set(ACTION_CAPABILITIES),
    new Set(p.actions.items.properties.capability.enum),
  );
  assert.deepEqual(
    new Set(POLICY_PRESETS),
    new Set(p.policyPresetRequest.enum),
  );
  assert.deepEqual(new Set(CAPABILITIES), new Set(p.requires.items.enum));
  assert.equal(FIELD_TYPES.length, 8);
  assert.equal(VIEW_TYPES.length, 21);
  assert.equal(ACTION_CAPABILITIES.length, 7);
  assert.equal(POLICY_PRESETS.length, 3);
});
for (const name of names)
  test(`original ${name} fixture decodes with canonical defaults and no shared mutation`, () => {
    const raw = fixture(name),
      before = canonicalJson(raw);
    const spec = decodeAppSpec(raw);
    assert.equal(canonicalAppSpec(spec), before);
    assert.deepEqual(decodeAppSpec(JSON.stringify(raw)), spec);
    assert.notEqual(spec, raw);
    assert.equal(canonicalJson(raw), before);
    for (const view of spec.views) {
      assert.equal(getView(spec, view.id), view);
      assert.deepEqual(
        actionsForView(spec, view).map((action) => action.id),
        view.actionIds,
      );
      const collection = collectionForView(spec, view);
      if (collection)
        assert.ok(
          fieldsForView(spec, view).every((field) =>
            collection.fields.includes(field),
          ),
        );
    }
    for (const page of spec.navigation?.pages ?? [])
      assert.deepEqual(
        viewsForPage(spec, page).map((view) => view.id),
        page.viewIds,
      );
    assert.deepEqual(compatibilityErrors(spec, spec), []);
  });

test("the original fixtures plus an action-view vector cover every declared language family", () => {
  const all = names.map((name) => decodeAppSpec(fixture(name)));
  const actionView = fixture("reading");
  actionView.requires.push("views.action.v1");
  actionView.views.push({
    id: "actionPanel",
    type: "action",
    collectionId: actionView.collections[0].id,
    label: "Actions",
    actionIds: [actionView.actions[0].id],
  });
  all.push(decodeAppSpec(actionView));
  assert.deepEqual(
    new Set(all.flatMap((spec) => spec.views.map((view) => view.type))),
    new Set(VIEW_TYPES),
  );
  assert.deepEqual(
    new Set(
      all.flatMap((spec) =>
        spec.collections.flatMap((collection) =>
          collection.fields.map((field) => field.type),
        ),
      ),
    ),
    new Set(FIELD_TYPES),
  );
  assert.deepEqual(
    new Set(
      all.flatMap((spec) => spec.actions.map((action) => action.capability)),
    ),
    new Set(ACTION_CAPABILITIES),
  );
  assert.deepEqual(
    new Set(all.map((spec) => spec.policyPresetRequest)),
    new Set(POLICY_PRESETS),
  );
  actionView.views.at(-1)!.actionIds = [];
  assert.throws(() => decodeAppSpec(actionView), /Action views/);
});

test("unsupported fixture and unknown capabilities fail safely", () => {
  assert.throws(
    () => decodeAppSpec(read("fixtures/unsupported.json")),
    AppSpecError,
  );
  const raw = fixture("reading");
  raw.requires.push("arbitrary.code" as never);
  const result = tryDecodeAppSpec(raw);
  assert.equal(result.ok, false);
  if (!result.ok) {
    assert.ok(result.error instanceof AppSpecError);
    assert.ok(result.error.message.length < 500);
  }
  assert.throws(() => decodeAppSpec("not JSON"), /valid JSON/);
});

test("plain JSON, size, depth, array and key bounds fail before unsafe traversal", () => {
  const raw = fixture("reading");
  assert.throws(
    () => decodeAppSpec({ ...raw, actorId: "forged" }),
    AppSpecError,
  );
  assert.throws(
    () => decodeAppSpec({ ...raw, formatVersion: 2 }),
    AppSpecError,
  );
  assert.throws(() => decodeAppSpec({ ...raw, name: " " }), AppSpecError);
  assert.throws(
    () => decodeAppSpec({ ...raw, name: "x".repeat(81) }),
    AppSpecError,
  );
  assert.throws(() => decodeAppSpec({ ...raw, views: [] }), AppSpecError);
  assert.throws(
    () =>
      decodeAppSpec({
        ...raw,
        views: Array.from({ length: 17 }, () => raw.views[0]),
      }),
    AppSpecError,
  );
  assert.throws(() => decodeAppSpec(" ".repeat(131073)), /too large/);
  const deep: Record<string, unknown> = {};
  let tail = deep;
  for (let i = 0; i < 14; i++) {
    tail.next = {};
    tail = tail.next as Record<string, unknown>;
  }
  assert.throws(() => decodeAppSpec(deep), /deeply nested/);
  const cyclic: Record<string, unknown> = {};
  cyclic.self = cyclic;
  assert.throws(() => decodeAppSpec(cyclic), /Cyclic/);
  assert.throws(() => decodeAppSpec({ ...raw, value: Number.NaN }), /finite/);
  assert.throws(
    () =>
      decodeAppSpec({
        ...raw,
        get hidden() {
          throw new Error("must never run");
        },
      }),
    /accessors/,
  );
  assert.throws(() => decodeAppSpec(new Date()), /plain JSON/);
});

test("stable IDs and duplicate IDs are validated at their proper scopes", () => {
  const raw = fixture("reading");
  raw.collections[0].fields.push(copy(raw.collections[0].fields[0]));
  assert.throws(() => decodeAppSpec(raw), /Duplicate/);
  const newline = fixture("reading");
  newline.collections[0].fields[0].id += "\n";
  assert.throws(() => decodeAppSpec(newline), AppSpecError);
  const duplicate = fixture("reading");
  duplicate.views.push(copy(duplicate.views[0]));
  assert.throws(() => decodeAppSpec(duplicate), /Duplicate/);
});

test("snapshot never invokes hidden or nested toJSON methods or accessors", () => {
  let calls = 0;
  for (const location of ["root", "nested", "array"] as const) {
    for (const mode of ["method", "getter"] as const) {
      const raw = fixture("reading");
      const target =
        location === "root"
          ? raw
          : location === "nested"
            ? raw.collections[0]
            : raw.requires;
      Object.defineProperty(
        target,
        "toJSON",
        mode === "method"
          ? {
              value: () => {
                calls++;
                return fixture("focus");
              },
              enumerable: false,
            }
          : {
              get: () => {
                calls++;
                return () => fixture("focus");
              },
              enumerable: false,
            },
      );
      assert.throws(() => decodeAppSpec(raw), AppSpecError);
      assert.equal(calls, 0);
    }
  }
  const nested = fixture("reading");
  Object.defineProperty(nested.collections[0].fields[0], "hidden", {
    get: () => {
      calls++;
      return "never";
    },
    enumerable: false,
  });
  assert.throws(() => decodeAppSpec(nested), /accessors/);
  assert.equal(calls, 0);
});

test("view fields, actions, behavior bindings and required capabilities are checked", () => {
  for (const mutate of [
    (spec: AppSpec) => {
      spec.views[0].collectionId = "missing";
    },
    (spec: AppSpec) => {
      spec.views[0].titleFieldId = "missing";
    },
    (spec: AppSpec) => {
      spec.views[0].actionIds = ["missing"];
    },
    (spec: AppSpec) => {
      spec.actions[0].collectionId = "missing";
    },
    (spec: AppSpec) => {
      spec.actions[0].behaviorId = "invented";
    },
    (spec: AppSpec) => {
      spec.requires = spec.requires.filter(
        (value) => value !== "collections.v1",
      );
    },
  ]) {
    const raw = fixture("reading");
    mutate(raw);
    assert.throws(() => decodeAppSpec(raw), AppSpecError);
  }
  const volunteer = fixture("volunteer");
  const action = volunteer.actions.find((entry) =>
    entry.capability.startsWith("capacity."),
  )!;
  delete action.behaviorId;
  assert.throws(() => decodeAppSpec(volunteer), /declared behavior/);
  const chores = fixture("chores");
  const workflow = chores.collections[0].behaviors.find(
    (entry) => entry.type === "workflow.v1",
  )!;
  workflow.transitions = { Invalid: ["Also invalid"] };
  assert.throws(() => decodeAppSpec(chores), /Unknown workflow/);
});

test("navigation destinations and dedicated record pages cannot be forged", () => {
  for (const mutate of [
    (spec: AppSpec) => {
      spec.navigation!.entryPageId = "missing";
    },
    (spec: AppSpec) => {
      spec.navigation!.tabs[0].pageId = "missing";
    },
    (spec: AppSpec) => {
      spec.navigation!.pages[0].viewIds = ["missing"];
    },
    (spec: AppSpec) => {
      spec.navigation!.pages[0].primaryActionId = "missing";
    },
    (spec: AppSpec) => {
      spec.views.find((view) => view.formPageId)!.formPageId = "missing";
    },
    (spec: AppSpec) => {
      const form = spec.views.find((view) => view.type === "form")!;
      spec.navigation!.pages[0].viewIds = [form.id];
    },
  ]) {
    const raw = fixture("planner");
    mutate(raw);
    assert.throws(() => decodeAppSpec(raw), AppSpecError);
  }
  const noNavigation = fixture("projectHub");
  delete noNavigation.navigation;
  assert.throws(() => decodeAppSpec(noNavigation), /navigation/);
});

test("combined search/choice/default filters respect the shared eight-filter limit", () => {
  const raw = fixture("reading"),
    collection = raw.collections[0],
    view = raw.views.find((view) => view.type === "list")!;
  const text = collection.fields.find((field) => field.type === "text")!,
    choice = collection.fields.find((field) => field.type === "choice")!;
  view.titleFieldId = text.id;
  view.filterFieldIds = [choice.id];
  view.query = {
    filters: Array.from({ length: 7 }, () => ({
      fieldId: text.id,
      operator: "eq",
      value: "x",
    })),
  };
  assert.throws(() => decodeAppSpec(raw), /combined filters/);
});

test("rich component bindings, form controls and step coverage are validated", () => {
  const project = fixture("projectHub");
  const calendar = project.views.find(
    (view) => view.type === "calendar",
  ) as ViewSpecOf<"calendar">;
  calendar.options!.dateFieldId = project.collections[0].fields.find(
    (field) => field.type === "text",
  )!.id;
  assert.throws(() => decodeAppSpec(project), /field binding/);
  const photo = fixture("photoJournal");
  const form = photo.views.find(
    (view) => view.type === "form",
  ) as ViewSpecOf<"form">;
  form.options!.steps![0].fieldIds = ["missing"];
  assert.throws(() => decodeAppSpec(photo), AppSpecError);
  const mismatch = fixture("photoJournal");
  const f = mismatch.views.find(
    (view) => view.type === "form",
  ) as ViewSpecOf<"form">;
  const text = mismatch.collections[0].fields.find(
    (field) => field.type === "text",
  )!;
  f.options!.controls = [
    { fieldId: text.id, control: "slider", min: 0, max: 10, step: 1 },
  ];
  assert.throws(() => decodeAppSpec(mismatch), /types do not match/);
  const badChart = fixture("habitTracker");
  const chart = badChart.views.find(
    (view) => view.type === "chart",
  ) as ViewSpecOf<"chart">;
  chart.options!.metric = "count";
  chart.options!.valueFieldId = "missing";
  assert.throws(() => decodeAppSpec(badChart), /Count takes no/);
  const content = fixture("focus");
  content.views[0].actionIds = ["missing"];
  assert.throws(() => decodeAppSpec(content), /Content blocks/);
});

test("reminder recipients, conditions and timestamp references are semantic authority boundaries", () => {
  const raw = fixture("reminders"),
    rule = raw.automationRequests[0];
  rule.trigger.fieldId = raw.collections[0].fields.find(
    (field) => field.type === "text",
  )!.id;
  assert.throws(() => decodeAppSpec(raw), /timestamp/);
  const wrongPolicy = fixture("reminders");
  wrongPolicy.policyPresetRequest = "groupWorkflow.v1";
  assert.throws(() => decodeAppSpec(wrongPolicy), /personal-tracker/);
  const recipient = fixture("reminders");
  recipient.automationRequests[0].effect.type = "notifyAssignee";
  assert.throws(() => decodeAppSpec(recipient), /matching behavior/);
  const condition = fixture("planner");
  condition.automationRequests[0].condition!.value = "Invented";
  assert.throws(() => decodeAppSpec(condition), /declared choice/);
});

test("canonical normalization omits defaults without changing source or inserting appearance", () => {
  const raw = fixture("reading");
  raw.views[0].options = {};
  raw.views[0].fieldIds = [];
  raw.views[0].filterFieldIds = [];
  raw.collections[0].fields.find((field) => field.type === "text")!.choices =
    [];
  const normalized = decodeAppSpec(raw);
  assert.equal(Object.hasOwn(normalized, "appearance"), false);
  assert.equal(Object.hasOwn(normalized, "navigation"), false);
  assert.equal(Object.hasOwn(normalized.views[0], "options"), false);
  assert.equal(Object.hasOwn(normalized.views[0], "fieldIds"), false);
  const styled = fixture("focus");
  styled.appearance = { style: "clean", accentColor: "#abcdef" };
  styled.requires.push("appearance.v1");
  styled.navigation!.pages[0].showDate = false as never;
  const output = decodeAppSpec(styled);
  assert.equal(output.appearance?.accentColor, "#ABCDEF");
  assert.equal(Object.hasOwn(output.navigation!.pages[0], "showDate"), false);
  assert.equal(styled.appearance.accentColor, "#abcdef");
});

test("all original field values normalize with explicit optional and numeric boundaries", () => {
  const field = (type: FieldSpec["type"], required = false): FieldSpec => ({
    id: "value",
    label: "Value",
    type,
    required,
    ...(type === "choice" ? { choices: ["One", "Two"] } : {}),
  });
  for (const type of FIELD_TYPES) {
    assert.equal(normalizeFieldValue(field(type), null), null);
    assert.throws(
      () => normalizeFieldValue(field(type, true), null),
      AppSpecError,
    );
  }
  assert.equal(
    normalizeFieldValue(field("integer"), Number.MAX_SAFE_INTEGER),
    Number.MAX_SAFE_INTEGER,
  );
  assert.throws(() =>
    normalizeFieldValue(field("integer"), Number.MAX_SAFE_INTEGER + 1),
  );
  assert.throws(() => normalizeFieldValue(field("integer"), 1.5));
  for (const value of [0, -1.5, 1e15, -1e15])
    assert.equal(normalizeFieldValue(field("number"), value), value);
  for (const value of [
    "1",
    true,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    1e15 + 1,
  ])
    assert.throws(() => normalizeFieldValue(field("number"), value));
  assert.equal(normalizeFieldValue(field("boolean"), false), false);
  assert.throws(() => normalizeFieldValue(field("boolean"), "false"));
  assert.equal(normalizeFieldValue(field("choice"), "One"), "One");
  assert.throws(() => normalizeFieldValue(field("choice"), "Other"));
  assert.equal(
    normalizeFieldValue(field("member"), "account-id"),
    "account-id",
  );
  assert.equal(
    normalizeFieldValue(field("image"), "private_asset-1"),
    "private_asset-1",
  );
  assert.throws(() =>
    normalizeFieldValue(field("image"), "https://private.invalid/image"),
  );
  assert.equal(
    normalizeFieldValue(field("text"), "  Keep spacing  "),
    "  Keep spacing  ",
  );
  assert.throws(() => normalizeFieldValue(field("text", true), "\u0085"));
  const collection = {
    id: "c",
    label: "C",
    fields: [field("text")],
    behaviors: [],
  };
  assert.deepEqual(normalizeRecordValues(collection, {}), {});
  assert.throws(() => normalizeRecordValues(collection, { unknown: "x" }));
});

test("explicit timestamps retain microseconds across UTC conversion and reject rollover", () => {
  assert.equal(
    normalizeTimestamp("2030-01-01T10:00:00-08:00"),
    "2030-01-01T18:00:00.000Z",
  );
  assert.equal(
    normalizeTimestamp("2000-02-29T23:59:59.123456+00:00"),
    "2000-02-29T23:59:59.123456Z",
  );
  assert.equal(
    normalizeTimestamp("0001-01-01T00:00:00Z"),
    "0001-01-01T00:00:00.000Z",
  );
  assert.equal(
    normalizeTimestamp("-0001-01-01T00:00:00Z"),
    "-0001-01-01T00:00:00.000Z",
  );
  assert.equal(
    normalizeTimestamp("0000-02-29T00:00:00Z"),
    "0000-02-29T00:00:00.000Z",
  );
  for (const value of [
    "today",
    "2026-10-28",
    "2026-02-29T10:00:00Z",
    "2024-02-30T10:00:00Z",
    "2024-01-01T24:00:00Z",
    "2024-01-01T00:00:00+99:00",
    "2024-01-01T00:00:00",
    "2024-01-01T00:00:00Z ",
    "2024-01-01T00:00:00Z\n",
  ])
    assert.throws(() => normalizeTimestamp(value), AppSpecError);
});

test("aggregate helpers validate global-query bindings and ordered microsecond UTC buckets", () => {
  const collection = decodeAppSpec(fixture("habitTracker")).collections[0];
  const number = collection.fields.find((field) => field.type === "number")!;
  const choice = collection.fields.find((field) => field.type === "choice")!;
  const date = collection.fields.find((field) => field.type === "timestamp")!;
  assert.deepEqual(validateAggregateQuery(collection, { metric: "count" }), {
    metric: "count",
  });
  assert.equal(
    validateAggregateQuery(collection, {
      metric: "sum",
      fieldId: number.id,
      groupFieldId: choice.id,
    }).fieldId,
    number.id,
  );
  const buckets = [
    {
      key: "a",
      start: "2026-01-01T00:00:00.000001Z",
      end: "2026-01-01T00:00:00.000002Z",
    },
    {
      key: "b",
      start: "2026-01-01T00:00:00.000002Z",
      end: "2026-01-01T00:00:00.000003Z",
    },
  ];
  assert.deepEqual(
    validateAggregateQuery(collection, {
      metric: "count",
      dateFieldId: date.id,
      buckets,
    }).buckets,
    buckets,
  );
  for (const query of [
    { metric: "count", fieldId: number.id },
    { metric: "sum", fieldId: choice.id },
    { metric: "count", dateFieldId: date.id },
    { metric: "count", groupFieldId: choice.id, dateFieldId: date.id, buckets },
    { metric: "count", dateFieldId: date.id, buckets: [...buckets].reverse() },
    {
      metric: "count",
      dateFieldId: date.id,
      buckets: [buckets[0], { ...buckets[1], key: "a" }],
    },
    {
      metric: "count",
      dateFieldId: date.id,
      buckets: [
        {
          key: "bad",
          start: "2026-01-01T00:00:00+00:00",
          end: "2026-01-02T00:00:00Z",
        },
      ],
    },
  ])
    assert.throws(
      () => validateAggregateQuery(collection, query as never),
      AppSpecError,
    );
});

test("typed record query helpers validate predicates, unset values, sorts and bounds", () => {
  const spec = decodeAppSpec(fixture("reading")),
    collection = spec.collections[0],
    text = collection.fields.find((field) => field.type === "text")!,
    integer = collection.fields.find((field) => field.type === "integer")!;
  assert.equal(
    validateRecordQuery(collection, {
      filters: [{ fieldId: text.id, operator: "contains", value: "Book" }],
      sort: [{ fieldId: integer.id, descending: true }],
    }).limit,
    50,
  );
  for (const query of [
    { limit: 101 },
    { filters: [{ fieldId: integer.id, operator: "contains", value: "1" }] },
    { sort: [{ fieldId: "missing", descending: false }] },
    { filters: [{ fieldId: text.id, operator: "in", value: [null] }] },
    { filters: [{ fieldId: integer.id, operator: "gte", value: null }] },
  ])
    assert.throws(
      () => validateRecordQuery(collection, query as never),
      AppSpecError,
    );
});

test("compatibility permits presentation and optional additions but rejects destructive changes", () => {
  const before = decodeAppSpec(fixture("reading")),
    next = copy(before);
  next.name = "Renamed";
  next.collections[0].fields[0].label = "New label";
  next.collections[0].fields.push({
    id: "extra",
    label: "Extra",
    type: "text",
    required: false,
  });
  assert.deepEqual(compatibilityErrors(before, decodeAppSpec(next)), []);
  for (const mutate of [
    (spec: AppSpec) => {
      spec.policyPresetRequest = "groupWorkflow.v1";
    },
    (spec: AppSpec) => {
      spec.collections = [];
    },
    (spec: AppSpec) => {
      spec.collections[0].fields.shift();
    },
    (spec: AppSpec) => {
      spec.collections[0].fields[0].type = "integer";
    },
    (spec: AppSpec) => {
      spec.collections[0].fields.push({
        id: "required",
        label: "Required",
        type: "text",
        required: true,
      });
    },
    (spec: AppSpec) => {
      spec.collections[0].fields
        .find((field) => field.type === "choice")!
        .choices!.pop();
    },
  ]) {
    const changed = copy(before);
    mutate(changed);
    assert.ok(compatibilityErrors(before, changed).length > 0);
  }
});

test("binding/default/device helpers are pure and never manufacture permissions", () => {
  const focus = decodeAppSpec(fixture("focus"));
  const clock = focus.views.find(
      (view) => view.type === "clock",
    ) as ViewSpecOf<"clock">,
    timer = focus.views.find(
      (view) => view.type === "timer",
    ) as ViewSpecOf<"timer">;
  assert.equal(clockOptions(clock).style, clock.options?.style ?? "digital");
  assert.equal(
    timerOptions(timer).durationMinutes,
    timer.options?.durationMinutes ?? 25,
  );
  const phone = decodeAppSpec(fixture("phoneToolkit"));
  assert.deepEqual(
    new Set(requestedDeviceCapabilities(phone)),
    new Set([
      "battery",
      "device",
      "connection",
      "locale",
      "flashlight",
      "brightness",
      "keepAwake",
      "haptics",
    ]),
  );
  const planner = decodeAppSpec(fixture("planner")),
    form = planner.views.find((view) => view.type === "form")!,
    collection = getCollection(planner, form.collectionId!);
  const workflow = collection.behaviors.find(
    (behavior) => behavior.type === "workflow.v1",
  );
  assert.ok(
    editableFieldsForView(planner, form).every(
      (field) => field.id !== workflow?.fieldId,
    ),
  );
  assert.throws(() => getField(collection, "missing"), AppSpecError);
  assert.throws(() => getAction(planner, "missing"), AppSpecError);
  assert.throws(() => getPage(planner, "missing"), AppSpecError);
});

test("bounded bridge keeps civil dates and long text explicitly distinct from full AppSpec", () => {
  const flat = {
    title: "Plan",
    description: "",
    primaryFieldId: "title",
    fields: [
      { id: "title", label: "Title", kind: "text", required: true },
      { id: "day", label: "Day", kind: "date" },
      { id: "notes", label: "Notes", kind: "longText" },
    ],
    view: { kind: "agenda", dateFieldId: "day" },
  };
  const result = decodeDefinitionDocument(flat);
  assert.equal(result.format, "tinkerloom-bounded-v1");
  if (result.format === "tinkerloom-bounded-v1")
    assert.equal(result.definition.fields[1].kind, "date");
  assert.equal(
    decodeDefinitionDocument(fixture("planner")).format,
    "appspec-v1",
  );
  assert.throws(() => decodeAppSpec(flat), AppSpecError);
  assert.throws(
    () => decodeBoundedDefinition({ ...flat, grant: "owner" }),
    AppSpecError,
  );
  assert.throws(
    () => decodeDefinitionDocument({ ...flat, formatVersion: 2 }),
    AppSpecError,
  );
});
