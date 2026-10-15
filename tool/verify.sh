#!/usr/bin/env bash
# Local quality gate. Mirrors .github/workflows/ci.yml (except iOS, which
# needs macOS, and the history secret scan).
#   tool/verify.sh            format + analyze + unit/widget tests
#   tool/verify.sh --all      also Functions (typecheck, lint, build, test),
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

if [[ "${1:-}" == '--all' ]]; then
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
