import 'dart:typed_data';

/// The broker owns one private Appwrite bucket. Client users receive no bucket
/// or file permissions, storage URLs, paths, provider IDs, or bearer tokens.
abstract interface class PrivateFileStore {
  /// Immutable create. An existing file is success only for identical bytes and
  /// MIME, which makes a lost response recoverable without replacing originals.
  Future<void> put(String id, Uint8List bytes, String contentType);
  Future<Uint8List> read(String id, {required int maximumBytes});

  /// Missing files are already removed. Other failures must be retryable.
  Future<void> remove(String id);
}

abstract final class MediaLimits {
  static const maxOriginalBytes = 5 * 1024 * 1024;
  static const maxThumbnailBytes = 512 * 1024;
  static const maxAppBytes = 250 * 1024 * 1024;
  static const maxAppAssets = 500;
  // Leaves shared Free storage for database state and other project overhead.
  // The provider's actual project quota remains a separate enforced limit.
  static const maxProjectBytes = 1024 * 1024 * 1024;
  static const chunkBytes = 256 * 1024;
  static const maxChunks = maxOriginalBytes ~/ chunkBytes;
  static const uploadLifetime = Duration(minutes: 10);
  static const leaseLifetime = Duration(minutes: 2);
  // Exceeds the required configured maximum 900-second Function lifetime. Keep bytes
  // reserved while prior executions drain, and sweep deterministic tombstones
  // afterward; provider-side commit timing still needs Cloud acceptance.
  static const deletionQuietPeriod = Duration(minutes: 16);
  static const unreferencedGrace = Duration(hours: 24);
}
