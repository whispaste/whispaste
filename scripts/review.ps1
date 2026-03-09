<#
.SYNOPSIS
    WhisPaste Quality Review Orchestrator
.DESCRIPTION
    Collects review-relevant files, groups them by concern area, generates
    structured review prompts, and executes them via GitHub Copilot CLI.
    Uses the quality-audit skill for evaluation criteria.
.PARAMETER Changed
    Only review files changed since last commit (uses git diff).
.PARAMETER Fleet
    Generate a combined prompt optimized for /fleet parallel execution
    and launch Copilot CLI interactively.
.PARAMETER DryRun
    Collect files and generate prompts without executing them.
.PARAMETER Concern
    Filter to a specific concern group: text, ui, code, design, or all.
.EXAMPLE
    .\review.ps1                    # Full review, sequential execution
    .\review.ps1 -Changed           # Review only changed files
    .\review.ps1 -Fleet             # Generate fleet prompt + launch Copilot
    .\review.ps1 -DryRun            # Preview prompts without executing
    .\review.ps1 -Concern ui        # Review only UI concern group
#>

[CmdletBinding()]
param(
    [switch]$Changed,
    [switch]$Fleet,
    [switch]$DryRun,
    [ValidateSet('all', 'text', 'ui', 'code', 'design')]
    [string]$Concern = 'all'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Configuration ---

$AppRoot = $PSScriptRoot
$SkillRef = '.agents/skills/quality-audit/SKILL.md'

# File patterns grouped by concern area
$ConcernGroups = @{
    text = @{
        Label       = 'Text & Content'
        Description = 'Translation files, content copy, localization'
        Patterns    = @(
            'ui_main/scripts/01-translations.js'
            'l10n.go'
            'postprocess.go'
            'README.md'
            'website/src/pages/*.astro'
            'website/src/scripts/i18n.ts'
        )
        Dimensions  = @(1, 5)  # Audience Alignment + Content Quality
    }
    ui = @{
        Label       = 'UI & Interaction'
        Description = 'HTML templates, JavaScript interactions, CSS styling'
        Patterns    = @(
            'ui_main/template.html'
            'ui_main/scripts/0[2-9]*.js'
            'ui_main/styles/*.css'
            'website/src/components/*.astro'
        )
        Dimensions  = @(2, 3, 6)  # UX Quality + Premium Score + Maintainability
    }
    code = @{
        Label       = 'Code Quality'
        Description = 'Go source files — error handling, logging, architecture'
        Patterns    = @(
            '*.go'
        )
        Exclude     = @('*_test.go')
        Dimensions  = @(2, 6)  # UX Quality + Maintainability (SoC)
    }
    design = @{
        Label       = 'Design System'
        Description = 'Design tokens, variables, theme consistency across surfaces'
        Patterns    = @(
            'ui_main/styles/00-variables.css'
            'website/src/styles/*.css'
            'website/design-system/**/*.md'
        )
        Dimensions  = @(3, 4)  # Premium Score + Cross-Surface Consistency
    }
}

$DimensionNames = @{
    1 = 'Zielgruppen-Passung (Target Audience Alignment)'
    2 = 'Benutzerfreundlichkeit (UX/UI Quality)'
    3 = 'Hochwertigkeit (Premium Quality Score)'
    4 = 'Oberflächen-Konsistenz (Cross-Surface Consistency)'
    5 = 'Inhaltsqualität (Content Quality)'
    6 = 'Wartbarkeit / SoC (Code Architecture & Maintainability)'
}

# --- Functions ---

function Get-ReviewFiles {
    param(
        [string[]]$Patterns,
        [string[]]$Exclude = @(),
        [bool]$ChangedOnly = $false
    )

    $files = @()

    if ($ChangedOnly) {
        # Get files changed since last commit
        $changedFiles = git diff --name-only HEAD 2>$null
        if (-not $changedFiles) {
            $changedFiles = git diff --name-only --staged 2>$null
        }
        if (-not $changedFiles) {
            return $files
        }

        foreach ($pattern in $Patterns) {
            foreach ($changed in $changedFiles) {
                if ($changed -like $pattern) {
                    $fullPath = Join-Path $AppRoot $changed
                    if (Test-Path $fullPath) {
                        $excluded = $false
                        foreach ($ex in $Exclude) {
                            if ($changed -like $ex) { $excluded = $true; break }
                        }
                        if (-not $excluded) {
                            $files += $changed
                        }
                    }
                }
            }
        }
    }
    else {
        foreach ($pattern in $Patterns) {
            $found = Get-ChildItem -Path $AppRoot -Filter (Split-Path $pattern -Leaf) -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $rel = $_.FullName.Substring($AppRoot.Length + 1).Replace('\', '/')
                    $matchesPattern = $rel -like $pattern
                    $isExcluded = $false
                    foreach ($ex in $Exclude) {
                        if ($rel -like $ex) { $isExcluded = $true; break }
                    }
                    $matchesPattern -and (-not $isExcluded)
                } |
                ForEach-Object {
                    $_.FullName.Substring($AppRoot.Length + 1).Replace('\', '/')
                }
            if ($found) { $files += $found }
        }
    }

    return $files | Sort-Object -Unique
}

function New-ReviewPrompt {
    param(
        [string]$GroupKey,
        [hashtable]$Group,
        [string[]]$Files
    )

    $dimList = ($Group.Dimensions | ForEach-Object { "  - Dimension $_`: $($DimensionNames[$_])" }) -join "`n"
    $fileRefs = ($Files | ForEach-Object { "  - @$_" }) -join "`n"
    $fileList = ($Files | ForEach-Object { "  - $_" }) -join "`n"

    $prompt = @"
Invoke the quality-audit skill (see $SkillRef) and perform an INCREMENTAL quality audit.

**Concern Group:** $($Group.Label) — $($Group.Description)

**Focus Dimensions:**
$dimList

**Files to audit:**
$fileList

Review each file against the checklist items for the focus dimensions defined in the quality-audit skill.
For each issue found, report: severity (BLOCKER/MAJOR/POLISH), dimension number, file and line,
affected persona(s), problem description, and concrete fix suggestion.

End with the dimension scores table and a prioritized refactoring list.
"@

    return $prompt
}

function Write-Banner {
    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '  ║   WhisPaste Quality Review Orchestrator      ║' -ForegroundColor Cyan
    Write-Host '  ╚══════════════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host ''
}

function Write-Summary {
    param(
        [hashtable]$Results
    )

    Write-Host ''
    Write-Host '  ┌──────────────────────────────────────────────┐' -ForegroundColor DarkGray
    Write-Host '  │  Review Summary                              │' -ForegroundColor DarkGray
    Write-Host '  └──────────────────────────────────────────────┘' -ForegroundColor DarkGray

    foreach ($key in $Results.Keys | Sort-Object) {
        $r = $Results[$key]
        $icon = if ($r.FileCount -gt 0) { '✓' } else { '○' }
        $color = if ($r.FileCount -gt 0) { 'Green' } else { 'DarkGray' }
        Write-Host "    $icon $($r.Label): $($r.FileCount) files" -ForegroundColor $color
    }
    Write-Host ''
}

# --- Main ---

Write-Banner

$mode = if ($Changed) { 'Changed files only' } else { 'Full codebase' }
$exec = if ($DryRun) { 'Dry run (no execution)' } elseif ($Fleet) { 'Fleet mode' } else { 'Sequential execution' }
Write-Host "  Mode: $mode | Execution: $exec" -ForegroundColor DarkGray
Write-Host ''

# Determine which groups to process
$groupsToProcess = if ($Concern -eq 'all') {
    $ConcernGroups.Keys
} else {
    @($Concern)
}

# Collect files per group
$reviewPlan = @{}
$totalFiles = 0

foreach ($key in $groupsToProcess) {
    $group = $ConcernGroups[$key]
    $exclude = if ($group.ContainsKey('Exclude')) { $group.Exclude } else { @() }
    $files = Get-ReviewFiles -Patterns $group.Patterns -Exclude $exclude -ChangedOnly $Changed.IsPresent

    $reviewPlan[$key] = @{
        Label     = $group.Label
        FileCount = $files.Count
        Files     = $files
        Group     = $group
    }
    $totalFiles += $files.Count

    if ($files.Count -gt 0) {
        Write-Host "  [$key] $($group.Label): $($files.Count) files found" -ForegroundColor White
        foreach ($f in $files) {
            Write-Host "      $f" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  [$key] $($group.Label): no files" -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host "  Total: $totalFiles files across $($groupsToProcess.Count) concern groups" -ForegroundColor Cyan
Write-Host ''

if ($totalFiles -eq 0) {
    Write-Host '  No files to review.' -ForegroundColor Yellow
    exit 0
}

# Generate prompts
$prompts = @{}
foreach ($key in $groupsToProcess) {
    $plan = $reviewPlan[$key]
    if ($plan.FileCount -eq 0) { continue }
    $prompts[$key] = New-ReviewPrompt -GroupKey $key -Group $plan.Group -Files $plan.Files
}

# --- Execution ---

if ($DryRun) {
    Write-Host '  === DRY RUN — Generated Prompts ===' -ForegroundColor Yellow
    Write-Host ''

    foreach ($key in $prompts.Keys | Sort-Object) {
        Write-Host "  ── [$key] $($reviewPlan[$key].Label) ──" -ForegroundColor Cyan
        Write-Host ''
        Write-Host $prompts[$key]
        Write-Host ''
        Write-Host '  ────────────────────────────────────' -ForegroundColor DarkGray
        Write-Host ''
    }
}
elseif ($Fleet) {
    # Fleet mode: combine all prompts into a single fleet-optimized prompt
    Write-Host '  Generating fleet-optimized prompt...' -ForegroundColor Yellow

    $combinedPrompt = @"
I need a comprehensive quality audit of WhisPaste. Use the quality-audit skill (see $SkillRef).

Please dispatch parallel sub-agents for each concern group below. Each agent should perform
an independent quality audit of its assigned files and dimensions, then return a structured
report following the quality-audit skill output format.

"@

    $agentNum = 1
    foreach ($key in $prompts.Keys | Sort-Object) {
        $plan = $reviewPlan[$key]
        $combinedPrompt += @"

--- Agent $agentNum`: $($plan.Label) ---
$($prompts[$key])

"@
        $agentNum++
    }

    $combinedPrompt += @"

After all agents complete, synthesize their reports into a single Quality Audit Report with:
1. Overall dimension scores (aggregate across all agents)
2. Combined prioritized refactoring list (sorted by severity then audience impact)
3. Total issue counts by severity
"@

    # Write to temp file for reference
    $tempFile = Join-Path $env:TEMP "whispaste-fleet-review-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
    Set-Content -Path $tempFile -Value $combinedPrompt -Encoding UTF8
    Write-Host "  Prompt saved to: $tempFile" -ForegroundColor DarkGray

    # Copy to clipboard
    $combinedPrompt | Set-Clipboard
    Write-Host '  Prompt copied to clipboard!' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Next steps:' -ForegroundColor White
    Write-Host '    1. Open Copilot CLI: copilot' -ForegroundColor DarkGray
    Write-Host '    2. Paste the prompt (Ctrl+V)' -ForegroundColor DarkGray
    Write-Host '    3. The agent will dispatch fleet sub-agents automatically' -ForegroundColor DarkGray
    Write-Host ''
}
else {
    # Sequential mode: execute each prompt via copilot -p
    Write-Host '  Executing review prompts sequentially...' -ForegroundColor Yellow
    Write-Host ''

    $results = @{}
    foreach ($key in $prompts.Keys | Sort-Object) {
        $plan = $reviewPlan[$key]
        Write-Host "  ── Reviewing: $($plan.Label) ($($plan.FileCount) files) ──" -ForegroundColor Cyan

        $prompt = $prompts[$key]

        try {
            # Execute via copilot -p
            $output = & copilot -p $prompt 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                Write-Host $output
                Write-Host ''
                $results[$key] = @{ Success = $true; Output = $output }
            }
            else {
                Write-Host "  ⚠ Copilot returned exit code $exitCode" -ForegroundColor Yellow
                Write-Host $output -ForegroundColor Yellow
                $results[$key] = @{ Success = $false; Output = $output }
            }
        }
        catch {
            Write-Host "  ✗ Failed to execute: $_" -ForegroundColor Red
            Write-Host "  Tip: Ensure 'copilot' is installed and in PATH" -ForegroundColor DarkGray
            Write-Host "  Install: npm install -g @github/copilot" -ForegroundColor DarkGray
            $results[$key] = @{ Success = $false; Output = $_.Exception.Message }
        }

        Write-Host '  ────────────────────────────────────' -ForegroundColor DarkGray
        Write-Host ''
    }

    # Summary
    $succeeded = ($results.Values | Where-Object { $_.Success }).Count
    $failed = ($results.Values | Where-Object { -not $_.Success }).Count
    Write-Host ''
    Write-Host "  Review complete: $succeeded succeeded, $failed failed" -ForegroundColor $(if ($failed -gt 0) { 'Yellow' } else { 'Green' })
}

Write-Summary -Results $reviewPlan
