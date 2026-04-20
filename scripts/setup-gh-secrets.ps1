# WhisPaste GitHub Secrets Setup (Windows PowerShell)
# This script sets up all required GitHub secrets for CI/CD workflows
# Reads from .env and sets each secret on GitHub via 'gh secret set'
# Run: .\scripts\setup-gh-secrets.ps1

param(
    [string]$SecretsFile = ".env"
)

$repo = "whispaste/whispaste"
$green = "`e[32m"
$yellow = "`e[33m"
$reset = "`e[0m"

Write-Host "${yellow}WhisPaste GitHub Secrets Setup${reset}"
Write-Host "Repository: $repo"
Write-Host ""

# Check GitHub CLI auth
$authCheck = & gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "${yellow}GitHub CLI not authenticated. Run: gh auth login${reset}"
    exit 1
}

Write-Host "${green}✓ GitHub CLI authenticated${reset}"
Write-Host ""

# Function to set secret
function Set-GitHubSecret {
    param(
        [string]$Name,
        [string]$Value,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Host "${yellow}⊘ Skipped $Name (empty value)${reset}"
        return
    }

    $Value | gh secret set $Name --repo $repo
    Write-Host "${green}✓ Set $Name${reset}"
}

# Load from .env if it exists
if (Test-Path $SecretsFile) {
    Write-Host "Loading secrets from $SecretsFile"
    Write-Host ""

    $content = Get-Content $SecretsFile
    foreach ($line in $content) {
        # Skip comments and empty lines
        if ($line.StartsWith("#") -or [string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        # Parse KEY=VALUE
        if ($line -match "^([^=]+)=(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            Set-GitHubSecret -Name $key -Value $value
        }
    }
} else {
    Write-Host "${yellow}.env not found. Prompting for values:${reset}"
    Write-Host ""

    $sentryToken = Read-Host "SENTRY_AUTH_TOKEN"
    Set-GitHubSecret -Name "SENTRY_AUTH_TOKEN" -Value $sentryToken

    $supabaseUrl = Read-Host "SUPABASE_URL"
    Set-GitHubSecret -Name "SUPABASE_URL" -Value $supabaseUrl

    $supabaseKey = Read-Host "SUPABASE_PUBLISHABLE_KEY"
    Set-GitHubSecret -Name "SUPABASE_PUBLISHABLE_KEY" -Value $supabaseKey
}

Write-Host ""
Write-Host "${green}GitHub secrets setup complete!${reset}"
Write-Host ""
Write-Host "Verify secrets:"
gh secret list --repo $repo
