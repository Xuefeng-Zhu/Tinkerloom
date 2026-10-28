import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appnest_server/src/modules/media/image_preflight.dart';
import 'package:appnest_server/src/modules/media/image_worker.dart';
import 'package:appnest_server/src/modules/media/media.dart';
import 'package:appnest_server/src/modules/media/processing_admission.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:image/image.dart' as image;
import 'package:test/test.dart';

final _fixtures = <String, String>{
  'webp_lossy': 'UklGRjoAAABXRUJQVlA4IC4AAADQAQCdASoDAAIAAUAmJaACdLoB+AADsAD+645f/NgVzXPv9/+rQ+Wh8tD9uwAA',
  'webp_lossless': 'UklGRh4AAABXRUJQVlA4TBEAAAAvAkAAEAdQqPrWo3iBiOh/AAA=',
  'jpeg_progressive': '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wgARCAACAAMDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAT/xAAUAQEAAAAAAAAAAAAAAAAAAAAF/9oADAMBAAIQAxAAAAGQFtf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAEFAn//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/AX//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/AX//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAY/An//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/IX//2gAMAwEAAgADAAAAEPv/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==',
  'jpeg_cmyk': '/9j/7gAOQWRvYmUAZAAAAAAA/9sAQwAIBgYHBgUIBwcHCQkICgwUDQwLCwwZEhMPFB0aHx4dGhwcICQuJyAiLCMcHCg3KSwwMTQ0NB8nOT04MjwuMzQy/8AAFAgAAgADBEMRAE0RAFkRAEsRAP/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/aAA4EQwBNAFkASwAAPwD3Wu5rIr2uv//Z',
};
Uint8List _fixture(String name) => base64Decode(_fixtures[name]!);
final _reject = throwsA(isA<SpecException>());

int _crc(List<int> bytes) {
  var c = 0xffffffff;
  for (final byte in bytes) {
    c ^= byte;
    for (var i = 0; i < 8; i++) {
      c = c & 1 != 0 ? (c >> 1) ^ 0xedb88320 : c >> 1;
    }
  }
  return c ^ 0xffffffff;
}

Uint8List _chunk(String type, List<int> data) {
  final b = Uint8List(12 + data.length);
  final v = ByteData.sublistView(b);
  v.setUint32(0, data.length);
  b.setAll(4, ascii.encode(type));
  b.setAll(8, data);
  v.setUint32(8 + data.length, _crc(b.sublist(4, 8 + data.length)));
  return b;
}

Uint8List _png(
  int width,
  int height,
  List<int> raw, {
  int color = 6,
  int bits = 8,
  int interlace = 0,
  bool split = false,
  List<int>? palette,
  List<int>? transparency,
}) {
  final header = Uint8List(13);
  ByteData.sublistView(header)
    ..setUint32(0, width)
    ..setUint32(4, height);
  header[8] = bits;
  header[9] = color;
  header[12] = interlace;
  final compressed = ZLibEncoder().convert(raw);
  final b = BytesBuilder()
    ..add([137, 80, 78, 71, 13, 10, 26, 10])
    ..add(_chunk('IHDR', header));
  if (palette != null) b.add(_chunk('PLTE', palette));
  if (transparency != null) b.add(_chunk('tRNS', transparency));
  if (split) {
    final mid = compressed.length ~/ 2;
    b
      ..add(_chunk('IDAT', compressed.sublist(0, mid)))
      ..add(_chunk('IDAT', compressed.sublist(mid)));
  } else {
    b.add(_chunk('IDAT', compressed));
  }
  b.add(_chunk('IEND', []));
  return b.takeBytes();
}

Uint8List _riff(List<int> chunks) {
  final b = Uint8List(12 + chunks.length);
  b.setAll(0, ascii.encode('RIFF'));
  ByteData.sublistView(b).setUint32(4, b.length - 8, Endian.little);
  b.setAll(8, ascii.encode('WEBP'));
  b.setAll(12, chunks);
  return b;
}

Uint8List _webpChunk(String type, List<int> data) {
  final b = Uint8List(8 + data.length + (data.length & 1));
  b.setAll(0, ascii.encode(type));
  ByteData.sublistView(b).setUint32(4, data.length, Endian.little);
  b.setAll(8, data);
  return b;
}

Uint8List _jpegHeader(
  int width,
  int height, {
  int count = 3,
  int sampling = 0x11,
}) => Uint8List.fromList([
  0xff,
  0xd8,
  0xff,
  0xc0,
  0,
  8 + count * 3,
  8,
  height >> 8,
  height & 255,
  width >> 8,
  width & 255,
  count,
  for (var i = 0; i < count; i++) ...[i + 1, sampling, 0],
  0xff,
  0xda,
  0,
  6 + count * 2,
  count,
  for (var i = 0; i < count; i++) ...[i + 1, 0],
  0,
  63,
  0,
  0xff,
  0xd9,
]);

Uint8List _jpegSegment(int marker, List<int> data) => Uint8List.fromList([
  0xff,
  marker,
  (data.length + 2) >> 8,
  (data.length + 2) & 255,
  ...data,
]);

Iterable<Uint8List> _jpegPayloads(Uint8List bytes, int marker) sync* {
  var p = 2;
  while (p + 4 <= bytes.length) {
    final current = bytes[p + 1];
    if (current == 0xda || current == 0xd9) return;
    final length = (bytes[p + 2] << 8) | bytes[p + 3];
    if (current == marker) {
      yield Uint8List.sublistView(bytes, p + 4, p + 2 + length);
    }
    p += 2 + length;
  }
}

Uint8List _orientationTiff(int orientation) {
  // A raw little-endian TIFF, without the JPEG-only Exif\0\0 prefix.
  final bytes = Uint8List(26)..setAll(0, [73, 73]);
  ByteData.sublistView(bytes)
    ..setUint16(2, 42, Endian.little)
    ..setUint32(4, 8, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 0x112, Endian.little)
    ..setUint16(12, 3, Endian.little)
    ..setUint32(14, 1, Endian.little)
    ..setUint16(18, orientation, Endian.little);
  return bytes;
}

image.Image _pattern({bool alpha = false}) {
  final src = image.Image(width: 3, height: 2, numChannels: alpha ? 4 : 3);
  for (final pixel in src) {
    pixel
      ..r = 30 + pixel.x * 70
      ..g = 20 + pixel.y * 90
      ..b = 30 + (pixel.y * src.width + pixel.x) * 20;
    if (alpha) pixel.a = 40 + (pixel.y * src.width + pixel.x) * 40;
  }
  return src;
}

image.Image _oriented(image.Image src, int orientation) {
  final swap = orientation >= 5;
  final expected = image.Image(
    width: swap ? src.height : src.width,
    height: swap ? src.width : src.height,
    numChannels: src.numChannels,
  );
  for (final pixel in expected) {
    final x = pixel.x, y = pixel.y;
    final (sx, sy) = switch (orientation) {
      1 => (x, y),
      2 => (src.width - 1 - x, y),
      3 => (src.width - 1 - x, src.height - 1 - y),
      4 => (x, src.height - 1 - y),
      5 => (y, x),
      6 => (y, src.height - 1 - x),
      7 => (src.width - 1 - y, src.height - 1 - x),
      8 => (src.width - 1 - y, x),
      _ => throw ArgumentError.value(orientation),
    };
    expected.setPixel(x, y, src.getPixel(sx, sy));
  }
  return expected;
}

void _expectPixels(image.Image actual, image.Image expected) {
  expect([actual.width, actual.height], [expected.width, expected.height]);
  expect(
    actual.getBytes(order: image.ChannelOrder.rgba),
    orderedEquals(expected.getBytes(order: image.ChannelOrder.rgba)),
  );
}

void main() {
  test('image workers return valid output, propagate rejection and terminate stalls', () async {
    final bytes = image.encodeJpg(image.Image(width: 3, height: 2));
    final result = await runImageTask(() => sanitizeImage(bytes));
    expect([result.width, result.height], [3, 2]);
    await expectLater(runImageTask(() => sanitizeImage(Uint8List(0))), _reject);
    await expectLater(
      runImageTask<int>(() {
        while (true) {}
      }, timeout: const Duration(milliseconds: 100)),
      _reject,
    );
    expect(await runImageTask(() => 42), 42);
  });
  test('allocation headers reject oversized JPEG before entering decoder', () {
    expect(() => checkImageInput(_jpegHeader(65535, 65535)), _reject);
    expect(() => checkImageInput(_jpegHeader(8193, 1)), _reject);
    expect(() => checkImageInput(_jpegHeader(10, 10, count: 5)), _reject);
    expect(() => checkImageInput(_jpegHeader(10, 10, sampling: 0x44)), _reject);
    final valid = _jpegHeader(10, 10);
    final duplicated = Uint8List.fromList([
      ...valid.sublist(0, 21),
      ...valid.sublist(2),
    ]);
    expect(() => checkImageInput(duplicated), _reject);
  });
  test('baseline, progressive, CMYK and gray JPEG remain usable', () {
    for (final bytes in [
      image.encodeJpg(image.Image(width: 3, height: 2)),
      image.encodeJpg(image.Image(width: 3, height: 2, numChannels: 1)),
      _fixture('jpeg_progressive'),
      _fixture('jpeg_cmyk'),
    ]) {
      final result = sanitizeImage(bytes);
      expect([result.width, result.height], [3, 2]);
      expect(image.decodeImage(result.display), isNotNull);
    }
  });
  for (var quality = 1; quality <= 100; quality++) {
    test(
      'JPEG encoder quality $quality preserves decoded preflight pixels',
      () {
        final bytes = image.encodeJpg(_pattern(), quality: quality);
        final expected = image.decodeJpg(bytes)!;
        final checked = checkImageInput(bytes);
        expect(checked.format, StillImageFormat.jpeg);
        expect([checked.width, checked.height], [3, 2]);
        _expectPixels(image.decodeJpg(checked.bytes)!, expected);
        final tables = _jpegPayloads(checked.bytes, 0xdb).toList();
        expect(tables, isNotEmpty);
        for (final table in tables) {
          expect(table.first >> 4, 1);
          expect([
            for (var i = 0; i + 1 < table.length; i++)
              if (table[i] == 0xff &&
                  {0xc0, 0xc1, 0xc2, 0xe1}.contains(table[i + 1]))
                i,
          ], isEmpty);
        }
        final result = sanitizeImage(bytes);
        expect([result.width, result.height], [3, 2]);
      },
    );
  }
  test('retained JPEG Huffman tables cannot hide an EXIF marker', () {
    final bytes = image.encodeJpg(_pattern());
    final table = _jpegPayloads(bytes, 0xc4).first;
    // Skip the table selector and sixteen code-length counts.
    table[17] = 0xff;
    table[18] = 0xe1;
    expect(() => checkImageInput(bytes), _reject);
  });
  test('JPEG orientation survives a later non-EXIF XMP APP1 segment', () {
    final original = image.encodeJpg(_pattern(), quality: 100);
    final bytes = Uint8List.fromList([
      ...original.sublist(0, 2),
      ..._jpegSegment(0xe1, [
        ...ascii.encode('Exif'),
        0,
        0,
        ..._orientationTiff(6),
      ]),
      ..._jpegSegment(
        0xe1,
        ascii.encode(
          'http://ns.adobe.com/xap/1.0/\x00<x:xmpmeta>private</x:xmpmeta>',
        ),
      ),
      ...original.sublist(2),
    ]);
    final expected = _oriented(image.decodeJpg(original)!, 6);
    final normalized = checkImageInput(bytes).bytes;
    _expectPixels(image.decodeJpg(normalized)!, expected);
    expect(
      ascii.decode(normalized, allowInvalid: true),
      isNot(contains('xmpmeta')),
    );
    final result = sanitizeImage(bytes);
    expect([result.width, result.height], [2, 3]);
    final actual = image.decodeImage(result.display)!;
    expect([actual.width, actual.height], [2, 3]);
    expect(actual.exif.imageIfd.hasOrientation, isFalse);
    for (final pixel in actual) {
      final e = expected.getPixel(pixel.x, pixel.y);
      expect(pixel.r, closeTo(e.r, 25));
      expect(pixel.g, closeTo(e.g, 25));
      expect(pixel.b, closeTo(e.b, 25));
    }
  });
  test('all JPEG orientations survive metadata stripping exactly once', () {
    for (var orientation = 1; orientation <= 8; orientation++) {
      final src = image.Image(width: 3, height: 2)
        ..exif.imageIfd.orientation = orientation;
      for (final pixel in src) {
        pixel
          ..r = pixel.x * 80
          ..g = pixel.y * 100
          ..b = 30;
      }
      final bytes = image.encodeJpg(src, quality: 100);
      final expected = image.decodeJpg(bytes)!;
      final result = sanitizeImage(bytes),
          actual = image.decodeImage(sanitizeImage(bytes).display)!;
      expect([result.width, result.height], [expected.width, expected.height]);
      for (final pixel in actual) {
        final e = expected.getPixel(pixel.x, pixel.y);
        expect(pixel.r, closeTo(e.r, 15));
        expect(pixel.g, closeTo(e.g, 15));
      }
      expect(actual.exif.imageIfd.hasOrientation, isFalse);
    }
  });
  test(
    'cyclic original JPEG EXIF is stripped without following its pointers',
    () {
      final b = Uint8List(40);
      b.setAll(0, [69, 120, 105, 102, 0, 0, 73, 73, 42, 0, 8, 0, 0, 0]);
      final v = ByteData.sublistView(b, 6);
      v
        ..setUint16(8, 0, Endian.little)
        ..setUint32(10, 20, Endian.little)
        ..setUint16(20, 0, Endian.little)
        ..setUint32(22, 8, Endian.little);
      final payload = [0xff, 0xe1, 0, b.length + 2, ...b];
      final original = image.encodeJpg(image.Image(width: 2, height: 1));
      final result = sanitizeImage(
        Uint8List.fromList([
          ...original.sublist(0, 2),
          ...payload,
          ...original.sublist(2),
        ]),
      );
      expect(result.width, 2);
    },
  );
  test('PNG rejects surplus or truncated expansion, across split IDAT', () {
    expect(() => sanitizeImage(_png(1, 1, Uint8List(65536))), _reject);
    expect(
      () => sanitizeImage(_png(1, 1, Uint8List(65536), split: true)),
      _reject,
    );
    expect(() => sanitizeImage(_png(1, 1, [0, 255])), _reject);
    final valid = _png(1, 1, [0, 190, 80, 30, 120], split: true);
    expect(sanitizeImage(valid).contentType, 'image/png');
  });
  test(
    'PNG palette, low-bit, 16-bit and Adam7 layouts retain pixel semantics',
    () {
      final palette = _png(
        1,
        1,
        [0, 0],
        color: 3,
        bits: 1,
        palette: [190, 80, 30],
        transparency: [120],
      );
      final low = _png(1, 1, [0, 0x80], color: 0, bits: 1);
      final sixteen = _png(1, 1, [0, 255, 255, 0, 0, 0, 0, 128, 128], bits: 16);
      // Exercise all seven Adam7 passes in a supported interlaced fixture.
      final interlaced = _png(8, 8, [
        for (final pass in [
          [0, 0, 8, 8],
          [4, 0, 8, 8],
          [0, 4, 4, 8],
          [2, 0, 4, 4],
          [0, 2, 2, 4],
          [1, 0, 2, 2],
          [0, 1, 1, 2],
        ])
          for (var y = pass[1]; y < 8; y += pass[3]) ...[
            0,
            for (var x = pass[0]; x < 8; x += pass[2]) ...[190, 80, 30, 255],
          ],
      ], interlace: 1);
      for (final bytes in [palette, low, sixteen, interlaced]) {
        expect(image.decodePng(checkImageInput(bytes).bytes), isNotNull);
        final result = sanitizeImage(bytes);
        expect(image.decodeImage(result.display), isNotNull);
      }
      final decoded = image.decodeImage(sanitizeImage(palette).display)!;
      expect(decoded.getPixel(0, 0).a, 120);
    },
  );
  test('PNG rejects APNG even with one declared frame and strips metadata', () {
    final still = _png(1, 1, [0, 190, 80, 30, 255]);
    expect(
      () => sanitizeImage(
        Uint8List.fromList([
          ...still.sublist(0, 33),
          ..._chunk('acTL', [0, 0, 0, 1, 0, 0, 0, 0]),
          ...still.sublist(33),
        ]),
      ),
      _reject,
    );
    final bytes = Uint8List.fromList([
      ...still.sublist(0, 33),
      ..._chunk('tEXt', ascii.encode('secret\x00private')),
      ...still.sublist(33),
    ]);
    expect(image.decodeImage(sanitizeImage(bytes).display)!.textData, isNull);
  });
  test('ordinary lossy, lossless and transparent WebP remain usable', () {
    for (final name in ['webp_lossy', 'webp_lossless']) {
      final result = sanitizeImage(_fixture(name));
      expect([result.width, result.height], [3, 2]);
      if (name == 'webp_lossless') {
        expect(image.decodeImage(result.display)!.getPixel(0, 0).a, 120);
      }
    }
  });
  for (var orientation = 1; orientation <= 8; orientation++) {
    test(
      'WebP raw TIFF orientation $orientation preserves pixels and alpha',
      () {
        final original = image.encodeWebP(_pattern(alpha: true));
        final expected = _oriented(image.decodeWebP(original)!, orientation);
        final bytes = _riff([
          ..._webpChunk('VP8X', [0x18, 0, 0, 0, 2, 0, 0, 1, 0, 0]),
          ...original.sublist(12),
          ..._webpChunk('EXIF', _orientationTiff(orientation)),
        ]);
        final checked = checkImageInput(bytes);
        expect(checked.orientation, orientation);
        final normalized = image.decodeWebP(checked.bytes)!;
        expect(normalized.exif.imageIfd.hasOrientation, isFalse);
        _expectPixels(normalized, image.decodeWebP(original)!);
        final result = sanitizeImage(bytes);
        expect(result.contentType, 'image/png');
        expect(
          [result.width, result.height],
          [expected.width, expected.height],
        );
        for (final output in [result.display, result.thumbnail]) {
          final actual = image.decodeImage(output)!;
          _expectPixels(actual, expected);
          expect(actual.exif.imageIfd.hasOrientation, isFalse);
        }
      },
    );
  }
  test(
    'WebP animation, duplicate bitstreams and inconsistent canvases rejected',
    () {
      final chunks = _fixture('webp_lossless').sublist(12);
      final animated = _riff([
        ..._webpChunk('VP8X', [2, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ..._webpChunk('ANMF', [...Uint8List(16), ...chunks]),
      ]);
      expect(() => checkImageInput(animated), _reject);
      expect(() => checkImageInput(_riff([...chunks, ...chunks])), _reject);
      expect(
        () => checkImageInput(
          _riff([
            ..._webpChunk('VP8X', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            ...chunks,
          ]),
        ),
        _reject,
      );
      expect(
        () => checkImageInput(
          _riff([
            ..._webpChunk('ANMF', [...Uint8List(16), ...chunks]),
          ]),
        ),
        _reject,
      );
    },
  );
  test('WebP original EXIF is removed before its parser can run', () {
    final chunks = _fixture('webp_lossless').sublist(12);
    final bytes = _riff([
      ...chunks,
      ..._webpChunk('EXIF', [73, 73, 42, 0, 8, 0, 0, 0, 0, 0, 8, 0, 0, 0]),
    ]);
    expect(sanitizeImage(bytes).width, 3);
  });
  test(
    'processing slots bound aggregate and actor work and release idempotently',
    () {
      final admission = ProcessingAdmission();
      final first = admission.acquire('one')!;
      expect(admission.acquire('one'), isNull);
      final second = admission.acquire('two')!;
      expect(admission.acquire('three'), isNull);
      first();
      first();
      final retry = admission.acquire('one')!;
      second();
      retry();
      expect(admission.acquire('three'), isNotNull);
    },
  );
}
