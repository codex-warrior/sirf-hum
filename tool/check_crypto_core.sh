#!/usr/bin/env bash
# Crypto-core dependency and policy checks (Prompt 06 Part 13). Fails closed.
#
# What it guarantees:
#   - every direct dependency of the crypto core is pinned with `=` (no ranges);
#   - Cargo.lock resolves OpenMLS and its companions to the decided versions
#     (D-054) and is in sync with Cargo.toml (`--locked`);
#   - OpenMLS' secret-logging features (crypto-debug, content-debug) are off;
#   - no logging/printing macros or logging crates are used in src/.
# What it does NOT guarantee: that the pinned code is free of vulnerabilities.
# Known advisories are checked separately by `cargo audit` in CI (RustSec
# database: known issues only, not unknown bugs).
set -euo pipefail
cd "$(dirname "$0")/../packages/sirf_hum_crypto/native"

fail() { echo "CRYPTO-CORE CHECK FAILED: $*" >&2; exit 1; }

echo "==> exact pins in Cargo.toml"
deps="$(awk '/^\[(dev-)?dependencies\]/{on=1; next} /^\[/{on=0} on && /^[a-z0-9_-]+ *=/' Cargo.toml)"
[ -n "$deps" ] || fail "no dependencies parsed"
while IFS= read -r line; do
  case "$line" in
    *'"='*) ;;
    *) fail "dependency not pinned with '=': $line" ;;
  esac
done <<< "$deps"

echo "==> decided versions in Cargo.lock"
expect() {
  local got
  got="$(grep -A1 "^name = \"$1\"$" Cargo.lock | sed -n 's/^version = "\(.*\)"$/\1/p' | sort -u)"
  [ "$got" = "$2" ] || fail "$1 resolves to '${got:-missing}', expected $2 (D-054). Changing it needs a reviewed decision."
}
expect openmls 0.9.1
expect openmls_rust_crypto 0.6.0
expect openmls_traits 0.6.0
expect openmls_basic_credential 0.6.0
expect openmls_memory_storage 0.6.0
expect chacha20poly1305 0.10.1

echo "==> lockfile in sync (cargo metadata --locked)"
cargo metadata --locked --format-version 1 > /dev/null

echo "==> OpenMLS secret-logging features are off"
features="$(cargo tree --locked -e features -i openmls 2>/dev/null || true)"
[ -n "$features" ] || fail "could not inspect openmls features"
if grep -qE 'crypto-debug|content-debug' <<< "$features"; then
  fail "openmls secret-logging feature enabled"
fi

echo "==> no logging or printing in src/"
if grep -rnE 'println!|eprintln!|print!\(|eprint!\(|dbg!|log::|tracing::|debug!\(|info!\(|warn!\(' src/; then
  fail "logging/printing found in crypto core sources"
fi
if grep -nE '^(log|tracing|env_logger|simplelog|fern) *=' Cargo.toml; then
  fail "logging crate dependency"
fi

echo "crypto-core checks passed"
