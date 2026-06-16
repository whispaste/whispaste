<#
.SYNOPSIS
  Submits a new WhisPaste version to the Microsoft Store via the Partner Center
  Submission API. Reads store listing content from the store/ directory in the
  repo root and injects bilingual release notes as the "What's new" field.

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
.PARAMETER WhatsNewEn
  "What's new" text in English. Trimmed to 1500 chars (store limit).
.PARAMETER WhatsNewDe
  "What's new" text in German. Trimmed to 1500 chars (store limit).
.PARAMETER StoreDir
  Path to the store/ directory containing listing content. Default: 'store'.
#>
param(
  [Parameter(Mandatory)] [string] $AppId,
  [Parameter(Mandatory)] [string] $TenantId,
  [Parameter(Mandatory)] [string] $ClientId,
  [Parameter(Mandatory)] [string] $ClientSecret,
  [Parameter(Mandatory)] [string] $MsixPath,
  [string] $WhatsNewEn = '',
  [string] $WhatsNewDe = '',
  [string] $StoreDir   = 'store'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$BASE_URL = 'https://manage.devcenter.microsoft.com/v1.0/my'

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

function Cap-Text {
  param([string] $Text, [int] $Max = 1500)
  if (-not $Text -or $Text.Length -le $Max) { return $Text }
  $cut     = $Text.Substring(0, $Max)
  $lastNl  = $cut.LastIndexOf("`n")
  if ($lastNl -gt 800) { return $cut.Substring(0, $lastNl).TrimEnd() }
  return ($cut.Substring(0, $Max - 3) + '...').TrimEnd()
}

function Read-StoreFile {
  param([string] $Path)
  if (-not (Test-Path $Path)) { return '' }
  return (Get-Content $Path -Raw -Encoding UTF8).Trim()
}

function Read-FeaturesList {
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

# ── Load listing content ──────────────────────────────────────────────────────

Write-Host ":: Loading store listing content..."
$enDesc     = Read-StoreFile "$StoreDir/en-US/description.txt"
$deDesc     = Read-StoreFile "$StoreDir/de-DE/description.txt"
$enFeatures = Read-FeaturesList "$StoreDir/en-US/features.txt"
$deFeatures = Read-FeaturesList "$StoreDir/de-DE/features.txt"
$wnEn       = Cap-Text $WhatsNewEn
$wnDe       = Cap-Text $WhatsNewDe

Write-Host "   EN: $($enDesc.Length) chars, $($enFeatures.Count) features"
Write-Host "   DE: $($deDesc.Length) chars, $($deFeatures.Count) features"
if ($wnEn) { Write-Host "   What's new EN: $($wnEn.Length) chars" }
if ($wnDe) { Write-Host "   What's new DE: $($wnDe.Length) chars" }

# ── Update listings ───────────────────────────────────────────────────────────

Write-Host ":: Updating listings..."

# Normalize locale keys to lowercase for consistent access
$normalizedListings = [PSCustomObject]@{}
foreach ($prop in $sub.listings.PSObject.Properties) {
  $normalizedListings | Add-Member -NotePropertyName $prop.Name.ToLower() `
    -NotePropertyValue $prop.Value -Force
}
$sub.listings = $normalizedListings

# Ensure both locales exist
foreach ($locale in @('en-us', 'de-de')) {
  if ($null -eq $sub.listings.$locale) {
    Write-Warning "   Locale '$locale' not in cloned submission — creating entry."
    $sub.listings | Add-Member -NotePropertyName $locale `
      -NotePropertyValue ([PSCustomObject]@{ baseListing = [PSCustomObject]@{} }) -Force
  }
}

if ($enDesc)              { $sub.listings.'en-us'.baseListing.description = $enDesc }
if ($enFeatures.Count -gt 0) { $sub.listings.'en-us'.baseListing.features  = $enFeatures }
if ($wnEn)                { $sub.listings.'en-us'.baseListing.whatsNew    = $wnEn }

if ($deDesc)              { $sub.listings.'de-de'.baseListing.description = $deDesc }
if ($deFeatures.Count -gt 0) { $sub.listings.'de-de'.baseListing.features  = $deFeatures }
if ($wnDe)                { $sub.listings.'de-de'.baseListing.whatsNew    = $wnDe }

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
    Write-Summary "Submission ``$subId`` accepted — now in certification. [Review in Partner Center](https://partner.microsoft.com/en-us/dashboard/apps/$AppId/submissions/$subId)"
    exit 0
  }
}

Write-Warning "Timed out waiting for commit acceptance — submission may still be processing."
Write-Host "Check: https://partner.microsoft.com/en-us/dashboard/apps/$AppId/submissions/$subId"
Write-Summary "### Microsoft Store submission: ⏳ timed out waiting for acceptance"
Write-Summary ""
Write-Summary "The commit was sent but Partner Center had not confirmed acceptance within 10 min — it may still be processing. [Check the submission](https://partner.microsoft.com/en-us/dashboard/apps/$AppId/submissions/$subId)"
