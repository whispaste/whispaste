<#
.SYNOPSIS
    Generates user-friendly, bilingual release notes from a raw git-cliff changelog.

.DESCRIPTION
    Takes a structured changelog (from git-cliff) and uses the OpenAI API to produce
    audience-friendly release notes in English and German. Sensitive information
    (API keys, internal paths, webhook URLs, implementation details) is stripped.

    Output files:
      - release-notes-en.md  (English, user-facing)
      - release-notes-de.md  (German, du-Form, user-facing)
      - release-notes-raw.md (raw git-cliff output, for GitHub Release details)

.PARAMETER RawChangelog
    Path to a text file containing the raw changes. Accepts git-cliff output,
    a CHANGELOG.md section extracted by awk, or plain git log text.

.PARAMETER Version
    The version string (e.g., "1.2.0").

.PARAMETER OpenAIKey
    OpenAI API key (from GitHub Actions secret).

.PARAMETER Model
    OpenAI model to use. Default: gpt-4o-mini (fast, cheap, good enough for summaries).

.PARAMETER OutputDir
    Directory for output files. Default: current directory.
#>
param(
    [Parameter(Mandatory)][string]$RawChangelog,
    [Parameter(Mandatory)][string]$Version,
    [string]$OpenAIKey,
    [string]$Model = "gpt-4o-mini",
    [string]$OutputDir = "."
)

$ErrorActionPreference = "Stop"

# Load .env file if OpenAIKey not provided and env var not set
if (-not $OpenAIKey -and -not $env:OPENAI_API_KEY) {
    $envFile = Join-Path (Split-Path $PSScriptRoot -Parent) ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^\s*([^#][^=]+?)\s*=\s*(.*)\s*$') {
                $val = $Matches[2].Trim()
                if ($val) {
                    [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $val, "Process")
                }
            }
        }
        Write-Host "Loaded secrets from .env"
    }
}

if (-not $OpenAIKey) { $OpenAIKey = $env:OPENAI_API_KEY }
# Trim whitespace/newlines — GitHub Actions injects secrets with a trailing newline
# which makes the Authorization header value invalid ("Bearer sk-...\n").
if ($OpenAIKey) { $OpenAIKey = $OpenAIKey.Trim() }

if (-not $OpenAIKey) {
    Write-Warning "No OpenAI API key found. Set it in .env, `$env:OPENAI_API_KEY, or -OpenAIKey parameter."
    Write-Warning "Falling back to raw changelog as release notes."
}

if (-not (Test-Path $RawChangelog)) {
    Write-Error "Raw changelog not found: $RawChangelog"
    exit 1
}

$raw = Get-Content $RawChangelog -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($raw)) {
    Write-Host "No changelog content — using fallback."
    $raw = "Minor improvements and bug fixes."
}

# Truncate to avoid excessive token usage (max ~3000 chars of commit log)
if ($raw.Length -gt 3000) {
    $raw = $raw.Substring(0, 3000) + "`n... (truncated)"
}

$systemPrompt = @"
You are a release notes writer for WhisPaste, a premium Windows desktop dictation app.
Your audience: non-technical Windows users (founders, freelancers, writers, consultants).

RULES:
- Write in a warm, professional, concise tone — past tense, declarative ("Smart Mode now works...")
- NEVER use imperative mood ("Enhance your...", "Introduce...", "Improve...") — these are announcements, not instructions
- Use max 2 sections: Highlights (user-visible changes) and Improvements (stability/quality).
  Skip empty sections. NEVER have a separate "Bug Fixes" section — merge fixes into Highlights.
- Section headers in German must be translated: "Highlights" stays "Highlights", but use "Verbesserungen" not "Improvements"
- Use simple, everyday language — no jargon, no code references, no file paths, no technical terms
- NEVER mention: API keys, webhook URLs, internal architecture, function names, file names,
  implementation details, server names (whisper-server, llama-server), database internals,
  crash reporter internals, CI/CD pipeline details, MSIX, Discord, subprocess, timeout, token limits,
  GPU detection, multi-vendor, binary selection, onboarding wizard internals, demo mode
- NEVER duplicate: each change appears in exactly ONE bullet. No overlap between sections.
- Focus on USER IMPACT: what changed FOR THE USER, not what changed in the code
- Keep it compact: 3-6 bullet points total across all sections
- Each bullet: one sentence, past tense or "now" phrasing, scannable in 1-2 seconds
- If a change is purely internal (refactoring, CI, tests, monitoring, onboarding restructure), skip it entirely
- Use "Windows taskbar" not "taskbar", "Microsoft Store" not "Store installs"
- German must use du-Form and feel natural, not like a machine translation

OUTPUT FORMAT (exactly):
===EN===
[English release notes in markdown, sections with ###]
===DE===
[German release notes in markdown, sections with ###, du-Form (informal "you")]
===END===
"@

$userPrompt = @"
Generate release notes for WhisPaste version $Version.

Here are the changes included in this release:

$raw
"@

$body = @{
    model    = $Model
    messages = @(
        @{ role = "system"; content = $systemPrompt }
        @{ role = "user"; content = $userPrompt }
    )
    temperature  = 0.4
    max_tokens   = 1500
} | ConvertTo-Json -Depth 5

Write-Host "Calling OpenAI API ($Model) for release notes..."

try {
    $response = Invoke-RestMethod `
        -Uri "https://api.openai.com/v1/chat/completions" `
        -Method POST `
        -Headers @{
            "Authorization" = "Bearer $($OpenAIKey.Trim())"
            "Content-Type"  = "application/json"
        } `
        -Body $body `
        -TimeoutSec 60

    if (-not $response.choices -or $response.choices.Count -eq 0 -or -not $response.choices[0].message) {
        throw "API returned unexpected response format: $($response | ConvertTo-Json -Depth 2 -Compress)"
    }
    $content = $response.choices[0].message.content
    Write-Host "AI response received ($($content.Length) chars)"
} catch {
    Write-Warning "OpenAI API call failed: $_"
    Write-Host "Using raw changelog as fallback."

    # Fallback: use raw changelog without AI processing
    $enNotes = "## What's New in v$Version`n`n$raw"
    $deNotes = "## Neuigkeiten in v$Version`n`n$raw"
    $enNotes | Out-File -FilePath "$OutputDir/release-notes-en.md" -Encoding UTF8
    $deNotes | Out-File -FilePath "$OutputDir/release-notes-de.md" -Encoding UTF8
    $raw | Out-File -FilePath "$OutputDir/release-notes-raw.md" -Encoding UTF8
    exit 0
}

# Parse AI response
$enNotes = ""
$deNotes = ""

if ($content -match '===EN===([\s\S]*?)===DE===') {
    $enNotes = $Matches[1].Trim()
}
if ($content -match '===DE===([\s\S]*?)===END===') {
    $deNotes = $Matches[1].Trim()
}

# Fallback if parsing failed
if ([string]::IsNullOrWhiteSpace($enNotes)) {
    Write-Warning "Could not parse EN section from AI response. Using raw."
    $enNotes = "## What's New in v$Version`n`n$raw"
}
if ([string]::IsNullOrWhiteSpace($deNotes)) {
    Write-Warning "Could not parse DE section from AI response. Using EN as fallback."
    $deNotes = $enNotes
}

# Security post-filter: strip anything that looks like a secret or internal path
$secretPatterns = @(
    'sk-[a-zA-Z0-9]{10,}',
    'gsk_[a-zA-Z0-9]+',
    'Bearer\s+[a-zA-Z0-9._\-]+',
    'https?://[^\s]*supabase[^\s]*',
    'https?://[^\s]*discord[^\s]*webhook[^\s]*',
    'C:\\[^\s]+\.(dart|ps1|yml|json|db|exe)',
    'whisper-server',
    'llama-server',
    'crashreporter',
    '127\.0\.0\.1:\d+'
)

foreach ($pattern in $secretPatterns) {
    $enNotes = [regex]::Replace($enNotes, $pattern, '[REDACTED]', 'IgnoreCase')
    $deNotes = [regex]::Replace($deNotes, $pattern, '[REDACTED]', 'IgnoreCase')
}

# Check for accidental leaks
if ($enNotes -match '\[REDACTED\]' -or $deNotes -match '\[REDACTED\]') {
    Write-Warning "Security filter caught potential sensitive content — redacted."
}

# Write output files
$enNotes | Out-File -FilePath "$OutputDir/release-notes-en.md" -Encoding UTF8 -NoNewline
$deNotes | Out-File -FilePath "$OutputDir/release-notes-de.md" -Encoding UTF8 -NoNewline
$raw | Out-File -FilePath "$OutputDir/release-notes-raw.md" -Encoding UTF8 -NoNewline

Write-Host "Release notes generated:"
Write-Host "  EN: $OutputDir/release-notes-en.md ($($enNotes.Length) chars)"
Write-Host "  DE: $OutputDir/release-notes-de.md ($($deNotes.Length) chars)"
Write-Host "  Raw: $OutputDir/release-notes-raw.md ($($raw.Length) chars)"
