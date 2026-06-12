-- Fix Supabase security-advisor findings (2026-06-12):
--
--  1. ERROR security_definer_view: `public_testimonials` ran with the view
--     owner's privileges. Switch to security_invoker and give anon exactly
--     the column-level SELECT + RLS policy the view needs — the testimonial
--     contract (approved rows only, no PII columns) is now enforced by
--     grants + RLS for the *querying* role instead of definer privileges.
--  2. WARN anon/authenticated_security_definer_function_executable: the
--     feedback trigger functions and rls_auto_enable were callable via
--     /rest/v1/rpc/* by anon/authenticated. Triggers execute as table owner,
--     so client EXECUTE is never needed — revoke it.
--  3. Hardening: authenticated had blanket table grants (SELECT/UPDATE/
--     DELETE/TRUNCATE/...) on user_feedback. The app only ever uses the
--     anon role (publishable key); revoke everything from authenticated.
--
-- Intentionally NOT addressed: the three INFO unused_index findings
-- (idx_feedback_device, idx_feedback_approved, idx_feedback_ip_hash_received).
-- They back the rate-limit triggers and the testimonials filter; "unused"
-- is an artifact of the near-empty table, and they become load-bearing as
-- rows accumulate toward the 10k cap.
--
-- Additive only: no table/column drops; the public_testimonials contract
-- (rating, text, received_at — approved & rating >= 4 only) is unchanged
-- for the website's build-time fetch.

-- 1. View: run with the caller's privileges -------------------------------

alter view public.public_testimonials set (security_invoker = true);

-- anon needs column-level SELECT on exactly the columns the view touches —
-- including approved_for_display, which the view's WHERE clause references.
grant select (rating, feedback_text, received_at, approved_for_display)
  on public.user_feedback to anon;

-- Replace the blanket deny with "approved rows only". Permissive policies
-- OR together, so the old `false` policy would be dead weight next to the
-- new one — drop it for clarity.
drop policy if exists anon_deny_select on public.user_feedback;

create policy anon_select_approved_feedback
  on public.user_feedback
  for select
  to anon
  using (approved_for_display = true);

-- 2. Trigger functions: no client-side EXECUTE ----------------------------

revoke execute on function public.check_feedback_global_cap()
  from public, anon, authenticated;
revoke execute on function public.check_feedback_ip_rate_limit()
  from public, anon, authenticated;
revoke execute on function public.check_feedback_rate_limit()
  from public, anon, authenticated;
revoke execute on function public.enforce_feedback_defaults()
  from public, anon, authenticated;
revoke execute on function public.rls_auto_enable()
  from public, anon, authenticated;

-- 3. authenticated: the app never uses this role on user_feedback ---------

revoke all on public.user_feedback from authenticated;
