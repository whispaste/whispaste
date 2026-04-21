-- Migration: Fix all Supabase Security Advisor + Performance Advisor findings
--
-- Security Advisor (4x WARN — function_search_path_mutable):
--   All four SECURITY DEFINER trigger functions lacked SET search_path = ''.
--   Without a fixed search_path a malicious object placed in any schema on
--   the connection's search_path could shadow a built-in and intercept calls.
--   Fix: add SET search_path = '' to each function. All table references are
--   already fully qualified (public.*) and all built-ins used here are in
--   pg_catalog which is always searched regardless of search_path.
--
-- Performance Advisor (1x DROP — unused_index):
--   idx_feedback_status_received was created for Discord-status queries in
--   migration 20260409. The Discord cleanup job was unscheduled in 20260412
--   and the crash_report_events table was dropped in 20260414. No active
--   query uses WHERE status = 'sent' on user_feedback anymore.
--   Dropping it removes write amplification on every INSERT.
--
-- Performance Advisor (3x INFO — unused_index, intentionally kept):
--   idx_feedback_device          — used by trg_feedback_rate_limit (device hash)
--   idx_feedback_approved        — used by testimonials Edge Function
--   idx_feedback_ip_hash_received — used by trg_feedback_ip_rate_limit (ip hash)
--   These indexes are "unused" only because the table is new; queries DO exist.

-- =========================================================================
-- 1. Drop obsolete Discord-status index
-- =========================================================================

DROP INDEX IF EXISTS public.idx_feedback_status_received;

-- =========================================================================
-- 2. Fix check_feedback_global_cap — add SET search_path = ''
-- =========================================================================

CREATE OR REPLACE FUNCTION public.check_feedback_global_cap()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Hard cap: reject if there are already 10000+ feedback entries.
  -- OFFSET skips 10000 rows; if a row still exists we are over the limit.
  IF EXISTS (SELECT 1 FROM public.user_feedback OFFSET 10000 LIMIT 1) THEN
    RAISE EXCEPTION 'global_feedback_cap_exceeded'
      USING HINT = 'Global feedback cap of 10000 entries reached';
  END IF;
  RETURN NEW;
END;
$$;

-- =========================================================================
-- 3. Fix enforce_feedback_defaults — add SET search_path = ''
-- =========================================================================

CREATE OR REPLACE FUNCTION public.enforce_feedback_defaults()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  headers_raw text;
  xff         text;
  ip_parts    text[];
  last_ip     text;
  raw_ua      text;
BEGIN
  -- Always generate a fresh UUID so callers cannot control the PK.
  NEW.id          := gen_random_uuid();
  NEW.received_at := now();

  -- Extract real client IP from PostgREST forwarded headers when present.
  headers_raw := current_setting('request.headers', true);
  IF headers_raw IS NOT NULL AND headers_raw <> '' THEN
    BEGIN
      xff := (headers_raw::json) ->> 'x-forwarded-for';
      IF xff IS NOT NULL AND xff <> '' THEN
        ip_parts := string_to_array(xff, ',');
        last_ip  := trim(ip_parts[array_length(ip_parts, 1)]);
        IF last_ip IS NOT NULL AND last_ip <> '' THEN
          NEW.ip_hash := encode(sha256(last_ip::bytea), 'hex');
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Malformed header: silently ignore, keep caller-supplied ip_hash if any.
      NULL;
    END;
  END IF;

  -- Sanitise user-agent length to prevent oversized payloads.
  raw_ua := current_setting('request.headers', true);
  IF NEW.user_agent IS NOT NULL AND length(NEW.user_agent) > 500 THEN
    NEW.user_agent := left(NEW.user_agent, 500);
  END IF;

  -- Force safe defaults for moderation fields.
  NEW.approved_for_display := false;
  NEW.status               := 'received';

  RETURN NEW;
END;
$$;

-- =========================================================================
-- 4. Fix check_feedback_ip_rate_limit — add SET search_path = ''
-- =========================================================================

CREATE OR REPLACE FUNCTION public.check_feedback_ip_rate_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  ip_count integer;
BEGIN
  -- Skip check when no IP hash is available (e.g. local dev without headers).
  IF NEW.ip_hash IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO ip_count
  FROM public.user_feedback
  WHERE ip_hash    = NEW.ip_hash
    AND received_at > now() - interval '24 hours';

  IF ip_count >= 5 THEN
    RAISE EXCEPTION 'ip_rate_limit_exceeded'
      USING HINT = 'Maximum 5 feedback submissions per IP per 24 hours';
  END IF;

  RETURN NEW;
END;
$$;

-- =========================================================================
-- 5. Fix check_feedback_rate_limit — add SET search_path = ''
-- =========================================================================

CREATE OR REPLACE FUNCTION public.check_feedback_rate_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  device_count integer;
BEGIN
  -- Skip when device hash absent (anonymous or old clients).
  IF NEW.device_id_hash IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO device_count
  FROM public.user_feedback
  WHERE device_id_hash = NEW.device_id_hash
    AND received_at    > now() - interval '24 hours';

  IF device_count >= 3 THEN
    RAISE EXCEPTION 'device_rate_limit_exceeded'
      USING HINT = 'Maximum 3 feedback submissions per device per 24 hours';
  END IF;

  RETURN NEW;
END;
$$;

-- =========================================================================
-- Comments (show intent in pg_proc)
-- =========================================================================

COMMENT ON FUNCTION public.check_feedback_global_cap() IS
  'Trigger: reject INSERT when user_feedback exceeds 10000 rows (global spam cap).';

COMMENT ON FUNCTION public.enforce_feedback_defaults() IS
  'Trigger: overwrite id/received_at, extract ip_hash from forwarded headers, force safe moderation defaults.';

COMMENT ON FUNCTION public.check_feedback_ip_rate_limit() IS
  'Trigger: limit to 5 feedback submissions per IP hash per 24 hours.';

COMMENT ON FUNCTION public.check_feedback_rate_limit() IS
  'Trigger: limit to 3 feedback submissions per device hash per 24 hours.';
