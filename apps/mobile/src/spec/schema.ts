import exportedSchema from "./schema.json";
import { AppSpecError, requireSpec } from "./errors";
import { LIMITS } from "./types";

type Schema = boolean | { [key: string]: unknown };
const keywords = new Set([
  "$schema",
  "$id",
  "title",
  "description",
  "type",
  "const",
  "enum",
  "properties",
  "required",
  "additionalProperties",
  "items",
  "minItems",
  "maxItems",
  "uniqueItems",
  "minLength",
  "maxLength",
  "pattern",
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "maxProperties",
  "allOf",
  "oneOf",
  "if",
  "then",
  "else",
  "not",
]);
export const APP_SPEC_SCHEMA = exportedSchema;
export function utf8Bytes(text: string): number {
  let bytes = 0;
  for (const char of text) {
    const cp = char.codePointAt(0)!;
    bytes += cp < 128 ? 1 : cp < 2048 ? 2 : cp < 65536 ? 3 : 4;
  }
  return bytes;
}
export function canonicalJson(value: unknown): string {
  const sort = (item: unknown): unknown =>
    Array.isArray(item)
      ? item.map(sort)
      : item !== null && typeof item === "object"
        ? Object.fromEntries(
            Object.keys(item)
              .sort()
              .map((key) => [
                key,
                sort((item as Record<string, unknown>)[key]),
              ]),
          )
        : item;
  return JSON.stringify(sort(value));
}
/** Reject non-JSON values, accessors, cycles and excessive nesting before cloning. */
export function jsonSnapshot(value: unknown): unknown {
  const parents = new Set<object>();
  const visit = (item: unknown, depth: number, path: string): unknown => {
    requireSpec(
      depth <= LIMITS.depth,
      path,
      "Definition is too deeply nested",
      "definition_depth",
    );
    if (item === null || typeof item === "string" || typeof item === "boolean")
      return item;
    if (typeof item === "number") {
      requireSpec(Number.isFinite(item), path, "Numbers must be finite");
      return item;
    }
    requireSpec(
      typeof item === "object" && item !== null,
      path,
      "Expected JSON data",
    );
    requireSpec(!parents.has(item), path, "Cyclic JSON is not supported");
    requireSpec(
      Array.isArray(item) ||
        Object.getPrototypeOf(item) === Object.prototype ||
        Object.getPrototypeOf(item) === null,
      path,
      "Expected a plain JSON object",
    );
    parents.add(item);
    const descriptors = Object.getOwnPropertyDescriptors(item);
    const keys = Reflect.ownKeys(descriptors);
    const result: Record<string, unknown> | unknown[] = Array.isArray(item)
      ? []
      : Object.create(null);
    if (Array.isArray(item)) {
      const indices = keys.filter((key) => key !== "length");
      requireSpec(
        indices.length === item.length &&
          indices.every((key, index) => key === String(index)),
        path,
        "Sparse arrays and custom array properties are not JSON arrays",
      );
    }
    for (const key of keys) {
      requireSpec(
        typeof key === "string",
        path,
        "JSON symbol keys are not supported",
      );
      if (Array.isArray(item) && key === "length") continue;
      const descriptor = descriptors[key];
      requireSpec(
        "value" in descriptor,
        path,
        "JSON accessors are not supported",
      );
      const cloned = visit(descriptor.value, depth + 1, `${path}.${key}`);
      if (Array.isArray(result)) result.push(cloned);
      else if (descriptor.enumerable) result[key] = cloned;
    }
    parents.delete(item);
    return result;
  };
  const clone = visit(value, 0, "$");
  // Only validated data reaches serialization. Never call an original object's
  // toJSON, including non-enumerable own methods that Object.keys would miss.
  const text = JSON.stringify(clone);
  requireSpec(
    utf8Bytes(text) <= LIMITS.definitionBytes,
    "$",
    "Definition is too large",
    "definition_size",
  );
  return JSON.parse(text);
}

/** Interpreter for this fixed exported schema. It never compiles or evaluates code. */
function check(schema: Schema, value: unknown, path: string): void {
  if (schema === true) return;
  requireSpec(schema !== false, path, "Value is not allowed");
  for (const key of Object.keys(schema))
    requireSpec(
      keywords.has(key),
      path,
      "The client schema needs an update",
      "unsupported_schema",
    );
  const equal = (a: unknown, b: unknown) =>
    canonicalJson(a) === canonicalJson(b);
  const matches = (part: Schema) => {
    try {
      check(part, value, path);
      return true;
    } catch (error) {
      if (
        !(error instanceof AppSpecError) ||
        error.code === "unsupported_schema"
      )
        throw error;
      return false;
    }
  };
  if (schema.allOf)
    for (const part of schema.allOf as Schema[]) check(part, value, path);
  if (schema.oneOf)
    requireSpec(
      (schema.oneOf as Schema[]).filter(matches).length === 1,
      path,
      "Value must match exactly one supported shape",
    );
  if (schema.if) {
    const branch = matches(schema.if as Schema) ? schema.then : schema.else;
    if (branch !== undefined) check(branch as Schema, value, path);
  }
  if (schema.not)
    requireSpec(
      !matches(schema.not as Schema),
      path,
      "Property combination is not allowed",
    );
  if (Object.prototype.hasOwnProperty.call(schema, "const"))
    requireSpec(equal(value, schema.const), path, "Unexpected constant value");
  if (schema.enum)
    requireSpec(
      (schema.enum as unknown[]).some((choice) => equal(value, choice)),
      path,
      "Unsupported value or capability",
      "unsupported_value",
    );
  if (schema.type) {
    const type = schema.type;
    const valid =
      type === "object"
        ? value !== null && typeof value === "object" && !Array.isArray(value)
        : type === "array"
          ? Array.isArray(value)
          : type === "integer"
            ? typeof value === "number" && Number.isInteger(value)
            : typeof value === type;
    requireSpec(valid, path, `Expected ${String(type)}`);
  }
  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    const object = value as Record<string, unknown>;
    const properties = (schema.properties ?? {}) as Record<string, Schema>;
    for (const key of (schema.required ?? []) as string[])
      requireSpec(
        Object.prototype.hasOwnProperty.call(object, key),
        `${path}.${key}`,
        "Required property is missing",
      );
    if (typeof schema.maxProperties === "number")
      requireSpec(
        Object.keys(object).length <= schema.maxProperties,
        path,
        "Too many properties",
      );
    for (const [key, item] of Object.entries(object)) {
      if (Object.prototype.hasOwnProperty.call(properties, key))
        check(properties[key], item, `${path}.${key}`);
      else if (schema.additionalProperties !== undefined)
        check(schema.additionalProperties as Schema, item, `${path}.${key}`);
    }
  }
  if (Array.isArray(value)) {
    if (typeof schema.minItems === "number")
      requireSpec(value.length >= schema.minItems, path, "Not enough items");
    if (typeof schema.maxItems === "number")
      requireSpec(value.length <= schema.maxItems, path, "Too many items");
    if (schema.uniqueItems)
      requireSpec(
        new Set(value.map(canonicalJson)).size === value.length,
        path,
        "Duplicate items are not allowed",
      );
    if (schema.items)
      value.forEach((item, i) =>
        check(schema.items as Schema, item, `${path}[${i}]`),
      );
  }
  if (typeof value === "string") {
    if (typeof schema.minLength === "number")
      requireSpec(value.length >= schema.minLength, path, "Text is too short");
    if (typeof schema.maxLength === "number")
      requireSpec(value.length <= schema.maxLength, path, "Text is too long");
    if (typeof schema.pattern === "string") {
      const match = new RegExp(schema.pattern).exec(value);
      requireSpec(
        match &&
          (!(schema.pattern.startsWith("^") && schema.pattern.endsWith("$")) ||
            match[0] === value),
        path,
        "Text has an invalid format",
      );
    }
  }
  if (typeof value === "number") {
    requireSpec(Number.isFinite(value), path, "Numbers must be finite");
    if (typeof schema.minimum === "number")
      requireSpec(value >= schema.minimum, path, "Number is below the minimum");
    if (typeof schema.maximum === "number")
      requireSpec(value <= schema.maximum, path, "Number exceeds the maximum");
    if (typeof schema.exclusiveMinimum === "number")
      requireSpec(
        value > schema.exclusiveMinimum,
        path,
        "Number must exceed the minimum",
      );
  }
}
export function assertSchema(value: unknown): void {
  check(exportedSchema as Schema, value, "$");
}
