#!/usr/bin/env bash
# build-libllama-macos.sh — reproducible build of the bundled `libllama`
# shared libraries (llama.cpp b10150, Metal + CPU backends) for the macOS
# `.app`. Produces flat, relocatable dylibs (`@loader_path` rpath, no absolute
# paths) plus a SHA-256 manifest, staged where the Xcode "[WP] Embed & Sign
# libllama" build phase (macos/Runner.xcodeproj) picks them up and copies them
# into `Contents/Frameworks/`, signed with the app's identity.
#
# Smart-Mode-v2 prototype (Gemma-4-E2B on-device text refinement), following
# the exact same bundling pattern already proven in production for whisper.cpp
# (see build-libwhisper-macos.sh) — no runtime code download, Apple Guideline
# 2.5.2. The GGUF model file stays separate (data, downloaded post-install).
#
# ggml namespacing: llama.cpp vendors its own copy of ggml, independently
# pinned from whisper.cpp's vendored copy — the two are not guaranteed
# ABI-compatible. To avoid an install-name collision when both engines'
# dylibs land in the same Contents/Frameworks/ directory, every ggml* dylib
# produced here is renamed with a `-llama` suffix (e.g. `libggml-base.0.dylib`
# -> `libggml-llama-base.0.dylib`) and libllama's own dependency references
# are rewritten to match, isolating it completely from libwhisper's ggml.
#
# Usage:  scripts/build-libllama-macos.sh
# Output: .build/libllama/macos/{libllama.dylib,libggml-llama*.dylib,SHA256SUMS}
#
# Requires: cmake, Xcode command-line tools (clang, otool, install_name_tool,
# codesign), a checked-out llama.cpp source tree (see LLAMA_SRC below).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Pinned source provenance ------------------------------------------------
# llama.cpp b10150, github.com/ggml-org/llama.cpp — the exact build already
# validated end-to-end in the Smart-Mode-v2 spike test (Gemma-4-E2B-it,
# --reasoning off, 17/18 correct on Metal + CPU-only; see
# .scratch/smart-mode-v2/spike-test-results.md), so this pin is not arbitrary.
LLAMA_TAG="b10150"
LLAMA_SRC="$REPO_ROOT/.build/deps/llama.cpp/$LLAMA_TAG"
LLAMA_PINNED_COMMIT="dee2a846b82f15d27f84a48fa387cb53e0d99c25"

BUILD_DIR="$REPO_ROOT/.build/libllama/macos-build"
STAGE_DIR="$REPO_ROOT/.build/libllama/macos"

echo "=== build-libllama-macos ($LLAMA_TAG) ==="

# --- 1. Verify pinned source ------------------------------------------------
if [[ ! -d "$LLAMA_SRC" ]]; then
  echo "ERROR: llama.cpp source not found at $LLAMA_SRC" >&2
  echo "       Fetch it first: git clone https://github.com/ggml-org/llama.cpp \"$LLAMA_SRC\" \\" >&2
  echo "       && git -C \"$LLAMA_SRC\" checkout $LLAMA_PINNED_COMMIT" >&2
  exit 1
fi
ACTUAL_COMMIT="$(git -C "$LLAMA_SRC" rev-parse HEAD 2>/dev/null || echo 'unknown')"
if [[ "$ACTUAL_COMMIT" != "$LLAMA_PINNED_COMMIT" ]]; then
  echo "ERROR: llama.cpp source commit mismatch (supply-chain guard)." >&2
  echo "       expected $LLAMA_PINNED_COMMIT" >&2
  echo "       actual   $ACTUAL_COMMIT" >&2
  exit 1
fi
echo "[1/5] source verified: $LLAMA_TAG @ $LLAMA_PINNED_COMMIT"

# --- 2. Configure + build shared libs (Metal + CPU) -------------------------
echo "[2/5] cmake configure + build (Metal + CPU, shared) …"
cmake -S "$LLAMA_SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_APP=OFF \
  -DLLAMA_OPENSSL=OFF \
  >/dev/null
cmake --build "$BUILD_DIR" --config Release -j >/dev/null
echo "      built."

# --- 3. Stage flat, relocatable, namespaced dylibs --------------------------
echo "[3/5] staging relocatable dylibs → $STAGE_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

while IFS= read -r real; do
  install_name="$(otool -D "$real" | sed -n '2p')"   # e.g. @rpath/libggml.0.dylib
  base="$(basename "$install_name")"                  # e.g. libggml.0.dylib
  cp "$real" "$STAGE_DIR/$base"
done < <(find "$BUILD_DIR/bin" -type f -name '*.dylib' 2>/dev/null)
# libllama-common IS needed here, despite the extra OpenSSL/Security/
# CoreFoundation linkage it drags in (its HTTP-model-download helpers, never
# called by our shim): Gemma-4's `enable_thinking: false` switch — the config
# that made the spike test's Cleanup/Concise/Translate presets fast AND
# reliable (spike-test-results.md) — is only reachable through
# `common_chat_templates_inputs.enable_thinking`, part of the Jinja-based
# chat-templating in common/chat.cpp. The raw `llama_chat_apply_template` C
# API (examples/simple-chat) has no equivalent kwarg support.

if [[ ! -f "$STAGE_DIR/libllama.dylib" ]]; then
  # NOT a wildcard-glob-then-head guess: `libllama-common.0.dylib` also
  # matches `libllama*.dylib` and sorts before `libllama.0.dylib`
  # ('-' < '.' in ASCII), which silently picked the wrong file here once.
  llama_soname="$(cd "$STAGE_DIR" && ls libllama.[0-9]*.dylib | sort -V | head -n1)"
  cp "$STAGE_DIR/$llama_soname" "$STAGE_DIR/libllama.dylib"
fi
echo "      staged (pre-namespacing): $(cd "$STAGE_DIR" && ls *.dylib | tr '\n' ' ')"

# --- 4. Namespace every ggml* dylib with a `-llama` suffix -------------------
# Rewrites both each ggml dylib's own install name (LC_ID_DYLIB) and every
# *consumer's* LC_LOAD_DYLIB reference to it, so libllama.dylib depends on
# `@rpath/libggml-llama-base.0.dylib` etc. instead of the plain `libggml-*`
# names whisper.cpp's own bundled ggml dylibs already occupy in the same
# Frameworks/ directory.
echo "[4/5] namespacing ggml dylibs (-llama suffix, avoids libwhisper collision)"
# bash 3.2 (macOS default /bin/bash) has no associative arrays — use two
# parallel indexed arrays instead of `declare -A`.
OLD_NAMES=()
NEW_NAMES=()
for f in "$STAGE_DIR"/libggml*.dylib; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"                       # libggml-base.0.dylib
  new_base="${base/libggml/libggml-llama}"       # libggml-llama-base.0.dylib
  OLD_NAMES+=("$base")
  NEW_NAMES+=("$new_base")
done

for i in "${!OLD_NAMES[@]}"; do
  mv "$STAGE_DIR/${OLD_NAMES[$i]}" "$STAGE_DIR/${NEW_NAMES[$i]}"
done

for dylib in "$STAGE_DIR"/*.dylib; do
  base="$(basename "$dylib")"
  for i in "${!OLD_NAMES[@]}"; do
    if [[ "$base" == "${NEW_NAMES[$i]}" ]]; then
      install_name_tool -id "@rpath/$base" "$dylib"
    fi
    install_name_tool -change "@rpath/${OLD_NAMES[$i]}" "@rpath/${NEW_NAMES[$i]}" "$dylib" 2>/dev/null || true
  done
done

# Make each staged dylib relocatable: remove absolute rpaths, add @loader_path.
for dylib in "$STAGE_DIR"/*.dylib; do
  while IFS= read -r rp; do
    [[ "$rp" == /* ]] && install_name_tool -delete_rpath "$rp" "$dylib" 2>/dev/null || true
  done < <(otool -l "$dylib" | awk '/LC_RPATH/{f=1} f&&/path/{print $2; f=0}')
  install_name_tool -add_rpath "@loader_path" "$dylib" 2>/dev/null || true
done
echo "      staged: $(cd "$STAGE_DIR" && ls *.dylib | tr '\n' ' ')"

# --- 5. SHA-256 manifest -----------------------------------------------------
echo "[5/5] writing SHA256SUMS"
( cd "$STAGE_DIR" && shasum -a 256 *.dylib > SHA256SUMS )
cat "$STAGE_DIR/SHA256SUMS"

echo "=== done. libllama staged at $STAGE_DIR ==="
