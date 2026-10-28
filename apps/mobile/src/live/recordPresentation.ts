import type { Field, Values } from "../preview/model";

export interface DisplayRecord {
  id: string;
  values: Values;
}

/** Retain zero and false: an empty cell is not the same as a falsy value. */
export function displayFieldValue(
  field: Field,
  value: Values[string] | undefined,
): string {
  if (field.kind === "boolean") return value === true ? "Yes" : "No";
  return value === undefined || value === "" ? "—" : String(value);
}

/** Civil dates are already validated by the definition domain; never convert them to instants. */
export function agendaGroups<T extends DisplayRecord>(
  records: readonly T[],
  dateFieldId: string,
): { date: string | null; records: T[] }[] {
  const dated = new Map<string, T[]>();
  const undated: T[] = [];
  for (const record of records) {
    const value = record.values[dateFieldId];
    if (typeof value !== "string" || value === "") {
      undated.push(record);
      continue;
    }
    const group = dated.get(value);
    if (group) group.push(record);
    else dated.set(value, [record]);
  }
  const groups: { date: string | null; records: T[] }[] = [...dated.keys()]
    .sort()
    .map((date) => ({ date, records: dated.get(date)! }));
  if (undated.length) groups.push({ date: null, records: undated });
  return groups;
}
