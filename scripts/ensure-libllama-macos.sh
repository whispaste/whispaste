#!/usr/bin/env bash
# ensure-libllama-macos.sh — makes sure .build/libllama/macos holds libllama +
# libsmartmode_shim before a local release build (fastlane mas_release /
# devid_release). Clones the pinned llama.cpp source when it is missing, then
# builds libllama and the shim when they are not staged yet. A no-op when
# both are already staged; macos/embed_libllama.sh still rebuilds a stale shim.
#
# Usage: scripts/ensure-libllama-macos.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_TAG="b10150"  # keep in sync with build-libllama-macos.sh
LLAMA_SRC="$REPO_ROOT/.build/deps/llama.cpp/$LLAMA_TAG"
STAGE_DIR="$REPO_ROOT/.build/libllama/macos"

# A stage from before GGML_NATIVE=OFF (no BUILD_FLAVOR stamp) carries
# M2+-only instructions; rebuild it.
if [[ "$(cat "$STAGE_DIR/BUILD_FLAVOR" 2>/dev/null)" != "native-off" ]]; then
  rm -f "$STAGE_DIR/libllama.dylib"
fi

if [[ -f "$STAGE_DIR/libllama.dylib" && -f "$STAGE_DIR/libsmartmode_shim.dylib" ]]; then
  echo "libllama + smartmode_shim already staged in $STAGE_DIR."
  exit 0
fi

if [[ ! -f "$STAGE_DIR/libllama.dylib" ]]; then
  if [[ ! -d "$LLAMA_SRC" ]]; then
    git clone --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp "$LLAMA_SRC"
  fi
  # Verifies the pinned commit itself (supply-chain guard).
  bash "$REPO_ROOT/scripts/build-libllama-macos.sh"
fi
bash "$REPO_ROOT/scripts/build-smartmode-shim-macos.sh"
