#!/usr/bin/env bash
# verify-sherpa-upstream.sh — checks the upstream sherpa-onnx binaries against
# scripts/sherpa-upstream.pin (ADR 0037). Fail-closed: every pinned file must
# exist and match its SHA-256, the pubspec.lock archive hash and version must
# equal the pin.
#
#   scripts/verify-sherpa-upstream.sh <macos|linux|windows> [--pub-cache DIR] [--bundle DIR]
#
# Default: the files in the pub-cache package (DIR defaults to $PUB_CACHE or
# ~/.pub-cache, hosted/pub.dev). --bundle DIR additionally checks that every file
# found by base name under DIR (the app bundle, Linux/Windows) is byte-identical
# to its pinned hash. macOS bundles are thinned and signed, so only the package
# is verified there (hash before slice selection and signing, ADR 0037).
# Test seams: SHERPA_UPSTREAM_ROOT (repo root), SHERPA_UPSTREAM_PIN (pin file).
set -uo pipefail

ROOT="${SHERPA_UPSTREAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PIN="${SHERPA_UPSTREAM_PIN:-$ROOT/scripts/sherpa-upstream.pin}"
die() { echo "verify-sherpa-upstream: $*" >&2; exit 1; }

platform="${1:-}"
case "$platform" in macos | linux | windows) shift ;; *) die "usage: $0 <macos|linux|windows> [--pub-cache DIR] [--bundle DIR]" ;; esac
cache="${PUB_CACHE:-$HOME/.pub-cache}"
bundle=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pub-cache) cache="${2:-}"; shift 2 ;;
    --bundle) bundle="${2:-}"; shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
pin_value() { sed -n "s/^$1=//p" "$PIN" | head -1; }

[[ -f "$PIN" ]] || die "no pin file $PIN"
version="$(pin_value UPSTREAM_VERSION)"
[[ -n "$version" ]] || die "no UPSTREAM_VERSION in $PIN"
upper="$(printf '%s' "$platform" | tr '[:lower:]' '[:upper:]')"
want_archive="$(pin_value "UPSTREAM_ARCHIVE_SHA256_$upper")"
[[ -n "$want_archive" ]] || die "no archive hash for $platform in $PIN"

# pubspec.lock: version and archive hash of sherpa_onnx_<platform> must equal the pin.
lock="$ROOT/pubspec.lock"
[[ -f "$lock" ]] || die "no $lock"
block="$(awk -v n="  sherpa_onnx_$platform:" '$0 == n { f = 1; next } f && /^  [^ ]/ { exit } f' "$lock")"
lock_hash="$(printf '%s\n' "$block" | sed -n 's/^ *sha256: *"\{0,1\}\([0-9a-f]\{64\}\).*/\1/p' | head -1)"
lock_version="$(printf '%s\n' "$block" | sed -n 's/^ *version: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -1)"
[[ "$lock_version" == "$version" ]] || die "pubspec.lock has sherpa_onnx_$platform ${lock_version:-?}, the pin says $version"
[[ "$lock_hash" == "$want_archive" ]] || die "pubspec.lock archive hash of sherpa_onnx_$platform (${lock_hash:-?}) differs from the pin ($want_archive)"

pkg="$cache/hosted/pub.dev/sherpa_onnx_$platform-$version"
[[ -d "$pkg" ]] || die "package not in the pub cache: $pkg (run flutter pub get --enforce-lockfile)"

fail=0
count=0
names=()
while IFS='|' read -r plat rel want; do
  [[ "$plat" == "$platform" ]] || continue
  count=$((count + 1))
  names+=("$(basename "$rel")|$want")
  if [[ ! -f "$pkg/$rel" ]]; then
    echo "FAIL (missing): $pkg/$rel"
    fail=1
    continue
  fi
  got="$(sha256_of "$pkg/$rel")"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL (hash): $rel is $got, the pin says $want"
    fail=1
  fi
done < <(sed -n 's/^UPSTREAM_FILE=//p' "$PIN")
[[ $count -gt 0 ]] || die "no files pinned for $platform in $PIN"

if [[ -n "$bundle" ]]; then
  [[ "$platform" != macos ]] || die "--bundle is not supported on macos (slice selection and signing change the bytes)"
  [[ -d "$bundle" ]] || die "bundle directory $bundle does not exist"
  for entry in "${names[@]}"; do
    base="${entry%%|*}"
    want="${entry##*|}"
    found="$(find "$bundle" -type f -name "$base" | head -1)"
    if [[ -z "$found" ]]; then
      echo "FAIL (not in bundle): $base"
      fail=1
    elif [[ "$(sha256_of "$found")" != "$want" ]]; then
      echo "FAIL (bundle hash): $found is not the pinned upstream $base"
      fail=1
    fi
  done
fi

[[ $fail -eq 0 ]] || die "FAILED for $platform (sherpa-onnx $version)"
echo "verify-sherpa-upstream: OK ($platform, sherpa-onnx $version, $count pinned file(s)${bundle:+, bundle checked})."
