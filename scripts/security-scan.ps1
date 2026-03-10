<#
.SYNOPSIS
    Local security scan for WhisPaste.
.DESCRIPTION
    Runs all available security tools and reports findings.
    Exit code 0 = clean, 1 = findings detected, 2 = tool missing/error.
.EXAMPLE
    .\scripts\security-scan.ps1            # Run all checks
    .\scripts\security-scan.ps1 -Quick     # Skip slow checks (govulncheck)
#>
param(
    [switch]$Quick
)

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
        Write-Result $name "ERROR" "Not installed. Run: go install ... or see README."
        $script:toolError = $true
        return $false
    }
    return $true
}

$env:CGO_ENABLED = "1"

# ------------------------------------------------------------------
# 1. golangci-lint (security profile)
# ------------------------------------------------------------------
Write-Header "golangci-lint (Security Linters)"

if (Test-Tool "golangci-lint") {
    $lintOutput = & golangci-lint run --timeout 5m 2>&1
    $lintExit = $LASTEXITCODE

    if ($lintExit -eq 0) {
        Write-Result "golangci-lint" "PASS" "No issues found"
    } else {
        $issueCount = ($lintOutput | Where-Object { $_ -match "^\w" } | Measure-Object).Count
        Write-Result "golangci-lint" "WARN" "$issueCount issue(s) found"
        $lintOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
        if ($script:exitCode -lt 1) { $script:exitCode = 1 }
    }
}

# ------------------------------------------------------------------
# 2. gosec (standalone — deeper analysis)
# ------------------------------------------------------------------
Write-Header "gosec (Go Security Scanner)"

if (Test-Tool "gosec") {
    $gosecOutput = & gosec -quiet -fmt text ./... 2>&1
    $gosecExit = $LASTEXITCODE

    if ($gosecExit -eq 0) {
        Write-Result "gosec" "PASS" "No security issues found"
    } else {
        Write-Result "gosec" "WARN" "Security issues detected"
        $gosecOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
        if ($script:exitCode -lt 1) { $script:exitCode = 1 }
    }
}

# ------------------------------------------------------------------
# 3. govulncheck (dependency vulnerabilities)
# ------------------------------------------------------------------
if (-not $Quick) {
    Write-Header "govulncheck (Dependency Vulnerabilities)"

    if (Test-Tool "govulncheck") {
        $vulnOutput = & govulncheck ./... 2>&1
        $vulnExit = $LASTEXITCODE

        if ($vulnExit -eq 0) {
            Write-Result "govulncheck" "PASS" "No known vulnerabilities"
        } else {
            Write-Result "govulncheck" "FAIL" "Vulnerable dependencies found"
            $vulnOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            if ($script:exitCode -lt 1) { $script:exitCode = 1 }
        }
    }
} else {
    Write-Result "govulncheck" "SKIP" "Skipped (use without -Quick to include)"
}

# ------------------------------------------------------------------
# 4. gitleaks (secret scanning)
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
# 5. go vet
# ------------------------------------------------------------------
Write-Header "go vet (Static Analysis)"

if (Test-Tool "go") {
    $vetOutput = & go vet ./... 2>&1
    $vetExit = $LASTEXITCODE

    if ($vetExit -eq 0) {
        Write-Result "go vet" "PASS" "No issues found"
    } else {
        Write-Result "go vet" "WARN" "Issues detected"
        $vetOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
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
$skipped = ($script:results | Where-Object { $_.Status -eq "SKIP" } | Measure-Object).Count
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
    Write-Host "  $passed passed, $warned warnings, $failed failed, $skipped skipped (of $total)" -ForegroundColor Yellow
}

Write-Host ""
exit $script:exitCode
