import 'package:flutter/foundation.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// What private-content encryption this build can offer.
///
/// No value means "production E2EE": Sirf Hum is NOT production E2EE yet
/// (docs/security/CRYPTO-CORE-ARCHITECTURE.md). Features that handle private
/// content must stay off until a reviewed phase adds a production-secure
/// key store and says otherwise.
enum PrivateContentCryptoSupport {
  /// The native crypto core and the platform key store are bundled, but
  /// nothing is reviewed and no feature uses them. For development and tests
  /// only; never for real users' content.
  nativeDevelopmentOnly,

  /// Web V1 has no private-content E2EE (D-046). Private features are
  /// unavailable on Web, never silently unencrypted.
  unavailableOnWeb,

  /// No native core for this platform (or ABI mismatch): fail closed.
  unavailable,
}

/// Classifies this build. [isWeb] and [nativeAvailable] are injectable for
/// tests; defaults read the real platform.
PrivateContentCryptoSupport privateContentCryptoSupport({
  bool isWeb = kIsWeb,
  bool Function()? nativeAvailable,
}) {
  final support = isWeb
      ? PrivateContentCryptoSupport.unavailableOnWeb
      : (nativeAvailable ?? () => CryptoCore.isAvailable)()
      ? PrivateContentCryptoSupport.nativeDevelopmentOnly
      : PrivateContentCryptoSupport.unavailable;
  AppLogger.debug(
    'private_content_crypto_support',
    fields: {'support': SafeLogString(support.name)},
  );
  return support;
}
