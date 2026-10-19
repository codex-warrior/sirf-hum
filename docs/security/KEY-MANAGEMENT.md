# Key Management

Status: **Design (Prompt 04). Local key storage implemented (Prompts 06–07): sealed state (D-065) and the platform key store (D-066, [DEVICE-IDENTITY](DEVICE-IDENTITY.md)); unreviewed.** Labels follow
[E2EE-ARCHITECTURE](E2EE-ARCHITECTURE.md#labels).

## 1. Key inventory

| Key | Type | Created where | Lives where | Leaves the device? | Purpose |
| --- | --- | --- | --- | --- | --- |
| Person Identity Key (PIK) | Ed25519 signing key pair | Person's first device | Private: each of the person's approved devices (encrypted local store) and, if opted in, the user's encrypted recovery backup | Private part: only device-to-device (encrypted, during device add) or inside the user-held encrypted backup. Public part: published | Certifies the person's devices; anchors partner verification |
| Device certificate | PIK signature over (deviceId, device signature public key, createdAt) | Signing device | Published with the device record and inside the MLS credential | Public | Binds a device to a person |
| Device signature key | Ed25519 (MLS leaf signature key) | The device | Device only | Never | Signs MLS messages and commits |
| MLS HPKE leaf / path keys | X25519 (ciphersuite) | The device (OpenMLS) | Device only (OpenMLS storage) | Never | TreeKEM |
| KeyPackage init keys | X25519, single use | The device | Private: device; public: Firestore | Public part only | Asynchronous add |
| Epoch secrets / secret tree | Derived (MLS key schedule) | Each member | Device only; deleted as the protocol advances | Never | Message keys |
| Media object keys | 256-bit random | Sending device | Inside MLS application messages; local key cache | Only inside MLS ciphertext | Media encryption |
| Local storage wrapping key (KEK) | AES-256-GCM, non-exportable | Platform keystore | Android Keystore / iOS Keychain (+ Secure Enclave wrapping where used) | Never (non-exportable) | Encrypts the local crypto store |
| Recovery key | ≥128-bit random, shown to the user | The device | With the user (paper / password manager) | Shown to the user only | Decrypts the user's encrypted recovery backup |

**Never** in Firestore, Cloud Storage, source control, logs, analytics,
crash reports, notifications or ordinary preferences: any private key, epoch
secret, media key outside MLS ciphertext, or the recovery key (**APPROVED**
principle, Prompt 01).

## 2. Lifecycle diagrams

### Device key lifecycle

```text
 install ──► generate device signature key + deviceId (in Rust core, CSPRNG)
               │
               ▼
        request approval ──(existing device scans QR / recovery key)──► PIK signs device certificate
               │                                                              │
               ▼                                                              ▼
        upload KeyPackages (public) ◄──────────────── device record published (deviceId, cert, pubkeys)
               │
               ▼
        added to personal group + couple group (MLS Commit by an existing member)
               │
       ┌───────┴─────────── periodic MLS Update (post-compromise healing) ◄──┐
       ▼                                                                      │
   active ─────────────────────────────────────────────────────────────────────┘
       │ removed by owner / lost / unpair / reinstall
       ▼
   MLS Remove commit (others move to a new epoch) ──► device record revoked, KeyPackages + FCM token deleted
       │
       ▼
   local wipe (if the device is still reachable and honest)
```

### PIK lifecycle

```text
 first device: generate PIK ──► publish PIK public ──► partner verifies fingerprint (pairing)
        │
        ├─► new own device: PIK private transferred device-to-device (encrypted channel set up by QR)
        ├─► optional: encrypted into the recovery backup under the recovery key
        │
        └─► rotation (suspected compromise / all devices lost without recovery):
              new PIK ──► all devices re-certified ──► partner sees "safety number changed" and re-verifies
```

## 3. Mobile key storage

**RECOMMENDED design:**

1. OpenMLS state (including secrets) persists through an OpenMLS
   **storage provider** backed by SQLite in app-private storage.
   `openmls_sqlite_storage` exists; whether to use it or our own is
   **UNRESOLVED**.
2. The database is encrypted at the application layer with a data
   encryption key (DEK). The DEK is wrapped by a **non-exportable key** in
   the platform keystore (KEK). Plaintext keys exist only in process memory
   while in use.
3. Rust holds secrets in zeroizing types where the library allows. Dart
   never receives private keys or epoch secrets; it receives plaintext only
   for display ([CRYPTOGRAPHIC-BOUNDARIES](../architecture/CRYPTOGRAPHIC-BOUNDARIES.md)).

| Topic | Android | iOS |
| --- | --- | --- |
| KEK | Android Keystore AES-256-GCM, `setIsStrongBoxBacked(true)` when available (fallback TEE) | Keychain item (or Secure Enclave P-256 key used to wrap the DEK via ECIES, since the Secure Enclave cannot hold X25519/Ed25519 keys) |
| Access restriction | Non-exportable; app UID only; optional user-authentication-bound key for an app-lock mode | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (allows background message processing after first unlock); optional app-lock with `.userPresence` |
| Device unlock | Background decryption needs the key without user auth, so auth-bound keys only for an opt-in app lock | `WhenUnlocked` would block background sync/notification processing; `AfterFirstUnlock` is the trade-off |
| Backups | Exclude the crypto DB and caches from Auto Backup / device transfer (`dataExtractionRules`); Keystore keys are not backed up | `ThisDeviceOnly` keychain items are not migrated; mark DB files `isExcludedFromBackup` |
| Device migration | Not migrated. The new phone is a new device, approved by the old one | Same |
| Reinstall | Keystore keys are deleted with the app, so the device is new | **Keychain items survive app deletion.** On first launch, if no app-container marker exists, delete stale Sirf Hum keychain items; it's a new device |
| Rotation | DEK re-wrap on KEK rotation; MLS keys rotate by protocol (Updates, new KeyPackages) | Same |
| Deletion | Remove device: wipe DB, delete Keystore key | Wipe DB, delete keychain items |
| Lost / stolen | Remote revocation from another device (RECOVERY-AND-REVOCATION). An unlocked stolen phone shows what the owner sees until revoked | Same |

Flutter integration (**DECIDED in Prompt 07: (a), D-066**). The
implementation differs from the table above in two details:

- Rust holds one sealed whole-state record per slot (D-065), not SQLite.
- The platform protects a per-account 32-byte store key:
  - Android: wrapped by the Keystore key in `noBackupFilesDir`;
  - iOS: a `ThisDeviceOnly` Keychain item; there is no Secure Enclave
    wrapping yet.

The options considered were:
- **(a) a thin native module we own:** a Kotlin/Swift plugin exposing only
  "wrap/unwrap DEK" with the settings above. This is the smallest trusted
  surface.
- **(b) `flutter_secure_storage`:** BSD-3, maintained, v11.2.0 released
  2026-09-16, after a code review of its key settings per platform.

(a) is **RECOMMENDED** because the required attributes (ThisDeviceOnly,
StrongBox, backup exclusion) must be exact.

Secure hardware is not a magic shield. A keystore protects the KEK *at
rest*; any code running inside the app process (a malicious dependency, a
compromised OS) can ask it to unwrap. Minimizing dependencies inside the
crypto boundary matters as much as hardware.

## 4. Rotation and deletion rules (RECOMMENDED)

- Each device issues an MLS **Update** at least every 7 days of activity
  (value **UNRESOLVED**), and immediately after any security event:
  - unlock after a suspected compromise;
  - the app was updated after an advisory.
- KeyPackages: keep N unused (e.g. 10) + one last-resort, replenished on
  launch; old ones deleted when superseded.
- Media keys are never reused across objects.
- Deleting content deletes its key from local caches. Keys inside old MLS
  epochs are deleted by the protocol as epochs advance.
- PIK rotation is rare and user-visible. It requires partner re-verification.
