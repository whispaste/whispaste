#!/usr/bin/env bash
#
# native_debug_symbols_test.sh — the native libraries must keep producing
# debug info and release.yml must keep uploading it to Sentry, or native crash
# frames in whisper/ggml/llama show up as bare addresses again. Guards the
# build flags, the collect/split calls, the upload steps and the cache keys
# (a cached stage dir from before this change would have no pdb/ or debug/).
# Usage: bash test/scripts/native_debug_symbols_test.sh [repo_root]
set -euo pipefail

ROOT="${1:-$(dirname "$0")/../..}"
RELEASE="$ROOT/.github/workflows/release.yml"
fail=0

expect() { # <file> <fixed string> <message>
  if ! grep -qF -- "$2" "$1"; then
    echo "FAIL: $3 ($1)"
    fail=1
  fi
}

# Windows: /Z7 + /DEBUG, then PDBs collected next to the staged DLLs.
expect "$RELEASE" "\$env:CFLAGS = '/Z7'" "libwhisper (Windows) is not built with /Z7"
expect "$RELEASE" "-OutDir .build/libwhisper/windows/pdb" "libwhisper (Windows) PDBs are not collected"
expect "$ROOT/scripts/build-libllama-windows.ps1" "\$env:CFLAGS = '/Z7'" "libllama (Windows) is not built with /Z7"
expect "$ROOT/scripts/build-libllama-windows.ps1" "collect-pdbs-windows.ps1" "libllama (Windows) PDBs are not collected"
expect "$ROOT/scripts/build-smartmode-shim-windows.ps1" "/DEBUG" "smartmode_shim.dll is linked without /DEBUG"
expect "$ROOT/scripts/build-smartmode-shim-windows.ps1" "collect-pdbs-windows.ps1" "smartmode_shim PDB is not collected"

# Linux: -g, then DWARF split off so the shipped .so stay small.
for s in build-libwhisper-linux.sh build-libllama-linux.sh; do
  expect "$ROOT/scripts/$s" "-DCMAKE_C_FLAGS=-g -DCMAKE_CXX_FLAGS=-g" "$s does not build with -g"
  expect "$ROOT/scripts/$s" "split-debug-linux.sh" "$s does not split the debug info"
done

# release.yml uploads both directory sets and rebuilds when the helpers change.
expect "$RELEASE" ".build/libwhisper/windows/pdb .build/libllama/windows/pdb" "Windows PDBs are not uploaded to Sentry"
expect "$RELEASE" ".build/libwhisper/linux/debug .build/libllama/linux/debug" "Linux debug files are not uploaded to Sentry"
n=$(grep -c "hashFiles(.*'scripts/collect-pdbs-windows.ps1'" "$RELEASE" || true)
[[ $n -ge 2 ]] || { echo "FAIL: Windows lib cache keys do not hash collect-pdbs-windows.ps1 ($n/2)"; fail=1; }
n=$(grep -c "hashFiles(.*'scripts/split-debug-linux.sh'" "$RELEASE" || true)
[[ $n -ge 2 ]] || { echo "FAIL: Linux lib cache keys do not hash split-debug-linux.sh ($n/2)"; fail=1; }

[[ $fail -eq 0 ]] && echo "PASS: native libs build with debug info and release.yml uploads it to Sentry"
exit $fail
