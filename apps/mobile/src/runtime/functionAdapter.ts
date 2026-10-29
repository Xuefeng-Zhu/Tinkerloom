import { BackendError } from "../backend/errors";
import { decodeAppSpec } from "../spec/decode";
import { getCollection } from "../spec/bindings";
import {
  normalizeRecordValues,
  validateAggregateQuery,
  validateRecordQuery,
} from "../spec/values";
import { runtimeJsonSnapshot } from "./json";
import type {
  ActionSpec,
  AggregateQuery,
  AppSpec,
  RecordQuery,
} from "../spec/types";
import { ensure, RuntimeError, runtimeError, unavailable } from "./errors";
import { policyPermits } from "./permissions";
import { freezeValidated } from "./immutable";
import type {
  CommandOutcome,
  ImageAsset,
  PickedImage,
  RecordPage,
  ReminderState,
  RuntimeAdapter,
  RuntimeCommand,
  RuntimeRecord,
  RuntimeRole,
  RuntimeSummary,
  RuntimeTransport,
  RuntimeAggregate,
  RuntimeReadContext,
} from "./types";

type ObjectData = Record<string, unknown>;
function object(value: unknown): ObjectData {
  ensure(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "invalid_response",
    "The server returned an invalid object.",
  );
  return value as ObjectData;
}
function text(value: unknown): string {
  ensure(
    typeof value === "string" && value.length > 0 && value.length <= 4096,
    "invalid_response",
    "The server returned invalid text.",
  );
  return value;
}
function integer(value: unknown): number {
  ensure(
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0,
    "invalid_response",
    "The server returned an invalid count.",
  );
  return value;
}
function array(value: unknown): unknown[] {
  ensure(
    Array.isArray(value),
    "invalid_response",
    "The server returned an invalid list.",
  );
  return value;
}
function numberOrNull(value: unknown): number | null {
  ensure(
    value === null || (typeof value === "number" && Number.isFinite(value)),
    "invalid_response",
    "The server returned an invalid number.",
  );
  return value;
}
export interface RuntimeManifest {
  id: string;
  workspaceId: string;
  name: string;
  engine: "appspec.v1";
  role: RuntimeRole;
  archived: boolean;
  capabilities: Record<string, boolean>;
  controlRevision: number;
  allowedActions: string[];
  version: null | {
    id: string;
    number: number;
    hash: string;
    spec: AppSpec;
  };
  draft: null | {
    revision: number;
    baseVersionId: string | null;
    candidateHash: string;
    spec: AppSpec;
    publishedVersionId: string | null;
  };
}
export function decodeRuntimeManifest(value: unknown): RuntimeManifest {
  const app = object(value);
  ensure(
    app.engine === "appspec.v1",
    "unsupported_engine",
    "This app requires a different runtime.",
  );
  ensure(
    ["owner", "builder", "member", "viewer"].includes(String(app.role)) &&
      typeof app.archived === "boolean",
    "invalid_response",
    "The server returned invalid access information.",
  );
  const capabilities = object(app.capabilities);
  ensure(
    Object.values(capabilities).every((v) => typeof v === "boolean"),
    "invalid_response",
    "The server returned invalid capabilities.",
  );
  const version = app.version === null ? null : object(app.version),
    draft = app.draft === null ? null : object(app.draft);
  return {
    id: text(app.id),
    workspaceId: text(app.workspaceId),
    name: text(app.name),
    engine: "appspec.v1",
    role: app.role as RuntimeRole,
    archived: app.archived,
    capabilities: capabilities as Record<string, boolean>,
    controlRevision: integer(app.controlRevision),
    allowedActions: array(app.allowedActions).map(text),
    version: version
      ? {
          id: text(version.id),
          number: integer(version.number),
          hash: text(version.hash),
          spec: decodeAppSpec(version.spec),
        }
      : null,
    draft: draft
      ? {
          revision: integer(draft.revision),
          baseVersionId:
            draft.baseVersionId === null ? null : text(draft.baseVersionId),
          candidateHash: text(draft.candidateHash),
          spec: decodeAppSpec(draft.spec),
          publishedVersionId:
            draft.publishedVersionId === null
              ? null
              : text(draft.publishedVersionId),
        }
      : null,
  };
}
export class FunctionRuntimeAdapter implements RuntimeAdapter {
  readonly preview = false;
  readonly approvedRuleIds: readonly string[] = [];
  readonly features = new Set<
    "members" | "reminders" | "imageRead" | "imageUpload" | "watch"
  >(["members"]);
  readonly appId: string;
  readonly versionId: string;
  readonly spec: AppSpec;
  readonly role: RuntimeRole;
  readonly archived: boolean;
  private disposed = false;
  private readonly allowedActions: ReadonlySet<string>;
  constructor(
    manifest: RuntimeManifest,
    private readonly transport: RuntimeTransport,
  ) {
    ensure(
      manifest.version,
      "unpublished",
      "Publish a reviewed version before opening the live app.",
    );
    this.appId = manifest.id;
    this.versionId = manifest.version.id;
    this.spec = freezeValidated(decodeAppSpec(manifest.version.spec));
    this.role = manifest.role;
    this.archived = manifest.archived;
    this.allowedActions = new Set(manifest.allowedActions);
    ensure(
      [...this.allowedActions].every((id) =>
        this.spec.actions.some((a) => a.id === id),
      ),
      "invalid_response",
      "The published version has an unsupported action.",
    );
  }
  static async load(appId: string, transport: RuntimeTransport) {
    const result = object(await transport({ op: "spec.getApp", appId }));
    return decodeRuntimeManifest(result.app);
  }
  permits(action: ActionSpec, record?: RuntimeRecord) {
    return (
      (record !== undefined || this.allowedActions.has(action.id)) &&
      policyPermits(this.spec, this.role, this.archived, action, record)
    );
  }
  private async call(
    op: string,
    payload: ObjectData,
    mutation = false,
    context?: RuntimeReadContext,
  ): Promise<ObjectData> {
    const request = freezeValidated(
      runtimeJsonSnapshot({
        op,
        appId: this.appId,
        ...(op.startsWith("spec.") ? { versionId: this.versionId } : {}),
        ...payload,
      }) as ObjectData,
    );
    const retryableRead =
      !mutation &&
      [
        "spec.query",
        "spec.getRecord",
        "spec.summary",
        "spec.aggregate",
        "listMembers",
      ].includes(op);
    const readContext = {
      isCurrent: () => !this.disposed && (context?.isCurrent() ?? true),
    };
    for (let attempt = 0; ; attempt++) {
      ensure(!this.disposed, "disposed", "This app is closed.");
      ensure(
        readContext.isCurrent(),
        "superseded_read",
        "This read has been superseded.",
      );
      try {
        const result = object(
          await this.transport(request, mutation ? undefined : readContext),
        );
        // Raw/unknown envelopes never qualify for the definite service-error retry.
        if (result.error) {
          const error = object(result.error),
            code = text(error.code);
          throw new RuntimeError(
            code,
            typeof error.message === "string"
              ? error.message
              : "The command could not be completed.",
            mutation && code === "transaction_conflict",
          );
        }
        ensure(
          !this.disposed,
          "disposed",
          "This app was closed while loading.",
        );
        ensure(
          readContext.isCurrent(),
          "superseded_read",
          "This read has been superseded.",
        );
        return result;
      } catch (error) {
        ensure(
          !this.disposed,
          "disposed",
          "This app was closed while loading.",
        );
        if (
          retryableRead &&
          attempt < 2 &&
          error instanceof BackendError &&
          error.kind === "service" &&
          error.status === 409 &&
          error.code === "transaction_conflict" &&
          !error.uncertain
        ) {
          // A completed, definite read rejection can be repeated with the same
          // captured request. Account-fenced transport rechecks each attempt.
          await new Promise((resolve) =>
            setTimeout(resolve, 40 * (attempt + 1)),
          );
          continue;
        }
        if (
          mutation &&
          error instanceof RuntimeError &&
          error.code === "invalid_response"
        )
          throw new RuntimeError(
            "outcome_unknown",
            "The command returned an unreadable response. Retry its original operation ID.",
            true,
          );
        throw runtimeError(error, mutation);
      }
    }
  }
  private version(result: ObjectData) {
    ensure(
      result.versionId === this.versionId,
      "definition_conflict",
      "The published version changed. Reopen the app before continuing.",
    );
  }
  private record(input: unknown): RuntimeRecord {
    const row = object(input),
      collectionId = text(row.collectionId),
      revision = integer(row.revision);
    ensure(
      revision > 0 && typeof row.claimed === "boolean",
      "invalid_response",
      "The server returned an invalid record revision.",
    );
    const allowedActions = array(row.allowedActions).map(text);
    ensure(
      allowedActions.every((id) =>
        this.spec.actions.some(
          (a) => a.id === id && a.collectionId === collectionId,
        ),
      ),
      "invalid_response",
      "The server returned an unsupported record action.",
    );
    const capacity = row.capacity === null ? null : integer(row.capacity),
      allocated = row.allocated === null ? null : integer(row.allocated);
    ensure(
      (capacity === null) === (allocated === null) &&
        (capacity === null || (capacity <= 10000 && allocated! <= capacity)) &&
        (!row.claimed || capacity !== null),
      "invalid_response",
      "The server returned invalid capacity counters.",
    );
    return {
      id: text(row.id),
      collectionId,
      data: normalizeRecordValues(
        getCollection(this.spec, collectionId),
        row.data,
      ),
      revision,
      writtenUnderVersionId: text(row.writtenUnderVersionId),
      capacity,
      allocated,
      claimed: row.claimed,
      allowedActions,
    };
  }
  async query(
    collectionId: string,
    input: RecordQuery,
    context?: RuntimeReadContext,
  ): Promise<RecordPage> {
    const query = validateRecordQuery(
        getCollection(this.spec, collectionId),
        runtimeJsonSnapshot(input) as RecordQuery,
      ),
      result = await this.call(
        "spec.query",
        { collectionId, query },
        false,
        context,
      );
    this.version(result);
    const records = array(result.records).map((row) => this.record(row));
    ensure(
      records.length <= query.limit! &&
        records.every((row) => row.collectionId === collectionId) &&
        new Set(records.map((r) => r.id)).size === records.length,
      "invalid_response",
      "The server returned an invalid record page.",
    );
    return {
      records,
      total: integer(result.total),
      nextCursor: result.nextCursor === null ? null : text(result.nextCursor),
      versionId: this.versionId,
    };
  }
  async get(recordId: string, context?: RuntimeReadContext) {
    const result = await this.call(
      "spec.getRecord",
      { recordId },
      false,
      context,
    );
    this.version(result);
    const row = this.record(result.record);
    ensure(
      row.id === recordId,
      "invalid_response",
      "The server returned a different record.",
    );
    return row;
  }
  async summary(
    collectionId: string,
    input: RecordQuery,
    groupFieldId: string,
    context?: RuntimeReadContext,
  ): Promise<RuntimeSummary> {
    const query = validateRecordQuery(
        getCollection(this.spec, collectionId),
        input,
      ),
      result = await this.call(
        "spec.summary",
        {
          collectionId,
          query,
          groupFieldId,
        },
        false,
        context,
      );
    this.version(result);
    const groups = Object.fromEntries(
      Object.entries(object(result.groups)).map(([key, value]) => [
        key,
        integer(value),
      ]),
    );
    return { total: integer(result.total), groups, versionId: this.versionId };
  }
  async aggregate(
    collectionId: string,
    input: RecordQuery,
    aggregation: AggregateQuery,
    context?: RuntimeReadContext,
  ): Promise<RuntimeAggregate> {
    const collection = getCollection(this.spec, collectionId),
      query = validateRecordQuery(collection, input),
      aggregate = validateAggregateQuery(collection, aggregation),
      result = await this.call(
        "spec.aggregate",
        {
          collectionId,
          query,
          aggregate,
        },
        false,
        context,
      );
    this.version(result);
    const groups = array(result.groups).map((item) => {
      const group = object(item);
      return {
        key: typeof group.key === "string" ? group.key : text(group.key),
        count: integer(group.count),
        value: numberOrNull(group.value),
      };
    });
    return {
      total: integer(result.total),
      value: numberOrNull(result.value),
      groups,
      versionId: this.versionId,
    };
  }
  async execute(input: RuntimeCommand): Promise<CommandOutcome> {
    const command = runtimeJsonSnapshot(input) as unknown as RuntimeCommand;
    ensure(
      command.appId === this.appId,
      "definition_conflict",
      "This command belongs to another app or version.",
    );
    const result = await this.call("spec.execute", { ...command }, true);
    try {
      const outcome = object(result.outcome),
        revision = integer(outcome.revision);
      ensure(
        revision > 0,
        "invalid_response",
        "The server returned an invalid command revision.",
      );
      return {
        recordId: text(outcome.recordId),
        revision,
        message: text(outcome.message),
      };
    } catch {
      throw new RuntimeError(
        "outcome_unknown",
        "The command returned an unreadable result. Retry its original operation ID to confirm the outcome.",
        true,
      );
    }
  }
  async members(
    context?: RuntimeReadContext,
  ): Promise<{ id: string; label: string }[]> {
    const rows: { id: string; label: string }[] = [],
      seen = new Set<string>(),
      cursors = new Set<string>();
    let afterId: string | undefined;
    do {
      const result = await this.call(
        "listMembers",
        afterId ? { afterId } : {},
        false,
        context,
      );
      const members = array(result.members);
      ensure(
        members.length <= (afterId ? 50 : 51),
        "invalid_response",
        "The member page exceeds its bounds.",
      );
      for (const item of members) {
        const member = object(item),
          id = text(member.actorId);
        ensure(
          !seen.has(id),
          "invalid_response",
          "The member directory overlaps.",
        );
        seen.add(id);
        if (member.role !== null)
          rows.push({ id, label: `${id} (${text(member.role)})` });
      }
      const next =
        result.nextCursor === null ? undefined : text(result.nextCursor);
      ensure(
        next === undefined || !cursors.has(next),
        "invalid_response",
        "The member cursor repeated.",
      );
      if (next) cursors.add(next);
      afterId = next;
      ensure(
        rows.length <= 1000,
        "invalid_response",
        "The member directory exceeds its bounds.",
      );
    } while (afterId);
    return rows;
  }
  async reminderState(_recordId: string): Promise<ReminderState> {
    return unavailable("Live reminder status");
  }
  async readImage(_assetId: string): Promise<ImageAsset> {
    return unavailable("Private image downloads");
  }
  async pickImage(): Promise<PickedImage | null> {
    return unavailable("Image picking");
  }
  async uploadImage(_image: PickedImage): Promise<string> {
    return unavailable("Private image uploads");
  }
  watch(_listener: () => void) {
    return () => {};
  }
  dispose() {
    this.disposed = true;
  }
}
