import { ensure } from "./errors";
const invalid = () =>
  ensure(false, "invalid_preview_image", "Choose a valid bounded still image.");
interface Tree {
  readonly codes: ReadonlyMap<number, number>[];
  readonly maximum: number;
}
function tree(
  lengths: readonly number[],
  maximum = 15,
  allowEmpty = false,
): Tree {
  const counts = new Array(maximum + 1).fill(0),
    codes = Array.from(
      { length: maximum + 1 },
      () => new Map<number, number>(),
    );
  for (const length of lengths) {
    if (!Number.isInteger(length) || length < 0 || length > maximum) invalid();
    counts[length]++;
  }
  const symbols = lengths.length - counts[0];
  if (!symbols) {
    if (!allowEmpty) invalid();
    return { codes, maximum: 0 };
  }
  let remaining = 1,
    code = 0,
    longest = 0;
  const next = new Array(maximum + 1).fill(0);
  for (let bits = 1; bits <= maximum; bits++) {
    remaining = remaining * 2 - counts[bits];
    if (remaining < 0) invalid();
    code = (code + (counts[bits - 1] ?? 0) * (bits === 1 ? 0 : 1)) * 2;
    next[bits] = code;
    if (counts[bits]) longest = bits;
  }
  if (remaining && !(symbols === 1 && longest === 1)) invalid();
  lengths.forEach((length, symbol) => {
    if (!length) return;
    let normal = next[length]++,
      reversed = 0;
    for (let n = 0; n < length; n++) {
      reversed = reversed * 2 + (normal & 1);
      normal >>>= 1;
    }
    codes[length].set(reversed, symbol);
  });
  return { codes, maximum: longest };
}
const lengthBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67,
  83, 99, 115, 131, 163, 195, 227, 258,
];
const lengthExtra = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5,
  5, 5, 0,
];
const distanceBase = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
];
const distanceExtra = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11,
  11, 12, 12, 13, 13,
];
const fixedLiteral = tree(
  Array.from({ length: 288 }, (_, n) =>
    n < 144 ? 8 : n < 256 ? 9 : n < 280 ? 7 : 8,
  ),
);
const fixedDistance = tree(new Array(32).fill(5));
/** Bounded zlib/DEFLATE validation: only a 32KiB history is retained, never the raster. */
export function validatePreviewInflate(
  input: Uint8Array,
  expected: number,
  onByte?: (position: number, value: number) => void,
): void {
  if (
    !Number.isSafeInteger(expected) ||
    expected < 0 ||
    expected > 128_016_384 ||
    input.length > 5 * 1024 * 1024 ||
    input.length < 6 ||
    (input[0] & 15) !== 8 ||
    input[0] >>> 4 > 7 ||
    ((input[0] << 8) | input[1]) % 31 ||
    input[1] & 32
  )
    invalid();
  const end = input.length - 4,
    window = 1 << ((input[0] >>> 4) + 8),
    history = new Uint8Array(32768);
  let position = 2,
    bits = 0,
    available = 0,
    count = 0,
    first = 1,
    second = 0,
    batch = 0;
  const read = (number: number) => {
    while (available < number) {
      if (position >= end) invalid();
      bits |= input[position++] << available;
      available += 8;
    }
    const value = bits & ((1 << number) - 1);
    bits >>>= number;
    available -= number;
    return value;
  };
  const symbol = (table: Tree) => {
    let value = 0;
    for (let length = 1; length <= table.maximum; length++) {
      value |= read(1) << (length - 1);
      const found = table.codes[length].get(value);
      if (found !== undefined) return found;
    }
    return invalid() as never;
  };
  const emit = (value: number) => {
    if (count >= expected) invalid();
    onByte?.(count, value);
    history[count++ & 32767] = value;
    first += value;
    second += first;
    if (++batch === 5552) {
      first %= 65521;
      second %= 65521;
      batch = 0;
    }
  };
  let final = 0,
    blocks = 0;
  while (!final) {
    if (++blocks > 65536) invalid();
    final = read(1);
    const kind = read(2);
    if (kind === 0) {
      available = 0;
      bits = 0;
      const length = read(16),
        inverse = read(16);
      if ((length ^ inverse) !== 65535) invalid();
      for (let n = 0; n < length; n++) emit(read(8));
      continue;
    }
    if (kind === 3) invalid();
    let literal = fixedLiteral,
      distance = fixedDistance;
    if (kind === 2) {
      const literalCount = read(5) + 257,
        distanceCount = read(5) + 1,
        count = read(4) + 4;
      if (literalCount > 286) invalid();
      const order = [
          16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
        ],
        lengths = new Array(19).fill(0);
      for (let n = 0; n < count; n++) lengths[order[n]] = read(3);
      const description = tree(lengths, 7),
        decoded: number[] = [];
      while (decoded.length < literalCount + distanceCount) {
        const value = symbol(description);
        if (value < 16) decoded.push(value);
        else {
          if (value === 16 && !decoded.length) invalid();
          const repeats =
            value === 16
              ? read(2) + 3
              : value === 17
                ? read(3) + 3
                : read(7) + 11;
          const repeated = value === 16 ? decoded[decoded.length - 1] : 0;
          if (decoded.length + repeats > literalCount + distanceCount)
            invalid();
          for (let n = 0; n < repeats; n++) decoded.push(repeated);
        }
      }
      if (!decoded[256]) invalid();
      literal = tree(decoded.slice(0, literalCount));
      distance = tree(decoded.slice(literalCount), 15, true);
    }
    while (true) {
      const value = symbol(literal);
      if (value < 256) {
        emit(value);
        continue;
      }
      if (value === 256) break;
      if (value > 285) invalid();
      const length = lengthBase[value - 257] + read(lengthExtra[value - 257]),
        code = symbol(distance);
      if (code > 29) invalid();
      const backwards = distanceBase[code] + read(distanceExtra[code]);
      if (backwards > count || backwards > window) invalid();
      for (let n = 0; n < length; n++)
        emit(history[(count - backwards) & 32767]);
    }
  }
  const checksum = ((first % 65521) | ((second % 65521) << 16)) >>> 0;
  const supplied = new DataView(
    input.buffer,
    input.byteOffset + end,
    4,
  ).getUint32(0);
  if (count !== expected || position !== end || checksum !== supplied)
    invalid();
}
