# Sirf Hum — Master Blueprint

The index of record. Each section summarises what is **decided** and links
to the detailed source of truth. Updated at the end of every phase.

Last updated: **Prompt 02 — 2026-10-15**.

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

## 8. E2EE architecture requirements

Private content encrypted on device; server never holds content keys;
established protocols only; versioned envelopes; person → account → devices
→ cryptographic identity → couple. **Not implemented.** Protocol choice:
**open**. → [E2EE-REQUIREMENTS](security/E2EE-REQUIREMENTS.md)

## 9. Data architecture

Firestore = metadata + ciphertext; Storage = encrypted media; fields
classified as private content / cryptographic / relationship / operational /
account. No schemas yet. → [FIREBASE-ARCHITECTURE](architecture/FIREBASE-ARCHITECTURE.md)

## 10. Platform architecture

One Flutter codebase for Android, iOS (≥15) and Web; adaptive layouts by
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
Workload Identity Federation. Production requires reviewers, `main` and an
explicit confirmation. Locally, use `tool/deploy.sh <env>`.

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

Phase 01 done. Proposed: environments → identity → E2EE design → pairing →
messaging → calls → Moments → … → [ROADMAP](phases/ROADMAP.md)

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
| 1 | Project ownership account and Blaze billing (D-025) | Storage, Functions, staging use |
| 2 | Release signing (Android upload key, Apple team) and store accounts | First store build |
| 3 | Initial market, languages (Hindi/English/other), and segments | Visual identity, copy, localisation |
| 4 | Sign-in methods (baseline email link or email/password; phone optional) | Identity phase |
| 5 | E2EE protocol and library; web device role; recovery model | E2EE phase |
| 6 | Shared history after unpairing | Pairing phase (product + legal) |
| 7 | LiveKit Cloud vs. self-hosted | Calls phase |
| 8 | Analytics vendor and consent posture | First analytics event |
| 9 | Visual identity (typeface, palette, iconography) | Visual identity phase |
| 10 | Legal/privacy-law review (DPDP Act 2023, GDPR if applicable) | Public beta |

## Decision Log

→ [decisions/DECISION-LOG.md](decisions/DECISION-LOG.md)
