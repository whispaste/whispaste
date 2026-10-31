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
# ggml namespacing: llama.cpp vendors its own ggml, ABI-independent of the
# one libwhisper ships in the bundle root (ggml.dll/ggml-base.dll). The
# Windows loader resolves a DLL's static imports by module NAME against the
# modules already in the process, regardless of directory: once whisper.dll
# has loaded the root ggml.dll, llama.dll's import of "ggml.dll" binds to it
# (error 127, procedure not found), and in the reverse order whisper.dll
# silently binds to llama's copy. A separate smart_mode\ subdirectory alone
# does not help. So, like the `-llama` renaming on macOS/Linux, the core
# ggml DLLs are built as ggml-llama.dll / ggml-base-llama.dll: a CMake
# project include sets the shared-library suffix inside the ggml project
# only, so the linker records the new names in every importer (llama.dll,
# the backend modules, smartmode_shim.dll) -- no PE patching. The backend
# MODULEs keep their names (ggml-cpu-<level>.dll, ggml-vulkan.dll): ggml
# finds them by that prefix and the shim loads them by full path from
# smart_mode\ only, which the loader keeps apart from libwhisper's
# same-named modules in the root.
#
# -DGGML_BACKEND_DL=ON (same reasoning as bundle-libwhisper-windows.ps1):
# without it, ggml.dll would hard-import ggml-vulkan.dll (and therefore
# vulkan-1.dll), breaking load on machines with no Vulkan-capable GPU driver
# at all — required for the product's hardware-inclusivity goal.
# -DGGML_CPU_ALL_VARIANTS=ON: one ggml-cpu-<level>.dll per x86-64 feature
# level instead of a single baseline (no AVX) ggml-cpu.dll; ggml picks the
# best one the CPU supports at runtime (same as build-libllama-linux.sh).
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
Write-Host "[2/3] cmake configure + build (Vulkan + CPU variants, shared, backend-dl) ..."
# Renames the core ggml DLLs (see "ggml namespacing" above). Included right
# after ggml's own project() call, so it only affects targets in ggml/.
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$GgmlSuffixInclude = Join-Path $BuildDir "ggml-llama-suffix.cmake"
'set(CMAKE_SHARED_LIBRARY_SUFFIX "-llama.dll")' | Set-Content -Encoding ascii $GgmlSuffixInclude
# /Z7 + /DEBUG: PDBs for Sentry (collected into $StageDir\pdb below, never
# bundled). CFLAGS/CXXFLAGS/LDFLAGS are appended to CMake's defaults, so /MD
# and the Release optimisation stay as they are; /OPT:REF /OPT:ICF undo the
# size growth /DEBUG would otherwise cause.
$env:CFLAGS = '/Z7'
$env:CXXFLAGS = '/Z7'
$env:LDFLAGS = '/DEBUG /OPT:REF /OPT:ICF'
cmake -S $LlamaSrc -B $BuildDir -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  "-DCMAKE_PROJECT_ggml_INCLUDE=$($GgmlSuffixInclude -replace '\\','/')" `
  -DBUILD_SHARED_LIBS=ON `
  -DGGML_VULKAN=ON `
  -DGGML_NATIVE=OFF `
  -DGGML_OPENMP=OFF `
  -DGGML_BACKEND_DL=ON `
  -DGGML_CPU_ALL_VARIANTS=ON `
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
if (-not ($dlls | Where-Object { $_.Name -like 'ggml-cpu-*.dll' })) {
  throw "No CPU backend variants (ggml-cpu-*.dll) built under $BuildDir"
}
foreach ($dll in $dlls) {
  Copy-Item $dll.FullName -Destination $StageDir -Force
}
Write-Host "      staged: $(($dlls | ForEach-Object { $_.Name }) -join ' ')"

# Hard guard: no staged DLL may be named, or import, libwhisper's core ggml
# DLLs (see "ggml namespacing" above).
$clashing = @('ggml.dll', 'ggml-base.dll')
foreach ($name in @('ggml-llama.dll', 'ggml-base-llama.dll')) {
  if (-not (Test-Path (Join-Path $StageDir $name))) { throw "$name missing -- core ggml DLLs were not renamed" }
}
foreach ($dll in Get-ChildItem -Path $StageDir -Filter *.dll) {
  if ($clashing -contains $dll.Name.ToLower()) { throw "$($dll.Name) staged -- would clash with libwhisper's ggml" }
  $imports = dumpbin /nologo /dependents $dll.FullName | ForEach-Object { $_.Trim().ToLower() }
  foreach ($c in $clashing) {
    if ($imports -contains $c) { throw "$($dll.Name) imports $c -- would bind to libwhisper's ggml" }
  }
}
Write-Host "      ggml namespacing verified (no ggml.dll / ggml-base.dll name or import)."

pwsh (Join-Path $PSScriptRoot "collect-pdbs-windows.ps1") -DllDir $StageDir -OutDir (Join-Path $StageDir "pdb")
if ($LASTEXITCODE -ne 0) { throw "collect-pdbs-windows.ps1 failed" }

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
