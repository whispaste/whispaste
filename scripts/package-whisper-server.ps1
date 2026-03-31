param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cpu", "cuda12", "vulkan")]
    [string]$Backend,
    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath,
    [string]$OutputDir = "",
    [string]$ChecksumFile = "",
    [string]$VulkanSDKRoot = "C:\VulkanSDK",
    [string]$CudaRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-RepoRoot {
    return Split-Path -Parent $PSScriptRoot
}

function Resolve-VersionedSdkDir {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (!(Test-Path $Root)) {
        throw "SDK root not found: $Root"
    }

    $dirs = Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^\d+\.\d+\.\d+\.\d+$'
    } | Sort-Object { [version]$_.Name } -Descending

    if ($dirs -and $dirs.Count -gt 0) {
        return $dirs[0].FullName
    }

    return $Root
}

function Resolve-VulkanSdkDir {
    param([Parameter(Mandatory = $true)][string]$Root)

    if ($env:VULKAN_SDK -and (Test-Path $env:VULKAN_SDK)) {
        return $env:VULKAN_SDK
    }

    return Resolve-VersionedSdkDir -Root $Root
}

function Resolve-CudaRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    if ($Root -and (Test-Path $Root)) {
        return $Root
    }
    if ($env:CUDA_PATH -and (Test-Path $env:CUDA_PATH)) {
        return $env:CUDA_PATH
    }
    return $null
}

function Copy-IfExists {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationDir
    )

    if (Test-Path $SourcePath) {
        Copy-Item -Force $SourcePath $DestinationDir
        return $true
    }
    return $false
}

function Copy-RequiredRuntimeDlls {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDir,
        [Parameter(Mandatory = $true)][string[]]$RequiredDlls,
        [Parameter(Mandatory = $true)][string]$DestinationDir,
        [Parameter(Mandatory = $true)][string]$BackendName
    )

    $missing = @()
    foreach ($dll in $RequiredDlls) {
        $sourcePath = Join-Path $BaseDir $dll
        if (!(Copy-IfExists -SourcePath $sourcePath -DestinationDir $DestinationDir)) {
            $missing += $dll
        }
    }

    if ($missing.Count -gt 0) {
        throw "Missing required $BackendName runtime DLLs in ${BaseDir}: $($missing -join ', ')"
    }
}

function Copy-OptionalRuntimeDlls {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDir,
        [Parameter(Mandatory = $true)][string[]]$OptionalDlls,
        [Parameter(Mandatory = $true)][string]$DestinationDir
    )

    foreach ($dll in $OptionalDlls) {
        Copy-IfExists -SourcePath (Join-Path $BaseDir $dll) -DestinationDir $DestinationDir | Out-Null
    }
}

if (!(Test-Path $ExecutablePath)) {
    throw "Executable not found: $ExecutablePath"
}

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot ".build\whisper-release"
}

$assetName = switch ($Backend) {
    "cpu" { "whisper-server-cpu-x64.zip" }
    "cuda12" { "whisper-server-cuda12-x64.zip" }
    "vulkan" { "whisper-server-vulkan-x64.zip" }
}

$stagingDir = Join-Path $OutputDir ("staging-" + $Backend)
$zipPath = Join-Path $OutputDir $assetName

if (Test-Path $stagingDir) {
    Remove-Item -Recurse -Force $stagingDir
}
if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}

New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$exeDir = Split-Path -Parent $ExecutablePath
Copy-Item -Force $ExecutablePath (Join-Path $stagingDir "whisper-server.exe")
Get-ChildItem -Path $exeDir -Filter *.dll -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -Force $_.FullName $stagingDir
}

switch ($Backend) {
    "cuda12" {
        $resolvedCuda = Resolve-CudaRoot -Root $CudaRoot
        if (-not $resolvedCuda) {
            throw "CUDA toolkit not found. Set -CudaRoot or CUDA_PATH before packaging CUDA assets."
        }
        Copy-RequiredRuntimeDlls `
            -BaseDir (Join-Path $resolvedCuda "bin") `
            -RequiredDlls @("cublas64_12.dll", "cublasLt64_12.dll", "cudart64_12.dll") `
            -DestinationDir $stagingDir `
            -BackendName "CUDA"
    }
    "vulkan" {
        $resolvedVulkan = Resolve-VulkanSdkDir -Root $VulkanSDKRoot
        $vulkanBin = Join-Path $resolvedVulkan "Bin"
        Copy-RequiredRuntimeDlls `
            -BaseDir $vulkanBin `
            -RequiredDlls @(
                "shaderc_shared.dll",
                "glslang.dll",
                "SPIRV-Tools-shared.dll",
                "spirv-cross-c-shared.dll",
                "dxcompiler.dll"
            ) `
            -DestinationDir $stagingDir `
            -BackendName "Vulkan"
        Copy-OptionalRuntimeDlls `
            -BaseDir $vulkanBin `
            -OptionalDlls @(
                "SPIRV-Tools-opt.dll",
                "dxil.dll"
            ) `
            -DestinationDir $stagingDir
    }
}

Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath -Force
$hash = (Get-FileHash -Algorithm SHA256 $zipPath).Hash.ToLowerInvariant()

if ([string]::IsNullOrWhiteSpace($ChecksumFile)) {
    $ChecksumFile = "$zipPath.sha256"
    "$hash  $assetName" | Set-Content -Encoding ascii $ChecksumFile
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ChecksumFile) | Out-Null
    "$hash  $assetName" | Add-Content -Encoding ascii $ChecksumFile
}

[pscustomobject]@{
    Backend      = $Backend
    AssetPath    = $zipPath
    ChecksumPath = $ChecksumFile
    Sha256       = $hash
}
