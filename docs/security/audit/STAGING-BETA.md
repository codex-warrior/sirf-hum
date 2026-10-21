# Prompt 19 — Staging Activation and Real-Device Beta

Status: **2026-10-21. PARTIALLY READY.** Backend activated after the owner
linked billing to staging (§10): Firestore, Storage and all 35 Functions
are deployed and verified. Still blocked for devices: no sign-in method
(D-138 not approved) and no App Check path for a sideloaded build (D-147
not approved). The real-device beta has not run.
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

## 10. Resumed after staging billing (2026-10-21, second pass)

Billing verified: `sirf-hum-staging` **enabled**; production still **off**. Every mutation below targeted `sirf-hum-staging` explicitly; nothing touched production or iOS.

| Category | Item |
| --- | --- |
| **Done manually (owner)** | Billing linked to `sirf-hum-staging` |
| **Done automatically** | Enabled `firebasestorage.googleapis.com`; created the default bucket `sirf-hum-staging.firebasestorage.app` in **ASIA-SOUTH1**; set **public access prevention = enforced** and **uniform bucket-level access** (no public IAM members) |
| | Granted the Firebase Storage service agent `roles/firebaserules.firestoreServiceAgent` (the standard cross-service grant; the Storage rules read conversation state from Firestore and fail closed without it) |
| | Storage rules deployed via `tool/deploy.sh staging --only storage` after 61 + 20 rules tests; live ruleset byte-identical to `firebase/storage.rules` |
| | Functions deployed via `tool/deploy.sh staging --only functions` (APIs enabled by the CLI: Functions, Build, Artifact Registry, Run, Eventarc, Scheduler): **35/35 ACTIVE** — 29 callables, 5 Firestore triggers, 1 scheduled job; Node 22, 2nd gen, `asia-south1`, `maxInstances: 10` |
| | Artifact Registry cleanup policy: images older than 1 day deleted (cost) |
| **Deploy incidents (resolved)** | First parallel deploy: Eventarc service-agent propagation (5 triggers) and Cloud Run "Quota exceeded for total allowable CPU per project per region" (10 functions; each 2nd-gen function requests 1 vCPU during health checks). Retried in small batches. Nine callables whose first create had failed were left **without** the standard callable invoker binding (Cloud Run 403 before the function); deleted and recreated through `tool/deploy.sh` so the CLI applied it. Triggers and the scheduled job correctly have no public invoker |
| **Blocked: approval (not permission)** | Auth: D-138 (email link) not approved and no sign-in code exists, so no provider was enabled (enabling one would let anyone with the public API key create accounts with no app to use them). App Check: Play Integrity needs Play Console (excluded); staging debug tokens (D-147) not approved, so staging stays **fail-closed** |
| **Blocked: external account** | GitHub `staging` secret `SH_ENV_CONFIG_JSON` not set, and `staging-build.yml` can only be dispatched once on `main` |
| **Not yet safe** | Budgets (billing-account configuration, owner); live authenticated tests (need Auth) |
| **Missing permissions** | **None.** The operator account is `roles/owner` on staging |

### Live verification

| Check | Result |
| --- | --- |
| Storage without auth: GET/LIST/UPLOAD on `conversations/…/media/…` and other paths (Firebase API) | 403 each; GCS JSON list 401; public URL 403 |
| Regional CPU quota at runtime | 29 simultaneous cold starts (a parallel smoke test) gave 9× 503; sequential calls all 401. Normal two-tester use is far below this. Fix if it recurs: request a Cloud Run CPU quota increase for `asia-south1` (owner, console) or lower per-function CPU in code (a reviewed change; affects production config too) |
| All callables without auth or App Check | `401 UNAUTHENTICATED` before function code; forged `X-Firebase-AppCheck` → rejected ("AppCheck token was rejected"), 401 |
| Scheduler | exactly 1 job (`cleanupExpiredDeviceRecords`, every 24 h, UTC); no duplicates |
| Eventarc | exactly 5 triggers (Firestore created/updated for messages, commits, accountTrust, couples, devices); no leftovers from the failed attempt |
| Function logs | SDK verification messages and categories only; no payloads, IDs, tokens or content |
| Staging config regenerated from the live project | identical to the existing file; `check_env_config.mjs staging` passes |
| Cross-environment search (code, CI, tools) | project IDs appear only in env→project maps, guards and example configs; no stray project or bucket literal |

### Cost observations

Nothing always-on: every function scales to zero (no `minInstances`), one daily job, Artifact Registry pruned daily. Expected staging cost while idle: storage of a few container images and near-zero Firestore/Storage. Function logs so far: a handful of entries from smoke tests. **Recommended (owner):** budget on the billing account scoped to `sirf-hum-staging` with alerts at 50/90/100 % (alerts only; no cap).

### Two-device readiness (Phone A trusted, Phone B new)

All 19 requested scenarios are **BLOCKED**, none failed: the build cannot sign in (no sign-in UI) and callables would reject it (no attestation). Plan and defect template: STAGING-BETA §6.

## 11. After owner approval of D-138 and D-147 (2026-10-21, third pass)

| Category | Item |
| --- | --- |
| **Done automatically** | Email-link sign-in built for Android (D-148) with 21 new tests; per-flavor App Link to `<project>.firebaseapp.com/__/auth/` |
| | Staging Hosting deployed (`tool/deploy.sh staging --only hosting`, from a clean worktree of `313ab0b`): `sirf-hum-staging.web.app` and the `/__/auth/` handler serve 200 |
| | Staging signing key generated outside the repo; SHA-256 `e7c88d35…a4bbc7` registered on the **staging** Android app only |
| | GitHub `staging` environment secrets set: `SH_ENV_CONFIG_JSON` (checked by `check_env_config.mjs`), `STAGING_KEYSTORE_BASE64`, `STAGING_KEYSTORE_PASSWORD`. Production environment: 0 secrets, unchanged |
| | `staging-build.yml`: signs with the staging key (refuses without it), verifies the certificate, builds with the App Check debug provider (D-147) |
| **Blocked: owner console action** | Firebase Auth not initialized in staging (`CONFIGURATION_NOT_FOUND`). The only API that initializes it (`initializeAuth`) upgrades the project to Identity Platform, which was not approved. Owner: console → Authentication → **Get started**. Then the agent sets, via the admin API: email link only (no password), email-enumeration protection, authorized domains = staging Hosting domains |
| **Pending verification** | `assetlinks.json` on the staging auth domain still served empty right after the SHA-256 was registered; until it lists the app, links open in the browser and the in-app "paste the link" path is the fallback |
| **Per phone, at install (D-147)** | First launch prints the App Check debug secret to logcat (`adb logcat \| grep -i DebugAppCheckProvider`); register it in console → App Check → Apps → staging Android → Manage debug tokens (or send it to the agent to register through the API). Delete the tokens when the beta ends |

## 12. Staging Auth configured (2026-10-21, fourth pass)

| Item | Result |
| --- | --- |
| Owner: Authentication → Get started | Done; project type `FIREBASE_AUTH` (no Identity Platform upgrade) |
| Sign-in methods (admin API) | Email link is the only method the app offers; the Email/Password provider is enabled because email link requires it (D-149); anonymous, phone and social providers off; anonymous sign-up → `ADMIN_ONLY_OPERATION` |
| Email-enumeration protection | on |
| Authorized domains | `sirf-hum-staging.firebaseapp.com`, `sirf-hum-staging.web.app` (`localhost` removed) |
| Email-link backend | Admin-minted link (no email sent) for a probe account → `signInWithEmailLink` succeeded; the link is `https://sirf-hum-staging.firebaseapp.com/__/auth/action?…mode=signIn…`, matching the app's filter |
| **S19-8** password sign-ups possible | Server side fixed by D-149 (callables require `email_verified`); pre-hijack verified closed by Firebase |
| App Links | Firebase serves an empty `assetlinks.json`; we serve our own per environment (`tool/app_links.mjs`: staging lists only `com.sirfhum.app.staging` + the staging certificate; production and development `[]`) |
| Probe accounts | 3 created and deleted; staging Auth has 0 accounts |
| Production Auth | still `CONFIGURATION_NOT_FOUND` (untouched) |
