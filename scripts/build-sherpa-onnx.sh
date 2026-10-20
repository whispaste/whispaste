#!/usr/bin/env bash
# build-sherpa-onnx.sh — builds sherpa-onnx's C API (libsherpa-onnx-c-api) from
# the pinned tag WITHOUT text-to-speech, and stages it for the app bundle.
#
# Why: the sherpa_onnx pub package ships prebuilt C-API libraries that contain
# espeak-ng (GPL-3.0-or-later) statically via the TTS frontends. WhisPaste is
# MIT, uses no TTS, and ships through the Mac App Store and MSIX. With
# -DSHERPA_ONNX_ENABLE_TTS=OFF the espeak-ng and piper-phonemize sources are
# never fetched or linked. The Dart bindings stay the pub package's; only the
# native library is replaced (see macos/embed_sherpa_onnx.sh and the Linux /
# Windows CMake overrides).
#
# Verified (probe builds, see BUILD.md): macOS universal, Linux x64, Linux
# aarch64 (cross build) and Windows x64 export the same 172 SherpaOnnx* symbols
# as the pub originals, contain no espeak-ng marker, and produce identical
# recognition output with the parakeet-tdt-0.6b-v3 model.
#
# Usage:
#   scripts/build-sherpa-onnx.sh macos
#   scripts/build-sherpa-onnx.sh linux
#   scripts/build-sherpa-onnx.sh linux --toolchain <cmake-toolchain> --stage-name linux-aarch64
#
# Output: .build/sherpa-onnx/<stage-name>/ (the shared library set + BUILD_INFO).
# Windows: scripts/build-sherpa-onnx.ps1 (same pins, same stage layout).
set -euo pipefail

# Pinned source: scripts/sherpa-onnx.pin (shared with the Windows script and
# the stage check). The tag must match the sherpa_onnx version in pubspec.lock.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091  # scripts/sherpa-onnx.pin: plain KEY=value file
. "$REPO_ROOT/scripts/sherpa-onnx.pin"
SHERPA_REPO="https://github.com/k2-fsa/sherpa-onnx"

# macOS deployment target = the app's MACOSX_DEPLOYMENT_TARGET (macos/Runner.xcodeproj).
MACOS_DEPLOYMENT_TARGET="12.0"

usage() {
  echo "usage: $0 macos|linux [--toolchain <file>] [--stage-name <name>]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
PLATFORM="$1"
shift
case "$PLATFORM" in
  macos|linux) ;;
  *) usage ;;
esac

TOOLCHAIN=""
STAGE_NAME="$PLATFORM"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --toolchain) TOOLCHAIN="${2:?--toolchain needs a file}"; shift 2 ;;
    --stage-name) STAGE_NAME="${2:?--stage-name needs a name}"; shift 2 ;;
    *) usage ;;
  esac
done

SRC="$REPO_ROOT/.build/deps/sherpa-onnx/$SHERPA_TAG"
BUILD="$REPO_ROOT/.build/sherpa-onnx/$STAGE_NAME-build"
STAGE="$REPO_ROOT/.build/sherpa-onnx/$STAGE_NAME"

# 1. Fetch the pinned tag and verify the commit (supply-chain guard).
if [[ ! -d "$SRC/.git" ]]; then
  mkdir -p "$(dirname "$SRC")"
  git clone --depth 1 --branch "$SHERPA_TAG" "$SHERPA_REPO" "$SRC"
fi
actual_commit="$(git -C "$SRC" rev-parse HEAD)"
if [[ "$actual_commit" != "$SHERPA_COMMIT" ]]; then
  echo "error: $SRC is at $actual_commit, expected $SHERPA_COMMIT ($SHERPA_TAG)." >&2
  echo "       Remove $SRC and re-run to re-clone the pinned tag." >&2
  exit 1
fi

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

# Configure: shared C API only, TTS and everything else off.
CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=ON
  -DSHERPA_ONNX_ENABLE_TTS=OFF
  -DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF
  -DSHERPA_ONNX_ENABLE_PYTHON=OFF
  -DSHERPA_ONNX_ENABLE_TESTS=OFF
  -DSHERPA_ONNX_ENABLE_BINARY=OFF
  -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF
  -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF
  -DSHERPA_ONNX_ENABLE_JNI=OFF
  -DSHERPA_ONNX_ENABLE_C_API=ON
)
if [[ "$PLATFORM" == "macos" ]]; then
  # Universal: the pub original is x86_64 + arm64 and the app ships both.
  CMAKE_ARGS+=(
    "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET"
  )
  # Reproducible output (GS-013): the same sources must give the same library
  # hash in any checkout and under any caller. Xcode exports SDKROOT and picks
  # its own SDK, so pin the SDK explicitly, and map the repo root to a fixed
  # prefix so __FILE__ and assert strings do not embed the checkout path.
  # The compiler itself (CMAKE_C_COMPILER/CMAKE_CXX_COMPILER) is not set here:
  # changing it in an existing cache makes CMake demand a cache reset.
  CMAKE_ARGS+=(
    "-DCMAKE_OSX_SYSROOT=$(xcrun --sdk macosx --show-sdk-path)"
    "-DCMAKE_C_FLAGS=-ffile-prefix-map=$REPO_ROOT=/wp-repo"
    "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=$REPO_ROOT=/wp-repo"
  )
fi
if [[ -n "$TOOLCHAIN" ]]; then
  CMAKE_ARGS+=("-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN")
fi

# 2. Fetch onnxruntime ourselves and verify its SHA-256 (scripts/fetch-onnxruntime.sh)
# so cmake never downloads an unverified archive (GS-008). sherpa's cmake takes a
# local archive from the build directory and still checks the hash it pins; the
# build also asserts that sherpa pins the same hash as scripts/sherpa-onnx.pin.
case "$STAGE_NAME" in
  macos) ORT_TARGET=osx; SHERPA_ORT_CMAKE=onnxruntime-osx-universal.cmake; ORT_PIN=ORT_OSX_UNIVERSAL_SHA256 ;;
  linux-aarch64) ORT_TARGET=linux-aarch64; SHERPA_ORT_CMAKE=onnxruntime-linux-aarch64.cmake; ORT_PIN=ORT_LINUX_AARCH64_SHA256 ;;
  linux) ORT_TARGET=linux-x64; SHERPA_ORT_CMAKE=onnxruntime-linux-x86_64.cmake; ORT_PIN=ORT_LINUX_X64_SHA256 ;;
  *) echo "error: no onnxruntime pin for stage '$STAGE_NAME'" >&2; exit 1 ;;
esac
pinned_hash="${!ORT_PIN}"
if ! grep -q "$pinned_hash" "$SRC/cmake/$SHERPA_ORT_CMAKE"; then
  echo "error: sherpa-onnx $SHERPA_TAG cmake/$SHERPA_ORT_CMAKE does not pin SHA-256 $pinned_hash." >&2
  echo "       Update scripts/sherpa-onnx.pin to match sherpa's onnxruntime pin before building." >&2
  exit 1
fi
mkdir -p "$BUILD"
bash "$REPO_ROOT/scripts/fetch-onnxruntime.sh" "$ORT_TARGET" "$BUILD" >/dev/null

echo "==> configure $STAGE_NAME ($SHERPA_TAG, TTS=OFF) -> $BUILD"
nice -n 19 cmake -S "$SRC" -B "$BUILD" "${CMAKE_ARGS[@]}" || {
  echo "error: cmake configure failed." >&2
  exit 1
}

# 3. Build only the C API target (takes ~6 min for macOS universal with -j$JOBS).
echo "==> build sherpa-onnx-c-api (-j$JOBS)"
nice -n 19 cmake --build "$BUILD" --target sherpa-onnx-c-api --config Release -j "$JOBS"

# 4. Stage the library set. Copy the real files (-L follows symlinks).
# Only this platform's format: a literal .dylib name made `cp` fail on Linux.
# shellcheck source=scripts/sherpa-stage-libs.sh
. "$REPO_ROOT/scripts/sherpa-stage-libs.sh"
staged_list="$(sherpa_stage_libs "$PLATFORM" "$BUILD")" || exit 1
libs=()  # no mapfile: macOS runs this with bash 3.2
while IFS= read -r lib; do libs+=("$lib"); done <<<"$staged_list"
rm -rf "$STAGE"
mkdir -p "$STAGE"
for lib in "${libs[@]}"; do
  cp -L "$lib" "$STAGE/"
done

{
  echo "sherpa-onnx $SHERPA_TAG ($SHERPA_COMMIT)"
  echo "platform: $STAGE_NAME"
  echo "tts: OFF (no espeak-ng, no piper-phonemize)"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # SHA-256 of every staged file, checked after the cache restore (GS-007).
  for f in "$STAGE"/*; do
    name="$(basename "$f")"
    [[ "$name" == BUILD_INFO ]] && continue
    if command -v sha256sum >/dev/null 2>&1; then h="$(sha256sum "$f" | cut -d' ' -f1)"
    else h="$(shasum -a 256 "$f" | cut -d' ' -f1)"; fi
    echo "sha256 $name $h"
  done
} > "$STAGE/BUILD_INFO"

# 5. Refuse to stage anything that does not match the pins, or that still
# carries espeak-ng.
cmake -DSTAGE_DIR="$STAGE" -DREPO_ROOT="$REPO_ROOT" -P "$REPO_ROOT/scripts/check-sherpa-stage.cmake"
bash "$REPO_ROOT/scripts/check-no-espeak.sh" "$STAGE"
echo "==> staged in $STAGE:"
ls -la "$STAGE"
