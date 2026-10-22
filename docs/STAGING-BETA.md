# Staging Beta — Environment Boundaries and Runbook

Status: **Prompt 19, 2026-10-21. Staging backend activated: billing (owner),
Firestore, Storage (`asia-south1`, private) and all 35 Functions. Auth and
App Check await owner decisions (D-138, D-147).** The real-device beta is
**blocked** (§5). Current state,
evidence and findings: [audit/STAGING-BETA](security/audit/STAGING-BETA.md).
Decisions: D-146, D-147.

> **STAGING ≠ PRODUCTION.** Staging is a separate Firebase project with its
> own app identity, credentials and data. Nothing in this document opens,
> configures or deploys production. Sirf Hum is **not production E2EE** and
> has **not been independently reviewed**; the staging beta does not
> replace that review (P0-1).

## 1. Environment boundaries (verified 2026-10-21)

Verified live with the owner's CLI credentials unless marked "repo".

| | Development | **Staging** | Production |
| --- | --- | --- | --- |
| Firebase project ID | `sirf-hum-dev` | **`sirf-hum-staging`** | `sirf-hum-prod` |
| Project number (prefix of every app ID; FCM sender) | `627383930881` | **`203770631547`** | `244475624083` |
| Android application ID (registered Firebase app) | `com.sirfhum.app.dev` | **`com.sirfhum.app.staging`** | `com.sirfhum.app` |
| Web app | registered | registered (`1:203770631547:web:…`) | registered |
| Client config (git-ignored) | `config/env/development.json` | `config/env/staging.json` (checked by `tool/check_env_config.mjs`) | not kept locally |
| `.firebaserc` alias (no default) | `development` | `staging` | `production` |
| Functions `SH_ENV` (`functions/.env.<alias>`; cold-start project check, repo) | `development` | `staging` | `production` |
| Region (Firestore, Functions, Storage) | `asia-south1` | `asia-south1` | `asia-south1` |
| Firestore `(default)` | `asia-south1`, Native | `asia-south1`, Native, delete protection **off**, PITR off | `asia-south1`, Native, delete protection **on**, PITR off |
| Storage bucket | none | **`sirf-hum-staging.firebasestorage.app`, ASIA-SOUTH1, public access prevention enforced** | none |
| Cloud Functions | none (API not enabled) | **35 deployed (29 callables, 5 triggers, 1 job)** | none (API not enabled) |
| Firebase Auth | not initialized | **not initialized** | not initialized |
| App Check | API on, no service config | API on, no service config | API on, no service config |
| Billing | Blaze | **Blaze (linked by owner)** | not linked |
| Deploy identity (WIF) | `github-deployer@sirf-hum-dev` | `github-deployer@sirf-hum-staging`, condition `repository_id == 1420599703 && repository_owner_id == 148367546 && environment == 'staging'` | `github-deployer@sirf-hum-prod`, plus `ref == refs/heads/main` |
| Deployer roles | rules, indexes, hosting, service usage | same; **no Functions deploy roles** | same |
| Service-account keys | none | none user-managed | none user-managed |
| GitHub Environment | `development` | `staging`: WIF variables; **no secrets** | `production`: `main` only; no secrets |

Separation holds at every layer (ENVIRONMENTS "How isolation is enforced"),
and Prompt 19 adds one: `tool/check_env_config.mjs` refuses a config whose
values name another environment's project ID or project number, so a
staging build cannot carry a production app ID or bucket (D-146).

**Operator hazard:** on the owner's machine `gcloud`'s default project is
an unrelated project. Every command in this document passes `--project`
explicitly; do the same (S19-5).

## 2. What staging needs, by service

From the existing architecture (FIREBASE-ARCHITECTURE, E2EE-MEDIA-AND-NOTIFICATIONS):

| Service | Why | Billing? | Status |
| --- | --- | --- | --- |
| Firestore + rules + indexes | All server state | No (free quota) | **Deployed** (rules = repo, byte-identical) |
| Cloud Storage default bucket + rules | Encrypted media blobs | **Yes** (Blaze for new buckets) | Blocked: billing |
| Cloud Functions (2nd gen): 29 callables, 1 scheduled job, 5 Firestore triggers | Device registry, trust, pairing, commits, recovery, unpair, push fan-out | **Yes** (Cloud Build, Artifact Registry, Cloud Run) | Blocked: billing |
| Eventarc | The 5 `onDocumentCreated/Updated` triggers | Yes (with Functions) | Enabled by the Functions deploy |
| Cloud Scheduler | `cleanupExpiredDeviceRecords` (every 24 h) | Yes (with Functions) | Enabled by the Functions deploy |
| Firebase Auth | Accounts (D-138: email link) | No | Not initialized; **no sign-in UI exists** |
| App Check | Every callable has `enforceAppCheck: true` | No | Blocked: no attestation path for a sideloaded build (D-147) |
| FCM | Content-free wake-ups | No | Needs Functions |
| Crashlytics | Sanitized records only | No | Created on first report |

Cost-producing services once billing is on: Functions (invocations,
compute, Cloud Build minutes, Artifact Registry storage for images),
Storage (stored bytes, operations, egress), Firestore beyond the free
quota, Eventarc and Scheduler (per job). Prices are on the Firebase and
Google Cloud pricing pages; this document does not restate them. Budgets
alert, they do not cap spend.

## 3. Activation order (owner + agent)

Each step names who does it. Never `firebase use`, never a bare
`firebase deploy`; only `tool/deploy.sh staging` or the Deploy workflow.

| # | Step | Who | Command / place |
| --- | --- | --- | --- |
| 1 | Link the billing account to **staging** (and decide whether development should stay on Blaze) | Owner | Firebase console → `sirf-hum-staging` → Usage and billing → Blaze; or `gcloud billing projects link sirf-hum-staging --billing-account=<account>` |
| 2 | Budget with alerts for `sirf-hum-staging` (and `sirf-hum-dev`) | Owner | Cloud console → Billing → Budgets & alerts → scope: project → thresholds 50/90/100 % |
| 3 | Create the default bucket in **`asia-south1`** (permanent choice) | Owner | Firebase console → Storage → Get started |
| 4 | Deploy Storage rules (repo rules, no staging variant) | Agent/owner | `tool/deploy.sh staging --only storage` |
| 5 | Decide and set up App Check for the beta (D-147) | Owner | §4 |
| 6 | Approve D-138 and authorize the sign-in prompt; initialize Auth (email link only, enumeration protection on, authorized domains = staging Hosting) | Owner | AUTH-PRODUCTION-DECISION §10 on `sirf-hum-staging` |
| 7 | Functions deploy: either grant the staging deployer the Functions roles (ENVIRONMENTS "Deploy identities") or deploy from a clean tree with owner credentials | Owner | `tool/deploy.sh staging --only functions` |
| 8 | Staging config secret for the build workflow | Owner | `gh secret set SH_ENV_CONFIG_JSON --env staging < config/env/staging.json` |
| 9 | Build the APK | Owner | Actions → "Staging beta build" (after merge) |
| 10 | Two-device test plan | Owner + tester | §6 |
| 11 | Google sign-in (D-150): enable the Google provider in staging, add the staging key's **SHA-1** (Staging beta build job summary) to `com.sirfhum.app.staging` only; then regenerate the config and update step 8's secret | Owner (console), then agent | AUTH-PRODUCTION-DECISION §12 |

## 4. App Check for a sideloaded staging build (D-147, accepted 2026-10-21)

**Owner decision:** option A below, staging only; debug App Check is never enabled in production. Built into `staging-build.yml`.

Play Integrity, the documented staging provider, needs the app in Play
Console (APP-CHECK-PRODUCTION §3 step 1), and this beta uploads nothing
to Play. Without attestation every callable rejects the build (they
enforce in code), so device registration fails on step 3 of the plan.
Options, none applied:

| Option | Effect | Assessment |
| --- | --- | --- |
| **A. Debug provider in staging, two registered debug tokens, deleted at beta end** | Build with `SH_APPCHECK_PROVIDER=debug` (the guard already allows it outside production); each test phone prints its token to logcat once; owner registers it under staging App Check → Manage debug tokens | **Recommended** for a two-person beta. Deviates from APP-CHECK-PRODUCTION step 5 ("never in staging"), so it needs the owner's decision. A token is a bearer secret for staging only; a leaked token still needs an account session and device proofs |
| B. Play Console internal testing for `com.sirfhum.app.staging` | Real Play Integrity, closest to production | Needs a Play developer account and an upload, which Prompt 19 forbids. The right path for the next beta stage |
| C. Turn off `enforceAppCheck` for staging | — | **Rejected:** weakens a reviewed control (rule 13 of the prompt; E94) |

## 5. Why the real-device beta is blocked

1. ~~Billing~~ resolved: staging backend deployed (audit record §10).
2. ~~No sign-in method~~ built for Android (D-138 accepted, D-148); waits
   on staging Auth initialization (owner console click, audit record §11).
3. ~~No attestation path~~ D-147 accepted: per-phone debug tokens (§4).

## 6. Two-device test plan

Device A: test account A. Device B: test account B. Both run the staging
APK (`com.sirfhum.app.staging`, "Sirf Hum Staging" launcher name). Use
test-only email addresses; never write credentials, emails, device serials
or message content into a report.

| # | Step | Expected |
| --- | --- | --- |
| 1 | Account creation (A, B) | A: Continue with Google → picker → signed in, lands on pairing (never Home). B: Continue with Email → link arrives; opening it signs in. A new UID per account |
| 1b | Same address, other provider | B (email link) taps Continue with Google with the same address: same UID, or "already signs in with an email link" and no new account; never a second UID |
| 2 | Sign in again after sign-out | Same UID; no data from another account visible |
| 3 | Device registration | Device record created server-side; first device is `pending` until activation |
| 4 | First-device activation | Device becomes `active`; person identity key created on device |
| 5 | Pairing invitation (A) | Invitation created; code shown on A only |
| 6 | Pairing code comparison | B must type the code (forced comparison, D-131); a wrong code fails |
| 7 | Pairing confirmation | Both consent; no couple before both confirm |
| 8 | Couple creation | One couple record with A and B; each sees the other's display name only |
| 9 | Partner verification | Partner shows **unverified** until verified (no silent TOFU, D-128) |
| 10 | Safety number | Same number on both phones; tapping "matches" verifies |
| 11 | QR verification | Scanning the partner's QR verifies; a stale/other QR does not |
| 12 | Encrypted conversation | MLS group established; server holds only envelopes |
| 13–14 | Send / receive | Message arrives and decrypts; push says only "You have a new message" |
| 15–16 | Offline queue, reconnect | Airplane mode on A: message queued; reconnect: delivered once, in order |
| 17 | Moments | A memory appears in both timelines |
| 18–19 | Encrypted photo upload / receive | Upload succeeds; B decrypts and shows it; Storage object is ciphertext |
| 20–21 | Future, Us | Plans and notebook entries sync both ways |
| 22–23 | Sign out, sign back in | Sign-out clears account state; signing back in on the same phone restores |
| 24 | Device trust | A second phone for A is `pending` until approved by A's trusted device or the recovery key |
| 25–26 | Revocation, revoked-device rejection | Revoked phone cannot send, commit, approve or read new content; it is told it was removed |
| 27 | Recovery | Recovery key activates a replacement device; history on the lost phone is not recovered |
| 28 | Identity reset | 7-day delay; every trusted device alerted ("Review a security change") and can cancel; completed reset = new unverified identity for the partner |
| 29 | Unpairing | Either partner unpairs from an active device; conversations close for both |
| 30 | Partner isolation | After unpairing, neither can read new content of the other; re-pairing needs fresh consent |

**Defect record** (one per failure): ID · expected · actual · device
model and Android version (no serials) · build SHA-256 · environment
`staging` · safe reproduction steps · private data exposed? (yes/no, what
class, never the content) · error category (from `AppLogger` events, which
carry categories, not content) · severity (SECURITY / BUG / UX /
PERFORMANCE / POLISH / FUTURE FEATURE). Security severity follows
PRODUCTION-BLOCKERS P0–P3; subjective preferences are never SECURITY.

## 7. Security checks to repeat on the live staging backend

Each has automated evidence today (emulators, unit tests); the live run
confirms the deployed configuration matches. Mapping and current status:
[audit/STAGING-BETA §5](security/audit/STAGING-BETA.md#5-security-tests-a-p).

## 8. Cost watch during the beta

Daily while the beta runs, in the staging project only: Firestore
reads/writes (Usage tab), Storage bytes and operations, Functions
invocations and errors, Eventarc and Scheduler executions, and Logs
Explorer volume. Look for loops (a trigger writing what it listens to;
push fan-out per message is bounded by the couple's devices) and retry
storms (client retries on refused callables). Never paste log payloads
into reports; Functions log only event names and outcome categories.
