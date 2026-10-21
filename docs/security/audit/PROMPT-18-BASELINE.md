# Prompt 18 — Baseline Before Changes

Status: **recorded 2026-10-21, before any Prompt 18 change.** The state of
the repository and of the three Firebase projects when Prompt 18
(production readiness and independent-review preparation) began. Later
changes are in [PRODUCTION-LAUNCH-GATE](PRODUCTION-LAUNCH-GATE.md) and the
Decision Log (D-137–D-145).

> **Sirf Hum has not yet received an independent security or
> cryptographic review.** It is not production E2EE. Nothing is deployed
> beyond development rules; no real user's content exists.

## 1. Repository

| Item | Value | How verified |
| --- | --- | --- |
| `main` HEAD | `138a730240e0cdce8aa2fcff559a7baacf793c65` (PR #16, Prompt 17 + 17B + 17C) | `git rev-parse HEAD` |
| `origin/main` | identical | `git fetch && git rev-parse origin/main` |
| Working tree | clean | `git status` |
| Branch for this work | `security/prompt-18-production-readiness` | — |
| Visibility | **public** (`codex-warrior/sirf-hum`) | `gh repo view` |
| Controls | secret scanning, push protection, Dependabot alerts, ruleset on `main` (PR + 10 CI checks, no force-push or deletion) | D-133 |

## 2. CI baseline

| Run | Commit | Result |
| --- | --- | --- |
| CI `39552357516` | `138a730` (push to `main`) | **10/10 jobs passed** |
| Prototypes `39552357484` | `138a730` | **8/8 jobs passed** |

Counts from the last full CI evidence (PROMPT-17C-CLOSURE §8.7, plus the
final commit): Flutter 683; crypto Dart package 63; Rust core 157 passed
(2 ignored) + policy, fmt, clippy, cargo-audit; Functions unit 59, emulator
170; Firestore rules 61; Storage rules 20; Android emulator integration 21;
Android development, staging and production builds; three web builds;
gitleaks full history; OSV-Scanner (Dart).

## 3. Environments (read-only inspection, 2026-10-21)

Inspected with the owner's `gcloud`/Firebase CLI credentials, **read-only**
(no setting was changed).

| | `sirf-hum-dev` | `sirf-hum-staging` | `sirf-hum-prod` |
| --- | --- | --- | --- |
| Billing (Blaze) | **off** | **off** | **off** |
| Firestore | exists (`asia-south1`) | exists | `(default)`, `asia-south1`, Native, **delete protection ENABLED**, **PITR DISABLED** |
| Security Rules released | Firestore rules released **2026-10-15** (before Prompts 05–17: stale) | not inspected in detail | **no rules release at all** |
| Cloud Storage bucket | none | none | **none** |
| Cloud Functions | none | none | **none** |
| Firebase Authentication | — | — | **not initialized** (`CONFIGURATION_NOT_FOUND`): no provider |
| App Check | API enabled | API enabled | API enabled; **no service enforcement configured** |
| Deploy identity | `github-deployer@…` via WIF | same | `github-deployer@sirf-hum-prod`: WIF condition `repository_id == 1420599703 && repository_owner_id == 148367546 && environment == 'production' && ref == 'refs/heads/main'` |
| User-managed service-account keys | **none** on `github-deployer` | **none** on `github-deployer` | **none** (both service accounts list only Google-managed keys) |
| Project IAM (prod) | — | — | one human Owner (`ahamshashvat@gmail.com`); deployer: rules admin, index admin, hosting admin, service usage; no Owner/Editor for automation |

Notes:
- A first listing showed "1 key" for the production Admin SDK account. It
  was an artifact of my own command (`wc -l` on empty output); a direct
  listing shows only a `SYSTEM_MANAGED` key. Recorded so it is not repeated.
- Key listing intermittently failed with `INVALID_ARGUMENT` for some
  accounts; every account was eventually listed successfully.
- With no rules release, the production database is expected to deny all
  client access by default. That is unverified here (nothing calls it), and
  it is the opposite of a reviewed state: see launch gate P1-INF-3.

## 4. Deployment state

- **No production deployment has happened.** Deploy workflow history: two
  runs on 2026-10-15, both `development` rules (one failed, one succeeded).
- Deploys are manual (`workflow_dispatch`); nothing deploys on push.
- Before Prompt 18, `tool/deploy.sh production` could still be run from a
  laptop with owner credentials, and no gate tied production Functions or
  Hosting to the review (fixed: D-137).

## 5. Authentication state

- `firebase_auth` observes sessions and signs out (D-107); **no sign-in
  method exists** (D-029, D-107 Open). A real build reaches only the
  welcome screen.
- Production Firebase Authentication is not initialized.

## 6. App Check state

- Client: debug provider in development, Play Integrity (Android) and
  reCAPTCHA Enterprise (web) otherwise; production refuses the debug
  provider (`environment_guard.dart`). Before Prompt 18 a production **web**
  build without a site key skipped App Check with a warning (fixed: D-139).
- Functions: every callable passes `enforceAppCheck: true`.
- Console enforcement: **off** for Firestore and Storage in every project.
  No Play Integrity link (the app is not on Play), no reCAPTCHA key, no
  debug tokens registered.

## 7. Known risks at baseline

From [PRODUCTION-BLOCKERS](PRODUCTION-BLOCKERS.md) (D-125, after 17B/17C):

| Class | Open items |
| --- | --- |
| **P0** | P0-1 independent review; P0-2 OpenMLS delta (`a3402f2` → 0.9.1) and provider; P0-3 Rust core, C ABI, key store; P0-4 `aead::stream` and the media composition; P0-5 claim language |
| **P1** | P1-6 deployment prerequisites (Blaze, Functions, Storage, Eventarc, Scheduler); P1-7 sign-in provider; P1-8 App Check attestation |
| **P2** | P2-1 partner lockout (mitigated); P2-3 picker copies; P2-4 web CSP; P2-5 repository visibility; P2-6 Gradle scanning; P2-7 local rollback; P2-8 retention and deletion; P2-9 EXIF; P2-10 revocation window; P2-11 build provenance |
| **P3** | P3-1–P3-14 accepted (metadata, sizes, withholding, no PQ, notification timing, Dart heap, unthrottled reads, dev-only advisories, RUSTSEC exceptions, server lineage ordering, stolen unlocked device, notebook edits, local partner anchor, emulator flake) |
| **P3-15** | Recorded only in the PR #16 description, **not** in the repository: `unpairCouple` walks the couple's conversation lineage before verifying the challenge and proof (reads + a one-bit signal; no bypass). Recorded and fixed in Prompt 18 (D-144) |

## 8. Production blockers at baseline

All P0 and the three P1 items above. Sirf Hum may make **no** production
security or privacy claim (PROMPT-17C-CLOSURE §6).

## 9. Independent review

**Has not happened.** All security work so far (Prompts 05–17C) is
internal. The only third-party assurance in the dependency chain is
SRLabs' 2026-03 review of OpenMLS at commit `a3402f2` (core crates,
providers excluded), which predates the pinned 0.9.1.
