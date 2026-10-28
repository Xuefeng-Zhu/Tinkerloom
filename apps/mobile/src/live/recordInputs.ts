import { parseNumericInput, validateValues } from "../preview/model";
import type { Definition, Values } from "../preview/model";

/** Keep unfinished numeric text in the editor; conversion happens only on save. */
export function prepareRecordValues(
  definition: Definition,
  inputs: Values,
): Values {
  const values = { ...inputs };
  for (const field of definition.fields) {
    if (field.kind !== "number") continue;
    const input = inputs[field.id];
    if (input !== undefined && typeof input !== "string") continue;
    try {
      values[field.id] = parseNumericInput(
        typeof input === "string" ? input : "",
      );
    } catch (failure) {
      throw new Error(
        `${field.label}: ${failure instanceof Error ? failure.message : "Enter a valid number."}`,
      );
    }
  }
  return validateValues(definition, values);
}

export function recordInputHint(
  kind: string,
  required?: boolean,
): string | undefined {
  const prefix = required ? "Required. " : "Optional. ";
  if (kind === "date")
    return `${prefix}Use YYYY-MM-DD, for example 2026-10-28. Dates have no time zone.`;
  if (kind === "number")
    return `${prefix}Enter a number between −1,000,000,000,000,000 and 1,000,000,000,000,000. Leave optional values blank.`;
  return required ? "Required" : undefined;
}
