import 'dart:io';
import 'dart:typed_data';

import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/media/media_storage.dart';
import 'package:sirf_hum/security/messaging/conversation_transport.dart';

class StoredObject {
  StoredObject(this.bytes, this.senderDeviceIdHex);

  Uint8List bytes;
  final String senderDeviceIdHex;
}

/// In-memory object store enforcing the Storage rules' semantics
/// (firebase/storage.rules, D-095): create-only objects, written only by an
/// active device of the caller's account, size-capped; plus the network
/// faults the service must survive. A "malicious server" can swap or edit
/// stored bytes directly through [objects].
class FakeMediaStorage implements MediaStorage {
  FakeMediaStorage({required this.uploaderStatus});

  /// Server-side status of the uploading device.
  final DeviceStatus Function(String deviceHex) uploaderStatus;

  final objects = <String, StoredObject>{};

  bool offline = false;

  /// The next upload stops midway: nothing is stored (Storage finalizes
  /// objects only on completion).
  bool interruptNextUpload = false;

  /// The next upload lands but its acknowledgement is lost.
  bool loseNextUploadAck = false;

  /// The next download stops midway, leaving a partial file behind.
  bool interruptNextDownload = false;

  int uploads = 0;
  int downloads = 0;

  static String key(String c, String m) => '$c/$m';

  @override
  Future<MediaUploadOutcome> upload({
    required String conversationIdHex,
    required String mediaIdHex,
    required String senderDeviceIdHex,
    required String filePath,
  }) async {
    if (offline) return MediaUploadOutcome.unavailable;
    if (interruptNextUpload) {
      interruptNextUpload = false;
      return MediaUploadOutcome.unavailable;
    }
    final k = key(conversationIdHex, mediaIdHex);
    final bytes = File(filePath).readAsBytesSync();
    if (objects.containsKey(k) ||
        uploaderStatus(senderDeviceIdHex) != DeviceStatus.active ||
        bytes.isEmpty ||
        bytes.length > 67125273) {
      return MediaUploadOutcome.refused;
    }
    uploads++;
    objects[k] = StoredObject(bytes, senderDeviceIdHex);
    if (loseNextUploadAck) {
      loseNextUploadAck = false;
      return MediaUploadOutcome.unavailable;
    }
    return MediaUploadOutcome.uploaded;
  }

  @override
  Future<StoredMediaObject?> stat({
    required String conversationIdHex,
    required String mediaIdHex,
  }) async {
    if (offline) throw const TransportException(TransportFailure.unavailable);
    final o = objects[key(conversationIdHex, mediaIdHex)];
    return o == null
        ? null
        : StoredMediaObject(
            size: o.bytes.length,
            senderDeviceIdHex: o.senderDeviceIdHex,
          );
  }

  @override
  Future<MediaDownloadOutcome> download({
    required String conversationIdHex,
    required String mediaIdHex,
    required int expectedSize,
    required String destinationPath,
  }) async {
    if (offline) return MediaDownloadOutcome.unavailable;
    final o = objects[key(conversationIdHex, mediaIdHex)];
    if (o == null) return MediaDownloadOutcome.notFound;
    if (o.bytes.length != expectedSize) return MediaDownloadOutcome.wrongSize;
    downloads++;
    if (interruptNextDownload) {
      interruptNextDownload = false;
      File(destinationPath).writeAsBytesSync(o.bytes.sublist(0, 10));
      return MediaDownloadOutcome.unavailable;
    }
    File(destinationPath).writeAsBytesSync(o.bytes);
    return MediaDownloadOutcome.downloaded;
  }
}
