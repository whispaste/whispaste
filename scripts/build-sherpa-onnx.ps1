# build-sherpa-onnx.ps1 — Windows counterpart of scripts/build-sherpa-onnx.sh.
# Builds sherpa-onnx's C API (sherpa-onnx-c-api.dll) from the pinned tag WITHOUT
# text-to-speech, so espeak-ng (GPL-3.0-or-later) is never linked, and stages
# the DLLs in .build\sherpa-onnx\windows for the Windows bundle.
#
# Verified by probe build (BUILD.md): 3.2 MB DLL, same 172 SherpaOnnx* exports
# as the pub original, no espeak-ng marker, identical recognition output.
# onnxruntime_providers_shared.dll is not needed (only onnxruntime.dll ships).
#
# Usage (from the repo root, Visual Studio 2022+ C++ tools and CMake on PATH):
#   pwsh -File scripts\build-sherpa-onnx.ps1
#   powershell -File scripts\build-sherpa-onnx.ps1   (Windows PowerShell 5.1)
param(
  [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 has no -MaximumRetryCount and may still default to a
# TLS version GitHub refuses; PowerShell 7 ignores this setting.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Invoke-DownloadWithRetry([string] $Uri, [string] $OutFile, [int] $Attempts = 4, [int] $DelaySec = 5) {
  # The progress bar slows Windows PowerShell 5.1 downloads down many times over.
  $ProgressPreference = 'SilentlyContinue'
  for ($attempt = 1; ; $attempt++) {
    try {
      Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
      return
    } catch {
      if ($attempt -ge $Attempts) {
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        throw "Download of $Uri failed after $attempt attempts: $($_.Exception.Message)"
      }
      Write-Host "Download attempt $attempt of $Attempts failed ($($_.Exception.Message)), retrying in $DelaySec s"
      Start-Sleep -Seconds $DelaySec
    }
  }
}

# Pinned source: scripts/sherpa-onnx.pin (shared with build-sherpa-onnx.sh and
# the stage check). The tag must match the sherpa_onnx version in pubspec.lock.
$pin = @{}
Get-Content (Join-Path $RepoRoot 'scripts\sherpa-onnx.pin') | ForEach-Object {
  if ($_ -match '^([A-Z0-9_]+)=(\S*)$') { $pin[$matches[1]] = $matches[2] }
}
$SherpaTag = $pin['SHERPA_TAG']
$SherpaCommit = $pin['SHERPA_COMMIT']
if (-not $SherpaTag -or -not $SherpaCommit) { throw 'scripts\sherpa-onnx.pin must define SHERPA_TAG and SHERPA_COMMIT' }
$SherpaRepo = 'https://github.com/k2-fsa/sherpa-onnx'

$src = Join-Path $RepoRoot ".build\deps\sherpa-onnx\$SherpaTag"
$build = Join-Path $RepoRoot '.build\sherpa-onnx\windows-build'
$stage = Join-Path $RepoRoot '.build\sherpa-onnx\windows'
# Sibling of the stage, never inside it: bundle and stage checks only know the DLLs.
$pdbDir = Join-Path $RepoRoot '.build\sherpa-onnx\windows-pdb'

# 1. Fetch the pinned tag and verify the commit (supply-chain guard).
if (-not (Test-Path (Join-Path $src '.git'))) {
  New-Item -ItemType Directory -Force -Path (Split-Path $src) | Out-Null
  git clone --depth 1 --branch $SherpaTag $SherpaRepo $src
  if ($LASTEXITCODE -ne 0) { throw "git clone of $SherpaTag failed" }
}
$actual = (git -C $src rev-parse HEAD).Trim()
if ($actual -ne $SherpaCommit) {
  throw "$src is at $actual, expected $SherpaCommit ($SherpaTag). Delete it and re-run."
}

# 1b. Fetch onnxruntime (MD, Release, the sherpa default) and verify its SHA-256
# against scripts/sherpa-onnx.pin before cmake sees it (GS-008). sherpa's cmake
# takes a local archive from the build directory and still checks the hash it
# pins; the build also asserts sherpa pins the same hash.
$ortName = $pin['ORT_WIN_X64_MD_RELEASE']
$ortWant = $pin['ORT_WIN_X64_MD_RELEASE_SHA256']
$ortVersion = $pin['ORT_VERSION']
if (-not $ortName -or -not $ortWant) { throw 'scripts\sherpa-onnx.pin lacks the onnxruntime win-x64 pin' }
$sherpaOrtCmake = Join-Path $src 'cmake\onnxruntime-win-x64.cmake'
if (-not (Select-String -Path $sherpaOrtCmake -SimpleMatch -Quiet -Pattern $ortWant)) {
  throw "sherpa-onnx $SherpaTag cmake\onnxruntime-win-x64.cmake does not pin SHA-256 $ortWant. Update scripts\sherpa-onnx.pin."
}
New-Item -ItemType Directory -Force -Path $build | Out-Null
$ortFile = Join-Path $build $ortName
$haveOrt = (Test-Path $ortFile) -and ((Get-FileHash $ortFile -Algorithm SHA256).Hash.ToLower() -eq $ortWant)
if (-not $haveOrt) {
  $ortUrl = "https://github.com/csukuangfj/onnxruntime-libs/releases/download/v$ortVersion/$ortName"
  Invoke-DownloadWithRetry -Uri $ortUrl -OutFile "$ortFile.partial"
  $got = (Get-FileHash "$ortFile.partial" -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $ortWant) { Remove-Item "$ortFile.partial" -Force; throw "onnxruntime $ortName has SHA-256 $got, pinned $ortWant. Refusing to use it." }
  Move-Item "$ortFile.partial" $ortFile -Force
}

# 2. Configure: shared C API only, TTS and everything else off.
$cmakeArgs = @(
  '-S', $src, '-B', $build, '-A', 'x64',
  '-DCMAKE_BUILD_TYPE=Release',
  '-DBUILD_SHARED_LIBS=ON',
  '-DSHERPA_ONNX_ENABLE_TTS=OFF',
  '-DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF',
  '-DSHERPA_ONNX_ENABLE_PYTHON=OFF',
  '-DSHERPA_ONNX_ENABLE_TESTS=OFF',
  '-DSHERPA_ONNX_ENABLE_BINARY=OFF',
  '-DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF',
  '-DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF',
  '-DSHERPA_ONNX_ENABLE_JNI=OFF',
  '-DSHERPA_ONNX_ENABLE_C_API=ON',
  # /Z7 + /DEBUG: PDB for Sentry (same flags as libwhisper/libllama). /OPT:REF
  # /OPT:ICF are restored because /DEBUG alone switches the linker to NOREF.
  '-DCMAKE_C_FLAGS=/Z7',
  '-DCMAKE_CXX_FLAGS=/Z7',
  '-DCMAKE_SHARED_LINKER_FLAGS=/DEBUG /OPT:REF /OPT:ICF'
)
Write-Host "==> configure windows x64 ($SherpaTag, TTS=OFF)"
cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed' }

# 3. Build only the C API target.
Write-Host '==> build sherpa-onnx-c-api'
cmake --build $build --config Release --target sherpa-onnx-c-api --parallel
if ($LASTEXITCODE -ne 0) { throw 'cmake build failed' }

# 4. Stage the DLLs (sherpa writes them under build\bin\Release or build\lib\Release).
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
$wanted = @('sherpa-onnx-c-api.dll', 'onnxruntime.dll')
foreach ($name in $wanted) {
  $found = Get-ChildItem $build -Recurse -File -Filter $name |
    Where-Object { $_.FullName -match '\\Release\\' } | Select-Object -First 1
  if (-not $found) { throw "$name not found under $build (Release)" }
  Copy-Item $found.FullName $stage -Force
}
# PDB of the C API DLL for Sentry and the .msixupload (release.yml). onnxruntime.dll
# is a prebuilt download we do not compile, so it has no PDB here.
if (Test-Path $pdbDir) { Remove-Item $pdbDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pdbDir | Out-Null
$pdb = Get-ChildItem $build -Recurse -File -Filter 'sherpa-onnx-c-api.pdb' |
  Where-Object { $_.FullName -match '\\Release\\' } | Select-Object -First 1
if (-not $pdb) { throw 'sherpa-onnx-c-api.pdb not found (Release) -- /Z7 + /DEBUG lost from the sherpa build?' }
Copy-Item $pdb.FullName $pdbDir -Force
$info = @(
  "sherpa-onnx $SherpaTag ($SherpaCommit)",
  'platform: windows-x64',
  'tts: OFF (no espeak-ng, no piper-phonemize)',
  "built: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
)
# SHA-256 of every staged file, checked after the cache restore (GS-007).
Get-ChildItem $stage -File | Where-Object { $_.Name -ne 'BUILD_INFO' } | ForEach-Object {
  $info += "sha256 $($_.Name) $((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower())"
}
$info | Set-Content -Path (Join-Path $stage 'BUILD_INFO') -Encoding ascii

# 5. Refuse to stage anything that does not match the pins, or that still
# carries espeak-ng. The stage check is CMake (same file as Linux/macOS); the
# guard is a bash script, so use the Git for Windows bash next to git.exe.
cmake "-DSTAGE_DIR=$stage" "-DREPO_ROOT=$RepoRoot" -P (Join-Path $RepoRoot 'scripts\check-sherpa-stage.cmake')
if ($LASTEXITCODE -ne 0) { throw 'sherpa-onnx stage check failed' }
$gitBash = Join-Path (Split-Path (Get-Command git).Source) '..\bin\bash.exe'
if (-not (Test-Path $gitBash)) { throw "Git for Windows bash not found at $gitBash" }
& $gitBash (Join-Path $RepoRoot 'scripts/check-no-espeak.sh') (Resolve-Path $stage).Path
if ($LASTEXITCODE -ne 0) { throw 'espeak-ng guard failed on the staged sherpa-onnx DLLs' }
Get-ChildItem $stage | Format-Table Name, Length -AutoSize | Out-String | Write-Host
