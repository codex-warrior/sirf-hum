#!/usr/bin/env bash
# Environment-explicit Firebase deploys. There is no default project in
# .firebaserc, so a bare `firebase deploy` fails; use this script (locally)
# or the "Deploy" GitHub workflow (staging/production).
#
#   tool/deploy.sh development [--only firestore,storage,functions,hosting]
#   tool/deploy.sh staging     [--only ...]
#   tool/deploy.sh production  [--only ...]
#
# Production requires: clean git tree on main, all checks passing, and typing
# the project ID (or SH_CONFIRM_PRODUCTION=sirf-hum-prod in CI, which runs
# behind the protected "production" GitHub environment).
set -euo pipefail
cd "$(dirname "$0")/.."

ENV="${1:-}"
shift || true
case "$ENV" in
  development) PROJECT=sirf-hum-dev ;;
  staging)     PROJECT=sirf-hum-staging ;;
  production)  PROJECT=sirf-hum-prod ;;
  *) echo "usage: $0 development|staging|production [--only targets]" >&2; exit 2 ;;
esac

ONLY='firestore:rules,firestore:indexes'
if [[ "${1:-}" == '--only' ]]; then
  ONLY="${2:?--only needs a value}"
fi
case ",$ONLY," in *,hosting*) HOSTING=1 ;; *) HOSTING=0 ;; esac

step() { printf '\n==> [%s] %s\n' "$ENV" "$1"; }

if [[ "$ENV" != development ]]; then
  step 'Checking git state'
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Refusing to deploy $ENV from a dirty working tree." >&2; exit 1
  fi
fi
if [[ "$ENV" == production ]]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$BRANCH" != main ]]; then
    echo "Production deploys only from main (on '$BRANCH')." >&2; exit 1
  fi
  CONFIRM="${SH_CONFIRM_PRODUCTION:-}"
  if [[ -z "$CONFIRM" ]]; then
    read -r -p "Deploying '$ONLY' to PRODUCTION. Type the project ID to continue: " CONFIRM
  fi
  if [[ "$CONFIRM" != "$PROJECT" ]]; then
    echo 'Confirmation did not match. Aborting.' >&2; exit 1
  fi
fi

step 'Security Rules tests (emulators)'
(cd firebase && npm ci --silent && npm test)

if [[ ",$ONLY," == *,functions* ]]; then
  step 'Functions checks'
  (cd functions && npm ci --silent && npm run check)
fi

if [[ "$HOSTING" == 1 ]]; then
  step 'Building web app'
  CONFIG="config/env/$ENV.json"
  [[ -f "$CONFIG" ]] || { echo "Missing $CONFIG (node tool/generate_env_config.mjs $ENV)." >&2; exit 1; }
  flutter build web --release --dart-define-from-file="$CONFIG"
fi

step "Deploying $ONLY to $PROJECT"
firebase deploy --project "$ENV" --only "$ONLY" --non-interactive
