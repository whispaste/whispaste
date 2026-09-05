# bundle-libllama-windows.ps1 — stage the prebuilt `llama.dll`/`ggml*.dll`/
# `smartmode_shim.dll` (Smart-Mode-v2, see build-libllama-windows.ps1 +
# build-smartmode-shim-windows.ps1) into a dedicated `smart_mode\`
# subdirectory of the Flutter Windows Release output, so the NSIS installer
# (installer/whispaste.nsi, `File /r "${BUILD_DIR}\*"`) packs it into the
# MSIX/setup automatically — same delivery mechanism as
# bundle-libwhisper-windows.ps1.
#
# Windows equivalent of macos/embed_libllama.sh, with one structural
# difference: macOS embeds straight into Contents/Frameworks/ alongside
# libwhisper's own dylibs, relying on the `-llama`-suffix renaming done in
# build-libllama-macos.sh to avoid a ggml*.dylib name collision. Windows
# DLLs aren't renamed (see build-libllama-windows.ps1's doc comment for why:
# renaming would require re-linking every consumer, which install_name_tool
# does for free on macOS but has no MSVC equivalent). Instead this script
# stages everything into its OWN subdirectory, `<ReleaseDir>\smart_mode\`,
# fully disjoint from the bundle-root DLLs bundle-libwhisper-windows.ps1
# stages — see smart_mode_ffi_engine.dart's `smartModeLibraryPathFor`
# (resolves the bundled library at exactly this path) and
# `_ensureWindowsDllSearchPath` (adds that subdirectory to the DLL search
# path before `DynamicLibrary.open`, exactly like the whisper engine already
# does for its own bundle-root DLLs).
#
# Smart Mode ships in the real app now (Settings → Smart Mode → On-Device is
# selectable on every platform, no build-time gate) — same status as
# macos/embed_libllama.sh, which runs unconditionally for every macOS build.
# This script is invoked from the regular Windows release workflow
# (.github/workflows/release.yml), not a separate prototype build.
#
# Usage:
#   pwsh scripts/bundle-libllama-windows.ps1 -Source <dir-with-dlls> `
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

$dlls = Get-ChildItem -Path $Source -Filter *.dll | Where-Object {
  $_.Name -match '^(llama|ggml|smartmode_shim)'
}
if ($dlls.Count -eq 0) { throw "No llama/ggml/smartmode_shim DLLs found in $Source" }

# Same SHA-256 pinning support as bundle-libwhisper-windows.ps1.
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

$smartModeDir = Join-Path $ReleaseDir "smart_mode"
New-Item -ItemType Directory -Path $smartModeDir -Force | Out-Null

foreach ($dll in $dlls) {
  Copy-Item $dll.FullName -Destination $smartModeDir -Force
  Write-Host "Staged $($dll.Name) -> $smartModeDir"
}
Write-Host "libllama Windows bundling complete ($($dlls.Count) DLLs) in $smartModeDir."
