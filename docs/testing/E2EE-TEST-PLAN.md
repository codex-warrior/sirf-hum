# E2EE Test Plan

Status: **Plan (Prompt 04); crypto-core foundation tests exist (Prompt 06,
below).** Passing them is not an E2EE claim (see gates).

Principle: never prove only that our code agrees with itself. Correctness
evidence comes from:
- **(a)** published test vectors;
- **(b)** independent implementations (interop);
- **(c)** negative tests that a broken system would fail.

## Layers

| Area | What we test | How | Evidence source |
| --- | --- | --- | --- |
| Known-answer vectors | MLS key schedule, tree math, message framing, secret tree, welcome, transcript hashes | Run RFC 9420 / IETF MLS test vectors (as OpenMLS does) against the **exact pinned** library + crypto provider we ship, in our CI | IETF mls-implementations test vectors |
| Primitive KATs | Ed25519 (RFC 8032), X25519 (RFC 7748), AES-GCM, ChaCha20-Poly1305 (RFC 8439), HKDF (RFC 5869), secretstream | Library vectors + Wycheproof where available | RFCs, Project Wycheproof |
| Round trips | Encrypt → decrypt for every content kind and size class | Unit tests in the Rust core | — |
| Tampered ciphertext / tags | Flip bits in ciphertext, tag, header, AAD; truncate; extend | Must fail closed with no partial plaintext | Spike covers MLS app messages |
| Replay / duplicates | Same ciphertext twice; same `clientMessageId` | MLS rejects; app dedupes | Spike covers MLS replay |
| Malformed payloads | Fuzz deserializers (MLS framing, our envelope, payload schema) | cargo-fuzz in CI (nightly) | OpenMLS fuzzes its own parsers; we fuzz ours |
| Unknown versions | Envelope/schema/ciphersuite versions from the future | Fail closed, "update" path | — |
| Key rotation | Updates, KeyPackage replenishment, PIK rotation with partner re-verification | Scenario tests | — |
| Device revocation | Online/offline removed device can't read later epochs; server-side denial | Scenario + rules tests | Spike covers both MLS cases |
| Multi-device delivery | 2 people × up to N devices; all receive; roster changes visible | Scenario tests | Spike covers roster convergence |
| Concurrent commits | Two devices commit in the same epoch; one wins; other re-bases | Scenario + Firestore emulator | — |
| Interrupted operations | Kill between Commit send and merge; resume upload mid-chunk | Fault injection | — |
| Recovery | Restore PIK from backup; wrong key; corrupted backup; no backup | Scenario tests | — |
| Cross-platform interop | Android ↔ iOS ↔ (future) web exchange the same groups | Device-farm or emulator matrix; byte-level fixtures recorded from one platform and checked on others | — |
| Web-specific | CSP blocks inline script/eval; logout wipes IndexedDB; non-extractable keys | Browser automation | — |
| Security rules | Only couple members' devices read group docs; revoked devices denied; append-only epochs; first-commit-wins | Firestore emulator tests (existing harness) | — |
| Privacy-safe logging | No plaintext, keys or ciphertext in logs/crash reports | Logger unit tests (exist) + tests that feed secret-shaped values through crypto error paths | — |

## Gates before any E2EE claim

1. All layers above pass in CI on Android, iOS (and web if in scope).
2. Pinned library versions run their upstream test-vector suites in our CI.
3. Independent cryptographic review of the protocol composition and the
   Rust core.
4. Threat model and these docs updated to match what was built.

## Crypto-core foundation tests (exist; Prompt 06)

Code: `packages/sirf_hum_crypto`. CI jobs: `crypto-core`,
`crypto-android-device`, `crypto-ios-device`, plus packaging checks in
`android` and `ios`.

Mandatory rollback scenarios (Prompt 06 Part 5), as Rust tests in
`native/tests/crypto_core.rs`:

| | Scenario | Test |
| --- | --- | --- |
| A | Valid message succeeds | `group_add_commit_encrypt_decrypt` |
| B | Tampered message fails | `tampering_anywhere_is_rejected` (every byte position) |
| C | Valid after tampered still succeeds | `forged_then_valid_message_still_decrypts` |
| D | Replay rejected | `replay_is_rejected` |
| E | State usable after rejected input | `malformed_then_valid_message_still_decrypts`, `failed_write_rolls_back_and_core_stays_usable` |
| F | Removed device can't decrypt new epoch | `removed_device_cannot_decrypt_new_epoch` |
| G | Restored pre-removal state can't decrypt new epoch | `restored_pre_removal_state_cannot_decrypt_new_epoch` |
| H | Outsider message rejected | `outsider_message_is_rejected` |
| I | Malformed message can't corrupt persistent state | `malformed_input_cannot_corrupt_persistent_state`, `persistence_failure_during_processing_rolls_back` |

The Rust tests also cover:

- **Identity:** create/reload, double-create, account vs device identity.
- **Credentials:** trusted accepted, untrusted add rejected, untrusted
  Welcome member rejected, revoked device not re-addable, a receiver
  rejecting an untrusted device added by a member who bypasses policy.
- **Persistence:** restart round trip, overwrite, corruption, unknown
  version, record swap, wrong KEK, wipe.
- **Limits:** exact limit and one byte over; oversize input rejected before
  parsing.
- **Errors and logging:** stable error table, redacted `Debug`, source scan
  for logging.

Above the Rust layer:

- **Dart, through the real library:** two-device exchange, restart, commit,
  tamper, replay, limits, garbage input, removal, untrusted add, wipe,
  corrupted state fails closed, platform keystore `unsupported`, closed
  handle, redaction. CI sets `SIRF_HUM_REQUIRE_NATIVE_CRYPTO=1` so a missing
  library fails.
- **Device:** `integration_test/crypto_core_test.dart` on an Android
  emulator inside the real app (it also ran on an iOS simulator until
  D-092).
- **Web:** the stub fails closed with `unsupported`, and the app classifies
  Web as `unavailableOnWeb`.

## Device identity tests (exist; Prompt 07)

Design: [DEVICE-IDENTITY](../security/DEVICE-IDENTITY.md). The replay and
cloning matrix is in §6 of that document.

| Layer | Where | What | Runs |
| --- | --- | --- | --- |
| Rust | `native/tests/device_identity.rs` | Account binding; device proof verifies only for its account, challenge and certificate; every certificate byte; challenge length; no state change; platform key open/restore/refuse; server golden vector | CI `crypto-core` |
| Dart package | `test/crypto_core_test.dart` (device identity group) | Platform key wiped after open; wrong key fails closed; account check; proof shape | CI `crypto-core` |
| Server verifier | `functions/test/device_proof.test.mjs` | Golden vector is reproducible and verifies; forged and altered certificates; altered account; stale challenge; copied key; other purpose | CI `functions` |
| Server flows | `functions/test/emulator/device_registration.test.mjs` | Activation; replayed proof; reused or stale challenge; cross-account challenge; copied records; duplicate device ID and key; altered device ID; revoked devices; malformed input | CI `functions` (emulator) |
| Rules | `firebase/tests/devices.test.js` | The 8 required cases plus schema, immutability, no client activation, one-way revocation, no deletes, server-only collections | CI `security-rules` |
| App | `test/security/device/`, `test/platform/`, `test/infrastructure/` | State machine; persistence; account switching; corruption; partial write; stale-key rotation; removal; key wiping; Web; registration flow (no challenge reuse, revoked terminal, account mismatch); log redaction; rules ↔ client field drift | CI `flutter` (native required) |
| Device | `integration_test/device_identity_test.dart` | Real Keystore/Keychain: key store, persistence, isolation, removal, missing key fails closed | CI Android emulator |

## Multi-device trust tests (exist; Prompt 08)

Design: [MULTI-DEVICE-TRUST](../security/MULTI-DEVICE-TRUST.md).

| Layer | Where | What | Runs |
| --- | --- | --- | --- |
| Rust | `native/tests/device_trust.rs`, `src/recovery.rs` | Independent key material per device; approval binds account, approver, new device, challenge and expiry; not forgeable from a device proof; self/tampered/revoked targets refused; approval lets the approver add the device to MLS (and survives restart); recovery key round trip, freshness and typos; base32 RFC 4648 vectors; server golden vectors (all three statements, code, seed→key) | CI `crypto-core` |
| Dart package | `test/crypto_core_test.dart` (multi-device group) | Approval, comparison code, recovery key, purposes, through the real library | CI `crypto-core` |
| Server verifiers | `functions/test/statements.test.mjs` | Golden vectors; wrong account/approver/device/challenge/expiry/signer; cross-statement and device-proof reuse rejected; recovery registration and approval bindings; comparison code | CI `functions` |
| Server flows | `functions/test/emulator/multi_device.test.mjs` | A approves B; chain A→B→C with B revoked (C stays, B can't approve); revoked B can't return; A lost, B approves C; unproven requests; enrollment proof purpose; rejection terminal; expired, consumed, pre-revocation, target-revoked, altered, wrong-account and wrong-device approvals; cross-account; offline revocation; copied stale state; copied metadata; forged certificate; recovery once and single-use; no recovery key; wrong key; revoked registrar; replayed challenge; pending cap; rate limits; failure budget; lazy and scheduled expiry; cleanup idempotent | CI `functions` (emulator) |
| Rules | `firebase/tests/devices.test.js` | No client create; terminal states immutable; no server-controlled fields from clients; revoked device can't restore; cross-account revocation; all server-only collections closed | CI `security-rules` |
| App | `test/security/device/` | State machine (new terminal states); enrollment flow (bootstrap vs approval, code, terminal); trust service (codes match, approve, reject, untrusted device refused, offline revocation, revoke, recovery, typo caught locally, unregistered key, log redaction of recovery key/IDs/codes); drift tests against server inputs, rules and failure categories | CI `flutter` |
| Device | `integration_test/device_identity_test.dart` | Approval, comparison code and recovery key with real platform keys | CI Android emulator |

## Device trust hardening tests (exist; Prompt 09)

| Layer | Where | What | Runs |
| --- | --- | --- | --- |
| Rust | `native/tests/trust_hardening.rs` | Revocation and reset-cancel binding, self-revocation, domain separation; trust epoch monotonic across restart and wipe; lineage: valid chain, revocation without cascade, server-asserted revocations, missing link, wrong root/account, tampered signature, wrong challenge, version 2, duplicate, foreign revoker, recovery links, malformed blobs; v2 golden vectors | CI `crypto-core` |
| Dart package | `test/lineage_test.dart`, `test/crypto_core_test.dart` (hardening group) | Dart lineage blob byte-identical to the server vector; native verification; signRevocation, observeTrustEpoch | CI `crypto-core` |
| Server unit | `functions/test/hardening.test.mjs` | v2 vector regeneration; every revocation field bound; unknown reasons; approval ≠ revocation; reset-cancel binding; static logger guard | CI `functions` |
| Server flows | `functions/test/emulator/hardening.test.mjs` | Signed revocation (evidence, epoch, self, revoked/pending/foreign revoker, forgery, replay, twice, cross-account, stale, bad reason); stored lineage evidence verifies; epoch monotonic; identity reset (cancel, delay, completion, one new bootstrap, old identity never returns, revoked/forged cancel); state edges (after rejection/expiry/revocation, v2 header, pending cap); races (double approval, double bootstrap, challenge reuse, double recovery, approval vs revocation, concurrent registrations); rate-limit boundaries (exact, one over, window reset, concurrent, per account) | CI `functions` (emulator) |
| Rules | `firebase/tests/devices.test.js` | No client revocation in any shape; `accountTrust` owner-read only; no epoch rollback, bootstrap reopen or fake reset | CI `security-rules` |
| App | `test/security/device/`, `test/infrastructure/` | Signed revoke, self-revoke, revoked/unknown target refused before signing; lineage with real signatures (approval + recovery), tamper and unproven-active fail closed; stale epoch refused before acting; reset request/cancel/complete; log redaction; payload ↔ server drift; lineage and trust-state parsing fail closed | CI `flutter` |
| Device | `integration_test/device_identity_test.dart` | Revocation, reset cancel, lineage and epoch persistence with real platform keys | CI Android emulator |

## Messaging core tests (exist; Prompt 10)

Design: [E2EE-MESSAGING-DESIGN](../security/E2EE-MESSAGING-DESIGN.md).
iOS is not run (D-092). Counts are from the local run on 2026-10-19 (Windows host, gnu toolchain,
native core loaded) and must match CI.

| Layer | Where | Covers | Runs |
| --- | --- | --- | --- |
| Trust unit (D-085), adversarial | `native/src/engine/trust_tests.rs` (17) | Lineage-proven device accepted; no re-labelling of a device to another account; revoked device cannot approve, re-mint a device ID with its PIK, reuse its certificate or forge one under another PIK; stale lineage epoch and stale approval; approval from outside the chain or bound to another account; anchored PIK certifies one device only; trusted ID under another PIK; valid certificate with broken lineage; omission drops trust; revocations are permanent; restart round trip; v1 state migration; the documented server-ordering limit | CI `crypto-core` |
| Messaging core (ABI v5) | `native/tests/messaging.rs` (30 + 1 ignored baseline) | Staging never advances the epoch; discard; exactly-once confirm; staged commit blocks sends/commits/v4 calls; first commit wins and loser converges; restart while staged; group-creation race; Welcome redirection; A1/A2/B1/B2 all pairs; revoked device removed, cannot send or rejoin; stale state of a removed device; late-joining device has no history; every envelope field bound (ID, versions, epoch, conversation, sender); copy into another conversation; tampering never consumes the key; replay/duplicate; 30 reordered messages; future/stale epochs; committer flush; offline queue + re-encryption; sealed history (no plaintext on disk, swap/flip/foreign key fail closed, account scope, wipe, rollback on write failure); exact limits; lineage-only trust with signed revocation driving MLS removal | CI `crypto-core` |
| Golden vectors | `engine/conversation.rs` `golden` + `test/messaging_types_test.dart` | History record and AAD bytes identical in Rust and Dart | CI `crypto-core` |
| Dart bindings | `test/messaging_native_test.dart` (5), `test/messaging_types_test.dart` (6) | v5 calls through the real library; error table -22..-25; strict history decoder; Web stub fails closed | CI `crypto-core` |
| Messaging service | `test/security/messaging/messaging_service_test.dart` (9) | Real cores + real enrollment/approval lineage + rules-faithful fake server: all pairs; revocation → untrusted roster refused → Remove → revoked device refused and removed; offline + stale re-encryption (same ID); lost ack never duplicates; concurrent membership commits; restart while staged; relabelled/copied/malformed messages fail closed; non-member/closed conversation; logs carry no text or IDs | CI `flutter` |
| Formats | `test/security/messaging/envelope_and_payload_test.dart` (7) | Text payload limits and strict decode; strict envelope parsing (plaintext fields, types, sizes); written fields equal the rules' allowed fields | CI `flutter` |
| Rules | `firebase/tests/messaging.test.js` (22) | Prompt 10 attack scenarios 1–14: outsider, wrong account, revoked/pending/unknown device, fake membership, edits, deletes, server time, stale-epoch replay, plaintext fields, malformed envelopes; first commit wins; forged commits; Welcomes only beside their commit; key packages; partner directory reads | CI `security-rules` |
| Provisioning | `functions/test/emulator/conversation.test.mjs` (6) | No callable; accepted pairing only; idempotent and concurrent; invalid pairings; one couple per account; ID collision never overwrites | CI `functions` |
| Device | `integration_test/messaging_test.dart` (1) | Platform key store slots for two accounts, staged group, AAD binding, sealed history across reopen, timing baseline | CI Android emulator |

**Not covered yet:** Firestore round-trip latency and real deployment
(Blaze BLOCKED); fuzzing of the new decoders; more than two Welcomes in one
rules batch.

## Encrypted media and notification tests (exist; Prompt 11)

Design: [E2EE-MEDIA-AND-NOTIFICATIONS](../security/E2EE-MEDIA-AND-NOTIFICATIONS.md)
(threats E35–E46). iOS is not run (D-092). Counts are from the local run on
2026-10-19: Windows host, GNU toolchain. Native Dart tests were run through
a local-only build-hook patch that is not committed; CI runs them on Linux.

| Layer | Where | Covers | Runs |
| --- | --- | --- | --- |
| Media core, STREAM layer alone | `native/src/engine/media.rs` (11) | AAD, view and object-name golden vectors; exact sizes; strict `media_ref` decode (version, kind, class, lengths, empty, over limit, trailing bytes); with the hash **bypassed**: wrong key, AAD version, schema, conversation, media ID, sender (re-attribution), class, length; chunk swap, repeat, truncation at a chunk boundary (last-block flag), nonce-prefix change; atomic write ; **STREAM AD schedule** (F4 correction): media AAD on chunk 0 only, ε on later chunks, checked chunk by chunk with a plain XChaCha20-Poly1305; old every-chunk schedule rejected; tampered first or later chunk; final flag; golden object digests (regression pins) | CI `crypto-core` |
| Media core (ABI v6) | `native/tests/media.rs` (18 + 1 ignored baseline) | Round trip at every chunk boundary; all classes; fresh key and prefix per object; receiver and history see the key-free view only; Dart cannot send kind 2; any modified, truncated, extended, header-only, empty or chunk-swapped object fails closed and the genuine one still opens; object substitution; conversation binding; text and unknown IDs are not media; missing object; replay; another account; restart and stale-epoch re-encryption; **no plaintext on disk** (object, state, history); revoked sender (old media stays, new refused); revoked recipient (send refused while in roster, no orphan object, no key after removal, old media stays); limits (empty, missing, directory, 64 MiB + 1, unwritable directory, unknown group, staged commit) with nothing left behind; persistence failure removes the object; redacted Debug | CI `crypto-core` |
| Proof purposes | `native/tests/device_identity.rs` (+1, 1 updated) | `push_token` (3) is its own signed domain; purpose 4 invalid | CI `crypto-core` |
| Dart bindings | `test/media_types_test.dart` (7), `test/media_native_test.dart` (4) | View golden vector and strict decode (a full reference with key is refused as a view); object names equal to Rust; limits; wire values; redaction; Web stub fails closed; v6 calls through the real library (round trip, tampering, forged reference refused, empty input) | CI `crypto-core` (native), everywhere (types) |
| Media service | `test/security/media/media_service_test.dart` (12) | Real cores and enrollment, rules-faithful fake object store: server sees ciphertext only and no plaintext on either device's disk; interrupted and offline uploads queue with **object before message**; lost upload ack (exactly one object); foreign object squatting at our path → `rejected`; substituted, modified and truncated objects → `corrupted`; corrupted cache re-downloaded once; interrupted download leaves nothing; deleted or missing object → `unavailable`; text and unknown messages are not media; input limits; lost outbox object abandoned; delete-for-me removes the cache; revoked device (no sends, no downloads, cache stays); no media support fails closed; logs carry categories only | CI `flutter` |
| Push client | `test/security/notifications/push_tokens_test.dart` (9) | Strict content-free signal parsing; fresh `push_token` proof per challenge; no token → nothing; rotation; logout (signed clear, then delete at FCM, also when offline); untrusted device; logs carry neither token nor device ID | CI `flutter` |
| Storage rules | `firebase/tests/storage/media_storage.test.js` (11, runs after the parallel files: cross-service reads need the emulators' own project) | Member active device creates; create-only (no overwrite, no metadata change); outsiders, anonymous, another account's device, cross-conversation; revoked, pending and unknown devices; closed conversation; fixed content type and metadata (no filename or caption); empty and non-opaque paths; members read, outsiders and anonymous do not; no list or delete; everything else denied | CI `security-rules` |
| Push tokens rules | `firebase/tests/push_tokens.test.js` (4) | Owner, partner, outsider, anonymous: no read, list, create, update or delete | CI `security-rules` |
| Push payloads and guards | `functions/test/notification.test.mjs` (8) | Exact message and sync payloads; no identifiers, topics or other platforms; token hash binding; token validation; purpose separation; static guard: notification modules never log or read documents whole; triggers read only `senderAccountId`, `senderDeviceId`, `status` and log counts only | CI `functions` |
| Push flows | `functions/test/emulator/notification.test.mjs` (14) | Register, rotate, clear; a password alone cannot register (other key, other purpose); challenge bound to token, single use, one account; pending, revoked, expired, rejected and unknown devices refused; revoked between challenge and registration; one token, one device; fan-out targets (partner `m`, own devices `s`, sender none); revoked, pending and stale devices never targeted; unregistered and stale tokens removed; token claiming another account ignored; commit sync; revocation deletes the token and wakes both accounts; identity reset; other status changes; empty conversation | CI `functions` |
| Device | `integration_test/media_test.dart` (1) | Platform key store slots, object in the slot's media directory, round trip, tampering, reopen, `media_baseline` (1, 8, 32 MiB) | CI Android emulator |

**Performance baseline (host):** Windows dev host, x86_64-pc-windows-gnu
release build, `cargo test --release --test media -- --ignored --nocapture`.

| Object | Encrypt + hash + seal message | Hash + decrypt (memory) | Object size |
| --- | --- | --- | --- |
| 1 MiB | 33 ms (30 MiB/s; dominated by the fsynced MLS-state and history writes) | 7 ms (138 MiB/s) | 1,048,857 B |
| 16 MiB | 146 ms (109 MiB/s) | 49 ms (323 MiB/s) | 16,781,337 B |
| 64 MiB | 588 ms (109 MiB/s) | 194 ms (330 MiB/s) | 67,125,273 B |

- **Android:** the `media_baseline` line in the CI emulator log (x86_64
  emulator, not a phone). It is recorded in the PR report, not asserted.
- **Memory:** encryption streams (O(64 KiB)). Decryption is O(plaintext),
  with an exact-capacity buffer that is never reallocated.
- **Failure behaviour:** covered by the tests above.

**Not covered yet:** a real FCM delivery and real Storage
(Blaze BLOCKED); OEM background-delivery behaviour; physical-device
throughput; objects over 64 MiB (refused by design).

## Decision-gate tests (exist; experimental; regression suite)

`prototypes/mls-decision-gate` (`.github/workflows/prototypes.yml`), run
against OpenMLS 0.9.1 **and** mls-rs 0.56.0, natively and on wasm32:
- 11 scenarios: lifecycle, 6-device couple, revocation (incl. retained
  plaintext), epoch rotation + stale state, replay, tamper sweep, outsider,
  persistence, rollback mitigation, plus two measured observations
  (forgery poisoning, late cross-epoch message);
- interop (15 steps);
- Dart FFI (3 tests);
- upstream test-vector suites at the pinned tags (OpenMLS 356 / mls-rs 437
  passed).

They probe library behaviour in our model. Cryptographic correctness comes
from the upstream vectors and independent review.
