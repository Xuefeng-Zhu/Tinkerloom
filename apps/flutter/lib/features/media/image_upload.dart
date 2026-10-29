import 'dart:typed_data';

import 'package:tinkerloom_client/tinkerloom_client.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:file_selector/file_selector.dart';

const maximumImageBytes = 5 * 1024 * 1024;

Future<Uint8List?> pickAppImage() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
        uniformTypeIdentifiers: [
          'public.jpeg',
          'public.png',
          'org.webmproject.webp',
        ],
      ),
    ],
  );
  if (file == null) return null;
  if (await file.length() > maximumImageBytes) {
    throw const FormatException('Choose an image smaller than 5 MiB.');
  }
  final bytes = await file.readAsBytes();
  imageContentType(bytes);
  return bytes;
}

/// A convenience check only. The server decodes and validates uploaded bytes.
String imageContentType(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maximumImageBytes) {
    throw const FormatException('Choose an image smaller than 5 MiB.');
  }
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71 &&
      bytes[4] == 13 &&
      bytes[5] == 10 &&
      bytes[6] == 26 &&
      bytes[7] == 10) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  throw const FormatException('Choose a JPEG, PNG, or WebP image.');
}

Future<String> uploadAppImage(
  Client client,
  Uint8List bytes, {
  required String appId,
  String? draftId,
  String? actionId,
  String? targetRecordId,
  String? fieldId,
  String? expectedDefinitionVersionId,
  Future<void> Function()? validateContext,
}) async {
  final actor = client.auth.actorId;
  final ticket = await client.media.beginUpload(
    MediaUploadRequest(
      appId: appId,
      draftId: draftId,
      actionId: actionId,
      targetRecordId: targetRecordId,
      fieldId: fieldId,
      expectedDefinitionVersionId: expectedDefinitionVersionId,
      byteLength: bytes.length,
      contentType: imageContentType(bytes),
      idempotencyKey: 'image-${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  await client.media.uploadBytes(ticket, bytes);
  // Completion never allocates a new upload or silently retries an uncertain
  // write. The same ticket identifies the bytes just uploaded.
  PendingImageUpload pending(String assetId) {
    Future<String> checkReady() async {
      if (client.auth.actorId != actor) {
        throw BackendUnauthorized('Your session changed. Reopen the form.');
      }
      await validateContext?.call();
      try {
        final ready = await client.media.checkUpload(appId, assetId);
        if (ready.assetId != assetId) {
          throw NestError(
            category: 'media_integrity',
            message: 'The image response belongs to another upload.',
          );
        }
        return ready.assetId;
      } on BackendMediaProcessing {
        throw pending(assetId);
      }
    }

    return PendingImageUpload(assetId: assetId, checkReady: checkReady);
  }

  try {
    final result = await client.media.completeUpload(appId, ticket.assetId);
    return result.assetId;
  } on BackendMediaProcessing catch (processing) {
    throw pending(processing.assetId);
  }
}
