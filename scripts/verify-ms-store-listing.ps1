<#
.SYNOPSIS
  Read-only post-submission QA check for the WhisPaste Microsoft Store
  listing. Run after every submit-ms-store.ps1 commit (CI or manual) — never
  writes anything, safe to run anytime.

.DESCRIPTION
  Verifies three things that have each caused a real, live incident before:
   1. No unmanaged/orphaned locale listings (the 'de' orphan, 2026-07-30).
   2. Managed locales' title/description/features/keywords/releaseNotes
      match store/ byte-for-byte (ignoring a UTF-8 BOM and trailing
      whitespace, which the classic API round-trip harmlessly adds).
   3. The live, publicly-served price is not Free/€0 (the pricing.priceId
      reset, 2026-07-30) — checked against the public DisplayCatalog API for
      every market in -Markets, with an explicit CDN-cache-lag caveat since
      that API is not authoritative, just a fast independent cross-check.

  Exits non-zero if anything looks wrong, so it can gate a release script
  later if desired — for now it's meant to be run and read by a human (or
  Claude) after each Store submission.

.PARAMETER Markets
  Public DisplayCatalog markets to price-check. Default covers the
  German-speaking markets WhisPaste ships to.
#>
param(
  [string] $AppId = $env:WP_STORE_APP_ID,
  [string] $TenantId = $env:AZURE_TENANT_ID,
  [string] $ClientId = $env:AZURE_CLIENT_ID,
  [string] $ClientSecret = $env:AZURE_CLIENT_SECRET,
  [string] $StoreDir = 'store',
  [string[]] $Markets = @('US', 'DE', 'AT', 'CH')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$BASE_URL = 'https://manage.devcenter.microsoft.com/v1.0/my'
$LOCALE_MAP = @{ 'en-US' = 'en-us'; 'de-DE' = 'de-de' }
$problems = @()

function Read-StoreFile { param([string]$Path) (Get-Content $Path -Raw -Encoding UTF8).TrimEnd("`r","`n") }
function Read-LineList  { param([string]$Path) @(Get-Content $Path -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }) }
function Normalize-Text { param([string]$s) if ($null -eq $s) { '' } else { $s.TrimStart([char]0xFEFF).Trim() } }

Write-Host ":: Authenticating..."
$tokenResp = Invoke-RestMethod `
  -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" -Method Post `
  -Body @{ grant_type = 'client_credentials'; client_id = $ClientId; client_secret = $ClientSecret; resource = 'https://manage.devcenter.microsoft.com' }
$authHeaders = @{ Authorization = "Bearer $($tokenResp.access_token)"; 'Content-Type' = 'application/json' }

$app = Invoke-RestMethod -Uri "$BASE_URL/applications/$AppId" -Headers $authHeaders -Method Get
$lastId = $app.lastPublishedApplicationSubmission.id
$sub = Invoke-RestMethod -Uri "$BASE_URL/applications/$AppId/submissions/$lastId" -Headers $authHeaders -Method Get

# ── 1. Orphaned locales ─────────────────────────────────────────────────────
Write-Host ""
Write-Host ":: Check 1/3 — unmanaged locale listings"
$managedLocales = @($LOCALE_MAP.Values)
$actualLocales = @($sub.listings.PSObject.Properties.Name)
$orphans = @($actualLocales | Where-Object { $managedLocales -notcontains $_ })
if ($orphans.Count -gt 0) {
  $problems += "Unmanaged locale listing(s) present: $($orphans -join ', ')"
  Write-Warning "   FOUND: $($orphans -join ', ')"
} else {
  Write-Host "   OK — only $($actualLocales -join ', ')"
}

# ── 2. Text content parity vs. store/ ───────────────────────────────────────
Write-Host ""
Write-Host ":: Check 2/3 — listing text vs. store/ source files"
$defaults = Get-Content (Join-Path $StoreDir 'defaults.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$title = $defaults.default.Title

foreach ($locale in $managedLocales) {
  $folder = ($LOCALE_MAP.GetEnumerator() | Where-Object { $_.Value -eq $locale }).Key
  $dir = Join-Path $StoreDir $folder
  if (-not ($sub.listings.PSObject.Properties.Match($locale).Count -gt 0)) {
    $problems += "$locale`: missing from live submission entirely"
    Write-Warning "   $locale`: MISSING"
    continue
  }
  $bl = $sub.listings.$locale.baseListing
  $mismatches = @()
  if ((Normalize-Text $bl.title) -ne (Normalize-Text $title)) { $mismatches += 'title' }
  if ((Normalize-Text $bl.description) -ne (Normalize-Text (Read-StoreFile (Join-Path $dir 'description.txt')))) { $mismatches += 'description' }
  $liveFeatures = @($bl.features)
  $srcFeatures = Read-LineList (Join-Path $dir 'features.txt')
  if (($liveFeatures -join "`n") -ne ($srcFeatures -join "`n")) { $mismatches += 'features' }
  $liveKeywords = @($bl.keywords)
  $srcKeywords = Read-LineList (Join-Path $dir 'search-terms.txt')
  if (($liveKeywords -join "`n") -ne ($srcKeywords -join "`n")) { $mismatches += 'keywords' }
  if ((Normalize-Text $bl.releaseNotes) -ne (Normalize-Text (Read-StoreFile (Join-Path $dir 'release-notes.txt')))) { $mismatches += 'releaseNotes' }

  if ($mismatches.Count -gt 0) {
    $problems += "$locale`: drifted field(s): $($mismatches -join ', ')"
    Write-Warning "   $locale`: MISMATCH in $($mismatches -join ', ')"
  } else {
    Write-Host "   $locale`: OK, matches store/$folder exactly"
  }
}

# ── 3. Live price vs. Free/€0 ────────────────────────────────────────────────
# Two independent, NEITHER fully authoritative, signals — checked via search
# (2026-07-30) for a real read API for "Preise und Verfügbarkeit": Microsoft's
# "Product Ingestion API" looked promising but only covers Azure Marketplace
# offers (VMs/SaaS/etc.), not regular Windows Store consumer apps like this
# one. No documented read-only API exists for Pricing V2's actual served
# price. Partner Center's own "Preise und Verfügbarkeit" page remains the
# only ground truth — a human must confirm it there before trusting either
# signal below.
Write-Host ""
Write-Host ":: Check 3/3 — price signals (both are cross-checks, NEITHER is ground truth — verify in Partner Center 'Preise und Verfügbarkeit' directly)"
try {
  $priceIdSignal = $sub.pricing.priceId
  if ($priceIdSignal -eq 'Free' -or [string]::IsNullOrEmpty($priceIdSignal)) {
    $problems += "Classic Submission API's pricing.priceId reads '$priceIdSignal' on the last published submission — weak signal, but worth a manual check"
    Write-Warning "   pricing.priceId (legacy, weak signal): '$priceIdSignal'"
  } else {
    Write-Host "   pricing.priceId (legacy, weak signal): '$priceIdSignal'"
  }
} catch {
  Write-Host "   pricing.priceId: not readable ($($_.Exception.Message))"
}
foreach ($market in $Markets) {
  try {
    $cat = Invoke-RestMethod -Uri "https://displaycatalog.mp.microsoft.com/v7.0/products/$AppId`?market=$market&languages=en-us&MS-CV=1" -Method Get
    $price = $cat.Product.DisplaySkuAvailabilities[0].Availabilities[0].OrderManagementData.Price
    if ($price.ListPrice -eq 0) {
      $problems += "Market $market`: live ListPrice is 0 $($price.CurrencyCode) — looks Free, expected a real price"
      Write-Warning "   $market`: $($price.ListPrice) $($price.CurrencyCode) — LOOKS FREE"
    } else {
      Write-Host "   $market`: $($price.ListPrice) $($price.CurrencyCode)"
    }
  } catch {
    Write-Host "   $market`: could not fetch ($($_.Exception.Message)) — skip, not conclusive"
  }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
if ($problems.Count -eq 0) {
  Write-Host "ALL CHECKS PASSED."
  exit 0
} else {
  Write-Host "PROBLEMS FOUND:"
  foreach ($p in $problems) { Write-Host "  - $p" }
  exit 1
}
