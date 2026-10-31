#!/usr/bin/env bash
# sherpa-stage-libs.test.sh — tests for scripts/sherpa-stage-libs.sh, the list of
# files build-sherpa-onnx.sh stages. Builds fake build trees at runtime:
#   1. Linux tree (versioned .so + symlinks)  -> only .so files, no .dylib
#   2. macOS tree                             -> only .dylib files, no .so
#   3. C API library missing                  -> FAIL with a message
#   4. onnxruntime missing                    -> FAIL with a message
#   5. the other platform's files only        -> FAIL (never stage a foreign set)
#   6. unknown platform                       -> FAIL
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sherpa-stage-libs.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=scripts/sherpa-stage-libs.sh
. "$REPO_ROOT/scripts/sherpa-stage-libs.sh"

failures=0
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# run <platform> <build-dir>: sets OUT (stdout, basenames), ERR, RC.
run() {
  local rc
  sherpa_stage_libs "$1" "$2" >"$WORK/out.txt" 2>"$WORK/err.txt"
  rc=$?
  RC=$rc
  OUT="$(xargs -r -n1 basename <"$WORK/out.txt" | sort | tr '\n' ' ')"
  ERR="$(cat "$WORK/err.txt")"
}

tree() { # tree <dir> <relative files...>
  local dir="$1"; shift
  mkdir -p "$dir/lib" "$dir/_deps/onnxruntime-src/lib"
  local f
  for f in "$@"; do : >"$dir/$f"; done
}

# 1. Linux.
L="$WORK/linux"
tree "$L" lib/libsherpa-onnx-c-api.so _deps/onnxruntime-src/lib/libonnxruntime.so.1.23.2
ln -s libonnxruntime.so.1.23.2 "$L/_deps/onnxruntime-src/lib/libonnxruntime.so"
run linux "$L"
if [[ $RC -eq 0 && "$OUT" == "libonnxruntime.so libonnxruntime.so.1.23.2 libsherpa-onnx-c-api.so " ]]; then
  echo "ok   - linux stages the .so set"
else
  fail "linux: rc=$RC out='$OUT' err='$ERR'"
fi

# 2. macOS.
M="$WORK/macos"
tree "$M" lib/libsherpa-onnx-c-api.dylib _deps/onnxruntime-src/lib/libonnxruntime.1.23.2.dylib
run macos "$M"
if [[ $RC -eq 0 && "$OUT" == "libonnxruntime.1.23.2.dylib libsherpa-onnx-c-api.dylib " ]]; then
  echo "ok   - macos stages the .dylib set"
else
  fail "macos: rc=$RC out='$OUT' err='$ERR'"
fi

# 3. C API missing.
N="$WORK/no-capi"
tree "$N" _deps/onnxruntime-src/lib/libonnxruntime.so.1.23.2
run linux "$N"
if [[ $RC -ne 0 && "$ERR" == *"libsherpa-onnx-c-api"* ]]; then
  echo "ok   - missing C API library fails loudly"
else
  fail "no C API: rc=$RC out='$OUT' err='$ERR'"
fi

# 4. onnxruntime missing.
O="$WORK/no-ort"
tree "$O" lib/libsherpa-onnx-c-api.so
run linux "$O"
if [[ $RC -ne 0 && "$ERR" == *"onnxruntime"* ]]; then
  echo "ok   - missing onnxruntime fails loudly"
else
  fail "no onnxruntime: rc=$RC out='$OUT' err='$ERR'"
fi

# 5. A macOS tree is never staged as Linux.
run linux "$M"
if [[ $RC -ne 0 ]]; then
  echo "ok   - foreign platform files are not staged"
else
  fail "foreign: rc=$RC out='$OUT'"
fi

# 6. Unknown platform.
run windows "$L"
if [[ $RC -ne 0 ]]; then
  echo "ok   - unknown platform fails"
else
  fail "unknown platform: rc=$RC out='$OUT'"
fi

if [[ $failures -gt 0 ]]; then
  echo "sherpa-stage-libs.test: $failures failure(s)"
  exit 1
fi
echo "sherpa-stage-libs.test: all passed"
