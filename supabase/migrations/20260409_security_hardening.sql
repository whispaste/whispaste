-- Security hardening: add audit columns for crash fix tracking
-- Supports T08 (fix action validation + audit trail)

ALTER TABLE crash_report_events
  ADD COLUMN IF NOT EXISTS fixed_at TIMESTAMPTZ DEFAULT NULL;

-- Schema cleanup: go_version → runtime_version (T11)
-- Keep old column as alias for backward compat with in-flight reports
ALTER TABLE crash_report_events
  ADD COLUMN IF NOT EXISTS runtime_version TEXT DEFAULT NULL;

-- Backfill runtime_version from go_version for existing rows
UPDATE crash_report_events
  SET runtime_version = payload->>'go_version'
  WHERE runtime_version IS NULL
    AND payload->>'go_version' IS NOT NULL;

-- Index for Discord posting rate limit queries (T06)
CREATE INDEX IF NOT EXISTS idx_crash_events_status_received
  ON crash_report_events (status, received_at)
  WHERE status = 'sent';

-- Index for feedback Discord rate limit queries (T06)
CREATE INDEX IF NOT EXISTS idx_feedback_status_received
  ON user_feedback (status, received_at)
  WHERE status = 'sent';
