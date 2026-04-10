$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

$extensions = @('.dart', '.yaml', '.yml', '.json', '.md')
$excludedPattern = '\\(\.git|build|node_modules)\\'
$pattern = '(sk-[a-zA-Z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}|password\s*=\s*"[^"]+")'

$files = Get-ChildItem -Path $repoRoot -Recurse -File | Where-Object {
  $extensions -contains $_.Extension -and
  $_.FullName -notmatch $excludedPattern
}

Write-Host 'Scanning for potential secrets...'

$matches = @($files | Select-String -Pattern $pattern -CaseSensitive)

if ($matches.Count -gt 0) {
  foreach ($match in $matches) {
    $relativePath = $match.Path.Substring($repoRoot.Length + 1)
    Write-Host "${relativePath}:$($match.LineNumber): $($match.Line.Trim())"
  }
  throw 'Potential secrets detected in source files.'
}

Write-Host 'No secrets found'
