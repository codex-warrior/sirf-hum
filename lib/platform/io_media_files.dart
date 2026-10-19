import 'dart:io';

import 'package:sirf_hum/security/media/media_storage.dart';

/// [MediaFiles] on the local file system (Android). The media directory is
/// `<account slot>/media`: app-private, in `noBackupFilesDir`, deleted with
/// the slot (D-066, D-096). It only ever holds ciphertext objects.
///
/// Not for Web (no `dart:io`); Web has no private media (D-046).
class IoMediaFiles implements MediaFiles {
  const IoMediaFiles();

  /// Creates (if needed) and returns the media directory of an account slot.
  static String mediaDirectoryOf(String slotDirectory) {
    final dir = Directory('$slotDirectory/media')..createSync(recursive: true);
    return dir.path;
  }

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  void delete(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  void rename(String from, String to) => File(from).renameSync(to);
}
