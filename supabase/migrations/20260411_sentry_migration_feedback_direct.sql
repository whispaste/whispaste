-- Migration: Sentry + Direct Feedback Architecture
--
-- Replaces Edge Function relay architecture with:
-- 1. Sentry (client-side) for crash reporting → no server component needed
-- 2. Direct PostgREST INSERT for feedback → RLS-protected, no Edge Function
--
-- Changes:
-- - DROP the deny-all INSERT policy on user_feedback for anon
-- - GRANT column-level INSERT on user_feedback to anon
-- - CREATE validated INSERT policy with constraints
-- - CREATE rate-limiting trigger (1 feedback per device per 24h)
-- - Mark crash_report_events as deprecated (Sentry replaces it)

-- ═══════════════════════════════════════════════════════════════════════════
-- 0. Enable RLS on user_feedback (was missing from initial table creation)
-- ═══════════════════════════════════════════════════════════════════════════

-- Without this, all policies on the table are inert and offer no protection.
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback FORCE ROW LEVEL SECURITY;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Replace deny-all policy with validated INSERT policy
-- ═══════════════════════════════════════════════════════════════════════════

-- Drop the blanket deny-all policy (from 20260405)
DROP POLICY IF EXISTS "Deny all — service role only" ON public.user_feedback;

-- Deny SELECT/UPDATE/DELETE for anon (service_role bypasses RLS).
CREATE POLICY "anon_deny_select"
  ON public.user_feedback FOR SELECT TO anon USING (false);

CREATE POLICY "anon_deny_update"
  ON public.user_feedback FOR UPDATE TO anon USING (false);

CREATE POLICY "anon_deny_delete"
  ON public.user_feedback FOR DELETE TO anon USING (false);

-- Allow INSERT with validation constraints.
CREATE POLICY "anon_can_insert_feedback"
  ON public.user_feedback FOR INSERT TO anon
  WITH CHECK (
    -- Rating must be 1–5 (also enforced by CHECK constraint, but defense-in-depth)
    rating >= 1 AND rating <= 5
    -- Feedback text must be reasonable length
    AND (feedback_text IS NULL OR length(feedback_text) <= 2000)
    -- App version must be provided and sane
    AND app_version IS NOT NULL AND length(app_version) <= 20
    -- Device ID hash must be provided (12-char MD5 prefix)
    AND device_id_hash IS NOT NULL AND length(device_id_hash) = 12
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Column-level GRANT — anon can only set these 4 columns
-- ═══════════════════════════════════════════════════════════════════════════

-- Revoke any existing broad grants first.
REVOKE ALL ON public.user_feedback FROM anon;

-- Grant INSERT on specific columns only (id, received_at use defaults;
-- ip_hash, discord_message_id, status, approved_for_display are server-only).
GRANT INSERT (rating, feedback_text, app_version, device_id_hash)
  ON public.user_feedback TO anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Rate-limiting trigger: max 3 feedbacks per device per 24 hours
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_feedback_rate_limit()
RETURNS TRIGGER AS $$
BEGIN
  IF (
    SELECT count(*) FROM public.user_feedback
    WHERE device_id_hash = NEW.device_id_hash
    AND received_at > now() - interval '24 hours'
  ) >= 3 THEN
    RAISE EXCEPTION 'rate_limited: max 3 feedback submissions per 24 hours'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_feedback_rate_limit
  BEFORE INSERT ON public.user_feedback
  FOR EACH ROW
  EXECUTE FUNCTION public.check_feedback_rate_limit();

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Add comment marking crash_report_events as deprecated
-- ═══════════════════════════════════════════════════════════════════════════

COMMENT ON TABLE public.crash_report_events IS
  'DEPRECATED — Crash reporting migrated to Sentry (v1.2.0). '
  'Table retained for historical data. No new inserts expected. '
  'Consider dropping after data export.';
