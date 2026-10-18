import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/crypto/private_content_crypto.dart';

void main() {
  test('Web never gets private-content crypto, even if a core existed', () {
    expect(
      privateContentCryptoSupport(isWeb: true, nativeAvailable: () => true),
      PrivateContentCryptoSupport.unavailableOnWeb,
    );
  });

  test('native core present is development-only, never production', () {
    expect(
      privateContentCryptoSupport(isWeb: false, nativeAvailable: () => true),
      PrivateContentCryptoSupport.nativeDevelopmentOnly,
    );
  });

  test('missing native core fails closed', () {
    expect(
      privateContentCryptoSupport(isWeb: false, nativeAvailable: () => false),
      PrivateContentCryptoSupport.unavailable,
    );
  });

  test('no support value claims production E2EE', () {
    for (final value in PrivateContentCryptoSupport.values) {
      expect(value.name.toLowerCase(), isNot(contains('production')));
      expect(value.name.toLowerCase(), isNot(contains('e2ee')));
    }
  });
}
