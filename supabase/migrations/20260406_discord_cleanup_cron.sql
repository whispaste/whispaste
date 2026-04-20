-- Move Discord cleanup scheduling from GitHub Actions to Supabase pg_cron.
-- This replaces .github/workflows/discord-cleanup.yml entirely.
--
-- ┌───────────────────────────────────────────────────────────────────┐
-- │  ONE-TIME SETUP (after applying this migration):                 │
-- │                                                                  │
-- │  Store the ADMIN_API_KEY in Supabase Vault via SQL Editor:       │
-- │                                                                  │
-- │    SELECT vault.create_secret(                                   │
-- │      '<your-admin-api-key>',                                     │
-- │      'admin_api_key',                                            │
-- │      'Admin API key for crash-cleanup Edge Function auth'        │
-- │    );                                                            │
-- │                                                                  │
-- │  Verify:                                                         │
-- │    SELECT name FROM vault.decrypted_secrets                      │
-- │      WHERE name = 'admin_api_key';                               │
-- └───────────────────────────────────────────────────────────────────┘

-- Schedule weekly Discord cleanup: Sunday 03:00 UTC
-- Identical schedule to the previous GitHub Action cron trigger.
-- Calls the crash-cleanup Edge Function's ?action=cleanup endpoint
-- which deletes Discord messages for dismissed/fixed crash reports
-- and expired feedback (90-day retention).
SELECT cron.schedule(
  'discord-cleanup-weekly',
  '0 3 * * 0',
  $$
  SELECT net.http_get(
    url := 'https://cnyniyflnefxrwafuqig.supabase.co/functions/v1/crash-cleanup',
    params := '{"action": "cleanup", "retention_days": "90"}'::jsonb,
    headers := jsonb_build_object(
      'x-api-key', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'admin_api_key'),
      'Content-Type', 'application/json'
    ),
    timeout_milliseconds := 120000
  ) AS request_id;
  $$
);

-- To check the job:    SELECT * FROM cron.job WHERE jobname = 'discord-cleanup-weekly';
-- To run manually:     SELECT cron.schedule('discord-cleanup-now', 'NOW', $$ ... same SQL ... $$);
-- To unschedule:       SELECT cron.unschedule('discord-cleanup-weekly');
-- To check results:    SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 5;
