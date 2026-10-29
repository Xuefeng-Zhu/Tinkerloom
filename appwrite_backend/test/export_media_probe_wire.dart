// Offline contract fixture generator: real service/sanitizer over MemoryStore.
// Never reads credentials, starts a server or invokes Appwrite/provider APIs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import '../lib/service.dart';
import '../lib/image_preflight.dart';
import '../lib/image_sanitizer.dart';
import 'media_check.dart' as media;

String digest(List<int> bytes) => sha256.convert(bytes).toString();
Future<void> main(List<String> args) async {
  if (args.length != 2)
    throw ArgumentError('synthetic PNG input and output JSON required');
  final original = File(args[0]).readAsBytesSync();
  if (original.length != MediaLimits.maxOriginalBytes)
    throw StateError('expected exactly 5 MiB');
  final checked = checkImageInput(original);
  final f = media.Fixture();
  await f.setup(publish: false);
  Future<Row> call(Row input) => f.api.execute('alice', input);
  final begin = await call(f.begin('max-png', original, draft: 1));
  final asset = (begin['asset'] as Row)['assetId'] as String;
  Row? first, last;
  for (
    var offset = 0;
    offset < original.length;
    offset += MediaLimits.chunkBytes
  ) {
    final chunk = Uint8List.sublistView(
      original,
      offset,
      offset + MediaLimits.chunkBytes,
    );
    final result = await call({
      'op': 'spec.media.chunk',
      'appId': 'app',
      'assetId': asset,
      'offset': offset,
      'sha256': digest(chunk),
      'dataBase64': base64Encode(chunk),
    });
    first ??= result;
    last = result;
  }
  final complete = await call({
    'op': 'spec.media.complete',
    'appId': 'app',
    'assetId': asset,
    'operationId': 'complete',
  });
  await f.api.processMedia(asset);
  final ready = await call({
    'op': 'spec.media.status',
    'appId': 'app',
    'assetId': asset,
  });
  final display = await call({
    'op': 'spec.media.read',
    'appId': 'app',
    'assetId': asset,
    'variant': 'display',
    'offset': 0,
  });
  final thumbnail = await call({
    'op': 'spec.media.read',
    'appId': 'app',
    'assetId': asset,
    'variant': 'thumbnail',
    'offset': 0,
  });
  final source = image.Image(width: 12, height: 6)
    ..exif.imageIfd.orientation = 6;
  source.textData = {'private': 'Tinkerloom synthetic EXIF stripping marker'};
  for (final pixel in source) {
    pixel
      ..r = pixel.x * 18
      ..g = pixel.y * 40
      ..b = 60;
  }
  final oriented = Uint8List.fromList(image.encodeJpg(source, quality: 100));
  final sanitized = sanitizeImage(oriented);
  final decoded = image.decodeJpg(sanitized.display)!;
  if (decoded.width != 6 ||
      decoded.height != 12 ||
      decoded.exif.imageIfd.hasOrientation)
    throw StateError('orientation fixture incorrect');
  final result = {
    'proof':
        'Real Dart service DTOs and actual image decoding over a simulated store; no Cloud evidence.',
    'capabilities': await call({'op': 'spec.capabilities'}),
    'png': {
      'byteLength': original.length,
      'sha256': digest(original),
      'width': checked.width,
      'height': checked.height,
    },
    'begin': begin,
    'firstChunk': first,
    'lastChunk': last,
    'complete': complete,
    'ready': ready,
    'display': display,
    'thumbnail': thumbnail,
    'usage': await call({'op': 'spec.media.usage', 'appId': 'app'}),
    'orientation': {
      'inputBase64': base64Encode(oriented),
      'inputSha256': digest(oriented),
      'inputByteLength': oriented.length,
      'originalWidth': 12,
      'originalHeight': 6,
      'orientation': 6,
      'displaySha256': digest(sanitized.display),
      'thumbnailSha256': digest(sanitized.thumbnail),
      'width': sanitized.width,
      'height': sanitized.height,
      'contentType': sanitized.contentType,
      'displayBytes': sanitized.display.length,
      'thumbnailBytes': sanitized.thumbnail.length,
    },
  };
  File(args[1]).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
}
