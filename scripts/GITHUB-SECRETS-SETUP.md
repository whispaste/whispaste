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
| `MS_STORE_APP_ID` | `release.yml` (submit-ms-store) | Partner Center → app → **Product ID** (e.g. `9P22JVKRQ2V0`) |
| `MS_STORE_TENANT_ID` | `release.yml` (submit-ms-store) | Microsoft Entra admin center → Overview → **Tenant ID** |
| `MS_STORE_CLIENT_ID` | `release.yml` (submit-ms-store) | Entra → App registrations → your app → **Application (client) ID** |
| `MS_STORE_CLIENT_SECRET` | `release.yml` (submit-ms-store) | Entra → App registrations → your app → Certificates & secrets → **client secret value** |

### Microsoft Store auto-submission (AFK)

When the four `MS_STORE_*` secrets above are set, the `submit-ms-store` job in
`release.yml` submits each tagged release to the Microsoft Store **fully
automatically** (no manual step, no Windows box) via the Partner Center
submission API, including the bilingual "What's new" notes. When they are absent
the job logs a warning and skips — so the rest of the release is never blocked.

One-time prerequisites (see `docs/store-release.md` → *Microsoft-Store-Automatisierung*
for the full walkthrough):

1. Register an app in **Microsoft Entra ID** and create a **client secret**.
2. In Partner Center → *Account settings → User management → Microsoft Entra
   applications*, add that app with the **Manager** role.
3. Put `MS_STORE_APP_ID`, `MS_STORE_TENANT_ID`, `MS_STORE_CLIENT_ID`,
   `MS_STORE_CLIENT_SECRET` into `.env`, then run `./scripts/setup-gh-secrets.sh`.

> **Rotation:** Entra client secrets expire (max 24 months). The scheduled
> `ms-store-credential-health.yml` workflow does a weekly test-auth and fails
> loudly (GitHub emails you) **before** a release silently skips. Rotate the
> secret and re-run `setup-gh-secrets.sh` when it warns.

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
