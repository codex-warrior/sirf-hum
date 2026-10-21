# Prompt 19 — Staging Activation and Real-Device Beta

Status: **2026-10-21. BLOCKED — owner actions required (§9).** Staging
Firestore rules and indexes are deployed and verified; nothing else in
staging could be activated, and the real-device beta did not run.
Boundaries and runbook: [STAGING-BETA](../../STAGING-BETA.md). Decisions:
D-146 (accepted), D-147 (proposed).

> Sirf Hum is **not production E2EE** and has **not been independently
> audited or reviewed**. Staging tests do not replace the independent
> review (P0-1). Production was not touched (§8).

## 1. Starting point

| Item | Value |
| --- | --- |
| `main` | `c01ffb81aea35d12274dfe5af1476627b14b02d9` (PR #17, Prompt 18; post-merge CI 10/10) |
| Branch | `feature/staging-activation` |
| Owner's statement | "Firebase Blaze billing has now been manually enabled" |

## 2. Billing, verified (not assumed)

`gcloud billing projects describe <project>`, 2026-10-21:

| Project | Billing | Account |
| --- | --- | --- |
| `sirf-hum-dev` | **enabled** | `billingAccounts/01F262-…` ("Firebase Payment") |
| `sirf-hum-staging` | **not enabled** | — |
| `sirf-hum-prod` | not enabled | — |

**S19-1:** Blaze was linked to **development**, not staging. Staging
cannot create a bucket or deploy Functions. Linking billing is a
financial action and was left to the owner. Development is now billable
with nothing scheduled or deployed there beyond Firestore (no Functions,
no bucket); no budget could be read: the Budgets API is not enabled on
the CLI's default project (an unrelated project, S19-5), and enabling it
there was out of scope.

APIs enabled in staging (identical across the three projects; nothing
was enabled in Prompt 19): Firestore/Datastore, Firebase Rules, App Check,
Identity Toolkit, Secure Token, FCM, Firebase Installations, Crashlytics,
Hosting, Storage (API only), Pub/Sub, IAM/STS/IAM Credentials, Logging,
Monitoring, plus Firebase/BigQuery defaults. **Not enabled:** Cloud
Functions, Cloud Build, Artifact Registry, Cloud Run, Eventarc, Cloud
Scheduler (the Functions deploy enables them once billing exists).

## 3. Staging infrastructure status

| Area | Status | Evidence |
| --- | --- | --- |
| Firestore `(default)` | Exists, `asia-south1`, Native; delete protection off, PITR off (staging data is test data) | `gcloud firestore databases list` |
| **Firestore rules** | **Deployed 2026-10-21 09:16 UTC** from `c01ffb8` (clean tree) via `tool/deploy.sh staging`, after the rules suite passed (61 Firestore + 20 Storage). Live ruleset `69b95612-…` is **byte-identical** to `firebase/firestore.rules` (SHA-256 `997e8609…7f9cfa`) | Rules API `releases/cloud.firestore` + ruleset source compared |
| Firestore indexes | Deployed with the rules | deploy output |
| Live deny smoke test | Unauthenticated `GET users/…`, `couples/…`, `conversations/…`, `accountTrust/…`, `users/…/devices/…`, `LIST conversations`, `PATCH users/…` → **403** each | REST with the public API key, no token |
| Storage | **No bucket** (billing). Rules not deployable | `gcloud storage buckets list` |
| Functions | **Not deployed** (billing). Statically staging-clean: `SH_ENV=staging` from `functions/.env.staging`, cold-start project assertion (`environment.ts`), region `asia-south1`, no project/bucket literal outside `environment.ts`, no secrets (`defineString('SH_ENV')` only) | grep, `npm run check` |
| Functions deploy identity | Staging deployer has rules/indexes/hosting/service-usage roles **only** (S19-4); a workflow Functions deploy would fail | `gcloud projects get-iam-policy` |
| Auth | **Not initialized** (`CONFIGURATION_NOT_FOUND`); **the app has no sign-in code** (no `signIn*`/`sendSignInLinkToEmail` in `lib/`) | Identity Toolkit admin API; grep |
| App Check | API on; no service configuration; nothing enforced. Callables enforce in code (E94) | App Check API `services` → `{}` |
| FCM | API on; fan-out lives in Functions (not deployed) | — |
| Eventarc / Scheduler | Not enabled (come with Functions) | services list |

## 4. Android staging build

- **CI's staging job is not a beta build (S19-6):** it builds
  `--debug --dart-define=SH_ENV=staging` without the staging config, so
  Firebase is "not configured" and it reaches no backend.
- **Added (D-146):** `.github/workflows/staging-build.yml`, manual: release
  APK, `--flavor staging --dart-define-from-file` from the `staging`
  environment secret, config checked by `tool/check_env_config.mjs`
  before the build; verifies the application ID `com.sirfhum.app.staging`
  (aapt2), the crypto core for every ABI, that `libapp.so` embeds the
  staging Android app ID and **no app ID of development or production**,
  and that the Gradle lockfile is unchanged; prints the APK SHA-256;
  artifact kept 7 days. Never uploads to Play. Debug-signed (no staging
  key exists; not distributable). **Not yet run:** a `workflow_dispatch`
  workflow can only be started once it is on `main`, and the staging
  secret is not set (owner action 8).
- Local build not possible on this machine (no MSVC for the Rust native
  assets; Rust tests also fail to link here; CI builds and tests both).

## 5. Security tests A–P

"Automated" = existing evidence that ran green in this prompt (counts in
§7). "Live" = against deployed staging.

| | Property | Automated evidence | Live staging |
| --- | --- | --- | --- |
| A | Account A cannot access account B | Rules `devices`, `couple`, `default_deny`; Functions `device_registration`, `multi_device` | Unauthenticated deny only (§3); per-account needs Auth |
| B | Couple A cannot access couple B | Rules `couple`, `messaging`, `storage/moments_isolation` | Blocked (Auth) |
| C | No access to revoked device state | Functions `multi_device`, rules `devices` | Blocked (Functions) |
| D | Revoked device cannot send | Functions `commit`, rules `messaging` | Blocked |
| E | Unpaired partner cannot access new content | Functions `unpair` (17C, D-136) | Blocked |
| F | Forged/modified device proof fails | Functions unit `device_proof`, emulator `hardening` | Blocked |
| G | Forged/modified commit fails | Functions `commit` (D-127) | Blocked |
| H | Replay fails | Functions `commit`, `recovery`, `unpair` (single-use challenges) | Blocked |
| I | Pairing code mismatch fails | Functions `pairing` (D-131) | Blocked |
| J | Wrong safety number shows unverified | Dart `test/security/verification` (D-128) | Blocked (device) |
| K | No server-side plaintext | Envelope-only boundary (`EncryptedEnvelope`), rules field allowlists | Nothing written yet |
| L | Push is content-free | Functions unit `notification` (constant payload: title "Sirf Hum", body "You have a new message" / "Review a security change", data `{v,k}`) | Blocked (Functions) |
| M | Web has private content disabled | D-046 tests (TEST-MATRIX) | Not deployed to staging Hosting |
| N | Storage private | Rules `storage/media_storage`, `moments_isolation` | Blocked (no bucket) |
| O | Functions do not log plaintext | `index.ts`: `logger.info(event, { outcome })` and counts only | Blocked |
| P | Crashlytics gets no private content | `test/core/logging/app_logger_test.dart` (redaction) | Blocked (device) |

No live security test failed; most could not run. Nothing here is a
claim that the deployed system is secure.

## 6. Findings

| ID | Class | Finding | Action |
| --- | --- | --- | --- |
| S19-1 | Operational (P1-6) | Blaze linked to `sirf-hum-dev`, not `sirf-hum-staging` | Owner: link staging; keep or unlink dev deliberately |
| S19-2 | Blocker (P1-7) | No sign-in method in the app; a real build stops at the welcome screen | Owner: approve D-138, authorize the sign-in prompt |
| S19-3 | Blocker (P1-8) | A sideloaded staging build has no attestation path (Play Integrity needs Play Console); every callable would reject it | Owner: decide D-147 |
| S19-4 | Operational | Staging deployer lacks Functions deploy roles | Owner: grant roles, or deploy with owner credentials from a clean tree |
| S19-5 | Operational (E100) | `gcloud` default project on the operator machine is an unrelated project; a command without `--project` acts there | Use `--project` always; optionally a dedicated `gcloud` configuration |
| S19-6 | BUG (fixed, D-146) | CI staging APK carries no Firebase config, so no staging build could reach the backend | `staging-build.yml`; `check_env_config.mjs` |
| S19-7 | Note | Staging Firestore delete protection off | Acceptable for test data; production's is on |

**Product/UX findings: none recorded.** The app was not exercised on a
device (§4); a review of the welcome screen alone would not be a product
beta. The UX categories in the prompt (pairing, Moments, Future, Us,
back button, keyboard, media, accessibility) carry over to the first
beta run.

## 7. Verification run in Prompt 19 (local, Windows)

| Check | Result |
| --- | --- |
| `dart format` / `flutter analyze` | clean / no issues |
| Flutter tests | **559 passed, 135 skipped** (native crypto tests skip without a host build; CI runs them: 683 at Prompt 18) |
| Crypto Dart package | 22 passed, 41 skipped (same reason) |
| Rust: crypto policy, `cargo fmt`, `clippy -D warnings`, `cargo audit` | pass (audit: 202 crates, 3 documented ignores) |
| Rust tests | **not run locally** (MinGW link failure, known); CI |
| Functions unit / emulator | **62 / 62**, **172 / 172** |
| Firestore / Storage rules | **61 / 61**, **20 / 20** |
| Deploy guard / web headers | 23 / 23 / pass |
| Env config isolation (new) | 9 / 9; real development and staging configs pass, a staging file checked as production fails |
| gitleaks (full history, 103 commits) | no leaks |
| OSV, Android emulator, Android builds, web builds | CI (PR) |

## 8. Production remains locked (re-verified at the end of Prompt 19)

`sirf-hum-prod`: billing off; no rules release; no bucket; Functions API
not enabled; Auth not initialized; App Check unconfigured; launch gate
`config/launch_gate.json` = `"closed"` (unchanged); nothing uploaded to
Play; no Hosting deploy by this prompt.

## 9. Owner actions (none performed by the agent)

In order; details in [STAGING-BETA §3](../../STAGING-BETA.md#3-activation-order-owner--agent).

1. Link billing to `sirf-hum-staging`; decide about `sirf-hum-dev`.
2. Budgets with alerts for the staging (and development) projects.
3. Storage → Get started in `asia-south1` (permanent).
4. Decide D-147 (App Check for the beta).
5. Approve D-138; authorize the sign-in prompt; initialize staging Auth
   (email link only, enumeration protection, staging Hosting domains).
6. Functions deploy path (roles for the staging deployer, or owner deploy).
7. `gh secret set SH_ENV_CONFIG_JSON --env staging < config/env/staging.json`.
8. Review and merge this PR; then run "Staging beta build".

After 1–3 the agent can deploy Storage rules; after 1, 4 and 6,
Functions; after 5, the beta plan (STAGING-BETA §6) can start.
