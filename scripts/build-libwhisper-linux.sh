#!/usr/bin/env bash
# build-libwhisper-linux.sh — reproducible build + bundle of `libwhisper` shared
# libraries (whisper.cpp v1.8.4, Vulkan + CPU) for the Linux app bundle.
#
# Mirrors scripts/build-libwhisper-macos.sh: same pinned source, same flat +
# relocatable staging, but with `$ORIGIN` rpath (the ELF equivalent of macOS
# `@loader_path`) so the co-located `libggml*` backends resolve inside the
# Flutter Linux bundle's lib/ directory.
#
# Verified live via WSL2 Ubuntu during v1.2.45 release prep: `ldd` on the
# staged libwhisper.so resolves libggml.so.0/libggml-base.so.0 correctly via
# the $ORIGIN rpath with no extra runtime setup (unlike Windows — its PE
# format has no rpath equivalent, which is why whisper_ffi_engine.dart needs
# a SetDllDirectoryW call there but not here).
#
# -DGGML_BACKEND_DL=ON matters for the same reason as on Windows: without it,
# ggml.so has a hard ELF NEEDED entry on libggml-vulkan.so (which itself needs
# libvulkan.so.1) — a machine with no Vulkan-capable driver at all would fail
# to load ggml.so (and therefore libwhisper.so) even for pure CPU
# transcription. Verified: removing libggml-vulkan.so after a build WITHOUT
# this flag breaks the load; the same removal with the flag set still loads
# fine (the Vulkan backend is now discovered + dlopen'd at runtime by ggml's
# own registry, which silently skips a missing/broken backend).
#
# -DGGML_CPU_ALL_VARIANTS=ON: ships one CPU backend module per x86-64 feature
# level (libggml-cpu-{x64,sse42,sandybridge,haswell,skylakex,icelake,...}.so)
# and lets ggml score them at load time, picking the best one the CPU
# supports. Without it, GGML_NATIVE=OFF yields a single baseline CPU backend
# with no AVX/AVX2 at all. Same flags as build-libllama-linux.sh.
#
# The backend modules are dlopen()ed by ggml's registry, which only scans the
# directory it is told to — WhisperFfiEngine passes libwhisper.so's own
# directory (<bundle>/lib/) to ggml_backend_load_all_from_path, since the
# default search (executable directory + CWD) never sees <bundle>/lib/.
#
# Usage:  [BUILD_JOBS=N] scripts/build-libwhisper-linux.sh [--bundle <flutter-bundle-dir>]
#         [BUILD_JOBS=N] [CUDA_ARCHS=...] scripts/build-libwhisper-linux.sh --cuda
# Output: .build/libwhisper/linux/{libwhisper.so,libggml*.so,libggml-cpu-*.so,
#         libwp_ffi_guard.so,SHA256SUMS}
#         plus debug/<lib>.debug (split DWARF for Sentry, never shipped),
#         and, with --bundle, copies the libraries into <flutter-bundle-dir>/lib/.
#
# --cuda builds ONLY the optional CUDA backend module (libggml-cuda.so) plus
# the CUDA runtime libraries it needs (cudart, cuBLAS, cuBLASLt) into
# .build/libwhisper/linux-cuda/. Same pin and ggml options as the regular
# build, so the module plugs into the shipped libggml-base.so: dropped into
# <bundle>/lib/, ggml_backend_load_all_from_path registers it before Vulkan
# (load order cuda → … → vulkan → cpu), which makes CUDA0 the device
# whisper.cpp picks. Needs nvcc on PATH (scripts/fetch-cuda-redist.py) and
# no Vulkan SDK — Vulkan is off here because ggml-base does not depend on
# which backends are enabled under GGML_BACKEND_DL.
# CUDA_ARCHS defaults to Turing+ (75;86-real;89-real;120-real): real SASS for
# RTX 20/30/40/50 plus sm_75 PTX that the driver JIT-compiles for anything
# newer or in between (A100 sm_80, Hopper, …). Pre-Turing cards stay on Vulkan.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

WHISPER_TAG="v1.8.4"
WHISPER_SRC="$REPO_ROOT/.build/deps/whisper.cpp/$WHISPER_TAG"
WHISPER_PINNED_COMMIT="9386f239401074690479731c1e41683fbbeac557"

BUILD_DIR="$REPO_ROOT/.build/libwhisper/linux-build"
STAGE_DIR="$REPO_ROOT/.build/libwhisper/linux"

BUNDLE_DIR=""
CUDA=0
if [[ "${1:-}" == "--bundle" ]]; then
  BUNDLE_DIR="${2:?--bundle needs a path to the Flutter Linux bundle dir}"
elif [[ "${1:-}" == "--cuda" ]]; then
  CUDA=1
  BUILD_DIR="$REPO_ROOT/.build/libwhisper/linux-cuda-build"
  STAGE_DIR="$REPO_ROOT/.build/libwhisper/linux-cuda"
fi

echo "=== build-libwhisper-linux ($WHISPER_TAG) ==="

# --- 1. Verify pinned source (AC3) ------------------------------------------
if [[ ! -d "$WHISPER_SRC" ]]; then
  echo "ERROR: whisper.cpp source not found at $WHISPER_SRC" >&2
  echo "       git clone --depth 1 --branch $WHISPER_TAG https://github.com/ggml-org/whisper.cpp \"$WHISPER_SRC\"" >&2
  exit 1
fi
ACTUAL_COMMIT="$(git -C "$WHISPER_SRC" rev-parse HEAD 2>/dev/null || echo 'unknown')"
if [[ "$ACTUAL_COMMIT" != "$WHISPER_PINNED_COMMIT" ]]; then
  echo "ERROR: whisper.cpp source commit mismatch (expected $WHISPER_PINNED_COMMIT, got $ACTUAL_COMMIT)" >&2
  exit 1
fi
echo "[1/4] source verified: $WHISPER_TAG @ $WHISPER_PINNED_COMMIT"

if [[ "$CUDA" == 1 ]]; then
  echo "[2/4] cmake configure + build (ggml-cuda module only) …"
  cmake -S "$WHISPER_SRC" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHS:-75;86-real;89-real;120-real}" \
    -DGGML_NATIVE=OFF \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF
  cmake --build "$BUILD_DIR" --config Release --target ggml-cuda \
    -j "${BUILD_JOBS:-$(nproc)}"

  echo "[3/4] staging libggml-cuda.so + CUDA runtime → $STAGE_DIR"
  rm -rf "$STAGE_DIR"
  mkdir -p "$STAGE_DIR"
  module="$(find "$BUILD_DIR" -type f -name 'libggml-cuda.so' | head -n1)"
  [[ -n "$module" ]] || { echo "ERROR: libggml-cuda.so not built" >&2; exit 1; }
  cp "$module" "$STAGE_DIR/"
  # The CUDA runtime libraries the module links, copied under their SONAME
  # from the toolkit. libcuda.so.1 (the driver) is the user's, never shipped.
  while read -r name path; do
    case "$name" in
      libcudart.so.*|libcublas.so.*|libcublasLt.so.*) cp -L "$path" "$STAGE_DIR/$name" ;;
    esac
  done < <(LD_LIBRARY_PATH="${CUDA_HOME:+$CUDA_HOME/lib64:$CUDA_HOME/lib:}${LD_LIBRARY_PATH:-}" \
    ldd "$module" | awk '$2 == "=>" && $3 != "not" { print $1, $3 }')
  for lib in libcudart.so libcublas.so libcublasLt.so; do
    ls "$STAGE_DIR/$lib".* >/dev/null 2>&1 \
      || { echo "ERROR: $lib.* not staged (is CUDA_HOME set?)" >&2; exit 1; }
  done
  for so in "$STAGE_DIR"/*.so*; do
    strip --strip-unneeded "$so"
    patchelf --remove-rpath "$so" 2>/dev/null || true
    patchelf --set-rpath '$ORIGIN' "$so"
  done

  echo "[4/4] writing SHA256SUMS"
  ( cd "$STAGE_DIR" && sha256sum *.so* > SHA256SUMS )
  cat "$STAGE_DIR/SHA256SUMS"
  du -sh "$STAGE_DIR"
  echo "=== done (cuda) ==="
  exit 0
fi

# --- 2. Configure + build shared libs (Vulkan + CPU) ------------------------
# Vulkan is the broadest GPU backend on Linux (NVIDIA/AMD/Intel); CPU is always
# built as the portable fallback. A dedicated CUDA variant is a CI matrix job
# (see .github/workflows/build-whisper-server.yml), out of scope for this host.
echo "[2/4] cmake configure + build (Vulkan + CPU variants, shared, backend-dl) …"
cmake -S "$WHISPER_SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS=-g -DCMAKE_CXX_FLAGS=-g \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_VULKAN=ON \
  -DGGML_NATIVE=OFF \
  -DGGML_BACKEND_DL=ON \
  -DGGML_CPU_ALL_VARIANTS=ON \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF
# BUILD_JOBS caps parallelism (see build-libllama-linux.sh: the CPU-variant +
# Vulkan-shader compile can OOM a small-RAM box with an unbounded -j).
cmake --build "$BUILD_DIR" --config Release -j "${BUILD_JOBS:-$(nproc)}"
# wp_ffi_guard: catches C++ exceptions before they unwind into Dart FFI
# frames (native/ffi_guard/ffi_guard.h). Built inside $BUILD_DIR so the
# staging below picks it up like every other .so.
cmake -S "$REPO_ROOT/native/ffi_guard" -B "$BUILD_DIR/ffi_guard" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS=-g \
  -DWHISPER_SOURCE_DIR="$WHISPER_SRC"
cmake --build "$BUILD_DIR/ffi_guard" --config Release -j "${BUILD_JOBS:-$(nproc)}"
echo "      built."

# --- 3. Stage flat, relocatable ($ORIGIN rpath) shared objects --------------
echo "[3/4] staging relocatable .so → $STAGE_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# Copy each real .so under its SONAME (so DT_NEEDED lookups resolve), set an
# $ORIGIN rpath, and drop absolute/build-tree rpaths (no host-path leak).
while IFS= read -r real; do
  soname="$(patchelf --print-soname "$real" 2>/dev/null || basename "$real")"
  cp "$real" "$STAGE_DIR/$soname"
done < <(find "$BUILD_DIR" -type f -name '*.so*' ! -type l)

if [[ ! -f "$STAGE_DIR/libwhisper.so" ]]; then
  whisper_soname="$(cd "$STAGE_DIR" && ls libwhisper.so* | head -n1)"
  cp "$STAGE_DIR/$whisper_soname" "$STAGE_DIR/libwhisper.so"
fi

for so in "$STAGE_DIR"/*.so*; do
  patchelf --remove-rpath "$so" 2>/dev/null || true
  patchelf --set-rpath '$ORIGIN' "$so" 2>/dev/null || true
done
if ! ls "$STAGE_DIR"/libggml-cpu-*.so >/dev/null 2>&1; then
  echo "ERROR: no CPU backend variants (libggml-cpu-*.so) staged." >&2
  exit 1
fi
echo "      staged: $(cd "$STAGE_DIR" && ls *.so* | tr '\n' ' ')"

# Built with -g for Sentry; ship stripped libraries, keep the DWARF aside.
bash "$REPO_ROOT/scripts/split-debug-linux.sh" "$STAGE_DIR" "$STAGE_DIR/debug"

# --- 4. SHA-256 manifest + optional bundle copy -----------------------------
echo "[4/4] writing SHA256SUMS"
( cd "$STAGE_DIR" && sha256sum *.so* > SHA256SUMS )
cat "$STAGE_DIR/SHA256SUMS"

if [[ -n "$BUNDLE_DIR" ]]; then
  dest="$BUNDLE_DIR/lib"
  echo "Copying staged libraries into Flutter bundle: $dest"
  mkdir -p "$dest"
  cp "$STAGE_DIR"/*.so* "$dest/"

  # Bundle the Silero-VAD model alongside libwhisper.so (see
  # assets/models/vad/NOTICE.md) — a fixed, tiny (<1MB) data file, vendored
  # in the repo rather than built per-platform like the .so files above.
  vad_model="$REPO_ROOT/assets/models/vad/ggml-silero-v5.1.2.bin"
  if [[ -f "$vad_model" ]]; then
    cp "$vad_model" "$dest/"
    echo "Staged ggml-silero-v5.1.2.bin (VAD model) -> $dest"
  else
    echo "warning: VAD model not found ($vad_model) — VAD stays unavailable at runtime."
  fi
fi

echo "=== done ==="
