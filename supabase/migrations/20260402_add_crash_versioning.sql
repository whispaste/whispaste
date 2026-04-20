-- Add version tracking columns to crash_report_events
ALTER TABLE crash_report_events ADD COLUMN IF NOT EXISTS dismissed boolean DEFAULT false;
ALTER TABLE crash_report_events ADD COLUMN IF NOT EXISTS fixed_in_version text;
ALTER TABLE crash_report_events ADD COLUMN IF NOT EXISTS build_commit text;

-- Index for quick lookup of known-fixed crashes by hash
CREATE INDEX IF NOT EXISTS idx_crash_fixed_hash ON crash_report_events (message_hash) WHERE fixed_in_version IS NOT NULL;
