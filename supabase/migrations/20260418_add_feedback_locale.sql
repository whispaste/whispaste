-- Migration: Add locale column to user_feedback
--
-- Stores the app language in use when the feedback was submitted (e.g. 'de',
-- 'en'). Allows the website and admin tooling to display feedback in the
-- correct language context.

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Add locale column (nullable so existing rows are not broken)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.user_feedback
  ADD COLUMN IF NOT EXISTS locale TEXT
    CHECK (locale IS NULL OR (length(locale) >= 2 AND length(locale) <= 10));

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Update column-level INSERT grant to include locale
-- ═══════════════════════════════════════════════════════════════════════════

REVOKE ALL ON public.user_feedback FROM anon;

GRANT INSERT ON public.user_feedback TO anon;
GRANT INSERT (rating, feedback_text, app_version, device_id_hash, category, locale)
  ON public.user_feedback TO anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Replace INSERT policy — allow locale (optional, validated server-side)
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "anon_can_insert_feedback" ON public.user_feedback;

CREATE POLICY "anon_can_insert_feedback"
  ON public.user_feedback
  FOR INSERT TO anon
  WITH CHECK (
    rating >= 1 AND rating <= 5
    AND (feedback_text IS NULL OR length(feedback_text) <= 1000)
    AND app_version IS NOT NULL AND length(app_version) <= 20
    AND device_id_hash IS NOT NULL AND length(device_id_hash) = 12
    AND category IS NOT NULL AND category IN ('bug', 'feature', 'general', 'ai')
    AND (locale IS NULL OR (length(locale) >= 2 AND length(locale) <= 10))
  );
