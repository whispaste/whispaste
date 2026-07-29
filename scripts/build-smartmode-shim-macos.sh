#!/usr/bin/env bash
# build-smartmode-shim-macos.sh — compiles native/smart_mode/smart_mode_shim.cpp
# (see smart_mode_shim.h for the public surface) into a relocatable
# `libsmartmode_shim.dylib`, linked against the already-staged `libllama` +
# `libllama-common` produced by build-libllama-macos.sh (run that first).
#
# This shim is WhisPaste's own code, not part of the pinned llama.cpp source
# tree — it wraps llama.cpp's C/C++ API (model load, Jinja chat-templating
# with `enable_thinking`, tokenize/decode/sample loop) behind one exported C
# function, mirroring how whisper.h already gives whisper_ffi_engine.dart a
# single `whisper_full()` call instead of a large low-level API surface.
#
# Usage:  scripts/build-libllama-macos.sh && scripts/build-smartmode-shim-macos.sh
# Output: .build/libllama/macos/libsmartmode_shim.dylib (added to the same
# stage dir + SHA256SUMS the Xcode "[WP] Embed & Sign libllama" phase reads).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

LLAMA_TAG="b10150"
LLAMA_SRC="$REPO_ROOT/.build/deps/llama.cpp/$LLAMA_TAG"
STAGE_DIR="$REPO_ROOT/.build/libllama/macos"
SHIM_SRC="$REPO_ROOT/native/smart_mode/smart_mode_shim.cpp"

echo "=== build-smartmode-shim-macos ==="

if [[ ! -f "$STAGE_DIR/libllama.dylib" ]]; then
  echo "ERROR: $STAGE_DIR/libllama.dylib not found — run scripts/build-libllama-macos.sh first." >&2
  exit 1
fi

LLAMA_COMMON_DYLIB="$(cd "$STAGE_DIR" && ls libllama-common.*.dylib 2>/dev/null | head -n1)"
if [[ -z "$LLAMA_COMMON_DYLIB" ]]; then
  echo "ERROR: libllama-common.*.dylib not found in $STAGE_DIR." >&2
  exit 1
fi

echo "[1/2] compiling smart_mode_shim.cpp"
clang++ -std=c++17 -dynamiclib -O2 \
  -I "$LLAMA_SRC/include" -I "$LLAMA_SRC/ggml/include" -I "$LLAMA_SRC/common" -I "$LLAMA_SRC/vendor" \
  -o "$STAGE_DIR/libsmartmode_shim.dylib" \
  "$SHIM_SRC" \
  "$STAGE_DIR/libllama.dylib" \
  "$STAGE_DIR/$LLAMA_COMMON_DYLIB" \
  "$STAGE_DIR/libggml-llama.0.dylib" \
  "$STAGE_DIR/libggml-llama-base.0.dylib" \
  -install_name "@rpath/libsmartmode_shim.dylib" \
  -Wl,-rpath,@loader_path

echo "[2/2] refreshing SHA256SUMS"
( cd "$STAGE_DIR" && shasum -a 256 *.dylib > SHA256SUMS )
cat "$STAGE_DIR/SHA256SUMS"

echo "=== done. libsmartmode_shim staged at $STAGE_DIR ==="
