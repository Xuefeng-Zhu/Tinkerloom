/** Dart String.trim's Unicode White_Space set plus BOM; JS trim omits NEL. */
export function canonicalText(value: string): string {
  return value.replace(/^[\s\u0085]+|[\s\u0085]+$/g, "");
}
