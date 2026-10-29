import assert from "node:assert/strict";
import test from "node:test";
import { deflateSync, constants } from "node:zlib";
import { previewImageFixtures } from "./previewImageFixtures";
import {
  checkPreviewImage,
  previewImageDataUri,
  PREVIEW_IMAGE_BYTES,
  PREVIEW_TOTAL_IMAGE_BYTES,
} from "./previewImagePreflight";
import { validatePreviewInflate } from "./previewImageInflate";
import { PreviewRuntimeAdapter } from "./preview";
import { PreviewSession } from "../full/PreviewSession";
import { fullTemplates } from "../full/catalog";
import type { PickedImage } from "./types";
const spec = fullTemplates.find(
  (template) => template.id === "photoJournal",
)!.spec;
const sample = () => new PreviewRuntimeAdapter(spec);
const picked = (
  bytes: Uint8Array,
  mimeType: PickedImage["mimeType"] = "image/png",
): PickedImage => ({ bytes, mimeType, name: "local-only-example" });
const rejected = (error: unknown) =>
  (error as { code?: string }).code === "invalid_preview_image";
const budgetRejected = (error: unknown) =>
  (error as { code?: string }).code === "preview_image_budget";
function crc(bytes: Uint8Array) {
  let result = 0xffffffff;
  for (const byte of bytes) {
    result ^= byte;
    for (let n = 0; n < 8; n++)
      result = result & 1 ? (result >>> 1) ^ 0xedb88320 : result >>> 1;
  }
  return (result ^ 0xffffffff) >>> 0;
}
function chunk(type: string, bytes: Uint8Array) {
  const result = Buffer.alloc(bytes.length + 12);
  result.writeUInt32BE(bytes.length);
  result.write(type, 4, "ascii");
  result.set(bytes, 8);
  result.writeUInt32BE(
    crc(result.subarray(4, bytes.length + 8)),
    bytes.length + 8,
  );
  return result;
}
function png(
  width = 1,
  height = 1,
  options: {
    raw?: Uint8Array;
    color?: number;
    bits?: number;
    interlace?: number;
    split?: boolean;
    palette?: Uint8Array;
    transparency?: Uint8Array;
    before?: Uint8Array[];
    after?: Uint8Array[];
    compressed?: Uint8Array;
    compression?: object;
  } = {},
) {
  const color = options.color ?? 6,
    bits = options.bits ?? 8,
    header = Buffer.alloc(13),
    channels = color === 6 ? 4 : color === 2 ? 3 : color === 4 ? 2 : 1;
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = bits;
  header[9] = color;
  header[12] = options.interlace ?? 0;
  const raw =
    options.raw ??
    Buffer.alloc(height * (1 + Math.ceil((width * bits * channels) / 8)));
  const compressed =
    options.compressed ?? deflateSync(raw, options.compression);
  const middle = Math.floor(compressed.length / 2);
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    ...(options.palette ? [chunk("PLTE", options.palette)] : []),
    ...(options.transparency ? [chunk("tRNS", options.transparency)] : []),
    ...(options.before ?? []),
    ...(options.split
      ? [
          chunk("IDAT", compressed.subarray(0, middle)),
          chunk("IDAT", compressed.subarray(middle)),
        ]
      : [chunk("IDAT", compressed)]),
    ...(options.after ?? []),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}
const fixture = (name: string) =>
  Buffer.from(
    previewImageFixtures.find((value) => value.name === name)!.base64,
    "base64",
  );
function riff(chunks: Uint8Array[]) {
  const result = Buffer.concat([
    Buffer.from("RIFF0000WEBP", "ascii"),
    ...chunks,
  ]);
  result.writeUInt32LE(result.length - 8, 4);
  return result;
}
function webpChunk(type: string, bytes: Uint8Array) {
  const result = Buffer.alloc(8 + bytes.length + (bytes.length & 1));
  result.write(type);
  result.writeUInt32LE(bytes.length, 4);
  result.set(bytes, 8);
  return result;
}
function padJpeg(target: number) {
  const source = fixture("dart_jpeg_quality_100"),
    parts: Buffer[] = [source.subarray(0, 2)];
  let remaining = target - source.length;
  while (remaining) {
    let size = Math.min(65537, remaining);
    if (remaining > size && remaining - size < 4) size -= 4;
    assert.ok(size >= 4);
    const segment = Buffer.alloc(size);
    segment[0] = 255;
    segment[1] = 254;
    segment.writeUInt16BE(size - 2, 2);
    parts.push(segment);
    remaining -= size;
  }
  parts.push(source.subarray(2));
  return Buffer.concat(parts);
}
function segment(data: Buffer, marker: number) {
  let p = 2;
  while (p + 4 <= data.length) {
    assert.equal(data[p], 255);
    if (data[p + 1] === marker) return p + 4;
    const length = data.readUInt16BE(p + 2);
    p += length + 2;
  }
  throw Error("fixture marker unavailable");
}
for (const vector of previewImageFixtures)
  test(`exact memory roundtrip: ${vector.name}`, async () => {
    const adapter = sample(),
      original = Buffer.from(vector.base64, "base64"),
      input = Uint8Array.from(original);
    try {
      assert.equal(adapter.features.has("imageUpload"), true);
      const id = await adapter.uploadImage(picked(input, vector.mimeType));
      assert.match(id, /^preview_memory_\d+_\d+$/);
      input.fill(0);
      const result = await adapter.readImage(id);
      assert.equal(result.width, vector.width);
      assert.equal(result.height, vector.height);
      assert.ok(result.uri.startsWith(`data:${vector.mimeType};base64,`));
      assert.deepEqual(
        Buffer.from(result.uri.split(",")[1], "base64"),
        original,
      );
      assert.notEqual(
        result.uri,
        (await adapter.readImage("preview_image_0")).uri,
      );
    } finally {
      adapter.dispose();
    }
  });

test("PNG palette/low-bit/16-bit/Adam7 and stored/fixed/dynamic DEFLATE layouts remain accepted", () => {
  const interlaced: number[] = [];
  for (const [x, y, dx, dy] of [
    [0, 0, 8, 8],
    [4, 0, 8, 8],
    [0, 4, 4, 8],
    [2, 0, 4, 4],
    [0, 2, 2, 4],
    [1, 0, 2, 2],
    [0, 1, 1, 2],
  ])
    for (let row = y; row < 8; row += dy) {
      interlaced.push(0);
      for (let col = x; col < 8; col += dx) interlaced.push(190, 80, 30, 255);
    }
  const vectors = [
    png(1, 1, {
      color: 3,
      bits: 1,
      raw: Buffer.from([0, 0]),
      palette: Buffer.from([190, 80, 30]),
      transparency: Buffer.from([120]),
    }),
    png(1, 1, { color: 0, bits: 1, raw: Buffer.from([0, 128]) }),
    png(1, 1, {
      bits: 16,
      raw: Buffer.from([0, 255, 255, 0, 0, 0, 0, 128, 128]),
    }),
    png(8, 8, { interlace: 1, raw: Buffer.from(interlaced) }),
    png(1, 1, { split: true }),
    png(1, 1, { compression: { level: 0 } }),
    png(1, 1, { compression: { strategy: constants.Z_FIXED } }),
  ];
  for (const bytes of vectors)
    assert.deepEqual(
      checkPreviewImage(picked(bytes)).bytes,
      Uint8Array.from(bytes),
    );
  const raw = Buffer.from("bounded dynamic payload".repeat(1000));
  for (const options of [{}, { level: 0 }, { strategy: constants.Z_FIXED }])
    validatePreviewInflate(deflateSync(raw, options), raw.length);
});

test("PNG expansion bombs, truncation, bad checksums, filters, dictionary and trailing compressed input never succeed", async () => {
  const base = Buffer.from(deflateSync(Buffer.alloc(5))),
    checksum = Buffer.from(base);
  checksum[checksum.length - 1] ^= 1;
  const dictionary = Buffer.from(base);
  dictionary[1] = 32;
  while (((dictionary[0] << 8) | dictionary[1]) % 31) dictionary[1]++;
  const malformed = [
    png(1, 1, { raw: Buffer.alloc(65536) }),
    png(1, 1, { raw: Buffer.alloc(65536), split: true }),
    png(1, 1, { raw: Buffer.from([0, 255]) }),
    png(1, 1, { raw: Buffer.from([5, 0, 0, 0, 0]) }),
    png(1, 1, { compressed: base.subarray(0, -1) }),
    png(1, 1, { compressed: checksum }),
    png(1, 1, { compressed: dictionary }),
    png(1, 1, { compressed: Buffer.concat([base, Buffer.from([0])]) }),
  ];
  const corruptCrc = png();
  corruptCrc[corruptCrc.length - 1] ^= 1;
  malformed.push(corruptCrc);
  const adapter = sample();
  try {
    for (const bytes of malformed)
      await assert.rejects(adapter.uploadImage(picked(bytes)), rejected);
    await assert.rejects(
      adapter.readImage("preview_memory_1_1"),
      (error) => (error as { code?: string }).code === "not_found",
    );
  } finally {
    adapter.dispose();
  }
});

test("DEFLATE rejects reserved blocks, invalid stored lengths, truncated streams and declared-size mismatch", () => {
  for (const bytes of [
    Buffer.from([0x78, 0x9c, 7, 0, 0, 0, 1]),
    Buffer.from([0x78, 0x01, 1, 1, 0, 1, 0, 0, 0, 0, 1]),
    Buffer.from([0x78, 0x9c]),
    Buffer.from(deflateSync(Buffer.from("sample"))).subarray(0, -2),
  ])
    assert.throws(() => validatePreviewInflate(bytes, 5));
  const bytes = deflateSync(Buffer.from("sixsix"));
  assert.throws(() => validatePreviewInflate(bytes, 5));
  assert.throws(() => validatePreviewInflate(bytes, 7));
});

test("PNG animation, critical/metadata bombs, duplicate IHDR and noncontiguous IDAT reject; retained text is not claimed stripped", async () => {
  const ordinary = png(),
    ihdr = ordinary.subarray(8, 33),
    compressed = deflateSync(Buffer.alloc(5));
  const invalid = [
    png(1, 1, { before: [chunk("acTL", Buffer.alloc(8))] }),
    png(1, 1, { before: [chunk("fcTL", Buffer.alloc(26))] }),
    png(1, 1, { before: [chunk("fdAT", Buffer.alloc(4))] }),
    png(1, 1, { before: [chunk("iCCP", Buffer.from("compressed bomb"))] }),
    png(1, 1, { before: [chunk("eXIf", Buffer.alloc(26))] }),
    png(1, 1, { before: [chunk("zTXt", Buffer.alloc(10))] }),
    png(1, 1, { before: [ihdr] }),
    png(1, 1, { before: [chunk("ABCD", Buffer.alloc(0))] }),
    png(1, 1, {
      compressed: compressed.subarray(0, 3),
      after: [
        chunk("tEXt", Buffer.from("key\0value")),
        chunk("IDAT", compressed.subarray(3)),
      ],
    }),
  ];
  for (const bytes of invalid)
    assert.throws(() => checkPreviewImage(picked(bytes)), rejected);
  const text = Buffer.from("private\0retained original metadata"),
    source = png(1, 1, { before: [chunk("tEXt", text)] }),
    adapter = sample();
  try {
    const id = await adapter.uploadImage(picked(source)),
      result = await adapter.readImage(id);
    assert.ok(Buffer.from(result.uri.split(",")[1], "base64").includes(text));
  } finally {
    adapter.dispose();
  }
});

test("JPEG frame bombs, malformed tables/scans and original EXIF/ICC containers are rejected before data URI exposure", () => {
  const original = fixture("dart_jpeg_quality_100"),
    frame = segment(original, 192),
    table = segment(original, 196),
    scan = segment(original, 218),
    quantization = segment(original, 219);
  const mutations: Buffer[] = [];
  for (const [offset, value] of [
    [frame + 1, 65535],
    [frame + 3, 8193],
  ]) {
    const b = Buffer.from(original);
    b.writeUInt16BE(value, offset);
    mutations.push(b);
  }
  const precision = Buffer.from(original);
  precision[frame] = 12;
  mutations.push(precision);
  const excessive = Buffer.from(original);
  excessive[frame + 7] = 0x44;
  mutations.push(excessive);
  const hidden = Buffer.from(original);
  hidden[table + 17] = 255;
  hidden[table + 18] = 225;
  mutations.push(hidden);
  const absentQuant = Buffer.from(original);
  absentQuant[quantization + 1] = 0;
  mutations.push(absentQuant);
  const unknownScan = Buffer.from(original);
  unknownScan[scan + 1] = 99;
  mutations.push(unknownScan);
  mutations.push(
    original.subarray(0, -2),
    Buffer.concat([original, Buffer.from([0])]),
    Buffer.concat([
      original.subarray(0, 2),
      Buffer.from([255, 225, 0, 8, 69, 120, 105, 102, 0, 0]),
      original.subarray(2),
    ]),
    Buffer.concat([
      original.subarray(0, 2),
      Buffer.from([255, 226, 0, 4, 0, 0]),
      original.subarray(2),
    ]),
  );
  for (const bytes of mutations)
    assert.throws(
      () => checkPreviewImage(picked(bytes, "image/jpeg")),
      rejected,
    );
});

test("WebP animation, duplicate streams, huge/inconsistent canvases, scale fields, malformed RIFF and EXIF/ICC reject", () => {
  const original = fixture("webp_lossless"),
    stream = original.subarray(12),
    vp8 = fixture("webp_lossy"),
    wrongSize = Buffer.from(original);
  wrongSize.writeUInt32LE(1, 4);
  const scaled = Buffer.from(vp8);
  scaled[27] |= 0xc0;
  const invalid = [
    riff([
      webpChunk("VP8X", Buffer.from([2, 0, 0, 0, 0, 0, 0, 0, 0, 0])),
      webpChunk("ANMF", Buffer.alloc(16)),
      stream,
    ]),
    riff([stream, stream]),
    riff([
      webpChunk("VP8X", Buffer.from([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])),
      stream,
    ]),
    riff([
      webpChunk(
        "VP8X",
        Buffer.from([0, 0, 0, 0, 255, 255, 255, 255, 255, 255]),
      ),
      stream,
    ]),
    riff([stream, webpChunk("EXIF", Buffer.alloc(26))]),
    riff([stream, webpChunk("ICCP", Buffer.alloc(10))]),
    wrongSize,
    scaled,
    original.subarray(0, -1),
  ];
  for (const bytes of invalid)
    assert.throws(
      () => checkPreviewImage(picked(bytes, "image/webp")),
      rejected,
    );
});

test("empty/unsupported/mismatched MIME/shared/oversized inputs fail without allocating an image ID", async () => {
  const adapter = sample(),
    good = png();
  try {
    for (const bytes of [
      Buffer.alloc(0),
      Buffer.from("<svg/>"),
      Buffer.from("GIF89a"),
      Buffer.alloc(PREVIEW_IMAGE_BYTES + 1),
      new Uint8Array(new SharedArrayBuffer(10)),
    ])
      await assert.rejects(adapter.uploadImage(picked(bytes)), rejected);
    await assert.rejects(
      adapter.uploadImage(picked(good, "image/jpeg")),
      rejected,
    );
    const id = await adapter.uploadImage(picked(good));
    assert.ok(id.endsWith("_1"));
  } finally {
    adapter.dispose();
  }
});

test("per-image side/pixel and aggregate16MP/16asset caps are enforced", async () => {
  assert.throws(
    () => checkPreviewImage(picked(png(8193, 1, { color: 0, bits: 1 }))),
    rejected,
  );
  assert.throws(
    () => checkPreviewImage(picked(png(8192, 1954, { color: 0, bits: 1 }))),
    rejected,
  );
  assert.equal(
    checkPreviewImage(picked(png(8192, 1, { color: 0, bits: 1 }))).width,
    8192,
  );
  const pixels = sample(),
    count = sample();
  try {
    await pixels.uploadImage(picked(png(4000, 4000, { color: 0, bits: 1 })));
    await assert.rejects(pixels.uploadImage(picked(png())), budgetRejected);
    for (let i = 0; i < 16; i++) await count.uploadImage(picked(png()));
    await assert.rejects(count.uploadImage(picked(png())), budgetRejected);
  } finally {
    pixels.dispose();
    count.dispose();
  }
});

test("5MiB original cap and aggregate8MiB retained bytes accept exact boundaries and reject overflow", async () => {
  const adapter = sample();
  try {
    const first = padJpeg(PREVIEW_IMAGE_BYTES),
      second = padJpeg(PREVIEW_TOTAL_IMAGE_BYTES - PREVIEW_IMAGE_BYTES);
    await adapter.uploadImage(picked(first, "image/jpeg"));
    await adapter.uploadImage(picked(second, "image/jpeg"));
    await assert.rejects(adapter.uploadImage(picked(png())), budgetRejected);
  } finally {
    adapter.dispose();
  }
});

test("memory IDs/images survive presentation updates but disposal and semantic reset clear them without picker/network/storage", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    throw Error("unexpected preview request");
  };
  const session = new PreviewSession(spec),
    initial = session.getSnapshot().session.controller
      .adapter as PreviewRuntimeAdapter;
  try {
    const bytes = png(),
      id = await initial.uploadImage(picked(bytes));
    session.update({ ...spec, name: "Presentation-only title" });
    assert.equal(session.getSnapshot().session.controller.adapter, initial);
    assert.deepEqual(
      Buffer.from((await initial.readImage(id)).uri.split(",")[1], "base64"),
      bytes,
    );
    const semantic = structuredClone(spec);
    semantic.collections[0].fields[0].required =
      !semantic.collections[0].fields[0].required;
    session.update(semantic);
    const next = session.getSnapshot().session.controller.adapter;
    await assert.rejects(
      next.readImage(id),
      (error) => (error as { code?: string }).code === "not_found",
    );
    const nextId = await next.uploadImage(picked(bytes));
    assert.notEqual(nextId, id);
    await assert.rejects(
      next.pickImage(),
      (error) => (error as { code?: string }).code === "unavailable",
    );
    assert.equal(calls, 0);
    session.dispose();
    await assert.rejects(
      next.readImage(nextId),
      (error) => (error as { code?: string }).code === "disposed",
    );
    await assert.rejects(
      next.uploadImage(picked(bytes)),
      (error) => (error as { code?: string }).code === "disposed",
    );
  } finally {
    session.dispose();
    globalThis.fetch = originalFetch;
  }
});

test("base64 roundtrip preserves every byte and padding for all tail sizes", () => {
  for (const size of [1, 2, 3, 4, 12287, 12288, 12289, 25000]) {
    const bytes = Uint8Array.from({ length: size }, (_, n) => (n * 29) & 255);
    const uri = previewImageDataUri({
      bytes,
      mimeType: "image/png",
      width: 1,
      height: 1,
    });
    assert.deepEqual(
      Buffer.from(uri.split(",")[1], "base64"),
      Buffer.from(bytes),
    );
  }
});

test("pure DEFLATE matches independent zlib output across windows, strategies and block sizes", () => {
  for (const length of [0, 1, 2, 31, 1024, 32769, 131072]) {
    let seed = 19;
    const raw = Buffer.alloc(length);
    for (let n = 0; n < length; n++) {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
      raw[n] = n % 3 === 0 ? seed >>> 24 : n & 31;
    }
    for (const options of [
      { level: 0 },
      { level: 1 },
      { level: 6 },
      { level: 9, strategy: constants.Z_FIXED },
      { strategy: constants.Z_HUFFMAN_ONLY },
      { strategy: constants.Z_RLE },
    ]) {
      const actual: number[] = [];
      validatePreviewInflate(
        deflateSync(raw, options),
        raw.length,
        (_position, value) => actual.push(value),
      );
      assert.deepEqual(Buffer.from(actual), raw);
    }
  }
});
