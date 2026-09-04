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

  RESOLVED 2026-09-04 (Microsoft support ticket API TrackingID#2608200050000071
  — see docs/store-release.md and ~/.claude/infrastructure/microsoft-
  partner-center.md §12 for the full trail): pricing.priceId is NOT
  unwritable for this account, and it must NEVER be passed through
  untouched or omitted. Microsoft's own Engineering Team confirmed the root
  cause of every "Base is not a valid PriceId" / "Pricing data was not
  provided" failure since 2026-08-20 (see history below): the GET response
  returns "Base" as an internal read-only sentinel for accounts on the
  newer schedule-based pricing model — it is NEVER a legal PUT value.
  Because isAdvancedPricingModel is true for this account, PUT requires an
  explicit "Free" or "Tier1001"+ value (legacy Tier2-Tier96 are rejected
  for this pricing model); the field must be present with a valid value on
  EVERY PUT, since the classic API does a full replacement and a missing
  field silently defaults to Free. This script now reads that value from
  store/defaults.json ("default.PriceId") and writes it explicitly on every
  submission — see "Set pricing.priceId" below for the mechanism and the
  hard-fail guard that prevents a repeat of this incident.

  ── History (kept for the git-blame trail; the mechanism below supersedes
  all of it — do not act on any belief stated in this history) ──
  CORRECTION (2026-07-30): an earlier version of this script believed a
  committed submission "simply carries forward whatever price is already
  live" as long as `priceId` was set to null. That is false and caused a
  real live price reset to Free — see the comment above the (now removed)
  pricing block near "Update listings" for the full finding.
  CORRECTION AGAIN (2026-08-20): passing `pricing` through untouched from
  the clone was then ALSO rejected by the API on the submission PUT itself
  ("'Base' is not a valid PriceId for base price."), even though the
  script at the time never read or wrote it — confirmed the rejected value
  was the account's own live, currently-serving price, not something
  corrupted by this script. Omitting `pricing` entirely was rejected too
  ("Pricing data was not provided"). At the time this looked like a
  Microsoft-side tightening with no known safe payload — Microsoft's own
  support ticket above proved that belief wrong: there was a third option
  (a concrete Tier10xx value) that nobody had tried yet.

  IMAGES (added 2026-07-29): despite docs/store-release.md's older claim that
  listing images aren't API-controllable, Microsoft's docs
  (learn.microsoft.com/windows/uwp/monetize/create-and-manage-submissions-
  using-windows-store-services, confirmed against
  create-and-manage-submissions-for-flights) describe image upload through
  the SAME mechanism as the package: image files go into the SAME ZIP
  uploaded to the submission's `fileUploadUrl`, and each locale's
  `baseListing.images[]` entry references its file by a path RELATIVE TO THE
  ZIP ROOT (`fileName`), plus a `description` and an `imageType` (we use
  `"Screenshot"` for every image — Microsoft doesn't have a dedicated "hero"
  type; the numbered 01_hero.png simply becomes the first screenshot in
  display order, matching how the Mac App Store listing already treats it).
  Screenshots are read from `$ScreenshotsDir/<lang>/microsoft/*.png` (the
  existing tools/appstore-screens generate.cjs output — run
  `npm run generate:all` in tools/appstore-screens/ before this script if
  that output is stale) and staged into the upload ZIP under `images/<locale>/`.

  PRICING: `store/defaults.json`'s `default.PriceId` (a "Free" or
  "Tier1001"+ string, see the header's "RESOLVED 2026-09-04" section above)
  is written to `pricing.priceId` on every submission, replacing whatever
  the clone returned. The script hard-fails before any network call if that
  value isn't a syntactically valid tier — see "Set pricing.priceId" below.

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
.PARAMETER ScreenshotsDir
  Path to the generated Store-screenshot output directory (contains
  <lang>/microsoft/*.png per locale, <lang> being 'en'/'de'). Default:
  'tools/appstore-screens/output'. Pass '' (empty string) to skip image
  upload entirely and only update text metadata + package, as before.
.PARAMETER SkipCommit
  Uploads the package/metadata/screenshots and leaves the submission as an
  editable DRAFT in Partner Center — skips the final /commit call (and the
  poll-for-certification loop after it), so nothing is actually sent to
  Microsoft for review. For out-of-band prep runs where a human commits the
  submission themselves in Partner Center. The tag-triggered release.yml job
  does NOT pass this — a real release still auto-submits as designed.
#>
param(
  [Parameter(Mandatory)] [string] $AppId,
  [Parameter(Mandatory)] [string] $TenantId,
  [Parameter(Mandatory)] [string] $ClientId,
  [Parameter(Mandatory)] [string] $ClientSecret,
  [Parameter(Mandatory)] [string] $MsixPath,
  [string] $StoreDir = 'store',
  [string] $ScreenshotsDir = 'tools/appstore-screens/output',
  [switch] $SkipCommit
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$BASE_URL = 'https://manage.devcenter.microsoft.com/v1.0/my'

# store/ folder name → classic Submission API locale key.
#
# CORRECTED AGAIN 2026-07-30 (this comment block was wrong for about 3 hours;
# read this version, not any earlier one): 'de-DE' -> 'de-de', NOT 'de'.
#
# The 2026-07-30-early-morning "fix" below (now reverted) claimed 'de' was
# the real, live German listing and 'de-de' a never-served phantom. That was
# checked only against a *pending, not-yet-published* submission and only by
# comparing image counts - not against what's actually served. A second,
# independent check the same day - the PUBLISHED submission's listing text,
# the public DisplayCatalog API for markets DE/AT/CH, and the public Store
# page itself - all agree on the opposite: 'de-de' is what every
# German-speaking market actually receives; 'de' is the orphan nobody sees.
# ('de' got created in the first place because this script and
# scripts/apply-store-metadata.mjs used to disagree on the locale key - one
# wrote 'de', the other 'de-de'. They must always agree; whichever key that
# is, make sure BOTH files use it.)
#
# tl;dr of the previous (wrong) comment, kept for the git-blame trail: it said
# Partner Center logged "Locale 'de-de' not in cloned submission - creating
# entry." on the 2026-07-29 run and concluded 'de-de' was therefore new/fake.
# That log line is real, but the conclusion drawn from it was backwards - see
# above for what actually determines which locale is live.
$LOCALE_MAP = @{ 'en-US' = 'en-us'; 'de-DE' = 'de-de' }

# store/ folder name → tools/appstore-screens output lang folder ('en'/'de').
$SCREENSHOT_LANG_MAP = @{ 'en-US' = 'en'; 'de-DE' = 'de' }

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
      # A 4xx (other than 429 Too Many Requests) is a validation/auth/
      # permission rejection, never a transient network blip — retrying it
      # 3x just delays a real failure by 15s and buries the actual error
      # under two identical warnings (verified live 2026-08-20: an
      # InvalidParameterValue pricing rejection was retried twice for no
      # reason before finally throwing). Fail fast on those; keep retrying
      # everything else (network errors, 5xx, 429).
      $statusCode = $_.Exception.Response?.StatusCode.value__
      if ($statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -ne 429) {
        throw
      }
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

# Lists the generated Store screenshots for one locale, sorted by their
# numeric prefix (01_hero.png, 02_workspace-overview.png, …). Returns an
# array of hashtables: LocalPath (source file), ZipEntry (path inside the
# upload ZIP, relative to its root), Description (human caption derived from
# the filename's slug, since tools/appstore-screens doesn't emit one
# separately). Returns an empty array (not an error) if the directory is
# missing — the caller decides whether that's fatal.
function Read-LocaleImages {
  param([string] $ScreenshotsDir, [string] $LangFolder, [string] $Locale)

  $dir = Join-Path $ScreenshotsDir (Join-Path $LangFolder 'microsoft')
  if (-not (Test-Path $dir)) { return @() }

  $files = Get-ChildItem -Path $dir -Filter '*.png' |
    Sort-Object { [int]([regex]::Match($_.Name, '^\d+').Value) }

  return @($files | ForEach-Object {
    $slug = $_.BaseName -replace '^\d+_', '' -replace '-', ' '
    $caption = (Get-Culture).TextInfo.ToTitleCase($slug)
    @{
      LocalPath   = $_.FullName
      ZipEntry    = "images/$Locale/$($_.Name)"
      Description = "WhisPaste — $caption"
    }
  })
}

# Appends a line to the GitHub Actions run summary when running in CI, so an
# AFK submission is auditable at a glance instead of buried in the job log.
function Write-Summary {
  param([string] $Line)
  if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $Line -Encoding UTF8
  }
}

# ── Validate pricing.priceId BEFORE touching the live submission ──────────────
# Mechanical guard against a repeat of the 2026-08-20/2026-09-04 incident
# chain (see header): fail loudly here, before any API call (auth, pending-
# submission delete, clone), rather than mid-flight after the live
# submission has already been deleted/cloned. Validates syntax only — it
# cannot know whether the tier's actual EUR/USD amount matches WhisPaste's
# intended price; that still requires a human to have looked it up once in
# Partner Center → Pricing and availability → the tier conversion table.
$defaults = Get-Content (Join-Path $StoreDir 'defaults.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$priceId  = $defaults.default.PriceId
if ($priceId -ne 'Free' -and $priceId -notmatch '^Tier(1[0-9]{3}|[2-9][0-9]?)$') {
  throw @"
$StoreDir/defaults.json's default.PriceId ('$priceId') is not a valid
Microsoft Store price tier. Set it to 'Free' or a 'TierNNNN' value looked
up in Partner Center -> Pricing and availability -> the tier conversion
table for WhisPaste's real price (isAdvancedPricingModel accounts use the
Tier1001+ range; legacy Tier2-Tier96 are rejected for this pricing model
per Microsoft support ticket API TrackingID#2608200050000071 -- see this
script's header and docs/store-release.md). Never guess a tier number:
committing a wrong-but-valid-looking tier silently changes the live price.
"@
}
Write-Host ":: pricing.priceId = '$priceId' (from $StoreDir/defaults.json)"

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

# Set-StrictMode -Version Latest (above) turns a merely-absent property into
# a hard error ("cannot be found on this object") instead of returning $null
# — and the DevCenter API omits `pendingApplicationSubmission` entirely from
# the JSON body when there's no pending submission, rather than sending it as
# null. Verified live 2026-07-28 (WhisPaste, freshly committed app state):
# `$app.pendingApplicationSubmission` alone crashed the very first real run
# of this revived script. Check property existence before touching it.
if ($app.PSObject.Properties.Match('pendingApplicationSubmission').Count -gt 0 -and $app.pendingApplicationSubmission) {
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

# ── Set pricing.priceId ────────────────────────────────────────────────────────
# The clone above carries whatever the GET response returns for pricing —
# for this account that is the literal string "Base", an internal read-only
# sentinel Microsoft's Engineering Team confirmed is NEVER a legal PUT value
# (see header's "RESOLVED 2026-09-04"). Overwrite it with the validated
# $priceId from store/defaults.json; leave every other pricing sub-field
# (isAdvancedPricingModel, trialPeriod, marketSpecificPricings, sales) from
# the clone untouched — only priceId itself was ever the problem.
Write-Host ":: Setting pricing.priceId = '$priceId'..."
$sub.pricing.priceId = $priceId

# ── Load managed listing content from store/ (Title/Description/Features/ ────
# ── Keywords/ReleaseNotes — same field set as apply-store-metadata.mjs) ───────
# $defaults was already loaded above for the pricing.priceId validation.

Write-Host ":: Loading store listing content..."
$title = $defaults.default.Title
if (-not $title) { throw "$StoreDir/defaults.json is missing default.Title." }

$managed = @{}
foreach ($folder in $LOCALE_MAP.Keys) {
  $locale = $LOCALE_MAP[$folder]
  $dir    = Join-Path $StoreDir $folder
  $images = @()
  if ($ScreenshotsDir) {
    $langFolder = $SCREENSHOT_LANG_MAP[$folder]
    $images     = Read-LocaleImages -ScreenshotsDir $ScreenshotsDir -LangFolder $langFolder -Locale $locale
  }
  $managed[$locale] = @{
    title        = $title
    description  = Read-StoreFile (Join-Path $dir 'description.txt')
    features     = Read-LineList  (Join-Path $dir 'features.txt')
    keywords     = Read-LineList  (Join-Path $dir 'search-terms.txt')
    releaseNotes = Read-StoreFile (Join-Path $dir 'release-notes.txt')
    images       = $images
  }
  Write-Host "   $locale`: $($managed[$locale].description.Length) chars description, $($managed[$locale].features.Count) features, $($managed[$locale].keywords.Count) keywords, $($images.Count) screenshots"
  if ($ScreenshotsDir -and $images.Count -eq 0) {
    Write-Warning "   No screenshots found for $locale under $ScreenshotsDir/$($SCREENSHOT_LANG_MAP[$folder])/microsoft/ — existing Store images (if any) will be left untouched for this locale."
  }
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

# Prune any locale the cloned submission carries that we don't manage (e.g. the
# 'de' orphan created 2026-07-30 when this script and apply-store-metadata.mjs
# disagreed on the locale key — see the $LOCALE_MAP comment above). Omitting a
# locale from `listings` on PUT is the documented way to remove it: Microsoft's
# submission-status-code table lists `ListingOptOutWarning` — "The developer
# removed a listing from a previous submission" — as an expected, non-fatal
# warning, not an error (learn.microsoft.com/windows/uwp/monetize/
# manage-app-submissions, confirmed 2026-07-30). Unlike applicationPackages,
# listings do NOT need a PendingDelete-style status flag; simple omission works.
# This keeps every future submission self-cleaning instead of relying on a
# one-off manual fix.
$managedLocales = @($LOCALE_MAP.Values)
foreach ($prop in @($sub.listings.PSObject.Properties)) {
  if ($managedLocales -notcontains $prop.Name) {
    Write-Warning "   Pruning unmanaged locale listing '$($prop.Name)' (not in `$LOCALE_MAP)."
    $sub.listings.PSObject.Properties.Remove($prop.Name)
  }
}

foreach ($locale in $LOCALE_MAP.Values) {
  # Same Set-StrictMode pitfall as the pendingApplicationSubmission fix above:
  # a PSCustomObject built via Add-Member throws "property cannot be found"
  # for a genuinely absent property instead of returning $null — verified
  # live 2026-07-28 (WhisPaste v1.2.60 real submission): the cloned draft had
  # no 'de-de' listing yet at all, not just an empty one.
  if (-not ($sub.listings.PSObject.Properties.Match($locale).Count -gt 0)) {
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
  # Only touch images when we actually found fresh ones for this locale — an
  # empty $m.images means "nothing generated", not "clear the listing's
  # screenshots", so the cloned submission's existing images pass through
  # untouched in that case (same fail-safe philosophy as the other fields,
  # which only write when non-empty).
  #
  # `images` is shared by screenshots AND icons/logos/promotional art (see
  # the Image resource docs — imageType also covers Icon/StoreLogo*/
  # PromotionalArt*/Xbox*). We only manage Screenshot entries here, so any
  # existing non-Screenshot images from the cloned submission are preserved
  # and merged with our fresh Screenshot set, instead of being wiped out by
  # a blind array replace.
  if ($m.images.Count -gt 0) {
    # Same Set-StrictMode pitfall as the locale-creation branch above: a
    # freshly-created baseListing (brand-new locale, no cloned images at
    # all) has no 'images' property yet, and reading it throws instead of
    # returning $null — verified live 2026-07-29 (real submission, de-de
    # created fresh for the first time since the images feature shipped).
    $existingImages = if ($bl.PSObject.Properties.Match('images').Count -gt 0) {
      $bl.images
    } else { @() }
    $existingNonScreenshots = @(
      $existingImages | Where-Object { $_.imageType -ne 'Screenshot' }
    )
    $newScreenshots = @(
      $m.images | ForEach-Object {
        [PSCustomObject]@{
          fileName    = $_.ZipEntry
          fileStatus  = 'PendingUpload'
          description = $_.Description
          imageType   = 'Screenshot'
        }
      }
    )
    $bl | Add-Member -NotePropertyName 'images' `
      -NotePropertyValue @($existingNonScreenshots + $newScreenshots) -Force
  }
  # Pricing is NOT part of baseListing (it's a top-level submission field);
  # it was already set once, explicitly, right after the clone above — see
  # "Set pricing.priceId" and the header's "RESOLVED 2026-09-04" section.
}

# Pricing (`$sub.pricing.priceId`) is deliberately handled ONCE, right after
# the clone (see "Set pricing.priceId" above), not here — everything else in
# this loop only ever touched `baseListing`, never the top-level `pricing`
# object, so there was never a second place for it to belong. The full
# 2026-07-30 → 2026-09-04 incident history (three wrong beliefs in a row:
# "priceId = null is safe", "pass pricing through untouched is safe", "no
# safe payload exists at all") lives in the header comment and
# docs/store-release.md — do not re-derive it here; read those before
# touching pricing logic again.

# ── Replace application packages ──────────────────────────────────────────────
# The API rejects a PUT that just swaps in a new package array — existing
# package entries must still be present, marked `PendingDelete` if being
# replaced (error verified live 2026-07-29: "Please keep all file entries
# for existing packages. If you wish to remove a package, mark it as
# PendingDelete. The following packages are missing in your update: <id>").
# Cloned packages already have `Uploaded`/`PendingDelete`/etc. status — only
# ones not already PendingDelete need flipping; a re-run against a
# submission this script itself already marked would otherwise double up.

$msixName = Split-Path $MsixPath -Leaf
Write-Host ":: Registering package: $msixName"
$existingPackages = @(
  $sub.applicationPackages | ForEach-Object {
    if ($_.fileStatus -ne 'PendingDelete') { $_.fileStatus = 'PendingDelete' }
    $_
  }
)
$sub.applicationPackages = @($existingPackages) + @(
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
# The ZIP must contain the .msix at its root AND every image referenced by a
# baseListing.images[].fileName, at that exact relative path — both packages
# and images travel in the same archive to the same fileUploadUrl. Stage
# everything into a scratch folder first so Compress-Archive produces the
# right internal layout (zipping $MsixPath alone, as before, would omit the
# images entirely).

Write-Host ":: Packaging MSIX + screenshots for upload..."
$stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) "ms-store-$subId-staging"
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDir | Out-Null
Copy-Item -Path $MsixPath -Destination (Join-Path $stagingDir $msixName)

$totalImages = 0
foreach ($locale in $LOCALE_MAP.Values) {
  foreach ($img in $managed[$locale].images) {
    $destPath = Join-Path $stagingDir $img.ZipEntry
    New-Item -ItemType Directory -Path (Split-Path $destPath) -Force | Out-Null
    Copy-Item -Path $img.LocalPath -Destination $destPath
    $totalImages++
  }
}
Write-Host "   Staged $totalImages screenshot(s) across $($LOCALE_MAP.Values.Count) locale(s)."

$zipPath = Join-Path ([System.IO.Path]::GetTempPath()) "ms-store-$subId.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $stagingDir '*') -DestinationPath $zipPath -Force
Remove-Item $stagingDir -Recurse -Force
$zipMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host "   ZIP: $zipMB MB"

Write-Host ":: Uploading package to Azure Storage..."
Invoke-WebRequest -Uri $uploadUrl -Method Put -InFile $zipPath `
  -ContentType 'application/octet-stream' `
  -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } | Out-Null
Write-Host "   Uploaded."

# ── Commit ────────────────────────────────────────────────────────────────────

if ($SkipCommit) {
  Write-Host ""
  Write-Host "Skipping commit (-SkipCommit) — submission left as an editable draft."
  Write-Host "Review and submit yourself: https://partner.microsoft.com/en-us/dashboard/apps/$AppId/submissions/$subId"
  Write-Summary "### Microsoft Store submission: 📝 draft prepared (not committed)"
  Write-Summary ""
  Write-Summary "Submission ``$subId`` has the updated package/metadata/screenshots staged but was NOT committed. [Review and submit in Partner Center](https://partner.microsoft.com/en-us/dashboard/apps/$AppId/submissions/$subId) when ready."
  exit 0
}

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
    # Same Set-StrictMode hazard as above — statusDetails/errors may be
    # genuinely absent on some failure shapes; guard proactively rather than
    # let a reporting crash mask the real failure underneath it.
    $errorList = if ($status.PSObject.Properties.Match('statusDetails').Count -gt 0 -and
                     $status.statusDetails.PSObject.Properties.Match('errors').Count -gt 0) {
      $status.statusDetails.errors
    } else { @() }
    $errors = ($errorList | ForEach-Object { "  • $($_.code): $($_.details)" }) -join "`n"
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
