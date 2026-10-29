import { RuntimeError } from "../runtime/errors";
import { runtimeJsonSnapshot } from "../runtime/json";
import {
  CHUNK_BYTES,
  DISPLAY_BYTES,
  ORIGINAL_BYTES,
  THUMBNAIL_BYTES,
} from "./types";
import type {
  InputMime,
  MediaAsset,
  MediaUploadContext,
  MediaVariant,
  OutputMime,
} from "./types";
export function fail(
  code = "media_invalid_response",
  uncertain = false,
): never {
  throw new RuntimeError(
    code,
    uncertain
      ? "The image request could not be confirmed. Retry the retained upload."
      : code === "media_too_large"
        ? "Choose a JPEG, PNG or WebP image no larger than 5 MiB."
        : code === "media_processing"
          ? "The private image is processing. Check its status before attaching it."
          : "The private image could not be verified. Your other values are retained.",
    uncertain,
  );
}
export function object(value: unknown): Record<string, unknown> {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    (Object.getPrototypeOf(value) !== Object.prototype &&
      Object.getPrototypeOf(value) !== null)
  )
    fail();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (
    Reflect.ownKeys(descriptors).some(
      (k) => typeof k !== "string" || !("value" in descriptors[k]),
    )
  )
    fail();
  return value as Record<string, unknown>;
}
export function keys(
  value: Record<string, unknown>,
  expected: readonly string[],
) {
  if (
    Object.keys(value).length !== expected.length ||
    expected.some((k) => !Object.hasOwn(value, k))
  )
    fail();
}
export function id(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/.test(value)
  )
    fail();
  return value;
}
export function counter(value: unknown, max = 2_147_483_646, min = 0): number {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < min ||
    (value as number) > max
  )
    fail();
  return value as number;
}
export function hash(value: unknown): string {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) fail();
  return value;
}
export function aligned(value: number, total: number) {
  return value === total || value % CHUNK_BYTES === 0;
}
export function context(value: unknown): MediaUploadContext {
  const row = object(runtimeJsonSnapshot(value));
  if (Object.hasOwn(row, "draftRevision")) {
    keys(row, ["draftRevision"]);
    return { draftRevision: counter(row.draftRevision, 2_147_483_646, 1) };
  }
  const expected = [
    "versionId",
    "actionId",
    "fieldId",
    ...(Object.hasOwn(row, "targetRecordId")
      ? ["targetRecordId", "expectedRecordRevision"]
      : []),
  ];
  keys(row, expected);
  const stable = (v: unknown) => {
    if (typeof v !== "string" || !/^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(v))
      fail("invalid_input");
    return v;
  };
  return {
    versionId: id(row.versionId),
    actionId: stable(row.actionId),
    fieldId: stable(row.fieldId),
    ...(Object.hasOwn(row, "targetRecordId")
      ? {
          targetRecordId: id(row.targetRecordId),
          expectedRecordRevision: counter(
            row.expectedRecordRevision,
            2_147_483_646,
            1,
          ),
        }
      : {}),
  };
}
export function asset(value: unknown, expectedId?: string): MediaAsset {
  const row = object(value),
    assetId = id(row.assetId);
  if (expectedId && assetId !== expectedId) fail();
  if (row.status === "ready") {
    keys(row, [
      "assetId",
      "status",
      "contentType",
      "byteLength",
      "width",
      "height",
      "sha256",
    ]);
    if (row.contentType !== "image/jpeg" && row.contentType !== "image/png")
      fail();
    return {
      assetId,
      status: "ready",
      contentType: row.contentType,
      byteLength: counter(row.byteLength, DISPLAY_BYTES, 1),
      width: counter(row.width, 2048, 1),
      height: counter(row.height, 2048, 1),
      sha256: hash(row.sha256),
    };
  }
  if (
    !["pending", "queued", "processing", "failed"].includes(
      row.status as string,
    )
  )
    fail();
  keys(row, [
    "assetId",
    "status",
    "uploadedBytes",
    "inputBytes",
    ...(row.status === "failed" ? ["error"] : []),
  ]);
  const inputBytes = counter(row.inputBytes, ORIGINAL_BYTES, 1),
    uploadedBytes = counter(row.uploadedBytes, inputBytes);
  if (
    !aligned(uploadedBytes, inputBytes) ||
    (row.status !== "pending" && uploadedBytes !== inputBytes)
  )
    fail();
  if (row.status === "failed") {
    if (typeof row.error !== "string" || !/^[a-z0-9_]{1,64}$/.test(row.error))
      fail();
    return {
      assetId,
      status: "failed",
      inputBytes,
      uploadedBytes,
      error: row.error,
    };
  }
  return {
    assetId,
    status: row.status as "pending" | "queued" | "processing",
    inputBytes,
    uploadedBytes,
  };
}
const alphabet =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
export function encode64(bytes: Uint8Array): string {
  const parts: string[] = [];
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i],
      b = bytes[i + 1],
      c = bytes[i + 2];
    parts.push(
      alphabet[a >> 2] +
        alphabet[((a & 3) << 4) | ((b ?? 0) >> 4)] +
        (b === undefined ? "=" : alphabet[((b & 15) << 2) | ((c ?? 0) >> 6)]) +
        (c === undefined ? "=" : alphabet[c & 63]),
    );
  }
  return parts.join("");
}
export function decode64(value: unknown, max = CHUNK_BYTES): Uint8Array {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > Math.ceil(max / 3) * 4 ||
    value.length % 4 !== 0 ||
    !/^[A-Za-z0-9+/]*={0,2}$/.test(value)
  )
    fail();
  const length =
    (value.length / 4) * 3 -
    (value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0);
  if (length > max || length < 1) fail();
  const bytes = new Uint8Array(length);
  let cursor = 0;
  for (let i = 0; i < value.length; i += 4) {
    const a = alphabet.indexOf(value[i]),
      b = alphabet.indexOf(value[i + 1]),
      c = alphabet.indexOf(value[i + 2]),
      d = alphabet.indexOf(value[i + 3]);
    bytes[cursor++] = (a << 2) | (b >> 4);
    if (cursor < length) bytes[cursor++] = ((b & 15) << 4) | (c >> 2);
    if (cursor < length) bytes[cursor++] = ((c & 3) << 6) | d;
  }
  if (encode64(bytes) !== value) fail();
  return bytes;
}
export function sniff(bytes: Uint8Array): InputMime {
  if (
    bytes.length >= 3 &&
    bytes[0] === 255 &&
    bytes[1] === 216 &&
    bytes[2] === 255
  )
    return "image/jpeg";
  if (
    bytes.length >= 8 &&
    [137, 80, 78, 71, 13, 10, 26, 10].every((v, i) => bytes[i] === v)
  )
    return "image/png";
  if (
    bytes.length >= 12 &&
    [82, 73, 70, 70].every((v, i) => bytes[i] === v) &&
    [87, 69, 66, 80].every((v, i) => bytes[i + 8] === v)
  )
    return "image/webp";
  return fail("media_unsupported");
}
export interface ReadChunk {
  assetId: string;
  variant: MediaVariant;
  offset: number;
  nextOffset: number | null;
  byteLength: number;
  contentType: OutputMime;
  sha256: string;
  chunkSha256: string;
  bytes: Uint8Array;
  width: number;
  height: number;
}
export function readChunk(
  value: unknown,
  assetId: string,
  variant: MediaVariant,
  offset: number,
): ReadChunk {
  const row = object(value);
  keys(row, [
    "assetId",
    "variant",
    "offset",
    "nextOffset",
    "byteLength",
    "contentType",
    "sha256",
    "chunkSha256",
    "dataBase64",
    "width",
    "height",
    "cacheControl",
  ]);
  if (
    id(row.assetId) !== assetId ||
    row.variant !== variant ||
    row.offset !== offset ||
    row.cacheControl !== "private, no-store"
  )
    fail();
  const byteLength = counter(
      row.byteLength,
      variant === "display" ? DISPLAY_BYTES : THUMBNAIL_BYTES,
      1,
    ),
    bytes = decode64(row.dataBase64),
    end = offset + bytes.length;
  if (
    offset % CHUNK_BYTES !== 0 ||
    end > byteLength ||
    bytes.length !== Math.min(CHUNK_BYTES, byteLength - offset) ||
    row.nextOffset !== (end === byteLength ? null : end) ||
    (row.contentType !== "image/jpeg" && row.contentType !== "image/png")
  )
    fail();
  return {
    assetId,
    variant,
    offset,
    nextOffset: row.nextOffset as number | null,
    byteLength,
    contentType: row.contentType,
    sha256: hash(row.sha256),
    chunkSha256: hash(row.chunkSha256),
    bytes,
    width: counter(row.width, 2048, 1),
    height: counter(row.height, 2048, 1),
  };
}
