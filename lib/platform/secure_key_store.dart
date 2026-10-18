import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sirf_hum/security/device/device_key_store.dart';

/// The app-owned platform key store (D-066, KEY-MANAGEMENT.md §3 option a),
/// implementing the security layer's [DeviceKeyStore] port:
///
/// - Android: a non-exportable Keystore AES-GCM key (StrongBox when
///   available) wraps each slot's store key; everything lives in
///   `noBackupFilesDir` (`android/.../SecureKeyStore.kt`).
/// - iOS: `ThisDeviceOnly`, non-synchronizing Keychain items; the crypto
///   directory is excluded from backup (`ios/Runner/SecureKeyStore.swift`).
class PlatformSecureKeyStore implements DeviceKeyStore {
  const PlatformSecureKeyStore({
    MethodChannel channel = const MethodChannel(channelName),
    bool? supported,
  }) : _channel = channel,
       _supportedOverride = supported;

  static const channelName = 'com.sirfhum.app/secure_key_store';

  final MethodChannel _channel;
  final bool? _supportedOverride;

  /// Android and iOS only. Web has no private-content E2EE in V1 (D-046).
  @override
  bool get isSupported =>
      _supportedOverride ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));

  @override
  Future<String> slotDirectory(String slot) async =>
      (await _call<String>('slotDirectory', {'slot': slot}))!;

  @override
  Future<Uint8List?> storeKey(String slot, {required bool create}) =>
      _call<Uint8List>('storeKey', {'slot': slot, 'create': create});

  @override
  Future<void> removeSlot(String slot) =>
      _call<void>('removeSlot', {'slot': slot});

  Future<T?> _call<T>(String method, Map<String, Object> arguments) async {
    if (!isSupported) {
      throw const DeviceKeyStoreException(DeviceKeyStoreFailure.unsupported);
    }
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      return switch (e.code) {
        // A missing key is a normal state (first run), not a failure.
        'key_missing' => null,
        'invalid_slot' => throw const DeviceKeyStoreException(
          DeviceKeyStoreFailure.invalidSlot,
        ),
        _ => throw const DeviceKeyStoreException(
          DeviceKeyStoreFailure.keystoreFailure,
        ),
      };
    } on MissingPluginException {
      throw const DeviceKeyStoreException(DeviceKeyStoreFailure.unsupported);
    }
  }
}
