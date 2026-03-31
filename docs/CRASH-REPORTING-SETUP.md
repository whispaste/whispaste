# Crash Reporting Setup Guide

WhisPaste now sends anonymous crash reports through a **Supabase Edge Function relay**. The app no longer reads a Discord webhook from `.env`, environment variables, or `crash_webhook.txt`.

Use `docs/SUPABASE-SETUP.md` to deploy the relay infrastructure. This document explains how the WhisPaste client side behaves once the relay exists.

## Overview

| Feature | Detail |
|---------|--------|
| **Transport** | Supabase Edge Function relay (HTTPS POST) |
| **Storage** | Local SQLite queue (`crash_queue.db`) |
| **Privacy** | Anonymous — no personal data, transcriptions, or API keys |
| **Default** | Enabled (opt-out via Settings → About → Error Reporting) |
| **Rate limit** | Relay-side throttling + client-side hourly cap |
| **Retention** | Queued reports auto-deleted after 30 days |
| **Offline** | Reports queued locally and sent when connectivity returns |

## Step 1: Deploy the Supabase relay

Follow:

```text
docs/SUPABASE-SETUP.md
```

After deployment, you will have a public relay endpoint like:

```text
https://YOUR-PROJECT-REF.supabase.co/functions/v1/crash-relay
```

## Step 2: Build WhisPaste with the relay URL

Use the build script and inject the public relay URL:

```powershell
.\scripts\build.ps1 -Release -Version "1.2.3" -CrashRelayURL "https://YOUR-PROJECT-REF.supabase.co/functions/v1/crash-relay"
```

The relay URL is public and safe to ship in the app. The real Discord webhook stays server-side as a Supabase secret.

## Step 3: Verify It Works

1. Start WhisPaste
2. Check the log file (`%APPDATA%\WhisPaste\whispaste.log`) for:
   ```
   Crash reporting: enabled (relay configured)
   ```
3. If the build did not include a relay URL, you'll see:
   ```
   Crash reporting: enabled (local queue only, no relay)
   ```

To trigger a test report, temporarily add a `logError()` call or wait for a real error. The app keeps retrying from the local queue.

## Step 4: Reading Crash Reports in Discord

Each crash report appears as a Discord embed with:

| Field | Description |
|-------|-------------|
| **Title** | Error message (sanitized) |
| **Version** | e.g. `1.2.3` |
| **Build** | Short commit hash for exact build identification |
| **OS / Arch** | e.g. `windows / amd64` |
| **Go Version** | e.g. `go1.26` |
| **Device** | Anonymous 12-char hash (groups crashes from one machine) |
| **GPU** | Selected GPU acceleration mode |
| **Runtime Config** | Sanitized snapshot of active profile, STT/LLM provider, model, language, VAD, audio device, update channel |
| **Stack Trace** | Sanitized call stack (paths anonymized) |

## How Privacy Is Ensured

The client and relay apply multiple layers of sanitization and abuse protection:

1. **API key patterns** (`sk-`, `gsk_`, `api_key=`, `token=`, `password=`, `Authorization:`) → message replaced with `[REDACTED]`
2. **User paths** (`C:\Users\YourName\...`) → replaced with `<home>`
3. **Username / app-data paths** → replaced with `<user>` / `<appdata>`
4. **Runtime snapshot is allow-list based** — only selected technical settings are included
5. **Relay-side deduplication** — repeated crashes are dropped within the configured time window
6. **Relay-side rate limiting** — the relay throttles abusive or noisy clients
7. **No transcription content** — audio and text data never enter the crash pipeline

## Architecture

```text
logError() ──async──▶ captureError()
                          │
                     ┌────▼────┐
                     │ SQLite  │  crash_queue.db (offline buffer)
                     │  Queue  │
                     └────┬────┘
                          │ every 60s
                     ┌────▼────┐
                     │ Relay   │  public HTTPS endpoint
                     │ Client  │
                     └────┬────┘
                          │
                     ┌────▼─────────────┐
                     │ Supabase Relay   │  validates, rate-limits, dedups
                     └────┬─────────────┘
                          │ server-side secret
                     ┌────▼────┐
                     │ Discord │
                     │ Channel │
                     └─────────┘
```

## Disabling Crash Reporting

Users can disable crash reporting at any time:

- **In the app:** Settings → About → toggle "Anonymous error reporting" off
- **During onboarding:** Uncheck "Help improve WhisPaste" on the final setup page
- **In config.json:** Set `"error_reporting_enabled": false`

When disabled, no reports are queued or sent. Existing queued reports remain local until reporting is re-enabled.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "local queue only, no relay" in log | Relay URL not injected at build time | Rebuild with `-CrashRelayURL` |
| Reports not appearing in Discord | Relay rejected or webhook secret missing | Check Supabase function logs and secrets |
| Reports stop after a while | Relay rate limiting or queue full | Check `crash_report_events` and app log |
| `Crash reporter DB init failed` | SQLite issue | Check disk space / permissions in `%APPDATA%\WhisPaste\` |
| Relay returns 500 | Supabase secret or migration missing | Run `supabase db push` and `supabase secrets set` again |
