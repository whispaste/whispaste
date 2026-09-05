# build-libllama-windows.ps1 — reproducible build of the bundled `llama` +
# `ggml` shared libraries (llama.cpp b10150, Vulkan + CPU backends) for the
# Windows build. Produces flat DLLs plus a SHA-256 manifest, staged where
# `bundle-libllama-windows.ps1` picks them up and copies them next to
# `whispaste.exe` under a dedicated `smart_mode\` subdirectory.
#
# Windows equivalent of build-libllama-macos.sh — same pinned llama.cpp
# source, same reasoning (Smart-Mode-v2, Gemma-4-E2B on-device text
# refinement, no runtime code download).
#
# ggml namespacing: unlike macOS (see build-libllama-macos.sh, which renames
# every ggml* dylib with a `-llama` suffix so it can share Contents/Frameworks/
# with libwhisper's own ggml build), Windows does NOT rename these DLLs.
# Instead `bundle-libllama-windows.ps1` stages them into their own
# `smart_mode\` subdirectory, disjoint from libwhisper's DLLs in the bundle
# root — see smart_mode_ffi_engine.dart's `smartModeLibraryPathFor` doc
# comment for why. Renaming Windows import-library-linked DLLs would require
# re-linking every consumer (the same problem install_name_tool solves for
# free on macOS via LC_LOAD_DYLIB rewriting); directory isolation avoids that
# entirely.
#
# -DGGML_BACKEND_DL=ON (same reasoning as bundle-libwhisper-windows.ps1):
# without it, ggml.dll would hard-import ggml-vulkan.dll (and therefore
# vulkan-1.dll), breaking load on machines with no Vulkan-capable GPU driver
# at all — required for the product's hardware-inclusivity goal.
#
# Usage:  pwsh scripts/build-libllama-windows.ps1
# Output: .build\libllama\windows\{llama.dll,ggml*.dll,SHA256SUMS}
#
# Requires: cmake + Ninja on PATH, run from a Developer PowerShell / Developer
# Command Prompt for VS 2022 (so cl.exe/link.exe resolve — same requirement
# as build-smartmode-shim-windows.ps1, which must run right after this in the
# same shell), a checked-out llama.cpp source tree (see LLAMA_SRC below).
#
# Uses the Ninja generator, NOT "Visual Studio 17 2022" — see
# bundle-libwhisper-windows.ps1's sibling CI job comment: the VS IDE
# generator's own vswhere-based instance-detection failed outright in GitHub
# Actions' windows-latest runner (confirmed live, v1.2.48 Windows job) even
# though the same runner has VS installed. Ninja + ilammy/msvc-dev-cmd (cl.exe
# on PATH) is the same combination the whisper.cpp Windows build already
# relies on in CI, and sidesteps that generator-detection failure entirely.
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

# --- Pinned source provenance (identical pin to build-libllama-macos.sh) ----
$LlamaTag = "b10150"
$LlamaSrc = Join-Path $RepoRoot ".build\deps\llama.cpp\$LlamaTag"
$LlamaPinnedCommit = "dee2a846b82f15d27f84a48fa387cb53e0d99c25"

$BuildDir = Join-Path $RepoRoot ".build\libllama\windows-build"
$StageDir = Join-Path $RepoRoot ".build\libllama\windows"

Write-Host "=== build-libllama-windows ($LlamaTag) ==="

# --- 1. Verify pinned source -------------------------------------------------
if (-not (Test-Path $LlamaSrc)) {
  Write-Error "llama.cpp source not found at $LlamaSrc`nFetch it first: git clone https://github.com/ggml-org/llama.cpp `"$LlamaSrc`" ; git -C `"$LlamaSrc`" checkout $LlamaPinnedCommit"
  exit 1
}
$actualCommit = (git -C $LlamaSrc rev-parse HEAD 2>$null)
if ($actualCommit -ne $LlamaPinnedCommit) {
  Write-Error "llama.cpp source commit mismatch (supply-chain guard).`nexpected $LlamaPinnedCommit`nactual   $actualCommit"
  exit 1
}
Write-Host "[1/3] source verified: $LlamaTag @ $LlamaPinnedCommit"

# --- 2. Configure + build shared libs (Vulkan + CPU, backend-dl) -----------
Write-Host "[2/3] cmake configure + build (Vulkan + CPU, shared, backend-dl) ..."
cmake -S $LlamaSrc -B $BuildDir -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DBUILD_SHARED_LIBS=ON `
  -DGGML_VULKAN=ON `
  -DGGML_NATIVE=OFF `
  -DGGML_OPENMP=OFF `
  -DGGML_BACKEND_DL=ON `
  -DLLAMA_BUILD_EXAMPLES=OFF `
  -DLLAMA_BUILD_TESTS=OFF `
  -DLLAMA_BUILD_SERVER=OFF `
  -DLLAMA_BUILD_TOOLS=OFF `
  -DLLAMA_BUILD_APP=OFF `
  -DLLAMA_OPENSSL=OFF `
  | Out-Null
cmake --build $BuildDir --config Release -j | Out-Null
Write-Host "      built."

# --- 3. Stage DLLs + SHA-256 manifest ---------------------------------------
Write-Host "[3/3] staging DLLs -> $StageDir"
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item -ItemType Directory -Path $StageDir | Out-Null

$dlls = Get-ChildItem -Path $BuildDir -Recurse -Filter *.dll |
  Where-Object { $_.Name -match '^(llama|ggml)' }
if ($dlls.Count -eq 0) { throw "No llama/ggml DLLs found under $BuildDir" }
foreach ($dll in $dlls) {
  Copy-Item $dll.FullName -Destination $StageDir -Force
}
Write-Host "      staged: $(($dlls | ForEach-Object { $_.Name }) -join ' ')"

Push-Location $StageDir
try {
  Get-ChildItem -Filter *.dll | ForEach-Object {
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower())  $($_.Name)"
  } | Set-Content SHA256SUMS
  Get-Content SHA256SUMS
} finally {
  Pop-Location
}

Write-Host "=== done. libllama staged at $StageDir ==="
