# Supabase Setup Guide

This guide configures all Supabase Edge Function relays for WhisPaste:

- **Crash Relay** — anonymous crash reports → Discord
- **Feedback Relay** — user feedback (star ratings) → Discord
- **Crash Cleanup** — admin endpoint to manage crash reports

## Architecture

```text
WhisPaste app ──HTTPS──▶ Supabase Edge Functions ──secret──▶ Discord webhooks
                              │
                         Supabase DB
                     (crash_report_events,
                      user_feedback)
```

The app ships only the public relay URLs. Discord webhook secrets stay server-side.

## What gets deployed

| File | Purpose |
|------|---------|
| `supabase/functions/crash-relay/index.ts` | Crash report relay with dedup + rate limiting |
| `supabase/functions/feedback-relay/index.ts` | User feedback relay with IP-based rate limiting |
| `supabase/functions/crash-cleanup/index.ts` | Admin endpoint to manage/delete crash reports |
| `supabase/migrations/20260331_create_crash_report_events.sql` | Crash reports table |
| `supabase/migrations/20260403_create_user_feedback.sql` | User feedback table |
| `supabase/config.toml` | Project configuration |

---

## Initial Setup (one-time)

### Step 1: Create or open your Supabase project

1. Open [supabase.com](https://supabase.com) and create a project (or use an existing one).
2. Copy the project ref from Settings → General, e.g. `cnyniyflnefxrwafuqig`.

### Step 2: Install and log into the Supabase CLI

```powershell
scoop install supabase
supabase login
```

### Step 3: Link the local repo to the Supabase project

From the repository root:

```powershell
supabase link --project-ref YOUR-PROJECT-REF
```

### Step 4: Deploy database migrations

```powershell
supabase db push
```

This creates the `crash_report_events` and `user_feedback` tables.

---

## Crash Reporting Setup

### Step 5a: Create a Discord webhook for crash reports

1. In your Discord server, go to the channel for crash reports.
2. Channel Settings → Integrations → Webhooks → New Webhook.
3. Name it `WhisPaste Crash Reporter` and copy the webhook URL.

### Step 5b: Set the crash webhook secret

```powershell
supabase secrets set CRASH_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/XXXXX/YYYYY"
```

### Step 5c: Set the admin API key (for crash management)

Generate a random key (e.g. `openssl rand -hex 32`) and set it:

```powershell
supabase secrets set ADMIN_API_KEY="your-random-admin-key-here"
```

This key protects the crash-cleanup `fix` and `delete` endpoints.

### Step 5d: Deploy crash functions

```powershell
supabase functions deploy crash-relay --no-verify-jwt
supabase functions deploy crash-cleanup --no-verify-jwt
```

---

## User Feedback Setup

### Step 6a: Create a Discord webhook for feedback

1. In your Discord server, create a **separate** channel for user feedback (e.g. `#user-feedback`).
2. Channel Settings → Integrations → Webhooks → New Webhook.
3. Name it `WhisPaste Feedback` and copy the webhook URL.

### Step 6b: Set the feedback webhook secret

```powershell
supabase secrets set FEEDBACK_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/XXXXX/YYYYY"
```

### Step 6c: Deploy the feedback function

```powershell
supabase functions deploy feedback-relay --no-verify-jwt
```

---

## Build WhisPaste with Relay URLs

Use the build script to inject both relay URLs into the binary:

```powershell
# All on one line:
.\scripts\build.ps1 -Release -Version "1.2.3" -CrashRelayURL "https://YOUR-PROJECT-REF.supabase.co/functions/v1/crash-relay" -FeedbackRelayURL "https://YOUR-PROJECT-REF.supabase.co/functions/v1/feedback-relay"

# Or with line continuation (backtick ` at end of line, NO space after it):
.\scripts\build.ps1 -Release -Version "1.2.3" `
    -CrashRelayURL "https://YOUR-PROJECT-REF.supabase.co/functions/v1/crash-relay" `
    -FeedbackRelayURL "https://YOUR-PROJECT-REF.supabase.co/functions/v1/feedback-relay"
```

Both URLs are public and safe to ship. The Discord webhooks stay server-side.

For a concrete example with the current project ref:

```powershell
.\scripts\build.ps1 -Release -Version "1.2.3" -CrashRelayURL "https://cnyniyflnefxrwafuqig.supabase.co/functions/v1/crash-relay" -FeedbackRelayURL "https://cnyniyflnefxrwafuqig.supabase.co/functions/v1/feedback-relay"
```

---

## Verify Everything Works

### Crash reporting

Expected app log:

```text
Crash reporting: enabled (relay configured)
```

Without `-CrashRelayURL`:

```text
Crash reporting: enabled (local queue only, no relay)
```

### Feedback

The feedback feature appears:
- In the tray menu → "Give Feedback"
- On the About page → "Rate WhisPaste" button
- Auto-prompt after 50 transcriptions (one-time)

Without `-FeedbackRelayURL`, feedback shows "not configured" and is hidden.

---

## Secrets Reference

| Secret | Required for | How to generate |
|--------|-------------|-----------------|
| `CRASH_DISCORD_WEBHOOK_URL` | crash-relay, crash-cleanup | Discord channel webhook URL |
| `FEEDBACK_DISCORD_WEBHOOK_URL` | feedback-relay | Discord channel webhook URL |
| `ADMIN_API_KEY` | crash-cleanup (fix/delete) | `openssl rand -hex 32` |

**Safe to ship in the app** (public):
- Supabase Edge Function URLs (crash-relay, feedback-relay)
- Supabase project URL / project ref

**Must stay server-side only** (never in code or binary):
- `CRASH_DISCORD_WEBHOOK_URL`
- `FEEDBACK_DISCORD_WEBHOOK_URL`
- `ADMIN_API_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

---

## Quick Reference: Deploy All Functions

After making changes, redeploy all functions at once:

```powershell
supabase functions deploy crash-relay --no-verify-jwt
supabase functions deploy crash-cleanup --no-verify-jwt
supabase functions deploy feedback-relay --no-verify-jwt
```

---

## Microsoft Store / App Review Note

This architecture is review-friendly:

- No private webhook secrets are shipped in the client
- All outgoing data goes to HTTPS relay endpoints you control
- Payload validation and abuse protection happen server-side
- Privacy disclosures can accurately point to your own relay endpoint
