-- Add an editorial "curated_text" column: raw feedback (feedback_text) is the
-- ground truth, but not every approved row is testimonial-ready as-is (may
-- contain support requests, unrelated asides, sponsorship offers, etc. mixed
-- in with the genuine praise). curated_text holds a hand-edited, testimonial-
-- appropriate version of the same feedback; NULL means "raw text is fine as
-- displayed". This is additive only — feedback_text is untouched.
ALTER TABLE public.user_feedback
    ADD COLUMN curated_text text;

COMMENT ON COLUMN public.user_feedback.curated_text IS
    'Optional hand-curated testimonial text derived from feedback_text (same '
    'core message, stripped of non-testimonial content e.g. support asks, '
    'sponsorship offers). NULL falls back to feedback_text via public_testimonials.';

-- Point the public view at the curated text when present, otherwise fall
-- back to the existing raw-text-capped behavior. Re-declaring preserves the
-- security_invoker=false posture and column set; the anon GRANT survives a
-- CREATE OR REPLACE VIEW (grants are not dropped by replacing a view's
-- query), but we re-assert it explicitly for clarity and defense-in-depth.
CREATE OR REPLACE VIEW public.public_testimonials
WITH (security_invoker = false)
AS
SELECT
    rating,
    left(coalesce(curated_text, feedback_text), 500) AS text,
    received_at
FROM public.user_feedback
WHERE approved_for_display = true
  AND rating             >= 4
  AND feedback_text IS NOT NULL;

GRANT SELECT ON public.public_testimonials TO anon;

COMMENT ON VIEW public.public_testimonials IS
    'GDPR-safe public view of approved testimonials (rating >= 4). '
    'Prefers curated_text over raw feedback_text when set. No PII columns exposed.';
