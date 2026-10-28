import { requireSpec } from "./errors";
import type {
  CollectionSpec,
  AggregateQuery,
  FieldSpec,
  JsonValue,
  RecordQuery,
  RecordValue,
  RecordValues,
} from "./types";

export const dartTrim = (text: string) =>
  text.replace(/^[\s\u0085]+|[\s\u0085]+$/g, "");
export function nonblank(value: string, path: string, max = 160): void {
  requireSpec(
    value.length <= max && dartTrim(value).length > 0,
    path,
    "Use nonblank text within the allowed length",
  );
}
export function validCivilParts(
  year: number,
  month: number,
  day: number,
): boolean {
  if (!Number.isInteger(year) || month < 1 || month > 12 || day < 1)
    return false;
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  return (
    day <=
    [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
  );
}
/** Explicit-offset instants only; never silently roll an invalid date into another month. */
function timestampParts(
  value: unknown,
  path: string,
): { date: Date; micros: string } {
  requireSpec(
    typeof value === "string",
    path,
    "A timestamp needs an explicit timezone",
  );
  const match =
    /^([+-]?\d{4,6})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|([+-])(\d{2}):(\d{2}))$/.exec(
      value,
    );
  requireSpec(
    match && match[0] === value,
    path,
    "Use an ISO timestamp with an explicit Z or offset",
  );
  const [
    ,
    ys,
    ms,
    ds,
    hs,
    mins,
    ss,
    fraction = "",
    ,
    sign,
    oh = "0",
    om = "0",
  ] = match;
  const year = Number(ys),
    month = Number(ms),
    day = Number(ds),
    hour = Number(hs),
    minute = Number(mins),
    second = Number(ss);
  requireSpec(
    validCivilParts(year, month, day) &&
      hour < 24 &&
      minute < 60 &&
      second < 60 &&
      Number(oh) < 24 &&
      Number(om) < 60,
    path,
    "Timestamp contains an invalid calendar date, time or offset",
  );
  const milliseconds = Number(fraction.padEnd(6, "0").slice(0, 3));
  const local = new Date(0);
  local.setUTCFullYear(year, month - 1, day);
  local.setUTCHours(hour, minute, second, milliseconds);
  const offset = (Number(oh) * 60 + Number(om)) * (sign === "-" ? -1 : 1);
  const instant = new Date(local.getTime() - offset * 60000);
  requireSpec(
    Number.isFinite(instant.getTime()),
    path,
    "Timestamp is outside the supported range",
  );
  const micros = fraction.padEnd(6, "0").slice(3, 6);
  return { date: instant, micros };
}
export function normalizeTimestamp(value: unknown, path = "timestamp"): string {
  const { date, micros } = timestampParts(value, path);
  const year = date.getUTCFullYear();
  // Dart uses four digits through ±9999, including negative years; JS's
  // toISOString uses six for every negative year, so format this explicitly.
  const y =
    year >= -9999 && year <= 9999
      ? `${year < 0 ? "-" : ""}${String(Math.abs(year)).padStart(4, "0")}`
      : `${year < 0 ? "-" : "+"}${String(Math.abs(year)).padStart(6, "0")}`;
  const two = (value: number) => String(value).padStart(2, "0");
  return `${y}-${two(date.getUTCMonth() + 1)}-${two(date.getUTCDate())}T${two(date.getUTCHours())}:${two(date.getUTCMinutes())}:${two(date.getUTCSeconds())}.${String(date.getUTCMilliseconds()).padStart(3, "0")}${micros === "000" ? "" : micros}Z`;
}
export function normalizeFieldValue(
  field: FieldSpec,
  value: unknown,
  path = field.id,
): RecordValue | null {
  if (value === undefined || value === null) {
    requireSpec(!field.required, path, "This field is required");
    return null;
  }
  switch (field.type) {
    case "text":
      requireSpec(
        typeof value === "string" &&
          value.length <= 10000 &&
          (!field.required || dartTrim(value).length > 0),
        path,
        "Expected text within 10000 characters",
      );
      return value;
    case "integer":
      requireSpec(
        typeof value === "number" && Number.isSafeInteger(value),
        path,
        "Expected a safe integer",
      );
      return Object.is(value, -0) ? 0 : value;
    case "number":
      requireSpec(
        typeof value === "number" &&
          Number.isFinite(value) &&
          Math.abs(value) <= 1e15,
        path,
        "Expected a finite number within ±1e15",
      );
      return Object.is(value, -0) ? 0 : value;
    case "boolean":
      requireSpec(typeof value === "boolean", path, "Expected true or false");
      return value;
    case "choice":
      requireSpec(
        typeof value === "string" && field.choices?.includes(value),
        path,
        "Choose a declared option",
      );
      return value;
    case "timestamp":
      return normalizeTimestamp(value, path);
    case "image":
      requireSpec(
        typeof value === "string" &&
          /^[A-Za-z0-9_-]{1,128}$/.exec(value)?.[0] === value,
        path,
        "Expected an opaque private image ID",
      );
      return value;
    case "member":
      requireSpec(
        typeof value === "string" && value.length > 0 && value.length <= 100,
        path,
        "Expected a member ID",
      );
      return value;
  }
}
export function normalizeRecordValues(
  collection: CollectionSpec,
  input: unknown,
): RecordValues {
  requireSpec(
    input !== null && typeof input === "object" && !Array.isArray(input),
    collection.id,
    "Expected a record object",
  );
  const values = input as Record<string, unknown>;
  requireSpec(
    Object.getPrototypeOf(values) === Object.prototype ||
      Object.getPrototypeOf(values) === null,
    collection.id,
    "Expected plain JSON record values",
  );
  for (const key of Object.keys(values))
    requireSpec(
      "value" in Object.getOwnPropertyDescriptor(values, key)!,
      collection.id,
      "Record accessors are not supported",
    );
  requireSpec(
    Object.keys(values).every((key) =>
      collection.fields.some((field) => field.id === key),
    ),
    collection.id,
    "Record has an unknown field",
  );
  return Object.fromEntries(
    collection.fields.flatMap((field) => {
      const value = normalizeFieldValue(
        field,
        Object.hasOwn(values, field.id) ? values[field.id] : undefined,
      );
      return value === null ? [] : [[field.id, value]];
    }),
  );
}
export function validateRecordQuery(
  collection: CollectionSpec,
  query: RecordQuery,
): RecordQuery {
  requireSpec(
    query !== null && typeof query === "object" && !Array.isArray(query),
    "query",
    "Expected a query object",
  );
  requireSpec(
    Object.keys(query).every((key) =>
      ["filters", "sort", "limit", "cursor"].includes(key),
    ),
    "query",
    "Unknown query property",
  );
  const filters = query.filters ?? [],
    sort = query.sort ?? [],
    limit = query.limit ?? 50;
  requireSpec(
    Array.isArray(filters) &&
      filters.length <= 8 &&
      Array.isArray(sort) &&
      sort.length <= 2 &&
      Number.isInteger(limit) &&
      limit >= 1 &&
      limit <= 100,
    "query",
    "Query exceeds its bounds",
  );
  const field = (id: string) => {
    const found = collection.fields.find((candidate) => candidate.id === id);
    requireSpec(found, "query", "Query references an unknown field");
    return found;
  };
  const normalized = filters.map((filter) => {
    requireSpec(
      filter !== null &&
        typeof filter === "object" &&
        Object.keys(filter).every((key) =>
          ["fieldId", "operator", "value"].includes(key),
        ) &&
        Object.hasOwn(filter, "value"),
      "query.filters",
      "Invalid filter",
    );
    const f = field(filter.fieldId),
      op = filter.operator;
    requireSpec(
      ["eq", "in", "contains", "gte", "lte", "lt"].includes(op),
      "query.filters",
      "Unsupported filter operator",
    );
    if (op === "contains")
      requireSpec(f.type === "text", f.id, "Contains needs text");
    if (["gte", "lte", "lt"].includes(op))
      requireSpec(
        ["integer", "number", "timestamp"].includes(f.type),
        f.id,
        "Range needs number or timestamp",
      );
    let value: JsonValue;
    if (op === "in") {
      requireSpec(
        Array.isArray(filter.value) &&
          filter.value.length <= 30 &&
          filter.value.every((entry) => entry !== null),
        f.id,
        "Invalid membership filter",
      );
      value = filter.value.map((entry) =>
        normalizeFieldValue(f, entry),
      ) as JsonValue;
    } else {
      requireSpec(
        op === "eq" || filter.value !== null,
        f.id,
        "Only equality can compare unset values",
      );
      value = normalizeFieldValue(f, filter.value);
    }
    return { ...filter, value };
  });
  for (const item of sort) {
    requireSpec(
      item !== null &&
        typeof item === "object" &&
        Object.keys(item).every((key) =>
          ["fieldId", "descending"].includes(key),
        ) &&
        typeof item.descending === "boolean",
      "query.sort",
      "Invalid sort",
    );
    field(item.fieldId);
  }
  if (query.cursor !== undefined) {
    requireSpec(
      typeof query.cursor === "string",
      "query.cursor",
      "Invalid cursor",
    );
    nonblank(query.cursor, "query.cursor", 4096);
  }
  return {
    filters: normalized,
    sort: sort.map((item) => ({ ...item })),
    limit,
    ...(query.cursor === undefined ? {} : { cursor: query.cursor }),
  };
}

/** Validate aggregate bindings and explicit ordered UTC ranges, not loaded-page data. */
export function validateAggregateQuery(
  collection: CollectionSpec,
  query: AggregateQuery,
): AggregateQuery {
  requireSpec(
    query !== null && typeof query === "object" && !Array.isArray(query),
    "aggregate",
    "Expected an aggregate object",
  );
  requireSpec(
    Object.keys(query).every((key) =>
      ["metric", "fieldId", "groupFieldId", "dateFieldId", "buckets"].includes(
        key,
      ),
    ) && ["count", "sum", "average"].includes(query.metric),
    "aggregate",
    "Invalid aggregate properties or metric",
  );
  const field = (id: string | undefined) => {
    const found = collection.fields.find((entry) => entry.id === id);
    requireSpec(found, "aggregate", "Unknown aggregate field");
    return found;
  };
  if (query.metric === "count")
    requireSpec(
      query.fieldId === undefined,
      "aggregate",
      "Counts do not take a value field",
    );
  else
    requireSpec(
      ["integer", "number"].includes(field(query.fieldId).type),
      "aggregate",
      "Numeric aggregates need a numeric field",
    );
  if (query.groupFieldId !== undefined)
    requireSpec(
      field(query.groupFieldId).type === "choice",
      "aggregate",
      "Groups need a choice field",
    );
  if (query.dateFieldId !== undefined)
    requireSpec(
      field(query.dateFieldId).type === "timestamp",
      "aggregate",
      "Date buckets need a timestamp field",
    );
  requireSpec(
    query.groupFieldId === undefined || query.dateFieldId === undefined,
    "aggregate",
    "Choose choice groups or date buckets",
  );
  const buckets = query.buckets ?? [];
  requireSpec(
    Array.isArray(buckets) &&
      buckets.length <= 366 &&
      (query.dateFieldId !== undefined) === buckets.length > 0,
    "aggregate",
    "Date aggregates need one to 366 buckets",
  );
  const keys = new Set<string>();
  type Instant = [milliseconds: number, micros: number];
  const instant = (text: string): Instant => {
    const { date, micros } = timestampParts(text, "aggregate.buckets");
    return [date.getTime(), Number(micros)];
  };
  const compare = (a: Instant, b: Instant) => a[0] - b[0] || a[1] - b[1];
  let previous: Instant | undefined;
  const normalized = buckets.map((bucket) => {
    requireSpec(
      bucket !== null &&
        typeof bucket === "object" &&
        Object.keys(bucket).every((key) =>
          ["key", "start", "end"].includes(key),
        ) &&
        typeof bucket.key === "string" &&
        typeof bucket.start === "string" &&
        typeof bucket.end === "string" &&
        bucket.start.endsWith("Z") &&
        bucket.end.endsWith("Z"),
      "aggregate.buckets",
      "Buckets need a key and explicit UTC start/end",
    );
    nonblank(bucket.key, "aggregate.buckets", 80);
    requireSpec(
      !keys.has(bucket.key),
      "aggregate.buckets",
      "Bucket keys must be unique",
    );
    keys.add(bucket.key);
    const start = normalizeTimestamp(bucket.start),
      end = normalizeTimestamp(bucket.end),
      a = instant(start),
      b = instant(end);
    requireSpec(
      compare(b, a) > 0 &&
        (previous === undefined || compare(a, previous) >= 0),
      "aggregate.buckets",
      "Buckets must be ordered and non-overlapping",
    );
    previous = b;
    return { key: bucket.key, start, end };
  });
  return {
    metric: query.metric,
    ...(query.fieldId === undefined ? {} : { fieldId: query.fieldId }),
    ...(query.groupFieldId === undefined
      ? {}
      : { groupFieldId: query.groupFieldId }),
    ...(query.dateFieldId === undefined
      ? {}
      : { dateFieldId: query.dateFieldId }),
    ...(normalized.length ? { buckets: normalized } : {}),
  };
}
