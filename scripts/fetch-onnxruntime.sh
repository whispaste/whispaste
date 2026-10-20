#!/usr/bin/env bash
# fetch-onnxruntime.sh — downloads one pinned onnxruntime archive into a
# directory and verifies its SHA-256 against scripts/sherpa-onnx.pin before the
# file is ever handed to cmake (GS-008). Usage:
#   scripts/fetch-onnxruntime.sh osx|linux-x64|linux-aarch64 <dest-dir>
# Prints the verified path. Exits non-zero on a download or hash mismatch.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091  # scripts/sherpa-onnx.pin: plain KEY=value file
. "$REPO_ROOT/scripts/sherpa-onnx.pin"

[[ $# -eq 2 ]] || { echo "usage: $0 osx|linux-x64|linux-aarch64 <dest-dir>" >&2; exit 2; }
case "$1" in
  osx) name="$ORT_OSX_UNIVERSAL"; want="$ORT_OSX_UNIVERSAL_SHA256" ;;
  linux-x64) name="$ORT_LINUX_X64"; want="$ORT_LINUX_X64_SHA256" ;;
  linux-aarch64) name="$ORT_LINUX_AARCH64"; want="$ORT_LINUX_AARCH64_SHA256" ;;
  *) echo "error: unknown onnxruntime target '$1'" >&2; exit 2 ;;
esac
dest="$2"
mkdir -p "$dest"
url="https://github.com/csukuangfj/onnxruntime-libs/releases/download/v${ORT_VERSION}/${name}"
out="$dest/$name"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

if [[ -f "$out" ]] && [[ "$(sha256_of "$out")" == "$want" ]]; then
  echo "$out"
  exit 0
fi
tmp="$out.partial"
curl --fail --location --retry 3 --retry-delay 5 --silent --show-error -o "$tmp" "$url"
got="$(sha256_of "$tmp")"
if [[ "$got" != "$want" ]]; then
  rm -f "$tmp"
  echo "error: onnxruntime $name has SHA-256 $got, pinned $want. Refusing to use it." >&2
  exit 1
fi
mv -f "$tmp" "$out"
echo "$out"
