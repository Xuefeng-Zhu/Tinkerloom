import { BackendError } from "./errors";

export const idPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/;
export const REVISION_LIMIT = 2_147_483_647;
export function validId(value: unknown): value is string {
  return typeof value === "string" && idPattern.test(value);
}
export function invalidResponse(mutation = false): never {
  throw new BackendError(
    mutation
      ? "The server response could not be confirmed. Retry this same request."
      : "The server returned an invalid response.",
    "invalid_response",
    "invalid_response",
    mutation,
  );
}
export function invalidRequest(): never {
  throw new BackendError(
    "This request is invalid. Refresh and try again.",
    "invalid_request",
    "service",
    false,
    400,
  );
}
export function object(
  value: unknown,
  mutation = false,
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    invalidResponse(mutation);
  return value as Record<string, unknown>;
}
export function id(value: unknown, mutation = false): string {
  if (!validId(value)) invalidResponse(mutation);
  return value;
}
export function validRevision(value: unknown, minimum = 0): value is number {
  return (
    Number.isInteger(value) &&
    (value as number) >= minimum &&
    (value as number) < REVISION_LIMIT
  );
}
export function revision(
  value: unknown,
  minimum = 0,
  mutation = false,
): number {
  if (!validRevision(value, minimum)) invalidResponse(mutation);
  return value;
}
export function exactKeys(
  data: Record<string, unknown>,
  keys: string[],
  mutation = false,
) {
  if (
    Object.keys(data).length !== keys.length ||
    keys.some((key) => !Object.prototype.hasOwnProperty.call(data, key))
  )
    invalidResponse(mutation);
}
export function operation(command: { appId: string; operationId: string }) {
  if (!validId(command.appId) || !validId(command.operationId))
    invalidRequest();
}
export function pageInput(appId: string, afterId?: string) {
  if (!validId(appId) || (afterId !== undefined && !validId(afterId)))
    invalidRequest();
  return { appId, ...(afterId !== undefined ? { afterId } : {}) };
}
export function pageCursor(value: unknown, afterId?: string): string | null {
  const next = value === null ? null : id(value);
  if (next !== null && next === afterId) invalidResponse();
  return next;
}
