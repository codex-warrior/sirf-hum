// Test-only fakes for the device identity layer. The key store is an
// in-memory stand-in for the Android Keystore / iOS Keychain adapter.
import 'dart:io';
import 'dart:typed_data';

import 'package:sirf_hum/security/device/device_key_store.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// CI sets this so missing native crypto fails instead of skipping.
final bool requireNative =
    Platform.environment['SIRF_HUM_REQUIRE_NATIVE_CRYPTO'] == '1';

/// Skip reason when the native core is not built for this host.
final Object nativeSkip = CryptoCore.isAvailable || requireNative
    ? false
    : 'no native crypto core on this host';

class FakeDeviceKeyStore implements DeviceKeyStore {
  FakeDeviceKeyStore(this.root);

  final Directory root;
  final Map<String, Uint8List> keys = {};
  final List<Uint8List> handedOut = [];
  int created = 0;

  @override
  bool isSupported = true;

  @override
  Future<String> slotDirectory(String slot) async =>
      (Directory('${root.path}/$slot')..createSync(recursive: true)).path;

  @override
  Future<Uint8List?> storeKey(String slot, {required bool create}) async {
    if (create) {
      created++;
      keys[slot] = Uint8List.fromList(
        List.generate(
          32,
          (i) => (i * 31 + created * 17 + slot.length) % 255 + 1,
        ),
      );
    }
    final key = keys[slot];
    if (key == null) return null;
    final copy = Uint8List.fromList(key);
    handedOut.add(copy);
    return copy;
  }

  @override
  Future<void> removeSlot(String slot) async {
    keys.remove(slot);
    final dir = Directory('${root.path}/$slot');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
