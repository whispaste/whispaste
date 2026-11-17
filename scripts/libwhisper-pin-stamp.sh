#!/usr/bin/env bash
# libwhisper-pin-stamp.sh — prints the macOS libwhisper stage stamp.
# One source for scripts/build-libwhisper-macos.sh (writes WHISPER_PIN) and
# macos/embed_libwhisper.sh (compares it to decide on a rebuild, #397):
#   <tag>@<commit>+ffi_guard:<hash16>+patches:<hash16>+macos:<floor>
# The macos part rebuilds a stage built for another minimum macOS (#1740).
# The guard part matters: a stage from before an ABI bump ships a guard the
# Dart side rejects, and without it no ggml backend (not even CPU) gets loaded.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="$REPO_ROOT/scripts/whisper-cpp.pin"
[[ -f "$PIN_FILE" ]] || { echo "error: $PIN_FILE missing" >&2; exit 1; }
# shellcheck source=whisper-cpp.pin
. "$PIN_FILE"
FFI_GUARD_HASH="$(cat "$REPO_ROOT"/native/ffi_guard/* | shasum -a 256 | cut -c1-16)"
WHISPER_PATCH_HASH="$(cat "$REPO_ROOT"/native/whisper_patches/*.patch | shasum -a 256 | cut -c1-16)"
echo "$WHISPER_TAG@$WHISPER_COMMIT+ffi_guard:$FFI_GUARD_HASH+patches:$WHISPER_PATCH_HASH+macos:13.0"
