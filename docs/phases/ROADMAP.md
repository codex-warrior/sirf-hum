# Roadmap

Status: **Phase 01 complete. Sequence after Phase 01 is proposed** and
will be confirmed prompt by prompt. Each phase gets its own document in
`docs/phases/` when it starts (scope, out of scope, decisions, Definition
of Done).

**Platform priority (D-092, 2026-10-19):** P0 Android · P1 Web where
applicable · iOS not part of the current product (decided after the Android
product is launched and validated). Phase notes below that mention iOS are
history.

## Phase 01 — Foundation ✅

Product constitution, documentation system, Flutter project (Android, iOS,
Web), module boundaries, design-token foundation, Firebase boundaries
(default-deny rules, emulator tests, Functions skeleton), environments
pattern, quality tooling and CI. **No product features.**

## Phase 02 — Environments & infrastructure ✅

- Three Firebase projects (`asia-south1` Firestore).
- App identity `com.sirfhum.app`.
- Android flavors and iOS schemes.
- Per-platform config generation.
- Runtime and Functions environment guards.
- App Check and Crashlytics wiring.
- Privacy-enforcing logger.
- Functions ESLint.
- Gated deploy script and workflow.
- gitleaks CLI scanning.

Blocked on billing: Storage bucket, Functions deploy.
See [ENVIRONMENTS](../architecture/ENVIRONMENTS.md).

## Phase 03 — Source control & CI ✅

- Private GitHub repo `codex-warrior/sirf-hum`.
- First real CI run, with iOS compiled for all schemes on macOS.
- Workload Identity Federation deployers.
- Production deploy gates.
- Ownership plan ([ACCOUNT-OWNERSHIP](../architecture/ACCOUNT-OWNERSHIP.md)).

Branch protection and production reviewers are blocked by the GitHub plan.

## Phase 04 — E2EE architecture (design) ✅

- MLS-based design, key management, pairing/device trust, recovery and
  revocation, web decision, crypto boundaries, test plan, threat-model
  extension.
- Isolated OpenMLS spike passed natively and on wasm32.
- **Blocking before implementation:** owner approvals (D-042, D-046, D-050)
  and the library decision with independent review (D-043).

## Phase 05 — MLS decision gate ✅

- OpenMLS 0.9.1 selected (medium confidence); mls-rs 0.56.0 fallback.
- Both libraries passed identical scenarios natively and on wasm32,
  interoperated, and passed their upstream test vectors.
- Android/iOS/wasm packaging and Dart FFI proven in the prototype.
- New mandatory behaviours: D-055–D-061.

[MLS-DECISION](../security/MLS-DECISION.md)

## Phase 06 — Crypto core foundation ✅

- Rust crypto core (`packages/sirf_hum_crypto`) on OpenMLS 0.9.1 behind a
  19-function C ABI, bundled by a first-party native-assets hook (D-063).
- Mandatory behaviours implemented and tested:
  - boundary credential validation (D-057, D-064);
  - checkpoint/rollback (D-056);
  - sealed atomic local state (D-058, D-065);
  - input limits (D-059);
  - stable error codes;
  - no logging.
- Runs inside the real app on an Android emulator and an iOS simulator in
  CI. Web compiles a fail-closed stub.
- **Sirf Hum is NOT production E2EE yet.** There was no platform key store
  yet (added in Phase 07), no review, and no product feature uses the core.

[CRYPTO-CORE-ARCHITECTURE](../security/CRYPTO-CORE-ARCHITECTURE.md)

## Phase 07 — Device identity & registration ✅

- Identity hierarchy: account ≠ device ≠ cryptographic identity ≠ MLS
  credential.
- One device identity per (installation, account) (D-071).
- Platform key store: Android Keystore / iOS Keychain (D-066).
- Device registry: `pending` → server proof of possession → `active` →
  `revoked` (D-069, D-070).
- Rules emulator tests, Functions emulator tests, and device integration
  tests.
- **Not done:** deploying the activation Functions (needs Blaze, D-025), no
  device approval UI, no sign-in. **Sirf Hum is NOT production E2EE yet.**

[DEVICE-IDENTITY](../security/DEVICE-IDENTITY.md)

## Phase 08 — Recovery, revocation & multi-device security ✅

- Every device keeps its own PIK and keys; trust between a person's
  devices is a chain of PIK-signed approvals (D-074).
- First-device bootstrap is once ever; later devices need approval by a
  trusted device or the recovery key; a comparison code is shown on both
  screens (D-075).
- Optional single-use recovery key (D-076); no server or support recovery;
  no history recovery.
- One-way revocation enforced server-side, including for offline devices
  (D-080).
- Rate limits (D-077), expiry and cleanup (D-078); rollback protection
  analysed but not provided (D-079 open).
- **Not done:** deployment (Blaze), device-management UI, identity reset,
  peer-side approval-chain verification. **Sirf Hum is NOT production
  E2EE yet.**

[MULTI-DEVICE-TRUST](../security/MULTI-DEVICE-TRUST.md)

## Phase 09 — Production device trust & signed revocation ✅

- Revocation is signed by a trusted device's PIK, with stored evidence;
  clients cannot write device records (D-081).
- Identity reset: delayed 7 days, cancellable by any trusted device, to a
  NEW identity partners must re-verify (D-082).
- Server trust epoch; devices refuse an older view (D-083).
- Peer-side lineage verification in Rust, golden vectors across
  TypeScript, Rust and Dart (D-084).
- Transition matrix, race and rate-limit boundary tests, rules re-audit,
  logging guard.
- **Not done / BLOCKED:** deployment (Blaze not enabled), reset
  notifications, local rollback protection (D-079), device-management UI.
  **Sirf Hum is NOT production E2EE yet.**

[MULTI-DEVICE-TRUST](../security/MULTI-DEVICE-TRUST.md)

## Phase 10 — E2EE messaging core, Part 1 (security design gate + trust/MLS foundation) ✅

- Design gate: [E2EE-MESSAGING-DESIGN](../security/E2EE-MESSAGING-DESIGN.md),
  D-085–D-091.
- Trust unit is the exact device certificate; revoked devices cannot
  re-mint trust with a retained PIK (D-085).
- Server-authoritative conversation provisioning from an accepted pairing
  (D-086); not reachable until the pairing phase exists.
- ABI v5: staged commits, first commit wins per epoch, messages with
  authenticated routing, sealed local history, offline queue (D-087–D-091).
- Firestore rules and emulator tests; development messaging service; no
  chat UI, text only.
- **Not done / BLOCKED:** deployment (Blaze not enabled), pairing, chat UI,
  independent review. **Sirf Hum is NOT production E2EE yet.**

**Prompt 11 (Phase 0 step 11): encrypted media + secure notifications.**
Infrastructure only, no media or notification UI
([E2EE-MEDIA-AND-NOTIFICATIONS](../security/E2EE-MEDIA-AND-NOTIFICATIONS.md),
D-093–D-099):
- ABI v6: media objects (STREAM over XChaCha20-Poly1305, per-object keys
  that never leave the core, SHA-256 commitment, AAD binding), ciphertext-only
  local cache, media send/open in the development messaging service.
- Storage rules (create-only ciphertext objects) and emulator tests.
- Content-free FCM wake-ups, push tokens registered with a device-key
  proof, revocation-aware fan-out triggers (emulator-tested).
- **Not done / BLOCKED:** deployment (Blaze: Storage bucket, Functions,
  triggers), thumbnails, size padding, notification permission and
  channels (UI), independent review.

**Prompt 12 (Phase 0 step 12): couple / account system.** Server logic,
rules and a client service; no UI
([COUPLE-AND-PAIRING](../security/COUPLE-AND-PAIRING.md), D-100–D-105):
- Account = Firebase UID; minimal `users/{uid}` profile (display name only).
- Two-consent pairing: invite (hashed 128-bit token) → accept (bound
  claimant, comparison code) → inviter confirms; explicit state machine.
- Every step signed by an active device (proof purpose 4); fails closed on
  identity reset, inactive devices, already paired; transactional locks.
- Confirmation creates the couple and its conversation atomically
  (`coupleId` on the conversation).
- **Not done / BLOCKED:** deployment (Blaze), pairing UI, unpairing, account
  deletion, PIK verification, independent review.

**Prompt 13: core UX / Home foundation.** The first user-facing app
([APP-SHELL-AND-NAVIGATION](../architecture/APP-SHELL-AND-NAVIGATION.md),
D-106–D-110):
- Server-authoritative, ID-free session state (`lib/session/`): signed out,
  not paired, pairing, paired, unavailable.
- Entry routes plus a five-area shell (bottom bar or rail) shown only to a
  paired couple. Deep links survive loading.
- Home:
  - greeting and couple mark;
  - a Together entry;
  - honest Moments and Future empty states.
- Entry states for Together, Moments and Future. Us shows the couple's names
  and sign-out.
- Small design-system component set; web private-content notices.
- `firebase_auth` for session restoration and sign-out only; bounded Firebase
  start-up.
- **Not done:**
  - the sign-in method and UI (D-107, open);
  - pairing screens and profile editing;
  - presence, calls, moments and plans;
  - deployment (Blaze).

  A real build reaches only the welcome screen. Not production-ready.

**Prompt 14: Together foundation.** The heart of "spend time together"
([TOGETHER-ARCHITECTURE](../architecture/TOGETHER-ARCHITECTURE.md),
D-111, D-112):
- ID-free Together state machine (idle → starting → waiting → together →
  ended, invitations, failures) driven by a realtime port that takes no
  identifiers.
- Together hub: partner and presence, "What do you want to do?", and Time
  together as the validation activity. Call, Watch and Listen are shown as
  coming soon.
- Account switch, sign-out and stale answers are safe; failures fail
  closed.
- **Not done:**
  - a production backend (privacy and device-trust design, Blaze);
  - real presence;
  - Call, Watch, Listen, games.

  A real build shows the hub with nothing startable.

**Prompt 15: Moments foundation.** The couple's private memory timeline
([MOMENTS-ARCHITECTURE](../architecture/MOMENTS-ARCHITECTURE.md),
D-113–D-117):
- **Implemented (development, unreviewed):**
  - a moment = its photos (kind-2 media refs, keys only in Rust) + a kind-3
    manifest (caption, date, photo IDs) in the couple's existing MLS
    conversation; no new server schema, rules, crypto or ABI;
  - `MomentsService`: seal everything before upload, discard on failure,
    offline/retry without duplicates, device-trust gating;
  - timeline (by month, pages of 24), detail, new-memory flow (system photo
    picker, up to 8 photos), honest empty/loading/error/blocked states, Home
    summary;
  - couple-isolation rules tests, real-core service tests, an on-device
    test with the real platform key store.
- **Pre-production:** nothing reviewed; Sirf Hum is NOT production E2EE.
- **Blocked by Blaze / sign-in:** a production backend (D-116: sign-in
  D-107, deployed device activation and Storage, D-025).
- **Deferred:** deletion and editing (cannot be truthful yet, D-116), video,
  voice notes, letters, thumbnails, EXIF stripping (D-117), moment
  notifications.

  A real build shows the Moments area with an honest entry state.

**Prompt 16: Future + Us.** Plan the future and build a shared identity
([FUTURE-AND-US-ARCHITECTURE](../architecture/FUTURE-AND-US-ARCHITECTURE.md),
D-118–D-121):
- **Implemented (development, unreviewed):**
  - one couple notebook as kind-4 MLS application messages in the
    couple's existing conversation (create / update / remove, last change
    wins, terminal remove); no new server schema, rules, crypto or ABI;
  - `MessagingService.exclusive`: one lock for every feature on the
    conversation (Moments now uses it);
  - Future: plans, places, things to try, important dates; coming up / by
    kind / done; never "missed"; add, edit, mark done, remove;
  - Us: names, together since, our story, little things, rituals,
    important dates, sign-out; Home shows the soonest plan ahead;
  - one editor (pushed page, single flight), honest empty / loading /
    error / blocked / offline states, web fail-closed;
  - payload, assembly, controller, screen, real-core service and
    on-device tests.
- **Pre-production:** nothing reviewed; Sirf Hum is NOT production E2EE.
- **Blocked by Blaze / sign-in:** a production backend (D-121, as D-116).
- **Deferred:** erasure and retention for removed records, history
  compaction, notifications and reminders, recurring dates, letters,
  devices and privacy settings in Us.

  A real build shows Future and Us with honest entry states.

**Prompt 17: Security hardening, threat model & audit preparation.** Not a
feature phase ([audit package](../security/audit/README.md), D-122–D-126):
- **Reviewed:** trust chain, MLS integration, media, messaging, Moments,
  Future + Us, push, pairing, rate limits, logging, local storage/backup,
  web boundary, rules/Functions, dependencies, CI/CD, repository.
- **Fixed:** a person key can be activated on one device, ever (server
  index + lineage rule); Android opts out of OS backup and device
  transfer; CI actions/tools pinned and inputs passed as env; npm audit
  gate for Functions; MLS messages padded to 256-byte blocks.
- **Documented, not fixed:** 19 findings classified P0–P3
  ([PRODUCTION-BLOCKERS](../security/audit/PRODUCTION-BLOCKERS.md)), new
  threats E77–E83, a status for every threat ID.
- **Outcome:** security blockers remain. No independent review has
  happened; Sirf Hum is NOT production E2EE. Nothing deployed.

**Prompt 17B: Security blocker remediation** ([remediation](../security/audit/PROMPT-17B-REMEDIATION.md),
D-127–D-134): both high findings fixed (device-bound commits; partner
verification by safety number and QR), forced pairing-code entry, signed
rejection, identity-reset alerts, Dart advisory scanning, GitHub security
controls. Deferred with reasons: picker cache sweep, web CSP, Gradle
scanning, local rollback, deletion. Open: conversation re-provisioning,
unpairing (D-134), deployment, sign-in, independent review.

## Proposed sequence

Ordering principle: identity and cryptography come **before** any feature
that stores private content, so no feature is built on a plaintext model
that must later be migrated.

| Phase | Theme | Depends on | Notes |
| --- | --- | --- | --- |
| 02 | ~~Environments & Firebase projects~~ (done) | 01 | — |
| 03 | Visual identity v1: typeface, palette, iconography, core components | 01 | Can run parallel to 02 |
| 04 | ~~E2EE architecture design~~ (done; Flutter-bridge prototype still pending) | 02 | No product UI |
| 05 | Identity: accounts, sign-in, device registration, device keys | 02, 04 | |
| 06 | Pairing: invite, accept, couple record, unpairing | 05 | Abusive-partner review |
| 07 | Messaging (E2EE) + privacy-safe notifications | 04–06 | First private content |
| 08 | Calls (LiveKit) | 06 | Token minting function |
| 09 | Moments (E2EE media pipeline) | 07 | |
| 10 | Home (presence, rituals, entry points) | 07–09 | |
| 11 | Future (plans, dates, goals) | 06 | |
| 12 | Together experiences (Watch/Listen Together, games) | 08 | |
| 13 | Sirf Hum Plus (subscriptions, entitlements per couple) | 06 | |
| 14 | Beta hardening: accessibility audit, performance, security review | all | |

## Not on the V1 roadmap

Our Money · AI features · advertising of any kind.

## Release strategy (to be detailed)

Internal (staging) → closed beta (Play internal testing, TestFlight,
password-protected web) → open beta → public launch. Each stage gated on:
CI green, Security Rules tests, manual accessibility pass, and — before
any public E2EE claim — independent cryptographic review.
