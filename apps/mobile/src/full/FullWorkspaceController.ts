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
import { FullCommandJournal, type RetainedFullCommand } from "./commandJournal";
import { row, text, count, nullableText, manifest } from "./contracts";
import type { HostStorage } from "./FullAppController";

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
}
export interface WorkspaceState {
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
  private listeners = new Set<() => void>();
  private state: WorkspaceState = {
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
  private fail(error: unknown, mutation = false) {
    if (this.closed) return;
    const failure = runtimeError(error, mutation);
    if (
      isRuntimeAccessFailure(failure) ||
      (error instanceof BackendError && error.status === 404)
    ) {
      this.sequence++;
      this.historySequence++;
      this.journal.dispose();
      this.emit({
        apps: [],
        drafts: [],
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
    this.emit({ loading: true, error: null });
    try {
      const result = row(
        await this.options.transport({
          op: "spec.launcher",
          workspaceId: this.options.workspaceId,
          limit: 50,
        }),
      );
      if (this.closed || sequence !== this.sequence) return;
      ensure(
        Array.isArray(result.apps),
        "invalid_response",
        "Apps could not be read.",
      );
      this.emit({
        apps: result.apps.map((v) => launcherApp(v, this.options.workspaceId)),
        cursor: nullableText(result.nextCursor),
      });
      const drafts = row(
        await this.options.transport({
          op: "spec.listDrafts",
          workspaceId: this.options.workspaceId,
          limit: 50,
        }),
      );
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
      });
    } catch (error) {
      if (sequence === this.sequence) this.fail(error);
    }
  }
  async loadMore(kind: "apps" | "drafts") {
    const cursor = kind === "apps" ? this.state.cursor : this.state.draftCursor;
    if (!cursor || this.state.loading) return;
    const sequence = this.sequence;
    this.emit({ loading: true, error: null });
    try {
      const result = row(
        await this.options.transport({
          op: kind === "apps" ? "spec.launcher" : "spec.listDrafts",
          workspaceId: this.options.workspaceId,
          cursor,
          limit: 50,
        }),
      );
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
      this.fail(error);
    }
  }
  private async transmit() {
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
            return { appId: null };
          }
          const app = manifest(data.app, String(request.id));
          ensure(
            app.workspaceId === request.workspaceId,
            "invalid_response",
            "The created app belongs to a different workspace.",
          );
          return { appId: app.id };
        },
      );
      this.active();
      this.emit({
        busy: false,
        pending: null,
        pendingStatus: null,
        createdAppId: result.appId,
      });
      await this.load();
    } catch (error) {
      this.fail(error, true);
    }
  }
  private async mutate(request: Record<string, unknown>) {
    this.active();
    ensure(
      !this.state.busy && !this.state.pending,
      "pending_command",
      "Resolve the retained operation first.",
    );
    this.emit({ busy: true, error: null });
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
  async create(name: string) {
    try {
      await this.mutate({
        op: "spec.createApp",
        id: this.options.newId(),
        workspaceId: this.options.workspaceId,
        name,
        operationId: this.options.newId(),
      });
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
      this.emit({ pending: null, pendingStatus: null, error: null });
      await this.load();
    } catch (error) {
      this.fail(error);
    }
  }
  clearCreated() {
    this.emit({ createdAppId: null });
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
      const result = row(
        await this.options.transport({
          op: "spec.listVersions",
          appId,
          limit: 25,
          ...(before !== null ? { beforeNumber: before } : {}),
        }),
      );
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
      const result = row(
        await this.options.transport({
          op: "spec.getVersion",
          appId,
          versionId,
        }),
      );
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
    this.sequence++;
    this.historySequence++;
    this.journal.dispose();
    this.host.lifetime.dispose();
    this.state = {
      ...this.state,
      apps: [],
      drafts: [],
      pending: null,
      versions: [],
      historical: null,
    };
    this.listeners.clear();
  }
}
