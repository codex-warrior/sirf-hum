# Crypto Core Architecture

Status: **Foundation implemented (Prompt 06). Sirf Hum is NOT production
E2EE yet.**

- Nothing here has been independently reviewed.
- The platform key store exists (Prompt 07, D-066); the insecure test
  key stores are refused in release builds.
- No product feature uses the core.

Code lives in `packages/sirf_hum_crypto/`. Decisions: D-054–D-068 in the
[Decision Log](../decisions/DECISION-LOG.md).

## Layers

```
Flutter app (lib/security/crypto/private_content_crypto.dart)
  └─ Dart facade        packages/sirf_hum_crypto/lib/      typed API, no MLS types
      └─ C ABI          native/src/ffi.rs                  opaque handle, (ptr,len), i32 codes
          └─ Rust core  native/src/engine.rs               credential policy, limits, checkpoints
              ├─ OpenMLS 0.9.1 + openmls_rust_crypto 0.6.0 (D-054)
              ├─ sealed records  native/src/record.rs      XChaCha20-Poly1305 (RustCrypto)
              ├─ CryptoStore     native/src/store.rs       atomic file replace
              └─ KEK provider    native/src/keystore.rs    test adapters only
```

The wrapper stays thin. It adds no cryptographic construction:

- MLS is OpenMLS;
- signatures are Ed25519 through `OpenMlsCrypto`;
- record sealing uses an AEAD from a reviewed crate.

The wrapper's own code is policy:

- which credentials are acceptable;
- size limits;
- checkpoint and rollback;
- the record format;
- error mapping.

## Boundaries

| Boundary | Rule | Enforced by |
| --- | --- | --- |
| **Trust** | Device-local: plaintext and keys exist only inside the app process on the device. The server, network, Firebase and Web are outside. | Architecture; no network code in the core |
| **Rust** | Owns all MLS state, private keys, epoch secrets and serialized state. Secrets are `Zeroizing` and wiped on drop, rollback and wipe. | `engine.rs` |
| **Dart** | Sees an opaque handle, public identifiers, MLS wire messages, error codes, decrypted application content from `processIncoming`, and (Prompt 08) a new recovery key's text exactly once for display, plus a user-typed recovery key going in. Never sees keys, OpenMLS objects or state bytes. | `ffi.rs` surface (no export function exists); `core_ffi.dart` |
| **Identity** | Distinct types for each kind of identity material (table below). | `identity.rs`, `types.dart` |
| **Storage** | Local only, app-private directory. Every record is sealed. Never written to Firestore or any server. | `store.rs`, `record.rs`; no Firebase dependency in the package |
| **Secure storage** | The store key (Rust: KEK) comes from a `KeyEncryptionKeyProvider`. The platform adapter supplies a per-account key (Android Keystore-wrapped / iOS `ThisDeviceOnly` Keychain) via `sh_crypto_open_with_platform_key` (D-066, [DEVICE-IDENTITY](DEVICE-IDENTITY.md)). Test adapters are refused in release builds. | `keystore.rs` (`PlatformProvidedKey`); `lib/platform/secure_key_store.dart` |
| **Firebase** | No crypto state, keys or plaintext. Only `EncryptedEnvelope` may reach infrastructure (already the rule). The package does not depend on Firebase. | Dependency graph; existing Security Rules unchanged |
| **Web** | No private-content E2EE in V1 (D-046). Web compiles a stub where every call throws `unsupported`. | Conditional export on `dart.library.ffi`; `types_test.dart`; app test |
| **Errors** | 21 stable `i32` codes (`account_mismatch` -18, Prompt 07; `recovery_key_invalid` -19, Prompt 08; `trust_state_stale` -20 and `trust_chain_invalid` -21, Prompt 09). No strings, payloads or native messages cross the ABI. Unknown codes become `internal`. | `error.rs`, `CryptoErrorCode` |
| **Dependencies** | Exact pins; OpenMLS versions fixed (D-054); `cargo audit --deny warnings` with three documented ignores, re-verified on every run, for code that is never compiled or never shipped (D-068) | `tool/check_crypto_core.sh`, `tool/crypto_audit.sh` |
| **Logging** | The core never logs. CI fails on printing/logging macros or crates in `src/` and on OpenMLS `crypto-debug`/`content-debug` features. Dart types print `<redacted>`. App-side logging goes through `AppLogger` with category names only. | `tool/check_crypto_core.sh`, the source-scan test, clippy `print_*`/`dbg_macro` deny, redaction tests |

### Identity material

| Type | Meaning | Secret? |
| --- | --- | --- |
| `AccountId` | Server account (1–128 bytes) | No; still redacted in output |
| `PersonKey` | Person Identity Key, public half (Ed25519) | No |
| *person private key* | Signs device certificates | **Yes**: Rust only, sealed `identity_secret` record |
| `DeviceId` | 16 random bytes, inside the certificate | No |
| *device signature key* | The MLS leaf signature key | **Yes**: Rust only |
| `DeviceCertificate` | `"SirfHum-DeviceCertificate-v1"` ‖ version ‖ person key ‖ device ID ‖ device signature key ‖ issued-at, signed by the person key (D-064) | No |
| MLS credential | `BasicCredential` whose identity bytes are the encoded certificate | No |

**Validation** (D-057) runs at our boundary before anything is merged. It
covers every KeyPackage we add, every Welcome roster, every commit's
adds/updates/path leaf, and the sender of every message. The checks, in
order:

1. Basic credential type.
2. Strict certificate decode.
3. Person-key signature.
4. The person key is in the trust policy.
5. The device is not revoked.
6. The certificate's device key equals the leaf's signature key.

The trust policy holds the device's own person key and person keys the user
has verified out of band (`trustVerifiedPersonKey`). Verification UX is the
pairing phase's job.

## Local state

There are up to four records, `{name}.shrec`, in the app-private directory:

| Record | Kind | Contents |
| --- | --- | --- |
| `identity_secret` | IdentitySecret | Account ID, person and device private keys, certificate |
| `public_metadata` | PublicMetadata | Non-secret identity data (still sealed) |
| `mls_state` | MlsState | The full OpenMLS storage map, group IDs, trust policy, revocations |
| `trust_epoch` | TrustEpoch (kind 4, Prompt 09) | The highest account trust epoch this device has seen (D-083) |

**Record format v1** (D-065):

```
magic "SHCR" | format u16 = 1 | kind u8 | reserved u8 | nonce[24] | XChaCha20-Poly1305(KEK, plaintext)
```

The AAD is the header plus the length-prefixed record name. A record
therefore cannot be swapped to another name, changed in kind, edited, or
opened with another KEK: each of those fails authentication. Unknown format
or state versions fail closed. Every failure is `stateCorruption`, and the
core refuses to open rather than silently starting empty.

**Atomicity.** Each put writes a temp file, fsyncs it, renames it over the
old file, and fsyncs the directory (Unix). The MLS state is one record, so
an operation is all-or-nothing on disk.

The identity and state records are independent. A crash between them leaves
an identity with empty MLS state, which is consistent, because loading
always re-trusts the device's own person key.

**Size bound.** Records over 8 MiB are rejected before they are read into
memory.

**Wipe.** Deletes all `.shrec` and temp files and zeroizes memory. On flash
storage, deletion is not secure erasure; protection of residual data
depends on the KEK being destroyed. The platform adapter must make that
possible (D-066).

## Checkpoint / rollback model

Every operation that changes MLS state runs inside `transact`:

```
checkpoint (copy of storage map + group IDs + trust)  ─►  operation  ─►  persist sealed state
             ▲                                               │ error         │ error
             └──────────────── rollback ◄────────────────────┴───────────────┘
```

- **Rejected input** (forged, malformed, wrong epoch, unauthorized,
  replayed): the core rolls back, returns the category, and leaves memory
  and disk exactly as before. A later genuine message still decrypts. This
  mitigates the Prompt 05 finding that a rejected forgery consumes the
  message key (D-056).
- **Persistence failure:** the core rolls back and returns
  `persistenceFailure`. Memory never runs ahead of disk.
- **Rollback failure:** the core is *poisoned*. Every later call returns
  `rollbackFailure` until the app reopens it from disk, which holds the
  last committed state.
- **Size limits** run before parsing (table below), so oversized input never
  reaches OpenMLS.

| Limit | Value |
| --- | --- |
| Plaintext | 64 KiB |
| Incoming MLS message | 128 KiB |
| KeyPackage | 16 KiB |
| Welcome | 128 KiB |
| Certificate | 512 B |
| Account ID | 128 B |
| Record | 8 MiB |
| Group members | 16 |

All limits are defined in `limits.rs` and tested at the boundary and one
byte over it.

**Versioning** (D-061): the record format, identity and state schema
versions, ciphersuite `0x0001` and `IMPLEMENTATION = "openmls/0.9.1"` are
explicit. `ABI_VERSION` (currently 4: platform store key, account check and device proof in Prompt 07; device approval, comparison code and recovery key in Prompt 08; signed revocation, reset cancellation, trust epoch and lineage verification in Prompt 09, [MULTI-DEVICE-TRUST](MULTI-DEVICE-TRUST.md)) is checked by Dart; a mismatch means
`isAvailable == false`.

## Platform integration (D-063)

- `hook/build.dart` uses the first-party `hooks`/`code_assets` 1.0.0, the
  versions Flutter 3.41.5's own tool uses.
- It runs `cargo build --locked --release` for the target triple and
  bundles `libsirf_hum_crypto` as a dynamic code asset:
  - Android: arm64-v8a, armeabi-v7a and x86_64 `.so`, NDK clang as linker,
    16 KB page alignment;
  - iOS: device and simulator framework.
- Targets without a core (Windows, Web) get no asset, and the API reports
  `isAvailable == false`.
- The Rust toolchain is pinned to 1.96.0 by `rust-toolchain.toml`.
- Android and iOS builds therefore need rustup. On Windows, local Android
  builds also need the MSVC Build Tools (build scripts are host binaries).
- Calls are synchronous on the calling isolate. Moving them to a background
  isolate is a later performance change; it is not a security change.

The app sees only `privateContentCryptoSupport()`:

- `nativeDevelopmentOnly`: core bundled, with the platform key store, but
  unreviewed and used by no feature;
- `unavailableOnWeb`;
- `unavailable`.

No value means production E2EE.

## Threat assumptions

**In scope and mitigated:**

- malicious or compromised server/network injecting, replaying, tampering
  with, reordering or truncating MLS messages (MLS authentication plus
  rollback);
- a malicious member adding an uncertified or untrusted device (boundary
  validation on every receiver);
- oversized inputs (limits);
- local state tampering or corruption (AEAD; fail closed);
- record swapping (AAD binds the name);
- panics reaching Dart (caught at every entry point).

**Assumed:**

- the device OS and app sandbox are not compromised;
- the platform keystore, once built, protects the KEK;
- OpenMLS, openmls_rust_crypto and RustCrypto implement their algorithms
  correctly.

**Not mitigated yet (open):**

- **Local rollback of the whole state directory** to an older snapshot. No
  monotonic counter exists. This needs hardware-backed storage or a counter
  (D-066).
- **Message withholding.** The server can drop messages; gap detection is
  unresolved (THREAT-MODEL E10).
- **Plaintext copies in the Dart heap.** Garbage-collected memory cannot
  be reliably wiped. Native copies are wiped; Dart copies are not.
- **Retained plaintext.** Content already decrypted by a removed device
  stays with that device (inherent to E2EE).
- **Past-epoch window.** It is 0, so messages sent before a commit and
  arriving after it are rejected (D-060 open).
- **Test key stores.** Refused in release builds (Prompt 07). `insecureTestFile` stores the KEK as a plaintext
  file next to the state. It must never be used for real users.

## What remains unaudited

Everything in this package has had no independent review:

- the credential policy and certificate format;
- the record format;
- the FFI;
- checkpoint/rollback;
- the build hook.

Neither has the OpenMLS 0.9.1 delta since the SRLabs-audited commit, or the
providers. The D-054 conditions remain open. **No security claim may be
made from this foundation.**

## Tests

| Layer | Where | Runs |
| --- | --- | --- |
| Rust core: lifecycle, persistence, rollback (Part 5 scenarios A–I), credentials, limits, errors, log scan | `native/tests/`, `engine.rs` unit test | CI `crypto-core` (Linux) |
| Dart facade through the real library | `test/crypto_core_test.dart` (`SIRF_HUM_REQUIRE_NATIVE_CRYPTO=1` turns skip into failure) | CI `crypto-core` |
| Types, error table, redaction, Web stub | `test/types_test.dart` | Everywhere |
| App classification | `test/security/private_content_crypto_test.dart` | `flutter test` |
| Real app on device | `integration_test/crypto_core_test.dart` | CI Android emulator + iOS simulator |
| Packaging | `.so` per ABI in the APK; framework in `Runner.app` | CI Android + iOS builds |
| Regression (Prompt 05) | `prototypes/mls-decision-gate` | `prototypes.yml` |

The full list is in [E2EE-TEST-PLAN](../testing/E2EE-TEST-PLAN.md).
