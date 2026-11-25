# build-sherpa-onnx.ps1 — Windows counterpart of scripts/build-sherpa-onnx.sh.
# Builds sherpa-onnx's C API (sherpa-onnx-c-api.dll) from the pinned tag WITHOUT
# text-to-speech, so espeak-ng (GPL-3.0-or-later) is never linked, and stages
# the DLLs in .build\sherpa-onnx\windows for the Windows bundle.
#
# Verified by probe build (BUILD.md): 3.3 MB DLL on v2.0.1, no espeak-ng marker,
# Parakeet recognition checked in the test lab.
# DirectML.dll is bundled next to onnxruntime.dll; neither needs CUDA.
#
# Usage (from the repo root, Visual Studio 2022+ C++ tools and CMake on PATH):
#   pwsh -File scripts\build-sherpa-onnx.ps1
#   powershell -File scripts\build-sherpa-onnx.ps1   (Windows PowerShell 5.1)
param(
  [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [switch] $CpuOnly,
  [int] $Jobs = 2
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
if ($CpuOnly) {
  $build = Join-Path $RepoRoot '.build\sherpa-onnx\windows-cpu-build'
  $stage = Join-Path $RepoRoot '.build\sherpa-onnx\windows-cpu'
}
# Sibling of the stage, never inside it: bundle and stage checks only know the DLLs.
$pdbDir = Join-Path $RepoRoot $(if ($CpuOnly) { '.build\sherpa-onnx\windows-cpu-pdb' } else { '.build\sherpa-onnx\windows-pdb' })

# 1. Fetch the pinned tag and verify the commit (supply-chain guard).
if (-not (Test-Path (Join-Path $src '.git'))) {
  New-Item -ItemType Directory -Force -Path (Split-Path $src) | Out-Null
  git -c core.longpaths=true clone --depth 1 --branch $SherpaTag $SherpaRepo $src
  if ($LASTEXITCODE -ne 0) { throw "git clone of $SherpaTag failed" }
}
$actual = (git -C $src rev-parse HEAD).Trim()
if ($actual -ne $SherpaCommit) {
  throw "$src is at $actual, expected $SherpaCommit ($SherpaTag). Delete it and re-run."
}

$patch = Join-Path $RepoRoot 'scripts\sherpa-provider.patch'
$ErrorActionPreference = 'Continue'
git -C $src apply --reverse --check $patch 2>$null
$patched = $LASTEXITCODE -eq 0
$ErrorActionPreference = 'Stop'
if (-not $patched) {
  git -C $src apply --check $patch
  if ($LASTEXITCODE -ne 0) { throw 'Sherpa provider patch does not apply' }
  git -C $src apply $patch
  if ($LASTEXITCODE -ne 0) { throw 'Sherpa provider patch failed' }
}
if ($CpuOnly) {
# 1b. Microsoft supplies matching DLLs and PDBs. Verify our own Windows pin
# before extraction (GS-008), deliberately not sherpa's different archive hash.
$ortName = $pin['ORT_WIN_X64_MD_RELEASE']
$ortWant = $pin['ORT_WIN_X64_MD_RELEASE_SHA256']
$ortVersion = $pin['ORT_VERSION']
if (-not $ortName -or -not $ortWant) { throw 'scripts\sherpa-onnx.pin lacks the onnxruntime win-x64 pin' }
# A build directory configured from another sherpa tag (after a pin bump)
# makes cmake stop with "does not match the source ... used to generate cache".
# Start it fresh instead; the stage itself is replaced below anyway.
$cache = Join-Path $build 'CMakeCache.txt'
if (Test-Path $cache) {
  $line = Select-String -Path $cache -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=' | Select-Object -First 1
  $cacheHome = if ($line) { $line.Line.Split('=', 2)[1] } else { '' }
  if ([System.IO.Path]::GetFullPath($cacheHome.Replace('/', '\')) -ne [System.IO.Path]::GetFullPath($src)) {
    Write-Host "==> $build was configured from $cacheHome; starting it fresh"
    Remove-Item $build -Recurse -Force
  }
}
New-Item -ItemType Directory -Force -Path $build | Out-Null
$ortFile = Join-Path $build $ortName
$haveOrt = (Test-Path $ortFile) -and ((Get-FileHash $ortFile -Algorithm SHA256).Hash.ToLower() -eq $ortWant)
if (-not $haveOrt) {
  # Microsoft's release first, then byte-identical copies from WP_ORT_ARCHIVE_MIRRORS
  # (';'-separated base URLs). Any source must match the same SHA-256 pin below.
  $ortUrls = @("https://github.com/microsoft/onnxruntime/releases/download/v$ortVersion/$ortName")
  $ortMirrors = $env:WP_ORT_ARCHIVE_MIRRORS
  if (-not $ortMirrors) { $ortMirrors = [Environment]::GetEnvironmentVariable('WP_ORT_ARCHIVE_MIRRORS', 'User') }
  if ($ortMirrors) {
    $ortUrls += $ortMirrors.Split(';') | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('/') + "/$ortName" }
  }
  $ortFetched = $false
  foreach ($ortUrl in $ortUrls) {
    try { Invoke-DownloadWithRetry -Uri $ortUrl -OutFile "$ortFile.partial"; $ortFetched = $true; break }
    catch { Write-Host "onnxruntime source $ortUrl failed: $($_.Exception.Message)" }
  }
  if (-not $ortFetched) { throw "onnxruntime $ortName could not be fetched from any source" }
  $got = (Get-FileHash "$ortFile.partial" -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $ortWant) { Remove-Item "$ortFile.partial" -Force; throw "onnxruntime $ortName has SHA-256 $got, pinned $ortWant. Refusing to use it." }
  Move-Item "$ortFile.partial" $ortFile -Force
}

# Always extract the verified archive, so stale extracted files cannot override it.
$ortExtract = Join-Path $build 'microsoft-ort'
Expand-Archive -LiteralPath $ortFile -DestinationPath $ortExtract -Force
$ortRoot = Join-Path $ortExtract "onnxruntime-win-x64-$ortVersion"
foreach ($file in 'include\onnxruntime_cxx_api.h', 'lib\onnxruntime.lib', 'lib\onnxruntime.dll',
    'lib\onnxruntime.pdb', 'lib\onnxruntime_providers_shared.pdb') {
  if (-not (Test-Path (Join-Path $ortRoot $file))) { throw "Microsoft ORT archive lacks $file" }
}

} else {
  & (Join-Path $PSScriptRoot 'build-onnxruntime-directml.ps1') -RepoRoot $RepoRoot -Jobs $Jobs
  $ortRoot = Join-Path $RepoRoot '.build\onnxruntime\windows-directml'
  $env:SHERPA_DIRECTML_DIR = Join-Path $ortRoot 'directml'
}
$env:SHERPA_ONNXRUNTIME_INCLUDE_DIR = Join-Path $ortRoot 'include'
$env:SHERPA_ONNXRUNTIME_LIB_DIR = Join-Path $ortRoot 'lib'

# 2. Configure: shared C API only, TTS and everything else off.
$cmakeArgs = @(
  '-S', $src, '-B', $build, '-A', 'x64',
  '-DCMAKE_BUILD_TYPE=Release',
  '-DBUILD_SHARED_LIBS=ON',
  '-DSHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=ON',
  "-DSHERPA_ONNX_ENABLE_DIRECTML=$(if ($CpuOnly) { 'OFF' } else { 'ON' })",
  # sherpa 2.0.1 omits IMPORTED_IMPLIB in the Windows CPU preinstalled path.
  # Remove this workaround when upstream sets location_onnxruntime_lib2 there.
  "-Dlocation_onnxruntime_lib2=$ortRoot/lib/onnxruntime.lib",
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
  # Preserve C++ unwinding so ORT errors reach the C API catch/CPU retry.
  '-DCMAKE_CXX_FLAGS=/Z7 /EHsc',
  '-DCMAKE_SHARED_LINKER_FLAGS=/DEBUG /OPT:REF /OPT:ICF'
)
Write-Host "==> configure windows x64 ($SherpaTag, TTS=OFF)"
cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed' }

# 3. Build only the C API target.
Write-Host '==> build sherpa-onnx-c-api'
cmake --build $build --config Release --target sherpa-onnx-c-api --parallel $Jobs
if ($LASTEXITCODE -ne 0) { throw 'cmake build failed' }

# 4. Stage the DLLs (sherpa writes them under build\bin\Release or build\lib\Release).
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
$wanted = @('sherpa-onnx-c-api.dll', 'onnxruntime.dll')
if (-not $CpuOnly) { $wanted += 'DirectML.dll' }
foreach ($name in $wanted) {
  if ($name -in @('onnxruntime.dll', 'DirectML.dll')) {
    Copy-Item (Join-Path $ortRoot "lib\$name") $stage -Force
    continue
  }
  $found = Get-ChildItem $build -Recurse -File -Filter $name |
    Where-Object { $_.FullName -match '\\Release\\' } | Select-Object -First 1
  if (-not $found) { throw "$name not found under $build (Release)" }
  Copy-Item $found.FullName $stage -Force
}
# Keep matching ORT/DirectML symbols separate: only the local release uploads them, never
# release.yml's existing windows-pdb upload. Neither directory enters the app.
$ortPdbDir = Join-Path $RepoRoot $(if ($CpuOnly) { '.build\sherpa-onnx\windows-cpu-ort-pdb' } else { '.build\sherpa-onnx\windows-ort-pdb' })
if (Test-Path $ortPdbDir) { Remove-Item $ortPdbDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ortPdbDir | Out-Null
foreach ($name in 'onnxruntime.pdb', 'onnxruntime_providers_shared.pdb') {
  if (Test-Path (Join-Path $ortRoot "lib\$name")) {
    Copy-Item (Join-Path $ortRoot "lib\$name") $ortPdbDir -Force
  }
}
if (-not $CpuOnly) {
  Copy-Item (Join-Path $ortRoot 'directml\bin\x64-win\DirectML.pdb') $ortPdbDir -Force
}
# PDB of the C API DLL for Sentry and the .msixupload.
if (Test-Path $pdbDir) { Remove-Item $pdbDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pdbDir | Out-Null
$pdb = Get-ChildItem $build -Recurse -File -Filter 'sherpa-onnx-c-api.pdb' |
  Where-Object { $_.FullName -match '\\Release\\' } | Select-Object -First 1
if (-not $pdb) { throw 'sherpa-onnx-c-api.pdb not found (Release) -- /Z7 + /DEBUG lost from the sherpa build?' }
Copy-Item $pdb.FullName $pdbDir -Force
$info = @(
  "sherpa-onnx $SherpaTag ($SherpaCommit)",
  'platform: windows-x64',
  "providers: $(if ($CpuOnly) { 'cpu' } else { 'cpu directml' })",
  "provider-patch: $((Get-FileHash $patch -Algorithm SHA256).Hash.ToLower())",
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
# git.exe sits in Git\cmd or Git\bin from PowerShell, but in Git\ucrt64\bin
# (or mingw64\bin) when the script is started from Git Bash; bash.exe is in
# Git\bin in every case.
$gitDir = Split-Path (Get-Command git).Source
$gitBash = @('..\bin\bash.exe', '..\..\bin\bash.exe') |
  ForEach-Object { Join-Path $gitDir $_ } |
  Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $gitBash) { throw "Git for Windows bash not found next to $gitDir (looked for ..\bin\bash.exe and ..\..\bin\bash.exe)" }
& $gitBash (Join-Path $RepoRoot 'scripts/check-no-espeak.sh') (Resolve-Path $stage).Path
if ($LASTEXITCODE -ne 0) { throw 'espeak-ng guard failed on the staged sherpa-onnx DLLs' }
Get-ChildItem $stage | Format-Table Name, Length -AutoSize | Out-String | Write-Host
