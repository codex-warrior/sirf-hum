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
| D-106 | One server-authoritative, ID-free session state (`lib/session`) for auth + couple; widgets never construct it | Accepted (development) | 2026-10-19 |
| D-107 | `firebase_auth` for session observation/restoration and sign-out only; sign-in method still open (D-029) | Accepted (development); sign-in method **Open** | 2026-10-19 |
| D-108 | Entry routes outside a five-area shell; shell only for a paired session; bottom bar / rail, no drawer | Accepted (development) | 2026-10-19 |
| D-109 | Small design-system component set; honest entry states instead of sample data; web private-content notices | Accepted (development) | 2026-10-19 |
| D-110 | Bounded Firebase start-up wait; a failed start is "couldn't start", never "signed out" | Accepted | 2026-10-19 |
| D-111 | Together: ID-free finite state machine, activity list, realtime port with no identifiers; only supported activities start | Accepted (development) | 2026-10-20 |
| D-112 | No production Together backend or presence yet (privacy D-100/T10, device trust needs Functions); production wires none, fake is test-only | Accepted; backend design **Open** | 2026-10-20 |
| D-118 | Future and Us are one couple notebook carried as MLS application messages in the couple's conversation; `MessagingService.exclusive` serializes every feature on the conversation | Accepted (development) | 2026-10-20 |
| D-119 | Notebook payload v1 (kind 4: create / update / remove ops) and assembly rules (server order, last change wins, terminal remove, shared editing) | Accepted (development); **unreviewed** | 2026-10-20 |
| D-120 | Future and Us product model: four Future kinds, planned/done, never "missed"; story, little things, rituals, together since; V1 limits; no scores, streaks, reminders or calendars | Accepted (development) | 2026-10-20 |
| D-121 | Notebook client behaviour: one ID-free controller for Future and Us; no production backend yet; web fails closed | Accepted; backend wiring **Blocked** (D-107, D-025) | 2026-10-20 |
| D-122 | A person key (PIK) belongs to one device, ever: server `personKeyIndex` and a lineage rule rejecting chains where one PIK certifies two devices | Accepted (development); needs independent review | 2026-10-20 |
| D-123 | Android: no app data in OS cloud backup or device-to-device transfer | Accepted | 2026-10-20 |
| D-124 | CI/CD supply chain: actions pinned to commit SHAs, exact firebase-tools, inputs passed as env, npm audit gate for Functions | Accepted | 2026-10-20 |
| D-125 | Prompt 17 security review: findings, audit package and P0–P3 production-blocker classification are the release gate of record | Accepted | 2026-10-20 |
| D-126 | MLS PrivateMessages padded to 256-byte blocks (`padding_size`); the server learns lengths only to within a block | Accepted (development); needs independent review | 2026-10-20 |
| D-127 | Device-bound MLS commit authorization: commits, Welcomes and the epoch are server-written only after a device-key proof (purpose 5) over the commit's binding | Accepted (development); needs independent review | 2026-10-20 |
| D-128 | Partner identity verification: safety number + QR over both root PIKs; trust only by explicit confirmation; reported revocations always applied | Accepted (development); needs independent review | 2026-10-20 |
| D-129 | Rejecting a pending device needs an active device's proof (purpose 6) bound to the request | Accepted | 2026-10-20 |
| D-130 | `qr` + `mobile_scanner` (Android only, CAMERA permission) for the safety-number code; `crypto` direct | Accepted | 2026-10-20 |
| D-131 | Forced pairing-code comparison: only the invitee sees the code, the inviter enters it, 3 wrong codes end the pairing (amends D-101) | Accepted (development) | 2026-10-20 |
| D-132 | Content-free identity-reset alerts (kind `a`) to the account and, on completion, the partner | Accepted (development) | 2026-10-20 |
| D-133 | OSV-Scanner for Dart lockfiles in CI; GitHub secret scanning, push protection, Dependabot alerts and a `main` ruleset | Accepted | 2026-10-20 |
| D-134 | Unpairing needs its own security decision; not implemented | **Superseded by D-136** | 2026-10-20 |
| D-135 | Conversation recovery: an active device (proof purpose 7) retires a stalled conversation and re-provisions a new MLS group for the same couple; history kept, nothing re-sent | Accepted (development); needs independent review | 2026-10-21 |
| D-136 | Secure unpairing: either partner unilaterally, from an active device (proof purpose 8); couple dissolved, conversations closed, partner access ended | Accepted (development); needs independent review | 2026-10-21 |
| D-137 | Production launch gate: production deploys only through the Deploy workflow; Functions and Hosting to production refused until `config/launch_gate.json` is `open` (changed only by a reviewed PR after the launch gate passes) | Accepted | 2026-10-21 |
| D-138 | Production sign-in provider: email link (passwordless) as the only provider, with email-enumeration protection; Auth stays account identity, never device trust | **Proposed — needs owner approval**; nothing enabled | 2026-10-21 |
| D-139 | App Check production readiness: production web refuses to start without a reCAPTCHA site key; every callable must enforce App Check (static test); enforcement order and manual steps in APP-CHECK-PRODUCTION | Accepted (development); enforcement **not enabled** | 2026-10-21 |
| D-140 | Web origin headers: CSP as Report-Only (browser-tested locally), COOP, CORP, wider Permissions-Policy, no-cache for code entry points; pinned by `tool/check_web_headers.mjs` | Accepted; CSP enforcement **deferred** to the staging origin | 2026-10-21 |
| D-141 | Photo-picker cache sweep at start-up: only `cacheDir/<v4 UUID>/` directories holding regular files (image_picker_android's layout) | Accepted | 2026-10-21 |
| D-142 | Gradle dependency locking (release runtime classpaths, STRICT) scanned by OSV-Scanner; Gradle wrapper checksum; Dependabot version updates except Cargo and Gradle | Accepted | 2026-10-21 |
| D-143 | A production release is never silently debug-signed; Play App Signing and build provenance attestations required before production | Accepted; provenance **not built** | 2026-10-21 |
| D-144 | P3-15: `unpairCouple` authorizes (challenge, couple, device, proof) before listing or walking the couple's conversations | Accepted (development); needs independent review | 2026-10-21 |
| D-145 | Prompt 18 review readiness: PRODUCTION-LAUNCH-GATE is the launch gate of record (with D-125's blocker classes); the independent review package is the reviewer's entry point | Accepted | 2026-10-21 |

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

### D-100 — Account and couple model (Prompt 12)
- **Decision:**
  - The Firebase Auth UID is the only account identifier. There is no second account identity, and the UID is never a cryptographic identity.
  - `users/{uid}` holds a minimal profile: `displayName` only, plus version and server timestamps. The owner writes it under rules that check exact fields. The owner and, once paired, the partner read it. It carries no authority.
  - `couples/{coupleId}` (16 random bytes) holds exactly two sorted member UIDs, `status: 'active'`, `pairingId`, `createdAt` and `schemaVersion`. It is server-created only, and members read it.
  - V1 allows at most one active couple per account, enforced through `accountPartners/{uid}` (D-086).
  - Couple membership is never inferred from Firebase Auth. It grants only what the existing rules already allow to a partner.
- **Privacy:** no email, phone, contacts, location, presence, last-seen, activity or scoring fields (rules reject extra fields; tested).
- **Status:** Accepted for development · 2026-10-19. Design: [COUPLE-AND-PAIRING](../security/COUPLE-AND-PAIRING.md).

### D-101 — Two-consent pairing protocol and state machine
- **Decision:**
  - The inviter creates an invitation and receives a 128-bit server-generated token once. Only its SHA-256 hash is stored, and the hash is deleted on redemption or end.
  - The invitee accepts with the token, which moves the pairing to `claimed`, bound to the invitee's account and device, with a 6-digit comparison code. The inviter then **confirms that account**, which moves it to `accepted`, or rejects it.
  - States: `pending`, `claimed`, `accepted`, `rejected`, `cancelled`, `expired`, `invalidated`. The transition table in `functions/src/couple/state.ts` is enforced on every write. Terminal states never move.
  - Lifetimes come from the server clock only: 24 h to accept, then 24 h to confirm.
- **Reason:**
  - A bearer link alone would let whoever intercepts it pair with the inviter.
  - Requiring the inviter's confirmation of the specific claimant makes both consents explicit.
- **Deviations from Prompt 04:**
  - The token is generated on the server, not the device, which guarantees its entropy.
  - Adds the inviter's confirmation step.
  - PIK fingerprint verification stays a later UX step. The comparison code is a human check, not cryptographic verification.
- **Status:** Accepted for development · 2026-10-19. **Amended by D-131** (2026-10-20): only the invitee sees the code; the inviter enters it.

### D-102 — Every pairing step is signed by an active device (proof purpose 4)
- **Decision:**
  - Each step (`create`, `accept`, `confirm`, `reject`, `cancel`) needs a single-use challenge from `requestPairingChallenge`. The challenge is bound server-side to the step and its subject: nothing, the token hash, or the pairing ID.
  - The device signs it with its device key under the new D-070 proof purpose **`pairing` = 4**. The server verifies the proof against the stored certificate of an **active** device in the same transaction as the step.
  - Failed proofs count toward `verificationFailure`.
  - The step fails closed (`invalidated`) on any of these:
    - a pending identity reset on either account;
    - a changed identity epoch (D-082);
    - a bound device (the inviter's creating device or the invitee's accepting device) no longer active;
    - either account already paired.
- **Crypto-core change:** one additive enum value (`ProofPurpose::Pairing`, `DeviceProofPurpose.pairing`, `ProofPurpose.pairing`).
  - The proof format, the existing purposes, the ABI functions and version (v6), OpenMLS and every pin are unchanged.
  - An older native library would refuse purpose 4 with `InvalidInput` (fails closed). Native assets ship with the Dart code, so they always match.
  - Tests: the cross-purpose matrix in Rust, TypeScript and Dart.
- **Reason:** a Firebase session or password alone must never pair, accept, confirm or end a pairing. This uses the existing device trust mechanism, with no second trust system.
- **Status:** Accepted for development · 2026-10-19.

### D-103 — Pairing concurrency, enumeration resistance and rate limits
- **Decision:**
  - Server-only `pairingLocks/{uid}` holds the one open pairing per account. Every transition is one Firestore transaction over the pairing, both locks, both `accountPartners` records, both `accountTrust` records and the bound devices.
  - Locks are hints that are re-validated against the pairing they name, so stale locks never block.
  - Accepting another person's invitation supersedes (cancels) one's own *unredeemed* invitation. An invitation someone has already accepted is never replaced: `pairing_in_progress`.
  - Uniform failures:
    - `invitation_invalid` for every unusable token;
    - `pairing_not_found` for unknown pairings and for pairings of other accounts.
  - There is no account lookup, and clients cannot list `users`, `couples` or `pairings`.
  - Rate limits (per account, D-077 mechanism):
    - `pairing` 30/h (step challenges);
    - `pairingInvitation` 10/24 h;
    - `pairingRedeemFailure` 10/h, checked before a challenge is issued.
  - Rules deny every client access to `pairings` and `pairingLocks`.
- **Status:** Accepted for development · 2026-10-19.

### D-104 — Couple ↔ conversation binding
- **Decision:**
  - `confirmPairing` creates the couple and provisions its conversation and both `accountPartners` records in **one transaction**. It does this through `writeCoupleConversation`, extracted from Prompt 10's `provisionConversation`, whose behaviour and tests are unchanged and which is still not a callable.
  - The conversation and the partner records carry `coupleId`. The couple does not list conversations, so later conversations can reference the same couple without changing it.
  - MLS group membership is still devices, decided on device by MLS and lineage (D-085). The couple record authorizes server access only.
- **No change to:** MLS, Prompt 10/11 message, commit or media formats, the ABI version, or the messaging rules.
- **Status:** Accepted for development · 2026-10-19.

### D-105 — Deferred couple and pairing features
- **Decision:**
  - **Unpairing / couple dissolution:** deferred. It needs open decision 6 (shared history), MLS removal and rules for dissolved conversations. When built it must be unilateral and instant.
  - **Account deletion or disablement:** no flow exists yet. A disabled account's ID token can live up to 1 h, but every step still needs an active device proof. A deletion flow must end open pairings and dissolve the couple.
  - **Also deferred:**
    - pairing UI (link or QR, code comparison, profile editing);
    - partner PIK verification (safety numbers);
    - content-free pairing notifications;
    - a retention policy for ended pairing records.
  - **Deployment:** blocked on Blaze (D-025). Emulator-tested only.
- **Status:** Accepted · 2026-10-19.

### D-106 — Session state: server-authoritative, ID-free (Prompt 13)
- **Decision:**
  - One `SessionController` (Riverpod) in a new `lib/session/` module produces a sealed `SessionState`: starting, signed out, not paired, pairing (stage), paired (display names), unavailable (`unreachable`, `signInAgain`, `startFailed`).
  - The account comes from the `AccountSession` port. The couple comes only from `getPairingState` through the existing `PairingBackend`, read-only. A malformed or unknown answer, or no backend, is `unavailable`, never a state.
  - States hold no account, couple, pairing, conversation or device IDs, tokens or codes. Display names are re-validated with the rules' constraint and never logged.
  - Answers for an earlier account are dropped (generation counter). A failed refresh keeps the state on screen; a rejected sign-in always replaces it. Nothing is persisted locally.
- **Reason:** the UI is never the authorization boundary (D-100, D-103). A single producer makes "UI cannot manufacture a couple" testable, and an ID-free model makes leaking internal IDs on screen structurally impossible.
- **Alternatives considered:** reading `accountPartners` directly for couple state (rejected: duplicates server logic and would show "paired" without the pairing state machine); caching the last state on device (rejected: relationship metadata in insecure storage).
- **Status:** Accepted for development · 2026-10-19. Design: [APP-SHELL-AND-NAVIGATION](../architecture/APP-SHELL-AND-NAVIGATION.md).

### D-107 — Account session via Firebase Auth; sign-in method still open
- **Decision:** add `firebase_auth` (imported only by `lib/infrastructure`) for `authStateChanges` (restored session first) and sign-out. `AccountSession` is a port in `lib/security/account/`. No sign-in UI and no provider: D-029 still holds, and the method (email link or email/password are the intended baseline) is a product decision for the identity/pairing UI prompt. The welcome screen says sign-in is coming instead of offering a dead button.
- **Consequence:** a real build today can only reach the welcome screen. Paired, pairing and error screens are exercised by widget tests, on-device integration tests with fake ports, and a local preview harness that is never committed.
- **Status:** Accepted for development · 2026-10-19. Sign-in method: **Open** (before the identity/pairing UI prompt).

### D-108 — Navigation: entry routes + five-area shell
- **Decision:** `/start`, `/welcome` and `/pair` live outside a `StatefulShellRoute` with the five V1 areas (Home, Together, Moments, Future, Us). There is a bottom `NavigationBar` on compact windows and a `NavigationRail` from 600 dp, with no drawer or nested tabs. One pure redirect function sends every non-paired state to its entry route. Area deep links survive loading via `?from=`, and only exact area paths are honoured. Features receive navigation as callbacks and do not import the router.
- **Reason:** UX-PRINCIPLES rules 1–2 (zero learning curve, familiar bottom navigation). A user who is not paired never sees a broken Home.
- **Status:** Accepted for development · 2026-10-19.

### D-109 — Design-system components v1 and honest entry states
- **Decision:**
  - Components: `AppPage`, `AppSection`, `EmptyState`, `ErrorState`, `Skeleton`/`SkeletonBlock`, `Notice`, `CoupleMark`. Buttons are themed in `AppTheme`: one filled accent primary per screen, outlined and text otherwise, with touch-target heights.
  - No new colors or fonts: the identity phase still owns them (D-020).
  - Unbuilt areas show deliberate entry states ("… is on its way"), never sample data.
  - On web, screens that will hold private content say it opens in the phone app (D-046).
- **Status:** Accepted for development · 2026-10-19.

### D-110 — Bounded Firebase start-up
- **Decision:** `FirebaseBootstrap` waits at most 10 s for `Firebase.initializeApp`. On web this call also waits for Firebase Auth to restore its session from IndexedDB, and never returns where IndexedDB does not settle (seen in headless Chrome; also possible with blocked storage). Past the bound the status is `failed`. A configured build whose Firebase failed uses `UnavailableAccountSession`, so the user sees "Sirf Hum couldn't start", never a blank page and never "signed out".
- **Status:** Accepted · 2026-10-19.

### D-111 — Together: state machine, activities and realtime port (Prompt 14)
- **Decision:**
  - `TogetherController` (Riverpod) is the only producer of a sealed, ID-free `TogetherState`: unavailable, loading, idle, starting, waiting, invited, joining, active, ending, ended, failed.
  - It runs only for a paired session (D-106) and rebuilds from nothing on any session change. In-flight answers are dropped by a generation check.
  - Errors, vanished sessions and unknown activities fail closed.
  - `TogetherActivity` lists Time together, Call, Watch and Listen. Only activities in `TogetherBackend.supportedActivities` can start; the rest are shown as "Coming soon", never as buttons.
  - `TogetherBackend` (`watch`, `start`, `join`, `leave`) takes no identifiers. A real implementation derives the account and couple on the server and requires an active device.
- **Reason:** explicit states make every step visible ("No ambiguous spinner, no fake success"). An ID-free port makes "Together with an arbitrary account" impossible to express from the client.
- **Status:** Accepted for development · 2026-10-20. Design: [TOGETHER-ARCHITECTURE](../architecture/TOGETHER-ARCHITECTURE.md).

### D-112 — No production Together backend or presence yet
- **Decision:** production wires no `TogetherBackend`. The hub then shows every activity as not yet available, and presence as "isn't shared yet". The deterministic `FakeTogetherBackend` lives under `test/` only and cannot be imported by the app.
- **Reason:**
  - A server session or presence record contradicts D-100 (no presence or activity fields) and needs an abuse review (THREAT-MODEL T10).
  - Firestore rules cannot verify that the caller's device is active; that needs a device proof checked by a Function (Blaze, D-025).
  - Call, Watch and Listen additionally need LiveKit token minting and a media-E2EE decision.
- **Candidate directions (Open):**
  - Together signals as application messages in the couple's MLS conversation (no new server metadata beyond ciphertext);
  - or a reviewed server session record with presence controls and retention.
- **Status:** Accepted · 2026-10-20. Backend design: **Open**.


### D-113 — Moments are MLS application messages in the couple's conversation (Prompt 15)
- **Decision:**
  - A moment is its photos — kind-2 `media_ref` messages built only by the Rust core (D-094) — followed by one kind-3 **manifest** message built by Dart, all in the couple's existing conversation (D-104).
  - No new server schema, Security Rules, Functions, cryptographic primitive, crate or ABI version. Caption and memory date are private content: they exist only inside MLS ciphertext and the sealed history (D-089, D-090).
  - The couple binding is the server-provisioned conversation (ID from the pairing answer, bound into the MLS AAD, membership enforced by the rules). The creator binding is the manifest's MLS-authenticated sender device. No `coupleId` field exists in a moment.
  - `MessagingService` gains `queueMedia`, `queuePayload` (seal without uploading) and `discardQueued` (drop a never-sent queued message and its object); within one millisecond the outbox sends media first. `sendMedia` and `sendText` are unchanged.
- **Reason:** composing the existing trust, membership, encryption and outbox systems means Moments cannot weaken any of them, and no second security system exists.
- **Alternatives considered:** a Firestore moment document with a plaintext caption (rejected: private content on the server); an encrypted moment document outside MLS (rejected: a second key system); a dedicated moments conversation (rejected for V1: needs server provisioning, i.e. Functions and Blaze, and a second MLS group, for no security gain).
- **Status:** Accepted for development · 2026-10-20. Design: [MOMENTS-ARCHITECTURE](../architecture/MOMENTS-ARCHITECTURE.md).

### D-114 — Moment manifest format v1 and timeline rules
- **Decision:**
  - Payload: `version 1 | kind 3 | client time u64 | schema u16 = 1 | date (y u16, m u8, d u8; zero = none) | count u8 (1..8) | count × photo message id [16] | caption len u16 | caption UTF-8 (≤ 2,000 bytes, trimmed)`. Strict decode; unknown versions, kinds or schemas fail closed.
  - A manifest is shown only if each listed photo is an `image` media message from the **same sender device**, not claimed by an earlier moment. Otherwise the whole moment is unreadable. Photos not yet received are counted as missing.
  - V1 limits: 8 photos per moment, 64 MiB per photo (D-093), photos only (video deferred: playback without plaintext at rest).
  - No location, EXIF, dimensions, file names, MIME types, device or OS fields.
- **Status:** Accepted for development · 2026-10-20. **Unreviewed.**

### D-115 — Moments client behaviour
- **Decision:**
  - `MomentsController` is the only producer of an ID-free `MomentsState`; it runs only for a paired session, on a platform that may hold private content, with a backend, and rebuilds on any session change (generation check).
  - Local first, then `refresh` = `refreshTrust` (active device + lineage) → `sync` → `flushOutbox`. A device that is not trusted is `MomentsBlocked`: the timeline is dropped and decoded images are evicted.
  - Pages of 24 moments. Photos decrypt on demand, one at a time, at display size; bytes live in memory only and are wiped on dispose; failed photo loads are never retried automatically.
  - Saving seals every part before anything is uploaded; any failure before the manifest is sealed discards everything; a permanent refusal after sealing (not a member, device not trusted) discards what the server has not taken and reports the failure. A transient failure after sealing (offline: transport or device registry unreachable) is `savedOnPhone`. Otherwise the outcome is `saved`, never a duplicate.
  - A chat view of the conversation must omit `momentProtocolMessageIds` (every manifest and every claimed photo).
  - Detail and the new-memory flow are pushed pages: no moment is ever in a URL.
- **Status:** Accepted for development · 2026-10-20.

### D-116 — No production moments backend yet; deletion and editing deferred
- **Decision:**
  - Production wires no `MomentsBackend` (`momentsBackendProvider` is `null`): there is no sign-in method (D-107), device activation is not deployed (Blaze, D-025), and no `MessagingService` is wired for the paired account. Moments then shows an honest entry state. The fake backend lives under `test/` only.
  - **Deletion is not offered.** It cannot be truthful yet: the rules forbid deleting objects and messages, server deletion needs a Function (Blaze) and a retention decision, and keys already on the partner's device cannot be recalled. A local-only "delete for me" would look like deletion while the moment remains elsewhere.
  - **Editing is not offered:** a second manifest would claim the same photos, which the timeline refuses by design. Both need a product and security design.
- **Status:** Accepted · 2026-10-20. Backend wiring: **Blocked** (D-107, D-025).

### D-117 — System photo picker (`image_picker`) and EXIF
- **Decision:** add `image_picker` (flutter.dev), used only by `features/moments/data/system_photo_picker.dart` and wired in `main.dart` on every platform except web (Android is the only target, D-092; iOS is not built). On Android 13+ it is the system Photo Picker: no storage permission, and the app sees only the chosen photos. The plugin's temporary copies (plaintext, app-private cache) are read only inside the core and deleted when the composer goes away, after any save still reading them. No resizing or re-encoding (it would write more plaintext files).
- **EXIF:** stays inside the encrypted photo; the server never sees it, but the partner's device receives it, including any location. Stripping before encryption needs on-device re-encoding without plaintext at rest; deferred and tracked (E68).
- **Status:** Accepted for development · 2026-10-20.

### D-118 — Future and Us are one couple notebook in the MLS conversation (Prompt 16)
- **Decision:**
  - Future's plans and Us's story, little things, rituals and "together since" are **one notebook** with five sections. Each change is one kind-4 MLS application message built by Dart in the couple's existing conversation (D-104), as a moment's manifest is (D-113).
  - No new server schema, Security Rules, Functions, cryptographic primitive, crate or ABI version. Titles, notes, details and dates are private content: only inside MLS ciphertext and the sealed history (D-089, D-090).
  - The couple binding is the server-provisioned conversation; the author binding is the MLS-authenticated sender device. No `coupleId`, account or device field exists in a record.
  - `MessagingService.exclusive` serializes state-changing operations (trust refresh, sync, seal, flush) of **every** feature on the conversation. `MomentsService` now uses it instead of its own queue, so a notebook sync can never interleave with a moment being sealed.
- **Reason:** composing the existing trust, membership, encryption and outbox systems means Future and Us cannot weaken them, and no second couple, trust, crypto or authorization model exists. The lock closes a race that appears as soon as a second feature shares the conversation.
- **Alternatives considered:** Firestore documents per plan or profile field (rejected: plaintext private content on the server, or a second key system if encrypted outside MLS); a dedicated conversation (rejected for V1: needs Functions and Blaze for provisioning and a second MLS group, for no security gain); phone-only storage (rejected: not shared).
- **Status:** Accepted for development · 2026-10-20. Design: [FUTURE-AND-US-ARCHITECTURE](../architecture/FUTURE-AND-US-ARCHITECTURE.md).

### D-119 — Notebook payload v1 and assembly rules
- **Decision:**
  - Payload: `version 1 | kind 4 | client time u64 | schema u16 = 1 | op u8 (create, update, remove) | target record id [16] (zero for create) | section u8 | category u8 | status u8 | date (y u16, m u8, d u8; zero = none) | title len u16 + UTF-8 | note len u16 + UTF-8 | detail len u8 + UTF-8`. Strict decode; values must be valid for the section; a remove carries no content.
  - A record's ID is the message ID of its create (chosen by the core).
  - Assembly in server order (server time, else local time for a queued change, then message ID): `update` replaces every field of a live record of the same section (last change wins); `remove` is terminal; changes to an absent record do nothing; a wrong-section change or an undecodable payload is counted as unreadable.
  - Either partner may change or remove any record (shared, like a paper notebook). Authorship is shown, not enforced.
  - Remove hides a record on both phones. It is **not erasure**: earlier versions stay sealed in each phone's history and as ciphertext on the server until a retention design exists.
  - A chat view must omit `notebookProtocolMessageIds`.
- **Reason:** append-only MLS messages cannot be edited, so edits are operations; deterministic ordering makes both phones converge without a server-side merge.
- **Status:** Accepted for development · 2026-10-20. **Unreviewed.**

### D-120 — Future and Us product model and V1 limits
- **Decision:**
  - Future kinds: plan, place, something to try, important date. Status: planned / done. Any real day is allowed and a passed day is never "missed"; important dates are single days with no recurrence.
  - Future files plans as Coming up / by kind / Important dates / Done together.
  - Us: couple names (session), "together since" (one date), Our story (named parts with optional date), Our little things (eight kinds, including "another little thing"), Rituals (name, free-text "how often", note), Important dates (Future's important-date records), sign-out.
  - Live-record limits: Future 200, story 12, little things 30, rituals 12, together-since 1.
  - No relationship scores, streaks, progress, reminders, calendar, recurrence, external calendars, time zones, location, presence, monitoring, AI analysis, public profiles, likes, followers or feeds.
- **Reason:** PRODUCT-CONSTITUTION and UX-PRINCIPLES: a private home for two, not a productivity tool or social profile. Small controlled sets keep the format closed and the UI calm.
- **Status:** Accepted for development · 2026-10-20.

### D-121 — Notebook client behaviour; no production backend yet
- **Decision:**
  - `NotebookController` is the only producer of an ID-free `NotebookState` (unavailable, loading, ready, blocked, failed), shared by Future, Us and Home. It runs only for a paired session, on a platform that may hold private content, with a backend; it rebuilds on any session change and drops late answers and late writes (generation check). Writes go only through it, only while ready.
  - Local first, then `refresh` = `refreshTrust` → `sync` → `flushOutbox`. A device that is not trusted is `blocked`: entries dropped, writes refused.
  - One editor for every section, as a pushed page (never a URL): Save in the app bar, single flight, cannot be left mid-save.
  - Production wires no `NotebookBackend` (`notebookBackendProvider` is `null`), for the same reasons as D-116; Future and Us show honest entry states. The fake backend lives under `test/` only.
  - Web shows the shells, names and sign-out, never the notebook (D-046).
- **Status:** Accepted · 2026-10-20. Backend wiring: **Blocked** (D-107, D-025).

### D-122 — A person key belongs to one device, ever (Prompt 17)
- **Problem (Prompt 17 finding P17-01):** D-074 gives every device its own PIK and D-085 says a PIK certifies exactly one device ID, but nothing enforced it end to end:
  - the server indexed device IDs and device keys (D-069), not person keys;
  - `approve_device` refuses a revoked PIK only when the approver *already knows* of the revocation;
  - the lineage verifier rejected duplicate device IDs, not a PIK certifying a second device.

  So a revoked device's retained PIK could certify a fresh device ID that an approver who had not refreshed lineage approved; the server activated it. Peers' MLS trust skipped it (revoked PIK), but the static `verifyLineage` listed it as proven, and devices *it* approved became lineage-trusted. After an identity reset, the old root's PIK could also root the new identity.
- **Decision:**
  - **Server:** a server-only `personKeyIndex/{sha256(PIK)}` is created in the same transaction as every activation (bootstrap, approval, recovery), next to `deviceIdIndex` and `deviceKeyIndex`. Registration and activation refuse a PIK that was ever activated, in any account, with the existing `duplicate_device`.
  - **Device (Rust lineage):** a chain in which one person key certifies two devices is `trust_chain_invalid` as a whole, like a duplicate device ID.
  - No format, ABI, statement, primitive or pin changes. Golden vectors are unaffected (each vector device has its own PIK).
- **Why fail the whole chain:** an honest server can no longer produce one, so such a chain means server misbehaviour; every other lineage defect already fails closed.
- **Tests:** Rust `a_revoked_pik_cannot_return_through_an_unaware_approver` (fails on the old verifier); emulator `person key uniqueness (Prompt 17, D-122)` (4 tests, each fails on the old server code); rules: `personKeyIndex` is client-unreachable.
- **Status:** Accepted for development · 2026-10-20. Needs independent review with the rest of the lineage design.

### D-123 — No app data in OS backups or device transfers (Android)
- **Problem (P17-02):** the manifest left Auto Backup on (the default) with no extraction rules. The crypto slots were already safe (`noBackupFilesDir`, D-066; a copied wrapped key is useless without this phone's Keystore), but the Firebase Auth session (shared preferences) and the Firestore offline cache (relationship metadata, device directory, ciphertext) could go to Google cloud backup or to a new phone by device-to-device transfer.
- **Decision:** `android:allowBackup="false"` and `android:fullBackupContent="false"` (Android ≤ 11: cloud and adb backup), plus `android:dataExtractionRules` excluding every domain for both `cloud-backup` and `device-transfer` (Android 12+, where transfer ignores `allowBackup`).
- **Consequence:** a new or restored phone starts signed out and is a new device (D-071): it is approved by a trusted device or the recovery key. This was already the trust model; the change removes the restored *session*, which was never trust.
- **Not claimed:** protection from a rooted device or from the OS vendor; this governs only the app's backup participation.
- **Status:** Accepted · 2026-10-20. Verified by the CI Android builds (manifest merge); no on-device backup test exists.

### D-124 — CI/CD supply-chain hardening
- **Problem (P17-03, P17-04):** workflow actions were referenced by mutable tags (`@v4`, `@v2`) and one by a branch (`dtolnay/rust-toolchain@master`); `firebase-tools` was installed unpinned in the job that holds deploy credentials; the production gate spliced the free-text `confirm` input into a shell script.
- **Decision:**
  - every action is pinned to a full commit SHA, with the version as a comment; pins are updated deliberately, in a PR;
  - `firebase-tools` is pinned to an exact version in CI and Deploy;
  - workflow inputs reach shell steps only as environment variables;
  - the Functions CI job runs `npm audit --omit=dev --audit-level=low`, the npm counterpart of `tool/crypto_audit.sh` (D-068), for the code that runs on the server.
- **Not covered (tracked in the Prompt 17 blocker list):** branch protection and GitHub secret scanning are repository settings (owner action); Dart and Gradle dependencies have no advisory gate yet.
- **Status:** Accepted · 2026-10-20

### D-125 — Prompt 17 security review and production-blocker classification
- **Decision:** the Prompt 17 review ([audit package](../security/audit/README.md)) is the security baseline of record:
  - the security-gap matrix and findings P17-01…P17-19 ([PROMPT-17-SECURITY-REVIEW](../security/audit/PROMPT-17-SECURITY-REVIEW.md));
  - the P0–P3 classification ([PRODUCTION-BLOCKERS](../security/audit/PRODUCTION-BLOCKERS.md)): no production security claim while any P0 is open, and no production E2EE while any P1 is open;
  - the threat-model status table (THREAT-MODEL, "Prompt 17 status review").
- **Changes made:** D-122, D-123, D-124, D-126 and documentation corrections. No primitive, statement format, ABI or pin changed; D-126 sets a standard MLS framing option.
- **Not a claim:** this is an internal engineering review. It is not an independent audit and does not make Sirf Hum production E2EE.
- **Status:** Accepted · 2026-10-20

### D-126 — MLS message padding (Prompt 17)
- **Problem (P17-19):** THREAT-MODEL E2/E12 and E2EE-ARCHITECTURE §8 listed "padded sizes" as a mitigation, but the core never set OpenMLS `padding_size`, whose default is 0. Every PrivateMessage therefore revealed its exact content length to the server: a text message, a moment caption, a notebook record. Measured: "ok" and a 150-byte payload gave 219- and 368-byte ciphertexts.
- **Decision:** both group configurations (create and join) set `padding_size = 256`. Each device pads what it sends; RFC 9420 §6.3.1 zero padding, stripped by every receiver, so the wire format, ABI and interoperability are unchanged. It applies to application messages and to handshake messages (D-055).
- **Bounds:** payloads stay ≤ 16 KiB and ciphertexts ≤ 32 KiB (`MAX_MESSAGE_CIPHERTEXT_BYTES`, rules) with ≤ 255 added bytes. Groups created before this change keep their stored configuration (development only; nothing is deployed).
- **What it is not:** length *hiding*. The server still learns the length to within 256 bytes, the message count and timing. Media objects are a separate format with exact sizes (E45, D-099). A finer scheme (e.g. Padmé buckets) would need custom padding and review.
- **Tests:** `ciphertext_length_hides_the_message_length_within_a_block` (creator and joiner; fails without the change).
- **Status:** Accepted for development · 2026-10-20. Needs independent review with the rest of the MLS configuration (D-054).

### D-127 — Device-bound MLS commit authorization (Prompt 17B)
- **Problem (P17-05, high):** clients wrote `commits/{epoch}`, the Welcomes and the epoch move themselves, and the rules could only check the account. Any Firebase session of either partner (a password thief, a session left on a revoked or stolen phone) could win an epoch with bytes no device can process: every device then failed closed and the conversation stalled permanently.
- **Decision:**
  - The rules deny every client write to `conversations/{c}` (including `epoch`), `commits/*` and `welcomes/*`. Members still read them.
  - Two callables are the only writers: `requestCommitChallenge` (single-use 32-byte nonce bound to account, device, conversation and `fromEpoch`; 5 minutes; rate limit `commit` 60/h) and `submitMlsCommit`.
  - The device signs, with its **device key** and the D-070 proof format under the new purpose **`commit` = 5**, a challenge derived from the nonce and the commit's binding: `SHA-256("SirfHum-CommitAuthorization-v1" | 1 | nonce | len|account | device | conversation | fromEpoch | toEpoch | protocol | SHA-256(commit) | SHA-256(n | n × (target | SHA-256(welcome))))`.
  - In one transaction the server checks the challenge (account, device, purpose, conversation, epoch, expiry; consumed whatever the outcome), the device (`active` now, of the caller's account), the conversation (active, caller a member), the proof against the stored certificate, and only then first-commit-wins (epoch unchanged, no commit yet). It writes the commit (sender from the verified values), the epoch move and the Welcomes together.
  - The server hashes opaque bytes and never parses or decrypts MLS. Staged-commit semantics are unchanged (stage → submit → confirm/discard by the server's `commits/{epoch}`).
- **Reuses:** the device certificate, the device-proof format and the challenge pattern of D-070, D-098 and D-102. No new primitive, statement format, ABI function or pin; one additive proof purpose (an older native library refuses it: fails closed).
- **What it does not stop:** a *trusted, active* device (a modified partner client, or a compromised phone) can still commit something the others reject. Recovery: see "Conversation recovery" below.
- **Conversation recovery (design, not built):** when devices hold `stateDiverged` for the current epoch, any active member device may call a future `reprovisionConversation` with the same device-bound authorization. In one transaction the server marks the conversation `retired`, creates a new conversation for the same couple (new ID = new MLS group, epoch 0) and points both `accountPartners` records at it. Devices keep the old history locally (sealed), start the new group from verified lineage, and show "Your conversation was restarted". Abuse bound: a rate limit per couple, and an abusive partner who keeps stalling is an unpairing case (D-134). Needs its own review; P1 until built.
- **Tests:** emulator `device-bound commit authorization (D-127)` (9); rules `commits, Welcomes and the epoch are server-only (D-127)` and the flipped documented-limit test; Functions unit `commit authorization v1` (vector, every bound field, malformed); Dart golden vector; Dart native (CI) password-only / wrong device / revoked / replay / refused-never-advances / cross-account.
- **Status:** Accepted for development · 2026-10-20. Needs independent review. Deployment needs Blaze (D-025).

### D-128 — Partner identity verification: safety number and QR (Prompt 17B)
- **Problem (P17-09, high):** nothing in the app could anchor a partner's root person key, so messaging could not start in production, and a future UX risked silent trust-on-first-use of server data.
- **Decision:**
  - **What is verified:** each person's **root PIK** (the anchor of their signed lineage, D-084/D-085) bound to their account. Every other device of a person is trusted only by signatures from that root, so one comparison covers devices added later.
  - **Safety number:** `fingerprint = SHA-256("SirfHum-SafetyNumber-v1" | 1 | len|account | len|root PIK)`; 30 digits per person (six 5-byte chunks, each mod 100000), the account that sorts first first: 60 digits, 12 groups, identical on both phones. **QR:** `SHSN1:` + upper-case hex of both 32-byte fingerprints (QR alphanumeric mode).
  - **Trust changes only by explicit confirmation:** "The numbers match" (after a confirmation dialog) or a scanned code equal to the shown number anchors the partner's root (`trustVerifiedPersonKey`, sealed in the core, survives restarts), and only if the server still presents that same root (`changedWhileShown` otherwise).
  - **Status is computed, never stored apart from the core:** verified = the partner's current lineage applies from an anchored root whose root device is still trusted. A new root (reset, substitution) is not anchored → "Not verified"; a revoked root can never be anchored again.
  - **Own root:** a device anchors its own account's root automatically only from a lineage that proves the device itself (a chain containing this device can only descend from this person's real root).
  - **Revocations always land:** when a partner's lineage cannot be applied, every device the server reports `revoked` is revoked locally (only removes trust). This closes a gap: an identity reset's revocations previously reached peers only after the new identity was verified.
  - **UI:** Us → Safety → "Safety number" (Verified / Not verified) → a pushed page with the number, the code, "The numbers match", "Scan their code", "They don't match". Web says it happens on the phone. Production wires no backend yet (D-116), so it shows an honest "on its way" state.
- **Not claimed:** verification does not make Sirf Hum production E2EE or audited; it authenticates the partner's identity key only.
- **Tests:** safety-number format (7); controller and screen (13, incl. sign-out and account switch during async work, wrong QR, mismatch, changed while shown, revoked); native service (10, CI): correct verification, wrong QR, server substitution, new device, changed identity, revoked root, restart, account switch, unavailable partner.
- **Status:** Accepted for development · 2026-10-20. Needs independent review (number construction, own-root rule).

### D-129 — Rejecting a pending device needs a trusted device (Prompt 17B)
- **Problem (P17-07):** `rejectDeviceApproval` accepted a Firebase session alone: a password thief could permanently block the owner's new devices (terminal `rejected`), against D-081's principle.
- **Decision:** the rejecter must be an **active** device of the account and sign a single-use challenge (`issueDeviceChallenge` purpose `approval_rejection`, bound to the request ID) with its device key under the new proof purpose **`approval_rejection` = 6**. Failed proofs count toward the shared failure budget; challenges are rate-limited at issue. Pending, revoked and other accounts' devices cannot reject.
- **Tests:** emulator `rejection needs a trusted device (D-129)` (2) and the updated rejection tests; Dart trust-service test (native).
- **Status:** Accepted · 2026-10-20

### D-130 — QR rendering and scanning dependencies (Prompt 17B)
- **Decision:** `qr` 4.0.0 (pure Dart, renders the code in the design-system `ScannableCode`, always dark-on-light) and `mobile_scanner` 7.4.2 (Android CameraX + on-device ML Kit barcode reading; frames never leave the phone). `mobile_scanner` is imported only by `features/verification/data/camera_qr_code_scanner.dart` and wired in `main.dart` on Android only. It adds the `CAMERA` permission to the merged Android manifest, requested only when the person taps "Scan their code".
- **Also:** `crypto` (dart-lang, already locked transitively) became a direct dependency for SHA-256 (D-127, D-128).
- **Status:** Accepted · 2026-10-20

### D-131 — Forced pairing-code comparison (amends D-101)
- **Problem (P17-08):** `getPairingState` gave the inviter the same code the claimant saw and `confirmPairing` took no code, so confirming did not prove any comparison happened; an intercepted link plus a careless inviter paired a stranger.
- **Decision (amends D-101):** only the **invitee's** phone shows the six-digit code. The inviter must **enter** the code the invitee reads out; `confirmPairing` requires it, compares in constant time, and after **3** wrong codes invalidates the pairing (`confirmation_code_mismatch`, locks released, code deleted). A wrong code returns `confirmation_code_invalid`. The Dart client refuses a malformed code without a server step and treats a server that hands the inviter a code as broken.
- **Still true:** the comparison is a human check, not cryptographic verification; the partner's identity is authenticated by D-128.
- **Tests:** emulator `forced code comparison (D-131)` (5: intercepted invitation, three wrong codes, one mistake allowed, malformed codes, invitee cannot confirm); Dart parse and service tests.
- **Status:** Accepted for development · 2026-10-20

### D-132 — Content-free identity-reset alerts (Prompt 17B)
- **Problem:** D-082 left reset notifications OPEN: a reset requested with only the password raised no signal.
- **Decision:** a Firestore trigger on `accountTrust/{uid}` reads only the reset status and sends the new constant kind `a` (visible: "Sirf Hum" / "Review a security change", its own notification slot, `visibility: private`, no IDs):
  - reset **requested** → every active device of the account (so it can be cancelled from any trusted phone);
  - reset **completed** → the partner's active devices (they must verify the new identity, D-128);
  - reset **cancelled** → the account's devices sync silently.
- **Tests:** payload unit test; emulator `identity reset alerts (D-132)` (3); the static guards (reads only `reset`, logs counts only).
- **Status:** Accepted for development · 2026-10-20. Deployment needs Blaze (Eventarc).

### D-133 — Dependency advisories for Dart and GitHub security controls (Prompt 17B)
- **Decision:**
  - CI job `dart-advisories` runs OSV-Scanner 2.6.0 (checksum-verified, pinned) on `pubspec.lock` and the crypto package's lockfile. Rust keeps `cargo audit` with its three documented, re-verified ignores (D-068); Functions keep `npm audit` (D-124).
  - Gradle has no lockfile, so it is covered only by GitHub's dependency graph and Dependabot alerts until Gradle dependency locking is adopted.
  - On the public repository the owner authorized enabling GitHub secret scanning, push protection, Dependabot alerts and a ruleset on `main` (PR required, required status checks, no force-push or deletion). Repository privacy is not a security boundary.
- **Status:** Accepted · 2026-10-20

### D-134 — Unpairing needs its own security decision (Prompt 17B)
- **Decision:** unpairing is **not implemented** in Prompt 17B. It must be unilateral and instant (T10), and that touches decisions not yet made: what happens to shared history (open decision 6), MLS removal of the other person's devices versus retiring the conversation, rules for a dissolved couple, re-pairing (a new group, never reused, D-044), content-free notification to the other person, and the account-deletion flow (D-105). A rushed version would risk an account-takeover path (a password alone dissolving a couple) or silent retention.
- **Required properties for the future decision:** device-key authorization (as D-127), no password-only path, server-side end of access for the other account, MLS removal or retirement, honest copy about what the partner keeps.
- **Status:** **Superseded by D-136** (2026-10-21). Was Open · 2026-10-20.

### D-135 — Conversation recovery: retire and re-provision (Prompt 17C)
- **Why:** since D-127 only an active device's key can move a conversation's epoch, but a *trusted* device (a bug, a modified partner client, a compromised phone) can still win `commits/{e}` with a commit the other devices cannot process. Every device then fails closed (`stateDiverged`) and the conversation stalls with no way forward. MLS has no "undo" for an accepted epoch, and the server never parses MLS, so the only sound recovery is a **new MLS group** for the same couple.
- **Authorization:** callables `requestRecoveryChallenge` and `recoverConversation`. The device signs, with its **device key** and the D-070 proof format under the new purpose **`conversation_recovery` = 7**, the derived challenge
  `SHA-256("SirfHum-ConversationRecovery-v1" | u8 1 | nonce[32] | u32 len | account | device id[16] | conversation id[16] | stalled epoch u64 BE | account trust epoch u64 BE)`.
  The nonce is single-use, 5 minutes, bound server-side to (account, device, purpose, conversation, epoch, trust epoch). Rate limit `conversationRecovery` 3 per 24 h per account. A Firebase session alone, a revoked, pending or unknown device, or another account cannot recover.
- **State transition (one transaction):** the server checks the challenge (consumed whatever the outcome), the device (`active`, caller's account), the caller's account trust epoch **equals** the signed one (a trust change in between refuses: recovery never acts on a stale trust view), the conversation (`active`, caller a member, epoch **equals** the signed one, and it is the couple's **current** conversation per both `accountPartners` records), the couple (`active`) and the proof. Then:
  - old conversation → `state: 'retired'`, `successorId`, `retiredAt`, `retiredByDeviceId`; it accepts no more writes (no messages, commits, key packages, media);
  - new conversation: new random ID (= new MLS group ID), same members, couple and pairing, `epoch: 0`, `generation` = old + 1, `predecessorId` = old;
  - both `accountPartners` records point at the new conversation.
- **Each device:** sees the old conversation `retired` (sync/send fail with `retired`), follows `successorId` only if the successor names it as `predecessorId` (no jumping to an unrelated or older conversation), publishes a fresh KeyPackage there and joins or creates the new group exactly as for a new couple: membership from verified lineage only (D-085), so revoked or unverified devices are never added. Trust state is unchanged (recovery is not a trust event).
- **Existing encrypted history:** untouched. Each phone keeps the old conversation's sealed history and can still show it; server ciphertext of the retired conversation stays readable by the members (it was always theirs) and is never decrypted or rebuilt by the server.
- **Pending messages:** messages queued in the old conversation stay sealed on the phone, marked not sent; they are **never** silently re-sent into the new group (that would be a new send the person did not make). The app can offer to send them again.
- **Offline devices:** on reconnect they find `retired` and the successor; their old MLS state is untouched.
- **Replay and cross-conversation use:** challenges are single-use and bound to one conversation, epoch and trust epoch; a retired conversation and its epoch never qualify again; the new conversation has a new group ID, so an old (broken) commit cannot be replayed into it (different group, and the commit path is server-only).
- **States the app distinguishes:** normal commit (accepted); rejected commit (`WriteOutcome.refused`); stalled conversation (`MessagingFailure.stateDiverged`); recovery requested (`MessagingService.recover()`); recovery completed (successor `ConversationId` returned, log `messaging_conversation_recovered`, server audit `conversation_recovered`; old conversation `retired` → `MessagingFailure.retired`, `MessagingService.successor()`); recovery failed (`TransportException` / `MessagingException` category; nothing changed).
- **Failure behaviour:** any check fails → nothing changes and a category is returned (`conversation_changed` when the epoch or trust epoch moved or the conversation is no longer current, `conversation_unavailable`, device and proof categories).
- **Abuse bound:** a trusted partner device can retire the conversation; that is a denial of service it could cause anyway (it can stall), bounded by the rate limit and resolved by unpairing (D-136).
- **Status:** Accepted for development · 2026-10-21. Needs independent review. Deployment needs Blaze.

### D-136 — Secure unpairing (Prompt 17C; supersedes D-134)
- **Who:** **either partner, unilaterally**, from one of their own **active** devices. Requiring the other's consent would let an abusive partner hold someone in the relationship (T10); so leaving needs no consent, only proof that it is really that person's trusted phone.
- **Authorization:** `requestUnpairChallenge` + `unpairCouple`; device proof purpose **`unpair` = 8** over `SHA-256("SirfHum-Unpair-v1" | u8 1 | nonce[32] | u32 len | account | device id[16] | couple id[16])`. A password or Firebase session alone **cannot** unpair (no stolen-password path to destroy the relationship); a revoked, pending or unknown device cannot; a challenge for one couple cannot end another. Rate limit `unpair` 5 per 24 h.
- **What happens (one transaction):** the couple → `status: 'dissolved'` (`dissolvedAt`, `dissolvedByDeviceId`; the ID is never reused); every conversation of the couple (active or retired) → `state: 'closed'`; both `accountPartners` records are deleted.
- **Consequences:**
  - *Removed partner's devices:* stay trusted **on their own account** (device trust is per account); they lose all access to the couple: the rules deny reads of a closed conversation's documents and media, and partner reads (profile, device directory) end with `accountPartners`.
  - *Shared history:* each phone keeps what it already decrypted, sealed in its own history; it cannot be recalled from the other phone (stated plainly in the product). Server ciphertext is retained, unreadable by clients, until a retention decision (P2-8).
  - *Future messages:* none: a closed conversation accepts no writes, and its MLS group never gets another epoch.
  - *Moments, Future + Us:* they live in the conversation, so the same as history.
  - *Pending invitations:* none can exist while paired (one couple per account); after unpairing either account may invite anyone.
  - *Recovery keys and devices:* unaffected (account-level).
  - *Reinstall:* a new device of the same account; no couple.
  - *Re-pairing:* only through the full two-consent flow (D-101, D-131) with a new couple, conversation and MLS group (D-044). The old couple never comes back.
  - *Reversible:* no.
  - *Notifications:* silent content-free sync wake-ups to the active devices of both accounts, so both apps update; no visible alert naming the event (safety: the leaving person decides what to tell the other).
- **Concurrency:** one transaction over the couple, both partner records and every conversation of the couple. The conversation IDs are listed outside the transaction (a collection query inside it would lock the whole range) and each conversation is then read **in** the transaction; completeness comes from following the partners' current conversation back through `predecessorId`, since any conversation created after the listing is a recovery successor that the partner records point to. If the walk reaches its bound with conversations still unread, the transaction **fails closed** (nothing written) rather than dissolve with one missed. The listing is injectable (`unpairCouple(…, list)`) so tests can simulate a conversation created after it. A racing recovery writes those partner records and so forces a retry; a racing commit, recovery or pairing step that commits later sees the dissolved couple, the closed conversation or the missing partner record and fails closed (emulator tests: concurrent unpair, unpair vs recovery, vs pairing, vs device approval).
- **Client:** `PairingService.unpair(account, coupleId)`: the device key signs inside the Rust core; a malformed couple ID or another account never reaches the server.
- **Status:** Accepted for development · 2026-10-21. Needs independent review (abusive-partner review in particular). D-134 is superseded.

### D-137 — Production launch gate and deploy lock (Prompt 18)
- **Problem:** the Deploy workflow already required `main`, a typed confirmation and WIF credentials bound to repository + `production` environment + `main`, but nothing tied a production deploy to the launch gate, and `tool/deploy.sh` still accepted a production deploy from a laptop with owner credentials. Once Blaze is enabled, one manual run could open production to traffic before the review.
- **Decision (`tool/deploy.sh`, mirrored in `.github/workflows/deploy.yml`):**
  - production deploys run only inside GitHub Actions (`GITHUB_ACTIONS=true`); a local production deploy is refused. A guard against accidents, not against the owner: the credentials themselves come only from WIF for the workflow on `main`;
  - an **allowlist**: with the gate closed, production accepts only `firestore`, `firestore:rules`, `firestore:indexes` and `storage` (rules only restrict access). Every other target, however spelled (whitespace, `functions:<name>`, `extensions`, combined lists), is refused;
  - the gate is `config/launch_gate.json` → `productionTraffic`; only the exact string `"open"` opens it; a missing or malformed file is closed. It is committed `closed` and may change only by a reviewed PR after every P0 and P1 gate in [PRODUCTION-LAUNCH-GATE](../security/audit/PRODUCTION-LAUNCH-GATE.md) is PASS;
  - workflow inputs reach shell steps only through `env:` (completes D-124 in Deploy).
- **Tests:** `tool/test_deploy_guard.sh` (23 hermetic dry-run cases; 20 fail against the previous script), in CI (`security-rules` job) and `tool/verify.sh`.
- **Status:** Accepted · 2026-10-21.

### D-138 — Production sign-in provider (Prompt 18; follows D-029, D-107)
- **Decision (proposed):** **email link (passwordless) sign-in** as the single production provider, with Firebase email-enumeration protection on; no email/password, phone or social provider in V1. Firebase Auth identifies the **account** only: it never authorizes a device, a key or a commit (device trust stays with PIKs, certificates and device proofs, D-070, D-127).
- **Why:** it is within D-029's documented baseline; with no password there is nothing to reuse, stuff or phish, and password reset (which is email control anyway) disappears as a second path. Full analysis: [AUTH-PRODUCTION-DECISION](../architecture/AUTH-PRODUCTION-DECISION.md).
- **Not done:** no provider is enabled (Firebase Authentication is not even initialized in `sirf-hum-prod`), no sign-in UI exists (D-107). Enabling it is an owner console action plus a UI prompt.
- **Status:** **Proposed — needs owner approval** · 2026-10-21. P1-7 stays open until it is approved, built and tested.

### D-139 — App Check production readiness (Prompt 18; extends D-028)
- **Decision:**
  - production web builds refuse to start without `SH_APPCHECK_WEB_RECAPTCHA_SITE_KEY` (environment guard); before this, App Check was skipped on web with only a warning. Development and staging keep working without one (never lock development out);
  - every client endpoint must be created through `callable()`/`audited()`, the only `onCall`, which passes `enforceAppCheck: true`; no `onRequest`. A static test pins the 29 callables;
  - limited-use tokens with replay protection (`consumeAppCheckToken`) are **not** adopted yet: they need client changes and measurement; candidates are pairing and unpair after the staging rollout;
  - manual steps and enforcement order: [APP-CHECK-PRODUCTION](../architecture/APP-CHECK-PRODUCTION.md).
- **Unchanged:** App Check is defence in depth, never the authorization; production never accepts the debug provider.
- **Status:** Accepted for development · 2026-10-21. Console enforcement **not enabled** anywhere (verified: `sirf-hum-prod` has no App Check service configuration).

### D-140 — Web origin security headers (Prompt 18; P2-4)
- **Decision:** Hosting headers on every path: `Content-Security-Policy-Report-Only` (`default-src 'self'`; scripts only from self + `www.gstatic.com` (CanvasKit, Firebase JS SDK) + reCAPTCHA, with `'wasm-unsafe-eval'` and no `'unsafe-inline'`/`'unsafe-eval'`; `frame-ancestors 'none'`, `object-src 'none'`, `base-uri 'self'`, `form-action 'none'`), `Cross-Origin-Opener-Policy: same-origin-allow-popups`, `Cross-Origin-Resource-Policy: same-origin`, a Permissions-Policy denying camera, microphone, geolocation, display capture, payment, USB, serial, Bluetooth, HID and MIDI, plus the existing `nosniff`, `X-Frame-Options: DENY`, referrer policy and HSTS. `no-cache` on `index.html`, `flutter_bootstrap.js`, `main.dart.js`, `version.json` and the service worker, so a fixed or revoked build reaches every browser on the next load.
- **Evidence:** a local development web build served with exactly these headers rendered in headless Chrome with **zero** CSP reports; a deliberately strict control policy produced the expected six reports, so the reporting path works. Not exercised: Firebase endpoints (an unconfigured build never loads the Firebase SDK) and reCAPTCHA.
- **Why Report-Only:** an enforcing CSP that is wrong breaks the app; enforcement waits for reports from the deployed staging origin with Firebase configured. CSP never makes the web client trusted ([WEB-SECURITY](../security/WEB-SECURITY.md)).
- **Tests:** `tool/check_web_headers.mjs` (CI `security-rules` job, `tool/verify.sh`).
- **Status:** Accepted · 2026-10-21. P2-4 stays open until the policy is enforced.

### D-141 — Photo-picker cache sweep (Prompt 18; P2-3, E81)
- **Decision:** at start-up, before `runApp` (so no composer holds a photo), the app deletes every `cacheDir/<lowercase v4 UUID>/` directory that holds only regular files: exactly `image_picker_android` 0.8.13's layout (`FileUtils.getPathFromUri`, whose own TODO recommends clearing picked files at start-up). It never follows links, never descends, never touches other cache entries. The Kotlin side only reports `cacheDir` (channel `com.sirfhum.app/app_cache`); the sweep is Dart so it is unit-tested. Best effort, never throws, logs a count only.
- **Limits:** no secure wipe (flash storage cannot be reliably overwritten); if the process dies, a copy exists from the pick until the next start. A plugin upgrade that changes the layout would silently disable the sweep, so the plugin version is pinned in review (`pubspec.lock`).
- **Tests:** `picker_cache_sweeper_test.dart` (unit); on-device `moments_test.dart` (CI emulator: real channel, real cache directory).
- **Status:** Accepted · 2026-10-21. P2-3 → fixed (implementation).

### D-142 — Gradle locking, scanning and update proposals (Prompt 18; P2-6)
- **Decision:**
  - Gradle dependency locking, `STRICT`, for the `*ReleaseRuntimeClasspath` configurations (what ships), in `android/app/gradle.lockfile`; CI fails if the build changes it;
  - OSV-Scanner scans it with the Dart lockfiles (2026-10-21: 121 + 52 + 183 packages, no advisories). The first lockfile, generated on Windows, held a `kotlin-stdlib-common` entry the Linux CI build does not resolve; STRICT locking failed the CI production build (run 39563846824) and the entry was removed, so locks are regenerated on Linux;
  - the Gradle wrapper pins `distributionSha256Sum` (services.gradle.org, cross-checked with gradle.org's checksum page);
  - Dependabot version updates (monthly, grouped) for GitHub Actions, the two npm projects and pub; **not** Cargo (crypto pins move only by decision, D-054, D-068) and **not** Gradle (locked; moves with Flutter upgrades). Dependabot alerts still cover every ecosystem.
- **Status:** Accepted · 2026-10-21. P2-6 → fixed.

### D-143 — Release signing and provenance (Prompt 18; P2-11, E14)
- **Decision:** a `ProductionRelease` assemble/bundle/package task fails without release signing (`android/key.properties`) unless `SH_ALLOW_DEBUG_SIGNED_RELEASE=1` explicitly asks for a non-distributable verification build (CI and `tool/verify.sh` do). CI proves the refusal on every run.
- **Required before production (not built):** Play App Signing, with the upload key in a managed store and never on a laptop; a release workflow on `main` behind the `production` environment that builds the AAB from a tagged commit and publishes a signed build-provenance attestation (`actions/attest-build-provenance`, SLSA) with the artifact digest; the App Check Play Integrity certificate is the Play app-signing certificate (APP-CHECK-PRODUCTION).
- **Status:** Accepted · 2026-10-21. P2-11 stays open (no provenance or signing pipeline exists yet).

### D-144 — Unpair authorizes before it walks the lineage (Prompt 18; P3-15)
- **Finding (P3-15, recorded in the PR #16 description, not in the repository until now):** `unpairCouple` listed the named couple's conversations and walked their `predecessorId` lineage (up to ~64 point reads) **before** verifying the challenge and proof. Any signed-in session could cause those reads, and an over-long lineage answered with an internal error instead of `challenge_invalid`: a one-bit signal. No state change, no data returned, no authorization bypass.
- **Fix:** the transaction first reads only the challenge, device and couple and decides the outcome (challenge binding, expiry, couple active with the caller a member, device active, purpose-8 proof); a refusal consumes the challenge and returns before any further read. Only an authorized request reads the partner records, lists the conversations and walks the lineage. Authorization, atomicity, the single-use challenge and the E90 completeness argument are unchanged.
- **Tests:** emulator `P3-15: no listing or lineage walk before the request is authorized` (a spy lister is never called for six kinds of refused request, and is called once authorized) and `P3-15: an over-long lineage answers a forged proof with proof_invalid, not the walk bound`; the 13 earlier unpair tests are unchanged and pass.
- **Status:** Accepted for development · 2026-10-21. P3-15 → fixed (implementation); in the independent review scope with D-136.

### D-145 — Prompt 18: review readiness and the launch gate of record
- **Decision:** [PRODUCTION-LAUNCH-GATE](../security/audit/PRODUCTION-LAUNCH-GATE.md) is the launch gate of record: P0–P3 gates, each PASS / FAIL / DEFERRED with evidence and an owner action. [PRODUCTION-BLOCKERS](../security/audit/PRODUCTION-BLOCKERS.md) keeps the D-125 classification. [INDEPENDENT-SECURITY-REVIEW-PACKAGE](../security/audit/INDEPENDENT-SECURITY-REVIEW-PACKAGE.md) is the reviewer's entry point. Prompt 18's target was **"prepared for independent security/cryptographic review"**, not launch.
- **Status:** Accepted · 2026-10-21. Sirf Hum is not production E2EE; no independent review has happened.
