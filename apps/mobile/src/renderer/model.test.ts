import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { decodeAppSpec } from "../spec/decode";
import type { AppSpec, FieldSpec, ViewSpecOf } from "../spec/types";
import type { RuntimeRecord } from "../runtime/types";
import { PreviewRuntimeAdapter } from "../runtime/preview";
import {
  checklistChecked,
  checklistCommand,
  displayField,
  editorFields,
  initialEditorValues,
  markdownBlocks,
  markdownSpans,
  normalizedEditorData,
  transitionTargets,
} from "./model";
import { pageRows, resolveAppearance } from "./appearance";
const fixture = (name: string) =>
  decodeAppSpec(
    JSON.parse(
      readFileSync(
        new URL(
          `../../../../appwrite_backend/packages/appnest_spec/fixtures/${name}.json`,
          import.meta.url,
        ),
        "utf8",
      ),
    ),
  );
const record = (data: RuntimeRecord["data"]): RuntimeRecord => ({
  id: "record",
  collectionId: "chores",
  data,
  revision: 2,
  writtenUnderVersionId: "v",
  capacity: null,
  allocated: null,
  claimed: false,
  allowedActions: [],
});

test("create hides managed workflow; patch additionally hides assignment", () => {
  const spec = fixture("chores"),
    view: ViewSpecOf<"form"> = {
      id: "editor",
      label: "Editor",
      type: "form",
      collectionId: "chores",
      actionIds: [],
    };
  assert.equal(
    editorFields(spec, view).some((field) => field.id === "status"),
    false,
  );
  assert.equal(
    editorFields(spec, view).some((field) => field.id === "assignee"),
    true,
  );
  const fields = editorFields(
    spec,
    view,
    record({ title: "Existing", status: "Open" }),
  );
  assert.equal(
    fields.some((field) => field.id === "assignee" || field.id === "status"),
    false,
  );
});
test("form keeps optional false, zero and unset distinct and rejects loose numeric parsing", () => {
  const fields: FieldSpec[] = [
    { id: "amount", label: "Amount", type: "number", required: false },
    { id: "count", label: "Count", type: "integer", required: false },
    { id: "enabled", label: "Enabled", type: "boolean", required: false },
    { id: "note", label: "Note", type: "text", required: false },
  ];
  const initial = initialEditorValues(fields);
  assert.deepEqual(initial, {
    amount: null,
    count: null,
    enabled: null,
    note: null,
  });
  assert.deepEqual(
    normalizedEditorData(fields, {
      amount: "0",
      count: "0",
      enabled: false,
      note: "",
    }),
    { amount: 0, count: 0, enabled: false, note: null },
  );
  assert.throws(() =>
    normalizedEditorData(fields, {
      amount: "12junk",
      count: null,
      enabled: null,
      note: null,
    }),
  );
  assert.throws(() =>
    normalizedEditorData(fields, {
      amount: "Infinity",
      count: null,
      enabled: null,
      note: null,
    }),
  );
  assert.throws(() =>
    normalizedEditorData(fields, {
      amount: null,
      count: "1.2",
      enabled: null,
      note: null,
    }),
  );
});
test("required boolean/choice receive defaults; timestamps retain original precision", () => {
  const fields: FieldSpec[] = [
    { id: "done", label: "Done", type: "boolean", required: true },
    {
      id: "kind",
      label: "Kind",
      type: "choice",
      required: true,
      choices: ["First", "Second"],
    },
    { id: "at", label: "At", type: "timestamp", required: false },
  ];
  assert.deepEqual(initialEditorValues(fields), {
    done: false,
    kind: "First",
    at: null,
  });
  const data = normalizedEditorData(fields, {
    done: false,
    kind: "First",
    at: "2030-01-05T10:00:00.123456+01:00",
  });
  assert.equal(data.at, "2030-01-05T09:00:00.123456Z");
  assert.throws(() =>
    normalizedEditorData(fields, {
      done: false,
      kind: "First",
      at: "2030-02-30T10:00:00Z",
    }),
  );
});
test("unchanged stored out-of-range configured values survive unrelated edits without clamping", () => {
  const fields: FieldSpec[] = [
      { id: "rating", label: "Rating", type: "integer", required: false },
      { id: "note", label: "Note", type: "text", required: false },
    ],
    controls = [{ fieldId: "rating", control: "rating" as const }],
    row = record({ rating: 8, note: "Stored" });
  assert.equal(
    normalizedEditorData(
      fields,
      { rating: "8", note: "Changed" },
      controls,
      row,
    ).rating,
    8,
  );
  assert.throws(() =>
    normalizedEditorData(
      fields,
      { rating: "9", note: "Changed" },
      controls,
      row,
    ),
  );
  assert.throws(() =>
    normalizedEditorData(fields, { rating: "8", note: "New" }, controls),
  );
});
test("checklist uses registered generic patch or workflow transition shape", async () => {
  const habit = fixture("habitTracker"),
    adapter = new PreviewRuntimeAdapter(habit),
    row = (await adapter.query("checkins", {})).records[0],
    view = habit.views.find(
      (v) => v.type === "checklist",
    ) as ViewSpecOf<"checklist">;
  assert.equal(checklistChecked(view, row), true);
  assert.deepEqual(checklistCommand(habit, view, row), {
    data: { completed: false },
  });
  const projects = fixture("projectHub"),
    projectAdapter = new PreviewRuntimeAdapter(projects),
    project = (await projectAdapter.query("projects", {})).records[0],
    projectView = projects.views.find(
      (v) => v.type === "checklist",
    ) as ViewSpecOf<"checklist">;
  assert.deepEqual(
    Object.keys(checklistCommand(projects, projectView, project)),
    ["value"],
  );
});
test("workflow target controls list only transitions declared for the current state", () => {
  const spec = fixture("chores");
  assert.deepEqual(
    transitionTargets(spec, "moveChore", record({ status: "Open" })),
    ["Doing"],
  );
  assert.deepEqual(
    transitionTargets(spec, "moveChore", record({ status: "Doing" })),
    ["Open", "Done"],
  );
  assert.deepEqual(
    transitionTargets(spec, "moveChore", record({ status: "Unknown" })),
    [],
  );
});
test("restricted markdown is text only and never interprets HTML, links or remote images", () => {
  const blocks = markdownBlocks(
    "# Heading\n- Item\n> Quote\n<script>alert(1)</script>\n![pixel](https://example.test/pixel.png)",
  );
  assert.deepEqual(
    blocks.map((b) => b.kind),
    ["heading", "bullet", "quote", "paragraph", "paragraph"],
  );
  assert.equal(blocks[3].text, "<script>alert(1)</script>");
  assert.match(blocks[4].text, /https:/);
});
test("restricted inline markup supports strong/emphasis/code while links remain inert text", () => {
  assert.deepEqual(
    markdownSpans("A **bold** *soft* `code` [link](https://example.test)"),
    [
      { text: "A ", style: "plain" },
      { text: "bold", style: "strong" },
      { text: " ", style: "plain" },
      { text: "soft", style: "emphasis" },
      { text: " ", style: "plain" },
      { text: "code", style: "code" },
      { text: " [link](https://example.test)", style: "plain" },
    ],
  );
  assert.equal(markdownBlocks("###### Small heading\n1. Item")[0].level, 6);
  assert.equal(markdownBlocks("1. Item")[0].kind, "bullet");
});
test("appearance resolves original style defaults and chooses readable accent foreground", () => {
  const base = fixture("notes");
  for (const [style, spacing, radius, serif] of [
    ["editorial", 1.25, 0, true],
    ["playful", 1, 28, false],
    ["clean", 0.8, 10, false],
  ] as const) {
    const tokens = resolveAppearance({ ...base, appearance: { style } });
    assert.equal(tokens.spacing, spacing);
    assert.equal(tokens.radius, radius);
    assert.equal(tokens.serif, serif);
  }
  assert.equal(
    resolveAppearance({
      ...base,
      appearance: { style: "clean", accentColor: "#FFFFFF" },
    }).onAccent,
    "#000000",
  );
  assert.equal(
    resolveAppearance({
      ...base,
      appearance: { style: "clean", accentColor: "#000000" },
    }).onAccent,
    "#ffffff",
  );
});
test("layout stacks on narrow/large-text screens and preserves featured/full-width reading order", () => {
  const spec = fixture("projectHub"),
    views = spec.views.slice(0, 4),
    page = {
      id: "p",
      title: "Page",
      viewIds: views.map((v) => v.id),
      layout: "twoColumn" as const,
    };
  assert.ok(pageRows(page, views, 959, 1).every((row) => row.length === 1));
  assert.ok(pageRows(page, views, 1200, 1.6).every((row) => row.length === 1));
  const simple: AppSpec["views"] = [
    { id: "a", type: "clock", label: "A", actionIds: [] },
    { id: "b", type: "clock", label: "B", actionIds: [] },
    { id: "c", type: "clock", label: "C", actionIds: [] },
  ];
  assert.deepEqual(
    pageRows({ ...page, layout: "featuredFirst" }, simple, 1200, 1).map((row) =>
      row.map((view) => view.id),
    ),
    [["a"], ["b", "c"]],
  );
  assert.equal(
    pageRows(page, views, 1200, 1)
      .flat()
      .map((v) => v.id)
      .join(","),
    views.map((v) => v.id).join(","),
  );
});
test("display renders missing, boolean and private image semantics without leaking asset IDs", () => {
  assert.equal(
    displayField(
      { id: "v", label: "V", type: "boolean", required: false },
      false,
    ),
    "No",
  );
  assert.equal(
    displayField(
      { id: "v", label: "V", type: "text", required: false },
      undefined,
    ),
    "Not set",
  );
  assert.equal(
    displayField(
      { id: "v", label: "V", type: "image", required: false },
      "private_asset_id",
    ),
    "Private image",
  );
});
