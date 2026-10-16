# E2EE Test Plan

Status: **Plan (Prompt 04).** Only the experimental spike tests exist today
(`prototypes/mls-device-roster`, not part of the app).

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

## Decision-gate tests (exist; experimental)

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
