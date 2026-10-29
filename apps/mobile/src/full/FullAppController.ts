import {
  AcceptedConversation,
  acceptedRequest,
  type ConversationSnapshot,
} from "./conversation";
import {
  assessClarification,
  builtInClarification,
  clarificationAccessFailure,
  type ClarificationAssessment,
} from "./clarification";
import { StaticPreviewImagePreloader } from "../host/staticPreviewImages";
import { staticPreviewImageIds } from "../runtime/previewImageAssets";
import type { PreviewStaticImageAssets } from "../runtime/previewImageAssets";
import type { PrivateMediaController } from "../media/controller";
import type { MediaRuntimeAdapter } from "../media/adapter";
import {
  createDraftMediaController,
  selectReadyDraftMedia,
} from "../media/draft";
import type {
  DraftMediaController,
  SavedDraftMediaSnapshot,
  SavedDraftMediaContext,
} from "../media/draft";
import type { InvalidationStamp } from "../runtime/invalidationTypes";
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
  RuntimeError,
  isRuntimeAccessFailure,
  runtimeError,
} from "../runtime/errors";
import { freezeValidated } from "../runtime/immutable";
import { FullCommandJournal, type RetainedFullCommand } from "./commandJournal";
import {
  manifest,
  generation as decodeGeneration,
  type Generation,
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
    context: { host: HostStorage; platform: PlatformCapabilities | null },
  ) => RuntimeAdapter;
  draftMediaFactory?: (
    saved: SavedDraftMediaSnapshot,
    transport: RuntimeTransport,
    context: {
      host: HostStorage;
      current: () => SavedDraftMediaSnapshot | null;
      onAccessFailure: (error: RuntimeError) => void;
    },
  ) => DraftMediaController;
  deviceFactory?: typeof createDeviceBridge;
  onAccessFailure?: (code: string) => void;
}
export interface FullAppState {
  app: FullManifest | null;
  platform: PlatformCapabilities | null;
  candidate: AppSpec | null;
  dirty: boolean;
  editorError: string | null;
  editorResetEpoch: number;
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
  guidance: ClarificationAssessment | null;
  guidanceLoading: boolean;
  preparedRequest: string | null;
  generationRequest: string;
  conversation: ConversationSnapshot;
  previewStaticImageAssets: PreviewStaticImageAssets | undefined;
  previewImagesLoading: boolean;
  previewUnavailableAssetCount: number;
}
/** Authenticated transport is injected by the account registry. No credentials or model keys enter this controller. */
export class FullAppController {
  private state: FullAppState = {
    app: null,
    platform: null,
    candidate: null,
    dirty: false,
    editorError: null,
    editorResetEpoch: 0,
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
    guidanceLoading: false,
    preparedRequest: null,
    generationRequest: "",
    conversation: { entries: [], omitted: 0 },
    previewStaticImageAssets: undefined,
    previewImagesLoading: false,
    previewUnavailableAssetCount: 0,
  };
  private listeners = new Set<() => void>();
  private editorInputGuards = new Set<() => boolean>();
  private liveLeases = new Map<symbol, boolean>();
  private closed = false;
  private sequence = 0;
  private guidanceSequence = 0;
  private preparedIdea: string | null = null;
  private composerRequest: string | null = null;
  private conversation = new AcceptedConversation();
  private acceptedGenerationReceipts = new Map<string, Generation>();
  private autosave: ReturnType<typeof setTimeout> | null = null;
  private saveTask: Promise<void> | null = null;
  private publishedEditTask: Promise<void> | null = null;
  readonly host: HostStorage;
  private journal: FullCommandJournal;
  private journalSuspended = false;
  runtime: RuntimeController | null = null;
  timers: UtilityTimerController | null = null;
  device: ScopedDeviceBridge | null = null;
  draftMedia: DraftMediaController | null = null;
  private draftMediaKey: string | null = null;
  private previewImageLoader: StaticPreviewImagePreloader | null = null;
  private previewImageSource: PrivateMediaController | null = null;
  private previewImageSpec: AppSpec | null = null;
  private previewImageEpoch = 0;
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
    this.reconcileDraftMedia();
    this.reconcileStaticPreviewImages();
    for (const listener of this.listeners) listener();
  }
  /** A read-only declaration for isolated preview, never a live runtime or automatic draft. */
  get previewSpec(): AppSpec | null {
    return this.canBuild
      ? (this.state.candidate ?? this.state.app?.version?.spec ?? null)
      : null;
  }
  get canEditPublishedVersion(): boolean {
    return (
      this.canBuild &&
      !!this.state.app?.version &&
      !this.state.app.draft &&
      !this.state.candidate &&
      this.canLeave &&
      !this.state.loading &&
      !this.state.refreshRequired &&
      !this.state.conflict &&
      !["queued", "generating", "validating"].includes(
        this.state.app.generation?.status ?? "",
      )
    );
  }
  /** Explicit customization of the displayed immutable version; never a side effect of opening Build. */
  editPublishedVersion(): Promise<void> {
    if (this.publishedEditTask) return this.publishedEditTask;
    const task = this.performPublishedEdit();
    this.publishedEditTask = task;
    void task.then(
      () => {
        if (this.publishedEditTask === task) this.publishedEditTask = null;
      },
      () => {
        if (this.publishedEditTask === task) this.publishedEditTask = null;
      },
    );
    return task;
  }
  private async performPublishedEdit() {
    try {
      this.editable();
      ensure(
        this.canEditPublishedVersion,
        "pending_command",
        "Resolve existing draft, generation or record work before copying the published version.",
      );
      const published = this.state.app!.version!;
      await this.load();
      ensure(
        !this.state.error && !this.state.loading && !this.state.refreshRequired,
        "refresh_required",
        "The current published version and access could not be confirmed. Refresh before starting an edit.",
      );
      // Join read-only record recovery before disposing/rebuilding any runtime for the save.
      await this.runtime?.recover();
      this.editable();
      ensure(
        this.state.app?.version?.id === published.id &&
          this.state.app.version.hash === published.hash &&
          same(this.state.app.version.spec, published.spec),
        "definition_conflict",
        "The published version changed. Review its current preview before starting an edit.",
      );
      ensure(
        this.canEditPublishedVersion,
        "revision_conflict",
        "An existing draft or operation must be resolved before starting a published-version edit.",
      );
      this.setCandidate(published.spec);
      // Capture the displayed version and zero author revision in this exact durable envelope.
      // A concurrent server publication/draft cannot silently become this save's new base.
      await this.mutate(
        {
          op: "spec.saveDraft",
          appId: this.options.scope.appId,
          operationId: this.options.newId(),
          expectedRevision: 0,
          expectedVersionId: published.id,
          spec: published.spec,
        },
        { kind: "save", originalVersionId: published.id },
      );
    } catch (error) {
      this.fail(error);
    }
  }
  /** Uses only authoritative saved metadata, never the dirty candidate. */
  savedDraftMediaSnapshot(): SavedDraftMediaSnapshot | null {
    const app = this.state.app;
    if (!app) return null;
    return {
      appId: app.id,
      role: app.role,
      archived: app.archived,
      draft: app.draft,
      pendingGeneration:
        this.closed ||
        !this.canBuild ||
        this.state.loading ||
        this.state.busy ||
        !!this.state.pending ||
        this.state.refreshRequired ||
        this.state.conflict ||
        ["queued", "generating", "validating"].includes(
          app.generation?.status ?? "",
        ),
    };
  }
  private closeDraftMedia() {
    this.draftMedia?.dispose();
    this.draftMedia = null;
    this.draftMediaKey = null;
  }
  private reconcileDraftMedia() {
    const saved = this.savedDraftMediaSnapshot();
    const eligible =
      !!saved &&
      this.state.platform?.privateMedia === true &&
      !saved.pendingGeneration &&
      !saved.archived &&
      ["owner", "builder"].includes(saved.role) &&
      saved.draft?.publishedVersionId === null;
    const key = eligible
      ? JSON.stringify([
          saved!.appId,
          saved!.role,
          saved!.draft!.revision,
          saved!.draft!.candidateHash,
        ])
      : null;
    if (key === this.draftMediaKey && this.draftMedia?.lifetime.active) return;
    this.closeDraftMedia();
    if (!key || !saved) return;
    try {
      const context = {
        host: this.host,
        current: () => this.savedDraftMediaSnapshot(),
        onAccessFailure: (error: RuntimeError) => this.invalidateAccess(error),
      };
      this.draftMedia =
        this.options.draftMediaFactory?.(
          saved,
          this.options.transport,
          context,
        ) ??
        createDraftMediaController(
          saved,
          this.options.transport,
          this.host.lifetime,
          {
            privateMedia: true,
            newId: this.options.newId,
            current: context.current,
            onAccessFailure: context.onAccessFailure,
          },
        );
      this.draftMediaKey = key;
    } catch {
      /* Other builder features stay available when local media storage is unavailable. */
    }
  }
  private staticPreviewSource(): PrivateMediaController | null {
    if (this.draftMedia?.lifetime.active) return this.draftMedia;
    const media = (this.runtime?.adapter as MediaRuntimeAdapter | undefined)
      ?.media;
    return media?.lifetime.active ? media : null;
  }
  private closeStaticPreviewImages() {
    this.previewImageLoader?.dispose();
    this.previewImageLoader = null;
    this.previewImageSource = null;
    this.previewImageSpec = null;
    this.previewImageEpoch++;
    this.state = {
      ...this.state,
      previewStaticImageAssets: undefined,
      previewImagesLoading: false,
      previewUnavailableAssetCount: 0,
    };
  }
  private reconcileStaticPreviewImages() {
    const spec = this.previewSpec,
      source = this.staticPreviewSource();
    if (
      this.closed ||
      !this.canBuild ||
      !spec ||
      !source ||
      this.state.loading ||
      this.state.busy ||
      this.state.pending ||
      this.state.refreshRequired ||
      this.state.editorError ||
      !this.state.platform?.privateMedia
    ) {
      this.closeStaticPreviewImages();
      return;
    }
    if (
      this.previewImageSource === source &&
      this.previewImageSpec === spec &&
      this.previewImageLoader
    )
      return;
    this.closeStaticPreviewImages();
    this.previewImageSource = source;
    this.previewImageSpec = spec;
    const identity = JSON.stringify([
      this.options.scope.appId,
      this.state.app?.draft?.revision ?? null,
      this.state.app?.draft?.candidateHash ?? null,
      this.state.app?.version?.id ?? null,
      ++this.previewImageEpoch,
    ]);
    const uploaded = source.getSnapshot().asset;
    const known = new Set([
      ...(this.state.app?.draft
        ? staticPreviewImageIds(this.state.app.draft.spec)
        : []),
      ...(this.state.app?.version
        ? staticPreviewImageIds(this.state.app.version.spec)
        : []),
      ...(uploaded?.status === "ready" ? [uploaded.assetId] : []),
    ]);
    let loader: StaticPreviewImagePreloader;
    const current = () =>
      !this.closed &&
      source.lifetime.active &&
      this.previewImageSource === source &&
      this.previewImageSpec === this.previewSpec &&
      this.previewImageLoader === loader;
    loader = new StaticPreviewImagePreloader({
      lifetime: source.lifetime,
      readImage: (assetId) => {
        ensure(
          known.has(assetId),
          "media_not_ready",
          "Only saved or broker-confirmed images can be preloaded.",
        );
        return source.read(assetId, "thumbnail");
      },
      ownsUri: (uri) => source.ownsUri(uri),
      isCurrent: (requested) => requested === identity && current(),
    });
    this.previewImageLoader = loader;
    this.state = {
      ...this.state,
      previewImagesLoading: staticPreviewImageIds(spec).length > 0,
    };
    void loader.load(spec, identity).then(
      (result) => {
        if (!current() || result.closed) return;
        this.emit({
          previewStaticImageAssets: result.staticImageAssets,
          previewImagesLoading: false,
          previewUnavailableAssetCount: result.unavailableAssetIds.length,
        });
      },
      () => {
        if (current())
          this.emit({
            previewImagesLoading: false,
            previewUnavailableAssetCount: staticPreviewImageIds(spec).length,
          });
      },
    );
  }
  /** Explicitly edit one selected existing banner; the normal Save button commits it. */
  async applyDraftBannerImage(
    viewId: string,
    assetId: string,
    expected: SavedDraftMediaContext,
  ) {
    this.editable();
    const media = this.draftMedia;
    const current = () =>
      !this.closed &&
      this.draftMedia === media &&
      !!media?.lifetime.active &&
      !this.state.dirty &&
      !this.state.editorError &&
      !this.state.busy &&
      !this.state.pending &&
      !this.state.loading &&
      !this.state.conflict &&
      !this.state.refreshRequired &&
      this.canBuild;
    ensure(
      media && current(),
      "media_context_changed",
      "Save the current private candidate before choosing its image.",
    );
    const target = this.state.candidate?.views.find(
      (view) => view.id === viewId,
    );
    ensure(
      target?.type === "banner",
      "invalid_input",
      "Choose an existing banner explicitly.",
    );
    const fingerprint = JSON.stringify(target);
    const selected = await selectReadyDraftMedia(
      media,
      expected,
      () =>
        current() &&
        JSON.stringify(
          this.state.candidate?.views.find((view) => view.id === viewId),
        ) === fingerprint,
      (ready) => {
        ensure(
          ready === assetId,
          "media_context_changed",
          "The selected private image changed.",
        );
        const { id: identity, ...view } = target;
        ensure(
          identity === viewId,
          "invalid_input",
          "The selected banner changed.",
        );
        this.edit({
          type: "UpdateView",
          viewId,
          view: {
            ...view,
            options: {
              ...view.options,
              title: target.options!.title,
              imageAssetId: ready,
              imageAlt:
                view.options?.imageAlt ?? view.options?.title ?? target.label,
            },
          },
        });
      },
    );
    ensure(
      selected,
      "media_not_ready",
      "Check the private image status before choosing it.",
    );
  }
  get canBuild() {
    const app = this.state.app;
    return (
      !!app &&
      !this.state.refreshRequired &&
      !app.archived &&
      ["owner", "builder"].includes(app.role) &&
      app.capabilities.editDefinition === true
    );
  }
  private canRecover(app = this.state.app) {
    return (
      !!app &&
      ["owner", "builder"].includes(app.role) &&
      (app.archived || app.capabilities.editDefinition === true)
    );
  }
  registerEditorInputGuard = (
    guard: () => boolean,
    subscribe?: (listener: () => void) => () => void,
  ) => {
    if (this.closed || !this.host.lifetime.active) return () => {};
    this.editorInputGuards.add(guard);
    const notify = () => {
      if (!this.closed && this.host.lifetime.active) this.emit({});
    };
    const unsubscribe = subscribe?.(notify);
    notify();
    return () => {
      unsubscribe?.();
      if (this.editorInputGuards.delete(guard)) notify();
    };
  };
  private editorInputsReady() {
    try {
      return [...this.editorInputGuards].every((guard) => guard());
    } catch {
      return false;
    }
  }
  get hasRejectedEditorInput() {
    return !this.editorInputsReady();
  }
  get canLeave() {
    return (
      !this.state.dirty &&
      !this.state.editorError &&
      this.editorInputsReady() &&
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
      failure.code === "session_changed" ||
      (accessRead && failure.code === "not_found") ||
      (accessRead && error instanceof BackendError && error.status === 404)
    ) {
      this.sequence++;
      this.guidanceSequence++;
      this.stopAutosave();
      this.preparedIdea = null;
      this.composerRequest = null;
      this.conversation.clear();
      this.acceptedGenerationReceipts.clear();
      this.editorInputGuards.clear();
      this.disposeRuntime();
      this.journal.dispose();
      this.journalSuspended = true;
      this.emit({
        app: null,
        editorResetEpoch: this.state.editorResetEpoch + 1,
        preparedRequest: null,
        generationRequest: "",
        conversation: this.conversation.getSnapshot(),
        candidate: null,
        review: null,
        reviewSpec: null,
        guidance: null,
        guidanceLoading: false,
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
  private install(
    app: FullManifest,
    acceptCandidate = false,
    createRuntime = true,
  ) {
    this.active();
    const prior = this.state.app;
    const build =
      !app.archived &&
      ["owner", "builder"].includes(app.role) &&
      app.capabilities.editDefinition === true;
    if (!build) {
      this.editorInputGuards.clear();
      this.preparedIdea = null;
      this.composerRequest = null;
      this.conversation.clear();
      this.acceptedGenerationReceipts.clear();
    } else this.conversation.observe(app.generation);
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
    const localEditorChanges =
      this.state.dirty ||
      !!this.state.editorError ||
      this.hasRejectedEditorInput;
    const staleDirty =
      build &&
      localEditorChanges &&
      !acceptCandidate &&
      prior?.draft?.revision !== app.draft?.revision;
    const candidate = build
      ? acceptCandidate || !localEditorChanges
        ? (app.draft?.spec ?? null)
        : this.state.candidate
      : null;
    const existing = this.runtime?.adapter;
    const changedRuntime =
      existing?.versionId !== app.version?.id ||
      existing?.role !== app.role ||
      existing?.archived !== app.archived;
    const preserveRuntime =
      !!this.runtime &&
      !this.runtime.canLeave &&
      existing?.role === app.role &&
      existing?.archived === app.archived;
    if (!app.version) {
      this.disposeRuntime();
    } else if (!this.runtime || (changedRuntime && !preserveRuntime)) {
      this.disposeRuntime();
      if (createRuntime) {
        const adapter =
          this.options.adapterFactory?.(app, this.options.transport, {
            host: this.host,
            platform: this.state.platform,
          }) ?? new FunctionRuntimeAdapter(app, this.options.transport);
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
        this.applyLiveActivity();
      }
    }
    const candidateChanged =
      !same(this.state.candidate, candidate) ||
      prior?.draft?.revision !== app.draft?.revision ||
      prior?.version?.id !== app.version?.id;
    const resetEditor =
      !build ||
      (!this.state.dirty &&
        !this.state.editorError &&
        !this.hasRejectedEditorInput &&
        !same(this.state.candidate, candidate));
    const clarificationChanged = candidateChanged || !build;
    if (clarificationChanged) this.guidanceSequence++;
    this.emit({
      app,
      candidate,
      conversation: this.conversation.getSnapshot(),
      editorResetEpoch: this.state.editorResetEpoch + (resetEditor ? 1 : 0),
      preparedRequest: build ? this.preparedIdea : null,
      generationRequest: build
        ? (this.composerRequest ??
          this.preparedIdea ??
          app.generation?.requestText ??
          "")
        : "",
      editorError: build ? this.state.editorError : null,
      dirty: build && this.state.dirty && !acceptCandidate,
      conflict: staleDirty || (!acceptCandidate && this.state.conflict),
      review: candidateChanged ? null : this.state.review,
      reviewSpec: candidateChanged ? null : this.state.reviewSpec,
      guidance: clarificationChanged ? null : this.state.guidance,
      guidanceLoading: clarificationChanged
        ? false
        : this.state.guidanceLoading,
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
      // Apply current authority before any optional capability request. Delay
      // constructing a new runtime until its operational features are known.
      this.install(app, false, false);
      try {
        const capabilities = platformCapabilities(
          await this.options.transport({ op: "spec.capabilities" }),
        );
        if (this.closed || sequence !== this.sequence) return;
        this.emit({ platform: capabilities });
      } catch (error) {
        if (this.closed || sequence !== this.sequence) return;
        this.fail(error);
        if (!this.state.app) return;
        this.emit({ platform: null });
      }
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
      this.emit({ ...this.reconcileConversation(), loading: false });
    } catch (error) {
      if (sequence === this.sequence) this.fail(error, false, true);
    }
  }
  /** Server job metadata proves only the latest restored request, never an invented full conversation. */
  private reconcileConversation(): Partial<FullAppState> {
    const app = this.state.app;
    if (!app || !this.canBuild)
      return { conversation: this.conversation.getSnapshot() };
    const retained = this.journal.pending?.request;
    if (retained?.op === "spec.generate") {
      if (this.composerRequest === null && typeof retained.request === "string")
        this.composerRequest = retained.request;
    } else {
      for (const job of this.acceptedGenerationReceipts.values()) {
        this.conversation.accept(job, "accepted");
        if (this.composerRequest === job.requestText) this.composerRequest = "";
        if (this.preparedIdea === job.requestText) this.preparedIdea = null;
      }
      this.acceptedGenerationReceipts.clear();
      if (app.generation) {
        this.conversation.accept(app.generation, "restored");
        if (this.composerRequest === null) this.composerRequest = "";
      }
    }
    this.conversation.observe(app.generation);
    return {
      conversation: this.conversation.getSnapshot(),
      generationRequest: this.composerRequest ?? this.preparedIdea ?? "",
      preparedRequest: this.preparedIdea,
    };
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
    this.guidanceSequence++;
    this.emit({
      candidate: this.state.app?.draft?.spec ?? null,
      editorResetEpoch: this.state.editorResetEpoch + 1,
      dirty: false,
      editorError: null,
      conflict: false,
      review: null,
      reviewSpec: null,
      guidance: null,
      guidanceLoading: false,
      error: null,
    });
  }
  setCandidate(input: unknown, debounce = false, preserveInputs = false) {
    this.editable();
    this.stopAutosave();
    try {
      const candidate = freezeValidated(decodeAppSpec(input));
      this.guidanceSequence++;
      this.emit({
        candidate,
        editorResetEpoch:
          this.state.editorResetEpoch + (preserveInputs ? 0 : 1),
        dirty: !same(candidate, this.state.app?.draft?.spec),
        editorError: null,
        review: null,
        reviewSpec: null,
        guidance: null,
        guidanceLoading: false,
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
    try {
      this.editable();
      this.stopAutosave();
      ensure(
        this.state.candidate,
        "invalid_input",
        "Choose a template or create a candidate first.",
      );
      this.setCandidate(
        applySemanticEdit(this.state.candidate, edit, this.options.newId),
        debounce,
        true,
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
    if (request.op === "spec.generate") {
      const job = decodeGeneration(result.generation);
      ensure(
        job &&
          app.generation &&
          same(job, app.generation) &&
          job.requestText === request.request &&
          job.mutation === Number(request.expectedRevision) + 1,
        "invalid_response",
        "The generation reply did not confirm the original request.",
      );
      acceptedRequest(job, "accepted");
    }
    if (request.op === "spec.generate" || request.op === "spec.keepPrevious")
      ensure(
        result.generation !== undefined,
        "invalid_response",
        "The generation result could not be confirmed.",
      );
    return app;
  }
  private async transmit() {
    const command = this.journal.pending;
    this.emit({
      busy: true,
      pending: this.journal.pending,
      pendingStatus: "sending",
      error: null,
    });
    try {
      const acknowledged = await this.journal.send(
        this.options.transport,
        (value, command) => this.decodeMutation(value, command),
      );
      this.active();
      if (command?.request.op === "spec.generate" && acknowledged.generation)
        this.acceptedGenerationReceipts.set(
          acknowledged.generation.id,
          acknowledged.generation,
        );
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
      guidanceLoading: false,
    });
    try {
      await this.journal.prepare(request, context);
      this.active();
      await this.transmit();
    } catch (error) {
      this.fail(error, true);
    }
  }
  save(): Promise<void> {
    if (this.saveTask) return this.saveTask;
    if (this.state.busy) return Promise.resolve();
    const task = Promise.resolve().then(() => this.performSave());
    this.saveTask = task;
    void task.then(
      () => {
        if (this.saveTask === task) this.saveTask = null;
      },
      () => {
        if (this.saveTask === task) this.saveTask = null;
      },
    );
    return task;
  }
  private async performSave() {
    if (this.state.busy) return;
    try {
      this.editable();
      ensure(
        !this.state.editorError && this.editorInputsReady(),
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
    this.stopAutosave();
    if (this.saveTask) await this.saveTask;
    else {
      if (this.state.busy || !this.editorInputsReady()) return false;
      await this.save();
    }
    return (
      !this.closed &&
      this.host.lifetime.active &&
      this.canBuild &&
      !this.state.loading &&
      !this.state.refreshRequired &&
      !this.state.dirty &&
      !this.state.editorError &&
      this.editorInputsReady() &&
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
      ensure(
        !this.state.editorError && this.editorInputsReady(),
        "invalid_edit",
        "Fix or discard the invalid local edit before publishing.",
      );
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
      this.composerRequest = request;
      this.emit({ generationRequest: request });
      this.clearPreparedIdea();
      await this.mutate(
        {
          op: "spec.generate",
          appId: this.options.scope.appId,
          operationId: this.options.newId(),
          expectedRevision: this.state.app!.draft?.revision ?? 0,
          expectedVersionId: this.state.app!.version?.id ?? null,
          request,
          startFromScratch:
            startFromScratch ||
            (!this.state.candidate && !this.state.app!.version),
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
      this.state.editorError ||
      this.hasRejectedEditorInput ||
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
      // A poll can finish after a local edit. Current authority still applies,
      // while unsent semantic/raw input keeps its candidate and conflict state.
      this.install(app);
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
  /** Memory-only handoff from an explicitly created shell; never a generation command. */
  prepareIdea(request: string) {
    this.active();
    ensure(
      request.trim().length > 0 &&
        new TextEncoder().encode(request).byteLength <= 16384,
      "invalid_input",
      "The prepared idea must fit 16 KiB.",
    );
    this.preparedIdea = request;
    if (this.state.app && !this.canBuild) {
      this.preparedIdea = null;
      return false;
    }
    if (this.canBuild)
      this.emit({
        preparedRequest: request,
        generationRequest: this.composerRequest ?? request,
      });
    return true;
  }
  setGenerationRequest(request: string) {
    this.active();
    ensure(this.canBuild, "forbidden", "Current builder access is required.");
    this.composerRequest = request;
    this.preparedIdea = null;
    this.guidanceSequence++;
    this.emit({
      generationRequest: request,
      preparedRequest: null,
      guidance: null,
      guidanceLoading: false,
    });
  }
  clearPreparedIdea() {
    this.preparedIdea = null;
    this.emit({ preparedRequest: null });
  }
  async requestGuidance(request: string, startFromScratch = false) {
    const sequence = ++this.guidanceSequence;
    try {
      this.editable();
      const mode =
        this.state.candidate && !startFromScratch ? "edit" : "create";
      this.emit({ error: null, guidance: null, guidanceLoading: true });
      const assessment = await assessClarification({
        request,
        mode,
        providerEnabled: this.state.platform?.guidance ?? null,
        askProvider: () =>
          this.options.transport({
            op: "spec.guidance",
            workspaceId: this.state.app!.workspaceId,
            appId: this.options.scope.appId,
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
  useBuiltInGuidance() {
    if (!this.state.guidance || !this.canBuild) return;
    const { requestText, mode } = this.state.guidance;
    this.guidanceSequence++;
    this.emit({
      guidance: builtInClarification(requestText, mode, "optional"),
      guidanceLoading: false,
    });
  }
  invalidateGuidance(keepVisible = false) {
    this.guidanceSequence++;
    this.emit({
      guidanceLoading: false,
      ...(!keepVisible ? { guidance: null } : {}),
    });
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
  /** A trusted watch denial hides private state even while forms are dirty. */
  invalidateAccess(error: unknown) {
    if (!this.closed) this.fail(error, false, true);
  }
  async observeInvalidation(stamp: InvalidationStamp) {
    if (this.closed) return;
    ensure(
      stamp.appId === this.options.scope.appId,
      "invalid_response",
      "The update belongs to a different app.",
    );
    const current = this.state.app;
    if (
      current &&
      (current.role !== stamp.role || current.archived !== stamp.archived)
    ) {
      this.invalidateAccess(
        new RuntimeError(
          "forbidden",
          "Your app access changed. Current access is being checked.",
        ),
      );
    }
    await this.load();
  }
  private applyLiveActivity() {
    const active = !this.closed && [...this.liveLeases.values()].some(Boolean);
    this.device?.setActive(active);
    this.runtime?.adapter.setActive?.(active);
  }
  /** Focus leases prevent a retained background route from keeping devices or polling active. */
  acquireLiveLease(active: boolean): () => void {
    this.active();
    const token = Symbol("focused-live-route");
    this.liveLeases.set(token, active);
    this.applyLiveActivity();
    return () => {
      if (!this.liveLeases.delete(token) || this.closed) return;
      this.applyLiveActivity();
    };
  }
  dispose() {
    if (this.closed) return;
    this.closed = true;
    this.preparedIdea = null;
    this.composerRequest = null;
    this.conversation.clear();
    this.acceptedGenerationReceipts.clear();
    this.editorInputGuards.clear();
    this.liveLeases.clear();
    this.sequence++;
    this.guidanceSequence++;
    this.stopAutosave();
    this.closeStaticPreviewImages();
    this.closeDraftMedia();
    this.disposeRuntime();
    this.journal.dispose();
    this.host.lifetime.dispose();
    this.state = {
      ...this.state,
      app: null,
      preparedRequest: null,
      generationRequest: "",
      conversation: this.conversation.getSnapshot(),
      candidate: null,
      editorError: null,
      review: null,
      reviewSpec: null,
      pending: null,
      guidance: null,
      guidanceLoading: false,
    };
    this.listeners.clear();
  }
}
