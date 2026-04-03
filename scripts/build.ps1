# WhisPaste Build Script
# Requires: Go 1.21+, GCC (MinGW-w64)
#
# The canonical version lives in types.go (AppVersion).
# Local builds ALWAYS use that version automatically.
# The -Version flag is reserved for CI/release workflows only.
param(
    [switch]$Release,
    [switch]$Clean,
    [string]$Version = "",
    [string]$CrashRelayURL = "",
    [string]$FeedbackRelayURL = ""
)

$ErrorActionPreference = "Stop"
$env:CGO_ENABLED = "1"

# Auto-detect GCC
$gccPaths = @(
    "C:\ProgramData\mingw64\mingw64\bin",
    "C:\msys64\mingw64\bin",
    "C:\TDM-GCC-64\bin"
)
foreach ($p in $gccPaths) {
    if (Test-Path "$p\gcc.exe") {
        $env:PATH = "$p;$env:PATH"
        Write-Host "Using GCC from: $p" -ForegroundColor Green
        break
    }
}

if ($Clean) {
    Write-Host "Cleaning..." -ForegroundColor Yellow
    Remove-Item -Force -ErrorAction SilentlyContinue whispaste.exe
    go clean -cache
    Write-Host "Done." -ForegroundColor Green
    exit 0
}

# Read canonical version from types.go (single source of truth)
$typesFile = Join-Path $PSScriptRoot "..\types.go"
$canonicalVersion = ""
if (Test-Path $typesFile) {
    $match = Select-String -Path $typesFile -Pattern 'var AppVersion\s*=\s*"([^"]+)"'
    if ($match) {
        $canonicalVersion = $match.Matches[0].Groups[1].Value
    }
}
if ($canonicalVersion -eq "") {
    Write-Host "ERROR: Could not read AppVersion from types.go" -ForegroundColor Red
    exit 1
}

# Version safety: -Version parameter must match types.go (or be omitted)
if ($Version -ne "" -and $Version -ne $canonicalVersion) {
    Write-Host ""
    Write-Host "ERROR: Version mismatch!" -ForegroundColor Red
    Write-Host "  -Version parameter: $Version" -ForegroundColor Red
    Write-Host "  types.go AppVersion: $canonicalVersion" -ForegroundColor Red
    Write-Host ""
    Write-Host "The canonical version is defined in types.go." -ForegroundColor Yellow
    Write-Host "To change the version, update types.go first." -ForegroundColor Yellow
    Write-Host "Then rebuild without -Version (it's read automatically)." -ForegroundColor Yellow
    exit 1
}

# Always use the canonical version
$Version = $canonicalVersion

Write-Host "`n=== Building WhisPaste ===" -ForegroundColor Cyan

$ldflags = "-s -w -H windowsgui"
if ($Release) {
    Write-Host "Mode: Release" -ForegroundColor Green
} else {
    Write-Host "Mode: Debug (console output enabled)" -ForegroundColor Yellow
    $ldflags = "-H windowsgui"
}

$ldflags += " -X main.AppVersion=$Version"
Write-Host "Version: $Version (from types.go)" -ForegroundColor Cyan

if ($CrashRelayURL -ne "") {
    $ldflags += " -X main.CrashRelayURL=$CrashRelayURL"
    Write-Host "Crash relay: $CrashRelayURL" -ForegroundColor Cyan
}
if ($FeedbackRelayURL -ne "") {
    $ldflags += " -X main.FeedbackRelayURL=$FeedbackRelayURL"
    Write-Host "Feedback relay: $FeedbackRelayURL" -ForegroundColor Cyan
}

# Inject build metadata (commit, branch, date) for all builds
try {
    $commit = (git rev-parse --short HEAD 2>$null)
    if ($commit) { $ldflags += " -X main.BuildCommit=$commit" }
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if ($branch) { $ldflags += " -X main.BuildBranch=$branch" }
} catch {}
$buildDate = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
$ldflags += " -X 'main.BuildDate=$buildDate'"

Write-Host "Running go build..."
$startTime = Get-Date
go build -ldflags="$ldflags" -o whispaste.exe .
if ($LASTEXITCODE -ne 0) {
    Write-Host "BUILD FAILED" -ForegroundColor Red
    exit 1
}
$elapsed = (Get-Date) - $startTime

$file = Get-Item whispaste.exe
$sizeMB = [math]::Round($file.Length / 1MB, 2)

Write-Host "`n=== Build Successful ===" -ForegroundColor Green
Write-Host "  Output:  whispaste.exe"
Write-Host "  Size:    $sizeMB MB"
Write-Host "  Time:    $([math]::Round($elapsed.TotalSeconds, 1))s"
Write-Host ""
