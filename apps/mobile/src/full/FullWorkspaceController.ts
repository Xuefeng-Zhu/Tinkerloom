import {
  assessClarification,
  builtInClarification,
  clarificationAccessFailure,
  type ClarificationAssessment,
} from "./clarification";
import { BackendError } from "../backend/errors";
import { createHostStorage } from "../host/createHostStorage";
import type { HostScope } from "../host/scope";
import { decodeAppSpec } from "../spec/decode";
import type { AppSpec } from "../spec/types";
import {
  ensure,
  isRuntimeAccessFailure,
  runtimeError,
} from "../runtime/errors";
import type { RuntimeTransport } from "../runtime/types";
import { freezeValidated } from "../runtime/immutable";
import { runtimeJsonSnapshot } from "../runtime/json";
import { FullCommandJournal, type RetainedFullCommand } from "./commandJournal";
import {
  row,
  text,
  count,
  nullableText,
  manifest,
  platformCapabilities,
} from "./contracts";
import type { HostStorage } from "./FullAppController";

type KnownWorkspaceRead = Record<string, unknown> & {
  op:
    | "spec.launcher"
    | "spec.listDrafts"
    | "spec.listVersions"
    | "spec.getVersion";
};
const supersededRead = Symbol("superseded-workspace-read");

export interface VersionSummary {
  id: string;
  number: number;
  hash: string;
  name: string;
  theme: string;
  icon: string;
  publisherId: string;
  createdAt: string | null;
}
export function versionSummary(value: unknown): VersionSummary {
  const data = row(value);
  return freezeValidated({
    id: text(data.id),
    number: count(data.number),
    hash: text(data.hash),
    name: text(data.name),
    theme: text(data.theme),
    icon: text(data.icon),
    publisherId: text(data.publisherId),
    createdAt: nullableText(data.createdAt),
  });
}
export interface LauncherApp {
  id: string;
  workspaceId: string;
  name: string;
  engine: "appspec.v1" | "bounded.v1";
  role: string;
  archived: boolean;
  pinned: boolean;
  pinRevision: number;
  recordCount: number;
  availablePlaces: number | null;
  version: VersionSummary | null;
}
function launcherApp(value: unknown, workspaceId: string): LauncherApp {
  const data = row(value);
  ensure(
    data.workspaceId === workspaceId &&
      ["appspec.v1", "bounded.v1"].includes(String(data.engine)) &&
      ["owner", "builder", "member", "viewer"].includes(String(data.role)) &&
      typeof data.archived === "boolean" &&
      typeof data.pinned === "boolean" &&
      (data.availablePlaces === null ||
        (typeof data.availablePlaces === "number" &&
          Number.isFinite(data.availablePlaces))),
    "invalid_response",
    "The launcher response is invalid.",
  );
  return freezeValidated({
    id: text(data.id),
    workspaceId,
    name: text(data.name),
    engine: data.engine as LauncherApp["engine"],
    role: String(data.role),
    archived: data.archived,
    pinned: data.pinned,
    pinRevision: count(data.pinRevision),
    recordCount: count(data.recordCount),
    availablePlaces: data.availablePlaces as number | null,
    version: data.version === null ? null : versionSummary(data.version),
  });
}
export interface PrivateDraftSummary {
  engine: "appspec.v1" | "bounded.v1";
  appId: string;
  workspaceId: string;
  name: string;
  revision: number;
  stale: boolean;
  updatedAt: string | null;
}
function privateDraft(
  value: unknown,
  workspaceId: string,
): PrivateDraftSummary {
  const data = row(value);
  ensure(
    data.workspaceId === workspaceId &&
      ["appspec.v1", "bounded.v1"].includes(String(data.engine)) &&
      typeof data.stale === "boolean",
    "invalid_response",
    "The private draft response is invalid.",
  );
  return freezeValidated({
    engine: data.engine as PrivateDraftSummary["engine"],
    appId: text(data.appId),
    workspaceId,
    name: text(data.name),
    revision: count(data.revision),
    stale: data.stale,
    updatedAt: nullableText(data.updatedAt),
  });
}
export interface WorkspaceOptions {
  scope: Omit<HostScope, "appId">;
  workspaceId: string;
  transport: RuntimeTransport;
  newId: () => string;
  host?: HostStorage;
  onAccessFailure?: (code: string) => void;
  onPreparedIdea?: (appId: string, request: string) => boolean;
}
export interface WorkspaceState {
  pinnedOnly: boolean;
  catalogLoaded: boolean;
  accessLost: boolean;
  plannedIdea: string;
  guidance: ClarificationAssessment | null;
  guidanceLoading: boolean;
  createdIdeaStatus: "prepared" | "not-restored" | null;
  apps: LauncherApp[];
  drafts: PrivateDraftSummary[];
  cursor: string | null;
  draftCursor: string | null;
  loading: boolean;
  busy: boolean;
  error: string | null;
  pending: RetainedFullCommand | null;
  pendingStatus: "sending" | "uncertain" | "rejected" | null;
  createdAppId: string | null;
  historyAppId: string | null;
  versions: VersionSummary[];
  versionCursor: number | null;
  historical: { summary: VersionSummary; spec: AppSpec } | null;
}
export class FullWorkspaceController {
  readonly host: HostStorage;
  private journal: FullCommandJournal;
  private closed = false;
  private sequence = 0;
  private historySequence = 0;
  private guidanceSequence = 0;
  private creationIdea: {
    operationId: string;
    appId: string;
    requestText: string | null;
  } | null = null;
  private listeners = new Set<() => void>();
  private state: WorkspaceState = {
    pinnedOnly: false,
    catalogLoaded: false,
    accessLost: false,
    plannedIdea: "",
    guidance: null,
    guidanceLoading: false,
    createdIdeaStatus: null,
    apps: [],
    drafts: [],
    cursor: null,
    draftCursor: null,
    loading: false,
    busy: false,
    error: null,
    pending: null,
    pendingStatus: null,
    createdAppId: null,
    historyAppId: null,
    versions: [],
    versionCursor: null,
    historical: null,
  };
  constructor(readonly options: WorkspaceOptions) {
    this.host =
      options.host ??
      createHostStorage({
        ...options.scope,
        appId: `workspace_${options.workspaceId}`,
      });
    this.journal = new FullCommandJournal(
      this.host.storage,
      "launcher-command",
      (command) => {
        const request = command.request;
        ensure(
          command.context.workspaceId === this.options.workspaceId &&
            [
              "spec.createApp",
              "spec.instantiate",
              "spec.remix",
              "spec.setPinned",
            ].includes(String(request.op)) &&
            (request.op === "spec.setPinned" ||
              request.workspaceId === this.options.workspaceId),
          "invalid_saved_scope",
          "The retained operation does not belong to this workbench. It has not been replaced.",
        );
      },
    );
  }
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  getSnapshot = () => this.state;
  private emit(change: Partial<WorkspaceState>) {
    if (this.closed) return;
    this.state = { ...this.state, ...change };
    for (const listener of this.listeners) listener();
  }
  private active() {
    ensure(
      !this.closed && this.host.lifetime.active,
      "disposed",
      "This account's workbench is closed.",
    );
  }
  /** Only definite completed read conflicts may repeat, using one immutable envelope. */
  private async readKnown(input: KnownWorkspaceRead, isCurrent: () => boolean) {
    const request = freezeValidated(
      runtimeJsonSnapshot(input) as KnownWorkspaceRead,
    );
    const current = () =>
      !this.closed && this.host.lifetime.active && isCurrent();
    for (let attempt = 0; ; attempt++) {
      if (!current()) return supersededRead;
      try {
        const response = await this.options.transport(request, {
          isCurrent: current,
        });
        return current() ? response : supersededRead;
      } catch (error) {
        if (!current()) return supersededRead;
        if (
          attempt >= 2 ||
          !(error instanceof BackendError) ||
          error.kind !== "service" ||
          error.status !== 409 ||
          error.code !== "transaction_conflict" ||
          error.uncertain !== false
        )
          throw error;
        await new Promise((resolve) =>
          setTimeout(resolve, 100 * (attempt + 1)),
        );
      }
    }
  }
  private fail(error: unknown, mutation = false, accessRead = false) {
    if (this.closed) return;
    const failure = runtimeError(error, mutation);
    if (
      isRuntimeAccessFailure(failure) ||
      failure.code === "session_changed" ||
      (accessRead && failure.code === "not_found") ||
      (error instanceof BackendError && error.status === 404)
    ) {
      this.sequence++;
      this.historySequence++;
      this.guidanceSequence++;
      this.creationIdea = null;
      this.journal.dispose();
      this.emit({
        apps: [],
        drafts: [],
        guidance: null,
        guidanceLoading: false,
        createdAppId: null,
        createdIdeaStatus: null,
        accessLost: true,
        plannedIdea: "",
        versions: [],
        historical: null,
        pending: null,
        pendingStatus: null,
        error: failure.message,
        busy: false,
        loading: false,
      });
      this.options.onAccessFailure?.(failure.code);
    } else
      this.emit({
        error: failure.message,
        busy: false,
        loading: false,
        pending: this.journal.pending,
        pendingStatus: this.journal.status,
      });
  }
  async load() {
    this.active();
    const sequence = ++this.sequence;
    const pinnedOnly = this.state.pinnedOnly;
    this.emit({ loading: true, error: null });
    try {
      const value = await this.readKnown(
        {
          op: "spec.launcher",
          pinnedOnly,
          workspaceId: this.options.workspaceId,
          limit: 50,
        },
        () => sequence === this.sequence,
      );
      if (value === supersededRead) return;
      const result = row(value);
      if (this.closed || sequence !== this.sequence) return;
      ensure(
        Array.isArray(result.apps),
        "invalid_response",
        "Apps could not be read.",
      );
      const apps = result.apps.map((v) =>
        launcherApp(v, this.options.workspaceId),
      );
      ensure(
        !pinnedOnly || apps.every((app) => app.pinned),
        "invalid_response",
        "The pinned apps response contains an unpinned app.",
      );
      this.emit({
        apps,
        cursor: nullableText(result.nextCursor),
      });
      const draftValue = await this.readKnown(
        {
          op: "spec.listDrafts",
          workspaceId: this.options.workspaceId,
          limit: 50,
        },
        () => sequence === this.sequence,
      );
      if (draftValue === supersededRead) return;
      const drafts = row(draftValue);
      if (this.closed || sequence !== this.sequence) return;
      ensure(
        Array.isArray(drafts.drafts),
        "invalid_response",
        "Private drafts could not be read.",
      );
      this.emit({
        drafts: drafts.drafts.map((v) =>
          privateDraft(v, this.options.workspaceId),
        ),
        draftCursor: nullableText(drafts.nextCursor),
      });
      await this.journal.recover();
      if (this.closed || sequence !== this.sequence) return;
      this.emit({
        pending: this.journal.pending,
        pendingStatus: this.journal.status,
        loading: false,
        catalogLoaded: true,
        accessLost: false,
      });
    } catch (error) {
      if (sequence === this.sequence) this.fail(error);
    }
  }
  async setPinnedOnly(pinnedOnly: boolean) {
    try {
      this.active();
      if (pinnedOnly === this.state.pinnedOnly || this.state.busy) return;
      // Catalog cursors are scoped to the filter. Clear them before any new read.
      this.emit({ pinnedOnly, apps: [], cursor: null, catalogLoaded: false });
      await this.load();
    } catch (error) {
      this.fail(error);
    }
  }
  async loadMore(kind: "apps" | "drafts") {
    this.active();
    const cursor = kind === "apps" ? this.state.cursor : this.state.draftCursor;
    if (!cursor || this.state.loading) return;
    const sequence = this.sequence;
    const pinnedOnly = this.state.pinnedOnly;
    this.emit({ loading: true, error: null });
    try {
      const value = await this.readKnown(
        {
          op: kind === "apps" ? "spec.launcher" : "spec.listDrafts",
          ...(kind === "apps" ? { pinnedOnly } : {}),
          workspaceId: this.options.workspaceId,
          cursor,
          limit: 50,
        },
        () => sequence === this.sequence,
      );
      if (value === supersededRead) return;
      const result = row(value);
      if (this.closed || sequence !== this.sequence) return;
      if (kind === "apps") {
        ensure(
          Array.isArray(result.apps),
          "invalid_response",
          "Apps could not be read.",
        );
        const next = result.apps.map((v) =>
          launcherApp(v, this.options.workspaceId),
        );
        ensure(
          !pinnedOnly || next.every((app) => app.pinned),
          "invalid_response",
          "The pinned apps response contains an unpinned app.",
        );
        ensure(
          new Set(next.map((app) => app.id)).size === next.length &&
            next.every((v) => !this.state.apps.some((old) => old.id === v.id)),
          "invalid_response",
          "The launcher page overlaps an earlier page.",
        );
        this.emit({
          apps: [...this.state.apps, ...next],
          cursor: nullableText(result.nextCursor),
          loading: false,
        });
      } else {
        ensure(
          Array.isArray(result.drafts),
          "invalid_response",
          "Drafts could not be read.",
        );
        const next = result.drafts.map((v) =>
          privateDraft(v, this.options.workspaceId),
        );
        ensure(
          next.every(
            (v) => !this.state.drafts.some((old) => old.appId === v.appId),
          ),
          "invalid_response",
          "The draft page overlaps an earlier page.",
        );
        this.emit({
          drafts: [...this.state.drafts, ...next],
          draftCursor: nullableText(result.nextCursor),
          loading: false,
        });
      }
    } catch (error) {
      if (sequence === this.sequence) this.fail(error);
    }
  }
  private async transmit() {
    const command = this.journal.pending;
    const prepared =
      this.creationIdea &&
      command?.request.operationId === this.creationIdea.operationId &&
      command.request.id === this.creationIdea.appId
        ? this.creationIdea
        : null;
    this.emit({
      busy: true,
      error: null,
      pending: this.journal.pending,
      pendingStatus: "sending",
    });
    try {
      const result = await this.journal.send(
        this.options.transport,
        (response, command) => {
          const data = row(response),
            request = command.request;
          if (request.op === "spec.setPinned") {
            const shortcut = row(data.shortcut);
            ensure(
              shortcut.appId === request.appId &&
                shortcut.pinned === request.pinned &&
                count(shortcut.revision) ===
                  (request.expectedRevision as number) + 1,
              "invalid_response",
              "The pin response did not confirm the original preference.",
            );
            return { appId: null, createdShell: false };
          }
          const app = manifest(data.app, String(request.id));
          ensure(
            app.workspaceId === request.workspaceId,
            "invalid_response",
            "The created app belongs to a different workspace.",
          );
          return {
            appId: app.id,
            createdShell: request.op === "spec.createApp",
          };
        },
      );
      this.active();
      let createdIdeaStatus: WorkspaceState["createdIdeaStatus"] = null;
      if (result.createdShell && result.appId) {
        if (prepared?.requestText && this.options.onPreparedIdea) {
          createdIdeaStatus = this.options.onPreparedIdea(
            result.appId,
            prepared.requestText,
          )
            ? "prepared"
            : "not-restored";
        } else if (!prepared) createdIdeaStatus = "not-restored";
      }
      this.creationIdea = null;
      this.emit({
        busy: false,
        pending: null,
        createdIdeaStatus,
        pendingStatus: null,
        createdAppId: result.appId,
      });
      await this.load();
    } catch (error) {
      this.fail(error, true);
    }
  }
  private async mutate(
    request: Record<string, unknown>,
    preparedIdea: string | null = null,
  ) {
    this.active();
    ensure(
      !this.state.accessLost,
      "forbidden",
      "Current workspace access is required.",
    );
    ensure(
      !this.state.busy && !this.state.pending,
      "pending_command",
      "Resolve the retained operation first.",
    );
    this.guidanceSequence++;
    if (request.op === "spec.createApp") {
      this.creationIdea = {
        operationId: String(request.operationId),
        appId: String(request.id),
        requestText: preparedIdea,
      };
    }
    this.emit({
      busy: true,
      error: null,
      guidance: null,
      guidanceLoading: false,
    });
    try {
      await this.journal.prepare(request, {
        workspaceId: this.options.workspaceId,
      });
      this.active();
      await this.transmit();
    } catch (error) {
      this.fail(error, true);
    }
  }
  async instantiate(templateKey: string) {
    try {
      await this.mutate({
        op: "spec.instantiate",
        id: this.options.newId(),
        workspaceId: this.options.workspaceId,
        templateKey,
        operationId: this.options.newId(),
      });
    } catch (error) {
      this.fail(error);
    }
  }
  async create(name: string, preparedIdea = "") {
    try {
      ensure(
        new TextEncoder().encode(preparedIdea).byteLength <= 16384,
        "invalid_input",
        "The prepared idea must fit 16 KiB.",
      );
      await this.mutate(
        {
          op: "spec.createApp",
          id: this.options.newId(),
          workspaceId: this.options.workspaceId,
          name,
          operationId: this.options.newId(),
        },
        preparedIdea.trim() ? preparedIdea : null,
      );
    } catch (error) {
      this.fail(error);
    }
  }
  async remix(sourceAppId: string, sourceVersionId: string) {
    try {
      await this.mutate({
        op: "spec.remix",
        id: this.options.newId(),
        workspaceId: this.options.workspaceId,
        sourceAppId,
        sourceVersionId,
        operationId: this.options.newId(),
      });
    } catch (error) {
      this.fail(error);
    }
  }
  async setPinned(app: LauncherApp, pinned: boolean) {
    try {
      ensure(
        app.workspaceId === this.options.workspaceId,
        "invalid_input",
        "Choose an app from this workbench.",
      );
      await this.mutate({
        op: "spec.setPinned",
        appId: app.id,
        pinned,
        expectedRevision: app.pinRevision,
        operationId: this.options.newId(),
      });
    } catch (error) {
      this.fail(error);
    }
  }
  async retry() {
    try {
      this.active();
      ensure(
        this.journal.status === "uncertain" && !this.state.busy,
        "pending_command",
        "No retained outcome is ready to check.",
      );
      await this.transmit();
    } catch (error) {
      this.fail(error, true);
    }
  }
  async acknowledgeRejection() {
    try {
      await this.journal.acknowledgeRejection();
      this.creationIdea = null;
      this.emit({ pending: null, pendingStatus: null, error: null });
      await this.load();
    } catch (error) {
      this.fail(error);
    }
  }
  clearCreated() {
    this.emit({ createdAppId: null, createdIdeaStatus: null });
  }
  setPlannedIdea(request: string) {
    this.active();
    if (this.state.accessLost) return;
    this.guidanceSequence++;
    this.emit({ plannedIdea: request, guidance: null, guidanceLoading: false });
  }
  async requestGuidance(request: string) {
    const sequence = ++this.guidanceSequence;
    try {
      this.active();
      ensure(
        !this.state.accessLost,
        "forbidden",
        "Current workspace access is required.",
      );
      ensure(
        !this.state.busy && !this.state.pending,
        "pending_command",
        "Resolve the retained workbench operation before asking for help.",
      );
      this.emit({ error: null, guidance: null, guidanceLoading: true });
      const assessment = await assessClarification({
        request,
        mode: "create",
        providerEnabled: async () =>
          platformCapabilities(
            await this.options.transport({ op: "spec.capabilities" }),
          ).guidance,
        askProvider: () =>
          this.options.transport({
            op: "spec.guidance",
            workspaceId: this.options.workspaceId,
            request,
          }),
        isAlive: () => !this.closed && this.host.lifetime.active,
        isCurrent: () => sequence === this.guidanceSequence,
      });
      if (this.closed || sequence !== this.guidanceSequence || !assessment)
        return;
      this.emit({ guidance: assessment, guidanceLoading: false });
    } catch (error) {
      if (
        this.closed ||
        (sequence !== this.guidanceSequence &&
          !clarificationAccessFailure(error))
      )
        return;
      this.emit({ guidanceLoading: false });
      this.fail(error, false, true);
    }
  }
  invalidateGuidance() {
    this.guidanceSequence++;
    this.emit({ guidance: null, guidanceLoading: false });
  }
  useBuiltInGuidance() {
    if (!this.state.guidance) return;
    const { requestText } = this.state.guidance;
    this.guidanceSequence++;
    this.emit({
      guidance: builtInClarification(requestText, "create", "optional"),
      guidanceLoading: false,
    });
  }
  async history(appId: string, more = false) {
    this.active();
    const before =
      more && this.state.historyAppId === appId
        ? this.state.versionCursor
        : null;
    if (more && before === null) return;
    const sequence = ++this.historySequence;
    this.emit({
      historyAppId: appId,
      loading: true,
      error: null,
      ...(!more ? { versions: [], historical: null } : {}),
    });
    try {
      const value = await this.readKnown(
        {
          op: "spec.listVersions",
          appId,
          limit: 25,
          ...(before !== null ? { beforeNumber: before } : {}),
        },
        () => sequence === this.historySequence,
      );
      if (value === supersededRead) return;
      const result = row(value);
      if (this.closed || sequence !== this.historySequence) return;
      ensure(
        Array.isArray(result.versions),
        "invalid_response",
        "Version history could not be read.",
      );
      const versions = result.versions.map(versionSummary);
      this.emit({
        versions: more ? [...this.state.versions, ...versions] : versions,
        versionCursor:
          result.nextBeforeNumber === null
            ? null
            : count(result.nextBeforeNumber),
        loading: false,
      });
    } catch (error) {
      if (sequence === this.historySequence) this.fail(error);
    }
  }
  async inspectVersion(appId: string, versionId: string) {
    const sequence = ++this.historySequence;
    this.emit({ loading: true, error: null, historical: null });
    try {
      const value = await this.readKnown(
        {
          op: "spec.getVersion",
          appId,
          versionId,
        },
        () => sequence === this.historySequence,
      );
      if (value === supersededRead) return;
      const result = row(value);
      if (this.closed || sequence !== this.historySequence) return;
      const version = row(result.version),
        summary = versionSummary(version);
      ensure(
        summary.id === versionId,
        "invalid_response",
        "The immutable version identity changed.",
      );
      this.emit({
        historical: { summary, spec: decodeAppSpec(version.spec) },
        loading: false,
      });
    } catch (error) {
      if (sequence === this.historySequence) this.fail(error);
    }
  }
  closeHistorical() {
    this.historySequence++;
    this.emit({ historical: null, loading: false });
  }
  closeHistory() {
    this.historySequence++;
    this.emit({
      historyAppId: null,
      versions: [],
      historical: null,
      versionCursor: null,
      loading: false,
    });
  }
  dispose() {
    if (this.closed) return;
    this.closed = true;
    this.creationIdea = null;
    this.guidanceSequence++;
    this.sequence++;
    this.historySequence++;
    this.journal.dispose();
    this.host.lifetime.dispose();
    this.state = {
      ...this.state,
      guidance: null,
      guidanceLoading: false,
      plannedIdea: "",
      createdAppId: null,
      createdIdeaStatus: null,
      apps: [],
      drafts: [],
      pending: null,
      versions: [],
      historical: null,
    };
    this.listeners.clear();
  }
}
