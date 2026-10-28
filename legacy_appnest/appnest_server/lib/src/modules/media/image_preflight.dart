import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appnest_spec/appnest_spec.dart';

enum StillImageFormat { jpeg, png, webp }

class CheckedImage {
  final Uint8List bytes;
  final StillImageFormat format;
  final int width, height;
  final int orientation;
  const CheckedImage(
    this.bytes,
    this.format,
    this.width,
    this.height, {
    this.orientation = 1,
  });
}

Never _invalid() => throw const SpecException(
  'Choose a valid still JPEG, PNG or WebP image no larger than 16 megapixels.',
);

void _dimensions(int width, int height) {
  if (width < 1 ||
      height < 1 ||
      width > 8192 ||
      height > 8192 ||
      width * height > 16000000) {
    _invalid();
  }
}

/// Inspects the actual allocation headers before calling a third-party decoder.
/// PNG compressed output is counted incrementally, without retaining it.
CheckedImage checkImageInput(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    return _jpeg(bytes);
  }
  if (bytes.length >= 8 &&
      _equal(bytes, 0, const [137, 80, 78, 71, 13, 10, 26, 10])) {
    return _png(bytes);
  }
  if (bytes.length >= 12 &&
      _tag(bytes, 0) == 'RIFF' &&
      _tag(bytes, 8) == 'WEBP') {
    return _webp(bytes);
  }
  _invalid();
}

bool _equal(Uint8List b, int p, List<int> value) {
  for (var i = 0; i < value.length; i++) {
    if (b[p + i] != value[i]) return false;
  }
  return true;
}

String _tag(Uint8List b, int p) => String.fromCharCodes(b.sublist(p, p + 4));
int _be16(Uint8List b, int p) => (b[p] << 8) | b[p + 1];
int _le24(Uint8List b, int p) => b[p] | (b[p + 1] << 8) | (b[p + 2] << 16);
int _u32(Uint8List b, int p, Endian endian) =>
    ByteData.sublistView(b, p, p + 4).getUint32(0, endian);

CheckedImage _jpeg(Uint8List b) {
  var p = 2;
  var inScan = false, sawScan = false;
  int? width, height;
  final components = <int>{};
  final clean = BytesBuilder(copy: false)..add(const [0xff, 0xd8]);
  var orientation = 1;
  while (p < b.length) {
    final segmentStart = p;
    // Entropy bytes may contain stuffed FF00 and standalone restart markers.
    if (inScan) {
      while (p < b.length && b[p] != 0xff) {
        p++;
      }
    }
    if (p >= b.length || b[p++] != 0xff) _invalid();
    while (p < b.length && b[p] == 0xff) {
      p++;
    }
    if (p >= b.length) _invalid();
    final marker = b[p++];
    if (marker == 0xd9) {
      if (width == null || height == null || !sawScan) _invalid();
      clean.add(Uint8List.sublistView(b, segmentStart, p));
      final pixels = clean.takeBytes();
      final normalized = BytesBuilder(copy: false)
        ..add(const [0xff, 0xd8])
        ..add(_orientationExif(orientation))
        ..add(Uint8List.sublistView(pixels, 2));
      return CheckedImage(
        normalized.takeBytes(),
        StillImageFormat.jpeg,
        width,
        height,
      );
    }
    if (marker == 0 && inScan ||
        marker == 1 ||
        (marker >= 0xd0 && marker <= 0xd7)) {
      clean.add(Uint8List.sublistView(b, segmentStart, p));
      continue;
    }
    if (marker < 0xc0 || marker == 0xd8 || p + 2 > b.length) _invalid();
    final length = _be16(b, p);
    if (length < 2 || p + length > b.length) _invalid();
    final end = p + length;
    final data = p + 2;
    if (marker == 0xe1) {
      orientation =
          _exifOrientation(Uint8List.sublistView(b, data, end)) ?? orientation;
    }
    final isFrame =
        marker >= 0xc0 &&
        marker <= 0xcf &&
        !{0xc4, 0xc8, 0xcc}.contains(marker);
    if (isFrame) {
      if (!{0xc0, 0xc1, 0xc2}.contains(marker) || width != null || length < 8) {
        _invalid();
      }
      final count = b[data + 5];
      if (b[data] != 8 ||
          !{1, 3, 4}.contains(count) ||
          length != 8 + count * 3) {
        _invalid();
      }
      height = _be16(b, data + 1);
      width = _be16(b, data + 3);
      _dimensions(width, height);
      var samples = 0;
      for (var i = 0; i < count; i++) {
        final c = data + 6 + i * 3;
        final h = b[c + 1] >> 4, v = b[c + 1] & 15;
        if (!components.add(b[c]) ||
            h < 1 ||
            h > 4 ||
            v < 1 ||
            v > 4 ||
            b[c + 2] > 3) {
          _invalid();
        }
        samples += h * v;
      }
      if (samples > 10) _invalid();
    } else if (marker == 0xda) {
      if (width == null || length < 6) _invalid();
      final count = b[data];
      if (count < 1 || count > components.length || length != 6 + count * 2) {
        _invalid();
      }
      final selected = <int>{};
      for (var i = 0; i < count; i++) {
        final id = b[data + 1 + i * 2], tables = b[data + 2 + i * 2];
        if (!components.contains(id) ||
            !selected.add(id) ||
            tables >> 4 > 3 ||
            tables & 15 > 3) {
          _invalid();
        }
      }
      sawScan = inScan = true;
    } else if (marker == 0xdc) {
      // Decoder dimensions must never be changed after frame preflight.
      _invalid();
    }
    final metadata = marker >= 0xe0 && marker <= 0xef || marker == 0xfe;
    // Keep only the fixed Adobe transform marker needed by CMYK decoding.
    // Never pass original EXIF/ICC/JFIF thumbnails to the metadata parsers.
    final adobe =
        marker == 0xee &&
        length == 14 &&
        _equal(b, data, const [65, 100, 111, 98, 101]);
    if (marker == 0xdb) {
      // Equivalent 16-bit tables prevent ordinary FFxx quantization values
      // from becoming metadata markers if a malformed scan resynchronizes.
      var markerStart = p - 2;
      while (markerStart > segmentStart && b[markerStart - 1] == 0xff) {
        markerStart--;
      }
      clean.add(Uint8List.sublistView(b, segmentStart, markerStart));
      clean.add(_normalizedQuantization(Uint8List.sublistView(b, data, end)));
    } else if (!metadata || adobe) {
      // Malformed scans can make the decoder resynchronize inside a table.
      // Such bytes must not introduce an unchecked allocation/EXIF marker.
      for (var i = data; i + 1 < end; i++) {
        if (b[i] == 0xff && {0xc0, 0xc1, 0xc2, 0xe1}.contains(b[i + 1])) {
          _invalid();
        }
      }
      clean.add(Uint8List.sublistView(b, segmentStart, end));
    } else if (inScan) {
      // Preserve entropy preceding a stripped metadata segment, excluding FF fill.
      var markerStart = p - 2;
      while (markerStart > segmentStart && b[markerStart - 1] == 0xff) {
        markerStart--;
      }
      clean.add(Uint8List.sublistView(b, segmentStart, markerStart));
    }
    p = end;
  }
  _invalid();
}

Uint8List _normalizedQuantization(Uint8List b) {
  var p = 0;
  final normalized = BytesBuilder(copy: false);
  if (b.isEmpty) _invalid();
  while (p < b.length) {
    final descriptor = b[p++], precision = descriptor >> 4;
    final id = descriptor & 15;
    if (precision > 1 || id > 3 || p + 64 * (precision + 1) > b.length) {
      _invalid();
    }
    final table = Uint8List(133);
    table.setAll(0, [0xff, 0xdb, 0, 131, 0x10 | id]);
    for (var i = 0; i < 64; i++) {
      final value = precision == 0 ? b[p++] : _be16(b, p);
      if (precision == 1) p += 2;
      // The pinned decoder stores quantization entries in signed Int16List.
      if (value == 0 || value > 32767) _invalid();
      table[5 + i * 2] = value >> 8;
      table[6 + i * 2] = value & 255;
    }
    normalized.add(table);
  }
  return normalized.takeBytes();
}

int? _exifOrientation(Uint8List b, {bool allowRaw = false}) {
  final prefixed =
      b.length >= 6 && _equal(b, 0, const [69, 120, 105, 102, 0, 0]);
  if (!prefixed && !allowRaw) return null;
  final start = prefixed ? 6 : 0;
  if (b.length - start < 8) return null;
  final t = ByteData.sublistView(b, start);
  final endian = b[start] == 73 && b[start + 1] == 73
      ? Endian.little
      : b[start] == 77 && b[start + 1] == 77
      ? Endian.big
      : null;
  if (endian == null || t.getUint16(2, endian) != 42) return null;
  final offset = t.getUint32(4, endian);
  if (offset < 8 || offset + 2 > t.lengthInBytes) return null;
  final count = t.getUint16(offset, endian);
  if (count > 256 || offset + 2 + count * 12 + 4 > t.lengthInBytes) return null;
  for (var i = 0; i < count; i++) {
    final p = offset + 2 + i * 12;
    if (t.getUint16(p, endian) == 0x112 &&
        t.getUint16(p + 2, endian) == 3 &&
        t.getUint32(p + 4, endian) == 1) {
      final value = t.getUint16(p + 8, endian);
      return value >= 1 && value <= 8 ? value : null;
    }
  }
  return null;
}

Uint8List _orientationExif(int orientation) => Uint8List.fromList([
  0xff,
  0xe1,
  0,
  34,
  69,
  120,
  105,
  102,
  0,
  0,
  73,
  73,
  42,
  0,
  8,
  0,
  0,
  0,
  1,
  0,
  18,
  1,
  3,
  0,
  1,
  0,
  0,
  0,
  orientation,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
]);

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var i = 0; i < 8; i++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
}, growable: false);

int _crc(Uint8List b, int start, int end) {
  var c = 0xffffffff;
  for (var i = start; i < end; i++) {
    c = _crcTable[(c ^ b[i]) & 255] ^ (c >> 8);
  }
  return c ^ 0xffffffff;
}

class _CountInflated extends ByteConversionSinkBase {
  final int expected;
  var count = 0;
  _CountInflated(this.expected);
  @override
  void add(List<int> bytes) {
    count += bytes.length;
    if (count > expected) _invalid();
  }

  @override
  void close() {
    if (count != expected) _invalid();
  }
}

int _pngInflatedSize(int width, int height, int bitsPerPixel, int interlace) {
  int pass(int x, int y, int dx, int dy) {
    final w = width <= x ? 0 : (width - x + dx - 1) ~/ dx;
    final h = height <= y ? 0 : (height - y + dy - 1) ~/ dy;
    return w == 0 || h == 0 ? 0 : h * (1 + (w * bitsPerPixel + 7) ~/ 8);
  }

  if (interlace == 0) return pass(0, 0, 1, 1);
  return pass(0, 0, 8, 8) +
      pass(4, 0, 8, 8) +
      pass(0, 4, 4, 8) +
      pass(2, 0, 4, 4) +
      pass(0, 2, 2, 4) +
      pass(1, 0, 2, 2) +
      pass(0, 1, 1, 2);
}

CheckedImage _png(Uint8List b) {
  var p = 8, chunks = 0;
  int? width, height;
  var bitsPerPixel = 0, interlace = 0, color = -1, paletteEntries = 0;
  var sawData = false,
      endedData = false,
      sawPalette = false,
      sawTransparency = false;
  final idat = <Uint8List>[];
  final clean = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
  while (p + 12 <= b.length) {
    if (++chunks > 4096) _invalid();
    final size = _u32(b, p, Endian.big);
    final end = p + 12 + size;
    if (end > b.length) _invalid();
    final type = _tag(b, p + 4), data = p + 8;
    if (_crc(b, p + 4, data + size) != _u32(b, data + size, Endian.big)) {
      _invalid();
    }
    if (width == null && type != 'IHDR') _invalid();
    if (type == 'IHDR') {
      if (width != null || size != 13) _invalid();
      width = _u32(b, data, Endian.big);
      height = _u32(b, data + 4, Endian.big);
      _dimensions(width, height);
      final bits = b[data + 8];
      color = b[data + 9];
      final depths = switch (color) {
        0 => const [1, 2, 4, 8, 16],
        2 || 4 || 6 => const [8, 16],
        3 => const [1, 2, 4, 8],
        _ => const <int>[],
      };
      if (!depths.contains(bits) ||
          b[data + 10] != 0 ||
          b[data + 11] != 0 ||
          b[data + 12] > 1) {
        _invalid();
      }
      bitsPerPixel =
          bits *
          switch (color) {
            2 => 3,
            4 => 2,
            6 => 4,
            _ => 1,
          };
      interlace = b[data + 12];
    } else if ({'acTL', 'fcTL', 'fdAT'}.contains(type)) {
      _invalid();
    } else if (type == 'PLTE') {
      if (sawPalette ||
          sawData ||
          size == 0 ||
          size > 768 ||
          size % 3 != 0 ||
          {0, 4}.contains(color)) {
        _invalid();
      }
      sawPalette = true;
      paletteEntries = size ~/ 3;
    } else if (type == 'tRNS') {
      if (sawTransparency ||
          sawData ||
          (color == 0
              ? size != 2
              : color == 2
              ? size != 6
              : color == 3
              ? !sawPalette || size < 1 || size > paletteEntries
              : true)) {
        _invalid();
      }
      sawTransparency = true;
    } else if (type == 'IDAT') {
      if (endedData || (color == 3 && !sawPalette)) _invalid();
      sawData = true;
      idat.add(Uint8List.sublistView(b, data, data + size));
    } else if (type == 'IEND') {
      if (size != 0 || !sawData || end != b.length) _invalid();
      clean.add(Uint8List.sublistView(b, p, end));
      final counter = _CountInflated(
        _pngInflatedSize(width!, height!, bitsPerPixel, interlace),
      );
      final sink = ZLibDecoder().startChunkedConversion(counter);
      for (final block in idat) {
        // Tiny compressed chunks also bound each native inflater output batch.
        for (var i = 0; i < block.length; i += 64) {
          sink.add(
            Uint8List.sublistView(
              block,
              i,
              i + 64 < block.length ? i + 64 : block.length,
            ),
          );
        }
      }
      sink.close();
      return CheckedImage(
        clean.takeBytes(),
        StillImageFormat.png,
        width,
        height,
      );
    } else {
      if (sawData) endedData = true;
      // Unknown critical chunks have semantics this still-image path cannot honor.
      if (b[p + 4] & 32 == 0) _invalid();
      if (type == 'gAMA' && (size != 4 || _u32(b, data, Endian.big) == 0)) {
        _invalid();
      }
    }
    // Strip metadata before decoding. Keep only bounded color/pixel semantics.
    if ({'IHDR', 'PLTE', 'tRNS', 'gAMA', 'IDAT'}.contains(type)) {
      clean.add(Uint8List.sublistView(b, p, end));
    }
    p = end;
  }
  _invalid();
}

CheckedImage _webp(Uint8List b) {
  if (_u32(b, 4, Endian.little) + 8 != b.length) _invalid();
  var p = 12;
  int? width, height, canvasWidth, canvasHeight;
  var alpha = false;
  var orientation = 1;
  final clean = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 12));
  while (p + 8 <= b.length) {
    final type = _tag(b, p), size = _u32(b, p + 4, Endian.little);
    final data = p + 8, end = data + size + (size & 1);
    if (end > b.length) _invalid();
    if ({'ANIM', 'ANMF'}.contains(type)) _invalid();
    if (type == 'VP8X') {
      if (p != 12 ||
          size != 10 ||
          b[data] & 0xc3 != 0 ||
          _le24(b, data + 1) != 0) {
        _invalid();
      }
      canvasWidth = _le24(b, data + 4) + 1;
      canvasHeight = _le24(b, data + 7) + 1;
      _dimensions(canvasWidth, canvasHeight);
    } else if (type == 'VP8L') {
      if (width != null || alpha || size < 5 || b[data] != 0x2f) _invalid();
      final header = _u32(b, data + 1, Endian.little);
      if (header >> 29 != 0) _invalid();
      width = (header & 0x3fff) + 1;
      height = ((header >> 14) & 0x3fff) + 1;
      _dimensions(width, height);
    } else if (type == 'VP8 ') {
      if (width != null ||
          size < 10 ||
          b[data] & 1 != 0 ||
          !_equal(b, data + 3, const [0x9d, 0x01, 0x2a])) {
        _invalid();
      }
      width = b[data + 6] | (b[data + 7] << 8);
      height = b[data + 8] | (b[data + 9] << 8);
      // The pinned decoder uses the raw fields, including scale bits.
      if (width & 0xc000 != 0 || height & 0xc000 != 0) _invalid();
      _dimensions(width, height);
    } else if (type == 'ALPH') {
      if (alpha || width != null || canvasWidth == null || size < 1) _invalid();
      alpha = true;
    } else if (type == 'EXIF') {
      orientation =
          _exifOrientation(
            Uint8List.sublistView(b, data, data + size),
            allowRaw: true,
          ) ??
          orientation;
    }
    if ({'VP8X', 'VP8 ', 'VP8L', 'ALPH'}.contains(type)) {
      final chunk = Uint8List.fromList(Uint8List.sublistView(b, p, end));
      if (type == 'VP8X') chunk[8] &= 0x10; // Only retained alpha semantics.
      clean.add(chunk);
    }
    p = end;
  }
  if (p != b.length ||
      width == null ||
      height == null ||
      (canvasWidth != null &&
          (canvasWidth != width || canvasHeight != height))) {
    _invalid();
  }
  final normalized = clean.takeBytes();
  ByteData.sublistView(normalized)
      .setUint32(4, normalized.length - 8, Endian.little);
  return CheckedImage(
    normalized,
    StillImageFormat.webp,
    width,
    height,
    orientation: orientation,
  );
}
