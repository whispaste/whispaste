#!/usr/bin/env bash
# build-cuda-pack-linux.sh — builds the optional Linux CUDA backend pack
# WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-linux-x64.tar.gz: libggml-cuda.so plus
# the CUDA 12.8.1 runtime libraries it links. Runs inside an ubuntu:24.04 Docker container on
# local-ai-srv; tool/cuda_pack_build.sh drives it from the Mac.
#
# Same whisper.cpp pin, CUDA redist and ggml options as
# `build-libwhisper-linux.sh --cuda`, but this script packs instead of staging:
# only libggml-cuda.so is stripped and gets RUNPATH $ORIGIN, the NVIDIA
# libraries are copied byte-for-byte, and the archive is reproducible.
# libggml-base is deliberately not bundled: the app's libggml-base.so.0
# satisfies the module's NEEDED entry by soname.
#
# Usage:   bash build-cuda-pack-linux.sh --install-deps   (once, as root)
#          [BUILD_JOBS=N] [CUDA_ARCHS=...] [WORK_DIR=...] [OUT_DIR=...] \
#            bash build-cuda-pack-linux.sh
# Output:  $OUT_DIR/WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-linux-x64.tar.gz
set -euo pipefail

PACK_ID="WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-linux-x64"
WHISPER_TAG="v1.9.5"
WHISPER_PINNED_COMMIT="d1be6fde11ac6e0407606b4e42fe72d34add8037"
CUDA_VERSION="12.8.1"
# Turing+ only: real SASS for RTX 20/30/40/50, sm_75 PTX for JIT on anything newer.
CUDA_ARCHS="${CUDA_ARCHS:-75;86-real;89-real;120-real}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/wp-cuda-build}"
OUT_DIR="${OUT_DIR:-$WORK_DIR/out}"
# Versioned by tag: an upgrade clones fresh instead of failing the pin check.
SRC="$WORK_DIR/src/whisper.cpp-$WHISPER_TAG"
CUDA_HOME="$WORK_DIR/cuda"
BUILD="$WORK_DIR/build-$WHISPER_TAG"
STAGE="$WORK_DIR/stage"
NUM_CPUS="$(nproc)"
# At most ~8 parallel jobs: nvcc is memory-hungry per translation unit.
BUILD_JOBS="${BUILD_JOBS:-$(( NUM_CPUS < 8 ? NUM_CPUS : 8 ))}"

if [[ "${1:-}" == "--install-deps" ]]; then
  [[ "$EUID" -eq 0 ]] || { echo "ERROR: --install-deps needs root (run as root, e.g. inside the container)" >&2; exit 1; }
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential cmake make git python3 patchelf binutils ca-certificates
  exit 0
fi

fail() { echo "ERROR: $*" >&2; exit 1; }

echo "=== build-cuda-pack-linux ($PACK_ID) ==="

# --- 0. Toolchain -----------------------------------------------------------
# shellcheck source=/dev/null
. /etc/os-release
echo "distro:  ${PRETTY_NAME} (glibc $(getconf GNU_LIBC_VERSION | awk '{print $2}'))"
[[ "${VERSION_ID:-}" == "24.04" ]] \
  || echo "warning: not Ubuntu 24.04; the app's Linux release is built on 24.04 (glibc 2.39)"
for tool in git cmake make g++ python3 patchelf readelf objdump nm strip ldd; do
  command -v "$tool" >/dev/null \
    || fail "$tool missing (run once as root: bash <this script> --install-deps)"
done
cmake --version | head -n1
g++ --version | head -n1

# --- 1. Pinned whisper.cpp source -------------------------------------------
mkdir -p "$WORK_DIR/src"
if [[ ! -d "$SRC/.git" ]]; then
  git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp "$SRC"
fi
actual_commit="$(git -C "$SRC" rev-parse HEAD)"
[[ "$actual_commit" == "$WHISPER_PINNED_COMMIT" ]] \
  || fail "whisper.cpp commit mismatch (expected $WHISPER_PINNED_COMMIT, got $actual_commit)"
echo "[1/6] source verified: $WHISPER_TAG @ $WHISPER_PINNED_COMMIT"

# --- 2. CUDA toolkit from NVIDIA redist archives (SHA-256 checked) ----------
if [[ ! -x "$CUDA_HOME/bin/nvcc" ]]; then
  python3 "$SCRIPT_DIR/fetch-cuda-redist.py" "$CUDA_VERSION" linux-x86_64 "$CUDA_HOME"
fi
export CUDA_HOME
export PATH="$CUDA_HOME/bin:$PATH"
export CUDACXX="$CUDA_HOME/bin/nvcc"
nvcc --version | tail -n1
echo "[2/6] CUDA $CUDA_VERSION at $CUDA_HOME"

# --- 3. Build the ggml-cuda target only -------------------------------------
echo "[3/6] cmake configure + build (ggml-cuda, archs $CUDA_ARCHS, jobs $BUILD_JOBS) ..."
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHS" \
  -DGGML_NATIVE=OFF \
  -DGGML_BACKEND_DL=ON \
  -DGGML_CPU_ALL_VARIANTS=ON \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF
cmake --build "$BUILD" --config Release --target ggml-cuda -j "$BUILD_JOBS"
module="$(find "$BUILD" -type f -name libggml-cuda.so -print -quit)"
[[ -n "$module" ]] || fail "libggml-cuda.so not built"

# --- 4. Stage the module and the CUDA runtime it links ----------------------
echo "[4/6] staging -> $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$module" "$STAGE/libggml-cuda.so"
# Copy the runtime libraries ggml-cuda resolves, under their SONAMEs. The
# driver (libcuda.so.1) is the user's and never shipped.
while read -r name path; do
  case "$name" in
    libcudart.so.12|libcublas.so.12|libcublasLt.so.12) cp -L "$path" "$STAGE/$name" ;;
  esac
done < <(LD_LIBRARY_PATH="$CUDA_HOME/lib64:$CUDA_HOME/lib" ldd "$module" \
  | awk '$2 == "=>" && $3 != "not" { print $1, $3 }')
for lib in libcudart.so.12 libcublas.so.12 libcublasLt.so.12; do
  [[ -f "$STAGE/$lib" ]] || fail "$lib not resolved for ggml-cuda"
done

# Only the module is modified: stripped, RUNPATH $ORIGIN, so the runtime
# libraries next to it are found without LD_LIBRARY_PATH.
strip --strip-unneeded "$STAGE/libggml-cuda.so"
patchelf --remove-rpath "$STAGE/libggml-cuda.so"
# shellcheck disable=SC2016 # literal $ORIGIN is the ELF token, not a shell variable
patchelf --set-rpath '$ORIGIN' "$STAGE/libggml-cuda.so"

awk -v license="$SRC/LICENSE" '
  $0 == "@WHISPER_LICENSE@" { while ((getline line < license) > 0) print line; close(license); next }
  { print }' "$SCRIPT_DIR/cuda-pack-NOTICE.template.txt" > "$STAGE/NOTICE.txt"

# --- 5. Verify --------------------------------------------------------------
echo "[5/6] verify"
lib="$STAGE/libggml-cuda.so"
# Dynamic section and symbols are captured first: `grep -q` on a pipe can
# SIGPIPE the producer, which pipefail would report as a failure.
dynamic="$(readelf -d "$lib")"
runpath="$(sed -n 's/.*(RUNPATH).*\[\(.*\)\].*/\1/p' <<<"$dynamic")"
# shellcheck disable=SC2016 # literal $ORIGIN, see patchelf above
[[ "$runpath" == '$ORIGIN' ]] || fail "RUNPATH is '$runpath', expected '\$ORIGIN'"
if grep -q '(RPATH)' <<<"$dynamic"; then fail "legacy DT_RPATH present"; fi
symbols="$(nm -D --defined-only "$lib")"
grep -q ' ggml_backend_init$' <<<"$symbols" \
  || fail "libggml-cuda.so does not export ggml_backend_init"

needed="$(sed -n 's/.*(NEEDED).*\[\(.*\)\].*/\1/p' <<<"$dynamic")"
echo "NEEDED:"
while read -r entry; do echo "  $entry"; done <<<"$needed"
# Allowed: our CUDA runtime, ggml-base (app-provided), the driver, glibc/libstdc++.
allowed='^(libcudart\.so\.12|libcublas\.so\.12|libcublasLt\.so\.12|libggml-base\.so\.0|libcuda\.so\.1|libstdc\+\+\.so\.6|libgcc_s\.so\.1|libc\.so\.6|libm\.so\.6|libgomp\.so\.1|ld-linux-x86-64\.so\.2)$'
unexpected="$(grep -vE "$allowed" <<<"$needed" || true)"
[[ -z "$unexpected" ]] || fail "unexpected NEEDED entries: $unexpected"

# ldd in a clean environment, from the staged directory: everything but the
# driver and the app-provided ggml-base must resolve from the pack or the system.
unresolved="$(cd "$STAGE" && env -u LD_LIBRARY_PATH ldd ./libggml-cuda.so \
  | awk '/=> not found/ {print $1}' | grep -vE '^(libcuda\.so\.1|libggml-base\.so\.0)$' || true)"
[[ -z "$unresolved" ]] || fail "unresolved libraries: $unresolved"

# glibc / libstdc++ floor across all shipped ELF files, must not exceed 2.39.
glibc_max="$(cd "$STAGE" && objdump -T ./*.so* | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -n1)"
glibcxx_max="$(cd "$STAGE" && objdump -T ./*.so* | grep -o 'GLIBCXX_[0-9.]*' | sort -uV | tail -n1 || true)"
echo "max GLIBC symbol version:    $glibc_max"
echo "max GLIBCXX symbol version:  ${glibcxx_max:-none}"
top="$(printf '%s\n' "$glibc_max" GLIBC_2.39 | sort -V | tail -n1)"
[[ "$top" == "GLIBC_2.39" ]] || fail "pack needs $glibc_max (> GLIBC_2.39 of ubuntu-24.04)"

# --- 6. SHA-256 manifest and reproducible archive ---------------------------
echo "[6/6] SHA256SUMS + archive"
mapfile -t names < <(cd "$STAGE" && LC_ALL=C ls -1)
(cd "$STAGE" && sha256sum "${names[@]}" > SHA256SUMS)
names+=(SHA256SUMS)
mkdir -p "$OUT_DIR"
archive="$OUT_DIR/$PACK_ID.tar.gz"
# Fixed mtime (source commit time) and owner, gzip -n: same inputs, same bytes.
epoch="$(git -C "$SRC" log -1 --format=%ct)"
tar --format=gnu --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$epoch" \
  -C "$STAGE" -cf - "${names[@]}" | gzip -n -9 > "$archive"

(cd "$STAGE" && ls -l)
echo "unpacked: $(du -cb "$STAGE"/* | tail -n1 | cut -f1) bytes"
ls -l "$archive"
sha256sum "$archive"
echo "=== done (linux pack) ==="
