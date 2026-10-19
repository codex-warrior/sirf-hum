import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/platform/io_media_files.dart';
import 'package:sirf_hum/platform/secure_key_store.dart';
import 'package:sirf_hum/security/device/local_device_identity.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// ABI v6 encrypted media on a real device (Android emulator in CI) with the
/// REAL platform key store: objects in each account's backup-excluded slot,
/// keys only in sealed history, tampering refused, and a throughput
/// baseline (reported, not asserted). Throwaway accounts; slots removed.
/// Run: `flutter test integration_test/media_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const keyStore = PlatformSecureKeyStore();
  final service = LocalDeviceIdentityService(keyStore: keyStore);
  final accountA = AccountId('itMediaA');
  final accountB = AccountId('itMediaB');
  final cid = ConversationId(Uint8List.fromList(List.filled(16, 0x3c)));

  Future<void> clean() async {
    await service.removeAccount(accountA);
    await service.removeAccount(accountB);
  }

  setUp(clean);
  tearDown(clean);

  Future<(CryptoCore, String)> open(AccountId account) async {
    final result = await service.open(account);
    expect(result, isA<LocalIdentityReady>(), reason: '$result');
    final slot = await keyStore.slotDirectory(
      LocalDeviceIdentityService.slotFor(account),
    );
    return (
      (result as LocalIdentityReady).core,
      IoMediaFiles.mediaDirectoryOf(slot),
    );
  }

  Uint8List data(int length) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) (i * 31) % 256]);

  test('media round trip, tampering and baseline on the device', () async {
    final (a, aMedia) = await open(accountA);
    final (b, bMedia) = await open(accountB);
    a.trustVerifiedPersonKey(b.publicIdentity().personKey);
    b.trustVerifiedPersonKey(a.publicIdentity().personKey);
    final staged = a.createConversationGroup(cid, [b.keyPackage()]);
    a.confirmCommit(cid, staged.fromEpoch);
    b.joinConversation(cid, staged.welcome!);

    final inputs = Directory.systemTemp.createTempSync('it_media_in_');
    addTearDown(() => inputs.deleteSync(recursive: true));

    ({SentMedia sent, String received}) transfer(Uint8List bytes) {
      final input = File('${inputs.path}/picked.bin')..writeAsBytesSync(bytes);
      final sent = a.sendMedia(
        cid,
        inputPath: input.path,
        mediaDirectory: aMedia,
        mediaClass: MediaClass.video,
      );
      input.deleteSync();
      final r = b.receiveMessage(
        cid,
        messageId: sent.message.messageId,
        sender: a.publicIdentity().deviceId,
        epoch: sent.message.epoch,
        schemaVersion: MessageVersions.schema,
        protocolVersion: MessageVersions.protocol,
        ciphertext: sent.message.ciphertext,
        serverTimeMs: 1,
      );
      expect(MediaRefView.decode(r.payload).mediaId, sent.mediaId);
      // "Download": copy the ciphertext object into B's own slot.
      final name = mediaObjectFileName(cid, sent.mediaId);
      final received = File('$aMedia/$name').copySync('$bMedia/$name').path;
      return (sent: sent, received: received);
    }

    final small = data(100000);
    final t = transfer(small);
    expect(b.openMedia(cid, t.sent.message.messageId, t.received), small);

    final tampered = File(t.received).readAsBytesSync()..[500] ^= 1;
    File('${t.received}.bad').writeAsBytesSync(tampered);
    expect(
      () => b.openMedia(cid, t.sent.message.messageId, '${t.received}.bad'),
      throwsA(
        isA<CryptoException>().having(
          (e) => e.code,
          'code',
          CryptoErrorCode.authenticationFailure,
        ),
      ),
    );

    // Keys are sealed under the platform key: still opens after reopening.
    a.close();
    b.close();
    final (b2, _) = await open(accountB);
    expect(b2.openMedia(cid, t.sent.message.messageId, t.received), small);
    b2.close();

    // Throughput baseline on this device (reported, not asserted).
    final (a3, _) = await open(accountA);
    final (b3, _) = await open(accountB);
    for (final mib in [1, 8, 32]) {
      final bytes = data(mib * 1024 * 1024);
      final input = File('${inputs.path}/big.bin')..writeAsBytesSync(bytes);
      final clock = Stopwatch()..start();
      final sent = a3.sendMedia(
        cid,
        inputPath: input.path,
        mediaDirectory: aMedia,
        mediaClass: MediaClass.video,
      );
      final encryptMs = clock.elapsedMilliseconds;
      b3.receiveMessage(
        cid,
        messageId: sent.message.messageId,
        sender: a3.publicIdentity().deviceId,
        epoch: sent.message.epoch,
        schemaVersion: MessageVersions.schema,
        protocolVersion: MessageVersions.protocol,
        ciphertext: sent.message.ciphertext,
        serverTimeMs: 2,
      );
      clock
        ..reset()
        ..start();
      final plain = b3.openMedia(
        cid,
        sent.message.messageId,
        '$aMedia/${mediaObjectFileName(cid, sent.mediaId)}',
      );
      final decryptMs = clock.elapsedMilliseconds;
      expect(plain.length, bytes.length);
      wipeBytes(plain);
      debugPrint(
        'media_baseline mib=$mib encrypt_ms=$encryptMs decrypt_ms=$decryptMs '
        'object_bytes=${sent.objectLength}',
      );
    }
    a3.close();
    b3.close();
  });
}
