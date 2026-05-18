# MS Store Listing Content

Store listing texts for WhisPaste. Checked into the repo so changes are versioned
and deployed automatically on every `v*` tag push.

## Structure

```
store/
  en-US/description.txt   EN product description (Partner Center → "Description")
  en-US/features.txt      EN feature bullets, one per line (max 200 chars each)
  de-DE/description.txt   DE product description
  de-DE/features.txt      DE feature bullets
```

"What's new" is injected automatically from the AI-generated release notes
(`release-notes-en.md` / `release-notes-de.md`) produced by
`scripts/generate-release-notes.mjs` during the release workflow.

## Automation

`scripts/submit-ms-store.ps1` submits via Partner Center Submission API.
Called by the `submit-ms-store` job in `.github/workflows/release.yml`.

### Required GitHub Secrets

| Secret                  | Value                                          |
|-------------------------|------------------------------------------------|
| `MS_STORE_APP_ID`       | `9P22JVKRQ2V0`                                 |
| `MS_STORE_TENANT_ID`    | Azure AD tenant ID (from Partner Center Users) |
| `MS_STORE_CLIENT_ID`    | App registration Client ID                     |
| `MS_STORE_CLIENT_SECRET`| App registration client secret                 |

### One-time Azure AD setup

1. partner.microsoft.com → Account settings → Users → Azure AD applications
2. Add Azure AD application → role: Manager
3. Add a new client secret → copy immediately
4. Add the four values above as GitHub repo secrets
