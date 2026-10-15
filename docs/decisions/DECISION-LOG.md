# Decision Log

Append-only. To change a decision, add a new entry that supersedes it and
mark the old one `Superseded by D-xxx`.

Statuses: **Accepted** · **Proposed** (needs owner confirmation) ·
**Open** (needs a decision before a named milestone) · **Superseded**.

| ID | Decision | Status | Date |
| --- | --- | --- | --- |
| D-001 | Product name: Sirf Hum | Accepted | 2026-10-15 |
| D-002 | Flutter + Dart as the frontend framework | Accepted | 2026-10-15 |
| D-003 | Targets: Android, iOS, Web from one codebase | Accepted | 2026-10-15 |
| D-004 | Firebase as the backend foundation | Accepted | 2026-10-15 |
| D-005 | Cloud Firestore as the primary database (not a plaintext private-content store) | Accepted | 2026-10-15 |
| D-006 | Cloud Storage for media (ciphertext only) | Accepted | 2026-10-15 |
| D-007 | Firebase Authentication for account identity | Accepted | 2026-10-15 |
| D-008 | Cloud Functions for backend logic; no microservices | Accepted | 2026-10-15 |
| D-009 | FCM for notifications, with privacy-safe payloads | Accepted | 2026-10-15 |
| D-010 | LiveKit for realtime media | Accepted | 2026-10-15 |
| D-011 | E2EE is a foundational requirement for private content | Accepted | 2026-10-15 |
| D-012 | Per-couple subscription is the primary monetization hypothesis | Accepted (hypothesis) | 2026-10-15 |
| D-013 | Our Money is a future area, not V1 | Accepted | 2026-10-15 |
| D-014 | No behavioural advertising | Accepted | 2026-10-15 |
| D-015 | Riverpod for state management | Accepted | 2026-10-15 |
| D-016 | Primary Firebase region `asia-south1` (Firestore, Functions, Storage) | Accepted (finalized Prompt 02) | 2026-10-15 |
| D-017 | go_router for navigation and deep links | Accepted | 2026-10-15 |
| D-018 | Three environments; build-time config via `--dart-define-from-file` | Accepted | 2026-10-15 |
| D-019 | Default-deny Security Rules, opened per phase with emulator tests | Accepted | 2026-10-15 |
| D-020 | Design tokens via ThemeExtension; provisional palette | Accepted (palette provisional) | 2026-10-15 |
| D-021 | GitHub + GitHub Actions for source control and CI | Accepted | 2026-10-15 |
| D-022 | Permanent app identity `com.sirfhum.app` (Android + iOS) | Accepted (finalized Prompt 02) | 2026-10-15 |
| D-023 | Environment flavors/schemes; non-production ID suffixes `.dev` / `.staging` | Accepted | 2026-10-15 |
| D-024 | Firebase projects `sirf-hum-dev` / `sirf-hum-staging` / `sirf-hum-prod`; no default CLI project | Accepted | 2026-10-15 |
| D-025 | Projects created under ahamshashvat@gmail.com on the Spark plan; billing deferred | Accepted — **review ownership** | 2026-10-15 |
| D-026 | Per-platform Firebase credentials via `--dart-define-from-file`, generated from live projects; no native Firebase config files | Accepted | 2026-10-15 |
| D-027 | Crashlytics without the Gradle plugin; errors reported as `RedactedError(type)` | Accepted | 2026-10-15 |
| D-028 | App Check: debug in development, attestation in staging/production; enforcement off until rollout | Accepted | 2026-10-15 |
| D-029 | No Auth sign-in provider enabled before the identity phase; phone auth not an architectural dependency | Accepted | 2026-10-15 |
| D-030 | Firebase Hosting serves the web app (target `app`); production domain `app.sirfhum.com` | Accepted | 2026-10-15 |
| D-031 | Secret scanning with the gitleaks CLI (not gitleaks-action) | Accepted | 2026-10-15 |
| D-032 | CI deploys via GitHub Environments + Workload Identity Federation; production requires reviewers and `main` | Accepted | 2026-10-15 |
| D-033 | Privacy-enforcing logging boundary (typed fields, redaction, error types only) | Accepted | 2026-10-15 |
| D-034 | iOS dependencies via CocoaPods with per-configuration xcconfigs (not Swift Package Manager) | Accepted | 2026-10-15 |
| D-035 | Functions linting: ESLint 9 flat config + typescript-eslint type-checked rules | Accepted | 2026-10-15 |
| D-036 | Delete protection on the production Firestore database | Accepted | 2026-10-15 |
| D-037 | Private GitHub repo `codex-warrior/sirf-hum`; `main` + `feature/`, `fix/`, `chore/`, `security/` branches | Accepted | 2026-10-15 |
| D-038 | Production deploy gates without required reviewers (GitHub free-plan limitation) | Accepted — **revisit on plan upgrade** | 2026-10-15 |
| D-039 | One Workload Identity deployer per project, bound to repo/owner IDs and GitHub Environment; least-privilege roles | Accepted | 2026-10-15 |
| D-040 | CI installs Flutter's pinned Android NDK explicitly | Accepted | 2026-10-15 |
| D-041 | LF line endings enforced by `.gitattributes` | Accepted | 2026-10-15 |

---

### D-001 — Product name: Sirf Hum
- **Decision:** The product is called Sirf Hum ("Just Us").
- **Reason:** Expresses the core positioning: a private space for two.
- **Alternatives considered:** None recorded (given by product owner).
- **Status:** Accepted · 2026-10-15

### D-002 — Flutter + Dart
- **Decision:** Flutter is the primary frontend framework.
- **Reason:** One codebase for Android, iOS and Web; strong rendering control for a premium custom design; mature Firebase and LiveKit SDKs.
- **Alternatives considered:** React Native (weaker web parity and design control); native Swift/Kotlin + separate web (three codebases, higher cost); Kotlin Multiplatform (less mature UI sharing for iOS/web).
- **Status:** Accepted · 2026-10-15

### D-003 — Android + iOS + Web
- **Decision:** Ship on Android, iOS and Web from one Flutter codebase; platform-specific code only where necessary (`lib/platform/`).
- **Reason:** Couples often use mixed platforms; web gives large-screen and convenience access.
- **Alternatives considered:** Mobile-only first (web later). Kept web in scope, with documented constraints (key storage, push).
- **Status:** Accepted · 2026-10-15

### D-004 — Firebase backend foundation
- **Decision:** Firebase is the backend platform.
- **Reason:** Managed auth, database, storage, functions, messaging and app integrity; fast iteration for a small team; scales.
- **Alternatives considered:** Supabase (Postgres, self-hostable; weaker mobile push/App Check integration); custom backend (higher ops cost, premature).
- **Status:** Accepted · 2026-10-15

### D-005 — Cloud Firestore primary database
- **Decision:** Firestore is the primary application database. It stores metadata and ciphertext; never plaintext private content.
- **Reason:** Realtime sync, offline support, Security Rules, tight Flutter integration.
- **Alternatives considered:** Realtime Database (weaker querying/rules model); Postgres via Supabase/Cloud SQL.
- **Status:** Accepted · 2026-10-15

### D-006 — Cloud Storage for media
- **Decision:** Encrypted media blobs live in Firebase Cloud Storage.
- **Reason:** Integrated with Auth and Security Rules; resumable uploads.
- **Alternatives considered:** Third-party object storage / CDN (revisit for cost at scale).
- **Status:** Accepted · 2026-10-15

### D-007 — Firebase Authentication
- **Decision:** Firebase Auth identifies each person's account.
- **Reason:** Managed, multi-provider, integrates with rules and functions.
- **Alternatives considered:** Custom auth (risky, unnecessary). Note: Auth identity ≠ device identity ≠ cryptographic identity.
- **Status:** Accepted · 2026-10-15. Sign-in methods: **Open** (identity phase).

### D-008 — Cloud Functions for server logic
- **Decision:** Server logic runs in Cloud Functions (TypeScript). No microservices.
- **Reason:** Sufficient for pairing, token minting, notifications and scheduled jobs; minimal ops.
- **Alternatives considered:** Cloud Run services (revisit if long-running workloads appear).
- **Status:** Accepted · 2026-10-15

### D-009 — FCM for notifications
- **Decision:** Firebase Cloud Messaging delivers notifications; payloads contain no private content.
- **Reason:** Cross-platform delivery (Android, iOS via APNs, Web Push).
- **Alternatives considered:** OneSignal and similar (extra third party with data access).
- **Status:** Accepted · 2026-10-15

### D-010 — LiveKit for realtime media
- **Decision:** LiveKit powers voice/video calls and future realtime Together experiences. No custom WebRTC infrastructure unless a later review requires it.
- **Reason:** Mature SFU and Flutter SDK; supports frame-level E2EE; cloud or self-hosted.
- **Alternatives considered:** Custom WebRTC (high complexity), Agora/Twilio (more closed, cost). LiveKit Cloud vs. self-hosted: **Open** (calls phase).
- **Status:** Accepted · 2026-10-15

### D-011 — E2EE as a foundational requirement
- **Decision:** Private content is architected toward genuine end-to-end encryption using established protocols and libraries. No custom cryptography. No E2EE claims before implementation and review.
- **Reason:** Privacy is the core promise; the operator must not be a plaintext repository.
- **Alternatives considered:** Server-side encryption at rest only (operator can read content — rejected for private content).
- **Status:** Accepted · 2026-10-15. Protocol and library: **Open** (dedicated E2EE phase).

### D-012 — Subscription monetization
- **Decision:** Primary business model hypothesis is a per-couple subscription (Sirf Hum Plus) on top of a useful free tier. Pricing not locked.
- **Reason:** Aligns revenue with user value without monetising private data.
- **Alternatives considered:** Advertising (rejected, D-014); per-person subscriptions (rejected: one subscription covers both partners).
- **Status:** Accepted (hypothesis) · 2026-10-15

### D-013 — Our Money is future, not V1
- **Decision:** No financial features in V1. Any future financial product requires legal, compliance, security and regulatory architecture and regulated partners.
- **Reason:** Regulatory risk and focus.
- **Alternatives considered:** None.
- **Status:** Accepted · 2026-10-15

### D-014 — No behavioural advertising
- **Decision:** Sirf Hum is not designed around behavioural advertising.
- **Reason:** Incompatible with the privacy promise.
- **Alternatives considered:** Ad-supported free tier (rejected).
- **Status:** Accepted · 2026-10-15

### D-015 — Riverpod for state management
- **Decision:** `flutter_riverpod` (v3), without code generation initially.
- **Reason:** Compile-safe dependency injection and overrides (great for tests and environment config), no BuildContext coupling, widely used.
- **Alternatives considered:** Bloc (more boilerplate), Provider (superseded by Riverpod), plain InheritedWidget (insufficient at scale).
- **Status:** Accepted · 2026-10-15

### D-016 — Primary region `asia-south1`
- **Decision:** `asia-south1` (Mumbai) for Firestore (all three projects, created in Prompt 02), Cloud Functions (`functions/src/config/environment.ts`), and the Cloud Storage default bucket when provisioned.
- **Reason:** Sirf Hum launches in India; Indian users are the first market; regional latency matters. Firestore and default-bucket locations cannot be changed after creation.
- **Alternatives considered:** `us-central1` (Firebase default; higher latency for India).
- **Notes:** Auth, FCM, App Check, Crashlytics and Hosting are global services. This is a data-residency architecture decision, not a legal certification.
- **Status:** Accepted (finalized by product owner, Prompt 02) · 2026-10-15

### D-017 — go_router
- **Decision:** `go_router` for navigation; `StatefulShellRoute` for the five areas.
- **Reason:** URL-based routing for web and notification deep links; maintained by the Flutter team.
- **Alternatives considered:** Navigator 2.0 directly (verbose), auto_route (code generation).
- **Status:** Accepted · 2026-10-15

### D-018 — Environments and configuration
- **Decision:** `development`, `staging`, `production` with separate Firebase projects. Client config via `--dart-define-from-file=config/env/<env>.json` (git-ignored). Bare builds default to development with Firebase unconfigured.
- **Reason:** Prevents dev builds from touching production; keeps credentials out of git.
- **Alternatives considered:** Committed `firebase_options.dart` per flavor (FlutterFire default; mixes environments in source).
- **Status:** Accepted · 2026-10-15. Native flavors/schemes added in Prompt 02 (D-023).

### D-019 — Default-deny Security Rules
- **Decision:** Firestore and Storage rules deny all access by default; each phase opens specific paths with emulator tests for allowed and denied cases.
- **Reason:** Secure by default; prevents accidental exposure.
- **Alternatives considered:** Firebase "test mode" rules (rejected — open to the world).
- **Status:** Accepted · 2026-10-15

### D-020 — Design-token architecture
- **Decision:** Tokens in `lib/design_system/tokens`; semantic colors as a `ThemeExtension`; primitives not exported to features. Palette and typeface are provisional.
- **Reason:** Visual identity can evolve without touching feature code; accessibility enforced centrally.
- **Alternatives considered:** Raw Material ColorScheme only (insufficient semantic roles).
- **Status:** Accepted (values provisional) · 2026-10-15

### D-021 — GitHub + GitHub Actions
- **Decision:** Source on GitHub; CI on GitHub Actions (`.github/workflows/ci.yml`).
- **Reason:** Specified by product owner; macOS runners available for iOS builds.
- **Alternatives considered:** Codemagic (Flutter-specialised; may be added for store releases).
- **Status:** Accepted · 2026-10-15

### D-022 — Permanent app identity `com.sirfhum.app`
- **Decision:** Android application ID, Android namespace and iOS bundle ID are `com.sirfhum.app` for production, replacing the generated `com.sirfhum.sirf_hum` / `com.sirfhum.sirfHum`.
- **Reason:** One consistent, domain-based identity on both platforms; permanent after first store release.
- **Alternatives considered:** Separate IDs per platform (rejected; no technical need).
- **Status:** Accepted (finalized by product owner, Prompt 02) · 2026-10-15

### D-023 — Environment flavors and ID suffixes
- **Decision:** Android product flavors and iOS schemes `development`/`staging`/`production` (iOS schemes `Development`/`Staging`/`Production`, configurations `Debug-Development` etc.). Non-production IDs `com.sirfhum.app.dev` and `com.sirfhum.app.staging`. Flavor must match `SH_ENV` (runtime guard).
- **Reason:** All environments installable side by side; a test build can't be mistaken for production; each environment maps to its own Firebase app.
- **Alternatives considered:** One ID with config-only switching (can't co-install; easy to ship the wrong config).
- **Status:** Accepted · 2026-10-15

### D-024 — Firebase projects and CLI safety
- **Decision:** Projects `sirf-hum-dev`, `sirf-hum-staging`, `sirf-hum-prod`. `.firebaserc` defines aliases `development`/`staging`/`production` and **no `default`**, so `firebase deploy` without a project fails. Deploys use `tool/deploy.sh` or the Deploy workflow.
- **Reason:** The target is explicit every time.
- **Alternatives considered:** A `default` alias pointing at development (one `firebase use` away from an accidental production deploy).
- **Status:** Accepted · 2026-10-15

### D-025 — Project ownership and billing
- **Decision:** Created in Prompt 02 with the Firebase CLI account `ahamshashvat@gmail.com`, on the Spark (free) plan with no billing linked, per product-owner instruction.
- **Consequences:** Cloud Storage default buckets and Cloud Functions are blocked until upgraded to Blaze. Ownership should move to an organization/shared account with at least two owners before launch.
- **Status:** Accepted — **review ownership and billing** before staging use · 2026-10-15. Reviewed in Prompt 03: nothing transferred; recommended structure and migration steps in [ACCOUNT-OWNERSHIP.md](../architecture/ACCOUNT-OWNERSHIP.md). Billing still not enabled.

### D-026 — Client Firebase configuration
- **Decision:** Each platform's Firebase app ID and API key are passed via `--dart-define-from-file` (`SH_FIREBASE_{ANDROID,IOS,WEB}_{APP_ID,API_KEY}`), generated by `tool/generate_env_config.mjs` from the live project. `google-services.json` / `GoogleService-Info.plist` are not used.
- **Reason:** One config mechanism for every platform; environment chosen in one place; nothing environment-specific committed.
- **Alternatives considered:** FlutterFire CLI per-flavor `firebase_options.dart` + native files (duplicated per platform, committed by default).
- **Status:** Accepted · 2026-10-15

### D-027 — Crashlytics integration
- **Decision:** `firebase_crashlytics` on Android/iOS without the Crashlytics Gradle plugin (`com.crashlytics.RequireBuildId=false`). Native collection disabled by default, enabled per environment at startup. Errors sent as `RedactedError(<type>)` plus stack; messages never leave the device.
- **Reason:** Keeps D-026's single config path; privacy over diagnostic convenience.
- **Trade-off:** No deobfuscation/symbolication of native frames until mapping/dSYM upload is added (needed before launch).
- **Status:** Accepted · 2026-10-15

### D-028 — App Check strategy
- **Decision:** Debug providers in development; Play Integrity, App Attest (DeviceCheck fallback) and reCAPTCHA Enterprise in staging/production. Production can never use debug (runtime guard). Enforcement off until the staged rollout in `docs/architecture/ENVIRONMENTS.md`.
- **Reason:** Protect Firebase from non-genuine clients without breaking local development.
- **Status:** Accepted · 2026-10-15

### D-029 — Authentication foundation
- **Decision:** Identity Toolkit API enabled; no sign-in provider enabled before the identity phase. Intended baseline: email link or email/password; phone auth only if later required; social providers only if justified.
- **Reason:** An enabled provider lets anyone with the public API key create accounts. Phone auth adds cost, fraud risk and personal data.
- **Status:** Accepted · 2026-10-15

### D-030 — Web hosting
- **Decision:** Firebase Hosting, target `app`, on each project's default site. Production domain `app.sirfhum.com` (to be attached). The marketing site `sirfhum.com` is separate and out of scope.
- **Status:** Accepted · 2026-10-15

### D-031 — Secret scanning
- **Decision:** gitleaks CLI v8.30.1 (MIT), checksum-verified, scanning the full history in CI.
- **Reason:** `gitleaks-action` needs a paid license for organization repos; the CLI gives the same detection for free.
- **Alternatives considered:** TruffleHog (AGPL). GitHub secret scanning should also be enabled in repository settings.
- **Status:** Accepted · 2026-10-15

### D-032 — CI deployment model
- **Decision:** Manual `workflow_dispatch` deploys bound to GitHub Environments with per-environment secrets; Google auth via Workload Identity Federation (no JSON keys); production requires reviewers and `main`. CI validation uses no secrets.
- **Status:** Accepted · 2026-10-15

### D-033 — Logging boundary
- **Decision:** `AppLogger` with debug/info/warning/error, snake_case events, typed field values (raw strings redacted), error types only, pluggable sinks.
- **Reason:** Privacy enforced by construction, not by reviewer vigilance.
- **Status:** Accepted · 2026-10-15

### D-034 — iOS dependency manager
- **Decision:** CocoaPods with a committed `ios/Podfile` mapping all nine configurations and per-configuration xcconfigs that include the matching Pods xcconfig.
- **Reason:** Swift Package Manager is opt-in on Flutter 3.41 stable.
- **Status:** Accepted · 2026-10-15. Revisit when SPM becomes the default.

### D-035 — Functions linting
- **Decision:** ESLint 9 flat config + `typescript-eslint` `recommendedTypeChecked`, plus defect-oriented rules (floating/misused promises, exhaustive switches, unused code, `eqeqeq`, no `console`). No stylistic rules.
- **Status:** Accepted · 2026-10-15

### D-036 — Production database delete protection
- **Decision:** Firestore delete protection enabled on `sirf-hum-prod`.
- **Status:** Accepted · 2026-10-15

### D-037 — GitHub repository and branch strategy
- **Decision:** Source lives in the private repository `codex-warrior/sirf-hum` (created in Prompt 03 under the developer's personal GitHub account, free plan). `main` is the production branch; work happens on `feature/*`, `fix/*`, `chore/*` and `security/*` branches merged by pull request after CI passes. Merge commits are disabled (squash/rebase only); merged branches are deleted automatically.
- **Reason:** Simple trunk-based flow; `main` stays releasable.
- **Alternatives considered:** GitFlow (unnecessary ceremony for this team size).
- **Status:** Accepted · 2026-10-15. Ownership follows [ACCOUNT-OWNERSHIP.md](../architecture/ACCOUNT-OWNERSHIP.md).

### D-038 — Production deploy gates on the free GitHub plan
- **Decision:** GitHub refuses required reviewers on environments and branch protection/rulesets for this private repository on the free plan. Production is protected instead by:
  - the `production` environment's deployment branch policy (`main` only);
  - a typed `confirm=sirf-hum-prod` workflow input;
  - Workload Identity conditions (repository + `production` environment + `refs/heads/main`);
  - the checks in `tool/deploy.sh`.
- **Gap:** No second person has to approve a production deploy, and `main` can technically be pushed to directly.
- **Revisit:** On upgrade to GitHub Pro/Team, add required reviewers on `production` and branch protection on `main` (PR required, CI checks required, no force-push, no deletion).
- **Status:** Accepted — revisit on plan upgrade · 2026-10-15

### D-039 — Deploy identities
- **Decision:** Each Firebase project has its own `github-deployer` service account, impersonable only through that project's Workload Identity pool. The condition matches the repository and owner by numeric ID plus the GitHub Environment, and production additionally requires `refs/heads/main`. Roles: `firebaserules.admin`, `datastore.indexAdmin`, `firebasehosting.admin`, `serviceusage.serviceUsageConsumer`, `serviceusage.serviceUsageViewer`. No Owner/Editor, no keys. Functions roles are deferred to the Functions phase.
- **Reason:** Least privilege; development/staging identities have no access to production.
- **Status:** Accepted · 2026-10-15. Reproduce with `tool/setup_github_wif.sh <env>`.

### D-040 — Pinned Android NDK in CI
- **Decision:** The Android CI job installs NDK `28.2.13676358` (pinned by Flutter 3.41.5) with `sdkmanager`, with retries, before building.
- **Reason:** The first CI run failed when Gradle auto-installed the NDK during configuration and got a corrupt archive. Explicit installation is deterministic and observable.
- **Status:** Accepted · 2026-10-15. Update together with `FLUTTER_VERSION`.

### D-041 — Line endings
- **Decision:** `.gitattributes` sets `* text=auto eol=lf` (binaries excluded).
- **Reason:** Windows checkouts with `core.autocrlf=true` produced CRLF files, which break `tool/*.sh` and diverge from `dart format`.
- **Status:** Accepted · 2026-10-15
