-- Migration: Add category column to user_feedback
--
-- Stores the feedback category as a server-validated enum, replacing the
-- [$category] text prefix previously embedded in feedback_text.
-- This enables proper DB-level filtering, analytics, and CHECK constraints.

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Add category column (nullable so existing rows are not broken)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.user_feedback
  ADD COLUMN IF NOT EXISTS category TEXT
    CHECK (category IN ('bug', 'feature', 'general', 'ai'));

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Update column-level INSERT grant to include category
-- ═══════════════════════════════════════════════════════════════════════════

-- Revoke and re-grant so the allowed-column list is the sole source of truth.
REVOKE ALL ON public.user_feedback FROM anon;

GRANT INSERT (rating, feedback_text, app_version, device_id_hash, category)
  ON public.user_feedback TO anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Replace INSERT policy — require a valid category on every new submission
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "anon_can_insert_feedback" ON public.user_feedback;

CREATE POLICY "anon_can_insert_feedback"
  ON public.user_feedback
  FOR INSERT TO anon
  WITH CHECK (
    rating >= 1 AND rating <= 5
    AND (feedback_text IS NULL OR length(feedback_text) <= 2000)
    AND app_version IS NOT NULL AND length(app_version) <= 20
    AND device_id_hash IS NOT NULL AND length(device_id_hash) = 12
    AND category IS NOT NULL AND category IN ('bug', 'feature', 'general', 'ai')
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Update daily summary view with category breakdown
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.feedback_daily_summary AS
SELECT
  date_trunc('day', received_at)::date AS day,
  COUNT(*)::int                         AS total,
  AVG(rating)::numeric(3, 2)            AS avg_rating,
  COUNT(*) FILTER (WHERE rating >= 4)::int AS positive,
  COUNT(*) FILTER (WHERE rating <= 2)::int AS negative,
  COUNT(*) FILTER (WHERE rating = 3)::int  AS neutral,
  COUNT(*) FILTER (WHERE category = 'bug')::int     AS bugs,
  COUNT(*) FILTER (WHERE category = 'feature')::int AS features,
  COUNT(*) FILTER (WHERE category = 'general')::int AS general,
  COUNT(*) FILTER (WHERE category = 'ai')::int      AS ai_quality
FROM public.user_feedback
GROUP BY day
ORDER BY day DESC;
