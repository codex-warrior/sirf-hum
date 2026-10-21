# Production Blockers

Status: **Prompt 17 classification (D-125), updated after Prompt 17B
(2026-10-20), Prompt 17C (2026-10-21,
[PROMPT-17C-CLOSURE](PROMPT-17C-CLOSURE.md)) and Prompt 18 (2026-10-21,
D-137–D-145; per-gate status and evidence in
[PRODUCTION-LAUNCH-GATE](PRODUCTION-LAUNCH-GATE.md)) and Prompt 19 (2026-10-21,
staging activation, [STAGING-BETA](STAGING-BETA.md), D-146, D-147).** **Sirf Hum is not yet
production E2EE; independent security/cryptographic review is still
required.** Every unresolved security item, classified after reviewing
the implementation. Update this file whenever an item closes; never close
one by rewording it.

| Class | Meaning |
| --- | --- |
| **P0** | Must be resolved before **any** production security claim (store listing, website, app copy, investor or press material) |
| **P1** | Must be resolved before **production E2EE**: real users' private content |
| **P2** | Should be resolved before **public launch** |
| **P3** | Accepted post-launch risk, documented and monitored |

Finding IDs P17-xx: [PROMPT-17-SECURITY-REVIEW](PROMPT-17-SECURITY-REVIEW.md),
[PROMPT-17B-REMEDIATION](PROMPT-17B-REMEDIATION.md),
[PROMPT-17C-CLOSURE](PROMPT-17C-CLOSURE.md); threat IDs:
[THREAT-MODEL](../THREAT-MODEL.md).

## P0 — before any production security claim

| # | Item | Exit criterion |
| --- | --- | --- |
| P0-1 | **No independent security / cryptography review has happened** (scope: PROMPT-17B-REMEDIATION §6) | Independent review completed; findings fixed or accepted in writing |
| P0-2 | OpenMLS delta review (`a3402f2` → 0.9.1) and crypto-provider review (D-054 conditions) | Completed |
| P0-3 | Review of our Rust core, C ABI and platform key store (D-063, D-065, D-066, D-085, D-122) | Included in P0-1 |
| P0-4 | `aead::stream` and the media composition are unaudited (D-093 F8) | Included in P0-1; F3 before any format v2 |
| P0-5 | No security claim language until P0 and P1 are closed (exact prohibited claims: [PROMPT-17C-CLOSURE §6](PROMPT-17C-CLOSURE.md#6-prohibited-security-claims)) | Copy review at release |

## P1 — before production E2EE

| # | Item | Ref | State |
| --- | --- | --- | --- |
| P1-6 | Deployment prerequisites: Blaze, Functions, Storage bucket + agent permission, Eventarc triggers, Cloud Scheduler | D-025 | **Open (owner actions).** Prompt 18 prepared the gates (D-137) and verified the projects read-only: billing off, no bucket, no functions (PROMPT-18-BASELINE §3). **Prompt 19:** billing is now linked to `sirf-hum-dev` only; staging and production still off (S19-1); staging still has no bucket or Functions. **Prompt 19 (second pass):** owner linked staging billing; staging bucket (`asia-south1`, private) and all 35 Functions deployed and smoke-tested; production unchanged (still off) |
| P1-6a | Reviewed Security Rules released in production; development's rules redeployed | — | **New (Prompt 18): open.** Production has **no** rules release; development's is from 2026-10-15. Deployable now through the Deploy workflow (rules pass the closed gate, D-137). **Prompt 19:** staging rules released from `c01ffb8`, verified byte-identical; production and development unchanged |
| P1-6b | Second owner and organization accounts; monitoring and budget alerts | D-025, ACCOUNT-OWNERSHIP | **New (Prompt 18): open** (owner) |
| P1-7 | Sign-in provider chosen and hardened | D-107, D-138 | **Decision proposed** (email link, D-138; needs owner approval); not configured or built. **Prompt 19:** blocks the staging beta (S19-2) |
| P1-8 | App Check attestation before the first Functions deploy | P17-10, D-028, D-139 | **Prepared, not enabled:** production refuses debug and unattested web; all callables enforce in code (static test); console steps in APP-CHECK-PRODUCTION. **Prompt 19:** no attestation path for a sideloaded staging build (S19-3); staging-only debug tokens proposed (D-147) |

**Closed in Prompt 17B (implementation; independent review is P0-1):**

| # | Item | Closed by |
| --- | --- | --- |
| P1-1 | Partner PIK verification and own-account root anchoring; no silent TOFU | D-128 |
| P1-2 | Forced pairing-code comparison | D-131 |
| P1-3 | Device-bound authorization for MLS commits | D-127 |
| P1-4 | Identity-reset notifications (content-free) | D-132 (deployment is P1-6) |

**Closed in Prompt 17C (implementation; independent review is P0-1):**

| # | Item | Closed by |
| --- | --- | --- |
| P1-3b | Conversation recovery: retire the stalled conversation, re-provision a new MLS group, device-bound (purpose 7) | D-135 |
| P1-5 | Unpairing: unilateral, from an active device only (purpose 8); couple dissolved, conversations closed | D-136 (supersedes D-134) |

## P2 — before public launch

| # | Item | Ref | State |
| --- | --- | --- | --- |
| P2-1 | Partner lockout by a trusted partner device's Remove | P17-06, E82 | Open; mitigated by recovery (D-135) and unpairing (D-136), repeatable by a hostile trusted device |
| P2-3 | Sweep picker plaintext copies | P17-11, E81 | **Fixed in Prompt 18** (D-141; unit + on-device tests). Residual: a copy lives until the next start if the process dies; no secure wipe |
| P2-4 | Content-Security-Policy for the web origin | P17-12, E17, D-140 | **Partly mitigated in Prompt 18:** Report-Only CSP + COOP/CORP/Permissions-Policy, browser-tested locally, pinned by a CI check. Enforcement still needs the deployed staging origin |
| P2-5 | Repository visibility decision before production | P17-13, E83 | Controls enabled (D-133); still public (verified 2026-10-21); make private before release (17B §5), owner action |
| P2-6 | Gradle dependency scanning | P17-16, D-142 | **Fixed in Prompt 18:** release classpaths locked (STRICT), OSV-Scanner in CI, wrapper checksum |
| P2-7 | Local rollback: server-anchored freshness or written acceptance | P17-17, E22 | Deferred (no new trust model) |
| P2-8 | Retention, server deletion, account deletion (Play policy); dissolved couples' ciphertext | P17-18, E72, D-105, D-136 | Deferred |
| P2-9 | EXIF stripping before encryption | E68, D-117 | **Deferred (Prompt 18)** until after the review: the strip belongs in the Rust media path; design in [DATA-LIFECYCLE](../DATA-LIFECYCLE.md) L1 |
| P2-10 | Revocation propagation window narrowed by deployed wake-ups | E33, E43 | Needs deployment |
| P2-11 | Build provenance / signed releases and Play App Signing | E14, D-143 | **Open; partly mitigated:** a production release can no longer be silently debug-signed (D-143). Provenance, release workflow and Play App Signing not built |

**Closed:** P2-2 (`rejectDeviceApproval` proof and limit, D-129).

## P3 — accepted post-launch risks

| # | Item | Ref |
| --- | --- | --- |
| P3-1 | Metadata visible to the server/Google | [METADATA-EXPOSURE](METADATA-EXPOSURE.md), E2, E12, E45 |
| P3-2 | Exact media sizes (padding deferred) | E45, D-099 |
| P3-3 | Server message withholding is undetectable | E10 |
| P3-4 | No post-quantum protection | D-050 |
| P3-5 | Notification timing visible to FCM and onlookers (incl. security alerts, D-132) | E11, E40, E75 |
| P3-6 | Plaintext in the Dart heap cannot be reliably wiped | E23, E46, E67 |
| P3-7 | Reads without rate limits (`listDeviceApprovalRequests`, `getPairingState`) | P17-14 |
| P3-8 | Dev-only `@grpc/grpc-js` advisories in the rules-test harness (GHSA-m9gg-hp2v-232j high, GHSA-f596-whhp-79r4 low; Dependabot alerts 1, 2) | P17-15. **Fixed in Prompt 18:** `firebase/package.json` overrides `@grpc/grpc-js` to 1.13.7 (`@firebase/firestore` 4.18.0 pins `~1.9`); `npm audit` 5 high → 0; rules tests 61 + 20 pass. Dev-only, never shipped; remove the override when `firebase` lifts its pin |
| P3-9 | RUSTSEC-2026-0330/0331 (uncompiled `libcrux-kem`), RUSTSEC-2026-0173 (compile-time `proc-macro-error2`): re-verified each CI run; remove with the next OpenMLS upgrade | D-068 |
| P3-10 | Server controls lineage ordering/completeness | E28, D-084 |
| P3-11 | A stolen unlocked active device can approve/reject/revoke/cancel a reset; only-device-stolen-without-recovery-key case | E25, D-081 |
| P3-12 | Notebook edits unbounded within the shared history | E74 |
| P3-13 | A device keeps its local partner-root anchor (D-128) after unpairing; authorizes nothing server-side | D-136, PROMPT-17C-CLOSURE §8.2 |
| P3-14 | Firestore emulator rejects some contended transactions (`INVALID_ARGUMENT`) under the parallel suite: test-infrastructure flake, never a partial state | PROMPT-17C-CLOSURE §8.3–8.4 |
| P3-15 | `unpairCouple` listed and walked the couple's conversation lineage (≤ ~64 reads) **before** verifying the challenge and proof; an over-long lineage answered with a generic error instead of `challenge_invalid` (one-bit signal). No state change, no data returned, no bypass. Found in the PR #16 merge-gate review and recorded there; recorded here in Prompt 18 | **Fixed in Prompt 18** (D-144): authorization first; regression tests `P3-15: …` (emulator). Kept in this table so the finding is not erased |

## Prompt 19 (staging activation)

Nothing closed. **S19-9** (App Links unverifiable on Firebase-reserved `assetlinks.json`; paste fallback; UX, not security). **S19-8** (password sign-ups possible alongside email link; fixed server-side by D-149). New operational findings S19-1–S19-7 ([STAGING-BETA §6](STAGING-BETA.md#6-findings)); S19-6 fixed (D-146). No new security finding in the code; no live security test failed, and most could not run.

## Closed in Prompt 18

P3-15 (D-144), P2-3 (D-141), P2-6 (D-142), P3-8 (D-142, override); implementation evidence only,
independent review is P0-1.

## Closed in Prompt 17

P17-01 (D-122), P17-02 (D-123), P17-03 and P17-04 (D-124), P17-19 (D-126),
P17-10 documentation.
