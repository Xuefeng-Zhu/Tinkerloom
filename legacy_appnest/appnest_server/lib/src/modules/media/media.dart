import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:image/image.dart' as image;
import 'package:serverpod/serverpod.dart';

import '../../generated/protocol.dart';
import '../runtime/access.dart';
import 'image_preflight.dart';
import 'image_worker.dart';
import 'processing_admission.dart';

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
Future<SanitizedImage> _sanitizeOffThread(Uint8List bytes) =>
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
  if (bytes.isEmpty || bytes.length > Media.maxOriginalBytes) {
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
  while (display.length > Media.maxOriginalBytes &&
      max(clean.width, clean.height) > 256) {
    clean = resize(clean, (max(clean.width, clean.height) * .75).floor());
    display = encode(clean);
  }
  var thumb = resize(clean, 384);
  var thumbnail = encode(thumb);
  while (thumbnail.length > Media.maxThumbnailBytes &&
      max(thumb.width, thumb.height) > 64) {
    thumb = resize(thumb, (max(thumb.width, thumb.height) * .75).floor());
    thumbnail = encode(thumb);
  }
  if (display.length > Media.maxOriginalBytes ||
      thumbnail.length > Media.maxThumbnailBytes) {
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

class Media {
  static final _processing = ProcessingAdmission();
  static const maxOriginalBytes = 5 * 1024 * 1024;
  static const maxThumbnailBytes = 512 * 1024;
  static const maxAppBytes = 250 * 1024 * 1024;
  static const maxAppAssets = 500;
  static String path(MediaAsset asset, String variant) =>
      'appnest/${asset.appId}/${asset.assetId}/$variant';

  static Future<MediaAsset> _asset(
    Session s,
    int appId,
    String assetId, {
    Transaction? tx,
  }) async {
    final result = await MediaAsset.db.findFirstRow(
      s,
      where: (t) => t.appId.equals(appId) & t.assetId.equals(assetId),
      transaction: tx,
    );
    if (result == null) fail('notFound', 'Image unavailable.');
    return result;
  }

  static Future<Access> _uploadAccess(
    Session s,
    MediaUploadRequest request,
    Transaction tx,
  ) async {
    final a = await access(s, request.appId, tx: tx, lock: true);
    a.writable();
    if (request.draftId != null) {
      a.requireBuilder();
      if (request.actionId != null ||
          request.targetRecordId != null ||
          request.fieldId != null) {
        fail('invalidInput', 'Choose either a draft or a record image.');
      }
      final draft = await AppDraft.db.findById(
        s,
        request.draftId!,
        transaction: tx,
      );
      if (draft == null ||
          draft.appId != a.app.id ||
          draft.publishedVersionId != null) {
        fail('notFound', 'Editable draft unavailable.');
      }
    } else {
      final spec = await a.spec(s, tx: tx);
      if (request.expectedDefinitionVersionId != a.app.activeVersionId) {
        fail('staleDefinition', 'The app changed. Refresh before uploading.');
      }
      final action = spec.action(request.actionId ?? '');
      if (!{
            'records.create.v1',
            'records.patch.v1',
          }.contains(action.capability) ||
          !allowed(a, spec, action)) {
        fail('forbidden', 'Your role cannot add this image.');
      }
      final col = spec.collection(action.collectionId);
      if (col.field(request.fieldId ?? '').type != FieldType.image) {
        fail('invalidInput', 'Choose an image field.');
      }
      if (action.capability == 'records.patch.v1') {
        if (request.targetRecordId == null) {
          fail('invalidInput', 'Choose a record.');
        }
        final row = await record(s, a, request.targetRecordId!, tx: tx);
        if (row.collectionId != col.id) fail('notFound', 'Record unavailable.');
      } else if (request.targetRecordId != null) {
        fail(
          'invalidInput',
          'New-record uploads cannot target an existing record.',
        );
      }
    }
    return a;
  }

  static Future<MediaUploadTicket> beginUpload(
    Session s,
    MediaUploadRequest request,
  ) => validated(() async {
    final asset = await s.db.transaction((tx) async {
      final a = await _uploadAccess(s, request, tx);
      if (request.byteLength < 1 ||
          request.byteLength > maxOriginalBytes ||
          !{
            'image/jpeg',
            'image/png',
            'image/webp',
          }.contains(request.contentType)) {
        fail('invalidInput', 'Choose a JPEG, PNG or WebP image up to 5 MiB.');
      }
      final key = str(request.idempotencyKey, 'upload key', max: 128);
      final hash = hashJson(request.toJson());
      final previous = await MediaAsset.db.findFirstRow(
        s,
        where: (t) =>
            t.appId.equals(request.appId) &
            t.uploaderId.equals(actor(s)) &
            t.idempotencyKey.equals(key),
        transaction: tx,
      );
      if (previous != null) {
        if (previous.requestHash != hash) {
          fail(
            'invalidInput',
            'Upload key was already used for another image.',
          );
        }
        if (previous.status == 'deleting' ||
            (previous.status != 'ready' &&
                !previous.expiresAt.isAfter(clock()))) {
          fail('invalidInput', 'This upload expired. Choose the image again.');
        }
        if (previous.uploadDescription != null) return previous;
        if (previous.leaseUntil?.isAfter(clock()) ?? false) {
          fail(
            'recordConflict',
            'This upload is being prepared. Try again shortly.',
          );
        }
        previous.status = 'issuing';
        previous.leaseUntil = clock().add(const Duration(minutes: 2));
        return MediaAsset.db.updateRow(s, previous, transaction: tx);
      }
      final usage = (await s.db.unsafeQuery(
        'SELECT COUNT(*),COALESCE(SUM("storedBytes"),0)::bigint FROM nest_media_asset WHERE "appId"=@app',
        parameters: QueryParameters.named({'app': request.appId}),
        transaction: tx,
      )).single;
      final reserved =
          request.byteLength + maxOriginalBytes + maxThumbnailBytes;
      if ((usage[0] as int) >= maxAppAssets ||
          (usage[1] as num) + reserved > maxAppBytes) {
        fail('quotaExceeded', 'This app has reached its image storage limit.');
      }
      return MediaAsset.db.insertRow(
        s,
        MediaAsset(
          assetId: 'img_${randomToken().replaceAll('-', '_')}',
          appId: request.appId,
          workspaceId: a.app.workspaceId,
          uploaderId: actor(s),
          idempotencyKey: key,
          requestHash: hash,
          requestJson: jsonEncode(request.toJson()),
          status: 'issuing',
          contentType: request.contentType,
          byteLength: request.byteLength,
          storedBytes: reserved,
          expiresAt: clock().add(const Duration(minutes: 10)),
          leaseUntil: clock().add(const Duration(minutes: 2)),
          createdAt: clock(),
          updatedAt: clock(),
        ),
        transaction: tx,
      );
    });
    if (asset.uploadDescription != null) {
      return MediaUploadTicket(
        assetId: asset.assetId,
        uploadDescription: asset.uploadDescription!,
      );
    }
    try {
      // Storage implementations own their connection/transaction. Never wait for
      // another pool connection while holding an app-row transaction open.
      final description = await s.storage.createUploadDescription(
        storageId: 'private',
        path: path(asset, 'original'),
        options: UploadOptions(
          contentLength: request.byteLength,
          maxFileSize: maxOriginalBytes,
          preventOverwrite: true,
          metadata: FileMetadata(
            contentType: request.contentType,
            cacheControl: 'private, no-store',
          ),
        ),
      );
      return await s.db.transaction((tx) async {
        await _uploadAccess(s, request, tx);
        final current = await _asset(s, request.appId, asset.assetId, tx: tx);
        if (current.status != 'issuing' ||
            current.leaseUntil != asset.leaseUntil ||
            !current.expiresAt.isAfter(clock())) {
          fail(
            'recordConflict',
            'Upload preparation changed. Choose the image again.',
          );
        }
        current.status = 'pending';
        current.leaseUntil = null;
        current.uploadDescription = description;
        await MediaAsset.db.updateRow(s, current, transaction: tx);
        return MediaUploadTicket(
          assetId: current.assetId,
          uploadDescription: description,
        );
      });
    } catch (_) {
      await s.db.unsafeExecute(
        'UPDATE nest_media_asset SET "leaseUntil"=NULL WHERE id=@id AND status=\'issuing\' AND "leaseUntil"=@lease',
        parameters: QueryParameters.named({
          'id': asset.id,
          'lease': asset.leaseUntil,
        }),
      );
      rethrow;
    }
  });

  static MediaInfo info(MediaAsset asset) => MediaInfo(
    assetId: asset.assetId,
    contentType: asset.contentType,
    width: asset.width,
    height: asset.height,
    byteLength: asset.byteLength,
  );

  static Future<MediaInfo> completeUpload(
    Session s,
    int appId,
    String assetId,
  ) => validated(() async {
    final asset = await s.db.transaction((tx) async {
      await access(s, appId, tx: tx, lock: true);
      final row = await _asset(s, appId, assetId, tx: tx);
      if (row.uploaderId != actor(s)) {
        fail('notFound', 'Image upload unavailable.');
      }
      await _uploadAccess(
        s,
        MediaUploadRequest.fromJson(jsonDecode(row.requestJson)),
        tx,
      );
      if (row.status == 'ready') return row;
      if (row.status == 'deleting' || !row.expiresAt.isAfter(clock())) {
        fail('invalidInput', 'Image upload expired.');
      }
      if (row.leaseUntil?.isAfter(clock()) ?? false) {
        fail(
          'recordConflict',
          'This image is still processing. Try again shortly.',
        );
      }
      row.status = 'processing';
      row.leaseUntil = clock().add(const Duration(minutes: 2));
      row.updatedAt = clock();
      return MediaAsset.db.updateRow(s, row, transaction: tx);
    });
    if (asset.status == 'ready') {
      await _removeOriginal(s, asset);
      return info(asset);
    }
    void Function()? release;
    try {
      release = _processing.acquire(actor(s));
      if (release == null) {
        fail(
          'quotaExceeded',
          'Images are busy. Try this upload again shortly.',
        );
      }
      // Verification is idempotent at this service boundary, including retries after a crash.
      await s.storage.verifyUpload(
        storageId: 'private',
        path: path(asset, 'original'),
      );
      final original = await s.storage.retrieveFile(
        storageId: 'private',
        path: path(asset, 'original'),
      );
      if (original.lengthInBytes != asset.byteLength) {
        fail('invalidInput', 'The uploaded image size did not match.');
      }
      final bytes = Uint8List.sublistView(original);
      final sanitized = await _sanitizeOffThread(bytes);
      for (final variant in {
        'display': sanitized.display,
        'thumbnail': sanitized.thumbnail,
      }.entries) {
        await s.storage.storeFile(
          storageId: 'private',
          path: path(asset, variant.key),
          byteData: ByteData.sublistView(variant.value),
          options: StoreFileOptions(
            metadata: FileMetadata(
              contentType: sanitized.contentType,
              cacheControl: 'private, no-store',
            ),
          ),
        );
      }
      final ready = await s.db.transaction((tx) async {
        await access(s, appId, tx: tx, lock: true);
        final row = await _asset(s, appId, assetId, tx: tx);
        await _uploadAccess(
          s,
          MediaUploadRequest.fromJson(jsonDecode(row.requestJson)),
          tx,
        );
        if (row.status != 'processing' || row.leaseUntil != asset.leaseUntil) {
          fail('recordConflict', 'Image processing changed. Retry the upload.');
        }
        row.status = 'ready';
        row.leaseUntil = null;
        row.width = sanitized.width;
        row.height = sanitized.height;
        row.contentType = sanitized.contentType;
        row.byteLength = sanitized.display.length;
        row.storedBytes =
            sanitized.display.length +
            sanitized.thumbnail.length +
            original.lengthInBytes;
        row.updatedAt = clock();
        final result = await MediaAsset.db.updateRow(s, row, transaction: tx);
        await changed(s, await access(s, appId, tx: tx), 'media.ready', tx);
        return result;
      });
      await _removeOriginal(s, ready);
      return info(ready);
    } catch (_) {
      // Paths remain recorded and cleanup can retry removal after any interruption.
      await s.db.unsafeExecute(
        'UPDATE nest_media_asset SET "leaseUntil"=NULL WHERE id=@id AND status=\'processing\' AND "leaseUntil"=@lease',
        parameters: QueryParameters.named({
          'id': asset.id,
          'lease': asset.leaseUntil,
        }),
      );
      rethrow;
    } finally {
      release?.call();
    }
  });

  static Future<void> _removeOriginal(Session s, MediaAsset asset) async {
    if (asset.originalRemoved) return;
    try {
      await s.storage.deleteFile(
        storageId: 'private',
        path: path(asset, 'original'),
      );
      final originalSize = MediaUploadRequest.fromJson(
        jsonDecode(asset.requestJson),
      ).byteLength;
      await s.db.transaction((tx) async {
        await MiniApp.db.findById(
          s,
          asset.appId,
          transaction: tx,
          lockMode: LockMode.forUpdate,
        );
        final current = await MediaAsset.db.findById(
          s,
          asset.id!,
          transaction: tx,
        );
        if (current == null ||
            current.status != 'ready' ||
            current.originalRemoved) {
          return;
        }
        current.originalRemoved = true;
        current.storedBytes -= originalSize;
        await MediaAsset.db.updateRow(s, current, transaction: tx);
      });
    } catch (_) {
      s.log('media_original_cleanup_retry asset_row=${asset.id}');
    }
  }

  static Future<bool> _visible(
    Session s,
    Access a,
    MediaAsset asset,
    Transaction tx,
  ) async {
    if (a.builder) return true;
    final rows = await s.db.unsafeQuery(
      'SELECT 1 FROM nest_media_reference ref LEFT JOIN nest_record r ON r.id=ref."recordId" '
      'WHERE ref."assetRowId"=@asset AND (ref."versionId"=@version OR (r.id IS NOT NULL AND NOT r.deleted)) LIMIT 1',
      parameters: QueryParameters.named({
        'asset': asset.id,
        'version': a.app.activeVersionId,
      }),
      transaction: tx,
    );
    if (rows.isNotEmpty) return true;
    return asset.uploaderId == actor(s) &&
        await MediaReference.db.count(
              s,
              where: (t) => t.assetRowId.equals(asset.id!),
              transaction: tx,
            ) ==
            0;
  }

  static Future<ByteData> readImage(
    Session s,
    int appId,
    String assetId,
    String variant,
  ) => validated(() async {
    if (!{'display', 'thumbnail'}.contains(variant)) {
      fail('invalidInput', 'Choose an image variant.');
    }
    Future<MediaAsset> authorize() => s.db.transaction((tx) async {
      final a = await access(s, appId, tx: tx, lock: true);
      final asset = await _asset(s, appId, assetId, tx: tx);
      if (asset.status != 'ready' || !await _visible(s, a, asset, tx)) {
        fail('notFound', 'Image unavailable.');
      }
      return asset;
    });
    final asset = await authorize();
    final bytes = await s.storage.retrieveFile(
      storageId: 'private',
      path: path(asset, variant),
    );
    // Revocation or reference removal during storage I/O must still deny the response.
    await authorize();
    s.setResponseHeader('Cache-Control', 'private, no-store');
    return bytes;
  });

  static Set<String> definitionAssets(AppSpec spec) => {
    for (final view in spec.views)
      if (view.type == 'banner' && view.options['imageAssetId'] is String)
        view.options['imageAssetId'] as String,
  };

  static Future<void> syncDefinition(
    Session s,
    Access a,
    AppSpec spec,
    Transaction tx, {
    int? draftId,
    int? versionId,
  }) => syncReferences(
    s,
    a,
    definitionAssets(spec),
    tx,
    draftId: draftId,
    versionId: versionId,
  );

  static Future<void> syncRecord(
    Session s,
    Access a,
    EntityRecord row,
    CollectionSpec col,
    Transaction tx,
  ) => syncReferences(
    s,
    a,
    {
      for (final field in col.fields)
        if (field.type == FieldType.image &&
            payload(row.data)[field.id] != null)
          payload(row.data)[field.id] as String,
    },
    tx,
    recordId: row.id,
  );

  static Future<void> syncReferences(
    Session s,
    Access a,
    Set<String> ids,
    Transaction tx, {
    int? draftId,
    int? versionId,
    int? recordId,
  }) async {
    if ([draftId, versionId, recordId].whereType<int>().length != 1) {
      throw StateError('A media reference needs one owner');
    }
    final assets = <MediaAsset>[];
    for (final id in ids) {
      final asset = await _asset(s, a.app.id!, id, tx: tx);
      if (asset.status != 'ready' || !await _visible(s, a, asset, tx)) {
        fail('invalidInput', 'Choose a ready image from this app.');
      }
      assets.add(asset);
    }
    final previous = await MediaReference.db.find(
      s,
      where: (t) =>
          t.appId.equals(a.app.id!) &
          (draftId != null
              ? t.draftId.equals(draftId)
              : versionId != null
              ? t.versionId.equals(versionId)
              : t.recordId.equals(recordId)),
      transaction: tx,
    );
    await MediaReference.db.deleteWhere(
      s,
      where: (t) =>
          t.appId.equals(a.app.id!) &
          (draftId != null
              ? t.draftId.equals(draftId)
              : versionId != null
              ? t.versionId.equals(versionId)
              : t.recordId.equals(recordId)),
      transaction: tx,
    );
    for (final asset in assets) {
      await MediaReference.db.insertRow(
        s,
        MediaReference(
          appId: a.app.id!,
          assetRowId: asset.id!,
          draftId: draftId,
          versionId: versionId,
          recordId: recordId,
        ),
        transaction: tx,
      );
    }
    // The grace period starts when the last reference is removed, not when the
    // upload originally happened. Touching retained refs is conservative too.
    for (final id in {
      ...previous.map((r) => r.assetRowId),
      ...assets.map((a) => a.id!),
    }) {
      final asset = await MediaAsset.db.findById(s, id, transaction: tx);
      if (asset == null) continue;
      asset.updatedAt = clock();
      await MediaAsset.db.updateRow(s, asset, transaction: tx);
    }
  }

  /// Structure-only remix must never retain access to another app's images.
  static AppSpec withoutAssets(AppSpec spec) {
    final json = jsonDecode(spec.canonical) as Map<String, dynamic>;
    for (final view in json['views'] as List) {
      if (view['type'] == 'banner') {
        (view['options'] as Map?)?.remove('imageAssetId');
      }
    }
    return AppSpec.parse(jsonEncode(json));
  }

  static Future<void> cleanup(Session s) async {
    final originals = await MediaAsset.db.find(
      s,
      where: (t) => t.status.equals('ready') & t.originalRemoved.equals(false),
      limit: 10,
    );
    for (final asset in originals) {
      await _removeOriginal(s, asset);
    }
    final ids = await s.db.unsafeQuery(
      'SELECT a.id FROM nest_media_asset a WHERE NOT EXISTS '
      '(SELECT 1 FROM nest_media_reference ref WHERE ref."assetRowId"=a.id) AND '
      '(a.status=\'deleting\' OR (a.status<>\'ready\' AND a."expiresAt"<@now) OR '
      '(a.status=\'ready\' AND a."updatedAt"<@cutoff)) ORDER BY a."updatedAt" LIMIT 10',
      parameters: QueryParameters.named({
        'now': clock(),
        'cutoff': clock().subtract(const Duration(hours: 24)),
      }),
    );
    final candidates = <MediaAsset>[];
    for (final id in ids) {
      final row = await MediaAsset.db.findById(s, id.first as int);
      if (row != null) candidates.add(row);
    }
    for (final candidate in candidates) {
      try {
        final deleting = await s.db.transaction((tx) async {
          await MiniApp.db.findById(
            s,
            candidate.appId,
            transaction: tx,
            lockMode: LockMode.forUpdate,
          );
          final row = await MediaAsset.db.findById(
            s,
            candidate.id!,
            transaction: tx,
          );
          if (row == null || (row.leaseUntil?.isAfter(clock()) ?? false)) {
            return null;
          }
          if (await MediaReference.db.count(
                s,
                where: (t) => t.assetRowId.equals(row.id!),
                transaction: tx,
              ) >
              0) {
            return null;
          }
          if (row.status == 'ready' &&
              !row.updatedAt.isBefore(
                clock().subtract(const Duration(hours: 24)),
              )) {
            return null;
          }
          row.status = 'deleting';
          row.leaseUntil = null;
          return MediaAsset.db.updateRow(s, row, transaction: tx);
        });
        if (deleting == null) continue;
        for (final variant in ['original', 'display', 'thumbnail']) {
          await s.storage.deleteFile(
            storageId: 'private',
            path: path(deleting, variant),
          );
        }
        await MediaAsset.db.deleteRow(s, deleting);
      } catch (_) {
        s.log('media_cleanup_retry asset_row=${candidate.id}');
      }
    }
  }
}
