# Environments

Status: **Established — Prompt 02 (2026-10-15).**

Sirf Hum has exactly three isolated environments. Nothing is shared between
them: separate Firebase projects, separate app identities, separate
credentials.

## Environment map

| | Development | Staging | Production |
| --- | --- | --- | --- |
| Purpose | Local work, emulators, experiments | Pre-release QA, internal testers | Real users |
| Firebase project ID | `sirf-hum-dev` | `sirf-hum-staging` | `sirf-hum-prod` |
| Firebase display name | Sirf Hum Development | Sirf Hum Staging | Sirf Hum Production |
| `.firebaserc` alias | `development` | `staging` | `production` |
| Primary region | `asia-south1` | `asia-south1` | `asia-south1` |
| Android application ID | `com.sirfhum.app.dev` | `com.sirfhum.app.staging` | **`com.sirfhum.app`** |
| iOS bundle ID | `com.sirfhum.app.dev` | `com.sirfhum.app.staging` | **`com.sirfhum.app`** |
| Flutter flavor (Android) | `development` | `staging` | `production` |
| iOS scheme / configs | `Development` / `*-Development` | `Staging` / `*-Staging` | `Production` / `*-Production` |
| Launcher name | Sirf Hum Dev | Sirf Hum Staging | Sirf Hum |
| Web (Hosting target `app`) | `sirf-hum-dev.web.app` | `sirf-hum-staging.web.app` | `sirf-hum-prod.web.app` → **`app.sirfhum.com`** (custom domain not yet attached) |
| Client config | `config/env/development.json` | `config/env/staging.json` | `config/env/production.json` |
| App Check provider | Debug | Attestation | Attestation |
| Crash reporting | Off (opt-in) | On | On |
| Deploys | Local script or workflow | Workflow (or clean local tree) | Workflow only, `main` only, typed confirmation |

Non-production IDs carry a suffix so all three apps can be installed side by
side on one device. The production identity is the unsuffixed
`com.sirfhum.app` (D-022). The marketing site `sirfhum.com` is separate and
not part of this repository yet; the app is served from `app.sirfhum.com`.

## How isolation is enforced

Defence in depth: each layer independently prevents cross-environment use.

1. **Separate projects and credentials.** Dev credentials cannot touch prod
   resources.
2. **No default Firebase project.** `.firebaserc` has aliases but no
   `default`, so `firebase deploy` without `--project` fails ("No project
   active"). Verified. Never run `firebase use production`; it would make
   production the directory's active project. Use `tool/deploy.sh`.
3. **Build-time pairing.** Mobile builds need both `--flavor <env>` (native
   identity) and `--dart-define-from-file=config/env/<env>.json` (Firebase
   config). Without a config file a build is `development` with Firebase
   "not configured", so a bare build reaches no backend at all.
4. **Runtime guard** (`lib/app/environment_guard.dart`). Startup aborts if:
   - the native flavor ≠ `SH_ENV`;
   - the Firebase project ≠ the environment's project
     (`AppEnvironment.firebaseProjectId`). A development build pointed at
     `sirf-hum-prod` refuses to run;
   - production uses the App Check debug provider;
   - production lacks Firebase configuration.
5. **Server-side guard** (`functions/src/config/environment.ts`). Each
   Functions instance verifies at cold start that `SH_ENV` (from
   `functions/.env.<alias>`) matches the project it runs in.
6. **Deploy gates** (`tool/deploy.sh`, `.github/workflows/deploy.yml`):
   - explicit environment argument;
   - Security Rules tests before every deploy;
   - staging and production require a clean tree;
   - production requires `main` and a typed confirmation of the project ID.
     In CI, the `production` GitHub Environment accepts only `main`, and
     Workload Identity Federation only mints production credentials for this
     repository + `production` environment + `main`. See "Production deploy
     gates" below; required reviewers are not available on the current
     GitHub plan.

## Region and data residency

- **Initial primary Firebase region: `asia-south1` (Mumbai)** for Firestore,
  Cloud Functions, and (once provisioned) the Cloud Storage default bucket.
- Why: India is the launch market; latency for Indian users; data stays in
  an Indian region where the service supports regional placement.
- **Consequential and largely irreversible:** a Firestore database's location
  cannot be changed after creation, and the default Storage bucket's location
  is fixed when it is created. Moving later means migrating data into new
  resources.
- **Global services:** Authentication, Cloud Messaging, App Check, Crashlytics
  and Hosting (CDN) are global services; Firebase does not offer per-region
  placement for them. Some metadata they process is handled outside India.
- This is an **architectural data-residency decision, not a legal
  compliance certification.** No legal review (e.g. DPDP Act 2023) has been
  performed.

## App Check

**What it is:** App Check attaches an attestation token proving a request
comes from a genuine Sirf Hum build, so Firebase can reject requests from
scripts, modified apps and other unauthorized clients.

**What it is not:** App Check does **not** provide end-to-end encryption,
message encryption, media encryption or key management. Likewise Firebase
Security Rules do not provide E2EE. The layers stay separate:

| Layer | Answers | Does not answer |
| --- | --- | --- |
| App Check | Is this a genuine Sirf Hum app? | Who is the user? Can anyone read the content? |
| Firebase Auth | Which person is this? | What may they access? |
| Security Rules / Functions | May this person access this resource? | Can the operator read the content? |
| E2EE (future) | Can only the couple's devices read this? | — |

**Per environment** (code: `lib/infrastructure/firebase/app_check_*.dart`):

| | Android | iOS | Web |
| --- | --- | --- | --- |
| Development | Debug provider | Debug provider | Debug provider |
| Staging | Play Integrity | App Attest → DeviceCheck fallback | reCAPTCHA Enterprise (site key required) |
| Production | Play Integrity | App Attest → DeviceCheck fallback | reCAPTCHA Enterprise (site key required) |

- `SH_APPCHECK_PROVIDER=debug|attestation` overrides the default, e.g. to
  test a staging build on an emulator. **Production can never use `debug`**
  (runtime guard).
- **Debug tokens** are generated by the Firebase SDK on each developer
  machine/emulator and printed to the device log. Register them in the
  Firebase console (App Check → Apps → Manage debug tokens) of the
  **development** project only. They are never committed, never placed in
  config files, and are revoked when a machine is retired.
- Web attestation needs a reCAPTCHA Enterprise **site key** (public) in
  `SH_APPCHECK_WEB_RECAPTCHA_SITE_KEY`. Without it, App Check is skipped on
  web with a warning.

**Production procedure:** [APP-CHECK-PRODUCTION](APP-CHECK-PRODUCTION.md)
(Prompt 18, D-139; supersedes the step list in 17B §4). Since Prompt 18 a
production **web** build without a reCAPTCHA site key refuses to start.

**Current status:**
- App Check is wired in the client and its API is enabled in all three
  projects.
- **Enforcement is OFF for Firestore and Storage** (console settings).
  **Callables enforce it in code** (`enforceAppCheck: true` on every
  callable), so the first Functions deploy rejects every client until
  attestation and debug tokens exist (Prompt 17 correction, P17-10;
  blocker P1-8).
- **Not yet done:**
  - Play Integrity linking needs the app on Google Play.
  - App Attest needs the Apple team ID.
  - reCAPTCHA Enterprise keys have not been created.
  - Debug tokens have not been registered.

**Rollout plan:**
1. Development: register debug tokens; monitor App Check metrics.
2. Staging: configure attestation providers; monitor verified vs.
   unverified traffic for at least one release cycle.
3. Enforce per service in staging (Firestore → Storage → Functions via
   `enforceAppCheck: true`).
4. Production: same sequence, only after metrics show ~100% verified traffic
   from current app versions. Old app versions without App Check will be
   rejected once enforcement is on, so a minimum supported version must
   exist first.

## Crash reporting (Crashlytics)

- Android and iOS only (Crashlytics does not support web).
- Collection is **disabled by default natively**
  (`firebase_crashlytics_collection_enabled=false` in the Android manifest,
  `FirebaseCrashlyticsCollectionEnabled=false` in Info.plist). The app enables
  it at startup per environment: off in development, on in staging and
  production (`SH_CRASH_REPORTING` overrides).
- Privacy:
  - Crashlytics receives only records produced by `AppLogger`. Their
    fields are type-checked and sanitized, and errors are reduced to
    `RedactedError(<type>)` plus the stack trace. Exception **messages
    never leave the device** because they can quote user content.
  - No custom keys, user IDs or content are attached.
- Trade-off (D-027): we don't use the Crashlytics Gradle plugin or
  `google-services.json`; Firebase is configured from Dart. Android sets
  `com.crashlytics.RequireBuildId=false`. As a result:
  - Dart errors are fully reported;
  - native (Java/Kotlin/Swift) frames are not deobfuscated or symbolicated
    until mapping/dSYM upload is added.
- Crashlytics itself is created in each project on first report or console
  visit.

## Logging

`lib/core/logging/` is the only logging boundary:

- **Levels:** debug, info, warning, error.
- **Events** are `snake_case` constants, never interpolated text.
- **Field values** are restricted to numbers, booleans, enums, durations,
  `SafeLogString` (an explicit, reviewable "this string is not user data")
  and `RedactedId` (shortened identifiers). Anything else, **including raw
  strings**, is replaced with `<redacted:Type>`.
- **Errors** keep their type and stack, never their message.
- **Sinks:** developer console always; Crashlytics when enabled. A failing
  sink never breaks the app.

## Authentication foundation (no UI)

**Prompt 18:** production provider proposed: email link, passwordless
(D-138, [AUTH-PRODUCTION-DECISION](AUTH-PRODUCTION-DECISION.md)); needs
owner approval; nothing enabled.


- The Identity Toolkit API is enabled in all projects.
- **No sign-in provider is enabled yet.** An enabled provider lets anyone
  with the public API key create accounts, which has no value before the
  identity phase.
- Intended providers, decided in the identity phase:
  - **Email link or email/password** as the baseline.
  - **Phone authentication only if later required.** The architecture does
    not depend on phone numbers: they cost money per SMS, attract fraud,
    and reveal more personal data.
  - **Social providers** only if justified; Sign in with Apple becomes
    mandatory on iOS if any other social login is offered.

## Cloud Storage and Cloud Functions: blocked on billing

The projects are on the free **Spark plan** (billing deliberately not linked
in Prompt 02):

- **Cloud Storage:** new default buckets require the Blaze plan. Not
  provisioned. When created, choose `asia-south1`.
- **Cloud Functions:** require Blaze (Cloud Build, Artifact Registry). The
  code skeleton and region are ready; nothing is deployed.
- The `storage` deploy target fails until a bucket exists, so it is a
  separate workflow option and not part of `rules`.
- These stay **intentionally unavailable** until the phase that needs them,
  when billing is deliberately enabled. Prompt 03 did not enable billing.
- **Prompt 19 (2026-10-21, verified):** billing is linked to
  `sirf-hum-dev` only; staging and production are still on Spark, so
  staging has no bucket and no Functions. Staging Firestore rules and
  indexes are released. Status and owner actions:
  [STAGING-BETA](../STAGING-BETA.md).

## GitHub repository and CI (Prompt 03)

- Repository: private `codex-warrior/sirf-hum` (personal account, free
  plan), default branch `main`.
- `ci.yml` runs on every push to `main` and every pull request, with no
  secrets. Jobs:
  - Flutter: format, analyze, test, three web builds;
  - Android: development/staging debug and production release, with
    application IDs verified;
  - iOS on macOS: all three schemes, each bundle ID checked,
    RunnerTests build;
  - Functions: typecheck, lint, build, test;
  - Security Rules emulator tests;
  - gitleaks full-history scan.
- Android CI runs one job per flavor (matrix). The second run showed that
  three Gradle builds in one job exhaust the runner's disk. Each job
  installs the NDK Flutter pins (`28.2.13676358`) explicitly; the first run
  failed when Gradle auto-installed it and the download was corrupt.

## Deploy identities (Workload Identity Federation)

Set up by `tool/setup_github_wif.sh <env>` in each project (Prompt 03). No
service-account keys exist.

| Environment | Service account | Who can impersonate it |
| --- | --- | --- |
| development | `github-deployer@sirf-hum-dev.iam.gserviceaccount.com` | GitHub OIDC tokens from repo ID 1420599703, owner ID 148367546, `environment == development` |
| staging | `github-deployer@sirf-hum-staging.iam.gserviceaccount.com` | same repo/owner, `environment == staging` |
| production | `github-deployer@sirf-hum-prod.iam.gserviceaccount.com` | same repo/owner, `environment == production` **and** `ref == refs/heads/main` |

Each service account lives in its own project and has roles only there, so
development and staging identities cannot touch production.

Project roles granted to each deployer (no Owner/Editor anywhere):

| Role | Why |
| --- | --- |
| `roles/firebaserules.admin` | Release Firestore and Storage rules |
| `roles/datastore.indexAdmin` | Deploy Firestore indexes |
| `roles/firebasehosting.admin` | Release the web app to Hosting |
| `roles/serviceusage.serviceUsageConsumer`, `roles/serviceusage.serviceUsageViewer` | Firebase CLI checks that APIs are enabled |

Functions deploy roles (`roles/cloudfunctions.developer`,
`roles/iam.serviceAccountUser` on the runtime service account, Artifact
Registry/Cloud Build access) are **not** granted until the Functions phase.
Production's extra restriction is the `main` condition plus the deploy gates
below; its roles match the other environments because there is no narrower
role that still deploys rules and hosting.

Conditions bind to the repository's **numeric** IDs, so a different
repository later created with the same name cannot obtain credentials. If the
repository moves to an organization, re-run the script with the new IDs (see
[ACCOUNT-OWNERSHIP.md](ACCOUNT-OWNERSHIP.md)).

## GitHub Environments

| Environment | Variables | Protection |
| --- | --- | --- |
| `development` | `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_DEPLOY_SERVICE_ACCOUNT` | none |
| `staging` | same | none |
| `production` | same | deployment branch policy: `main` only |

- The provider and service-account values are identifiers, not secrets, so
  they are environment **variables**.
- `SH_ENV_CONFIG_JSON` (an environment **secret**: the contents of
  `config/env/<env>.json`) is only needed for `hosting` deploys and is
  **not yet set** in any environment.
- **Not available on the current plan:** required reviewers on environments,
  and branch protection/rulesets on `main`. The GitHub API answers
  "Upgrade to GitHub Pro or make this repository public".

### Production deploy gates

All of these must hold for a production deploy:

1. The Deploy workflow is started manually. Only users with write access can
   do this.
2. The run is on `main`: the environment's branch policy enforces this, and
   the job re-checks it.
3. The `confirm` input equals `sirf-hum-prod`.
4. Google issues credentials only for repo + `production` environment +
   `refs/heads/main`.
5. `tool/deploy.sh` re-checks for a clean tree, `main` and the confirmation,
   and runs the rules tests first.
6. **Prompt 18 (D-137):** `tool/deploy.sh` refuses production outside
   GitHub Actions (no laptop deploys), and refuses every production
   target except Firestore rules/indexes and Storage rules unless
   `config/launch_gate.json` says `"productionTraffic": "open"`. That file
   is committed `closed`; opening it is a reviewed PR after every P0 and P1
   gate in [PRODUCTION-LAUNCH-GATE](../security/audit/PRODUCTION-LAUNCH-GATE.md)
   passes. Tested by `tool/test_deploy_guard.sh` in CI.

**Verified read-only on 2026-10-21 (Prompt 18):** billing off in all three
projects; production has no Storage bucket, no Functions, no Security
Rules release and no initialized Firebase Authentication; production
Firestore is `asia-south1` with delete protection on and PITR off; no
user-managed service-account keys anywhere; the production WIF condition
is exactly as documented above. Details and owner actions:
[PROMPT-18-BASELINE](../security/audit/PROMPT-18-BASELINE.md),
[PRODUCTION-LAUNCH-GATE](../security/audit/PRODUCTION-LAUNCH-GATE.md) (P1-INF).

When the account moves to a plan that supports them, add required reviewers
on `production` and branch protection on `main` (D-038).

**Prompt 17 (P17-13):** the repository is currently **public**, and public
repositories get rulesets/branch protection, secret scanning, push
protection and Dependabot alerts on the free plan. **Enabled in Prompt 17B
(owner-authorized, D-133):** secret scanning, push protection, Dependabot
alerts, and ruleset "main: PR + CI required" (pull request required, the
ten CI checks required, no force pushes, no deletion, no bypass actors).
Visibility: make the repository private before the first production
release (PROMPT-17B-REMEDIATION §5); privacy is not a security boundary.

Rules:
- Use **Workload Identity Federation**, never service-account JSON keys.
- Never put credentials in workflow YAML.
- Pin every action to a full commit SHA (tag as a comment) and every tool a
  workflow installs to an exact version; pass workflow inputs to shell steps
  only through `env:` (D-124).
- Production secrets exist only in the `production` environment.
- Future secrets (Android upload keystore, App Store Connect API key, LiveKit
  API secret for Functions) follow the same per-environment pattern;
  Functions runtime secrets go in Secret Manager (`defineSecret`).

## Secret scanning

The gitleaks CLI (MIT, v8.30.1, checksum-verified) scans the **full git
history** on every push and PR (`ci.yml` → `secrets-scan`). We use the CLI
rather than `gitleaks-action` because the action requires a paid license for
organization-owned repositories. Locally:
`gitleaks git . --redact` (or `gitleaks dir <path>`) before pushing.
