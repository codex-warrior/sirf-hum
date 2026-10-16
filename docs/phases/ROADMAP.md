# Roadmap

Status: **Phase 01 complete. Sequence after Phase 01 is proposed** and
will be confirmed prompt by prompt. Each phase gets its own document in
`docs/phases/` when it starts (scope, out of scope, decisions, Definition
of Done).

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
