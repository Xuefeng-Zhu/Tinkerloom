/** Deterministic synthetic bytes only; no I/O, credentials or network. */
import { createHash } from "node:crypto";
import { inflateSync } from "node:zlib";
export const MAX_BYTES = 5 * 1024 * 1024;
export const CHUNK_BYTES = 256 * 1024;
export const PNG_METADATA_MARKER =
  "Tinkerloom synthetic PNG metadata must be stripped";
export const byteSha = (value) =>
  createHash("sha256").update(value).digest("hex");
const crcTable = Array.from({ length: 256 }, (_, n) => {
  for (let i = 0; i < 8; i++) n = n & 1 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
  return n >>> 0;
});
export function crc32(bytes) {
  let crc = 0xffffffff;
  for (const value of bytes) crc = crcTable[(crc ^ value) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
export function pngChunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length);
  out.write(type, 4, 4, "ascii");
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, -4)), out.length - 4);
  return out;
}
// One uncompressed DEFLATE block avoids platform/zlib-version variance in the
// original's exact SHA. The source pixels are tiny; PNG padding supplies 5 MiB.
function storedZlib(bytes) {
  if (bytes.length > 65535) throw new Error("synthetic_deflate_bound");
  const out = Buffer.alloc(bytes.length + 11);
  out[0] = 0x78;
  out[1] = 0x01;
  out[2] = 0x01;
  out.writeUInt16LE(bytes.length, 3);
  out.writeUInt16LE(~bytes.length & 65535, 5);
  bytes.copy(out, 7);
  let a = 1,
    b = 0;
  for (const value of bytes) {
    a = (a + value) % 65521;
    b = (b + a) % 65521;
  }
  out.writeUInt32BE(((b << 16) | a) >>> 0, out.length - 4);
  return out;
}
export function maximumSyntheticPng() {
  const width = 16,
    height = 8,
    pixels = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++)
    for (let x = 0; x < width; x++) {
      const at = (y * width + x) * 4;
      pixels.set(
        [
          x * 13,
          y * 29,
          (x * 17 + y * 11) % 256,
          x === 0 && y === 0 ? 128 : 255,
        ],
        at,
      );
    }
  const scanlines = Buffer.alloc(height * (1 + width * 4));
  for (let y = 0; y < height; y++)
    pixels.copy(
      scanlines,
      y * (1 + width * 4) + 1,
      y * width * 4,
      (y + 1) * width * 4,
    );
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const pieces = [
    Buffer.from("89504e470d0a1a0a", "hex"),
    pngChunk("IHDR", header),
    pngChunk("tEXt", Buffer.from(`Comment\0${PNG_METADATA_MARKER}`)),
    pngChunk("IDAT", storedZlib(scanlines)),
    pngChunk("IEND", Buffer.alloc(0)),
  ];
  const paddingBytes =
    MAX_BYTES - pieces.reduce((n, p) => n + p.length, 0) - 12;
  const padding = Buffer.alloc(paddingBytes);
  for (let i = 0; i < padding.length; i++) padding[i] = (i * 73 + 19) & 255;
  pieces.splice(-1, 0, pngChunk("npAd", padding));
  const bytes = Buffer.concat(pieces);
  return {
    bytes,
    width,
    height,
    pixels,
    sha256: byteSha(bytes),
    contentType: "image/png",
    chunks: 20,
  };
}
const paeth = (a, b, c) => {
  const p = a + b - c,
    pa = Math.abs(p - a),
    pb = Math.abs(p - b),
    pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
};
/** Small sanitized PNG verifier: CRC, exact end, still 8-bit RGBA/RGB and pixels. */
export function decodeSyntheticPng(bytes, { maximum = MAX_BYTES } = {}) {
  if (
    !Buffer.isBuffer(bytes) ||
    bytes.length > maximum ||
    !bytes.subarray(0, 8).equals(Buffer.from("89504e470d0a1a0a", "hex"))
  )
    throw new Error("invalid_png");
  let at = 8,
    width,
    height,
    channels,
    ended = false;
  const types = [],
    data = [];
  while (at + 12 <= bytes.length) {
    const size = bytes.readUInt32BE(at),
      end = at + 12 + size;
    if (end > bytes.length || types.length > 4096)
      throw new Error("invalid_png");
    const type = bytes.toString("ascii", at + 4, at + 8),
      body = bytes.subarray(at + 8, end - 4);
    if (crc32(bytes.subarray(at + 4, end - 4)) !== bytes.readUInt32BE(end - 4))
      throw new Error("invalid_png_crc");
    if (!types.length && type !== "IHDR") throw new Error("invalid_png_header");
    types.push(type);
    if (type === "IHDR") {
      if (
        width !== undefined ||
        size !== 13 ||
        body[8] !== 8 ||
        ![2, 6].includes(body[9]) ||
        body[10] ||
        body[11] ||
        body[12]
      )
        throw new Error("unsupported_png");
      width = body.readUInt32BE();
      height = body.readUInt32BE(4);
      channels = body[9] === 6 ? 4 : 3;
      if (width < 1 || height < 1 || width * height > 16000000)
        throw new Error("invalid_png_dimensions");
    } else if (type === "IDAT") data.push(body);
    else if (type === "IEND") {
      if (size || end !== bytes.length) throw new Error("invalid_png_end");
      ended = true;
    }
    if (["acTL", "fcTL", "fdAT"].includes(type))
      throw new Error("animated_png");
    at = end;
  }
  if (!ended || at !== bytes.length || !data.length)
    throw new Error("invalid_png_end");
  const stride = width * channels,
    expected = height * (stride + 1);
  const raw = inflateSync(Buffer.concat(data), { maxOutputLength: expected });
  if (raw.length !== expected) throw new Error("invalid_png_pixels");
  const pixels = Buffer.alloc(width * height * channels);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    if (filter > 4) throw new Error("unsupported_png_filter");
    for (let x = 0; x < stride; x++) {
      const out = y * stride + x,
        value = raw[y * (stride + 1) + 1 + x],
        a = x < channels ? 0 : pixels[out - channels],
        b = y ? pixels[out - stride] : 0,
        c = y && x >= channels ? pixels[out - stride - channels] : 0;
      pixels[out] =
        (value + [0, a, b, Math.floor((a + b) / 2), paeth(a, b, c)][filter]) &
        255;
    }
  }
  return { width, height, channels, pixels, types };
}
