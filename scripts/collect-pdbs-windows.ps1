# collect-pdbs-windows.ps1 — copy the PDB of every DLL in a staging dir into a
# separate folder, so release.yml can upload them to Sentry without the PDBs
# ever landing in the portable zip, the NSIS installer or the MSIX (the bundle
# scripts only pick up *.dll from the staging dir's top level).
#
# Usage: pwsh scripts/collect-pdbs-windows.ps1 -DllDir <stage> -OutDir <stage>\pdb
#
# Each DLL's CodeView (RSDS) record names the exact PDB the linker wrote; that
# file is what Sentry matches by GUID + age, so it is copied as-is. Fails when a
# DLL has no RSDS record (built without /Z7 + /DEBUG) or its PDB is missing, so
# a lost flag cannot silently ship unsymbolicated builds. Re-running it for the
# same DllDir is idempotent. Needs dumpbin.exe on PATH (MSVC developer
# environment), like the ggml namespacing checks.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$DllDir,
  [Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$dlls = Get-ChildItem -Path $DllDir -Filter *.dll
if ($dlls.Count -eq 0) { throw "No DLLs found in $DllDir" }

foreach ($dll in $dlls) {
  $headers = dumpbin /nologo /headers $dll.FullName
  $match = $headers | Select-String -Pattern 'Format: RSDS, \{[0-9A-Fa-f-]+\}, \d+, (.+\.pdb)\s*$' | Select-Object -First 1
  if (-not $match) { throw "$($dll.Name) has no CodeView record -- built without /Z7 + /DEBUG?" }
  $pdb = $match.Matches[0].Groups[1].Value.Trim()
  if (-not (Test-Path $pdb)) { throw "$($dll.Name) references $pdb, which does not exist" }
  # Named after the DLL: the linker's own PDB names need not be unique.
  Copy-Item $pdb -Destination (Join-Path $OutDir "$($dll.BaseName).pdb") -Force
}
Write-Host "      collected $($dlls.Count) PDBs -> $OutDir"
