-- Add explicit deny-all RLS policies for service-role-only tables.
-- These tables are accessed exclusively via Edge Functions using the
-- service_role_key, which bypasses RLS. The policies make the intent
-- explicit and silence the Supabase linter (rls_enabled_no_policy).

-- crash_report_events: written by crash-relay, read by analytics/crash-cleanup
CREATE POLICY "Deny all — service role only"
  ON public.crash_report_events
  FOR ALL
  USING (false);

-- user_feedback: written by feedback relay, read by analytics/testimonials
CREATE POLICY "Deny all — service role only"
  ON public.user_feedback
  FOR ALL
  USING (false);
