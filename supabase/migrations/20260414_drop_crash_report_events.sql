-- Drop orphaned crash_report_events table.
-- Crash reporting migrated to Sentry in v1.2.0; the crash-relay Edge Function
-- was deleted. This table receives no writes and can be safely removed.

-- Fully idempotent: guard every statement behind an existence check.
-- DROP POLICY IF EXISTS and REVOKE raise 42P01 when the TABLE doesn't exist,
-- even though they have their own IF EXISTS / permissive semantics.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname = 'public' AND tablename = 'crash_report_events'
  ) THEN
    DROP POLICY IF EXISTS "deny_all_crash_report_events" ON crash_report_events;
    REVOKE ALL ON crash_report_events FROM anon, authenticated;
    DROP TABLE crash_report_events;
  END IF;
END $$;
