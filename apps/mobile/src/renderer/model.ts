import { ownValue } from "../spec/ownValue";
import { collectionForView, fieldsForView, getField } from "../spec/bindings";
import { normalizeFieldValue } from "../spec/values";
import type {
  AppSpec,
  FieldSpec,
  FormControl,
  JsonValue,
  ViewSpecOf,
} from "../spec/types";
import type { RuntimeRecord } from "../runtime/types";

export type EditorValues = Record<string, string | boolean | null>;
export function editorFields(
  spec: AppSpec,
  view: ViewSpecOf<"form">,
  record?: RuntimeRecord,
): FieldSpec[] {
  const collection = collectionForView(spec, view)!;
  const protectedFields = new Set(
    collection.behaviors
      .filter((b) => record || b.type === "workflow.v1")
      .map((b) => b.fieldId),
  );
  return fieldsForView(spec, view).filter(
    (field) => !protectedFields.has(field.id),
  );
}
export function initialEditorValues(
  fields: readonly FieldSpec[],
  record?: RuntimeRecord,
): EditorValues {
  return Object.fromEntries(
    fields.map((field) => {
      const value =
        ownValue(record?.data, field.id) ??
        (field.required
          ? field.type === "choice"
            ? field.choices![0]
            : field.type === "boolean"
              ? false
              : null
          : null);
      return [
        field.id,
        value === null
          ? null
          : typeof value === "boolean"
            ? value
            : String(value),
      ];
    }),
  );
}
export function normalizedEditorData(
  fields: readonly FieldSpec[],
  values: EditorValues,
  controls: readonly FormControl[] = [],
  initial?: RuntimeRecord,
): Record<string, JsonValue> {
  return Object.fromEntries(
    fields.map((field) => {
      const raw = ownValue(values, field.id);
      let candidate: unknown = raw;
      if (field.type === "integer" || field.type === "number") {
        const text = typeof raw === "string" ? raw.trim() : "";
        // Number('') and parseFloat('12junk') must never create a silent value.
        if (text === "") candidate = null;
        else {
          if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(text))
            throw new Error(`${field.label} needs a valid number.`);
          candidate = Number(text);
        }
      } else if (raw === "") candidate = null;
      const normalized = normalizeFieldValue(field, candidate),
        control = controls.find((c) => c.fieldId === field.id);
      if (
        typeof normalized === "number" &&
        control &&
        ["slider", "stepper", "rating"].includes(control.control) &&
        normalized !== ownValue(initial?.data, field.id)
      ) {
        const min = control.control === "rating" ? 1 : control.min!,
          max = control.control === "rating" ? 5 : control.max!;
        if (normalized < min || normalized > max)
          throw new Error(`${field.label} must be between ${min} and ${max}.`);
      }
      return [field.id, normalized];
    }),
  );
}
export function recordTitle(
  spec: AppSpec,
  view: { collectionId?: string; titleFieldId?: string },
  record: RuntimeRecord,
): string {
  const collection = spec.collections.find((c) => c.id === view.collectionId);
  const field = collection?.fields.find(
    (f) => f.id === (view.titleFieldId ?? collection.fields[0]?.id),
  );
  return field?.type === "image"
    ? "Image record"
    : field && ownValue(record.data, field.id) !== undefined
      ? String(ownValue(record.data, field.id))
      : "Untitled";
}
export function displayField(field: FieldSpec, value: unknown): string {
  if (value === null || value === undefined) return "Not set";
  if (field.type === "boolean") return value ? "Yes" : "No";
  if (field.type === "timestamp") {
    const date = new Date(String(value));
    return Number.isFinite(date.getTime())
      ? date.toLocaleString()
      : String(value);
  }
  if (field.type === "image") return "Private image";
  return String(value);
}
export type MarkdownBlock = {
  kind: "heading" | "paragraph" | "bullet" | "quote";
  text: string;
  level?: number;
};
/** Render a restricted text subset. HTML, links and images never execute or fetch. */
export function markdownBlocks(markdown: string): MarkdownBlock[] {
  return markdown
    .split(/\r?\n/)
    .filter((line) => line.trim())
    .map((line) => {
      const heading = /^(#{1,6})\s+(.*)$/.exec(line);
      if (heading)
        return { kind: "heading", text: heading[2], level: heading[1].length };
      if (/^(?:[-*]|\d+\.)\s+/.test(line))
        return { kind: "bullet", text: line.replace(/^(?:[-*]|\d+\.)\s+/, "") };
      if (/^>\s?/.test(line))
        return { kind: "quote", text: line.replace(/^>\s?/, "") };
      return { kind: "paragraph", text: line };
    });
}
export interface MarkdownSpan {
  text: string;
  style: "plain" | "strong" | "emphasis" | "code";
}
export function markdownSpans(text: string): MarkdownSpan[] {
  const pattern = /(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)/g,
    result: MarkdownSpan[] = [];
  let offset = 0;
  for (const match of text.matchAll(pattern)) {
    if (match.index > offset)
      result.push({ text: text.slice(offset, match.index), style: "plain" });
    const token = match[0],
      strong = token.startsWith("**");
    result.push({
      text: token.slice(strong ? 2 : 1, strong ? -2 : -1),
      style: strong ? "strong" : token.startsWith("*") ? "emphasis" : "code",
    });
    offset = match.index + token.length;
  }
  if (offset < text.length)
    result.push({ text: text.slice(offset), style: "plain" });
  return result;
}
export function transitionTargets(
  spec: AppSpec,
  actionId: string,
  record: RuntimeRecord,
): string[] {
  const action = spec.actions.find((a) => a.id === actionId);
  if (!action?.behaviorId) return [];
  const c = spec.collections.find((c) => c.id === action.collectionId)!,
    behavior = c.behaviors.find((b) => b.id === action.behaviorId)!;
  return (
    ownValue(
      behavior.transitions,
      String(ownValue(record.data, behavior.fieldId!)),
    ) ?? []
  );
}
export function checklistInput(
  view: ViewSpecOf<"checklist">,
  record: RuntimeRecord,
): Record<string, JsonValue> {
  const options = view.options!,
    value = ownValue(record.data, options.fieldId);
  return {
    value:
      typeof value === "boolean"
        ? !value
        : value === options.checkedValue
          ? options.uncheckedValue!
          : options.checkedValue!,
  };
}
export function checklistChecked(
  view: ViewSpecOf<"checklist">,
  record: RuntimeRecord,
): boolean {
  return view.options?.checkedValue
    ? ownValue(record.data, view.options.fieldId) === view.options.checkedValue
    : ownValue(record.data, view.options!.fieldId) === true;
}
export function checklistCommand(
  spec: AppSpec,
  view: ViewSpecOf<"checklist">,
  record: RuntimeRecord,
): Record<string, JsonValue> {
  const action = spec.actions.find((a) => a.id === view.options?.actionId)!,
    field = getField(collectionForView(spec, view)!, view.options!.fieldId),
    value = checklistInput(view, record).value;
  return action.capability === "records.patch.v1"
    ? { data: { [field.id]: value } }
    : { value };
}
