import 'dart:typed_data';

import 'package:serverpod/serverpod.dart';

import '../generated/protocol.dart';
import '../modules/media/media.dart';

class MediaEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  Future<MediaUploadTicket> beginUpload(
    Session session,
    MediaUploadRequest request,
  ) => Media.beginUpload(session, request);

  Future<MediaInfo> completeUpload(
    Session session,
    int appId,
    String assetId,
  ) => Media.completeUpload(session, appId, assetId);

  Future<ByteData> readImage(
    Session session,
    int appId,
    String assetId,
    String variant,
  ) => Media.readImage(session, appId, assetId, variant);
}
