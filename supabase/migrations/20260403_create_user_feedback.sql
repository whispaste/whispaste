CREATE TABLE IF NOT EXISTS user_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  received_at timestamptz DEFAULT now(),
  rating smallint NOT NULL CHECK (rating >= 1 AND rating <= 5),
  feedback_text text,
  app_version text NOT NULL,
  device_id_hash text NOT NULL,
  ip_hash text,
  discord_message_id text,
  status text DEFAULT 'pending'
);

CREATE INDEX IF NOT EXISTS idx_feedback_device ON user_feedback (device_id_hash);
CREATE INDEX IF NOT EXISTS idx_feedback_received ON user_feedback (received_at DESC);
