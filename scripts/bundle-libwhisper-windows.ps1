# bundle-libwhisper-windows.ps1 — stage the prebuilt `whisper.dll` (+ ggml*.dll)
# next to whispaste.exe in the Flutter Windows Release output, so the NSIS
# installer (installer/whispaste.nsi, `File /r "${BUILD_DIR}\*"`) packs them into
# the MSIX/setup automatically.
#
# Verified live on SilviosPC during v1.2.45 release prep (two real bugs found
# and fixed there, not just staging the files):
#
# 1. Placing whisper.dll beside whispaste.exe is NOT enough on Windows, unlike
#    macOS/Linux. Loading whisper.dll via a bare LoadLibraryW (what dart:ffi's
#    DynamicLibrary.open does) resolves whisper.dll's OWN transitive
#    dependencies (ggml.dll -> ggml-cpu.dll/ggml-vulkan.dll) only against "the
#    folder the application loaded from" (whispaste.exe's dir) and the system
#    paths — NOT against whisper.dll's own directory, even though they're the
#    same folder here (see MS docs: "the system searches for the dependent
#    DLLs as if they were loaded by using only their module names", which
#    resets at every level of the chain). A CreateProcess'd standalone .exe
#    (the retired whisper-server subprocess) never hit this, because for a
#    freshly launched process ITS OWN folder always is step 7 of the search
#    order. An in-process LoadLibrary of a DLL doesn't get that same
#    treatment for that DLL's own dependencies.
#    Fixed in lib/services/stt/whisper/whisper_ffi_engine.dart
#    (_ensureWindowsDllSearchPath): calls SetDllDirectoryW(execDir) once
#    before DynamicLibrary.open(), matching Microsoft's own documented
#    recommendation for this exact scenario and the same pattern used by
#    other Flutter-Windows plugins bundling multiple native DLLs (e.g.
#    flutter_onnxruntime's windows_utils.cc).
# 2. A plain `-DGGML_VULKAN=ON` build gives ggml.dll a HARD static import on
#    ggml-vulkan.dll (which itself needs vulkan-1.dll) — on a machine with no
#    Vulkan-capable GPU driver at all, ggml.dll (and therefore whisper.dll)
#    would fail to load entirely, even for pure CPU transcription. Verified:
#    removing ggml-vulkan.dll after building WITHOUT -DGGML_BACKEND_DL=ON
#    breaks the load; the SAME test with -DGGML_BACKEND_DL=ON still loads
#    fine (ggml.dll no longer PE-imports ggml-vulkan.dll at all — the backend
#    is now discovered and dlopen'd at runtime by ggml's own registry, which
#    silently skips a missing/broken backend instead of hard-failing). This
#    is required for the product's hardware-inclusivity goal (old/weak
#    hardware with no GPU driver must still get working CPU transcription).
#
# Build the DLLs locally with:
#   cmake -S <whisper-src> -B build -G "Visual Studio 17 2022" -A x64 `
#         -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DGGML_VULKAN=ON `
#         -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_BACKEND_DL=ON `
#         -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF
#   cmake --build build --config Release
# (GGML_OPENMP=OFF avoids an extra VCOMP140.DLL runtime dependency that isn't
# bundled anywhere else in the app — verified missing on a real Windows box.)
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

# Bundle the Silero-VAD model alongside whisper.dll (see
# assets/models/vad/NOTICE.md) — a fixed, tiny (<1MB) data file, vendored in
# the repo rather than built per-platform like the DLLs above.
$repoRoot = Split-Path -Parent $PSScriptRoot
$vadModel = Join-Path $repoRoot "assets\models\vad\ggml-silero-v5.1.2.bin"
if (Test-Path $vadModel) {
  Copy-Item $vadModel -Destination $ReleaseDir -Force
  Write-Host "Staged ggml-silero-v5.1.2.bin (VAD model) -> $ReleaseDir"
} else {
  Write-Warning "VAD model not found ($vadModel) - VAD stays unavailable at runtime."
}
