param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cpu", "cuda12", "vulkan")]
    [string]$Backend,
    [string]$WhisperRef = "",
    [string]$SourceDir = "",
    [string]$OutputDir = "",
    [string]$VulkanSDKRoot = "C:\VulkanSDK",
    [string]$CudaRoot = "",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-RepoRoot {
    return Split-Path -Parent $PSScriptRoot
}

function Get-ShortWorkRoot {
    $drive = $env:SystemDrive
    if ([string]::IsNullOrWhiteSpace($drive)) {
        $drive = "C:"
    }
    $root = Join-Path $drive "wp"
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function Read-PinnedWhisperRef {
    $refFile = Join-Path $PSScriptRoot "whispercpp-ref.txt"
    if (!(Test-Path $refFile)) {
        throw "Pinned whisper.cpp ref not found: $refFile"
    }
    $value = (Get-Content -Path $refFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Pinned whisper.cpp ref is empty: $refFile"
    }
    return $value
}

function Ensure-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (!(Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found in PATH: $Name"
    }
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
    throw "CUDA toolkit not found. Set -CudaRoot or CUDA_PATH."
}

function Resolve-WhisperSourceDir {
    param(
        [Parameter(Mandatory = $true)][string]$Ref,
        [string]$RequestedSourceDir = "",
        [Parameter(Mandatory = $true)][string]$CacheRoot
    )

    if (![string]::IsNullOrWhiteSpace($RequestedSourceDir)) {
        if (!(Test-Path $RequestedSourceDir)) {
            throw "Provided whisper.cpp source directory not found: $RequestedSourceDir"
        }
        return (Resolve-Path $RequestedSourceDir).Path
    }

    Ensure-Command -Name "git"
    $safeRef = ($Ref -replace '[^A-Za-z0-9._-]', '_')
    $cloneDir = Join-Path $CacheRoot $safeRef

    if (!(Test-Path $cloneDir)) {
        New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
        & git clone --depth 1 --branch $Ref https://github.com/ggml-org/whisper.cpp.git $cloneDir
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone whisper.cpp ref $Ref"
        }
    }

    return $cloneDir
}

Ensure-Command -Name "cmake"

$repoRoot = Get-RepoRoot
$shortWorkRoot = Get-ShortWorkRoot
if ([string]::IsNullOrWhiteSpace($WhisperRef)) {
    $WhisperRef = Read-PinnedWhisperRef
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $shortWorkRoot "whisper-build"
}

$cacheRoot = Join-Path $shortWorkRoot "whisper-src"
$sourcePath = Resolve-WhisperSourceDir -Ref $WhisperRef -RequestedSourceDir $SourceDir -CacheRoot $cacheRoot
$buildDir = Join-Path $OutputDir ("build-" + $Backend)

if ($Clean -and (Test-Path $buildDir)) {
    Remove-Item -Recurse -Force $buildDir
}
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

$cmakeArgs = @(
    "-S", $sourcePath,
    "-B", $buildDir,
    "-G", "Visual Studio 17 2022",
    "-A", "x64",
    "-DWHISPER_BUILD_SERVER=ON",
    "-DCMAKE_BUILD_TYPE=Release"
)

switch ($Backend) {
    "cuda12" {
        $resolvedCuda = Resolve-CudaRoot -Root $CudaRoot
        $env:CUDA_PATH = $resolvedCuda
        $cmakeArgs += @(
            "-DGGML_CUDA=ON",
            "-DCUDAToolkit_ROOT=$resolvedCuda"
        )
    }
    "vulkan" {
        $resolvedVulkan = Resolve-VulkanSdkDir -Root $VulkanSDKRoot
        $env:VULKAN_SDK = $resolvedVulkan
        $vulkanBin = Join-Path $resolvedVulkan "Bin"
        if (Test-Path $vulkanBin) {
            $env:PATH = "$vulkanBin;$env:PATH"
        }
        $cmakeArgs += "-DGGML_VULKAN=ON"
    }
}

& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
    throw "CMake configure failed for backend: $Backend"
}

& cmake --build $buildDir --config Release --target whisper-server
if ($LASTEXITCODE -ne 0) {
    throw "CMake build failed for backend: $Backend"
}

$exe = Get-ChildItem -Path $buildDir -Recurse -File | Where-Object {
    $_.Name -ieq "whisper-server.exe" -or $_.Name -ieq "server.exe"
} | Sort-Object FullName | Select-Object -First 1

if (-not $exe) {
    throw "whisper-server.exe was not produced for backend: $Backend"
}

[pscustomobject]@{
    Backend        = $Backend
    WhisperRef     = $WhisperRef
    SourceDir      = $sourcePath
    BuildDir       = $buildDir
    ExecutablePath = $exe.FullName
}
