#!/usr/bin/env bash
# Environment-explicit Firebase deploys. There is no default project in
# .firebaserc, so a bare `firebase deploy` fails; use this script (locally)
# or the "Deploy" GitHub workflow (staging/production).
#
#   tool/deploy.sh development [--only firestore,storage,functions,hosting]
#   tool/deploy.sh staging     [--only ...]
#   tool/deploy.sh production  [--only ...]
#
# Production requires: the Deploy workflow (never a laptop), a clean git tree
# on main, all checks passing, and the typed project ID
# (SH_CONFIRM_PRODUCTION=sirf-hum-prod, set by the workflow behind the
# protected "production" GitHub environment). Functions and Hosting, which
# open production to traffic, additionally need the launch gate in
# config/launch_gate.json to be "open" (D-137); rules stay deployable, since
# they only restrict access.
#
# SH_DEPLOY_DRY_RUN=1 stops after the gates (tool/test_deploy_guard.sh).
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
# The Firebase CLI ignores whitespace in --only; so do the gates below.
ONLY="${ONLY//[[:space:]]/}"
case ",$ONLY," in *,hosting*) HOSTING=1 ;; *) HOSTING=0 ;; esac

step() { printf '\n==> [%s] %s\n' "$ENV" "$1"; }
refuse() { echo "Refusing to deploy: $*" >&2; exit 1; }

if [[ "$ENV" == production ]]; then
  # A guard against accidents, not against the repository owner: the
  # credentials themselves are only minted for the workflow on main (WIF).
  [[ "${GITHUB_ACTIONS:-}" == true ]] \
    || refuse 'production deploys run only through the Deploy workflow (docs/architecture/ENVIRONMENTS.md).'
  # Anything that serves production traffic waits for the launch gate
  # (docs/security/audit/PRODUCTION-LAUNCH-GATE.md). Allowlist, so it fails
  # closed: only Firestore rules/indexes and Storage rules (which restrict
  # access) pass a closed gate; every other target, however spelled, needs
  # it open. A missing or malformed file, or any value but exactly "open",
  # keeps it shut.
  RESTRICT_ONLY=1
  IFS=',' read -ra TARGETS <<< "$ONLY"
  for target in "${TARGETS[@]}"; do
    [[ "$target" =~ ^(firestore|firestore:rules|firestore:indexes|storage)$ ]] || RESTRICT_ONLY=0
  done
  if [[ "$RESTRICT_ONLY" != 1 ]]; then
    GATE="$(node -e '
      try {
        const g = JSON.parse(require("fs").readFileSync("config/launch_gate.json", "utf8"));
        process.stdout.write(g.productionTraffic === "open" ? "open" : "closed");
      } catch { process.stdout.write("closed"); }
    ' 2>/dev/null || echo closed)"
    [[ "$GATE" == open ]] \
      || refuse "the production launch gate is closed (config/launch_gate.json); '$ONLY' would open production to traffic."
  fi
fi

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

if [[ "${SH_DEPLOY_DRY_RUN:-}" == 1 ]]; then
  echo "deploy gates passed for $ENV ($ONLY); dry run, nothing deployed"
  exit 0
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
