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
  media and notifications (Prompt 11), independent review. **Sirf Hum is NOT
  production E2EE yet.**

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
