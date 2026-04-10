<#
.SYNOPSIS
    Run cppcheck static analysis on WhisPaste native C++ code.
.DESCRIPTION
    Analyzes windows/runner/*.cpp and *.h for bugs, performance issues,
    and portability problems. Install cppcheck first: choco install cppcheck
.EXAMPLE
    .\scripts\cppcheck.ps1
    .\scripts\cppcheck.ps1 -Strict
#>
param(
    [switch]$Strict  # Treat all warnings as errors
)

$ErrorActionPreference = 'Stop'

$cppcheck = Get-Command cppcheck -ErrorAction SilentlyContinue
if (-not $cppcheck) {
    Write-Host "cppcheck not found. Install with: choco install cppcheck" -ForegroundColor Red
    exit 1
}

$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root "windows\runner"
Write-Host "Running cppcheck on $target ..." -ForegroundColor Cyan

$enableChecks = "warning,performance,portability"
if ($Strict) {
    $enableChecks = "all"
}

$exitCode = 0
& cppcheck `
    --enable=$enableChecks `
    --std=c++17 `
    --platform=win64 `
    --suppress=missingIncludeSystem `
    --suppress=unmatchedSuppression `
    --suppress=useStlAlgorithm `
    --inline-suppr `
    --error-exitcode=1 `
    --template="{file}({line}): {severity} ({id}): {message}" `
    $target

$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "`ncppcheck passed — no issues found." -ForegroundColor Green
} else {
    Write-Host "`ncppcheck found issues (exit code $exitCode)." -ForegroundColor Red
}

exit $exitCode
