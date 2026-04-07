<#
.SYNOPSIS
    Local security scan for WhisPaste (Flutter).
.DESCRIPTION
    Runs language-agnostic security tools and reports findings.
    Exit code 0 = clean, 1 = findings detected, 2 = tool missing/error.
.EXAMPLE
    .\scripts\security-scan.ps1
#>

$ErrorActionPreference = "Continue"
$script:exitCode = 0
$script:results = @()
$script:toolError = $false

function Write-Header($text) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Write-Result($tool, $status, $detail) {
    $color = if ($status -eq "PASS") { "Green" } elseif ($status -eq "WARN") { "Yellow" } else { "Red" }
    $icon = if ($status -eq "PASS") { [char]0x2713 } elseif ($status -eq "WARN") { "!" } else { "X" }
    Write-Host "  [$icon] $tool - $status" -ForegroundColor $color
    if ($detail) { Write-Host "      $detail" -ForegroundColor DarkGray }
    $script:results += [PSCustomObject]@{ Tool = $tool; Status = $status; Detail = $detail }
}

function Test-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Result $name "ERROR" "Not installed. See README for installation instructions."
        $script:toolError = $true
        return $false
    }
    return $true
}

# ------------------------------------------------------------------
# 1. gitleaks (secret scanning)
# ------------------------------------------------------------------
Write-Header "gitleaks (Secret Scanner)"

if (Test-Tool "gitleaks") {
    $leaksOutput = & gitleaks detect --source . --no-banner 2>&1
    $leaksExit = $LASTEXITCODE

    if ($leaksExit -eq 0) {
        Write-Result "gitleaks" "PASS" "No secrets detected"
    } else {
        Write-Result "gitleaks" "FAIL" "Secrets detected in repository!"
        $leaksOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        if ($script:exitCode -lt 1) { $script:exitCode = 1 }
    }
}

# ------------------------------------------------------------------
# 2. DevSkim (multi-language security linter: Dart, JS, HTML, CSS)
# ------------------------------------------------------------------
Write-Header "DevSkim (Multi-Language Security Linter)"

if (Test-Tool "devskim") {
    $devskimOutput = & devskim analyze `
        --source-code . `
        --file-format text `
        --severity "Critical,Important,Moderate" `
        --ignore-globs "**/.git/**,**/bin/**,**/node_modules/**,**/dist/**,**/build/**,**/*.exe,**/*.dll,skills-lock.json" `
        2>&1
    $devskimExit = $LASTEXITCODE

    if ($devskimExit -ne 0) {
        Write-Result "DevSkim" "ERROR" "Scanner failed (exit code $devskimExit)"
        $script:toolError = $true
    } else {
        $devskimFindings = ($devskimOutput | Where-Object { $_ -match "\[(Critical|Important|Moderate)\]" })
        $findingCount = ($devskimFindings | Measure-Object).Count

        if ($findingCount -eq 0) {
            Write-Result "DevSkim" "PASS" "No security issues found (Dart, JS, HTML, CSS)"
        } else {
            Write-Result "DevSkim" "WARN" "$findingCount finding(s) — review for false positives"
            $devskimFindings | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
            if ($script:exitCode -lt 1) { $script:exitCode = 1 }
        }
    }
}

# ------------------------------------------------------------------
# 3. Flutter analyze (Dart static analysis)
# ------------------------------------------------------------------
Write-Header "Flutter Analyze (Dart Static Analysis)"

if (Test-Tool "flutter") {
    $env:CI = "true"
    $analyzeOutput = & flutter analyze --no-preamble 2>&1
    $analyzeExit = $LASTEXITCODE

    if ($analyzeExit -eq 0) {
        Write-Result "flutter analyze" "PASS" "No issues found"
    } else {
        $issueCount = ($analyzeOutput | Where-Object { $_ -match "(error|warning|info)\s+•" } | Measure-Object).Count
        Write-Result "flutter analyze" "WARN" "$issueCount issue(s) found"
        $analyzeOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
        if ($script:exitCode -lt 1) { $script:exitCode = 1 }
    }
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host ""
Write-Header "Summary"

$passed = ($script:results | Where-Object { $_.Status -eq "PASS" } | Measure-Object).Count
$warned = ($script:results | Where-Object { $_.Status -eq "WARN" } | Measure-Object).Count
$failed = ($script:results | Where-Object { $_.Status -eq "FAIL" } | Measure-Object).Count
$errors = ($script:results | Where-Object { $_.Status -eq "ERROR" } | Measure-Object).Count
$total = $script:results.Count

Write-Host ""
foreach ($r in $script:results) {
    Write-Result $r.Tool $r.Status $r.Detail
}
Write-Host ""

if ($script:toolError) {
    $script:exitCode = 2
    Write-Host "  Tool error: $errors tool(s) not found. Install missing tools first." -ForegroundColor Red
} elseif ($script:exitCode -eq 0) {
    Write-Host "  All $passed checks passed!" -ForegroundColor Green
} else {
    Write-Host "  $passed passed, $warned warnings, $failed failed (of $total)" -ForegroundColor Yellow
}

Write-Host ""
exit $script:exitCode