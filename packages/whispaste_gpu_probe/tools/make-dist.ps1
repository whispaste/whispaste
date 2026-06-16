<#
.SYNOPSIS
  Assembles a self-contained, no-install WhisPaste GPU-Probe distribution ZIP.

.DESCRIPTION
  Copies the probe exe, the bundled engine binaries and the CPU baseline from a
  built run directory into a clean staging folder, drops in the LIESMICH.txt
  guide (with the version substituted), and zips the result. Models are NOT
  bundled — the tool downloads them on demand into the extracted folder.

  Allowlist-based on purpose: only known-good artifacts are shipped, so build
  litter (logs, history, temp wavs, downloaded models, .new.exe) can never leak
  into a tester's download.

.EXAMPLE
  powershell -File make-dist.ps1 -Version 0.13.0-gpu `
    -RunDir C:\Users\Public\gpuprobe -OutDir C:\Users\Public\gpb-dist
#>
param(
  [Parameter(Mandatory = $true)] [string] $Version,
  [string] $RunDir = "C:\Users\Public\gpuprobe",
  [string] $OutDir = "C:\Users\Public\gpb-dist",
  [string] $Template = ""
)
$ErrorActionPreference = "Stop"

# Resolve the LIESMICH template relative to this script when not given. Done in
# the body (not the param default) because $PSScriptRoot is not reliably bound
# at default-evaluation time under every invocation style.
if (-not $Template) {
  $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } `
    else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $Template = Join-Path $scriptDir "dist\LIESMICH.txt"
}

# Engine folders shipped as-is (each is self-contained with its own DLLs).
$engineDirs = @(
  "const-me", "sherpa-onnx", "sherpa-onnx-cuda",
  "faster-whisper", "whisper-vulkan", "onnx-directml"
)
# Flat files: the whisper.cpp CPU baseline (exe + its ggml/whisper DLLs).
$flatFiles = @(
  "whisper.exe", "whisper.dll", "ggml.dll", "ggml-base.dll", "ggml-cpu.dll"
)

$stageName = "WhisPaste-GPU-Probe"
$stage = Join-Path $OutDir $stageName
$zip = Join-Path $OutDir ("WhisPaste-GPU-Probe-$Version.zip")

Write-Host "Staging -> $stage"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# Probe exe, renamed to a friendly double-click name.
$probe = Join-Path $RunDir "whispaste-gpu-probe.exe"
if (-not (Test-Path $probe)) { throw "probe exe not found: $probe" }
Copy-Item $probe (Join-Path $stage "WhisPaste-GPU-Probe.exe") -Force

foreach ($f in $flatFiles) {
  $src = Join-Path $RunDir $f
  if (-not (Test-Path $src)) { throw "missing CPU-baseline file: $src" }
  Copy-Item $src $stage -Force
}

# Model/cache subfolders that an engine may have accumulated at runtime but that
# must NOT ship (models are downloaded on demand into the extracted folder).
# NB: do NOT prune onnx-directml\_internal — those are the PyInstaller runtime
# deps the runner needs.
$pruneDirs = @("_models", "models", ".cache", "out")

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

# LIESMICH.txt with the version substituted.
if (-not (Test-Path $Template)) { throw "template not found: $Template" }
(Get-Content $Template -Raw).Replace("{{VERSION}}", $Version) |
  Set-Content (Join-Path $stage "LIESMICH.txt") -Encoding UTF8

# Zip it (overwrite any stale archive).
if (Test-Path $zip) { Remove-Item $zip -Force }
Write-Host "Compressing -> $zip (this can take a minute)"
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal

$mb = [math]::Round((Get-Item $zip).Length / 1MB, 0)
Write-Host "Done: $zip ($mb MB)"
