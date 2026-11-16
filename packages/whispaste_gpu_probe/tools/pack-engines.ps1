<#
.SYNOPSIS
  Packs the static GPU-Probe engine bundle for the pinned GitHub release.

.DESCRIPTION
  Collects ONLY the engine binaries and the whisper.cpp CPU baseline from a
  manually-assembled run directory into a clean staging folder and zips them
  with their contents at the archive root (no wrapping folder), so the release
  pipeline can extract the result straight into a RunDir and hand it to
  make-dist.ps1.

  This bundle is the static, rarely-changing half of the distribution: the
  probe exe itself is compiled fresh per release in CI, the models are
  downloaded on demand. Run this ONCE (and again only when an engine binary
  actually changes), then upload the result to the pinned `gpu-probe-engines`
  release:

    gh release create gpu-probe-engines `
      --repo whispaste/whispaste `
      --title "GPU-Probe engine bundle" `
      --notes "Static engine binaries consumed by release.yml. Not a user download." `
      gpu-probe-engines-x64.zip
    # On later updates (same tag, replace the asset):
    gh release upload gpu-probe-engines gpu-probe-engines-x64.zip --clobber

  The allowlist below MUST stay in sync with make-dist.ps1 ($engineDirs /
  $flatFiles) — make-dist.ps1 throws loudly if a CPU-baseline file is missing,
  so drift surfaces at the next release build.

.EXAMPLE
  powershell -File pack-engines.ps1 -RunDir C:\Users\Public\gpuprobe
#>
param(
  [string] $RunDir = "C:\Users\Public\gpuprobe",
  [string] $OutDir = "."
)
$ErrorActionPreference = "Stop"

# Engine folders shipped as-is (each is self-contained with its own DLLs).
# Keep in sync with make-dist.ps1 $engineDirs.
$engineDirs = @(
  "const-me", "sherpa-onnx", "sherpa-onnx-cuda",
  "faster-whisper", "whisper-vulkan", "onnx-directml"
)
# Flat files: the whisper.cpp CPU baseline (exe + its ggml/whisper DLLs).
# Keep in sync with make-dist.ps1 $flatFiles.
$flatFiles = @(
  "whisper.exe", "whisper.dll", "ggml.dll", "ggml-base.dll", "ggml-cpu.dll"
)

# Model/cache subfolders an engine may have accumulated at runtime but that must
# NOT ship (models are downloaded on demand into the extracted folder).
$pruneDirs = @("_models", "models", ".cache", "out")

$stage = Join-Path $OutDir "gpu-probe-engines"
$zip = Join-Path $OutDir "gpu-probe-engines-x64.zip"

Write-Host "Staging -> $stage"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

foreach ($f in $flatFiles) {
  $src = Join-Path $RunDir $f
  if (-not (Test-Path $src)) { throw "missing CPU-baseline file: $src" }
  Copy-Item $src $stage -Force
}

foreach ($d in $engineDirs) {
  $src = Join-Path $RunDir $d
  if (-not (Test-Path $src)) {
    Write-Warning "engine folder absent, skipped: $d"
    continue
  }
  $dstDir = Join-Path $stage $d
  Copy-Item $src $dstDir -Recurse -Force
  foreach ($p in $pruneDirs) {
    Get-ChildItem $dstDir -Recurse -Directory -Filter $p -ErrorAction SilentlyContinue |
      ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
  }
  Get-ChildItem $dstDir -Recurse -File -Include *.log, *.jsonl -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
  $mb = [math]::Round(((Get-ChildItem $dstDir -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 0)
  Write-Host "  + engine: $d ($mb MB)"
}

# Zip the staged CONTENTS (not the folder) so extraction lands at the RunDir
# root — that is exactly what make-dist.ps1 expects to find.
# sherpa-onnx engine folders must be built from scripts/sherpa-onnx.pin and match
# the sherpa_onnx version in pubspec.lock (BUILD_INFO check, see
# scripts/check-sherpa-stage.cmake). A folder without a matching BUILD_INFO fails.
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
foreach ($d in @('sherpa-onnx', 'sherpa-onnx-cuda')) {
  $engineDir = Join-Path $stage $d
  if (-not (Test-Path (Join-Path $engineDir 'sherpa-onnx-c-api.dll'))) { continue }
  & cmake "-DSTAGE_DIR=$engineDir" "-DREPO_ROOT=$repoRoot" -P (Join-Path $repoRoot 'scripts\check-sherpa-stage.cmake')
  if ($LASTEXITCODE -ne 0) { throw "sherpa-onnx engine '$d' does not match scripts/sherpa-onnx.pin and pubspec.lock - rebuild it from the pinned TTS-free build" }
}

# Release guard: no espeak-ng (GPL-3.0) in anything that gets zipped. Uses the
# Git for Windows bash next to git.exe (never WSL's bash). Fails before the zip.
$gitBash = Join-Path (Split-Path (Get-Command git).Source) '..\bin\bash.exe'
if (-not (Test-Path $gitBash)) { throw "Git for Windows bash not found at $gitBash" }
& $gitBash (Join-Path $PSScriptRoot '..\..\..\scripts\check-no-espeak.sh') (Resolve-Path $stage).Path
if ($LASTEXITCODE -ne 0) { throw "espeak-ng guard failed on $stage — refusing to build the GPU-probe ZIP" }

if (Test-Path $zip) { Remove-Item $zip -Force }
Write-Host "Compressing -> $zip (this can take a minute)"
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal

$mb = [math]::Round((Get-Item $zip).Length / 1MB, 0)
Write-Host "Done: $zip ($mb MB)"
