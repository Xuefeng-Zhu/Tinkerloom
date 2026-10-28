/** Treat record maps as data: inherited members and accessors are never field values. */
export function ownValue<T>(
  values: Readonly<Record<string, T>> | null | undefined,
  key: string,
): T | undefined {
  if (values === null || values === undefined) return undefined;
  const descriptor = Object.getOwnPropertyDescriptor(values, key);
  return descriptor && "value" in descriptor
    ? (descriptor.value as T)
    : undefined;
}
