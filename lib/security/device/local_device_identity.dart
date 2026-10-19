import 'package:flutter/foundation.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_key_store.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Opens the crypto core with a platform store key (injectable for tests).
typedef PlatformCoreOpener =
    CryptoCore Function({
      required String directory,
      required Uint8List storeKey,
    });

/// The outcome of opening this device's identity for one account.
sealed class LocalIdentityResult {
  const LocalIdentityResult();
}

/// The identity is open. The caller owns [core] and must close it.
final class LocalIdentityReady extends LocalIdentityResult {
  const LocalIdentityReady({
    required this.core,
    required this.identity,
    required this.created,
  });

  final CryptoCore core;

  /// Public material only (device ID, person key, certificate).
  final PublicIdentity identity;

  /// True when this call created a new device identity.
  final bool created;
}

enum LocalIdentityUnavailableReason { web, noKeyStore, noNativeCore }

/// No device identity on this platform. Never degrades to an unprotected one.
final class LocalIdentityUnavailable extends LocalIdentityResult {
  const LocalIdentityUnavailable(this.reason);

  final LocalIdentityUnavailableReason reason;
}

enum LocalIdentityCorruptionReason {
  /// Sealed state exists but this device's key cannot open it (tampered,
  /// truncated, restored from another device, or the key was lost).
  undecryptable,

  /// The slot holds another account's identity.
  accountMismatch,
}

/// Local state exists but is unusable. Nothing is deleted automatically:
/// [LocalDeviceIdentityService.removeAccount] is an explicit decision, and
/// it means a NEW device identity next time (DEVICE-IDENTITY.md).
final class LocalIdentityCorrupted extends LocalIdentityResult {
  const LocalIdentityCorrupted(this.reason);

  final LocalIdentityCorruptionReason reason;
}

/// Thrown for account IDs that cannot name a local slot.
class InvalidAccountSlotException implements Exception {
  const InvalidAccountSlotException();

  @override
  String toString() => 'InvalidAccountSlotException()';
}

/// This installation's device identity, kept separately per account
/// (DEVICE-IDENTITY.md, "Account switching"):
///
/// - each account has its own slot: sealed state + its own platform store
///   key; another account's slot is never opened for it;
/// - every open re-checks inside the core that the identity belongs to the
///   requested account;
/// - logging out does nothing here (the slot stays, so logging back in
///   resumes the same device identity);
/// - [removeAccount] deletes the slot's key, then its state
///   (crypto-erasure).
class LocalDeviceIdentityService {
  LocalDeviceIdentityService({
    required DeviceKeyStore keyStore,
    bool Function()? nativeAvailable,
    PlatformCoreOpener? openCore,
    bool isWeb = kIsWeb,
  }) : _keyStore = keyStore,
       _nativeAvailable = nativeAvailable ?? (() => CryptoCore.isAvailable),
       _openCore = openCore ?? CryptoCore.initializeWithPlatformKey,
       _isWeb = isWeb;

  static final RegExp _slotPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  final DeviceKeyStore _keyStore;
  final bool Function() _nativeAvailable;
  final PlatformCoreOpener _openCore;
  final bool _isWeb;

  /// The account's local slot name. Firebase UIDs are used as-is: the slot
  /// is a local storage label, never a cryptographic identity.
  static String slotFor(AccountId account) {
    if (!_slotPattern.hasMatch(account.value)) {
      throw const InvalidAccountSlotException();
    }
    return account.value;
  }

  /// Opens (or, on first use for [account], creates) this device's identity.
  Future<LocalIdentityResult> open(AccountId account) async {
    if (_isWeb) {
      return const LocalIdentityUnavailable(LocalIdentityUnavailableReason.web);
    }
    if (!_keyStore.isSupported) {
      return const LocalIdentityUnavailable(
        LocalIdentityUnavailableReason.noKeyStore,
      );
    }
    if (!_nativeAvailable()) {
      return const LocalIdentityUnavailable(
        LocalIdentityUnavailableReason.noNativeCore,
      );
    }
    final slot = slotFor(account);
    final directory = await _keyStore.slotDirectory(slot);
    final existing = await _keyStore.storeKey(slot, create: false);
    final freshKey = existing == null;
    final key = existing ?? await _requireFreshKey(slot);

    CryptoCore core;
    try {
      core = _openCore(directory: directory, storeKey: key);
    } on CryptoException catch (e) {
      if (e.code != CryptoErrorCode.stateCorruption) rethrow;
      _log('device_identity_corrupted', 'undecryptable');
      return const LocalIdentityCorrupted(
        LocalIdentityCorruptionReason.undecryptable,
      );
    } finally {
      wipeBytes(key);
    }

    try {
      core.checkAccount(account);
      _log('device_identity_opened', 'existing');
      return LocalIdentityReady(
        core: core,
        identity: core.publicIdentity(),
        created: false,
      );
    } on CryptoException catch (e) {
      if (e.code == CryptoErrorCode.accountMismatch) {
        core.close();
        _log('device_identity_corrupted', 'account_mismatch');
        return const LocalIdentityCorrupted(
          LocalIdentityCorruptionReason.accountMismatch,
        );
      }
      if (e.code != CryptoErrorCode.identityState) {
        core.close();
        rethrow;
      }
    }

    // No identity yet. A key that predates it (e.g. an iOS Keychain item
    // surviving a reinstall) is discarded: a new identity always starts with
    // a fresh store key.
    try {
      if (!freshKey) {
        core
          ..wipe()
          ..close();
        final rotated = await _requireFreshKey(slot);
        try {
          core = _openCore(directory: directory, storeKey: rotated);
        } finally {
          wipeBytes(rotated);
        }
      }
      final identity = core.createIdentity(account);
      _log('device_identity_opened', 'created');
      return LocalIdentityReady(core: core, identity: identity, created: true);
    } on Object {
      core.close();
      rethrow;
    }
  }

  /// Removes [account]'s device identity from this installation: the store
  /// key first (crypto-erasure), then the state. The next [open] creates a
  /// NEW device identity. Revoking the old server record is separate.
  Future<void> removeAccount(AccountId account) async {
    await _keyStore.removeSlot(slotFor(account));
    _log('device_identity_removed', 'removed');
  }

  Future<Uint8List> _requireFreshKey(String slot) async {
    final key = await _keyStore.storeKey(slot, create: true);
    if (key == null) {
      throw const DeviceKeyStoreException(
        DeviceKeyStoreFailure.keystoreFailure,
      );
    }
    return key;
  }

  void _log(String event, String outcome) =>
      AppLogger.info(event, fields: {'outcome': SafeLogString(outcome)});
}
