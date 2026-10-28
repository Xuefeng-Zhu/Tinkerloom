/** Call only on the output of a JSON/DTO validator, never on arbitrary objects. */
export function freezeValidated<T>(value: T): T {
  if (value !== null && typeof value === "object") {
    for (const child of Object.values(value)) freezeValidated(child);
    Object.freeze(value);
  }
  return value;
}
