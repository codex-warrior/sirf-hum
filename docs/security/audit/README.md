# Sirf Hum — Independent Security Review Package

Prepared in Prompt 17 (2026-10-20, D-125) for an external security and
cryptography reviewer; updated in Prompt 17B and Prompt 17C (2026-10-21).
Baseline: branch `security/prompt-17-hardening-audit` (PR #16).

> **SIRF HUM IS NOT YET PRODUCTION E2EE.**
> **INDEPENDENT SECURITY/CRYPTOGRAPHIC REVIEW IS STILL REQUIRED.**

**Status, stated plainly:**
- Sirf Hum is **not** production end-to-end encrypted. Nothing is deployed;
  no real user's content exists.
- **No independent review or audit has been performed.** The Prompt 17
  review is internal.
- The only third-party assurance in the dependency chain is SRLabs' 2026-03
  review of OpenMLS at commit `a3402f2` (core crates, providers excluded),
  which predates the pinned 0.9.1.

## 1. What Sirf Hum claims to protect, from whom

**Asset:** the private content of a couple (two people, each with one or
more phones): messages, photos with their captions and dates ("Moments"),
and a shared notebook of plans, story and rituals ("Future + Us").

**Intended properties (implemented in development, unreviewed):**

| Property | Against | Mechanism |
| --- | --- | --- |
| Confidentiality of content | The server, Firebase/Google, a database or bucket dump, the network, another couple | MLS (RFC 9420, OpenMLS 0.9.1, ciphersuite 0x0001) group of the couple's devices; media under per-object keys sent inside MLS; local history sealed under a Keystore-protected key |
| Integrity and authenticity of content, sender and routing | Same, plus a malicious member re-attributing content | MLS authentication; Rust-built AAD binding conversation, message ID and sender device; authenticated media digest |
| Device trust independent of the account password | Stolen credentials, a malicious server adding devices | Per-device PIK; device certificates; approvals, revocations and recovery as PIK-signed statements verified **on device** from a root PIK verified out of band |
| Revocation | Lost/stolen/compromised device | Signed revocation, MLS removal, permanent PIK revocation |
| Server-side authorization | Other accounts, strangers, replay, races | Default-deny rules, signed callables, one transaction per state change |

**Explicitly NOT protected:** metadata (who, when, how much, device lists,
relationship graph: [METADATA-EXPOSURE](METADATA-EXPOSURE.md)); a
compromised or rooted phone; what the partner chooses to copy; server
withholding or delaying messages; post-quantum adversaries; local state
rollback by someone controlling the phone's storage (D-079); web clients
(no private content on web by design, D-046).

## 2. Cryptographic trust boundaries

```text
            ┌──────────────── phone (trusted while uncompromised) ────────────────┐
 person ──► │ Flutter UI ─► Dart services ─► C ABI v6 ─► Rust core (OpenMLS,      │
            │                (plaintext as   (opaque     credential policy,        │
            │                 return values)  handle)    sealed store) ◄─ store key│◄─ Android Keystore
            └──────────────────────────────▲──────────────────────────────────────┘
                     ciphertext + public    │ TB1: everything beyond is untrusted for content
                     metadata only          ▼
   Firebase Auth (account, NOT device trust) · Firestore/Storage (rules: account-level
   authorization of ciphertext) · Functions (verify signatures, order, rate-limit;
   never hold keys) · FCM (constant wake-ups)
```

- **Private keys** (PIK, device signature key, MLS secrets, media keys)
  exist only inside the Rust core and its sealed records. The C ABI exports
  no key or state ([CRYPTO-CORE-ARCHITECTURE](../CRYPTO-CORE-ARCHITECTURE.md)).
- **Trust roots:** a partner's root PIK must be verified out of band; every
  other device is trusted only through a signed lineage from that root
  ([MULTI-DEVICE-TRUST](../MULTI-DEVICE-TRUST.md) §11). The partner's root is
  anchored only when the person compares the safety number or scans the
  partner's QR code (D-128); never on first contact.
- **The server is trusted for availability and ordering only**, and for
  authorization of *ciphertext access* (which accounts may read/write).
  Firebase Auth identifies accounts, never devices: everything that moves a
  conversation's epoch therefore needs a device-key proof (D-127).

## 3. Package contents (the 22 requested areas)

| # | Area | Read |
| --- | --- | --- |
| 1 | System architecture | [ARCHITECTURE](../../architecture/ARCHITECTURE.md), [FIREBASE-ARCHITECTURE](../../architecture/FIREBASE-ARCHITECTURE.md), [CRYPTOGRAPHIC-BOUNDARIES](../../architecture/CRYPTOGRAPHIC-BOUNDARIES.md) |
| 2 | Threat model | [THREAT-MODEL](../THREAT-MODEL.md) (IDs T1–T12, E1–E90; "Prompt 17 status review", "New in Prompt 17B/17C") |
| 3 | Trust model | §1–2 above; [MULTI-DEVICE-TRUST](../MULTI-DEVICE-TRUST.md) §1, §11 |
| 4 | E2EE architecture | [E2EE-ARCHITECTURE](../E2EE-ARCHITECTURE.md), [E2EE-REQUIREMENTS](../E2EE-REQUIREMENTS.md), [MLS-DECISION](../MLS-DECISION.md) |
| 5 | MLS integration | [CRYPTO-CORE-ARCHITECTURE](../CRYPTO-CORE-ARCHITECTURE.md); review §4.4 |
| 6 | Device identity | [DEVICE-IDENTITY](../DEVICE-IDENTITY.md) |
| 7 | Multi-device trust | [MULTI-DEVICE-TRUST](../MULTI-DEVICE-TRUST.md) |
| 8 | Recovery / revocation | [RECOVERY-AND-REVOCATION](../RECOVERY-AND-REVOCATION.md), MULTI-DEVICE-TRUST §6–§9; conversation recovery D-135 ([PROMPT-17C-CLOSURE](PROMPT-17C-CLOSURE.md) §1) |
| 9 | Message protocol | [E2EE-MESSAGING-DESIGN](../E2EE-MESSAGING-DESIGN.md) |
| 10 | Media protocol | [E2EE-MEDIA-AND-NOTIFICATIONS](../E2EE-MEDIA-AND-NOTIFICATIONS.md) §2; [D-093-SECURITY-REVIEW](../D-093-SECURITY-REVIEW.md) |
| 11 | Pairing protocol | [COUPLE-AND-PAIRING](../COUPLE-AND-PAIRING.md); unpairing D-136 ([PROMPT-17C-CLOSURE](PROMPT-17C-CLOSURE.md) §2) |
| 12 | Moments | [MOMENTS-ARCHITECTURE](../../architecture/MOMENTS-ARCHITECTURE.md) |
| 13 | Future + Us | [FUTURE-AND-US-ARCHITECTURE](../../architecture/FUTURE-AND-US-ARCHITECTURE.md) |
| 14 | Web boundary | [WEB-SECURITY](../WEB-SECURITY.md); review §4.13 |
| 15 | Push privacy | E2EE-MEDIA-AND-NOTIFICATIONS §8; [METADATA-EXPOSURE](METADATA-EXPOSURE.md) |
| 16 | Firebase security | `firebase/firestore.rules`, `firebase/storage.rules`, `functions/src/`; review §4.14 |
| 17 | CI/CD security | [ENVIRONMENTS](../../architecture/ENVIRONMENTS.md), [ACCOUNT-OWNERSHIP](../../architecture/ACCOUNT-OWNERSHIP.md), `.github/workflows/`; review §4.16 |
| 18 | Known limitations | [PRODUCTION-BLOCKERS](PRODUCTION-BLOCKERS.md); THREAT-MODEL residual risks |
| 19 | Security decisions | [DECISION-LOG](../../decisions/DECISION-LOG.md) D-042–D-136 |
| 20 | Test matrix | [TEST-MATRIX](TEST-MATRIX.md); [E2EE-TEST-PLAN](../../testing/E2EE-TEST-PLAN.md) |
| 21 | Dependency / audit status | Review §4.15; `tool/crypto_audit.sh`, `tool/check_crypto_core.sh` |
| 22 | Open production blockers | [PRODUCTION-BLOCKERS](PRODUCTION-BLOCKERS.md) |

Findings of the internal review: [PROMPT-17-SECURITY-REVIEW](PROMPT-17-SECURITY-REVIEW.md);
what Prompt 17B fixed, deferred and still needs external review:
[PROMPT-17B-REMEDIATION](PROMPT-17B-REMEDIATION.md); conversation recovery,
unpairing, the final classification and the prohibited claims:
[PROMPT-17C-CLOSURE](PROMPT-17C-CLOSURE.md).

## 4. Where we most want scrutiny

1. Our compositions around OpenMLS: credential policy and the
   exact-certificate trust unit (D-057, D-064, D-085, D-122); checkpoint and
   rollback around every input (D-056, D-058); staged commits and
   first-commit-wins ordering (D-087, D-088); message AAD (D-089).
2. The device-trust statements and lineage verification (D-070, D-075,
   D-081–D-084), including the documented server-ordering limit and the
   device-bound commit authorization that replaced account-level commit
   writes (D-127, P17-05).
3. The media format: STREAM over XChaCha20-Poly1305 with our AAD and digest
   (D-093; `aead::stream` itself has no known audit).
4. The pairing protocol's code entry (D-101, D-131) and the partner
   verification / safety-number construction (D-128).
5. Conversation recovery (D-135) and unpairing (D-136): device-proof
   purposes 7 and 8, their transactions and races, successor following, and
   the abusive-partner model.
6. The Android Keystore adapter and sealed local store (D-065, D-066) and
   the local rollback analysis (review §4.3).

## 5. Reproducing the evidence

```sh
tool/verify.sh --all                 # format, analyze, all Dart tests, Rust core
                                     # (fmt, clippy, tests), Functions, rules,
                                     # web + Android builds
tool/check_crypto_core.sh            # pins, banned features, no logging
tool/crypto_audit.sh                 # cargo audit with re-verified ignores
(cd functions && npm run test:emulator)
(cd firebase && npm test)
```

CI (`.github/workflows/ci.yml`) runs all of the above on every PR, plus the
on-device integration tests on an Android emulator and a full-history
secret scan.
