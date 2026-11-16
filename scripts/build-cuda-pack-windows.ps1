# build-cuda-pack-windows.ps1 — builds the optional Windows CUDA backend pack
# WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-windows-x64.zip: ggml-cuda.dll plus the
# CUDA 12.8.1 runtime DLLs it imports. Runs on the test-lab VM win-vm under Windows
# PowerShell 5.1. tool/cuda_pack_build.sh starts it detached and polls the
# build-windows.done marker in the work directory.
#
# Same whisper.cpp pin, CUDA redist and ggml options as the Linux pack, with
# Vulkan off and only the ggml-cuda target built. Like the Linux pack, only
# ggml-cuda.dll is modified (none, in fact); the CUDA DLLs are copied as shipped.
#
# Toolchain: MSVC from VS Build Tools 2026 (18.x), activated through VsDevCmd.bat.
# CUDA 12.8's nvcc only knows MSVC up to VS 2022 and rejects newer hosts, so the
# build passes -allow-unsupported-compiler via CMAKE_CUDA_FLAGS. Upstream's
# Windows CUDA job avoids this by using windows-2022; VS 2022 is deliberately
# not installed on this box.
#
# Usage:   powershell -NoProfile -ExecutionPolicy Bypass -File build-cuda-pack-windows.ps1
#            [-WorkDir C:\wp-cuda-build] [-BuildJobs 4] [-InstallPrereqs]
# Output:  <WorkDir>\out\WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-windows-x64.zip
#          <WorkDir>\build-windows.log and build-windows.done (DONE_RC=<exit code>)
[CmdletBinding()]
param(
  [string]$WorkDir = 'C:\wp-cuda-build',
  [int]$BuildJobs = 8,
  [string]$CudaArchs = '75;86-real;89-real;120-real',
  [switch]$InstallPrereqs
)

$ErrorActionPreference = 'Stop'

$PackId = 'WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-windows-x64'
$CudaVersion = '12.8.1'
$ScriptDir = $PSScriptRoot
# whisper.cpp pin: scripts\whisper-cpp.pin, synced next to this script.
$Pin = @{}
Get-Content (Join-Path $ScriptDir 'whisper-cpp.pin') | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)=(.*)$') { $Pin[$Matches[1]] = $Matches[2].Trim() }
}
$WhisperTag = $Pin['WHISPER_TAG']
$WhisperPinnedCommit = $Pin['WHISPER_COMMIT']
if (-not $WhisperTag -or -not $WhisperPinnedCommit) { throw 'whisper-cpp.pin needs WHISPER_TAG and WHISPER_COMMIT' }
# The pack id names the whisper.cpp version; a raised pin needs a new pack id.
if (-not $PackId.Contains("-ggml-$WhisperTag-")) { throw "PackId $PackId does not match whisper-cpp.pin ($WhisperTag)" }

# Versioned by tag: an upgrade clones fresh instead of failing the pin check.
$Src = Join-Path $WorkDir "src\whisper.cpp-$WhisperTag"
$CudaHome = Join-Path $WorkDir 'cuda'
$Build = Join-Path $WorkDir "build-$WhisperTag"
$Stage = Join-Path $WorkDir ('stage\' + $PackId)
$OutDir = Join-Path $WorkDir 'out'
$LicenseFile = Join-Path $ScriptDir 'LICENSE-NVIDIA.txt'
$LicenseSha256 = '95815d3a862cf6bb5b3b58b661c3a3172a58b9ca6fcfa36b0e3d19a8e63a18e3'
$DoneMarker = Join-Path $WorkDir 'build-windows.done'
$LogFile = Join-Path $WorkDir 'build-windows.log'

function Write-Step([string]$Message) {
  Write-Host ''
  Write-Host "== $Message"
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

# Runs a native tool, streams its output to the log and fails on a non-zero exit.
# ErrorActionPreference is relaxed locally: Windows PowerShell turns stderr
# progress lines (git, cmake, nvcc) into terminating errors under 'Stop'.
function Invoke-Native([string]$Exe, [string[]]$CmdArgs) {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $Exe @CmdArgs 2>&1 | ForEach-Object { Write-Host "$_" }
  } finally {
    $ErrorActionPreference = $previous
  }
  if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE" }
}

# Same as Invoke-Native, but returns the output lines instead of logging them.
function Get-Native([string]$Exe, [string[]]$CmdArgs) {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = & $Exe @CmdArgs 2>&1 | ForEach-Object { "$_" }
  } finally {
    $ErrorActionPreference = $previous
  }
  if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE" }
  return $output
}

function Import-VsDevEnvironment {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found: Visual Studio Build Tools are missing' }
  $vsPath = (Get-Native $vswhere @('-latest', '-products', '*', '-requires',
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath')) |
    Select-Object -First 1
  if (-not $vsPath) { throw 'no Visual Studio install with the C++ x64 toolchain found' }
  Write-Host "Visual Studio: $vsPath"

  # VsDevCmd.bat plus `set` dumped by a helper .cmd, so no quoting reaches cmd.exe
  # from PowerShell's argument passing.
  $devCmd = Join-Path $vsPath 'Common7\Tools\VsDevCmd.bat'
  # CUDA 12.8 accepts MSVC up to the VS 2022 toolsets (14.4x); newer ones fail
  # even with -allow-unsupported-compiler (cudafe++ crashes on their STL). Use
  # the newest 14.4x side-by-side toolset when one is installed.
  $vcvarsVer = ''
  $toolset = Get-ChildItem (Join-Path $vsPath 'VC\Tools\MSVC') -Directory -Filter '14.4*' -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
  if ($toolset) {
    $vcvarsVer = ' -vcvars_ver=' + (($toolset.Name -split '\.')[0..1] -join '.')
    Write-Host "MSVC toolset pinned: $($toolset.Name)"
  }
  $envScript = Join-Path $WorkDir 'vsdevenv.cmd'
  Set-Content -Path $envScript -Encoding ascii -Value @(
    '@echo off',
    "call `"$devCmd`" -arch=amd64 -host_arch=amd64 -no_logo$vcvarsVer",
    '@set')
  foreach ($line in (Get-Native 'cmd.exe' @('/d', '/c', $envScript))) {
    if ($line -match '^([^=]+)=(.*)$') {
      [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
  }
}

# First working Python 3: PATH entries can be stale shims (or the Store alias),
# so each candidate is actually run.
function Find-Python {
  $candidates = @(Get-Command python -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
  $candidates += @(Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | ForEach-Object { $_.FullName })
  foreach ($candidate in $candidates) {
    try { $version = (Get-Native $candidate @('--version')) -join ' ' } catch { continue }
    if ($version -match 'Python 3\.') { return $candidate }
  }
  throw 'no working Python 3 found (run once with -InstallPrereqs)'
}

function Install-Prereqs {
  if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Step 'winget: Python 3.12 (per-user)'
    Invoke-Native 'winget' @('install', '-e', '--id', 'Python.Python.3.12', '--scope', 'user',
      '--silent', '--accept-source-agreements', '--accept-package-agreements')
  }
  Write-Host 'prerequisites checked; start the build in a new session so PATH is current'
}

function Test-LicenseFile([string]$Path = $LicenseFile) {
  # The pack ships NVIDIA's full CUDA EULA text; refuse to build without it.
  # The text is pinned by SHA-256: a changed file is a deliberate bump, not a silent update.
  if (-not (Test-Path $Path)) { throw "$Path missing (NVIDIA CUDA EULA text is required in every pack)" }
  if ([IO.File]::ReadAllText($Path).Trim().Length -eq 0) { throw "$Path is empty" }
  $actual = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
  if ($actual -ne $LicenseSha256) {
    throw "$Path text changed, bump the pinned hash deliberately (expected $LicenseSha256, got $actual)"
  }
}

function Invoke-Pack {
  Test-LicenseFile
  Write-Step 'toolchain'
  Import-VsDevEnvironment
  foreach ($tool in 'cmake', 'ninja', 'git', 'dumpbin') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool not on PATH after VsDevCmd" }
  }
  $python = Find-Python
  Write-Host ((Get-Native 'cmake' @('--version')) | Select-Object -First 1)
  Write-Host ("ninja " + (Get-Native 'ninja' @('--version')))
  Write-Host "MSVC toolset $env:VCToolsVersion (VS $env:VSCMD_VER)"
  Write-Host (Get-Native $python @('--version'))

  Write-Step "[1/6] whisper.cpp $WhisperTag source"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Src) | Out-Null
  if (-not (Test-Path (Join-Path $Src '.git'))) {
    Invoke-Native 'git' @('clone', '--depth', '1', '--branch', $WhisperTag,
      'https://github.com/ggml-org/whisper.cpp', $Src)
  }
  $actualCommit = (Get-Native 'git' @('-C', $Src, 'rev-parse', 'HEAD') | Select-Object -First 1).Trim()
  if ($actualCommit -ne $WhisperPinnedCommit) {
    throw "whisper.cpp commit mismatch (expected $WhisperPinnedCommit, got $actualCommit)"
  }
  Write-Host "source verified: $WhisperTag @ $WhisperPinnedCommit"

  Write-Step "[2/6] CUDA $CudaVersion from NVIDIA redist archives"
  if (-not (Test-Path (Join-Path $CudaHome 'bin\nvcc.exe'))) {
    Invoke-Native $python @((Join-Path $ScriptDir 'fetch-cuda-redist.py'), $CudaVersion,
      'windows-x86_64', $CudaHome)
  }
  $env:CUDA_PATH = $CudaHome
  $env:CUDACXX = Join-Path $CudaHome 'bin\nvcc.exe'
  $env:Path = (Join-Path $CudaHome 'bin') + ';' + $env:Path
  Write-Host ((Get-Native $env:CUDACXX @('--version')) | Select-Object -Last 1)

  Write-Step "[3/6] cmake configure + build (ggml-cuda, archs $CudaArchs, jobs $BuildJobs)"
  Invoke-Native 'cmake' @(
    '-S', $Src, '-B', $Build, '-G', 'Ninja',
    '-DCMAKE_BUILD_TYPE=Release',
    '-DBUILD_SHARED_LIBS=ON',
    '-DGGML_CUDA=ON',
    "-DCMAKE_CUDA_ARCHITECTURES=$CudaArchs",
    '-DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler',
    # /Z7 + /DEBUG: PDB for Sentry; /OPT:REF /OPT:ICF restored because /DEBUG
    # alone switches the linker to NOREF. Same flags as libwhisper/libllama.
    '-DCMAKE_C_FLAGS=/Z7',
    '-DCMAKE_CXX_FLAGS=/Z7',
    '-DCMAKE_SHARED_LINKER_FLAGS=/DEBUG /OPT:REF /OPT:ICF',
    '-DGGML_VULKAN=OFF',
    '-DGGML_NATIVE=OFF',
    '-DGGML_OPENMP=OFF',
    '-DGGML_BACKEND_DL=ON',
    '-DGGML_CPU_ALL_VARIANTS=ON',
    '-DWHISPER_BUILD_EXAMPLES=OFF',
    '-DWHISPER_BUILD_TESTS=OFF',
    '-DWHISPER_BUILD_SERVER=OFF')
  Invoke-Native 'cmake' @('--build', $Build, '--config', 'Release', '--target', 'ggml-cuda', '-j', "$BuildJobs")

  $module = @(Get-ChildItem -Path $Build -Recurse -Filter 'ggml-cuda.dll' -File)
  if ($module.Count -ne 1) { throw "expected exactly one ggml-cuda.dll, found $($module.Count)" }
  $modulePath = $module[0].FullName

  # ggml-cuda.pdb goes to $WorkDir\pdb for a manual Sentry upload. It stays out
  # of the stage on purpose: the pack zip is built from the stage directory.
  $pdbDir = Join-Path $WorkDir 'pdb'
  Remove-Item $pdbDir -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $pdbDir | Out-Null
  $modulePdb = [IO.Path]::ChangeExtension($modulePath, '.pdb')
  if (-not (Test-Path $modulePdb)) { throw "ggml-cuda.pdb missing next to $modulePath -- /Z7 + /DEBUG lost?" }
  Copy-Item $modulePdb $pdbDir -Force

  Write-Step '[4/6] staging ggml-cuda.dll + CUDA runtime DLLs'
  Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $Stage | Out-Null
  Copy-Item $modulePath $Stage
  foreach ($dll in 'cudart64_12.dll', 'cublas64_12.dll', 'cublasLt64_12.dll') {
    $source = Join-Path $CudaHome "bin\$dll"
    if (-not (Test-Path $source)) { throw "$dll missing from the CUDA redist" }
    Copy-Item $source $Stage
  }

  # Import check: only our CUDA runtime, ggml-base (app-provided), the driver
  # (nvcuda.dll) and system DLLs may be imported.
  $imports = @(Get-Native 'dumpbin' @('/nologo', '/dependents', $modulePath) | ForEach-Object {
    if ($_ -match '^\s+(\S+\.dll)\s*$') { $Matches[1].ToLower() }
  })
  Write-Host "imports: $($imports -join ', ')"
  foreach ($required in 'cudart64_12.dll', 'cublas64_12.dll', 'ggml-base.dll') {
    if ($imports -notcontains $required) { throw "ggml-cuda.dll does not import $required; the runtime list is stale" }
  }
  $packaged = @('cudart64_12.dll', 'cublas64_12.dll', 'cublaslt64_12.dll', 'ggml-base.dll', 'nvcuda.dll')
  foreach ($import in $imports) {
    if ($packaged -contains $import) { continue }
    if ($import -like 'api-ms-win-*' -or $import -like 'ext-ms-*') { continue }
    if (Test-Path (Join-Path $env:SystemRoot "System32\$import")) { continue }
    throw "unexpected import $import (not a system DLL, not packaged)"
  }

  # NOTICE.txt: the template with the whisper.cpp MIT license text inserted.
  $license = [IO.File]::ReadAllText((Join-Path $Src 'LICENSE')).Replace("`r`n", "`n").TrimEnd("`n")
  $template = [IO.File]::ReadAllText((Join-Path $ScriptDir 'cuda-pack-NOTICE.template.txt')).Replace("`r`n", "`n")
  Write-Utf8NoBom (Join-Path $Stage 'NOTICE.txt') $template.Replace('@WHISPER_LICENSE@', $license)
  Copy-Item $LicenseFile (Join-Path $Stage 'LICENSE-NVIDIA.txt')
  Test-LicenseFile (Join-Path $Stage 'LICENSE-NVIDIA.txt')

  Write-Step '[5/6] SHA256SUMS + verify'
  $names = @(Get-ChildItem -Path $Stage -File | ForEach-Object { $_.Name })
  [Array]::Sort($names, [StringComparer]::Ordinal)
  $sums = foreach ($name in $names) {
    $hash = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Stage $name)).Hash.ToLower()
    "$hash  $name"
  }
  Write-Utf8NoBom (Join-Path $Stage 'SHA256SUMS') (($sums -join "`n") + "`n")
  $names += 'SHA256SUMS'
  foreach ($required in 'ggml-cuda.dll', 'cudart64_12.dll', 'cublas64_12.dll', 'cublasLt64_12.dll', 'NOTICE.txt', 'LICENSE-NVIDIA.txt', 'SHA256SUMS') {
    if ($names -notcontains $required) { throw "pack is missing $required" }
  }

  Write-Step '[6/6] zip (files at the archive root)'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $zipPath = Join-Path $OutDir "$PackId.zip"
  Remove-Item $zipPath -ErrorAction SilentlyContinue
  [IO.Compression.ZipFile]::CreateFromDirectory($Stage, $zipPath,
    [IO.Compression.CompressionLevel]::Optimal, $false)
  $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $entries = @($zip.Entries | ForEach-Object { $_.FullName })
  } finally {
    $zip.Dispose()
  }
  if ($entries | Where-Object { $_ -match '[\\/]' }) { throw 'zip contains a subfolder; files must sit at the root' }

  Write-Host ''
  Get-ChildItem -Path $Stage -File | ForEach-Object { '{0,14:N0}  {1}' -f $_.Length, $_.Name }
  $unpacked = (Get-ChildItem -Path $Stage -File | Measure-Object -Property Length -Sum).Sum
  Write-Host ('unpacked total: {0:N0} bytes' -f $unpacked)
  $archive = Get-Item $zipPath
  Write-Host ('archive: {0} ({1:N0} bytes)' -f $archive.FullName, $archive.Length)
  Write-Host ('sha256: ' + (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLower())
}

# -InstallPrereqs only installs; it must not write the done marker that the driver polls.
if ($InstallPrereqs) {
  New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
  Install-Prereqs
  exit 0
}

$exitCode = 1
try {
  Remove-Item $DoneMarker -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
  Start-Transcript -Path $LogFile -Force | Out-Null
  $started = Get-Date
  Invoke-Pack
  Write-Host ('build duration: {0:N0} s' -f ((Get-Date) - $started).TotalSeconds)
  $exitCode = 0
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Write-Host $_.ScriptStackTrace
} finally {
  try { Stop-Transcript | Out-Null } catch { }
  "DONE_RC=$exitCode" | Out-File -FilePath $DoneMarker -Encoding ascii
}
exit $exitCode
