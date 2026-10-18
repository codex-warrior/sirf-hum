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
| D-042 | E2EE protocol: MLS (RFC 9420), one couple group of devices | **Accepted** (owner direction, Prompt 05) | 2026-10-16 |
| D-043 | MLS library: OpenMLS leading, mls-rs alternative | **Superseded by D-054** | 2026-10-16 |
| D-044 | Couple group + per-person personal group | Proposed (RECOMMENDED) | 2026-10-16 |
| D-045 | Person Identity Key (PIK) + PIK-signed device certificates; roster acceptance policy | Proposed (RECOMMENDED) | 2026-10-16 |
| D-046 | Web v1 carries no end-to-end-encrypted private content | **Accepted** (owner direction, Prompt 05) | 2026-10-16 |
| D-047 | Recovery: device-to-device default, opt-in recovery key, no escrow | Proposed (RECOMMENDED) | 2026-10-16 |
| D-048 | Media: per-object keys, libsodium secretstream; key inside MLS message | Proposed; binding Open | 2026-10-16 |
| D-049 | Content-free notifications; previews off by default | Proposed (RECOMMENDED) | 2026-10-16 |
| D-050 | Post-quantum not a V1 launch blocker; crypto agility required | **Accepted** (owner, Prompt 05) | 2026-10-16 |
| D-051 | Rejected E2EE candidates: libsignal (AGPL, unsupported outside Signal, no web), Dart Signal port, Wire core-crypto (GPL), custom protocol | Accepted (rejection) | 2026-10-16 |
| D-052 | Experimental prototypes live in `prototypes/`, isolated, path-filtered CI | Accepted | 2026-10-16 |
| D-053 | gitleaks exceptions must be rule + path + exact match, with negative controls | Accepted | 2026-10-16 |
| D-054 | Cryptographic core: **OpenMLS 0.9.1** (dev); mls-rs 0.56.0 tested fallback | **Accepted for development — medium confidence; production conditional** | 2026-10-16 |
| D-055 | Handshake messages sent as PrivateMessage (encrypted commits/proposals) | Accepted | 2026-10-16 |
| D-056 | Process untrusted MLS input inside a checkpoint; roll back on rejection | Accepted | 2026-10-16 |
| D-057 | Crypto core validates every credential before merge (OpenMLS has no identity-provider hook) | Accepted | 2026-10-16 |
| D-058 | Transactional local storage provider (one atomic write per operation) | Accepted | 2026-10-16 |
| D-059 | Size/structure limits on MLS input before parsing | Accepted | 2026-10-16 |
| D-060 | Past-epoch key retention window | **Open** | 2026-10-16 |
| D-061 | Crypto agility: explicit protocol/ciphersuite/implementation/schema versions on every record | Accepted | 2026-10-16 |
| D-062 | Keep the backend-neutral harness + interop suite as a library-switch safety net | Accepted | 2026-10-16 |
| D-063 | Flutter bridge: own hand-written C ABI + first-party Flutter native assets (not flutter_rust_bridge) | **Accepted** (Prompt 06) | 2026-10-18 |
| D-064 | Device certificate v1: PIK-signed, domain-separated, carried in the MLS BasicCredential; trust = verified person keys − revoked devices | Accepted (development) | 2026-10-18 |
| D-065 | Local crypto state: sealed records (XChaCha20-Poly1305, AAD = header + name), one atomic whole-state record, fail closed on corruption | Accepted (development) | 2026-10-18 |
| D-066 | Key-encryption key via a provider interface; only insecure test adapters exist; production needs a platform adapter (Android Keystore / iOS Keychain) | **Open** (production adapter) | 2026-10-18 |
| D-067 | Native build: Rust 1.96.0 pinned by `rust-toolchain.toml`; `hooks`/`code_assets` pinned to the versions Flutter's tool uses (1.0.0) | Accepted | 2026-10-18 |
| D-068 | Crypto dependency gate: exact pins, decided OpenMLS versions, `--locked`, banned secret-logging features, `cargo audit --deny warnings` | Accepted | 2026-10-18 |

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
- **Status:** Accepted · 2026-10-15. Protocol proposed in Prompt 04 (D-042); library still open (D-043).

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
- **Also:** Android CI builds one flavor per job (matrix). Building three flavors plus the NDK in a single job ran out of runner disk on the second CI run.
- **Status:** Accepted · 2026-10-15. Update together with `FLUTTER_VERSION`.

### D-041 — Line endings
- **Decision:** `.gitattributes` sets `* text=auto eol=lf` (binaries excluded).
- **Reason:** Windows checkouts with `core.autocrlf=true` produced CRLF files, which break `tool/*.sh` and diverge from `dart format`.
- **Status:** Accepted · 2026-10-15

### D-042 — E2EE protocol: MLS (RFC 9420)
- **Decision (proposed):** Use MLS (RFC 9420) with ciphersuite `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519`. One MLS group per couple whose members are the devices of both people.
- **Reason:**
  - an IETF standard with formal analyses of its core;
  - forward secrecy and post-compromise security;
  - the device roster is part of authenticated group state, so a malicious server can't show different rosters to different devices undetected. This addresses the failure class in Albrecht et al. (2022) against Matrix.
- **Alternatives considered:**
  - Signal protocol family: strongest deployed protocol and has post-quantum, but no usable non-AGPL, supported, browser-capable implementation, and multi-device roster agreement would be custom (D-051);
  - Olm/Megolm via vodozemac: audited and runs in browsers, but Megolm lacks PCS and device trust lives in Matrix-specific code.
- **Evidence and status:** see [E2EE-ARCHITECTURE §4](../security/E2EE-ARCHITECTURE.md#4-candidate-evaluation). The Prompt 04 spike (OpenMLS 0.9.1) passed 6/6 natively and 6/6 on wasm32 under Node: GitHub Actions run 38870995297, commit `a308745`.
- **Status:** Proposed · 2026-10-16. Awaiting owner approval and D-043.
- **Update (Prompt 05):** Accepted as the protocol direction by the product owner; reconfirmed by the decision gate (no flaw found). Library: D-054.

### D-043 — MLS library
- **Leading candidate:** OpenMLS (MIT, active, wasm32 tests in its CI, production use through Wire's fork, public advisories handled).
- **Alternative:** mls-rs (Apache-2.0/MIT; lib.rs states no third-party audit yet).
- **Blocker:** no public independent audit of either was found. Before implementation:
  - commission or locate a review of the pinned version + crypto provider;
  - prototype through flutter_rust_bridge on Android, iOS and Web;
  - decide the storage provider.
- **Status:** Open · 2026-10-16
- **Correction (Prompt 05):** A public independent review of OpenMLS exists (SRLabs Security Assurance Assessment v1.2, 2026-03-11, core crates at commit a3402f2); Prompt 04 missed it. mls-rs still has none.
- **Superseded by D-054** (2026-10-16).

### D-044 — Group topology
- **Decision (proposed):** a couple group (both people's devices) for shared content; a personal group per person (own devices only) for private-to-self data. A new group for every pairing; never reused.
- **Status:** Proposed · 2026-10-16

### D-045 — Person identity and device certificates
- **Decision (proposed):**
  - each person has an Ed25519 Person Identity Key (PIK) that signs a certificate for each device;
  - every device accepts an MLS member only if the credential chains to one of the two verified PIKs and is not revoked;
  - Firestore device records are a directory, never trust.
- **Open:** credential format (X.509 vs Basic credential + certificate) and fingerprint format.
- **Status:** Proposed · 2026-10-16

### D-046 — Web v1 capability
- **Decision (proposed):** Web v1 offers no end-to-end-encrypted private content (account, device management, support only). An ephemeral linked-session design is a later, separately reviewed phase.
- **Reason:** the web delivers code on every load, so a compromised hosting/deploy path, XSS or extensions would expose plaintext and keys. See [WEB-SECURITY](../security/WEB-SECURITY.md).
- **Status:** Proposed — **requires product-owner approval** (it changes what web offers) · 2026-10-16
- **Update (Prompt 05):** Accepted by the product owner. Web V1 offers no private E2EE content. Prompt 05 showed the MLS core *runs* on wasm32; that is technical feasibility, not security acceptance.

### D-047 — Recovery
- **Decision (proposed):** add devices from an existing device by default; an opt-in high-entropy recovery key that decrypts a user-held encrypted backup of the PIK; no Sirf Hum escrow; no partner-vouched recovery. Without device or key, a new identity, visible to the partner.
- **Open:** whether to offer an encrypted history archive.
- **Status:** Proposed · 2026-10-16

### D-048 — Media encryption
- **Decision (proposed):** random per-object key; libsodium `crypto_secretstream_xchacha20poly1305` for chunked media; key and header delivered inside an MLS application message; thumbnails encrypted separately on device.
- **Open:** binding (Dart libsodium vs Rust), chunk size, size padding.
- **Status:** Proposed · 2026-10-16

### D-049 — Notifications
- **Decision (proposed):** data-only, content-free FCM payloads; generic local text; previews off by default (on-device decryption only, if ever enabled).
- **Status:** Proposed · 2026-10-16

### D-050 — Post-quantum
- **Open:** Standard MLS ciphersuites are not post-quantum, so content could be recorded now and decrypted later by a quantum-capable adversary. Signal already ships PQXDH + SPQR. The owner must decide whether to accept this for v1 and adopt PQ MLS ciphersuites when standardized and implemented.
- **Status:** Open · 2026-10-16
- **Update (Prompt 05):** Decided by the product owner: *Sirf Hum V1 does not require post-quantum MLS as a launch blocker.* Required instead:
  - crypto agility (D-061);
  - versioned protocol metadata;
  - a documented migration path via MLS ReInit when a standardized PQ ciphersuite is implementable.

  No claim is made about future PQ support in either library.

### D-051 — Rejected E2EE options
- **libsignal:**
  - AGPL-3.0;
  - README: "Use outside of Signal is unsupported"; APIs change without notice;
  - TypeScript is a Node add-on; no browser support documented.
- **libsignal_protocol_dart:** unofficial port, GPL-3.0, no review found.
- **Wire core-crypto:** GPL-3.0; Wire-specific.
- **Building from primitives:** a custom protocol.
- **Status:** Accepted (rejection) · 2026-10-16. Revisit libsignal only if the owner chooses an AGPL client and drops web.

### D-052 — Prototype policy
- **Decision:**
  - experiments live in `prototypes/<name>/`, marked EXPERIMENTAL;
  - never imported by the app;
  - no credentials;
  - focused tests;
  - CI only via the path-filtered `prototypes.yml`.
- **Status:** Accepted · 2026-10-16

### D-053 — Secret-scanner exceptions
- **Decision:** every gitleaks exception is scoped to a rule AND a path AND an exact match, documented in `.gitleaks.toml`, and verified with negative controls. First case: the public crate name `libcrux-secrets` in Cargo.lock. Local commits are gated on the scanner's exit code, never on piped output (a piped run let one flagged commit through in Prompt 04; it was a false positive).
- **Status:** Accepted · 2026-10-16

### D-054 — Cryptographic core selection (Prompt 05 decision gate)
- **Decision:** OpenMLS **0.9.1** (`openmls_rust_crypto` 0.6.0, `openmls_basic_credential` 0.6.0, `openmls_traits` 0.6.0; tag `v0.9.1` = `1762090a…`) is the development cryptographic core. mls-rs **0.56.0** (`8f1b43f4…`) stays a tested, wire-interoperable fallback.
- **Confidence:** medium.
- **Reason:**
  - the only candidate with a public independent review (SRLabs v1.2, 2026-03);
  - a visible advisory process;
  - production use through Wire, XMTP and White Noise;
  - upstream wasm32 CI.
- **Measured in Prompt 05:** both libraries passed every scenario natively and on wasm32, interoperated on all 15 steps, and passed their upstream test vectors (OpenMLS 356/0 failed; mls-rs 437/0 failed). GitHub Actions run 38887400583.
- **Why not high:**
  - the audit covered commit `a3402f2` (2025-10), not 0.9.1;
  - providers and storage were out of scope;
  - finding S1-3 (storage desync) is unfixed;
  - three parser advisories appeared after the audit.
- **Conditions:** see [MLS-DECISION](../security/MLS-DECISION.md): delta review, provider review, D-056–D-059, CI bans on secret-logging features, RustSec monitoring, platform tests, pen test, and design review.
- **Status:** Accepted for development · 2026-10-16. Supersedes the open D-043.

### D-055 — Encrypted handshake messages
- **Decision:** Commits and proposals are sent as MLS PrivateMessage (OpenMLS default policy; mls-rs `encrypt_control_messages = true`).
- **Reason:** hides membership changes from the delivery service. Interop showed the policy must be identical on all clients: mismatched defaults produced `IncompatibleWireFormat`.
- **Status:** Accepted · 2026-10-16

### D-056 — Rollback on rejected input
- **Decision:** Every untrusted MLS input is processed inside a local checkpoint; any rejection rolls back state.
- **Reason:** Prompt 05 measured that a rejected forged copy consumes the message key in **both** libraries (OpenMLS 20/52, mls-rs 28/65 tested byte positions), letting an injector make a genuine message undecryptable. The rollback scenario preserves the genuine message and keeps replay protection.
- **Status:** Accepted · 2026-10-16

### D-057 — Credential validation inside the crypto core
- **Decision:** The crypto core applies the PIK certificate policy (D-045) to every Add/Welcome/leaf update before any merge. Basic credentials are never trusted in production.
- **Reason:** OpenMLS leaves credential validation to the application (no identity-provider hook, unlike mls-rs).
- **Status:** Accepted · 2026-10-16

### D-058 — Transactional storage provider
- **Decision:** The OpenMLS storage provider is backed by an encrypted local database with one atomic transaction per operation.
- **Reason:** SRLabs S1-3 (acknowledged): OpenMLS storage writes during commit processing are not atomic. Also required by D-056.
- **Status:** Accepted · 2026-10-16

### D-059 — Input limits
- **Decision:** Bound message size, extension counts and nesting before handing bytes to MLS parsing.
- **Reason:** SRLabs S0-1 (unbounded allocations, risk-accepted upstream) and the 2026 OpenMLS parser advisories (quadratic decoding, OOB panic, unbounded recursion).
- **Status:** Accepted · 2026-10-16

### D-060 — Past-epoch window
- **Open:** OpenMLS defaults to keeping 0 past epochs, so late messages after a commit are rejected (measured); mls-rs keeps prior epochs. Choose a small window that balances delivery reliability against forward secrecy. Decide with the messaging design.
- **Status:** Open · 2026-10-16

### D-061 — Crypto agility
- **Decision:** Every protocol record carries explicit versions:
  - `EncryptedEnvelope.protocolVersion`;
  - MLS protocol version and ciphersuite;
  - the implementation identifier (`openmls/0.9.1`) in non-secret device capabilities;
  - the payload `schemaVersion`.

  Unknown versions fail closed; ciphersuite changes go through MLS ReInit.
- **Status:** Accepted · 2026-10-16

### D-062 — Library-switch safety net
- **Decision:** Keep `prototypes/mls-decision-gate` (backend-neutral scenarios, OpenMLS↔mls-rs interop, upstream test vectors) running in CI while the core is built, so switching implementations remains practical.
- **Status:** Accepted · 2026-10-16

### D-063 — Flutter bridge mechanism
- **Decision:** a hand-written C ABI (`native/src/ffi.rs`, 19 functions, `ABI_VERSION = 1`) called from `dart:ffi` `@Native` bindings and packaged by a first-party native-assets build hook (`hook/build.dart`, `hooks`/`code_assets` from dart.dev). Not flutter_rust_bridge.
- **Reason:**
  - **smallest reviewable boundary:** opaque handle, `(ptr, len)` inputs, Rust-owned output buffers freed (and wiped) by one function, `i32` error codes. No generated code to audit, no serialization framework, no strings across the boundary;
  - **no third-party build tool:** the hook calls `cargo` directly; `native_toolchain_rust` (third-party) is not used;
  - **Web separation is a compile-time import split** (`dart.library.ffi`), with no runtime bridge on Web (D-046);
  - flutter_rust_bridge 2.13.0 would add a code generator, a runtime and a wider generated surface (async, streams, opaque Rust types in Dart), all of which would need review, for features we do not want across this boundary.
- **Evidence:** the hook builds Android (`.so` for arm64-v8a, armeabi-v7a and x86_64) and iOS (device + simulator) inside the real app. CI checks the bundled binaries and runs `integration_test/crypto_core_test.dart` on an Android emulator and an iOS simulator ([CRYPTO-CORE-ARCHITECTURE](../security/CRYPTO-CORE-ARCHITECTURE.md)).
- **Cost:** ABI changes are manual on both sides; mitigated by the ABI version check and Dart tests through the real library.
- **Status:** Accepted · 2026-10-18 (Prompt 06). Was Open since 2026-10-16.

### D-064 — Device certificate v1
- **Decision:** concretises D-045 for development.
  - Each device's MLS `BasicCredential` identity is an encoded certificate: `"SirfHum-DeviceCertificate-v1"` ‖ version ‖ person key ‖ device ID (16 random bytes) ‖ device signature key ‖ issued-at.
  - The certificate is signed by the Person Identity Key (Ed25519 through `OpenMlsCrypto`).
  - Receivers accept a member only if:
    - the signature verifies;
    - the person key is trusted (own key, or verified via `trustVerifiedPersonKey`);
    - the device is not revoked;
    - the certified key equals the leaf signature key.
- **Not decided here:** how person keys are verified by users (pairing phase), certificate expiry, and PIK rotation.
- **Status:** Accepted for development · 2026-10-18. Format review is a condition of production use (D-054).

### D-065 — Local crypto state format
- **Decision:** refines D-058.
  - Three local records:
    - `identity_secret`;
    - `public_metadata`;
    - `mls_state`, which holds the whole OpenMLS storage map, group IDs and trust policy.
  - Each record is sealed as `SHCR | format=1 | kind | nonce[24] | XChaCha20-Poly1305` under the KEK, with AAD = header + record name.
  - Each record is replaced atomically (temp file + fsync + rename + directory fsync), once per operation, after a successful checkpointed operation.
  - Unknown versions, a failed authentication, or a wrong kind or name fail closed (`stateCorruption`). There is never a silent reset.
- **Reason:** one atomic record makes every operation all-or-nothing on disk (SRLabs S1-3; D-056), and the AEAD makes tampering detectable. The crate is `chacha20poly1305 =0.10.1`, already in OpenMLS's dependency tree; 192-bit random nonces make random-nonce reuse negligible.
- **Trade-off:** each write re-seals the whole state. That is fine at couple scale (≤ 16 members, bounded record ≤ 8 MiB); revisit with history.
- **Status:** Accepted for development · 2026-10-18

### D-066 — Key-encryption key storage
- **Decision:** the core gets its KEK from a `KeyEncryptionKeyProvider` that reports `is_production_secure()`.
  - Two adapters exist, both **insecure and test-only**: `EphemeralTestKeyStore` (memory) and `InsecureFileTestKeyStore` (a plaintext file).
  - `KeyStoreKind.platform` returns `unsupported`.
  - The app classifies native support as `nativeDevelopmentOnly`.
- **Open:** a platform adapter (Android Keystore with StrongBox where available / iOS Keychain with `ThisDeviceOnly` accessibility) that wraps or holds the KEK and can destroy it on wipe. It must also address whole-directory rollback (no monotonic counter exists today).
- **Status:** **Open** · 2026-10-18. Required before any real user's content.

### D-067 — Native build pinning
- **Decision:**
  - Rust 1.96.0 with the Android/iOS targets is pinned in `native/rust-toolchain.toml`; CI fails if another `rustc` is active.
  - `hooks` and `code_assets` are pinned to 1.0.0, the versions Flutter 3.41.5's tool depends on. 2.x conflicts with Flutter's pinned `meta`.
  - Builds are always `cargo build --locked --release`.
- **Consequence:** Android and iOS app builds need rustup. On Windows, local Android builds also need the MSVC Build Tools.
- **Invariant (enforced):** the `hooks` and `code_assets` versions in `packages/sirf_hum_crypto/pubspec.yaml` are exact pins equal to the versions in the installed Flutter SDK's `packages/flutter_tools/pubspec.yaml`.
  - `tool/check_flutter_hook_pins.sh` compares them and fails closed. It runs from `tool/check_crypto_core.sh` (CI `crypto-core` job, after Flutter is installed and before any Rust build) and from `tool/verify.sh`.
  - Tests: `tool/test_check_flutter_hook_pins.sh` (fixtures: match passes; hooks/code_assets mismatch, ranges and missing entries fail).
- **Why the invariant exists:**
  - the build hook talks to `flutter_tools` through those packages' hook protocol, so a different version can drift from what the SDK speaks;
  - newer majors can also be unresolvable. Prompt 06's first draft pinned `hooks 2.2.0`, whose `record_use` dependency needs `meta ^1.19.0` against Flutter 3.41.5's pinned `meta 1.17.0`.
  - Upgrading Flutter therefore means re-pinning both packages to the new SDK's versions in the same change.
- **Status:** Accepted · 2026-10-18 · invariant added 2026-10-18

### D-068 — Crypto dependency gate
- **Decision:** CI (`tool/check_crypto_core.sh` plus the `crypto-core` job) fails when:
  - a direct dependency is not `=`-pinned;
  - OpenMLS or its companions resolve to anything other than the D-054 versions;
  - `Cargo.lock` is out of sync or changed by the build;
  - OpenMLS `crypto-debug` / `content-debug` is enabled;
  - a logging/printing macro or crate appears;
  - `cargo audit --deny warnings` reports a RustSec advisory (vulnerability, unmaintained, unsound or yanked).
- **What it does not guarantee:** cargo-audit only knows *published* advisories. It finds no unknown bugs and is no substitute for review.
- **Tool pin:** cargo-audit **0.22.2** (exact, `--locked`).
  - 0.21.2 could not parse the current RustSec database (CVSS 4.0 vector in RUSTSEC-2026-0124) and failed closed. That was a tool failure, not a finding.
  - Assessed: RUSTSEC-2026-0124 affects `libcrux-chacha20poly1305 < 0.0.8`. We lock 0.0.9 (patched), so it does not apply.
  - A database-format break must be fixed by updating the tool, never by skipping the audit.
- **Documented ignores** (`tool/crypto_audit.sh`; each is re-verified on every run, and the script fails if the reason stops holding):
  - **RUSTSEC-2026-0330, RUSTSEC-2026-0331** (`libcrux-kem 0.0.9`: panics on short hybrid seeds and keys; medium and high).
    - Why inapplicable: the crate is locked only as an inactive optional dependency (`hpke-rs` feature `libcrux` is off; `openmls_rust_crypto 0.6.0` uses the RustCrypto HPKE backend). It is never compiled, which CI build logs confirm.
    - Why not bumped: `hpke-rs-libcrux 0.7.0` pins `=0.0.9`, and the fix needs `hpke-rs 0.8`, outside the D-054 pins.
    - Check: `cargo tree --target all -e normal,build -i libcrux-kem` (and `hpke-rs-libcrux`) must be empty.
  - **RUSTSEC-2026-0173** (`proc-macro-error2 2.0.1` unmaintained; not a vulnerability).
    - Why inapplicable: it is used only by proc-macro crates (`hax-lib-macros`), so it runs at compile time and never ships in the binary. No maintained release exists.
    - Check: every user of the crate in `cargo metadata` must be a proc-macro target.
  - **Revisit:** any OpenMLS/provider upgrade (the D-054 delta review) must try to remove all three ignores. A new ignore needs the same treatment: a written reason, an automated re-check, and an entry here.
- **Status:** Accepted · 2026-10-18
