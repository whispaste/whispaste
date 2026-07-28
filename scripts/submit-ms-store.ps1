<#
.SYNOPSIS
  Submits a new WhisPaste version to the Microsoft Store via the classic
  Partner Center Submission API (manage.devcenter.microsoft.com), bypassing
  the `msstore` CLI's hard "paid products not supported" guard (see
  docs/store-release.md and ~/.claude/infrastructure/microsoft-partner-center.md
  for the full research trail on why that guard exists and why this API is
  NOT subject to the same restriction for anything except Pricing).

  Revived from the version removed in commit 213c1d18 (2026-07-01, "GitHub-
  basierte MS-Store-Auto-Submission entfernt … Release-Flow läuft lokal auf
  macOS" — that reasoning no longer applies now that this runs on
  windows-latest in CI). Corrected against Microsoft's current API docs
  (learn.microsoft.com/windows/uwp/monetize/manage-app-submissions, fetched
  2026-07-28): the prior version wrote a `whatsNew` field that does not exist
  on the baseListing resource — the real field is `releaseNotes`. Extended to
  also manage `title` and `keywords` (the old version only touched
  description/features/whatsNew), so this script now covers the SAME managed
  field set as scripts/apply-store-metadata.mjs (Title, Description, Features,
  Keywords, ReleaseNotes) — just against the classic API's lowercase
  camelCase schema (title/description/features/keywords/releaseNotes) instead
  of the msstore-CLI's PascalCase one (Title/Description/Features/Keywords/
  ReleaseNotes under Listings.<locale>.BaseListing).

  Pricing is deliberately never touched here, same rationale as
  apply-store-metadata.mjs: WhisPaste's account is on Pricing V2, and every
  attempt to write Pricing.PriceId through either API failed at commit with
  "Price Tier is not supported". The price stays a one-time manual step in
  Partner Center → Pricing and availability; a submission created by this
  script simply carries forward whatever price is already live.

.PARAMETER AppId
  Store App ID. WhisPaste: 9P22JVKRQ2V0
.PARAMETER TenantId
  Azure AD tenant ID for the service principal registered in Partner Center.
.PARAMETER ClientId
  Service principal application (client) ID.
.PARAMETER ClientSecret
  Service principal client secret.
.PARAMETER MsixPath
  Local path to the .msix file to upload.
.PARAMETER StoreDir
  Path to the store/ directory containing listing content. Default: 'store'.
#>
param(
  [Parameter(Mandatory)] [string] $AppId,
  [Parameter(Mandatory)] [string] $TenantId,
  [Parameter(Mandatory)] [string] $ClientId,
  [Parameter(Mandatory)] [string] $ClientSecret,
  [Parameter(Mandatory)] [string] $MsixPath,
  [string] $StoreDir = 'store'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$BASE_URL = 'https://manage.devcenter.microsoft.com/v1.0/my'

# store/ folder name → classic Submission API locale key (lowercase, both
# parts — "en-US" → "en-us", "de-DE" → "de-de". NOT the same mapping as
# scripts/apply-store-metadata.mjs, which maps "de-DE" → "de" for the
# msstore-CLI's own, differently-cased locale keys.)
$LOCALE_MAP = @{ 'en-US' = 'en-us'; 'de-DE' = 'de-de' }

# ── Helpers ───────────────────────────────────────────────────────────────────

function Invoke-Api {
  param(
    [string]    $Uri,
    [string]    $Method  = 'GET',
    [hashtable] $Headers = @{},
    [string]    $Body    = $null
  )
  $p = @{ Uri = $Uri; Method = $Method; Headers = $Headers }
  if ($Body) { $p.Body = $Body }

  $attempt = 0
  while ($true) {
    $attempt++
    try {
      return Invoke-RestMethod @p
    } catch {
      if ($attempt -ge 3) { throw }
      $wait = 5 * $attempt
      Write-Warning "API call failed (attempt $attempt/3, retry in ${wait}s): $_"
      Start-Sleep -Seconds $wait
    }
  }
}

function Read-StoreFile {
  param([string] $Path)
  if (-not (Test-Path $Path)) { return '' }
  return (Get-Content $Path -Raw -Encoding UTF8).Trim()
}

function Read-LineList {
  param([string] $Path)
  if (-not (Test-Path $Path)) { return @() }
  return @(
    Get-Content $Path -Encoding UTF8 |
      Where-Object { $_.Trim() -ne '' } |
      ForEach-Object { $_.Trim() }
  )
}

# Appends a line to the GitHub Actions run summary when running in CI, so an
# AFK submission is auditable at a glance instead of buried in the job log.
function Write-Summary {
  param([string] $Line)
  if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $Line -Encoding UTF8
  }
}

# ── Authenticate ──────────────────────────────────────────────────────────────

Write-Host ":: Authenticating with Partner Center API..."
$tokenResp = Invoke-RestMethod `
  -Uri    "https://login.microsoftonline.com/$TenantId/oauth2/token" `
  -Method Post `
  -Body   @{
    grant_type    = 'client_credentials'
    client_id     = $ClientId
    client_secret = $ClientSecret
    resource      = 'https://manage.devcenter.microsoft.com'
  }
$authHeaders = @{
  Authorization  = "Bearer $($tokenResp.access_token)"
  'Content-Type' = 'application/json'
}
Write-Host "   Authenticated."

# ── Delete any pending submission ─────────────────────────────────────────────

Write-Host ":: Fetching app data for $AppId..."
$app = Invoke-Api -Uri "$BASE_URL/applications/$AppId" -Headers $authHeaders

if ($app.pendingApplicationSubmission) {
  $pendingId = $app.pendingApplicationSubmission.id
  Write-Host "   Deleting pending submission $pendingId..."
  Invoke-Api -Uri "$BASE_URL/applications/$AppId/submissions/$pendingId" `
    -Method Delete -Headers $authHeaders | Out-Null
}

# ── Create new submission (cloned from last published) ────────────────────────

Write-Host ":: Creating new submission..."
$sub       = Invoke-Api -Uri "$BASE_URL/applications/$AppId/submissions" `
  -Method Post -Headers $authHeaders
$subId     = $sub.id
$uploadUrl = $sub.fileUploadUrl
Write-Host "   Submission ID: $subId"

# ── Load managed listing content from store/ (Title/Description/Features/ ────
# ── Keywords/ReleaseNotes — same field set as apply-store-metadata.mjs) ───────

Write-Host ":: Loading store listing content..."
$defaults = Get-Content (Join-Path $StoreDir 'defaults.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$title    = $defaults.default.Title
if (-not $title) { throw "$StoreDir/defaults.json is missing default.Title." }

$managed = @{}
foreach ($folder in $LOCALE_MAP.Keys) {
  $locale = $LOCALE_MAP[$folder]
  $dir    = Join-Path $StoreDir $folder
  $managed[$locale] = @{
    title        = $title
    description  = Read-StoreFile (Join-Path $dir 'description.txt')
    features     = Read-LineList  (Join-Path $dir 'features.txt')
    keywords     = Read-LineList  (Join-Path $dir 'search-terms.txt')
    releaseNotes = Read-StoreFile (Join-Path $dir 'release-notes.txt')
  }
  Write-Host "   $locale`: $($managed[$locale].description.Length) chars description, $($managed[$locale].features.Count) features, $($managed[$locale].keywords.Count) keywords"
}

# ── Update listings ───────────────────────────────────────────────────────────

Write-Host ":: Updating listings..."

# Normalize locale keys to lowercase for consistent access (cloned submission
# may carry differently-cased keys depending on how Partner Center last saved it).
$normalizedListings = [PSCustomObject]@{}
foreach ($prop in $sub.listings.PSObject.Properties) {
  $normalizedListings | Add-Member -NotePropertyName $prop.Name.ToLower() `
    -NotePropertyValue $prop.Value -Force
}
$sub.listings = $normalizedListings

foreach ($locale in $LOCALE_MAP.Values) {
  if ($null -eq $sub.listings.$locale) {
    Write-Warning "   Locale '$locale' not in cloned submission — creating entry."
    $sub.listings | Add-Member -NotePropertyName $locale `
      -NotePropertyValue ([PSCustomObject]@{ baseListing = [PSCustomObject]@{} }) -Force
  }

  $m = $managed[$locale]
  $bl = $sub.listings.$locale.baseListing
  if ($m.title)                { $bl | Add-Member -NotePropertyName 'title'        -NotePropertyValue $m.title        -Force }
  if ($m.description)          { $bl | Add-Member -NotePropertyName 'description'  -NotePropertyValue $m.description  -Force }
  if ($m.features.Count -gt 0) { $bl | Add-Member -NotePropertyName 'features'     -NotePropertyValue $m.features     -Force }
  if ($m.keywords.Count -gt 0) { $bl | Add-Member -NotePropertyName 'keywords'     -NotePropertyValue $m.keywords     -Force }
  if ($m.releaseNotes)         { $bl | Add-Member -NotePropertyName 'releaseNotes' -NotePropertyValue $m.releaseNotes -Force }
  # Pricing is NOT part of baseListing (it's a top-level submission field) and
  # is never touched anywhere in this script — see the header comment.
}

# ── Replace application packages ──────────────────────────────────────────────

$msixName = Split-Path $MsixPath -Leaf
Write-Host ":: Registering package: $msixName"
$sub.applicationPackages = @(
  [PSCustomObject]@{
    fileName              = $msixName
    fileStatus            = 'PendingUpload'
    minimumDirectXVersion = 'None'
    minimumSystemRam      = 'None'
  }
)

# ── PUT updated submission ────────────────────────────────────────────────────

Write-Host ":: Pushing submission data..."
$putBody = $sub | ConvertTo-Json -Depth 20 -Compress
Invoke-Api -Uri "$BASE_URL/applications/$AppId/submissions/$subId" `
  -Method Put -Headers $authHeaders -Body $putBody | Out-Null
Write-Host "   Done."

# ── Build upload ZIP and push to Azure Storage ────────────────────────────────

Write-Host ":: Packaging MSIX for upload..."
$zipPath = Join-Path ([System.IO.Path]::GetTempPath()) "ms-store-$subId.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $MsixPath -DestinationPath $zipPath -Force
$zipMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host "   ZIP: $zipMB MB"

Write-Host ":: Uploading package to Azure Storage..."
Invoke-WebRequest -Uri $uploadUrl -Method Put -InFile $zipPath `
  -ContentType 'application/octet-stream' `
  -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } | Out-Null
Write-Host "   Uploaded."

# ── Commit ────────────────────────────────────────────────────────────────────

Write-Host ":: Committing submission..."
Invoke-Api -Uri "$BASE_URL/applications/$AppId/submissions/$subId/commit" `
  -Method Post -Headers $authHeaders | Out-Null

# ── Poll for commit acceptance ────────────────────────────────────────────────
# "CommitStarted / PreProcessing / Certification / Release" = accepted by Partner Center.
# We only wait long enough to confirm the commit was accepted, not for full certification.

Write-Host ":: Polling for commit status (up to 10 min)..."
$deadline = (Get-Date).AddMinutes(10)
$accepted = @('CommitStarted', 'PreProcessing', 'Certification', 'Release', 'PendingRelease')
$failed   = @('PreProcessingFailed', 'CertificationFailed', 'PublishFailed', 'CommitFailed')

while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 20
  $status = Invoke-Api `
    -Uri "$BASE_URL/applications/$AppId/submissions/$subId" `
    -Headers $authHeaders
  $cs = $status.status
  Write-Host "   Status: $cs"

  if ($cs -in $failed) {
    $errors = ($status.statusDetails.errors |
      ForEach-Object { "  • $($_.code): $($_.details)" }) -join "`n"
    Write-Summary "### Microsoft Store submission: ❌ FAILED ($cs)"
    Write-Summary ""
    Write-Summary "Submission ``$subId`` was rejected by Partner Center:"
    Write-Summary "$errors"
    throw "Submission $subId failed ($cs):`n$errors"
  }

  if ($cs -in $accepted) {
    Write-Host ""
    Write-Host "Submission accepted by Partner Center."
    Write-Host "Review: https://partner.microsoft.com/en-us/dashboard/apps/$AppId/submissions/$subId"
    Write-Summary "### Microsoft Store submission: ✅ accepted ($cs)"
    Write-Summary ""
    Write-Summary "Submission ``$subId`` accepted — now in certification. Price was carried forward unchanged (Pricing V2 — verify under Pricing and availability before this reaches Release). [Review in Partner Center](https://partner.microsoft.com/en-us/dashboard/apps/$AppId/submissions/$subId)"
    exit 0
  }
}

Write-Warning "Timed out waiting for commit acceptance — submission may still be processing."
Write-Host "Check: https://partner.microsoft.com/en-us/dashboard/apps/$AppId/submissions/$subId"
Write-Summary "### Microsoft Store submission: ⏳ timed out waiting for acceptance"
Write-Summary ""
Write-Summary "The commit was sent but Partner Center had not confirmed acceptance within 10 min — it may still be processing. [Check the submission](https://partner.microsoft.com/en-us/dashboard/apps/$AppId/submissions/$subId)"
