import { ownValue } from "../spec/ownValue";
import { getCollection, getField } from "../spec/bindings";
import { canonicalJson } from "../spec/schema";
import {
  normalizeTimestamp,
  validateAggregateQuery,
  validateRecordQuery,
} from "../spec/values";
import type {
  AggregateQuery,
  AppSpec,
  CollectionSpec,
  JsonValue,
  RecordQuery,
  ViewSpec,
} from "../spec/types";
import type { RuntimeAggregate, RuntimeRecord } from "./types";

export const localDayKey = (date: Date): string =>
  `${String(date.getFullYear()).padStart(4, "0")}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
export function localDayRange(date: Date): { start: string; end: string } {
  return {
    start: new Date(
      date.getFullYear(),
      date.getMonth(),
      date.getDate(),
    ).toISOString(),
    end: new Date(
      date.getFullYear(),
      date.getMonth(),
      date.getDate() + 1,
    ).toISOString(),
  };
}
export function monthBuckets(
  month: Date,
): NonNullable<AggregateQuery["buckets"]> {
  const count = new Date(
    month.getFullYear(),
    month.getMonth() + 1,
    0,
  ).getDate();
  return Array.from({ length: count }, (_, i) => {
    const date = new Date(month.getFullYear(), month.getMonth(), i + 1);
    return { key: localDayKey(date), ...localDayRange(date) };
  });
}
/** Construct each boundary in local civil time: DST days are not always 24 hours. */
export function dateBuckets(
  now: Date,
  unit: "day" | "week" | "month" = "day",
  periods = 30,
): NonNullable<AggregateQuery["buckets"]> {
  if (!Number.isInteger(periods) || periods < 1 || periods > 366)
    throw new Error("Expected one to 366 periods");
  const anchor = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (unit === "month") anchor.setDate(1);
  if (unit === "week")
    anchor.setDate(anchor.getDate() - ((anchor.getDay() + 6) % 7));
  const boundary = (offset: number) =>
    unit === "month"
      ? new Date(anchor.getFullYear(), anchor.getMonth() + offset, 1)
      : new Date(
          anchor.getFullYear(),
          anchor.getMonth(),
          anchor.getDate() + offset * (unit === "week" ? 7 : 1),
        );
  return Array.from({ length: periods }, (_, i) => {
    const offset = i + 1 - periods,
      start = boundary(offset);
    return {
      key: localDayKey(start),
      start: start.toISOString(),
      end: boundary(offset + 1).toISOString(),
    };
  });
}
export interface ViewSelection {
  search?: string;
  choices?: Record<string, string>;
  sort?: { fieldId: string; descending: boolean };
  selectedDay?: Date;
  undated?: boolean;
}
export function buildViewQuery(
  spec: AppSpec,
  view: ViewSpec,
  state: ViewSelection = {},
  now = new Date(),
): RecordQuery {
  const collection = getCollection(spec, view.collectionId!);
  const filters = [...(view.query?.filters ?? [])];
  if (view.dateFilter) {
    const { start, end } = localDayRange(now);
    filters.push({
      fieldId: view.dateFilter.fieldId,
      operator: view.dateFilter.period === "today" ? "gte" : "lt",
      value: start,
    });
    if (view.dateFilter.period === "today")
      filters.push({
        fieldId: view.dateFilter.fieldId,
        operator: "lt",
        value: end,
      });
  }
  const title = collection.fields.find((f) => f.id === view.titleFieldId);
  if (
    state.search?.trim() &&
    title?.type === "text" &&
    view.filterFieldIds?.length
  )
    filters.push({
      fieldId: title.id,
      operator: "contains",
      value: state.search.trim(),
    });
  for (const [fieldId, value] of Object.entries(state.choices ?? {}))
    if (view.filterFieldIds?.includes(fieldId) && value)
      filters.push({ fieldId, operator: "eq", value });
  if (view.type === "calendar" && state.selectedDay) {
    const range = localDayRange(state.selectedDay);
    filters.push(
      {
        fieldId: view.options!.dateFieldId,
        operator: "gte",
        value: range.start,
      },
      { fieldId: view.options!.dateFieldId, operator: "lt", value: range.end },
    );
  }
  if (view.type === "timeline" && state.undated)
    filters.push({
      fieldId: view.options!.dateFieldId,
      operator: "eq",
      value: null,
    });
  const sort =
    view.type === "calendar" || view.type === "timeline"
      ? [{ fieldId: view.options!.dateFieldId, descending: false }]
      : state.sort
        ? [state.sort]
        : view.query?.sort;
  return validateRecordQuery(collection, {
    filters,
    ...(sort ? { sort } : {}),
    limit: view.query?.limit ?? 50,
  });
}
/** Compare canonical timestamps including the six fractional digits JS Date drops. */
export function compareTyped(
  type: string,
  a: JsonValue | undefined,
  b: JsonValue | undefined,
): number {
  if (a === b) return 0;
  if (a === undefined || a === null) return 1;
  if (b === undefined || b === null) return -1;
  if (type === "timestamp") {
    const aa = normalizeTimestamp(a),
      bb = normalizeTimestamp(b);
    const milliseconds = (value: string) =>
      Date.parse(
        value.replace(
          /^(-\d{4})-/,
          (_, year: string) => `-${year.slice(1).padStart(6, "0")}-`,
        ),
      );
    const am = aa.slice(aa.indexOf(".") + 1, -1).padEnd(6, "0"),
      bm = bb.slice(bb.indexOf(".") + 1, -1).padEnd(6, "0");
    return (
      milliseconds(aa) - milliseconds(bb) || (am < bm ? -1 : am > bm ? 1 : 0)
    );
  }
  return typeof a === "number" && typeof b === "number"
    ? a - b
    : typeof a === "boolean" && typeof b === "boolean"
      ? Number(a) - Number(b)
      : String(a) < String(b)
        ? -1
        : 1;
}
export function matchingRecords(
  collection: CollectionSpec,
  records: readonly RuntimeRecord[],
  input: RecordQuery,
): RuntimeRecord[] {
  const query = validateRecordQuery(collection, input);
  const result = records.filter(
    (r) =>
      r.collectionId === collection.id &&
      query.filters!.every((f) => {
        const field = getField(collection, f.fieldId),
          value = ownValue(r.data, f.fieldId);
        const compare = (candidate: JsonValue) =>
          compareTyped(field.type, value, candidate);
        switch (f.operator) {
          case "eq":
            return f.value === null
              ? value === undefined
              : compare(f.value) === 0;
          case "in":
            return (f.value as JsonValue[]).some((v) => compare(v) === 0);
          case "contains":
            return (
              typeof value === "string" &&
              value.toLowerCase().includes(String(f.value).toLowerCase())
            );
          case "gte":
            return value !== undefined && compare(f.value) >= 0;
          case "lte":
            return value !== undefined && compare(f.value) <= 0;
          case "lt":
            return value !== undefined && compare(f.value) < 0;
        }
      }),
  );
  return result.sort((a, b) => {
    for (const sort of query.sort!) {
      const av = ownValue(a.data, sort.fieldId),
        bv = ownValue(b.data, sort.fieldId),
        cmp = compareTyped(getField(collection, sort.fieldId).type, av, bv);
      if (cmp)
        return av === undefined || bv === undefined
          ? cmp
          : sort.descending
            ? -cmp
            : cmp;
    }
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
}
export const queryIdentity = (collectionId: string, query: RecordQuery) =>
  canonicalJson({
    collectionId,
    filters: query.filters ?? [],
    sort: query.sort ?? [],
  });
export function aggregateRecords(
  collection: CollectionSpec,
  records: readonly RuntimeRecord[],
  query: RecordQuery,
  input: AggregateQuery,
  versionId: string,
): RuntimeAggregate {
  const aggregate = validateAggregateQuery(collection, input),
    rows = matchingRecords(collection, records, query);
  const value = (items: readonly RuntimeRecord[]) => {
    if (aggregate.metric === "count") return items.length;
    const numbers = items
      .map((r) => ownValue(r.data, aggregate.fieldId!))
      .filter((v): v is number => typeof v === "number");
    const sum = numbers.reduce((a, b) => a + b, 0);
    return aggregate.metric === "sum"
      ? sum
      : numbers.length
        ? sum / numbers.length
        : null;
  };
  const groups: RuntimeAggregate["groups"] = [];
  if (aggregate.groupFieldId) {
    const f = getField(collection, aggregate.groupFieldId);
    for (const key of [...(f.choices ?? []), ""]) {
      const matches = rows.filter(
        (r) => (ownValue(r.data, f.id) ?? "") === key,
      );
      if (key !== "" || matches.length)
        groups.push({ key, count: matches.length, value: value(matches) });
    }
  }
  if (aggregate.dateFieldId)
    for (const bucket of aggregate.buckets!) {
      const matches = rows.filter(
        (r) =>
          ownValue(r.data, aggregate.dateFieldId!) !== undefined &&
          compareTyped(
            "timestamp",
            ownValue(r.data, aggregate.dateFieldId!),
            bucket.start,
          ) >= 0 &&
          compareTyped(
            "timestamp",
            ownValue(r.data, aggregate.dateFieldId!),
            bucket.end,
          ) < 0,
      );
      groups.push({
        key: bucket.key,
        count: matches.length,
        value: value(matches),
      });
    }
  return { total: rows.length, value: value(rows), groups, versionId };
}
