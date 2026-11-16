#!/usr/bin/env bash
# ensure-libllama-macos.sh — makes sure .build/libllama/macos holds libllama +
# libsmartmode_shim before a local release build (fastlane mas_release /
# devid_release). Clones the pinned llama.cpp source when it is missing, then
# builds libllama and the shim when they are not staged yet or were staged
# from another pin (LLAMA_PIN stamp). A no-op when both are current; macos/embed_libllama.sh still rebuilds a stale shim.
#
# Usage: scripts/ensure-libllama-macos.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Pinned source: scripts/llama-cpp.pin (one pin for all platforms).
# shellcheck disable=SC1091  # plain KEY=value file
. "$REPO_ROOT/scripts/llama-cpp.pin"
STAGE_DIR="$REPO_ROOT/.build/libllama/macos"

# A stage from before GGML_NATIVE=OFF (no BUILD_FLAVOR stamp) carries
# M2+-only instructions; rebuild it.
if [[ "$(cat "$STAGE_DIR/BUILD_FLAVOR" 2>/dev/null)" != "native-off" ]]; then
  rm -f "$STAGE_DIR/libllama.dylib"
fi

# A stage built from another llama.cpp pin (or without a LLAMA_PIN stamp) would
# fail to link the shim against the new headers; rebuild it.
if [[ "$(cat "$STAGE_DIR/LLAMA_PIN" 2>/dev/null)" != "$LLAMA_TAG $LLAMA_COMMIT" ]]; then
  rm -f "$STAGE_DIR/libllama.dylib"
fi

if [[ -f "$STAGE_DIR/libllama.dylib" && -f "$STAGE_DIR/libsmartmode_shim.dylib" ]]; then
  echo "libllama + smartmode_shim already staged in $STAGE_DIR."
  exit 0
fi

if [[ ! -f "$STAGE_DIR/libllama.dylib" ]]; then
  bash "$REPO_ROOT/scripts/fetch-native-deps.sh" llama
  # Verifies the pinned commit itself (supply-chain guard).
  bash "$REPO_ROOT/scripts/build-libllama-macos.sh"
fi
bash "$REPO_ROOT/scripts/build-smartmode-shim-macos.sh"
