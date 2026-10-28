import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'media_store.dart';

/// Server-only Storage REST transport. Each staging file is <=256 KiB and each
/// sanitized variant <=5 MiB, the official Dart SDK's single-request threshold.
/// Neither a user JWT nor a public permission is sent to Storage.
class AppwritePrivateFiles implements PrivateFileStore {
  AppwritePrivateFiles(this.endpoint, this.project, this.bucket, this.key);
  final Uri endpoint;
  final String project, bucket, key;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  static final _id = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,35}$');

  Uri _uri(String? id, [String suffix = '']) {
    if (id != null && !_id.hasMatch(id))
      throw const ServiceException('invalid_id', 400);
    final base = endpoint.toString().replaceFirst(RegExp(r'/$'), '');
    return Uri.parse(
      '$base/storage/buckets/${Uri.encodeComponent(bucket)}/files'
      '${id == null ? '' : '/${Uri.encodeComponent(id)}'}$suffix',
    );
  }

  Future<HttpClientRequest> _open(String method, Uri uri) async {
    final request = await _client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 8));
    request.followRedirects = false;
    request.headers.set('X-Appwrite-Project', project);
    request.headers.set('X-Appwrite-Key', key);
    return request;
  }

  Future<Uint8List> _bytes(HttpClientResponse response, int maximum) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw RestException(response.statusCode);
    }
    final result = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (result.length + chunk.length > maximum)
        throw const ServiceException('media_integrity', 502);
      result.add(chunk);
    }
    return result.takeBytes();
  }

  Future<Map<String, dynamic>> _metadata(String id) async {
    final request = await _open('GET', _uri(id));
    final bytes = await _bytes(
      await request.close().timeout(const Duration(seconds: 15)),
      16384,
    );
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>)
      throw const ServiceException('media_integrity', 502);
    return data;
  }

  void _private(Map<String, dynamic> data, String id) {
    if (data[r'$id'] != id ||
        data['bucketId'] != bucket ||
        data[r'$permissions'] is! List ||
        (data[r'$permissions'] as List).isNotEmpty ||
        data['chunksTotal'] is! int ||
        data['chunksUploaded'] != data['chunksTotal'] ||
        (data['chunksTotal'] as int) < 1)
      throw const ServiceException('media_integrity', 502);
  }

  @override
  Future<void> put(String id, Uint8List bytes, String contentType) async {
    if (!_id.hasMatch(id)) throw const ServiceException('invalid_id', 400);
    if (bytes.isEmpty ||
        bytes.length > MediaLimits.maxOriginalBytes ||
        !{
          'image/jpeg',
          'image/png',
          'application/octet-stream',
        }.contains(contentType))
      throw const ServiceException('invalid_media', 400);
    final request = await _open('POST', _uri(null));
    // All names/MIME are generated here, never supplied filenames or headers.
    final boundary = 'tinkerloom_${sha256.convert(utf8.encode(id))}';
    final start = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="fileId"\r\n\r\n$id\r\n'
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="private.bin"\r\n'
      'Content-Type: $contentType\r\n\r\n',
    );
    final end = utf8.encode('\r\n--$boundary--\r\n');
    request.headers.set(
      'Content-Type',
      'multipart/form-data; boundary=$boundary',
    );
    request.contentLength = start.length + bytes.length + end.length;
    request.add(start);
    request.add(bytes);
    request.add(end);
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode == 409) {
      await response.drain<void>();
      final metadata = await _metadata(id);
      _private(metadata, id);
      if (metadata['sizeOriginal'] != bytes.length)
        throw const ServiceException('operation_conflict', 409);
      final existing = await read(id, maximumBytes: bytes.length);
      if (sha256.convert(existing).toString() !=
          sha256.convert(bytes).toString())
        throw const ServiceException('operation_conflict', 409);
      return;
    }
    // With a server execution key there is no current-user default grant. Empty
    // arrays emit no multipart fields, matching the official SDK. Check the
    // authoritative resulting permissions rather than assuming that default.
    final metadata = jsonDecode(utf8.decode(await _bytes(response, 16384)));
    if (metadata is! Map<String, dynamic>)
      throw const ServiceException('media_integrity', 502);
    _private(metadata, id);
    if (metadata['sizeOriginal'] != bytes.length)
      throw const ServiceException('media_integrity', 502);
  }

  @override
  Future<Uint8List> read(String id, {required int maximumBytes}) async {
    final metadata = await _metadata(id);
    _private(metadata, id);
    final length = metadata['sizeOriginal'];
    if (length is! int || length < 1 || length > maximumBytes)
      throw const ServiceException('media_integrity', 502);
    final request = await _open('GET', _uri(id, '/download'));
    final bytes = await _bytes(
      await request.close().timeout(const Duration(seconds: 15)),
      maximumBytes,
    );
    if (bytes.length != length)
      throw const ServiceException('media_integrity', 502);
    return bytes;
  }

  @override
  Future<void> remove(String id) async {
    final request = await _open('DELETE', _uri(id));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final status = response.statusCode;
    await response.drain<void>();
    if (status != 404 && (status < 200 || status >= 300))
      throw RestException(status);
  }

  void close() => _client.close(force: true);
}
