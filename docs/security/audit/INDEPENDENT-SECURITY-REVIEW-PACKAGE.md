# Independent Security Review Package

Prepared in **Prompt 18 (2026-10-21, D-145)** as the entry point for an
external security and cryptography reviewer. It consolidates and extends
the Prompt 17 package ([README](README.md)); where a topic is already
documented in depth, this file states the exact scope and links to it.

> **Sirf Hum has not yet received an independent security or
> cryptographic review.**
>
> It is **not** production E2EE. Every property below is implemented and
> tested in development and reviewed only internally. Nothing in this
> package is a claim of security; it is the material a reviewer needs to
> test the claims.

**Source under review:** branch `security/prompt-18-production-readiness`
on top of `main` `138a730240e0cdce8aa2fcff559a7baacf793c65`. The exact
head commit and its CI run are recorded in the PR description (a commit
cannot contain its own SHA). Reviewers should pin that commit.

## 1. Architecture overview

Two people ("a couple"), each with one or more Android phones. Each phone
is an MLS member; private content (messages, photos, Moments, the Future +
Us notebook) travels only as MLS ciphertext through Firebase. The server
authorizes **which account may read or write which ciphertext**, orders
commits and rate-limits; it never holds content keys. Web is account
management only (no private content, D-046). iOS is out of scope (D-092).

```text
 Flutter UI ─► Dart services ─► C ABI v6 (hand-written, opaque handle) ─► Rust core
 (plaintext only as return values)                     OpenMLS 0.9.1, credential policy,
                                                       sealed store ◄─ store key ◄─ Android Keystore
──────────────── TB1: beyond here only ciphertext + public metadata ────────────────
 Firebase Auth (account, never device trust) · Firestore/Storage rules (ciphertext access)
 Cloud Functions (verify device proofs, order, rate-limit; hold no keys) · FCM (constant payloads)
```

Read: [ARCHITECTURE](../../architecture/ARCHITECTURE.md),
[CRYPTOGRAPHIC-BOUNDARIES](../../architecture/CRYPTOGRAPHIC-BOUNDARIES.md),
[FIREBASE-ARCHITECTURE](../../architecture/FIREBASE-ARCHITECTURE.md),
[README §1–2](README.md) (claimed properties, explicit non-goals).

## 2. Threat model

[THREAT-MODEL](../THREAT-MODEL.md): actors T1–T12, threats E1–E99,
"Prompt 17 status review", and the **Prompt 18 consolidated register**
(every attacker class requested for this review, with precondition,
asset, path, impact, mitigation, residual, evidence, status).

## 3. Crypto architecture

| Component | Construction | Docs |
| --- | --- | --- |
| Group messaging | MLS (RFC 9420), OpenMLS 0.9.1, ciphersuite `0x0001` `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519` (D-042) | [CRYPTO-CORE-ARCHITECTURE](../CRYPTO-CORE-ARCHITECTURE.md), [MLS-DECISION](../MLS-DECISION.md) |
| Crypto provider | `openmls_rust_crypto` 0.6.0 (RustCrypto: `aes-gcm`, `chacha20poly1305`, `ed25519-dalek`, `x25519-dalek`, `hkdf`, `sha2`; HPKE via `hpke-rs` 0.7.0 RustCrypto backend) | §13 |
| Message AAD | Built in Rust: conversation, message ID, sender device bound into the MLS AAD (D-089) | [E2EE-MESSAGING-DESIGN](../E2EE-MESSAGING-DESIGN.md) |
| Message padding | OpenMLS `padding_size = 256` on create and join (D-126) | §8.7 |
| Local state at rest | One atomic sealed record per operation, XChaCha20-Poly1305 under a per-account 32-byte store key, wrapped by a non-exportable Android Keystore AES-256-GCM key (StrongBox if available), `noBackupFilesDir` (D-058, D-065, D-066) | [KEY-MANAGEMENT](../KEY-MANAGEMENT.md) |
| Media | STREAM (`aead` 0.5.2 `StreamBE32`) over XChaCha20-Poly1305, 64 KiB chunks, per-object random key, SHA-256 object digest in the MLS-authenticated `media_ref` (D-093) | §8.6 |
| Device identity | Per-device person identity key (PIK, Ed25519) certifying one device signature key; certificates; proofs of possession (D-070, D-074, D-122) | [DEVICE-IDENTITY](../DEVICE-IDENTITY.md) |
| Hashes (server derivations) | SHA-256 over length-prefixed, domain-separated fields (D-127, D-135, D-136) | §8 |

No custom primitive is used. The compositions (credential policy, record
format, media format, proof payloads, safety number) are ours and are the
main review target.

## 4. Trust and device architecture

- Trust unit: the **exact device certificate**; a PIK certifies exactly
  one device ID, ever (D-085, D-122).
- Roots: a partner's root PIK is trusted only after explicit safety-number
  or QR verification (D-128); every other device is trusted only through a
  signed lineage from that root (D-084), verified **on device**.
- Approvals, revocations, reset cancellations: PIK-signed statements
  (D-075, D-081, D-082); server ordering and completeness are trusted for
  availability only (D-084, documented limit).
- State machine and transition matrix:
  [MULTI-DEVICE-TRUST](../MULTI-DEVICE-TRUST.md) §1–§11.

## 5. MLS architecture

Staged commits (D-087), first-commit-wins per epoch written only by the
server after a device-key proof (D-088, D-127), per-epoch receive order
with past-epoch window 0 (D-091), Welcomes validated against verified
lineage before joining, proposals by reference and external joins refused.
[E2EE-MESSAGING-DESIGN](../E2EE-MESSAGING-DESIGN.md) (D-085–D-091),
[PROMPT-17-SECURITY-REVIEW §4.4](PROMPT-17-SECURITY-REVIEW.md#44-mls--openmls-part-3).

## 6. Media encryption architecture

[E2EE-MEDIA-AND-NOTIFICATIONS §2](../E2EE-MEDIA-AND-NOTIFICATIONS.md) and
the D-093 review brief; internal investigation
[D-093-SECURITY-REVIEW](../D-093-SECURITY-REVIEW.md). Keys never cross
Dart (D-094); plaintext never reaches disk through the core
(`no_plaintext_reaches_disk_through_send_or_open`).

## 7. Pairing and safety-number architecture

Two-consent pairing with device proofs (purpose 4, D-101–D-104), forced
code comparison (D-131), partner verification (D-128).
[COUPLE-AND-PAIRING](../COUPLE-AND-PAIRING.md).

## 8. Exact constructions requested for review

### 8.1 Device proofs (D-070) and purposes 1–8

A device proof is an Ed25519 signature by the **device signature key**
(certified by the PIK) over a domain-separated payload built in Rust; the
server verifies it against the stored certificate and requires the
certificate's device ID to equal the caller's. Challenges are 32 random
bytes, single-use, 5 minutes, bound server-side to account, device and
purpose.

| Purpose | Value | Used by | Bound fields (beyond nonce, account, device) |
| --- | --- | --- | --- |
| `activation` | 1 | First-device bootstrap (D-075) | — |
| `enrollment` | 2 | New device proves its key while pending (D-070, D-075) | — |
| `pushToken` | 3 | FCM token registration (D-098) | token hash (challenge record) |
| `pairing` | 4 | Every pairing step (D-102) | step binding `SHA-256("SirfHum-PairingStep-v1\|" action "\|" subject)` (challenge record) |
| `commit` | 5 | MLS commit authorization (D-127) | conversation, from/to epoch, protocol, SHA-256(commit), SHA-256 of Welcomes |
| `approvalRejection` | 6 | Rejecting a pending device (D-129) | approval request (challenge record) |
| `conversationRecovery` | 7 | Retire + re-provision (D-135) | conversation, stalled epoch, account trust epoch |
| `unpair` | 8 | Dissolve the couple (D-136) | couple |

For purposes 3, 4 and 6 the extra binding lives in the single-use server-side challenge record; for 5, 7 and 8 it is also inside the signed SHA-256 derivation (§8.2, §8.5). Purposes 9+ are invalid (Rust and Functions tests). Golden vectors are
shared between Rust, TypeScript and Dart (`functions/test/vectors/`).

### 8.2 D-127 — server-authorized commits

`SHA-256("SirfHum-CommitAuthorization-v1" | 1 | nonce | len|account | device | conversation | fromEpoch | toEpoch | protocol | SHA-256(commit) | SHA-256(n | n × (target | SHA-256(welcome))))`, signed under purpose 5. One transaction checks challenge, device `active`, membership, proof, then first-commit-wins, and writes commit, epoch and Welcomes together. Clients cannot write commits, Welcomes or the epoch (rules). The server hashes opaque bytes; it never parses MLS. Decision Log D-127.

### 8.3 D-128 — partner verification

`fingerprint = SHA-256("SirfHum-SafetyNumber-v1" | 1 | len|account | len|root PIK)`; 30 digits per person (six 5-byte chunks, each mod 100000), lower-sorting account first: 60 digits. QR: `SHSN1:` + hex of both fingerprints. Trust changes only by explicit confirmation, and only if the server still presents the same root. Own root anchored only from a lineage proving this device. Server-reported revocations always applied. Decision Log D-128.

### 8.4 D-131 — pairing code confirmation

Only the invitee sees the six-digit code; the inviter must enter it; constant-time comparison; 3 wrong codes invalidate the pairing. A human check, not cryptographic authentication (D-128 authenticates). Decision Log D-131.

### 8.5 D-135 recovery and D-136 unpairing

Recovery: purpose 7 over `SHA-256("SirfHum-ConversationRecovery-v1" | 1 | nonce | len|account | device | conversation | epoch u64 BE | trust epoch u64 BE)`; old conversation `retired`, new MLS group for the same couple, successor followed only if it names the old one as predecessor with identical members. Unpair: purpose 8 over `SHA-256("SirfHum-Unpair-v1" | 1 | nonce | len|account | device | couple)`; couple `dissolved`, every conversation `closed`, partner records deleted, one transaction; since Prompt 18 the lineage walk runs only after authorization (D-144, P3-15). [PROMPT-17C-CLOSURE §1–2, §8](PROMPT-17C-CLOSURE.md).

### 8.6 D-093 — STREAM media format

| Item | Value |
| --- | --- |
| Construction | STREAM (Hoang–Reyhanitabar–Rogaway–Vizár 2015), `aead` 0.5.2 `StreamBE32`, over XChaCha20-Poly1305 (`chacha20poly1305` 0.10.1, feature `stream`) |
| Header | 25 bytes: `"SHMD"` \| format 1 \| random 19-byte nonce prefix |
| Chunks | 64 KiB plaintext, 16-byte tag each, last-block flag |
| Key / ID | Fresh random 32-byte key and 16-byte media ID per object, OS CSPRNG, inside Rust |
| AAD | `"SirfHum-MediaAAD" \| 1 \| schema 1 \| conversation \| media ID \| sender device \| class \| plaintext length \| header` on the **first** chunk only; empty AD afterwards (paper's schedule, F4 correction) |
| Integrity of the whole object | SHA-256 of header + all chunks, carried in the MLS-authenticated `media_ref`, checked before decryption. An authenticated ciphertext digest, **not** key commitment |
| Limits | 64 MiB plaintext; empty refused |
| Key delivery | Inside the MLS application message (`media_ref`); never crosses Dart |

**The STREAM implementation and its composition require independent
review.** `aead::stream` has no known audit; NCC's 2020 review of
`chacha20poly1305` predates 0.10.1 and did not cover it; XChaCha20-Poly1305
has no final IETF specification. D-093's "approved for pre-production"
was an internal owner decision, **not** an audit. Open items F3 (format
version not inside `media_ref`; required before any v2), F5 (zeroization
of key copies inside OpenMLS not established), F7 (server-controlled
upload metadata DoS), F8 (no audit), F9 (no end-to-end forged-reference
test).

### 8.7 Message padding (D-126)

OpenMLS `padding_size = 256` on create and join; RFC 9420 §6.3.1 zero
padding stripped by receivers; payload ≤ 16 KiB, ciphertext ≤ 32 KiB.
Length hidden only within a 256-byte block. Test:
`ciphertext_length_hides_the_message_length_within_a_block`.

### 8.8 The six deliberate deviations from upstream OpenMLS behaviour

Recorded in Prompt 05 (D-056–D-059) and Prompt 10 (D-087, D-091),
re-stated in Prompt 17 review §4.4.

| # | Upstream behaviour | Sirf Hum behaviour | Reason | Security impact | Tests | Question for the reviewer |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | **Credential validation** is left to the application (no identity-provider hook) | Every Add, Update, update-path leaf, Welcome member and **every sender** is validated in the core: basic credential → strict certificate decode → PIK signature → not revoked → exact certificate trusted → leaf key = certified key (D-057, D-085) | Without it any basic credential would be accepted | Membership authentication rests entirely on our policy | `untrusted_member_in_welcome_is_rejected_before_joining`, `a_trusted_device_id_under_another_pik_is_refused`, `revoked_device_is_removed_and_cannot_rejoin_or_send`, `lineage_trust_and_signed_revocation_drive_mls_membership` | Is the validation applied at every point OpenMLS accepts a credential (incl. update paths, GroupInfo, external senders)? Is the leaf-key-equals-certified-key check complete? |
| 2 | **Rejected input can consume state**: a forged copy of a message consumes its key (measured: OpenMLS 20/52 byte positions) | Every untrusted input is processed inside a checkpoint and rolled back on any error; a rollback failure poisons the core (D-056) | An injector could otherwise make genuine messages undecryptable | Availability and replay protection depend on the checkpoint covering all state | `tampered_ciphertext_fails_and_never_consumes_the_key`, `forged_then_valid_message_still_decrypts`, `malformed_then_valid_message_still_decrypts`, `persistence_failure_during_processing_rolls_back` | Can any OpenMLS state escape the checkpoint (secret tree, ratchet, caches)? Does rollback reopen a replay window? |
| 3 | **Storage writes during commit processing are not atomic** (SRLabs S1-3) | One atomic sealed record per operation through our storage provider (D-058) | Crash consistency; required by #2 | A torn write could fork local state | `malformed_input_cannot_corrupt_persistent_state`, `corrupted_record_is_detected_on_open`, `record_moved_to_another_name_is_rejected`, `state_round_trips_through_restart_and_conversation_continues`, `encryption_writes_the_committed_object_atomically` | Is the record format (version, AAD, naming) sound? Power-loss fault injection was **not** performed |
| 4 | **Unbounded parsing** (SRLabs S0-1; 2026 parser advisories) | Message size, extension counts and nesting bounded before MLS parsing (D-059) | DoS and parser bugs | Bounds must not reject valid traffic or leave gaps | `oversized_inputs_are_rejected_before_parsing`, `inputs_are_bounded_and_failures_leave_nothing_behind` | Are the bounds sufficient for every TLS-decoded structure we accept? Fuzzing was **not** performed |
| 5 | **Commits merge immediately** | Membership commits are staged, uploaded, and confirmed only when the server's `commits/{epoch}` names ours; discarded otherwise; while staged, sending and other commits are refused (D-087) | Server-ordered first-commit-wins without forks | Correctness of confirm/discard is security-relevant (fork, stall) | `a_staged_commit_blocks_everything_that_would_fork_state`, `discard_restores_the_active_state_and_is_idempotent`, `concurrent_commits_first_wins_and_the_loser_converges` | Any path where a discarded commit's secrets are used, or a confirmed one is applied twice? |
| 6 | **Sender-ratchet out-of-order tolerance 5** | 32 generations (D-091), past-epoch window 0 | Mobile reordering within an epoch | Larger tolerance keeps more skipped keys (forward secrecy within an epoch) | `reordered_and_delayed_messages_within_an_epoch_decrypt`, `late_message_from_previous_epoch_fails_closed`, `replay_is_rejected` | Is 32 an acceptable FS/availability trade-off; is memory bounded? |

Additional configuration choices to review with them: padding 256 (D-126,
§8.7); ciphersuite 0x0001 only; proposals by reference and external joins
refused; group ID = conversation ID.

### 8.9 Rust core, C ABI, Flutter bridge

| Item | Value |
| --- | --- |
| Crate | `sirf_hum_crypto` 0.1.0 (`packages/sirf_hum_crypto/native`), edition 2021, `cdylib` + `rlib`, `panic = "unwind"` caught at the FFI boundary |
| Toolchain | rustc **1.96.0** pinned (`rust-toolchain.toml`) |
| ABI | Hand-written C ABI, `ABI_VERSION = 6` (`src/ffi.rs`); opaque handle; Rust-owned buffers wiped on free; no key or state export; no logging (CI scan + clippy) |
| Dart side | `packages/sirf_hum_crypto` (Dart FFI `ffi` 2.2.0; native assets `hooks` 1.0.0 / `code_assets` 1.0.0, pins checked against the Flutter SDK, D-067) |
| Platform key store | `SecureKeyStore.kt` (Android Keystore, D-066); production opens the core only through `LocalDeviceIdentityService`; `KeyStoreKind.insecureTest*` refused in release builds |
| Policy gate | `tool/check_crypto_core.sh` (exact pins, OpenMLS version, banned features `crypto-debug`/`content-debug`, lockfile, no logging) |

Review questions: memory safety of every `extern "C"` function (lengths,
null pointers, aliasing, double free); panic and error paths leaving no
partially written state; the Dart bindings' lifetime handling of returned
buffers; whether plaintext copies in the Dart heap (P3-6) can be reduced.

### 8.10 Recovery, revocation, identity reset

[RECOVERY-AND-REVOCATION](../RECOVERY-AND-REVOCATION.md),
[MULTI-DEVICE-TRUST §6–§9](../MULTI-DEVICE-TRUST.md): signed revocation by
an active device (D-081); single-use recovery key (D-076); identity reset
with a 7-day cancellable delay producing a **new** identity (D-082) and
content-free alerts (D-132).

## 9. Firebase security model

Default-deny rules (`firebase/firestore.rules`, `firebase/storage.rules`);
server-only collections for every trust record; callables are the only
writers of trust state, commits, couples and conversation state; each
state change is one transaction. App Check is enforced in code on all 29
callables (D-139), not yet in the console. Rules authorize **accounts**,
not devices (E77, documented limit): everything that moves an epoch or
the couple needs a device proof. Read
[FIREBASE-ARCHITECTURE](../../architecture/FIREBASE-ARCHITECTURE.md),
`functions/src/`, PROMPT-17 review §4.14.

## 10. CI/CD security

Actions pinned to commit SHAs, exact tool versions, inputs only via `env`
(D-124, D-137); WIF only, no service-account keys (verified 2026-10-21:
no user-managed keys in any project); production credentials only for
repository + `production` environment + `main`; production deploys only
from the Deploy workflow, and Functions/Hosting only behind the launch
gate (D-137); full-history gitleaks; cargo-audit, npm audit, OSV-Scanner
(Dart + Gradle); Gradle wrapper checksum; release-signing guard (D-143).
No build provenance yet (P2-11). [ENVIRONMENTS](../../architecture/ENVIRONMENTS.md).

## 11. Known limitations

[PRODUCTION-BLOCKERS](PRODUCTION-BLOCKERS.md) (P2/P3),
[DATA-LIFECYCLE §3](../DATA-LIFECYCLE.md) (L1–L13 classified),
[METADATA-EXPOSURE](METADATA-EXPOSURE.md). Highlights: metadata visible;
exact media sizes; undetectable withholding; no post-quantum; local
rollback undetected; revocation window; partner lockout by a hostile
trusted device (repeatable, mitigated by recovery and unpairing); EXIF
inside the encryption; no deletion; Dart heap plaintext.

## 12. Open findings

| ID | Finding | State |
| --- | --- | --- |
| P0-1–P0-5 | Independent review, OpenMLS delta + provider, core/ABI/key store, STREAM, claim language | **Open** (this review) |
| P1-6 | Deployment prerequisites (Blaze, Functions, Storage, Eventarc, Scheduler) | Open (owner) |
| P1-7 | Sign-in provider | Decision proposed (D-138), not built |
| P1-8 | App Check attestation and enforcement | Prepared (D-139), not enabled |
| P2-1, P2-4, P2-5, P2-7–P2-11 | See PRODUCTION-BLOCKERS | Open / deferred |
| D-093 F3, F5, F7, F9 | Media format follow-ups | Open |
| Note (17C §8.2) | `provisionConversation` writes partner records without `coupleId`; unreachable through any callable today | For review |

## 13. Exact dependency versions

**Crypto core (`Cargo.lock`, 202 packages):**

| Crate | Version | Role |
| --- | --- | --- |
| `openmls` | 0.9.1 | MLS (SRLabs-reviewed at `a3402f2`, earlier; providers excluded) |
| `openmls_traits` | 0.6.0 | Provider traits |
| `openmls_rust_crypto` | 0.6.0 | Crypto provider |
| `openmls_basic_credential` | 0.6.0 | Signature key type (policy is ours) |
| `openmls_memory_storage` | 0.6.0 | Storage (wrapped by our atomic sealed records) |
| `hpke-rs` / `hpke-rs-crypto` / `hpke-rs-rust-crypto` | 0.7.0 | HPKE (RustCrypto backend) |
| `chacha20poly1305` | 0.10.1 | Local sealing; media (feature `stream`) |
| `aead` | 0.5.2 | STREAM (`StreamBE32`) |
| `chacha20` / `poly1305` | 0.9.1 / 0.8.0 | Underlying primitives |
| `aes-gcm` | 0.10.3 | MLS AEAD |
| `ed25519-dalek` | 2.2.0 | Signatures |
| `x25519-dalek` / `curve25519-dalek` | 2.0.1 / 4.1.3 | DHKEM X25519 |
| `sha2` | 0.10.9 (ours, provider) and 0.11.1 (provider, HPKE) | Hashing |
| `hkdf` / `hmac` | 0.12.4 & 0.13.0 / 0.12.1 & 0.13.0 | KDF |
| `p256` / `p384` | 0.13.2 / 0.13.1 | Compiled by the provider; unused by ciphersuite 0x0001 |
| `x-wing` → `x25519-dalek` 3.0.0, `curve25519-dalek` 5.0.0, `ml-kem` | compiled through `hpke-rs-rust-crypto` | Post-quantum KEM code compiled but **not used** by ciphersuite 0x0001; reviewer: confirm unreachable |
| `tls_codec` | 0.5.0 | MLS wire encoding |
| `zeroize` | 1.9.1 | Wiping |
| `getrandom` | 0.2.17 (and 0.4.3 via `rand` 0.10) | OS CSPRNG |

Known advisories, explicit and re-verified on every CI run
(`tool/crypto_audit.sh`, D-068): **RUSTSEC-2026-0330, RUSTSEC-2026-0331**
(`libcrux-kem` 0.0.9, locked but never compiled: `hpke-rs` feature
`libcrux` is off) and **RUSTSEC-2026-0173** (`proc-macro-error2` 2.0.1
unmaintained, compile-time only). Re-evaluated 2026-10-21 against
crates.io: `openmls` 0.9.1 and `openmls_rust_crypto` 0.6.0 are still the
latest releases; the fix needs `hpke-rs` 0.8.0 (released 2026-10-07) /
`libcrux-kem` 0.0.10, which the 0.6.0 provider does not accept. **No
compatible OpenMLS upgrade removes them yet.** No upgrade was made; any
future one requires a Decision Log entry and the full crypto regression
suite.

**Application:** Flutter 3.41.5 / Dart 3.11.3; `firebase_core` 4.15.0,
`firebase_auth` 6.7.0, `cloud_firestore` 6.10.0, `cloud_functions` 6.5.0,
`firebase_storage` 13.6.0, `firebase_messaging` 16.7.0,
`firebase_app_check` 0.4.8, `firebase_crashlytics` 5.4.0, `image_picker`
1.2.4 (`image_picker_android` 0.8.13+17), `mobile_scanner` 7.4.2, `qr`
4.0.0, `crypto` 3.0.7 (full list: `pubspec.lock`, 121 packages).
Android: AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14 (checksum-pinned), NDK
28.2.13676358, JDK 17 (CI build); release classpath locked in
`android/app/gradle.lockfile` (183 entries). **Server:** Node 22,
`firebase-functions` 7.4.0, `firebase-admin` 14.5.0, TypeScript 5.9.3,
`firebase-tools` 15.34.0 (deploy and emulators).

## 14. Exact source commits

| What | Commit |
| --- | --- |
| Baseline `main` before Prompt 18 | `138a730240e0cdce8aa2fcff559a7baacf793c65` |
| Prompt 18 head | PR description of `security/prompt-18-production-readiness` |
| OpenMLS SRLabs-reviewed commit | `a3402f2` (predates 0.9.1; delta review is P0-2) |
| OpenMLS used | crates.io `openmls` 0.9.1 (checksum in `Cargo.lock`) |

## 15. Test matrix

[TEST-MATRIX](TEST-MATRIX.md) (adversarial property → tests, including
the Prompt 18 section) and [E2EE-TEST-PLAN](../../testing/E2EE-TEST-PLAN.md).
Layers: R (Rust), F (Functions emulator), Fu (Functions unit), S
(rules), D (Dart/Flutter), I (Android emulator integration).

## 16. Reproduction

```sh
git checkout <Prompt 18 head>
flutter pub get
tool/verify.sh --all            # format, analyze, Dart tests, deploy-gate and header
                                # checks, Rust core (fmt, clippy, tests), Functions,
                                # rules, web + Android builds
tool/check_crypto_core.sh       # pins, banned features, no logging
tool/crypto_audit.sh            # cargo audit with re-verified ignores (needs cargo-audit 0.22.2)
(cd functions && npm ci && npm test && npm run test:emulator)
(cd firebase && npm ci && npm test)
osv-scanner scan source --lockfile pubspec.lock \
  --lockfile packages/sirf_hum_crypto/pubspec.lock --lockfile android/app/gradle.lockfile
```

Native Dart tests (crypto bridge, messaging, verification) need a host
build of the core; CI runs them on Linux with
`SIRF_HUM_REQUIRE_NATIVE_CRYPTO=1`, which fails instead of skipping. The
Android emulator suite runs in CI (`crypto-android-device` job).

## 17. Questions for the reviewer

1. OpenMLS 0.9.1 vs the audited `a3402f2`: which changed code paths does
   Sirf Hum exercise, and is `openmls_rust_crypto` 0.6.0 sound for them?
2. The six deviations (§8.8): each row's question.
3. Credential policy and trust unit (D-057, D-085, D-122): can any
   certificate, lineage or Welcome make a device trusted that no anchored
   root signed?
4. Lineage verification and its documented reliance on server ordering
   (D-084): is the "omission drops trust, never adds it" argument sound?
5. Device proofs (purposes 1–8): domain separation, length prefixes,
   challenge binding, replay; can a proof for one purpose or object be
   used for another?
6. D-127: is the commit/Welcome binding complete; can a valid
   authorization be replayed or re-targeted?
7. D-128: is the safety-number construction (truncation to 30 digits per
   person, ordering) adequate; is the own-root anchoring rule safe?
8. D-131: is the human code comparison step meaningful given D-128?
9. D-135/D-136 (and D-144): races, the predecessor-walk completeness
   argument, the abusive-partner model.
10. STREAM media (§8.6): is the composition (first-chunk AAD, digest in
    `media_ref`, key in MLS) secure; is lack of key commitment a problem
    here?
11. Local storage: record format, Keystore wrapping, the rollback analysis
    (review §4.3).
12. C ABI and Dart bindings (§8.9).
13. Notification privacy (D-097, D-132) and metadata exposure: anything
    worse than METADATA-EXPOSURE states?
14. Is anything in the server path able to obtain plaintext or keys?

## 18. Explicit scope

**In scope (mandatory):** OpenMLS 0.9.1 integration; the crypto provider;
the six deliberate OpenMLS deviations; message padding; the STREAM
implementation and media composition; the Rust core; the C ABI/FFI; the
Flutter/native bridge and the platform key store; device proofs and
purposes 1–8; D-127 server-authorized commits; D-128 partner
verification; D-131 pairing code confirmation; D-135 conversation
recovery; D-136 unpairing (with D-144); recovery, revocation and identity
reset; the complete E2EE architecture including Firebase rules and
Functions as they affect confidentiality and integrity.

**Out of scope:**
- iOS (not a product platform, D-092; its code is not built or tested);
- private content on web (does not exist, D-046); the web origin is in
  scope only as an account-management surface;
- LiveKit / calls and the Together backend (not built, D-112);
- the `prototypes/` directory (isolated, never imported, D-052);
- legal compliance (DPDP Act, GDPR) and Play policy review;
- availability against a malicious server (withholding is an accepted,
  documented limit, P3-3);
- post-quantum security (none claimed, P3-4);
- a compromised or rooted phone (T4), except where the design claims
  otherwise (backup exclusion, cloned state failing closed).

> **Sirf Hum has not yet received an independent security or
> cryptographic review.**
