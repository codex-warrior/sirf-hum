# Sirf Hum — Master Blueprint

The index of record. Each section summarises what is **decided** and links
to the detailed source of truth. Updated at the end of every phase.

Last updated: **Prompt 15 — 2026-10-20**.

## 1. Vision

*Sirf Hum is the private digital home for two people.* Ambition: every
couple should have a Sirf Hum account. → [PRODUCT-VISION](product/PRODUCT-VISION.md)

## 2. Users

Couples; both partners are independent, first-class users. Must work for
people with zero technical knowledge. Initial market and segments: **open**.

## 3. Product principles

A private digital world shared by two people — not a messenger, social
network, productivity tool, dating app, couples game or stats dashboard.
Core loop: Connect → Spend time together → Create memories → Plan the future
→ Grow together → Return. Five areas: **Home, Together, Moments, Future, Us**.
→ [PRODUCT-CONSTITUTION](product/PRODUCT-CONSTITUTION.md)

## 4. UX principles

Ten rules: zero learning curve, familiar interactions, minimal
configuration, intelligent defaults, one primary action, hidden advanced
features, human language, discoverability over tutorials, motion that
communicates, failure states matter. Accessibility is architecture.
→ [UX-PRINCIPLES](product/UX-PRINCIPLES.md)

## 5. Design principles

*The relationship is the hero; the interface disappears.* No AI-startup
aesthetics. Token-driven; light and dark first-class; identity not yet
decided. → [DESIGN-CONSTITUTION](design/DESIGN-CONSTITUTION.md) ·
[DESIGN-TOKENS](design/DESIGN-TOKENS.md)

## 6. Product architecture

Flutter client with `app / core / design_system / features / security /
infrastructure / platform` modules; Riverpod; go_router with one branch per
area. → [ARCHITECTURE](architecture/ARCHITECTURE.md)

## 7. Security architecture

Clients untrusted; server-side authorization; default-deny rules; explicit
trust boundaries and threat actors. → [THREAT-MODEL](security/THREAT-MODEL.md)

## 8. E2EE architecture

Requirements: private content is encrypted on the device; the server never
holds content keys; established protocols only; versioned envelopes; the
person → account → devices → cryptographic identity → couple model.
**Crypto-core foundation implemented (Prompt 06); messaging core added
(Prompt 10: device-pinned trust, staged commits, authenticated text
messages, sealed local history; development only, no chat UI); encrypted
media and content-free notifications added (Prompt 11, undeployed, no UI);
couple / account foundation added (Prompt 12: two-consent, device-signed
pairing, server-created couples; undeployed, no UI,
[COUPLE-AND-PAIRING](security/COUPLE-AND-PAIRING.md)); app shell and Home
(Prompt 13), Together foundation (Prompt 14), and Moments (Prompt 15: photos
and an encrypted kind-3 manifest in the couple's MLS conversation, no new
server state or crypto, no production backend yet,
[MOMENTS-ARCHITECTURE](architecture/MOMENTS-ARCHITECTURE.md), D-113–D-117).
Sirf Hum is NOT production E2EE yet:**

- the platform key store exists (Prompt 07, D-066) but nothing is reviewed;
- device identity and registration exist (Prompt 07) but server activation
  is emulator-only until Blaze (D-025);
- no independent review has taken place.

→ [CRYPTO-CORE-ARCHITECTURE](security/CRYPTO-CORE-ARCHITECTURE.md) ·
[E2EE-MESSAGING-DESIGN](security/E2EE-MESSAGING-DESIGN.md)

**Authoritative for future prompts (Prompt 05 decision gate):**

- **Protocol: MLS (RFC 9420).** APPROVED direction (D-042).
  - One couple group whose members are devices, plus a personal group per
    person.
  - Each person has an identity key (PIK) that signs their device
    certificates.
  - Encrypted handshake messages (D-055).
- **Crypto core: OpenMLS 0.9.1, medium confidence** (D-054).
  - mls-rs 0.56.0 is a tested, interoperable fallback.
  - Evidence: [MLS-IMPLEMENTATION-COMPARISON](security/MLS-IMPLEMENTATION-COMPARISON.md);
    decision and conditions: [MLS-DECISION](security/MLS-DECISION.md).
- **Integration boundary:**
  - Flutter → narrow Dart facade → hand-written C ABI bundled by
    first-party native assets (D-063, decided in Prompt 06) → Rust core
    (OpenMLS + credential policy + sealed atomic store) → KEK provider.
    Platform key store: Android Keystore-wrapped / iOS Keychain store keys
    (D-066, Prompt 07).
  - Device identity and registration: one identity per (installation,
    account), `pending` → server proof of possession → `active` →
    `revoked` (D-069–D-071).
    → [DEVICE-IDENTITY](security/DEVICE-IDENTITY.md)
  - Multi-device trust (Prompt 08): own PIK per device; approvals signed
    by trusted devices; first-device bootstrap once ever; optional
    single-use recovery key; one-way server-enforced revocation; rate
    limits and expiry (D-074–D-080).
  - Device trust hardening (Prompt 09): signed revocation, delayed
    cancellable identity reset, server trust epoch, on-device lineage
    verification (D-081–D-084).
    → [MULTI-DEVICE-TRUST](security/MULTI-DEVICE-TRUST.md)
  - No API exports keys or state.
  - The core never depends on Firebase.
  - Measured: Android `.so`, iOS XCFramework, wasm32 and Dart FFI all work
    in the prototype.
- **Mandatory core behaviours:**
  - credential validation before merge (D-057);
  - transactional persistence (D-058);
  - rollback on rejected input (D-056);
  - input limits (D-059);
  - crypto agility: versioned records, fail-closed on unknown versions
    (D-061).
  - all of the above are implemented and tested in the Prompt 06 core
    (credential format D-064, state format D-065, dependency gate D-068).
- **Web limitation:** Web V1 handles **no private E2EE content** (D-046
  APPROVED). WASM working is not web security approval.
- **Recovery direction:** trusted-device recovery by default, plus an
  opt-in user-held recovery key. An encrypted history archive is deferred.
  A server master key or escrow is **rejected**.
- **Post-quantum:** not a V1 launch blocker (D-050 APPROVED); agility and a
  migration path are required.
- **Production security gates:** all of the following, before any
  production E2EE claim:
  - an independent delta review of OpenMLS since the audited commit;
  - a review of the crypto provider;
  - a review of our core and FFI;
  - platform security testing;
  - penetration testing;
  - an independent design review.

→ [E2EE-ARCHITECTURE](security/E2EE-ARCHITECTURE.md) ·
[KEY-MANAGEMENT](security/KEY-MANAGEMENT.md) ·
[PAIRING-AND-DEVICE-TRUST](security/PAIRING-AND-DEVICE-TRUST.md) ·
[RECOVERY-AND-REVOCATION](security/RECOVERY-AND-REVOCATION.md) ·
[WEB-SECURITY](security/WEB-SECURITY.md) ·
[CRYPTOGRAPHIC-BOUNDARIES](architecture/CRYPTOGRAPHIC-BOUNDARIES.md) ·
[E2EE-TEST-PLAN](testing/E2EE-TEST-PLAN.md)

## 9. Data architecture

Firestore = metadata + ciphertext; Storage = encrypted media; fields
classified as private content / cryptographic / relationship / operational /
account. No schemas yet. → [FIREBASE-ARCHITECTURE](architecture/FIREBASE-ARCHITECTURE.md)

## 10. Platform architecture

One Flutter codebase for Android (P0) and Web (P1, where applicable); iOS is
not part of the current product (D-092, supersedes D-073); adaptive layouts by
window size; web key-storage limits acknowledged. →
[PLATFORM-STRATEGY](architecture/PLATFORM-STRATEGY.md)

**Application identity (D-022):** `com.sirfhum.app` on Android and iOS
(production). Staging `com.sirfhum.app.staging`, development
`com.sirfhum.app.dev`. Web app: `app.sirfhum.com` (production, domain not
yet attached); marketing site `sirfhum.com` is separate.

### 10a. Environment architecture

Three isolated environments, each with its own Firebase project, app IDs,
config and credentials: development `sirf-hum-dev`, staging
`sirf-hum-staging`, production `sirf-hum-prod`. Region **`asia-south1`**
(D-016; Firestore location is irreversible). Isolation is layered:
- separate projects;
- no default CLI project;
- flavor + per-environment config;
- a runtime guard that refuses mismatched builds;
- a Functions cold-start guard;
- explicit, gated deploys.

→ [ENVIRONMENTS](architecture/ENVIRONMENTS.md)

### 10b. CI/CD and deployment safety

CI validates without secrets:
- Flutter checks;
- web builds per environment;
- Android development/staging debug and production release builds;
- iOS builds for all schemes on macOS;
- Functions typecheck, lint, build and tests;
- Security Rules emulator tests;
- a gitleaks history scan.

Deploys are manual per environment through GitHub Environments with
Workload Identity Federation (one keyless deployer per project, bound to this
repository's numeric ID and environment). Production requires `main`, a
typed confirmation and production-only credentials. **Required reviewers
and branch protection are unavailable on the current free GitHub plan**
(D-038). Locally, use `tool/deploy.sh <env>`.

**Source control (Prompt 03):**
- Private repository `codex-warrior/sirf-hum`; `main` plus
  `feature/`, `fix/`, `chore/` and `security/` branches merged by PR.
- First CI run executed on GitHub: iOS compiled for all three schemes on
  macOS.
- Ownership is currently personal on both Google and GitHub; the target
  structure is in [ACCOUNT-OWNERSHIP](architecture/ACCOUNT-OWNERSHIP.md).

### 10c. App Check, crash reporting, logging

- **App Check:** debug provider in development; Play Integrity, App Attest
  and reCAPTCHA Enterprise in staging and production. Enforcement is
  **off** until the staged rollout. App Check protects Firebase access; it
  is not encryption.
- **Crashlytics** (mobile only): collection is off by default, enabled per
  environment. Only sanitized records are sent; errors carry their type,
  never their message.
- **Logging** goes through `AppLogger`: typed fields, and raw strings are
  redacted.

### 10d. Development workflow

Generate config with `node tool/generate_env_config.mjs <env>`, run with
`--flavor <env> --dart-define-from-file=config/env/<env>.json`, and validate
with `tool/verify.sh --all`. →
[DEVELOPMENT-ENVIRONMENT](architecture/DEVELOPMENT-ENVIRONMENT.md)

## 11. Feature roadmap

Prompts 01–15 done (through the Moments foundation; nothing deployed).
Next steps are confirmed prompt by prompt. → [ROADMAP](phases/ROADMAP.md)

## 12. Business model

Free core + **Sirf Hum Plus**, one subscription per couple. →
[BUSINESS-MODEL](business/BUSINESS-MODEL.md)

## 13. Monetization

Pricing hypotheses ₹99–₹199/month or ₹799–₹1,499/year per couple (not
locked). No behavioural advertising. Ethical rules: privacy never paid,
own data never paywalled, no emotional pressure.

## 14. Analytics

Behavioural events only; never content. No SDK integrated yet. →
[ANALYTICS-POLICY](security/ANALYTICS-POLICY.md)

## 15. Privacy

Don't collect what isn't needed; store ciphertext; don't know what you
don't need to know; privacy-safe notifications. →
[PRIVACY-CONSTITUTION](security/PRIVACY-CONSTITUTION.md)

## 16. Testing

Unit, widget, integration (smoke), Security Rules emulator tests in place;
Functions, E2EE and E2E layers planned. →
[TESTING-STRATEGY](testing/TESTING-STRATEGY.md)

## 17. Release strategy

Internal → closed beta → open beta → launch, gated on CI, rules tests,
accessibility pass and (for E2EE claims) independent review. Store
listings, versioning and signing: **open**.

## 18. Future roadmap

Our Money (regulated partnerships only), premium experiences, AI features
designed with privacy — all **post-V1** and individually reviewed.

## 19. Open decisions

| # | Decision | Needed before |
| --- | --- | --- |
| 1 | Account ownership (Google + GitHub) and Blaze billing (D-025, ACCOUNT-OWNERSHIP.md) | Storage, Functions, staging use, launch |
| 1a | GitHub plan upgrade for branch protection + production reviewers (D-038) | Second contributor / first production deploy |
| 2 | Release signing (Android upload key, Apple team) and store accounts | First store build |
| 3 | Initial market, languages (Hindi/English/other), and segments | Visual identity, copy, localisation |
| 4 | Sign-in methods (baseline email link or email/password; phone optional) | Identity phase |
| 5 | Commission the independent OpenMLS delta + crypto-core review (D-054 conditions, now including `packages/sirf_hum_crypto`); decide D-060 (past-epoch window) | Before production E2EE |
| 5a | Local rollback protection and review of the platform key store (D-066 residual) | Before any real user's private content |
| 5b | Blaze plan to deploy device trust Functions and the cleanup schedule (D-025, D-069, D-078) | First real device activation |
| 5c | Identity-reset notifications (D-082); local rollback protection (D-079) | Before production E2EE |
| 6 | Shared history after unpairing (blocks unpairing, D-105) | Unpairing (product + legal) |
| 7 | LiveKit Cloud vs. self-hosted | Calls phase |
| 8 | Analytics vendor and consent posture | First analytics event |
| 9 | Visual identity (typeface, palette, iconography) | Visual identity phase |
| 10 | Legal/privacy-law review (DPDP Act 2023, GDPR if applicable) | Public beta |

## Decision Log

→ [decisions/DECISION-LOG.md](decisions/DECISION-LOG.md)
