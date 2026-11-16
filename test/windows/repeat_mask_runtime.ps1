# Opt-in desktop test, never a CI test: sends Ctrl+Alt+F24 using SendInput.
# Compile unchanged production method bodies against real Win32 APIs; Flutter
# transport and RawInput delivery are deliberately outside this harness.
param([string]$OutputDirectory = "$env:TEMP/whispaste-repeat-mask")
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$source = Get-Content "$root/windows/runner/keyboard_monitor_host.cpp" -Raw
$methods = @('UpdateRepeatMaskHook', 'UninstallRepeatMaskHook',
    'RepeatMaskHookProc', 'HeldModifierMask', 'SwallowsRepeat',
    'EndRepeatSession', 'RepeatGapLimitMs', 'ArmRelease')
$bodies = foreach ($name in $methods) {
    $pattern = '(?ms)^(?:void|bool|uint8_t|DWORD|LRESULT CALLBACK) KeyboardMonitorHost::' + $name + '\(.*?^}'
    $match = [regex]::Match($source, $pattern)
    if (!$match.Success) { throw "Production method not found: $name" }
    $match.Value
}
$modifier = [regex]::Match($source, '(?ms)^bool IsModifierVk\(.*?^}')
if (!$modifier.Success) { throw 'Production modifier classifier not found' }
$template = Get-Content "$PSScriptRoot/repeat_mask_runtime.cpp.in" -Raw
$generated = $template.Replace('// PRODUCTION_METHODS', ($modifier.Value + "`n" + ($bodies -join "`n")))
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$generated | Set-Content "$OutputDirectory/runtime.cpp" -Encoding utf8
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'MSVC x64 build tools are required' }
$vcvars = "$vs/VC/Auxiliary/Build/vcvars64.bat"
# A temporary batch file avoids interpolation through multiple shells.
@"
@echo off
call "$vcvars" >nul
cl /nologo /std:c++17 /EHsc /W4 /WX /I "$root/windows/runner" "$OutputDirectory/runtime.cpp" /Fo"$OutputDirectory/runtime.obj" /Fe"$OutputDirectory/runtime.exe" user32.lib
"@ | Set-Content "$OutputDirectory/build.cmd" -Encoding ascii
& "$OutputDirectory/build.cmd" *> "$OutputDirectory/build.log"
if ($LASTEXITCODE -ne 0) {
    Get-Content "$OutputDirectory/build.log"
    throw 'Runtime harness compilation failed'
}
Write-Output "Built $OutputDirectory/runtime.exe. Run from an interactive desktop after announcing keyboard automation."
