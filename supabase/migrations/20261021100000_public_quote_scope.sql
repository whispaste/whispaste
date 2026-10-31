-- Migration: quotes on the website only for praise and store reviews
-- (decision 24, CONTEXT 6.7a)
--
-- Bug reports (category bug) and feature wishes (category feature) are never
-- published, even if a client sends publish_consent for them. Praise and
-- questions share category general, so the server cannot tell them apart; the
-- app offers the quote consent for praise only. Rows without a category (store
-- reviews synced by tools/testimonials/sync-store-reviews.py) keep their
-- curation rules.
--
-- Additive. CREATE OR REPLACE VIEW keeps the column list and the SELECT grant
-- of 20261020100000; the view body only gets one more condition.

CREATE OR REPLACE VIEW public.public_testimonials
WITH (security_invoker = false)
AS
SELECT
    rating,
    left(coalesce(curated_text, feedback_text), 500) AS text,
    received_at
FROM public.user_feedback
WHERE approved_for_display = true
  AND feedback_text IS NOT NULL
  AND (rating >= 4 OR curated_text IS NOT NULL)
  AND (source <> 'in_app' OR publish_consent = true)
  AND (category IS NULL OR category = 'general');
