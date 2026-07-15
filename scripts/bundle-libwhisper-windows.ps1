# bundle-libwhisper-windows.ps1 — stage the prebuilt `whisper.dll` (+ ggml*.dll)
# next to whispaste.exe in the Flutter Windows Release output, so the NSIS
# installer (installer/whispaste.nsi, `File /r "${BUILD_DIR}\*"`) packs them into
# the MSIX/setup automatically. On Windows the loader searches the executable's
# own directory, so DLLs beside whispaste.exe are found with no rpath.
#
# The DLLs come from the CI backend matrix (CUDA12 / Vulkan / CPU — see
# .github/workflows/build-whisper-server.yml) as prebuilt, SHA-256-verified
# artifacts, OR from a local CMake build:
#   cmake -S <whisper-src> -B build -DBUILD_SHARED_LIBS=ON -DGGML_VULKAN=ON `
#         -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF
#   cmake --build build --config Release
#
# NOT verified on the macOS dev host — real verification is Issue 14 (Abnahme
# Windows). This is the configured bundling step.
#
# Usage:
#   pwsh scripts/bundle-libwhisper-windows.ps1 -Source <dir-with-dlls> `
#        [-ReleaseDir build\windows\x64\runner\Release] [-ExpectedSums SHA256SUMS.txt]
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Source,
  [string]$ReleaseDir = "build\windows\x64\runner\Release",
  [string]$ExpectedSums = ""
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $Source)) { throw "Source dir not found: $Source" }
if (-not (Test-Path $ReleaseDir)) { throw "Flutter Release dir not found: $ReleaseDir (run 'flutter build windows' first)" }

# whisper.dll plus its ggml* backend DLLs (and, for the CPU build, bundled VC++
# runtime DLLs staged alongside them by the CI job).
$dlls = Get-ChildItem -Path $Source -Filter *.dll | Where-Object {
  $_.Name -match '^(whisper|ggml)' -or $_.Name -match '^(msvcp|vcruntime|concrt)'
}
if ($dlls.Count -eq 0) { throw "No whisper/ggml DLLs found in $Source" }

# AC3: verify against a pinned SHA-256 manifest when provided.
if ($ExpectedSums -and (Test-Path $ExpectedSums)) {
  $expected = @{}
  Get-Content $ExpectedSums | ForEach-Object {
    $parts = $_ -split '\s+', 2
    if ($parts.Count -eq 2) { $expected[$parts[1].Trim()] = $parts[0].Trim().ToLower() }
  }
  foreach ($dll in $dlls) {
    if ($expected.ContainsKey($dll.Name)) {
      $actual = (Get-FileHash $dll.FullName -Algorithm SHA256).Hash.ToLower()
      if ($actual -ne $expected[$dll.Name]) {
        throw "SHA-256 mismatch for $($dll.Name): expected $($expected[$dll.Name]), got $actual"
      }
    }
  }
  Write-Host "SHA-256 verified against $ExpectedSums"
}

foreach ($dll in $dlls) {
  Copy-Item $dll.FullName -Destination $ReleaseDir -Force
  Write-Host "Staged $($dll.Name) -> $ReleaseDir"
}
Write-Host "libwhisper Windows bundling complete ($($dlls.Count) DLLs)."
