import { BackendError, normalizeError } from "./errors";
import type {
  AppBackend,
  CreateApp,
  CreateWorkspace,
  MiniApp,
  User,
  Workspace,
} from "./types";

export interface SdkAccount {
  get(): Promise<unknown>;
  create(input: {
    userId: string;
    email: string;
    password: string;
    name: string;
  }): Promise<unknown>;
  createEmailPasswordSession(input: {
    email: string;
    password: string;
  }): Promise<unknown>;
  deleteSession(input: { sessionId: string }): Promise<unknown>;
}

export interface ExecutionResult {
  status: unknown;
  responseStatusCode: unknown;
  responseBody: unknown;
}

export interface SdkAdapter {
  account: SdkAccount;
  execute(body: string): Promise<ExecutionResult>;
  newId(): string;
}

const idPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/;

function invalidResponse(mutation = false): never {
  throw new BackendError(
    mutation
      ? "The server response could not be confirmed. Retry this same request."
      : "The server returned an invalid response.",
    "invalid_response",
    "invalid_response",
    mutation,
  );
}

function object(value: unknown, mutation = false): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    invalidResponse(mutation);
  return value as Record<string, unknown>;
}

function id(value: unknown, mutation = false): string {
  if (typeof value !== "string" || !idPattern.test(value))
    invalidResponse(mutation);
  return value;
}

function title(value: unknown, mutation = false): string {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > 128 ||
    value.trim() !== value
  ) {
    invalidResponse(mutation);
  }
  return value;
}

function workspace(value: unknown, mutation = false): Workspace {
  const row = object(value, mutation);
  return { id: id(row.id, mutation), name: title(row.name, mutation) };
}

function app(value: unknown, workspaceId: string, mutation = false): MiniApp {
  const row = object(value, mutation);
  const parsed = {
    ...workspace(row, mutation),
    workspaceId: id(row.workspaceId, mutation),
  };
  if (parsed.workspaceId !== workspaceId) invalidResponse(mutation);
  return parsed;
}

function list<T extends { id: string }>(
  value: unknown,
  parse: (value: unknown) => T,
): T[] {
  if (!Array.isArray(value) || value.length > 100) invalidResponse();
  const rows = value.map(parse);
  if (new Set(rows.map((row) => row.id)).size !== rows.length)
    invalidResponse();
  return rows;
}

function parseUser(value: unknown): User {
  const row = object(value);
  const userId = id(row.$id);
  if (
    typeof row.email !== "string" ||
    !row.email ||
    row.email.length > 320 ||
    typeof row.name !== "string" ||
    row.name.length > 128
  )
    invalidResponse();
  return { id: userId, email: row.email, name: row.name };
}

function validateCommand(command: CreateWorkspace): CreateWorkspace {
  const name = command.name.trim();
  if (!idPattern.test(command.id) || !name || name.length > 128) {
    throw new BackendError(
      "Use a name between 1 and 128 characters.",
      "invalid_request",
      "service",
      false,
      400,
    );
  }
  return { id: command.id, name };
}

export class AppwriteBackend implements AppBackend {
  constructor(private readonly sdk: SdkAdapter) {}

  newId() {
    return this.sdk.newId();
  }

  async currentUser(): Promise<User | null> {
    try {
      return parseUser(await this.sdk.account.get());
    } catch (error) {
      const normalized = normalizeError(error);
      if (normalized.kind === "unauthenticated") return null;
      throw normalized;
    }
  }

  async signIn(email: string, password: string): Promise<User> {
    let sessionCreated = false;
    try {
      await this.sdk.account.createEmailPasswordSession({
        email: email.trim(),
        password,
      });
      sessionCreated = true;
      return await this.userForEmail(email);
    } catch (error) {
      if (
        error instanceof BackendError &&
        error.code === "existing_session_mismatch"
      )
        throw error;
      // A session mutation may have reached Appwrite before the response was
      // lost. Reconcile once with a read; never repeat the mutation here.
      try {
        return await this.userForEmail(email);
      } catch (reconciliationError) {
        if (
          reconciliationError instanceof BackendError &&
          reconciliationError.code === "existing_session_mismatch"
        ) {
          throw reconciliationError;
        }
        const failure = normalizeError(error, true);
        const reconciliation = normalizeError(reconciliationError);
        if (
          sessionCreated ||
          failure.uncertain ||
          reconciliation.kind !== "unauthenticated"
        ) {
          throw new BackendError(
            "We could not confirm sign-in. Check your existing session before trying again.",
            failure.code,
            failure.kind === "unauthenticated" ? "transport" : failure.kind,
            true,
            failure.status,
          );
        }
        throw failure;
      }
    }
  }

  private async userForEmail(email: string): Promise<User> {
    const user = parseUser(await this.sdk.account.get());
    if (user.email.trim().toLowerCase() !== email.trim().toLowerCase()) {
      throw new BackendError(
        "A different account is already signed in. Check the existing session and sign out before using another email.",
        "existing_session_mismatch",
        "service",
      );
    }
    return user;
  }

  async signUp(email: string, password: string, name: string): Promise<User> {
    try {
      await this.sdk.account.create({
        userId: this.newId(),
        email: email.trim(),
        password,
        name: name.trim(),
      });
    } catch (error) {
      const failure = normalizeError(error, true);
      if (failure.uncertain || failure.status === 409) {
        throw new BackendError(
          "An account with this email may already exist. Use Sign in or check your existing session before creating an account again.",
          failure.code,
          failure.kind,
          failure.uncertain,
          failure.status,
        );
      }
      throw failure;
    }
    try {
      return await this.signIn(email, password);
    } catch (error) {
      const failure = normalizeError(error);
      if (failure.code === "existing_session_mismatch") throw failure;
      throw new BackendError(
        "Your account was created, but sign-in could not be confirmed. Use Sign in or check your existing session to continue.",
        failure.code,
        failure.kind,
        failure.uncertain,
        failure.status,
      );
    }
  }

  async signOut(): Promise<void> {
    try {
      await this.sdk.account.deleteSession({ sessionId: "current" });
    } catch (error) {
      const normalized = normalizeError(error);
      if (normalized.kind !== "unauthenticated") throw normalized;
    }
  }

  private async request(payload: Record<string, string>, mutation = false) {
    try {
      const execution = await this.sdk.execute(JSON.stringify(payload));
      if (execution.status !== "completed") {
        throw new BackendError(
          mutation
            ? "The result is unknown. Retry this same request."
            : "The server did not complete the request.",
          "execution_incomplete",
          "service",
          mutation,
        );
      }
      if (
        typeof execution.responseBody !== "string" ||
        execution.responseBody.length > 262_144 ||
        !Number.isInteger(execution.responseStatusCode)
      )
        invalidResponse(mutation);
      const status = execution.responseStatusCode as number;
      if (status < 100 || status > 599) invalidResponse(mutation);
      let data: Record<string, unknown>;
      try {
        data = object(JSON.parse(execution.responseBody), mutation);
      } catch (error) {
        if (error instanceof BackendError) throw error;
        invalidResponse(mutation);
      }
      if (status < 200 || status >= 300) {
        const code =
          typeof data.error === "string" && /^[a-z0-9_]+$/.test(data.error)
            ? data.error
            : "service_error";
        throw new BackendError(
          code === "id_conflict"
            ? "This request ID was already used for different data."
            : code === "not_found"
              ? "That workspace is unavailable."
              : status === 401
                ? "Please sign in again."
                : status === 429
                  ? "Too many requests. Wait a moment and try again."
                  : "The server could not complete the request.",
          code,
          status === 401 ? "unauthenticated" : "service",
          mutation && status >= 500,
          status,
        );
      }
      return data;
    } catch (error) {
      throw normalizeError(error, mutation);
    }
  }

  async listWorkspaces(): Promise<Workspace[]> {
    return list(
      (await this.request({ op: "listWorkspaces" })).workspaces,
      (row) => workspace(row),
    );
  }

  async createWorkspace(command: CreateWorkspace): Promise<void> {
    const valid = validateCommand(command);
    const row = workspace(
      (await this.request({ op: "createWorkspace", ...valid }, true)).workspace,
      true,
    );
    if (row.id !== valid.id || row.name !== valid.name) invalidResponse(true);
  }

  async listApps(workspaceId: string): Promise<MiniApp[]> {
    if (!idPattern.test(workspaceId))
      throw new BackendError(
        "Choose a workspace first.",
        "invalid_id",
        "service",
        false,
        400,
      );
    return list(
      (await this.request({ op: "listApps", workspaceId })).apps,
      (row) => app(row, workspaceId),
    );
  }

  async createApp(command: CreateApp): Promise<void> {
    const valid = validateCommand(command);
    if (!idPattern.test(command.workspaceId))
      throw new BackendError(
        "Choose a workspace first.",
        "invalid_id",
        "service",
        false,
        400,
      );
    const row = app(
      (
        await this.request(
          { op: "createApp", ...valid, workspaceId: command.workspaceId },
          true,
        )
      ).app,
      command.workspaceId,
      true,
    );
    if (row.id !== valid.id || row.name !== valid.name) invalidResponse(true);
  }
}
