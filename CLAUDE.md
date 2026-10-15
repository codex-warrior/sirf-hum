# Sirf Hum — Development Protocol

Sirf Hum is the private digital home for two people. Flutter (Android, iOS,
Web) + Firebase + LiveKit. Built in bounded, numbered prompts/phases.

## Source of truth

Start at `docs/MASTER-BLUEPRINT.md`. Read only the documents relevant to
the task — they replace restating the spec in prompts:

| Working on | Read first |
| --- | --- |
| Any feature | `docs/product/PRODUCT-CONSTITUTION.md`, `docs/product/UX-PRINCIPLES.md`, `docs/phases/ROADMAP.md` |
| UI | `docs/design/DESIGN-CONSTITUTION.md`, `docs/design/DESIGN-TOKENS.md` |
| Code structure | `docs/architecture/ARCHITECTURE.md` |
| Environments, deploys, App Check, CI, branches | `docs/architecture/ENVIRONMENTS.md`, `docs/architecture/DEVELOPMENT-ENVIRONMENT.md`, `docs/architecture/ACCOUNT-OWNERSHIP.md` |
| Firebase, rules, functions, notifications | `docs/architecture/FIREBASE-ARCHITECTURE.md` |
| Private content, keys, devices | `docs/security/E2EE-REQUIREMENTS.md`, `docs/security/THREAT-MODEL.md`, `docs/security/PRIVACY-CONSTITUTION.md` |
| Analytics | `docs/security/ANALYTICS-POLICY.md` |
| Tests | `docs/testing/TESTING-STRATEGY.md` |
| Past decisions | `docs/decisions/DECISION-LOG.md` |

## Rules for every change

1. Read the relevant docs and inspect existing code before creating abstractions; reuse, don't duplicate.
2. Stay inside the prompt's scope. Never implement future phases without authorization. Don't change unrelated code.
3. Never silently change product requirements. Record architectural decisions in the Decision Log.
4. Add/update tests. Run `tool/verify.sh` (and `--all` when touching Functions, rules or platform config).
5. Report failures honestly. Never disable tests or weaken Security Rules to make things pass.
6. Never commit secrets. Client config lives in git-ignored `config/env/*.json`.
7. Never run a bare `firebase deploy` or `firebase use production`. Deploy with `tool/deploy.sh <env>`; production only via the Deploy workflow.
8. Work on `feature/`, `fix/`, `chore/` or `security/` branches and merge via PR after CI passes; never push directly to or force-push `main` (not enforced by GitHub on the current plan, so it is on us).

## Security non-negotiables

Never invent cryptography · never store plaintext private content on the
server · never expose private keys or log private content · never trust
client-side authorization · couple membership ≠ unlimited access · no
private content in notifications · never claim E2EE or a security audit that
doesn't exist.

## Code conventions

- `package:sirf_hum/...` imports only; UI imports `package:sirf_hum/design_system/design_system.dart`.
- No hard-coded colors, sizes, durations — use tokens. Animations go through `Motion.resolve`.
- Firebase SDK only in `lib/infrastructure/` and feature `data/` layers. Private content crosses into infrastructure only as `EncryptedEnvelope`.
- Log only through `AppLogger` with snake_case events and typed fields (raw strings are redacted; wrap known-safe strings in `SafeLogString`, IDs in `RedactedId`). Comments explain *why*.
- Definition of Done: happy path + loading/empty/error/offline/retry/recovery, accessibility, responsive, server authorization, analytics review, tests, docs.

## Token efficiency

Less repetition, not less engineering: reference docs instead of restating
them, edit targeted files, batch related work, keep reports concise. Never
trade away security, testing or cryptographic reasoning to save tokens.

## Commands

```sh
flutter pub get
node tool/generate_env_config.mjs development   # config/env/development.json (git-ignored)
flutter run --flavor development --dart-define-from-file=config/env/development.json
flutter run -d chrome --dart-define-from-file=config/env/development.json
tool/verify.sh                 # format check + analyze + tests
tool/verify.sh --all           # + Functions check, rules tests, web + Android builds
tool/deploy.sh development     # deploy rules to sirf-hum-dev
```

Windows note: `firebase emulators:exec` may leave the Firestore emulator
running on port 8080 after rules tests; stop it before re-running.
