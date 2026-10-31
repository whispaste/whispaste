-- Unschedule the Discord cleanup cron job.
-- The crash-cleanup Edge Function was removed in the Sentry migration.
-- Crash reporting now uses Sentry (no Discord integration).
SELECT cron.unschedule('discord-cleanup-weekly');
