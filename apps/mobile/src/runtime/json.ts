import { utf8Bytes } from "../spec/schema";
import { ensure } from "./errors";
export const RUNTIME_REQUEST_BYTES = 6 * 1024 * 1024;
/** Definitions retain their separate 128 KiB bound. Runtime record input is larger. */
export function runtimeJsonSnapshot(value: unknown): unknown {
  const parents = new Set<object>();
  let nodes = 0;
  const visit = (item: unknown, depth: number): unknown => {
    ensure(
      depth <= 12 && ++nodes <= 1000000,
      "invalid_input",
      "Runtime JSON exceeds its nesting or item bound.",
    );
    if (item === null || typeof item === "string" || typeof item === "boolean")
      return item;
    if (typeof item === "number") {
      ensure(
        Number.isFinite(item),
        "invalid_input",
        "Runtime numbers must be finite.",
      );
      return item;
    }
    ensure(
      typeof item === "object" &&
        item !== null &&
        (Array.isArray(item) ||
          Object.getPrototypeOf(item) === Object.prototype ||
          Object.getPrototypeOf(item) === null),
      "invalid_input",
      "Runtime input must contain plain JSON data.",
    );
    ensure(
      !parents.has(item),
      "invalid_input",
      "Runtime JSON cannot contain cycles.",
    );
    parents.add(item);
    const descriptors = Object.getOwnPropertyDescriptors(item),
      keys = Reflect.ownKeys(descriptors),
      result: unknown[] | Record<string, unknown> = Array.isArray(item)
        ? []
        : Object.create(null);
    if (Array.isArray(item)) {
      const indices = keys.filter((key) => key !== "length");
      ensure(
        indices.length === item.length &&
          indices.every((key, index) => key === String(index)),
        "invalid_input",
        "Sparse arrays or custom array properties are unsupported.",
      );
    }
    for (const key of keys) {
      ensure(
        typeof key === "string",
        "invalid_input",
        "JSON symbol keys are unsupported.",
      );
      if (Array.isArray(item) && key === "length") continue;
      const descriptor = descriptors[key];
      ensure(
        "value" in descriptor,
        "invalid_input",
        "JSON accessors are unsupported.",
      );
      const child = visit(descriptor.value, depth + 1);
      if (Array.isArray(result)) result.push(child);
      else if (descriptor.enumerable) result[key] = child;
    }
    parents.delete(item);
    return result;
  };
  const clone = visit(value, 0),
    text = JSON.stringify(clone);
  ensure(
    utf8Bytes(text) <= RUNTIME_REQUEST_BYTES,
    "request_too_large",
    "Runtime input exceeds the 6 MiB request bound.",
  );
  return JSON.parse(text);
}
