import 'dart:math';
import 'dart:typed_data';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:image/image.dart' as image;
import 'image_preflight.dart';
import 'image_worker.dart';
import 'media_store.dart';

class SanitizedImage {
  final Uint8List display, thumbnail;
  final String contentType;
  final int width, height;
  const SanitizedImage(
    this.display,
    this.thumbnail,
    this.contentType,
    this.width,
    this.height,
  );
}

// Keep this closure outside endpoint/service scopes: capturing a Session in an
// isolate closure would capture unsendable database connections and completers.
Future<SanitizedImage> sanitizeOffThread(Uint8List bytes) =>
    runImageTask(() => sanitizeImage(bytes));

/// Decode only supported, bounded still images; never retain original metadata.
SanitizedImage sanitizeImage(Uint8List bytes) {
  try {
    return _sanitizeImage(bytes);
  } on SpecException {
    rethrow;
  } catch (_) {
    throw const SpecException(
      'The image could not be decoded. Choose another image.',
    );
  }
}

SanitizedImage _sanitizeImage(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > MediaLimits.maxOriginalBytes) {
    throw const SpecException('Images must be no larger than 5 MiB.');
  }
  final checked = checkImageInput(bytes);
  final image.Decoder decoder = switch (checked.format) {
    StillImageFormat.jpeg => image.JpegDecoder(),
    StillImageFormat.png => image.PngDecoder(),
    StillImageFormat.webp => image.WebPDecoder(),
  };
  final info = decoder.startDecode(checked.bytes);
  if (info == null ||
      (checked.format == StillImageFormat.webp
          ? info.numFrames > 1
          : info.numFrames != 1) ||
      info.width != checked.width ||
      info.height != checked.height ||
      info.width < 1 ||
      info.height < 1 ||
      info.width > 8192 ||
      info.height > 8192 ||
      info.width * info.height > 16000000) {
    throw const SpecException(
      'Choose a still image no larger than 16 megapixels.',
    );
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) {
    throw const SpecException('The image could not be decoded.');
  }
  if (checked.format == StillImageFormat.webp && checked.orientation != 1) {
    decoded.exif.imageIfd.orientation = checked.orientation;
  }
  var clean = image.bakeOrientation(decoded);
  clean.exif = image.ExifData();
  clean.iccProfile = null;
  clean.textData = null;
  image.Image resize(image.Image source, int edge) {
    if (max(source.width, source.height) <= edge) return source;
    return source.width >= source.height
        ? image.copyResize(
            source,
            width: edge,
            interpolation: image.Interpolation.average,
          )
        : image.copyResize(
            source,
            height: edge,
            interpolation: image.Interpolation.average,
          );
  }

  final alpha = clean.hasAlpha;
  Uint8List encode(image.Image frame) =>
      alpha ? image.encodePng(frame) : image.encodeJpg(frame, quality: 85);
  clean = resize(clean, 2048);
  var display = encode(clean);
  while (display.length > MediaLimits.maxOriginalBytes &&
      max(clean.width, clean.height) > 256) {
    clean = resize(clean, (max(clean.width, clean.height) * .75).floor());
    display = encode(clean);
  }
  var thumb = resize(clean, 384);
  var thumbnail = encode(thumb);
  while (thumbnail.length > MediaLimits.maxThumbnailBytes &&
      max(thumb.width, thumb.height) > 64) {
    thumb = resize(thumb, (max(thumb.width, thumb.height) * .75).floor());
    thumbnail = encode(thumb);
  }
  if (display.length > MediaLimits.maxOriginalBytes ||
      thumbnail.length > MediaLimits.maxThumbnailBytes) {
    throw const SpecException('The image could not fit the storage limits.');
  }
  return SanitizedImage(
    display,
    thumbnail,
    alpha ? 'image/png' : 'image/jpeg',
    clean.width,
    clean.height,
  );
}
