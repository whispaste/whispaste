<#
.SYNOPSIS
  Release package smoke test (Windows x64).

.DESCRIPTION
  Installs WhisPaste-Setup.exe silently into -InstallDir and, when -MsixPath
  is given, side-loads the MSIX signed with a throwaway self-signed test
  certificate. Each installation is started once with
  `whispaste.exe --diagnose --out <report>` (see
  lib/services/headless/package_diagnose.dart): it must exit 0, which proves
  the runner, Flutter engine, AOT snapshot and the bundled native engine DLLs
  (whisper.dll, smart_mode\smartmode_shim.dll) all load. Throws on any
  failure, so the release job stops before publishing.

  The Store MSIX is built unsigned (`msix:create --store`; the Store signs it),
  so the script signs a COPY whose certificate subject equals the manifest's
  Publisher. The uploaded artifact is never modified. The test certificate,
  its trust entry and the side-loaded package are removed again at the end.
  Trusting the certificate (LocalMachine\TrustedPeople) needs an elevated
  shell, as on the GitHub-hosted runners.

  The NSIS uninstaller is deliberately not run: it asks whether to delete the
  user's app data (no /SD default), which would block a silent run.

  ASCII-only and Windows PowerShell 5.1 compatible.

.EXAMPLE
  pwsh scripts/smoke/smoke-windows.ps1 -ArtifactDir release-artifacts `
    -MsixPath build\windows\x64\runner\Release\whispaste.msix
#>
param(
  [Parameter(Mandatory = $true)][string]$ArtifactDir,
  [string]$MsixPath,
  [string]$InstallDir = (Join-Path ([IO.Path]::GetTempPath()) 'whispaste-smoke-install'),
  [int]$TimeoutSeconds = 120,
  # Install even though a WhisPaste installer registration already exists for
  # this user (the installer would overwrite its uninstall entry).
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$workDir = Join-Path ([IO.Path]::GetTempPath()) ("whispaste-smoke-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) {
  Write-Host "::error::$Message"
  $failures.Add($Message)
}

# Starts <Exe> --diagnose; it must exit 0 within the timeout and write a report.
function Invoke-Diagnose([string]$Exe, [string]$Label) {
  $report = Join-Path $workDir "$Label.json"
  Write-Host "-- ${Label}: $Exe --diagnose"
  if (-not (Test-Path $Exe)) {
    Add-Failure "${Label}: $Exe not found"
    return
  }
  # whispaste.exe is a GUI-subsystem binary: its stdout does not reliably
  # reach this console, so the report goes through --out and success through
  # the exit code (same as headless-benchmark.yml). stdout/stderr must still
  # be redirected: started without std handles, the Dart CLI blocks on its
  # stdout write and never exits (seen on Windows 11 24H2).
  $stdoutLog = Join-Path $workDir "$Label.stdout.txt"
  $stderrLog = Join-Path $workDir "$Label.stderr.txt"
  $p = Start-Process -FilePath $Exe -ArgumentList @('--diagnose', '--out', "`"$report`"") -PassThru `
    -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
  $null = $p.Handle  # caches the handle so ExitCode is readable after exit
  if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Add-Failure "${Label}: --diagnose did not exit within $TimeoutSeconds s"
    return
  }
  if (Test-Path $report) {
    Get-Content $report | Write-Host
  } else {
    Add-Failure "${Label}: --diagnose wrote no report (the app did not reach Dart's main)"
  }
  if (Test-Path $stderrLog) { Get-Content $stderrLog | Write-Host }
  if ($p.ExitCode -ne 0) {
    Add-Failure "${Label}: --diagnose exited with $($p.ExitCode)"
  }
}

function Find-SignTool {
  $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
  $tool = Get-ChildItem $kits -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\' } |
    Sort-Object FullName -Descending | Select-Object -First 1
  if (-not $tool) { throw 'signtool.exe not found (Windows SDK missing)' }
  return $tool.FullName
}

function Get-MsixIdentity([string]$Path) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entry = $zip.GetEntry('AppxManifest.xml')
    if (-not $entry) { throw "$Path has no AppxManifest.xml" }
    $reader = New-Object IO.StreamReader($entry.Open())
    try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
  } finally {
    $zip.Dispose()
  }
  return $manifest.Package.Identity
}

try {
  # --- NSIS installer -------------------------------------------------------
  $setup = Join-Path $ArtifactDir 'WhisPaste-Setup.exe'
  if (-not (Test-Path $setup)) {
    Add-Failure "WhisPaste-Setup.exe not found in $ArtifactDir"
  } else {
    $uninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WhisPaste'
    if ((Test-Path $uninstKey) -and -not $Force) {
      throw "A WhisPaste installation is already registered for this user ($uninstKey); rerun with -Force to install over its registration."
    }
    Write-Host "-- NSIS: $setup /S /D=$InstallDir"
    # /D must be the last argument and must not be quoted (NSIS rule).
    $p = Start-Process -FilePath $setup -ArgumentList @('/S', "/D=$InstallDir") -PassThru
    $null = $p.Handle
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
      Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
      Add-Failure "NSIS: silent install did not finish within $TimeoutSeconds s"
    } elseif ($p.ExitCode -ne 0) {
      Add-Failure "NSIS: silent install exited with $($p.ExitCode)"
    } else {
      Invoke-Diagnose (Join-Path $InstallDir 'whispaste.exe') 'nsis'
    }
  }

  # --- MSIX -----------------------------------------------------------------
  if ($MsixPath) {
    $identity = Get-MsixIdentity $MsixPath
    Write-Host "-- MSIX: $($identity.Name) $($identity.Version) ($($identity.Publisher))"
    if (Get-AppxPackage -Name $identity.Name) {
      throw "$($identity.Name) is already installed for this user; refusing to replace it."
    }
    $signed = Join-Path $workDir 'smoke.msix'
    Copy-Item $MsixPath $signed
    $cert = New-SelfSignedCertificate -Type Custom -Subject $identity.Publisher `
      -KeyUsage DigitalSignature -FriendlyName 'WhisPaste package smoke test' `
      -CertStoreLocation 'Cert:\CurrentUser\My' `
      -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
    $cerFile = Join-Path $workDir 'smoke.cer'
    $package = $null
    try {
      Export-Certificate -Cert $cert -FilePath $cerFile | Out-Null
      Import-Certificate -FilePath $cerFile -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
      & (Find-SignTool) sign /fd SHA256 /sha1 $cert.Thumbprint $signed
      if ($LASTEXITCODE -ne 0) { throw "signtool failed with $LASTEXITCODE" }
      Add-AppxPackage -Path $signed
      $package = Get-AppxPackage -Name $identity.Name
      if (-not $package) {
        Add-Failure "MSIX: $($identity.Name) not registered after Add-AppxPackage"
      } else {
        Invoke-Diagnose (Join-Path $package.InstallLocation 'whispaste.exe') 'msix'
      }
    } finally {
      if ($package) { Remove-AppxPackage -Package $package.PackageFullName }
      Get-ChildItem 'Cert:\LocalMachine\TrustedPeople', 'Cert:\CurrentUser\My' |
        Where-Object { $_.Thumbprint -eq $cert.Thumbprint } |
        Remove-Item -ErrorAction SilentlyContinue
    }
  }
} finally {
  Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
  throw "Windows package smoke test: $($failures.Count) failure(s)."
}
Write-Host 'Windows package smoke test: all packages passed.'
