-- The rating >= 4 gate on public_testimonials existed to stop a positive-
-- sounding sentence from an otherwise negative/mixed review surfacing as a
-- testimonial. But the Feedback Hub's curation workflow (curated_text +
-- approved_for_display) already puts a human in the loop for exactly that
-- judgment call: whoever sets curated_text has read the full raw feedback
-- and decided the excerpt is fair and representative. Requiring rating >= 4
-- on top of that second-guesses a decision that was already made deliberately,
-- and silently drops testimonials whose overall rating reflects an unrelated
-- gripe (e.g. a feature request) rather than the quality of the quoted text.
--
-- Keep the rating >= 4 gate as the bar for *uncurated* text (feedback_text
-- shown as-is, never manually reviewed for testimonial framing), but let a
-- non-null curated_text bypass it.
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
  AND (rating >= 4 OR curated_text IS NOT NULL);

GRANT SELECT ON public.public_testimonials TO anon;

COMMENT ON VIEW public.public_testimonials IS
    'GDPR-safe public view of approved testimonials. Uncurated feedback needs '
    'rating >= 4; a curated_text (human-reviewed excerpt) bypasses the rating '
    'gate since curation already vetted the excerpt. No PII columns exposed.';
