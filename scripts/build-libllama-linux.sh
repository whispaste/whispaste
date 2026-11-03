#!/usr/bin/env bash
# build-libllama-linux.sh — reproducible build + bundle of the on-device Smart
# Mode engine for Linux: `libllama` (llama.cpp b10150, Vulkan + CPU backends)
# plus WhisPaste's own `libsmartmode_shim.so` (native/smart_mode/).
#
# Linux equivalent of build-libllama-macos.sh + build-smartmode-shim-macos.sh
# (one script here, like build-libwhisper-linux.sh, since there is no separate
# IDE embed phase to hand off to): same pinned llama.cpp source, same
# flat + relocatable staging, `$ORIGIN` rpath instead of `@loader_path`.
#
# Bundle layout: <flutter-bundle>/lib/smart_mode/ — a subdirectory of the
# lib/ directory libwhisper ships in. Linux needs BOTH isolation measures the
# other platforms use one of each (see smartModeLibraryPathFor in
# lib/services/smart_mode/smart_mode_ffi_engine.dart):
#   1. Own directory (like Windows' smart_mode\): the shim points ggml's
#      backend scan (ggml_backend_load_all_from_path) at its own directory, so
#      it never dlopen()s libwhisper's libggml-cpu.so/libggml-vulkan.so, which
#      are built against whisper.cpp's independently pinned ggml.
#   2. `-llama`-suffixed core ggml SONAMEs (like macOS): the ELF loader dedupes
#      DT_NEEDED entries by SONAME process-wide, regardless of directory or
#      RTLD_LOCAL — an unrenamed `libggml.so.0`/`libggml-base.so.0` would bind
#      libllama to whichever engine's ggml happened to load first. Backend
#      modules keep their file names (the scan matches `libggml-<name>*.so`)
#      but their DT_NEEDED on ggml-base is rewritten to the renamed SONAME.
#
# -DGGML_BACKEND_DL=ON: same reasoning as build-libwhisper-linux.sh — without
# it libggml hard-links libggml-vulkan.so (-> libvulkan.so.1), so a machine
# with no Vulkan driver could not load Smart Mode even for pure CPU use.
# -DGGML_CPU_ALL_VARIANTS=ON: ships one CPU backend per x86-64 feature level
# (sse4.2 … avx512) and lets ggml pick the best one at runtime, instead of a
# single AVX2 build that would SIGILL on older CPUs (hardware inclusivity).
# -DGGML_OPENMP=OFF: same as the Windows build — ggml's own thread pool, no
# extra runtime dependency on libgomp.
#
# Usage:  [BUILD_JOBS=N] scripts/build-libllama-linux.sh [--bundle <flutter-bundle-dir>]
# Output: .build/libllama/linux/{libllama.so.0,libllama-common.so.0,
#         libggml-llama*.so.0,libggml-{cpu-*,vulkan}.so,libsmartmode_shim.so,
#         SHA256SUMS} plus debug/<lib>.debug (split DWARF for Sentry, never
#         shipped) and, with --bundle, copies the libraries into
#         <flutter-bundle-dir>/lib/smart_mode/.
#
# Requires: cmake, g++, patchelf, libvulkan-dev + glslc (Vulkan backend), a
# checked-out llama.cpp source tree (see LLAMA_SRC below).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Pinned source provenance (identical pin to build-libllama-macos.sh) ----
LLAMA_TAG="b10150"
LLAMA_SRC="$REPO_ROOT/.build/deps/llama.cpp/$LLAMA_TAG"
LLAMA_PINNED_COMMIT="dee2a846b82f15d27f84a48fa387cb53e0d99c25"

BUILD_DIR="$REPO_ROOT/.build/libllama/linux-build"
STAGE_DIR="$REPO_ROOT/.build/libllama/linux"
SHIM_SRC="$REPO_ROOT/native/smart_mode/smart_mode_shim.cpp"

BUNDLE_DIR=""
if [[ "${1:-}" == "--bundle" ]]; then
  BUNDLE_DIR="${2:?--bundle needs a path to the Flutter Linux bundle dir}"
fi

echo "=== build-libllama-linux ($LLAMA_TAG) ==="

# --- 1. Verify pinned source -------------------------------------------------
if [[ ! -d "$LLAMA_SRC" ]]; then
  echo "ERROR: llama.cpp source not found at $LLAMA_SRC" >&2
  echo "       git clone --depth 1 --branch $LLAMA_TAG https://github.com/ggml-org/llama.cpp \"$LLAMA_SRC\"" >&2
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

# --- 2. Configure + build shared libs (Vulkan + CPU variants, backend-dl) ---
echo "[2/5] cmake configure + build (Vulkan + CPU variants, shared, backend-dl) …"
cmake -S "$LLAMA_SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS=-g -DCMAKE_CXX_FLAGS=-g \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_VULKAN=ON \
  -DGGML_NATIVE=OFF \
  -DGGML_BACKEND_DL=ON \
  -DGGML_CPU_ALL_VARIANTS=ON \
  -DGGML_OPENMP=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_APP=OFF \
  -DLLAMA_OPENSSL=OFF
# BUILD_JOBS caps parallelism: the CPU-variant + Vulkan-shader compile peaks
# at well over 1 GB per job, so an unbounded -j on a small-RAM box (verified:
# 8 jobs on an 8 GB WSL2 VM) gets cc1plus OOM-killed.
cmake --build "$BUILD_DIR" --config Release -j "${BUILD_JOBS:-$(nproc)}"
echo "      built."

# --- 3. Stage flat, relocatable, namespaced shared objects -------------------
echo "[3/5] staging relocatable .so → $STAGE_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# Copy each real .so under its SONAME (so DT_NEEDED lookups resolve); backend
# modules (no SONAME) keep their file name, which ggml's scan matches on.
while IFS= read -r real; do
  soname="$(patchelf --print-soname "$real" 2>/dev/null || true)"
  [[ -n "$soname" ]] || soname="$(basename "$real")"
  cp "$real" "$STAGE_DIR/$soname"
done < <(find "$BUILD_DIR" -type f -name '*.so*' ! -type l)

for required in libllama.so.0 libggml.so.0 libggml-base.so.0 libggml-vulkan.so; do
  if [[ ! -f "$STAGE_DIR/$required" ]]; then
    echo "ERROR: expected $required in $STAGE_DIR — staged: $(cd "$STAGE_DIR" && ls | tr '\n' ' ')" >&2
    exit 1
  fi
done
if ! ls "$STAGE_DIR"/libllama-common.so* >/dev/null 2>&1; then
  echo "ERROR: libllama-common not staged (the shim needs its chat templating)." >&2
  exit 1
fi
if ! ls "$STAGE_DIR"/libggml-cpu-*.so >/dev/null 2>&1; then
  echo "ERROR: no CPU backend variants (libggml-cpu-*.so) staged." >&2
  exit 1
fi

# Rename the two core ggml libraries (file + SONAME) and rewrite every
# consumer's DT_NEEDED entry to match — see the header for why.
for core in libggml.so.0 libggml-base.so.0; do
  renamed="${core/libggml/libggml-llama}"
  mv "$STAGE_DIR/$core" "$STAGE_DIR/$renamed"
  patchelf --set-soname "$renamed" "$STAGE_DIR/$renamed"
  for so in "$STAGE_DIR"/*.so*; do
    patchelf --replace-needed "$core" "$renamed" "$so"
  done
done

for so in "$STAGE_DIR"/*.so*; do
  patchelf --remove-rpath "$so"
  patchelf --set-rpath '$ORIGIN' "$so"
done

# Hard guard: nothing staged may still reference an unrenamed core ggml.
if readelf -d "$STAGE_DIR"/*.so* | grep -E 'NEEDED.*\[libggml(-base)?\.so'; then
  echo "ERROR: a staged library still depends on an unrenamed core ggml (see above)." >&2
  exit 1
fi
echo "      staged: $(cd "$STAGE_DIR" && ls | tr '\n' ' ')"

# --- 4. Compile WhisPaste's shim against the staged, renamed libraries ------
echo "[4/5] compiling smart_mode_shim.cpp → libsmartmode_shim.so"
LLAMA_COMMON_SO="$(cd "$STAGE_DIR" && ls libllama-common.so* | head -n1)"
g++ -std=c++17 -O2 -g -shared -fPIC \
  -I "$LLAMA_SRC/include" -I "$LLAMA_SRC/ggml/include" -I "$LLAMA_SRC/common" -I "$LLAMA_SRC/vendor" \
  -o "$STAGE_DIR/libsmartmode_shim.so" \
  "$SHIM_SRC" \
  "$STAGE_DIR/libllama.so.0" \
  "$STAGE_DIR/$LLAMA_COMMON_SO" \
  "$STAGE_DIR/libggml-llama.so.0" \
  "$STAGE_DIR/libggml-llama-base.so.0" \
  -ldl \
  -Wl,-soname,libsmartmode_shim.so \
  -Wl,-rpath,'$ORIGIN'
echo "      shim NEEDED: $(readelf -d "$STAGE_DIR/libsmartmode_shim.so" | awk '/NEEDED/{print $5}' | tr -d '[]' | tr '\n' ' ')"

# Built with -g for Sentry; ship stripped libraries, keep the DWARF aside.
bash "$REPO_ROOT/scripts/split-debug-linux.sh" "$STAGE_DIR" "$STAGE_DIR/debug"

# --- 5. SHA-256 manifest + optional bundle copy -----------------------------
echo "[5/5] writing SHA256SUMS"
( cd "$STAGE_DIR" && sha256sum *.so* > SHA256SUMS )
cat "$STAGE_DIR/SHA256SUMS"

if [[ -n "$BUNDLE_DIR" ]]; then
  dest="$BUNDLE_DIR/lib/smart_mode"
  echo "Copying staged libraries into Flutter bundle: $dest"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp "$STAGE_DIR"/*.so* "$dest/"
fi

echo "=== done. libllama + libsmartmode_shim staged at $STAGE_DIR ==="
