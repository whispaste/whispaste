$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

$cppcheck = Get-Command cppcheck -ErrorAction SilentlyContinue
if (-not $cppcheck) {
  $defaultPath = 'C:\Program Files\Cppcheck\cppcheck.exe'
  if (Test-Path $defaultPath) {
    $cppcheck = @{ Source = $defaultPath }
  }
}

if (-not $cppcheck) {
  throw 'cppcheck was not found in PATH. Install it first or let CI install it before calling this script.'
}

Write-Host 'Running cppcheck on windows/runner/...'

& $cppcheck.Source `
  --enable=warning,performance,portability `
  --std=c++17 `
  --platform=win64 `
  --suppress=missingIncludeSystem `
  --suppress=unmatchedSuppression `
  --suppress=useStlAlgorithm `
  --inline-suppr `
  --error-exitcode=1 `
  --template='{file}({line}): {severity} ({id}): {message}' `
  windows/runner/

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
