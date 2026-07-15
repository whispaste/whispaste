#!/usr/bin/env bash
# build-libwhisper-macos.sh — reproducible build of the bundled `libwhisper`
# shared libraries (whisper.cpp v1.8.4, Metal + CPU backends) for the macOS
# `.app`. Produces flat, relocatable dylibs (`@loader_path` rpath, no absolute
# paths) plus a SHA-256 manifest, staged where the Xcode "[WP] Embed & Sign
# libwhisper" build phase (macos/Runner.xcodeproj) picks them up and copies them
# into `Contents/Frameworks/`, signed with the app's identity.
#
# This is the macOS half of the cross-platform bundling for Issue 11 (ADR-01,
# Option C: prebuilt, SHA-256-verified libwhisper embedded into the signed
# bundle — no runtime code download, Apple Guideline 2.5.2). GGML model files
# stay separate (data, still downloadable).
#
# Usage:  scripts/build-libwhisper-macos.sh
# Output: .build/libwhisper/macos/{libwhisper.dylib,libggml*.dylib,SHA256SUMS}
#
# Requires: cmake, Xcode command-line tools (clang, otool, install_name_tool,
# codesign), a checked-out whisper.cpp source tree (see WHISPER_SRC below).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Pinned source provenance (AC3: SHA-256-verified library bezug) ----------
# whisper.cpp v1.8.4, github.com/ggml-org/whisper.cpp, tag v1.8.4.
# The source tree is fetched by Issue 01 into .build/deps (gitignored); its git
# HEAD must match this pinned commit before we build against it.
WHISPER_TAG="v1.8.4"
WHISPER_SRC="$REPO_ROOT/.build/deps/whisper.cpp/$WHISPER_TAG"
WHISPER_PINNED_COMMIT="9386f239401074690479731c1e41683fbbeac557"

BUILD_DIR="$REPO_ROOT/.build/libwhisper/macos-build"
STAGE_DIR="$REPO_ROOT/.build/libwhisper/macos"

echo "=== build-libwhisper-macos ($WHISPER_TAG) ==="

# --- 1. Verify pinned source ------------------------------------------------
if [[ ! -d "$WHISPER_SRC" ]]; then
  echo "ERROR: whisper.cpp source not found at $WHISPER_SRC" >&2
  echo "       Fetch it first (Issue 01): git clone --depth 1 --branch $WHISPER_TAG \\" >&2
  echo "       https://github.com/ggml-org/whisper.cpp \"$WHISPER_SRC\"" >&2
  exit 1
fi
ACTUAL_COMMIT="$(git -C "$WHISPER_SRC" rev-parse HEAD 2>/dev/null || echo 'unknown')"
if [[ "$ACTUAL_COMMIT" != "$WHISPER_PINNED_COMMIT" ]]; then
  echo "ERROR: whisper.cpp source commit mismatch (supply-chain guard)." >&2
  echo "       expected $WHISPER_PINNED_COMMIT" >&2
  echo "       actual   $ACTUAL_COMMIT" >&2
  exit 1
fi
echo "[1/4] source verified: $WHISPER_TAG @ $WHISPER_PINNED_COMMIT"

# --- 2. Configure + build shared libs (Metal + CPU) -------------------------
echo "[2/4] cmake configure + build (Metal + CPU, shared) …"
cmake -S "$WHISPER_SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  >/dev/null
cmake --build "$BUILD_DIR" --config Release -j >/dev/null
echo "      built."

# --- 3. Stage flat, relocatable dylibs --------------------------------------
# Copy every produced dylib (resolving symlinks to the real file) into one flat
# dir, named by its own install-name basename so `@rpath/...` dependency lookups
# resolve. Strip absolute LC_RPATH entries (no home-path leak) and add a single
# portable `@loader_path` rpath so co-located siblings load inside Frameworks/.
echo "[3/4] staging relocatable dylibs → $STAGE_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# Real (non-symlink) dylibs from the build tree.
while IFS= read -r real; do
  install_name="$(otool -D "$real" | sed -n '2p')"          # e.g. @rpath/libggml.0.dylib
  base="$(basename "$install_name")"                          # e.g. libggml.0.dylib
  cp "$real" "$STAGE_DIR/$base"
done < <(find "$BUILD_DIR/src" "$BUILD_DIR/ggml" -type f -name '*.dylib')

# The app opens the plain name; ensure it exists (copy of the SONAME file).
if [[ ! -f "$STAGE_DIR/libwhisper.dylib" ]]; then
  whisper_soname="$(cd "$STAGE_DIR" && ls libwhisper*.dylib | head -n1)"
  cp "$STAGE_DIR/$whisper_soname" "$STAGE_DIR/libwhisper.dylib"
fi

# Make each staged dylib relocatable: remove absolute rpaths, add @loader_path.
for dylib in "$STAGE_DIR"/*.dylib; do
  while IFS= read -r rp; do
    [[ "$rp" == /* ]] && install_name_tool -delete_rpath "$rp" "$dylib" 2>/dev/null || true
  done < <(otool -l "$dylib" | awk '/LC_RPATH/{f=1} f&&/path/{print $2; f=0}')
  install_name_tool -add_rpath "@loader_path" "$dylib" 2>/dev/null || true
done
echo "      staged: $(cd "$STAGE_DIR" && ls *.dylib | tr '\n' ' ')"

# --- 4. SHA-256 manifest (AC3) ----------------------------------------------
echo "[4/4] writing SHA256SUMS"
( cd "$STAGE_DIR" && shasum -a 256 *.dylib > SHA256SUMS )
cat "$STAGE_DIR/SHA256SUMS"

echo "=== done. Now run: flutter build macos ==="
