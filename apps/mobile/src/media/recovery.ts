import type { ScopedHostStorage } from "../host/storage";
import { freezeValidated } from "../runtime/immutable";
import { runtimeJsonSnapshot } from "../runtime/json";
import { CHUNK_BYTES, MAX_CHUNKS, ORIGINAL_BYTES } from "./types";
import type { BeginCommand, MediaMutation, UploadManifest } from "./types";
import {
  context,
  counter,
  decode64,
  encode64,
  fail,
  hash,
  id,
  keys,
  object,
} from "./codec";

export interface StoredUpload extends UploadManifest {
  revision: number;
}
const kind = "private-media-v1";
export function decodeUpload(value: unknown): StoredUpload {
  const row = object(runtimeJsonSnapshot(value));
  keys(row, [
    "format",
    "revision",
    "localId",
    "appId",
    "versionId",
    ...(Object.hasOwn(row, "candidateHash") ? ["candidateHash"] : []),
    "context",
    "begin",
    "completeOperationId",
    "chunkHashes",
    "phase",
    "assetId",
    "nextChunk",
    "pending",
    "outcome",
  ]);
  if (
    row.format !== 1 ||
    ![
      "preparing",
      "begin",
      "chunks",
      "complete",
      "processing",
      "ready",
      "failed",
    ].includes(row.phase as string) ||
    !["none", "sending", "uncertain", "failed"].includes(row.outcome as string)
  )
    fail("media_saved_invalid");
  const intent = context(row.context),
    begin = object(row.begin),
    appId = id(row.appId),
    versionId = row.versionId === null ? null : id(row.versionId);
  const candidateHash = Object.hasOwn(row, "candidateHash")
    ? hash(row.candidateHash)
    : undefined;
  if (
    (versionId === null && (!("draftRevision" in intent) || !candidateHash)) ||
    (candidateHash !== undefined && !("draftRevision" in intent)) ||
    (!("draftRevision" in intent) && versionId !== intent.versionId)
  )
    fail("media_saved_invalid");
  const contextKeys = Object.keys(intent);
  keys(begin, [
    "op",
    "appId",
    "operationId",
    "byteLength",
    "contentType",
    "sha256",
    ...contextKeys,
  ]);
  if (
    begin.op !== "spec.media.begin" ||
    begin.appId !== appId ||
    !["image/jpeg", "image/png", "image/webp"].includes(
      begin.contentType as string,
    ) ||
    contextKeys.some(
      (k) => begin[k] !== Object.getOwnPropertyDescriptor(intent, k)?.value,
    )
  )
    fail("media_saved_invalid");
  id(begin.operationId);
  hash(begin.sha256);
  const length = counter(begin.byteLength, ORIGINAL_BYTES, 1),
    chunks = Math.ceil(length / CHUNK_BYTES);
  if (
    !Array.isArray(row.chunkHashes) ||
    row.chunkHashes.length !== chunks ||
    chunks > MAX_CHUNKS
  )
    fail("media_saved_invalid");
  const chunkHashes = row.chunkHashes.map(hash),
    nextChunk = counter(row.nextChunk, chunks);
  const assetId = row.assetId === null ? null : id(row.assetId);
  const pending = row.pending === null ? null : object(row.pending);
  if (pending) {
    if (pending.op === "spec.media.begin") {
      keys(pending, Object.keys(begin));
      if (Object.keys(begin).some((key) => pending[key] !== begin[key]))
        fail("media_saved_invalid");
    } else if (pending.op === "spec.media.complete") {
      keys(pending, ["op", "appId", "assetId", "operationId"]);
      if (
        pending.appId !== appId ||
        pending.assetId !== assetId ||
        pending.operationId !== row.completeOperationId
      )
        fail("media_saved_invalid");
    } else if (pending.op === "spec.media.chunk") {
      keys(pending, [
        "op",
        "appId",
        "assetId",
        "offset",
        "sha256",
        "dataBase64",
      ]);
      const offset = counter(pending.offset, length - 1),
        index = offset / CHUNK_BYTES,
        bytes = decode64(pending.dataBase64);
      if (
        pending.appId !== appId ||
        pending.assetId !== assetId ||
        !Number.isInteger(index) ||
        pending.sha256 !== chunkHashes[index] ||
        bytes.length !== Math.min(CHUNK_BYTES, length - offset)
      )
        fail("media_saved_invalid");
    } else fail("media_saved_invalid");
  }
  if (
    (row.phase === "preparing" && pending !== null) ||
    (row.phase === "begin" && pending?.op !== "spec.media.begin") ||
    (["chunks", "complete", "processing", "ready"].includes(
      row.phase as string,
    ) &&
      assetId === null) ||
    (["processing", "ready"].includes(row.phase as string) &&
      (pending !== null || nextChunk !== chunks)) ||
    (pending !== null && row.outcome === "none") ||
    (pending === null &&
      ["sending", "uncertain"].includes(row.outcome as string))
  )
    fail("media_saved_invalid");
  return freezeValidated({
    format: 1,
    revision: counter(row.revision),
    localId: id(row.localId),
    appId,
    versionId,
    ...(candidateHash !== undefined ? { candidateHash } : {}),
    context: intent,
    begin: begin as BeginCommand,
    completeOperationId: id(row.completeOperationId),
    chunkHashes,
    phase: row.phase as StoredUpload["phase"],
    assetId,
    nextChunk,
    pending: pending as MediaMutation | null,
    outcome: row.outcome as StoredUpload["outcome"],
  });
}
/** All entries use the existing encrypted account/app-scoped host storage. */
export class MediaRecovery {
  readonly durability = "durable" as const;
  constructor(
    readonly storage: ScopedHostStorage,
    readonly namespace: "private-media-v1" | "private-draft-media-v1" = kind,
  ) {}
  async read(): Promise<StoredUpload | null> {
    const value = await this.storage.read(this.namespace);
    return value === null ? null : decodeUpload(value);
  }
  async reserve(value: StoredUpload) {
    const frozen = decodeUpload(value);
    await this.storage.change(this.namespace, (previous) => {
      if (previous !== null) fail("media_pending");
      return frozen;
    });
    return frozen;
  }
  async save(value: StoredUpload): Promise<StoredUpload> {
    const next = decodeUpload({ ...value, revision: value.revision + 1 });
    await this.storage.change(this.namespace, (previous) => {
      if (previous === null) fail("media_storage_conflict");
      const old = decodeUpload(previous);
      if (old.localId !== value.localId || old.revision !== value.revision)
        fail("media_storage_conflict");
      return next;
    });
    return next;
  }
  private key(localId: string, index: number) {
    return `${this.namespace}-${id(localId)}-${counter(index, MAX_CHUNKS - 1)}`;
  }
  async putChunk(value: StoredUpload, index: number, bytes: Uint8Array) {
    const data = encode64(bytes),
      expected = value.chunkHashes[index];
    await this.storage.change(this.key(value.localId, index), (previous) => {
      if (previous !== null) {
        const row = object(previous);
        keys(row, ["hash", "data"]);
        if (row.hash !== expected || row.data !== data)
          fail("media_saved_invalid");
        return row;
      }
      return { hash: expected, data };
    });
  }
  async chunk(value: StoredUpload, index: number): Promise<Uint8Array> {
    const entry = await this.storage.read(this.key(value.localId, index));
    if (entry === null) fail("media_reselect_required");
    const row = object(entry);
    keys(row, ["hash", "data"]);
    const bytes = decode64(row.data);
    if (
      row.hash !== value.chunkHashes[index] ||
      bytes.length !==
        Math.min(CHUNK_BYTES, value.begin.byteLength - index * CHUNK_BYTES)
    )
      fail("media_saved_invalid");
    return bytes;
  }
  async clear(value: StoredUpload) {
    await this.storage.change(this.namespace, (previous) => {
      if (previous === null) return null;
      const old = decodeUpload(previous);
      if (old.localId !== value.localId || old.revision !== value.revision)
        fail("media_storage_conflict");
      return null;
    });
    // Clearing must be confirmed before deleting data needed by an unknown save.
    for (let index = 0; index < value.chunkHashes.length; index++)
      await this.storage.change(this.key(value.localId, index), () => null);
  }
}
