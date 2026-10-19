# Decision Log

Append-only. To change a decision, add a new entry that supersedes it and
mark the old one `Superseded by D-xxx`.

Statuses: **Accepted** · **Proposed** (needs owner confirmation) ·
**Open** (needs a decision before a named milestone) · **Superseded**.

| ID | Decision | Status | Date |
| --- | --- | --- | --- |
| D-001 | Product name: Sirf Hum | Accepted | 2026-10-15 |
| D-002 | Flutter + Dart as the frontend framework | Accepted | 2026-10-15 |
| D-003 | Targets: Android, iOS, Web from one codebase | **iOS part superseded by D-092** (Android + Web) | 2026-10-15 |
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
| D-045 | Person Identity Key (PIK) + PIK-signed device certificates; roster acceptance policy | Proposed — **PIK transfer superseded by D-074** (each device keeps its own PIK) | 2026-10-16 |
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
| D-060 | Past-epoch key retention window | **Resolved for messaging by D-091** (window 0) | 2026-10-16 |
| D-061 | Crypto agility: explicit protocol/ciphersuite/implementation/schema versions on every record | Accepted | 2026-10-16 |
| D-062 | Keep the backend-neutral harness + interop suite as a library-switch safety net | Accepted | 2026-10-16 |
| D-063 | Flutter bridge: own hand-written C ABI + first-party Flutter native assets (not flutter_rust_bridge) | **Accepted** (Prompt 06) | 2026-10-18 |
| D-064 | Device certificate v1: PIK-signed, domain-separated, carried in the MLS BasicCredential; trust = verified person keys − revoked devices | Accepted (development) | 2026-10-18 |
| D-065 | Local crypto state: sealed records (XChaCha20-Poly1305, AAD = header + name), one atomic whole-state record, fail closed on corruption | Accepted (development) | 2026-10-18 |
| D-066 | Key-encryption key via a provider interface; platform adapter (Android Keystore-wrapped / iOS `ThisDeviceOnly` Keychain) implemented in Prompt 07; test adapters refused in release | Accepted (adapter) — **rollback protection and review open** | 2026-10-18 |
| D-067 | Native build: Rust 1.96.0 pinned by `rust-toolchain.toml`; `hooks`/`code_assets` pinned to the versions Flutter's tool uses (1.0.0) | Accepted | 2026-10-18 |
| D-068 | Crypto dependency gate: exact pins, decided OpenMLS versions, `--locked`, banned secret-logging features, `cargo audit --deny warnings` | Accepted | 2026-10-18 |
| D-069 | Device registry `users/{uid}/devices/{deviceId}`: client creates `pending`, server activates, owner revokes one-way, no deletes, global device-ID/key uniqueness | Accepted (development) | 2026-10-18 |
| D-070 | Device proof of possession: server challenge (single-use, 5 min) signed by the device key over a domain-separated payload built in Rust | Accepted (development) | 2026-10-18 |
| D-071 | Device identity is per (installation, account): one local slot per account, account re-checked in the core, logout keeps, explicit removal is crypto-erasure | Accepted | 2026-10-18 |
| D-072 | `lib/platform` may implement ports defined by `lib/security` (e.g. `DeviceKeyStore`) | Accepted | 2026-10-18 |
| D-073 | Platform priority: "iOS supported from day one; iOS optimized/hardened at the end." Android is the primary development platform | **Superseded by D-092** | 2026-10-18 |
| D-074 | Multi-device model: every device keeps its own PIK and keys (no key sharing or transfer); trust between a person's devices is a chain of PIK-signed approvals (Option C) | Accepted (development) | 2026-10-18 |
| D-075 | Device approval protocol: bootstrap-only proof of possession for an account's first device; later devices need an approval statement by an active device, verified server-side; six-digit comparison code | Accepted (development) | 2026-10-18 |
| D-076 | V1 recovery: trusted-device approval + optional single-use user-held recovery key (public half registered); no server/support recovery; no history recovery; identity reset without devices or key **open** | Accepted (development) — reset **Open** | 2026-10-18 |
| D-077 | Per-account fixed-window rate limits and a shared verification-failure budget (no enumeration oracle) | Accepted | 2026-10-18 |
| D-078 | Server-authoritative expiry (challenge 5 min, request 10 min, pending device 7 days) with lazy enforcement and an idempotent scheduled cleanup | Accepted (scheduler needs Blaze) | 2026-10-18 |
| D-079 | Local rollback protection is not provided; analysis recorded; production hardening must choose an external freshness anchor | **Open** | 2026-10-18 |
| D-080 | Revocation: owner session may revoke (one way); no cascade, lineage recorded; approvals die with their approver | Accepted | 2026-10-18 |
| D-081 | Signed revocation by an active device's PIK; no client writes to device records | Accepted (development) | 2026-10-18 |
| D-082 | Identity reset: delayed 7 days, cancellable by any trusted device, to a new identity | Accepted (development) | 2026-10-18 |
| D-083 | Server trust epoch; devices refuse an older view | Accepted (development) | 2026-10-18 |
| D-084 | Peer-side lineage verification in Rust | Accepted (development) | 2026-10-18 |
| D-085 | Trust unit is the exact device certificate (device-pinned, one device per PIK); anchors only root lineage; revoking a device revokes its PIK | Accepted (development); own-account anchoring UX **Open** | 2026-10-19 |
| D-086 | Conversations are server-provisioned from an accepted pairing only; clients cannot create or change membership | Accepted (development); pairing phase pending | 2026-10-19 |
| D-087 | ABI v5 staged commits: stage, server acceptance, confirm/discard; ABI v4 semantics unchanged | Accepted (development) | 2026-10-19 |
| D-088 | First commit wins per conversation epoch (create-only, rules-enforced); messages only at the current epoch; server arbitration never replaces MLS validation | Accepted (development) | 2026-10-19 |
| D-089 | Versioned message envelope; routing fields bound in MLS authenticated data built by Rust; Rust-generated random message IDs | Accepted (development) | 2026-10-19 |
| D-090 | Local message history as sealed core records in the account slot, atomic with MLS state; no plaintext fallback | Accepted (development) | 2026-10-19 |
| D-092 | iOS is not part of the current product: Android P0, Web P1 where applicable, iOS undecided; iOS CI jobs removed; shared code stays platform-neutral | Accepted (owner decision) | 2026-10-19 |
| D-091 | Per-epoch receive order; past-epoch window 0 (resolves D-060 for messaging); out-of-order tolerance 32; encrypt at compose, re-encrypt the same ID after a stale-epoch refusal | Accepted (development) | 2026-10-19 |

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
- **Update (Prompt 10):** resolved for messaging by D-091: window 0, made safe by per-epoch processing and server-side current-epoch writes.

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
- **Decision:** the core gets its store key (Rust: "KEK") from a `KeyEncryptionKeyProvider` that reports `is_production_secure()`. That flag describes the key source only; it is never a claim that the system is production E2EE.
  - **Platform adapter (Prompt 07):** app-owned channel, KEY-MANAGEMENT §3 option (a). A per-account 32-byte store key is passed in through `sh_crypto_open_with_platform_key` (`PlatformProvidedKey`).
    - Android: wrapped by a non-exportable Keystore AES-256-GCM key (StrongBox when available), AAD-bound to its slot, kept in `noBackupFilesDir`.
    - iOS: a `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non-synchronizing Keychain item, with the crypto directory excluded from backup.
  - **Test adapters** (`EphemeralTestKeyStore`, `InsecureFileTestKeyStore`) remain for tests and are **refused in release builds** by the Dart facade.
  - **Correction:** Prompt 06's comment said the facade refused them in release, but no code did; Prompt 07 implements it.
- **Reason for passing the key through Dart:** one small channel per platform is the smallest trusted surface. Calling Keystore/Keychain from Rust (JNI / Security.framework) would add far more code inside the boundary.
- **Residual risk:**
  - platform message-codec copies of the store key cannot be reliably wiped;
  - whole-directory rollback on a rooted/jailbroken device is undetected (no monotonic counter).
- **Status:** Accepted (adapter) · 2026-10-18. **Open:** rollback protection; independent review.

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

### D-069 — Device registry
- **Decision:** `users/{accountId}/devices/{deviceId}` (32-hex device ID).
  - **Owner's client:** may create an exact v1 `pending` record (schema, platform, certificate, ciphersuite, implementation, `createdAt == request.time`), read its own records, and revoke one-way (`pending|active → revoked`, `revokedReason: user_removed`). *(Client create removed in Prompt 08; client revocation replaced by signed revocation in D-081.)*
  - **Activation** is server-only (`activateDevice`).
  - **Records are never deleted.**
  - **Server-only indexes** `deviceIdIndex` and `deviceKeyIndex` make every device ID and device key activatable at most once, ever.
- **Alternatives:**
  - *Client writes `active` after proof:* rejected, because rules cannot verify signatures.
  - *Function-only writes for everything:* rejected for now. The rules-validated `pending` create keeps the registry usable without the Functions deploy, and is easy to test.
  - *Top-level `devices/{deviceId}`:* rejected, because owner-scoped paths keep the rules trivially correct.
- **Metadata minimisation:** no `lastSeenAt`, app or OS version, model, hardware/advertising IDs, or push token (DEVICE-IDENTITY §4).
- **Status:** Accepted for development · 2026-10-18. Deploying activation needs Blaze (D-025).
- **Amended (Prompt 08):** clients no longer create records. `registerDevice` (a Function) verifies the certificate, rate-limits, caps pending devices at 3 and sets `expiresAt`; the rules deny every client create. New server fields: `expiresAt`, `activationMethod` (`first_device`/`approval`/`recovery`), `approvedBy`, `rejectedAt`. New terminal states: `rejected`, `expired` (D-075, D-078).

### D-070 — Device proof of possession
- **Decision:**
  - **Challenge:** `issueDeviceChallenge` creates a 32-byte challenge, single-use, 5-minute expiry, bound to (account, device, purpose).
  - **Proof:** the device signs `"SirfHum-DeviceProof-v1" | purpose | account | device ID | certificate | challenge` with its certified device key. The payload is built inside the Rust core (`sh_crypto_device_proof`), so callers cannot request signatures over arbitrary data.
  - **Verification:** `activateDevice` checks the certificate (PIK signature) and the proof with `node:crypto` Ed25519, consuming the challenge on every attempt within one transaction.
  - **Purposes:** each purpose is a separate signed domain. Only `activation = 1` exists.
- **Reason:** authentication (Firebase) and device possession are separate facts. Binding account, device, certificate and a fresh challenge defeats replay, cross-account reuse and copied metadata (DEVICE-IDENTITY §6).
- **Cross-implementation check:** a golden vector generated by the server code is verified by the Rust tests.
- **Status:** Accepted for development · 2026-10-18. Needs independent review.
- **Amended (Prompt 08):** purpose `enrollment = 2` was added (a new device proving possession for an approval request). Proof of possession with purpose `activation` now activates **only an account's first device, once ever** (D-075).

### D-071 — Account slots and account switching
- **Decision:** device identity is per (installation, account).
  - Each account has its own local slot: a directory plus its own platform store key. Slot name = account ID, validated `[A-Za-z0-9_-]{1,128}`.
  - The Rust core re-checks on every open that the stored identity belongs to the requested account (`AccountMismatch`, code -18).
  - Logout keeps the slot. Explicit removal deletes the key first (crypto-erasure).
  - A new identity always gets a fresh store key, which also discards a stale iOS Keychain item after a reinstall.
- **Reason:**
  - **no identity crossover between accounts;**
  - **no installation-wide identifier** that would let the server link accounts used on one phone;
  - **honest reinstall semantics:** a reinstall is a new device.
- **Status:** Accepted · 2026-10-18

### D-072 — Platform implements security ports
- **Decision:** `lib/platform` may depend on `lib/security` *only* to implement ports that `lib/security` defines (first: `DeviceKeyStore`). Security never imports platform or infrastructure.
- **Reason:** keeps platform channels (`MethodChannel`, `kIsWeb`) out of the security layer while the security layer owns the contract. Previously the platform layer could depend on `core` only.
- **Status:** Accepted · 2026-10-18

### D-073 — Platform priority: iOS supported from day one, hardened at the end
- **Decision (owner direction, during Prompt 07):** "iOS supported from day one; iOS optimized/hardened at the end."
  - Android is the primary platform for rapid development and verification. Flutter/Web continues where applicable (Web V1 still has no private E2EE, D-046).
  - **iOS security-critical functionality and compatibility remain required in every prompt:**
    - device identity;
    - Keychain key storage;
    - persistence and corruption behaviour;
    - crypto-core integration;
    - no secret leakage;
    - iOS security tests and iOS CI jobs.
  - iOS-specific performance and build optimization (Xcode/Rust compile times, CI speed) is **not** a development blocker. Slow iOS CI is allowed to finish, never skipped.
  - A dedicated **iOS Hardening & Release Pass** before production will cover:
    - Keychain edge cases;
    - background/foreground behaviour and device migration;
    - crypto integration and push notifications;
    - permissions and performance;
    - App Store requirements and CI optimization.
- **Never used to justify:** skipping, disabling or weakening an iOS security test or job, or dropping iOS support.
- **Status:** **Superseded by D-092** (2026-10-19): iOS is not part of the current product.

### D-074 — Multi-device model: independent device identities linked by approvals
- **Decision:**
  - Every device of an account keeps its **own** device ID, device signature key and PIK. No private key is ever shared, copied, derived or transferred between devices.
  - A person's devices are linked by **approval statements**: an active device's PIK signs "this new device is mine" (D-075).
  - Approving also makes the approver trust the new device's PIK locally, so it can add the new device to MLS groups.
- **Options evaluated** (MULTI-DEVICE-TRUST §2):
  - **(A) Unlinked per-device PIKs:** rejected. There is no proof that two devices belong to one person.
  - **(B) PIK private-key transfer** (Prompt 04 D-045 idea): rejected. Prompt 08 forbids reusing private keys across devices, one compromise would expose every device's identity, and it would need a new encrypted transfer channel.
  - **(C) Independent PIK plus a signed authorization artifact:** selected. It is the smallest safe model; it reuses the D-064 certificate unchanged; the server can verify it now and peers later; and it allows per-device revocation.
- **Consequences:**
  - **D-045's PIK-transfer step is superseded.** D-064 is unchanged.
  - A partner trusts a person's devices through a chain from a verified PIK. Peer-side chain verification is future work.
  - The new device does not yet learn its approvers' PIKs (future sync).
- **Status:** Accepted for development · 2026-10-18. Needs independent review.

### D-075 — Device approval protocol
- **Decision:**
  - **Bootstrap:** proof of possession (D-070, purpose `activation`) activates a device only if the account has **never** had a trusted device. A server-only `accountTrust/{uid}` record makes this once-ever, so revoking every device never re-enables bootstrap.
  - **Every later device:** `registerDevice` → `requestDeviceApproval` (single-use 32-byte challenge, 10-minute server-chosen expiry) → `proveDeviceEnrollment` (device proof, purpose `enrollment`) → `approveDevice`.
  - **The approval statement** is signed by an active device's PIK:

    ```text
    "SirfHum-DeviceApproval-v1" | version 1 | account | approver id
    | approver certificate | new id | new certificate | challenge | expires_at
    ```

    It is verified against the approver's **stored** certificate. The approver must be `active` at submission; the request is consumed by its first use; B is activated atomically.
  - **Rejection** (`rejectDeviceApproval`) makes the device `rejected` (terminal).
  - **Comparison code:** a six-digit SHA-256 code over (new certificate, challenge), shown on both devices so the user approves the device in their hand.
- **Reason:** Firebase Auth proves the account, not device trust. The binding set prevents account confusion, device substitution, replay, forwarding, approving the wrong device, and approval by an untrusted device (MULTI-DEVICE-TRUST §4). The domain separation is tested against device proofs and recovery statements.
- **Cross-implementation:** golden vectors generated by the server code (`functions/test/vectors/device_trust_v1.json`) are verified by the Rust tests.
- **Status:** Accepted for development · 2026-10-18. Needs independent review.

### D-076 — V1 recovery model
- **Decision:**
  - **Default:** trusted-device approval (D-075).
  - **Optional user-held recovery key:**
    - an Ed25519 seed generated in Rust and shown once as `SHRK1-…` text (versioned base32 with a typo checksum);
    - only its public half is registered, by an active device's PIK-signed `"SirfHum-RecoveryKeyRegistration-v1"` statement;
    - recovery = the key signs `"SirfHum-RecoveryApproval-v1"` for a proven new device;
    - **single-use:** the server deletes the registered key on success.
  - **Rejected:** server recovery and support/admin recovery of device trust; a server master key; server copies of keys; password-reset-based recovery.
  - **No message-history recovery:** an encrypted archive is deferred.
- **Open:** "identity reset" when every device and the recovery key are lost. It would let the account start a new identity, visible to the partner, with re-verification. Not implemented: a server-only reset would turn a password compromise into a trust compromise.
- **Status:** Accepted for development · 2026-10-18. Needs independent review. The reset is decided in **D-082** (Prompt 09).

### D-077 — Rate limits
- **Decision:** per-account fixed-window limits in the server-only `rateLimits` collection, enforced by the Functions in transactions:

  | Operation | Limit |
  | --- | --- |
  | Registration | 5 per hour |
  | Challenges | 10 per hour |
  | Approval requests | 5 per hour |
  | Verification failures (shared budget) | 5 per hour, then every verifying call is refused for the window |
  | Recovery attempts | 3 per day |
  | Pending devices | at most 3 at once |

- **Why not an enumeration oracle:** the limits are keyed by the caller's own account, the error is a generic `rate_limited`, and nothing about other accounts is revealed.
- **Not used:** no third-party service.
- **Status:** Accepted · 2026-10-18

### D-078 — Expiry and cleanup
- **Decision:** server-chosen, signed where relevant, and enforced on every call (lazy):

  | Item | Lifetime |
  | --- | --- |
  | Challenges | 5 minutes |
  | Approval requests | 10 minutes |
  | Pending devices | 7 days, then `expired`: terminal, never deleted, so the ID is never reused |

  The scheduled `cleanupExpiredDeviceRecords` tidies records daily. It is idempotent, re-checks each record in a transaction, and never touches active or revoked devices. A collection-group index supports it.
- **Status:** Accepted · 2026-10-18. The schedule needs Cloud Scheduler (Blaze, D-025).

### D-079 — Local rollback protection
- **Decision:** not provided, and not claimed.
  - An in-state counter rolls back with the state.
  - Neither platform offers a general app-level monotonic counter.
  - Server-held versions would need per-write reporting (activity metadata) and an offline design.
- **What holds:**
  - copied state is useless off-device;
  - restored state cannot regain server trust, because status is server-side and IDs and keys are indexed forever;
  - MLS removal blocks new epochs.
- **Status:** **Open (partly addressed)** · 2026-10-18. D-083 adds a server trust epoch that devices refuse to see go backwards; local file rollback is still not prevented. Production hardening must choose an external freshness anchor (MULTI-DEVICE-TRUST §10).

### D-080 — Revocation model
- **Decision:**
  - **Who:** the account owner, from any signed-in session, revokes via the rules (one way). Server-side revocation is also possible. Revocation only reduces trust, and a user whose only device was stolen must still be able to kill it.
  - **Accepted risk:** a password holder can revoke devices. That is a denial of service, never a trust gain.
  - **No cascade:** past approvals by a later-revoked device stand. `approvedBy` lineage lets the owner review and revoke them.
  - **Approvals die with their approver:** a revoked device can never approve or register a recovery key; the server checks at submission.
  - **Local wipe is separate from revocation** (MULTI-DEVICE-TRUST §7).
- **Follow-up:** signed revocation statements, for attribution and peer verification.
- **Status:** **Superseded by D-081** (Prompt 09) for *who* may revoke. No cascade, approvals dying with their approver and the local-wipe separation still hold.

### D-081 — Signed revocation
- **Decision:** a device is revoked only by a statement signed by the PIK of an `active` device of the same account, which may be the device itself, or by a completed identity reset (D-082). The flow is `issueDeviceChallenge(purpose revocation)` (5 minutes, bound to the revoker) → `revokeDevice`.
- **Statement:**

  ```text
  "SirfHum-DeviceRevocation-v1" | version 1 | len|account | revoker id | len|revoker cert
  | revoked id | len|revoked cert | reason u8 | challenge[32] | expires u64
  ```

  The reasons are 1 removed, 2 lost, 3 stolen, 4 compromised. The statement is verified against the **stored** certificates in one transaction, which also checks that the revoker is active and the target is pending or active, and consumes the challenge. The evidence is stored on the revoked record.
- **Rules:** clients cannot write device records at all. The owner's session revocation (D-080) is removed.
- **Reason:** attribution and peer verification (D-084). A password alone no longer changes device state.
- **Accepted residual:** when the only device is stolen and there is no recovery key, nothing can sign its revocation. The remaining path is an identity reset, and the thief's unlocked device could cancel it. The UI must strongly recommend a recovery key.
- **Status:** Accepted for development · 2026-10-18. Needs independent review.

### D-082 — Identity reset (delayed, cancellable, new identity)
- **Decision:** Prompt 09 §6 option C.
  - A signed-in session may request a reset only once the account has trust (`requestIdentityReset`). Repeating the request keeps the original deadline.
  - Any `active` device can cancel within **7 days** by signing `"SirfHum-IdentityResetCancel-v1" | version 1 | len|account | device id | len|cert | challenge | expires`.
  - After the delay, `completeIdentityReset` revokes every pending or active device (`authority: identity_reset`), deletes the recovery key, increments `identityEpoch` and opens **one** new bootstrap.
  - The new first device has a **new PIK**: nothing of the old identity is inherited, and partners must re-verify.
  - Rate limit: 3 per 7 days.
- **Rejected:**
  - a server-only reset, because a password compromise would become a trust compromise;
  - a terminal no-recovery state alone, because it leaves no path for a legitimate user.
- **Not a takeover:** an attacker who completes a reset gets an unverified new identity, never the old trust. Partners see the change as a new identity.
- **OPEN before production:** push notifications (D-009/D-049, no private content) so the legitimate user and the partner learn of a reset request. Partner-visible re-verification also needs the pairing UX.
- **Status:** Accepted for development · 2026-10-18. Needs independent review.

### D-083 — Trust epoch (server freshness signal)
- **Decision:**
  - `accountTrust.trustEpoch` increases by one in the same transaction as every trust change (bootstrap, approval, recovery, recovery-key registration, revocation, reset request, cancel and completion).
  - Device records carry `activatedEpoch` and `revokedEpoch`.
  - Each device stores the highest epoch it has seen as a sealed record in its Rust state (record kind 4) and refuses an older one with `trust_state_stale` (code -20) before approving, revoking, cancelling a reset or registering a recovery key.
- **Limits:** this detects stale or rolled-back server views relative to what a device already saw. It does not detect a rollback of the device's own files (D-079), and it does not prove the server is honest.
- **Status:** Accepted for development · 2026-10-18.

### D-084 — Peer-side lineage verification
- **Decision:**
  - **Server side:** the server stores on each record the exact statements that activated it (approval, or recovery-key registration plus recovery approval) and that revoked it.
  - **Device side:** devices verify the chain in Rust. `verify_lineage` and the FFI `sh_crypto_verify_lineage` (ABI 4) take a versioned, strictly decoded blob and return the trusted device IDs. Any defect is `trust_chain_invalid` (code -21).
  - **Chain rules:**
    - the root is the current identity's first device;
    - each approver or registrar must already be in the chain;
    - protocol version 1;
    - no duplicate devices;
    - revocations need an in-chain revoker;
    - server-asserted revocations can only remove trust.
  - **Mismatch:** the client fails closed if the server lists an `active` device the chain does not prove.
  - **Vectors:** golden vectors `device_trust_v2.json` are generated by TypeScript and verified identically in Rust and Dart.
- **Trust anchor:** the root PIK is trusted only through partner out-of-band verification (D-064). The lineage proves descent from the root, not who the root is.
- **Accepted limits:** the server can withhold evidence (omission) and controls ordering. Freshness is the trust epoch (D-083). There is no cascade (D-080).
- **Status:** Accepted for development · 2026-10-18. Needs independent review.

### D-085 — Device-pinned trust unit
- **Problem:** the core trusted person keys (PIKs) and blocked device IDs. Since D-074 each device has its own PIK, which can sign any number of certificates. A revoked device could therefore certify a new device ID with its old PIK and pass validation.
- **Decision:**
  - The trust unit is the **exact device certificate** (person key, device ID, device signature key, issued-at, PIK signature). The core's `TrustPolicy` holds it with its source: own, approved, anchor, or the lineage of an account.
  - Person keys verified out of band are **anchors**: roots for lineage verification. An anchor's own first certificate is accepted and **pinned**; a PIK certifies exactly one device ID.
  - `trustLineage(lineage, trustEpoch)` (ABI v5) verifies an account's chain (D-084) from an anchored root. It trusts every proven certificate for that account, drops that account's devices no longer proven, and refuses a trust epoch older than one already applied.
  - Revoking a device, locally or through lineage evidence, also revokes its PIK permanently.
  - A device keeps the account a lineage first proved it for, permanently; a lineage that would re-label it is refused (Prompt 10 Part 2 review). A root-only lineage does not prove its account, so a root's first binding rests on the server and on out-of-band verification.
  - The state record moves to version 2. Version 1 still loads; its person keys become anchors.
- **Rejected:**
  - keeping PIK trust with only device-ID revocation (the gap);
  - deriving device trust from Firebase records (server authority over trust).
- **Open:** a non-root device must anchor its own account's root PIK. The verification UX belongs to the device-management/pairing phase.
- **Status:** Accepted for development · 2026-10-19. Needs independent review.

### D-086 — Server-authoritative conversation provisioning
- **Decision:**
  - A conversation (`conversations/{id}`, ID = 16 random bytes = MLS group ID) is created only by the server-internal `provisionConversation`.
  - It needs a `pairings/{id}` record with `status: 'accepted'`, written by the future pairing phase.
  - It also writes `accountPartners/{uid}` for both accounts, so each can read the other's public device directory for lineage verification.
  - No callable exposes it. Clients cannot create pairings, conversations or partner records, or change membership.
- **Reason:** couple membership is relationship metadata that the server must authorize; clients must never declare it.
- **Status:** Accepted for development · 2026-10-19. Unreachable in the product until pairing exists.

### D-087 — ABI v5 staged commits
- **Decision:**
  - Membership-changing commits for messaging are staged (`create_conversation_group`, `stage_add_members`, `stage_remove_members`, `stage_self_update`), uploaded, then confirmed with `confirm_commit(fromEpoch)` or dropped with `discard_commit(fromEpoch)`.
  - Staging never advances the active epoch.
  - A duplicate confirm is idempotent. Confirming after a discard, or at the wrong epoch, fails with `no_staged_commit` (-23).
  - While a commit is staged, sending, other commits and ABI v4 membership calls are refused with `commit_pending` (-22). Application messages may still be processed.
  - Discarding an unconfirmed new group deletes it.
  - ABI v4 functions keep their immediate-merge semantics for regression.
- **Status:** Accepted for development · 2026-10-19.

### D-088 — First commit wins per epoch
- **Decision:**
  - `conversations/{c}/commits/{epoch}` is create-only. It is written in one batch with the conversation `epoch` moving to `epoch + 1` and with that commit's Welcomes.
  - Rules check both halves of the batch, and that the writer is a member using an `active` device.
  - Messages are accepted only at the current epoch.
  - The server orders and authorizes; it never parses or validates MLS. Every device validates the winning commit itself and rejects an invalid one.
- **Status:** Accepted for development · 2026-10-19. Emulator-tested only.

### D-089 — Message envelope and authenticated data
- **Decision:**
  - A message document carries `schemaVersion`, `protocolVersion`, `senderAccountId`, `senderDeviceId`, `epoch`, `ciphertext` and `serverTime`. Its ID is a 16-byte random message ID generated in Rust.
  - Rust builds the MLS AAD `"SirfHum-MessageAAD" | 1 | schema | protocol | conversation id | message id | sender device id`.
  - On receipt, Rust compares that AAD with the envelope fields and the authenticated sender, inside the rollback transaction (`envelope_mismatch`, -25).
  - The envelope epoch must equal the MLS message epoch.
  - `senderAccountId` is checked against the verified lineage.
- **Status:** Accepted for development · 2026-10-19.

### D-090 — Local encrypted message history
- **Decision:**
  - Sent and received messages are sealed core records (kind 5) in the account's slot directory, written in the same checkpoint as the MLS state change.
  - A queued message's ciphertext lives in the same record until the server accepts it.
  - Any persistence failure fails the operation. There is no plaintext fallback.
- **Status:** Accepted for development · 2026-10-19.

### D-091 — Ordering, past-epoch window, offline
- **Decision:**
  - Receivers process per epoch: all messages of epoch L, then commit L.
  - The server accepts messages only at the current epoch and moves the epoch atomically with the commit. The past-epoch window therefore stays **0**, which resolves D-060 for messaging.
  - The sender-ratchet out-of-order tolerance is 32 generations (the default is 5).
  - Messages are encrypted at compose time. After a stale-epoch refusal, the same message ID is re-encrypted from the sealed record.
  - No global or causal order is promised; display order is server time.
- **Status:** Accepted for development · 2026-10-19.

### D-092 — iOS is not part of the current product
- **Decision (owner, 2026-10-19):** Sirf Hum does not support, maintain or build iOS now.
  - Platform priority: **P0 Android**; **P1 Web** where it is already useful (Web V1 still has no private E2EE, D-046); **iOS: future, undecided**.
  - Whether to build iOS at all is evaluated only after the Android product is complete, secure, launched and validated: user demand, business case, cost and approach.
  - No iOS-specific features, fixes, compatibility work, optimisation or platform code, unless shared architecture strictly requires it.
  - **CI:** the iOS compile job, the iOS simulator integration job and the prototype iOS packaging job are removed. They are not merge gates and are not run.
  - **Kept, unmaintained:** the existing `ios/` project, the iOS Keychain adapter and the build hook's iOS targets stay in the repository as they are. They are not built, tested or promised. Removing or repairing them is a later decision.
  - **Not weakened:** every shared Rust, Dart, crypto, Firebase and security check still runs. Domain, security and crypto code stays platform-neutral where that is natural; no iOS abstraction layer is built in advance.
- **Supersedes:** D-073; the iOS part of D-003.
- **Risk accepted:** iOS breakage can go unnoticed (no CI). A future iOS version will need its own security work: Keychain adapter review, build hook, platform key store tests, push and store requirements.
- **Status:** Accepted · 2026-10-19

### D-093 — Media encryption construction (Prompt 11)
- **Decision:**
  - Media objects use **STREAM** (Hoang–Reyhanitabar–Rogaway–Vizár 2015, `aead 0.5.2` `StreamBE32`) over **XChaCha20-Poly1305**: 64 KiB chunks, 16-byte tag each, last-block flag, random 19-byte nonce prefix in a 25-byte header (`"SHMD" | format 1 | prefix`).
  - Every object has a fresh random 32-byte key and a random 16-byte media ID, both from the OS CSPRNG inside Rust.
  - The media AAD is built in Rust: `"SirfHum-MediaAAD" | 1 | schema 1 | conversation | media ID | sender device | class | plaintext length | header`. Following the published STREAM schedule, it is the AD of the **first** chunk only; every later chunk uses the empty AD (corrected before release, see below).
  - The SHA-256 of the whole object (header and every chunk with its tag) is carried in the MLS-authenticated `media_ref` and checked before any decryption. This is an *authenticated ciphertext digest*, **not** key commitment (D-093 review, F1).
  - Plaintext is limited to 64 MiB, and empty media is refused.
- **Dependencies:** no new crate. The change enables the `stream` feature of the already-pinned `chacha20poly1305 =0.10.1` and adds `sha2 =0.10.9` as a direct, exact-pinned dependency. `openmls_rust_crypto 0.6.0` already compiles that version. The D-054 pins are unchanged (`tool/check_crypto_core.sh`).
- **Supersedes:** the Prompt 04 recommendation of libsodium `crypto_secretstream` (E2EE-ARCHITECTURE §7). The properties are the same: chunked, per-chunk authentication, truncation detection. There is no second native crypto library. **Audit status:** no audit of `aead::stream` is known. libsodium's published 2017 audit (1.0.12–1.0.13) **predates** `crypto_secretstream` (added in 1.0.14), so it does not give the alternative an audit advantage for the stream construction either. *Corrected 2026-10-19 by the D-093 review (F2); the earlier text implied it did.*
- **Review brief:** E2EE-MEDIA-AND-NOTIFICATIONS §2, "D-093 review brief". It covers exact versions, the construction's source, audit status (none for `aead::stream`; NCC's 2020 review of `chacha20poly1305` predates 0.10.1 and did not cover it), properties, nonces, ordering, finalization, AAD, key lifecycle, size limits, and the custom composition around STREAM.
- **Investigation:** [D-093-SECURITY-REVIEW](../security/D-093-SECURITY-REVIEW.md) (2026-10-19). Engineering recommendation: *merge with specific security changes*, meaning documentation corrections F1 and F2 (applied) plus human sign-off. Pre-v2 follow-up: F3. This is not an approval.
- **F4 evidence pass (2026-10-19):** the paper was obtained (co-author's copy). `StreamBE32` matches its nonce encoding, final flag and state machine. **Deviation:** Sirf Hum passes the media AAD to every segment, while the paper's STREAM uses it on segment 1 only (ε afterwards), so Theorem 2 does not literally cover the implemented variant. No weakness found. Resolve by (a) review of the adapted reduction or (b) switching to the paper's AD schedule (review §13.6). **Sign-off blocked until then.**
- **F4 correction (option (b), 2026-10-19):** Sirf Hum's AD schedule now matches the paper. The media AAD goes on the first chunk only and the empty AD on every later chunk, so Theorem 2 applies directly and the adapted proof is no longer needed. This is a pre-production format correction: no compatibility mode, and old multi-chunk objects fail closed. Nothing was deployed. No change to the primitive, nonces, key handling, header, digest, `media_ref` or limits. Review §14.
- **Status:** **APPROVED FOR PRE-PRODUCTION IMPLEMENTATION** · 2026-10-19 (human security review, owner decision; PR #10 head `54ddce6`, CI run 39243698359 green). Proposed earlier the same day, pending that review.
  - **Human security review: completed.** It accepted the final STREAM AAD schedule (the media AAD on the first chunk, the empty AD on every later chunk), which follows the published STREAM construction (HRRV 2015, Fig. 8). It also accepted the implementation as having passed the required security and regression checks, and the documented residual risks for this pre-production stage.
  - **This approval does NOT mean:** that an independent security audit was completed; production E2EE certification; zero vulnerabilities; or approval for a production launch.
  - **`aead::stream` remains unaudited** (no known independent audit of the module or of `aead 0.5.2`). Sirf Hum's composition around it is also unaudited: the object format, media AAD, authenticated ciphertext digest and MLS key delivery.
  - **The broader Sirf Hum E2EE system remains subject to a future independent security review** (D-054 conditions; THREAT-MODEL unresolved risks).
  - **Production deployment remains blocked** until the production-readiness requirements are met: Blaze/deployment (D-025), the independent review, and the remaining open items.
  - **Residual risks accepted for pre-production (not removed):**
    - F3: the format version is not in the authenticated reference; required before any format v2.
    - F5: zeroization of media-key copies inside OpenMLS is not established.
    - F7: server-controlled upload metadata can cause a denial of service.
    - F8: no audit of `aead::stream` or of the composition.
    - F9: no end-to-end forged-reference test.
    - Also: exact media sizes are visible (E45), and XChaCha20-Poly1305 has no authoritative specification (expired IETF draft).

    See D-093-SECURITY-REVIEW §10 and §14.

### D-094 — Media keys never leave the core
- **Decision:**
  - The media key is delivered inside an MLS application message, the `media_ref` payload (kind 2, 107 bytes). That payload is built only by `send_media`; `send_message` refuses a caller-supplied kind 2.
  - On receipt the reference is strictly validated, sealed in history (D-090), and returned to Dart as a 43-byte **key-free view**. `history` returns the same view.
  - `open_media` takes the AAD fields from the history record of the authenticated message that delivered the key, so an object is bound to its conversation, media ID and **sender device**. Re-attribution by another member fails.
  - Media keys never cross the FFI (ABI v6).
- **Status:** Accepted for development · 2026-10-19.

### D-095 — Media storage model
- **Decision:**
  - Objects live at `conversations/{c}/media/{m}`: opaque IDs, `application/octet-stream`, custom metadata exactly `{sd: uploading device}`. There is no Firestore media document.
  - Storage rules: members read (`get`); nobody lists. Create-only, by an `active` device of the caller's own account in an `active` conversation, size 1..67,125,273 B. No update or delete. Membership and device status are checked with cross-service `firestore.get`.
  - The object is uploaded before its message. After a lost acknowledgement, the refused retry counts as uploaded only if the stored size and `sd` match this device.
  - Server deletion and retention are deferred.
- **Deployment:** needs a Storage bucket (Blaze, D-025) and the Storage service agent's Firestore read permission. Emulator-tested only.
- **Status:** Accepted for development · 2026-10-19.

### D-096 — Local media cache
- **Decision:**
  - The cache holds **ciphertext only**: `<account slot>/media/<conversation hex>_<media hex>.shm`, inside the backup-excluded slot and deleted with it.
  - The core names and writes outgoing objects atomically (temp, fsync, rename) before queueing the message, and deletes them if queueing fails.
  - `open_media` decrypts to memory only (≤ 64 MiB): two streamed passes, hash then decrypt. The app never writes media plaintext.
  - Downloads go to a temporary name and are size-checked against the authenticated reference before they enter the cache. An object that fails verification is deleted and downloaded once more, then reported `corrupted`.
  - A device that is no longer active refuses new downloads; content it already cached stays, as text history does.
- **Status:** Accepted for development · 2026-10-19.

### D-097 — Content-free push notifications
- **Decision:**
  - FCM messages are constant except for the device token and a kind: `data {v: '1', k: 'm' | 's'}`, Android-only options, no topics.
  - `m` (partner's new message): high priority, the generic notification "Sirf Hum" / "You have a new message", constant tag and collapse key, `visibility: private`.
  - `s` (silent sync): sent for own-device messages, commits and revocations.
  - No conversation, message, media, device or account IDs, and no names, counts, text, ciphertext or previews.
  - Firestore triggers (`notifyOnMessage`, `notifyOnCommit`, `notifyOnDeviceStatus`) read only routing fields and log counts only. They target only devices that are `active` at send time.
- **Deployment:** needs Functions and Eventarc (Blaze). Emulator-tested as pure functions with a recording FCM fake. Showing the notification on Android 13+ needs the POST_NOTIFICATIONS permission (UI, deferred).
- **Status:** Accepted for development · 2026-10-19.

### D-098 — Push token lifecycle with proof of possession
- **Decision:**
  - Tokens live in server-only `pushTokens/{deviceId}` (rules deny all client access).
  - Registering or clearing a token takes a single-use challenge bound to the token's hash (`requestPushTokenChallenge`). The device then signs it with its device key under the new proof purpose **`push_token` = 3** (D-070 format). `registerPushToken` verifies the proof against the stored certificate, in one transaction, for an `active` device.
  - One token maps to one device: registering a token removes it from any other device.
  - Revocation and every other move out of `active` delete the token at once (trigger). A revocation also wakes the remaining devices of the account and its partner, so they refresh lineage and remove the device from MLS (narrows E33).
  - Tokens FCM reports unregistered, or older than 60 days, are deleted.
  - Rate limit: `pushToken` 20 per hour per account.
- **Reason:** a Firebase session alone must not redirect or silence another device's wake-ups (E24 principle). Tokens are never identity.
- **Status:** Accepted for development · 2026-10-19.

### D-099 — Deferred media features
- **Decision:**
  - **Thumbnails and previews:** deferred. They will never be generated on the server. When added, they will be generated on device and encrypted as their own objects with D-093.
  - **Size padding:** deferred. Exact object sizes are visible; format v2 can add bucketed padding after a review of the scheme.
  - **EXIF stripping** (privacy from the *partner*; the server never sees EXIF in clear): media UI phase.
  - **Streaming playback** of objects over 64 MiB: deferred.
  - **Server-side retention and deletion:** deferred.
  - **Web:** no private media and no push registration (D-046).
  - **iOS:** excluded (D-092).
- **Status:** Accepted · 2026-10-19.
