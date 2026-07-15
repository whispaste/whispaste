#!/usr/bin/env bash
# build-libwhisper-linux.sh — reproducible build + bundle of `libwhisper` shared
# libraries (whisper.cpp v1.8.4, Vulkan + CPU) for the Linux app bundle.
#
# Mirrors scripts/build-libwhisper-macos.sh: same pinned source, same flat +
# relocatable staging, but with `$ORIGIN` rpath (the ELF equivalent of macOS
# `@loader_path`) so the co-located `libggml*` backends resolve inside the
# Flutter Linux bundle's lib/ directory. Real verification happens on a Linux
# host in Issue 14 (Abnahme Ubuntu); this script is the configured build/bundle
# step, NOT verified on the macOS dev host.
#
# Usage:  scripts/build-libwhisper-linux.sh [--bundle <flutter-bundle-dir>]
# Output: .build/libwhisper/linux/{libwhisper.so,libggml*.so,SHA256SUMS}
#         and, with --bundle, copies them into <flutter-bundle-dir>/lib/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

WHISPER_TAG="v1.8.4"
WHISPER_SRC="$REPO_ROOT/.build/deps/whisper.cpp/$WHISPER_TAG"
WHISPER_PINNED_COMMIT="9386f239401074690479731c1e41683fbbeac557"

BUILD_DIR="$REPO_ROOT/.build/libwhisper/linux-build"
STAGE_DIR="$REPO_ROOT/.build/libwhisper/linux"

BUNDLE_DIR=""
if [[ "${1:-}" == "--bundle" ]]; then
  BUNDLE_DIR="${2:?--bundle needs a path to the Flutter Linux bundle dir}"
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

# --- 2. Configure + build shared libs (Vulkan + CPU) ------------------------
# Vulkan is the broadest GPU backend on Linux (NVIDIA/AMD/Intel); CPU is always
# built as the portable fallback. A dedicated CUDA variant is a CI matrix job
# (see .github/workflows/build-whisper-server.yml), out of scope for this host.
echo "[2/4] cmake configure + build (Vulkan + CPU, shared) …"
cmake -S "$WHISPER_SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_VULKAN=ON \
  -DGGML_NATIVE=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF
cmake --build "$BUILD_DIR" --config Release -j
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
echo "      staged: $(cd "$STAGE_DIR" && ls *.so* | tr '\n' ' ')"

# --- 4. SHA-256 manifest + optional bundle copy -----------------------------
echo "[4/4] writing SHA256SUMS"
( cd "$STAGE_DIR" && sha256sum *.so* > SHA256SUMS )
cat "$STAGE_DIR/SHA256SUMS"

if [[ -n "$BUNDLE_DIR" ]]; then
  dest="$BUNDLE_DIR/lib"
  echo "Copying staged libraries into Flutter bundle: $dest"
  mkdir -p "$dest"
  cp "$STAGE_DIR"/*.so* "$dest/"
fi

echo "=== done ==="
