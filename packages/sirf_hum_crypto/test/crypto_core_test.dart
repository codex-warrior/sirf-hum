// End-to-end tests through the real native library (built by hook/build.dart).
// TEST ONLY: uses the insecure test key stores.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';
import 'package:test/test.dart';

// CI sets this so a missing native build fails instead of skipping.
final bool _required =
    Platform.environment['SIRF_HUM_REQUIRE_NATIVE_CRYPTO'] == '1';

Matcher _fails(CryptoErrorCode code) =>
    throwsA(isA<CryptoException>().having((e) => e.code, 'code', code));

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

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

  void restart() {
    core.close();
    core = CryptoCore.initialize(
      directory: dir.path,
      keyStore: KeyStoreKind.insecureTestFile,
    );
  }

  Uint8List open(Uint8List ciphertext) =>
      (core.processIncoming(ciphertext) as IncomingApplication).plaintext;
}

void main() {
  final available = CryptoCore.isAvailable;

  test(
    'native crypto core is bundled when required',
    () {
      expect(available, isTrue, reason: 'native asset missing or ABI mismatch');
    },
    skip: _required || available ? false : 'no native crypto core on this host',
  );

  group(
    'native',
    () {
      late Directory root;
      late _Device alice;
      late _Device bob;
      late GroupId gid;

      setUp(() {
        root = Directory.systemTemp.createTempSync('sh_crypto_test_');
        alice = _Device(
          Directory('${root.path}/alice')..createSync(),
          'account-alice',
        );
        bob = _Device(
          Directory('${root.path}/bob')..createSync(),
          'account-bob',
        );
        alice.core.trustVerifiedPersonKey(bob.public.personKey);
        bob.core.trustVerifiedPersonKey(alice.public.personKey);
        gid = alice.core.createGroup();
        final added = alice.core.addMember(gid, bob.core.keyPackage());
        expect(bob.core.join(added.welcome), gid);
      });

      tearDown(() {
        alice.core.close();
        bob.core.close();
        root.deleteSync(recursive: true);
      });

      test('two devices exchange messages both ways', () {
        expect(
          bob.open(alice.core.encrypt(gid, _bytes('hi bob'))),
          _bytes('hi bob'),
        );
        expect(
          alice.open(bob.core.encrypt(gid, _bytes('hi alice'))),
          _bytes('hi alice'),
        );
        expect(alice.core.epoch(gid), bob.core.epoch(gid));
        final roster = alice.core.roster(gid).map((e) => e.deviceId).toSet();
        expect(roster, {alice.public.deviceId, bob.public.deviceId});
      });

      test('state survives restart and keeps working', () {
        final before = bob.core.epoch(gid);
        alice.restart();
        bob.restart();
        expect(bob.core.epoch(gid), before);
        expect(alice.core.publicIdentity().deviceId, alice.public.deviceId);
        expect(
          bob.open(alice.core.encrypt(gid, _bytes('after restart'))),
          _bytes('after restart'),
        );
      });

      test('commits advance both devices', () {
        final commit = alice.core.selfUpdate(gid);
        final result = bob.core.processIncoming(commit);
        expect(
          result,
          isA<IncomingCommit>().having(
            (c) => c.epoch,
            'epoch',
            alice.core.epoch(gid),
          ),
        );
      });

      test('tampered message is rejected and state stays usable', () {
        final ct = alice.core.encrypt(gid, _bytes('real'));
        final epoch = bob.core.epoch(gid);
        final tampered = Uint8List.fromList(ct)..[ct.length - 1] ^= 0x01;
        expect(
          () => bob.core.processIncoming(tampered),
          throwsA(isA<CryptoException>()),
        );
        expect(bob.core.epoch(gid), epoch);
        expect(bob.open(ct), _bytes('real'));
      });

      test('replay is rejected', () {
        final ct = alice.core.encrypt(gid, _bytes('once'));
        bob.open(ct);
        expect(
          () => bob.core.processIncoming(ct),
          _fails(CryptoErrorCode.replay),
        );
      });

      test('oversized input is rejected before processing', () {
        expect(
          () => bob.core.processIncoming(Uint8List(128 * 1024 + 1)),
          _fails(CryptoErrorCode.inputTooLarge),
        );
        expect(
          () => alice.core.encrypt(gid, Uint8List(64 * 1024 + 1)),
          _fails(CryptoErrorCode.inputTooLarge),
        );
      });

      test('garbage is rejected with a category, not a crash', () {
        expect(
          () => bob.core.processIncoming(Uint8List(0)),
          throwsA(isA<CryptoException>()),
        );
        expect(
          () => bob.core.processIncoming(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<CryptoException>()),
        );
        expect(
          () => bob.core.join(Uint8List(10)),
          throwsA(isA<CryptoException>()),
        );
      });

      test('removed device learns it was removed and cannot read on', () {
        final commit = alice.core.removeMember(gid, bob.public.deviceId);
        expect(bob.core.processIncoming(commit), isA<IncomingRemoved>());
        expect(() => bob.core.epoch(gid), _fails(CryptoErrorCode.unknownGroup));
        expect(
          () => bob.core.processIncoming(alice.core.encrypt(gid, _bytes('x'))),
          throwsA(isA<CryptoException>()),
        );
      });

      test('untrusted person cannot be added', () {
        final mallory = _Device(
          Directory('${root.path}/mallory')..createSync(),
          'account-mallory',
        );
        addTearDown(mallory.core.close);
        final epoch = alice.core.epoch(gid);
        expect(
          () => alice.core.addMember(gid, mallory.core.keyPackage()),
          _fails(CryptoErrorCode.unauthorizedDevice),
        );
        expect(alice.core.epoch(gid), epoch);
      });

      test('wipe deletes local state', () {
        alice.core.wipe();
        expect(
          () => alice.core.publicIdentity(),
          _fails(CryptoErrorCode.identityState),
        );
        alice.restart();
        expect(
          () => alice.core.publicIdentity(),
          _fails(CryptoErrorCode.identityState),
        );
      });

      test('corrupted state fails closed on open', () {
        bob.core.close();
        final record = File('${bob.dir.path}/mls_state.shrec');
        final bytes = record.readAsBytesSync()..[40] ^= 0xff;
        record.writeAsBytesSync(bytes);
        expect(
          () => CryptoCore.initialize(
            directory: bob.dir.path,
            keyStore: KeyStoreKind.insecureTestFile,
          ),
          _fails(CryptoErrorCode.stateCorruption),
        );
        // Give tearDown a live handle to close.
        final fresh = Directory('${root.path}/fresh')..createSync();
        bob.core = CryptoCore.initialize(
          directory: fresh.path,
          keyStore: KeyStoreKind.insecureTestEphemeral,
        );
      });

      test('platform key store is not implemented and says so', () {
        expect(
          () => CryptoCore.initialize(
            directory: '${root.path}/p',
            keyStore: KeyStoreKind.platform,
          ),
          _fails(CryptoErrorCode.unsupported),
        );
      });

      test('closed handle is unusable', () {
        alice.core.close();
        expect(
          () => alice.core.publicIdentity(),
          _fails(CryptoErrorCode.invalidInput),
        );
        alice.core.close(); // idempotent
        alice.restart();
      });

      test('identity material prints redacted', () {
        for (final value in [
          alice.public,
          alice.public.deviceId,
          alice.public.personKey,
          gid,
        ]) {
          expect(value.toString(), contains('<redacted>'));
        }
      });
    },
    skip: available
        ? false
        : (_required ? false : 'no native crypto core on this host'),
  );
}
