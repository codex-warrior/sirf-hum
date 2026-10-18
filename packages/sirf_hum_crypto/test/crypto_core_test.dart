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

      test('platform key store is never opened through initialize', () {
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

  group(
    'device identity (Prompt 07)',
    () {
      late Directory dir;
      Uint8List key(int byte) => Uint8List.fromList(List.filled(32, byte));
      CryptoCore open(int byte) => CryptoCore.initializeWithPlatformKey(
        directory: dir.path,
        storeKey: key(byte),
      );

      setUp(() => dir = Directory.systemTemp.createTempSync('sh_device_'));
      tearDown(() => dir.deleteSync(recursive: true));

      test('platform store key opens, restores, and is wiped after use', () {
        final storeKey = key(5);
        final core = CryptoCore.initializeWithPlatformKey(
          directory: dir.path,
          storeKey: storeKey,
        );
        expect(storeKey.every((b) => b == 0), isTrue);
        final id = core.createIdentity(AccountId('account-a')).deviceId;
        core.close();
        final again = open(5);
        expect(again.publicIdentity().deviceId, id);
        again.close();
      });

      test('an unmodifiable store key (channel-decoded) still opens', () {
        // Regression: wiping must not throw and mask the open result.
        final core = CryptoCore.initializeWithPlatformKey(
          directory: dir.path,
          storeKey: key(5).asUnmodifiableView(),
        );
        core.createIdentity(AccountId('account-a'));
        core.close();
      });

      test('a different store key cannot open the state', () {
        open(5)
          ..createIdentity(AccountId('account-a'))
          ..close();
        expect(() => open(6), _fails(CryptoErrorCode.stateCorruption));
      });

      test('malformed store keys are refused', () {
        for (final bad in [Uint8List(32), Uint8List(31), Uint8List(33)]) {
          expect(
            () => CryptoCore.initializeWithPlatformKey(
              directory: dir.path,
              storeKey: bad,
            ),
            _fails(CryptoErrorCode.invalidInput),
          );
        }
      });

      test('account check binds the identity to one account', () {
        final core = open(5);
        expect(
          () => core.checkAccount(AccountId('account-a')),
          _fails(CryptoErrorCode.identityState),
        );
        core.createIdentity(AccountId('account-a'));
        core.checkAccount(AccountId('account-a'));
        expect(
          () => core.checkAccount(AccountId('account-b')),
          _fails(CryptoErrorCode.accountMismatch),
        );
        core.close();
      });

      test('device proof is a 64-byte signature bound to the challenge', () {
        final core = open(5)..createIdentity(AccountId('account-a'));
        final c1 = Uint8List.fromList(List.filled(32, 1));
        final c2 = Uint8List.fromList(List.filled(32, 2));
        final p1 = core.deviceProof(DeviceProofPurpose.activation, c1);
        expect(p1, hasLength(64));
        // Ed25519 is deterministic: same input, same proof; new challenge, new proof.
        expect(core.deviceProof(DeviceProofPurpose.activation, c1), p1);
        expect(core.deviceProof(DeviceProofPurpose.activation, c2), isNot(p1));
        for (final bad in [Uint8List(0), Uint8List(31), Uint8List(33)]) {
          expect(
            () => core.deviceProof(DeviceProofPurpose.activation, bad),
            _fails(CryptoErrorCode.invalidInput),
          );
        }
        core.close();
      });

      test('no proof without an identity', () {
        final core = open(5);
        expect(
          () => core.deviceProof(DeviceProofPurpose.activation, Uint8List(32)),
          _fails(CryptoErrorCode.identityState),
        );
        core.close();
      });
    },
    skip: available
        ? false
        : (_required ? false : 'no native crypto core on this host'),
  );

  group(
    'multi-device trust (Prompt 08)',
    () {
      late Directory root;
      late CryptoCore a;
      late CryptoCore b;
      final challenge = Uint8List.fromList(List.filled(32, 4));
      const expires = 1800000000;

      CryptoCore open(String name, int keyByte) {
        final core = CryptoCore.initializeWithPlatformKey(
          directory: (Directory('${root.path}/$name')..createSync()).path,
          storeKey: Uint8List.fromList(List.filled(32, keyByte)),
        );
        core.createIdentity(AccountId('accountA'));
        return core;
      }

      setUp(() {
        root = Directory.systemTemp.createTempSync('sh_trust_');
        a = open('a', 11);
        b = open('b', 12);
      });
      tearDown(() {
        a.close();
        b.close();
        root.deleteSync(recursive: true);
      });

      test('two devices of one account have independent identities', () {
        final ia = a.publicIdentity();
        final ib = b.publicIdentity();
        expect(ia.deviceId, isNot(ib.deviceId));
        expect(ia.personKey, isNot(ib.personKey));
      });

      test('approval is a 64-byte signature; self-approval is refused', () {
        final sig = a.approveDevice(
          newCertificate: b.publicIdentity().certificate,
          challenge: challenge,
          expiresAtUnix: expires,
        );
        expect(sig, hasLength(64));
        expect(
          () => a.approveDevice(
            newCertificate: a.publicIdentity().certificate,
            challenge: challenge,
            expiresAtUnix: expires,
          ),
          _fails(CryptoErrorCode.invalidInput),
        );
        expect(
          () => a.approveDevice(
            newCertificate: b.publicIdentity().certificate,
            challenge: challenge,
            expiresAtUnix: -1,
          ),
          _fails(CryptoErrorCode.invalidInput),
        );
      });

      test('comparison code is six digits and bound to device + challenge', () {
        final cert = b.publicIdentity().certificate;
        final code = CryptoCore.approvalCode(
          newCertificate: cert,
          challenge: challenge,
        );
        expect(code, inInclusiveRange(0, 999999));
        expect(
          CryptoCore.approvalCode(newCertificate: cert, challenge: challenge),
          code,
        );
        expect(
          CryptoCore.approvalCode(
            newCertificate: a.publicIdentity().certificate,
            challenge: challenge,
          ),
          isNot(code),
        );
      });

      test(
        'recovery key: created once, typed on a new device, typos caught',
        () {
          final bundle = a.createRecoveryKey(
            challenge: challenge,
            expiresAtUnix: expires,
          );
          expect(bundle.secret, startsWith('SHRK1-'));
          expect(bundle.publicKey, hasLength(32));
          expect(bundle.registrationSignature, hasLength(64));
          expect(bundle.toString(), contains('<redacted>'));
          final approval = b.recoveryApproval(
            recoveryKey: bundle.secret.toLowerCase(),
            challenge: challenge,
            expiresAtUnix: expires,
          );
          expect(approval.signature, hasLength(64));
          expect(approval.recoveryPublicKey, bundle.publicKey);
          final typo =
              '${bundle.secret.substring(0, bundle.secret.length - 1)}'
              '${bundle.secret.endsWith('A') ? 'B' : 'A'}';
          expect(
            () => b.recoveryApproval(
              recoveryKey: typo,
              challenge: challenge,
              expiresAtUnix: expires,
            ),
            _fails(CryptoErrorCode.recoveryKeyInvalid),
          );
        },
      );

      test('enrollment proofs are a separate purpose from activation', () {
        final c1 = a.deviceProof(DeviceProofPurpose.activation, challenge);
        final c2 = a.deviceProof(DeviceProofPurpose.enrollment, challenge);
        expect(c1, isNot(c2));
      });
    },
    skip: available
        ? false
        : (_required ? false : 'no native crypto core on this host'),
  );
}
