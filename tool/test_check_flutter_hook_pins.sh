#!/usr/bin/env bash
# Deterministic tests for tool/check_flutter_hook_pins.sh (D-067), using
# fixture pubspecs only (no network, no Flutter SDK needed).
set -euo pipefail
check="$(cd "$(dirname "$0")" && pwd)/check_flutter_hook_pins.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
# expect <pass|fail> <name> <package hooks> <package code_assets> <sdk hooks> <sdk code_assets>
expect() {
  local want="$1" name="$2"
  cat > "$tmp/package.yaml" <<EOF
name: sirf_hum_crypto
dependencies:
  code_assets: $4
  ffi: 2.2.0
  hooks: $3

dev_dependencies:
  test: 1.33.0
EOF
  cat > "$tmp/tools.yaml" <<EOF
name: flutter_tools
dependencies:
  hooks: $5
  code_assets: $6 # pinned by the SDK

dev_dependencies:
  hooks: 9.9.9
EOF
  local got=pass
  "$check" "$tmp/package.yaml" "$tmp/tools.yaml" > /dev/null 2>&1 || got=fail
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: expected $want, got $got"
    failures=$((failures + 1))
  fi
}

expect pass 'matching versions'                1.0.0   1.0.0   1.0.0 1.0.0
expect fail 'hooks differs from SDK'           2.2.0   1.0.0   1.0.0 1.0.0
expect fail 'code_assets differs from SDK'     1.0.0   2.1.0   1.0.0 1.0.0
expect fail 'range instead of exact pin'       ^1.0.0  1.0.0   1.0.0 1.0.0
expect pass 'quoted exact pin matches'         '"1.0.0"' 1.0.0 1.0.0 1.0.0
expect fail 'SDK entry missing'                1.0.0   1.0.0   ''    1.0.0

# Missing input files fail closed.
if "$check" "$tmp/nope.yaml" "$tmp/tools.yaml" > /dev/null 2>&1; then
  echo "FAIL missing file: expected fail, got pass"; failures=$((failures + 1))
else
  echo "ok   missing file fails closed"
fi

[ "$failures" -eq 0 ] || { echo "$failures hook pin check test(s) failed" >&2; exit 1; }
echo "hook pin check tests passed"
