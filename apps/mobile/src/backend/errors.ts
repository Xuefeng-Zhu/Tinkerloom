export type BackendErrorKind =
  | "unauthenticated"
  | "transport"
  | "invalid_response"
  | "service"
  | "configuration";

export class BackendError extends Error {
  readonly name = "BackendError";

  constructor(
    message: string,
    readonly code: string,
    readonly kind: BackendErrorKind,
    readonly uncertain = false,
    readonly status?: number,
  ) {
    super(message);
  }
}

export function normalizeError(error: unknown, mutation = false): BackendError {
  if (error instanceof BackendError) return error;
  const details =
    error !== null && typeof error === "object"
      ? (error as { code?: unknown; type?: unknown })
      : {};
  const status = typeof details.code === "number" ? details.code : undefined;
  const code =
    typeof details.type === "string" && /^[a-z0-9_]+$/.test(details.type)
      ? details.type
      : "appwrite_error";
  if (status === 401) {
    return new BackendError(
      "Please sign in again.",
      code,
      "unauthenticated",
      false,
      status,
    );
  }
  if (status === undefined || status === 0) {
    return new BackendError(
      mutation
        ? "The connection was interrupted. The result is unknown. Retry this same request."
        : "Could not connect. Check your connection and try again.",
      "connection_failed",
      "transport",
      mutation,
    );
  }
  return new BackendError(
    status === 429
      ? "Too many requests. Wait a moment and try again."
      : status === 403
        ? "You do not have permission to do that."
        : "Appwrite could not complete the request.",
    code,
    "service",
    mutation && status >= 500,
    status,
  );
}
