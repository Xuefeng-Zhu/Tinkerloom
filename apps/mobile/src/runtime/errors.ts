import { BackendError } from "../backend/errors";

export class RuntimeError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly uncertain = false,
  ) {
    super(message);
    this.name = "RuntimeError";
  }
}
export const unavailable = (feature: string): never => {
  throw new RuntimeError(
    "unavailable",
    `${feature} is not available in this runtime.`,
  );
};
export function runtimeError(error: unknown, mutation = false): RuntimeError {
  if (error instanceof RuntimeError) return error;
  if (error instanceof BackendError)
    return new RuntimeError(
      error.kind === "unauthenticated" || error.status === 401
        ? "unauthenticated"
        : error.status === 403 && error.code !== "app_archived"
          ? "forbidden"
          : error.code,
      error.message,
      error.uncertain ||
        (mutation &&
          (error.code === "transaction_conflict" ||
            error.kind === "invalid_response" ||
            error.kind === "transport")),
    );
  // A response may have been lost after the server committed. Never infer failure
  // from a network exception and never create a new key automatically.
  return new RuntimeError(
    mutation ? "outcome_unknown" : "read_failed",
    mutation
      ? "The result could not be confirmed. Retry the retained command to check its outcome."
      : "The data could not be loaded. Try again.",
    mutation,
  );
}
export function ensure(
  condition: unknown,
  code: string,
  message: string,
): asserts condition {
  if (!condition) throw new RuntimeError(code, message);
}
export function isRuntimeAccessFailure(error: RuntimeError): boolean {
  return [
    "forbidden",
    "unauthenticated",
    "user_jwt_invalid",
    "user_unauthorized",
    "session_expired",
    "authorization_failure",
  ].includes(error.code);
}
