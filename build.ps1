# Whispaste Build Script
# Requires: Go 1.21+, GCC (MinGW-w64)
param(
    [switch]$Release,
    [switch]$Clean,
    [string]$Version = ""
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

Write-Host "`n=== Building Whispaste ===" -ForegroundColor Cyan

$ldflags = "-s -w -H windowsgui"
if ($Release) {
    Write-Host "Mode: Release" -ForegroundColor Green
} else {
    Write-Host "Mode: Debug" -ForegroundColor Yellow
    $ldflags = "-H windowsgui"
}

if ($Version -ne "") {
    $ldflags += " -X main.AppVersion=$Version"
    Write-Host "Version: $Version" -ForegroundColor Cyan
}

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
