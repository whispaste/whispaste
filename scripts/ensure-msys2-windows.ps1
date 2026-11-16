# Provides MSYS2 bash + make for scripts/build-video-decoder.py when C:\msys64 is absent (the lab-win guest image has none).
# Installs a pinned MSYS2 base into -Root once (SHA-256 verified) and prints the root; callers export WP_MSYS2_ROOT.
param([string]$Root = "L:\labbuild\msys64")
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$version = "20260927"
$sha256 = "ea2f31a0b6ade63914ce441ffb022f0f6aa96982bfefa2326460a26d5fb01322"
$bash = Join-Path $Root "usr\bin\bash.exe"
$make = Join-Path $Root "usr\bin\make.exe"
if ((Test-Path "C:\msys64\usr\bin\make.exe") -and (Test-Path "C:\msys64\usr\bin\bash.exe")) { return }
if (-not ((Test-Path $bash) -and (Test-Path $make))) {
  $tmp = Join-Path ([IO.Path]::GetTempPath()) "msys2-$version"
  Remove-Item -Recurse -Force $tmp, $Root -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $archive = Join-Path $tmp "msys2-base.tar.xz"
  Invoke-WebRequest -UseBasicParsing "https://github.com/msys2/msys2-installer/releases/download/2026-09-27/msys2-base-x86_64-$version.tar.xz" -OutFile $archive
  if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $sha256.ToUpper()) { throw "MSYS2 base SHA-256 mismatch" }
  $parent = Split-Path $Root -Parent
  New-Item -ItemType Directory -Force $parent | Out-Null
  tar -xf $archive -C $parent
  if ($LASTEXITCODE) { throw "tar failed" }
  Move-Item (Join-Path $parent "msys64") $Root -ErrorAction SilentlyContinue
  # The very first login shell only runs the MSYS2 one-time setup (and may exit non-zero); its result is not checked.
  & $bash -lc "exit 0" 2>&1 | Out-Null
  # First pacman run initialises the keyring; make is the only package the FFmpeg build needs beyond the base.
  & $bash -lc "pacman-key --init && pacman-key --populate msys2 && pacman -Sy --noconfirm --needed make"
  if ($LASTEXITCODE -or -not (Test-Path $make)) { throw "pacman make failed" }
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
$Root
