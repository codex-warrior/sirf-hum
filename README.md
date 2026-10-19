# Sirf Hum

**Just Us.** The private digital home for two people.

> Status: **Phase 02 — Environments & infrastructure.** No product features yet. Sirf Hum is
> **not** end-to-end encrypted yet; E2EE is a requirement being designed.

## Stack

Flutter (Android first · Web; iOS not a current target, D-092) · Firebase (Auth, Firestore, Storage,
Functions, FCM, App Check) · LiveKit (realtime media).

## Getting started

Requirements: Flutter 3.41.x stable, Node 22+ (Functions) / 24.12+ (rules
tests), Java 21+ and `firebase-tools` (emulators).

```sh
flutter pub get
flutter run -d chrome                                   # development, Firebase not configured
node tool/generate_env_config.mjs development           # needs firebase login + project access
flutter run --flavor development --dart-define-from-file=config/env/development.json
tool/verify.sh                                          # format, analyze, test
```

Environments (`sirf-hum-dev` / `sirf-hum-staging` / `sirf-hum-prod`, region
`asia-south1`, app ID `com.sirfhum.app`): see
[docs/architecture/ENVIRONMENTS.md](docs/architecture/ENVIRONMENTS.md) and
[docs/architecture/DEVELOPMENT-ENVIRONMENT.md](docs/architecture/DEVELOPMENT-ENVIRONMENT.md).

## Repository map

```text
lib/
  app/             composition root: app, router, navigation shell, config
  core/            dependency-free utilities (environment, logging)
  design_system/   design tokens + theme
  features/        home · together · moments · future · us (not built yet)
  security/        cryptography boundary (EncryptedEnvelope)
  infrastructure/  Firebase (and later LiveKit) integrations
  platform/        device capability wrappers (empty)
test/              unit + widget tests (mirror lib/)
integration_test/  on-device smoke test
firebase/          Security Rules + emulator tests
functions/         Cloud Functions (TypeScript)
config/env/        build-time environment config (only example committed)
docs/              source of truth — start at docs/MASTER-BLUEPRINT.md
tool/              verify.sh (quality gate), deploy.sh (gated deploys),
                   generate_env_config.mjs, provision_firebase.sh
```

## Documentation

Everything important is in [docs/MASTER-BLUEPRINT.md](docs/MASTER-BLUEPRINT.md).
Contributor rules: [CLAUDE.md](CLAUDE.md).
