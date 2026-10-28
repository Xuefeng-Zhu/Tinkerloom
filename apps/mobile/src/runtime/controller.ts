import { getAction, getCollection, getView } from "../spec/bindings";
import type {
  AggregateQuery,
  JsonValue,
  RecordQuery,
  ViewSpec,
} from "../spec/types";
import {
  ensure,
  RuntimeError,
  runtimeError,
  isRuntimeAccessFailure,
} from "./errors";
import { decodeRetainedCommand, MemoryRuntimeCommandStore } from "./commands";
import type { RuntimeCommandStore } from "./commands";
import { buildViewQuery, dateBuckets, monthBuckets } from "./query";
import type { ViewSelection } from "./query";
import type {
  CommandOutcome,
  RuntimeAdapter,
  RuntimeAggregate,
  RuntimeCommand,
  RuntimeLocation,
  RuntimeRecord,
  RuntimeSummary,
} from "./types";

export interface RuntimeViewState {
  loading: boolean;
  records: RuntimeRecord[];
  total: number;
  nextCursor: string | null;
  query: RecordQuery;
  summary?: RuntimeSummary;
  aggregate?: RuntimeAggregate;
  error?: RuntimeError;
}
export interface PendingCommand {
  command: RuntimeCommand;
  status: "sending" | "uncertain" | "failed";
  error?: RuntimeError;
}
export interface RuntimeSnapshot {
  location: RuntimeLocation;
  history: RuntimeLocation[];
  views: Record<string, RuntimeViewState>;
  record: RuntimeRecord | null;
  loading: boolean;
  dirty: boolean;
  pending: PendingCommand | null;
  error: RuntimeError | null;
  outcome: CommandOutcome | null;
  accessDenied: boolean;
}
export interface ViewSettings extends ViewSelection {
  month?: Date;
}
const emptyView = (query: RecordQuery): RuntimeViewState => ({
  query,
  loading: true,
  records: [],
  total: 0,
  nextCursor: null,
});
let scopeSequence = 0;

/** Owned by a host scope, not by a route. A navigation event cannot lose a command. */
export class RuntimeController {
  readonly scopeId = ++scopeSequence;
  private state: RuntimeSnapshot;
  private listeners = new Set<() => void>();
  private settings = new Map<string, ViewSettings>();
  private scrolls = new Map<string, number>();
  private request = 0;
  private disposed = false;
  private unsubscribe = () => {};
  private recovered = false;
  private recovery: Promise<void> | null = null;
  constructor(
    readonly adapter: RuntimeAdapter,
    private readonly operationId: () => string,
    private readonly now: () => Date = () => new Date(),
    readonly commands: RuntimeCommandStore = new MemoryRuntimeCommandStore(),
    private readonly callbacks: {
      onAccessFailure?: (error: RuntimeError) => void;
    } = {},
  ) {
    this.state = {
      location: {
        pageId: adapter.spec.navigation?.entryPageId ?? "__legacy__",
      },
      history: [],
      views: {},
      record: null,
      loading: false,
      dirty: false,
      pending: null,
      error: null,
      outcome: null,
      accessDenied: false,
    };
    if (adapter.features.has("watch"))
      this.unsubscribe = adapter.watch(() => {
        if (!this.state.dirty && !this.state.pending) void this.refresh();
      });
  }
  getSnapshot = () => this.state;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  private emit(patch: Partial<RuntimeSnapshot>) {
    if (this.disposed) return;
    this.state = { ...this.state, ...patch };
    for (const listener of this.listeners) listener();
  }
  private invalidateAccess(error: RuntimeError) {
    ++this.request;
    this.emit({
      accessDenied: true,
      views: {},
      record: null,
      dirty: false,
      loading: false,
      error,
    });
    this.callbacks.onAccessFailure?.(error);
  }
  get views(): ViewSpec[] {
    const navigation = this.adapter.spec.navigation;
    return navigation
      ? (navigation.pages
          .find((p) => p.id === this.state.location.pageId)
          ?.viewIds.map((id) => getView(this.adapter.spec, id)) ?? [])
      : this.adapter.spec.views;
  }
  settingsFor(viewId: string): ViewSettings {
    return this.settings.get(viewId) ?? {};
  }
  scrollFor(pageId: string) {
    return this.scrolls.get(pageId) ?? 0;
  }
  rememberScroll(pageId: string, offset: number) {
    if (!this.disposed && Number.isFinite(offset))
      this.scrolls.set(pageId, Math.max(0, offset));
  }
  focusRecord(record: RuntimeRecord) {
    ensure(
      !this.state.dirty && !this.state.pending,
      "unsaved_changes",
      "Finish the current command first.",
    );
    ++this.request;
    this.emit({
      location: { ...this.state.location, recordId: record.id },
      record,
      error: null,
    });
  }
  dismissRecord() {
    if (this.state.pending) return;
    ++this.request;
    this.emit({
      location: { pageId: this.state.location.pageId },
      record: null,
    });
  }
  get canLeave() {
    return !this.state.dirty && !this.state.pending;
  }
  get writeAvailable() {
    return (
      !this.state.accessDenied &&
      (this.adapter.preview || this.commands.durability === "durable")
    );
  }
  /** Never auto-replays. Recovery makes the exact saved envelope explicitly retryable. */
  recover(): Promise<void> {
    if (this.recovered || this.disposed) return Promise.resolve();
    if (this.recovery) return this.recovery;
    this.recovery = (async () => {
      const saved = await this.commands.read();
      if (this.disposed) return;
      if (saved !== null) {
        const command = decodeRetainedCommand(saved, this.adapter.appId);
        ++this.request;
        this.emit({
          pending: {
            command,
            status: "uncertain",
            error: new RuntimeError(
              "outcome_unknown",
              "A previous command has an unconfirmed result. Check its original operation before making another change.",
              true,
            ),
          },
          dirty: true,
          views: {},
          record: null,
        });
      }
      this.recovered = true;
    })().finally(() => {
      this.recovery = null;
    });
    return this.recovery;
  }
  setDirty(dirty: boolean) {
    if (dirty) ++this.request;
    this.emit({ dirty, ...(dirty ? { loading: false } : {}) });
  }
  /** Dirty or unresolved commands require an explicit host decision before leaving. */
  navigate(location: RuntimeLocation, discard = false): boolean {
    if (this.state.pending) return false;
    if (this.state.dirty && !discard) return false;
    const nav = this.adapter.spec.navigation;
    ensure(
      nav
        ? nav.pages.some((p) => p.id === location.pageId)
        : location.pageId === "__legacy__",
      "invalid_location",
      "This page is not part of the app.",
    );
    ++this.request;
    this.emit({
      location: { ...location },
      history: [...this.state.history, this.state.location],
      views: {},
      record: null,
      dirty: false,
      error: null,
      outcome: null,
    });
    void this.refresh();
    return true;
  }
  back(discard = false): boolean {
    if (this.state.pending || (this.state.dirty && !discard)) return false;
    const previous = this.state.history.at(-1);
    if (!previous) return false;
    ++this.request;
    this.emit({
      location: previous,
      history: this.state.history.slice(0, -1),
      views: {},
      record: null,
      dirty: false,
      error: null,
      outcome: null,
    });
    void this.refresh();
    return true;
  }
  async select(viewId: string, selection: Partial<ViewSettings>) {
    ensure(
      !this.state.dirty && !this.state.pending,
      "unsaved_changes",
      "Finish or discard the current edit before changing the view.",
    );
    this.settings.set(viewId, { ...this.settingsFor(viewId), ...selection });
    await this.refresh(false);
  }
  private async readView(
    view: ViewSpec,
    retain: number,
  ): Promise<RuntimeViewState> {
    if (!view.collectionId) return { ...emptyView({}), loading: false };
    let settings = this.settingsFor(view.id);
    if (view.type === "calendar" && !settings.selectedDay) {
      settings = { ...settings, selectedDay: this.now(), month: this.now() };
      this.settings.set(view.id, settings);
    }
    const query = buildViewQuery(this.adapter.spec, view, settings, this.now());
    if (view.type === "summary")
      return {
        ...emptyView(query),
        loading: false,
        summary: await this.adapter.summary(
          view.collectionId,
          query,
          view.groupByFieldId!,
        ),
      };
    if (view.type === "metric" || view.type === "chart") {
      const options = view.options!,
        aggregate: AggregateQuery = {
          metric: options.metric,
          ...("valueFieldId" in options && options.valueFieldId
            ? { fieldId: options.valueFieldId }
            : {}),
          ...(view.groupByFieldId ? { groupFieldId: view.groupByFieldId } : {}),
          ...(view.type === "chart" && view.options?.dateFieldId
            ? {
                dateFieldId: view.options.dateFieldId,
                buckets: dateBuckets(
                  this.now(),
                  view.options.bucket,
                  view.options.periods,
                ),
              }
            : {}),
        };
      const result = await this.adapter.aggregate(
        view.collectionId,
        query,
        aggregate,
      );
      return {
        ...emptyView(query),
        loading: false,
        total: result.total,
        aggregate: result,
      };
    }
    let page = await this.adapter.query(view.collectionId, query),
      records = page.records;
    const cursors = new Set<string>();
    while (page.nextCursor && records.length < retain) {
      ensure(
        !cursors.has(page.nextCursor) && page.records.length > 0,
        "invalid_response",
        "The refreshed cursor did not advance.",
      );
      cursors.add(page.nextCursor);
      page = await this.adapter.query(view.collectionId, {
        ...query,
        cursor: page.nextCursor,
      });
      records = [...records, ...page.records];
    }
    ensure(
      new Set(records.map((r) => r.id)).size === records.length,
      "invalid_response",
      "The refreshed pages overlap. Refresh the view.",
    );
    const result: RuntimeViewState = {
      query,
      records,
      total: page.total,
      nextCursor: page.nextCursor,
      loading: false,
    };
    if (view.type === "calendar") {
      // Global month badges use all matching rows, never the selected day's page.
      const base = buildViewQuery(
        this.adapter.spec,
        view,
        { ...settings, selectedDay: undefined },
        this.now(),
      );
      result.aggregate = await this.adapter.aggregate(view.collectionId, base, {
        metric: "count",
        dateFieldId: view.options!.dateFieldId,
        buckets: monthBuckets(
          settings.month ?? settings.selectedDay ?? this.now(),
        ),
      });
    }
    if (view.type === "board" && view.groupByFieldId)
      result.summary = await this.adapter.summary(
        view.collectionId,
        query,
        view.groupByFieldId,
      );
    return result;
  }
  async refresh(retain = true): Promise<void> {
    if (!this.recovered) {
      try {
        await this.recover();
      } catch {
        this.emit({
          error: new RuntimeError(
            "invalid_saved_command",
            "The saved command could not be recovered. Writes are blocked until the host resolves the saved data.",
          ),
        });
        return;
      }
    }
    if (
      this.disposed ||
      this.state.accessDenied ||
      this.state.dirty ||
      this.state.pending
    )
      return;
    const generation = ++this.request,
      previous = this.state.views,
      views = this.views,
      recordId = this.state.location.recordId;
    this.emit({ loading: true, error: null });
    const results = await Promise.allSettled(
      views.map(
        async (view) =>
          [
            view.id,
            await this.readView(
              view,
              retain ? (previous[view.id]?.records.length ?? 0) : 0,
            ),
          ] as const,
      ),
    );
    let record: RuntimeRecord | null = null,
      recordError: RuntimeError | null = null;
    if (recordId) {
      try {
        record = await this.adapter.get(recordId);
      } catch (error) {
        recordError = runtimeError(error);
      }
    }
    if (this.disposed || generation !== this.request) return;
    const denied =
      recordError && isRuntimeAccessFailure(recordError)
        ? recordError
        : results
            .flatMap((result) =>
              result.status === "rejected" ? [runtimeError(result.reason)] : [],
            )
            .find(isRuntimeAccessFailure);
    if (denied) {
      this.invalidateAccess(denied);
      return;
    }
    const next: Record<string, RuntimeViewState> = {};
    results.forEach((result, i) => {
      const view = views[i];
      next[view.id] =
        result.status === "fulfilled"
          ? result.value[1]
          : {
              ...emptyView({}),
              loading: false,
              error: runtimeError(result.reason),
            };
    });
    // Failed reads never leave an older private record or a cached form visible.
    this.emit({ views: next, record, loading: false, error: recordError });
  }
  async loadMore(viewId: string): Promise<void> {
    const current = this.state.views[viewId];
    if (
      !current?.nextCursor ||
      current.loading ||
      this.state.dirty ||
      this.state.pending
    )
      return;
    const generation = this.request,
      location = this.state.location,
      view = getView(this.adapter.spec, viewId),
      cursor = current.nextCursor;
    this.emit({
      views: {
        ...this.state.views,
        [viewId]: { ...current, loading: true, error: undefined },
      },
    });
    try {
      const page = await this.adapter.query(view.collectionId!, {
        ...current.query,
        cursor,
      });
      if (
        this.disposed ||
        generation !== this.request ||
        this.state.location !== location
      )
        return;
      ensure(
        page.versionId === this.adapter.versionId,
        "definition_conflict",
        "The published version changed.",
      );
      const ids = new Set(current.records.map((r) => r.id));
      ensure(
        page.records.every((r) => !ids.has(r.id)),
        "invalid_response",
        "The next page overlaps. Refresh the view.",
      );
      this.emit({
        views: {
          ...this.state.views,
          [viewId]: {
            ...current,
            loading: false,
            records: [...current.records, ...page.records],
            total: page.total,
            nextCursor: page.nextCursor,
          },
        },
      });
    } catch (error) {
      if (!this.disposed && generation === this.request) {
        const failure = runtimeError(error);
        if (isRuntimeAccessFailure(failure)) {
          this.invalidateAccess(failure);
          return;
        }
        this.emit({
          views: {
            ...this.state.views,
            [viewId]: {
              ...current,
              loading: false,
              error: failure,
            },
          },
        });
      }
    }
  }
  async execute(
    actionId: string,
    input: Record<string, JsonValue>,
    record?: RuntimeRecord,
  ): Promise<CommandOutcome | null> {
    ensure(!this.disposed, "disposed", "This app is closed.");
    ensure(
      !this.state.accessDenied,
      "forbidden",
      "Reopen the app to confirm your current access before continuing.",
    );
    await this.recover();
    ensure(
      this.adapter.preview || this.commands.durability === "durable",
      "unavailable",
      "This live host must provide a durable command store before sending writes.",
    );
    ensure(
      !this.state.pending,
      "pending_command",
      "Resolve the retained command before sending another write.",
    );
    const action = getAction(this.adapter.spec, actionId);
    ensure(
      this.adapter.permits(action, record),
      "forbidden",
      "This action is not allowed.",
    );
    if (record)
      ensure(
        record.collectionId ===
          getCollection(this.adapter.spec, action.collectionId).id,
        "invalid_input",
        "The record belongs to another collection.",
      );
    const command = decodeRetainedCommand(
      {
        appId: this.adapter.appId,
        operationId: this.operationId(),
        versionId: this.adapter.versionId,
        actionId,
        ...(record
          ? {
              targetRecordId: record.id,
              expectedRecordRevision: record.revision,
            }
          : {}),
        input,
      },
      this.adapter.appId,
    );
    // Fence any in-flight reads before the write. The original spec and record
    // revision stay in this command even if a newer version appears afterwards.
    ++this.request;
    // Persistence precedes the first network call. A failed save is a definite
    // local failure and must never send an unretained command.
    this.emit({
      pending: { command, status: "sending" },
      error: null,
      outcome: null,
    });
    try {
      await this.commands.save(command);
    } catch {
      const error = new RuntimeError(
        "command_store_failed",
        "The command could not be retained. No network request was sent.",
      );
      this.emit({ pending: { command, status: "failed", error }, error });
      return null;
    }
    if (this.disposed) return null;
    return this.send(command);
  }
  private async send(command: RuntimeCommand): Promise<CommandOutcome | null> {
    try {
      const outcome = await this.adapter.execute(command);
      if (this.disposed) return null;
      try {
        await this.commands.clear(command.operationId);
      } catch {
        throw new RuntimeError(
          "outcome_unknown",
          "The save succeeded but its recovery entry could not be cleared. Retry the original operation to confirm it safely.",
          true,
        );
      }
      this.emit({ pending: null, dirty: false, outcome, error: null });
      await this.refresh();
      return outcome;
    } catch (error) {
      if (this.disposed) return null;
      const failure = runtimeError(error, true);
      this.emit({
        pending: {
          command,
          status: failure.uncertain ? "uncertain" : "failed",
          error: failure,
        },
        error: failure,
      });
      if (isRuntimeAccessFailure(failure)) this.invalidateAccess(failure);
      return null;
    }
  }
  async retry(): Promise<CommandOutcome | null> {
    ensure(
      !this.disposed && !this.state.accessDenied,
      "forbidden",
      "Reopen the app to confirm your access before checking this retained command.",
    );
    const pending = this.state.pending;
    ensure(
      pending && pending.status === "uncertain",
      "no_retry",
      "There is no unresolved command to retry.",
    );
    this.emit({ pending: { ...pending, status: "sending" }, error: null });
    return this.send(pending.command);
  }
  /** A definite server rejection can be acknowledged; an unknown result cannot. */
  async acknowledgeFailure() {
    ensure(
      this.state.pending?.status === "failed",
      "outcome_unknown",
      "An unresolved result must be checked with the same command.",
    );
    try {
      await this.commands.clear(this.state.pending!.command.operationId);
      this.emit({ pending: null, error: null });
    } catch {
      this.emit({
        error: new RuntimeError(
          "command_store_failed",
          "The recovery entry could not be cleared. Its original command is retained.",
        ),
      });
    }
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    ++this.request;
    this.unsubscribe();
    this.listeners.clear();
    this.adapter.dispose();
  }
}
