#!/usr/bin/env bash
# Local quality gate. Mirrors .github/workflows/ci.yml (except iOS, which
# needs macOS, and the history secret scan).
#   tool/verify.sh            format + analyze + unit/widget tests
#                             + crypto package analyze/tests
#   tool/verify.sh --all      also the Rust crypto core (needs a native Rust
#                             toolchain; on Windows that means MSVC Build
#                             Tools), Functions (typecheck, lint, build, test),
#                             Security Rules emulator tests, web build and
#                             Android development + production builds
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n==> %s\n' "$1"; }

step 'Format check'
dart format --output=none --set-exit-if-changed .

step 'Static analysis + lints'
flutter analyze

step 'Unit + widget tests'
flutter test

step 'Crypto package: analyze + Dart tests (native tests skip without a host build)'
(cd packages/sirf_hum_crypto && dart pub get && dart analyze --fatal-infos && dart test)

if [[ "${1:-}" == '--all' ]]; then
  step 'Crypto core (Rust): policy, fmt, clippy, tests'
  bash tool/check_crypto_core.sh
  (
    cd packages/sirf_hum_crypto/native
    cargo fmt --check
    cargo clippy --locked --all-targets -- -D warnings
    cargo test --locked
  )

  step 'Cloud Functions: typecheck, lint, build, test'
  (cd functions && npm ci && npm run check)

  step 'Security Rules tests (emulators)'
  (cd firebase && npm ci && npm test)

  step 'Web build (production identity, no credentials)'
  flutter build web --release --dart-define=SH_ENV=production

  step 'Android: development debug + production release'
  flutter build apk --debug --flavor development --dart-define=SH_ENV=development
  flutter build apk --release --flavor production --dart-define=SH_ENV=production
fi

printf '\nAll requested checks passed.\n'
