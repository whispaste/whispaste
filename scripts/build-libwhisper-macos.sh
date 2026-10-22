#!/usr/bin/env bash
# build-libwhisper-macos.sh — reproducible build of the bundled `libwhisper`
# shared libraries (whisper.cpp v1.9.5, Metal + CPU backends) for the macOS
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
# -DGGML_NATIVE=OFF + -DGGML_BACKEND_DL=ON + -DGGML_CPU_ALL_VARIANTS=ON: the
# CPU backend ships as one loadable module per Apple core generation
# (libggml-cpu-{apple_m1,apple_m2_m3,apple_m4}.so) and ggml scores them at
# load time. A native build instead tunes the single CPU backend to the build
# machine: built on an M2+ it contains i8mm instructions (smmla) that an M1
# cannot execute. Metal becomes a module too (libggml-metal.so). ggml names
# backend modules `.so` on macOS; WhisperFfiEngine points
# ggml_backend_load_all_from_path at libwhisper's own directory.
#
# Usage:  scripts/build-libwhisper-macos.sh
# Output: .build/libwhisper/macos/{libwhisper.dylib,libggml*.dylib,
#         libggml-cpu-*.so,libggml-metal.so,libggml-blas.so,
#         libwp_ffi_guard.dylib,SHA256SUMS,WHISPER_PIN}
#
# Requires: cmake, Xcode command-line tools (clang, otool, install_name_tool,
# codesign), a checked-out whisper.cpp source tree (see WHISPER_SRC below).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Pinned source provenance (AC3: SHA-256-verified library bezug) ----------
# whisper.cpp v1.9.5, github.com/ggml-org/whisper.cpp, tag v1.9.5.
# The source tree is fetched by Issue 01 into .build/deps (gitignored); its git
# HEAD must match this pinned commit before we build against it.
WHISPER_TAG="v1.9.5"
WHISPER_SRC="$REPO_ROOT/.build/deps/whisper.cpp/$WHISPER_TAG"
WHISPER_PINNED_COMMIT="d1be6fde11ac6e0407606b4e42fe72d34add8037"

BUILD_DIR="$REPO_ROOT/.build/libwhisper/macos-build"
STAGE_DIR="$REPO_ROOT/.build/libwhisper/macos"

echo "=== build-libwhisper-macos ($WHISPER_TAG) ==="

# --- 1. Verify pinned source ------------------------------------------------
# `.build/` is gitignored per-checkout state (Issue 01 originally fetched it
# once into the main repo checkout, but a `git worktree add` checkout starts
# with an empty `.build/` -- it doesn't inherit the main checkout's build
# cache). Auto-clone here instead of erroring so a fresh worktree/checkout
# self-heals on first build instead of silently shipping broken STT.
if [[ ! -d "$WHISPER_SRC" ]]; then
  echo "note: whisper.cpp source not found at $WHISPER_SRC -- cloning pinned $WHISPER_TAG."
  mkdir -p "$(dirname "$WHISPER_SRC")"
  git clone --depth 1 --branch "$WHISPER_TAG" \
    https://github.com/ggml-org/whisper.cpp "$WHISPER_SRC"
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
  -DGGML_NATIVE=OFF \
  -DGGML_BACKEND_DL=ON \
  -DGGML_CPU_ALL_VARIANTS=ON \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  >/dev/null
cmake --build "$BUILD_DIR" --config Release -j "${BUILD_JOBS:-$(sysctl -n hw.ncpu)}" >/dev/null
# wp_ffi_guard: catches C++ exceptions before they unwind into Dart FFI
# frames (native/ffi_guard/ffi_guard.h). Built against the same headers.
cmake -S "$REPO_ROOT/native/ffi_guard" -B "$BUILD_DIR/ffi_guard" \
  -DCMAKE_BUILD_TYPE=Release \
  -DWHISPER_SOURCE_DIR="$WHISPER_SRC" \
  >/dev/null
cmake --build "$BUILD_DIR/ffi_guard" --config Release -j "${BUILD_JOBS:-$(sysctl -n hw.ncpu)}" >/dev/null
echo "      built."

# --- 3. Stage flat, relocatable dylibs --------------------------------------
# Copy every produced dylib (resolving symlinks to the real file) into one flat
# dir, named by its own install-name basename so `@rpath/...` dependency lookups
# resolve. Strip absolute LC_RPATH entries (no home-path leak) and add a single
# portable `@loader_path` rpath so co-located siblings load inside Frameworks/.
echo "[3/4] staging relocatable dylibs → $STAGE_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# Real (non-symlink) dylibs from the build tree, including libparakeet (the
# GPU Parakeet engine, same ggml backends as libwhisper).
while IFS= read -r real; do
  install_name="$(otool -D "$real" | sed -n '2p')"          # e.g. @rpath/libggml.0.dylib
  base="$(basename "$install_name")"                          # e.g. libggml.0.dylib
  cp "$real" "$STAGE_DIR/$base"
done < <(find "$BUILD_DIR/bin" "$BUILD_DIR/ffi_guard" -type f -name '*.dylib')

# Backend modules (MH_BUNDLE, no install name) keep their file names: ggml's
# registry finds them by the libggml-<backend>[-<variant>].so pattern.
while IFS= read -r module; do
  cp "$module" "$STAGE_DIR/"
done < <(find "$BUILD_DIR/bin" -type f -name 'libggml-*.so')

# The app opens the plain name; ensure it exists (copy of the SONAME file).
if [[ ! -f "$STAGE_DIR/libwhisper.dylib" ]]; then
  whisper_soname="$(cd "$STAGE_DIR" && ls libwhisper*.dylib | head -n1)"
  cp "$STAGE_DIR/$whisper_soname" "$STAGE_DIR/libwhisper.dylib"
fi

# Same plain-name alias for the GPU Parakeet engine (libparakeet.1.dylib ->
# libparakeet.dylib), which the Dart side opens next to libwhisper.
if [[ ! -f "$STAGE_DIR/libparakeet.dylib" ]]; then
  parakeet_soname="$(cd "$STAGE_DIR" && ls libparakeet*.dylib | head -n1)"
  cp "$STAGE_DIR/$parakeet_soname" "$STAGE_DIR/libparakeet.dylib"
fi

# Make each staged library relocatable: remove absolute rpaths, add @loader_path.
for dylib in "$STAGE_DIR"/*.dylib "$STAGE_DIR"/*.so; do
  while IFS= read -r rp; do
    [[ "$rp" == /* ]] && install_name_tool -delete_rpath "$rp" "$dylib" 2>/dev/null || true
  done < <(otool -l "$dylib" | awk '/LC_RPATH/{f=1} f&&/path/{print $2; f=0}')
  install_name_tool -add_rpath "@loader_path" "$dylib" 2>/dev/null || true
done
echo "      staged: $(cd "$STAGE_DIR" && ls *.dylib *.so | tr '\n' ' ')"

# --- 4. SHA-256 manifest (AC3) ----------------------------------------------
echo "[4/4] writing SHA256SUMS"
( cd "$STAGE_DIR" && shasum -a 256 *.dylib *.so > SHA256SUMS )
# Pin stamp: lets the Xcode embed phase notice dylibs staged from an older
# whisper.cpp pin or older native/ffi_guard sources and rebuild them. The
# guard part matters: a stage from before an ABI bump ships a guard the Dart
# side rejects, and without it no ggml backend (not even CPU) gets loaded.
FFI_GUARD_HASH="$(cat "$REPO_ROOT"/native/ffi_guard/* | shasum -a 256 | cut -c1-16)"
echo "$WHISPER_TAG@$WHISPER_PINNED_COMMIT+ffi_guard:$FFI_GUARD_HASH" > "$STAGE_DIR/WHISPER_PIN"
cat "$STAGE_DIR/SHA256SUMS"

echo "=== done. Now run: flutter build macos ==="
