#!/usr/bin/env bash
# Known-vulnerability gate for the crypto core (D-068). Fails closed.
#
# Runs `cargo audit --deny warnings` on the crypto core's Cargo.lock. Exactly
# three advisories are ignored, each only while the fact that makes it
# inapplicable is re-verified below on every run. If a fact stops holding,
# this script fails, and the ignore must be re-assessed (never just widened).
#
#   RUSTSEC-2026-0330, RUSTSEC-2026-0331 — libcrux-kem 0.0.9 (fixed in 0.0.10).
#     Locked only as an inactive optional dependency (hpke-rs feature
#     `libcrux`, which is off); openmls_rust_crypto 0.6.0 uses the RustCrypto
#     HPKE backend. The crate is never compiled. It cannot be bumped: hpke-rs-
#     libcrux 0.7.0 pins it to =0.0.9 and the fix needs hpke-rs 0.8, which the
#     D-054 OpenMLS pins do not accept.
#   RUSTSEC-2026-0173 — proc-macro-error2 2.0.1 unmaintained (not a
#     vulnerability). Used only by proc-macro crates (hax-lib-macros), so it
#     runs at compile time and never ships in the binary. No release exists.
set -euo pipefail
cd "$(dirname "$0")/../packages/sirf_hum_crypto/native"

fail() { echo "CRYPTO AUDIT FAILED: $*" >&2; exit 1; }

echo "==> re-verify: libcrux-kem / hpke-rs-libcrux are not compiled"
for crate in libcrux-kem hpke-rs-libcrux; do
  # Active graph only (features resolved), every target, normal + build edges.
  graph="$(cargo tree --locked --target all -e normal,build -i "$crate" 2>/dev/null || true)"
  if [ -n "$graph" ]; then
    echo "$graph" >&2
    fail "$crate is now compiled; RUSTSEC-2026-0330/0331 apply. Upgrade or re-assess (D-068)."
  fi
done

echo "==> re-verify: proc-macro-error2 is used only by proc-macro crates"
cargo metadata --locked --format-version 1 | python3 -c '
import json, sys
d = json.load(sys.stdin)
kinds = {p["id"]: {k for t in p["targets"] for k in t["kind"]} for p in d["packages"]}
target = [p["id"] for p in d["packages"] if p["name"] == "proc-macro-error2"]
users = [n["id"] for n in d["resolve"]["nodes"] if any(t in n["dependencies"] for t in target)]
bad = [u for u in users if "proc-macro" not in kinds[u]]
if not users:
    print("proc-macro-error2 no longer used; drop its ignore", file=sys.stderr); sys.exit(1)
if bad:
    print("non-proc-macro users of proc-macro-error2:", bad, file=sys.stderr); sys.exit(1)
' || fail "proc-macro-error2 usage changed; re-assess RUSTSEC-2026-0173 (D-068)."

echo "==> cargo audit --deny warnings (3 documented ignores)"
cargo audit --file Cargo.lock --deny warnings \
  --ignore RUSTSEC-2026-0330 \
  --ignore RUSTSEC-2026-0331 \
  --ignore RUSTSEC-2026-0173

echo "crypto audit passed"
