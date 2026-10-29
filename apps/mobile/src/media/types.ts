import type { PickedImage, RuntimeRole, RuntimeRecord } from "../runtime/types";
import type { AppSpec, ActionSpec } from "../spec/types";

/** Authority metadata only. This interface has no record/query execution surface. */
export interface MediaAuthority {
  readonly appId: string;
  readonly versionId: string | null;
  readonly spec: AppSpec;
  readonly role: RuntimeRole;
  readonly archived: boolean;
  readonly preview: boolean;
  readonly draft?: {
    readonly revision: number;
    readonly candidateHash: string;
  };
  permits?(action: ActionSpec, record?: RuntimeRecord): boolean;
}
export interface DraftMediaAuthority extends MediaAuthority {
  readonly versionId: null;
  readonly preview: false;
  readonly role: "owner" | "builder";
  readonly draft: { readonly revision: number; readonly candidateHash: string };
}

export const ORIGINAL_BYTES = 5 * 1024 * 1024;
export const DISPLAY_BYTES = ORIGINAL_BYTES;
export const THUMBNAIL_BYTES = 512 * 1024;
export const CHUNK_BYTES = 256 * 1024;
export const MAX_CHUNKS = 20;
export type InputMime = PickedImage["mimeType"];
export type OutputMime = "image/jpeg" | "image/png";
export type MediaVariant = "display" | "thumbnail";
export interface RecordMediaUploadContext {
  versionId: string;
  actionId: string;
  fieldId: string;
  targetRecordId?: string;
  expectedRecordRevision?: number;
}
export interface DraftMediaUploadContext {
  draftRevision: number;
}
export type MediaUploadContext =
  RecordMediaUploadContext | DraftMediaUploadContext;
export interface ReadyAsset {
  assetId: string;
  status: "ready";
  contentType: OutputMime;
  byteLength: number;
  width: number;
  height: number;
  sha256: string;
}
export interface PendingAsset {
  assetId: string;
  status: "pending" | "queued" | "processing";
  uploadedBytes: number;
  inputBytes: number;
}
export interface FailedAsset {
  assetId: string;
  status: "failed";
  uploadedBytes: number;
  inputBytes: number;
  error: string;
}
export type MediaAsset = ReadyAsset | PendingAsset | FailedAsset;
export interface ImageResource {
  uri: string;
  dispose(): void;
}
/** Host-owned implementations; neither the definition nor a transport response chooses these. */
export interface MediaPorts {
  sha256(bytes: Uint8Array): Promise<string>;
  pick(): Promise<PickedImage | null>;
  image(bytes: Uint8Array, contentType: OutputMime): Promise<ImageResource>;
  dispose(): void;
}
export interface BeginCommand extends Record<string, unknown> {
  op: "spec.media.begin";
  appId: string;
  operationId: string;
  byteLength: number;
  contentType: InputMime;
  sha256: string;
}
export interface ChunkCommand extends Record<string, unknown> {
  op: "spec.media.chunk";
  appId: string;
  assetId: string;
  offset: number;
  sha256: string;
  dataBase64: string;
}
export interface CompleteCommand extends Record<string, unknown> {
  op: "spec.media.complete";
  appId: string;
  assetId: string;
  operationId: string;
}
export type MediaMutation = BeginCommand | ChunkCommand | CompleteCommand;
export interface UploadManifest {
  format: 1;
  localId: string;
  appId: string;
  versionId: string | null;
  candidateHash?: string;
  context: MediaUploadContext;
  begin: BeginCommand;
  completeOperationId: string;
  chunkHashes: string[];
  phase:
    | "preparing"
    | "begin"
    | "chunks"
    | "complete"
    | "processing"
    | "ready"
    | "failed";
  assetId: string | null;
  nextChunk: number;
  pending: MediaMutation | null;
  outcome: "none" | "sending" | "uncertain" | "failed";
}
export interface UploadSnapshot {
  initialized: boolean;
  busy: boolean;
  stage: UploadManifest["phase"] | null;
  asset: MediaAsset | null;
  uploadedBytes: number;
  inputBytes: number;
  pending: null | {
    operation: MediaMutation["op"];
    operationId?: string;
    offset?: number;
  };
  uncertain: boolean;
  error: string | null;
  accessDenied: boolean;
}
