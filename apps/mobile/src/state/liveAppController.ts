import { BackendError } from "../backend/errors";
import type {
  AppBackend,
  AppDocument,
  LiveRecord,
  SaveDraft,
  PublishApp,
  SaveRecord,
} from "../backend/types";
import { validateDefinition, validateValues } from "../preview/model";
import type { Definition, Values } from "../preview/model";

export type PendingSave =
  | { kind: "draft"; command: SaveDraft }
  | { kind: "publish"; command: PublishApp }
  | { kind: "record"; command: SaveRecord };
export type PublicationReview = Pick<
  PublishApp,
  "expectedRevision" | "candidateRevision" | "expectedPublishedRevision"
>;
export interface LiveAppState {
  app: AppDocument | null;
  records: LiveRecord[];
  nextCursor: string | null;
  loading: boolean;
  busy: boolean;
  error: string | null;
  notice: string | null;
  pending: PendingSave | null;
  editingDefinition: Definition | null;
  editingRevision: number | null;
  editingPublishedRevision: number | null;
}

const initial = (): LiveAppState => ({
  app: null,
  records: [],
  nextCursor: null,
  loading: false,
  busy: false,
  error: null,
  notice: null,
  pending: null,
  editingDefinition: null,
  editingRevision: null,
  editingPublishedRevision: null,
});
const message = (error: unknown) =>
  error instanceof BackendError
    ? error.message
    : "We could not confirm this request. Check your connection and retry the same save.";
const snapshot = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

/** Retained commands live above routes; no operation is repeated automatically. */
export class LiveAppController {
  private state = initial();
  private listeners = new Set<() => void>();
  private generation = 0;
  private disposed = false;
  constructor(
    private backend: AppBackend,
    readonly appId: string,
    private onAuthFailure: () => void,
  ) {}
  getSnapshot = () => this.state;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };
  private set(patch: Partial<LiveAppState>) {
    if (this.disposed) return;
    this.state = { ...this.state, ...patch };
    for (const listener of this.listeners) listener();
  }
  private fail(error: unknown) {
    if (error instanceof BackendError && error.kind === "unauthenticated") {
      this.set(initial());
      this.onAuthFailure();
      return;
    }
    if (
      error instanceof BackendError &&
      (error.status === 403 || error.status === 404)
    ) {
      this.set({
        app: null,
        records: [],
        nextCursor: null,
        editingDefinition: null,
        editingRevision: null,
        editingPublishedRevision: null,
      });
    }
    this.set({ error: message(error), loading: false, busy: false });
  }
  async load(): Promise<void> {
    if (this.disposed || this.state.busy) return;
    const generation = ++this.generation;
    this.set({ loading: true, error: null });
    try {
      const app = await this.backend.getApp(this.appId);
      if (this.disposed || generation !== this.generation) return;
      // A confirmed downgrade takes effect even if the following record read
      // loses its response. Never leave the former private editor available.
      if (!app.capabilities?.editDefinition)
        this.set({
          app,
          records: [],
          nextCursor: null,
          editingDefinition: null,
          editingRevision: null,
          editingPublishedRevision: null,
        });
      const page = app.publishedDefinition
        ? await this.backend.listRecords(this.appId, app.publishedRevision)
        : null;
      if (this.disposed || generation !== this.generation) return;
      if (page && app.publishedDefinition) {
        for (const record of page.records)
          validateValues(app.publishedDefinition, record.values);
      }
      this.set({
        app,
        records: page?.records ?? [],
        nextCursor: page?.nextCursor ?? null,
        loading: false,
        ...(!app.capabilities?.editDefinition
          ? {
              editingDefinition: null,
              editingRevision: null,
              editingPublishedRevision: null,
            }
          : {}),
      });
    } catch (error) {
      if (!this.disposed && generation === this.generation) this.fail(error);
    }
  }
  async loadMore(): Promise<void> {
    const app = this.state.app;
    const afterId = this.state.nextCursor;
    if (
      !app?.publishedDefinition ||
      !afterId ||
      this.state.loading ||
      this.state.busy ||
      this.disposed
    )
      return;
    const generation = ++this.generation;
    this.set({ loading: true, error: null });
    try {
      const page = await this.backend.listRecords(
        this.appId,
        app.publishedRevision,
        afterId,
      );
      if (this.disposed || generation !== this.generation) return;
      const oldIds = new Set(this.state.records.map((record) => record.id));
      for (const record of page.records) {
        if (oldIds.has(record.id))
          throw new BackendError(
            "Records changed while loading. Refresh the app.",
            "invalid_response",
            "invalid_response",
          );
        validateValues(app.publishedDefinition, record.values);
      }
      this.set({
        records: [...this.state.records, ...page.records],
        nextCursor: page.nextCursor,
        loading: false,
      });
    } catch (error) {
      if (!this.disposed && generation === this.generation) this.fail(error);
    }
  }
  editDefinition(definition: Definition): void {
    if (
      !this.state.app?.capabilities?.editDefinition ||
      this.state.pending ||
      this.state.busy
    )
      return;
    this.set({
      editingDefinition: snapshot(definition),
      editingRevision:
        this.state.editingRevision ?? this.state.app.draftRevision,
      editingPublishedRevision:
        this.state.editingPublishedRevision ?? this.state.app.publishedRevision,
      notice: null,
    });
  }
  async reloadEditor(): Promise<void> {
    if (this.state.pending || this.state.busy) return;
    await this.load();
    if (!this.state.error)
      this.set({
        editingDefinition: null,
        editingRevision: null,
        editingPublishedRevision: null,
      });
  }
  async saveDefinition(definition: Definition): Promise<void> {
    if (
      !this.state.app?.capabilities?.editDefinition ||
      this.state.pending ||
      this.state.busy ||
      this.state.loading
    )
      return;
    try {
      validateDefinition(definition);
    } catch {
      this.set({
        error: "Please review the app title and fields before saving.",
      });
      return;
    }
    await this.run({
      kind: "draft",
      command: {
        appId: this.appId,
        operationId: this.backend.newId(),
        expectedRevision:
          this.state.editingRevision ?? this.state.app.draftRevision,
        expectedPublishedRevision:
          this.state.editingPublishedRevision ??
          this.state.app.publishedRevision,
        definition: snapshot(definition),
      },
    });
  }
  async publish(review: PublicationReview): Promise<void> {
    const app = this.state.app;
    if (
      !app?.definition ||
      !app.capabilities?.editDefinition ||
      app.draftRevision < 1 ||
      this.state.pending ||
      this.state.busy ||
      this.state.loading
    )
      return;
    await this.run({
      kind: "publish",
      command: {
        appId: this.appId,
        operationId: this.backend.newId(),
        ...snapshot(review),
      },
    });
  }
  async writeRecord(record: LiveRecord | null, values: Values): Promise<void> {
    const app = this.state.app;
    if (
      !app?.publishedDefinition ||
      !app.capabilities?.writeRecords ||
      this.state.pending ||
      this.state.busy ||
      this.state.loading
    )
      return;
    let valid: Values;
    try {
      valid = validateValues(app.publishedDefinition, values);
    } catch (error) {
      this.set({
        error:
          error instanceof Error ? error.message : "Please review the record.",
      });
      return;
    }
    await this.run({
      kind: "record",
      command: {
        appId: this.appId,
        id: record?.id ?? this.backend.newId(),
        operationId: this.backend.newId(),
        expectedRevision: record?.revision ?? 0,
        definitionRevision: app.publishedRevision,
        values: snapshot(valid),
      },
    });
  }
  async retry(): Promise<void> {
    if (this.state.pending && !this.state.busy && !this.disposed)
      await this.run(this.state.pending);
  }
  private async run(pending: PendingSave): Promise<void> {
    if (this.disposed) return;
    ++this.generation;
    this.set({ busy: true, pending, error: null, notice: null });
    try {
      if (pending.kind === "draft") {
        const app = await this.backend.saveDraft(pending.command);
        if (
          !this.disposed &&
          (!this.state.app ||
            (app.draftRevision >= this.state.app.draftRevision &&
              app.publishedRevision >= this.state.app.publishedRevision))
        )
          this.set({ app });
      } else if (pending.kind === "publish") {
        const app = await this.backend.publishApp(pending.command);
        if (
          !this.disposed &&
          (!this.state.app ||
            (app.draftRevision >= this.state.app.draftRevision &&
              app.publishedRevision >= this.state.app.publishedRevision))
        )
          this.set({ app });
      } else {
        const record = await this.backend.saveRecord(pending.command);
        if (!this.disposed)
          this.set({
            records: this.state.records.some((row) => row.id === record.id)
              ? this.state.records.map((row) =>
                  row.id === record.id && row.revision <= record.revision
                    ? record
                    : row,
                )
              : [record, ...this.state.records],
          });
      }
      if (this.disposed) return;
      this.set({
        busy: false,
        pending: null,
        notice:
          pending.kind === "publish"
            ? "This version is live."
            : pending.kind === "draft"
              ? "Draft saved."
              : "Record saved.",
      });
      if (pending.kind === "draft")
        this.set({
          editingDefinition: null,
          editingRevision: null,
          editingPublishedRevision: null,
        });
      await this.load();
    } catch (error) {
      if (this.disposed) return;
      const uncertain = !(error instanceof BackendError) || error.uncertain;
      this.set({ pending: uncertain ? pending : null });
      this.fail(error);
    }
  }
  dispose(): void {
    this.disposed = true;
    this.generation++;
    this.listeners.clear();
    this.state = initial();
  }
}

export class LiveAppRegistry {
  private entries = new Map<
    string,
    { userId: string; controller: LiveAppController }
  >();
  constructor(
    private backend: AppBackend,
    private onAuthFailure: () => void,
  ) {}
  get(userId: string, appId: string): LiveAppController {
    const key = `${userId}:${appId}`;
    let entry = this.entries.get(key);
    if (!entry) {
      entry = {
        userId,
        controller: new LiveAppController(
          this.backend,
          appId,
          this.onAuthFailure,
        ),
      };
      this.entries.set(key, entry);
    }
    return entry.controller;
  }
  keepUser(userId: string | null): void {
    for (const [key, entry] of this.entries)
      if (entry.userId !== userId) {
        entry.controller.dispose();
        this.entries.delete(key);
      }
  }
  dispose(): void {
    this.keepUser(null);
  }
}
