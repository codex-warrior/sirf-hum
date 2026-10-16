# MLS Implementation Comparison: OpenMLS vs mls-rs

Status: **Evidence for the Prompt 05 decision gate (2026-10-16).** The
decision is in [MLS-DECISION](MLS-DECISION.md).

Evidence sources (all accessed 2026-10-16):
- **Measured:** the experimental workspace `prototypes/mls-decision-gate`,
  GitHub Actions run **38887400583** (commit `5dfc426`, all 10 jobs passed);
  runner AMD EPYC 7763 ×2 vCPU, Linux (ubuntu-24.04), Rust 1.96.0, plus
  macOS for iOS.
- **Upstream:** crates.io metadata, repository source at the pinned tags,
  each project's own CI configuration, GitHub security advisories, and
  published audit reports (links at the end).

"Unknown" means we could not verify the fact. No score is given without
evidence.

## Versions evaluated

| | OpenMLS | mls-rs |
| --- | --- | --- |
| Crate / version | `openmls` **0.9.1** (crates.io 2026-10-07) | `mls-rs` **0.56.0** (crates.io 2026-08-19) |
| Upstream commit of tag | `1762090a4523cdd241f454b4058e91b64bbdc6de` (`v0.9.1`) | `8f1b43f447a792ff9307f1c2c7f54da63914870e` (`0.56.0`) |
| Companion crates used | `openmls_rust_crypto` 0.6.0, `openmls_basic_credential` 0.6.0, `openmls_traits` 0.6.0 | `mls-rs-crypto-rustcrypto` 0.22.1, `mls-rs-core` 0.27.0 |
| Features used | default (none) + `js`,`js-test` on wasm32 | `std`, `rfc_compliant`, `tree_index`, `fast_serialize` (no `rayon`) |
| Ciphersuite | `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519` (0x0001) | same (`CURVE25519_AES128`) |
| Handshake wire format | PrivateMessage (default policy) | PrivateMessage (`encrypt_control_messages = true`, set by us) |
| License | MIT | Apache-2.0 OR MIT |

## Comparison matrix

| Category | OpenMLS | mls-rs | Evidence |
| --- | --- | --- | --- |
| **RFC 9420 alignment** | Maintainers: "With two small exceptions, OpenMLS is a feature-complete implementation of RFC9420" and "performs all of RFC9420's prescribed validation checks". The two exceptions are not named (unknown) | Self-reported "100% RFC 9420 conformance"; also states it "has not yet received a full security audit by a 3rd party" | OpenMLS audit blog post; mls-rs README/docs.rs |
| **Upstream suite at pinned tag (incl. IETF vectors)** | **356 passed, 0 failed, 4 ignored** | **437 passed, 0 failed, 0 ignored** | Our CI `upstream-kats` job runs each project's own `cargo test --release` at the tag |
| **Interop (each library with the other)** | ✔ 15/15 steps | ✔ 15/15 steps | Our `interop` tests: both directions of join; app messages both ways; cross-library commits (add, remove, update); equal epoch authenticators; removed device rejects |
| **Maturity / production use** | Used (via a pinned fork) by Wire `core-crypto`; used by XMTP `libxmtp` and White Noise MDK | Developed by AWS Labs; vendored in Mozilla's comm-central tree (purpose not verified); other production users unknown | Wire `Cargo.toml`; NCC XMTP report; Least Authority MDK report; searchfox |
| **Maintenance** | Very active; 0.9.x released 2026-08/10; security fixes shipped within the same week as advisories | Active (pushed 2026-10-15); release cadence ~1–3 months (0.55.x → 0.56.0) | GitHub/crates.io |
| **Language / memory safety** | Rust; unsafe use not audited by us | Rust; same | — |
| **Android** | ✔ builds `.so` for arm64-v8a, armeabi-v7a, x86_64 (NDK 28.2, API 24) | ✔ same | CI `android` job |
| **iOS** | ✔ static libs for device + simulators, XCFramework packaged | ✔ same | CI `ios` job (macOS) |
| **Web / wasm32** | ✔ all 11 scenarios pass under Node; upstream CI also tests wasm32 | ✔ all 11 pass under Node; a WebCrypto provider exists (`mls-rs-crypto-webcrypto`, not tested) | CI `wasm` job |
| **Flutter integration** | No official Dart binding. Via our C ABI + `dart:ffi`: ✔ 3/3 Dart tests (Linux, macOS) | Same; official UniFFI bindings exist for Kotlin/Swift (`mls-rs-uniffi` 0.1.0, last release 2024-03: stale) but not Dart | CI `dart-ffi` + `ios` jobs |
| **FFI complexity** | Generic over a provider trait; the app supplies storage + crypto providers | Generic over a builder `Config` (storage, identity, rules, crypto); the type is nameable via public aliases | Our backends (~200 lines each) |
| **Credential / identity validation** | **Application's job**: no identity-provider hook; the app must inspect credentials in proposals/staged commits before merging | **`IdentityProvider` trait**: validation is called by the library for members and external senders; X.509 built in. Docs: BasicCredential "not recommended for production" | Source at tags |
| **Key storage integration** | `StorageProvider` trait (key/value); signature keys stored in the same store; providers out of audit scope | `GroupStateStorage` + `KeyPackageStorage` + `PreSharedKeyStorage` traits; SQLite/SQLCipher provider available | Source at tags |
| **Persistence model** | **Writes during processing** (e.g. `merge_pending_commit`). The audit finding S1-3 (Low, *acknowledged*, unfixed): storage writes are not atomic, so an error can desync group state from storage; the application must supply an atomic provider | **Explicit `write_to_storage()`**: the application decides when state is persisted; the trait docs ask for one atomic transaction per write | SRLabs report §8.6; mls-rs trait docs |
| **Serialization** | TLS codec (`tls_codec`); 2026 advisories: OOB panic and quadratic decoding fixed in 0.9.0, unbounded recursion fixed in 0.9.1 | `mls-rs-codec`; no published advisories | GitHub advisories |
| **Past-epoch messages** | Default keeps **0** past epochs: a message from epoch N arriving after the commit to N+1 is **rejected** (measured) | `prior_epoch` (in `rfc_compliant`) keeps some: the same late message **decrypted** (measured) | `late_message_across_epoch` observation |
| **Rejected-forgery robustness** | A forged copy (bit flipped in content ciphertext, sender data intact) is rejected, **but consumes the key**: the genuine message then fails (`SecretReuseError`) at 20/52 tested byte positions | **Same behaviour**: 28/65 positions (`KeyMissing`) | `rejected_forgery_poisoning` observation; DoS only, see §Findings |
| **Integrity / replay / outsider / removed / stale epoch** | ✔ all rejected | ✔ all rejected | Scenario tests |
| **Security audit** | **SRLabs, report v1.2 (2026-03-11)**: `openmls`, `traits`, `basic_credential` up to commit `a3402f2` (2025-10-22). Crypto + storage providers and bindings **out of scope**. 8 findings (1 High, 3 Medium, 2 Low, 2 Info), 6 mitigated, 1 Low acknowledged, 1 Info risk-accepted | **No independent audit** (project's own statement) | Report PDF; mls-rs README |
| **Audited version = version we'd ship?** | **No.** Audit predates 0.8.x/0.9.x; three advisories were published after the audit (2026-08/10) | n/a | — |
| **Known advisories** | 5 GitHub advisories (2025-09 to 2026-10), all with patched versions ≤ 0.9.1 | 0 published (absence of evidence, not of bugs) | GitHub security advisories API |
| **License** | MIT | Apache-2.0 OR MIT | crates.io |
| **Release stability** | 0.x; breaking changes between minors; storage-format migration features provided (`0-8-1-storage-format`, `migration-import`) | 0.x; frequent minor releases with breaking changes | Cargo features |
| **Upgrade risk** | Medium: API and storage format change across minors | Medium: same class | — |
| **Community / ecosystem** | Larger (≈950k crate downloads; multiple downstream messengers) | Smaller (≈380k downloads) | crates.io |
| **Performance (native, median µs, 30 runs)** | create 92 · add 550 · join 337 · remove 412 · enc/dec 1 KB 51/57 · 10 KB 93/87 · 100 KB 850/531 · restore 34 | create 153 · add 380 · join 214 · remove 440 · enc/dec 1 KB 80/50 · 10 KB 130/89 · 100 KB 757/671 · restore 4 | CI `native` bench; **both far below user-perceptible latency** |
| **Binary size** | Android arm64 2.48 MB (stripped), armv7 1.74 MB, x86_64 2.97 MB; wasm 2.70 MB | Android arm64 **1.23 MB**, armv7 0.94 MB, x86_64 1.55 MB; wasm **1.67 MB** | CI packaging jobs |
| **State snapshot size (1 peer)** | 8,273 bytes (entire provider store incl. signer and key packages) | 1,436 bytes (group state + epochs) | bench |
| **Debugging** | Debug features exist that **log secrets** (`crypto-debug`, `content-debug`); must be forbidden | Debug tree printing (`debug_tree`); no secret-logging feature found | Cargo features |
| **Long-term maintainability** | Strong ecosystem + funded audit history; post-audit parser bugs show the need for continued review | Corporate maintainer; no audit; solid engineering fit | — |

## Findings that matter for Sirf Hum (both libraries)

1. **Rejected forgeries can destroy the genuine message (DoS).**
   - Mechanism: once the encrypted sender data authenticates, both
     libraries consume the generation key before content authentication
     fails.
   - Who can exploit it: anyone who can deliver a forged copy *before* the
     real one, i.e. the server, or a member able to write a message
     document.
   - It is **not** a confidentiality or integrity break; the forgery is
     always rejected. The server can already withhold messages.
   - **Mitigation verified for both libraries:** checkpoint before
     processing untrusted input and roll back on rejection
     (`rollback_on_rejection_preserves_genuine_message`: genuine message
     preserved, replay still rejected). This requires a persistence layer
     that can checkpoint, which is natural with mls-rs' explicit writes and
     requires a transactional storage provider with OpenMLS.
2. **Wire-format policy must match** across all clients. We encrypt
   handshake messages (PrivateMessage), which also hides membership changes
   from the server.
3. **Past-epoch window is a configuration decision.** It trades delivery
   reliability for forward secrecy.

## Sirf Hum use case fit

- **Two people × up to three devices (6 members, 1 group):** ✔ both
  libraries. Every device reads every other device's message, and rosters
  and epoch authenticators converge (`six_device_couple`).
- **Lifecycle** A1,B1 → +A2 → +B2 → A2 revoked → B1 replaced → A1 offline
  during traffic and a commit, then reconnects: ✔ both
  (`device_lifecycle`).
- **Revocation:** a removed device (offline or online) cannot read later
  messages; epoch advances by one. **Limitation verified and documented:**
  plaintext it decrypted earlier stays with it.
- **Epoch rotation / stale state:** new epoch ⇒ new authenticator. Restored
  stale state (old epoch) and a removed member's pre-removal snapshot both
  fail on new-epoch messages.

Guarantees actually shown:
- removal and new epochs cut off future content;
- replay, tamper and outsiders are rejected;
- state round-trips through persistence.

**Not shown by these tests:** formal forward secrecy or post-compromise
security. Those come from RFC 9420's design and the formal analyses cited
in [E2EE-ARCHITECTURE](E2EE-ARCHITECTURE.md), conditional on correct
implementation and key deletion.

## Sources

- OpenMLS: [SRLabs Security Assurance Assessment v1.2](https://blog.openmls.tech/SRL-OpenMLS_security_assurance_assessment.pdf) ·
  [audit announcement](https://blog.phnx.im/openmls-independent-security-audit/) ·
  GitHub security advisories `GHSA-gc79-23g3-8g52`, `GHSA-w62v-gv48-63rh`, `GHSA-rrmv-c79f-cf5r`, `GHSA-8x3w-qj7j-gqhf`, `GHSA-qr9h-x63w-vqfm` ·
  [OpenMLS advisory DB](https://advisories.gitlab.com/pkg/cargo/openmls/)
- Downstream reviews: [NCC Group: XMTP MLS review](https://www.nccgroup.com/research/public-report-xmtp-mls-implementation-review/) ·
  [Least Authority: White Noise MDK (built on OpenMLS)](https://leastauthority.com/wp-content/uploads/2026/03/Least-Authority-White-Noise-MDK-Final-Audit-Report.pdf)
- mls-rs: [repository README (audit statement)](https://github.com/awslabs/mls-rs) ·
  [lib.rs](https://lib.rs/crates/mls-rs) ·
  [comm-central vendored copy](https://searchfox.org/comm-central/source/third_party/rust/mls-rs/README.md)
- Wire `core-crypto` `Cargo.toml` (OpenMLS fork dependency).
