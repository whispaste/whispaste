-- Migration: Fix feedback archival CRON — preserve approved testimonials
--
-- BUG: The previous archival job (20260416) deleted ALL rows older than 90
-- days, including rows with approved_for_display = true.  Those rows are the
-- data source for the testimonials Edge Function and must never be deleted.
--
-- FIX: Narrow the DELETE to only rows that have NOT been approved for display.
--   - approved_for_display IS NOT TRUE → unapproved (pending review), rejected,
--     or NULL (hypothetical — trigger always sets false, but NULL-safe is better)
--   - approved_for_display = true       → curated testimonial; keep indefinitely
--
-- Note: `= false` would miss NULL values (three-valued SQL logic).
--       `IS NOT TRUE` is the correct NULL-safe predicate here.
--
-- Storage impact: testimonials are a tiny fraction of total feedback volume.
-- A single approved testimonial is ≈1 KB.  Keeping 100 approved testimonials
-- forever adds at most ~100 KB of permanent storage — negligible.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'feedback-archival-daily') THEN
    PERFORM cron.unschedule('feedback-archival-daily');
  END IF;
END $$;

SELECT cron.schedule(
  'feedback-archival-daily',
  '0 4 * * *',
  $$DELETE FROM public.user_feedback
    WHERE received_at < now() - interval '90 days'
      AND approved_for_display IS NOT TRUE;$$
);
