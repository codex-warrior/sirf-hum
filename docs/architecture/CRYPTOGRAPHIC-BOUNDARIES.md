# Cryptographic Boundaries

Status: **Design (Prompt 04); crypto core, KeyStore, persistence and agility boundaries defined and platform feasibility measured (Prompt 05). Not implemented in the app.** Where plaintext and keys may
exist in code, and how the crypto core connects to Flutter and Firebase.
Labels follow [E2EE-ARCHITECTURE](../security/E2EE-ARCHITECTURE.md#labels).

## Layering (RECOMMENDED)

```text
┌──────────────────────── Flutter (Dart) ─────────────────────────┐
│ features/*/presentation   ◄── plaintext for display only         │
│ features/*/application                                            │
│ lib/security/  (Dart facade: small typed API, no key material)   │
│      │  narrow C ABI + dart:ffi, or flutter_rust_bridge (D-063)   │
├──────┼───────────────────── Rust crypto core ────────────────────┤
│ sirf_hum_crypto (our crate, thin):                                │
│   - OpenMLS 0.9.1 (pinned, D-054) + crypto provider               │
│   - storage provider → encrypted SQLite (KEK from platform)       │
│   - credential validation (PIK certificates, roster policy)       │
│   - media AEAD (secretstream) — binding UNRESOLVED                 │
│   - exports: EncryptedEnvelope bytes, plaintext to facade only    │
├──────────────────────── Platform ────────────────────────────────┤
│ lib/platform + Kotlin/Swift: Keystore/Keychain KEK wrap/unwrap    │
└───────────────────────────────────────────────────────────────────┘
lib/infrastructure (Firebase SDK)  ◄── EncryptedEnvelope, public keys, metadata ONLY
```

### Rules

1. **Private keys and epoch secrets never cross into Dart.** The Rust core
   owns them. The Dart facade gets handles and results.
2. **Plaintext crosses into Dart** only as the result of a successful
   decrypt (for display) or as input to encrypt. It is never logged:
   `AppLogger` redacts strings by construction. It is never persisted
   unencrypted.
3. **`lib/infrastructure` accepts only `EncryptedEnvelope`** for private
   content (existing rule; type in
   `lib/security/crypto/encrypted_envelope.dart`), plus public keys and
   non-secret metadata.
4. **Our Rust crate contains no cryptographic algorithms.** It only
   composes:
   - OpenMLS;
   - the chosen AEAD library;
   - the credential policy (which PIKs are allowed; revocation list), which
     is application logic, not cryptography.
5. **Dependencies inside the boundary are minimized and pinned.** Every
   crate inside the crypto core is reviewed on upgrade.
6. **Debug features that log secrets** (OpenMLS `crypto-debug`,
   `content-debug`) are forbidden by CI policy (to be enforced when the core
   exists).

## Platform builds (feasibility measured in Prompt 05)

Evidence: `prototypes/mls-decision-gate` (GitHub Actions run 38887400583).
This is feasibility only, not the production bridge.

| Target | Result | Notes |
| --- | --- | --- |
| Android | ✔ `cdylib` built for arm64-v8a, armeabi-v7a, x86_64 with the app's pinned NDK 28.2 at API 24. Stripped `.so`: OpenMLS 2.48/1.74/2.97 MB | `CARGO_TARGET_*_LINKER` set to NDK clang; no Gradle integration yet |
| iOS | ✔ static libs for `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`; XCFramework created with `xcodebuild -create-xcframework` (no signing) | Static archives are unstripped (38 MB OpenMLS before linking); the final app-size impact must be measured after linking |
| Dart ↔ Rust | ✔ `dart:ffi` test (3/3) calls the C ABI on Linux and macOS: create, add, join, encrypt, decrypt, remove, commit processing; tamper/replay rejected through FFI | Opaque handles only; panics caught at the boundary |
| Web | ✔ all scenarios pass on wasm32 under Node (wasm-bindgen-test); release wasm 2.70 MB (OpenMLS) | "WASM works" is **not** "web E2EE is acceptable"; see below |

### Flutter integration path (UNRESOLVED; decide in Prompt 06)

| Option | For | Against |
| --- | --- | --- |
| **Own narrow C ABI + `dart:ffi`**, bundled with Flutter **native assets / build hooks** (enabled by default on Flutter 3.41 stable) | Smallest surface; no codegen; first-party Flutter mechanism; ABI reviewed by hand | Hand-written bindings; no web path (wasm needs a separate JS/wasm-bindgen layer) |
| **flutter_rust_bridge** 2.13.0 (stable on crates.io) | Generated bindings incl. web; async support | Larger generated surface to review; codegen toolchain in CI |

Either way, the API stays narrow: no "export key" or "dump state"
functions.

### Web: technical feasibility vs. security acceptability

- **Technical:** the MLS core runs in wasm32 (measured).
- **Security:** unchanged. **Web V1 does not handle private E2EE content**
  (D-046, approved direction). Code delivered on every load, XSS,
  extensions and browser storage remain unmitigated
  ([WEB-SECURITY](../security/WEB-SECURITY.md)). Web may offer account and
  device management, linking and security settings.

## Crypto-core API (narrow; RECOMMENDED shape)

The Rust core exposes operations, never secrets:

```text
identity:   create_device_identity() -> DeviceHandle           // keys generated inside, stored via KeyStore
            device_public_info(DeviceHandle) -> {deviceId, signature public key}
            publish_key_packages(DeviceHandle, n) -> [KeyPackage bytes]
group:      create_couple_group(DeviceHandle) -> GroupHandle
            add_devices(GroupHandle, [KeyPackage bytes]) -> {commit, welcome}
            remove_device(GroupHandle, deviceId) -> commit
            self_update(GroupHandle) -> commit
            join(DeviceHandle, welcome) -> GroupHandle
            process(GroupHandle, bytes) -> Commit{rosterChange} | Application{plaintext} | Rejected{reason}
            encrypt(GroupHandle, plaintext) -> bytes (EncryptedEnvelope)
            roster(GroupHandle) -> [{personFingerprint, deviceId}]
lifecycle:  delete_device_identity(DeviceHandle)               // wipes keys + state
```

Rules:
- `process` runs inside a storage transaction. On *any* failure it rolls
  back (rejected-forgery mitigation).
- Credential policy runs inside `process`/`join` before anything merges
  (OpenMLS has no identity-provider hook).
- Inputs are size-limited before parsing.

## KeyStore boundary (interface only; no real keys yet)

The crypto core depends on this interface. It never depends on Firebase.

```text
KeyStore
  save(id: KeyId, material: SecretBytes, policy: AccessPolicy) -> Result
  load(id: KeyId) -> Result<SecretBytes | NotFound>
  delete(id: KeyId) -> Result
  exists(id: KeyId) -> bool
  wipe_all() -> Result                    // device removal / logout
AccessPolicy = { this_device_only: true, requires_unlock: AfterFirstUnlock | UserPresence }
```

In practice the KeyStore holds **one key-encryption key (KEK)**. All MLS
state lives in the encrypted local store (below), wrapped by that KEK.

| Platform | Mapping |
| --- | --- |
| Android | Android Keystore non-exportable AES-256-GCM KEK (StrongBox when present), app UID only; excluded from backup |
| iOS | Keychain item `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (Secure Enclave can wrap via P-256, since it does not hold X25519/Ed25519); stale items wiped on fresh install |
| Web | **Separate, higher-risk model**: non-extractable Web Crypto key in IndexedDB. Not used for private content in V1 |

## Persistence abstraction (what must persist)

| State | Why | Notes |
| --- | --- | --- |
| Device signature key pair + credential | Sign commits/messages | Secret; KEK-wrapped |
| Unused KeyPackage private init keys (+ last resort) | Join via Welcome | Delete on use |
| Group state per group: tree, group context, epoch, interim/confirmed transcript hashes | Process future messages | Secret parts KEK-wrapped |
| Epoch secrets / secret tree (current + retained past epochs) | Decrypt in-epoch and late messages | Window = D-060; deleted as epochs advance |
| Sender-ratchet generations (replay protection) | Reject replays | Must persist **atomically with** group state |
| Pending commit (own, not yet confirmed by the delivery service) | Merge on confirmation, discard on conflict | Cleared on conflict |
| Pending proposals (if by-reference proposals are used) | Commit correctness | — |
| Application dedupe set (`clientMessageId`) | Idempotent UI | Not secret |

**Atomicity rule:** each `process`/`encrypt`/commit call is one local
transaction. Failure means rollback; nothing partial is persisted (SRLabs
S1-3). Local only: **never** Firestore.

## Crypto agility (required)

Every protocol record carries explicit versions so upgrades never require
guessing:

| Field | Where | Example |
| --- | --- | --- |
| `protocolVersion` | `EncryptedEnvelope` (Sirf Hum wire format) | 1 |
| MLS protocol version | MLS framing | `mls10` |
| MLS ciphersuite | MLS group context | 0x0001 |
| `implementation` | Device capability record (non-secret) | `openmls/0.9.1` |
| `schemaVersion` | Application payload inside the ciphertext | 1 |

- Unknown or unsupported versions fail closed ("update the app").
- Ciphersuite changes create a new group via MLS ReInit; there is no
  in-place downgrade.
- The harness keeps a second implementation (mls-rs) runnable and
  wire-interoperable, so a library switch is a contained change.

## Responsibilities

| Component | Sees plaintext private content? | Holds private keys? | Decides trust? |
| --- | --- | --- | --- |
| UI (presentation) | Yes, rendered | No | No |
| `lib/security` Dart facade | Yes, in transit to/from the core | No | No (asks the core) |
| Rust crypto core | Yes | **Yes** | **Yes**: validates credentials and the roster |
| Platform keystore | No | KEK only | No |
| `lib/infrastructure` | **No** | No | No |
| Firebase Auth / Firestore / Storage / Functions / FCM | **No** | No | No (authorization of ciphertext access only) |
| App Check | No | No | No (client genuineness signal) |

## Firestore data shapes (illustrative; rules are designed per feature)

```text
users/{uid}/devices/{deviceId}       { pikPublic, deviceCert, sigPublic, status, fcmToken?, createdAt }
users/{uid}/keyPackages/{kpId}        { deviceId, keyPackage (public), lastResort }
couples/{coupleId}                    { members: [uidA, uidB], state, groupRef }
groups/{groupRef}/epochs/{n}          { commit (MLS bytes), committerDevice }   // create-if-absent: first wins
groups/{groupRef}/welcomes/{id}       { forDevice, welcome (MLS bytes) }
groups/{groupRef}/messages/{id}       { envelope (EncryptedEnvelope bytes), senderDevice, sentAt, size }
invites/{tokenHash}                   { inviterUid, pikFingerprint, expiresAt }  // via Function
```

All private content fields are `EncryptedEnvelope` bytes. No document
contains a plaintext message, caption, filename or private key.
