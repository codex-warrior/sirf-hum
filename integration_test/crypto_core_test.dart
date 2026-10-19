import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/security/crypto/private_content_crypto.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Proves the crypto core is bundled into the real app and works on a device
/// (Android emulator in CI). TEST ONLY: insecure test key
/// stores, throwaway identities, app-private temp storage.
/// Run: `flutter test integration_test/crypto_core_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('native core is bundled and classified development-only', () {
    expect(CryptoCore.isAvailable, isTrue);
    expect(
      privateContentCryptoSupport(),
      PrivateContentCryptoSupport.nativeDevelopmentOnly,
    );
  });

  test('two devices: create, join, exchange, restart, reject tampering', () {
    final root = Directory.systemTemp.createTempSync('sh_crypto_it_');
    addTearDown(() => root.deleteSync(recursive: true));
    CryptoCore open(String name) => CryptoCore.initialize(
      directory: (Directory('${root.path}/$name')..createSync()).path,
      keyStore: KeyStoreKind.insecureTestFile,
    );

    final alice = open('alice');
    var bob = open('bob');
    final a = alice.createIdentity(AccountId('it-alice'));
    final b = bob.createIdentity(AccountId('it-bob'));
    alice.trustVerifiedPersonKey(b.personKey);
    bob.trustVerifiedPersonKey(a.personKey);

    final group = alice.createGroup();
    final added = alice.addMember(group, bob.keyPackage());
    expect(bob.join(added.welcome), group);

    final message = Uint8List.fromList(utf8.encode('device round trip'));
    final ciphertext = alice.encrypt(group, message);
    expect(ciphertext, isNot(message));

    // Tampering is rejected and leaves the valid message processable.
    final tampered = Uint8List.fromList(ciphertext)
      ..[ciphertext.length - 1] ^= 1;
    expect(
      () => bob.processIncoming(tampered),
      throwsA(isA<CryptoException>()),
    );

    // Restart: state restored from encrypted local records.
    bob.close();
    bob = CryptoCore.initialize(
      directory: '${root.path}/bob',
      keyStore: KeyStoreKind.insecureTestFile,
    );
    final incoming = bob.processIncoming(ciphertext);
    expect((incoming as IncomingApplication).plaintext, message);
    expect(bob.epoch(group), alice.epoch(group));

    alice
      ..wipe()
      ..close();
    bob
      ..wipe()
      ..close();
  });
}
