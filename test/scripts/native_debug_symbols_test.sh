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
# sherpa-onnx C API (Windows) is ours to build, so it needs a PDB too; the PDB
# lives beside the stage (windows-pdb), never inside it.
expect "$ROOT/scripts/build-sherpa-onnx.ps1" "'-DCMAKE_C_FLAGS=/Z7'" "sherpa-onnx (Windows) is not built with /Z7"
expect "$ROOT/scripts/build-sherpa-onnx.ps1" "'-DCMAKE_SHARED_LINKER_FLAGS=/DEBUG /OPT:REF /OPT:ICF'" "sherpa-onnx (Windows) is linked without /DEBUG"
expect "$ROOT/scripts/build-sherpa-onnx.ps1" "sherpa-onnx-c-api.pdb" "sherpa-onnx (Windows) PDB is not kept"
# CUDA backend pack (built by hand on the Windows box): same flags, PDB outside the stage.
expect "$ROOT/scripts/build-cuda-pack-windows.ps1" "'-DCMAKE_C_FLAGS=/Z7'" "CUDA pack ggml-cuda is not built with /Z7"
expect "$ROOT/scripts/build-cuda-pack-windows.ps1" "'-DCMAKE_SHARED_LINKER_FLAGS=/DEBUG /OPT:REF /OPT:ICF'" "CUDA pack ggml-cuda is linked without /DEBUG"
expect "$ROOT/scripts/build-cuda-pack-windows.ps1" "ggml-cuda.pdb missing" "CUDA pack PDB is not checked"

# Linux: -g, then DWARF split off so the shipped .so stay small.
for s in build-libwhisper-linux.sh build-libllama-linux.sh; do
  expect "$ROOT/scripts/$s" "-DCMAKE_C_FLAGS=-g -DCMAKE_CXX_FLAGS=-g" "$s does not build with -g"
  expect "$ROOT/scripts/$s" "split-debug-linux.sh" "$s does not split the debug info"
done

# release.yml uploads both directory sets and rebuilds when the helpers change.
expect "$RELEASE" ".build/libwhisper/windows/pdb .build/libllama/windows/pdb" "Windows PDBs are not uploaded to Sentry"
expect "$RELEASE" ".build/libwhisper/linux/debug .build/libllama/linux/debug" "Linux debug files are not uploaded to Sentry"
# sherpa PDB: cached, uploaded to Sentry and offered to the .msixupload.
n=$(grep -cE 'sherpa-onnx[/\\]windows-pdb' "$RELEASE" || true)
[[ $n -ge 3 ]] || { echo "FAIL: sherpa-onnx PDB dir is not cached, uploaded and packaged in .msixupload ($n/3)"; fail=1; }
n=$(grep -c "hashFiles(.*'scripts/collect-pdbs-windows.ps1'" "$RELEASE" || true)
[[ $n -ge 2 ]] || { echo "FAIL: Windows lib cache keys do not hash collect-pdbs-windows.ps1 ($n/2)"; fail=1; }
n=$(grep -c "hashFiles(.*'scripts/split-debug-linux.sh'" "$RELEASE" || true)
[[ $n -ge 2 ]] || { echo "FAIL: Linux lib cache keys do not hash split-debug-linux.sh ($n/2)"; fail=1; }

# whispaste.exe: Release links with /DEBUG and writes its PDB outside the
# shipped bundle dir; Sentry gets it too.
RUNNER="$ROOT/windows/runner/CMakeLists.txt"
expect "$RUNNER" '$<$<CONFIG:Release>:/DEBUG>' "whispaste.exe Release is linked without /DEBUG"
expect "$RUNNER" '$<$<CONFIG:Release>:/PDB:${WHISPASTE_SYMBOLS_DIR}/' "whispaste.exe PDB is not redirected out of the bundle dir"
expect "$RUNNER" '$<$<CONFIG:Release>:/PDBALTPATH:${BINARY_NAME}.pdb>' "whispaste.exe embeds the absolute build path of its PDB"
# %_PDB% gets double-escaped by the VS generator ("%%%whispaste.pdb%%%").
if grep -v '^[[:space:]]*#' "$RUNNER" | grep -qF '%_PDB%'; then
  echo "FAIL: /PDBALTPATH uses the %_PDB% macro, which CMake's VS generator mangles ($RUNNER)"
  fail=1
fi
expect "$RELEASE" "build/windows/x64/symbols .build/libwhisper/windows/pdb" "whispaste.exe PDB is not uploaded to Sentry"

# Partner Center: the .msixupload must carry the PDBs from the symbol dirs
# (up to v1.3.0 it searched only the Release dir, found 0 PDBs and was
# skipped), must fail loudly, and the Store submission must use it.
expect "$RELEASE" 'foreach ($dir in @("build\windows\x64\symbols", ".build\libllama\windows\pdb", ".build\libwhisper\windows\pdb", ".build\sherpa-onnx\windows-pdb"))' ".msixupload does not collect the runner/whisper/llama/sherpa PDBs"
expect "$RELEASE" 'Move-Item $zip "store-upload\WhisPaste.msixupload"' ".msixupload is not built"
expect "$RELEASE" "-Filter *.msixupload" "Store submission does not prefer the .msixupload"
if grep -qF 'Write-Warning "No PDBs' "$RELEASE"; then
  echo "FAIL: .msixupload step still skips silently when no PDBs are found ($RELEASE)"
  fail=1
fi

[[ $fail -eq 0 ]] && echo "PASS: native libs build with debug info and release.yml uploads it to Sentry"
exit $fail
