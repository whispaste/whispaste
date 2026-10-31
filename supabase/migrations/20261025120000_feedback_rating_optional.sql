-- ═══════════════════════════════════════════════════════════════════════════
-- Feedback rating becomes optional on the server (FB-03).
--
-- The feedback form may send no star rating. The server must accept that
-- before the app ships the optional form. Until then the app still sends a
-- rating, so this migration changes nothing for existing clients.
--
-- Changes (additive only, no data change):
--   1. rating may be NULL. The CHECK (rating >= 1 AND rating <= 5) already
--      accepts NULL, so it stays as it is.
--   2. The anon insert policy accepts NULL rating or a value in 1..5. Every
--      other condition is copied unchanged from 20260717_add_feedback_contact_email.
--   3. The publish gate (rating >= 4 OR curated_text IS NOT NULL) already
--      treats NULL as "not publishable", so it is not touched.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.user_feedback ALTER COLUMN rating DROP NOT NULL;

DROP POLICY IF EXISTS "anon_can_insert_feedback" ON public.user_feedback;

CREATE POLICY "anon_can_insert_feedback"
  ON public.user_feedback
  FOR INSERT TO anon
  WITH CHECK (
    (rating IS NULL OR (rating >= 1 AND rating <= 5))
    AND (feedback_text IS NULL OR length(feedback_text) <= 1000)
    AND app_version IS NOT NULL AND length(app_version) <= 20
    AND device_id_hash IS NOT NULL AND length(device_id_hash) = 12
    AND category IS NOT NULL AND category IN ('bug', 'feature', 'general', 'ai')
    AND (locale IS NULL OR (length(locale) >= 2 AND length(locale) <= 10))
    AND (
      contact_email IS NULL
      OR (length(contact_email) <= 254
          AND contact_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
    )
    AND (
      contact_locale IS NULL
      OR (length(contact_locale) >= 2 AND length(contact_locale) <= 10)
    )
  );
