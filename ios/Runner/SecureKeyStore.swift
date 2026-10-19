import Flutter
import Foundation
import Security

/// Platform key store for the crypto core's per-account store key (D-066,
/// docs/security/KEY-MANAGEMENT.md §3, DEVICE-IDENTITY.md).
///
/// - Each account slot's 32-byte store key is a Keychain generic-password
///   item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: never
///   synchronized to iCloud Keychain and never migrated to another device by
///   a backup restore, so cloned state fails closed.
/// - The crypto directory is excluded from iCloud/iTunes backup.
/// - Keychain items survive app deletion. The Dart side asks for a *fresh*
///   key whenever no local state exists, which discards a stale item left by
///   a previous install: a reinstall is a new device.
///
/// Platform primitives only (Keychain, SecRandomCopyBytes); nothing here is
/// custom cryptography. Errors carry a category, never key bytes.
enum SecureKeyStore {
  static let channelName = "com.sirfhum.app/secure_key_store"
  private static let service = "com.sirfhum.app.store-key.v1"
  private static let storeKeyBytes = 32

  private enum Failure: Error {
    case invalidSlot, keyMissing, keystore
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in handle(call, result) }
  }

  private static func handle(_ call: FlutterMethodCall, _ result: FlutterResult) {
    do {
      switch call.method {
      case "slotDirectory":
        result(try slotDirectory(slot: try slot(call.arguments as? [String: Any])).path)
      case "storeKey":
        let args = call.arguments as? [String: Any]
        var key = try storeKey(slot: try slot(args), create: (args?["create"] as? Bool) == true)
        result(FlutterStandardTypedData(bytes: key))
        // Best effort: the codec has copied it; wipe ours.
        key.resetBytes(in: 0..<key.count)
      case "removeSlot":
        try removeSlot(slot: try slot(call.arguments as? [String: Any]))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch Failure.invalidSlot {
      result(FlutterError(code: "invalid_slot", message: nil, details: nil))
    } catch Failure.keyMissing {
      result(FlutterError(code: "key_missing", message: nil, details: nil))
    } catch {
      result(FlutterError(code: "keystore_failure", message: nil, details: nil))
    }
  }

  private static func slot(_ args: [String: Any]?) throws -> String {
    guard let slot = args?["slot"] as? String,
      slot.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil
    else { throw Failure.invalidSlot }
    return slot
  }

  /// The crypto root is excluded from backup, which covers every slot in it.
  private static func cryptoRoot() throws -> URL {
    var url = try FileManager.default
      .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("sirf_hum_crypto", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
    return url
  }

  private static func slotURL(slot: String) throws -> URL {
    try cryptoRoot().appendingPathComponent("accounts", isDirectory: true)
      .appendingPathComponent(slot, isDirectory: true)
  }

  /// One directory per account slot.
  private static func slotDirectory(slot: String) throws -> URL {
    let url = try slotURL(slot: slot)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// Deletes the key first (the slot's sealed state becomes unrecoverable at
  /// once), then the state itself.
  private static func removeSlot(slot: String) throws {
    try deleteStoreKey(slot: slot)
    let url = try slotURL(slot: slot)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private static func query(slot: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: slot,
    ]
  }

  /// create = true: a fresh random key replaces any previous item (no local
  /// state exists). create = false: the existing key, or keyMissing.
  private static func storeKey(slot: String, create: Bool) throws -> Data {
    if create {
      try deleteStoreKey(slot: slot)
      var key = Data(count: storeKeyBytes)
      let status = key.withUnsafeMutableBytes {
        SecRandomCopyBytes(kSecRandomDefault, storeKeyBytes, $0.baseAddress!)
      }
      guard status == errSecSuccess else { throw Failure.keystore }
      var add = query(slot: slot)
      add[kSecValueData as String] = key
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      add[kSecAttrSynchronizable as String] = false
      guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw Failure.keystore }
      return key
    }
    var read = query(slot: slot)
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(read as CFDictionary, &item)
    if status == errSecItemNotFound { throw Failure.keyMissing }
    guard status == errSecSuccess, let key = item as? Data, key.count == storeKeyBytes else {
      throw Failure.keystore
    }
    return key
  }

  private static func deleteStoreKey(slot: String) throws {
    let status = SecItemDelete(query(slot: slot) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keystore }
  }
}
