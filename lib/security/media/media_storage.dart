/// Why a media operation stopped. Categories only: never paths, IDs or
/// content.
enum MediaFailure {
  /// This service was built without media support (e.g. Web, D-046).
  unsupported,

  /// The input file is missing, empty, not a file, or changed while it was
  /// being encrypted.
  invalidInput,

  /// The input is over the 64 MiB limit (D-093).
  tooLarge,

  /// The message is not a media message on this device (text, deleted,
  /// another account, not received yet).
  notMedia,

  /// The object is not on the server (not uploaded yet, deleted) or could
  /// not be fetched right now. Retry later; never shown as content.
  unavailable,

  /// The object failed its size, hash or AEAD check even after one fresh
  /// download. "This couldn't be opened."
  corrupted,

  /// The local ciphertext object of a queued message is gone and the
  /// server never received it: the message can never be delivered.
  objectLost,
}

class MediaException implements Exception {
  const MediaException(this.failure);

  final MediaFailure failure;

  @override
  String toString() => 'MediaException(${failure.name})';
}

/// How the server answered a create-only object upload.
enum MediaUploadOutcome {
  /// Stored.
  uploaded,

  /// Refused by the Storage rules: the object already exists (perhaps our
  /// own earlier attempt), or the caller may not write it. The caller reads
  /// the object's metadata to learn which.
  refused,

  /// Not reached (offline, interrupted): retry later. An interrupted upload
  /// never leaves a partial object.
  unavailable,
}

enum MediaDownloadOutcome {
  downloaded,

  /// No such object.
  notFound,

  /// The object's size is not what the authenticated reference says:
  /// refused before (or after) writing, never opened.
  wrongSize,

  /// Not reached or interrupted: retry later. Nothing is kept.
  unavailable,
}

/// What the server says about a stored object (public metadata only).
class StoredMediaObject {
  const StoredMediaObject({required this.size, this.senderDeviceIdHex});

  final int size;

  /// The uploading device, from the object's `sd` metadata (D-095).
  final String? senderDeviceIdHex;

  @override
  String toString() => 'StoredMediaObject(size: $size)';
}

/// Port to the ciphertext object store (D-072 pattern), implemented by
/// `lib/infrastructure/firebase/firebase_media_storage.dart`. Objects live
/// at `conversations/{conversation}/media/{media}`; they are opaque
/// ciphertext, create-only, with content type `application/octet-stream`
/// and no metadata but the uploading device (D-095).
abstract interface class MediaStorage {
  Future<MediaUploadOutcome> upload({
    required String conversationIdHex,
    required String mediaIdHex,
    required String senderDeviceIdHex,
    required String filePath,
  });

  /// Null when the object does not exist.
  Future<StoredMediaObject?> stat({
    required String conversationIdHex,
    required String mediaIdHex,
  });

  /// Writes the object to [destinationPath] only if it is exactly
  /// [expectedSize] bytes; on any other outcome nothing is left there.
  Future<MediaDownloadOutcome> download({
    required String conversationIdHex,
    required String mediaIdHex,
    required int expectedSize,
    required String destinationPath,
  });
}

/// The few file operations the media cache needs, so the security layer
/// stays free of `dart:io` (implemented by `lib/platform/io_media_files.dart`).
/// Every path is inside the account's media directory and holds ciphertext
/// only (D-096).
abstract interface class MediaFiles {
  bool exists(String path);

  /// No-op when absent.
  void delete(String path);

  /// Replaces [to] if it exists.
  void rename(String from, String to);
}

/// Media wiring for one account on one device: the object store, the file
/// operations and the account's media directory (inside its backup-excluded
/// slot, so removing the account removes the cache).
class MediaSupport {
  const MediaSupport({
    required this.storage,
    required this.files,
    required this.directory,
  });

  final MediaStorage storage;
  final MediaFiles files;
  final String directory;
}
