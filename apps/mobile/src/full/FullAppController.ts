import { BackendError } from "../backend/errors";
import type { AppSpec } from "../spec/types";
import { decodeAppSpec } from "../spec/decode";
import { requestedDeviceCapabilities } from "../spec/bindings";
import { createHostStorage } from "../host/createHostStorage";
import { createDeviceBridge } from "../host/createDeviceBridge";
import type { HostScope } from "../host/scope";
import type { ScopedDeviceBridge } from "../host/device";
import { RuntimeController } from "../runtime/controller";
import { FunctionRuntimeAdapter } from "../runtime/functionAdapter";
import type { RuntimeAdapter, RuntimeTransport } from "../runtime/types";
import { UtilityTimerController } from "../runtime/timer";
import {
  ensure,
  isRuntimeAccessFailure,
  runtimeError,
} from "../runtime/errors";
import { freezeValidated } from "../runtime/immutable";
import { FullCommandJournal, type RetainedFullCommand } from "./commandJournal";
import {
  manifest,
  platformCapabilities,
  publicationReview,
  row,
  selected,
  same,
  type FullManifest,
  type PlatformCapabilities,
  type PublicationReview,
} from "./contracts";
import { applySemanticEdit, type SemanticEdit } from "./semanticEdits";

export type HostStorage = ReturnType<typeof createHostStorage>;
export interface FullAppOptions {
  scope: HostScope;
  transport: RuntimeTransport;
  newId: () => string;
  host?: HostStorage;
  adapterFactory?: (
    app: FullManifest,
    transport: RuntimeTransport,
  ) => RuntimeAdapter;
  deviceFactory?: typeof createDeviceBridge;
  onAccessFailure?: (code: string) => void;
}
export interface FullAppState {
  app: FullManifest | null;
  platform: PlatformCapabilities | null;
  candidate: AppSpec | null;
  dirty: boolean;
  editorError: string | null;
  loading: boolean;
  busy: boolean;
  error: string | null;
  conflict: boolean;
  pending: RetainedFullCommand | null;
  pendingStatus: "sending" | "uncertain" | "rejected" | null;
  review: PublicationReview | null;
  reviewSpec: AppSpec | null;
  runtimeOutdated: boolean;
  refreshRequired: boolean;
  guidance: { question: string; options: string[] }[] | null;
}
/** Authenticated transport is injected by the account registry. No credentials or model keys enter this controller. */
export class FullAppController {
  private state: FullAppState = {
    app: null,
    platform: null,
    candidate: null,
    dirty: false,
    editorError: null,
    loading: false,
    busy: false,
    error: null,
    conflict: false,
    pending: null,
    pendingStatus: null,
    review: null,
    reviewSpec: null,
    runtimeOutdated: false,
    refreshRequired: false,
    guidance: null,
  };
  private listeners = new Set<() => void>();
  private closed = false;
  private sequence = 0;
  private guidanceSequence = 0;
  private autosave: ReturnType<typeof setTimeout> | null = null;
  readonly host: HostStorage;
  private journal: FullCommandJournal;
  private journalSuspended = false;
  runtime: RuntimeController | null = null;
  timers: UtilityTimerController | null = null;
  device: ScopedDeviceBridge | null = null;
  constructor(readonly options: FullAppOptions) {
    this.host = options.host ?? createHostStorage(options.scope);
    this.journal = this.createJournal();
  }
  private createJournal() {
    return new FullCommandJournal(
      this.host.storage,
      "full-command",
      (command) => {
        const request = command.request;
        ensure(
          request.appId === this.options.scope.appId &&
            [
              "spec.saveDraft",
              "spec.publish",
              "spec.generate",
              "spec.keepPrevious",
            ].includes(String(request.op)),
          "invalid_saved_scope",
          "The retained operation does not belong to this app. It has not been replaced.",
        );
        ensure(
          typeof request.operationId === "string" &&
            /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(request.operationId),
          "invalid_saved_command",
          "The retained operation ID is invalid.",
        );
        if (request.op === "spec.saveDraft") decodeAppSpec(request.spec);
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
  private emit(change: Partial<FullAppState>) {
    if (this.closed) return;
    this.state = { ...this.state, ...change };
    for (const listener of this.listeners) listener();
  }
  get canBuild() {
    const app = this.state.app;
    return (
      !!app &&
      !this.state.refreshRequired &&
      !app.archived &&
      ["owner", "builder"].includes(app.role) &&
      app.capabilities.build === true
    );
  }
  private canRecover(app = this.state.app) {
    return (
      !!app &&
      ["owner", "builder"].includes(app.role) &&
      (app.archived || app.capabilities.build === true)
    );
  }
  get canLeave() {
    return (
      !this.state.dirty &&
      !this.state.editorError &&
      !this.state.busy &&
      !this.state.pending &&
      (this.runtime?.canLeave ?? true)
    );
  }
  private active() {
    ensure(
      !this.closed && this.host.lifetime.active,
      "disposed",
      "This account's app session is closed.",
    );
  }
  private editable() {
    this.active();
    ensure(
      !this.state.refreshRequired && !this.state.loading,
      "refresh_required",
      "Refresh the authorized manifest before making a new change.",
    );
    ensure(this.canBuild, "forbidden", "Current builder access is required.");
    ensure(
      !this.state.conflict,
      "revision_conflict",
      "Reload the current private draft before making another change.",
    );
    ensure(
      !this.state.pending && !this.state.busy,
      "pending_command",
      "Resolve the retained operation before making another change.",
    );
    ensure(
      !this.runtime?.getSnapshot().pending,
      "pending_command",
      "Resolve the pending record operation before editing the definition.",
    );
  }
  private stopAutosave() {
    if (this.autosave) clearTimeout(this.autosave);
    this.autosave = null;
  }
  private fail(error: unknown, mutation = false, accessRead = false) {
    if (this.closed) return;
    const failure = runtimeError(error, mutation);
    if (
      isRuntimeAccessFailure(failure) ||
      (accessRead && error instanceof BackendError && error.status === 404)
    ) {
      this.sequence++;
      this.guidanceSequence++;
      this.stopAutosave();
      this.disposeRuntime();
      this.journal.dispose();
      this.journalSuspended = true;
      this.emit({
        app: null,
        candidate: null,
        review: null,
        reviewSpec: null,
        guidance: null,
        pending: null,
        pendingStatus: null,
        dirty: false,
        editorError: null,
        busy: false,
        loading: false,
        error: failure.message,
      });
      this.options.onAccessFailure?.(failure.code);
      return;
    }
    this.emit({
      error: failure.message,
      busy: false,
      loading: false,
      pending: this.canRecover() ? this.journal.pending : null,
      pendingStatus: this.canRecover() ? this.journal.status : null,
    });
  }
  private disposeRuntime() {
    this.runtime?.dispose();
    this.timers?.dispose();
    this.device?.dispose();
    this.runtime = null;
    this.timers = null;
    this.device = null;
  }
  private install(app: FullManifest, acceptCandidate = false) {
    this.active();
    const prior = this.state.app;
    const build =
      !app.archived &&
      ["owner", "builder"].includes(app.role) &&
      app.capabilities.build === true;
    if (!this.canRecover(app)) {
      this.stopAutosave();
      this.guidanceSequence++;
      this.journal.dispose();
      this.journalSuspended = true;
    }
    if (this.canRecover(app) && this.journalSuspended) {
      this.journal = this.createJournal();
      this.journalSuspended = false;
    }
    const staleDirty =
      build &&
      this.state.dirty &&
      !acceptCandidate &&
      prior?.draft?.revision !== app.draft?.revision;
    const candidate = build
      ? acceptCandidate || !this.state.dirty
        ? (app.draft?.spec ?? null)
        : this.state.candidate
      : null;
    const changedRuntime =
      prior?.version?.id !== app.version?.id ||
      prior?.role !== app.role ||
      prior?.archived !== app.archived ||
      prior?.controlRevision !== app.controlRevision;
    const preserveRuntime =
      !!this.runtime &&
      !this.runtime.canLeave &&
      prior?.role === app.role &&
      prior?.archived === app.archived &&
      prior?.controlRevision === app.controlRevision;
    if (!app.version) {
      this.disposeRuntime();
    } else if (!this.runtime || (changedRuntime && !preserveRuntime)) {
      this.disposeRuntime();
      const adapter =
        this.options.adapterFactory?.(app, this.options.transport) ??
        new FunctionRuntimeAdapter(app, this.options.transport);
      this.runtime = new RuntimeController(
        adapter,
        this.options.newId,
        undefined,
        this.host.commands,
        { onAccessFailure: (failure) => this.fail(failure) },
      );
      this.timers = new UtilityTimerController(this.host.timers);
      this.device = (this.options.deviceFactory ?? createDeviceBridge)(
        this.host.storage,
        requestedDeviceCapabilities(app.version.spec),
      );
      void this.device.initialize().catch(() => {});
      void this.runtime.recover().catch((error) => this.fail(error));
    }
    const candidateChanged =
      !same(this.state.candidate, candidate) ||
      prior?.draft?.revision !== app.draft?.revision ||
      prior?.version?.id !== app.version?.id;
    this.emit({
      app,
      candidate,
      editorError: build ? this.state.editorError : null,
      dirty: build && this.state.dirty && !acceptCandidate,
      conflict: staleDirty || (!acceptCandidate && this.state.conflict),
      review: candidateChanged ? null : this.state.review,
      reviewSpec: candidateChanged ? null : this.state.reviewSpec,
      guidance: candidateChanged ? null : this.state.guidance,
      pending: this.canRecover(app) ? this.journal.pending : null,
      pendingStatus: this.canRecover(app) ? this.journal.status : null,
      runtimeOutdated: preserveRuntime && changedRuntime,
    });
  }
  async load() {
    this.active();
    const sequence = ++this.sequence;
    this.emit({ loading: true, error: null });
    try {
      const response = row(
        await this.options.transport({
          op: "spec.getApp",
          appId: this.options.scope.appId,
        }),
      );
      if (this.closed || sequence !== this.sequence) return;
      const app = manifest(response.app, this.options.scope.appId);
      this.install(app);
      this.emit({ refreshRequired: false });
      if (this.canRecover()) {
        await this.journal.recover();
        if (this.closed || sequence !== this.sequence) return;
        this.emit({
          pending: this.journal.pending,
          pendingStatus: this.journal.status,
        });
      }
      this.emit({ loading: false });
      try {
        const capabilities = platformCapabilities(
          await this.options.transport({ op: "spec.capabilities" }),
        );
        if (!this.closed && sequence === this.sequence)
          this.emit({ platform: capabilities });
      } catch (error) {
        if (!this.closed && sequence === this.sequence) this.fail(error);
      }
    } catch (error) {
      if (sequence === this.sequence) this.fail(error, false, true);
    }
  }
  /** Explicitly abandons only unsent local edits. Unknown commands remain locked. */
  discardLocalEdits() {
    this.active();
    ensure(
      !this.state.pending && !this.state.busy,
      "pending_command",
      "A retained operation cannot be discarded.",
    );
    this.stopAutosave();
    this.emit({
      candidate: this.state.app?.draft?.spec ?? null,
      dirty: false,
      editorError: null,
      conflict: false,
      review: null,
      reviewSpec: null,
      guidance: null,
      error: null,
    });
  }
  setCandidate(input: unknown, debounce = false) {
    this.editable();
    this.stopAutosave();
    try {
      const candidate = freezeValidated(decodeAppSpec(input));
      this.guidanceSequence++;
      this.emit({
        candidate,
        dirty: !same(candidate, this.state.app?.draft?.spec),
        editorError: null,
        review: null,
        reviewSpec: null,
        guidance: null,
        error: null,
      });
      if (debounce && this.state.dirty)
        this.autosave = setTimeout(() => {
          this.autosave = null;
          void this.save();
        }, 600);
    } catch (error) {
      this.emit({
        editorError:
          error instanceof Error
            ? error.message
            : "Fix the invalid local edit before saving.",
      });
      throw error;
    }
  }
  edit(edit: SemanticEdit, debounce = false) {
    this.editable();
    this.stopAutosave();
    ensure(
      this.state.candidate,
      "invalid_input",
      "Choose a template or create a candidate first.",
    );
    try {
      this.setCandidate(
        applySemanticEdit(this.state.candidate, edit, this.options.newId),
        debounce,
      );
    } catch (error) {
      this.emit({
        editorError:
          error instanceof Error
            ? error.message
            : "Fix the invalid local edit before saving.",
      });
      throw error;
    }
  }
  private decodeMutation(response: unknown, command: RetainedFullCommand) {
    const result = row(response),
      app = manifest(result.app, this.options.scope.appId),
      request = command.request;
    if (request.op === "spec.saveDraft")
      ensure(
        app.draft &&
          same(app.draft.spec, request.spec) &&
          app.draft.revision === (request.expectedRevision as number) + 1,
        "invalid_response",
        "The save response did not confirm the retained candidate.",
      );
    if (request.op === "spec.publish")
      ensure(
        app.version !== null &&
          app.version.hash === request.candidateHash &&
          app.draft?.publishedVersionId === app.version.id,
        "invalid_response",
        "The publish response did not confirm the reviewed candidate.",
      );
    if (request.op === "spec.generate" || request.op === "spec.keepPrevious")
      ensure(
        result.generation !== undefined,
        "invalid_response",
        "The generation result could not be confirmed.",
      );
    return app;
  }
  private async transmit() {
    this.emit({
      busy: true,
      pending: this.journal.pending,
      pendingStatus: "sending",
      error: null,
    });
    try {
      await this.journal.send(this.options.transport, (value, command) =>
        this.decodeMutation(value, command),
      );
      this.active();
      this.sequence++;
      this.disposeRuntime();
      this.emit({
        busy: true,
        refreshRequired: true,
        dirty: false,
        pending: null,
        pendingStatus: null,
        conflict: false,
        error: null,
        review: null,
        reviewSpec: null,
      });
      await this.load();
      this.emit({ busy: false });
    } catch (error) {
      this.fail(error, true);
    }
  }
  private async mutate(
    request: Record<string, unknown>,
    context: Record<string, unknown> = {},
  ) {
    this.editable();
    this.stopAutosave();
    this.sequence++;
    this.guidanceSequence++;
    this.emit({
      busy: true,
      error: null,
      review: null,
      reviewSpec: null,
      guidance: null,
    });
    try {
      await this.journal.prepare(request, context);
      this.active();
      await this.transmit();
    } catch (error) {
      this.fail(error, true);
    }
  }
  async save() {
    if (this.state.busy) return;
    try {
      this.editable();
      ensure(
        !this.state.editorError,
        "invalid_edit",
        "Fix or discard the invalid local edit before saving.",
      );
      if (!this.state.dirty) return;
      ensure(
        this.state.candidate,
        "invalid_input",
        "A valid candidate is required.",
      );
      await this.mutate(
        {
          op: "spec.saveDraft",
          appId: this.options.scope.appId,
          operationId: this.options.newId(),
          expectedRevision: this.state.app!.draft?.revision ?? 0,
          expectedVersionId: this.state.app!.version?.id ?? null,
          spec: this.state.candidate,
        },
        {
          kind: "save",
          originalVersionId: this.state.app!.version?.id ?? null,
        },
      );
    } catch (error) {
      this.fail(error);
    }
  }
  async flush() {
    if (this.state.busy) return false;
    this.stopAutosave();
    await this.save();
    return (
      !this.state.dirty &&
      !this.state.editorError &&
      !this.state.pending &&
      !this.state.busy &&
      !this.state.conflict
    );
  }
  async retry() {
    if (this.state.busy) return;
    try {
      this.active();
      ensure(
        this.canRecover() &&
          !this.state.busy &&
          this.journal.pending &&
          this.journal.status === "uncertain",
        "pending_command",
        "A retained operation can be retried only with current builder access.",
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
      this.emit({ pending: null, pendingStatus: null, error: null });
      await this.load();
    } catch (error) {
      this.fail(error);
    }
  }
  async review(
    enabledRuleIds: string[] = [],
    activateExistingRecordIds: string[] = [],
  ) {
    if (!(await this.flush())) return;
    try {
      this.editable();
      const draft = this.state.app!.draft;
      ensure(
        draft && !draft.publishedVersionId,
        "invalid_input",
        "Save a new private candidate before publication.",
      );
      const rules = selected(enabledRuleIds),
        records = selected(activateExistingRecordIds);
      ensure(
        rules.every((id) => {
          const rule = draft.spec.automationRequests.find((r) => r.id === id);
          return (
            rule && this.state.platform?.effects.includes(rule.effect.type)
          );
        }),
        "unavailable",
        "Selected reminder effects are not operational on this backend.",
      );
      const sequence = ++this.sequence;
      this.emit({ busy: true, error: null, review: null, reviewSpec: null });
      const result = publicationReview(
        row(
          await this.options.transport({
            op: "spec.review",
            appId: this.options.scope.appId,
            expectedRevision: draft.revision,
            enabledRuleIds: rules,
            activateExistingRecordIds: records,
          }),
        ).review,
      );
      if (this.closed || sequence !== this.sequence) return;
      ensure(
        result.candidateHash === draft.candidateHash &&
          result.expectedRevision === draft.revision &&
          result.baseVersionId === draft.baseVersionId &&
          result.currentVersionId === (this.state.app!.version?.id ?? null) &&
          same(result.enabledRuleIds, rules) &&
          same(result.activateExistingRecordIds, records),
        "invalid_response",
        "The review does not match this candidate and approval scope.",
      );
      this.emit({ review: result, reviewSpec: draft.spec, busy: false });
    } catch (error) {
      this.fail(error);
    }
  }
  async publish() {
    if (this.state.busy) return;
    try {
      this.editable();
      const review = this.state.review,
        draft = this.state.app!.draft;
      ensure(
        review &&
          draft &&
          !this.state.dirty &&
          same(draft.spec, this.state.reviewSpec) &&
          draft.revision === review.expectedRevision &&
          draft.candidateHash === review.candidateHash &&
          draft.baseVersionId === review.baseVersionId &&
          (this.state.app!.version?.id ?? null) === review.currentVersionId &&
          review.compatibilityErrors.length === 0,
        "review_required",
        "Review the exact current candidate before publishing.",
      );
      await this.mutate(
        {
          op: "spec.publish",
          appId: this.options.scope.appId,
          operationId: this.options.newId(),
          expectedRevision: review.expectedRevision,
          expectedVersionId: review.currentVersionId,
          candidateHash: review.candidateHash,
          reviewHash: review.reviewHash,
          enabledRuleIds: review.enabledRuleIds,
          activateExistingRecordIds: review.activateExistingRecordIds,
        },
        { kind: "publish", review, spec: this.state.reviewSpec },
      );
    } catch (error) {
      this.fail(error);
    }
  }
  async generate(request: string, startFromScratch = false) {
    if (!(await this.flush())) return;
    try {
      this.editable();
      ensure(
        this.state.platform?.generation,
        "unavailable",
        "AI generation is not configured. Templates and manual editing remain available.",
      );
      ensure(
        request.trim().length > 0 &&
          new TextEncoder().encode(request).length <= 16384,
        "invalid_input",
        "Describe the app in no more than 16 KiB.",
      );
      await this.mutate(
        {
          op: "spec.generate",
          appId: this.options.scope.appId,
          operationId: this.options.newId(),
          expectedRevision: this.state.app!.draft?.revision ?? 0,
          expectedVersionId: this.state.app!.version?.id ?? null,
          request,
          startFromScratch,
        },
        { kind: "generate" },
      );
    } catch (error) {
      this.fail(error);
    }
  }
  async pollGeneration() {
    const job = this.state.app?.generation;
    if (
      !job ||
      this.state.busy ||
      this.state.pending ||
      this.state.dirty ||
      this.closed
    )
      return;
    const sequence = ++this.sequence;
    try {
      const response = row(
        await this.options.transport({
          op: "spec.getGeneration",
          appId: this.options.scope.appId,
          jobId: job.id,
        }),
      );
      if (this.closed || sequence !== this.sequence) return;
      const app = manifest(response.app, this.options.scope.appId);
      ensure(
        app.generation?.id === job.id || app.generation === null,
        "invalid_response",
        "Generation job identity changed.",
      );
      this.install(app, true);
    } catch (error) {
      if (sequence === this.sequence) this.fail(error);
    }
  }
  async keepPrevious() {
    if (this.state.busy) return;
    try {
      this.editable();
      const job = this.state.app!.generation;
      ensure(
        job?.mode === "edit" &&
          job.status === "failed" &&
          this.state.app!.draft,
        "invalid_input",
        "Only a failed edit with a previous valid candidate can be kept.",
      );
      await this.mutate(
        {
          op: "spec.keepPrevious",
          appId: this.options.scope.appId,
          jobId: job.id,
          operationId: this.options.newId(),
          expectedRevision: this.state.app!.draft.revision,
        },
        { kind: "keepPrevious" },
      );
    } catch (error) {
      this.fail(error);
    }
  }
  async requestGuidance(request: string) {
    try {
      this.editable();
      ensure(
        this.state.platform?.guidance,
        "unavailable",
        "Guidance is not configured.",
      );
      ensure(
        request.length <= 2000 &&
          new TextEncoder().encode(request).length <= 4000,
        "invalid_input",
        "Guidance requests must fit 2,000 characters and 4,000 bytes.",
      );
      const sequence = ++this.guidanceSequence;
      this.emit({ error: null, guidance: null });
      const response = row(
        await this.options.transport({
          op: "spec.guidance",
          workspaceId: this.state.app!.workspaceId,
          appId: this.options.scope.appId,
          request,
        }),
      );
      if (this.closed || sequence !== this.guidanceSequence) return;
      ensure(
        Array.isArray(response.questions) && response.questions.length <= 3,
        "invalid_response",
        "Guidance could not be read.",
      );
      const questions = response.questions.map((item) => {
        const q = row(item);
        ensure(
          typeof q.question === "string" &&
            q.question.length <= 2000 &&
            Array.isArray(q.options) &&
            q.options.every((v) => typeof v === "string" && v.length <= 2000),
          "invalid_response",
          "Guidance could not be read.",
        );
        return { question: q.question, options: q.options as string[] };
      });
      this.emit({ guidance: questions });
    } catch (error) {
      this.fail(error);
    }
  }
  invalidateGuidance(keepVisible = false) {
    this.guidanceSequence++;
    if (!keepVisible) this.emit({ guidance: null });
  }
  async useLatestVersion() {
    if (this.runtime && !this.runtime.canLeave) {
      this.emit({
        error:
          "Save or resolve the current record operation before opening the latest version.",
      });
      return;
    }
    this.disposeRuntime();
    await this.load();
  }
  setLiveActive(active: boolean) {
    this.device?.setActive(active);
  }
  dispose() {
    if (this.closed) return;
    this.closed = true;
    this.sequence++;
    this.guidanceSequence++;
    this.stopAutosave();
    this.disposeRuntime();
    this.journal.dispose();
    this.host.lifetime.dispose();
    this.state = {
      ...this.state,
      app: null,
      candidate: null,
      editorError: null,
      review: null,
      reviewSpec: null,
      pending: null,
      guidance: null,
    };
    this.listeners.clear();
  }
}
