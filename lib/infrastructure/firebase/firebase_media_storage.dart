import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:sirf_hum/security/media/media_storage.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';

/// Cloud Storage implementation of [MediaStorage] (Prompt 11, D-095; rules
/// in firebase/storage.rules). Moves **ciphertext objects only**: the files
/// it uploads and downloads are encrypted by the crypto core, whose keys
/// never reach this layer.
///
/// Objects: `conversations/{conversation}/media/{media}`, content type
/// `application/octet-stream`, custom metadata exactly `{sd: deviceId}`
/// (the rules check that device is active). No filename, MIME type, class
/// or cache headers are ever set.
///
/// Needs a Cloud Storage bucket, i.e. the Blaze plan (D-025): until then it
/// runs against the emulator only. Android only (`dart:io`); Web has no
/// private media (D-046).
class FirebaseMediaStorage implements MediaStorage {
  FirebaseMediaStorage({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// The only content type an object ever has (the rules require it).
  static const String contentType = 'application/octet-stream';

  /// The object's metadata: the uploading device, nothing else.
  static SettableMetadata metadataFor(String senderDeviceIdHex) =>
      SettableMetadata(
        contentType: contentType,
        customMetadata: {'sd': senderDeviceIdHex},
      );

  static String objectPath(String conversationIdHex, String mediaIdHex) =>
      'conversations/$conversationIdHex/media/$mediaIdHex';

  Reference _ref(String c, String m) => _storage.ref(objectPath(c, m));

  @override
  Future<MediaUploadOutcome> upload({
    required String conversationIdHex,
    required String mediaIdHex,
    required String senderDeviceIdHex,
    required String filePath,
  }) async {
    try {
      await _ref(
        conversationIdHex,
        mediaIdHex,
      ).putFile(File(filePath), metadataFor(senderDeviceIdHex));
      return MediaUploadOutcome.uploaded;
    } on FirebaseException catch (e) {
      // Rules refusals (including "already exists": objects are
      // create-only) versus not reaching the server. Codes only.
      return e.code == 'unauthorized'
          ? MediaUploadOutcome.refused
          : MediaUploadOutcome.unavailable;
    }
  }

  @override
  Future<StoredMediaObject?> stat({
    required String conversationIdHex,
    required String mediaIdHex,
  }) async {
    try {
      final meta = await _ref(conversationIdHex, mediaIdHex).getMetadata();
      return StoredMediaObject(
        size: meta.size ?? -1,
        senderDeviceIdHex: meta.customMetadata?['sd'],
      );
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return null;
      throw TransportException(
        e.code == 'unauthorized' || e.code == 'unauthenticated'
            ? TransportFailure.denied
            : TransportFailure.unavailable,
      );
    }
  }

  @override
  Future<MediaDownloadOutcome> download({
    required String conversationIdHex,
    required String mediaIdHex,
    required int expectedSize,
    required String destinationPath,
  }) async {
    final ref = _ref(conversationIdHex, mediaIdHex);
    final file = File(destinationPath);
    try {
      // Size first: a larger object than the authenticated reference says
      // is never fetched (no unbounded download into the cache).
      final meta = await ref.getMetadata();
      if (meta.size != expectedSize) return MediaDownloadOutcome.wrongSize;
      await ref.writeToFile(file);
      if (file.lengthSync() != expectedSize) {
        await _discard(file);
        return MediaDownloadOutcome.wrongSize;
      }
      return MediaDownloadOutcome.downloaded;
    } on FirebaseException catch (e) {
      await _discard(file);
      return e.code == 'object-not-found'
          ? MediaDownloadOutcome.notFound
          : MediaDownloadOutcome.unavailable;
    } on FileSystemException {
      await _discard(file);
      return MediaDownloadOutcome.unavailable;
    }
  }

  static Future<void> _discard(File file) async {
    if (file.existsSync()) file.deleteSync();
  }
}
