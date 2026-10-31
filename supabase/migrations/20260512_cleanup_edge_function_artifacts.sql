-- Cleanup leftover artifacts after retiring all Edge Functions.
--
-- The three remaining Edge Functions (crash-relay, analytics, testimonials)
-- were deleted in May 2026 to keep free-tier invocations at zero. This
-- migration removes the two server-side artifacts that only existed to
-- support those functions:
--
--   1. feedback_daily_summary view — read exclusively by the analytics
--      function. Ad-hoc feedback inspection now happens via the Supabase
--      Dashboard (Table Editor / SQL Editor).
--
--   2. admin_api_key secret in Vault — consumed exclusively by the analytics
--      and testimonials functions for x-api-key auth. No code path references
--      it anymore.
--
-- After running this migration, also delete the deployed functions from the
-- platform side:
--
--     supabase functions delete crash-relay
--     supabase functions delete analytics
--     supabase functions delete testimonials

DROP VIEW IF EXISTS public.feedback_daily_summary;

DELETE FROM vault.secrets WHERE name = 'admin_api_key';
