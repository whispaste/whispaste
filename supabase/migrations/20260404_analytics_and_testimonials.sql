-- Analytics views for crash and feedback aggregation
-- + Testimonials pipeline columns + Discord cleanup tracking

-- ─── Crash pattern aggregation ───────────────────────────────────
CREATE OR REPLACE VIEW public.crash_patterns AS
SELECT
  message_hash,
  COUNT(*)::int AS occurrence_count,
  MIN(received_at) AS first_seen,
  MAX(received_at) AS last_seen,
  array_agg(DISTINCT app_version ORDER BY app_version) AS affected_versions,
  bool_or(dismissed) AS is_dismissed,
  MAX(fixed_in_version) AS fixed_in_version,
  COUNT(DISTINCT device_id)::int AS unique_devices,
  -- Extract crash title from first payload for display
  (array_agg(payload->'report'->>'message' ORDER BY received_at DESC))[1] AS latest_message,
  (array_agg(payload->'report'->>'severity' ORDER BY received_at DESC))[1] AS severity
FROM public.crash_report_events
GROUP BY message_hash;

-- ─── Daily crash summary ─────────────────────────────────────────
CREATE OR REPLACE VIEW public.crash_daily_summary AS
SELECT
  date_trunc('day', received_at)::date AS day,
  COUNT(*)::int AS total,
  COUNT(*) FILTER (WHERE NOT dismissed)::int AS active,
  COUNT(*) FILTER (WHERE dismissed)::int AS dismissed,
  COUNT(DISTINCT message_hash)::int AS unique_hashes,
  COUNT(DISTINCT device_id)::int AS unique_devices
FROM public.crash_report_events
GROUP BY day
ORDER BY day DESC;

-- ─── Feedback summary by day ─────────────────────────────────────
CREATE OR REPLACE VIEW public.feedback_daily_summary AS
SELECT
  date_trunc('day', received_at)::date AS day,
  COUNT(*)::int AS total,
  AVG(rating)::numeric(3,2) AS avg_rating,
  COUNT(*) FILTER (WHERE rating >= 4)::int AS positive,
  COUNT(*) FILTER (WHERE rating <= 2)::int AS negative,
  COUNT(*) FILTER (WHERE rating = 3)::int AS neutral
FROM public.user_feedback
GROUP BY day
ORDER BY day DESC;

-- ─── Testimonials pipeline ───────────────────────────────────────
-- Admin can approve high-rating feedback for public display
ALTER TABLE public.user_feedback
  ADD COLUMN IF NOT EXISTS approved_for_display boolean DEFAULT false;

-- Index for fast public testimonial queries
CREATE INDEX IF NOT EXISTS idx_feedback_approved
  ON public.user_feedback (approved_for_display, rating DESC)
  WHERE approved_for_display = true AND rating >= 4;

-- ─── Discord cleanup tracking ────────────────────────────────────
ALTER TABLE public.crash_report_events
  ADD COLUMN IF NOT EXISTS discord_cleaned_at timestamptz;
ALTER TABLE public.user_feedback
  ADD COLUMN IF NOT EXISTS discord_cleaned_at timestamptz;

-- ─── Revoke public access to views ──────────────────────────────
REVOKE ALL ON public.crash_patterns FROM anon, authenticated;
REVOKE ALL ON public.crash_daily_summary FROM anon, authenticated;
REVOKE ALL ON public.feedback_daily_summary FROM anon, authenticated;
