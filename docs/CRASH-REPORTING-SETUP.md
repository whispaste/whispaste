# Crash Reporting Setup Guide

WhisPaste includes an optional crash reporter that sends anonymous error reports to a Discord channel via webhook. This guide walks you through setting it up.

> **Important:** A raw Discord webhook URL is a secret. Do **not** ship it inside a production desktop app. Use direct webhook access only for local development or self-hosted internal builds. For public releases (including Microsoft Store), route reports through a small HTTPS relay that keeps the real Discord webhook on the server side.

## Overview

| Feature | Detail |
|---------|--------|
| **Transport** | Discord webhook (HTTPS POST) or production relay |
| **Storage** | Local SQLite queue (`crash_queue.db`) |
| **Privacy** | Anonymous — no personal data, transcriptions, or API keys |
| **Default** | Enabled (opt-out via Settings → About → Error Reporting) |
| **Rate limit** | Max 20 reports/hour |
| **Retention** | Queued reports auto-deleted after 30 days |
| **Offline** | Reports queued locally and sent when connectivity returns |

## Step 1: Create a Discord Server (or use an existing one)

1. Open Discord (desktop or web)
2. Click the **+** button in the server sidebar → **Create My Own**
3. Choose **For me and my friends** → name it e.g. `WhisPaste Ops`
4. Create a channel named `#crash-reports`

## Step 2: Create a Webhook

1. Right-click the `#crash-reports` channel → **Edit Channel**
2. Go to **Integrations** → **Webhooks**
3. Click **New Webhook**
4. Name it `WhisPaste Crash Reporter`
5. (Optional) Upload the WhisPaste icon as the webhook avatar
6. Click **Copy Webhook URL** — it looks like:
   ```
   https://discord.com/api/webhooks/1234567890/ABCDefgh...
   ```
7. Click **Save Changes**

## Step 3: Configure WhisPaste

You have two options to provide the webhook URL. Choose one:

### Option A: `.env` / Environment Variable (recommended for development)

Set the `WHISPASTE_CRASH_WEBHOOK` environment variable:

**PowerShell (current session):**
```powershell
$env:WHISPASTE_CRASH_WEBHOOK = "https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
```

**Permanently (user-level):**
```powershell
[System.Environment]::SetEnvironmentVariable("WHISPASTE_CRASH_WEBHOOK", "https://discord.com/api/webhooks/YOUR_WEBHOOK_URL", "User")
```

**Project-local `.env` file:**
```dotenv
WHISPASTE_CRASH_WEBHOOK=https://discord.com/api/webhooks/YOUR_WEBHOOK_URL
```

WhisPaste loads this value automatically at startup in local/dev environments.

### Option B: Config file (self-hosted installs only)

Create a file named `crash_webhook.txt` in the WhisPaste config directory:

```
%APPDATA%\WhisPaste\crash_webhook.txt
```

The file should contain **only** the webhook URL on a single line:

```powershell
# Create the file:
Set-Content -Path "$env:APPDATA\WhisPaste\crash_webhook.txt" -Value "https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
```

> **Security note:** The webhook URL is a secret — anyone with it can post to your channel. Never commit it to source control. The file has user-only read permissions, but this is still **not** appropriate for mass-distributed public builds.

### Option C: Production relay (recommended for public releases / Microsoft Store)

For public releases, use this flow instead:

```
WhisPaste app  ->  HTTPS relay endpoint  ->  Discord webhook
```

The app should only know the relay URL. The relay keeps the real Discord webhook secret server-side and can also enforce:

- payload validation
- rate limiting
- request size limits
- abuse protection
- IP-based throttling
- server-side deduplication

Good low-complexity options:

- Cloudflare Worker
- Supabase Edge Function
- Vercel Serverless Function

This is the recommended setup for Microsoft Store distribution because secrets are not embedded in the client.

## Step 4: Verify It Works

1. Start WhisPaste
2. Check the log file (`%APPDATA%\WhisPaste\whispaste.log`) for:
   ```
   Crash reporting: enabled (webhook configured)
   ```
3. If the webhook is missing or unreachable, you'll see:
   ```
   Crash reporting: enabled (local queue only, no webhook)
   ```

To trigger a test report, you can temporarily add a `logError()` call, or simply wait for a real error to occur. Reports are batched and sent every 60 seconds.

## Step 5: Reading Crash Reports in Discord

Each crash report appears as a Discord embed with:

| Field | Description |
|-------|-------------|
| **Title** | Error message (sanitized) |
| **Type** | `error`, `panic`, or `subprocess_crash` |
| **Severity** | `error`, `critical`, or `warning` |
| **Version** | e.g. `1.2.3` |
| **Build** | Short commit hash for exact build identification |
| **OS / Arch** | e.g. `windows / amd64` |
| **Go Version** | e.g. `go1.26` |
| **Device** | Anonymous 12-char hash (groups crashes from one machine) |
| **GPU** | Selected GPU acceleration mode |
| **Runtime Config** | Sanitized snapshot of active profile, STT/LLM provider, model, language, VAD, audio device, update channel |
| **Stack Trace** | Sanitized call stack (paths anonymized) |

## How Privacy Is Ensured

The crash reporter applies multiple layers of sanitization before sending:

1. **API key patterns** (`sk-`, `gsk_`, `api_key=`, `token=`, `password=`, `Authorization:`) → message replaced with `[REDACTED]`
2. **User paths** (`C:\Users\YourName\...`) → replaced with `<home>`
3. **Username / app-data paths** → replaced with `<user>` / `<appdata>`
4. **Runtime snapshot is allow-list based** — only selected technical settings are included
5. **Deduplication** — identical errors within 1 hour are sent only once
6. **Rate limiting** — max 20 reports per hour
7. **No transcription content** — audio and text data never enter the crash pipeline

## Architecture

```
logError() ──async──▶ captureError()
                          │
                     ┌────▼────┐
                     │ SQLite  │  crash_queue.db (offline buffer)
                     │  Queue  │  max 500 items, 30-day TTL
                     └────┬────┘
                          │ every 60s
                     ┌────▼────┐
                     │ Sender  │  checks network, rate limit, dedup
                     │  Loop   │  2s delay between Discord POSTs
                     └────┬────┘
                          │
                     ┌────▼────┐
                     │ Discord │  webhook POST with embed
                     │ Channel │
                     └─────────┘
```

### Recommended production architecture

```
logError() ──async──▶ captureError() ──▶ local SQLite queue
                                      │
                                      └──▶ HTTPS relay (public endpoint)
                                              │ server-side secret
                                              ▼
                                           Discord webhook
```

This keeps the Discord webhook out of the shipped app while preserving the same queueing and privacy behavior on the client.

## Disabling Crash Reporting

Users can disable crash reporting at any time:

- **In the app:** Settings → About → toggle "Anonymous error reporting" off
- **During onboarding:** Uncheck "Help improve WhisPaste" on the final setup page
- **In config.json:** Set `"error_reporting_enabled": false`

When disabled, no reports are queued or sent. Existing queued reports are not sent until re-enabled.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "local queue only, no webhook" in log | Webhook URL not found | Check `crash_webhook.txt` path or env var |
| Reports not appearing in Discord | Rate limited or network issue | Wait 60s, check network. Max 20/hour. |
| Reports stop after a while | Queue full (500 max) | Old reports auto-pruned after 30 days |
| `Crash reporter DB init failed` | SQLite issue | Check disk space / permissions in `%APPDATA%\WhisPaste\` |
