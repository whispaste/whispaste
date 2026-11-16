#!/usr/bin/env bash
#
# fetch-sparkle.sh — puts the pinned Sparkle.framework into the
# auto_updater_macos fork (packages/auto_updater_macos/macos/Frameworks/).
#
# Sparkle 2.10 left CocoaPods, so the framework is no longer a pod. The
# version and the SHA-256 of the release tarball come from scripts/sparkle.pin
# only; a tarball whose hash differs is never unpacked. The framework is not
# checked in (gitignored).
#
# Run it directly, or source it and call fetch_sparkle (the per-entry form of
# scripts/fetch-native-deps.sh). Does nothing when the target already holds
# the pinned version.
#
#   bash scripts/fetch-sparkle.sh [<frameworks-dir>]
#
# Overrides (tests): SPARKLE_PIN_FILE, SPARKLE_DOWNLOAD_URL, SPARKLE_CACHE_DIR.

set -euo pipefail

FETCH_SPARKLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# sparkle_pin <KEY> — prints the value of KEY from the pin file.
sparkle_pin() {
  local pin="${SPARKLE_PIN_FILE:-$FETCH_SPARKLE_ROOT/scripts/sparkle.pin}"
  local value
  value="$(sed -n "s/^$1=//p" "$pin" | head -1)"
  if [[ -z "$value" ]]; then
    echo "fetch-sparkle: no $1 in $pin" >&2
    return 1
  fi
  printf '%s' "$value"
}

_sparkle_sha256() {
  if command -v shasum >/dev/null; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

# fetch_sparkle_tarball — prints the path of the pinned release tarball,
# downloading it into the cache first. The hash is checked on every call, so
# a cached file that changed is rejected too.
fetch_sparkle_tarball() {
  local version sha cache tarball url tmp actual
  version="$(sparkle_pin SPARKLE_VERSION)" || return 1
  sha="$(sparkle_pin SPARKLE_SHA256)" || return 1
  cache="${SPARKLE_CACHE_DIR:-$HOME/.cache/sparkle/$version}"
  tarball="$cache/Sparkle-$version.tar.xz"
  if [[ ! -f "$tarball" ]]; then
    url="${SPARKLE_DOWNLOAD_URL:-https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz}"
    mkdir -p "$cache"
    tmp="$(mktemp "$cache/.tmp.XXXXXX")"
    if ! curl -fsSL -o "$tmp" "$url"; then
      rm -f "$tmp"
      echo "fetch-sparkle: download failed: $url" >&2
      return 1
    fi
    mv "$tmp" "$tarball"
  fi
  actual="$(_sparkle_sha256 "$tarball")"
  if [[ "$actual" != "$sha" ]]; then
    rm -f "$tarball"
    echo "fetch-sparkle: SHA-256 mismatch for Sparkle-$version.tar.xz" >&2
    echo "  expected $sha" >&2
    echo "  got      $actual" >&2
    return 1
  fi
  printf '%s' "$tarball"
}

# _sparkle_installed_version <framework> — CFBundleShortVersionString or "".
_sparkle_installed_version() {
  local plist="$1/Resources/Info.plist"
  [[ -f "$plist" ]] || return 0
  sed -n '/<key>CFBundleShortVersionString<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$plist"
}

# fetch_sparkle [<frameworks-dir>] — installs Sparkle.framework there.
fetch_sparkle() {
  local dir="${1:-$FETCH_SPARKLE_ROOT/packages/auto_updater_macos/macos/Frameworks}"
  local version tarball work
  version="$(sparkle_pin SPARKLE_VERSION)" || return 1
  if [[ "$(_sparkle_installed_version "$dir/Sparkle.framework")" == "$version" ]]; then
    return 0
  fi
  tarball="$(fetch_sparkle_tarball)" || return 1
  mkdir -p "$dir"
  work="$(mktemp -d "$dir/.tmp.XXXXXX")"
  # Unpacked next to the target, so the final mv stays on one volume.
  if ! tar -xJf "$tarball" -C "$work" ./Sparkle.framework; then
    rm -rf "$work"
    echo "fetch-sparkle: no Sparkle.framework in the tarball" >&2
    return 1
  fi
  # tar keeps the Versions/Current symlinks; cp -R without -P would not.
  rm -rf "$dir/Sparkle.framework"
  mv "$work/Sparkle.framework" "$dir/Sparkle.framework"
  rm -rf "$work"
  echo "fetch-sparkle: Sparkle $version -> $dir/Sparkle.framework"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  fetch_sparkle "$@"
fi
