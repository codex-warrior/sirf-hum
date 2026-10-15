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
| Deploys | Local script or workflow | Workflow (or clean local tree) | Workflow, reviewer-approved, `main` only |

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
   - production requires `main`, a typed confirmation of the project ID,
     and, in CI, approval through the protected `production` GitHub
     Environment.

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

**Current status:**
- App Check is wired in the client and its API is enabled in all three
  projects.
- **Enforcement is OFF for every service.**
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
- `storage` deploy targets fail until a bucket exists.

## CI secrets

CI validation (`ci.yml`) uses **no secrets**. Deploys (`deploy.yml`) use
GitHub **Environments** named `development`, `staging`, `production`, each
with its own secrets:

| Secret (per environment) | Purpose |
| --- | --- |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Workload Identity Federation provider resource name for that project |
| `GCP_DEPLOY_SERVICE_ACCOUNT` | Deploy service account email in that project (least privilege: Firebase Rules Admin, Cloud Functions Developer, Firebase Hosting Admin, Service Account User) |
| `SH_ENV_CONFIG_JSON` | Contents of `config/env/<env>.json` (client identifiers) for hosting builds |

Rules:
- Use **Workload Identity Federation**, never service-account JSON keys.
- Never put credentials in workflow YAML.
- The `production` environment has required reviewers and is restricted to
  the `main` branch.
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
