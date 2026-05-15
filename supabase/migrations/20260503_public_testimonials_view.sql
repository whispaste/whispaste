-- Replace the testimonials Edge Function public-GET endpoint with a PostgREST view.
--
-- The Astro SSG build called /functions/v1/testimonials on every website deployment.
-- We eliminate this by exposing a security_invoker=false view that the anon role
-- can SELECT directly via PostgREST — zero Edge Function invocations.
--
-- security_invoker = false: view runs as its owner (postgres/superuser), bypassing
-- the anon_deny_select RLS policy on user_feedback. The view itself enforces the
-- same restrictions the Edge Function applied: approved entries only, rating >= 4,
-- non-null text, and only three non-PII columns (rating, text, received_at).
--
-- PII that is NOT exposed: device_id_hash, ip_hash, app_version, discord_message_id,
-- discord_cleaned_at, status, id, category.

CREATE OR REPLACE VIEW public.public_testimonials
WITH (security_invoker = false)
AS
SELECT
    rating,
    feedback_text  AS text,
    received_at
FROM public.user_feedback
WHERE approved_for_display = true
  AND rating             >= 4
  AND feedback_text IS NOT NULL;

-- Grant SELECT to the anon role so PostgREST can serve it without authentication.
-- Column-level security: the view exposes only rating, text, received_at.
-- The anon role cannot reach any other column or any other row.
GRANT SELECT ON public.public_testimonials TO anon;

COMMENT ON VIEW public.public_testimonials IS
    'GDPR-safe public view of approved testimonials (rating >= 4). '
    'Replaces the Edge Function public GET. No PII columns exposed.';
