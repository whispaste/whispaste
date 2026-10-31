#!/usr/bin/env bash
# check-libwhisper-guard.test.sh — tests for scripts/check-libwhisper-guard.sh.
# Fixtures are generated at runtime. Cases:
#   1. libwhisper without any guard                    -> must FAIL
#   2. no libwhisper at all                            -> must FAIL
#   3. guard file that is not a loadable library       -> must FAIL (ABI check)
#   4. stage pin stamp from other guard sources        -> must FAIL (stale stage)
#   5. real guard, matching stamp (WP_GUARD_LIB)       -> must PASS
#   6. real guard, no stamp (WP_GUARD_LIB)             -> must PASS
#   7. release.yml (Linux, Windows), release-macos-local.sh and smoke-macos.sh
#      call the check
# Cases 5 and 6 need a built guard: set WP_GUARD_LIB=<path to libwp_ffi_guard.dylib|.so>.
# Without it they are reported as skipped, not as passed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-libwhisper-guard.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-libwhisper-guard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

failures=0
skipped=0

expect() { # expect <ok|fail> <label> <dir>
  local want="$1" label="$2" dir="$3" rc
  bash "$GUARD" "$dir" >"$WORK/out.txt" 2>&1
  rc=$?
  if [[ "$want" == "ok" && $rc -eq 0 ]] || [[ "$want" == "fail" && $rc -ne 0 ]]; then
    echo "ok   - $label (exit $rc)"
  else
    echo "FAIL - $label: wanted $want, exit $rc"
    sed 's/^/       /' "$WORK/out.txt"
    failures=$((failures + 1))
  fi
}

new_dir() { mkdir -p "$WORK/$1"; printf '%s\n' "$WORK/$1"; }
stamp_hash() { cat "$REPO_ROOT"/native/ffi_guard/* | shasum -a 256 | cut -c1-16; }

# 1. libwhisper without guard
d="$(new_dir no-guard)"; : >"$d/libwhisper.dylib"; : >"$d/libwhisper.so"
expect fail "libwhisper without guard" "$d"

# 2. no libwhisper at all
d="$(new_dir empty)"; : >"$d/libggml-metal.so"
expect fail "directory without libwhisper" "$d"

# 3. fake guard, not loadable
d="$(new_dir fake-guard)"; : >"$d/libwhisper.so"; printf 'not an elf\n' >"$d/libwp_ffi_guard.so"
expect fail "guard that cannot be loaded" "$d"

# 4. stale stage stamp (guard sources changed after the stage was built)
d="$(new_dir stale-stamp)"; : >"$d/libwhisper.dylib"; : >"$d/libwp_ffi_guard.dylib"
echo "v1.9.5@d1be6fde11ac6e0407606b4e42fe72d34add8037+ffi_guard:0000000000000000" >"$d/WHISPER_PIN"
expect fail "stage pin from other guard sources" "$d"

if [[ -n "${WP_GUARD_LIB:-}" && -f "${WP_GUARD_LIB}" ]]; then
  guard_name="$(basename "$WP_GUARD_LIB")"
  # 5. real guard with matching stamp
  d="$(new_dir real-stamped)"; : >"$d/libwhisper.dylib"; cp "$WP_GUARD_LIB" "$d/$guard_name"
  printf 'v1.9.5@d1be6fde11ac6e0407606b4e42fe72d34add8037+ffi_guard:%s\n' "$(stamp_hash)" >"$d/WHISPER_PIN"
  expect ok "real guard, matching stamp" "$d"

  # 6. real guard, no stamp (Linux or Flutter bundle)
  d="$(new_dir real-bundle)"; : >"$d/libwhisper.so"; cp "$WP_GUARD_LIB" "$d/$guard_name"
  expect ok "real guard in a bundle without stamp" "$d"
else
  echo "skip - real guard cases 5 and 6 (set WP_GUARD_LIB to a built libwp_ffi_guard)"
  skipped=$((skipped + 2))
fi

# 7. wiring: every bundle path calls the check, and the Windows step looks for the DLL
RELEASE="$REPO_ROOT/.github/workflows/release.yml"
wired() { # wired <label> <file> <fixed string>
  if grep -qF -- "$3" "$2"; then
    echo "ok   - $1"
  else
    echo "FAIL - $1: '$3' not found in $2"
    failures=$((failures + 1))
  fi
}
# macOS builds locally, never on GitHub (Actions minutes): the local release
# script checks the macOS stage.
wired "release-macos-local.sh checks the macOS stage" "$REPO_ROOT/scripts/release-macos-local.sh" "bash scripts/check-libwhisper-guard.sh .build/libwhisper/macos"
wired "release.yml checks the Linux bundle" "$RELEASE" "bash scripts/check-libwhisper-guard.sh build/linux/x64/release/bundle/lib"
wired "release.yml checks the Windows Release folder for the DLL" "$RELEASE" 'Release\wp_ffi_guard.dll'
wired "smoke-macos.sh checks the guard inside the app" "$REPO_ROOT/scripts/smoke/smoke-macos.sh" "check-libwhisper-guard.sh"

echo "----"
echo "failures: $failures, skipped: $skipped"
[[ $failures -eq 0 ]]
