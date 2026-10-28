import 'dart:typed_data';

import 'package:appnest_client/appnest_client.dart';
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
  required int appId,
  int? draftId,
  String? actionId,
  int? targetRecordId,
  String? fieldId,
  int? expectedDefinitionVersionId,
}) async {
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
  final uploaded = await FileUploader(ticket.uploadDescription)
      .uploadByteData(ByteData.sublistView(bytes));
  try {
    // A response may be lost after storage accepted the bytes. Completion
    // validates the upload and is safe to repeat for this particular asset.
    final result = await client.media.completeUpload(appId, ticket.assetId);
    return result.assetId;
  } catch (_) {
    if (uploaded) rethrow;
    throw StateError(
      'The image upload failed. Choose the image again to retry.',
    );
  }
}
