import 'dart:typed_data';

import 'package:appnest_server/src/modules/media/media.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:image/image.dart' as image;
import 'package:test/test.dart';

void main() {
  test(
    'sanitization downsamples, creates thumbnail and strips text metadata',
    () {
      final source = image.Image(width: 2200, height: 500, numChannels: 4);
      source.textData = {'private': 'do not retain'};
      final result = sanitizeImage(image.encodePng(source));
      expect(result.width, 2048);
      expect(result.contentType, 'image/png');
      final display = image.decodeImage(result.display)!;
      expect(display.textData, isNull);
      expect(image.decodeImage(result.thumbnail)!.width, 384);
    },
  );

  test('unsupported, corrupt and oversized uploads are rejected', () {
    expect(
      () => sanitizeImage(Uint8List.fromList('<svg/>'.codeUnits)),
      throwsA(isA<SpecException>()),
    );
    expect(
      () => sanitizeImage(Uint8List(Media.maxOriginalBytes + 1)),
      throwsA(isA<SpecException>()),
    );
    final gif = image.encodeGif(image.Image(width: 1, height: 1));
    expect(() => sanitizeImage(gif), throwsA(isA<SpecException>()));
  });
}
