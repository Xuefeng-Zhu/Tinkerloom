import type { HostLifetime } from "../host/scope";
import type {
  ImageAsset,
  PickedImage,
  RuntimeTransport,
} from "../runtime/types";
import { RuntimeError, runtimeError } from "../runtime/errors";
import { getCollection } from "../spec/bindings";
import { canonicalJson } from "../spec/schema";
import { freezeValidated } from "../runtime/immutable";
import { CHUNK_BYTES, ORIGINAL_BYTES } from "./types";
import type {
  MediaAsset,
  MediaAuthority,
  MediaPorts,
  MediaUploadContext,
  MediaVariant,
  UploadSnapshot,
  ImageResource,
} from "./types";
import {
  aligned,
  asset,
  context,
  counter,
  encode64,
  fail,
  hash,
  id,
  keys,
  object,
  readChunk,
  sniff,
} from "./codec";
import { MediaRecovery } from "./recovery";
import type { StoredUpload } from "./recovery";

export interface PrivateMediaOptions {
  privateMedia: boolean;
  newId(): string;
  recovery: MediaRecovery;
  ports: MediaPorts;
  captureUploadContext?(): MediaUploadContext;
  isCurrent?(): boolean;
  onAccessFailure?(error: RuntimeError): void;
  readVariant?: MediaVariant;
  maxCacheBytes?: number;
  pollAttempts?: number;
  requestTimeoutMs?: number;
  readConcurrency?: number;
  sleep?(milliseconds: number): Promise<void>;
}
const empty = (): UploadSnapshot => ({
  initialized: false,
  busy: false,
  stage: null,
  asset: null,
  uploadedBytes: 0,
  inputBytes: 0,
  pending: null,
  uncertain: false,
  error: null,
  accessDenied: false,
});
interface CachedImage {
  fingerprint: string;
  resource: ImageResource;
  asset: ImageAsset;
  bytes: number;
}

/** One account/app/version owner. Opening recovery never dispatches a mutation. */
export class PrivateMediaController {
  private state = empty();
  private readonly authority: readonly [
    string,
    string | null,
    string,
    boolean,
    number | null,
    string | null,
  ];
  private listeners = new Set<() => void>();
  private disposed = false;
  private generation = 0;
  private saved: StoredUpload | null = null;
  private initialization: Promise<void> | null = null;
  private cache = new Map<string, CachedImage>();
  private reads = new Map<string, Promise<ImageAsset>>();
  private removeLifetime: () => void;
  private cancellations = new Set<() => void>();
  private readSlots = 0;
  private readQueue: (() => void)[] = [];
  constructor(
    readonly base: MediaAuthority,
    private transport: RuntimeTransport,
    readonly lifetime: HostLifetime,
    private options: PrivateMediaOptions,
  ) {
    if (
      base.preview ||
      (base.versionId === null && !base.draft) ||
      !options.privateMedia ||
      lifetime.scope.appId !== base.appId ||
      options.recovery.storage.lifetime !== lifetime
    )
      fail("media_scope_mismatch");
    if (options.maxCacheBytes !== undefined)
      counter(options.maxCacheBytes, 64 * 1024 * 1024, ORIGINAL_BYTES);
    if (options.requestTimeoutMs !== undefined)
      counter(options.requestTimeoutMs, 60_000, 1);
    if (options.readConcurrency !== undefined)
      counter(options.readConcurrency, 4, 1);
    this.authority = [
      base.appId,
      base.versionId,
      base.role,
      base.archived,
      base.draft?.revision ?? null,
      base.draft?.candidateHash ?? null,
    ];
    this.removeLifetime = lifetime.onDispose(() => this.dispose());
  }
  getSnapshot = () => this.state;
  ownsUri(uri: string): boolean {
    try {
      this.guard();
    } catch {
      return false;
    }
    return [...this.cache.values()].some((value) => value.resource.uri === uri);
  }
  currentContext(): MediaUploadContext | null {
    return this.saved?.context ?? null;
  }
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  private emit(patch: Partial<UploadSnapshot>) {
    if (this.disposed) return;
    this.state = { ...this.state, ...patch };
    for (const listener of this.listeners) listener();
  }
  private guard(generation = this.generation) {
    if (
      this.disposed ||
      !this.lifetime.active ||
      generation !== this.generation
    )
      fail("disposed");
    if (
      this.base.appId !== this.authority[0] ||
      this.base.versionId !== this.authority[1] ||
      this.base.role !== this.authority[2] ||
      this.base.archived !== this.authority[3] ||
      (this.base.draft?.revision ?? null) !== this.authority[4] ||
      (this.base.draft?.candidateHash ?? null) !== this.authority[5] ||
      (this.options.isCurrent && !this.options.isCurrent())
    ) {
      this.invalidate();
      fail("media_scope_changed");
    }
  }
  private showSaved(assetInfo?: MediaAsset) {
    const value = this.saved,
      pending = value?.pending;
    this.emit({
      stage: value?.phase ?? null,
      inputBytes: value?.begin.byteLength ?? 0,
      uploadedBytes:
        assetInfo && assetInfo.status !== "ready"
          ? assetInfo.uploadedBytes
          : Math.min(
              value?.begin.byteLength ?? 0,
              (value?.nextChunk ?? 0) * CHUNK_BYTES,
            ),
      pending: pending
        ? {
            operation: pending.op,
            ...("operationId" in pending
              ? { operationId: pending.operationId as string }
              : {}),
            ...("offset" in pending
              ? { offset: pending.offset as number }
              : {}),
          }
        : null,
      uncertain: value?.outcome === "uncertain" || value?.outcome === "sending",
      ...(assetInfo ? { asset: assetInfo } : {}),
    });
  }
  private safe(error: unknown, mutation = false): RuntimeError {
    const normalized = runtimeError(error, mutation),
      uncertain =
        normalized.uncertain ||
        (mutation &&
          [
            "transaction_conflict",
            "media_busy",
            "media_state_conflict",
            "disposed",
            "media_scope_changed",
            "media_request_timeout",
            "media_invalid_response",
          ].includes(normalized.code));
    const code = /^[a-z0-9_]{1,64}$/.test(normalized.code)
      ? normalized.code
      : "media_failed";
    return new RuntimeError(
      code,
      uncertain
        ? "The image request could not be confirmed. Retry the retained upload."
        : code === "media_processing"
          ? "The private image is processing. Check its status before attaching it."
          : code === "media_reselect_required"
            ? "Local preparation was interrupted. Reselect the same image or discard this local upload."
            : code === "media_too_large"
              ? "Choose a JPEG, PNG or WebP image no larger than 5 MiB."
              : "The private image request is unavailable. Your other values are retained.",
      uncertain,
    );
  }
  private observeFailure(error: RuntimeError) {
    if (this.disposed || !this.lifetime.active) return;
    if (
      [
        "forbidden",
        "unauthenticated",
        "not_found",
        "user_unauthorized",
        "user_jwt_invalid",
        "session_expired",
        "authorization_failure",
      ].includes(error.code)
    ) {
      if (!this.state.accessDenied) {
        this.invalidate();
        this.emit({ accessDenied: true });
        this.options.onAccessFailure?.(error);
      }
    }
    this.emit({ error: error.message });
  }
  private async rpc(request: Record<string, unknown>): Promise<unknown> {
    this.guard();
    const generation = this.generation;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let cancel: (() => void) | undefined;
    try {
      const result = await Promise.race([
        Promise.resolve().then(() => {
          this.guard(generation);
          return this.transport(request);
        }),
        new Promise<never>((_, reject) => {
          cancel = () =>
            reject(
              new RuntimeError("disposed", "The image scope is closed.", true),
            );
          this.cancellations.add(cancel);
          timer = setTimeout(
            () =>
              reject(
                new RuntimeError(
                  "media_request_timeout",
                  "The image request timed out.",
                  true,
                ),
              ),
            this.options.requestTimeoutMs ?? 30_000,
          );
        }),
      ]);
      this.guard(generation);
      return result;
    } finally {
      if (timer) clearTimeout(timer);
      if (cancel) this.cancellations.delete(cancel);
    }
  }
  private async readSlot<T>(
    work: () => Promise<T>,
    generation: number,
  ): Promise<T> {
    if (this.readSlots >= (this.options.readConcurrency ?? 2)) {
      if (this.readQueue.length >= 128) fail("media_busy");
      await new Promise<void>((resolve) => this.readQueue.push(resolve));
    } else this.readSlots++;
    try {
      this.guard(generation);
      return await work();
    } finally {
      const next = this.readQueue.shift();
      if (next) next();
      else this.readSlots--;
    }
  }
  async recover(): Promise<void> {
    this.guard();
    if (this.state.initialized) return;
    if (this.initialization) return this.initialization;
    const generation = this.generation;
    this.initialization = (async () => {
      try {
        const saved = await this.options.recovery.read();
        this.guard(generation);
        if (saved && saved.appId !== this.base.appId)
          fail("media_saved_invalid");
        this.saved = saved;
        this.emit({ initialized: true, error: null });
        this.showSaved();
      } catch (error) {
        const safe = this.safe(error);
        this.observeFailure(safe);
        throw safe;
      }
    })().finally(() => {
      this.initialization = null;
    });
    return this.initialization;
  }
  private validateContext(value: MediaUploadContext) {
    this.guard();
    if (
      this.base.archived ||
      this.base.role === "viewer" ||
      this.state.accessDenied
    )
      fail("forbidden");
    if ("draftRevision" in value) {
      if (this.base.role !== "owner" && this.base.role !== "builder")
        fail("forbidden");
      if (!this.base.draft) fail("media_draft_authority_required");
      if (value.draftRevision !== this.base.draft.revision)
        fail("media_context_changed");
      return;
    }
    if (this.base.draft) fail("media_context_changed");
    if (value.versionId !== this.base.versionId) fail("media_context_changed");
    const action = this.base.spec.actions.find((a) => a.id === value.actionId);
    if (
      !action ||
      !["records.create.v1", "records.patch.v1"].includes(action.capability)
    )
      fail("invalid_input");
    if (
      getCollection(this.base.spec, action.collectionId).fields.find(
        (f) => f.id === value.fieldId,
      )?.type !== "image"
    )
      fail("invalid_input");
    if (
      (action.capability === "records.patch.v1") !==
      Object.hasOwn(value, "targetRecordId")
    )
      fail("invalid_input");
    // Member policies remain authoritative in the existing runtime permission layer.
    if (!this.base.permits?.(action)) fail("forbidden");
  }
  private validateSavedContext(value: StoredUpload) {
    this.validateContext(value.context);
    if (
      this.base.draft &&
      value.candidateHash !== this.base.draft.candidateHash
    )
      fail("media_context_changed");
  }
  private async save(value: StoredUpload) {
    this.guard();
    try {
      const next = await this.options.recovery.save(value);
      this.guard();
      this.saved = next;
      this.showSaved();
      return next;
    } catch (error) {
      this.emit({ initialized: false });
      throw error;
    }
  }
  private async verifyOriginal(value: StoredUpload): Promise<void> {
    const bytes = new Uint8Array(value.begin.byteLength);
    try {
      for (let index = 0; index < value.chunkHashes.length; index++) {
        this.guard();
        const chunk = await this.options.recovery.chunk(value, index);
        try {
          this.guard();
          if (
            (await this.options.ports.sha256(chunk)) !==
            value.chunkHashes[index]
          )
            fail("media_saved_invalid");
          bytes.set(chunk, index * CHUNK_BYTES);
        } finally {
          chunk.fill(0);
        }
      }
      if (
        (await this.options.ports.sha256(bytes)) !== value.begin.sha256 ||
        sniff(bytes) !== value.begin.contentType
      )
        fail("media_saved_invalid");
    } finally {
      bytes.fill(0);
    }
  }
  async pickImage(): Promise<PickedImage | null> {
    this.guard();
    if (
      !this.state.initialized ||
      this.state.busy ||
      this.state.accessDenied ||
      this.base.archived ||
      this.base.role === "viewer"
    )
      fail("media_recovery_required");
    const generation = this.generation;
    this.emit({ busy: true, error: null });
    let picked: PickedImage | null = null;
    try {
      picked = await this.options.ports.pick();
      this.guard(generation);
      if (
        picked &&
        (!(picked.bytes instanceof Uint8Array) ||
          picked.bytes.length < 1 ||
          picked.bytes.length > ORIGINAL_BYTES ||
          sniff(picked.bytes) !== picked.mimeType)
      )
        fail("media_too_large");
      return picked;
    } catch (error) {
      picked?.bytes.fill(0);
      const safe = this.safe(error);
      this.observeFailure(safe);
      throw safe;
    } finally {
      if (!this.disposed) this.emit({ busy: false });
    }
  }
  async upload(value: MediaUploadContext, image: PickedImage): Promise<string> {
    this.guard();
    if (this.state.busy) fail("media_pending");
    this.emit({ busy: true, error: null });
    const bytes =
      image.bytes instanceof Uint8Array
        ? Uint8Array.from(image.bytes)
        : new Uint8Array();
    try {
      const intent = freezeValidated(context(value));
      await this.recover();
      this.guard();
      this.validateContext(intent);
      if (bytes.length < 1 || bytes.length > ORIGINAL_BYTES)
        fail("media_too_large");
      if (sniff(bytes) !== image.mimeType) fail("media_unsupported");
      const digest = hash(await this.options.ports.sha256(bytes));
      this.guard();
      if (this.saved?.phase === "ready") {
        await this.options.recovery.clear(this.saved);
        this.guard();
        this.saved = null;
        this.showSaved();
      }
      if (this.saved) {
        if (
          canonicalJson(this.saved.context) !== canonicalJson(intent) ||
          this.saved.begin.sha256 !== digest ||
          this.saved.begin.byteLength !== bytes.length ||
          this.saved.begin.contentType !== image.mimeType
        )
          fail("media_pending");
        // Reselecting identical bytes is an explicit retry; changed bytes never
        // get a new operation while the original upload is unresolved.
        if (this.saved.phase === "preparing") await this.prepareChunks(bytes);
        else if (this.saved.outcome === "failed") fail("media_pending");
      } else {
        const chunkHashes: string[] = [];
        for (let offset = 0; offset < bytes.length; offset += CHUNK_BYTES)
          chunkHashes.push(
            hash(
              await this.options.ports.sha256(
                bytes.subarray(offset, offset + CHUNK_BYTES),
              ),
            ),
          );
        this.guard();
        const begin = {
          op: "spec.media.begin" as const,
          appId: this.base.appId,
          operationId: id(this.options.newId()),
          byteLength: bytes.length,
          contentType: image.mimeType,
          sha256: digest,
          ...intent,
        };
        const manifest: StoredUpload = {
          format: 1,
          revision: 0,
          localId: id(this.options.newId()),
          appId: this.base.appId,
          versionId: this.base.versionId,
          ...(this.base.draft
            ? { candidateHash: this.base.draft.candidateHash }
            : {}),
          context: intent,
          begin,
          completeOperationId: id(this.options.newId()),
          chunkHashes,
          phase: "preparing",
          assetId: null,
          nextChunk: 0,
          pending: null,
          outcome: "none",
        };
        try {
          this.saved = await this.options.recovery.reserve(manifest);
        } catch (error) {
          this.emit({ initialized: false });
          throw error;
        }
        this.guard();
        this.showSaved();
        await this.prepareChunks(bytes);
      }
      return await this.advance(true);
    } catch (error) {
      const safe = this.safe(error);
      this.observeFailure(safe);
      throw safe;
    } finally {
      bytes.fill(0);
      this.emit({ busy: false });
    }
  }
  private async prepareChunks(bytes: Uint8Array) {
    const value = this.saved!;
    for (let index = 0; index < value.chunkHashes.length; index++) {
      this.guard();
      await this.options.recovery.putChunk(
        value,
        index,
        bytes.subarray(index * CHUNK_BYTES, (index + 1) * CHUNK_BYTES),
      );
    }
    await this.save({
      ...value,
      phase: "begin",
      pending: value.begin,
      outcome: "sending",
    });
  }
  private async sendPending() {
    const current = this.saved!,
      pending = current.pending;
    if (!pending) return;
    this.guard();
    let response: unknown;
    try {
      response = await this.rpc(pending);
      this.guard();
      const row = object(response);
      if (pending.op === "spec.media.begin") {
        keys(row, ["asset", "chunkBytes", "expiresAt"]);
        const info = asset(row.asset);
        if (
          info.status !== "pending" ||
          info.inputBytes !== current.begin.byteLength ||
          info.uploadedBytes !== 0 ||
          row.chunkBytes !== CHUNK_BYTES ||
          typeof row.expiresAt !== "string" ||
          !Number.isFinite(Date.parse(row.expiresAt))
        )
          fail();
        await this.save({
          ...current,
          assetId: info.assetId,
          phase: "chunks",
          pending: null,
          outcome: "none",
        });
        this.showSaved(info);
      } else if (pending.op === "spec.media.chunk") {
        keys(row, ["assetId", "uploadedBytes"]);
        const bytes = counter(row.uploadedBytes, current.begin.byteLength);
        const end =
          pending.offset +
          Math.min(CHUNK_BYTES, current.begin.byteLength - pending.offset);
        if (
          row.assetId !== current.assetId ||
          bytes < end ||
          !aligned(bytes, current.begin.byteLength)
        )
          fail();
        // Even if the ACK reports later committed chunks, resend each retained
        // subsequent chunk so the broker validates all duplicate hashes.
        await this.save({
          ...current,
          nextChunk: pending.offset / CHUNK_BYTES + 1,
          pending: null,
          outcome: "none",
        });
      } else {
        keys(row, ["asset"]);
        const info = asset(row.asset, current.assetId!);
        if (
          info.status !== "queued" &&
          info.status !== "processing" &&
          info.status !== "ready"
        )
          fail();
        await this.save({
          ...current,
          phase: info.status === "ready" ? "ready" : "processing",
          pending: null,
          outcome: "none",
        });
        this.showSaved(info);
      }
    } catch (error) {
      const safe = this.safe(error, true);
      if (!this.disposed && this.lifetime.active) {
        try {
          await this.save({
            ...current,
            phase: safe.uncertain ? current.phase : "failed",
            outcome: safe.uncertain ? "uncertain" : "failed",
          });
        } catch {
          /* Retain the older exact request when its local update is uncertain. */
        }
      }
      this.observeFailure(safe);
      throw safe;
    }
  }
  private async advance(replayFirst = false): Promise<string> {
    this.guard();
    await this.verifyOriginal(this.saved!);
    if (replayFirst && this.saved!.pending) await this.sendPending();
    while (this.saved && this.saved.phase !== "ready") {
      this.guard();
      const value = this.saved;
      if (value.pending) {
        await this.sendPending();
        continue;
      }
      if (value.phase === "preparing") fail("media_reselect_required");
      if (value.phase === "failed") fail("media_pending");
      if (value.phase === "processing") break;
      this.validateSavedContext(value);
      if (value.nextChunk < value.chunkHashes.length) {
        const chunk = await this.options.recovery.chunk(value, value.nextChunk);
        this.guard();
        const pending = {
          op: "spec.media.chunk" as const,
          appId: this.base.appId,
          assetId: value.assetId!,
          offset: value.nextChunk * CHUNK_BYTES,
          sha256: value.chunkHashes[value.nextChunk],
          dataBase64: encode64(chunk),
        };
        chunk.fill(0);
        await this.save({
          ...value,
          phase: "chunks",
          pending,
          outcome: "sending",
        });
      } else {
        await this.save({
          ...value,
          phase: "complete",
          pending: {
            op: "spec.media.complete",
            appId: this.base.appId,
            assetId: value.assetId!,
            operationId: value.completeOperationId,
          },
          outcome: "sending",
        });
      }
    }
    const attempts = Math.max(1, Math.min(this.options.pollAttempts ?? 1, 10));
    for (let i = 0; i < attempts; i++) {
      const ready = await this.pollInternal();
      if (ready) return ready;
      if (i < attempts - 1) {
        await (
          this.options.sleep ??
          ((ms) => new Promise((resolve) => setTimeout(resolve, ms)))
        )(1000);
        this.guard();
      }
    }
    return fail("media_processing");
  }
  async retry(): Promise<string> {
    this.guard();
    if (this.state.busy) fail("media_pending");
    this.emit({ busy: true, error: null });
    try {
      await this.recover();
      if (!this.saved || this.saved.outcome === "failed") fail("media_pending");
      return await this.advance(true);
    } catch (error) {
      const safe = this.safe(error);
      this.observeFailure(safe);
      throw safe;
    } finally {
      this.emit({ busy: false });
    }
  }
  private async status(assetId: string): Promise<MediaAsset> {
    const generation = this.generation;
    const result = object(
      await this.rpc({
        op: "spec.media.status",
        appId: this.base.appId,
        assetId,
      }),
    );
    this.guard(generation);
    keys(result, ["asset"]);
    return asset(result.asset, assetId);
  }
  private async pollInternal(): Promise<string | null> {
    if (!this.saved?.assetId) fail("media_pending");
    const value = this.saved,
      info = await this.status(value.assetId!);
    this.showSaved(info);
    if (info.status === "failed") {
      await this.save({
        ...value,
        phase: "failed",
        pending: null,
        outcome: "failed",
      });
      return fail("media_failed");
    }
    if (info.status !== "ready") return null;
    if (value.pending) return null; // Status never acknowledges an unknown mutation.
    this.validateSavedContext(value);
    if (value.phase !== "ready")
      await this.save({
        ...value,
        phase: "ready",
        pending: null,
        outcome: "none",
      });
    this.showSaved(info);
    return info.assetId;
  }
  async poll(): Promise<string | null> {
    this.guard();
    if (this.state.busy) fail("media_pending");
    this.emit({ busy: true, error: null });
    try {
      await this.recover();
      return await this.pollInternal();
    } catch (error) {
      const safe = this.safe(error);
      this.observeFailure(safe);
      throw safe;
    } finally {
      this.emit({ busy: false });
    }
  }
  async discard(): Promise<void> {
    this.guard();
    if (this.state.busy) fail("media_pending");
    this.emit({ busy: true, error: null });
    try {
      await this.recover();
      if (this.saved) await this.options.recovery.clear(this.saved);
      this.guard();
      this.saved = null;
      this.emit({ ...empty(), initialized: true });
    } catch (error) {
      const safe = this.safe(error);
      this.observeFailure(safe);
      throw safe;
    } finally {
      this.emit({ busy: false });
    }
  }
  read(
    assetId: string,
    variant: MediaVariant = this.options.readVariant ?? "thumbnail",
  ): Promise<ImageAsset> {
    this.guard();
    id(assetId);
    const key = `${variant}:${assetId}`;
    const pending = this.reads.get(key);
    if (pending) return pending;
    const generation = this.generation;
    const task = this.readSlot(
      () => this.readInternal(assetId, variant, key),
      generation,
    )
      .catch((error) => {
        const safe = this.safe(error);
        if (generation === this.generation) this.observeFailure(safe);
        throw safe;
      })
      .finally(() => {
        if (this.reads.get(key) === task) this.reads.delete(key);
      });
    this.reads.set(key, task);
    return task;
  }
  private async readInternal(
    assetId: string,
    variant: MediaVariant,
    key: string,
  ): Promise<ImageAsset> {
    const generation = this.generation,
      info = await this.status(assetId);
    if (info.status !== "ready") return fail("media_not_ready");
    const fingerprint = JSON.stringify([
      this.base.versionId,
      info.sha256,
      info.contentType,
      info.width,
      info.height,
    ]);
    const cached = this.cache.get(key);
    if (cached?.fingerprint === fingerprint) {
      this.cache.delete(key);
      this.cache.set(key, cached);
      return { ...cached.asset };
    }
    if (cached) {
      cached.resource.dispose();
      this.cache.delete(key);
    }
    let bytes: Uint8Array | null = null,
      first: ReturnType<typeof readChunk> | null = null,
      offset = 0;
    try {
      do {
        this.guard(generation);
        const chunk = readChunk(
          await this.rpc({
            op: "spec.media.read",
            appId: this.base.appId,
            assetId,
            variant,
            offset,
          }),
          assetId,
          variant,
          offset,
        );
        try {
          this.guard(generation);
          if (
            (await this.options.ports.sha256(chunk.bytes)) !== chunk.chunkSha256
          )
            fail("media_integrity");
          this.guard(generation);
          if (!first) {
            first = chunk;
            if (
              chunk.contentType !== info.contentType ||
              chunk.width !== info.width ||
              chunk.height !== info.height ||
              (variant === "display" &&
                (chunk.sha256 !== info.sha256 ||
                  chunk.byteLength !== info.byteLength))
            )
              fail();
            bytes = new Uint8Array(chunk.byteLength);
          }
          if (
            chunk.byteLength !== first.byteLength ||
            chunk.sha256 !== first.sha256 ||
            chunk.contentType !== first.contentType ||
            chunk.width !== first.width ||
            chunk.height !== first.height
          )
            fail();
          bytes!.set(chunk.bytes, offset);
        } finally {
          chunk.bytes.fill(0);
        }
        if (chunk.nextOffset === null) break;
        offset = chunk.nextOffset;
      } while (true);
      if (
        !first ||
        !bytes ||
        (await this.options.ports.sha256(bytes)) !== first.sha256 ||
        sniff(bytes) !== first.contentType
      )
        fail("media_integrity");
      this.guard(generation);
      const resource = await this.options.ports.image(bytes, first.contentType);
      try {
        this.guard(generation);
        if (!/^(blob:|file:\/\/)/.test(resource.uri)) fail("media_invalid_uri");
      } catch (error) {
        resource.dispose();
        throw error;
      }
      const result = {
        uri: resource.uri,
        width: first.width,
        height: first.height,
        alt: "Private image",
      };
      this.cache.set(key, {
        fingerprint,
        resource,
        asset: result,
        bytes: bytes.length,
      });
      const max = this.options.maxCacheBytes ?? 32 * 1024 * 1024;
      while (
        [...this.cache.values()].reduce((sum, item) => sum + item.bytes, 0) >
          max &&
        this.cache.size > 1
      ) {
        const oldest = this.cache.keys().next().value!;
        this.cache.get(oldest)!.resource.dispose();
        this.cache.delete(oldest);
      }
      return { ...result };
    } finally {
      bytes?.fill(0);
    }
  }
  handleFailure(error: unknown): RuntimeError {
    const safe = this.safe(error);
    this.observeFailure(safe);
    return safe;
  }
  invalidate() {
    this.generation++;
    for (const cancel of this.cancellations) cancel();
    this.cancellations.clear();
    for (const value of this.cache.values()) {
      try {
        value.resource.dispose();
      } catch {}
    }
    this.cache.clear();
    this.reads.clear();
  }
  dispose() {
    if (this.disposed) return;
    this.invalidate();
    this.disposed = true;
    this.removeLifetime();
    this.options.ports.dispose();
    this.saved = null;
    this.state = empty();
    for (const listener of this.listeners) {
      try {
        listener();
      } catch {}
    }
    this.listeners.clear();
  }
}
