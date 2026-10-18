#!/usr/bin/env bash
# D-067 invariant: the crypto package pins `hooks` and `code_assets` to exactly
# the versions the installed Flutter SDK's own tool (flutter_tools) uses.
#
# Why: the build hook (packages/sirf_hum_crypto/hook/build.dart) speaks the
# hook protocol of those packages to flutter_tools. A different version can
# drift from the SDK's protocol or, as with hooks 2.x vs Flutter 3.41.5's
# pinned meta 1.17.0, fail to resolve at all. Fails closed.
#
# Usage: check_flutter_hook_pins.sh <package pubspec.yaml> <flutter_tools pubspec.yaml>
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: $0 <package pubspec.yaml> <flutter_tools pubspec.yaml>" >&2; exit 2; }
package_pubspec="$1"
tools_pubspec="$2"
for f in "$package_pubspec" "$tools_pubspec"; do
  [ -f "$f" ] || { echo "HOOK PIN CHECK FAILED: file not found: $f" >&2; exit 1; }
done

# Prints the version of top-level `dependencies:` entry $2 in pubspec $1
# (comments and quotes stripped); prints nothing if absent.
dependency_version() {
  awk -v name="$2" '
    /^[^[:space:]#]/ { in_deps = ($0 ~ /^dependencies:[[:space:]]*(#.*)?$/); next }
    in_deps && $0 ~ "^  " name ":" {
      value = $0
      sub("^  " name ":[[:space:]]*", "", value)
      sub(/[[:space:]]*#.*$/, "", value)
      gsub(/["\047]/, "", value)
      print value
      exit
    }
  ' "$1"
}

exact='^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'
status=0
for dep in hooks code_assets; do
  pinned="$(dependency_version "$package_pubspec" "$dep")"
  sdk="$(dependency_version "$tools_pubspec" "$dep")"
  if [ -z "$pinned" ]; then
    echo "HOOK PIN CHECK FAILED: $dep is not a dependency of $package_pubspec" >&2; status=1
  elif ! [[ "$pinned" =~ $exact ]]; then
    echo "HOOK PIN CHECK FAILED: $dep must be an exact version, got '$pinned' (D-067)" >&2; status=1
  elif [ -z "$sdk" ]; then
    echo "HOOK PIN CHECK FAILED: $dep not found in Flutter SDK $tools_pubspec" >&2; status=1
  elif [ "$pinned" != "$sdk" ]; then
    echo "HOOK PIN CHECK FAILED: $dep is pinned to $pinned but the Flutter SDK uses $sdk." >&2
    echo "  Re-pin $dep to $sdk in $package_pubspec (D-067)." >&2
    status=1
  else
    echo "$dep $pinned matches the Flutter SDK"
  fi
done
exit "$status"
