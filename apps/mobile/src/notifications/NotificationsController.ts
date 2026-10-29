import { BackendError } from "../backend/errors";
import { createHostStorage } from "../host/createHostStorage";
import type { HostScope } from "../host/scope";
import type { HostStorage } from "../full/FullAppController";
import {
  ensure,
  isRuntimeAccessFailure,
  runtimeError,
} from "../runtime/errors";
import { runtimeJsonSnapshot } from "../runtime/json";
import { freezeValidated } from "../runtime/immutable";
import type {
  RuntimeAdapter,
  RuntimeRecord,
  RuntimeTransport,
} from "../runtime/types";
import {
  id,
  inboxPage,
  type InboxItem,
  type ReadNotification,
  type SessionLifetime,
} from "./contracts";
import { NotificationJournal } from "./NotificationJournal";
export interface VerifiedNotificationTarget {
  appId: string;
  versionId: string;
  recordId: string;
  collectionId: string;
  record: RuntimeRecord;
}
export interface NotificationsOptions {
  scope: Omit<HostScope, "appId">;
  transport: RuntimeTransport;
  newId: () => string;
  host?: HostStorage;
  lifetime?: SessionLifetime;
  onUnauthenticated?: () => void;
}
export interface NotificationsState {
  items: InboxItem[];
  cursor: string | null;
  loading: boolean;
  busy: boolean;
  error: string | null;
  pending: ReadNotification | null;
  phase: "sending" | "uncertain" | "rejected" | null;
  openingId: string | null;
}
const authFailure = (error: unknown) =>
  (error instanceof BackendError &&
    (error.kind === "unauthenticated" || error.status === 401)) ||
  runtimeError(error).code === "unauthenticated";
const accessFailure = (error: unknown) =>
  isRuntimeAccessFailure(runtimeError(error)) ||
  (error instanceof BackendError && [403, 404].includes(error.status ?? 0));
export class NotificationsController {
  readonly host: HostStorage;
  private journal: NotificationJournal;
  private closed = false;
  private sequence = 0;
  private targetSequence = 0;
  private stopLifetime = () => {};
  private listeners = new Set<() => void>();
  private state: NotificationsState = {
    items: [],
    cursor: null,
    loading: false,
    busy: false,
    error: null,
    pending: null,
    phase: null,
    openingId: null,
  };
  constructor(readonly options: NotificationsOptions) {
    this.host =
      options.host ?? createHostStorage({ ...options.scope, appId: "inbox" });
    const actual = this.host.lifetime.scope;
    ensure(
      actual.appId === "inbox" &&
        actual.accountId === options.scope.accountId &&
        actual.projectId === options.scope.projectId &&
        actual.endpoint ===
          new URL(options.scope.endpoint).toString().replace(/\/+$/, ""),
      "invalid_scope",
      "Inbox recovery must belong to the same backend, project and account.",
    );
    this.journal = new NotificationJournal(
      this.host.storage,
      this.host.lifetime,
    );
    this.stopLifetime =
      options.lifetime?.onDispose?.(() => this.dispose()) ?? (() => {});
  }
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  getSnapshot = () => this.state;
  private active() {
    this.host.lifetime.assertActive();
    this.options.lifetime?.assertActive();
    ensure(!this.closed, "disposed", "This account's inbox is closed.");
  }
  private emit(change: Partial<NotificationsState>) {
    if (this.closed) return;
    this.state = { ...this.state, ...change };
    for (const listener of this.listeners) listener();
  }
  private fail(error: unknown, mutation = false, appId?: string) {
    if (this.closed) return;
    const failure = runtimeError(error, mutation);
    if (authFailure(error)) {
      this.emit({
        items: [],
        cursor: null,
        pending: null,
        phase: null,
        loading: false,
        busy: false,
        openingId: null,
        error: failure.message,
      });
      try {
        this.options.onUnauthenticated?.();
      } finally {
        this.dispose();
      }
      return;
    }
    if (accessFailure(error)) {
      this.targetSequence++;
      this.emit({
        items: appId
          ? this.state.items.filter((item) => item.appId !== appId)
          : [],
        cursor: null,
        openingId: null,
        loading: false,
        error:
          "Current access to these notifications could not be confirmed. Refresh after checking app access.",
      });
    } else this.emit({ loading: false, error: failure.message });
  }
  async load(more = false) {
    if (
      this.closed ||
      !this.host.lifetime.active ||
      (this.options.lifetime && !this.options.lifetime.active)
    )
      return;
    this.active();
    const cursor = more ? this.state.cursor : null;
    if (more && (!cursor || this.state.loading)) return;
    const sequence = ++this.sequence;
    this.emit({ loading: true, error: null });
    try {
      const response = await this.options.transport(
        {
          op: "spec.inbox",
          ...(cursor ? { afterId: cursor } : {}),
        },
        {
          isCurrent: () =>
            !this.closed &&
            this.host.lifetime.active &&
            (this.options.lifetime?.active ?? true) &&
            sequence === this.sequence,
        },
      );
      this.active();
      if (sequence !== this.sequence) return;
      const page = inboxPage(response);
      if (more)
        ensure(
          page.items.every(
            (item) =>
              !this.state.items.some((existing) => existing.id === item.id),
          ) && page.nextCursor !== cursor,
          "invalid_response",
          "The inbox page overlaps earlier results. Refresh the inbox.",
        );
      this.emit({
        items: more ? [...this.state.items, ...page.items] : page.items,
        cursor: page.nextCursor,
        loading: false,
      });
      await this.journal.recover();
      this.active();
      if (sequence !== this.sequence) return;
      this.emit({ pending: this.journal.pending, phase: this.journal.phase });
    } catch (error) {
      if (sequence === this.sequence) this.fail(error);
    }
  }
  private loaded(input: InboxItem) {
    const current = this.state.items.find((item) => item.id === input.id);
    ensure(
      current &&
        current.appId === input.appId &&
        current.runId === input.runId &&
        current.recordId === input.recordId &&
        current.collectionId === input.collectionId,
      "invalid_input",
      "Refresh this notification before using it.",
    );
    return current;
  }
  private async transmit() {
    this.emit({
      busy: true,
      pending: this.journal.pending,
      phase: "sending",
      error: null,
    });
    try {
      const command = await this.journal.send(this.options.transport);
      this.active();
      this.emit({
        items: this.state.items.map((item) =>
          item.id === command.notificationId &&
          item.appId === command.appId &&
          item.runId === command.runId
            ? { ...item, isRead: true }
            : item,
        ),
        busy: false,
        pending: null,
        phase: null,
      });
    } catch (error) {
      this.fail(error, true, this.journal.pending?.appId);
      this.emit({
        busy: false,
        pending: this.journal.pending,
        phase: this.journal.phase,
      });
    }
  }
  async markRead(input: InboxItem) {
    if (this.state.busy) return;
    try {
      this.active();
      const item = this.loaded(input);
      if (item.isRead) return;
      ensure(
        !this.state.pending,
        "pending_command",
        "Resolve the original notification read receipt first.",
      );
      this.emit({ busy: true, error: null });
      await this.journal.prepare({
        op: "spec.readNotification",
        appId: item.appId,
        runId: item.runId,
        notificationId: item.id,
        operationId: this.options.newId(),
      });
      this.active();
      await this.transmit();
    } catch (error) {
      this.fail(error, true, input.appId);
      this.emit({
        busy: false,
        pending: this.journal.pending,
        phase: this.journal.phase,
      });
    }
  }
  async retry() {
    if (this.state.busy) return;
    try {
      this.active();
      ensure(
        this.journal.pending && this.journal.phase === "uncertain",
        "pending_command",
        "No uncertain read receipt is ready to check.",
      );
      await this.transmit();
    } catch (error) {
      this.fail(error, true);
    }
  }
  async acknowledgeRejection() {
    if (this.state.busy) return;
    try {
      await this.journal.acknowledgeRejection();
      this.active();
      this.emit({ pending: null, phase: null, error: null });
    } catch (error) {
      this.fail(error);
    }
  }
  async verifyTarget(
    input: InboxItem,
    resolveRuntime: (appId: string) => Promise<RuntimeAdapter>,
  ): Promise<VerifiedNotificationTarget | null> {
    this.active();
    const sequence = ++this.targetSequence;
    try {
      const item = this.loaded(input);
      ensure(
        item.recordId && item.collectionId,
        "not_found",
        "The current record is unavailable.",
      );
      this.emit({ openingId: item.id, error: null });
      const adapter = await resolveRuntime(item.appId);
      this.active();
      if (sequence !== this.targetSequence) return null;
      ensure(
        !adapter.preview && adapter.appId === item.appId,
        "invalid_response",
        "The notification target belongs to a different app.",
      );
      const versionId = adapter.versionId;
      id(versionId);
      const record = await adapter.get(item.recordId, {
        isCurrent: () =>
          !this.closed &&
          this.host.lifetime.active &&
          (this.options.lifetime?.active ?? true) &&
          sequence === this.targetSequence,
      });
      this.active();
      if (sequence !== this.targetSequence) return null;
      this.loaded(item);
      ensure(
        adapter.appId === item.appId &&
          adapter.versionId === versionId &&
          record.id === item.recordId &&
          record.collectionId === item.collectionId,
        "invalid_response",
        "The current record does not match the notification target.",
      );
      const checked = freezeValidated(
        runtimeJsonSnapshot(record) as RuntimeRecord,
      );
      this.emit({ openingId: null });
      return freezeValidated({
        appId: item.appId,
        versionId,
        recordId: record.id,
        collectionId: record.collectionId,
        record: checked,
      });
    } catch (error) {
      if (sequence === this.targetSequence) {
        this.fail(error, false, input.appId);
        this.emit({ openingId: null });
      }
      return null;
    }
  }
  async openTarget(
    input: InboxItem,
    resolveRuntime: (appId: string) => Promise<RuntimeAdapter>,
    open: (target: VerifiedNotificationTarget) => void | Promise<void>,
  ) {
    const target = await this.verifyTarget(input, resolveRuntime);
    if (!target) return;
    try {
      this.active();
      await open(target);
      this.active();
    } catch (error) {
      this.fail(error, false, input.appId);
    }
  }
  dispose() {
    if (this.closed) return;
    this.closed = true;
    this.sequence++;
    this.targetSequence++;
    this.stopLifetime();
    this.journal.dispose();
    this.host.lifetime.dispose();
    this.state = {
      ...this.state,
      items: [],
      cursor: null,
      pending: null,
      phase: null,
      openingId: null,
      loading: false,
      busy: false,
      error: null,
    };
    this.listeners.clear();
  }
}
