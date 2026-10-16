# Cryptographic Boundaries

Status: **Design (Prompt 04). Not implemented.** Where plaintext and keys may
exist in code, and how the crypto core connects to Flutter and Firebase.
Labels follow [E2EE-ARCHITECTURE](../security/E2EE-ARCHITECTURE.md#labels).

## Layering (RECOMMENDED)

```text
┌──────────────────────── Flutter (Dart) ─────────────────────────┐
│ features/*/presentation   ◄── plaintext for display only         │
│ features/*/application                                            │
│ lib/security/  (Dart facade: small typed API, no key material)   │
│      │  flutter_rust_bridge (FFI on Android/iOS, wasm on web)     │
├──────┼───────────────────── Rust crypto core ────────────────────┤
│ sirf_hum_crypto (our crate, thin):                                │
│   - OpenMLS (pinned) + crypto provider                            │
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

## Platform builds (UNRESOLVED until prototyped through Flutter)

| Target | Build | Bridge | Notes |
| --- | --- | --- | --- |
| Android | Rust → `cdylib` for arm64-v8a, armeabi-v7a, x86_64 (NDK) | flutter_rust_bridge (FFI) | NDK already pinned in CI (D-040) |
| iOS | Rust → static library / XCFramework | flutter_rust_bridge (FFI) | Bitcode n/a; check App Store binary size |
| Web | Rust → wasm32 | flutter_rust_bridge web support (documented since v2) | Web v1 has no private content ([WEB-SECURITY](../security/WEB-SECURITY.md)); prove the build path anyway |

flutter_rust_bridge: MIT, actively developed. Latest stable on crates.io
was 2.12.x per docs.rs and 2.14.0 is in beta (*verify at adoption*). The
bridge is generated glue, not cryptography, but it handles plaintext
buffers: zeroize on the Rust side; avoid extra copies.

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
