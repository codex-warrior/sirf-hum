#!/usr/bin/env bash
# Tests for the production deploy gates in tool/deploy.sh (D-137).
# Hermetic: runs a copy of deploy.sh inside a throwaway git repository with
# SH_DEPLOY_DRY_RUN=1, which exits after the gates. Nothing is ever deployed
# and no credentials are needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/tool" "$WORK/config"
cp "$ROOT/tool/deploy.sh" "$WORK/tool/deploy.sh"
cp "$ROOT/config/launch_gate.json" "$WORK/config/launch_gate.json"
git -C "$WORK" init -q -b main
git -C "$WORK" -c user.email=t@example.invalid -c user.name=t add -A
git -C "$WORK" -c user.email=t@example.invalid -c user.name=t commit -qm init

PASS=0
FAIL=0
# expect <pass|refuse> <message substring> <env assignments...> -- <deploy args...>
expect() {
  local want="$1" needle="$2"
  shift 2
  local envs=()
  while [[ "$1" != -- ]]; do envs+=("$1"); shift; done
  shift
  local out status=0
  out="$(cd "$WORK" && env -u GITHUB_ACTIONS -u SH_CONFIRM_PRODUCTION SH_DEPLOY_DRY_RUN=1 "${envs[@]}" \
    bash tool/deploy.sh "$@" 2>&1 < /dev/null)" || status=$?
  local ok=1
  if [[ "$want" == pass && "$status" -ne 0 ]]; then ok=0; fi
  if [[ "$want" == refuse && "$status" -eq 0 ]]; then ok=0; fi
  if [[ "$out" != *"$needle"* ]]; then ok=0; fi
  if [[ "$ok" == 1 ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: expected $want ('$needle') for: ${envs[*]} deploy.sh $*" >&2
    echo "$out" | sed 's/^/    /' >&2
  fi
}

CI=(GITHUB_ACTIONS=true SH_CONFIRM_PRODUCTION=sirf-hum-prod)

# Production never deploys from a laptop.
expect refuse 'only through the Deploy workflow' -- production --only firestore:rules
expect refuse 'only through the Deploy workflow' SH_CONFIRM_PRODUCTION=sirf-hum-prod -- production

# Closed gate: everything that serves traffic is refused, however spelled.
expect refuse 'launch gate is closed' "${CI[@]}" -- production --only functions
expect refuse 'launch gate is closed' "${CI[@]}" -- production --only hosting:app
expect refuse 'launch gate is closed' "${CI[@]}" -- production --only 'firestore:rules, functions'
expect refuse 'launch gate is closed' "${CI[@]}" -- production --only firestore:rules,extensions
expect refuse 'launch gate is closed' "${CI[@]}" -- production --only functions:unpairCouple
expect refuse 'launch gate is closed' "${CI[@]}" -- production --only firestore,storage,functions,hosting

# Closed gate: restrictive targets still pass (rules only narrow access).
expect pass 'deploy gates passed' "${CI[@]}" -- production
expect pass 'deploy gates passed' "${CI[@]}" -- production --only firestore:rules,firestore:indexes
expect pass 'deploy gates passed' "${CI[@]}" -- production --only storage

# The other production gates still apply.
expect refuse 'Confirmation did not match' GITHUB_ACTIONS=true SH_CONFIRM_PRODUCTION=sirf-hum-dev -- production
git -C "$WORK" checkout -q -b feature/x
expect refuse 'only from main' "${CI[@]}" -- production
git -C "$WORK" checkout -q main
echo dirty > "$WORK/dirty.txt"
expect refuse 'dirty working tree' "${CI[@]}" -- production
rm "$WORK/dirty.txt"

# Development and staging are not affected by the launch gate.
expect pass 'deploy gates passed' -- development --only functions
expect pass 'deploy gates passed' -- staging --only hosting:app

# Opening the gate needs exactly "open"; anything else stays closed.
commit_gate() {
  mkdir -p "$WORK/config"
  printf '%s' "$1" > "$WORK/config/launch_gate.json"
  git -C "$WORK" add config/launch_gate.json
  git -C "$WORK" -c user.email=t@example.invalid -c user.name=t commit -qm gate
}
commit_gate '{"productionTraffic":"Open"}'
expect refuse 'launch gate is closed' "${CI[@]}" -- production --only functions
commit_gate '{"productionTraffic":true}'
expect refuse 'launch gate is closed' "${CI[@]}" -- production --only functions
commit_gate 'not json'
expect refuse 'launch gate is closed' "${CI[@]}" -- production --only functions
git -C "$WORK" rm -q config/launch_gate.json
git -C "$WORK" -c user.email=t@example.invalid -c user.name=t commit -qm 'no gate'
expect refuse 'launch gate is closed' "${CI[@]}" -- production --only functions
commit_gate '{"productionTraffic":"open"}'
expect pass 'deploy gates passed' "${CI[@]}" -- production --only functions
expect pass 'deploy gates passed' "${CI[@]}" -- production --only hosting:app
# Even open, production still never deploys from a laptop.
expect refuse 'only through the Deploy workflow' SH_CONFIRM_PRODUCTION=sirf-hum-prod -- production --only functions

echo "deploy guard tests: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
