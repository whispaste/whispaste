-- Cap testimonial text at 500 characters in the PostgREST view.
--
-- The retired Edge Function applied sanitizeText().slice(0, 500) on every
-- response. The PostgREST view exposed feedback_text without a length limit.
-- This migration restores consistent behaviour: any text longer than 500 chars
-- is silently truncated at the DB layer before it reaches the client.

CREATE OR REPLACE VIEW public.public_testimonials
WITH (security_invoker = false)
AS
SELECT
    rating,
    left(feedback_text, 500) AS text,
    received_at
FROM public.user_feedback
WHERE approved_for_display = true
  AND rating             >= 4
  AND feedback_text IS NOT NULL;

-- GRANT stays the same (no change to permissions needed).
GRANT SELECT ON public.public_testimonials TO anon;

COMMENT ON VIEW public.public_testimonials IS
    'GDPR-safe public view of approved testimonials (rating >= 4). '
    'Text capped at 500 chars. No PII columns exposed.';
