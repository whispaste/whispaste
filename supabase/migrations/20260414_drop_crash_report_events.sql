-- Drop orphaned crash_report_events table.
-- Crash reporting migrated to Sentry in v1.2.0; the crash-relay Edge Function
-- was deleted. This table receives no writes and can be safely removed.

-- First drop dependent policies and triggers
DROP POLICY IF EXISTS "deny_all_crash_report_events" ON crash_report_events;

-- Revoke any remaining grants
REVOKE ALL ON crash_report_events FROM anon, authenticated;

-- Drop the table
DROP TABLE IF EXISTS crash_report_events;
