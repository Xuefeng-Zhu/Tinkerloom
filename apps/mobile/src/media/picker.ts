import type { PickedImage } from "../runtime/types";
import { CHUNK_BYTES, ORIGINAL_BYTES } from "./types";
import { fail, sniff } from "./codec";

/** Reads the original without decoding pixels or allocating beyond the input bound. */
export async function collectPickedImage(
  read: (maximum: number) => Promise<Uint8Array>,
  guard: () => void,
  sizes: readonly (number | undefined)[],
  declaredMime?: string,
): Promise<PickedImage> {
  guard();
  for (const size of sizes) {
    if (size === undefined) continue;
    if (!Number.isSafeInteger(size) || size < 1) fail("media_unsupported");
    if (size > ORIGINAL_BYTES) fail("media_too_large");
  }
  if (
    declaredMime &&
    !["image/jpeg", "image/png", "image/webp"].includes(declaredMime)
  )
    fail("media_unsupported");
  const chunks: Uint8Array[] = [];
  let length = 0;
  let bytes: Uint8Array | undefined;
  try {
    while (true) {
      guard();
      const maximum = Math.min(CHUNK_BYTES, ORIGINAL_BYTES + 1 - length);
      const chunk = await read(maximum);
      if (!(chunk instanceof Uint8Array)) fail("media_unsupported");
      chunks.push(chunk);
      guard();
      if (chunk.length > maximum || length + chunk.length > ORIGINAL_BYTES)
        fail("media_too_large");
      if (chunk.length === 0) break;
      length += chunk.length;
    }
    if (!length || sizes.some((size) => size !== undefined && size !== length))
      fail("media_unsupported");
    bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    const mimeType = sniff(bytes);
    if (declaredMime && declaredMime !== mimeType) fail("media_unsupported");
    guard();
    return { bytes, mimeType, name: "Selected private image" };
  } catch (error) {
    bytes?.fill(0);
    throw error;
  } finally {
    for (const chunk of chunks) chunk.fill(0);
  }
}
