-- Migration: Optional contact email + preferred contact language on feedback
--
-- Lets a user optionally leave an email address (so we can follow up on
-- their specific feedback) and a preferred language to be contacted in.
-- Both are nullable and validated server-side; anon can INSERT them but
-- never SELECT them back (no read grant added — same insert-only contract
-- as the rest of the table). public_testimonials / feedback_daily_summary
-- use explicit column lists (never SELECT *), so neither new column is
-- reachable through those views — no change needed there.
--
-- Privacy minimization: the existing 90-day archival CRON (20260417) already
-- deletes unapproved feedback, but keeps approved (`approved_for_display =
-- true`) rows indefinitely for the testimonials feature. Extend that same
-- job to additionally scrub contact_email/contact_locale (NULL them out) on
-- approved rows once they age past 90 days — the testimonial text/rating is
-- kept forever, the submitter's contact info is not.

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Add columns (nullable so existing rows are not broken)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.user_feedback
  ADD COLUMN IF NOT EXISTS contact_email TEXT
    CHECK (
      contact_email IS NULL
      OR (length(contact_email) <= 254
          AND contact_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
    );

ALTER TABLE public.user_feedback
  ADD COLUMN IF NOT EXISTS contact_locale TEXT
    CHECK (
      contact_locale IS NULL
      OR (length(contact_locale) >= 2 AND length(contact_locale) <= 10)
    );

COMMENT ON COLUMN public.user_feedback.contact_email IS
  'Optional, user-volunteered — only for following up on this feedback. '
  'Insert-only for anon (no SELECT grant); scrubbed after 90 days even on '
  'approved/testimonial rows, see feedback-archival-daily cron below.';

COMMENT ON COLUMN public.user_feedback.contact_locale IS
  'Optional language the submitter prefers to be contacted in (e.g. "de", '
  '"en") — distinct from [locale], which is the app UI language at submit '
  'time. Same insert-only + 90-day scrub contract as contact_email.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Update column-level INSERT grant — anon may write but never read these
-- ═══════════════════════════════════════════════════════════════════════════

REVOKE ALL ON public.user_feedback FROM anon;

GRANT INSERT ON public.user_feedback TO anon;
GRANT INSERT (
  rating, feedback_text, app_version, device_id_hash, category, locale,
  contact_email, contact_locale
) ON public.user_feedback TO anon;

-- Re-apply the existing SELECT grant (20260612) — REVOKE ALL above cleared
-- it too, and it must stay scoped to exactly the testimonials-view columns.
GRANT SELECT (rating, feedback_text, received_at, approved_for_display)
  ON public.user_feedback TO anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Replace INSERT policy — validate the two new optional columns
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

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Extend the daily archival CRON: scrub contact info on aged testimonials
--    (the DELETE-unapproved half is unchanged from 20260417).
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'feedback-archival-daily') THEN
    PERFORM cron.unschedule('feedback-archival-daily');
  END IF;
END $$;

SELECT cron.schedule(
  'feedback-archival-daily',
  '0 4 * * *',
  $$
    DELETE FROM public.user_feedback
      WHERE received_at < now() - interval '90 days'
        AND approved_for_display IS NOT TRUE;
    UPDATE public.user_feedback
      SET contact_email = NULL, contact_locale = NULL
      WHERE received_at < now() - interval '90 days'
        AND approved_for_display IS TRUE
        AND (contact_email IS NOT NULL OR contact_locale IS NOT NULL);
  $$
);
