import { RuntimeError } from "./errors";
import { validatePreviewInflate } from "./previewImageInflate";
import type { PickedImage } from "./types";
export const PREVIEW_IMAGE_BYTES = 5 * 1024 * 1024;
export const PREVIEW_TOTAL_IMAGE_BYTES = 8 * 1024 * 1024;
export const PREVIEW_TOTAL_IMAGE_PIXELS = 16_000_000;
export const PREVIEW_IMAGE_COUNT = 16;
export interface CheckedPreviewImage {
  readonly bytes: Uint8Array;
  readonly mimeType: PickedImage["mimeType"];
  readonly width: number;
  readonly height: number;
}
const invalid = (): never => {
  throw new RuntimeError(
    "invalid_preview_image",
    "Choose a valid still JPEG, PNG or WebP image of at most 5 MiB and 16 megapixels.",
  );
};
function dimensions(width: number, height: number) {
  if (
    width < 1 ||
    height < 1 ||
    width > 8192 ||
    height > 8192 ||
    width * height > PREVIEW_TOTAL_IMAGE_PIXELS
  )
    invalid();
}
const tag = (b: Uint8Array, p: number) =>
  String.fromCharCode(...b.subarray(p, p + 4));
const equal = (b: Uint8Array, p: number, values: readonly number[]) =>
  values.every((value, n) => b[p + n] === value);
const be16 = (b: Uint8Array, p: number) => (b[p] << 8) | b[p + 1];
const le24 = (b: Uint8Array, p: number) =>
  b[p] | (b[p + 1] << 8) | (b[p + 2] << 16);
const u32 = (b: Uint8Array, p: number, little = false) =>
  new DataView(b.buffer, b.byteOffset + p, 4).getUint32(0, little);

function jpeg(b: Uint8Array): [number, number] {
  let p = 2,
    inScan = false,
    sawScan = false,
    width = 0,
    height = 0,
    frame = 0,
    entropy = 0,
    segments = 0;
  const components = new Map<number, number>(),
    quantization = new Set<number>(),
    huffman = new Set<number>();
  while (p < b.length) {
    if (++segments > 4096) invalid();
    if (inScan)
      while (p < b.length && b[p] !== 255) {
        p++;
        entropy++;
      }
    if (p >= b.length || b[p++] !== 255) invalid();
    while (p < b.length && b[p] === 255) p++;
    if (p >= b.length) invalid();
    const marker = b[p++];
    if (marker === 217) {
      if (!width || !sawScan || !entropy || p !== b.length) invalid();
      return [width, height];
    }
    if ((marker === 0 || (marker >= 208 && marker <= 215)) && inScan) {
      if (marker === 0) entropy++;
      continue;
    }
    if (marker === 1) continue;
    if (marker < 192 || marker === 216 || p + 2 > b.length) invalid();
    const length = be16(b, p),
      end = p + length,
      data = p + 2;
    if (length < 2 || end > b.length) invalid();
    const isFrame =
      marker >= 192 && marker <= 207 && ![196, 200, 204].includes(marker);
    if (isFrame) {
      if (![192, 193, 194].includes(marker) || width || length < 8) invalid();
      const count = b[data + 5];
      if (
        b[data] !== 8 ||
        ![1, 3, 4].includes(count) ||
        length !== 8 + count * 3
      )
        invalid();
      height = be16(b, data + 1);
      width = be16(b, data + 3);
      dimensions(width, height);
      frame = marker;
      let samples = 0;
      for (let n = 0; n < count; n++) {
        const at = data + 6 + n * 3,
          horizontal = b[at + 1] >>> 4,
          vertical = b[at + 1] & 15;
        if (
          components.has(b[at]) ||
          horizontal < 1 ||
          horizontal > 4 ||
          vertical < 1 ||
          vertical > 4 ||
          b[at + 2] > 3
        )
          invalid();
        components.set(b[at], b[at + 2]);
        samples += horizontal * vertical;
      }
      if (samples > 10) invalid();
    } else if (marker === 218) {
      if (!width || length < 6) invalid();
      const count = b[data],
        selected = new Set<number>();
      if (count < 1 || count > components.size || length !== 6 + count * 2)
        invalid();
      const start = b[data + 1 + count * 2],
        stop = b[data + 2 + count * 2],
        approximation = b[data + 3 + count * 2];
      if (
        start > stop ||
        stop > 63 ||
        approximation >>> 4 > 13 ||
        (approximation & 15) > 13 ||
        (frame !== 194 && (start !== 0 || stop !== 63 || approximation !== 0))
      )
        invalid();
      for (let n = 0; n < count; n++) {
        const id = b[data + 1 + n * 2],
          tables = b[data + 2 + n * 2];
        if (
          !components.has(id) ||
          selected.has(id) ||
          tables >>> 4 > 3 ||
          (tables & 15) > 3 ||
          !quantization.has(components.get(id)!)
        )
          invalid();
        if (
          (start === 0 && !huffman.has(tables >>> 4)) ||
          (stop > 0 && !huffman.has(16 | (tables & 15)))
        )
          invalid();
        selected.add(id);
      }
      sawScan = inScan = true;
    } else if (marker === 220) invalid();
    else if (marker === 219) {
      let at = data;
      if (at === end) invalid();
      while (at < end) {
        const descriptor = b[at++],
          precision = descriptor >>> 4,
          id = descriptor & 15;
        if (precision > 1 || id > 3 || at + 64 * (precision + 1) > end)
          invalid();
        for (let n = 0; n < 64; n++) {
          const value = precision ? be16(b, at) : b[at];
          at += precision + 1;
          if (!value || value > 32767) invalid();
        }
        quantization.add(id);
      }
    } else if (marker === 196) {
      let at = data;
      while (at < end) {
        if (at + 17 > end) invalid();
        const descriptor = b[at++];
        if (descriptor >>> 4 > 1 || (descriptor & 15) > 3) invalid();
        let count = 0,
          remaining = 1;
        for (let n = 0; n < 16; n++) {
          const size = b[at++];
          count += size;
          remaining = remaining * 2 - size;
          if (remaining < 0) invalid();
        }
        if (!count || count > 256 || at + count > end) invalid();
        for (let n = 0; n < count; n++) {
          const value = b[at++];
          if (descriptor >>> 4 === 0 ? value > 11 : (value & 15) > 10)
            invalid();
        }
        huffman.add(descriptor);
      }
    } else if (marker >= 224 && marker <= 239) {
      // Original bytes are retained. Refuse metadata that the live worker strips
      // before decoding, including EXIF thumbnails and ICC allocation containers.
      if (marker === 224) {
        if (length > 256) invalid();
        if (equal(b, data, [74, 70, 73, 70, 0])) {
          if (length < 16 || length !== 16 + b[data + 12] * b[data + 13] * 3)
            invalid();
        } else invalid();
      } else if (marker === 238) {
        if (length !== 14 || !equal(b, data, [65, 100, 111, 98, 101]))
          invalid();
      } else invalid();
    } else if (marker === 221) {
      if (length !== 4) invalid();
    } else if (marker !== 254) invalid();
    // Original decoder resynchronization must not find hidden allocation/EXIF markers.
    // Quantization values may legitimately contain FFxx. Their declared table
    // lengths/precision are fully checked above; unlike the live worker this
    // memory path neither normalizes tables nor invokes the Dart decoder.
    if (marker !== 219)
      for (let n = data; n + 1 < end; n++)
        if (b[n] === 255 && [192, 193, 194, 225].includes(b[n + 1])) invalid();
    p = end;
  }
  return invalid();
}
const crcTable = Uint32Array.from({ length: 256 }, (_, value) => {
  let crc = value;
  for (let n = 0; n < 8; n++)
    crc = crc & 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  return crc >>> 0;
});
function crc(b: Uint8Array, start: number, end: number) {
  let value = 0xffffffff;
  for (let p = start; p < end; p++)
    value = crcTable[(value ^ b[p]) & 255] ^ (value >>> 8);
  return (value ^ 0xffffffff) >>> 0;
}
function png(b: Uint8Array): [number, number] {
  let p = 8,
    chunks = 0,
    width = 0,
    height = 0,
    bits = 0,
    color = -1,
    interlace = 0,
    channels = 0,
    palette = 0,
    sawPalette = false,
    transparency = false,
    sawData = false,
    endedData = false;
  const idat: Uint8Array[] = [];
  while (p + 12 <= b.length) {
    if (++chunks > 4096) invalid();
    const size = u32(b, p),
      end = p + 12 + size,
      data = p + 8;
    if (end > b.length) invalid();
    const type = tag(b, p + 4);
    if (
      !/^[A-Za-z]{4}$/.test(type) ||
      crc(b, p + 4, data + size) !== u32(b, data + size) ||
      (!width && type !== "IHDR")
    )
      invalid();
    if (type === "IHDR") {
      if (width || size !== 13) invalid();
      width = u32(b, data);
      height = u32(b, data + 4);
      dimensions(width, height);
      bits = b[data + 8];
      color = b[data + 9];
      const depths =
        color === 0
          ? [1, 2, 4, 8, 16]
          : [2, 4, 6].includes(color)
            ? [8, 16]
            : color === 3
              ? [1, 2, 4, 8]
              : [];
      if (
        !depths.includes(bits) ||
        b[data + 10] ||
        b[data + 11] ||
        b[data + 12] > 1
      )
        invalid();
      channels = color === 2 ? 3 : color === 4 ? 2 : color === 6 ? 4 : 1;
      interlace = b[data + 12];
    } else if (["acTL", "fcTL", "fdAT"].includes(type)) invalid();
    else if (type === "PLTE") {
      if (
        sawPalette ||
        sawData ||
        !size ||
        size > 768 ||
        size % 3 ||
        [0, 4].includes(color)
      )
        invalid();
      sawPalette = true;
      palette = size / 3;
      if (color === 3 && palette > 2 ** bits) invalid();
    } else if (type === "tRNS") {
      if (
        transparency ||
        sawData ||
        (color === 0
          ? size !== 2
          : color === 2
            ? size !== 6
            : color === 3
              ? !sawPalette || size < 1 || size > palette
              : true)
      )
        invalid();
      transparency = true;
    } else if (type === "IDAT") {
      if (endedData || (color === 3 && !sawPalette)) invalid();
      sawData = true;
      idat.push(b.subarray(data, data + size));
    } else if (type === "IEND") {
      if (size || !sawData || end !== b.length) invalid();
      const passes = (
        interlace
          ? [
              [0, 0, 8, 8],
              [4, 0, 8, 8],
              [0, 4, 4, 8],
              [2, 0, 4, 4],
              [0, 2, 2, 4],
              [1, 0, 2, 2],
              [0, 1, 1, 2],
            ]
          : [[0, 0, 1, 1]]
      ).flatMap(([x, y, dx, dy]) => {
        const w = width <= x ? 0 : Math.ceil((width - x) / dx),
          h = height <= y ? 0 : Math.ceil((height - y) / dy);
        return w && h
          ? [{ rows: h, stride: 1 + Math.ceil((w * bits * channels) / 8) }]
          : [];
      });
      const expected = passes.reduce(
          (sum, pass) => sum + pass.rows * pass.stride,
          0,
        ),
        compressed = new Uint8Array(
          idat.reduce((sum, part) => sum + part.length, 0),
        );
      let offset = 0;
      for (const part of idat) {
        compressed.set(part, offset);
        offset += part.length;
      }
      let pass = 0,
        row = 0,
        column = 0;
      validatePreviewInflate(compressed, expected, (_position, value) => {
        if (column === 0 && value > 4) invalid();
        if (++column === passes[pass].stride) {
          column = 0;
          if (++row === passes[pass].rows) {
            pass++;
            row = 0;
          }
        }
      });
      return [width, height];
    } else {
      if (sawData) endedData = true;
      if (
        !["gAMA", "pHYs", "sRGB", "cHRM", "tEXt"].includes(type) ||
        size > 65536
      )
        invalid();
      if (
        (type === "gAMA" && (size !== 4 || !u32(b, data))) ||
        (type === "pHYs" && size !== 9) ||
        (type === "sRGB" && (size !== 1 || b[data] > 3)) ||
        (type === "cHRM" && size !== 32)
      )
        invalid();
    }
    p = end;
  }
  return invalid();
}
function webp(b: Uint8Array): [number, number] {
  if (u32(b, 4, true) + 8 !== b.length) invalid();
  let p = 12,
    width = 0,
    height = 0,
    canvasWidth = 0,
    canvasHeight = 0,
    alpha = false,
    flags = 0,
    chunks = 0;
  while (p + 8 <= b.length) {
    if (++chunks > 4096) invalid();
    const type = tag(b, p),
      size = u32(b, p + 4, true),
      data = p + 8,
      end = data + size + (size & 1);
    if (end > b.length || (size & 1 && b[end - 1] !== 0)) invalid();
    if (type === "VP8X") {
      if (p !== 12 || size !== 10 || b[data] & ~16 || le24(b, data + 1))
        invalid();
      flags = b[data];
      canvasWidth = le24(b, data + 4) + 1;
      canvasHeight = le24(b, data + 7) + 1;
      dimensions(canvasWidth, canvasHeight);
    } else if (type === "VP8L") {
      if (width || alpha || size < 6 || b[data] !== 47) invalid();
      const header = u32(b, data + 1, true);
      if (header >>> 29) invalid();
      width = (header & 16383) + 1;
      height = ((header >>> 14) & 16383) + 1;
      dimensions(width, height);
    } else if (type === "VP8 ") {
      if (
        width ||
        size < 11 ||
        b[data] & 1 ||
        !equal(b, data + 3, [157, 1, 42])
      )
        invalid();
      const frame = le24(b, data);
      if (
        ((frame >>> 1) & 7) > 3 ||
        !(frame & 16) ||
        frame >>> 5 > size - 10 ||
        !(frame >>> 5)
      )
        invalid();
      width = b[data + 6] | (b[data + 7] << 8);
      height = b[data + 8] | (b[data + 9] << 8);
      if (width & 49152 || height & 49152) invalid();
      dimensions(width, height);
    } else if (type === "ALPH") {
      if (
        alpha ||
        width ||
        !canvasWidth ||
        !size ||
        !(flags & 16) ||
        b[data] & 192 ||
        (b[data] & 3) > 1 ||
        ((b[data] >>> 4) & 3) > 1
      )
        invalid();
      if ((b[data] & 3) === 0 && size !== 1 + canvasWidth * canvasHeight)
        invalid();
      alpha = true;
    } else invalid(); // ANIM/ANMF, EXIF/ICCP/XMP and unknown original decoder containers.
    p = end;
  }
  if (
    p !== b.length ||
    !width ||
    !height ||
    (canvasWidth && (canvasWidth !== width || canvasHeight !== height))
  )
    invalid();
  return [width, height];
}
/** Allocation/container preflight only; no decoder, sanitizer or metadata removal is claimed. */
export function checkPreviewImage(image: PickedImage): CheckedPreviewImage {
  if (
    !(image.bytes instanceof Uint8Array) ||
    !(image.bytes.buffer instanceof ArrayBuffer) ||
    !image.bytes.length ||
    image.bytes.length > PREVIEW_IMAGE_BYTES
  )
    invalid();
  const bytes = new Uint8Array(image.bytes.length);
  bytes.set(image.bytes);
  let mimeType: PickedImage["mimeType"], result: [number, number];
  if (bytes.length >= 2 && bytes[0] === 255 && bytes[1] === 216) {
    mimeType = "image/jpeg";
    result = jpeg(bytes);
  } else if (
    bytes.length >= 8 &&
    equal(bytes, 0, [137, 80, 78, 71, 13, 10, 26, 10])
  ) {
    mimeType = "image/png";
    result = png(bytes);
  } else if (
    bytes.length >= 12 &&
    tag(bytes, 0) === "RIFF" &&
    tag(bytes, 8) === "WEBP"
  ) {
    mimeType = "image/webp";
    result = webp(bytes);
  } else return invalid();
  if (image.mimeType !== mimeType) invalid();
  return { bytes, mimeType, width: result[0], height: result[1] };
}
const alphabet =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
export function previewImageDataUri(image: CheckedPreviewImage): string {
  const chunks: string[] = [];
  for (let start = 0; start < image.bytes.length; start += 12288) {
    const parts: string[] = [],
      end = Math.min(image.bytes.length, start + 12288);
    for (let p = start; p < end; p += 3) {
      const a = image.bytes[p],
        hasB = p + 1 < end,
        hasC = p + 2 < end,
        b = hasB ? image.bytes[p + 1] : 0,
        c = hasC ? image.bytes[p + 2] : 0;
      parts.push(
        alphabet[a >>> 2],
        alphabet[((a & 3) << 4) | (b >>> 4)],
        hasB ? alphabet[((b & 15) << 2) | (c >>> 6)] : "=",
        hasC ? alphabet[c & 63] : "=",
      );
    }
    chunks.push(parts.join(""));
  }
  return `data:${image.mimeType};base64,${chunks.join("")}`;
}
