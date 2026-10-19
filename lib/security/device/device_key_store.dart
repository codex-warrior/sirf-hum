import 'dart:typed_data';

/// Why a device key-store operation failed. Categories only: never key bytes
/// or platform messages.
enum DeviceKeyStoreFailure {
  /// The slot name was rejected.
  invalidSlot,

  /// The Keystore/Keychain refused or failed the operation.
  keystoreFailure,

  /// This platform has no key store (Web, desktop).
  unsupported,
}

class DeviceKeyStoreException implements Exception {
  const DeviceKeyStoreException(this.failure);

  final DeviceKeyStoreFailure failure;

  @override
  String toString() => 'DeviceKeyStoreException(${failure.name})';
}

/// Port for the platform key store (D-066), implemented by
/// `lib/platform/secure_key_store.dart`. One *slot* per account: a private,
/// backup-excluded directory for the crypto core's sealed state, plus that
/// slot's 32-byte store key held by the Android Keystore / iOS Keychain.
abstract interface class DeviceKeyStore {
  /// False on Web and other platforms without a native key store.
  bool get isSupported;

  /// Creates (if needed) and returns the slot's state directory.
  Future<String> slotDirectory(String slot);

  /// With [create]: a fresh random key that replaces any existing one.
  /// Without: the existing key, or null if the slot has none. The caller
  /// must wipe the returned bytes after use.
  Future<Uint8List?> storeKey(String slot, {required bool create});

  /// Deletes the slot's key, then its state. Deleting the key alone already
  /// makes the sealed state unrecoverable (crypto-erasure).
  Future<void> removeSlot(String slot);
}
