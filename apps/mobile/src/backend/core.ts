import { BackendError, normalizeError } from "./errors";
import { canonicalText } from "../preview/canonicalText";
import { access } from "./access";
import { CollaborationRpc } from "./collaboration";
import { runtimeJsonSnapshot } from "../runtime/json";
import { utf8Bytes } from "../spec/schema";
import {
  idPattern,
  invalidResponse,
  object,
  id,
  revision,
  validRevision,
  operation,
} from "./validation";
import type {
  AppBackend,
  CreateApp,
  CreateWorkspace,
  MiniApp,
  User,
  Workspace,
  AppDocument,
  LiveRecord,
  RecordPage,
  SaveDraft,
  PublishApp,
  SaveRecord,
  CreateInvitation,
  AcceptInvitation,
  RevokeInvitation,
  SetGrant,
  ArchiveApp,
} from "./types";
import { NUMBER_LIMIT, validateDefinition } from "../preview/model";
import type {
  Definition,
  DefinitionView,
  Field,
  Values,
} from "../preview/model";

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

function title(value: unknown, mutation = false): string {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > 128 ||
    canonicalText(value) !== value
  ) {
    invalidResponse(mutation);
  }
  return value;
}

function workspace(
  value: unknown,
  mutation = false,
  legacy = false,
): Workspace {
  const row = object(value, mutation);
  if (Object.keys(row).some((key) => !["id", "name", "role"].includes(key)))
    invalidResponse(mutation);
  if (
    !(legacy && row.role === undefined) &&
    row.role !== "owner" &&
    row.role !== "member"
  )
    invalidResponse(mutation);
  return {
    id: id(row.id, mutation),
    name: title(row.name, mutation),
    ...(row.role === undefined ? {} : { role: row.role as Workspace["role"] }),
  };
}

function app(
  value: unknown,
  workspaceId: string,
  mutation = false,
  legacy = false,
  summary = false,
): MiniApp {
  const row = object(value, mutation);
  if (
    summary &&
    Object.keys(row).some(
      (key) =>
        ![
          "id",
          "name",
          "workspaceId",
          "role",
          "archived",
          "capabilities",
          "engine",
        ].includes(key),
    )
  )
    invalidResponse(mutation);
  if (
    row.engine !== undefined &&
    row.engine !== "bounded.v1" &&
    row.engine !== "appspec.v1"
  )
    invalidResponse(mutation);
  const parsed = {
    id: id(row.id, mutation),
    name: title(row.name, mutation),
    workspaceId: id(row.workspaceId, mutation),
    ...access(row, mutation, legacy),
    ...(row.engine === undefined
      ? {}
      : { engine: row.engine as MiniApp["engine"] }),
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
  const name = canonicalText(command.name);
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

function definition(value: unknown, mutation = false): Definition {
  try {
    const data = object(value, mutation);
    if (!Array.isArray(data.fields) || data.fields.length > 10)
      invalidResponse(mutation);
    const fields: Field[] = data.fields.map((entry) => {
      const field = object(entry, mutation);
      if (
        typeof field.id !== "string" ||
        typeof field.label !== "string" ||
        typeof field.kind !== "string" ||
        (field.required !== undefined && typeof field.required !== "boolean")
      )
        invalidResponse(mutation);
      if (
        field.options !== undefined &&
        (!Array.isArray(field.options) ||
          field.options.some((option) => typeof option !== "string"))
      )
        invalidResponse(mutation);
      return {
        id: field.id,
        label: canonicalText(field.label),
        kind: field.kind as Field["kind"],
        required: field.required === true,
        ...(field.options !== undefined
          ? {
              options: (field.options as string[]).map((option) =>
                canonicalText(option),
              ),
            }
          : {}),
      };
    });
    if (
      typeof data.title !== "string" ||
      typeof data.description !== "string" ||
      typeof data.primaryFieldId !== "string"
    )
      invalidResponse(mutation);
    const result: Definition = {
      title: canonicalText(data.title),
      description: data.description,
      primaryFieldId: data.primaryFieldId,
      fields,
    };
    if (data.view !== undefined) {
      const rawView = object(data.view, mutation);
      if (
        Object.keys(rawView).some(
          (key) => key !== "kind" && key !== "dateFieldId",
        ) ||
        !["list", "table", "agenda"].includes(rawView.kind as string)
      )
        invalidResponse(mutation);
      if (rawView.kind === "agenda") {
        if (typeof rawView.dateFieldId !== "string") invalidResponse(mutation);
        result.view = { kind: "agenda", dateFieldId: rawView.dateFieldId };
      } else {
        if (Object.prototype.hasOwnProperty.call(rawView, "dateFieldId"))
          invalidResponse(mutation);
        result.view = { kind: rawView.kind } as DefinitionView;
      }
    }
    validateDefinition(result);
    return result;
  } catch {
    invalidResponse(mutation);
  }
}

function document(
  value: unknown,
  mutation = false,
  legacy = false,
): AppDocument {
  const data = object(value, mutation);
  if (
    Object.keys(data).some(
      (key) =>
        ![
          "id",
          "name",
          "workspaceId",
          "role",
          "archived",
          "capabilities",
          "draftRevision",
          "candidateRevision",
          "basePublishedRevision",
          "publishedRevision",
          "definition",
          "publishedDefinition",
        ].includes(key),
    )
  )
    invalidResponse(mutation);
  const base = app(data, id(data.workspaceId, mutation), mutation, legacy);
  const draftRevision = revision(data.draftRevision, 0, mutation);
  const publishedRevision = revision(data.publishedRevision, 0, mutation);
  const oldReceipt = base.role === undefined;
  if (
    (draftRevision === 0) !== (data.definition === null) ||
    (publishedRevision === 0) !== (data.publishedDefinition === null)
  )
    invalidResponse(mutation);
  let candidate: Pick<
    AppDocument,
    "candidateRevision" | "basePublishedRevision"
  > = {};
  if (oldReceipt) {
    if (
      publishedRevision > draftRevision ||
      Object.prototype.hasOwnProperty.call(data, "candidateRevision") ||
      Object.prototype.hasOwnProperty.call(data, "basePublishedRevision")
    )
      invalidResponse(mutation);
  } else {
    const candidateRevision = revision(data.candidateRevision, 0, mutation);
    const basePublishedRevision = revision(
      data.basePublishedRevision,
      0,
      mutation,
    );
    if (
      (draftRevision === 0) !== (candidateRevision === 0) ||
      basePublishedRevision > publishedRevision ||
      (draftRevision === 0 && basePublishedRevision !== publishedRevision) ||
      ((base.role === "member" || base.role === "viewer") &&
        draftRevision !== 0)
    )
      invalidResponse(mutation);
    candidate = { candidateRevision, basePublishedRevision };
  }
  return {
    ...base,
    ...candidate,
    draftRevision,
    publishedRevision,
    definition:
      data.definition === null ? null : definition(data.definition, mutation),
    publishedDefinition:
      data.publishedDefinition === null
        ? null
        : definition(data.publishedDefinition, mutation),
  };
}

function validPrimitiveValues(values: Record<string, unknown>): boolean {
  return !(
    Object.keys(values).length > 10 ||
    Object.entries(values).some(
      ([key, value]) =>
        !/^[a-z][a-zA-Z0-9_]{0,31}$/.test(key) ||
        (typeof value !== "string" &&
          typeof value !== "boolean" &&
          typeof value !== "number") ||
        (typeof value === "string" && value.length > 4000) ||
        (typeof value === "number" &&
          (!Number.isFinite(value) || Math.abs(value) > NUMBER_LIMIT)),
    )
  );
}

function record(value: unknown, mutation = false): LiveRecord {
  const data = object(value, mutation);
  const values = object(data.values, mutation);
  if (!validPrimitiveValues(values)) invalidResponse(mutation);
  return {
    id: id(data.id, mutation),
    revision: revision(data.revision, 1, mutation),
    values: { ...values } as Values,
  };
}

function validateOperation(command: {
  appId: string;
  operationId: string;
  expectedRevision: number;
}): void {
  operation(command);
  if (!validRevision(command.expectedRevision)) {
    throw new BackendError(
      "This save is invalid. Reload the app and try again.",
      "invalid_request",
      "service",
      false,
      400,
    );
  }
}

function limitContent(value: unknown, label: string): void {
  let serialized: string | undefined;
  try {
    serialized = JSON.stringify(value);
  } catch {
    /* Rejected before dispatch below. */
  }
  if (typeof serialized !== "string")
    throw new BackendError(
      "This content cannot be saved.",
      "invalid_request",
      "service",
      false,
      400,
    );
  let bytes = 0;
  for (const character of serialized) {
    const code = character.codePointAt(0)!;
    bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
    if (bytes > 16384) {
      throw new BackendError(
        `${label} is too large. Shorten the content before saving.`,
        "content_too_large",
        "service",
        false,
        400,
      );
    }
  }
}

export class AppwriteBackend implements AppBackend {
  private readonly collaboration: CollaborationRpc;
  constructor(private readonly sdk: SdkAdapter) {
    this.collaboration = new CollaborationRpc((payload, mutation) =>
      this.request(payload, mutation),
    );
  }

  async executeSpec(
    payload: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    let request: Record<string, unknown>;
    try {
      request = runtimeJsonSnapshot(payload) as Record<string, unknown>;
    } catch {
      throw new BackendError(
        "This request is invalid or too large. It has not been sent.",
        "invalid_request",
        "service",
        false,
        400,
      );
    }
    const op = request?.op;
    if (
      typeof op !== "string" ||
      !(op.startsWith("spec.") || op === "listMembers")
    )
      throw new BackendError(
        "That operation is unavailable.",
        "invalid_request",
        "service",
        false,
        400,
      );
    const reads = new Set([
      "spec.capabilities",
      "spec.templates",
      "spec.getApp",
      "spec.watch",
      "spec.appAccess",
      "spec.launcher",
      "spec.listDrafts",
      "spec.listVersions",
      "spec.getVersion",
      "spec.review",
      "spec.query",
      "spec.getRecord",
      "spec.summary",
      "spec.aggregate",
      "spec.getGeneration",
      "spec.reminderState",
      "spec.inbox",
      "spec.runs",
      "spec.media.usage",
      "spec.media.status",
      "spec.media.read",
      "listMembers",
    ]);
    return this.request(request, !reads.has(op));
  }

  createInvitation(command: CreateInvitation) {
    return this.collaboration.createInvitation(command);
  }
  acceptInvitation(command: AcceptInvitation) {
    return this.collaboration.acceptInvitation(command);
  }
  inspectInvitation(token: string) {
    return this.collaboration.inspectInvitation(token);
  }
  listInvitations(appId: string, afterId?: string) {
    return this.collaboration.listInvitations(appId, afterId);
  }
  revokeInvitation(command: RevokeInvitation) {
    return this.collaboration.revokeInvitation(command);
  }
  listMembers(appId: string, afterId?: string) {
    return this.collaboration.listMembers(appId, afterId);
  }
  setGrant(command: SetGrant) {
    return this.collaboration.setGrant(command);
  }
  async archiveAppAccess(command: ArchiveApp): Promise<MiniApp> {
    operation(command);
    // Full AppSpec archive receipts can include two large immutable definition
    // snapshots. Parse only shared metadata, never a fabricated bounded app.
    const envelope = await this.request(
      { op: "archiveApp", ...command },
      true,
      true,
    );
    if (
      Object.keys(envelope).length !== 1 ||
      !Object.prototype.hasOwnProperty.call(envelope, "app")
    )
      invalidResponse(true);
    const row = object(envelope.app, true);
    const result = app(row, id(row.workspaceId, true), true);
    if (
      result.id !== command.appId ||
      result.role !== "owner" ||
      result.archived !== true
    )
      invalidResponse(true);
    return result;
  }

  async archiveApp(command: ArchiveApp): Promise<AppDocument> {
    operation(command);
    const result = document(
      (await this.request({ op: "archiveApp", ...command }, true)).app,
      true,
    );
    if (
      result.id !== command.appId ||
      result.role !== "owner" ||
      result.archived !== true
    )
      invalidResponse(true);
    return result;
  }

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

  private async request(
    payload: Record<string, unknown>,
    mutation = false,
    fullResponse = false,
  ) {
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
        execution.responseBody.length >
          (fullResponse || String(payload.op).startsWith("spec.")
            ? 8_388_608
            : 262_144) ||
        utf8Bytes(execution.responseBody) >
          (fullResponse || String(payload.op).startsWith("spec.")
            ? 8_388_608
            : 262_144) ||
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
              ? "That item is unavailable."
              : code === "invitation_unavailable"
                ? "This invitation is unavailable or has expired. Ask for a new invitation."
                : code === "app_archived"
                  ? "This app is archived and read-only."
                  : code === "forbidden" || status === 403
                    ? "You do not have permission to do that."
                    : code === "operation_conflict"
                      ? "This request ID was already used for different data."
                      : code === "transaction_conflict"
                        ? "Another save happened at the same time. Retry this same save."
                        : code === "revision_conflict" ||
                            code === "definition_conflict"
                          ? "This app changed. Refresh it before saving again."
                          : code === "incompatible_definition"
                            ? "This update would invalidate existing records. Keep existing fields and choices."
                            : code === "not_published"
                              ? "Publish the app before adding live records."
                              : status === 401
                                ? "Please sign in again."
                                : status === 429
                                  ? "Too many requests. Wait a moment and try again."
                                  : "The server could not complete the request.",
          code,
          status === 401 ? "unauthenticated" : "service",
          mutation && (status >= 500 || code === "transaction_conflict"),
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
      true,
    );
    if (
      row.id !== valid.id ||
      row.name !== valid.name ||
      (row.role !== undefined && row.role !== "owner")
    )
      invalidResponse(true);
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
      (row) => app(row, workspaceId, false, false, true),
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
      true,
      true,
    );
    if (
      row.id !== valid.id ||
      row.name !== valid.name ||
      (row.role !== undefined && (row.role !== "owner" || row.archived))
    )
      invalidResponse(true);
  }

  async getAppAccess(appId: string): Promise<MiniApp> {
    if (!idPattern.test(appId))
      throw new BackendError(
        "That app is unavailable.",
        "invalid_id",
        "service",
        false,
        400,
      );
    const envelope = await this.request({ op: "getAppAccess", appId });
    if (
      Object.keys(envelope).length !== 1 ||
      !Object.prototype.hasOwnProperty.call(envelope, "app")
    )
      invalidResponse();
    const row = object(envelope.app);
    const result = app(row, id(row.workspaceId), false, false, true);
    if (result.id !== appId || result.engine === undefined) invalidResponse();
    return result;
  }

  async getApp(appId: string): Promise<AppDocument> {
    if (!idPattern.test(appId))
      throw new BackendError(
        "That app is unavailable.",
        "invalid_id",
        "service",
        false,
        400,
      );
    const result = document((await this.request({ op: "getApp", appId })).app);
    if (result.id !== appId) invalidResponse();
    return result;
  }

  async saveDraft(command: SaveDraft): Promise<AppDocument> {
    validateOperation(command);
    if (!validRevision(command.expectedPublishedRevision))
      throw new BackendError(
        "Refresh the published app before saving the draft.",
        "invalid_request",
        "service",
        false,
        400,
      );
    const candidate = definition(command.definition);
    limitContent(candidate, "This app definition");
    const result = document(
      (await this.request({ op: "saveDraft", ...command }, true)).app,
      true,
      true,
    );
    if (
      result.id !== command.appId ||
      result.draftRevision !== command.expectedRevision + 1 ||
      (result.role !== undefined &&
        (result.publishedRevision !== command.expectedPublishedRevision ||
          result.basePublishedRevision !== command.expectedPublishedRevision ||
          !result.candidateRevision ||
          result.candidateRevision <= command.expectedPublishedRevision ||
          !result.capabilities?.editDefinition)) ||
      JSON.stringify(result.definition) !== JSON.stringify(candidate)
    )
      invalidResponse(true);
    return result;
  }

  async publishApp(command: PublishApp): Promise<AppDocument> {
    validateOperation(command);
    if (
      !validRevision(command.expectedPublishedRevision) ||
      !validRevision(command.candidateRevision, 1) ||
      command.expectedRevision < 1
    )
      throw new BackendError(
        "Review the saved draft before publication.",
        "invalid_request",
        "service",
        false,
        400,
      );
    const result = document(
      (await this.request({ op: "publishApp", ...command }, true)).app,
      true,
      true,
    );
    if (
      result.id !== command.appId ||
      result.draftRevision !== command.expectedRevision ||
      (result.role === undefined
        ? result.publishedRevision !== command.expectedRevision ||
          command.candidateRevision !== command.expectedRevision
        : result.publishedRevision !== command.candidateRevision ||
          result.candidateRevision !== command.candidateRevision ||
          result.basePublishedRevision !== command.candidateRevision ||
          !result.capabilities?.editDefinition) ||
      JSON.stringify(result.definition) !==
        JSON.stringify(result.publishedDefinition)
    )
      invalidResponse(true);
    return result;
  }

  async listRecords(
    appId: string,
    definitionRevision: number,
    afterId?: string,
  ): Promise<RecordPage> {
    if (
      !idPattern.test(appId) ||
      !validRevision(definitionRevision, 1) ||
      (afterId !== undefined && !idPattern.test(afterId))
    ) {
      throw new BackendError(
        "Refresh the published app before loading records.",
        "invalid_request",
        "service",
        false,
        400,
      );
    }
    const data = await this.request({
      op: "listRecords",
      appId,
      definitionRevision,
      ...(afterId ? { afterId } : {}),
    });
    const records = list(data.records, (row) => record(row));
    if (
      records.length > 10 ||
      revision(data.definitionRevision, 1) !== definitionRevision
    )
      invalidResponse();
    const nextCursor = data.nextCursor === null ? null : id(data.nextCursor);
    if (
      nextCursor &&
      (records.length === 0 ||
        nextCursor !== records[records.length - 1].id ||
        nextCursor === afterId)
    )
      invalidResponse();
    return { records, definitionRevision, nextCursor };
  }

  async saveRecord(command: SaveRecord): Promise<LiveRecord> {
    validateOperation(command);
    if (
      !command.values ||
      typeof command.values !== "object" ||
      Array.isArray(command.values) ||
      !validPrimitiveValues(command.values)
    ) {
      throw new BackendError(
        "Please review the record fields before saving.",
        "invalid_values",
        "service",
        false,
        400,
      );
    }
    limitContent(command.values, "This record");
    if (
      !idPattern.test(command.id) ||
      !validRevision(command.definitionRevision, 1)
    ) {
      throw new BackendError(
        "Refresh the published app before saving records.",
        "invalid_request",
        "service",
        false,
        400,
      );
    }
    const data = await this.request({ op: "saveRecord", ...command }, true);
    const result = record(data.record, true);
    if (
      result.id !== command.id ||
      result.revision !== command.expectedRevision + 1 ||
      revision(data.definitionRevision, 1, true) !==
        command.definitionRevision ||
      Object.entries(command.values).some(
        ([key, value]) =>
          result.values[key] !==
          (typeof value === "string" ? canonicalText(value) : value),
      )
    )
      invalidResponse(true);
    return result;
  }
}
