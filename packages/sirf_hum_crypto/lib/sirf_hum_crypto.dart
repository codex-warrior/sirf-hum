/// Sirf Hum crypto core: OpenMLS 0.9.1 behind a small C ABI.
///
/// **NOT production E2EE: unaudited.** Only insecure test key stores exist;
/// the platform key store is not implemented. See
/// docs/security/CRYPTO-CORE-ARCHITECTURE.md.
///
/// Dart never sees MLS objects, private keys, epoch secrets or serialized
/// state: only opaque handles, public identifiers, MLS wire messages and
/// (from [CryptoCore.processIncoming]) decrypted application content.
library;

export 'package:sirf_hum_crypto/src/core_unsupported.dart'
    if (dart.library.ffi) 'package:sirf_hum_crypto/src/core_ffi.dart'
    show CryptoCore, expectedAbiVersion;
export 'package:sirf_hum_crypto/src/types.dart';
