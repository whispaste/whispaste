[CmdletBinding()]
param(
  [switch]$SkipGoldens,
  [switch]$SkipInstall,
  [switch]$SkipPremium
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..\..')
$appstoreDir = Join-Path $repoRoot 'tools\appstore-screens'
$ogDir = Join-Path $repoRoot 'tools\og-image'
$rawScreensDir = Join-Path $repoRoot 'screenshots\raw'
$storeGoldensDir = Join-Path $repoRoot 'test\screenshots\goldens\windowsStoreScreenshots'

function Invoke-Step {
  param(
    [string]$Label,
    [scriptblock]$Action
  )

  Write-Host ''
  Write-Host "==> $Label" -ForegroundColor Cyan
  & $Action
}

Push-Location $repoRoot
try {
  if (-not $SkipGoldens) {
    Invoke-Step 'Refreshing golden screenshots' {
      if (Test-Path $storeGoldensDir) {
        Get-ChildItem -Path $storeGoldensDir -Filter '*.png' -ErrorAction SilentlyContinue | Remove-Item -Force
      }
      flutter test --update-goldens test/screenshots/
    }

    Invoke-Step 'Collecting raw store screenshots' {
      py -3 scripts\store-screenshots.py --no-regen
    }
  }

  if (-not $SkipInstall) {
    Invoke-Step 'Installing screenshot tool dependencies' {
      Push-Location $appstoreDir
      try {
        npm install
        npx playwright install chromium
      }
      finally {
        Pop-Location
      }
    }
  }

  Invoke-Step 'Generating store screenshots' {
    Push-Location $appstoreDir
    try {
      node generate.cjs --lang=all
    }
    finally {
      Pop-Location
    }
  }

  Invoke-Step 'Generating OG images' {
    Push-Location $ogDir
    try {
      node generate.cjs --lang=all
    }
    finally {
      Pop-Location
    }
  }

  if (-not $SkipPremium -and (Test-Path $rawScreensDir) -and (Get-ChildItem -Path $rawScreensDir -Filter 'screenshot-*.png' -ErrorAction SilentlyContinue)) {
    Invoke-Step 'Generating framed premium screenshots from live captures' {
      py -3 scripts\premium-screenshots.py
    }
  }

  Write-Host ''
  Write-Host 'All screenshot assets are up to date.' -ForegroundColor Green
}
finally {
  Pop-Location
}
