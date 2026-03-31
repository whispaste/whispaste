param(
    [Parameter(Mandatory = $true)]
    [string]$Tag,
    [ValidateSet("cpu", "cuda12", "vulkan")]
    [string[]]$Backends = @("cpu", "cuda12", "vulkan"),
    [string]$WhisperRef = "",
    [string]$SourceDir = "",
    [string]$BuildOutputDir = "",
    [string]$PackageOutputDir = "",
    [string]$VulkanSDKRoot = "C:\VulkanSDK",
    [string]$CudaRoot = "",
    [switch]$ReuseExistingBuilds,
    [switch]$CreateDraftRelease,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-RepoRoot {
    return Split-Path -Parent $PSScriptRoot
}

function Ensure-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (!(Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found in PATH: $Name"
    }
}

function Find-WhisperServerExe {
    param([Parameter(Mandatory = $true)][string]$BuildDir)

    $exe = Get-ChildItem -Path $BuildDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ieq "whisper-server.exe" -or $_.Name -ieq "server.exe"
    } | Sort-Object FullName | Select-Object -First 1

    return $exe
}

function Find-ReusableBuildExe {
    param(
        [Parameter(Mandatory = $true)][string]$Backend,
        [Parameter(Mandatory = $true)][string]$PreferredBuildRoot,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $candidateRoots = @(
        (Join-Path $PreferredBuildRoot ("build-" + $Backend)),
        (Join-Path $RepoRoot (".build\whisper-benchmark\build-" + $Backend)),
        (Join-Path $RepoRoot (".build\whisper-build\build-" + $Backend)),
        (Join-Path $RepoRoot (".build\build-" + $Backend))
    )

    foreach ($candidateRoot in $candidateRoots) {
        if (!(Test-Path $candidateRoot)) {
            continue
        }
        $exe = Find-WhisperServerExe -BuildDir $candidateRoot
        if ($exe) {
            return $exe
        }
    }

    return $null
}

Ensure-Command -Name "gh"

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($BuildOutputDir)) {
    $BuildOutputDir = "C:\wp\whisper-build"
}
if ([string]::IsNullOrWhiteSpace($PackageOutputDir)) {
    $PackageOutputDir = "C:\wp\whisper-release-local"
}

if ($Clean -and (Test-Path $PackageOutputDir)) {
    Remove-Item -Recurse -Force $PackageOutputDir
}
New-Item -ItemType Directory -Force -Path $PackageOutputDir | Out-Null

$packageScript = Join-Path $PSScriptRoot "package-whisper-server.ps1"
$buildScript = Join-Path $PSScriptRoot "build-whisper-server.ps1"
$combinedChecksum = Join-Path $PackageOutputDir "checksums.sha256"
if (Test-Path $combinedChecksum) {
    Remove-Item -Force $combinedChecksum
}

$assetPaths = @()
$perBackendChecksums = @()
$results = @()

foreach ($backend in $Backends) {
    $buildDir = Join-Path $BuildOutputDir ("build-" + $backend)
    $exe = $null

    if ($ReuseExistingBuilds) {
        $exe = Find-ReusableBuildExe -Backend $backend -PreferredBuildRoot $BuildOutputDir -RepoRoot $repoRoot
        if (-not $exe) {
            throw "No existing whisper-server executable found for backend '$backend' in $buildDir"
        }
    } else {
        $buildParams = @{
            Backend       = $backend
            WhisperRef    = $WhisperRef
            SourceDir     = $SourceDir
            OutputDir     = $BuildOutputDir
            VulkanSDKRoot = $VulkanSDKRoot
            CudaRoot      = $CudaRoot
        }
        if ($Clean) {
            $buildParams.Clean = $true
        }
        $buildResult = & $buildScript @buildParams
        $exe = Get-Item $buildResult.ExecutablePath
    }

    $checksumFile = Join-Path $PackageOutputDir ($backend + ".sha256")
    if (Test-Path $checksumFile) {
        Remove-Item -Force $checksumFile
    }

    $packageParams = @{
        Backend        = $backend
        ExecutablePath = $exe.FullName
        OutputDir      = $PackageOutputDir
        ChecksumFile   = $checksumFile
        VulkanSDKRoot  = $VulkanSDKRoot
        CudaRoot       = $CudaRoot
    }
    $packageResult = & $packageScript @packageParams
    $assetPaths += $packageResult.AssetPath
    $perBackendChecksums += $packageResult.ChecksumPath
    $results += $packageResult
}

foreach ($checksumPath in $perBackendChecksums) {
    Get-Content $checksumPath | Add-Content -Encoding ascii $combinedChecksum
}

gh release view $Tag *> $null
if ($LASTEXITCODE -ne 0) {
    if ($CreateDraftRelease) {
        gh release create $Tag --draft --prerelease --title "Whisper Server Assets ($Tag)" --notes "Local-first whisper-server asset publish."
    } else {
        throw "GitHub release for tag '$Tag' was not found. Re-run with -CreateDraftRelease or create the release first."
    }
}

$filesToUpload = @($assetPaths + $combinedChecksum)
gh release upload $Tag @filesToUpload --clobber
if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload whisper-server assets to release '$Tag'"
}

[pscustomobject]@{
    Tag              = $Tag
    Backends         = $Backends
    BuildOutputDir   = $BuildOutputDir
    PackageOutputDir = $PackageOutputDir
    AssetPaths       = $assetPaths
    ChecksumPath     = $combinedChecksum
    Uploaded         = $true
}
