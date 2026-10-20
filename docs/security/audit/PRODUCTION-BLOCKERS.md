# Production Blockers (Prompt 17 classification)

Status: **2026-10-20, D-125.** Every unresolved security item, classified
after reviewing the implementation (not the example list). Update this file
whenever an item closes; never close one by rewording it.

| Class | Meaning |
| --- | --- |
| **P0** | Must be resolved before **any** production security claim (store listing, website, app copy, investor or press material) |
| **P1** | Must be resolved before **production E2EE**: real users' private content |
| **P2** | Should be resolved before **public launch** |
| **P3** | Accepted post-launch risk, documented and monitored |

Finding IDs P17-xx are in [PROMPT-17-SECURITY-REVIEW](PROMPT-17-SECURITY-REVIEW.md);
threat IDs in [THREAT-MODEL](../THREAT-MODEL.md).

## P0 — before any production security claim

| # | Item | Why | Exit criterion |
| --- | --- | --- | --- |
| P0-1 | **No independent security / cryptography review has happened** | Every protocol here (device certificates, approvals, revocation, reset, lineage, trust unit, message AAD, media format, pairing, push-token proofs) is our own composition; tests prove what we thought of | Independent review of this package's scope, findings fixed or accepted in writing |
| P0-2 | OpenMLS delta review since the audited commit (`a3402f2` → 0.9.1) and review of the crypto provider (D-054 conditions) | The SRLabs review covered an earlier commit and excluded providers; three parser advisories followed | Delta + provider review completed |
| P0-3 | Review of our Rust core, C ABI and platform key store (D-063, D-065, D-066) | Credential policy, checkpoint/rollback, sealed records, Keystore adapter are unreviewed | Included in P0-1 |
| P0-4 | `aead::stream` and the media composition are unaudited (D-093 F8) | No audit of the module or of `aead 0.5.2`; composition is ours | Included in P0-1; F3 before any format v2 |
| P0-5 | No security claim language until P0 and P1 are closed | "E2EE" or "audited" claims would be false today | Copy review at release; CLAUDE.md rule stays |

## P1 — before production E2EE

| # | Item | Ref | Exit criterion |
| --- | --- | --- | --- |
| P1-1 | Partner PIK verification (safety numbers / QR) and own-account root anchoring for non-root devices; no silent trust-on-first-use | P17-09, E1, E5, D-085 | UX built; anchoring only after verification or an explicit, recorded TOFU decision with warnings |
| P1-2 | Pairing confirmation must force the code comparison (inviter enters what the invitee reads out; server-checked, attempt-limited) | P17-08, E48 | D-101 amended by the owner; tests |
| P1-3 | Device-bound authorization for MLS commits (and ideally messages) plus conversation recovery / re-provisioning after a stall | P17-05, E77, E32 | A Firebase session without an active device's key (password thief, leftover session on a revoked phone) cannot win `commits/{epoch}`; a stalled conversation can be recovered; tested |
| P1-4 | Identity-reset and new-device notifications to the account and the partner (content-free) | D-082 OPEN, E24, E27 | Deployed push for reset request and device changes |
| P1-5 | Unpairing (unilateral, instant) | D-105, T10, E19 | Built with MLS removal and rules for dissolved conversations |
| P1-6 | Deployment prerequisites for the trust model to exist at all: Blaze, Functions, Storage bucket + agent permission, Eventarc triggers, Cloud Scheduler | D-025, D-078, D-095, D-097 | Deployed to staging, then production via the Deploy workflow |
| P1-7 | Sign-in provider chosen and hardened (email enumeration protection, password policy, MFA option) | D-107 | Decision + configuration |
| P1-8 | App Check attestation (Play Integrity) and debug tokens before Functions deploy (callables enforce App Check in code); then Firestore/Storage enforcement | P17-10, D-028 | Staging metrics ≈100 % verified |

## P2 — before public launch

| # | Item | Ref |
| --- | --- | --- |
| P2-1 | Membership-removal policy that prevents a partner from locking the other person out, without forking on stale trust | P17-06, E82 |
| P2-2 | `rejectDeviceApproval` needs a device proof and a rate limit | P17-07 |
| P2-3 | Sweep picker plaintext copies at start-up and sign-out | P17-11, E81 |
| P2-4 | Content-Security-Policy for the web origin | P17-12, E17 |
| P2-5 | Repository: enable secret scanning, push protection, Dependabot alerts (free, public repo); ruleset on `main`; decide visibility | P17-13, E83 |
| P2-6 | Advisory scanning for Dart/Flutter and Gradle dependencies | P17-16 |
| P2-7 | Local rollback (D-079): server-anchored freshness or a written acceptance | P17-17, E22 |
| P2-8 | Retention and deletion design for messages, media, removed notebook records; account deletion flow (Play policy) | P17-18, E72, D-105, D-116 |
| P2-9 | EXIF stripping before encryption (partner currently receives location) | E68, D-117 |
| P2-10 | Revocation propagation window: deployed sync wake-ups (D-098) narrow E33/E43 | E33, E43 |
| P2-11 | Build provenance / signed release artifacts and Play App Signing | E14, D-124 |

## P3 — accepted post-launch risks

| # | Item | Ref |
| --- | --- | --- |
| P3-1 | Metadata visible to the server/Google: who, when, sizes, counts, device lists, relationship graph | [METADATA-EXPOSURE](METADATA-EXPOSURE.md), E2, E12, E45 |
| P3-2 | Exact media sizes (padding deferred) | E45, D-099 |
| P3-3 | Server message withholding is undetectable (no gap detection) | E10 |
| P3-4 | No post-quantum protection | D-050 |
| P3-5 | Notification timing visible to FCM and onlookers | E11, E40, E75 |
| P3-6 | Plaintext in the Dart heap cannot be reliably wiped | E23, E46, E67 |
| P3-7 | Reads without rate limits (`listDeviceApprovalRequests`, `getPairingState`); pre-check overshoot | P17-14 |
| P3-8 | Dev-only `@grpc/grpc-js` advisories in the rules-test harness | P17-15 |
| P3-9 | RUSTSEC-2026-0330/0331 (uncompiled `libcrux-kem`), RUSTSEC-2026-0173 (compile-time `proc-macro-error2`): re-verified each CI run; remove with the next OpenMLS upgrade | D-068 |
| P3-10 | Server controls lineage ordering/completeness (omission, post-revocation backdating with a revoked PIK) | E28, D-084 |
| P3-11 | Stolen unlocked active device can approve/revoke/cancel a reset; only-device-stolen-without-recovery-key case | E25, D-081 |
| P3-12 | Notebook edits unbounded within the shared 10,000-record history | E74 |

## Closed in Prompt 17

| Finding | Fix |
| --- | --- |
| P17-01 PIK reuse across devices / identity epochs | D-122 |
| P17-02 Android backup / device transfer | D-123 (CI Android build confirms the manifest merge) |
| P17-03 Unpinned actions and tools | D-124 |
| P17-04 Workflow input injection | D-124 |
| P17-19 Exact message lengths visible (no MLS padding) | D-126 (lengths now visible only to within 256 bytes; P3-1 still applies) |
| P17-10 (docs part) App Check documentation | ENVIRONMENTS, FIREBASE-ARCHITECTURE corrected |
