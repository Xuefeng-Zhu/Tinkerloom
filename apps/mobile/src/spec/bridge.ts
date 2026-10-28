import { validateDefinition } from "../preview/model";
import type { Definition } from "../preview/model";
import { decodeAppSpec } from "./decode";
import { requireSpec } from "./errors";
import { jsonSnapshot, utf8Bytes } from "./schema";
import type { AppSpec } from "./types";

/** A civil date/longText flat definition is not an AppSpec timestamp/collection. */
export type DefinitionDocument =
  | { format: "appspec-v1"; spec: AppSpec }
  | { format: "tinkerloom-bounded-v1"; definition: Definition };

export function decodeBoundedDefinition(input: unknown): Definition {
  const value = jsonSnapshot(input);
  requireSpec(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "$",
    "Expected a bounded definition",
  );
  const data = value as Record<string, unknown>;
  requireSpec(
    Object.keys(data).every((key) =>
      ["title", "description", "primaryFieldId", "fields", "view"].includes(
        key,
      ),
    ),
    "$",
    "Unknown bounded definition property",
  );
  requireSpec(Array.isArray(data.fields), "fields", "Expected bounded fields");
  for (const item of data.fields) {
    requireSpec(
      item !== null && typeof item === "object" && !Array.isArray(item),
      "fields",
      "Invalid bounded field",
    );
    const field = item as Record<string, unknown>;
    requireSpec(
      Object.keys(field).every((key) =>
        ["id", "label", "kind", "required", "options"].includes(key),
      ) &&
        (field.required === undefined || typeof field.required === "boolean"),
      "fields",
      "Invalid bounded field properties",
    );
  }
  const definition = data as unknown as Definition;
  validateDefinition(definition);
  requireSpec(
    utf8Bytes(JSON.stringify(value)) <= 16384,
    "$",
    "Bounded definition is too large",
  );
  return definition;
}
export function decodeDefinitionDocument(input: unknown): DefinitionDocument {
  let value = input;
  if (typeof input === "string") {
    // Full decode supplies a safe syntax error for malformed JSON as well.
    try {
      value = JSON.parse(input);
    } catch {
      return { format: "appspec-v1", spec: decodeAppSpec(input) };
    }
  }
  if (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.hasOwn(value, "formatVersion")
  )
    return { format: "appspec-v1", spec: decodeAppSpec(input) };
  return {
    format: "tinkerloom-bounded-v1",
    definition: decodeBoundedDefinition(value),
  };
}
