-- Security hardening: add audit columns for crash fix tracking
-- Supports T08 (fix action validation + audit trail)

ALTER TABLE crash_report_events
  ADD COLUMN IF NOT EXISTS fixed_at TIMESTAMPTZ DEFAULT NULL;

-- Index for Discord posting rate limit queries (T06)
CREATE INDEX IF NOT EXISTS idx_crash_events_status_received
  ON crash_report_events (status, received_at)
  WHERE status = 'sent';

-- Index for feedback Discord rate limit queries (T06)
CREATE INDEX IF NOT EXISTS idx_feedback_status_received
  ON user_feedback (status, received_at)
  WHERE status = 'sent';
