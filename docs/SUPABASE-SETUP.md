# Supabase Crash Relay Setup

This guide configures WhisPaste crash reporting through a Supabase Edge Function relay.

## Goal

Use this production-safe flow:

```text
WhisPaste app -> Supabase Edge Function -> Discord webhook
```

The app ships only the public relay URL. The Discord webhook stays server-side as a Supabase secret.

## What gets deployed

- `supabase/functions/crash-relay/index.ts`
- `supabase/migrations/20260331_create_crash_report_events.sql`
- `supabase/config.toml`

## 1. Create or open your Supabase project

1. Open Supabase.
2. Create a project or use an existing one.
3. Copy the project URL, e.g.:

```text
https://YOUR-PROJECT-REF.supabase.co
```

## 2. Install and log into the Supabase CLI

```powershell
npm install -g supabase
supabase login
```

## 3. Link the local repo to the Supabase project

From the repository root:

```powershell
supabase link --project-ref YOUR-PROJECT-REF
```

## 4. Set the Discord webhook as a Supabase secret

```powershell
supabase secrets set CRASH_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."
```

The webhook URL never belongs in the app, in `.env`, or in source control.

## 5. Deploy the database migration

```powershell
supabase db push
```

This creates `public.crash_report_events`, which the relay uses for:

- deduplication
- rate limiting
- audit / delivery status

## 6. Deploy the Edge Function

```powershell
supabase functions deploy crash-relay --no-verify-jwt
```

Public endpoint:

```text
https://YOUR-PROJECT-REF.supabase.co/functions/v1/crash-relay
```

## 7. Build WhisPaste with the public relay URL

Use the existing PowerShell build script:

```powershell
.\scripts\build.ps1 -Release -Version "1.2.3" -CrashRelayURL "https://YOUR-PROJECT-REF.supabase.co/functions/v1/crash-relay"
```

This injects the public relay URL into the binary via `-ldflags`.

## 8. Verify the relay

Expected app log message:

```text
Crash reporting: enabled (relay configured)
```

Expected relay behavior:

- accepts JSON crash payloads from the app
- validates payload size and required fields
- rate-limits by device/IP window
- deduplicates repeated crashes within one hour
- stores delivery metadata in Supabase
- posts the final embed to Discord

## Secrets vs public values

Safe to ship in the app:

- Supabase Edge Function URL

Must stay server-side only:

- `CRASH_DISCORD_WEBHOOK_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

## Microsoft Store / App Review note

This setup is much safer and more review-friendly than embedding a Discord webhook in the app because:

- no private webhook secret is shipped in the client
- all outgoing crash reports go to a single HTTPS relay you control
- payload validation and abuse protection happen server-side
- privacy disclosures can accurately point to your own relay endpoint

## Recommended next hardening

- add a short Privacy Policy section that names Supabase as the relay processor
- add a relay health check in CI or release validation
- add alerting on repeated `discord_failed` rows in `crash_report_events`
