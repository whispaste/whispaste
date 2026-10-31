# build-libwhisper-windows.ps1 — reproducible build of the bundled `whisper`
# + `ggml` shared libraries (whisper.cpp from scripts\whisper-cpp.pin, Vulkan + CPU backends) for
# the Windows build, so on-device Whisper can be built locally like on macOS
# and Linux, not only in the release workflow.
#
# Windows counterpart of build-libwhisper-linux.sh: same pinned source and
# the same cmake options as the "Build libwhisper (Windows)" step in
# .github/workflows/release.yml (-DGGML_BACKEND_DL=ON and -DGGML_OPENMP=OFF
# for the reasons in bundle-libwhisper-windows.ps1's header). Keep the two in
# step when the pin or the flags change.
#
# Usage:  pwsh scripts/build-libwhisper-windows.ps1
#         pwsh scripts/bundle-libwhisper-windows.ps1 -Source .build/libwhisper/windows
#         (after `flutter build windows --release`)
# Output: .build\libwhisper\windows\{whisper.dll,ggml*.dll,parakeet.dll,
#         wp_ffi_guard.dll,SHA256SUMS} plus pdb\ (for Sentry, never bundled)
#
# Requires:
#   - the pinned source at .build\deps\whisper.cpp\<WHISPER_TAG> (see step 1),
#   - the Vulkan SDK (VULKAN_SDK set, glslc.exe on PATH; release uses 1.4.328.1),
#   - cmake + Ninja + MSVC. Outside a Developer PowerShell the VS 2022 build
#     tools are activated through vswhere (the same ones `flutter build
#     windows` uses).
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

# --- Pinned source provenance: scripts\whisper-cpp.pin (all platforms) ------
$Pin = @{}
Get-Content (Join-Path $RepoRoot 'scripts\whisper-cpp.pin') | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)=(.*)$') { $Pin[$Matches[1]] = $Matches[2].Trim() }
}
$WhisperTag = $Pin['WHISPER_TAG']
$WhisperPinnedCommit = $Pin['WHISPER_COMMIT']
if (-not $WhisperTag -or -not $WhisperPinnedCommit) {
  throw "scripts\whisper-cpp.pin needs WHISPER_TAG and WHISPER_COMMIT"
}
$WhisperSrc = Join-Path $RepoRoot ".build\deps\whisper.cpp\$WhisperTag"

$BuildDir = Join-Path $RepoRoot ".build\libwhisper\windows-build"
$StageDir = Join-Path $RepoRoot ".build\libwhisper\windows"

Write-Host "=== build-libwhisper-windows ($WhisperTag) ==="

# --- 1. Verify pinned source -------------------------------------------------
if (-not (Test-Path $WhisperSrc)) {
  Write-Error "whisper.cpp source not found at $WhisperSrc`nFetch it first: git clone --depth 1 --branch $WhisperTag https://github.com/ggml-org/whisper.cpp `"$WhisperSrc`""
  exit 1
}
$actualCommit = (git -C $WhisperSrc rev-parse HEAD 2>$null)
if ($actualCommit -ne $WhisperPinnedCommit) {
  Write-Error "whisper.cpp source commit mismatch (supply-chain guard).`nexpected $WhisperPinnedCommit`nactual   $actualCommit"
  exit 1
}
Write-Host "[1/4] source verified: $WhisperTag @ $WhisperPinnedCommit"

# --- 2. Toolchain --------------------------------------------------------------
if (-not $env:VULKAN_SDK -or -not (Get-Command glslc.exe -ErrorAction SilentlyContinue)) {
  Write-Error "Vulkan SDK not found (VULKAN_SDK unset or glslc.exe not on PATH). Install the LunarG SDK, e.g. 1.4.328.1 as in release.yml."
  exit 1
}
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  $vs = if (Test-Path $vswhere) {
    & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  }
  if (-not $vs) { Write-Error "MSVC not found: run from a Developer PowerShell for VS 2022."; exit 1 }
  Import-Module (Join-Path $vs "Common7\Tools\Microsoft.VisualStudio.DevShell.dll")
  Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null
}
Write-Host "[2/4] toolchain: $((Get-Command cl.exe).Source)"

# --- 3. Configure + build (Vulkan + CPU variants, shared, backend-dl) ------
Write-Host "[3/4] cmake configure + build ..."
# /Z7 + /DEBUG: PDBs for Sentry, see build-libllama-windows.ps1.
$env:CFLAGS = '/Z7'
$env:CXXFLAGS = '/Z7'
$env:LDFLAGS = '/DEBUG /OPT:REF /OPT:ICF'
cmake -S $WhisperSrc -B $BuildDir -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON `
  -DGGML_VULKAN=ON -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON `
  -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
cmake --build $BuildDir --config Release -j
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }
# wp_ffi_guard (native/ffi_guard): catches C++ exceptions before they unwind
# into Dart FFI frames; bundled next to whisper.dll.
$GuardDir = Join-Path $BuildDir "ffi_guard"
cmake -S (Join-Path $RepoRoot "native\ffi_guard") -B $GuardDir -G Ninja `
  -DCMAKE_BUILD_TYPE=Release "-DWHISPER_SOURCE_DIR=$WhisperSrc"
if ($LASTEXITCODE -ne 0) { throw "ffi_guard configure failed" }
cmake --build $GuardDir --config Release
if ($LASTEXITCODE -ne 0) { throw "ffi_guard build failed" }

# --- 4. Stage DLLs + SHA-256 manifest ---------------------------------------
Write-Host "[4/4] staging DLLs -> $StageDir"
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item -ItemType Directory -Path $StageDir | Out-Null
# v1.9.5 also builds parakeet.dll: the GPU Parakeet engine (libparakeet).
Copy-Item (Join-Path $BuildDir "bin\*.dll") $StageDir -Force
Copy-Item (Join-Path $GuardDir "wp_ffi_guard.dll") $StageDir -Force
foreach ($name in @('whisper.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-vulkan.dll', 'wp_ffi_guard.dll')) {
  if (-not (Test-Path (Join-Path $StageDir $name))) { throw "$name missing from $StageDir" }
}
if (-not (Get-ChildItem $StageDir -Filter 'ggml-cpu-*.dll')) {
  throw "No CPU backend variants (ggml-cpu-*.dll) built under $BuildDir"
}

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

Write-Host "=== done. libwhisper staged at $StageDir ==="
