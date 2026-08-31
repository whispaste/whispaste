# build-smartmode-shim-windows.ps1 — compiles native/smart_mode/smart_mode_shim.cpp
# (see smart_mode_shim.h for the public surface) into a `smartmode_shim.dll`,
# linked against the already-staged `llama`/`ggml` DLLs produced by
# build-libllama-windows.ps1 (run that first).
#
# Windows equivalent of build-smartmode-shim-macos.sh. Same shim source, no
# macOS-specific code in it (see smart_mode_shim.cpp: only <cstdio>/<cstring>/
# <string>/<vector> + llama.h/chat.h/smart_mode_shim.h — no #ifdef __APPLE__,
# no ObjC interop), so nothing here rewrites or forks the shim itself; only
# the compiler invocation and the produced artifact (.dll instead of .dylib)
# differ.
#
# Usage:  scripts\build-libllama-windows.ps1 ; scripts\build-smartmode-shim-windows.ps1
# Output: .build\libllama\windows\smartmode_shim.dll (added to the same stage
# dir + SHA256SUMS that build-libllama-windows.ps1 produced;
# bundle-libllama-windows.ps1 stages the whole directory next to
# whispaste.exe under smart_mode\).
#
# Requires: a Developer PowerShell / Developer Command Prompt for VS 2022 (so
# `cl.exe`/`link.exe` are on PATH) — run this from that shell, or via
# `vcvarsall.bat x64` first.
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$LlamaTag = "b10150"
$LlamaSrc = Join-Path $RepoRoot ".build\deps\llama.cpp\$LlamaTag"
$StageDir = Join-Path $RepoRoot ".build\libllama\windows"
$ShimSrc = Join-Path $RepoRoot "native\smart_mode\smart_mode_shim.cpp"

Write-Host "=== build-smartmode-shim-windows ==="

if (-not (Test-Path (Join-Path $StageDir "llama.dll"))) {
  Write-Error "$StageDir\llama.dll not found - run scripts\build-libllama-windows.ps1 first."
  exit 1
}

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
  Write-Error "cl.exe not found on PATH - run this from a 'Developer PowerShell for VS 2022' (or call vcvarsall.bat x64 first)."
  exit 1
}

# The import library (.lib) for llama.dll, produced alongside it by the same
# cmake build (MSVC always emits one for a DLL target) — needed at link time,
# unlike macOS/Linux where the shared object itself carries the symbols.
$llamaImportLib = Get-ChildItem -Path (Join-Path $RepoRoot ".build\libllama\windows-build") -Recurse -Filter "llama.lib" |
  Select-Object -First 1
if (-not $llamaImportLib) {
  Write-Error "llama.lib (import library) not found under .build\libllama\windows-build - re-run build-libllama-windows.ps1."
  exit 1
}

Write-Host "[1/2] compiling smart_mode_shim.cpp"
cl.exe /std:c++17 /O2 /EHsc /LD `
  /I "$LlamaSrc\include" /I "$LlamaSrc\ggml\include" /I "$LlamaSrc\common" /I "$LlamaSrc\vendor" `
  "$ShimSrc" `
  "$($llamaImportLib.FullName)" `
  /Fe:"$StageDir\smartmode_shim.dll" `
  /link /MACHINE:X64

if ($LASTEXITCODE -ne 0) { throw "cl.exe failed with exit code $LASTEXITCODE" }

# cl.exe /LD drops build byproducts (.obj/.exp/.lib for the shim itself) next
# to the source file by default when no /Fo is given — clean those up so
# repeated runs stay idempotent and the stage dir only holds DLLs.
Remove-Item (Join-Path $RepoRoot "native\smart_mode\smart_mode_shim.obj") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $StageDir "smartmode_shim.exp") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $StageDir "smartmode_shim.lib") -ErrorAction SilentlyContinue

Write-Host "[2/2] refreshing SHA256SUMS"
Push-Location $StageDir
try {
  Get-ChildItem -Filter *.dll | ForEach-Object {
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower())  $($_.Name)"
  } | Set-Content SHA256SUMS
  Get-Content SHA256SUMS
} finally {
  Pop-Location
}

Write-Host "=== done. smartmode_shim.dll staged at $StageDir ==="
