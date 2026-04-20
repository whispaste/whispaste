# GitHub Secrets Setup for WhisPaste

GitHub Secrets are required for CI/CD workflows (Sentry release tracking, Supabase integration, etc.).

## Setup Instructions

### 1. Authenticate with GitHub CLI

```bash
gh auth login
```

Follow the prompts. You'll need a GitHub Personal Access Token with `repo` + `workflow` scopes, or use browser-based OAuth.

### 2. Prepare `.env`

Your local `.env` file already exists (gitignored). It contains all secrets needed for CI/CD:

```bash
# .env already exists from .env.example
cat .env
```

Edit `.env` with your real Sentry Auth Token and Supabase credentials if you haven't already.

### 3. Set Secrets on GitHub

Choose your platform:

**macOS / Linux:**
```bash
./scripts/setup-gh-secrets.sh
```

**Windows PowerShell:**
```powershell
.\scripts\setup-gh-secrets.ps1
```

**Cross-platform (Python):**
```bash
python3 scripts/setup-gh-secrets.py
```

All three scripts load from `.env` and set secrets on GitHub.

### 4. Verify

```bash
gh secret list
```

or

```bash
python3 scripts/setup-gh-secrets.py --list
```

## What Each Secret Does

| Secret | Used By | Source |
|--------|---------|--------|
| `SENTRY_DSN` | `lib/core/logging/app_monitoring.dart` | Sentry Project Settings → Client Keys (DSN) |
| `SUPABASE_URL` | `.github/workflows/ci.yml` | Supabase Dashboard → Project Settings → API |
| `SUPABASE_PUBLISHABLE_KEY` | `.github/workflows/ci.yml` | Supabase Dashboard → Project Settings → API Keys |

## Local vs GitHub Secrets

**Local `.env`** — Development (never committed):
- `flutter run` uses these values
- Add to `.env` for local testing
- Required for local app to connect to services

**GitHub Secrets** — CI/CD (set via `gh secret set`):
- Used by GitHub Actions workflows
- Private, encrypted on GitHub
- Not visible in logs or exported environment
- Set once per repo, persists

## Troubleshooting

**"GitHub CLI not authenticated"**
```bash
gh auth login
```

**"Repository not found"**
Make sure you're in the `whispaste/whispaste` directory and have access.

**List secrets:**
```bash
gh secret list
```

**Update a secret:**
```bash
python3 scripts/setup-gh-secrets.py
# or
gh secret set SECRET_NAME -b "new value"
```

**Delete a secret:**
```bash
gh secret delete SECRET_NAME
```
