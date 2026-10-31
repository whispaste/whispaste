#!/usr/bin/env bash
# check-libwhisper-guard.sh — fails when a libwhisper stage or bundle ships
# without a usable wp_ffi_guard (native/ffi_guard) for this build.
#
# Usage: bash scripts/check-libwhisper-guard.sh <dir>
#   <dir>  a stage (.build/libwhisper/<os>), a Flutter bundle lib/ directory or
#          an app's Contents/Frameworks/.
#
# Rules (see CONTEXT.md, "GPU-Laufzeit-Schutz"):
#   1. libwhisper is present -> the guard must be present too. Without the guard
#      the Dart side initialises no GPU backend (backendAllowedByGuard), so a
#      bundle without it silently runs on CPU.
#   2. A macOS stage (WHISPER_PIN present) must carry the hash of the current
#      native/ffi_guard sources. Otherwise the stage predates a guard change.
#   3. On macOS and Linux the guard is loaded with ctypes (python3 -I): its
#      wpg_abi_version() must equal WPG_ABI_VERSION of ffi_guard.h, and both
#      wpg_sizeof_* symbols must exist. The sizes are printed for the record.
#      The struct sizes are compared against the Dart bindings at runtime
#      (NativeCallGuard.supportsWhisperStructs), not here.
# Windows: presence only. bundle-libwhisper-windows.ps1 already throws without
# wp_ffi_guard.dll, and ctypes cannot run the DLL on the build host.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:?usage: check-libwhisper-guard.sh <dir>}"
HEADER="$REPO_ROOT/native/ffi_guard/ffi_guard.h"

fail() { echo "error: libwhisper guard check: $*" >&2; exit 1; }

first_existing() { # first argument that is a regular file, or empty
  local candidate
  for candidate in "$@"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 0
}

[[ -d "$DIR" ]] || fail "$DIR is not a directory"

whisper="$(first_existing "$DIR/libwhisper.dylib" "$DIR/libwhisper.so" "$DIR"/libwhisper.so.* "$DIR/whisper.dll")"
[[ -n "$whisper" ]] || fail "no libwhisper in $DIR, nothing to guard (expected a staged or bundled libwhisper)"

guard="$(first_existing "$DIR/libwp_ffi_guard.dylib" "$DIR/libwp_ffi_guard.so" "$DIR"/libwp_ffi_guard.so.* "$DIR/wp_ffi_guard.dll")"
[[ -n "$guard" ]] || fail "libwhisper is in $DIR but wp_ffi_guard is missing: GPU backends would be disabled, or the bundle is broken. Rebuild with the guard (scripts/build-libwhisper-*.sh)."
echo "guard present: $guard"

if [[ -f "$DIR/WHISPER_PIN" ]]; then
  guard_hash="$(cat "$REPO_ROOT"/native/ffi_guard/* | shasum -a 256 | cut -c1-16)"
  if ! grep -qF "+ffi_guard:$guard_hash" "$DIR/WHISPER_PIN"; then
    fail "$DIR/WHISPER_PIN ($(cat "$DIR/WHISPER_PIN")) was built from other native/ffi_guard sources than the current tree (+ffi_guard:$guard_hash). Rebuild the stage."
  fi
  echo "stage pin matches native/ffi_guard ($guard_hash)"
fi

case "$guard" in
  *.dll)
    echo "ABI check skipped on this host (Windows DLL, presence checked only)"
    ;;
  *)
    command -v python3 >/dev/null || fail "python3 is needed for the ABI check"
    expected_abi="$(sed -n 's/^#define WPG_ABI_VERSION[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$HEADER")"
    [[ -n "$expected_abi" ]] || fail "WPG_ABI_VERSION not found in $HEADER"
    python3 -I - "$guard" "$expected_abi" <<'PY' || fail "ABI check failed for $guard"
import ctypes
import sys

path, expected = sys.argv[1], int(sys.argv[2])
try:
    lib = ctypes.CDLL(path)
except OSError as err:
    sys.exit(f"cannot load {path}: {err}")
abi = lib.wpg_abi_version
abi.restype = ctypes.c_int
actual = abi()
if actual != expected:
    sys.exit(f"ABI {actual} in {path}, the C header and Dart expect {expected}")
for symbol in ("wpg_sizeof_whisper_context_params", "wpg_sizeof_whisper_full_params"):
    try:
        fn = getattr(lib, symbol)
    except AttributeError:
        sys.exit(f"{symbol} missing in {path}")
    fn.restype = ctypes.c_size_t
    print(f"{symbol} = {fn()}")
print(f"ABI {actual} ok")
PY
    ;;
esac

echo "libwhisper guard check passed: $DIR"
