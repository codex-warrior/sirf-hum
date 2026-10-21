# Production Launch Gate

Status: **Prompt 18, 2026-10-21 (D-145). Launch is NOT permitted.**
The gate of record for opening production to real users. Blocker classes
follow D-125 ([PRODUCTION-BLOCKERS](PRODUCTION-BLOCKERS.md)); this file
adds an explicit status, evidence and owner action per gate.

> **Sirf Hum has not yet received an independent security or
> cryptographic review.** It is not production E2EE. No production
> security or privacy claim is permitted
> ([PROMPT-17C-CLOSURE §6](PROMPT-17C-CLOSURE.md#6-prohibited-security-claims)).

**Rules for this file**
- **PASS** only with evidence a reader can check (test name, CI run,
  document, command output). A PASS for an implementation means
  *implemented and tested internally*; its independent review is a P0
  gate.
- **FAIL**: required and not met. **DEFERRED**: knowingly not met yet,
  with the reason and the stage that must close it.
- Never change a status by rewording. Opening production traffic also
  needs `config/launch_gate.json` → `"open"` in a reviewed PR (D-137):
  `tool/deploy.sh` refuses production Functions and Hosting until then.

## P0 — before any production security claim

| Gate | Status | Evidence | Owner action |
| --- | --- | --- | --- |
| P0-1 Independent security and cryptographic review of the full system | **FAIL** | Not performed. Package ready: [INDEPENDENT-SECURITY-REVIEW-PACKAGE](INDEPENDENT-SECURITY-REVIEW-PACKAGE.md) | Commission a qualified external reviewer; fix or accept every finding in writing |
| P0-2 OpenMLS delta review (`a3402f2` → 0.9.1) and crypto-provider review (`openmls_rust_crypto` 0.6.0) | **FAIL** | Not performed (package §8.8, §13, Q1) | Part of P0-1 scope |
| P0-3 Rust crypto core, C ABI v6 / FFI, Dart bridge, platform key store | **FAIL** | Not performed (package §8.9) | Part of P0-1 scope |
| P0-4 STREAM media construction and composition (D-093) | **FAIL** | `aead::stream` has no known audit; D-093's approval was internal (package §8.6) | Part of P0-1 scope; F3 before any format v2 |
| P0-5 Full E2EE architecture (D-127, D-128, D-131, D-135, D-136, D-144; device proofs 1–8; recovery, revocation, reset) | **FAIL** | Not performed (package §8) | Part of P0-1 scope |
| P0-6 Claim language | **DEFERRED** | No store listing, website or release copy exists; prohibited claims listed (17C §6) | Copy review against §6 before any public material |

## P1 — before production E2EE (real users' content)

### Infrastructure

| Gate | Status | Evidence | Owner action |
| --- | --- | --- | --- |
| P1-INF-1 Blaze billing on staging and production (D-025) | **FAIL** | `gcloud billing projects describe`: `billingEnabled: False` for all three (2026-10-21) | Link an organization billing account (ACCOUNT-OWNERSHIP) and set budget alerts |
| P1-INF-2 Functions, Eventarc triggers, Cloud Scheduler, Storage bucket (`asia-south1`) + Storage service agent permission (P1-6) | **FAIL** | None exist in `sirf-hum-prod` (no bucket; no functions) | After INF-1: create the bucket in `asia-south1`; grant Functions deploy roles to `github-deployer` (ENVIRONMENTS "Deploy identities"); deploy staging first |
| P1-INF-3 Reviewed Security Rules released in production | **FAIL** | `firebaserules … /releases` for `sirf-hum-prod` returns **no release**; development's release dates from 2026-10-15 (stale) | Deploy rules through the Deploy workflow (`targets: rules`, `storage` once the bucket exists): allowed while the gate is closed (D-137). Redeploy development |
| P1-INF-4 Backups and recovery: PITR / scheduled backups tied to the retention policy | **DEFERRED** | Firestore delete protection **enabled**, PITR **disabled** (2026-10-21) | Decide with P2-8 (backups must expire with deletion); enable after the decision |
| P1-INF-5 Environment separation and no accidental production deploy | **PASS** | Separate projects; no default project; runtime and Functions environment guards (tests `environment_guard_test.dart`, `environment.test.mjs`); production deploys only from the Deploy workflow and Functions/Hosting only behind the launch gate (`tool/test_deploy_guard.sh`, 23 cases, CI); nothing deploys on push | Keep `config/launch_gate.json` closed until every P0 and P1 gate is PASS |
| P1-INF-6 Least-privilege deploy credentials, no long-lived keys, WIF only | **PASS** | No user-managed service-account keys in any project; production WIF condition binds repository ID, owner ID, `production` environment and `refs/heads/main`; deployer has no Owner/Editor (PROMPT-18-BASELINE §3) | Re-check before enabling Functions roles; grant `roles/iam.serviceAccountUser` only on the runtime service account |
| P1-INF-7 Account ownership: ≥ 2 owners, organization accounts | **FAIL** | One personal Owner on every project; personal GitHub account (ACCOUNT-OWNERSHIP) | Add a second owner with hardware-key 2FA; move to organization accounts |
| P1-INF-8 Monitoring and alerting (Functions errors, rate-limit spikes, App Check rejections, budget) | **FAIL** | Nothing configured (no deployment) | Cloud Monitoring alert policies on error rate and invocation spikes; budget alerts; review Cloud Logging retention with P2-8 |
| P1-INF-9 Region and data residency | **PASS** (architecture) | Production Firestore `asia-south1` (verified); Functions `REGION = asia-south1`; global services documented (ENVIRONMENTS). Not a legal certification | Create the bucket in `asia-south1` (INF-2) |

### Authentication and App Check

| Gate | Status | Evidence | Owner action |
| --- | --- | --- | --- |
| P1-7 Production sign-in provider | **FAIL** | Decision proposed: email link (D-138, [AUTH-PRODUCTION-DECISION](../../architecture/AUTH-PRODUCTION-DECISION.md)); Firebase Authentication not initialized in production; no sign-in UI | Approve D-138; follow its §10 console steps (staging first); authorize the sign-in UI prompt |
| P1-8 App Check attestation and enforcement | **FAIL** | Code ready: production refuses debug and unattested web (D-139 tests); all 29 callables enforce in code (static test). Console: no enforcement, no Play Integrity link, no reCAPTCHA key | [APP-CHECK-PRODUCTION](../../architecture/APP-CHECK-PRODUCTION.md) §3 steps 1–9, **before** the first Functions deploy |

### Security behaviour (implemented; review is P0)

| Gate | Status | Evidence | Owner action |
| --- | --- | --- | --- |
| Device trust (proofs 1–8, approvals, PIK uniqueness, lineage) | **PASS** (implementation) | TEST-MATRIX "Device trust"; D-070, D-075, D-084, D-085, D-122; CI 10/10 on `138a730` | Independent review (P0-5) |
| Partner verification (safety number, QR) | **PASS** (implementation) | D-128; `safety_number_test.dart`, `verification_controller_test.dart`, native `partner_verification_test.dart` (CI) | P0-5 |
| Commit authorization | **PASS** (implementation) | D-127; F/S/Fu/D tests (TEST-MATRIX) | P0-5 |
| Conversation recovery | **PASS** (implementation) | D-135; `recovery.test.mjs` (9), R and native D tests | P0-5 |
| Unpairing | **PASS** (implementation) | D-136 + D-144; `unpair.test.mjs` (15, incl. two P3-15 tests) | P0-5 |
| Revocation and identity reset | **PASS** (implementation) | D-081, D-082; emulator and Rust tests (TEST-MATRIX) | P0-5 |
| Reset and revocation alerts delivered | **FAIL** | Triggers built (D-132, D-097) but undeployed (Eventarc) | INF-2 |

## P2 — before public launch

| Gate | Status | Evidence | Owner action |
| --- | --- | --- | --- |
| P2-1 Partner lockout by a hostile trusted device | **FAIL** (mitigated) | Recovery (D-135) and unpairing (D-136) exist; a trusted partner device can still remove the other's devices repeatedly | Design question for the review (package Q9); product copy must not claim otherwise |
| P2-3 Photo-picker plaintext copies | **PASS** | D-141; `picker_cache_sweeper_test.dart`, on-device `moments_test.dart` (CI) | Re-check the layout on every `image_picker_android` upgrade |
| P2-4 Web CSP | **DEFERRED** | Report-Only policy, browser-tested locally with 0 reports (D-140); headers pinned by `tool/check_web_headers.mjs` | Deploy to staging Hosting, collect reports with Firebase configured, self-host CanvasKit, then enforce |
| P2-5 Repository visibility | **FAIL** | Public (`gh repo view`, 2026-10-21) | Owner: make private before the first production release, keeping secret scanning and the ruleset (17B §5) |
| P2-6 Gradle dependency scanning | **PASS** | D-142; `android/app/gradle.lockfile` (STRICT), OSV-Scanner in CI (183 packages, 0 advisories locally); wrapper checksum | Regenerate locks deliberately on upgrades |
| P2-7 Local rollback detection | **DEFERRED** | D-079; pinned by `documented_limit_a_restored_older_state_is_not_detected_until_refreshed` | Server-anchored freshness design after the review, or written acceptance |
| P2-8 Retention, server deletion, account deletion (Play policy) | **FAIL** | Not built; order designed (AUTH-PRODUCTION-DECISION §8, DATA-LIFECYCLE §4) | Retention decision; build after Blaze; Play requires account deletion |
| P2-9 EXIF stripping | **DEFERRED** | Design in DATA-LIFECYCLE L1 (belongs in the Rust media path; not added before the review to keep the reviewed surface stable) | Implement after the review with golden-file tests; until then UI must say location stays in the photo |
| P2-10 Revocation propagation window | **DEFERRED** | Push wake-ups built, need deployment | INF-2, then measure |
| P2-11 Build provenance, signed releases, Play App Signing | **FAIL** | Partial: production release refuses debug signing (D-143; CI proves the refusal). No release workflow, no provenance attestation, no Play App Signing | Build the release workflow per D-143 |

## P3 — accepted residual risks (documented)

PASS here means *documented, bounded and tested where testable*; each
still needs the owner's written acceptance at launch.

| Gate | Status | Evidence |
| --- | --- | --- |
| P3-1 Metadata visible to server/Google | **PASS** (documented) | METADATA-EXPOSURE |
| P3-2 Exact media sizes | **PASS** (documented) | D-099, E45 |
| P3-3 Server withholding undetectable | **PASS** (documented) | E10 |
| P3-4 No post-quantum protection | **PASS** (documented) | D-050 |
| P3-5 Notification timing | **PASS** (documented) | E11, E40, E75, D-132 |
| P3-6 Dart heap plaintext | **PASS** (documented) | E23, E46, E67 |
| P3-7 Unthrottled reads | **PASS** (documented) | P17-14 |
| P3-8 Dev-only grpc-js advisories | **PASS** (documented) | P17-15 |
| P3-9 RUSTSEC-2026-0330/0331/0173 exceptions | **PASS** (re-verified every CI run) | `tool/crypto_audit.sh`; no compatible OpenMLS upgrade removes them (re-checked 2026-10-21) |
| P3-10 Server controls lineage ordering | **PASS** (documented) | D-084, R `documented_limit_peers_rely_on_server_ordering_for_revoked_approvers` |
| P3-11 Stolen unlocked active device | **PASS** (documented) | D-081 |
| P3-12 Notebook edits unbounded | **PASS** (documented) | E74 |
| P3-13 Local partner anchor after unpair | **PASS** (documented) | D-136, 17C §8.2 |
| P3-14 Emulator transaction flake | **PASS** (documented; test infrastructure) | 17C §8.3–8.4 |
| P3-15 Unpair walked the lineage before authorization | **PASS** (fixed in Prompt 18) | D-144; emulator `P3-15: …` tests |

## Summary

| Class | PASS | FAIL | DEFERRED |
| --- | --- | --- | --- |
| P0 | 0 | 5 | 1 |
| P1 | 9 | 8 | 1 |
| P2 | 2 | 4 | 4 |
| P3 | 15 | 0 | 0 |

**Production deployment remains blocked.** **Independent review remains
mandatory.** The repository is prepared for that review; it is not
prepared for launch.
