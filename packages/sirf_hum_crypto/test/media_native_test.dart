// ABI v6 media end to end through the real native library (CI: crypto-core
// job, SIRF_HUM_REQUIRE_NATIVE_CRYPTO=1). TEST ONLY: insecure test key
// stores. Prompt 11, docs/security/E2EE-MEDIA-AND-NOTIFICATIONS.md.
import 'dart:io';
import 'dart:typed_data';

import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';
import 'package:test/test.dart';

final bool _required =
    Platform.environment['SIRF_HUM_REQUIRE_NATIVE_CRYPTO'] == '1';

Matcher _fails(CryptoErrorCode code) =>
    throwsA(isA<CryptoException>().having((e) => e.code, 'code', code));

class _Device {
  _Device(this.dir, String account) {
    core = CryptoCore.initialize(
      directory: dir.path,
      keyStore: KeyStoreKind.insecureTestFile,
    );
    public = core.createIdentity(AccountId(account));
  }

  final Directory dir;
  late CryptoCore core;
  late PublicIdentity public;
}

Uint8List _plaintext(int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (i * 7) % 256]);

void main() {
  final available = CryptoCore.isAvailable;

  group(
    'media (ABI v6)',
    () {
      late Directory root;
      late _Device a;
      late _Device b;
      final cid = ConversationId(Uint8List.fromList(List.filled(16, 5)));

      setUp(() {
        root = Directory.systemTemp.createTempSync('sh_media_test_');
        Directory('${root.path}/media').createSync();
        a = _Device(Directory('${root.path}/a')..createSync(), 'accountA');
        b = _Device(Directory('${root.path}/b')..createSync(), 'accountB');
        a.core.trustVerifiedPersonKey(b.public.personKey);
        b.core.trustVerifiedPersonKey(a.public.personKey);
        final staged = a.core.createConversationGroup(cid, [
          b.core.keyPackage(),
        ]);
        a.core.confirmCommit(cid, 0);
        b.core.joinConversation(cid, staged.welcome!);
      });

      tearDown(() {
        a.core.close();
        b.core.close();
        root.deleteSync(recursive: true);
      });

      String objectPath(SentMedia m) =>
          '${root.path}/media/${mediaObjectFileName(cid, m.mediaId)}';

      SentMedia send(Uint8List data, {MediaClass c = MediaClass.image}) {
        final input = File('${root.path}/input.bin')..writeAsBytesSync(data);
        final sent = a.core.sendMedia(
          cid,
          inputPath: input.path,
          mediaDirectory: '${root.path}/media',
          mediaClass: c,
        );
        input.deleteSync();
        return sent;
      }

      ReceivedMessage receive(SentMedia m) => b.core.receiveMessage(
        cid,
        messageId: m.message.messageId,
        sender: a.public.deviceId,
        epoch: m.message.epoch,
        schemaVersion: MessageVersions.schema,
        protocolVersion: MessageVersions.protocol,
        ciphertext: m.message.ciphertext,
        serverTimeMs: 7,
      );

      test('round trip: the receiver gets the view, then the plaintext', () {
        final data = _plaintext(70000);
        final m = send(data, c: MediaClass.video);
        final object = File(objectPath(m));
        expect(object.lengthSync(), m.objectLength);
        expect(m.objectLength, MediaLimits.objectLength(70000));

        final r = receive(m);
        expect(r.payload, hasLength(MediaRefView.length));
        final view = MediaRefView.decode(r.payload);
        expect(view.mediaId, m.mediaId);
        expect(view.mediaClass, MediaClass.video);
        expect(view.plaintextLength, 70000);
        expect(view.objectLength, m.objectLength);

        expect(b.core.openMedia(cid, m.message.messageId, object.path), data);
        expect(a.core.openMedia(cid, m.message.messageId, object.path), data);
        for (final d in [a, b]) {
          final media = d.core
              .history(cid)
              .singleWhere((h) => h.messageId == m.message.messageId);
          expect(MediaRefView.decode(media.payload).mediaId, m.mediaId);
        }
      });

      test('a modified or truncated object fails closed', () {
        final data = _plaintext(1000);
        final m = send(data);
        receive(m);
        final object = File(objectPath(m));
        final genuine = object.readAsBytesSync();
        final tampered = File('${root.path}/tampered.shm');
        for (final bytes in [
          Uint8List.fromList(genuine)..[30] ^= 1,
          Uint8List.fromList(genuine)..[genuine.length - 1] ^= 1,
          genuine.sublist(0, genuine.length - 1),
        ]) {
          tampered.writeAsBytesSync(bytes);
          expect(
            () => b.core.openMedia(cid, m.message.messageId, tampered.path),
            _fails(CryptoErrorCode.authenticationFailure),
          );
        }
        expect(b.core.openMedia(cid, m.message.messageId, object.path), data);
      });

      test('Dart cannot forge a media reference; unknown media fails', () {
        expect(
          () => a.core.sendMessage(cid, Uint8List.fromList([1, 2, 0, 0])),
          _fails(CryptoErrorCode.invalidInput),
        );
        final m = send(_plaintext(10));
        // Not received yet: no key on this device.
        expect(
          () => b.core.openMedia(cid, m.message.messageId, objectPath(m)),
          _fails(CryptoErrorCode.invalidInput),
        );
      });

      test('limits: empty input refused, nothing left behind', () {
        final empty = File('${root.path}/empty.bin')..writeAsBytesSync([]);
        expect(
          () => a.core.sendMedia(
            cid,
            inputPath: empty.path,
            mediaDirectory: '${root.path}/media',
            mediaClass: MediaClass.file,
          ),
          _fails(CryptoErrorCode.invalidInput),
        );
        expect(Directory('${root.path}/media').listSync(), isEmpty);
        expect(a.core.history(cid), isEmpty);
      });
    },
    skip: available
        ? false
        : (_required ? false : 'no native crypto core on this host'),
  );
}
